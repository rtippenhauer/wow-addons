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
- **Locked room:** says when the **Keeper of the Key** shows up on the map (it drops the Archaic Amani
  Key) and when you have the key.
- **Quests from the Labyrinth:** every quest your quest log files under the *The Labyrinth of
  Kindo'jan* heading, e.g. the one from a mask, plus anything picked up inside. It doesn't matter
  when you picked it up or where you are now; `/tw maze` shows them anywhere. Click one to track it,
  see the next step, and get a waypoint to where the game says to go to finish it.

| Command | What it does |
|---|---|
| `/tw maze` | Show or hide the window (`/tw labyrinth` and `/tw lab` work too) |
| `/tw maze where` | Which chamber the addon thinks you're in |
| `/tw maze spots` | The five mask/locked-room spots with coordinates |
| `/tw maze reset` | Start a fresh run list |

This first version also writes what the game reports into `/tw log`: chamber names, objectives, buffs,
map markers and quests. That's so the chamber, mask and room detection can be checked against a real
run and tightened up.

Spot coordinates are from Wowhead / Seramate (Oct 15 2026): Chamber of Rites 50.3, 82.6; The Cave Towers
88.5, 51.5; Akil'zon's Roost 56.8, 17.8; Jan'alai's Refuge 18.8, 18.2; Nalorakk's Rest 58.5, 21.7.

Requires **TippWorks-Core**. The arrow needs **TippWorks-Curios** or TomTom.
