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
ns.VERSION = "1.0.2"
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
local WIDTH, ROW_H = 330, 17

local db, run, win
local rows = {}

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
    end
    ns.Refresh()
end

local function MaskFound(m, how)
    if run.masks[m.key] then return end
    local c = CurrentChamber()
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

local function ScanAuras()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or type(a) ~= "table" then break end
        if Readable(a.name) then
            local m = MaskByName(a.name)
            if m then MaskFound(m, "buff: " .. a.name)
            elseif a.name:lower():find("mask", 1, true) or a.name:lower():find("hex", 1, true) then
                Note("aura:" .. a.name, "buff on you: %s (spell %s)", a.name, tostring(a.spellId))
            end
        end
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
            if (lower:find("locked", 1, true) or lower:find("door", 1, true)) and not run.lockedSeen then
                run.lockedSeen = true
                local c = CurrentChamber()
                if c and c.special then run.spots[c.name] = "Locked room" end
                TW.Log("MAZE", "locked room marker: %s in %s (%s)", name, c and c.name or "?", where)
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
    local x, y = c.spot[1] / 100, c.spot[2] / 100
    local label = c.name .. " - mask/locked-room spot"
    if TW.GuideArrow then
        TW.GuideArrow(MAZE_MAP, x, y, label)
    elseif TomTom and TomTom.AddWaypoint then
        pcall(TomTom.AddWaypoint, TomTom, MAZE_MAP, x, y, { title = label, crazy = true })
        Print("TomTom arrow set: " .. label)
    else
        Print(("%s: %.1f, %.1f (enable TippWorks-Curios or TomTom for an arrow)"):format(label, c.spot[1], c.spot[2]))
    end
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
        width = WIDTH, db = db })
    win.footer = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.footer:SetPoint("BOTTOMLEFT", 12, 10)
    win.footer:SetWidth(WIDTH - 24)
    win.footer:SetJustifyH("LEFT")
    win:SetScript("OnShow", function() ns.Refresh() end)
end

local function Header(text) return { header = text } end

function ns.Refresh()
    if not win or not run or not win:IsShown() then return end
    local list = {}
    local here = CurrentChamber()
    list[#list + 1] = Header(("Chambers  %d/9  |cff888888%s|r"):format(DoneCount(),
        InLabyrinth() and "(rewards at 3, 6, 9)" or "(your last run)"))
    for _, c in ipairs(CHAMBERS) do
        local st = run.chambers[c.name]
        list[#list + 1] = { chamber = c,
            left = (here == c and "|cffffffff> " or "  ") .. c.name .. (c.special and " |cff888888*|r" or ""),
            right = st == "done" and "|cff33ff33done|r" or st == "here" and "|cffffd100in progress|r" or "|cff888888-|r",
            tip = function()
                local t = { c.name, "Where: " .. c.where }
                if c.special then t[#t + 1] = "* Can hold a Hexmask or the locked room." end
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
    list[#list + 1] = Header("Locked room" .. (run.lockedSeen and " |cff33ff33seen|r" or "") ..
        (run.keeperSeen and "  |cffffd100Keeper on map|r" or ""))
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
    for i, e in ipairs(list) do
        local b = rows[i] or Row(i)
        b.entry = (not e.header) and e or nil
        b.left:SetText(e.header and ("|cffffd100" .. e.header .. "|r") or e.left)
        b.right:SetText(e.right or "")
        b:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide(); rows[i].entry = nil end
    win.footer:SetText(#spots > 0 and ("|cff888888" .. table.concat(spots, "  |  ") .. "|r")
        or "|cff888888* = a spot that can hold a Hexmask or the locked room|r")
    win:SetHeight(-win.top + #list * ROW_H + 40)
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
        { "spots", "the five mask/locked-room spots with coordinates" },
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

local inside = false
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        TippWorksLabyrinthDB = TippWorksLabyrinthDB or {}
        db = TippWorksLabyrinthDB
        run = db.run
        if not run then NewRun("first load") end
        TW.Log("INFO", "TippWorks-Labyrinth v%s loaded", ns.VERSION)
        CreateWindow()
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
            "SCENARIO_CRITERIA_UPDATE", "SCENARIO_UPDATE", "UNIT_AURA", "QUEST_ACCEPTED", "QUEST_LOG_UPDATE", "QUEST_REMOVED",
            "CHAT_MSG_LOOT" }) do self:RegisterEvent(e) end
        C_Timer.NewTicker(1, function()
            if not inside then return end
            TW.Guard("maze scan", function()
                MarkChamber(CurrentChamber(), "here", "entered")
                ScanMarkers()
                ScanScenario()
            end)
        end)
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        TW.Guard("maze quest log", ScanQuestLog)
        local _, isReload = ...
        local now = InLabyrinth()
        if now and not inside then
            if not isReload then NewRun("entered the Labyrinth") end
            win:Show()
        elseif not now and inside then
            win:Hide()
        end
        inside = now
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
    elseif event == "CHAT_MSG_LOOT" then
        local msg = ...
        if Readable(msg) then
            local m = MaskByName(msg)
            if m then MaskFound(m, "loot message") end
            if msg:find("Amani Key", 1, true) then
                run.hasKey = true
                Print("you have the |cffffd100key|r - now find the locked room.")
                TW.Log("MAZE", "key looted: %s", msg)
            end
        end
    else
        TW.Guard("maze scenario", ScanScenario)
        ns.Refresh()
    end
end)
