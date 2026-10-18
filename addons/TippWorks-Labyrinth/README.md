# Tippenhauer Works — Labyrinth of Kindo'jan

For the Labyrinth of Kindo'jan, the 12.1.5 mega-delve. The window opens by itself inside and tracks
**this run**. Chamber progress doesn't carry over between runs, so each new entry starts a fresh list.

- **Chambers (x/9):** the nine chambers, with the one you're standing in marked with ">". Each one
  goes from "in progress" to "done" when the game completes its objective. Every 3 is a reward
  checkpoint (3, 6, 9). **Right-click** a chamber to mark it done or not done by hand. **Left-click** a
  starred (*) chamber to get the guide arrow to its mask/locked-room spot. Map waypoints don't work
  inside delves, so this uses TippWorks-Curios' arrow (or TomTom's).
- **Hexmasks (x/3):** Frozen, Fiery and Thundering, and the chamber where you found each one. All three in one
  run earns *Happy Hexmask Collector*. The five chambers marked * are the spots that can hold a mask
  or the locked room (from Journey rank 2): Chamber of Rites, The Cave Towers, Akil'zon's Roost,
  Jan'alai's Refuge and Nalorakk's Rest.
- **Locked room:** the **Keeper of the Key** showing up on the map, and whether you have the **Archaic Amani
  Key**. The key counts whether it arrives as a loot line, a bag item or a buff. Once the locked door is
  found, it's marked with a **key icon** on the Labyrinth map, until the key is used (it leaves your bags or
  the buff ends) or you mark it opened. The "Door" row: left-click for the arrow, right-click to mark it
  opened. `/tw maze door` marks the door where you're standing if the addon missed it.
- **Chests tab:** the **20 Sturdy Chests** that need nothing to reach, by chamber with coordinates. Sturdy
  Chests loot **once per character**, so these stay ticked across runs. When you open loot right beside one
  (within about 2% of the map), it's ticked automatically. Left-click a chest for the guide arrow;
  right-click marks it looted or not. Unlooted ones also show as gold pins on the Labyrinth's world map.
  Our padlock pins on the sealed rooms are off by default, since the game marks sealed doors itself (`/tw maze padlocks` turns them on; a room's padlock goes once you've been inside, remembered per
  character; right-click its row to mark it opened or locked). The tab also lists the **9 Loa-sealed rooms** (2-3 more chests each, opened at Labyrinth Journey ranks
  3/5/7/9) and how to reach the **Flooded Chamber**: swim under the two waterfalls on the east side of the
  Central Chamber, then melt the ice wall with any Fire damage. The Run tab shows "chests got/total" per chamber.
- **Quests from the Labyrinth:** every quest your quest log files under the *The Labyrinth of
  Kindo'jan* heading, e.g. the one from a mask, plus anything picked up inside. It doesn't matter
  when you picked it up or where you are now; `/tw maze` shows them anywhere. Click one to track it,
  see the next step, and get a waypoint to where the game says to go to finish it.

| Command | What it does |
|---|---|
| `/tw maze` | Show or hide the window (`/tw labyrinth` and `/tw lab` work too) |
| `/tw maze where` | Which chamber the addon thinks you're in |
| `/tw maze spots` | The five mask/locked-room spots with coordinates |
| `/tw maze chests` | Open the Chests tab |
| `/tw maze door` | Mark the locked door where you're standing (key icon on the map) |
| `/tw maze pins` | Show or hide the chest pins on the Labyrinth map |
| `/tw maze reset` | Start a fresh run list |

This first version also writes what the game reports into `/tw log`: chamber names, objectives, buffs,
map markers and quests. That's so the chamber, mask and room detection can be checked against a real
run and tightened up.

Chest, sealed-room and spot coordinates are from Wowhead's Labyrinth guide (updated Oct 16 2026): Chamber of Rites 50.3, 82.6; The Cave Towers
88.5, 51.5; Akil'zon's Roost 56.8, 17.8; Jan'alai's Refuge 18.8, 18.2; Nalorakk's Rest 58.5, 21.7.

Tier doesn't matter for the masks, the key and locked room, or the chests: those depend on your
Labyrinth Journey rank. Kindo'jan and Wah'du's weekly tasks need Tier 8+; the Tier 11 achievements need Tier 11.

Requires **TippWorks-Core**. The arrow needs **TippWorks-Curios** or TomTom.
