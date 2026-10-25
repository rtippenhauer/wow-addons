local ADDON, ns = ...
local TW = TippWorks

-- Bag manager: at a vendor, lists what can go (junk, gear well below what you
-- wear, armor that isn't your type, items for quests you've finished) and
-- sells it with one click - or by itself if you turn that on. Items that
-- can't be sold can be deleted, one confirmed click each.
-- Never touched: uncollected transmog, equipment-set items, items you keep,
-- unbound blue+ gear (Auction House) and anything above epic.
-- At the Auction House, the Auction tab lists what could be posted; click one
-- and it goes into Blizzard's Post screen, and after you post the next loads.

-- The running version. WoW only re-reads the .toc on a full restart, so the
-- number lives here too. Bump both together.
ns.VERSION = "1.7.0"
local Print = TW.Printer("Bags")
local Safe = TW.Safe

-- Popups name the addon: they appear in the middle of the screen with no other hint where they came from.
local POPUP_HEADER = "|cff" .. TW.COLOR .. "Tippenhauer Works|r - Bag Manager\n\n"

local MAX_SELL = 12 -- the vendor's buyback tab holds the last 12 items: keep every sale recoverable
local SELL_DELAY = 0.2

local db
local win, rows = nil, {}
local WIDTH, ROW_H = 500, 18 -- six tabs need 498

-- Defaults: junk and finished-quest items on; the gear rules are opt-in.
local DEFAULTS = {
    junk = true, lowLevel = false, wrongArmor = false, quest = true, pets = true, known = true, decor = true, offerDelete = true,
    protectTransmog = true, protectTradeable = true, autoSell = false, ilvlGap = 20,
    autoNext = true, auctionMats = false, protectValue = true,
}
local function Opt(k) if db[k] == nil then return DEFAULTS[k] end return db[k] end

---------------------------------------------------------------------------
-- What the player wears
---------------------------------------------------------------------------
local ARMOR_CLASS, WEAPON_CLASS = 4, 2
local ARMOR_TYPE = { WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4, HUNTER = 3, SHAMAN = 3, EVOKER = 3,
    ROGUE = 2, DRUID = 2, MONK = 2, DEMONHUNTER = 2, MAGE = 1, PRIEST = 1, WARLOCK = 1 }
local ARMOR_NAME = { "cloth", "leather", "mail", "plate" }
-- Only these slots have an armor type (cloaks are "cloth" for everyone).
local TYPED_SLOTS = { INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true,
    INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true }
-- Equipped slots to compare an item with (the lower of two for rings, trinkets, one-handers).
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_RANGED = { 16 }, INVTYPE_RANGEDRIGHT = { 16 },
}

-- Bind types (Enum.ItemBind) that can never be traded: bind on pickup, quest, and the warbound /
-- account-bound kinds (7 ToWoWAccount, 8 ToBnetAccount, 9 ToBnetAccountUntilEquipped).
local NO_TRADE_BIND = { [1] = true, [4] = true, [7] = true, [8] = true, [9] = true }

-- What can go on the Auction House besides unbound gear (item class -> label).
local AUCTION_KIND = { [3] = "gem", [8] = "enhancement", [9] = "recipe", [16] = "glyph", [19] = "profession gear" }
local function AuctionKind(classID, subclassID, quality)
    if classID == ARMOR_CLASS or classID == WEAPON_CLASS then return quality >= 2 and "unbound gear" or nil end
    if AUCTION_KIND[classID] then return AUCTION_KIND[classID] end
    if classID == 15 and subclassID == 2 then return "pet" end
    if classID == 15 and subclassID == 5 then return "mount" end
    if classID == 7 and Opt("auctionMats") then return "material" end
end

-- Pets: how many of a species you have and the most you can learn (usually 3, unique pets 1).
local function PetCount(speciesID)
    if not speciesID or not (C_PetJournal and C_PetJournal.GetNumCollectedInfo) then return nil end
    local ok, have, limit = pcall(C_PetJournal.GetNumCollectedInfo, speciesID)
    if ok and have and limit then return have, limit end
end
local function PetSpecies(itemID)
    if not (C_PetJournal and C_PetJournal.GetPetInfoByItemID) then return nil end
    local r = { pcall(C_PetJournal.GetPetInfoByItemID, itemID) }
    return r[1] and r[14] or nil -- 13th return value: speciesID
end
-- Housing decor: using the item adds it to your housing storage.
local function IsDecor(itemID, classID)
    if C_Item.IsDecorItem then
        local ok, v = pcall(C_Item.IsDecorItem, itemID)
        if ok and v then return true end
    end
    return Enum and Enum.ItemClass and Enum.ItemClass.Housing ~= nil and classID == Enum.ItemClass.Housing
end

-- Mounts and toys you already know: returns "mount" / "toy" when this item teaches one you have.
local function KnownKind(itemID)
    if C_MountJournal and C_MountJournal.GetMountFromItem then
        local ok, mountID = pcall(C_MountJournal.GetMountFromItem, itemID)
        if ok and mountID and C_MountJournal.GetMountInfoByID then
            local r = { pcall(C_MountJournal.GetMountInfoByID, mountID) }
            if r[1] and r[12] == true then return "mount" end -- 11th return value: isCollected
            return nil
        end
    end
    if C_ToyBox and C_ToyBox.GetToyInfo and PlayerHasToy then
        local ok, toyItem = pcall(C_ToyBox.GetToyInfo, itemID)
        if ok and toyItem and PlayerHasToy(itemID) then return "toy" end
    end
end

local function PetNote(have, limit)
    if not have then return "" end
    if have == 0 then return " - |cffff9933not collected|r" end
    return (" - you have %d/%d"):format(have, limit)
end

local function ItemLevel(link)
    local lvl = C_Item.GetDetailedItemLevelInfo and Safe(C_Item.GetDetailedItemLevelInfo, link)
    return tonumber(lvl)
end

-- The lowest item level you wear in the slots this item would go in; nil if one is empty.
local function EquippedLevel(equipLoc)
    local slots = SLOTS[equipLoc]
    if not slots then return nil end
    local low
    for _, s in ipairs(slots) do
        local link = GetInventoryItemLink("player", s)
        local lvl = link and ItemLevel(link)
        if not lvl then return nil end
        if not low or lvl < low then low = lvl end
    end
    return low
end

-- True when the item's appearance can still be collected (by anyone in the warband).
local function UncollectedAppearance(link)
    if not C_TransmogCollection or not C_TransmogCollection.GetItemInfo then return false end
    local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(link)
    if not appearanceID or not sourceID then return false end -- no appearance (rings, trinkets...)
    local sources = C_TransmogCollection.GetAllAppearanceSources and Safe(C_TransmogCollection.GetAllAppearanceSources, appearanceID)
    for _, id in ipairs(type(sources) == "table" and sources or { sourceID }) do
        local info = Safe(C_TransmogCollection.GetSourceInfo, id)
        if type(info) == "table" and info.isCollected then return false end
    end
    return true
end

---------------------------------------------------------------------------
-- Sorting the bags
---------------------------------------------------------------------------
local auctionOpen = false

-- False only when the Auction House says the item can't be posted (it only knows while open).
local function Postable(bag, slot)
    if not auctionOpen or not (C_AuctionHouse and C_AuctionHouse.IsSellItemValid and ItemLocation) then return true end
    local ok, valid = pcall(C_AuctionHouse.IsSellItemValid, ItemLocation:CreateFromBagAndSlot(bag, slot), false)
    return not ok or valid ~= false
end

local function Money(c) return GetCoinTextureString and GetCoinTextureString(c) or (tostring(math.floor(c / 10000)) .. "g") end

-- TradeSkillMaster's public API (TSM_API): market value per item, from the TSM desktop app's data.
-- Returns nil when TSM isn't loaded or has no price for the item.
local TSM_PRICE = "first(dbmarket, dbregionmarketavg)"
local function TSMLoaded() return TSM_API and TSM_API.GetCustomPriceValue and TSM_API.ToItemString and true or false end
local function TSMPrice(priceString, link)
    if not TSMLoaded() then return nil end
    local ok, itemString = pcall(TSM_API.ToItemString, link)
    if not ok or not itemString then return nil end
    local ok2, v = pcall(TSM_API.GetCustomPriceValue, priceString, itemString)
    v = ok2 and tonumber(v)
    return v and v > 0 and v or nil
end

-- Auctionator's public API (Auctionator.API.v1): prices from your own scans, how many days
-- old they are (nil past 21 days), and what disenchanting would bring.
local AUCTIONATOR_ID = "TippWorks-Bags"
local function AuctionatorAPI(fn, link)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    local f = api and api[fn]
    if not f then return nil end
    local ok, v = pcall(f, AUCTIONATOR_ID, link)
    v = ok and tonumber(v)
    return v
end

-- What the Auction House addons know about an item: market (per item), where it came from,
-- the age in days (Auctionator only) and the disenchant value. TSM wins when both know.
local function Prices(link)
    local p = {}
    p.market = TSMPrice(TSM_PRICE, link)
    if p.market then p.source = "TSM"
    else
        p.market = AuctionatorAPI("GetAuctionPriceByItemLink", link)
        if p.market and p.market > 0 then
            p.source = "Auctionator"
            p.age = AuctionatorAPI("GetAuctionAgeByItemLink", link)
        else p.market = nil end
    end
    p.de = TSMPrice("destroy", link) or AuctionatorAPI("GetDisenchantPriceByItemLink", link)
    if p.de and p.de <= 0 then p.de = nil end
    return p
end

local function PriceNote(p)
    local s = p.source
    if p.source == "Auctionator" then
        s = s .. (p.age and (p.age == 0 and ", today" or (", %d day%s old"):format(p.age, p.age == 1 and "" or "s")) or ", 3+ weeks old")
    end
    return s
end
-- Worth keeping for the Auction House: at least this many times the vendor price, and at least 1 gold.
local VALUE_FACTOR, VALUE_MIN = 3, 10000

-- "Warbound until equipped" items report neither isBound nor a warbound bind type, so ask the
-- item itself, then fall back to the binding line on its tooltip. Cached per item link.
local NO_TRADE_LINES
local untradeableCache = {}
local function WarboundOrBound(bag, slot, link)
    if untradeableCache[link] ~= nil then return untradeableCache[link] end
    local result = false
    if ItemLocation then
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        for _, fn in ipairs({ "IsItemBindToAccountUntilEquip", "IsBoundToAccountUntilEquip" }) do
            if C_Item[fn] then
                local ok, v = pcall(C_Item[fn], loc)
                if ok and v == true then result = true end
            end
        end
    end
    if not result and C_TooltipInfo and C_TooltipInfo.GetBagItem then
        if not NO_TRADE_LINES then
            NO_TRADE_LINES = {}
            for _, g in ipairs({ "ITEM_ACCOUNTBOUND_UNTIL_EQUIP", "ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP", "ITEM_ACCOUNTBOUND",
                "ITEM_BNETACCOUNTBOUND", "ITEM_BIND_TO_ACCOUNT", "ITEM_BIND_TO_BNETACCOUNT" }) do
                if type(_G[g]) == "string" then NO_TRADE_LINES[_G[g]] = true end
            end
        end
        local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
        if ok and type(data) == "table" and type(data.lines) == "table" then
            for _, line in ipairs(data.lines) do
                local t = line.leftText
                if type(t) == "string" and not (issecretvalue and issecretvalue(t)) and NO_TRADE_LINES[t] then
                    result = true
                    break
                end
            end
        end
    end
    untradeableCache[link] = result
    return result
end

-- Containers: your bags, and (while the bank is open) the bank and warband bank tabs.
local function BagContainers()
    local t = {}
    for bag = 0, (NUM_TOTAL_BAG_FRAMES or NUM_BAG_SLOTS or 4) do t[#t + 1] = bag end
    return t
end
local function BankContainers()
    local seen, t = {}, {}
    for key, id in pairs(Enum and Enum.BagIndex or {}) do
        if type(id) == "number" and not seen[id] and (key == "Bank" or key == "Reagentbank" or key:find("^BankBag_")
            or key:find("^CharacterBankTab_") or key:find("^AccountBankTab_")) then
            seen[id] = true
            t[#t + 1] = id
        end
    end
    table.sort(t)
    return t
end

-- Returns { sell = {...}, delete = {...}, kept = {...}, auction = {...} }; each entry is
-- { bag, slot, itemID, link, name, count, price, why }. bank = true scans the bank instead of the bags.
local function Scan(bank)
    local out = { sell = {}, delete = {}, kept = {}, auction = {}, decor = {} }
    local _, class = UnitClass("player")
    local myArmor = ARMOR_TYPE[class or ""]
    for _, bag in ipairs(bank and BankContainers() or BagContainers()) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and not info.isLocked then
                local link = info.hyperlink
                local name, _, quality, _, _, _, _, _, equipLoc, _, price, classID, subclassID, bindType = C_Item.GetItemInfo(link)
                -- Tradeable = not bound to you and not warbound/account-bound (the bag API calls those unbound).
                local tradeable = info and not info.isBound and not NO_TRADE_BIND[bindType or 0]
                    and not (quality and quality >= 1 and WarboundOrBound(bag, slot, link))
                local species = tonumber(link:match("|Hbattlepet:(%d+)"))
                if species then
                    -- A caged battle pet: always tradeable, so it's an Auction tab item.
                    local hideKey = "pet:" .. species
                    if not db.noAuction[hideKey] and Postable(bag, slot) then
                        local have, limit = PetCount(species)
                        local prices = Prices(link)
                        out.auction[#out.auction + 1] = { bag = bag, slot = slot, itemID = info.itemID, link = link,
                            name = link:match("%[(.-)%]") or "battle pet", count = 1, price = 0, quality = info.quality or 1,
                            hideKey = hideKey, why = "caged pet" .. PetNote(have, limit),
                            market = prices.market, priceNote = prices.market and PriceNote(prices) }
                    end
                elseif name and Opt("decor") and IsDecor(info.itemID, classID) then
                    -- Housing decor goes to the Decor tab: one click adds it to your housing storage.
                    if not db.keep[info.itemID] then
                        out.decor[#out.decor + 1] = { bag = bag, slot = slot, itemID = info.itemID, link = link, name = name,
                            count = info.stackCount or 1, price = 0, why = "housing decor" }
                    end
                elseif name then
                    local e = { bag = bag, slot = slot, itemID = info.itemID, link = link, name = name,
                        count = info.stackCount or 1, price = (price or 0) * (info.stackCount or 1) }
                    local gear = classID == ARMOR_CLASS or classID == WEAPON_CLASS
                    -- Why it could go (first rule that matches).
                    local why
                    if quality == 0 and Opt("junk") then
                        why = "junk"
                    end
                    if not why and gear and equipLoc and equipLoc ~= "" and Opt("lowLevel") then
                        local lvl, worn = ItemLevel(link), EquippedLevel(equipLoc)
                        if lvl and worn and lvl <= worn - Opt("ilvlGap") then
                            why = ("item level %d (you wear %d)"):format(lvl, worn)
                        end
                    end
                    if not why and classID == ARMOR_CLASS and TYPED_SLOTS[equipLoc] and Opt("wrongArmor")
                        and myArmor and subclassID and subclassID >= 1 and subclassID <= 4 and subclassID ~= myArmor then
                        why = ARMOR_NAME[subclassID] .. " - you wear " .. ARMOR_NAME[myArmor]
                    end
                    if not why and Opt("quest") then
                        local q = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
                        if q and q.questID and not q.isActive and C_QuestLog.IsQuestFlaggedCompleted(q.questID) then
                            why = "quest already done"
                        end
                    end
                    local petHave, petLimit
                    -- Any miscellaneous item can teach a pet (older ones aren't always filed as Companion Pets).
                    if classID == 15 then petHave, petLimit = PetCount(PetSpecies(info.itemID)) end
                    if not why and Opt("pets") and petHave and petLimit > 0 and petHave >= petLimit then
                        why = ("pet - you have %d/%d"):format(petHave, petLimit)
                    end
                    local known = not why and not gear and Opt("known") and KnownKind(info.itemID)
                    if known then why = known .. " - you already know it" end
                    -- Why it must stay (wins over every rule).
                    local keep
                    local prices = quality and quality >= 1 and Prices(link) or {}
                    local market = tradeable and prices.market or nil
                    if why then
                        if db.keep[info.itemID] then keep = "you keep it"
                        elseif quality and quality >= 5 then keep = "legendary or better"
                        elseif C_Container.GetContainerItemEquipmentSetInfo and C_Container.GetContainerItemEquipmentSetInfo(bag, slot) then
                            keep = "in an equipment set"
                        elseif (petHave or known) and tradeable then
                            keep = "could go on the Auction House"
                        elseif gear and Opt("protectTransmog") and UncollectedAppearance(link) then
                            keep = "appearance not collected"
                        elseif gear and Opt("protectTradeable") and tradeable and quality and quality >= 3 then
                            keep = "not bound - could go on the Auction House"
                        elseif market and Opt("protectValue") and market >= VALUE_MIN and market >= VALUE_FACTOR * (price or 0) then
                            keep = "worth " .. Money(market) .. " on the Auction House (" .. PriceNote(prices) .. ")"
                        end
                    end
                    if why and keep then
                        e.why = why .. "  |cff888888(kept: " .. keep .. ")|r"
                        out.kept[#out.kept + 1] = e
                    elseif why and (info.hasNoValue or (price or 0) == 0) then
                        e.why = why
                        if Opt("offerDelete") then out.delete[#out.delete + 1] = e end
                    elseif why then
                        e.why = why
                        -- Worth more as enchanting materials? Say so (EasyDisenchant can do it).
                        if gear and prices.de and prices.de > (price or 0) then
                            e.why = why .. "  |cffa335ee(disenchant ~" .. Money(prices.de) .. ")|r"
                        end
                        out.sell[#out.sell + 1] = e
                    end
                    -- Could go on the Auction House (anything not headed for the vendor).
                    local kind = (not why or keep) and tradeable and quality and quality >= 1
                        and not db.noAuction[info.itemID]
                        and ((petHave and "pet") or known or AuctionKind(classID, subclassID, quality) or (keep and market and "worth more at auction"))
                    if kind and Postable(bag, slot) then
                        local a = { bag = bag, slot = slot, itemID = info.itemID, link = link, name = name,
                            count = e.count, price = e.price, quality = quality, why = kind,
                            market = market and market * e.count, priceNote = market and PriceNote(prices),
                            de = gear and prices.de }
                        if kind == "pet" then a.why = kind .. PetNote(petHave, petLimit) end
                        if known then a.why = known .. " - you already know it" end
                        if kind == "unbound gear" then
                            a.ilvl = ItemLevel(link)
                            if a.ilvl then a.why = kind .. " " .. a.ilvl end
                            if Opt("protectTransmog") and UncollectedAppearance(link) then
                                a.why = a.why .. " - |cffff9933appearance not collected|r"
                            end
                        end
                        out.auction[#out.auction + 1] = a
                    end
                end
            end
        end
    end
    -- Junk first, then the most valuable: if the 12-item cap bites, the rest waits for the next visit.
    table.sort(out.sell, function(a, b)
        if (a.why == "junk") ~= (b.why == "junk") then return a.why == "junk" end
        return a.price > b.price
    end)
    -- Most valuable first when TSM knows the price; otherwise by quality and item level.
    table.sort(out.auction, function(a, b)
        if (a.market or 0) ~= (b.market or 0) then return (a.market or 0) > (b.market or 0) end
        if a.quality ~= b.quality then return a.quality > b.quality end
        if (a.ilvl or 0) ~= (b.ilvl or 0) then return (a.ilvl or 0) > (b.ilvl or 0) end
        return a.name < b.name
    end)
    return out
end
ns.Scan = Scan -- for tests

---------------------------------------------------------------------------
-- Selling and deleting
---------------------------------------------------------------------------
local selling = false
local merchantOpen = false

local function SameItem(e)
    local info = C_Container.GetContainerItemInfo(e.bag, e.slot)
    return info and info.itemID == e.itemID and not info.isLocked
end

local function Sell()
    if selling then return end
    if not merchantOpen then Print("open a vendor first.") return end
    local list = Scan().sell
    if #list == 0 then Print("nothing to sell.") return end
    selling = true
    local i, sold, capped, total = 0, 0, 0, 0
    local function Next()
        i = i + 1
        local e = list[i]
        -- Greys don't count against the cap: nobody buys junk back.
        if not e or not merchantOpen or (capped >= MAX_SELL and e.why ~= "junk") then
            selling = false
            if sold > 0 then Print(("sold %d item%s for %s."):format(sold, sold == 1 and "" or "s", Money(total))) end
            if e and merchantOpen then Print("more to sell - the vendor's buyback holds 12, so the rest waits for the next visit.") end
            ns.Refresh()
            return
        end
        if SameItem(e) then
            C_Container.UseContainerItem(e.bag, e.slot)
            sold, total = sold + 1, total + e.price
            if e.why ~= "junk" then capped = capped + 1 end
            TW.Log("BAGS", "sold %s x%d (%s) for %d copper", e.name, e.count, e.why, e.price)
        end
        C_Timer.After(SELL_DELAY, Next)
    end
    Next()
end

StaticPopupDialogs["TIPPWORKS_BAGS_DELETE"] = {
    text = POPUP_HEADER .. "Delete %s?\n|cff888888(%s - it can't be sold)|r",
    button1 = DELETE or "Delete", button2 = CANCEL or "Cancel",
    OnAccept = function(_, e)
        if not SameItem(e) then Print("that item moved - not deleted.") return end
        ClearCursor()
        C_Container.PickupContainerItem(e.bag, e.slot)
        local _, id = GetCursorInfo()
        if id ~= e.itemID then ClearCursor(); Print("couldn't pick it up - not deleted.") return end
        DeleteCursorItem()
        TW.Log("BAGS", "deleted %s x%d (%s)", e.name, e.count, e.why)
        Print("deleted " .. e.link .. ".")
        C_Timer.After(0.3, ns.Refresh)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Auction House: load items into Blizzard's Post screen, one after another
---------------------------------------------------------------------------
local posting -- the item last loaded into the Post screen

local function StillThere(e)
    local info = C_Container.GetContainerItemInfo(e.bag, e.slot)
    return info and info.itemID == e.itemID
end

local function LoadForPost(e)
    if not auctionOpen then Print("open the Auction House first.") return end
    if not SameItem(e) then ns.Refresh() return end
    -- TSM replaces Blizzard's Auction House window (unless you switch back to it).
    if TSMLoaded() and not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        Print("TSM is running the Auction House: drag " .. e.link .. " into your TSM group and post it there.")
        ns.Refresh()
        return
    end
    if not (AuctionHouseFrame and AuctionHouseFrame.SetPostItem and ItemLocation) then
        Print("couldn't reach the Post screen - right-click the item in your bags instead.")
        return
    end
    local ok, err = pcall(AuctionHouseFrame.SetPostItem, AuctionHouseFrame, ItemLocation:CreateFromBagAndSlot(e.bag, e.slot))
    if not ok then
        TW.Log("ERROR", "bags post: %s", tostring(err))
        Print("couldn't load it - right-click the item in your bags instead.")
        return
    end
    posting = e
    C_Timer.After(0.2, ns.Refresh)
end

-- The first item on the Auction tab (the one in the Post screen is locked, so it's not listed).
local function LoadNext()
    local e = Scan().auction[1]
    if e then LoadForPost(e)
    else posting = nil; Print("nothing left to post."); ns.Refresh() end
end

-- After a post the item leaves its bag slot: load the next one.
local function CheckPosted()
    if not posting or not auctionOpen or StillThere(posting) then return end
    TW.Log("BAGS", "posted %s x%d", posting.name, posting.count)
    posting = nil
    if Opt("autoNext") then C_Timer.After(0.5, function() TW.Guard("bags next", LoadNext) end) end
end

local function ToggleHide(e)
    db.noAuction[e.hideKey or e.itemID] = e.name
    Print(e.link .. " won't be listed on the Auction tab (/tw bags unhide to bring it back).")
    ns.Refresh()
end

local function AskDelete(e)
    StaticPopup_Show("TIPPWORKS_BAGS_DELETE", e.link, e.why, e)
end

---------------------------------------------------------------------------
-- Bank: what in the bank and warband bank should go. Vendors only buy from
-- your bags, so those move to your bags; what can't be sold is deleted there.
---------------------------------------------------------------------------
local bankOpen, moving = false, false

local function BankList()
    local scan = Scan(true)
    local list = {}
    for _, e in ipairs(scan.sell) do e.action = "move"; list[#list + 1] = e end
    for _, e in ipairs(scan.delete) do e.action = "delete"; list[#list + 1] = e end
    for _, e in ipairs(scan.decor) do e.action = "decor"; list[#list + 1] = e end
    return list
end

-- Free slots in your regular bags (not the reagent bag).
local function FreeBagSlots()
    local n = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        if (family or 0) == 0 then n = n + (free or 0) end
    end
    return n
end

-- With the bank open, using a bank item moves it to your bags.
local function MoveToBags(e)
    if not bankOpen then Print("open your bank first.") return false end
    if not SameItem(e) then return false end
    if FreeBagSlots() == 0 then Print("your bags are full.") return false end
    C_Container.UseContainerItem(e.bag, e.slot)
    TW.Log("BAGS", "moved %s x%d from the bank (%s)", e.name, e.count, e.why)
    return true
end

-- WoW only deletes from your bags: move the item out of the bank first, then ask.
local function MoveThenDelete(e)
    local before = {}
    for _, bag in ipairs(BagContainers()) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == e.itemID then before[bag .. ":" .. slot] = true end
        end
    end
    if not MoveToBags(e) then return end
    C_Timer.After(0.5, function() TW.Guard("bags delete from bank", function()
        for _, bag in ipairs(BagContainers()) do
            for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID == e.itemID and not before[bag .. ":" .. slot] then
                    AskDelete({ bag = bag, slot = slot, itemID = e.itemID, link = e.link, name = e.name,
                        count = info.stackCount or e.count, why = e.why })
                    return
                end
            end
        end
        Print(e.link .. " is in your bags now - delete it from the Delete tab.")
        ns.Refresh()
    end) end)
end

local function MoveAll()
    if moving then return end
    local list = {}
    for _, e in ipairs(BankList()) do list[#list + 1] = e end
    if #list == 0 then Print("nothing in the bank to move.") return end
    moving = true
    local i, moved = 0, 0
    local function Next()
        i = i + 1
        local e = list[i]
        if not e or not bankOpen or FreeBagSlots() == 0 then
            moving = false
            if moved > 0 then
                Print(("moved %d item%s to your bags: sell at the next vendor; what can't be sold is on the Delete tab.")
                    :format(moved, moved == 1 and "" or "s"))
            end
            if e and bankOpen then Print("your bags are full - sell, then move the rest.") end
            ns.Refresh()
            return
        end
        if MoveToBags(e) then moved = moved + 1 end
        C_Timer.After(SELL_DELAY, Next)
    end
    Next()
end

local function ToggleKeep(e)
    if db.keep[e.itemID] then
        db.keep[e.itemID] = nil
        Print(e.link .. " can be sold again.")
    else
        db.keep[e.itemID] = e.name
        Print(e.link .. " will be kept.")
    end
    ns.Refresh()
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
-- Using an item needs a secure button: each Decor row gets one on top. They live on UIParent and
-- are only placed and shown out of combat, so the window itself can still move and hide in combat.
local secureButtons, secureOf = {}, {}
local function HideSecure()
    if InCombatLockdown() then return end
    for _, s in ipairs(secureButtons) do s:Hide(); s:ClearAllPoints() end
end

local function SecureFor(row)
    if secureOf[row] then return secureOf[row] end
    local s = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    s:RegisterForClicks("AnyUp", "AnyDown")
    s:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    s:SetAttribute("type1", "item")
    s:SetScript("OnEnter", function() local f = row:GetScript("OnEnter"); if f then f(row) end end)
    s:SetScript("OnLeave", GameTooltip_Hide)
    s:SetScript("PostClick", function(_, btn, down)
        if (down and true or false) ~= GetCVarBool("ActionButtonUseKeyDown") then return end
        local e = row.entry
        if not e then return end
        if btn == "RightButton" then ToggleKeep(e) return end
        TW.Log("BAGS", "added %s to housing storage", e.name)
        C_Timer.After(0.5, ns.Refresh)
    end)
    s:Hide()
    secureOf[row] = s
    secureButtons[#secureButtons + 1] = s
    return s
end

local function PlaceSecure(row, e)
    if InCombatLockdown() then return end
    local s = SecureFor(row)
    s:SetAttribute("item", e.bag .. " " .. e.slot)
    s:ClearAllPoints()
    s:SetAllPoints(row)
    s:SetFrameStrata(win:GetFrameStrata())
    s:SetFrameLevel(row:GetFrameLevel() + 5)
    s:Show()
end

local function Row(i)
    local b = CreateFrame("Button", nil, win)
    b:SetSize(WIDTH - 20, ROW_H)
    b:SetPoint("TOPLEFT", 10, win.top - (i - 1) * ROW_H)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.left = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.left:SetPoint("LEFT", 4, 0)
    b.left:SetWidth(WIDTH - 110)
    b.left:SetJustifyH("LEFT")
    b.left:SetWordWrap(false)
    b.right = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.right:SetPoint("RIGHT", -4, 0)
    b:SetScript("OnClick", function(self, btn)
        local e = self.entry
        if not e then return end
        if db.tab == "auction" then
            if btn == "RightButton" then ToggleHide(e) else LoadForPost(e) end
        elseif db.tab == "decor" then
            if btn == "RightButton" then ToggleKeep(e) else Print("after combat: click it again to add it to your housing storage.") end
        elseif db.tab == "bank" and btn ~= "RightButton" then
            if e.action == "delete" then MoveThenDelete(e)
            elseif MoveToBags(e) then C_Timer.After(0.3, ns.Refresh) end
        elseif btn == "RightButton" or db.tab == "kept" then ToggleKeep(e)
        elseif db.tab == "delete" then AskDelete(e)
        else ToggleKeep(e) end
    end)
    b:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetBagItem, GameTooltip, e.bag, e.slot)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("TippWorks: " .. e.why, 1, 0.82, 0, true)
        if e.market then GameTooltip:AddLine("Auction price: " .. Money(e.market) .. " (" .. e.priceNote .. ")", 1, 1, 1) end
        if e.de then GameTooltip:AddLine("Disenchant: ~" .. Money(e.de), 0.64, 0.21, 0.93) end
        GameTooltip:AddLine(db.tab == "decor" and "Click: add it to your housing storage  |  Right-click: keep it in your bags"
            or db.tab == "bank" and (e.action == "delete" and "Click: move to your bags and delete (asks first)  |  Right-click: keep it"
                or e.action == "decor" and "Click: move to your bags (then add it from the Decor tab)  |  Right-click: keep it"
                or "Click: move to your bags (sell at a vendor)  |  Right-click: keep it")
            or db.tab == "auction" and "Click: load it into Post  |  Right-click: don't list it"
            or db.tab == "delete" and "Left-click: delete (asks first)  |  Right-click: keep it"
            or db.tab == "kept" and "Click: let it be sold again" or "Click: keep it (never sell)", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = b
    return b
end

function ns.Refresh()
    if not win or not win:IsShown() then return end
    local list
    if db.tab == "bank" then list = bankOpen and BankList() or {}
    else
        local scan = Scan()
        list = scan[db.tab] or scan.sell
    end
    local total = 0
    for _, e in ipairs(list) do total = total + e.price end
    local n = 0
    for i, e in ipairs(list) do
        n = i
        local b = rows[i] or Row(i)
        b.entry = e
        b.left:SetText(e.link .. (e.count > 1 and (" x" .. e.count) or "") .. "  |cff888888" .. e.why .. "|r")
        if db.tab == "auction" then
            local loaded = posting and posting.bag == e.bag and posting.slot == e.slot
            b.right:SetText(loaded and "|cff33ff33in Post|r" or e.market and Money(e.market) or "")
        elseif db.tab == "bank" then
            b.right:SetText(e.action == "delete" and "|cffff6060to bags, delete|r"
                or e.action == "decor" and "|cff33ff99to bags|r, decor" or ("|cff33ff99to bags|r " .. Money(e.price)))
        else
            b.right:SetText(db.tab == "delete" and "|cffff6060delete|r" or (e.price > 0 and Money(e.price) or ""))
        end
        b:Show()
        if db.tab == "decor" then PlaceSecure(b, e)
        elseif secureOf[b] and not InCombatLockdown() then secureOf[b]:Hide(); secureOf[b]:ClearAllPoints() end
    end
    for i = n + 1, #rows do
        rows[i]:Hide(); rows[i].entry = nil
        local s = secureOf[rows[i]]
        if s and not InCombatLockdown() then s:Hide(); s:ClearAllPoints() end
    end
    local footer
    local tsmUI = TSMLoaded() and not (AuctionHouseFrame and AuctionHouseFrame:IsShown())
    win.post:SetShown(db.tab == "auction" and auctionOpen and n > 0 and not tsmUI)
    local toMove = 0
    if db.tab == "bank" then for _, e in ipairs(list) do if e.action == "move" then toMove = toMove + 1 end end end
    win.move:SetShown(db.tab == "bank" and bankOpen and n > 0)
    if db.tab == "decor" then
        win.sell:Hide()
        footer = n == 0 and "|cff888888No housing decor in your bags.|r"
            or InCombatLockdown() and "|cff888888After combat: click one to add it to your housing storage.|r"
            or "|cff888888Click one to add it to your housing storage.|r"
    elseif db.tab == "bank" then
        win.sell:Hide()
        footer = not bankOpen and "|cff888888Open your bank or warband bank to check it.|r"
            or n == 0 and "|cff888888Nothing in the bank to sell or delete.|r"
            or ("|cff888888%d to sell, %d to delete or add as decor - all go to your bags first.|r")
                :format(toMove, n - toMove)
    elseif db.tab == "auction" then
        win.sell:Hide()
        footer = n == 0 and "|cff888888Nothing unbound to post.|r"
            or not auctionOpen and "|cff888888Open the Auction House to post these.|r"
            or tsmUI and "|cff888888Drag these into your TSM group, then Post Scan.|r"
            or (Opt("autoNext") and "|cff888888Click one, then Post. The next loads by itself.|r"
                or "|cff888888Click one to load it into Post.|r")
    elseif db.tab == "sell" then
        footer = n == 0 and "|cff888888Nothing to sell with your current rules (/tw bags rules).|r"
            or ("%d item%s, %s%s"):format(n, n == 1 and "" or "s", Money(total),
                merchantOpen and "" or "  |cff888888- open a vendor to sell|r")
        win.sell:SetShown(merchantOpen and n > 0)
    else
        win.sell:Hide()
        footer = db.tab == "delete"
            and (n == 0 and "|cff888888Nothing to delete.|r" or "|cff888888Can't be sold. Click one to delete it (asks first).|r")
            or (n == 0 and "|cff888888Nothing held back.|r" or "|cff888888Matched a rule but held back. Click to change.|r")
    end
    win.footer:SetText(footer)
    win:SetHeight(-win.top + math.max(n, 1) * ROW_H + 40 + ((win.sell:IsShown() or win.post:IsShown() or win.move:IsShown()) and 24 or 0))
end

local function CreateWindow()
    win = TW.CreateWindow({ name = "TippWorksBagsFrame", title = "Bag Manager", version = ns.VERSION,
        width = WIDTH, db = db, onTab = function() ns.Refresh() end, tabs = {
            { key = "sell", label = "Sell", title = "Bag Manager - sell" },
            { key = "delete", label = "Delete", title = "Bag Manager - can't sell" },
            { key = "kept", label = "Kept", title = "Bag Manager - held back" },
            { key = "auction", label = "Auction", title = "Bag Manager - Auction House" },
            { key = "bank", label = "Bank", title = "Bag Manager - bank" },
            { key = "decor", label = "Decor", title = "Bag Manager - housing decor" },
        } })
    win.footer = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.footer:SetPoint("BOTTOMLEFT", 12, 10)
    win.footer:SetWidth(WIDTH - 120)
    win.footer:SetJustifyH("LEFT")
    win.sell = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.sell:SetSize(90, 22)
    win.sell:SetPoint("BOTTOMRIGHT", -10, 8)
    win.sell:SetText("Sell")
    win.sell:SetScript("OnClick", Sell)
    win.post = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.post:SetSize(90, 22)
    win.post:SetPoint("BOTTOMRIGHT", -10, 8)
    win.post:SetText("Load next")
    win.post:SetScript("OnClick", function() TW.Guard("bags next", LoadNext) end)
    win.post:Hide()
    win.move = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.move:SetSize(90, 22)
    win.move:SetPoint("BOTTOMRIGHT", -10, 8)
    win.move:SetText("Move all")
    win.move:SetScript("OnClick", function() TW.Guard("bags move", MoveAll) end)
    win.move:Hide()
    win:SetScript("OnShow", function() ns.Refresh() end)
    win:HookScript("OnHide", HideSecure)
    win:SelectTab(win.tabs[db.tab] and db.tab or "sell")
end

---------------------------------------------------------------------------
-- TippWorks registration, /tw bags, settings, saved data
---------------------------------------------------------------------------
local function Toggle() if win then win:Toggle() end end

local RULES = {
    { "junk", "junk", "Sell junk (grey items)" },
    { "low", "lowLevel", "Sell gear well below the item level you wear" },
    { "armor", "wrongArmor", "Sell armor that isn't your type (cloth, leather, mail, plate)" },
    { "quest", "quest", "Sell items for quests you've already done" },
    { "pets", "pets", "Sell pets you can't learn any more (bound ones; tradeable ones go to the Auction tab)" },
    { "known", "known", "Sell mounts and toys you already know (bound ones; tradeable ones go to the Auction tab)" },
    { "housing", "decor", "List housing decor to add to your housing storage (Decor tab; from the bank too)" },
    { "delete", "offerDelete", "Offer to delete matching items that can't be sold" },
    { "transmog", "protectTransmog", "Keep gear whose appearance you haven't collected" },
    { "tradeable", "protectTradeable", "Keep unbound blue and epic gear (Auction House)" },
    { "value", "protectValue", "Keep items worth 3x their vendor price (1g+) on the Auction House (TSM or Auctionator prices)" },
    { "auto", "autoSell", "Sell at the vendor without asking" },
    { "next", "autoNext", "Auction House: after you post, load the next item" },
    { "mats", "auctionMats", "Auction tab: list crafting materials too" },
}

local function ShowRules()
    for _, r in ipairs(RULES) do
        Print(("  %s %s  |cff888888(/tw bags %s)|r"):format(Opt(r[2]) and "|cff33ff33on |r" or "|cff888888off|r", r[3], r[1]))
    end
    Print(("  item-level gap: %d  |cff888888(/tw bags gap <number>)|r"):format(Opt("ilvlGap")))
end

local module
local function Command(rest)
    local sub, arg = (rest or ""):match("^(%S*)%s*(.-)$")
    sub = (sub or ""):lower()
    if sub == "" or sub == "show" then Toggle() return end
    if sub == "sell" then Sell() return end
    if sub == "rules" then ShowRules() return end
    if sub == "auction" or sub == "ah" then db.tab = "auction"; win:SelectTab("auction"); win:Show() return end
    if sub == "bank" then db.tab = "bank"; win:SelectTab("bank"); win:Show() return end
    if sub == "decor" then db.tab = "decor"; win:SelectTab("decor"); win:Show() return end
    if sub == "why" then
        -- Everything Bags sees about one item (also in /tw log), to explain where it's listed or why it isn't.
        local id = tonumber(arg:match("item:(%d+)") or arg)
        if not id then Print("usage: /tw bags why <shift-click an item>") return end
        local function Out(fmt, ...) local s = fmt:format(...); Print(s); TW.Log("BAGS", "why: %s", s) end
        local found
        for bag = 0, (NUM_TOTAL_BAG_FRAMES or NUM_BAG_SLOTS or 4) do
            for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if not found and info and info.itemID == id then found = { bag = bag, slot = slot, info = info } end
            end
        end
        if not found then Out("item %d isn't in your bags.", id) return end
        local info = found.info
        local name, _, quality, _, _, _, _, _, equipLoc, _, price, classID, subclassID, bindType = C_Item.GetItemInfo(info.hyperlink)
        Out("%s: quality %s, class %s/%s, bind type %s, bound to you %s, vendor price %s%s, locked %s",
            tostring(name), tostring(quality), tostring(classID), tostring(subclassID), tostring(bindType),
            tostring(info.isBound), tostring(price), info.hasNoValue and " (no value)" or "", tostring(info.isLocked))
        local species = PetSpecies(id)
        if species then
            local have, limit = PetCount(species)
            Out("teaches pet species %d: you have %s of %s", species, tostring(have), tostring(limit))
        end
        local scan = Scan()
        local where
        for _, list in ipairs({ "sell", "delete", "kept", "auction" }) do
            for _, e in ipairs(scan[list]) do
                if not where and e.bag == found.bag and e.slot == found.slot then where = list .. " tab: " .. e.why end
            end
        end
        Out("listed on: %s", where or ("nothing" .. (Opt("offerDelete") and "" or " (offering to delete is off)")))
        return
    end
    if sub == "prices" then
        -- What TSM and Auctionator actually return for the first items on the Auction tab (also in /tw log).
        local function Out(fmt, ...) local s = fmt:format(...); Print(s); TW.Log("BAGS", "prices: %s", s) end
        Out("TSM %s, Auctionator %s", TSMLoaded() and "loaded" or "not loaded",
            (Auctionator and Auctionator.API and Auctionator.API.v1) and "loaded" or "not loaded")
        local list = Scan().auction
        if #list == 0 then Out("nothing on the Auction tab to look up.") return end
        for i = 1, math.min(5, #list) do
            local e = list[i]
            local tsm = "-"
            if TSMLoaded() then
                local ok, s = pcall(TSM_API.ToItemString, e.link)
                local ok2, v, err = false, nil, nil
                if ok and s then ok2, v, err = pcall(TSM_API.GetCustomPriceValue, TSM_PRICE, s) end
                tsm = ("%s -> %s%s"):format(tostring(ok and s or "error: " .. tostring(s)),
                    tostring(ok2 and v or "error"), err and (" (" .. tostring(err) .. ")") or "")
            end
            Out("%s: TSM %s, Auctionator %s", e.name, tsm, tostring(AuctionatorAPI("GetAuctionPriceByItemLink", e.link)))
        end
        return
    end
    if sub == "unhide" then
        wipe(db.noAuction)
        Print("every item is back on the Auction tab.")
        ns.Refresh()
        return
    end
    if sub == "gap" then
        local n = tonumber(arg)
        if not n or n < 1 then Print("usage: /tw bags gap 20") return end
        db.ilvlGap = math.floor(n)
        Print(("gear %d or more item levels below what you wear counts as low."):format(db.ilvlGap))
        ns.Refresh()
        return
    end
    if sub == "keep" then
        local id = tonumber(arg:match("item:(%d+)") or arg)
        if not id then Print("usage: /tw bags keep <shift-click an item>") return end
        if db.keep[id] then db.keep[id] = nil; Print("item can be sold again.")
        else db.keep[id] = arg:match("%[(.-)%]") or tostring(id); Print("item will be kept.") end
        ns.Refresh()
        return
    end
    for _, r in ipairs(RULES) do
        if sub == r[1] then
            db[r[2]] = not Opt(r[2])
            Print(r[3] .. ": " .. (db[r[2]] and "on" or "off"))
            ns.Refresh()
            return
        end
    end
    TW.ModuleHelp(module)
end

local function Summary(tt)
    if not db then return end
    local scan = Scan()
    local total = 0
    for _, e in ipairs(scan.sell) do total = total + e.price end
    tt:AddLine(("Bags: %d to sell (%s), %d to delete"):format(#scan.sell, Money(total), #scan.delete), 1, 1, 1)
end

module = TW.Register({
    key = "bags", aliases = { "bag", "junk" },
    name = "Bag Manager", addon = ADDON, version = ns.VERSION,
    command = Command, toggle = Toggle, summary = Summary,
    help = {
        { "", "show/hide the Bag Manager (opens by itself at a vendor when there's something to sell)" },
        { "sell", "sell everything on the Sell list (at a vendor)" },
        { "rules", "show which rules are on" },
        { "junk | low | armor | quest | pets | known", "turn a selling rule on/off" },
        { "delete", "turn on/off offering to delete matching items that can't be sold" },
        { "transmog | tradeable | value", "turn a protection on/off (value = TSM or Auctionator price)" },
        { "auto", "turn on/off selling at the vendor without asking" },
        { "auction", "show the Auction tab (opens by itself at the Auction House)" },
        { "bank", "show the Bank tab: what in the bank to sell or delete (opens by itself at the bank)" },
        { "decor", "show the Decor tab: housing decor to add to your housing storage" },
        { "housing", "turn on/off listing housing decor" },
        { "next | mats", "Auction House: load the next item after a post / list materials too" },
        { "unhide", "bring back items you right-clicked off the Auction tab" },
        { "why <item>", "explain what Bags sees about an item and where it is listed (shift-click it in)" },
        { "prices", "show what TSM and Auctionator return for the first items on the Auction tab" },
        { "gap <number>", "how far below your item level counts as low (default 20)" },
        { "keep <item>", "never sell this item (shift-click it into the command); again to undo" },
    },
})

function TippWorksBags_OnAddonCompartmentClick() Toggle() end
function TippWorksBags_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff" .. TW.COLOR .. "Tippenhauer Works|r - Bag Manager")
    Summary(GameTooltip)
    GameTooltip:AddLine("Click: show/hide  |  /tw bags help", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end
function TippWorksBags_OnAddonCompartmentLeave() GameTooltip:Hide() end

local function AddSettings()
    if not TW.AddCheckbox then return end
    for _, r in ipairs(RULES) do
        TW.AddCheckbox("Bag Manager", "TW_BAGS_" .. r[2]:upper(), r[3], nil,
            function() return Opt(r[2]) and true or false end,
            function(v) db[r[2]] = v and true or false; ns.Refresh() end)
    end
end

-- Other addons that sell at the vendor: two sellers at once fight over the same items.
local OTHER_SELLERS = { "CrapAway", "Scrap", "Peddler", "AutoVendor", "Vendor", "SellJunk" }

StaticPopupDialogs["TIPPWORKS_BAGS_OTHER"] = {
    text = POPUP_HEADER .. "%s is also loaded, and it sells at the vendor too. Two addons selling at once can fight over the same items.\n\nDisable %s? (Your UI reloads.)",
    button1 = "Disable it", button2 = "Keep both",
    OnAccept = function(_, name)
        C_AddOns.DisableAddOn(name)
        TW.Log("BAGS", "disabled %s", name)
        ReloadUI()
    end,
    OnCancel = function(_, name, reason)
        if reason ~= "clicked" then return end
        db.allowOther[name] = true
        Print("ok - no more warnings about " .. name .. ".")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function CheckOtherSellers()
    if not (C_AddOns and C_AddOns.IsAddOnLoaded) then return end
    for _, name in ipairs(OTHER_SELLERS) do
        if Safe(C_AddOns.IsAddOnLoaded, name) and not db.allowOther[name] then
            TW.Log("BAGS", "%s is also loaded - it sells at the vendor too", name)
            Print(("|cffff6060warning:|r %s is also loaded and sells at the vendor too. Turn one of them off."):format(name))
            StaticPopup_Show("TIPPWORKS_BAGS_OTHER", name, name, name)
            return
        end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        TippWorksBagsDB = TippWorksBagsDB or {}
        db = TippWorksBagsDB
        db.keep = db.keep or {}
        db.noAuction = db.noAuction or {}
        db.allowOther = db.allowOther or {}
        db.tab = db.tab or "sell"
        TW.Log("INFO", "TippWorks-Bags v%s loaded", ns.VERSION)
        CreateWindow()
        AddSettings()
        self:RegisterEvent("MERCHANT_SHOW")
        self:RegisterEvent("MERCHANT_CLOSED")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        self:RegisterEvent("AUCTION_HOUSE_SHOW")
        self:RegisterEvent("AUCTION_HOUSE_CLOSED")
        self:RegisterEvent("PLAYER_LOGIN")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        -- The bank: the old events and the interaction manager (whichever this client has).
        for _, e in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
            "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
            pcall(self.RegisterEvent, self, e)
        end
        return
    end
    local P = Enum and Enum.PlayerInteractionType
    local isBank = event == "BANKFRAME_OPENED" or event == "BANKFRAME_CLOSED"
        or (P and (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
            and ((...) == P.Banker or (...) == P.AccountBanker or (...) == P.CharacterBanker))
    if isBank then
        local open = event == "BANKFRAME_OPENED" or event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
        if open == bankOpen then return end
        bankOpen = open
        if open then
            -- The bank's contents arrive a moment after it opens.
            C_Timer.After(0.5, function() TW.Guard("bags bank", function()
                if bankOpen and #BankList() > 0 then db.tab = "bank"; win:SelectTab("bank"); win:Show() end
            end) end)
        else
            if win:IsShown() and db.tab == "bank" then win:Hide() end
        end
        return
    end
    -- Combat: the secure Decor buttons are pulled off the window just before lockdown starts.
    if event == "PLAYER_REGEN_DISABLED" then HideSecure() return end
    if event == "PLAYER_REGEN_ENABLED" then TW.Guard("bags refresh", ns.Refresh) return end
    if event == "PLAYER_LOGIN" then
        C_Timer.After(5, function() TW.Guard("bags other sellers", CheckOtherSellers) end)
        return
    end
    if event == "MERCHANT_SHOW" then
        merchantOpen = true
        TW.Guard("bags merchant", function()
            local scan = Scan()
            if #scan.sell == 0 then return end
            if Opt("autoSell") then Sell()
            else db.tab = "sell"; win:SelectTab("sell"); win:Show() end
        end)
    elseif event == "MERCHANT_CLOSED" then
        merchantOpen = false
        if win:IsShown() and db.tab == "sell" then win:Hide() end
    elseif event == "AUCTION_HOUSE_SHOW" then
        auctionOpen = true
        TW.Guard("bags auction", function()
            if #Scan().auction == 0 then return end
            db.tab = "auction"; win:SelectTab("auction"); win:Show()
        end)
        -- TSM swaps in its own window right after this event: look again once it has.
        C_Timer.After(0.5, function() TW.Guard("bags refresh", ns.Refresh) end)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        auctionOpen, posting = false, nil
        if win:IsShown() and db.tab == "auction" then win:Hide() end
    elseif event == "BAG_UPDATE_DELAYED" and not selling then
        TW.Guard("bags posted", CheckPosted)
        TW.Guard("bags refresh", ns.Refresh)
    end
end)
