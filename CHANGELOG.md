# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
