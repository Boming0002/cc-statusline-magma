# Custom Claude Code statusline with progress bars — PowerShell port.
# Cross-platform sibling of statusline.sh for Windows users WITHOUT Git Bash
# (Claude Code routes the status line command through PowerShell when Git Bash
# is absent). Reads rate-limit + context fields exposed by CC 2.1.116+.
#
# Compatible with BOTH Windows PowerShell 5.1 and PowerShell 7+:
#   - no ?? / ?. / ?: / && / || operators (7+ only)  -> Coalesce helper + if/else
#   - no `e escape (7+ only)                          -> [char]27
#   - source is pure ASCII; glyphs built via [char]   -> no UTF-8 BOM needed on 5.1
#
# Knobs (same as the bash version):
#   $env:STATUSLINE_THEME = magma (default) | viridis | ocean | forest | cyberpunk
#   $env:STATUSLINE_BG    = dark  (default) | light
#
# Wire into ~/.claude/settings.json (forward slashes — Git Bash eats backslashes):
#   "statusLine": { "type": "command",
#     "command": "powershell -NoProfile -File C:/Users/YOU/.claude/statusline.ps1" }

# Force UTF-8 output so the bar glyphs survive on Windows PowerShell 5.1 (whose
# default console encoding is the OEM/ANSI code page). No BOM ($false) so the
# first ANSI escape is not corrupted. Harmless on 7+ (already UTF-8).
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }

# ---- helpers ----

# Null-coalescing without the 7+ `??` operator. Note member access on a missing
# property yields $null in PowerShell (non-throwing), so guarding the leaf is enough.
function Coalesce($Value, $Default) {
  if ($null -ne $Value) { return $Value } else { return $Default }
}

# Build an ANSI SGR sequence: Esc '38;2;255;0;0' -> ESC[38;2;255;0;0m
$ESC = [char]27
function Esc([string]$code) { return [string]$ESC + '[' + $code + 'm' }
$E0 = Esc '0'   # reset

# Glyphs as code points keeps the source pure-ASCII (see header).
$G_FILLED = [char]0x25B0   # black parallelogram
$G_EMPTY  = [char]0x25B1   # white parallelogram
$G_BAR    = [char]0x2502   # box-drawing vertical
$G_BOLT   = [char]0x26A1   # high voltage
$G_DOWN   = [char]0x2193   # down arrow
$G_UP     = [char]0x2191   # up arrow
$G_MID    = [char]0x00B7   # middle dot

# 10-cell gradient bar coloured by cell position (matches statusline.sh exactly).
function Render-Bar([int]$pct) {
  $width = 10
  $filled = [int][math]::Floor(($pct * $width) / 100)
  if ($filled -gt $width) { $filled = $width }
  if ($pct -gt 0 -and $filled -eq 0) { $filled = 1 }
  $bar = ''
  for ($i = 0; $i -lt $filled; $i++) {
    $rgb = $GRADIENT[$i] -split ' '
    $bar += (Esc ('38;2;' + $rgb[0] + ';' + $rgb[1] + ';' + $rgb[2])) + $G_FILLED + $E0
  }
  if ($filled -lt $width) {
    $bar += (Esc '2')
    for ($i = $filled; $i -lt $width; $i++) { $bar += $G_EMPTY }
    $bar += (Esc '22')
  }
  return $bar
}

function Format-Tokens($n) {
  $v = [int64](Coalesce $n 0)
  if ($v -ge 1000000) { return ('{0:0.0}M' -f ($v / 1000000.0)) }
  elseif ($v -ge 1000) { return ('{0:0}k' -f ($v / 1000.0)) }
  else { return ('{0}' -f $v) }
}

# ---- read + parse stdin ----
$raw = [Console]::In.ReadToEnd()
try {
  $j = $raw | ConvertFrom-Json
} catch {
  [Console]::Out.Write('statusline: invalid input JSON')
  exit 0
}

# ---- scalar fields (mirror the jq reads in statusline.sh) ----
$model = [string](Coalesce $j.model.display_name '?')
$model = $model -creplace 'Opus ', 'O'
$model = $model -creplace 'Sonnet ', 'S'
$model = $model -creplace 'Haiku ', 'H'
$model = $model -creplace ' \(1M context\)', ($G_MID + '1M')
$model = $model -creplace ' \(200K context\)', ($G_MID + '200K')

$ctxPct  = [int][math]::Floor([double](Coalesce $j.context_window.used_percentage 0))
$ctxSize = [int64](Coalesce $j.context_window.context_window_size 0)
$h5pct   = [int][math]::Floor([double](Coalesce $j.rate_limits.five_hour.used_percentage 0))
$h5reset = Coalesce $j.rate_limits.five_hour.resets_at 0
$d7pct   = [int][math]::Floor([double](Coalesce $j.rate_limits.seven_day.used_percentage 0))
$cost    = [double](Coalesce $j.cost.total_cost_usd 0)
$transcript = [string](Coalesce $j.transcript_path '')

# ---- cache + token stats from the transcript (main thread only) ----
# Mirrors the jq -rs reduction in statusline.sh: aggregate usage across the
# session, excluding subagent/Task entries (isSidechain == true) which would
# otherwise inflate the totals and skew the last-turn cache-hit %.
$cachePct = 0
$cacheReadTotal = [int64]0
$inTotal = [int64]0
$outTotal = [int64]0
if ($transcript -ne '' -and (Test-Path -LiteralPath $transcript)) {
  try {
    $last = $null
    foreach ($line in [System.IO.File]::ReadLines($transcript)) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      try { $o = $line | ConvertFrom-Json } catch { continue }
      if ($null -eq $o.message -or $null -eq $o.message.usage) { continue }
      if ($o.isSidechain -eq $true) { continue }
      $u  = $o.message.usage
      $cr = [int64](Coalesce $u.cache_read_input_tokens 0)
      $cc = [int64](Coalesce $u.cache_creation_input_tokens 0)
      $it = [int64](Coalesce $u.input_tokens 0)
      $ot = [int64](Coalesce $u.output_tokens 0)
      $cacheReadTotal += $cr
      $inTotal  += ($it + $cc + $cr)
      $outTotal += $ot
      $last = $u
    }
    if ($null -ne $last) {
      $crL = [int64](Coalesce $last.cache_read_input_tokens 0)
      $ccL = [int64](Coalesce $last.cache_creation_input_tokens 0)
      $itL = [int64](Coalesce $last.input_tokens 0)
      $denom = $crL + $ccL + $itL
      if ($denom -gt 0) { $cachePct = [int][math]::Floor(($crL * 100) / $denom) }
    }
  } catch { }
}

# ---- 5h reset countdown ----
# resets_at is expected to be epoch seconds; guard against a non-numeric value
# (e.g. an ISO-8601 string) so we never feed garbage into the arithmetic.
$h5left = ''
if (("$h5reset" -match '^\d+$') -and ("$h5reset" -ne '0')) {
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $diff = [int64]$h5reset - $now
  if ($diff -gt 0) {
    $h = [int][math]::Floor($diff / 3600)
    $m = [int][math]::Floor(($diff % 3600) / 60)
    $h5left = ' ' + $h + 'h' + $m + 'm'
  }
}

# ---- theme / background -> gradient (matches statusline.sh case table) ----
$theme = $env:STATUSLINE_THEME; if ([string]::IsNullOrEmpty($theme)) { $theme = 'magma' }
$bg = $env:STATUSLINE_BG;       if ([string]::IsNullOrEmpty($bg))    { $bg = 'dark' }

$MAGMA_DARK = @('30 10 70','60 15 110','95 25 140','130 35 150','170 45 140','205 60 110','230 80 70','245 115 40','255 160 30','255 215 20')
switch ("${theme}_${bg}") {
  'magma_dark'     { $GRADIENT = $MAGMA_DARK }
  'magma_light'    { $GRADIENT = @('40 15 80','70 20 120','100 30 150','135 40 160','170 50 145','195 65 115','210 85 80','200 100 50','180 110 30','150 100 20') }
  'viridis_dark'   { $GRADIENT = @('68 1 84','72 35 116','64 67 135','52 94 141','41 120 142','32 144 140','34 167 132','94 201 97','173 220 53','253 231 36') }
  'viridis_light'  { $GRADIENT = @('50 5 65','60 30 100','55 60 115','50 85 125','45 105 130','40 130 130','50 155 120','75 175 85','120 180 50','150 170 30') }
  'ocean_dark'     { $GRADIENT = @('3 4 94','5 22 122','8 50 153','10 90 195','15 135 230','60 175 245','120 205 250','175 225 250','215 240 252','240 252 255') }
  'ocean_light'    { $GRADIENT = @('5 15 80','10 30 110','15 50 140','20 80 170','25 115 195','40 145 200','60 170 195','70 180 175','75 175 150','70 160 120') }
  'forest_dark'    { $GRADIENT = @('10 40 16','20 70 28','35 100 40','50 130 55','75 160 70','110 190 90','150 215 110','190 230 130','220 240 155','245 248 180') }
  'forest_light'   { $GRADIENT = @('15 50 20','25 75 30','40 100 45','55 125 55','75 145 65','95 160 70','115 170 70','130 170 60','140 165 50','140 155 40') }
  'cyberpunk_dark' { $GRADIENT = @('30 0 60','80 0 130','140 0 180','200 0 220','240 30 200','255 70 150','200 100 240','100 200 255','0 240 220','0 255 150') }
  'cyberpunk_light'{ $GRADIENT = @('40 0 70','75 0 110','115 0 145','150 0 165','180 20 160','195 50 145','200 75 130','150 100 175','100 130 195','60 150 180') }
  default          { $GRADIENT = $MAGMA_DARK }
}

# Accent colours for model name / cost / token counts.
if ($bg -eq 'light') { $cModel = '34'; $cTokens = '34'; $cCost = '31' }
else                 { $cModel = '36'; $cTokens = '36'; $cCost = '35' }

# ---- assemble ----
$barCtx   = Render-Bar $ctxPct
$bar5h    = Render-Bar $h5pct
$bar7d    = Render-Bar $d7pct
$barCache = Render-Bar $cachePct
$inFmt        = Format-Tokens $inTotal
$outFmt       = Format-Tokens $outTotal
$cacheReadFmt = Format-Tokens $cacheReadTotal

if ($ctxSize -ge 1000000)  { $ctxLabel = ('{0}M' -f [int][math]::Floor($ctxSize / 1000000)) }
elseif ($ctxSize -gt 0)    { $ctxLabel = ('{0}K' -f [int][math]::Floor($ctxSize / 1000)) }
else                       { $ctxLabel = '?' }

$costFmt = '{0:0.00}' -f $cost
$pctCtx   = '{0,3}' -f $ctxPct
$pct5h    = '{0,3}' -f $h5pct
$pct7d    = '{0,3}' -f $d7pct
$pctCache = '{0,3}' -f $cachePct

$sep = ' ' + $G_BAR + ' '   # " | "
$line  = (Esc $cModel) + $model + $E0
$line += $sep + 'ctx ' + $barCtx + ' ' + $pctCtx + '%/' + $ctxLabel
$line += $sep + '5h ' + $bar5h + ' ' + $pct5h + '%' + $h5left
$line += $sep + '7d ' + $bar7d + ' ' + $pct7d + '%'
$line += $sep + $G_BOLT + $barCache + ' ' + $pctCache + '%'
$line += $sep + $G_DOWN + (Esc $cTokens) + $inFmt + $E0 + ' ' + $G_UP + (Esc $cTokens) + $outFmt + $E0 + ' ' + $cacheReadFmt + ' cached'
$line += $sep + (Esc $cCost) + '$' + $costFmt + $E0

[Console]::Out.Write($line)
[Console]::Out.Flush()
exit 0
