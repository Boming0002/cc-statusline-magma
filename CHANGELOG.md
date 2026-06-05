# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] — 2026-06-05

### Added

- **Windows support**, in two paths that match how Claude Code runs the status line on Windows (through Git Bash if installed, otherwise PowerShell):
  - `statusline.ps1` — a PowerShell port for Windows **without** Git Bash. No `jq` dependency (parses JSON natively via `ConvertFrom-Json`), targets **both Windows PowerShell 5.1 and PowerShell 7+**, and renders identically to the bash version (same gradients, same `STATUSLINE_THEME` / `STATUSLINE_BG` knobs). Source is pure ASCII (glyphs built from code points) so no UTF-8 BOM is needed on 5.1.
  - `install.ps1` — PowerShell installer (`irm … | iex` or `-File .\install.ps1`): copies the script, smoke-tests it, and merges the `statusLine` block into `settings.json` (written UTF-8 **without BOM**) using a forward-slash `powershell -NoProfile -File …` command.
  - `install.sh` now also resolves `jq` via `winget` / `scoop` / `choco` / `pacman` (Windows / MSYS), alongside `brew` / `apt` / `yum` / `dnf` / `apk`.
- `.gitattributes` normalises line endings (`* text=auto`) and pins `*.sh` / `*.ps1` / `*.md` to LF — chiefly so a CRLF checkout on Windows can't turn the bash shebang into `bash\r` (`bad interpreter`).
- README: **Windows** section (both paths) and an **Uninstall** section.

### Fixed

- **Cache / token stats now count the main thread only.** The transcript reduction excludes subagent/Task entries (`isSidechain: true`), which previously inflated the cumulative `↓in` / `↑out` / `cached` totals and could let a subagent's turn drive the displayed last-turn cache-hit %.
- **`statusline.sh` no longer errors when `resets_at` is non-numeric.** A digit guard ensures only an epoch-seconds value reaches the countdown arithmetic, so an ISO-8601 timestamp can't emit a per-render `$(( ))` error or silently drop the countdown.
- Under Git Bash, `statusline.sh` translates the Windows `transcript_path` via `cygpath`, so cache/token stats work there (the Windows-style path couldn't be `stat`-ed before, zeroing those fields).

### Changed / Hardened

- `install.sh`: `jq` auto-install now uses `sudo -n` (never blocks on a password prompt in a piped `curl | bash`) and skips `sudo` when running as root or when it's absent; **warns before replacing a *different* existing `statusLine`**; keeps a single rolling `settings.json.bak` instead of accumulating `.bak.<epoch>` files on every run.
- `statusline.sh`: `fmt_tokens` coerces a non-integer argument to `0` (defensive); a missing `jq` at runtime now prints a short notice instead of a broken half-line.

### Docs

- Corrected the README example and field table to match the **actual** output: model is abbreviated to `O4.7·1M` (`Opus`→`O`, `Sonnet`→`S`, `Haiku`→`H`; context suffix `·1M` / `·200K` — previously undocumented), token totals carry the `.0` decimal (`106.0M`), percentages are right-aligned to 3 chars, and the cumulative totals are main-thread only.

## [1.2.1] — 2026-05-20

### Improved

- **Hardened `install.sh`** to catch silent failures users were hitting:
  - Pre-flight validation: jq version printed, `~/.claude/` writability checked.
  - Post-download checks: file size sanity (`> 100 bytes`) + `bash -n` syntax check on `statusline.sh` — catches corrupt / partial downloads.
  - **Smoke test built into installer**: pipes a mock JSON through the script and verifies non-empty output before declaring success.
  - JSON validation of `settings.json` **before** mutation (refuses to merge into malformed JSON; preserves user's broken file untouched).
  - Post-merge verification: re-reads `.statusLine.command` and confirms it points to the installed script.
- **Bold inverted-video "RESTART CLAUDE CODE" reminder** at the end (was dim text in v1.0–1.2, easy to miss).
- Step-by-step progress output with `==>` headers + `✓` confirmations — diagnoses where things fail without `--verbose`.

### Why

Several users reported "installed but statusline doesn't show". Root causes were:
1. They didn't restart Claude Code (now: prominent reminder)
2. `curl` partial download produced a zero-byte / truncated `statusline.sh` (now: size + syntax check)
3. Pre-existing malformed `settings.json` made `jq` merge fail silently (now: validate first, refuse on bad input)

## [1.2.0] — 2026-05-20

### Added

- **Light terminal support** via `STATUSLINE_BG=light` environment variable.
  - Each of the 5 themes now ships with a hand-tuned light-bg gradient that caps brightness — no fade-to-white that becomes invisible.
  - Accent colours swap on light bg: `cyan` → `blue` for model name and token counts; `magenta` → `red` for cost.
  - Default `STATUSLINE_BG=dark` preserves all existing behaviour.
- Unknown `STATUSLINE_BG` values silently fall back to `dark`.

### Changed

- Theme + bg are now combined via `${THEME}_${BG}` case statement (10 valid combinations).
- README has a new "Dark vs Light terminal" section with mix examples.

## [1.1.0] — 2026-05-20

### Added

- **5 colour themes**, switchable via `STATUSLINE_THEME` environment variable:
  - `magma` *(default)* — original indigo → magenta → orange → yellow
  - `viridis` — colour-blind friendly, perceptually uniform
  - `ocean` — deep navy → cyan → white, cool aquatic
  - `forest` — dark green → lime, warm natural
  - `cyberpunk` — purple → magenta → cyan → mint, saturated neon
- Unknown theme values silently fall back to `magma`.

## [1.0.0] — 2026-05-20

### Added

- Initial public release.
- `statusline.sh` — bash + jq script rendering model / context% / 5h quota / 7d quota / cache hit% / session tokens / cost.
- Smooth-Magma 24-bit gradient (10 RGB triples, dark indigo → magenta → orange → bright yellow).
- Cells coloured by position (not percentage) for consistent palette across all metrics; labels carry the good-vs-bad semantic.
- Dimmed empty cells (`▱`) for visual contrast.
- Cache hit rate computed from session transcript via `jq` reduction on `cache_read_input_tokens` / `cache_creation_input_tokens` / `input_tokens`.
- Session-cumulative input / output / cache-read totals in human units (`k`, `M`).
- `install.sh` — one-command installer that detects OS, ensures `jq`, copies the script, and merges `statusLine` block into `~/.claude/settings.json`.
- README with usage screenshot and troubleshooting table.
- MIT License.

### Compatibility

- Claude Code ≥ 2.1.116 required (earlier versions lack `context_window` / `rate_limits` / `cost` JSON fields).
- Tested on macOS bash 3.2.57 and Linux bash 5.x.
- Truecolor terminal required for full gradient; old terminals fall back to uncoloured `▰▱` characters.
