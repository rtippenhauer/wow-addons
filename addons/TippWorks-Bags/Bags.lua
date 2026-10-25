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
ns.VERSION = "1.1.0"
local Print = TW.Printer("Bags")
local Safe = TW.Safe

local MAX_SELL = 12 -- the vendor's buyback tab holds the last 12 items: keep every sale recoverable
local SELL_DELAY = 0.2

local db
local win, rows = nil, {}
local WIDTH, ROW_H = 380, 18

-- Defaults: junk and finished-quest items on; the gear rules are opt-in.
local DEFAULTS = {
    junk = true, lowLevel = false, wrongArmor = false, quest = true, offerDelete = true,
    protectTransmog = true, protectTradeable = true, autoSell = false, ilvlGap = 20,
    autoNext = true, auctionMats = false,
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

-- What can go on the Auction House besides unbound gear (item class -> label).
local AUCTION_KIND = { [3] = "gem", [8] = "enhancement", [9] = "recipe", [16] = "glyph", [19] = "profession gear" }
local function AuctionKind(classID, subclassID, quality)
    if classID == ARMOR_CLASS or classID == WEAPON_CLASS then return quality >= 2 and "unbound gear" or nil end
    if AUCTION_KIND[classID] then return AUCTION_KIND[classID] end
    if classID == 15 and subclassID == 2 then return "pet" end
    if classID == 15 and subclassID == 5 then return "mount" end
    if classID == 7 and Opt("auctionMats") then return "material" end
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

-- Returns { sell = {...}, delete = {...}, kept = {...}, auction = {...} }; each entry is
-- { bag, slot, itemID, link, name, count, price, why }.
local function Scan()
    local out = { sell = {}, delete = {}, kept = {}, auction = {} }
    local _, class = UnitClass("player")
    local myArmor = ARMOR_TYPE[class or ""]
    for bag = 0, (NUM_TOTAL_BAG_FRAMES or NUM_BAG_SLOTS or 4) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and not info.isLocked then
                local link = info.hyperlink
                local name, _, quality, _, _, _, _, _, equipLoc, _, price, classID, subclassID = C_Item.GetItemInfo(link)
                if name then
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
                    -- Why it must stay (wins over every rule).
                    local keep
                    if why then
                        if db.keep[info.itemID] then keep = "you keep it"
                        elseif quality and quality >= 5 then keep = "legendary or better"
                        elseif C_Container.GetContainerItemEquipmentSetInfo and C_Container.GetContainerItemEquipmentSetInfo(bag, slot) then
                            keep = "in an equipment set"
                        elseif gear and Opt("protectTransmog") and UncollectedAppearance(link) then
                            keep = "appearance not collected"
                        elseif gear and Opt("protectTradeable") and not info.isBound and quality and quality >= 3 then
                            keep = "not bound - could go on the Auction House"
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
                        out.sell[#out.sell + 1] = e
                    end
                    -- Could go on the Auction House (anything not headed for the vendor).
                    local kind = (not why or keep) and not info.isBound and quality and quality >= 1
                        and not db.noAuction[info.itemID] and AuctionKind(classID, subclassID, quality)
                    if kind and Postable(bag, slot) then
                        local a = { bag = bag, slot = slot, itemID = info.itemID, link = link, name = name,
                            count = e.count, price = e.price, quality = quality, why = kind }
                        if kind == "unbound gear" then
                            a.ilvl = ItemLevel(link)
                            if Opt("protectTransmog") and UncollectedAppearance(link) then
                                a.why = kind .. " - |cffff9933appearance not collected|r"
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
    table.sort(out.auction, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        if (a.ilvl or 0) ~= (b.ilvl or 0) then return (a.ilvl or 0) > (b.ilvl or 0) end
        return a.name < b.name
    end)
    return out
end

local function Money(c) return GetCoinTextureString and GetCoinTextureString(c) or (tostring(math.floor(c / 10000)) .. "g") end

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
    text = "Delete %s?\n|cff888888(%s - it can't be sold)|r",
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
    db.noAuction[e.itemID] = e.name
    Print(e.link .. " won't be listed on the Auction tab (/tw bags unhide to bring it back).")
    ns.Refresh()
end

local function AskDelete(e)
    StaticPopup_Show("TIPPWORKS_BAGS_DELETE", e.link, e.why, e)
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
        elseif btn == "RightButton" or db.tab == "kept" then ToggleKeep(e)
        elseif db.tab == "delete" then AskDelete(e)
        else ToggleKeep(e) end
    end)
    b:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(e.bag, e.slot)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("TippWorks: " .. e.why, 1, 0.82, 0, true)
        GameTooltip:AddLine(db.tab == "auction" and "Click: load it into Post  |  Right-click: don't list it"
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
    local scan = Scan()
    local list = scan[db.tab] or scan.sell
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
            b.right:SetText(loaded and "|cff33ff33in Post|r" or e.ilvl and ("ilvl " .. e.ilvl) or "")
        else
            b.right:SetText(db.tab == "delete" and "|cffff6060delete|r" or (e.price > 0 and Money(e.price) or ""))
        end
        b:Show()
    end
    for i = n + 1, #rows do rows[i]:Hide(); rows[i].entry = nil end
    local footer
    win.post:SetShown(db.tab == "auction" and auctionOpen and n > 0)
    if db.tab == "auction" then
        win.sell:Hide()
        footer = n == 0 and "|cff888888Nothing unbound to post.|r"
            or not auctionOpen and "|cff888888Open the Auction House to post these.|r"
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
    win:SetHeight(-win.top + math.max(n, 1) * ROW_H + 40 + ((win.sell:IsShown() or win.post:IsShown()) and 24 or 0))
end

local function CreateWindow()
    win = TW.CreateWindow({ name = "TippWorksBagsFrame", title = "Bag Manager", version = ns.VERSION,
        width = WIDTH, db = db, onTab = function() ns.Refresh() end, tabs = {
            { key = "sell", label = "Sell", title = "Bag Manager - sell" },
            { key = "delete", label = "Delete", title = "Bag Manager - can't sell" },
            { key = "kept", label = "Kept", title = "Bag Manager - held back" },
            { key = "auction", label = "Auction", title = "Bag Manager - Auction House" },
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
    win:SetScript("OnShow", function() ns.Refresh() end)
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
    { "delete", "offerDelete", "Offer to delete matching items that can't be sold" },
    { "transmog", "protectTransmog", "Keep gear whose appearance you haven't collected" },
    { "tradeable", "protectTradeable", "Keep unbound blue and epic gear (Auction House)" },
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
        { "junk | low | armor | quest", "turn a selling rule on/off" },
        { "delete", "turn on/off offering to delete matching items that can't be sold" },
        { "transmog | tradeable", "turn a protection on/off" },
        { "auto", "turn on/off selling at the vendor without asking" },
        { "auction", "show the Auction tab (opens by itself at the Auction House)" },
        { "next | mats", "Auction House: load the next item after a post / list materials too" },
        { "unhide", "bring back items you right-clicked off the Auction tab" },
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
    text = "%s is also loaded, and it sells at the vendor too. Two addons selling at once can fight over the same items.\n\nDisable %s? (Your UI reloads.)",
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
        return
    end
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
    elseif event == "AUCTION_HOUSE_CLOSED" then
        auctionOpen, posting = false, nil
        if win:IsShown() and db.tab == "auction" then win:Hide() end
    elseif event == "BAG_UPDATE_DELAYED" and not selling then
        TW.Guard("bags posted", CheckPosted)
        TW.Guard("bags refresh", ns.Refresh)
    end
end)
