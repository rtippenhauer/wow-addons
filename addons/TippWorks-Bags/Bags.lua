local ADDON, ns = ...
local TW = TippWorks

-- Bag manager: at a vendor, lists what can go (junk, gear well below what you
-- wear, armor that isn't your type, items for quests you've finished) and
-- sells it with one click - or by itself if you turn that on. Items that
-- can't be sold can be deleted, one confirmed click each.
-- Never touched: uncollected transmog, equipment-set items, items you keep,
-- unbound blue+ gear (Auction House) and anything above epic.

-- The running version. WoW only re-reads the .toc on a full restart, so the
-- number lives here too. Bump both together.
ns.VERSION = "1.0.0"
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
-- Returns { sell = {...}, delete = {...}, kept = {...} }; each entry is
-- { bag, slot, itemID, link, name, count, price, why }.
local function Scan()
    local out = { sell = {}, delete = {}, kept = {} }
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
                end
            end
        end
    end
    -- Junk first, then the most valuable: if the 12-item cap bites, the rest waits for the next visit.
    table.sort(out.sell, function(a, b)
        if (a.why == "junk") ~= (b.why == "junk") then return a.why == "junk" end
        return a.price > b.price
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
        if btn == "RightButton" or db.tab == "kept" then ToggleKeep(e)
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
        GameTooltip:AddLine(db.tab == "delete" and "Left-click: delete (asks first)  |  Right-click: keep it"
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
        b.right:SetText(db.tab == "delete" and "|cffff6060delete|r" or (e.price > 0 and Money(e.price) or ""))
        b:Show()
    end
    for i = n + 1, #rows do rows[i]:Hide(); rows[i].entry = nil end
    local footer
    if db.tab == "sell" then
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
    win:SetHeight(-win.top + math.max(n, 1) * ROW_H + 40 + (merchantOpen and db.tab == "sell" and 24 or 0))
end

local function CreateWindow()
    win = TW.CreateWindow({ name = "TippWorksBagsFrame", title = "Bag Manager", version = ns.VERSION,
        width = WIDTH, db = db, onTab = function() ns.Refresh() end, tabs = {
            { key = "sell", label = "Sell", title = "Bag Manager - sell" },
            { key = "delete", label = "Delete", title = "Bag Manager - can't sell" },
            { key = "kept", label = "Kept", title = "Bag Manager - held back" },
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
    win:SetScript("OnShow", function() ns.Refresh() end)
    win:SelectTab(db.tab == "delete" and "delete" or db.tab == "kept" and "kept" or "sell")
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

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        TippWorksBagsDB = TippWorksBagsDB or {}
        db = TippWorksBagsDB
        db.keep = db.keep or {}
        db.tab = db.tab or "sell"
        TW.Log("INFO", "TippWorks-Bags v%s loaded", ns.VERSION)
        CreateWindow()
        AddSettings()
        self:RegisterEvent("MERCHANT_SHOW")
        self:RegisterEvent("MERCHANT_CLOSED")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
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
    elseif event == "BAG_UPDATE_DELAYED" and not selling then
        TW.Guard("bags refresh", ns.Refresh)
    end
end)
