# Coiled Rare Tracker — handoff notes (for the next Claude session)

World of Warcraft **Midnight (12.1, Season 2)** retail addon, built iteratively with Rob
(Nectras on Zuluhed) and played with Terry (Ngoth). Current version: **1.9.5**.
Nothing here could ever be run in game by Claude — every change was syntax-checked only,
then verified by Rob in game via screenshots, `/crt log`, and the SavedVariables file.

## What it does (one window, four tabs + a delve panel)
- **Rares** (Coiled Isle, uiMapID 2512): 12 daily rares (50 Coffer Key Shards each).
  Kill tracking, distance/direction, click = waypoint + `/targetexact` + skull.
  Saved route drawn on the world map (Build/Clear Route buttons, bottom-left, shift-drag).
  Fly-over "not up" dimming via vignettes/nameplates. Popup "Target: X" secure button
  (bindable) because addons cannot target on their own.
  Only auto-shows in the Coiled Isle, never inside delves/instances.
- **Delves**: the 10 **Delver's Call** leveling quests (one-time, picked up from an object
  near each entrance — Atal'Aman's is inside the delve). Each row is a 3-step flow:
  1 pick up (waypoint to pickup object) → 2 run delve (waypoint to entrance) →
  done – hold until level 87 → 3 turn in (super-tracks the quest so Blizzard's arrow
  leads to the NPC). Status read from the quest log; all 10 quest IDs are in Data.lua
  and matched to delves by in-game title. Travel directions + closest flight point +
  Silvermoon portal waypoints. Coiled Isle delves are excluded (level 90, no Call).
- **Weekly** (level 90 checklist from Rob's Season 2 gearing PDF): Great Vault, Coffer
  Key Shards x/600, rares (marked "not needed" once shards are capped), Vault delves
  (C_WeeklyRewards World row), Catalyst/Manaflux + tier pieces, Orin's Voidcore (read
  from Nebulous Voidcore season cap), bountiful clears, bounty map, Gilded Stashes.
- **Bountiful**: today's bountiful delves read live from `C_AreaPoiInfo.GetDelvesForMap`
  (atlas contains "bountiful"), version from the POI tooltip widgets.
- **Delve Curiosities panel** (separate window, only inside delves): tracks Mislaid
  Curiosities / Sturdy Chests / Heavy Trunks / troves from vignettes, party sync via
  addon messages (prefix `CRTCurio`), world-map pins, click a row = guide arrow
  (TomTom if installed, else own arrow; `/crt arrow auto|tomtom|own|both`).

## Files
| File | Role |
|---|---|
| CoiledRareTracker.toc | Load order, SavedVariables, AddOns-compartment hooks. `## Version` here too. |
| Data.lua | **`ns.VERSION`**, rares, delves (pickups, IDs, turn-ins), flight points, travel/portals, curio patterns. |
| Log.lua | `ns.Log`, `ns.Guard` (error capture), `/crt log` copyable window, raid-mark + blocked-action logging. |
| Core.lua | Main frame/tabs, rares logic, slash commands, events, zone visibility. |
| Route.lua | World-map route overlay + map buttons. |
| Target.lua | Secure "Target: X" popup + Bindings. |
| Delves.lua | Delver's Call tab, map-name lookup, waypoint/share/describe, `/crt calls`. |
| Curios.lua | Delve curiosity panel, sync, pins, guide arrow, loot detection. |
| Weekly.lua | Weekly tab (currencies found by name, cached in `db.currencyIDs`). |
| Bountiful.lua | Bountiful tab + `ns.DelveTooltipCount` (Gilded Stash probe). |
| Minimap.lua | Minimap button + AddOns compartment entry. |
| Bindings.xml | Key binding for the target popup. |
| INSTALL.md | Install/update steps. |

SavedVariables: `CoiledRareTrackerDB` (per character), `CoiledRareTrackerAccountDB`
(warband: portals, Orin unlock, minimap angle).

## Hard-won facts — don't relearn these
- **Midnight "secret values"**: wrap unit/vignette reads in pcall + `issecretvalue` (see `Safe`).
- **Secure buttons** (rare rows, target popup) can't be shown/hidden/re-attributed in combat;
  their parents can't be resized/hidden in combat either. Everything defers via `pendingToggle`
  or skips while `InCombatLockdown()`. Secure buttons register `AnyUp, AnyDown` and check
  the `ActionButtonUseKeyDown` CVar in PostClick.
- **Map waypoints don't work inside instances**/delves → own arrow / TomTom.
- **Curiosities**: the game spawns **one copy per player** at each spot, and each client sees
  **different GUIDs** for the same object (e.g. `…4C0CE6` vs `…CC0CE6`). Items are merged by
  name + position (≤10 yd world, or same map within 0.01). Copies are counted per spot.
- **Markers/sparkles stay up after looting** (the loot radar keeps them; Deep Delve addon has the
  same problem). So pickups are detected from **loot**: `LOOT_OPENED` + `GetLootSourceInfo`
  (exact GUID), then `CHAT_MSG_LOOT` "You receive … Boon of …" (nearest unclaimed ≤30 yd,
  covers Dundun's walk-over), and only lastly a copy vanishing ≤15 yd.
- Some delve maps (Parhelion Plaza) have **no world transform** (`GetWorldPosFromMapPos` → nil);
  `DistTo` falls back to map position × `C_Map.GetMapWorldSize` (or 500 yd). Without that, distances
  vanish and Boon/vanish pickup detection silently stops.
- Vignettes drop out of view at ~250 yd — vanishes beyond 200 yd are ignored.
- **A new list starts on every zone-in** (only a `/reload` inside the delve keeps it). Safety net:
  the GUID zoneUID (`Creature-0-<srv>-<inst>-<zoneUID>-…`) identifies the delve copy; a different
  one starts a new list, and sync messages from another copy are ignored.
- A delve entered before the scenario starts reports difficulty 0 and shows no curiosities.
- **Addon messages get throttled** (SendAddonMessage result 3). The outbox is de-duplicated and
  drained one message per 0.4 s. Hello `H|<ver>` is answered with `R|<ver>` (never answered back);
  unknown-version senders get a hello. Version swaps work outside delves too.
- `/reload` re-reads Lua but **not the .toc** — so the running version lives in `ns.VERSION`
  (Data.lua). **Adding a new file to the .toc needs a full game restart**; code-only changes
  need just `/reload`.
- Rob (and party members not leader/assist) can't set raid marks in groups — logged as such.
- Coffer Key Shards currency id 3310 (found by name), keys 3028, Voidcore 3418, Manaflux 3465.

## Release routine (keep doing this)
1. Change code. Syntax-check every .lua (e.g. `npx luaparse` / a Lua 5.1 parser).
2. **Bump the version in BOTH** `Data.lua` (`ns.VERSION`) and the `.toc` (`## Version`).
3. Note whether the change adds files (→ "full restart") or not (→ "`/reload` is enough").
4. Zip the `CoiledRareTracker` folder (folder at the zip root), commit/push to the repo.
5. Install: delete `_retail_\Interface\AddOns\CoiledRareTracker`, copy the new folder in.
   **Never touch the WTF folder** (saved kills, routes, logs).
6. Tell the other machine(s) to update; each confirms the version shown in the window corner,
   and in a delve the curiosity footer should show `synced: <name> v<same>` in grey.
7. Other machines must **not** edit the addon locally — changes go through the repo with a
   version bump (an un-bumped local edit caused a 1.9.1/1.9.1 mismatch once).

## Debugging
- `/crt log` (copyable), saved in `WTF\Account\<acct>\<realm>\<char>\SavedVariables\CoiledRareTracker.lua`
  (written only on `/reload`/logout). Rob can upload that file.
- `/crt curios scan` — every map marker the game currently shows (name, atlas, position).
- `/crt stash`, `/crt calls`, `/crt map` (re-resolve map ids).
- `/console scriptErrors 1` or BugSack for Lua errors.

## Open items / unverified
- Szarith the Fanged has no coordinates (`/crt set Szarith` while standing there).
- Gilded Stash count source unknown (`/crt stash` probes a currency and delve tooltips).
- TomTom inside delves: untested — first test pending.
- Bountiful "version" wording in tooltips unconfirmed.
- Weekly "Nebulous Voidcore season cap" assumed to be Orin's allowance only.
- Coiled Isle flight points / Silvermoon flight master coordinates unknown.

## Slash commands
`/crt` toggle · `/crt rares|delves|weekly|bountiful` · `/crt new` · `/crt clearroute` · `/crt next` ·
`/crt route` · `/crt autonext` · `/crt reset` · `/crt set|clear <rare>` · `/crt unseen` · `/crt unlock` ·
`/crt mapbuttons` · `/crt share group|say|guild|self` · `/crt portal <zone>` · `/crt calls` ·
`/crt curios [reset|scan]` · `/crt arrow auto|tomtom|own|both` · `/crt log [clear]` · `/crt minimap` ·
`/crt stash` · `/crt map` · `/crt auto`
