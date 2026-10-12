# Coiled Rare Tracker - install / update

## Install or update (manual or Claude Code)
1. Close the CoiledRareTracker window in game (optional).
2. Unzip `CoiledRareTracker.zip` into:
   `World of Warcraft\_retail_\Interface\AddOns\`
   so you end up with `...\Interface\AddOns\CoiledRareTracker\CoiledRareTracker.toc`.
   **Replace** the existing `CoiledRareTracker` folder (delete it first, then unzip),
   so no old files are left behind.
3. In game:
   - Updating, and the release notes say "/reload is enough": type `/reload`.
   - First install, or the update adds new files: exit WoW fully and start it again
     (WoW only reads an addon's file list at startup).
4. Check the version in the top-right corner of the addon window matches the one you installed.

Saved data (kills, routes, logs) lives in `WTF\Account\...\SavedVariables\CoiledRareTracker.lua`
and is NOT touched by updating - don't delete that.

## Prompt you can give Claude Code
> Install the WoW addon in CoiledRareTracker.zip: find my World of Warcraft install,
> delete `_retail_\Interface\AddOns\CoiledRareTracker` if it exists, and unzip the zip
> into `_retail_\Interface\AddOns` so the .toc file is at
> `_retail_\Interface\AddOns\CoiledRareTracker\CoiledRareTracker.toc`.
> Do not touch the WTF folder.
