local _, ns = ...
local TW = TippWorks

-- Gear export: this character's spec and talents, stats, equipped gear (stats,
-- effects, enchants, gems), bags, bank gear, Great Vault progress and choices,
-- currencies, action bars and a SimulationCraft profile as plain text, to paste
-- into ChatGPT (or anywhere) when planning upgrades. /tw gear or the Gear button
-- shows it; it's also saved on logout / reload and when the bank or vault opens.

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
                -- In full: the export goes to a file, and the numbers at the end matter.
                facts.effects[#facts.effects + 1] = (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+", " "))
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
    if Readable(import) and import ~= "" then
        out[#out + 1] = "- Talent import string: " .. import
        -- The game only exports the active spec's build, so each spec's is kept from when you last played it.
        ns.db.talents = ns.db.talents or {}
        ns.db.talents[specID] = { at = date("%Y-%m-%d"), hero = hero, loadout = loadout, import = import }
    end
    for i = 1, (GetNumSpecializations and GetNumSpecializations() or 0) do
        if i ~= spec then
            local id, name, _, _, r = GetSpecializationInfo(i)
            local names = {}
            for _, cid in ipairs(id and CT and CT.GetConfigIDsBySpecID and Safe(CT.GetConfigIDsBySpecID, id) or {}) do
                names[#names + 1] = ConfigName(cid)
            end
            local saved = id and ns.db.talents and ns.db.talents[id]
            out[#out + 1] = ("- Other spec: %s (%s)%s%s"):format(name or "?", r and r:lower() or "?",
                saved and saved.hero and (", hero talents: " .. saved.hero) or "",
                #names > 0 and (", saved loadouts: " .. table.concat(names, ", ")) or "")
            out[#out + 1] = saved
                and ("  - Its talent import string (as of %s, when you last played it): %s"):format(saved.at, saved.import)
                or "  - (its talents aren't known yet: switch to it once)"
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

-- Snapshot when the bank opens (its items need a moment to load), and again
-- after each change while it's open, so deposits and withdrawals are caught.
local bankEv, bankOpen, bankQueued = CreateFrame("Frame"), false, false
local function QueueBankSnapshot(delay)
    if bankQueued then return end
    bankQueued = true
    C_Timer.After(delay, function()
        bankQueued = false
        if bankOpen and ns.db then TW.Guard("bank snapshot", SnapshotBank) end
    end)
end
bankEv:RegisterEvent("BANKFRAME_OPENED")
bankEv:RegisterEvent("BANKFRAME_CLOSED")
bankEv:RegisterEvent("BAG_UPDATE_DELAYED")
bankEv:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_OPENED" then
        bankOpen = true
        QueueBankSnapshot(1.5)
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
    elseif bankOpen then
        QueueBankSnapshot(1)
    end
end)

local VAULT_ROWS = { { "Raid", "Raid" }, { "Activities", "Dungeons (Mythic+)" }, { "World", "Delves / world" } }
local function Vault(out)
    if not (C_WeeklyRewards and C_WeeklyRewards.GetActivities and Enum.WeeklyRewardChestThresholdType) then return end
    out[#out + 1] = ""
    out[#out + 1] = "## Great Vault this week"
    local choices, choiceLinks = {}, {}
    ns.vaultChoiceLinks = nil
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
                        choiceLinks[#choiceLinks + 1] = link
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
    -- Once a reward is claimed the old choices can linger in the activity data: list them only while one waits.
    if waiting and #choices > 0 then
        ns.vaultChoiceLinks = choiceLinks
        out[#out + 1] = ""
        out[#out + 1] = "## Great Vault rewards to choose from (pick one)"
        for _, l in ipairs(choices) do out[#out + 1] = l end
    elseif waiting then
        out[#out + 1] = "- (open the Great Vault once so its choices are in this export)"
    end
end

-- Opening the Great Vault saves the export too, with the choices in it: again a
-- few seconds later (a choice's Equip text can still be loading at first), and
-- when it closes (after a pick the choices are gone and the reward is in your bags
-- or currencies).
local vaultEv, vaultHooked = CreateFrame("Frame"), false
vaultEv:RegisterEvent("ADDON_LOADED")
local function VaultSave()
    if ns.db and not InCombatLockdown() then TW.Guard("vault snapshot", ns.SaveGearExport) end
end
local function HookVault()
    if not WeeklyRewardsFrame or vaultHooked then return end
    vaultHooked = true
    WeeklyRewardsFrame:HookScript("OnShow", function()
        C_Timer.After(1, VaultSave)
        C_Timer.After(5, VaultSave)
    end)
    WeeklyRewardsFrame:HookScript("OnHide", function() C_Timer.After(1, VaultSave) end)
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

-- SimulationCraft profile (paste into Raidbots Quick Sim / Top Gear), built from
-- the item links the same way the SimulationCraft addon does: item id, enchant,
-- gems, bonus ids, context, drop level and crafted stats. Bag gear and vault
-- choices are commented out, which is how Top Gear finds alternatives.
local SIMC_SLOT = {
    [1] = "head", [2] = "neck", [3] = "shoulder", [15] = "back", [5] = "chest", [9] = "wrist", [10] = "hands",
    [6] = "waist", [7] = "legs", [8] = "feet", [11] = "finger1", [12] = "finger2", [13] = "trinket1",
    [14] = "trinket2", [16] = "main_hand", [17] = "off_hand",
}
local SIMC_EQUIPLOC = {
    INVTYPE_HEAD = "head", INVTYPE_NECK = "neck", INVTYPE_SHOULDER = "shoulder", INVTYPE_CLOAK = "back",
    INVTYPE_CHEST = "chest", INVTYPE_ROBE = "chest", INVTYPE_WRIST = "wrist", INVTYPE_HAND = "hands",
    INVTYPE_WAIST = "waist", INVTYPE_LEGS = "legs", INVTYPE_FEET = "feet", INVTYPE_FINGER = "finger1",
    INVTYPE_TRINKET = "trinket1", INVTYPE_WEAPON = "main_hand", INVTYPE_2HWEAPON = "main_hand",
    INVTYPE_WEAPONMAINHAND = "main_hand", INVTYPE_RANGED = "main_hand", INVTYPE_RANGEDRIGHT = "main_hand",
    INVTYPE_WEAPONOFFHAND = "off_hand", INVTYPE_SHIELD = "off_hand", INVTYPE_HOLDABLE = "off_hand",
}
local SIMC_ROLE = { DAMAGER = nil, HEALER = "heal", TANK = "tank" }
local REGIONS = { "us", "kr", "eu", "tw", "cn" }

local function Token(s)
    return (s or ""):gsub("(%l)(%u)", "%1_%2"):gsub("[%s%-]+", "_"):gsub("'", ""):lower()
end

-- "slot=,id=...,bonus_id=..." from an item link, or nil if it isn't one.
local function SimcItem(slot, link)
    local body = type(link) == "string" and link:match("|Hitem:([^|]+)|h")
    if not body then return end
    local f = {}
    for v in (body .. ":"):gmatch("([^:]*):") do f[#f + 1] = v end
    local function n(i) return tonumber(f[i]) end
    local parts = { slot .. "=", "id=" .. (f[1] or "0") }
    if n(2) then parts[#parts + 1] = "enchant_id=" .. f[2] end
    local gems = {}
    for i = 3, 6 do if n(i) then gems[#gems + 1] = f[i] end end
    if #gems > 0 then parts[#parts + 1] = "gem_id=" .. table.concat(gems, "/") end
    local i = 14
    local numBonus = n(13) or 0
    local bonus = {}
    for b = 1, numBonus do if n(i + b - 1) then bonus[#bonus + 1] = f[i + b - 1] end end
    if #bonus > 0 then parts[#parts + 1] = "bonus_id=" .. table.concat(bonus, "/") end
    if n(12) then parts[#parts + 1] = "context=" .. f[12] end
    i = i + numBonus
    local numMods = n(i) or 0
    local crafted = {}
    for m = 1, numMods do
        local mtype, value = n(i + 2 * m - 1), f[i + 2 * m]
        if mtype == 9 and tonumber(value) then parts[#parts + 1] = "drop_level=" .. value
        elseif (mtype == 29 or mtype == 30) and tonumber(value) then crafted[#crafted + 1] = value end
    end
    if #crafted > 0 then parts[#parts + 1] = "crafted_stats=" .. table.concat(crafted, "/") end
    return table.concat(parts, ",")
end

local function Simc(out)
    local spec = GetSpecialization and GetSpecialization()
    if not spec then return end
    local _, specName, _, _, role = GetSpecializationInfo(spec)
    local _, classFile = UnitClass("player")
    local _, raceFile = UnitRace("player")
    raceFile = raceFile == "Scourge" and "Undead" or raceFile == "EarthenDwarf" and "Earthen" or raceFile
    out[#out + 1] = ""
    out[#out + 1] = "## SimulationCraft profile (copy everything below into Raidbots Quick Sim or Top Gear)"
    out[#out + 1] = ('%s="%s"'):format(Token(classFile), UnitName("player") or "?")
    out[#out + 1] = "level=" .. UnitLevel("player")
    out[#out + 1] = "race=" .. Token(raceFile)
    out[#out + 1] = "region=" .. (REGIONS[GetCurrentRegion and GetCurrentRegion() or 1] or "us")
    out[#out + 1] = "server=" .. Token(GetRealmName())
    if SIMC_ROLE[role or ""] then out[#out + 1] = "role=" .. SIMC_ROLE[role] end
    out[#out + 1] = "spec=" .. Token(specName)
    local active = C_ClassTalents and C_ClassTalents.GetActiveConfigID and Safe(C_ClassTalents.GetActiveConfigID)
    local import = active and C_Traits.GenerateImportString and Safe(C_Traits.GenerateImportString, active)
    if Readable(import) and import ~= "" then out[#out + 1] = "talents=" .. import end
    out[#out + 1] = ""
    for _, s in ipairs(SLOTS) do
        local line = SimcItem(SIMC_SLOT[s[1]], GetInventoryItemLink("player", s[1]))
        if line then out[#out + 1] = line end
    end
    local function Commented(title, links)
        if #links == 0 then return end
        out[#out + 1] = ""
        out[#out + 1] = "### " .. title
        for _, link in ipairs(links) do
            local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
            local line = SIMC_EQUIPLOC[equipLoc or ""] and SimcItem(SIMC_EQUIPLOC[equipLoc], link)
            if line then
                out[#out + 1] = ("# %s (%s)"):format(ItemName(link), tostring(ItemLevel(link) or "?"))
                out[#out + 1] = "# " .. line
            end
        end
    end
    local bagLinks = {}
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, Safe(C_Container.GetContainerNumSlots, bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink then bagLinks[#bagLinks + 1] = info.hyperlink end
        end
    end
    Commented("Gear from Bags", bagLinks)
    Commented("Weekly Reward Choices", ns.vaultChoiceLinks or {})
end

-- What's on each action bar and its keybinding, with macro text, so rotation
-- advice can refer to your actual buttons. Bars 1-8 as Edit Mode numbers them.
local BARS = {
    { "Bar 1", nil, "ACTIONBUTTON" }, { "Bar 2", 61, "MULTIACTIONBAR1BUTTON" },
    { "Bar 3", 49, "MULTIACTIONBAR2BUTTON" }, { "Bar 4", 25, "MULTIACTIONBAR3BUTTON" },
    { "Bar 5", 37, "MULTIACTIONBAR4BUTTON" }, { "Bar 6", 145, "MULTIACTIONBAR5BUTTON" },
    { "Bar 7", 157, "MULTIACTIONBAR6BUTTON" }, { "Bar 8", 169, "MULTIACTIONBAR7BUTTON" },
}
local function Str(v) return Readable(v) and type(v) == "string" and v ~= "" and v or nil end

local function ActionText(slot)
    local ok, kind, id = pcall(GetActionInfo, slot)
    if not ok or not Readable(kind) or not kind then return end
    if not Readable(id) then id = nil end
    if kind == "spell" then
        local name = id and C_Spell and C_Spell.GetSpellName and Str(Safe(C_Spell.GetSpellName, id))
        return name or ("spell " .. tostring(id))
    elseif kind == "macro" then
        local name, _, body
        if id and GetMacroInfo then
            local mok, mname, _, mbody = pcall(GetMacroInfo, id)
            if mok then name, body = Str(mname), Str(mbody) end
        end
        name = name or Str(Safe(GetActionText, slot)) or "?"
        return "macro \"" .. name .. "\"" .. (body and (": " .. strtrim(body):gsub("\r?\n", " / ")) or "")
    elseif kind == "item" then
        return "item " .. (id and Str(Safe(C_Item.GetItemNameByID, id)) or tostring(id))
    elseif kind == "flyout" then
        return "flyout " .. (id and GetFlyoutInfo and Str(Safe(GetFlyoutInfo, id)) or tostring(id))
    end
    return kind .. (id and (" " .. tostring(id)) or "")
end

local function ActionBars(out)
    if not GetActionInfo then return end
    out[#out + 1] = ""
    out[#out + 1] = "## Action bars and keybindings (current spec)"
    local offset = GetBonusBarOffset and Safe(GetBonusBarOffset) or 0
    local page = GetActionBarPage and Safe(GetActionBarPage) or 1
    local any = false
    for _, bar in ipairs(BARS) do
        local first = bar[2] or ((offset and offset > 0) and ((6 + offset - 1) * 12 + 1) or ((page - 1) * 12 + 1))
        for b = 1, 12 do
            local text = ActionText(first + b - 1)
            if text then
                local keys = {}
                local kok, k1, k2 = pcall(GetBindingKey, bar[3] .. b)
                if kok then
                    if Str(k1) then keys[#keys + 1] = k1 end
                    if Str(k2) then keys[#keys + 1] = k2 end
                end
                out[#out + 1] = ("- %s button %d%s: %s"):format(bar[1], b,
                    #keys > 0 and (" [" .. table.concat(keys, ", ") .. "]") or "", text)
                any = true
            end
        end
    end
    if not any then out[#out + 1] = "- (none readable)" end
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
    ActionBars(out)
    Simc(out)
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

-- Logging out (or /reload) saves a fresh export, so Export-Gear.cmd always has
-- what you ended the session with. Switching spec or talents keeps that spec's
-- build for the export's "Other spec" lines.
local saveEv = CreateFrame("Frame")
saveEv:RegisterEvent("PLAYER_LOGOUT")
saveEv:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
saveEv:RegisterEvent("TRAIT_CONFIG_UPDATED")
saveEv:RegisterEvent("PLAYER_ENTERING_WORLD")
local talentQueued = false
saveEv:SetScript("OnEvent", function(_, event, unit)
    if not ns.db then return end
    if event == "PLAYER_LOGOUT" then
        TW.Guard("logout export", ns.SaveGearExport)
    elseif event ~= "PLAYER_SPECIALIZATION_CHANGED" or unit == "player" then
        if talentQueued then return end
        talentQueued = true
        C_Timer.After(3, function()
            talentQueued = false
            if not InCombatLockdown() then TW.Guard("talent record", Talents, {}) end
        end)
    end
end)
