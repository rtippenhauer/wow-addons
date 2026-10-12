# Tippenhauer Works WoW addons — notes for Claude

Retail WoW (Midnight 12.x) addons by rtippenhauer (Rob). Repo: https://github.com/rtippenhauer/wow-addons.
Played with Terry and Bill. Read `addons/CoiledRareTracker/HANDOFF.md` before touching Lua: it holds
the hard-won in-game facts (secret values, secure buttons in combat, delve quirks).

## Layout
- `addons/<Folder>/` — one folder per addon, each with `<Folder>.toc`. The updater installs every such folder.
- `tools/Update-WowAddons.ps1` — pull + backup + replace into AddOns. Must stay **Windows PowerShell 5.1**
  compatible and ASCII-only (Bill runs it with no extra tooling). `Update-WowAddons.cmd` wraps it.
- `tools/migrations.json` — one-time folder renames (`{from, to}`): saved data is copied, old folder removed.
- `install.settings.json` — per machine, gitignored. Template: `install.settings.example.json`.
- `.claude/skills/install-wow-addon/` — the `/install-wow-addon` skill shared by Rob and Terry.

## Brand conventions (TippWorks split in progress)
- Folders `TippWorks-<Name>`. Lua globals and SavedVariables use `TippWorks<Name>` (no hyphen).
- `.toc`: `## Title: |cff<accent>Tippenhauer Works|r · <Name>`, `## Author: rtippenhauer (Tippenhauer Works)`,
  `## X-Website: https://github.com/rtippenhauer/wow-addons`, `## Category: Tippenhauer Works`,
  `## Group: TippWorks-Core`, and `## Dependencies: TippWorks-Core` for everything except Core.
- Slash commands: `/tw <feature> ...`, plus `/tw help`. Each addon has a README.md with its command table.
- One minimap launcher button (TippWorks-Core), plus an AddOns compartment entry per addon.

## Release routine
Claude cannot run WoW. Every change is syntax-checked here and then verified in game by Rob.
1. Change the code. Syntax-check every changed .lua (Lua 5.1 parser, e.g. `npx luaparse`).
2. Bump the version in **both** the addon's `.toc` (`## Version`) and its `ns.VERSION`.
3. Optionally test locally: `/install-wow-addon --local` (runs the updater with `-NoPull`).
4. Commit and push to `main`. The updater tells each player whether `/reload` is enough or a restart is needed.
5. Offer to tell Terry's session (ListAgents / SendMessage): "TippWorks update pushed: <addons/versions>,
   run /install-wow-addon". Send only that notice, never code. Bill updates himself with `Update-WowAddons.cmd`.
6. Never edit addons on Terry's or Bill's machines. The updater refuses to pull over local edits.
