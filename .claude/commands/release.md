---
description: Release TippWorks addon changes (test locally, push, notify Terry)
---

Release the current TippWorks addon changes.

1. Syntax-check every changed .lua (Lua 5.1 parser) and confirm each changed addon's version is bumped in both
   its `.toc` (`## Version`) and `ns.VERSION` (Core: `TW.VERSION`).
2. Optionally test locally: `/install-wow-addon --local` (runs the updater with `-NoPull`). Before a patch, try it
   on the PTR with `/install-wow-addon --local --ptr` (`-Flavor ptr`), and add the PTR's interface number to each
   `.toc` `## Interface:` line so WoW doesn't list the addon as out of date.
3. Commit and push to `main`. The updater tells each player whether `/reload` is enough or a restart is needed.
4. Offer to tell Terry's session (ListAgents / SendMessage): "TippWorks update pushed: <addons/versions>, run
   /install-wow-addon". Send only that notice, never code. Bill updates himself with `Update-WowAddons.cmd`.
5. The updater refuses to pull over local edits on a player's machine; never edit addons there.
