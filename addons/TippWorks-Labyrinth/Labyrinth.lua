local ADDON, ns = ...
local TW = TippWorks

-- Labyrinth of Kindo'jan (12.1.5 mega-delve): the nine chambers of this run
-- and which are done, the three Hexmasks and where they spawned, the locked
-- room and its Keeper of the Key, and any quest picked up inside (with "where
-- do I go" for it). Opens by itself in the Labyrinth.
-- Data from the launch guides (Oct 2026); a first version that also LOGS what
-- the game reports (sub-zones, scenario objectives, buffs, markers, quests) so
-- the guesses below can be replaced by facts after a run - /tw log.

-- The running version. WoW only re-reads the .toc on a full restart, so the
-- number lives here too. Bump both together.
ns.VERSION = "1.5.7"
local Print = TW.Printer("Labyrinth")
local Safe = TW.Safe
local function Readable(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end

-- Every three chambers is a reward checkpoint; nine per run.
local CHAMBERS = {
    { name = "Chamber of Rites", where = "start", special = true, spot = { 50.3, 82.6 } },
    { name = "The Reliquary", where = "southwest" },
    { name = "The Catacombs", where = "southeast" },
    { name = "Halazzi's Lair", where = "west" },
    { name = "The Central Chamber", where = "middle" },
    { name = "The Cave Towers", where = "east", special = true, spot = { 88.5, 51.5 } },
    { name = "Jan'alai's Refuge", where = "northwest", special = true, spot = { 18.8, 18.2 } },
    { name = "Nalorakk's Rest", where = "northeast", special = true, spot = { 58.5, 21.7 } },
    { name = "Akil'zon's Roost", where = "north - Speaker's Chamber", special = true, spot = { 56.8, 17.8 } },
}
-- special = one of the five spots that can hold a Hexmask or the locked room
-- (from Journey rank 2: three masks, one locked room, one empty). spot = where
-- on the Labyrinth map (uiMapID 2647), from Wowhead/Seramate (Oct 15 2026).
local MAZE_MAP = 2647

local MASKS = {
    { key = "frozen", name = "Frozen Hexmask", what = "Frost Nova" },
    { key = "fiery", name = "Fiery Hexmask", what = "Burning Gaze of Ula'tek" },
    { key = "thundering", name = "Thundering Hexmask", what = "Chain Lightning" },
}
local KEEPER_NPC = 273788

-- The 20 Sturdy Chests with no requirements, the nine Loa-sealed rooms
-- (Journey ranks 3/5/7/9) and the Flooded Chamber - Wowhead's Labyrinth
-- guide (updated 2026/10/16), all on the Labyrinth map (uiMapID 2647).
-- Sturdy Chests loot ONCE per character, so they're tracked across runs.
local CHESTS = {
    { 1, "Chamber of Rites", 37.1, 69.8 }, { 2, "Chamber of Rites", 47.0, 64.3 },
    { 3, "The Reliquary", 30.0, 74.1 }, { 4, "The Reliquary", 22.0, 68.6 },
    { 5, "Halazzi's Lair", 13.8, 35.5 }, { 6, "Halazzi's Lair", 26.2, 40.3 },
    { 7, "The Catacombs", 72.3, 65.6 }, { 8, "The Catacombs", 69.6, 70.9 },
    { 9, "The Cave Towers", 87.0, 63.0 }, { 10, "The Cave Towers", 81.5, 55.4 },
    { 11, "Akil'zon's Roost", 40.6, 20.7 }, { 12, "Akil'zon's Roost", 45.4, 11.7 },
    { 13, "Nalorakk's Rest", 68.4, 33.8 }, { 14, "Nalorakk's Rest", 67.5, 27.7 },
    { 15, "Jan'alai's Refuge", 22.4, 29.4 }, { 16, "Jan'alai's Refuge", 21.5, 36.4 }, { 17, "Jan'alai's Refuge", 28.5, 22.9 },
    { 18, "The Central Chamber", 45.8, 48.0 }, { 19, "The Central Chamber", 40.7, 45.7 }, { 20, "The Central Chamber", 47.6, 40.3 },
}
local SEALED = {
    { "Akil'zon", 3, "Chamber of Rites", 38.7, 78.1 }, { "Akil'zon", 3, "The Cave Towers", 88.7, 70.7 },
    { "Akil'zon", 3, "Akil'zon's Roost", 34.9, 17.8 },
    { "Jan'alai", 5, "Halazzi's Lair", 24.4, 35.6 }, { "Jan'alai", 5, "Jan'alai's Refuge", 23.4, 16.3 },
    { "Nalorakk", 7, "The Reliquary", 28.8, 77.1 }, { "Nalorakk", 7, "Nalorakk's Rest", 64.1, 39.2 },
    { "Halazzi", 9, "Halazzi's Lair", 13.5, 46.1 }, { "Halazzi", 9, "The Catacombs", 66.6, 54.9 },
}
-- What each seal's chests give, and the items tied to a specific sealed room.
local SEAL_REWARDS = {
    ["Akil'zon"] = "Akil'zon's Swiftness (+3% speed per chamber cleared, every run) and the Falco Strikes glove enchant",
    ["Jan'alai"] = "the Heat Wave glove enchant (no permanent upgrade)",
    ["Nalorakk"] = "Nalorakk's Ferocity (+3% primary stat per chamber cleared, every run) and the Ursine's Ironhide glove enchant",
    ["Halazzi"] = "Halazzi's Shroud (cheat death once per run) and the Eye of the Lynx glove enchant",
}
local ROOM_REWARDS = {
    ["Akil'zon@Chamber of Rites"] = "Loa-Touched Spine, Hexdrinker's Shoulders (transmog)",
    ["Akil'zon@Akil'zon's Roost"] = "Feathers of Akil'zon (toy)",
    ["Jan'alai@Jan'alai's Refuge"] = "Loa-Touched Deltoid (transmog)",
    ["Jan'alai@Halazzi's Lair"] = "Rite of Jan'alai's Flame (toy)",
    ["Nalorakk@The Reliquary"] = "Nalorakk's Strength Charm (toy)",
    ["Halazzi@Halazzi's Lair"] = "Loa-Touched Visage (transmog)",
    ["Halazzi@The Catacombs"] = "Trail of Halazzi (toy)",
}
-- Somewhere among the 44 Sturdy Chests (Wowhead doesn't say which):
local CHEST_UNIQUES = "Amani Effigy, Hexbearer's Pauldrons, Effigy of Corrosion, Ancient Amani Mural, Brown Amani Tapestry"

local CHEST_LOOT_RANGE = 0.02 -- map fraction (~2%): loot opened this close to a chest's spot = that chest
local ROOM_ENTER_RANGE = 0.015 -- standing this close to a sealed room's spot = you've been inside it
local KEY_NAME = "Archaic Amani Key"
local ICON_KEY = "Interface\\Icons\\INV_Misc_Key_03"
local ICON_LOCK = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK"
local ICON_MASK = 135462 -- unchecked hidden room: possible Hexmask (same icon file HandyNotes_Midnight uses)
local WIDTH, ROW_H = 330, 17

local db, run, win
local warband -- account-wide (TippWorksLabyrinthAccountDB): Sturdy Chests loot once per warband
local rows = {}

-- HandyNotes_Midnight already marks the Hexmask spots: then ours stay hidden
-- unless /tw maze masks turns them on. (The key icon always shows.)
local function MaskIconsShown()
    if db.maskIcons ~= nil then return db.maskIcons end
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and Safe(C_AddOns.IsAddOnLoaded, "HandyNotes_Midnight")
    return not loaded
end

---------------------------------------------------------------------------
-- Where am I
---------------------------------------------------------------------------
local function InLabyrinth()
    local name = GetInstanceInfo()
    return Readable(name) and type(name) == "string" and (name:find("Labyrinth", 1, true) or name:find("Kindo", 1, true)) and true or false
end

local function Norm(s) return s and s:lower():gsub("\226\128\153", "'"):gsub("^the ", "") end

local byNorm = {}
for _, c in ipairs(CHAMBERS) do byNorm[Norm(c.name)] = c end

-- The chamber you're standing in: from the sub-zone text or the map name.
local function CurrentChamber()
    for _, fn in ipairs({ GetSubZoneText, GetMinimapZoneText }) do
        local t = Safe(fn)
        local c = type(t) == "string" and byNorm[Norm(t)]
        if c then return c end
    end
    local m = C_Map.GetBestMapForUnit("player")
    local info = m and C_Map.GetMapInfo(m)
    return info and Readable(info.name) and byNorm[Norm(info.name)] or nil
end

---------------------------------------------------------------------------
-- Run state (one per entry; chamber progress doesn't carry over)
---------------------------------------------------------------------------
local function NewRun(why)
    run = { started = time(), chambers = {}, masks = {}, spots = {}, quests = {}, notes = {} }
    db.run = run
    TW.Log("MAZE", "new Labyrinth run (%s)", why)
end

-- Inside / outside. A saved run only carries on when you never left it and were in it
-- within the last 30 minutes (a /reload inside); anything else starts a new run.
local STALE_RUN = 30 * 60
local inside = false
local function SetInside(now)
    if now and not inside then
        local fresh = run and not run.left and run.lastSeen and time() - run.lastSeen < STALE_RUN
        if not fresh then NewRun(run and run.lastSeen and not run.left and "the saved run is over 30 minutes old"
            or run and not run.lastSeen and "the saved run is from an older version" or "entered the Labyrinth") end
        run.lastSeen = time()
        if win then win:Show() end
    elseif not now then
        if inside and win then win:Hide() end
        if run and run.lastSeen and not run.left then
            run.left = true
            TW.Log("MAZE", "left the Labyrinth")
        end
    end
    inside = now
end

local function DoneCount()
    local n = 0
    for _, c in ipairs(CHAMBERS) do if run.chambers[c.name] == "done" then n = n + 1 end end
    return n
end

local function Note(key, fmt, ...)
    -- Log each distinct thing once per run, to learn what the game reports.
    if run.notes[key] then return end
    run.notes[key] = true
    TW.Log("MAZE", fmt, ...)
end

local function MarkChamber(c, state, how)
    if not c or run.chambers[c.name] == "done" then return end
    if state == "here" and run.chambers[c.name] then return end
    run.chambers[c.name] = state
    TW.Log("MAZE", "%s: %s (%s)", c.name, state == "done" and "completed" or "entered", how)
    if state == "done" then
        local n = DoneCount()
        if n == 3 or n == 6 or n == 9 then Print(("%d chambers done - reward checkpoint!"):format(n)) end
        -- Like Dundun: the Keeper hides in a chamber, so look before moving on.
        if not run.hasKey and not run.keyHolder and not run.doorOpened then
            Print("before you move on: press |cffffd100Find the Keeper|r (key binding) - he may be hiding in this chamber.")
        end
    end
    ns.Refresh()
end

-- The five hidden rooms (three Hexmasks, the locked room, one empty).
-- run.rooms[name] = "Fiery Hexmask" / "locked" / "opened" / "empty".
local HIDDEN = {}
for _, c in ipairs(CHAMBERS) do if c.spot then HIDDEN[#HIDDEN + 1] = c end end
local SPOT_RANGE = 0.04 -- map fraction: this close to a hidden room = that room

local function NearestHidden(x, y) -- x, y as map fractions (0..1)
    local best, bestD
    for _, c in ipairs(HIDDEN) do
        local d = math.sqrt((x - c.spot[1] / 100) ^ 2 + (y - c.spot[2] / 100) ^ 2)
        if not bestD or d < bestD then best, bestD = c, d end
    end
    if bestD and bestD <= SPOT_RANGE then return best end
end

-- Only ONE room per run is the locked room, and a room where you took a mask
-- never is. Returns true if this room was marked.
local function MarkLocked(room, why)
    if not room then return false end
    run.rooms = run.rooms or {}
    for name, state in pairs(run.rooms) do
        if state == "locked" then return name == room.name end -- already known
    end
    local state = run.rooms[room.name]
    if state and state ~= "empty" then return false end -- a mask was taken here
    run.rooms[room.name] = "locked"
    TW.Log("MAZE", "%s is this run's locked room (%s)", room.name, why)
    return true
end

local function HiddenHere()
    local p = C_Map.GetPlayerMapPosition(MAZE_MAP, "player")
    return p and NearestHidden(p.x, p.y)
end

local function MaskFound(m, how)
    if run.masks[m.key] then return end
    local room = HiddenHere()
    if room then
        run.rooms = run.rooms or {}
        run.rooms[room.name] = m.name
    end
    local c = room or CurrentChamber()
    run.masks[m.key] = c and c.name or "?"
    if c then run.spots[c.name] = m.name end
    TW.Log("MAZE", "%s found in %s (%s)", m.name, c and c.name or "an unknown chamber", how)
    local n = 0
    for _ in pairs(run.masks) do n = n + 1 end
    Print(("%s found (%d/3)%s"):format(m.name, n, n == 3 and " - all three: Happy Hexmask Collector!" or ""))
    ns.Refresh()
end

local function MaskByName(text)
    if type(text) ~= "string" then return end
    local t = text:lower()
    for _, m in ipairs(MASKS) do
        if t:find(m.name:lower(), 1, true) then return m end
    end
end

-- A mask's power on a button (zone ability / extra action): its name or the mask's.
local function MaskByAbility(text)
    if type(text) ~= "string" then return end
    local m = MaskByName(text)
    if m then return m end
    local t = text:lower()
    for _, x in ipairs(MASKS) do
        if t == x.what:lower() then return x end
    end
end

---------------------------------------------------------------------------
-- Watching the game
---------------------------------------------------------------------------
-- Scenario objectives: log every one; completing one while in a chamber
-- completes that chamber (to be confirmed from the logs).
local criteriaDone = {}
local function ScanScenario()
    if not (C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo) then return end
    local step = Safe(C_ScenarioInfo.GetScenarioStepInfo)
    if type(step) == "table" and Readable(step.title) then Note("step:" .. tostring(step.title), "scenario step: %s", tostring(step.title)) end
    local count = type(step) == "table" and Readable(step.numCriteria) and step.numCriteria or 0
    for i = 1, count do
        local ok, c = pcall(C_ScenarioInfo.GetCriteriaInfo, i)
        if ok and type(c) == "table" and Readable(c.description) then
            local key = tostring(c.description)
            Note("crit:" .. key, "objective: %s (%s/%s)", key, tostring(c.quantity), tostring(c.totalQuantity))
            if Readable(c.completed) and c.completed and not criteriaDone[key] then
                criteriaDone[key] = true
                local here = CurrentChamber()
                TW.Log("MAZE", "objective done: %s (in %s)", key, here and here.name or "?")
                -- An objective naming a chamber completes that chamber; else the one you're in.
                local named = byNorm[Norm(key)]
                for _, ch in ipairs(CHAMBERS) do
                    if key:lower():find(Norm(ch.name), 1, true) then named = ch end
                end
                MarkChamber(named or here, "done", "objective: " .. key)
            end
        end
    end
end

-- The key: in your bags = you have it; gone again after that = the door was opened.
local function CheckKey()
    local count = (C_Item and C_Item.GetItemCount and Safe(C_Item.GetItemCount, KEY_NAME))
        or (GetItemCount and Safe(GetItemCount, KEY_NAME)) or 0
    if count > 0 then
        if not run.keyInBags then
            run.keyInBags, run.hasKey = true, true
            TW.Log("MAZE", "%s is in your bags", KEY_NAME)
            if run.door and not run.doorOpened then Print("you have the |cffffd100key|r - the arrow can take you to the locked door (/tw maze door).") end
            ns.Refresh()
        end
    elseif run.keyInBags and not run.doorOpened then
        run.doorOpened = true
        TW.Log("MAZE", "%s used - locked door opened", KEY_NAME)
        Print("locked room |cff33ff33opened|r.")
        ns.Refresh()
    end
end

-- Other places a mask can show: its item in your bags, its power on a zone-ability or
-- extra action button. Every button seen is logged once per run to learn what the game uses.
local function SpellName(id)
    if not id then return nil end
    local n = C_Spell and C_Spell.GetSpellName and Safe(C_Spell.GetSpellName, id)
    return type(n) == "string" and n or nil
end

local function MaskSources()
    local found = {}
    for _, m in ipairs(MASKS) do
        local n = (C_Item and C_Item.GetItemCount and Safe(C_Item.GetItemCount, m.name)) or 0
        if n > 0 then found[#found + 1] = { m = m, how = "item in your bags" } end
    end
    if C_ZoneAbility and C_ZoneAbility.GetActiveAbilities then
        local list = Safe(C_ZoneAbility.GetActiveAbilities)
        for _, z in ipairs(type(list) == "table" and list or {}) do
            local name = SpellName(z.spellID)
            Note("zoneab:" .. tostring(z.spellID), "zone ability: %s (spell %s)", tostring(name), tostring(z.spellID))
            local m = MaskByAbility(name)
            if m then found[#found + 1] = { m = m, how = "zone ability: " .. name } end
        end
    end
    if HasExtraActionBar and Safe(HasExtraActionBar) and GetActionInfo then
        local slot = ExtraActionButton1 and ExtraActionButton1.action
        local ok, kind, id = false, nil, nil
        if slot then ok, kind, id = pcall(GetActionInfo, slot) end
        if not ok or not Readable(kind) or not Readable(id) then kind, id = nil, nil end
        local name = kind == "spell" and SpellName(id) or nil
        Note("extra:" .. tostring(id), "extra action button: %s %s (%s)", tostring(kind), tostring(id), tostring(name))
        local m = MaskByAbility(name)
        if m then found[#found + 1] = { m = m, how = "extra action: " .. name } end
    end
    return found
end

local function CheckMaskSources()
    for _, f in ipairs(MaskSources()) do MaskFound(f.m, f.how) end
end

-- Standing inside a Loa-sealed room (at its spot): it's open for you from now on.
-- The locked room holds several Mislaid Curiosities, visible on the map
-- through the closed door. 3+ curiosities (from TippWorks-Curios' list) inside
-- an unresolved hidden room = that's the locked room, before its door is seen.
local LOCKED_CLUSTER = 3
local function CheckCuriosityCluster()
    local cr = TippWorksCuriosDB and TippWorksCuriosDB.curioRun
    if type(cr) ~= "table" or type(cr.items) ~= "table" then return end
    run.rooms = run.rooms or {}
    for _, c in ipairs(HIDDEN) do
        if not run.rooms[c.name] then
            local n = 0
            for _, it in pairs(cr.items) do
                if type(it) == "table" and it.map == MAZE_MAP and it.kind ~= "Dundun" and type(it.x) == "number"
                    and math.sqrt((it.x - c.spot[1] / 100) ^ 2 + (it.y - c.spot[2] / 100) ^ 2) <= SPOT_RANGE then
                    n = n + 1
                end
            end
            if n >= LOCKED_CLUSTER and MarkLocked(c, n .. " curiosities behind one door") then
                Print(("|cffffd100%s|r looks like this run's locked room (%d curiosities inside) - key icon on the map; find the Keeper of the Key."):format(c.name, n))
                ns.Refresh()
            end
        end
    end
end

local function CheckSealedRooms()
    local p = C_Map.GetPlayerMapPosition(MAZE_MAP, "player")
    if not p then return end
    for i, r in ipairs(SEALED) do
        if not db.rooms[i] and math.sqrt((p.x - r[4] / 100) ^ 2 + (p.y - r[5] / 100) ^ 2) <= ROOM_ENTER_RANGE then
            db.rooms[i] = time()
            TW.Log("MAZE", "%s sealed room (%s) entered - padlock removed", r[1], r[3])
            Print(("%s sealed room (%s) opened."):format(r[1], r[3]))
            ns.Refresh()
        end
    end
end

local function ScanAuras()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    local keyNow, secret = nil, 0
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
            if not ok or type(a) ~= "table" then break end
            if not Readable(a.name) then secret = secret + 1 end
            if Readable(a.name) and type(a.name) == "string" then
                local lower = a.name:lower()
                local m = MaskByName(a.name)
                if m then MaskFound(m, "buff: " .. a.name)
                elseif lower:find("mask", 1, true) or lower:find("hex", 1, true) then
                    Note("aura:" .. a.name, "buff on you: %s (spell %s)", a.name, tostring(a.spellId))
                end
                -- The key can be a buff instead of a bag item.
                if lower:find("key", 1, true) then
                    keyNow = a.name
                    Note("keyaura:" .. a.name, "key buff on you: %s (spell %s)", a.name, tostring(a.spellId))
                end
            end
        end
    end
    if secret > 0 then Note("aurasecret", "%d of your auras have names hidden from addons", secret) end
    if keyNow and not run.keyBuff then
        run.keyBuff, run.hasKey = true, true
        Print("you have the |cffffd100key|r (" .. keyNow .. ")" .. (run.door and " - head for the locked door." or " - now find the locked door."))
        ns.Refresh()
    elseif not keyNow and run.keyBuff and not run.doorOpened then
        -- The key buff is gone: it was used on the door.
        run.keyBuff, run.doorOpened = nil, true
        TW.Log("MAZE", "key buff gone - locked door opened")
        Print("locked room |cff33ff33opened|r.")
        ns.Refresh()
    end
end

local function ScanMarkers()
    if not C_VignetteInfo then return end
    local map = C_Map.GetBestMapForUnit("player")
    for _, guid in ipairs(C_VignetteInfo.GetVignettes() or {}) do
        local info = C_VignetteInfo.GetVignetteInfo(guid)
        if type(info) == "table" and Readable(info.name) and type(info.name) == "string" then
            local name = info.name
            local pos = map and Safe(C_VignetteInfo.GetVignettePosition, guid, map)
            local where = pos and ("%.1f, %.1f"):format(pos.x * 100, pos.y * 100) or "no position"
            Note("vig:" .. name, "marker: %s | atlas %s | %s", name, tostring(info.atlasName), where)
            local guidStr = Safe(function() return info.objectGUID end)
            local npc = type(guidStr) == "string" and tonumber(guidStr:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
            if (npc == KEEPER_NPC or name:find("Keeper of the Key", 1, true)) and not run.keeperSeen then
                run.keeperSeen = true
                Print("|cffffd100Keeper of the Key|r is on the map (" .. where .. ") - it drops the key for the locked room.")
            end
            local lower = name:lower()
            local message = name:find('^"') or lower:find("unlocked", 1, true) or lower:find("seal", 1, true)
                or lower:find("path", 1, true)
            if not message and (lower:find("locked", 1, true) or lower:find("door", 1, true)) and not run.lockedSeen then
                run.lockedSeen = true
                local c = CurrentChamber()
                if c and c.special then run.spots[c.name] = "Locked room" end
                -- Where the door is on the Labyrinth map: the marker's own position,
                -- else the mask/locked-room spot of the chamber you're in.
                local mp = Safe(C_VignetteInfo.GetVignettePosition, guid, MAZE_MAP)
                if mp and Readable(mp.x) then run.door = { x = mp.x * 100, y = mp.y * 100 }
                elseif c and c.spot then run.door = { x = c.spot[1], y = c.spot[2] } end
                MarkLocked(run.door and NearestHidden(run.door.x / 100, run.door.y / 100), "its door marker")
                TW.Log("MAZE", "locked room marker: %s in %s (%s)", name, c and c.name or "?", where)
                if not run.doorOpened then
                    Print("|cffffd100Locked door|r found" .. (c and (" in " .. c.name) or "") .. (run.hasKey and
                        " - you have the key, go open it!" or " - marked with a key icon on the map until you open it."))
                end
                ns.Refresh()
            end
        end
    end
end

-- Labyrinth quests: everything your quest log files under the "The Labyrinth
-- of Kindo'jan" heading (however long ago, wherever you are now), plus any
-- quest picked up while inside. Shown with their objectives; a click tracks it
-- and points the way (the game's own next-step waypoint).
local logQuests = {}  -- questID -> title, from the quest log heading
local loggedQuest = {} -- questID -> true once written to /tw log
local function ScanQuestLog()
    wipe(logQuests)
    local n = Safe(C_QuestLog.GetNumQuestLogEntries) or 0
    local header
    for i = 1, n do
        local info = Safe(C_QuestLog.GetInfo, i)
        if type(info) == "table" and Readable(info.title) then
            if info.isHeader then
                header = info.title
            elseif header and (header:find("Labyrinth", 1, true) or header:find("Kindo", 1, true)) and Readable(info.questID) then
                logQuests[info.questID] = info.title
                if not loggedQuest[info.questID] then
                    loggedQuest[info.questID] = true
                    TW.Log("MAZE", "Labyrinth quest in your log: %s (%d)", info.title, info.questID)
                end
            end
        end
    end
end

local function AllQuests()
    local all = {}
    for id, t in pairs(logQuests) do all[id] = t end
    for id, t in pairs(run and run.quests or {}) do
        if Safe(C_QuestLog.GetLogIndexForQuestID, id) then all[id] = all[id] or t end -- still in your log
    end
    return all
end

local function QuestPicked(questID)
    if not Readable(questID) or not run then return end
    local title = Safe(C_QuestLog.GetTitleForQuestID, questID) or ("quest " .. questID)
    run.quests[questID] = title
    TW.Log("MAZE", "quest picked up: %s (%d) in %s", title, questID, (CurrentChamber() or {}).name or "?")
    Print("quest picked up: |cffffd100" .. title .. "|r - click it in the Labyrinth window for where to go.")
    ns.Refresh()
end

-- Arrow to a chamber's mask/locked-room spot. Map waypoints don't work inside
-- delves, so it borrows TippWorks-Curios' guide arrow (or TomTom's).
function ns.GuideToSpot(c)
    if not c.spot then Print(c.name .. " isn't one of the mask/locked-room spots. Right-click marks it done.") return end
    ns.GuideTo(c.name .. " - mask/locked-room spot", c.spot[1], c.spot[2])
end

local function QuestText(questID)
    local lines = {}
    local objs = Safe(C_QuestLog.GetQuestObjectives, questID)
    for _, o in ipairs(type(objs) == "table" and objs or {}) do
        if Readable(o.text) then lines[#lines + 1] = (o.finished and "|cff33ff33[x]|r " or "[ ] ") .. o.text end
    end
    return lines
end

local function GuideQuest(questID)
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then pcall(C_SuperTrack.SetSuperTrackedQuestID, questID) end
    local title = AllQuests()[questID] or tostring(questID)
    Print("|cffffd100" .. title .. "|r - tracked, follow the quest arrow.")
    for _, l in ipairs(QuestText(questID)) do Print("  " .. l) end
    local wp = C_QuestLog.GetNextWaypointText and Safe(C_QuestLog.GetNextWaypointText, questID)
    if type(wp) == "string" and wp ~= "" then Print("  Next: " .. wp) end
    if C_QuestLog.GetNextWaypoint then
        local ok, map, x, y = pcall(C_QuestLog.GetNextWaypoint, questID)
        if ok and Readable(map) and map and Readable(x) and x then
            local info = C_Map.GetMapInfo(map)
            Print(("  Go to: %s %.1f, %.1f"):format(info and info.name or ("map " .. map), x * 100, y * 100))
            if C_Map.CanSetUserWaypointOnMap(map) then
                C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x, y))
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            end
            if TomTom and TomTom.AddWaypoint then pcall(TomTom.AddWaypoint, TomTom, map, x, y, { title = title }) end
        end
    end
    if C_QuestLog.IsComplete and Safe(C_QuestLog.IsComplete, questID) then
        Print("  |cff33ff33Complete|r - hand it in (the arrow leads to the turn-in).")
    end
end

---------------------------------------------------------------------------
-- Sturdy Chests: looted once per WARBAND (a chest opened on one character
-- can't be looted on another), so warband.chests[n] = time looted, account-wide.
---------------------------------------------------------------------------
local function ChestsIn(chamber)
    local got, total = 0, 0
    for _, ch in ipairs(CHESTS) do
        if ch[2] == chamber then
            total = total + 1
            if warband.chests[ch[1]] then got = got + 1 end
        end
    end
    return got, total
end

local function ChestLooted(ch, how)
    if warband.chests[ch[1]] then return end
    warband.chests[ch[1]] = time()
    TW.Log("MAZE", "Sturdy Chest %d (%s) looted (%s)", ch[1], ch[2], how)
    Print(("Sturdy Chest %d (%s) looted."):format(ch[1], ch[2]))
    ns.Refresh()
end

-- Loot opened close to a chest's spot: that chest. Every loot position is
-- logged so the range can be checked against a real run.
local function OnLoot()
    local p = C_Map.GetPlayerMapPosition(MAZE_MAP, "player")
    if not p then
        Note("lootnopos", "loot opened, but no position on map %d (you're on map %s)", MAZE_MAP,
            tostring(C_Map.GetBestMapForUnit("player")))
        return
    end
    local best, bestD
    for _, ch in ipairs(CHESTS) do
        local d = math.sqrt((p.x - ch[3] / 100) ^ 2 + (p.y - ch[4] / 100) ^ 2)
        if not bestD or d < bestD then best, bestD = ch, d end
    end
    TW.Log("MAZE", "loot opened at %.1f, %.1f - nearest Sturdy Chest %d (%s) %.1f%% away", p.x * 100, p.y * 100,
        best[1], best[2], bestD * 100)
    if bestD <= CHEST_LOOT_RANGE then
        -- What this chest gave: the loot window's items, kept for its tooltip.
        local got = {}
        for slot = 1, (Safe(GetNumLootItems) or 0) do
            local ok, _, name, qty = pcall(GetLootSlotInfo, slot)
            if ok and Readable(name) and type(name) == "string" and name ~= "" then
                got[#got + 1] = (Readable(qty) and qty and qty > 1) and (name .. " x" .. qty) or name
            end
        end
        if #got > 0 then
            warband.chestLoot[best[1]] = got
            TW.Log("MAZE", "Sturdy Chest %d (%s) gave: %s", best[1], best[2], table.concat(got, ", "))
        end
        ChestLooted(best, "loot opened beside it")
    end
end

-- Arrow to a spot on the Labyrinth map. Map waypoints don't work inside
-- delves, so it borrows TippWorks-Curios' guide arrow (or TomTom's).
function ns.GuideTo(label, x, y)
    if TW.GuideArrow then
        TW.GuideArrow(MAZE_MAP, x / 100, y / 100, label)
    elseif TomTom and TomTom.AddWaypoint then
        pcall(TomTom.AddWaypoint, TomTom, MAZE_MAP, x / 100, y / 100, { title = label, crazy = true })
        Print("TomTom arrow set: " .. label)
    else
        Print(("%s: %.1f, %.1f (enable TippWorks-Curios or TomTom for an arrow)"):format(label, x, y))
    end
end

-- Gold pins on the Labyrinth map for chests you haven't looted.
local overlay, pins = nil, {}
function ns.DrawPins()
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local canvas = WorldMapFrame.ScrollContainer.Child
    if not overlay then
        overlay = CreateFrame("Frame", nil, canvas)
        overlay:SetAllPoints(canvas)
        overlay:SetFrameLevel(canvas:GetFrameLevel() + 2050)
    end
    for _, p in ipairs(pins) do p:Hide() end
    if WorldMapFrame:GetMapID() ~= MAZE_MAP or db.hidePins then return end
    local w, h = canvas:GetSize()
    local size = math.max(12, (w or 0) / 55)
    local n = 0
    local function Pin(x, y, title, line, atlas, texture)
        n = n + 1
        local p = pins[n]
        if not p then
            p = CreateFrame("Frame", nil, overlay)
            p.tex = p:CreateTexture(nil, "OVERLAY")
            p.tex:SetAllPoints()
            p:EnableMouse(true)
            p:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.title)
                GameTooltip:AddLine(self.line, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            p:SetScript("OnLeave", GameTooltip_Hide)
            pins[n] = p
        end
        if atlas then p.tex:SetAtlas(atlas) else p.tex:SetTexture(texture) end
        p.title, p.line = title, line
        p:SetSize(size, size)
        p:ClearAllPoints()
        p:SetPoint("CENTER", overlay, "TOPLEFT", x / 100 * w, -y / 100 * h)
        p:Show()
    end
    for _, ch in ipairs(CHESTS) do
        if not warband.chests[ch[1]] then
            Pin(ch[3], ch[4], ("Sturdy Chest %d"):format(ch[1]), ("%s  %.1f, %.1f"):format(ch[2], ch[3], ch[4]), "VignetteLoot")
        end
    end
    -- The five hidden rooms: padlock until resolved (mask taken, found empty);
    -- the locked room gets the key icon until it's opened.
    for _, c in ipairs(HIDDEN) do
        local state = run and run.rooms and run.rooms[c.name]
        if not state and MaskIconsShown() then
            Pin(c.spot[1], c.spot[2], c.name .. " - possible Hexmask",
                "One of the five spots: 3 hold a Hexmask, 1 is the locked room, 1 is empty. Right-click it in the Labyrinth window if it's empty.",
                nil, ICON_MASK)
        elseif state == "locked" and not run.doorOpened and not run.door then
            Pin(c.spot[1], c.spot[2], c.name .. " - locked room",
                run.hasKey and "You have the Archaic Amani Key - open it." or "Needs the Archaic Amani Key from the Keeper of the Key.",
                nil, ICON_KEY)
        end
    end
    -- Locked door this run: key icon until it's opened.
    if run and run.door and not run.doorOpened then
        Pin(run.door.x, run.door.y, "Locked door",
            run.hasKey and "You have the Archaic Amani Key - open it." or "Needs the Archaic Amani Key from the Keeper of the Key.",
            nil, ICON_KEY)
    end
    -- Loa-sealed rooms: padlock until you've been inside. Off by default - the
    -- game already marks sealed doors itself (/tw maze padlocks turns them on).
    for i, r in ipairs(SEALED) do
        if db.showPadlocks and not db.rooms[i] then
            Pin(r[4], r[5], r[1] .. " sealed room", ("%s - opens at Labyrinth Journey rank %d."):format(r[3], r[2]), nil, ICON_LOCK)
        end
    end
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
    b.left = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.left:SetPoint("LEFT", 4, 0)
    b.right = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.right:SetPoint("RIGHT", -4, 0)
    b:SetScript("OnClick", function(self, btn)
        local e = self.entry
        if not e then return end
        if e.chamber and btn ~= "RightButton" then
            ns.GuideToSpot(e.chamber)
        elseif e.chamber then
            -- Manual fix-up: not done -> done -> not done.
            run.chambers[e.chamber.name] = run.chambers[e.chamber.name] ~= "done" and "done" or nil
            TW.Log("MAZE", "%s marked %s by hand", e.chamber.name, run.chambers[e.chamber.name] or "not done")
            ns.Refresh()
        elseif e.mask then
            if run.masks[e.mask.key] then run.masks[e.mask.key] = nil else MaskFound(e.mask, "marked by hand") end
            ns.Refresh()
        elseif e.quest then
            GuideQuest(e.quest)
        elseif e.chest and btn == "RightButton" then
            if warband.chests[e.chest[1]] then warband.chests[e.chest[1]] = nil; ns.Refresh()
            else ChestLooted(e.chest, "marked by hand") end
        elseif e.chest then
            ns.GuideTo(("Sturdy Chest %d (%s)"):format(e.chest[1], e.chest[2]), e.chest[3], e.chest[4])
        elseif e.sealed and btn == "RightButton" then
            db.rooms[e.room] = (not db.rooms[e.room]) and time() or nil
            TW.Log("MAZE", "%s sealed room (%s) marked %s by hand", e.sealed[1], e.sealed[3], db.rooms[e.room] and "opened" or "locked")
            ns.Refresh()
        elseif e.hidden and btn == "RightButton" then
            run.rooms = run.rooms or {}
            run.rooms[e.hidden.name] = (run.rooms[e.hidden.name] == nil) and "empty" or nil
            TW.Log("MAZE", "hidden room %s marked %s by hand", e.hidden.name, run.rooms[e.hidden.name] or "not checked")
            ns.Refresh()
        elseif e.hidden then
            ns.GuideTo(e.hidden.name .. " - hidden room", e.hidden.spot[1], e.hidden.spot[2])
        elseif e.door and btn == "RightButton" then
            run.doorOpened = not run.doorOpened or nil
            TW.Log("MAZE", "locked door marked %s by hand", run.doorOpened and "opened" or "not opened")
            ns.Refresh()
        elseif e.door then
            if run.door then ns.GuideTo("Locked door", run.door.x, run.door.y)
            else Print("the locked door hasn't been found yet this run (/tw maze door marks it where you stand).") end
        elseif e.sealed then
            ns.GuideTo(e.sealed[1] .. " sealed room (" .. e.sealed[3] .. ")", e.sealed[4], e.sealed[5])
        end
    end)
    b:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e or not e.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for i, l in ipairs(e.tip()) do
            if i == 1 then GameTooltip:AddLine(l) else GameTooltip:AddLine(l, 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = b
    return b
end

local function CreateWindow()
    win = TW.CreateWindow({ name = "TippWorksLabyrinthFrame", title = "Labyrinth of Kindo'jan", version = ns.VERSION,
        width = WIDTH, db = db, keepOnEscape = true, onTab = function() ns.Refresh() end, tabs = {
            { key = "run", label = "This run", title = "Labyrinth of Kindo'jan" },
            { key = "chests", label = "Chests", title = "Labyrinth Chests" },
        } })
    win.footer = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.footer:SetPoint("BOTTOMLEFT", 12, 10)
    win.footer:SetWidth(WIDTH - 24)
    win.footer:SetJustifyH("LEFT")
    win:SetScript("OnShow", function() ns.Refresh() end)
    win:SelectTab(db.tab == "chests" and "chests" or "run")
    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", ns.DrawPins)
        if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", ns.DrawPins) end
    end
end

local function Header(text) return { header = text } end

local function ChestList()
    local list = {}
    local got = 0
    for _ in pairs(warband.chests) do got = got + 1 end
    list[#list + 1] = Header(("Sturdy Chests  %d/20  |cff888888(once per warband)|r"):format(got))
    for _, ch in ipairs(CHESTS) do
        list[#list + 1] = { chest = ch,
            left = ("  %d. %s"):format(ch[1], ch[2]),
            right = warband.chests[ch[1]] and "|cff33ff33looted|r" or ("|cffffd100%.1f, %.1f|r"):format(ch[3], ch[4]),
            tip = function()
                local t = { ("Sturdy Chest %d"):format(ch[1]), ("%s  %.1f, %.1f"):format(ch[2], ch[3], ch[4]) }
                local got = warband.chestLoot[ch[1]]
                if got then
                    t[#t + 1] = "You got: " .. table.concat(got, ", ")
                else
                    t[#t + 1] = "Reputation, Journey progress, Voidlight Marl, Corrosive Coins, Undercoin - and maybe one of: " .. CHEST_UNIQUES
                end
                t[#t + 1] = "Left-click: guide arrow  |  Right-click: mark looted / not looted"
                return t
            end }
    end
    list[#list + 1] = Header("Loa-sealed rooms  |cff888888(2-3 more chests each)|r")
    for i, r in ipairs(SEALED) do
        list[#list + 1] = { sealed = r, room = i,
            left = ("  %s seal - %s"):format(r[1], r[3]),
            right = db.rooms[i] and "|cff33ff33opened|r" or ("|cff888888Journey %d - locked|r"):format(r[2]),
            tip = function()
                local t = { r[1] .. " sealed room", ("%s  %.1f, %.1f"):format(r[3], r[4], r[5]),
                    ("Opens at Labyrinth Journey rank %d."):format(r[2]),
                    "Seal reward: " .. SEAL_REWARDS[r[1]] }
                local special = ROOM_REWARDS[r[1] .. "@" .. r[3]]
                if special then t[#t + 1] = "In this room: " .. special end
                t[#t + 1] = "Left-click: guide arrow  |  Right-click: mark opened / locked"
                return t
            end }
    end
    return list, "|cff888888Flooded Chamber: swim under the two waterfalls on the east side of the Central Chamber, "
        .. "melt the ice wall with any Fire damage (the Fiery Hexmask works) - 5 more Sturdy Chests.|r"
end

local function RunList()
    local list = {}
    local here = CurrentChamber()
    list[#list + 1] = Header(("Chambers  %d/9  |cff888888%s|r"):format(DoneCount(),
        InLabyrinth() and "(rewards at 3, 6, 9)" or "(your last run)"))
    for _, c in ipairs(CHAMBERS) do
        local st = run.chambers[c.name]
        list[#list + 1] = { chamber = c,
            left = (here == c and "|cffffffff> " or "  ") .. c.name .. (c.special and " |cff888888*|r" or ""),
            right = (function()
                local got, total = ChestsIn(c.name)
                local chests = total > 0 and ("|cff888888chests %d/%d|r  "):format(got, total) or ""
                return chests .. (st == "done" and "|cff33ff33done|r" or st == "here" and "|cffffd100in progress|r" or "|cff888888-|r")
            end)(),
            tip = function()
                local t = { c.name, "Where: " .. c.where }
                if c.special then t[#t + 1] = "* Can hold a Hexmask or the locked room." end
                if c.name == "The Cave Towers" then
                    t[#t + 1] = "Bonus objective: find 5 Loa Statuettes hidden here for the Ruined Amani Ritual Urn (decor)."
                end
                if c.spot then t[#t + 1] = ("Mask/locked-room spot: %.1f, %.1f - left-click for the arrow"):format(c.spot[1], c.spot[2]) end
                t[#t + 1] = "Right-click: mark done / not done"
                return t
            end }
    end
    local found = 0
    for _ in pairs(run.masks) do found = found + 1 end
    list[#list + 1] = Header(("Hexmasks  %d/3"):format(found))
    for _, m in ipairs(MASKS) do
        local at = run.masks[m.key]
        list[#list + 1] = { mask = m, left = "  " .. m.name,
            right = at and ("|cff33ff33" .. at .. "|r") or "|cff888888not found|r",
            tip = function() return { m.name, m.what, "Spawns at one of the * chambers (Journey rank 2+).",
                "All three in one run: Happy Hexmask Collector.", "Click: mark found / not found" } end }
    end
    local spots = {}
    for _, c in ipairs(CHAMBERS) do if c.special and run.spots[c.name] then spots[#spots + 1] = c.name .. ": " .. run.spots[c.name] end end
    local resolved = 0
    for _, c in ipairs(HIDDEN) do if run.rooms and run.rooms[c.name] then resolved = resolved + 1 end end
    list[#list + 1] = Header(("Hidden rooms  %d/5 checked"):format(resolved))
    for _, c in ipairs(HIDDEN) do
        local state = run.rooms and run.rooms[c.name]
        local text = not state and "|cff888888possible mask|r"
            or state == "locked" and (run.doorOpened and "|cff33ff33locked room - opened|r" or "|cffffd100locked room - key|r")
            or state == "empty" and "|cff888888empty|r"
            or ("|cff33ff33" .. state .. "|r")
        list[#list + 1] = { hidden = c, left = "  " .. c.name, right = text,
            tip = function() return { c.name .. " - hidden room", ("%.1f, %.1f"):format(c.spot[1], c.spot[2]),
                "Holds a Hexmask, the locked room, or nothing this run.",
                "Left-click: guide arrow  |  Right-click: mark empty / not checked" } end }
    end
    list[#list + 1] = Header("Locked room" .. (run.keeperSeen and "  |cffffd100Keeper on map|r" or ""))
    list[#list + 1] = { door = true,
        left = "  Door" .. (run.door and ((" %.1f, %.1f"):format(run.door.x, run.door.y)) or " - not found yet"),
        right = run.doorOpened and "|cff33ff33opened|r" or run.hasKey and "|cffffd100you have the key|r"
            or run.keyHolder and ("|cffffd100" .. run.keyHolder .. " has the key|r") or "|cff888888no key yet|r",
        tip = function()
            local t = { "Locked room", "Kill the Keeper of the Key and loot the Archaic Amani Key from him.",
                "He hides in one of the chambers, often on a lower floor - in each chamber press Find the Keeper "
                    .. "(Options > Keybindings > AddOns) before moving on. The nameplate (Ctrl+V) shows him through walls.",
                "The door shows as a key icon on the map until it's opened." }
            for _, k in ipairs(warband.keeper or {}) do
                t[#t + 1] = ("Found before: %s (%.1f, %.1f)"):format(k.chamber or "?", k.x or 0, k.y or 0)
            end
            for _, l in ipairs({
                "Left-click: arrow to the door  |  Right-click: mark opened / not opened",
                "/tw maze door: mark the door where you're standing" }) do t[#t + 1] = l end
            return t
        end }
    local qn = 0
    for id, title in pairs(AllQuests()) do
        if qn == 0 then list[#list + 1] = Header("Quests from the Labyrinth") end
        qn = qn + 1
        local done = Safe(C_QuestLog.IsComplete, id)
        list[#list + 1] = { quest = id, left = "  " .. title,
            right = done and "|cff33ff33turn in|r" or "|cffffd100click: where to go|r",
            tip = function()
                local t = { title }
                for _, l in ipairs(QuestText(id)) do t[#t + 1] = l end
                t[#t + 1] = "Click: track it and point the way"
                return t
            end }
    end
    return list, #spots > 0 and ("|cff888888" .. table.concat(spots, "  |  ") .. "|r")
        or "|cff888888* = a spot that can hold a Hexmask or the locked room|r"
end

function ns.Refresh()
    if not win or not run or not win:IsShown() then return end
    ns.DrawPins()
    local list, footer
    if db.tab == "chests" then list, footer = ChestList() else list, footer = RunList() end
    for i, e in ipairs(list) do
        local b = rows[i] or Row(i)
        b.entry = (not e.header) and e or nil
        b.left:SetText(e.header and ("|cffffd100" .. e.header .. "|r") or e.left)
        b.right:SetText(e.right or "")
        b:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide(); rows[i].entry = nil end
    win.footer:SetText(footer)
    win:SetHeight(-win.top + #list * ROW_H + 30 + (tonumber(win.footer:GetStringHeight()) or 12))
end

---------------------------------------------------------------------------
-- TippWorks registration, /tw maze, saved data
---------------------------------------------------------------------------
local function Toggle() if win then win:Toggle() end end

local function Summary(tt)
    if run and InLabyrinth() then
        local found = 0
        for _ in pairs(run.masks) do found = found + 1 end
        tt:AddLine(("Labyrinth: %d/9 chambers, %d/3 Hexmasks"):format(DoneCount(), found), 1, 1, 1)
    end
end

local module
local function Command(rest)
    local sub = (rest:match("^(%S*)") or ""):lower()
    if sub == "" or sub == "show" or sub == "toggle" then Toggle()
    elseif sub == "reset" then NewRun("reset by hand"); ns.Refresh(); Print("run cleared.")
    elseif sub == "spots" then
        for _, c in ipairs(CHAMBERS) do
            if c.spot then
                Print(("  %s: %.1f, %.1f%s"):format(c.name, c.spot[1], c.spot[2],
                    run and run.spots[c.name] and (" - " .. run.spots[c.name]) or ""))
            end
        end
    elseif sub == "door" then
        local p = C_Map.GetPlayerMapPosition(MAZE_MAP, "player")
        if not p or not InLabyrinth() then Print("stand at the locked door inside the Labyrinth, then try again.") return end
        run.door, run.lockedSeen, run.doorOpened = { x = p.x * 100, y = p.y * 100 }, true, nil
        MarkLocked(NearestHidden(p.x, p.y), "door marked by hand")
        TW.Log("MAZE", "locked door marked by hand at %.1f, %.1f", p.x * 100, p.y * 100)
        Print(("locked door marked at %.1f, %.1f - key icon on the map until it's opened."):format(p.x * 100, p.y * 100))
        ns.Refresh()
    elseif sub == "keeper" then
        Print("Find the Keeper: Options > Keybindings > AddOns > Tippenhauer Works - Labyrinth,")
        Print("or a macro with: /click TippWorksLabyrinthKeeperButton  - press it in each chamber before moving on.")
        for _, k in ipairs(warband.keeper or {}) do
            Print(("  found before: %s (%.1f, %.1f)"):format(k.chamber or "?", k.x or 0, k.y or 0))
        end
    elseif sub == "chests" then
        if win then win:SelectTab("chests"); win:Show() end
    elseif sub == "masks" then
        db.maskIcons = not MaskIconsShown()
        Print("mask icons on the five hidden rooms " .. (db.maskIcons and "shown." or "hidden."))
        ns.DrawPins()
    elseif sub == "padlocks" then
        db.showPadlocks = not db.showPadlocks or nil
        Print("padlocks on the Loa-sealed rooms " .. (db.showPadlocks and "shown." or "hidden (the game marks sealed doors itself)."))
        ns.DrawPins()
    elseif sub == "pins" then
        db.hidePins = not db.hidePins or nil
        Print("chest pins on the Labyrinth map " .. (db.hidePins and "hidden." or "shown."))
        ns.DrawPins()
    elseif sub == "probe" then
        -- What the game shows that could be a mask (also in /tw log).
        local function Out(fmt, ...) local t = fmt:format(...); Print(t); TW.Log("MAZE", "probe: %s", t) end
        local names, secret = {}, 0
        for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
            for i = 1, 40 do
                local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
                if not ok or type(a) ~= "table" then break end
                if Readable(a.name) then names[#names + 1] = tostring(a.name) .. " (" .. tostring(a.spellId) .. ")" else secret = secret + 1 end
            end
        end
        Out("your auras: %s%s", #names > 0 and table.concat(names, ", ") or "none readable", secret > 0 and (" + %d hidden"):format(secret) or "")
        local found = MaskSources()
        for _, f in ipairs(found) do Out("%s: %s", f.m.name, f.how) end
        if #found == 0 then Out("no mask item, zone ability or extra action button found") end
        local mine = {}
        for k, v in pairs(run.masks) do mine[#mine + 1] = k .. " in " .. v end
        Out("masks this run: %s", #mine > 0 and table.concat(mine, ", ") or "none")
    elseif sub == "where" then
        local c = CurrentChamber()
        Print(("sub-zone '%s', map '%s' -> chamber: %s"):format(tostring(Safe(GetSubZoneText)),
            tostring((C_Map.GetMapInfo(C_Map.GetBestMapForUnit("player") or 0) or {}).name), c and c.name or "not recognised"))
    else TW.ModuleHelp(module) end
end

module = TW.Register({
    key = "maze", aliases = { "labyrinth", "lab" },
    name = "Labyrinth of Kindo'jan", addon = ADDON, version = ns.VERSION,
    command = Command, toggle = Toggle, summary = Summary,
    help = {
        { "", "show/hide the Labyrinth window (opens by itself inside)" },
        { "where", "which chamber the addon thinks you're in" },
        { "probe", "show what the game reports that could be a Hexmask (auras, buttons, items)" },
        { "spots", "the five mask/locked-room spots with coordinates" },
        { "chests", "open the Chests tab (Sturdy Chests, sealed rooms)" },
        { "door", "mark the locked door where you're standing (key icon on the map)" },
        { "keeper", "how to find the Keeper of the Key (key binding / macro)" },
        { "pins", "show/hide the chest pins on the Labyrinth map" },
        { "masks", "show/hide the mask icons on the hidden rooms (hidden while HandyNotes_Midnight is loaded)" },
        { "padlocks", "show/hide padlocks on the Loa-sealed rooms (off by default)" },
        { "reset", "start a fresh run list" },
    },
})

function TippWorksLabyrinth_OnAddonCompartmentClick() Toggle() end
function TippWorksLabyrinth_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff" .. TW.COLOR .. "Tippenhauer Works|r - Labyrinth of Kindo'jan")
    Summary(GameTooltip)
    GameTooltip:AddLine("Click: show/hide  |  /tw maze help", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end
function TippWorksLabyrinth_OnAddonCompartmentLeave() GameTooltip:Hide() end

---------------------------------------------------------------------------
-- Find the Keeper: the game hides his name from addons in delves, so like
-- Dundun he's found with a macro - target him, skull him, ping him. A hidden
-- secure button run by a key binding (Bindings.xml) or /click.
---------------------------------------------------------------------------
local KEEPER_MACRO = "/cleartarget\n/tar Keeper of the Key\n/stopmacro [noexists]\n"
    .. "/tm [@target,exists,nodead] 0\n/tm [@target,exists,nodead] 8\n/ping [@target] Assist"

local function KeeperFound()
    if not UnitExists("target") or UnitIsDead("target") then
        Print("no Keeper of the Key in range here.")
        return
    end
    local p = C_Map.GetPlayerMapPosition(MAZE_MAP, "player")
    local c = CurrentChamber()
    local name = c and c.name or tostring(Safe(GetSubZoneText) or "?")
    TW.Log("MAZE", "Keeper of the Key targeted from %s (%.1f, %.1f)", name, p and p.x * 100 or 0, p and p.y * 100 or 0)
    Print(("|cffffd100Keeper of the Key|r found near %s - skull and ping on him. Turn on nameplates (Ctrl+V) to see him through walls."):format(name))
    if run and not run.keeperFound then
        run.keeperFound = true
        warband.keeper = warband.keeper or {}
        table.insert(warband.keeper, 1, { chamber = name, x = p and p.x * 100, y = p and p.y * 100, at = time() })
        while #warband.keeper > 5 do table.remove(warband.keeper) end
        ns.Refresh()
    end
end

local function InitKeeperButton()
    local b = CreateFrame("Button", "TippWorksLabyrinthKeeperButton", UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", KEEPER_MACRO)
    b:SetScript("PostClick", function(_, _, down)
        if (down and true or false) ~= GetCVarBool("ActionButtonUseKeyDown") then return end
        TW.Guard("maze keeper", KeeperFound)
    end)
    b:Hide()
end

BINDING_HEADER_TIPPWORKSLABYRINTH = "Tippenhauer Works - Labyrinth"
_G["BINDING_NAME_CLICK TippWorksLabyrinthKeeperButton:LeftButton"] = "Find the Keeper of the Key (target + skull + ping)"

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        TippWorksLabyrinthDB = TippWorksLabyrinthDB or {}
        db = TippWorksLabyrinthDB
        TippWorksLabyrinthAccountDB = TippWorksLabyrinthAccountDB or {}
        warband = TippWorksLabyrinthAccountDB
        warband.chests = warband.chests or {}
        warband.chestLoot = warband.chestLoot or {}
        -- Before 1.5.0 chests were saved per character: merge them into the warband list.
        -- Copied, not moved: after a /reload (no full restart) the warband file isn't saved yet.
        if db.chests or db.chestLoot then
            for n, t in pairs(db.chests or {}) do warband.chests[n] = warband.chests[n] or t end
            for n, l in pairs(db.chestLoot or {}) do warband.chestLoot[n] = warband.chestLoot[n] or l end
            TW.Log("MAZE", "chest list copied to the warband list")
        end
        db.rooms = db.rooms or {}
        run = db.run
        if not run then NewRun("first load") end
        -- Before 1.5.4 door-message markers could mark several locked rooms (and a
        -- key icon in the wrong place): a run with more than one is cleaned up.
        local lockedRooms = 0
        for _, st in pairs(run.rooms or {}) do if st == "locked" then lockedRooms = lockedRooms + 1 end end
        if lockedRooms > 1 then
            for name, st in pairs(run.rooms) do if st == "locked" then run.rooms[name] = nil end end
            run.door, run.lockedSeen = nil, nil
            TW.Log("MAZE", "cleared %d wrongly locked rooms and the door marker from an older version", lockedRooms)
        end
        -- First sighting (Oct 18, Rob and Terry): the Keeper was in Jan'alai's Refuge.
        if not warband.keeper then
            warband.keeper = { { chamber = "Jan'alai's Refuge", x = 22.2, y = 35.3, at = 1792363532 } }
        end
        InitKeeperButton()
        TW.Log("INFO", "TippWorks-Labyrinth v%s loaded", ns.VERSION)
        CreateWindow()
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
            "SCENARIO_CRITERIA_UPDATE", "SCENARIO_UPDATE", "UNIT_AURA", "QUEST_ACCEPTED", "QUEST_LOG_UPDATE", "QUEST_REMOVED",
            "CHAT_MSG_LOOT", "LOOT_OPENED", "BAG_UPDATE_DELAYED" }) do self:RegisterEvent(e) end
        C_Timer.NewTicker(1, function()
            -- Entering or leaving without a loading-screen event we caught (PLAYER_ENTERING_WORLD can come
            -- before the instance name is known).
            if InLabyrinth() ~= inside then TW.Guard("maze where", SetInside, InLabyrinth()) end
            if not inside then return end
            run.lastSeen = time()
            TW.Guard("maze scan", function()
                MarkChamber(CurrentChamber(), "here", "entered")
                CheckSealedRooms()
                CheckMaskSources()
                CheckCuriosityCluster()
                ScanMarkers()
                ScanScenario()
            end)
        end)
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        TW.Guard("maze quest log", ScanQuestLog)
        SetInside(InLabyrinth())
        return
    end
    -- Quests matter everywhere: you finish them outside the Labyrinth.
    if event == "QUEST_LOG_UPDATE" or event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" then
        TW.Guard("maze quest log", ScanQuestLog)
        if event == "QUEST_ACCEPTED" and inside then TW.Guard("maze quest", QuestPicked, select(1, ...)) end
        ns.Refresh()
        return
    end
    if not inside or not run then return end
    if event:find("^ZONE_CHANGED") then
        local c = CurrentChamber()
        Note("zone:" .. tostring(Safe(GetSubZoneText)), "sub-zone: '%s' -> %s", tostring(Safe(GetSubZoneText)), c and c.name or "not a known chamber")
        TW.Guard("maze zone", MarkChamber, c, "here", "entered")
    elseif event == "UNIT_AURA" then
        if ... == "player" then TW.Guard("maze auras", ScanAuras) end
    elseif event == "BAG_UPDATE_DELAYED" then
        TW.Guard("maze key", CheckKey)
    elseif event == "LOOT_OPENED" then
        TW.Guard("maze loot", OnLoot)
    elseif event == "CHAT_MSG_LOOT" then
        local msg = ...
        if Readable(msg) then
            local m = MaskByName(msg)
            if m then MaskFound(m, "loot message") end
            if msg:find("Amani Key", 1, true) then
                -- "You receive ..." is yours; "Ndeath-Garona receives ..." is a party member's.
                local who = msg:match("^([^%s]+) receives? ")
                if who == "You" then who = nil end
                if who then
                    who = Ambiguate(who, "short")
                    if run.keyHolder ~= who then
                        run.keyHolder = who
                        Print(("|cffffd100%s|r has the key - they open the locked door."):format(who))
                    end
                elseif not run.hasKey then
                    run.hasKey = true
                    Print("you have the |cffffd100key|r" .. (run.door and " - head for the locked door." or " - now find the locked door."))
                end
                TW.Log("MAZE", "key looted: %s", msg)
                ns.Refresh()
            end
        end
    else
        TW.Guard("maze scenario", ScanScenario)
        ns.Refresh()
    end
end)
