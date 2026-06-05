#!/usr/bin/env bash
# cc-statusline-magma installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Boming0002/cc-statusline-magma/main/install.sh | bash
# Or, after cloning the repo:
#   ./install.sh

set -euo pipefail

REPO_URL_RAW="https://raw.githubusercontent.com/Boming0002/cc-statusline-magma/main"
CLAUDE_DIR="${HOME}/.claude"
SCRIPT_DEST="${CLAUDE_DIR}/statusline.sh"
SETTINGS_PATH="${CLAUDE_DIR}/settings.json"

# ---- colours ----
if [[ -t 1 ]]; then
  c_red='\033[31m'; c_grn='\033[32m'; c_ylw='\033[33m'
  c_dim='\033[2m'; c_bold='\033[1m'; c_rev='\033[7m'; c_rst='\033[0m'
else
  c_red=''; c_grn=''; c_ylw=''; c_dim=''; c_bold=''; c_rev=''; c_rst=''
fi

step()  { printf "${c_grn}==>${c_rst} ${c_bold}%s${c_rst}\n" "$*"; }
info()  { printf "${c_dim}    %s${c_rst}\n" "$*"; }
warn()  { printf "${c_ylw}!! %s${c_rst}\n" "$*"; }
die()   { printf "${c_red}✗ %s${c_rst}\n" "$*" >&2; exit 1; }
ok()    { printf "${c_grn}    ✓${c_rst} %s\n" "$*"; }

# ---- 0. Banner ----
printf "${c_bold}cc-statusline-magma installer${c_rst}\n"
printf "${c_dim}Source: %s${c_rst}\n\n" "$REPO_URL_RAW"

# ---- 1. Ensure ~/.claude exists ----
step "Preparing ${CLAUDE_DIR}"
if [[ ! -d "$CLAUDE_DIR" ]]; then
  mkdir -p "$CLAUDE_DIR" || die "Cannot create $CLAUDE_DIR (permissions?)"
  ok "created $CLAUDE_DIR"
else
  ok "exists"
fi

# ---- 2. Check & install jq ----
step "Checking jq"
if ! command -v jq >/dev/null 2>&1; then
  warn "jq not found, attempting to install"
  # Escalate only when needed: nothing as root, otherwise sudo -n (never prompt —
  # in a piped curl|bash there's no TTY, so a blocking prompt would hang/fail).
  SUDO=""
  if [[ "$(id -u)" -ne 0 ]] && command -v sudo >/dev/null 2>&1; then SUDO="sudo -n"; fi
  # set -e is suspended around the attempt so a blocked/failed install falls
  # through to the friendly check below instead of aborting cryptically.
  set +e
  if   command -v brew    >/dev/null 2>&1; then HOMEBREW_NO_AUTO_UPDATE=1 brew install jq
  elif command -v winget  >/dev/null 2>&1; then winget install --id jqlang.jq -e --accept-source-agreements --accept-package-agreements
  elif command -v scoop   >/dev/null 2>&1; then scoop install jq
  elif command -v choco   >/dev/null 2>&1; then choco install -y jq
  elif command -v pacman  >/dev/null 2>&1; then $SUDO pacman -S --noconfirm jq            # MSYS2 / Git Bash
  elif command -v apt-get >/dev/null 2>&1; then $SUDO apt-get update; $SUDO apt-get install -y jq
  elif command -v yum     >/dev/null 2>&1; then $SUDO yum install -y jq
  elif command -v dnf     >/dev/null 2>&1; then $SUDO dnf install -y jq
  elif command -v apk     >/dev/null 2>&1; then $SUDO apk add jq
  else warn "no supported package manager found"
  fi
  set -e
  command -v jq >/dev/null 2>&1 || die "jq is required but could not be auto-installed.
    Install it manually — https://jqlang.org/download/
    Windows: winget install jqlang.jq  |  scoop install jq  |  choco install jq
    Then re-run this installer."
fi
ok "jq $(jq --version)"

# ---- 3. Download / copy statusline.sh ----
step "Installing statusline.sh"
if [[ -f "./statusline.sh" ]]; then
  cp "./statusline.sh" "$SCRIPT_DEST"
  info "copied from ./statusline.sh"
else
  info "downloading from $REPO_URL_RAW/statusline.sh"
  curl -fsSL "${REPO_URL_RAW}/statusline.sh" -o "$SCRIPT_DEST" \
    || die "curl failed. Network/firewall block? Try manual download."
fi
chmod +x "$SCRIPT_DEST"

# Sanity: non-empty + syntactically valid bash
size=$(wc -c < "$SCRIPT_DEST" | tr -d ' ')
(( size > 100 )) || die "statusline.sh is suspiciously small ($size bytes) — download corrupt?"
bash -n "$SCRIPT_DEST" || die "statusline.sh failed bash syntax check — file corrupted, re-run installer"
ok "$SCRIPT_DEST  (${size} bytes, executable, syntax OK)"

# ---- 4. Smoke test ----
step "Smoke-testing statusline"
test_input='{"model":{"display_name":"Opus 4.7"},"context_window":{"used_percentage":50,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":25},"seven_day":{"used_percentage":10}},"cost":{"total_cost_usd":1.23},"transcript_path":""}'
test_output=$(echo "$test_input" | bash "$SCRIPT_DEST" 2>&1) || die "Script crashed on test input:
$test_output"
[[ -n "$test_output" ]] || die "Script ran but produced no output"
ok "renders (first 80 chars): $(echo "$test_output" | head -c 80)…"

# ---- 5. Merge statusLine block into settings.json ----
step "Updating $SETTINGS_PATH"
if [[ ! -f "$SETTINGS_PATH" ]]; then
  echo '{}' > "$SETTINGS_PATH"
  info "created empty settings.json"
fi

# Validate JSON before touching it
jq empty "$SETTINGS_PATH" 2>/dev/null \
  || die "$SETTINGS_PATH is not valid JSON — fix it manually before re-running"

# Single rolling backup (overwritten each run) — avoids piling up .bak.<epoch>
# files in ~/.claude on repeated installs.
backup="${SETTINGS_PATH}.bak"
cp "$SETTINGS_PATH" "$backup"
info "backup: $backup (previous settings.json)"

# Warn before clobbering a different, pre-existing statusLine so the user knows
# their custom config was replaced (and where to recover it).
existing_cmd=$(jq -r '.statusLine.command // ""' "$SETTINGS_PATH")
if [[ -n "$existing_cmd" && "$existing_cmd" != "$SCRIPT_DEST" ]]; then
  warn "Replacing an existing statusLine command"
  info "was: $existing_cmd"
  info "now: $SCRIPT_DEST   (previous config saved in $backup)"
fi

tmp=$(mktemp)
jq --arg cmd "$SCRIPT_DEST" \
   '. + {statusLine: {type: "command", command: $cmd, padding: 0}}' \
   "$SETTINGS_PATH" > "$tmp" && mv "$tmp" "$SETTINGS_PATH"

# Verify the key landed
written_cmd=$(jq -r '.statusLine.command // "MISSING"' "$SETTINGS_PATH")
[[ "$written_cmd" == "$SCRIPT_DEST" ]] \
  || die "settings.json merge did not write the expected statusLine.command (got: $written_cmd)"
ok ".statusLine.command = $written_cmd"

# ---- 6. Final reminder (BOLD, NOT DIM) ----
printf "\n${c_rev}${c_bold}  RESTART CLAUDE CODE TO SEE THE STATUSLINE  ${c_rst}\n"
printf "${c_bold}  In CC: type ${c_grn}/exit${c_rst}${c_bold}, then re-run ${c_grn}claude${c_rst}\n\n"

# Optional next steps
printf "${c_dim}Optional:${c_rst}\n"
printf "${c_dim}  • Switch theme:   ${c_rst}export STATUSLINE_THEME=viridis   ${c_dim}# magma|viridis|ocean|forest|cyberpunk${c_rst}\n"
printf "${c_dim}  • Light terminal: ${c_rst}export STATUSLINE_BG=light\n"
printf "${c_dim}  • Verify config:  ${c_rst}jq .statusLine $SETTINGS_PATH\n"
printf "${c_dim}  • Manual preview: ${c_rst}echo '<mock json>' | $SCRIPT_DEST\n"
printf "\n${c_grn}Done.${c_rst}\n"
