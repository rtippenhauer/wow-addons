local _, ns = ...
local TW = TippWorks

-- Gear export: this character's spec and talents, stats, equipped gear (stats,
-- effects, enchants, gems), bags, bank gear, Great Vault progress and choices and
-- currencies as plain text, to paste into ChatGPT (or anywhere) when planning
-- upgrades. /tw gear, the Gear button, or just opening the bank or the Great Vault.

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

-- Stats as the item link carries them (its real item level and bonuses).
local STATS = {
    { "ITEM_MOD_STRENGTH_SHORT", "Str" }, { "ITEM_MOD_AGILITY_SHORT", "Agi" }, { "ITEM_MOD_INTELLECT_SHORT", "Int" },
    { "ITEM_MOD_CRIT_RATING_SHORT", "Crit" }, { "ITEM_MOD_HASTE_RATING_SHORT", "Haste" },
    { "ITEM_MOD_MASTERY_RATING_SHORT", "Mastery" }, { "ITEM_MOD_VERSATILITY", "Vers" },
    { "ITEM_MOD_CR_LIFESTEAL_SHORT", "Leech" }, { "ITEM_MOD_CR_AVOIDANCE_SHORT", "Avoidance" },
    { "ITEM_MOD_CR_SPEED_SHORT", "Speed" },
}
local function Stats(link)
    local get = C_Item.GetItemStats or GetItemStats
    local s = get and Safe(get, link)
    if type(s) ~= "table" then return end
    local parts = {}
    for _, st in ipairs(STATS) do
        local v = s[st[1]]
        if Readable(v) and v > 0 then parts[#parts + 1] = ("%s %d"):format(st[2], v) end
    end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

-- What the tooltip says that the item link doesn't: upgrade track, enchant, tier set, Equip/Use effects.
local function TooltipFacts(data)
    local facts = { effects = {} }
    for _, line in ipairs(data and data.lines or {}) do
        local t = line.leftText
        if Readable(t) and type(t) == "string" then
            local track = t:match("^Upgrade Level:%s*(.+)")
            local enchant = t:match("^Enchanted:%s*(.+)")
            local set = t:match("^(.-)%s*%((%d+/%d+)%)$")
            if track then facts.track = track
            elseif enchant then facts.enchant = enchant
            elseif t:match("^Equip:") or t:match("^Use:") then
                local e = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+", " ")
                facts.effects[#facts.effects + 1] = #e > 240 and (e:sub(1, 237) .. "...") or e
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
    local stats = Stats(link)
    if stats then parts[#parts + 1] = stats end
    if f.set then parts[#parts + 1] = "tier set " .. f.set end
    for _, e in ipairs(f.effects) do parts[#parts + 1] = e end
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

local PRIMARY = { "Strength", "Agility", "Stamina", "Intellect" }
local function Num(f, ...)
    local v = f and Safe(f, ...)
    return Readable(v) and type(v) == "number" and v or nil
end

-- Character sheet totals: primary stat, then each secondary as rating and %.
local function CharacterStats(out)
    out[#out + 1] = ""
    out[#out + 1] = "## Character stats (out of combat, with buffs active now)"
    local spec = GetSpecialization and GetSpecialization()
    local primary = spec and select(6, GetSpecializationInfo(spec))
    if primary and PRIMARY[primary] then
        local ok, _, total = pcall(UnitStat, "player", primary)
        if ok and Readable(total) and type(total) == "number" then out[#out + 1] = ("- %s: %d"):format(PRIMARY[primary], total) end
    end
    local function Line(label, rating, pct)
        if rating or pct then
            out[#out + 1] = ("- %s: %s%s"):format(label, rating and tostring(rating) or "?", pct and (" (%.1f%%)"):format(pct) or "")
        end
    end
    Line("Crit", Num(GetCombatRating, CR_CRIT_SPELL or 11), Num(GetCritChance))
    Line("Haste", Num(GetCombatRating, CR_HASTE_SPELL or 20), Num(GetHaste))
    Line("Mastery", Num(GetCombatRating, CR_MASTERY or 26), Num(GetMasteryEffect))
    local vr = CR_VERSATILITY_DAMAGE_DONE or 29
    local vpct = Num(GetCombatRatingBonus, vr)
    local vbonus = Num(GetVersatilityBonus, vr)
    Line("Versatility", Num(GetCombatRating, vr), vpct and (vpct + (vbonus or 0)))
    Line("Leech", Num(GetCombatRating, CR_LIFESTEAL or 17), Num(GetLifesteal))
end

local function ConfigName(id)
    local info = id and C_Traits and C_Traits.GetConfigInfo and Safe(C_Traits.GetConfigInfo, id)
    return info and Readable(info.name) and info.name or nil
end

-- Active spec's talents (loadout, hero tree, import string for Wowhead/Raidbots),
-- other specs' saved loadouts, and equipment sets.
local function Talents(out)
    out[#out + 1] = ""
    out[#out + 1] = "## Talents and specs"
    local spec = GetSpecialization and GetSpecialization()
    if not spec then out[#out + 1] = "- (no spec)" return end
    local specID, specName, _, _, role = GetSpecializationInfo(spec)
    if not specID then out[#out + 1] = "- (no spec)" return end
    local CT = C_ClassTalents
    local active = CT and CT.GetActiveConfigID and Safe(CT.GetActiveConfigID)
    local loadout = CT and CT.GetLastSelectedSavedConfigID and ConfigName(Safe(CT.GetLastSelectedSavedConfigID, specID))
    local hero
    local sub = CT and CT.GetActiveHeroTalentSpec and Safe(CT.GetActiveHeroTalentSpec)
    if sub and active and C_Traits.GetSubTreeInfo then
        local info = Safe(C_Traits.GetSubTreeInfo, active, sub)
        hero = info and Readable(info.name) and info.name or nil
    end
    out[#out + 1] = ("- Active: %s (%s)%s%s"):format(specName or "?", role and role:lower() or "?",
        hero and (", hero talents: " .. hero) or "", loadout and (", loadout: " .. loadout) or "")
    local import = active and C_Traits.GenerateImportString and Safe(C_Traits.GenerateImportString, active)
    if Readable(import) and import ~= "" then out[#out + 1] = "- Talent import string: " .. import end
    for i = 1, (GetNumSpecializations and GetNumSpecializations() or 0) do
        if i ~= spec then
            local id, name, _, _, r = GetSpecializationInfo(i)
            local names = {}
            for _, cid in ipairs(id and CT and CT.GetConfigIDsBySpecID and Safe(CT.GetConfigIDsBySpecID, id) or {}) do
                names[#names + 1] = ConfigName(cid)
            end
            out[#out + 1] = ("- Other spec: %s (%s)%s"):format(name or "?", r and r:lower() or "?",
                #names > 0 and (", saved loadouts: " .. table.concat(names, ", ")) or "")
        end
    end
    local ES = C_EquipmentSet
    local sets = ES and ES.GetEquipmentSetIDs and Safe(ES.GetEquipmentSetIDs) or {}
    local equipped = {}
    if #sets > 0 then
        for _, s in ipairs(SLOTS) do equipped[s[1]] = GetInventoryItemID("player", s[1]) end
    end
    for _, setID in ipairs(sets) do
        local name = Safe(ES.GetEquipmentSetInfo, setID)
        local forSpec = ES.GetEquipmentSetAssignedSpec and Safe(ES.GetEquipmentSetAssignedSpec, setID)
        local diff = {}
        local ids = Safe(ES.GetItemIDs, setID) or {}
        for _, s in ipairs(SLOTS) do
            local want = ids[s[1]]
            if want and want > 0 and want ~= equipped[s[1]] then
                diff[#diff + 1] = s[2] .. " " .. (C_Item.GetItemNameByID and Safe(C_Item.GetItemNameByID, want) or ("item " .. want))
            end
        end
        out[#out + 1] = ("- Equipment set \"%s\"%s: %s"):format(name or "?",
            forSpec and (" for " .. (select(2, GetSpecializationInfo(forSpec)) or "?")) or "",
            #diff > 0 and ("differs from what's equipped: " .. table.concat(diff, "; ")) or "same as equipped")
    end
end

local TIER_SLOTS = { [1] = true, [3] = true, [5] = true, [10] = true, [7] = true }

local function Equipped(out)
    out[#out + 1] = ""
    out[#out + 1] = "## Equipped"
    local noSet = {}
    for _, s in ipairs(SLOTS) do
        local link = GetInventoryItemLink("player", s[1])
        if link then
            local data = C_TooltipInfo and Safe(C_TooltipInfo.GetInventoryItem, "player", s[1])
            out[#out + 1] = ("- %s: %s"):format(s[2], Describe(link, data))
            if TIER_SLOTS[s[1]] and not TooltipFacts(data).set then noSet[#noSet + 1] = s[2] end
        elseif s[1] ~= 17 then
            out[#out + 1] = ("- %s: (empty)"):format(s[2])
        end
    end
    if #noSet > 0 then
        out[#out + 1] = "- Tier slots without a set piece (the Catalyst can turn this season's gear there into one; "
            .. "charges are under Currencies): " .. table.concat(noSet, ", ")
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
    -- The whole export is saved too, so a bank visit is all Export-Gear.cmd needs.
    ns.SaveGearExport()
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
    local choices = {}
    for _, r in ipairs(VAULT_ROWS) do
        local kind = Enum.WeeklyRewardChestThresholdType[r[1]]
        local acts = kind and Safe(C_WeeklyRewards.GetActivities, kind)
        if acts and #acts > 0 then
            table.sort(acts, function(a, b) return a.threshold < b.threshold end)
            local slots = {}
            for i, a in ipairs(acts) do
                local text
                if (a.progress or 0) >= a.threshold then
                    -- The item level this slot gives (the game's own example item for it).
                    local example = a.id and C_WeeklyRewards.GetExampleRewardItemHyperlinks
                        and Safe(C_WeeklyRewards.GetExampleRewardItemHyperlinks, a.id)
                    local ilvl = Readable(example) and type(example) == "string" and ItemLevel(example)
                    text = ("unlocked (level %s%s)"):format(tostring(a.level or "?"), ilvl and (", ilvl " .. ilvl) or "")
                else
                    text = ("%d/%d"):format(a.progress or 0, a.threshold)
                end
                slots[#slots + 1] = text
                for _, rw in ipairs(a.rewards or {}) do
                    local link = rw.itemDBID and C_WeeklyRewards.GetItemHyperlink
                        and Safe(C_WeeklyRewards.GetItemHyperlink, rw.itemDBID)
                    if Readable(link) and type(link) == "string" and link ~= "" then
                        local data = C_TooltipInfo and Safe(C_TooltipInfo.GetHyperlink, link)
                        local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
                        choices[#choices + 1] = ("- %s slot %d: %s (%s)"):format(r[2], i, Describe(link, data),
                            equipLoc and _G[equipLoc] or "item")
                    end
                end
            end
            out[#out + 1] = ("- %s: %s"):format(r[2], table.concat(slots, "; "))
        end
    end
    local waiting = C_WeeklyRewards.HasAvailableRewards and Safe(C_WeeklyRewards.HasAvailableRewards)
    if waiting then
        out[#out + 1] = "- A reward from last week is waiting to be claimed"
    end
    if #choices > 0 then
        out[#out + 1] = ""
        out[#out + 1] = "## Great Vault rewards to choose from (pick one)"
        for _, l in ipairs(choices) do out[#out + 1] = l end
    elseif waiting then
        out[#out + 1] = "- (open the Great Vault once so its choices are in this export)"
    end
end

-- Opening the Great Vault saves the export too, with the choices in it.
local vaultEv, vaultHooked = CreateFrame("Frame"), false
vaultEv:RegisterEvent("ADDON_LOADED")
local function HookVault()
    if not WeeklyRewardsFrame or vaultHooked then return end
    vaultHooked = true
    WeeklyRewardsFrame:HookScript("OnShow", function()
        C_Timer.After(1, function()
            if ns.db and not InCombatLockdown() then TW.Guard("vault snapshot", ns.SaveGearExport) end
        end)
    end)
end
vaultEv:SetScript("OnEvent", function(_, _, name) if name == "Blizzard_WeeklyRewards" then HookVault() end end)
HookVault()

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
    Talents(out)
    CharacterStats(out)
    Equipped(out)
    Bags(out)
    Bank(out)
    Vault(out)
    Currencies(out)
    return out
end

function ns.GearReport() return table.concat(GearLines(), "\n") end

-- Too long to copy in one go, so it's saved too: Export-Gear.cmd (in the wow-addons folder) writes it
-- to a text file once WoW has saved it (on /reload or logout).
function ns.SaveGearExport()
    local lines = GearLines()
    ns.db.gearExport = { at = date("%Y-%m-%d %H:%M"), lines = lines }
    TW.Log("VAULT", "gear export made (%d lines)", #lines)
    return lines
end

function ns.ShowGear()
    if InCombatLockdown() then ns.Print("leave combat first.") return end
    TW.Guard("gear export", function()
        local lines = ns.SaveGearExport()
        TW.ShowText("Gear export - paste into ChatGPT", table.concat(lines, "\n"))
        ns.Print("saved for a file too: /reload (or log out), then run Export-Gear.cmd in your wow-addons folder.")
    end)
end
