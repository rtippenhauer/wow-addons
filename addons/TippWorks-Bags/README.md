# Tippenhauer Works · Bags

Bag manager. When you open a vendor and something in your bags matches one of your rules, the Bag Manager
opens with a **Sell** list and a total; click **Sell**. Turn on `auto` to sell without asking.

## Rules (per character)

| Rule | Default | What goes |
|---|---|---|
| Junk | on | Grey items |
| Low item level | off | Gear 20+ item levels below the lowest item you wear in that slot (`/tw bags gap <n>` to change) |
| Not your armor type | off | Cloth, leather, mail or plate you can't wear (head, shoulders, chest, waist, legs, feet, wrists, hands) |
| Finished quests | on | Items for quests you've already done |
| Pets you can't learn | on | Pets you already have the most of (usually 3/3). Bound ones are sold (or deleted if the vendor won't take them); tradeable ones go to the **Auction** tab instead |
| Delete what can't be sold | on | Matching items with no vendor price go to the **Delete** tab: click one, confirm, gone |

## Always kept

- Items you **keep**: click one in the window (or `/tw bags keep <shift-click item>`); the **Kept** tab lists them.
- Gear whose **appearance isn't collected** yet (anyone in the warband).
- Items in an **equipment set**, and anything legendary or better.
- **Unbound blue and epic gear**, which could go on the Auction House (setting).
- With **TradeSkillMaster** or **Auctionator** loaded: anything worth at least 3x its vendor price (and 1 gold or more)
  on the Auction House (`/tw bags value`). TSM's price wins when both know the item.

At most **12 items** (greys don't count) are sold per vendor visit: the buyback tab holds the last 12, so every
sale can be bought back. Everything sold or deleted is in `/tw log`.

Settings: Options > AddOns > Tippenhauer Works > Bag Manager.

## Auction House

When you open the Auction House, the **Auction** tab lists what could be posted: unbound green-or-better gear,
recipes, gems, enhancements, pets (with how many you have, e.g. "you have 3/3"), caged battle pets and mounts (`/tw bags mats` adds crafting materials). Click one and it goes
into Blizzard's Post screen with the usual suggested price; click **Post**, and the next item loads by itself.
**Load next** starts from the top. Right-click an item to leave it off the list (`/tw bags unhide` brings them back).
Gear you haven't collected the appearance of is marked, in case you'd rather learn it.

**Prices:** with TradeSkillMaster or Auctionator loaded, each item shows its auction value (the tooltip says whose,
and how old an Auctionator price is) and the list is sorted most valuable first. Auctionator only knows items you've
scanned, so run a full scan now and then. Gear on the Sell list that would disenchant for more than the vendor pays
is marked *(disenchant ~price)*.
TSM replaces the Auction House window, so drag the items into your TSM group and use TSM's Post Scan
(or switch TSM back to the WoW window and the click-to-load works as above).

## Bank

When you open your bank or warband bank and something there matches your rules, the **Bank** tab opens. Vendors only
buy from your bags, so items to sell say *to bags*: click one (or **Move all**) and it moves to your bags for the next
vendor. WoW only deletes from your bags, so clicking an item that can't be sold moves it to your bags first and then
asks to delete it. **Move all** moves both kinds. Right-click to keep an item.

## Other selling addons

If CrapAway (or Scrap, Peddler, AutoVendor, Vendor, SellJunk) is also loaded, Bags warns at login and offers to
disable it. **Keep both** stops the warning for that addon.

## Commands

| Command | What it does |
|---|---|
| `/tw bags` | Show/hide the Bag Manager |
| `/tw bags sell` | Sell the Sell list (at a vendor) |
| `/tw bags rules` | Show which rules are on |
| `/tw bags junk` / `low` / `armor` / `quest` / `pets` | Turn a selling rule on/off |
| `/tw bags delete` | Turn on/off offering to delete items that can't be sold |
| `/tw bags transmog` / `tradeable` / `value` | Turn a protection on/off (`value` uses TSM or Auctionator prices) |
| `/tw bags auto` | Sell at the vendor without asking |
| `/tw bags auction` | Show the Auction tab |
| `/tw bags bank` | Show the Bank tab |
| `/tw bags next` | Turn on/off loading the next item after you post |
| `/tw bags mats` | Turn on/off listing crafting materials on the Auction tab |
| `/tw bags unhide` | Bring back items you right-clicked off the Auction tab |
| `/tw bags why <item>` | Explain what Bags sees about an item and which tab it is on (shift-click the item in) |
| `/tw bags prices` | Show what TSM and Auctionator return for the first items on the Auction tab (for troubleshooting) |
| `/tw bags gap <number>` | Item levels below yours that count as low (default 20) |
| `/tw bags keep <item>` | Never sell this item; again to undo |

Requires **TippWorks-Core**. Replaces CrapAway (it warns you if CrapAway is still on).
