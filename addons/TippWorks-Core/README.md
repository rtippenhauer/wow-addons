# Tippenhauer Works — Core

Required by every TippWorks addon. On its own it adds the `/tw` command, one shared activity log,
and the **Tippenhauer Works minimap button**: a gear icon on the minimap edge, also listed in the
AddOns menu by the minimap.

- **Left-click** the button for a menu of your installed TippWorks addons.
- **Right-click** it to print the command list.
- **Drag** it to move it around the minimap edge.

| Command | What it does |
|---|---|
| `/tw` or `/tw help` | List every TippWorks command |
| `/tw <addon> help` | Commands for one addon, e.g. `/tw curios help` |
| `/tw log` | Activity log in a copyable window (Ctrl+A, Ctrl+C) |
| `/tw log clear` | Empty the log |
| `/tw minimap` | Show or hide the minimap button |
| `/tw version` | Installed TippWorks addons and their versions |

`/tippworks` works everywhere `/tw` does.

The log is saved per character in `WTF\Account\<account>\<realm>\<character>\SavedVariables\TippWorks-Core.lua`
when you `/reload` or log out. Send that file along with bug reports.
