# Tippenhauer Works WoW addons — notes for Claude

Retail WoW (Midnight 12.x) addons by rtippenhauer (Rob), played with Terry and Bill.
Read `docs/HANDOFF.md` before touching Lua: hard-won in-game facts (secret values, secure buttons in combat, delve quirks).

## Constraints
- `tools/Update-WowAddons.ps1` must stay Windows PowerShell 5.1 compatible and ASCII-only (Bill runs it with no extra tooling).
- `tools/migrations.json`: one-time folder renames `{from, to}`; saved data is copied, the old folder removed.
- `install.settings.json` is per machine and gitignored (template: `install.settings.example.json`).
- TippWorks-Rares keeps CoiledRareTracker's SavedVariables (`CoiledRareTrackerDB`, `CoiledRareTrackerAccountDB`) and its
  target button's global name (key binding). Other addons copy old settings from those once (`db.migrated`), so they list
  TippWorks-Rares and CoiledRareTracker in `## OptionalDeps`.
- Never edit addons on Terry's or Bill's machines. To Terry's session, send only the update notice, never code.

## Brand conventions
- Folders `TippWorks-<Name>`; Lua globals and SavedVariables `TippWorks<Name>` (no hyphen).
- `.toc`: `## Title: |cff<accent>Tippenhauer Works|r · <Name>`, `## Author: rtippenhauer (Tippenhauer Works)`,
  `## X-Website: https://github.com/rtippenhauer/wow-addons`, `## Category: Tippenhauer Works`, `## Group: TippWorks-Core`,
  and `## Dependencies: TippWorks-Core` for everything except Core.
- Slash commands are `/tw <feature> ...` plus `/tw help`; each addon's README.md has its command table.
- One minimap launcher (Core), plus an AddOns compartment entry per addon.

## Every change
- Claude cannot run WoW: syntax-check every changed .lua with a Lua 5.1 parser; Rob verifies in game.
- Bump the version in both the `.toc` (`## Version`) and `ns.VERSION` (Core: `TW.VERSION` in Core.lua).
- Release steps (install, PTR, push, notify Terry): `/release`, see `.claude/commands/release.md`.
- Before reading a file over 300 lines, grep or Read with offset/limit; never load whole large files into context.
