local ADDON, ns = ...
local TW = TippWorks

-- Every delve's Delver's Call intro quest, grouped by zone with the closest
-- flight master. The leveling plan for 80 -> 90: pick up each Call, finish
-- the delve on Tier 1, hold the finished quests and hand them in around 87.

-- The running version. WoW only re-reads the .toc on a full restart, so the
-- number lives here too. Bump both together.
ns.VERSION = "1.0.0"
local Print = TW.Printer("Calls")

-- All ten Delver's Call quest ids; matched to delves by their in-game title.
local CALL_IDS = { 93372, 93384, 93385, 93409, 93410, 93416, 93421, 93427, 93428, 93386 }

-- quest = the part of the title after "Delver's Call: ". questID where known
-- (Wowhead); the rest are matched by title in your log. pickup = where the
-- Call object actually is (in-game verified list, Oct 2026) - the click
-- waypoint goes there, not to the entrance. Coordinates: Season 1 delve guides.
local DELVES = {
    { zone = "Eversong Woods", name = "The Shadow Enclave", quest = "Shadow Enclave", questID = 93372, x = 45.5, y = 86.0,
      pickup = { "Eversong Woods", 50.8, 40.0, "banner on the bridge platform" } },
    { zone = "Silvermoon City", name = "Collegiate Calamity", quest = "Collegiate Calamity", questID = 93384, x = 40.6, y = 53.7,
      turnin = "Naleidea Rivergleam",
      pickup = { "Silvermoon City", 41.8, 61.4, "floating book (Agitated Tome) at ground level" } },
    { zone = "Silvermoon City", name = "The Darkway", quest = "The Darkway", x = 52.2, y = 78.0,
      pickup = { "Silvermoon City", 52.2, 78.0, "poster beside the entrance" } },
    { zone = "Isle of Quel'Danas", name = "Parhelion Plaza", quest = "Parhelion Plaza", x = 46.8, y = 40.9,
      pickup = { "Silvermoon City", 52.5, 77.9, "banner by the Quel'Danas portal, beside The Darkway pickup" } },
    { zone = "Zul'Aman", name = "Twilight Crypts", quest = "Twilight Crypts", questID = 93410, x = 25.4, y = 84.4,
      turnin = "Tavikko",
      pickup = { "Zul'Aman", 43.7, 67.3, "poster on the large tree" } },
    { zone = "Zul'Aman", name = "Atal'Aman", quest = "Atal'Aman", questID = 93409, x = 63.7, y = 80.1,
      inside = "the body near the beginning of the delve - loot/interact with it" },
    { zone = "Harandar", name = "The Grudge Pit", quest = "The Grudge Pit", x = 70.4, y = 64.8,
      pickup = { "Harandar", 71.1, 52.1, "banner attached to a vertical branch" } },
    { zone = "Harandar", name = "The Gulf of Memory", quest = "The Gulf of Memory", questID = 93416, x = 36.7, y = 49.6,
      pickup = { "Harandar", 52.8, 51.7, "banner above the cave, near a small tree" } },
    { zone = "Voidstorm", name = "Sunkiller Sanctum", quest = "Sunkiller Sanctum", questID = 93427, x = 54.8, y = 47.1,
      turnin = "Perodius",
      pickup = { "Voidstorm", 42.7, 70.7, "body beside a flagpole" } },
    { zone = "Voidstorm", name = "Shadowguard Point", quest = "Shadowguard Point", x = 37.1, y = 49.1,
      pickup = { "Voidstorm", 37.6, 51.9, "standing flagpole" } },
    -- The Coiled Isle delves (Ring of Glory 71.35, 56.54; Gnarldor Isle 64.54, 77.58)
    -- are level 90 only with no Delver's Call, so they're not on this leveling list.
    -- They still appear on TippWorks-Vault's Bountiful tab (read live from the map).
}

local WIDTH, ROW_H = 350, 18
local db, win
local items = {}

---------------------------------------------------------------------------
-- Quest status
---------------------------------------------------------------------------
local function Norm(s)
    return (s:lower():gsub("\226\128\153", "'"):gsub("^the ", ""))
end

local logByTitle = {}
local function ScanLog()
    wipe(logByTitle)
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.title then
            local t = info.title:match("^Delver.s Call: (.+)$")
            if t then logByTitle[Norm(t)] = info.questID end
        end
    end
end

-- Resolve every known Delver's Call id to its delve by the quest's title.
local idsResolved = false
local function ResolveIds()
    if idsResolved then return end
    local byQuest = {}
    for _, d in ipairs(DELVES) do byQuest[Norm(d.quest)] = d end
    local all = true
    for _, id in ipairs(CALL_IDS) do
        local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
        if title then
            local d = byQuest[Norm(title:gsub("^.-:%s*", ""))]
            if d and not d.questID then db.delveQuestIDs[d.name] = id end
        else
            all = false -- not cached yet; the game loads it, try again later
        end
    end
    idsResolved = all
end

-- "done", "ready" (complete, turn it in), "hold" (complete, below the
-- hand-in level), "inlog", or "todo"
local function Status(d)
    ResolveIds()
    local id = d.questID or db.delveQuestIDs[d.name]
    if id and C_QuestLog.IsQuestFlaggedCompleted(id) then return "done" end
    if db.delveDone[d.name] then return "done" end
    local inLog = logByTitle[Norm(d.quest)]
    if inLog then
        db.delveQuestIDs[d.name] = inLog -- learn the id so completion is detected later
        id = inLog
    elseif id and C_QuestLog.GetLogIndexForQuestID(id) then
        inLog = id
    end
    if inLog then
        if C_QuestLog.IsComplete(id) then
            return UnitLevel("player") >= TW.CALL_HOLD_LEVEL and "ready" or "hold"
        end
        return "inlog"
    end
    return "todo"
end

-- Each Call is three steps; the status names the NEXT one.
local STATUS = {
    todo = "|cffffffff1 pick up|r",
    inlog = "|cffffd1002 run delve|r",
    hold = "|cff33ff33done|r |cff888888- hold to 87|r",
    ready = "|cff33ff333 turn in!|r",
    done = "|cff33ff33turned in|r",
}

---------------------------------------------------------------------------
-- Click: the next step for this Call
---------------------------------------------------------------------------
local function OnClick(self, btn)
    local d = self.delve
    if btn == "RightButton" then
        db.delveDone[d.name] = not db.delveDone[d.name] or nil
        ns.Refresh()
        return
    end
    ScanLog()
    local st = Status(d)
    local id = d.questID or db.delveQuestIDs[d.name]
    if st == "done" then
        Print(d.name .. ": Delver's Call already turned in - nothing left to do.")
        return
    elseif st == "hold" then
        Print(("%s: done - |cff33ff33hold the quest|r until level %d (you're %d). Turn in to %s then."):format(
            d.name, TW.CALL_HOLD_LEVEL, UnitLevel("player"), d.turnin or "the quest's turn-in NPC"))
        return
    elseif st == "ready" then
        -- Let Blizzard's own quest arrow lead to the turn-in NPC.
        if id and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            C_SuperTrack.SetSuperTrackedQuestID(id)
            Print(("%s: |cff33ff33turn in now|r - tracking the quest, follow the arrow to %s."):format(
                d.name, d.turnin or "the turn-in NPC"))
        else
            Print(d.name .. ": turn in now - open your quest log to see where.")
        end
        return
    elseif st == "inlog" then
        -- Step 2: the delve itself.
        TW.ActivateDelve(setmetatable({ stage = "run" }, { __index = d }))
        return
    end
    if d.pickup then
        -- Head for the quest object, not the delve entrance.
        local p = d.pickup
        TW.ActivateDelve(setmetatable({ zone = p[1], x = p[2], y = p[3], pickupWhat = p[4] }, { __index = d }))
    else
        TW.ActivateDelve(d)
    end
end

-- /tw calls list: same as the community /run check, using the addon's data.
local function PrintCalls()
    ResolveIds()
    ScanLog()
    local label = { done = "TURNED IN", ready = "LOG (turn in now)", hold = "LOG (holding)", inlog = "in log, not done", todo = "NEEDED" }
    for _, d in ipairs(DELVES) do Print(("%s - %s"):format(label[Status(d)] or "?", d.name)) end
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local function DelveRow(parent, d)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(WIDTH - 20, ROW_H)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.delve = d
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.name:SetPoint("LEFT", 12, 0)
    b.name:SetText(d.name)
    b.status = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.status:SetPoint("RIGHT", -4, 0)
    b.fp = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.fp:SetPoint("RIGHT", b.status, "LEFT", -8, 0) -- status length varies by step
    b.fp:SetJustifyH("RIGHT")
    b:SetScript("OnClick", OnClick)
    b:SetScript("OnEnter", function(self)
        local fp, yards = TW.ClosestFlightPoint(d)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Delver's Call: " .. d.quest)
        if d.pickup then
            GameTooltip:AddLine(("Pickup: %s - %s %.1f, %.1f"):format(d.pickup[4], d.pickup[1], d.pickup[2], d.pickup[3]), 0.4, 0.8, 1, true)
        elseif d.inside then
            GameTooltip:AddLine("Pickup: inside the delve - " .. d.inside, 0.4, 0.8, 1, true)
        end
        GameTooltip:AddLine(("%s  %.1f, %.1f"):format(d.zone, d.x, d.y), 1, 1, 1)
        local travel = TW.TRAVEL[d.zone]
        if travel then
            GameTooltip:AddLine("Getting there:", 0.4, 0.8, 1)
            for _, line in ipairs(travel) do GameTooltip:AddLine(line, 1, 1, 1, true) end
        end
        if fp then GameTooltip:AddLine("Closest flight: " .. fp .. (yards and (" (~%d yd)"):format(yards) or ""), 1, 1, 1) end
        if d.note then GameTooltip:AddLine(d.note, 0.8, 0.8, 0.8, true) end
        ScanLog()
        local st = Status(d)
        local function step(done, text) GameTooltip:AddLine((done and "|cff33ff33[x]|r " or "|cff888888[ ]|r ") .. text, 1, 1, 1, true) end
        GameTooltip:AddLine(" ")
        step(st ~= "todo", "1. Pick up the Call" .. (d.inside and " (inside the delve)" or ""))
        step(st == "hold" or st == "ready" or st == "done", "2. Complete the delve (Tier 1 is fine)")
        step(st == "done", ("3. Turn in%s at level %d+"):format(d.turnin and (" to " .. d.turnin) or "", TW.CALL_HOLD_LEVEL))
        local nextAction = ({ todo = "waypoint to the pickup", inlog = "waypoint to the delve entrance",
            hold = "reminder - hold until " .. TW.CALL_HOLD_LEVEL, ready = "track the turn-in (quest arrow)", done = "nothing left" })[st]
        local mode = TW.db.shareMode or "group"
        GameTooltip:AddLine("Left-click: " .. nextAction .. ", share (" .. (mode == "group" and "party/raid if grouped" or mode) .. ")", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Shift-click: put it in your chat box instead", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Right-click: mark done / not done", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

local function CreateWindow()
    win = TW.CreateWindow({ name = "TippWorksCallsFrame", title = "Delver's Call Quests", version = ns.VERSION,
        width = WIDTH, db = db })
    local y = win.top
    for _, zone in ipairs(TW.DELVE_ZONES) do
        local list = {}
        for _, d in ipairs(DELVES) do
            if d.zone == zone then list[#list + 1] = d end
        end
        if #list > 0 then
            local h = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            h:SetPoint("TOPLEFT", 14, y - 3)
            h.zone, h.list = zone, list
            items[#items + 1] = { header = h }
            y = y - ROW_H
            for _, d in ipairs(list) do
                local row = DelveRow(win, d)
                row:SetPoint("TOPLEFT", 10, y)
                items[#items + 1] = { row = row }
                y = y - ROW_H
            end
        end
    end
    win.footer = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.footer:SetPoint("BOTTOMLEFT", 12, 12)
    win:SetHeight(-y + 40)
    win:SetScript("OnShow", function() ns.Refresh() end)
end

local function Counts()
    ScanLog()
    local picked, done = 0, 0
    for _, d in ipairs(DELVES) do
        local st = Status(d)
        if st ~= "todo" then picked = picked + 1 end
        if st == "done" then done = done + 1 end
    end
    return picked, done
end

function ns.Refresh()
    if not win or not win:IsShown() then return end
    ScanLog()
    local picked, done = 0, 0
    local zoneDone = {}
    for _, it in ipairs(items) do
        local row = it.row
        if row then
            local d = row.delve
            local st = Status(d)
            row.status:SetText(STATUS[st])
            local fp = TW.ClosestFlightPoint(d)
            row.fp:SetText(fp and ("via " .. fp) or "")
            row:SetAlpha(st == "done" and 0.45 or 1)
            row.name:SetTextColor(st == "done" and 0.5 or 1, st == "done" and 0.5 or 0.82, st == "done" and 0.5 or 0)
            if st ~= "todo" then picked = picked + 1 end
            if st == "hold" then row.name:SetTextColor(0.6, 0.9, 0.6) end
            if st == "done" then
                done = done + 1
                zoneDone[d.zone] = (zoneDone[d.zone] or 0) + 1
            end
        end
    end
    for _, it in ipairs(items) do
        local h = it.header
        if h then h:SetText(("%s  |cff888888%d/%d|r"):format(h.zone, zoneDone[h.zone] or 0, #h.list)) end
    end
    win.footer:SetText(("Picked up or done: %d/%d  |  done: %d"):format(picked, #DELVES, done))
end

---------------------------------------------------------------------------
-- TippWorks registration, /tw calls, saved data
---------------------------------------------------------------------------
local function Toggle() if win then win:Toggle() end end

local function Summary(tt)
    local picked, done = Counts()
    tt:AddLine(("Delver's Calls: %d/%d turned in, %d picked up"):format(done, #DELVES, picked), 1, 1, 1)
end

local module
local function Command(rest)
    local sub = (rest:match("^(%S*)") or ""):lower()
    if sub == "" or sub == "show" or sub == "toggle" then Toggle()
    elseif sub == "list" then PrintCalls()
    else TW.ModuleHelp(module) end
end

module = TW.Register({
    key = "calls", aliases = { "delves", "call" },
    name = "Delver's Calls (80-90)", addon = ADDON, version = ns.VERSION,
    command = Command, toggle = Toggle, summary = Summary,
    help = {
        { "", "show/hide the Delver's Call list (click a row for the next step)" },
        { "list", "print every Call's status in chat" },
    },
})

function TippWorksCalls_OnAddonCompartmentClick() Toggle() end
function TippWorksCalls_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff" .. TW.COLOR .. "Tippenhauer Works|r - Delver's Calls")
    Summary(GameTooltip)
    GameTooltip:AddLine("Click: show/hide  |  /tw calls help", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end
function TippWorksCalls_OnAddonCompartmentLeave() GameTooltip:Hide() end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        TippWorksCallsDB = TippWorksCallsDB or {}
        db = TippWorksCallsDB
        -- One-time: carry Calls progress (and the shared share/portal settings)
        -- over from CoiledRareTracker, whose saved data TippWorks-Rares keeps.
        if not db.migrated then
            local old, oldAcct = CoiledRareTrackerDB, CoiledRareTrackerAccountDB
            if type(old) == "table" then
                db.delveDone = db.delveDone or old.delveDone
                db.delveQuestIDs = db.delveQuestIDs or old.delveQuestIDs
                db.pos = db.pos or old.pos
                if TW.db.shareMode == nil then TW.db.shareMode = old.shareMode end
                TW.Log("CALLS", "copied Delver's Call progress from CoiledRareTracker")
            end
            if type(oldAcct) == "table" and oldAcct.portals and not TW.account.portals then
                TW.account.portals = oldAcct.portals
            end
            db.migrated = true
        end
        db.delveDone = db.delveDone or {}
        db.delveQuestIDs = db.delveQuestIDs or {}
        TW.Log("INFO", "TippWorks-Calls v%s loaded", ns.VERSION)
        CreateWindow()
        self:RegisterEvent("QUEST_LOG_UPDATE")
        self:RegisterEvent("QUEST_TURNED_IN")
        self:RegisterEvent("PLAYER_LEVEL_UP")
    else
        ns.Refresh()
    end
end)
