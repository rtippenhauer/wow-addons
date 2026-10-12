# Tippenhauer Works — Delve Curiosities

Inside a delve, a panel lists every **Mislaid Curiosity, Sturdy Chest, Heavy Trunk and Trove**
as the game shows it on the map. Use a reveal buff and you get them all at once. The panel
also tracks who has picked up which one.

- **Unnamed objects:** sometimes the game shows a marker but won't say what it is (Deep Delve's
  purple "?"). These are listed in purple as **Unnamed object (?)**. When the game reveals the
  name, usually up close, the row takes it.
- **Pickups the game never showed:** if you get a Boon with no known curiosity nearby, the addon
  adds a **Curiosity (picked up)** row where you stood, so your count stays right.
- **Party sync:** party members running this addon share finds and pickups automatically.
  The footer shows who is synced and their version. A version in red means it doesn't match yours.
- **Map pins:** the world map shows a green tick for picked up, gold for still there, grey for gone.
- **Rows:** click a row for a guide arrow to it. Shift-click opens the map. Right-click toggles
  "I got this" if the addon missed a pickup.
- **Guide arrow:** the addon's own on-screen arrow, or TomTom's if TomTom is installed. Drag the
  arrow to move it; right-click it to clear it.

The panel opens by itself when a delve starts and closes when you leave. A new list starts every
time you enter a delve; a `/reload` inside the delve keeps the current list.

| Command | What it does |
|---|---|
| `/tw curios` | Show or hide the panel |
| `/tw curios reset` | Clear this delve's list |
| `/tw curios scan` | Print every map marker the game is showing right now (for bug reports) |
| `/tw curios arrow auto` | Use TomTom's arrow if TomTom is installed, otherwise the addon's own (default) |
| `/tw curios arrow tomtom` / `own` / `both` | Choose the arrow yourself |

You can also open the panel from the Tippenhauer Works minimap button or the AddOns menu.

Requires **TippWorks-Core**. Replaces the curiosities panel from CoiledRareTracker. Your arrow
setting, panel position and the current run are copied over the first time it loads, and the
old `/crt curios` and `/crt arrow` commands still work. It syncs with party members still on
CoiledRareTracker 1.9.x.
