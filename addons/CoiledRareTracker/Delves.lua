local _, ns = ...

-- "Delves" tab: every delve's Delver's Call intro quest, grouped by zone with
-- the closest flight master. Pick these up at 80 before running delves.
local ROW_H = 18
local page, items = nil, {}
local closestFP = {}

---------------------------------------------------------------------------
-- Map ids by zone name (no hard-coded ids for the Midnight zones)
---------------------------------------------------------------------------
local mapIndex

local function BuildMapIndex()
    mapIndex = {}
    for id = 2300, 3500 do
        local info = C_Map.GetMapInfo(id)
        if info and info.name and info.name ~= "" then
            local cur = mapIndex[info.name]
            -- Prefer the zone-level map over floors, micro-maps and duplicates.
            if not cur or (info.mapType == Enum.UIMapType.Zone and cur.type ~= Enum.UIMapType.Zone) then
                mapIndex[info.name] = { id = id, type = info.mapType }
            end
        end
    end
end

function ns.FindMapByName(name)
    if name == ns.ZONE_NAME then return ns.ZoneMap() end
    ns.db.maps = ns.db.maps or {}
    local hint = ns.MAP_HINTS and ns.MAP_HINTS[name]
    if hint then
        local info = C_Map.GetMapInfo(hint)
        if info and info.name == name then return hint end
    end
    local saved = ns.db.maps[name]
    if saved then
        local info = C_Map.GetMapInfo(saved)
        if info and info.name == name then return saved end
    end
    -- Where the player is standing is the most trustworthy answer.
    local m = C_Map.GetBestMapForUnit("player")
    while m and m > 0 do
        local info = C_Map.GetMapInfo(m)
        if info and info.name == name and info.mapType == Enum.UIMapType.Zone then
            ns.db.maps[name] = m
            return m
        end
        m = info and info.parentMapID
    end
    if not mapIndex then BuildMapIndex() end
    local hit = mapIndex[name]
    if hit then ns.db.maps[name] = hit.id end
    return hit and hit.id
end

function ns.ResetMapCache()
    mapIndex = nil
    wipe(closestFP)
    if ns.db.maps then wipe(ns.db.maps) end
end

local function World(map, x, y)
    if map then
        local _, w = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x / 100, y / 100))
        if w then return w.x, w.y, true end
    end
    return x, y, false
end

-- Returns name, yards-or-nil
local function ClosestFlightPoint(d)
    local ck = ("%s@%s,%.1f,%.1f"):format(d.name, d.zone, d.x, d.y)
    local c = closestFP[ck]
    if c then return c.name, c.yards end
    local fps = ns.FLIGHT_POINTS[d.zone]
    if not fps then return end
    local map = ns.FindMapByName(d.zone)
    local dx, dy, inYards = World(map, d.x, d.y)
    local best, bestD
    for _, fp in ipairs(fps) do
        if fp[2] then
            local fx, fy = World(map, fp[2], fp[3])
            local dist = math.sqrt((fx - dx) ^ 2 + (fy - dy) ^ 2)
            if not bestD or dist < bestD then best, bestD = fp[1], dist end
        elseif not best then
            best = fp[1]
        end
    end
    closestFP[ck] = { name = best, yards = inYards and bestD or nil }
    return best, inYards and bestD or nil
end

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

-- "done", "ready" (complete, turn it in), "inlog", or "todo"
-- Resolve every known Delver's Call id to its delve by the quest's title.
local idsResolved = false
local function ResolveIds()
    if idsResolved then return end
    local byQuest = {}
    for _, d in ipairs(ns.DELVES) do byQuest[Norm(d.quest)] = d end
    local all = true
    for _, id in ipairs(ns.DELVERS_CALL_IDS) do
        local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
        if title then
            local d = byQuest[Norm(title:gsub("^.-:%s*", ""))]
            if d and not d.questID then ns.db.delveQuestIDs[d.name] = id end
        else
            all = false -- not cached yet; the game loads it, try again later
        end
    end
    idsResolved = all
end

local function Status(d)
    local db = ns.db
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
            return UnitLevel("player") >= ns.CALL_HOLD_LEVEL and "ready" or "hold"
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
-- Click: waypoint + share + what to look for
---------------------------------------------------------------------------
-- /crt share group|say|guild|self. "group" = party/raid when grouped,
-- otherwise only you see it.
-- A portal spot saved in game (/crt portal <zone>) beats the guide's.
function ns.PortalFor(zone)
    -- Saved portals are warband-wide: a portal is in the same place for every alt.
    local saved = CoiledRareTrackerAccountDB.portals and CoiledRareTrackerAccountDB.portals[zone]
    if saved then return { name = "Portal to " .. zone .. " (your saved spot)", x = saved.x, y = saved.y } end
    local travel = ns.TRAVEL[zone]
    return travel and travel.portal
end

function ns.SavePortal(query)
    query = (query or ""):lower()
    local zone
    for _, z in ipairs(ns.DELVE_ZONES) do
        if query ~= "" and z:lower():find(query, 1, true) then zone = z break end
    end
    if not zone then ns.Print("usage: /crt portal <zone>  e.g. /crt portal harandar  (stand on the portal in Silvermoon)") return end
    local sm = ns.FindMapByName("Silvermoon City")
    local p = sm and C_Map.GetPlayerMapPosition(sm, "player")
    if not p then ns.Print("stand in Silvermoon City, on the portal, then try again.") return end
    local acct = CoiledRareTrackerAccountDB
    acct.portals = acct.portals or {}
    acct.portals[zone] = { x = p.x * 100, y = p.y * 100 }
    ns.Print(("saved the %s portal at %.1f, %.1f for all your characters - delve clicks from Silvermoon will point here."):format(zone, p.x * 100, p.y * 100))
end

local function ChatChannel()
    local mode = ns.db.shareMode or "group"
    if mode == "self" then return end
    if mode == "say" then return "SAY" end
    if mode == "guild" then return IsInGuild() and "GUILD" or nil end
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function Send(msg, channel)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    pcall(send, msg, channel)
end

local function ShareLine(d, pinSet)
    local fp = ClosestFlightPoint(d)
    local label = d.bountiful
        and ("Bountiful delve: " .. d.name .. (d.variant and (" (" .. d.variant .. ")") or ""))
        or ("Delver's Call: " .. d.quest)
    local msg = ("%s - %s %.1f, %.1f%s"):format(
        label, d.zone, d.x, d.y, fp and (" (closest flight: " .. fp .. ")") or "")
    -- Only link the pin we just placed, never a stale one from earlier.
    local link = pinSet and C_Map.GetUserWaypointHyperlink and C_Map.GetUserWaypointHyperlink()
    if link then msg = msg .. " " .. link end
    return msg
end

local function SetDelveWaypoint(d)
    local map = ns.FindMapByName(d.zone)
    if not map then
        ns.Print("couldn't find the " .. d.zone .. " map - try /crt map once you're there.")
        return false
    end
    if TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(map, d.x / 100, d.y / 100, { title = d.name })
    end
    if C_Map.CanSetUserWaypointOnMap(map) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, d.x / 100, d.y / 100))
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        return true, true
    end
    ns.Print("Blizzard won't place a map pin on " .. d.zone .. " - use the coordinates below.")
    return true, false
end

-- True if any map in the player's chain has this name (works whether a
-- city is its own zone or a sub-map of the zone around it).
local function PlayerIsIn(name)
    local m = C_Map.GetBestMapForUnit("player")
    while m and m > 0 do
        local info = C_Map.GetMapInfo(m)
        if info and info.name == name then return true end
        m = info and info.parentMapID
    end
    return false
end

local function Describe(d)
    local fp, yards = ClosestFlightPoint(d)
    ns.Print(("|cffffd100%s|r (%s %.1f, %.1f)"):format(d.name, d.zone, d.x, d.y))
    local travel = ns.TRAVEL[d.zone]
    if travel and not PlayerIsIn(d.zone) then
        ns.Print("  |cff66ccffGetting there:|r")
        for _, line in ipairs(travel) do ns.Print("    " .. line) end
        if travel.hearth then
            local bind = GetBindLocation and GetBindLocation()
            if bind and bind ~= "" then ns.Print("    Your Hearthstone is set to: |cffffffff" .. bind .. "|r") end
        end
    end
    if fp then
        ns.Print("  Then fly to: " .. fp .. (yards and (" (~%d yd from the entrance)"):format(yards) or ""))
    end
    ns.Print("  Look for: the delve entrance - the swirling delve portal / delve icon at the waypoint.")
    if d.variant then ns.Print("  Version today: |cffffffff" .. d.variant .. "|r") end
    if d.bountiful then
        ns.Print("  Bountiful today: bring a Restored Coffer Key for the Bountiful Coffer at the end.")
        ns.Print("  (The key is only for the coffer - entry and Great Vault credit don't need one.)")
    end
    if d.quest and d.stage == "run" then
        ns.Print("  |cff66ccffStep 2:|r you have the Call - run the delve, any tier (Tier 1 is fine).")
        ns.Print(("  Afterwards keep the finished quest in your log until level %d, then click again to turn in."):format(ns.CALL_HOLD_LEVEL))
    elseif d.quest then
        if d.pickupWhat then
            ns.Print(("  |cff66ccffQuest pickup:|r %s - %s %.1f, %.1f (waypoint set here)"):format(
                d.pickupWhat, d.zone, d.x, d.y))
        elseif d.inside then
            ns.Print("  |cff66ccffQuest pickup:|r INSIDE the delve - " .. d.inside .. ".")
        end
        ns.Print("  Accept the Call before you complete that delve. Leveling: finish it on Tier 1,")
        ns.Print(("  then keep the finished quest in your log until about level %d-88."):format(ns.CALL_HOLD_LEVEL))
        if d.turnin then ns.Print("  Turn in to: " .. d.turnin) end
        if not ns.callTipShown then
            ns.callTipShown = true
            ns.Print("  |cff888888Can't see the pickup on an alt? Minimap tracking -> enable 'Track Warband Completed Quests'.")
            ns.Print("  Your warband also needs 'Void Walk With Me' (end of Eversong's Shadowfall story) done once.|r")
        end
    end
    if d.note then ns.Print("  Note: " .. d.note) end
end

-- Waypoint (or the Silvermoon portal first), share, and explain. Used by
-- the Delves and Bountiful tabs.
function ns.ActivateDelve(d)
    -- Standing in Silvermoon and the zone has a portal there: point at the
    -- portal first; click again once you're through for the entrance.
    local travel = ns.TRAVEL[d.zone]
    local portal = ns.PortalFor(d.zone)
    if portal and PlayerIsIn("Silvermoon City") and not PlayerIsIn(d.zone) then
        local sm = ns.FindMapByName("Silvermoon City")
        if sm and C_Map.CanSetUserWaypointOnMap(sm) then
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(sm, portal.x / 100, portal.y / 100))
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            ns.Print(("waypoint set to the %s (%.1f, %.1f) - click %s again once you're through."):format(
                portal.name, portal.x, portal.y, d.name))
            Describe(d)
            return
        end
    end
    local ok, pinSet = SetDelveWaypoint(d)
    if not ok then return end
    local msg = ShareLine(d, pinSet)
    if IsShiftKeyDown() then
        local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
        if open then open(msg) end
    else
        local channel = ChatChannel()
        if channel then
            Send(msg, channel)
        else
            -- Make it unmistakable that nobody else saw this.
            ns.Print("|cff888888[Only you can see this]|r " .. msg)
            ns.Print("|cff888888Not sent - you're not in a group. Shift-click to post it yourself, or /crt share say|guild.|r")
        end
    end
    Describe(d)
end

local function OnClick(self, btn)
    local d = self.delve
    if btn == "RightButton" then
        ns.db.delveDone[d.name] = not ns.db.delveDone[d.name] or nil
        ns.RefreshDelves()
        return
    end
    ScanLog()
    local st = Status(d)
    local id = d.questID or ns.db.delveQuestIDs[d.name]
    if st == "done" then
        ns.Print(d.name .. ": Delver's Call already turned in - nothing left to do.")
        return
    elseif st == "hold" then
        ns.Print(("%s: done - |cff33ff33hold the quest|r until level %d (you're %d). Turn in to %s then."):format(
            d.name, ns.CALL_HOLD_LEVEL, UnitLevel("player"), d.turnin or "the quest's turn-in NPC"))
        return
    elseif st == "ready" then
        -- Let Blizzard's own quest arrow lead to the turn-in NPC.
        if id and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            C_SuperTrack.SetSuperTrackedQuestID(id)
            ns.Print(("%s: |cff33ff33turn in now|r - tracking the quest, follow the arrow to %s."):format(
                d.name, d.turnin or "the turn-in NPC"))
        else
            ns.Print(d.name .. ": turn in now - open your quest log to see where.")
        end
        return
    elseif st == "inlog" then
        -- Step 2: the delve itself.
        ns.ActivateDelve(setmetatable({ stage = "run" }, { __index = d }))
        return
    end
    if d.pickup then
        -- Head for the quest object, not the delve entrance.
        local p = d.pickup
        local target = setmetatable({ zone = p[1], x = p[2], y = p[3], pickupWhat = p[4] }, { __index = d })
        ns.ActivateDelve(target)
    else
        ns.ActivateDelve(d)
    end
end
ns.ClosestFlightPoint = function(d) return ClosestFlightPoint(d) end

-- /crt calls: same as the community /run check, using the addon's data.
function ns.PrintCalls()
    ResolveIds()
    ScanLog()
    local label = { done = "TURNED IN", ready = "LOG (turn in now)", hold = "LOG (holding)", inlog = "in log, not done", todo = "NEEDED" }
    for _, d in ipairs(ns.DELVES) do
        if d.zone ~= "Coiled Isle" then
            ns.Print(("%s - %s"):format(label[Status(d)] or "?", d.name))
        end
    end
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local function DelveRow(parent, d)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(ns.WIDTH - 20, ROW_H)
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
        local fp, yards = ClosestFlightPoint(d)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Delver's Call: " .. d.quest)
        if d.pickup then
            GameTooltip:AddLine(("Pickup: %s - %s %.1f, %.1f"):format(d.pickup[4], d.pickup[1], d.pickup[2], d.pickup[3]), 0.4, 0.8, 1, true)
        elseif d.inside then
            GameTooltip:AddLine("Pickup: inside the delve - " .. d.inside, 0.4, 0.8, 1, true)
        end
        GameTooltip:AddLine(("%s  %.1f, %.1f"):format(d.zone, d.x, d.y), 1, 1, 1)
        local travel = ns.TRAVEL[d.zone]
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
        step(st == "done", ("3. Turn in%s at level %d+"):format(d.turnin and (" to " .. d.turnin) or "", ns.CALL_HOLD_LEVEL))
        local nextAction = ({ todo = "waypoint to the pickup", inlog = "waypoint to the delve entrance",
            hold = "reminder - hold until " .. ns.CALL_HOLD_LEVEL, ready = "track the turn-in (quest arrow)", done = "nothing left" })[st]
        local mode = ns.db.shareMode or "group"
        GameTooltip:AddLine("Left-click: " .. nextAction .. ", share (" .. (mode == "group" and "party/raid if grouped" or mode) .. ")", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Shift-click: put it in your chat box instead", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Right-click: mark done / not done", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

function ns.CreateDelvesPage(parent, top)
    page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    local y = top
    for _, zone in ipairs(ns.DELVE_ZONES) do
        local list = {}
        for _, d in ipairs(ns.DELVES) do
            if d.zone == zone then list[#list + 1] = d end
        end
        if #list > 0 then
            local h = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            h:SetPoint("TOPLEFT", 14, y - 3)
            h.zone, h.list = zone, list
            items[#items + 1] = { header = h }
            y = y - ROW_H
            for _, d in ipairs(list) do
                local row = DelveRow(page, d)
                row:SetPoint("TOPLEFT", 10, y)
                items[#items + 1] = { row = row }
                y = y - ROW_H
            end
        end
    end
    page.footer = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.footer:SetPoint("BOTTOMLEFT", 12, 12)
    page.contentHeight = -y
    page:Hide()
    return page
end

function ns.RefreshDelves()
    if not page or not page:IsShown() then return end
    ScanLog()
    local picked, done, total = 0, 0, #ns.DELVES
    local zoneDone = {}
    for _, it in ipairs(items) do
        local row = it.row
        if row then
            local d = row.delve
            local st = Status(d)
            row.status:SetText(STATUS[st])
            local fp = ClosestFlightPoint(d)
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
    page.footer:SetText(("Picked up or done: %d/%d  |  done: %d"):format(picked, total, done))
end
