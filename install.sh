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

c_red='\033[31m'; c_grn='\033[32m'; c_ylw='\033[33m'; c_dim='\033[2m'; c_rst='\033[0m'

say()  { printf "${c_grn}==>${c_rst} %s\n" "$*"; }
warn() { printf "${c_ylw}!! %s${c_rst}\n" "$*"; }
die()  { printf "${c_red}✗ %s${c_rst}\n" "$*" >&2; exit 1; }

# ---- 1. Ensure ~/.claude exists ----
mkdir -p "$CLAUDE_DIR"

# ---- 2. Check & install jq ----
if ! command -v jq >/dev/null 2>&1; then
  warn "jq not found, attempting to install"
  if   command -v brew    >/dev/null 2>&1; then HOMEBREW_NO_AUTO_UPDATE=1 brew install jq
  elif command -v apt-get >/dev/null 2>&1; then sudo apt-get update && sudo apt-get install -y jq
  elif command -v yum     >/dev/null 2>&1; then sudo yum install -y jq
  elif command -v dnf     >/dev/null 2>&1; then sudo dnf install -y jq
  elif command -v apk     >/dev/null 2>&1; then sudo apk add jq
  else die "No supported package manager found. Install jq manually."
  fi
fi
say "jq: $(jq --version)"

# ---- 3. Install statusline.sh ----
say "Installing statusline.sh → $SCRIPT_DEST"
if [[ -f "./statusline.sh" ]]; then
  cp "./statusline.sh" "$SCRIPT_DEST"
else
  curl -fsSL "${REPO_URL_RAW}/statusline.sh" -o "$SCRIPT_DEST"
fi
chmod +x "$SCRIPT_DEST"

# ---- 4. Merge statusLine block into settings.json ----
say "Updating $SETTINGS_PATH"

if [[ ! -f "$SETTINGS_PATH" ]]; then
  echo '{}' > "$SETTINGS_PATH"
fi

# Backup first
backup="${SETTINGS_PATH}.bak.$(date +%s)"
cp "$SETTINGS_PATH" "$backup"
printf "${c_dim}   backup: %s${c_rst}\n" "$backup"

# Merge using jq — preserves all other top-level keys
tmp=$(mktemp)
jq --arg cmd "$SCRIPT_DEST" \
   '. + {statusLine: {type: "command", command: $cmd, padding: 0}}' \
   "$SETTINGS_PATH" > "$tmp" && mv "$tmp" "$SETTINGS_PATH"

# ---- 5. Done ----
say "Installed."
printf "${c_dim}\n"
cat <<EOF
   Verify:
     cat $SETTINGS_PATH | jq .statusLine
     echo '{"model":{"display_name":"Opus 4.7"},"context_window":{"used_percentage":50,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":25},"seven_day":{"used_percentage":10}},"cost":{"total_cost_usd":1.23},"transcript_path":""}' | $SCRIPT_DEST

   Restart Claude Code (or /clear) to see the statusline.

   Truecolor required for the gradient — iTerm2, Warp, VS Code terminal, Apple Terminal.app all work.
EOF
printf "${c_rst}"
