local ADDON, ns = ...
local TW = TippWorks

-- Inside a delve: records every curiosity/chest map marker (once a reveal
-- buff shows them map-wide they're all captured), keeps them for the run,
-- and syncs who picked what up with party members running this addon.

-- The running version. WoW only re-reads the .toc on a full restart, so the
-- number lives here too. Bump both together.
ns.VERSION = "1.0.2"
ns.Log, ns.Guard, ns.Print = TW.Log, TW.Guard, TW.Printer("Curios")

-- Delve pickups tracked on the panel (matched against map marker names,
-- case-insensitive). Add a pattern here if one is missed.
ns.CURIO_PATTERNS = {
    { "curiosit", "Curiosity" },   -- Mislaid Curiosity
    { "sturdy chest", "Sturdy Chest" },
    { "heavy trunk", "Heavy Trunk" },
    { "trove", "Trove" },
}

-- Same prefix as the CoiledRareTracker versions, so mixed parties still sync.
local PREFIX = "CRTCurio"
local LOOT_RANGE = 15 -- yards: a marker vanishing this close means you took it
local VIEW_RANGE = 200 -- markers drop out of view around 250 yd; beyond this a vanish means nothing
local ROW_H, WIDTH, MAX_ROWS = 18, 300, 16

local db, run
local frame, rows = nil, {}
local overlay, pins = nil, {}
local inDelve, wasInDelve = false, nil
local outbox = {}
local SUCCESS = Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0
local lastHello = 0
local me = UnitName("player")
local addonUsers = {}
local answered

local Safe, IsDelve = TW.Safe, TW.IsDelve

local function Readable(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end

-- Curiosities by object id, for when the game hides the marker's name.
local CURIO_OBJECT_IDS = { [455914] = { "Curiosity", "Mislaid Curiosity" } }

-- Markers WoW reports with a position but no info at all ("unnamed objects").
-- Could be a curiosity or another interactable; listed as UNKNOWN until the
-- name becomes readable (usually when you get closer), never synced.
local UNKNOWN, UNKNOWN_NAME = "Unknown", "Unnamed object (?)"
local IGNORED_VIGNETTES = { [6116] = true } -- Delver's Supplies

-- A Boon with no known curiosity nearby: the game never showed this one, so
-- it's added where you stood, already picked up. Local only, never synced.
local PICKUP, PICKUP_NAME = "Pickup", "Curiosity (picked up)"

local function Syncable(it) return it.kind ~= UNKNOWN and it.kind ~= PICKUP end

local function VignetteID(guid)
    return Readable(guid) and type(guid) == "string"
        and tonumber(guid:match("^Vignette%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")) or nil
end

-- Returns kind, display name for a tracked marker (nil if not tracked).
local function Kind(info)
    local name = Readable(info.name) and type(info.name) == "string" and info.name or nil
    if name then
        local lower = name:lower()
        for _, p in ipairs(ns.CURIO_PATTERNS) do
            if lower:find(p[1], 1, true) then return p[2], name end
        end
    end
    local guid = Safe(function() return info.objectGUID end)
    local id = type(guid) == "string" and tonumber(guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    local known = id and CURIO_OBJECT_IDS[id]
    if known then return known[1], name or known[2] end
end

---------------------------------------------------------------------------
-- Party sync (hidden addon messages; only people running this addon)
---------------------------------------------------------------------------
local function Channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInGroup() then return "PARTY" end
end

-- WoW throttles addon messages (result 3), so the queue is drained one
-- message at a time by a ticker instead of in a burst, and never holds the
-- same message twice.
local queued = {}
local stalled = nil
local RESULT = { [3] = "throttled by WoW", [5] = "not in a group", [9] = "general error" }

local function SendOne()
    local msg = outbox[1]
    if not msg then return end
    local ch = Channel()
    if not ch then wipe(outbox); wipe(queued) return end
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, ch)
    if not ok or (res ~= nil and res ~= true and res ~= SUCCESS) then
        local why = ok and (RESULT[res] or ("code " .. tostring(res))) or "error"
        if stalled ~= why then -- log a stall once, not once per message
            stalled = why
            ns.Log("SYNC", "sending paused (%s), %d queued - will keep retrying", why, #outbox)
        end
        return
    end
    if stalled then ns.Log("SYNC", "sending resumed"); stalled = nil end
    ns.Log("SYNC", "sent to %s: %s", ch, msg)
    table.remove(outbox, 1)
    queued[msg] = nil
end
local Flush = SendOne

local function Broadcast(msg)
    if msg:sub(1, 1) == "H" then -- roster updates fire a lot; say hello at most every 10s
        if GetTime() - lastHello < 10 then return end
        lastHello = GetTime()
    end
    if not Channel() or queued[msg] then return end
    queued[msg] = true
    outbox[#outbox + 1] = msg
end

local function Encode(it, tag)
    return table.concat({ tag, it.key, it.kind, ("%.4f"):format(it.x), ("%.4f"):format(it.y), it.map, it.name }, "|")
end

---------------------------------------------------------------------------
-- Run state
---------------------------------------------------------------------------
-- Object GUIDs look like Creature-0-<server>-<instance>-<zoneUID>-<npc>-<spawn>;
-- zoneUID is unique to one copy of a delve, so it tells two runs apart.
local function ZoneOf(guid)
    if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return end
    return guid:match("^[^-]+%-%d+%-%d+%-%d+%-(%d+)%-")
end

local function NewRun(why)
    run = { inst = select(8, GetInstanceInfo()), items = {}, order = {}, compacted = true }
    db.curioRun = run
    answered = nil
    ns.Log("CURIO", "new curiosity list (%s)", why)
end

-- fresh = we zoned in (not a /reload inside the delve): always a new list.
local function StartRunIfNeeded(fresh)
    local instMap = select(8, GetInstanceInfo())
    run = db.curioRun
    if fresh then
        NewRun("entered the delve")
    elseif not run or run.inst ~= instMap or time() - (run.lastSeen or 0) > 1800 then
        run = { inst = instMap, items = {}, order = {}, compacted = true }
        db.curioRun = run
    elseif not run.compacted then
        ns.CompactCurioRun()
    end
    run.lastSeen = time()
end

local MERGE_YARDS = 10

local function World(map, x, y)
    local ok, _, w = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    if ok and w then return w.x, w.y end
end

-- The same chest can arrive under two keys: its object GUID vs name+position,
-- or name+position on two different floor maps of the same delve. Same name
-- at the same spot in the world = the same curiosity. An unnamed object at
-- the same spot as a named one is the same thing too.
local function FindSame(name, map, x, y, kind)
    local wx, wy = World(map, x, y)
    for _, k in ipairs(run.order) do
        local it = run.items[k]
        if it.name == name or kind == UNKNOWN or it.kind == UNKNOWN then
            if wx and it.wx then
                if math.sqrt((wx - it.wx) ^ 2 + (wy - it.wy) ^ 2) <= MERGE_YARDS then return it end
            elseif it.map == map and math.abs(it.x - x) < 0.01 and math.abs(it.y - y) < 0.01 then
                return it
            end
        end
    end
end

local quietMerge = false
local function AddItem(key, kind, name, map, x, y)
    run.alias = run.alias or {}
    local it = run.items[run.alias[key] or key]
    if it then return it, false end
    local same = FindSame(name, map, x, y, kind)
    if same and same.kind == UNKNOWN and kind ~= UNKNOWN then
        -- The unnamed object turned out to be this: take the real name.
        run.alias[key] = same.key
        ns.Log("CURIO", "unnamed object at %.1f,%.1f is a %s", x * 100, y * 100, name)
        same.kind, same.name = kind, name
        return same, true
    elseif same then
        run.alias[key] = same.key
        if not quietMerge then ns.Log("CURIO", "%s arrived under a second key (%s) - merged with the one already listed",
            name, key:find("@", 1, true) and "name+position" or "object GUID") end
        return same, false
    end
    it = { key = key, kind = kind, name = name, map = map, x = x, y = y, looted = {} }
    it.wx, it.wy = World(map, x, y)
    run.items[key] = it
    run.order[#run.order + 1] = key
    return it, true
end

-- Fold duplicates saved by older versions (one entry per copy / per key).
function ns.CompactCurioRun()
    local old = run
    run = { inst = old.inst, items = {}, order = {}, alias = {}, lastSeen = old.lastSeen, compacted = true }
    quietMerge = true
    for _, key in ipairs(old.order or {}) do
        local o = old.items[key]
        if o then
            local it = AddItem(key, o.kind, o.name, o.map, o.x, o.y)
            for who in pairs(o.looted or {}) do it.looted[who] = true end
            it.present = it.present or o.present
        end
    end
    quietMerge = false
    db.curioRun = run
    ns.Log("CURIO", "tidied saved list: %d entries -> %d curiosities", #(old.order or {}), #run.order)
end

function ns.ResetCurioRun()
    db.curioRun = nil
    run = nil
    if IsInInstance() then StartRunIfNeeded() end
    ns.Log("CURIO", "curiosity list cleared by hand")
    ns.Print("curiosity list cleared.")
    if ns.RefreshCurios then ns.RefreshCurios() end
end

local lastMine -- GetTime() of your last credited pickup
local function MarkLooted(it, who, fromSync)
    if it.looted[who] then return end
    it.looted[who] = true
    if who == me and ns.CurioArrowLooted then ns.CurioArrowLooted(it) end
    if who == me then lastMine = GetTime() end
    if who == me and not fromSync and Syncable(it) then Broadcast(Encode(it, "L")) end
    ns.RefreshCurios()
end

---------------------------------------------------------------------------
-- Scanning
---------------------------------------------------------------------------
local function PlayerWorld(map)
    local p = map and C_Map.GetPlayerMapPosition(map, "player")
    if not p then return end
    local _, w = C_Map.GetWorldPosFromMapPos(map, p)
    return w
end

-- Some delve maps (e.g. Parhelion Plaza) have no world transform, so world
-- positions come back nil. Fall back to map position x the map's size in
-- yards, or a typical delve size if even that is unknown.
local DEFAULT_MAP_YARDS = 500
local function MapYards(map)
    if C_Map.GetMapWorldSize then
        local ok, w, h = pcall(C_Map.GetMapWorldSize, map)
        if ok and w and w > 0 and h and h > 0 then return w, h end
    end
    return DEFAULT_MAP_YARDS, DEFAULT_MAP_YARDS
end

local function DistTo(it)
    local pw = PlayerWorld(it.map)
    if pw then
        local _, w = C_Map.GetWorldPosFromMapPos(it.map, CreateVector2D(it.x, it.y))
        if w then return math.sqrt((w.x - pw.x) ^ 2 + (w.y - pw.y) ^ 2) end
    end
    local p = C_Map.GetPlayerMapPosition(it.map, "player")
    if not p then return end
    local mw, mh = MapYards(it.map)
    return math.sqrt(((it.x - p.x) * mw) ^ 2 + ((it.y - p.y) * mh) ^ 2)
end

-- Every distinct map marker in a delve is logged once per run, tracked or
-- not, so a pickup the addon misses shows up in /tw log under its real name.
local function NoteMarker(info, kind, hasPos)
    run.markers = run.markers or {}
    local name = not Readable(info.name) and (info.name == nil and "<no name>" or "<hidden by the game>") or tostring(info.name)
    local k = name .. (hasPos and "" or " (no position)")
    if run.markers[k] then return end
    run.markers[k] = true
    ns.Log("MARKER", "%s | atlas %s | %s%s", name, tostring(info.atlasName), kind and ("tracked as " .. kind) or "NOT tracked",
        hasPos and "" or " | game gave no map position")
end

local function NoteUnnamed(vid, pos)
    run.markers = run.markers or {}
    local k = ("unnamed %s@%.2f,%.2f"):format(tostring(vid), pos.x, pos.y)
    if run.markers[k] then return end
    run.markers[k] = true
    ns.Log("MARKER", "<no info from the game> | vignette id %s | %.1f, %.1f | %s", tostring(vid), pos.x * 100, pos.y * 100,
        IGNORED_VIGNETTES[vid] and "ignored" or ("listed as " .. UNKNOWN_NAME))
end

local function MarkerPos(guid, map)
    local ok, pos = pcall(C_VignetteInfo.GetVignettePosition, guid, map)
    if ok and Readable(pos) and pos then
        local x, y = pos.x, pos.y
        if Readable(x) and Readable(y) and type(x) == "number" then return pos end
    end
end

-- /tw curios scan: everything the game is showing right now.
function ns.CurioScanReport()
    local map = C_Map.GetBestMapForUnit("player")
    local list = C_VignetteInfo and C_VignetteInfo.GetVignettes() or {}
    ns.Print(("map %s, in delve: %s, markers visible: %d"):format(tostring(map), tostring(inDelve), #list))
    for _, guid in ipairs(list) do
        local info = C_VignetteInfo.GetVignetteInfo(guid)
        local pos = map and MarkerPos(guid, map)
        local where = pos and ("%.1f, %.1f"):format(pos.x * 100, pos.y * 100) or "no position"
        if Readable(info) and info then
            local kind = Kind(info)
            local secret = not Readable(info.name)
            ns.Print(("  %s | atlas %s | %s | %s"):format(secret and "<hidden by the game>" or tostring(info.name),
                tostring(info.atlasName), kind and ("tracked as " .. kind) or "not tracked", where))
        else
            local vid = VignetteID(guid)
            ns.Print(("  <no info from the game> | vignette id %s | %s | %s"):format(tostring(vid),
                IGNORED_VIGNETTES[vid] and "ignored" or "listed as unnamed", where))
        end
    end
end

local function Scan()
    local map = C_Map.GetBestMapForUnit("player")
    if not map or not C_VignetteInfo then return end
    local seen, changed = {}, false
    local copies = {} -- the game spawns one copy of each curiosity per player
    local vignettes = C_VignetteInfo.GetVignettes() or {}
    for _, guid in ipairs(vignettes) do
        local info = C_VignetteInfo.GetVignetteInfo(guid)
        local zone = Readable(info) and info and Kind(info)
            and ZoneOf(Safe(function() return info.objectGUID end))
        if zone then
            if run.zone and run.zone ~= zone then
                NewRun("curiosities belong to a different copy of the delve")
                changed = true
            end
            run.zone = zone
            break
        end
    end
    local function Track(key, kind, name, pos)
        local it, new = AddItem(key, kind, name, map, pos.x, pos.y)
        if kind == UNKNOWN and it.kind ~= UNKNOWN then
            -- Unnamed duplicate of a marker we already know by name: don't count it as a copy.
            seen[it.key] = true
            return
        end
        it.x, it.y, it.map = pos.x, pos.y, map
        it.wx, it.wy = World(map, pos.x, pos.y)
        seen[it.key] = true
        copies[it.key] = (copies[it.key] or 0) + 1
        if new then
            changed = true
            ns.Log("CURIO", "found %s at %.1f,%.1f (key: %s)", it.name, pos.x * 100, pos.y * 100,
                kind == UNKNOWN and "no info from the game" or key:find("@", 1, true) and "name+position, GUID hidden" or "object GUID")
            if Syncable(it) then Broadcast(Encode(it, "F")) end
        end
        if it.gone then
            -- The marker only dropped out of view; it's still there.
            ns.Log("CURIO", "%s marker is back (was flagged gone)", it.name)
            it.gone = nil
            changed = true
        end
        if not it.present then it.present = true; changed = true end
    end

    for _, guid in ipairs(vignettes) do
        local info = C_VignetteInfo.GetVignetteInfo(guid)
        local pos = MarkerPos(guid, map)
        if Readable(info) and info then
            local kind, name = Kind(info)
            NoteMarker(info, kind, pos ~= nil)
            if kind and pos then
                -- Object GUID is the same for everyone in the instance; fall
                -- back to name + position if it is hidden.
                local key = Safe(function() return info.objectGUID end)
                    or ("%s@%.3f,%.3f"):format(name, pos.x, pos.y)
                Track(key, kind, name, pos)
            end
        elseif pos then
            -- WoW reports something here but says nothing about it.
            local vid = VignetteID(guid)
            NoteUnnamed(vid, pos)
            if not IGNORED_VIGNETTES[vid] then
                Track(("unnamed@%.3f,%.3f"):format(pos.x, pos.y), UNKNOWN, UNKNOWN_NAME, pos)
            end
        end
    end
    -- Copies that vanished since the last scan. One copy disappearing right
    -- next to you is your pickup, even while your partner's copy stays visible.
    for _, key in ipairs(run.order) do
        local it = run.items[key]
        if it.map == map then
            local now, before = copies[key] or 0, it.copies or 0
            if now < before then
                local d = DistTo(it)
                if d and d <= LOOT_RANGE then
                    ns.Log("CURIO", "%s: a copy vanished %d yd from you (%d -> %d) -> YOUR pickup", it.name, d, before, now)
                    MarkLooted(it, me)
                    changed = true
                elseif now == 0 and d and d > VIEW_RANGE then
                    -- Just out of view (~250 yd); not a pickup, not gone.
                    it.present = false
                elseif now == 0 then
                    it.present = false
                    it.gone = true
                    changed = true
                    ns.Log("CURIO", "%s marker vanished %s from you -> 'marker gone' (someone without the addon took it?)",
                        it.name, d and (math.floor(d) .. " yd") or "at unknown distance")
                else
                    ns.Log("CURIO", "%s: a copy vanished %s away (%d -> %d) - another player's pickup",
                        it.name, d and (math.floor(d) .. " yd") or "?", before, now)
                end
            end
            it.copies = now
        end
    end
    if changed then ns.RefreshCurios() end
end

---------------------------------------------------------------------------
-- Guide arrow. WoW won't place map waypoints inside instances, so clicking a
-- curiosity shows our own on-screen arrow + distance (and still tries
-- Blizzard's waypoint and TomTom, in case they work there).
---------------------------------------------------------------------------
local arrow, arrowTarget
local ARRIVE_YARDS = 6
local DIRS8 = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local tomtomUID -- the TomTom waypoint we placed, so it can be removed again

local function UseOwnArrow()
    -- "auto": TomTom's arrow when TomTom is installed, ours otherwise.
    local mode = db.arrowMode or "auto"
    if mode == "own" or mode == "both" then return true end
    return not (TomTom and TomTom.AddWaypoint)
end

local function ClearTomTom()
    if tomtomUID and TomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, tomtomUID) end
    tomtomUID = nil
end

local function ClearArrow(reason)
    arrowTarget = nil
    if arrow then arrow:Hide() end
    ClearTomTom()
    if reason then ns.Print(reason) end
end

-- Your pickup clears the guide (our arrow and the TomTom waypoint), even
-- while our arrow is hidden in TomTom mode.
function ns.CurioArrowLooted(it)
    if arrowTarget == it then ClearArrow("got it - arrow cleared.") end
end

function ns.SetArrowMode(mode)
    if mode == "auto" or mode == "own" or mode == "tomtom" or mode == "both" then
        db.arrowMode = mode
        ns.Print("curiosity guide arrow: " .. mode .. (mode == "auto" and " (TomTom if installed, otherwise the addon's own)" or "") .. ".")
    else
        ns.Print("curiosity guide arrow is '" .. (db.arrowMode or "auto") .. "'. Options: /tw curios arrow auto | tomtom | own | both"
            .. (TomTom and "  (TomTom is installed)" or "  (TomTom is not installed)"))
    end
end

-- Bearing to the target, clockwise from north, in radians (map coords
-- scaled by the map's real size so it isn't skewed).
local function Bearing(it)
    local p = C_Map.GetPlayerMapPosition(it.map, "player")
    if not p then return end
    local w, h = 1, 1
    if C_Map.GetMapWorldSize then
        local mw, mh = C_Map.GetMapWorldSize(it.map)
        if mw and mw > 0 then w, h = mw, mh end
    end
    local east, north = (it.x - p.x) * w, (p.y - it.y) * h
    return math.atan2(east, north)
end

local function UpdateArrow()
    local it = arrowTarget
    if not it then return end
    if it.looted[me] then ClearArrow("got it - arrow cleared.") return end
    if not arrow:IsShown() then return end
    local d = DistTo(it)
    local b = Bearing(it)
    if d and d <= ARRIVE_YARDS then
        arrow.text:SetText("|cff33ff33You're there|r")
        arrow.tex:Hide()
        return
    end
    arrow.text:SetText(d and ("%d yd"):format(d) or "?")
    local facing = Safe(GetPlayerFacing)
    if b and facing then
        -- Facing is counter-clockwise from north; the texture points up.
        arrow.tex:Show()
        arrow.tex:SetRotation(-b - facing)
        arrow.dir:SetText("")
    elseif b then
        -- No facing available here: fall back to a compass direction.
        arrow.tex:Hide()
        local i = math.floor((b % (2 * math.pi)) / (2 * math.pi) * 8 + 0.5) % 8
        arrow.dir:SetText(DIRS8[i + 1])
    end
end

local function CreateArrow()
    arrow = CreateFrame("Button", "TippWorksCuriosArrow", UIParent)
    arrow:SetSize(70, 90)
    local pos = db.arrowPos
    if pos then arrow:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else arrow:SetPoint("TOP", UIParent, "TOP", 0, -200) end
    arrow:SetMovable(true)
    arrow:RegisterForDrag("LeftButton")
    arrow:RegisterForClicks("RightButtonUp")
    arrow:SetScript("OnDragStart", arrow.StartMoving)
    arrow:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        db.arrowPos = { p, rp, x, y }
    end)
    arrow:SetScript("OnClick", function() ClearArrow("arrow cleared.") end)
    arrow.tex = arrow:CreateTexture(nil, "ARTWORK")
    arrow.tex:SetTexture("Interface\\Minimap\\MinimapArrow")
    arrow.tex:SetSize(56, 56)
    arrow.tex:SetPoint("TOP")
    arrow.tex:SetVertexColor(1, 0.82, 0)
    arrow.dir = arrow:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    arrow.dir:SetPoint("CENTER", arrow.tex, "CENTER")
    arrow.text = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    arrow.text:SetPoint("BOTTOM")
    arrow:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(arrowTarget and arrowTarget.name or "Curiosity")
        GameTooltip:AddLine("Drag to move  |  Right-click to clear", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    arrow:SetScript("OnLeave", GameTooltip_Hide)
    local acc = 0
    arrow:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 0.05 then acc = 0; UpdateArrow() end
    end)
    arrow:Hide()
end

local function GuideTo(it)
    if not arrow then CreateArrow() end
    ClearTomTom()
    arrowTarget = it
    arrow:SetShown(UseOwnArrow())
    UpdateArrow()
    -- Bonus routes, if this content allows them.
    local pinned = false
    if C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(it.map) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(it.map, it.x, it.y))
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        pinned = true
    end
    local viaTomTom = false
    if TomTom and TomTom.AddWaypoint and (db.arrowMode or "auto") ~= "own" then
        local ok, uid = pcall(TomTom.AddWaypoint, TomTom, it.map, it.x, it.y,
            { title = it.name, persistent = false, crazy = true, from = "Tippenhauer Works" })
        if ok and uid then tomtomUID = uid; viaTomTom = true end
        ns.Log("CURIO", "TomTom waypoint for %s: %s", it.name, ok and (uid and "set" or "no waypoint returned") or ("error " .. tostring(uid)))
    end
    ns.Print(("guiding to %s (%.1f, %.1f) - %s%s."):format(it.name, it.x * 100, it.y * 100,
        viaTomTom and (UseOwnArrow() and "TomTom + addon arrow" or "follow TomTom's arrow") or "follow the arrow",
        pinned and ", map pin set too" or ""))

end

---------------------------------------------------------------------------
-- Pickups from the loot itself. A marker can stay up (and keep sparkling)
-- after you've looted it, so a vanishing marker alone misses pickups.
---------------------------------------------------------------------------
local function ItemByGUID(guid)
    if not run or type(guid) ~= "string" then return end
    return run.items[(run.alias and run.alias[guid]) or guid]
end

-- 1) Loot window: WoW names the exact object the loot came from.
local function OnLootOpened()
    if not run or not GetNumLootItems then return end
    for slot = 1, GetNumLootItems() do
        local sources = { pcall(GetLootSourceInfo, slot) }
        if sources[1] then
            for i = 2, #sources, 2 do
                local guid = sources[i]
                if not (issecretvalue and issecretvalue(guid)) then
                    local it = ItemByGUID(guid)
                    if it and not it.looted[me] then
                        ns.Log("CURIO", "%s at %.1f,%.1f: loot window from it -> YOUR pickup", it.name, it.x * 100, it.y * 100)
                        MarkLooted(it, me)
                    end
                end
            end
        end
    end
end

-- 2) "You receive loot: [Boon of ...]" - Boons only come from curiosities,
-- and this also catches walk-over pickups (e.g. Dundun's Favor) with no
-- loot window: credit the nearest one you haven't got yet.
local CLAIM_YARDS = 30
local function OnLootMessage(msg)
    if not run then return end
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then
        ns.Log("CURIO", "a loot message arrived but the game hid its text - can't use it")
        return
    end
    if not (msg:find("^You receive") and msg:find("Boon of", 1, true)) then return end
    local best, bestD
    for _, k in ipairs(run.order) do
        local it = run.items[k]
        if not it.looted[me] then
            local d = DistTo(it)
            if d and d <= CLAIM_YARDS and (not bestD or d < bestD) then best, bestD = it, d end
        end
    end
    if best then
        ns.Log("CURIO", "%s at %.1f,%.1f: got a Boon %d yd from it -> YOUR pickup", best.name, best.x * 100, best.y * 100, bestD)
        MarkLooted(best, me)
        return
    end
    -- One pickup can send two Boon lines, sometimes after the pickup was already
    -- counted (marker vanished next to you): those aren't new curiosities.
    if lastMine and GetTime() - lastMine < 10 then
        ns.Log("CURIO", "got a Boon - already counted (pickup %.1fs ago)", GetTime() - lastMine)
        return
    end
    for _, k in ipairs(run.order) do
        local it = run.items[k]
        local d = it.looted[me] and DistTo(it)
        if d and d <= CLAIM_YARDS then
            ns.Log("CURIO", "got a Boon %d yd from %s you already have - already counted", d, it.name)
            return
        end
    end
    local map = C_Map.GetBestMapForUnit("player")
    local p = map and C_Map.GetPlayerMapPosition(map, "player")
    if not p then
        ns.Log("CURIO", "got a Boon, no curiosity known nearby and no position to record it")
        return
    end
    local it = AddItem(("pickup@%d"):format(time()), PICKUP, PICKUP_NAME, map, p.x, p.y)
    it.present = false
    ns.Log("CURIO", "got a Boon with no curiosity known nearby -> added '%s' at %.1f,%.1f", PICKUP_NAME, p.x * 100, p.y * 100)
    MarkLooted(it, me)
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local function WhoText(it)
    local names = {}
    for who in pairs(it.looted) do names[#names + 1] = who == me and "you" or who end
    table.sort(names)
    return table.concat(names, ", ")
end

function ns.RefreshCurios()
    if not frame or not run then return end
    local total, mine = #run.order, 0
    for i = 1, MAX_ROWS do
        local row, key = rows[i], run.order[i]
        local it = key and run.items[key]
        if it then
            local who = WhoText(it)
            if it.looted[me] then mine = mine + 1 end
            row.name:SetText(it.kind == UNKNOWN and ("|cffcc8cff" .. it.name .. "|r") or it.name)
            local d = DistTo(it)
            local where = d and ("%d yd"):format(d) or ""
            if who ~= "" then
                row.status:SetText("|cff33ff33" .. who .. "|r")
                row:SetAlpha(it.looted[me] and 0.5 or 0.85)
            elseif it.gone then
                row.status:SetText("|cffaaaaaamarker gone|r")
                row:SetAlpha(0.7)
            else
                row.status:SetText("|cffffd100open|r  " .. where)
                row:SetAlpha(1)
            end
            row.item = it
            row:Show()
        else
            row:Hide()
        end
    end
    for i = 1, total do
        local it = run.items[run.order[i]]
        if i > MAX_ROWS and it.looted[me] then mine = mine + 1 end
    end
    local users = {}
    for n, v in pairs(addonUsers) do
        -- Red when a partner runs a different version than you.
        local same = v == ns.VERSION
        users[#users + 1] = ("%s %s"):format(n, same and ("|cff888888v" .. v .. "|r")
            or ("|cffff5555" .. (v == "?" and "v?" or v == "older" and "old version" or ("v" .. v)) .. "|r"))
    end
    frame.footer:SetText(("Found %d  |  you: %d%s"):format(total, mine,
        #users > 0 and ("  |  synced: " .. table.concat(users, ", ")) or "  |  no party sync"))
    frame:SetHeight(48 + math.max(1, math.min(total, MAX_ROWS)) * ROW_H + 24)
    frame.empty:SetShown(total == 0)
    ns.DrawCurioPins()
end

local function CreatePanel()
    frame = CreateFrame("Frame", "TippWorksCuriosPanel", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, 100)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.8)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        db.curioPos = { p, rp, x, y }
    end)
    local pos = db.curioPos
    if pos then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else frame:SetPoint("LEFT", UIParent, "LEFT", 40, 0) end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Delve Curiosities")
    local ver = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ver:SetPoint("TOPRIGHT", -30, -13)
    ver:SetText("v" .. ns.VERSION)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() frame:Hide() end)

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.empty:SetPoint("TOPLEFT", 14, -40)
    frame.empty:SetText("None spotted yet - they appear as you find them\nor when a reveal buff shows them on the map.")
    frame.empty:SetJustifyH("LEFT")

    for i = 1, MAX_ROWS do
        local r = CreateFrame("Button", nil, frame)
        r:SetSize(WIDTH - 20, ROW_H)
        r:SetPoint("TOPLEFT", 10, -36 - (i - 1) * ROW_H)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        r.name:SetPoint("LEFT", 4, 0)
        r.status = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.status:SetPoint("RIGHT", -4, 0)
        r:SetScript("OnClick", function(self, btn)
            local it = self.item
            if not it then return end
            if btn == "RightButton" then -- manual fix-up
                if it.looted[me] then it.looted[me] = nil; ns.RefreshCurios() else MarkLooted(it, me) end
            elseif IsShiftKeyDown() then
                OpenWorldMap(it.map)
            else
                GuideTo(it)
            end
        end)
        r:SetScript("OnEnter", function(self)
            local it = self.item
            if not it then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(it.name)
            GameTooltip:AddLine(("%.1f, %.1f   |cff888888copies on the map: %s|r"):format(it.x * 100, it.y * 100,
                it.copies ~= nil and tostring(it.copies) or "?"), 1, 1, 1)
            local who = WhoText(it)
            GameTooltip:AddLine(who ~= "" and ("Picked up by: " .. who) or "Nobody (that we know of) has it yet", 1, 1, 1)
            if it.kind == PICKUP then
                GameTooltip:AddLine("Counted from the Boon you received - the game never showed a marker for it.", 0.8, 0.8, 0.8, true)
            end
            if it.kind == UNKNOWN then
                GameTooltip:AddLine("WoW shows a marker here but won't say what it is. Often a curiosity, but it can be"
                    .. " another object. It gets its real name once the game reveals it (usually up close).", 0.8, 0.55, 1, true)
            end
            if it.gone and who == "" then
                GameTooltip:AddLine("The map marker disappeared: someone without the addon took it, or it's out of view.", 0.8, 0.8, 0.8, true)
            end
            GameTooltip:AddLine("Party members without this addon can't be seen.", 0.6, 0.6, 0.6, true)
            GameTooltip:AddLine("Left-click: arrow to it  |  Shift-click: open map", 0.6, 0.6, 0.6)
            GameTooltip:AddLine("Right-click: toggle 'I got this'", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", GameTooltip_Hide)
        r:Hide()
        rows[i] = r
    end

    frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.footer:SetPoint("BOTTOMLEFT", 12, 10)
    frame:Hide()
end

---------------------------------------------------------------------------
-- World map markers (persist after the in-game marker is gone)
---------------------------------------------------------------------------
function ns.DrawCurioPins()
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local canvas = WorldMapFrame.ScrollContainer.Child
    if not overlay then
        overlay = CreateFrame("Frame", nil, canvas)
        overlay:SetAllPoints(canvas)
        overlay:SetFrameLevel(canvas:GetFrameLevel() + 2100)
    end
    for _, p in ipairs(pins) do p:Hide() end
    if not run or not inDelve then return end
    local shown = WorldMapFrame:GetMapID()
    local w, h = canvas:GetSize()
    local size = math.max(12, (w or 0) / 50)
    local n = 0
    for _, key in ipairs(run.order) do
        local it = run.items[key]
        if it.map == shown then
            n = n + 1
            local p = pins[n]
            if not p then
                p = CreateFrame("Frame", nil, overlay)
                p.tex = p:CreateTexture(nil, "OVERLAY")
                p.tex:SetAllPoints()
                p.tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                pins[n] = p
            end
            p:SetSize(size, size)
            p:ClearAllPoints()
            p:SetPoint("CENTER", overlay, "TOPLEFT", it.x * w, -it.y * h)
            local got = next(it.looted) ~= nil
            -- Green tick = someone has it; gold ? = still to grab; grey = gone.
            p.tex:SetTexture(got and "Interface\\RaidFrame\\ReadyCheck-Ready"
                or it.gone and "Interface\\RaidFrame\\ReadyCheck-NotReady"
                or "Interface\\RaidFrame\\ReadyCheck-Waiting")
            p:Show()
        end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")

local lastPEWWasReload = false
local function Enter(fresh)
    local name, instType, diff = GetInstanceInfo()
    ns.Log("CURIO", "entered delve %s (type %s, difficulty %s), group: %s%s", tostring(name), tostring(instType),
        tostring(diff), IsInGroup() and (Channel() or "?") or "solo", fresh and "" or " (after /reload - keeping the list)")
    StartRunIfNeeded(fresh)
    if not frame:IsShown() then frame:Show() end
    Broadcast("H|" .. ns.VERSION)
    ns.RefreshCurios()
end

local lastAsk = 0
local function OnAddonMessage(prefix, msg, _, sender)
    if prefix ~= PREFIX then return end
    local who = Ambiguate(sender, "short")
    if who == me then return end
    ns.Log("SYNC", "from %s: %s", who, msg)
    local tag, key, kind, x, y, map, name = strsplit("|", msg, 7)
    -- Versions are swapped whether or not a delve run is being tracked:
    -- hello ("H") and its reply ("R") carry the sender's version (older
    -- versions sent a bare "H" and ignore "R").
    if tag == "H" or tag == "R" then
        addonUsers[who] = key or "older"
    else
        if not addonUsers[who] or addonUsers[who] == "?" then
            addonUsers[who] = "?"
            -- Hearing from someone whose version we don't know: ask (a hello
            -- makes them reply with theirs). At most every 15s.
            if GetTime() - lastAsk > 15 then
                lastAsk = GetTime()
                lastHello = 0
                Broadcast("H|" .. ns.VERSION)
            end
        end
    end
    if tag == "R" then ns.RefreshCurios() return end
    if tag == "H" then
        -- Answer with our own version so both sides show it, even after
        -- only one of you reloaded. A reply is never answered (no ping-pong).
        Broadcast("R|" .. ns.VERSION)
        if not inDelve or not run then ns.RefreshCurios() return end
        -- Someone joined (or reloaded): tell them what we know, at most once a minute each.
        answered = answered or {}
        if answered[who] and GetTime() - answered[who] < 60 then ns.RefreshCurios() return end
        answered[who] = GetTime()
        for _, k in ipairs(run.order) do
            local it = run.items[k]
            if Syncable(it) then Broadcast(Encode(it, it.looted[me] and "L" or "F")) end
        end
        ns.RefreshCurios()
        return
    end
    if not run then return end -- pickups only mean something during a delve run
    local zone = ZoneOf(key)
    if zone and run.zone and zone ~= run.zone then return end -- from another delve copy
    x, y, map = tonumber(x), tonumber(y), tonumber(map)
    if not (key and x and y and map) then return end
    local it = AddItem(key, kind, name, map, x, y)
    if tag == "L" then MarkLooted(it, who, true) else ns.RefreshCurios() end
end

function ns.InitCurios()
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    CreatePanel()
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("CHAT_MSG_ADDON")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("LOOT_OPENED")
    ev:RegisterEvent("CHAT_MSG_LOOT")
    ev:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            local _, isReload = ...
            lastPEWWasReload = isReload and true or false
            inDelve = IsDelve()
            if inDelve and not wasInDelve then Enter(not lastPEWWasReload)
            elseif not inDelve and wasInDelve ~= false then frame:Hide(); wipe(addonUsers); ClearArrow() end
            wasInDelve = inDelve
        elseif event == "CHAT_MSG_ADDON" then
            OnAddonMessage(...)
        elseif event == "PLAYER_REGEN_ENABLED" then
            Flush()
        elseif event == "LOOT_OPENED" and inDelve then
            ns.Guard("curio loot", OnLootOpened)
        elseif event == "CHAT_MSG_LOOT" and inDelve then
            local msg = ...
            ns.Guard("curio loot msg", OnLootMessage, msg)
        elseif event == "GROUP_ROSTER_UPDATE" and inDelve then
            Broadcast("H|" .. ns.VERSION)
        end
    end)
    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", ns.DrawCurioPins)
        if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", ns.DrawCurioPins) end
    end
    C_Timer.NewTicker(0.4, SendOne) -- drain the sync queue gently
    local tick = 0
    C_Timer.NewTicker(0.5, function()
        -- Delves can start (scenario begins) after the loading screen.
        if not inDelve and IsInInstance() and IsDelve() then
            inDelve, wasInDelve = true, true
            Enter(not lastPEWWasReload)
        end
        if not inDelve then return end
        run.lastSeen = time()
        ns.Guard("curio scan", Scan)
        tick = tick + 1
        if tick % 4 == 0 and frame:IsShown() then ns.RefreshCurios() end -- distances
    end)
end

function ns.ToggleCurios()
    if not frame then return end
    if frame:IsShown() then frame:Hide() else frame:Show(); ns.RefreshCurios() end
end

---------------------------------------------------------------------------
-- TippWorks registration, /tw curios, saved data
---------------------------------------------------------------------------
local function Summary(tt)
    if inDelve and run then
        local mine = 0
        for _, k in ipairs(run.order) do if run.items[k].looted[me] then mine = mine + 1 end end
        tt:AddLine(("Curiosities: %d found, you have %d"):format(#run.order, mine), 1, 1, 1)
    else
        tt:AddLine("Curiosities: panel opens by itself in delves", 1, 1, 1)
    end
end

local module
local function Command(rest)
    local sub, arg = rest:match("^(%S*)%s*(.-)$")
    sub = (sub or ""):lower()
    if sub == "" or sub == "show" or sub == "toggle" then ns.ToggleCurios()
    elseif sub == "reset" then ns.ResetCurioRun()
    elseif sub == "scan" then ns.CurioScanReport()
    elseif sub == "arrow" then ns.SetArrowMode((arg or ""):lower())
    else TW.ModuleHelp(module) end
end

module = TW.Register({
    key = "curios", aliases = { "curiosities", "curio" },
    name = "Delve Curiosities", addon = ADDON, version = ns.VERSION,
    command = Command, toggle = ns.ToggleCurios, summary = Summary,
    help = {
        { "", "show/hide the curiosities panel (opens by itself in delves)" },
        { "reset", "clear this delve's list" },
        { "scan", "print every map marker the game shows right now" },
        { "arrow auto|tomtom|own|both", "which guide arrow a row click uses" },
    },
})

-- Blizzard's AddOns compartment (the menu button by the minimap); named in the .toc.
function TippWorksCurios_OnAddonCompartmentClick() ns.ToggleCurios() end
function TippWorksCurios_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff" .. TW.COLOR .. "Tippenhauer Works|r - Delve Curiosities")
    Summary(GameTooltip)
    GameTooltip:AddLine("Click: show/hide  |  /tw curios help", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end
function TippWorksCurios_OnAddonCompartmentLeave() GameTooltip:Hide() end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    TippWorksCuriosDB = TippWorksCuriosDB or {}
    db = TippWorksCuriosDB
    -- One-time: carry settings and the current run over from CoiledRareTracker
    -- (loaded first via OptionalDeps, so its saved data is already here).
    if not db.migrated then
        local old = CoiledRareTrackerDB
        if type(old) == "table" then
            for _, k in ipairs({ "arrowMode", "arrowPos", "curioPos", "curioRun" }) do
                if db[k] == nil then db[k] = old[k] end
            end
            ns.Log("CURIO", "copied curiosity settings from CoiledRareTracker")
        end
        db.migrated = true
    end
    ns.Log("INFO", "TippWorks-Curios v%s loaded", ns.VERSION)
    ns.InitCurios()
end)
