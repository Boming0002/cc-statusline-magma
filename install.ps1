#Requires -Version 5.1
# cc-statusline-magma installer (PowerShell) — for Windows WITHOUT Git Bash.
# (When Git Bash is installed, Claude Code routes the status line through it;
#  use install.sh instead — it sets up the more battle-tested bash version.)
#
# Usage, from a cloned repo:
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
# Or one-liner (downloads statusline.ps1 itself):
#   irm https://raw.githubusercontent.com/Boming0002/cc-statusline-magma/main/install.ps1 | iex

$ErrorActionPreference = 'Stop'

$RepoRaw      = 'https://raw.githubusercontent.com/Boming0002/cc-statusline-magma/main'
$ClaudeDir    = Join-Path $HOME '.claude'
$ScriptDest   = Join-Path $ClaudeDir 'statusline.ps1'
$SettingsPath = Join-Path $ClaudeDir 'settings.json'

# ---- pretty output ----
$ESC = [char]27
function Esc([string]$c) { return [string]$ESC + '[' + $c + 'm' }
function Step($m) { Write-Host ((Esc '32') + '==> ' + (Esc '0') + (Esc '1') + $m + (Esc '0')) }
function Info($m) { Write-Host ((Esc '2') + '    ' + $m + (Esc '0')) }
function Ok($m)   { Write-Host ((Esc '32') + '    ' + [char]0x2713 + (Esc '0') + ' ' + $m) }
function Warn($m) { Write-Host ((Esc '33') + '!! ' + $m + (Esc '0')) }
function Die($m)  { Write-Host ((Esc '31') + [char]0x2717 + ' ' + $m + (Esc '0')); exit 1 }

# Make UTF-8 (no BOM) the file-writing encoding — works on both 5.1 and 7. A BOM
# in settings.json breaks Claude Code's JSON parser, so never let one slip in.
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
function Write-TextFile($path, $text) { [System.IO.File]::WriteAllText($path, $text, $Utf8NoBom) }

Write-Host ((Esc '1') + 'cc-statusline-magma installer (PowerShell)' + (Esc '0'))
Info ('Source: ' + $RepoRaw)
Write-Host ''

# ---- 1. ensure ~/.claude ----
Step ('Preparing ' + $ClaudeDir)
if (-not (Test-Path -LiteralPath $ClaudeDir)) {
  New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
  Ok ('created ' + $ClaudeDir)
} else { Ok 'exists' }

# ---- 2. pick a PowerShell launcher (5.1 'powershell' preferred; fall back to pwsh) ----
$PsLauncher = 'powershell'
if (-not (Get-Command powershell -ErrorAction SilentlyContinue)) {
  if (Get-Command pwsh -ErrorAction SilentlyContinue) { $PsLauncher = 'pwsh' }
  else { Die 'Neither powershell nor pwsh found on PATH.' }
}

# ---- 3. install statusline.ps1 ----
Step 'Installing statusline.ps1'
$localSrc = $null
if ($PSScriptRoot) { $localSrc = Join-Path $PSScriptRoot 'statusline.ps1' }
if ($localSrc -and (Test-Path -LiteralPath $localSrc)) {
  Copy-Item -LiteralPath $localSrc -Destination $ScriptDest -Force
  Info 'copied from ./statusline.ps1'
} else {
  Info ('downloading from ' + $RepoRaw + '/statusline.ps1')
  try { Invoke-WebRequest -UseBasicParsing -Uri ($RepoRaw + '/statusline.ps1') -OutFile $ScriptDest }
  catch { Die ('download failed: ' + $_.Exception.Message) }
}
$size = (Get-Item -LiteralPath $ScriptDest).Length
if ($size -lt 100) { Die ("statusline.ps1 is suspiciously small ($size bytes) — download corrupt?") }
Ok ($ScriptDest + "  ($size bytes)")

# ---- 4. smoke test (run it through the same launcher that settings.json will use) ----
Step 'Smoke-testing statusline'
$testJson = '{"model":{"display_name":"Opus 4.7"},"context_window":{"used_percentage":50,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":25},"seven_day":{"used_percentage":10}},"cost":{"total_cost_usd":1.23},"transcript_path":""}'
$out = ''
$errFile = [System.IO.Path]::GetTempFileName()
try {
  # & is a native-command call: a crash sets $LASTEXITCODE + writes stderr but does
  # NOT throw, so we must check the exit code explicitly (the catch only fires for
  # parent-side launch errors). Capture stderr to fold into the diagnostic, like
  # install.sh's `2>&1 || die`.
  $out = $testJson | & $PsLauncher -NoProfile -File $ScriptDest 2>$errFile
} catch {
  Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
  Die ('script crashed on test input: ' + $_.Exception.Message)
}
$childExit = $LASTEXITCODE
$err = Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
$out = ($out | Out-String).TrimEnd("`r", "`n")   # flatten any multi-line capture to one string
if ($childExit -ne 0)               { Die ("script crashed on test input (exit $childExit):`n" + $err) }
if ([string]::IsNullOrWhiteSpace($out)) { Die ("script ran but produced no output`n" + $err) }
Ok ('renders: ' + $out.Substring(0, [math]::Min(60, $out.Length)) + [char]0x2026)

# ---- 5. merge statusLine block into settings.json ----
Step ('Updating ' + $SettingsPath)
if (-not (Test-Path -LiteralPath $SettingsPath)) {
  Write-TextFile $SettingsPath '{}'
  Info 'created empty settings.json'
}
try { $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json }
catch { Die ($SettingsPath + ' is not valid JSON — fix it manually before re-running') }
if ($null -eq $settings) { $settings = [PSCustomObject]@{} }

$backup = $SettingsPath + '.bak'
Copy-Item -LiteralPath $SettingsPath -Destination $backup -Force
Info ('backup: ' + $backup + ' (previous settings.json)')

# Forward slashes in the path — Git Bash (if CC ever routes through it) eats
# unquoted backslashes, and PowerShell accepts forward slashes fine.
$fwdPath = $ScriptDest -replace '\\', '/'
$command = $PsLauncher + ' -NoProfile -File ' + $fwdPath

$existing = $null
if ($settings.PSObject.Properties.Name -contains 'statusLine') { $existing = $settings.statusLine.command }
if ($existing -and ($existing -ne $command)) {
  Warn 'Replacing an existing statusLine command'
  Info ('was: ' + $existing)
  Info ('now: ' + $command + '   (previous config saved in ' + $backup + ')')
}

$sl = [PSCustomObject]@{ type = 'command'; command = $command; padding = 0 }
$settings | Add-Member -NotePropertyName statusLine -NotePropertyValue $sl -Force
Write-TextFile $SettingsPath (($settings | ConvertTo-Json -Depth 100))

$check = (Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json).statusLine.command
if ($check -ne $command) { Die ('settings.json merge did not write the expected command (got: ' + $check + ')') }
Ok ('.statusLine.command = ' + $command)

# ---- 6. final reminder ----
Write-Host ''
Write-Host ((Esc '7') + (Esc '1') + '  RESTART CLAUDE CODE TO SEE THE STATUSLINE  ' + (Esc '0'))
Write-Host ((Esc '1') + '  In CC: type ' + (Esc '32') + '/exit' + (Esc '0') + (Esc '1') + ', then re-run ' + (Esc '32') + 'claude' + (Esc '0'))
Write-Host ''
Info 'Optional:'
Info '  Switch theme:   $env:STATUSLINE_THEME = "viridis"   # magma|viridis|ocean|forest|cyberpunk'
Info '  Light terminal: $env:STATUSLINE_BG = "light"'
Info ('  Manual preview: ' + "'<mock json>'" + ' | ' + $PsLauncher + ' -NoProfile -File ' + $ScriptDest)
Write-Host ((Esc '32') + 'Done.' + (Esc '0'))
