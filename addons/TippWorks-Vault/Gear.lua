local _, ns = ...
local TW = TippWorks

-- Gear export: this character's spec, equipped gear, bags, bank gear, Great
-- Vault progress and currencies as plain text, to paste into ChatGPT (or anywhere)
-- when planning upgrades. /tw gear, or the Gear button on the Vault window.

local Safe = TW.Safe
local function Readable(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end

local SLOTS = {
    { 1, "Head" }, { 2, "Neck" }, { 3, "Shoulder" }, { 15, "Back" }, { 5, "Chest" }, { 9, "Wrist" },
    { 10, "Hands" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" }, { 11, "Ring 1" }, { 12, "Ring 2" },
    { 13, "Trinket 1" }, { 14, "Trinket 2" }, { 16, "Main Hand" }, { 17, "Off Hand" },
}

local function ItemName(link) return link:match("%[(.-)%]") or link end

local function ItemLevel(link)
    local get = C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo
    return get and Safe(get, link)
end

-- What the tooltip says that the item link doesn't: upgrade track, enchant, tier set.
local function TooltipFacts(data)
    local facts = {}
    for _, line in ipairs(data and data.lines or {}) do
        local t = line.leftText
        if Readable(t) and type(t) == "string" then
            local track = t:match("^Upgrade Level:%s*(.+)")
            local enchant = t:match("^Enchanted:%s*(.+)")
            local set = t:match("^(.-)%s*%((%d+/%d+)%)$")
            if track then facts.track = track
            elseif enchant then facts.enchant = enchant
            elseif set and not facts.set and line.leftColor and line.leftColor.r > 0.9 and line.leftColor.g > 0.75
                and line.leftColor.b < 0.2 then
                facts.set = t -- the set name line is gold: "Name of the Set (2/5)"
            end
        end
    end
    return facts
end

local function Gems(link)
    local gems = {}
    for i = 1, 4 do
        local name = Safe(C_Item.GetItemGem or GetItemGem, link, i)
        if name then gems[#gems + 1] = name end
    end
    local sockets = C_Item.GetItemNumSockets and Safe(C_Item.GetItemNumSockets, link) or 0
    return gems, math.max(0, (sockets or 0) - #gems)
end

local function Describe(link, data)
    local parts = { ItemName(link) }
    local ilvl = ItemLevel(link)
    if ilvl then parts[#parts + 1] = "ilvl " .. ilvl end
    local f = TooltipFacts(data)
    if f.track then parts[#parts + 1] = f.track end
    if f.set then parts[#parts + 1] = "tier set " .. f.set end
    if f.enchant then parts[#parts + 1] = "enchant: " .. f.enchant end
    local gems, empty = Gems(link)
    if #gems > 0 then parts[#parts + 1] = "gems: " .. table.concat(gems, ", ") end
    if empty > 0 then parts[#parts + 1] = empty .. " empty socket" .. (empty > 1 and "s" or "") end
    return table.concat(parts, " | ")
end

local function Character(out)
    local name, realm = UnitName("player"), GetRealmName()
    local class = UnitClass("player")
    local race = UnitRace("player")
    local spec = GetSpecialization and GetSpecialization()
    local specName = spec and select(2, GetSpecializationInfo(spec))
    out[#out + 1] = ("Character: %s - %s, level %d %s %s%s, %s"):format(name or "?", realm or "?", UnitLevel("player"),
        race or "", class or "", specName and (" (" .. specName .. " spec)") or "", UnitFactionGroup("player") or "")
    local overall, equipped = GetAverageItemLevel()
    out[#out + 1] = ("Average item level: %.1f equipped, %.1f best available"):format(equipped or 0, overall or 0)
    out[#out + 1] = ("Gold: %d"):format(math.floor((GetMoney() or 0) / 10000))
end

local function Equipped(out)
    out[#out + 1] = ""
    out[#out + 1] = "## Equipped"
    for _, s in ipairs(SLOTS) do
        local link = GetInventoryItemLink("player", s[1])
        if link then
            local data = C_TooltipInfo and Safe(C_TooltipInfo.GetInventoryItem, "player", s[1])
            out[#out + 1] = ("- %s: %s"):format(s[2], Describe(link, data))
        elseif s[1] ~= 17 then
            out[#out + 1] = ("- %s: (empty)"):format(s[2])
        end
    end
end

-- Weapons and armor (cosmetics left out) as described lines; everything else
-- as name -> count (junk left out).
local function Collect(bags)
    local gear, other = {}, {}
    for _, bag in ipairs(bags) do
        for slot = 1, Safe(C_Container.GetContainerNumSlots, bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local link = info and info.hyperlink
            if link then
                local _, _, subType, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
                local isGear = (classID == 2 or classID == 4) and equipLoc and equipLoc ~= ""
                    and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" and equipLoc ~= "INVTYPE_TABARD"
                    and equipLoc ~= "INVTYPE_BODY" and not (classID == 4 and subclassID == 5)
                if isGear then
                    local data = C_TooltipInfo and Safe(C_TooltipInfo.GetBagItem, bag, slot)
                    local where = _G[equipLoc] or equipLoc
                    if classID == 4 and subType and subType ~= "Miscellaneous" then where = where .. ", " .. subType end
                    gear[#gear + 1] = ("- %s (%s)"):format(Describe(link, data), where)
                elseif (info.quality or 1) > 0 then
                    local name = ItemName(link)
                    other[name] = (other[name] or 0) + (info.stackCount or 1)
                end
            end
        end
    end
    return gear, other
end

local function BagIDs(patterns)
    local ids = {}
    for key, id in pairs(Enum.BagIndex or {}) do
        for _, p in ipairs(patterns) do
            if key:match(p) then ids[#ids + 1] = id break end
        end
    end
    table.sort(ids)
    return ids
end

local function Bags(out)
    local ids = {}
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do ids[#ids + 1] = bag end
    local gear, other = Collect(ids)
    out[#out + 1] = ""
    out[#out + 1] = "## Gear in bags"
    if #gear == 0 then out[#out + 1] = "- (none)" end
    for _, l in ipairs(gear) do out[#out + 1] = l end
    local names = {}
    for name in pairs(other) do names[#names + 1] = name end
    table.sort(names)
    out[#out + 1] = ""
    out[#out + 1] = "## Other items in bags"
    if #names == 0 then out[#out + 1] = "- (none)" end
    for _, name in ipairs(names) do
        out[#out + 1] = other[name] > 1 and ("- %s x%d"):format(name, other[name]) or ("- " .. name)
    end
end

-- The bank can only be read while it's open: its gear is saved then (the
-- character bank per character, the warband bank for the whole account).
local function SnapshotBank()
    local mine = Collect(BagIDs({ "^Bank$", "^BankBag", "^CharacterBankTab" }))
    local wbTabs = BagIDs({ "^AccountBankTab" })
    local warband = Collect(wbTabs)
    ns.db.bankGear = { at = date("%Y-%m-%d"), lines = mine }
    local readable = false
    for _, id in ipairs(wbTabs) do
        if (Safe(C_Container.GetContainerNumSlots, id) or 0) > 0 then readable = true end
    end
    if readable then
        TW.account.warbandGear = { at = date("%Y-%m-%d"), by = UnitName("player"), lines = warband }
    end
    TW.Log("VAULT", "bank gear saved for the export: %d in your bank, %d in the warband bank", #mine, #warband)
end

local function Bank(out)
    local function Section(title, snap, note)
        out[#out + 1] = ""
        out[#out + 1] = title .. (snap and (" (as of " .. snap.at .. (note or "") .. ")") or "")
        if not snap then out[#out + 1] = "- (not known yet: open the bank once)" return end
        if #snap.lines == 0 then out[#out + 1] = "- (none)" end
        for _, l in ipairs(snap.lines) do out[#out + 1] = l end
    end
    Section("## Gear in my bank", ns.db.bankGear)
    local wb = TW.account.warbandGear
    Section("## Gear in the warband bank (any of my characters can take it)", wb, wb and (", seen by " .. wb.by))
end

local bankEv = CreateFrame("Frame")
bankEv:RegisterEvent("BANKFRAME_OPENED")
bankEv:SetScript("OnEvent", function()
    -- Give the bank's items a moment to load.
    C_Timer.After(1.5, function()
        if ns.db then TW.Guard("bank snapshot", SnapshotBank) end
    end)
end)

local VAULT_ROWS = { { "Raid", "Raid" }, { "Activities", "Dungeons (Mythic+)" }, { "World", "Delves / world" } }
local function Vault(out)
    if not (C_WeeklyRewards and C_WeeklyRewards.GetActivities and Enum.WeeklyRewardChestThresholdType) then return end
    out[#out + 1] = ""
    out[#out + 1] = "## Great Vault this week"
    for _, r in ipairs(VAULT_ROWS) do
        local type = Enum.WeeklyRewardChestThresholdType[r[1]]
        local acts = type and Safe(C_WeeklyRewards.GetActivities, type)
        if acts and #acts > 0 then
            table.sort(acts, function(a, b) return a.threshold < b.threshold end)
            local slots = {}
            for _, a in ipairs(acts) do
                slots[#slots + 1] = (a.progress or 0) >= a.threshold
                    and ("unlocked (level %s)"):format(tostring(a.level or "?"))
                    or ("%d/%d"):format(a.progress or 0, a.threshold)
            end
            out[#out + 1] = ("- %s: %s"):format(r[2], table.concat(slots, "; "))
        end
    end
    if C_WeeklyRewards.HasAvailableRewards and Safe(C_WeeklyRewards.HasAvailableRewards) then
        out[#out + 1] = "- A reward from last week is waiting to be claimed"
    end
end

-- Every currency you have, grouped as in your currency tab. Collapsed groups
-- are named but not opened (that would change your currency tab).
local function Currencies(out)
    out[#out + 1] = ""
    out[#out + 1] = "## Currencies"
    local collapsed, header = {}, nil
    for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
        local c = C_CurrencyInfo.GetCurrencyListInfo(i)
        if c and c.isHeader then
            header = c.name
            if not c.isHeaderExpanded then collapsed[#collapsed + 1] = c.name end
        elseif c and (c.quantity or 0) > 0 then
            local extra = {}
            if (c.maxWeeklyQuantity or 0) > 0 then
                extra[#extra + 1] = ("this week %d/%d"):format(c.quantityEarnedThisWeek or 0, c.maxWeeklyQuantity)
            end
            if (c.maxQuantity or 0) > 0 then
                extra[#extra + 1] = c.useTotalEarnedForMaxQty
                    and ("earned %d/%d so far"):format(c.totalEarned or 0, c.maxQuantity)
                    or ("cap %d"):format(c.maxQuantity)
            end
            out[#out + 1] = ("- %s%s: %d%s"):format(header and (header .. " / ") or "", c.name, c.quantity,
                #extra > 0 and (" (" .. table.concat(extra, ", ") .. ")") or "")
        end
    end
    if #collapsed > 0 then
        out[#out + 1] = "- (not listed, collapsed in the currency tab: " .. table.concat(collapsed, ", ") .. ")"
    end
end

local function GearLines()
    local out = {
        ("# World of Warcraft character export (%s, TippWorks-Vault %s)"):format(date("%Y-%m-%d"), ns.VERSION),
        "Retail WoW, Midnight. Please suggest my best gear upgrades and what to spend currencies on.",
        "",
    }
    Character(out)
    Equipped(out)
    Bags(out)
    Bank(out)
    Vault(out)
    Currencies(out)
    return out
end

function ns.GearReport() return table.concat(GearLines(), "\n") end

function ns.ShowGear()
    if InCombatLockdown() then ns.Print("leave combat first.") return end
    TW.Guard("gear export", function()
        local lines = GearLines()
        -- Too long to copy in one go, so it's saved too: Export-Gear.cmd (in the wow-addons folder) writes it
        -- to a text file once WoW has saved it (on /reload or logout).
        ns.db.gearExport = { at = date("%Y-%m-%d %H:%M"), lines = lines }
        TW.Log("VAULT", "gear export made (%d lines)", #lines)
        TW.ShowText("Gear export - paste into ChatGPT", table.concat(lines, "\n"))
        ns.Print("saved for a file too: /reload (or log out), then run Export-Gear.cmd in your wow-addons folder.")
    end)
end
