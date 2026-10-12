# Tippenhauer Works — Coiled Isle Rares

The 12 Coiled Isle daily rares, worth 50 Coffer Key Shards each. The window opens by itself when
you arrive on the Coiled Isle, but not inside delves.

- **Rows:** distance and direction to each rare. Kills are detected automatically. Rares you fly
  past that aren't up are dimmed.
- **Left-click a row** for a waypoint. It also targets the rare and puts a skull on it.
- **Right-click a row** to toggle "killed".
- **Route:** **New Route** plans the shortest run from where you are. It's drawn on the world map
  with numbered pins. The map's Build/Clear Route buttons can be moved with shift-drag.
- **Target popup:** when a rare is spotted, a "Target: X" button pops up. Click it or press its key
  binding (Options → Keybindings → AddOns) to target and skull the rare. Addons can't target on
  their own.

| Command | What it does |
|---|---|
| `/tw rares` or `/crt` | Show or hide the window |
| `/tw rares new` | Build a new route from where you are |
| `/tw rares next` | Waypoint to the next rare on the route |
| `/tw rares clearroute` | Remove the route from the map |
| `/tw rares route` | Show or hide the route on the map |
| `/tw rares autonext` | Auto-waypoint to the next rare after a kill (on/off) |
| `/tw rares auto` | Open the window by itself on the Coiled Isle (on/off) |
| `/tw rares reset` | Clear today's kills |
| `/tw rares unseen` | Clear the "not up" marks |
| `/tw rares set <rare>` | Save a rare's location where you stand (e.g. `set Szarith`) |
| `/tw rares clear <rare>` | Restore a rare's default location |
| `/tw rares unlock` | Move the Target popup (run it again to lock) |
| `/tw rares mapbuttons` | Move the map buttons back to the bottom-left |
| `/tw rares map` | Re-find the Coiled Isle map |

The on/off options (`auto`, `autonext`, `route`) are also checkboxes in Options → AddOns →
Tippenhauer Works → Coiled Rares (`/tw settings`).

Everything after `/tw rares` also works after `/crt` (e.g. `/crt new`). Old commands like
`/crt weekly` and `/crt curios` still work and open the new addons.

Requires **TippWorks-Core**. This is CoiledRareTracker's rares part. It keeps the same saved data,
so your kills, route, settings and Target key binding carry over. The updater copies the saved
data and removes the old CoiledRareTracker folder. That last step needs WoW closed.
