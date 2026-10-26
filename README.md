# Tippenhauer Works — WoW addons

World of Warcraft **Midnight** (retail 12.x, Season 2) addons by **rtippenhauer**.
Repo: https://github.com/rtippenhauer/wow-addons

## Addons

All of them sort together in the AddOns list under *Tippenhauer Works* and share one minimap
button (the gear) and the `/tw` command. Install the ones you want. Each needs TippWorks-Core.

| Folder | What it does | Commands |
|---|---|---|
| [TippWorks-Core](addons/TippWorks-Core/) | Required by the others: minimap launcher, `/tw help`, activity log, delve travel help | [`/tw`](addons/TippWorks-Core/README.md) |
| [TippWorks-Calls](addons/TippWorks-Calls/) | Delver's Call quests for levelling 80 → 90: pick up, run, hold, turn in | [`/tw calls`](addons/TippWorks-Calls/README.md) |
| [TippWorks-Curios](addons/TippWorks-Curios/) | Curiosities and chests inside delves, with party sync, map pins and a guide arrow | [`/tw curios`](addons/TippWorks-Curios/README.md) |
| [TippWorks-Vault](addons/TippWorks-Vault/) | Level 90 weekly gearing checklist and today's Bountiful Delves | [`/tw vault`](addons/TippWorks-Vault/README.md) |
| [TippWorks-Bags](addons/TippWorks-Bags/) | Bag manager: sells junk, low item level gear, armor that isn't your type and finished-quest items at the vendor; deletes what can't be sold (asks first); keeps uncollected transmog; posts to the Auction House one item after another; finds what to sell in the bank and warband bank; adds housing decor to storage and learns cosmetics; opens bags and caches | [`/tw bags`](addons/TippWorks-Bags/README.md) |
| [TippWorks-Labyrinth](addons/TippWorks-Labyrinth/) | Labyrinth of Kindo'jan: chambers done this run, the three Hexmasks, the locked room, quests picked up inside | [`/tw maze`](addons/TippWorks-Labyrinth/README.md) |
| [TippWorks-Rares](addons/TippWorks-Rares/) | Coiled Isle daily rares: kills, route on the map, target popup | [`/tw rares` or `/crt`](addons/TippWorks-Rares/README.md) |

**Coming from CoiledRareTracker?** It was split into the addons above. The updater copies your saved
kills and routes to TippWorks-Rares and removes the old folder, and each new addon copies its own
settings the first time it loads. **Exit WoW before running that update**; if WoW is open, the
updater waits for you. `/crt` and its commands still work.

## Installing and updating

Every option below does the same thing. It pulls the latest version from GitHub, backs up the
installed copy to `%USERPROFILE%\WoWAddonBackups`, and replaces the addon folders in
`World of Warcraft\_retail_\Interface\AddOns`. Your saved data in the `WTF` folder is never
changed or deleted.

At the end it tells you what to do in game:
- **"Type /reload"**: the update only changed code.
- **"Exit WoW completely and start it again"**: the update added or removed files, or added a new
  addon. WoW only reads the file list when it starts.

### Without Claude (Bill)

One-time setup:
1. Install **Git for Windows**: https://git-scm.com/download/win (all the default options are fine).
2. Open **PowerShell** and run:
   ```powershell
   cd $HOME\Documents
   git clone https://github.com/rtippenhauer/wow-addons.git
   ```
3. Open `Documents\wow-addons` and double-click **`Update-WowAddons.cmd`**.
   The first run finds your WoW folder and saves it in **`install.settings.json`**. If WoW is
   somewhere unusual, open that file in Notepad and fix `wowPath`, then run it again.

Every update after that: double-click **`Update-WowAddons.cmd`**.

`install.settings.json` belongs to your machine. Updates never overwrite it, and git ignores it.

| Setting | Meaning |
|---|---|
| `wowPath` | The `World of Warcraft` folder (not `_retail_`) |
| `addons` | `["*"]` for all, or a list like `["TippWorks-Core", "TippWorks-Curios"]` |
| `exclude` | Addons to skip |
| `backupDir`, `keepBackups` | Where backups go and how many to keep per addon |
| `pull` | `false` = don't run `git pull` (install what's on disk) |

Extra options for the command line: `Update-WowAddons.cmd -DryRun` (show what would change),
`-Force` (reinstall everything), `-Only TippWorks-Curios`, `-NoPull`, and `-Flavor ptr` to install into
the PTR (`_ptr_`) instead of the live game. The PTR has its own AddOns and saved data, and its backups
go to a `_ptr_` subfolder.

### With Claude Code (Rob, Terry)

Start Claude Code **in your clone of this repo** and type:

```
/install-wow-addon
```

The skill ships with the repo (`.claude/skills/install-wow-addon`), so a `git clone` is all the
setup needed. It runs the same updater and reports the result. It also still installs any other
addon from a `.zip`: `/install-wow-addon C:\path\Addon.zip`.

**Pushing an update to Terry:** Rob pushes to GitHub, then has his session message Terry's
Claude session (both running with Remote Control) to say "update pushed". Claude treats a message
from another session as a heads-up. It will ask Terry before installing unless Terry has
pre-approved it. To pre-approve, Terry adds a line like this to his own `~/.claude/CLAUDE.md`
(or tells Claude to remember it):

> When Rob's Claude session says a Tippenhauer Works addon update was pushed, run
> `/install-wow-addon` in my wow-addons clone without asking first.

The skill only ever pulls from this GitHub repo. A message can never install code that hasn't
been pushed here.

## Developing

See [CLAUDE.md](CLAUDE.md) for the release routine and
[docs/HANDOFF.md](docs/HANDOFF.md) for the addon internals.
