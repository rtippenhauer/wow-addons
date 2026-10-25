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
| Delete what can't be sold | on | Matching items with no vendor price go to the **Delete** tab: click one, confirm, gone |

## Always kept

- Items you **keep**: click one in the window (or `/tw bags keep <shift-click item>`); the **Kept** tab lists them.
- Gear whose **appearance isn't collected** yet (anyone in the warband).
- Items in an **equipment set**, and anything legendary or better.
- **Unbound blue and epic gear**, which could go on the Auction House (setting).

At most **12 items** (greys don't count) are sold per vendor visit: the buyback tab holds the last 12, so every
sale can be bought back. Everything sold or deleted is in `/tw log`.

Settings: Options > AddOns > Tippenhauer Works > Bag Manager.

## Commands

| Command | What it does |
|---|---|
| `/tw bags` | Show/hide the Bag Manager |
| `/tw bags sell` | Sell the Sell list (at a vendor) |
| `/tw bags rules` | Show which rules are on |
| `/tw bags junk` / `low` / `armor` / `quest` | Turn a selling rule on/off |
| `/tw bags delete` | Turn on/off offering to delete items that can't be sold |
| `/tw bags transmog` / `tradeable` | Turn a protection on/off |
| `/tw bags auto` | Sell at the vendor without asking |
| `/tw bags gap <number>` | Item levels below yours that count as low (default 20) |
| `/tw bags keep <item>` | Never sell this item; again to undo |

Requires **TippWorks-Core**. Replaces CrapAway (disable it, or both will sell junk).
