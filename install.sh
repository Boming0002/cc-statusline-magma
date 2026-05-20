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
  if   command -v brew    >/dev/null 2>&1; then HOMEBREW_NO_AUTO_UPDATE=1 brew install jq
  elif command -v apt-get >/dev/null 2>&1; then sudo apt-get update && sudo apt-get install -y jq
  elif command -v yum     >/dev/null 2>&1; then sudo yum install -y jq
  elif command -v dnf     >/dev/null 2>&1; then sudo dnf install -y jq
  elif command -v apk     >/dev/null 2>&1; then sudo apk add jq
  else die "No supported package manager. Install jq manually then re-run."
  fi
  command -v jq >/dev/null 2>&1 || die "jq install reported success but binary still not on PATH"
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

backup="${SETTINGS_PATH}.bak.$(date +%s)"
cp "$SETTINGS_PATH" "$backup"
info "backup: $backup"

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
