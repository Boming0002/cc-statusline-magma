#!/bin/bash
# Custom Claude Code statusline with progress bars.
# Reads rate-limit + context fields exposed by CC 2.1.116+.

INPUT=$(cat)

MODEL_RAW=$(echo "$INPUT" | jq -r '.model.display_name // "?"')
MODEL=$(echo "$MODEL_RAW" | sed -E \
  -e 's/Opus /O/' \
  -e 's/Sonnet /S/' \
  -e 's/Haiku /H/' \
  -e 's/ \(1M context\)/·1M/' \
  -e 's/ \(200K context\)/·200K/')
CTX_PCT=$(echo "$INPUT" | jq -r '(.context_window.used_percentage // 0) | floor')
CTX_SIZE=$(echo "$INPUT" | jq -r '.context_window.context_window_size // 0')
H5_PCT=$(echo "$INPUT" | jq -r '(.rate_limits.five_hour.used_percentage // 0) | floor')
H5_RESET=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.resets_at // 0')
D7_PCT=$(echo "$INPUT" | jq -r '(.rate_limits.seven_day.used_percentage // 0) | floor')
COST=$(echo "$INPUT" | jq -r '.cost.total_cost_usd // 0')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')

# Cache + token stats from transcript:
# - cache hit rate for last turn (signal: is caching working?)
# - session cumulative cache reads, total input (all kinds), total output
CACHE_PCT=0
CACHE_READ_TOTAL=0
IN_TOTAL=0
OUT_TOTAL=0
if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
  CACHE_STATS=$(jq -rs '
    [.[] | select(.message.usage != null) | .message.usage] as $u
    | ($u[-1] // {}) as $last
    | (($last.cache_read_input_tokens // 0)
       + ($last.cache_creation_input_tokens // 0)
       + ($last.input_tokens // 0)) as $denom
    | {
        pct: (if $denom > 0
              then (($last.cache_read_input_tokens // 0) * 100 / $denom | floor)
              else 0 end),
        read_total: ($u | map(.cache_read_input_tokens // 0) | add // 0),
        in_total:   ($u | map((.input_tokens // 0)
                              + (.cache_creation_input_tokens // 0)
                              + (.cache_read_input_tokens // 0)) | add // 0),
        out_total:  ($u | map(.output_tokens // 0) | add // 0)
      }
    | "\(.pct) \(.read_total) \(.in_total) \(.out_total)"
  ' "$TRANSCRIPT" 2>/dev/null)
  read -r CACHE_PCT CACHE_READ_TOTAL IN_TOTAL OUT_TOTAL <<<"$CACHE_STATS"
  [[ -z "$CACHE_PCT" ]] && CACHE_PCT=0
  [[ -z "$CACHE_READ_TOTAL" ]] && CACHE_READ_TOTAL=0
  [[ -z "$IN_TOTAL" ]] && IN_TOTAL=0
  [[ -z "$OUT_TOTAL" ]] && OUT_TOTAL=0
fi

fmt_tokens() {
  local n=$1
  if (( n >= 1000000 )); then
    printf '%.1fM' "$(echo "$n" | awk '{print $1/1000000}')"
  elif (( n >= 1000 )); then
    printf '%.0fk' "$(echo "$n" | awk '{print $1/1000}')"
  else
    printf '%d' "$n"
  fi
}

H5_LEFT=""
if [[ "$H5_RESET" != "0" ]]; then
  NOW=$(date +%s)
  DIFF=$(( H5_RESET - NOW ))
  if (( DIFF > 0 )); then
    H=$(( DIFF / 3600 ))
    M=$(( (DIFF % 3600) / 60 ))
    H5_LEFT=" ${H}h${M}m"
  fi
fi

# 10-stop gradient. Each cell colored by its position (0..9); leading edge
# shows magnitude. Same palette for every metric — labels (ctx / 5h / 7d / ⚡)
# carry the good-vs-bad semantic.
#
# Two knobs:
#   STATUSLINE_THEME = magma (default) | viridis | ocean | forest | cyberpunk
#   STATUSLINE_BG    = dark  (default) | light
# Light-bg variants cap brightness so filled cells stay visible on white
# backgrounds (no yellow/white fade to invisible).

THEME="${STATUSLINE_THEME:-magma}"
BG="${STATUSLINE_BG:-dark}"

case "${THEME}_${BG}" in
  magma_dark)
    # Dark indigo → magenta → orange → bright yellow.
    GRADIENT=(
      "30 10 70"   "60 15 110"  "95 25 140"  "130 35 150" "170 45 140"
      "205 60 110" "230 80 70"  "245 115 40" "255 160 30" "255 215 20"
    ) ;;
  magma_light)
    # Same hue family, capped brightness to stay visible on white.
    GRADIENT=(
      "40 15 80"   "70 20 120"  "100 30 150" "135 40 160" "170 50 145"
      "195 65 115" "210 85 80"  "200 100 50" "180 110 30" "150 100 20"
    ) ;;
  viridis_dark)
    # Color-blind friendly. Matplotlib's perceptually-uniform map.
    GRADIENT=(
      "68 1 84"    "72 35 116"  "64 67 135"  "52 94 141"  "41 120 142"
      "32 144 140" "34 167 132" "94 201 97"  "173 220 53" "253 231 36"
    ) ;;
  viridis_light)
    # Truncated viridis — stops before reaching too-bright endpoints.
    GRADIENT=(
      "50 5 65"    "60 30 100"  "55 60 115"  "50 85 125"  "45 105 130"
      "40 130 130" "50 155 120" "75 175 85"  "120 180 50" "150 170 30"
    ) ;;
  ocean_dark)
    # Deep navy → bright blue → light cyan → near-white.
    GRADIENT=(
      "3 4 94"     "5 22 122"   "8 50 153"    "10 90 195"   "15 135 230"
      "60 175 245" "120 205 250" "175 225 250" "215 240 252" "240 252 255"
    ) ;;
  ocean_light)
    # Stops before fading to white; ends at teal.
    GRADIENT=(
      "5 15 80"    "10 30 110"  "15 50 140"  "20 80 170"  "25 115 195"
      "40 145 200" "60 170 195" "70 180 175" "75 175 150" "70 160 120"
    ) ;;
  forest_dark)
    # Dark forest → grass → pale lime.
    GRADIENT=(
      "10 40 16"   "20 70 28"   "35 100 40"  "50 130 55"  "75 160 70"
      "110 190 90" "150 215 110" "190 230 130" "220 240 155" "245 248 180"
    ) ;;
  forest_light)
    # Stays darker overall; ends at olive instead of pale lime.
    GRADIENT=(
      "15 50 20"   "25 75 30"   "40 100 45"  "55 125 55"  "75 145 65"
      "95 160 70"  "115 170 70" "130 170 60" "140 165 50" "140 155 40"
    ) ;;
  cyberpunk_dark)
    # Saturated neon clash — vapor-wave / Blade Runner vibe.
    GRADIENT=(
      "30 0 60"    "80 0 130"   "140 0 180"   "200 0 220"   "240 30 200"
      "255 70 150" "200 100 240" "100 200 255" "0 240 220"  "0 255 150"
    ) ;;
  cyberpunk_light)
    # Darker chromatic clash; avoids neon glare on white.
    GRADIENT=(
      "40 0 70"    "75 0 110"   "115 0 145"  "150 0 165"  "180 20 160"
      "195 50 145" "200 75 130" "150 100 175" "100 130 195" "60 150 180"
    ) ;;
  *)
    # Unknown theme/bg — fall back to magma_dark silently.
    GRADIENT=(
      "30 10 70"   "60 15 110"  "95 25 140"  "130 35 150" "170 45 140"
      "205 60 110" "230 80 70"  "245 115 40" "255 160 30" "255 215 20"
    ) ;;
esac

# Accent colors for model name / cost / token counts.
# Dark bg → cyan + magenta. Light bg → darker blue + red for contrast.
if [[ "$BG" == "light" ]]; then
  C_MODEL="34"   # blue
  C_TOKENS="34"  # blue
  C_COST="31"    # red
else
  C_MODEL="36"   # cyan
  C_TOKENS="36"  # cyan
  C_COST="35"    # magenta
fi

render_bar() {
  local pct=$1
  local width=10
  local filled=$(( pct * width / 100 ))
  (( filled > width )) && filled=$width
  (( pct > 0 && filled == 0 )) && filled=1
  local bar=""
  local i r g b
  for (( i = 0; i < filled; i++ )); do
    read -r r g b <<<"${GRADIENT[$i]}"
    bar+=$'\033'"[38;2;${r};${g};${b}m▰"$'\033'"[0m"
  done
  if (( filled < width )); then
    bar+=$'\033[2m'
    for (( i = filled; i < width; i++ )); do bar+="▱"; done
    bar+=$'\033[22m'
  fi
  echo "$bar"
}

BAR_CTX=$(render_bar "$CTX_PCT")
BAR_5H=$(render_bar "$H5_PCT")
BAR_7D=$(render_bar "$D7_PCT")
BAR_CACHE=$(render_bar "$CACHE_PCT")
CACHE_READ_FMT=$(fmt_tokens "$CACHE_READ_TOTAL")
IN_FMT=$(fmt_tokens "$IN_TOTAL")
OUT_FMT=$(fmt_tokens "$OUT_TOTAL")

if (( CTX_SIZE >= 1000000 )); then
  CTX_LABEL="$(( CTX_SIZE / 1000000 ))M"
elif (( CTX_SIZE > 0 )); then
  CTX_LABEL="$(( CTX_SIZE / 1000 ))K"
else
  CTX_LABEL="?"
fi

COST_FMT=$(printf '%.2f' "$COST")
ESC=$'\033'

printf "${ESC}[${C_MODEL}m%s${ESC}[0m │ ctx %s %3s%%/%s │ 5h %s %3s%%%s │ 7d %s %3s%% │ ⚡%s %3s%% │ ↓${ESC}[${C_TOKENS}m%s${ESC}[0m ↑${ESC}[${C_TOKENS}m%s${ESC}[0m %s cached │ ${ESC}[${C_COST}m\$%s${ESC}[0m" \
  "$MODEL" \
  "$BAR_CTX" "$CTX_PCT" "$CTX_LABEL" \
  "$BAR_5H" "$H5_PCT" "$H5_LEFT" \
  "$BAR_7D" "$D7_PCT" \
  "$BAR_CACHE" "$CACHE_PCT" \
  "$IN_FMT" "$OUT_FMT" "$CACHE_READ_FMT" \
  "$COST_FMT"
