local ADDON, ns = ...
local TW = TippWorks

-- Coiled Isle daily rares: kill tracking, distances, waypoint + target +
-- skull on click, a saved route on the world map (Route.lua) and a target
-- popup (Target.lua). Saved data keeps CoiledRareTracker's names
-- (CoiledRareTrackerDB) so kills, routes and settings carry over.
ns.VERSION = ns.VERSION or C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?" -- set in Data.lua
ns.Log, ns.Guard = TW.Log, TW.Guard
local db
local zoneMapID
local byName = {}
local rows = {}
local frame
local pendingToggle
local wasInZone
local SKULL = 8

local ROW_H, WIDTH = 18, 350
local TOP = 36 -- title
ns.WIDTH = WIDTH

local Print = TW.Printer("Rares")
-- Guard against Midnight "secret values": anything restricted in combat is skipped.
local Safe = TW.Safe

---------------------------------------------------------------------------
-- Daily reset
---------------------------------------------------------------------------
local function CheckReset()
    local now = time()
    if db.resetAt and now >= db.resetAt then
        wipe(db.killed)
        wipe(db.absent)
        db.route = nil
        Print("daily reset - all rares are up again. Press New Route to plan today's run.")
    end
    local secs = C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset and C_DateAndTime.GetSecondsUntilDailyReset()
    if secs then db.resetAt = now + secs end
end

---------------------------------------------------------------------------
-- Zone map lookup (found by name, so no hard-coded uiMapID to go stale)
---------------------------------------------------------------------------
local function NameMatches(info)
    return info and info.name and info.name:find(ns.ZONE_NAME, 1, true)
end

local function ZoneMap()
    if zoneMapID then return zoneMapID end
    if ns.ZONE_MAP_ID and NameMatches(C_Map.GetMapInfo(ns.ZONE_MAP_ID)) then
        zoneMapID = ns.ZONE_MAP_ID
        db.mapID = zoneMapID
        return zoneMapID
    end
    if db.mapID and NameMatches(C_Map.GetMapInfo(db.mapID)) then
        zoneMapID = db.mapID
        return zoneMapID
    end
    -- Walk up from where the player is standing.
    local m = C_Map.GetBestMapForUnit("player")
    while m and m > 0 do
        local info = C_Map.GetMapInfo(m)
        if NameMatches(info) and info.mapType == Enum.UIMapType.Zone then
            zoneMapID = m
            break
        end
        m = info and info.parentMapID
    end
    -- Otherwise scan the Midnight-era map id range.
    if not zoneMapID then
        local fallback
        for id = 2300, 3500 do
            local info = C_Map.GetMapInfo(id)
            if NameMatches(info) then
                if info.mapType == Enum.UIMapType.Zone then zoneMapID = id break end
                fallback = fallback or id
            end
        end
        zoneMapID = zoneMapID or fallback
    end
    db.mapID = zoneMapID
    return zoneMapID
end

-- In the Coiled Isle itself - not in a delve or any other instance there.
local function InCoiledIsle()
    if IsInInstance() then return false end
    local map = ZoneMap()
    local here = C_Map.GetBestMapForUnit("player")
    while map and here and here > 0 do
        if here == map then return true end
        local info = C_Map.GetMapInfo(here)
        here = info and info.parentMapID
    end
    return false
end
ns.InCoiledIsle = InCoiledIsle

local function Coords(r)
    local c = db.custom[r.name]
    if c then return c.x, c.y end
    return r.x, r.y
end

---------------------------------------------------------------------------
-- Distance / direction
---------------------------------------------------------------------------
local DIRS = { "E", "SE", "S", "SW", "W", "NW", "N", "NE" }

local function PlayerWorldPos()
    local m = C_Map.GetBestMapForUnit("player")
    if not m then return end
    local p = C_Map.GetPlayerMapPosition(m, "player")
    if not p then return end
    return C_Map.GetWorldPosFromMapPos(m, p)
end

local function DistanceTo(r, pCont, pWorld)
    local map, x, y = ZoneMap(), Coords(r)
    if not (map and x and pWorld) then return end
    local cont, w = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x / 100, y / 100))
    if not w or cont ~= pCont then return end
    local dx, dy = w.x - pWorld.x, w.y - pWorld.y
    local dist = math.sqrt(dx * dx + dy * dy)

    -- Direction from zone-map coordinates (x grows east, y grows south).
    local dir
    local pp = C_Map.GetPlayerMapPosition(map, "player")
    if pp and dist > 15 then
        local ang = math.atan2(y / 100 - pp.y, x / 100 - pp.x) -- 0 = east, +pi/2 = south
        local i = math.floor((ang / (2 * math.pi)) * 8 + 0.5) % 8
        dir = DIRS[i + 1]
    end
    return dist, dir
end

-- Expose for Route.lua
ns.ZoneMap = ZoneMap
ns.Coords = Coords
ns.Print = Print

---------------------------------------------------------------------------
-- Route: nearest-neighbour then 2-opt over the rares still up today
---------------------------------------------------------------------------
local function PointFor(map, x, y)
    local _, w = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x, y))
    -- World yards when available so the map's aspect ratio doesn't skew it.
    if w then return w.x, w.y end
    return x * 1000, y * 1000
end

local function Dist(a, b)
    if not a or not b then return 0 end
    local dx, dy = a.wx - b.wx, a.wy - b.wy
    return math.sqrt(dx * dx + dy * dy)
end

-- Returns start (player point or nil) and an ordered list of { rare, x, y } (x/y 0-1).
function ns.BuildRoute()
    local map = ZoneMap()
    if not map then return nil, {} end
    local todo = {}
    for _, r in ipairs(ns.RARES) do
        local x, y = Coords(r)
        if x and not db.killed[r.name] then
            local p = { rare = r, x = x / 100, y = y / 100 }
            p.wx, p.wy = PointFor(map, p.x, p.y)
            todo[#todo + 1] = p
        end
    end

    local start
    local pp = C_Map.GetPlayerMapPosition(map, "player")
    if pp and pp.x > 0 and pp.x < 1 and pp.y > 0 and pp.y < 1 then
        start = { x = pp.x, y = pp.y }
        start.wx, start.wy = PointFor(map, pp.x, pp.y)
    end

    -- Nearest neighbour from the player (or from the first rare).
    local path, cur = {}, start
    while #todo > 0 do
        local bi, bd = 1, math.huge
        if cur then
            for i, p in ipairs(todo) do
                local d = Dist(cur, p)
                if d < bd then bi, bd = i, d end
            end
        end
        cur = table.remove(todo, bi)
        path[#path + 1] = cur
    end

    -- 2-opt on an open path with a fixed start.
    local n = #path
    local function P(i) if i == 0 then return start else return path[i] end end
    local improved = true
    while improved do
        improved = false
        for i = 1, n - 1 do
            for k = i + 1, n do
                local a, b, c, d = P(i - 1), path[i], path[k], path[k + 1]
                local before = (a and Dist(a, b) or 0) + (d and Dist(c, d) or 0)
                local after = (a and Dist(a, c) or 0) + (d and Dist(b, d) or 0)
                if after + 0.5 < before then
                    local lo, hi = i, k
                    while lo < hi do
                        path[lo], path[hi] = path[hi], path[lo]
                        lo, hi = lo + 1, hi - 1
                    end
                    improved = true
                end
            end
        end
    end
    return start, path
end

---------------------------------------------------------------------------
-- Kill detection
---------------------------------------------------------------------------
local SetWaypoint
local ABSENT_RANGE = 100 -- yards, flat distance, so flying over a spawn counts
local SEEN_FRESH = 60    -- seconds a sighting counts as "up"
local seenAt = {}

-- "killed", "absent" (flew past, not there), "up" (spotted recently) or nil.
function ns.State(name)
    if db.killed[name] then return "killed" end
    if db.absent[name] then return "absent" end
    if seenAt[name] and GetTime() - seenAt[name] < SEEN_FRESH then return "up" end
end

local function Changed()
    ns.Refresh()
    if ns.DrawRoute then ns.DrawRoute() end
end

-- Next rare on the saved route that is neither killed nor known to be missing.
local function NextOnRoute()
    local _, route = ns.GetRoute()
    if #route == 0 then _, route = ns.BuildRoute() end
    for _, p in ipairs(route) do
        if not db.killed[p.rare.name] and not db.absent[p.rare.name] then return p.rare end
    end
    for _, p in ipairs(route) do
        if not db.killed[p.rare.name] then return p.rare end
    end
end

local function MarkKilled(name, silent, how)
    if db.killed[name] then return end
    db.killed[name] = time()
    db.absent[name] = nil
    ns.Log("RARE", "%s killed (%s)", name, how or "unit seen dead")
    if not silent then Print(name .. " marked as killed for today.") end
    if db.autoNext then
        local r = NextOnRoute()
        if r then SetWaypoint(r, true) end
    end
    Changed()
end

local function Spotted(name)
    if not byName[name] or db.killed[name] then return end
    local now = GetTime()
    local announce = db.absent[name] or not seenAt[name] or now - seenAt[name] > SEEN_FRESH
    seenAt[name] = now
    db.absent[name] = nil
    if announce then
        Print("|cff00ff00" .. name .. " is UP!|r")
        ns.Log("RARE", "%s spotted", name)
        pcall(PlaySound, SOUNDKIT.RAID_WARNING)
        Changed()
    end
end

local function SpotUnit(unit)
    if not UnitExists(unit) then return end
    local name = Safe(UnitName, unit)
    if name and byName[name] and not Safe(UnitIsDead, unit) then Spotted(name) end
end

-- Rares show as vignettes (the minimap skull/star) well before nameplate range.
-- Kills from the map marker. Midnight often hides the target's name from addons
-- in combat, so "target is dead" alone misses most kills. The marker itself is
-- readable: it reports the rare dead, or it disappears right where you are.
local VANISH_KILL_YARDS = 40
local markerSeenAt = {} -- rare name -> GetTime() its map marker was last seen

local function ScanPresence()
    if C_VignetteInfo and C_VignetteInfo.GetVignettes then
        local seenNow = {}
        for _, guid in ipairs(C_VignetteInfo.GetVignettes() or {}) do
            local info = C_VignetteInfo.GetVignetteInfo(guid)
            local name = info and info.name
            if name and not (issecretvalue and issecretvalue(name)) and byName[name] then
                seenNow[name] = true
                markerSeenAt[name] = GetTime()
                local dead = info.isDead
                if dead == true and not (issecretvalue and issecretvalue(dead)) then
                    MarkKilled(name, false, "its map marker shows it dead")
                else
                    Spotted(name)
                end
            end
        end
        -- A marker seen moments ago that vanished right next to you: killed.
        local pCont, pWorld = PlayerWorldPos()
        for name, at in pairs(markerSeenAt) do
            if not seenNow[name] then
                markerSeenAt[name] = nil
                if GetTime() - at < 5 and not db.killed[name] and pWorld then
                    local d = DistanceTo(byName[name], pCont, pWorld)
                    if d and d <= VANISH_KILL_YARDS then
                        MarkKilled(name, false, ("its map marker vanished %d yd from you"):format(d))
                    end
                end
            end
        end
    end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then SpotUnit(unit) end
    end
    SpotUnit("target")
    SpotUnit("mouseover")
end

-- Within ABSENT_RANGE of a spawn with no sighting: it isn't up, dim it.
local function CheckAbsent()
    local pCont, pWorld = PlayerWorldPos()
    if not pWorld then return end
    local now, changed = GetTime(), false
    for _, r in ipairs(ns.RARES) do
        local n = r.name
        if not db.killed[n] and not db.absent[n] and not (seenAt[n] and now - seenAt[n] < 20) then
            local d = DistanceTo(r, pCont, pWorld)
            if d and d <= ABSENT_RANGE then
                db.absent[n] = time()
                changed = true
                Print("|cffaaaaaa" .. n .. " isn't up - dimmed on the map.|r")
                ns.Log("RARE", "%s not up: passed within %d yd with no sighting", n, d)
            end
        end
    end
    if changed then Changed() end
end

local function CheckUnit(unit)
    if not UnitExists(unit) then return end
    local name = Safe(UnitName, unit)
    if not name or not byName[name] or db.killed[name] then return end
    if Safe(UnitIsDead, unit) and not Safe(UnitIsTapDenied, unit) then
        MarkKilled(name)
    end
end

---------------------------------------------------------------------------
-- Waypoints
---------------------------------------------------------------------------
function SetWaypoint(r, isAuto)
    local map, x, y = ZoneMap(), Coords(r)
    if not x then
        if not isAuto then Print(r.name .. " has no location yet. Stand at it and type /tw rares set " .. r.name) end
        return
    end
    if not map then
        Print("couldn't find the Coiled Isle map yet - try again once you're in the zone.")
        return
    end
    if TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(map, x / 100, y / 100, { title = r.name, from = ADDON })
    end
    if C_Map.CanSetUserWaypointOnMap(map) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
    Print(("%swaypoint set: %s (%.1f, %.1f)"):format(isAuto and "next " or "", r.name, x, y))
end
ns.SetWaypoint = SetWaypoint

-- The route is saved and stays put until New Route is pressed again.
function ns.GetRoute()
    if not db.route then return nil, {} end
    local list = {}
    for _, n in ipairs(db.route.order) do
        local r = byName[n]
        local x, y
        if r then x, y = Coords(r) end
        if x then list[#list + 1] = { rare = r, x = x / 100, y = y / 100 } end
    end
    return db.route.start, list
end

function ns.ClearRoute()
    if not db.route then return end
    db.route = nil
    Print("route removed from the map. Press Build Route to plan a new one.")
    Changed()
end

function ns.MakeRoute()
    local start, path = ns.BuildRoute()
    if #path == 0 then
        Print("nothing to route - everything is killed, or the Coiled Isle map isn't found yet.")
        return
    end
    local order = {}
    for i, p in ipairs(path) do order[i] = p.rare.name end
    db.route = { start = start and { x = start.x, y = start.y }, order = order }
    db.showRoute = true
    wipe(db.absent) -- a fresh run re-checks everything
    Print(("new route: %d rares, starting from %s."):format(#order, start and "your position" or order[1]))
    SetWaypoint(byName[order[1]], true)
    Changed()
end

---------------------------------------------------------------------------
-- Targeting + skull. Both are protected, so the row itself is a secure macro
-- button that targets the rare and puts the skull on it (/tm). The addon never
-- calls SetRaidTarget itself: in Midnight that is ADDON_ACTION_FORBIDDEN when it
-- happens during the macro's own targeting (it broke the click's waypoint too).
---------------------------------------------------------------------------
-- Clear the mark first: /tm toggles, so a rare already wearing the skull
-- would otherwise lose it.
function ns.TargetMacro(r)
    return ("/targetexact %s\n/tm [@target,exists,nodead] 0\n/tm [@target,exists,nodead] %d"):format(r.name, SKULL)
end

-- After the macro: say so if nothing could be targeted (the name itself may
-- be hidden from addons, so only "is there a target" is checked).
local function SkullIfTargeted(r)
    if not UnitExists("target") then Print(r.name .. " isn't in range to target yet.") end
end

ns.SkullIfTargeted = SkullIfTargeted
ns.CheckUnit = CheckUnit
ns.DistanceTo = DistanceTo
ns.PlayerWorldPos = PlayerWorldPos
ns.byName = byName

local function SetRowRare(row, r)
    row.rare = r
    if InCombatLockdown() then return end
    row:SetAttribute("type1", "macro")
    row:SetAttribute("macrotext1", ns.TargetMacro(r))
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local function CreateRow(i)
    local b = CreateFrame("Button", nil, frame.rares, "SecureActionButtonTemplate")
    b:SetSize(WIDTH - 20, ROW_H)
    b:SetPoint("TOPLEFT", 10, -TOP - (i - 1) * ROW_H)
    -- Secure buttons act on key-down or key-up depending on this CVar;
    -- register both so the macro fires either way.
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    b.num = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.num:SetPoint("LEFT", 2, 0)
    b.num:SetWidth(22)
    b.num:SetJustifyH("RIGHT")
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.name:SetPoint("LEFT", 28, 0)
    b.name:SetJustifyH("LEFT")
    b.dist = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.dist:SetPoint("RIGHT", -4, 0)
    b.dist:SetJustifyH("RIGHT")

    -- Runs after the secure macro, so the target has already changed.
    b:SetScript("PostClick", function(self, btn, down)
        if (down and true or false) ~= GetCVarBool("ActionButtonUseKeyDown") then return end
        local r = self.rare
        if not r then return end
        if btn == "RightButton" then
            if db.killed[r.name] then db.killed[r.name] = nil else db.killed[r.name] = time() end
            ns.Refresh()
            if ns.DrawRoute then ns.DrawRoute() end
        else
            SetWaypoint(r)
            SkullIfTargeted(r)
            CheckUnit("target")
        end
    end)
    b:SetScript("OnEnter", function(self)
        if not self.rare then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.rare.name)
        local x, y = Coords(self.rare)
        if x then GameTooltip:AddLine(("%.1f, %.1f"):format(x, y), 1, 1, 1) end
        if self.rare.note then GameTooltip:AddLine(self.rare.note, 0.8, 0.8, 0.8, true) end
        GameTooltip:AddLine(db.killed[self.rare.name] and "Killed today" or "Available", 1, 0.82, 0)
        GameTooltip:AddLine("Left-click: waypoint + target + skull", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Right-click: toggle killed", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    SetRowRare(b, ns.RARES[i])
    return b
end

local function Toggle(show)
    if show == nil then show = not frame:IsShown() end
    -- The list holds secure buttons, so it can't be shown/hidden in combat.
    if InCombatLockdown() then pendingToggle = show return end
    if show then frame:Show(); ns.Refresh() else frame:Hide() end
end

ns.Toggle = function(show) Toggle(show) end


local function CreateMainFrame()
    frame = CreateFrame("Frame", "TippWorksRaresFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, TOP + #ns.RARES * ROW_H + 54) -- room for a 2-line footer
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
    frame:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        db.pos = { p, rp, x, y }
    end)
    if db.pos then
        frame:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 0)
    end

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 12, -10)
    frame.title:SetText("Coiled Isle Rares")
    local ver = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ver:SetPoint("TOPRIGHT", -30, -13)
    ver:SetText("v" .. ns.VERSION)

    frame.rares = CreateFrame("Frame", nil, frame)
    frame.rares:SetAllPoints()

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() Toggle(false) end)

    local refresh = CreateFrame("Button", nil, frame.rares, "UIPanelButtonTemplate")
    refresh:SetSize(84, 20)
    refresh:SetPoint("BOTTOMRIGHT", -10, 8)
    refresh:SetText("New Route")
    refresh:SetScript("OnClick", function() ns.MakeRoute() end)

    local clear = CreateFrame("Button", nil, frame.rares, "UIPanelButtonTemplate")
    clear:SetSize(84, 20)
    clear:SetPoint("RIGHT", refresh, "LEFT", -4, 0)
    clear:SetText("Clear Route")
    clear:SetScript("OnClick", function() ns.ClearRoute() end)
    frame.clearButton = clear

    frame.footer = frame.rares:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.footer:SetPoint("BOTTOMLEFT", 12, 34) -- above the buttons

    for i = 1, #ns.RARES do rows[i] = CreateRow(i) end
    frame:Hide()
end

local function PaintRow(row, order, pCont, pWorld)
    local r = row.rare
    local state = ns.State(r.name)
    local d, dir = DistanceTo(r, pCont, pWorld)
    local where
    if d then
        where = ("%d yd%s"):format(d, dir and (" " .. dir) or "")
    elseif not Coords(r) then
        where = "no location"
    else
        where = "--"
    end
    row.name:SetText(r.name)
    row.num:SetText(order and ("#" .. order) or "")
    if state == "killed" then
        row.name:SetTextColor(0.5, 0.5, 0.5)
        row.dist:SetText("killed")
        row:SetAlpha(0.4)
    elseif state == "absent" then
        row.name:SetTextColor(0.7, 0.6, 0.45)
        row.dist:SetText("not up  " .. where)
        row:SetAlpha(0.6)
    elseif state == "up" then
        row.name:SetTextColor(0.2, 1, 0.2)
        row.dist:SetText("|cff33ff33UP|r  " .. where)
        row:SetAlpha(1)
    else
        row.name:SetTextColor(1, 0.82, 0)
        row.dist:SetText(where)
        row:SetAlpha(1)
    end
end

function ns.Refresh()
    if not frame then return end
    CheckReset()

    local orderOf = {}
    if db.route then
        for i, n in ipairs(db.route.order) do orderOf[n] = i end
    end
    local pCont, pWorld = PlayerWorldPos()
    local distOf = {}
    for _, r in ipairs(ns.RARES) do distOf[r.name] = DistanceTo(r, pCont, pWorld) end

    -- Rows are secure buttons: only reorder them out of combat.
    if not InCombatLockdown() then
        local list = {}
        for _, r in ipairs(ns.RARES) do list[#list + 1] = r end
        -- With a saved route the list keeps its order (killed rows just dim);
        -- without one it is nearest-first with kills at the bottom.
        table.sort(list, function(a, b)
            local oa, ob = orderOf[a.name], orderOf[b.name]
            if db.route then
                if oa and ob then return oa < ob end
                if oa or ob then return oa ~= nil end
            end
            local ka, kb = db.killed[a.name] ~= nil, db.killed[b.name] ~= nil
            if ka ~= kb then return not ka end
            local da, dbb = distOf[a.name], distOf[b.name]
            if da and dbb then return da < dbb end
            if da or dbb then return da ~= nil end
            return a.name < b.name
        end)
        for i, r in ipairs(list) do SetRowRare(rows[i], r) end
    end

    local done = 0
    for _, row in ipairs(rows) do
        if db.killed[row.rare.name] then done = done + 1 end
        PaintRow(row, orderOf[row.rare.name], pCont, pWorld)
    end

    frame.clearButton:SetEnabled(db.route ~= nil)
    local reset = db.resetAt and (db.resetAt - time()) or 0
    frame.footer:SetText(("%d/%d killed  |  reset in %dh %dm%s"):format(
        done, #ns.RARES, math.floor(reset / 3600), math.floor(reset % 3600 / 60),
        (TW.ShardsCapped and TW.ShardsCapped()) and "\n|cff888888Shards capped (600) this week - rares are optional.|r" or ""))
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function FindRare(query)
    query = query:lower()
    for _, r in ipairs(ns.RARES) do
        if r.name:lower():find(query, 1, true) then return r end
    end
end

-- Commands that moved to other TippWorks addons: /crt <old> -> /tw <new>.
local MOVED = {
    curios = "curios", curiosities = "curios", arrow = "curios arrow",
    calls = "calls list", delves = "calls", weekly = "weekly", bountiful = "bountiful", stash = "vault stash",
    share = "share", portal = "portal", log = "log", minimap = "minimap",
}

local module
local function Command(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "show" or cmd == "toggle" or cmd == "rares" then
        Toggle(cmd == "show" or nil)
    elseif MOVED[cmd] then
        TW.Command(MOVED[cmd] .. (rest ~= "" and (" " .. rest) or ""))
    elseif cmd == "reset" then
        wipe(db.killed); wipe(db.absent); Changed(); Print("all rares cleared.")
    elseif cmd == "set" or cmd == "clear" then
        local r = rest ~= "" and FindRare(rest)
        if not r then Print("no rare matches '" .. rest .. "'.") return end
        if cmd == "clear" then
            db.custom[r.name] = nil
            Print(r.name .. " location restored to default.")
        else
            local map = ZoneMap()
            local p = map and C_Map.GetPlayerMapPosition(map, "player")
            if not p then Print("can't read your position on the Coiled Isle map here.") return end
            db.custom[r.name] = { x = p.x * 100, y = p.y * 100 }
            Print(("%s location saved at %.1f, %.1f."):format(r.name, p.x * 100, p.y * 100))
        end
        Changed()
    elseif cmd == "next" then
        local r = NextOnRoute()
        if r then SetWaypoint(r) else Print("nothing left on the route today.") end
    elseif cmd == "clearroute" then
        ns.ClearRoute()
    elseif cmd == "newroute" or cmd == "new" then
        ns.MakeRoute()
    elseif cmd == "mapbuttons" then
        db.mapBarPos = nil
        if ns.PlaceMapButtons then ns.PlaceMapButtons() end
        Print("map buttons moved back to the bottom-left of the map.")
    elseif cmd == "unlock" then
        ns.ToggleTargetButtonLock()
    elseif cmd == "unseen" then
        wipe(db.absent); Changed(); Print("cleared the 'not up' marks.")
    elseif cmd == "route" then
        db.showRoute = not db.showRoute
        ns.DrawRoute()
        Print("map route " .. (db.showRoute and "ON" or "OFF") .. ".")
    elseif cmd == "autonext" then
        db.autoNext = not db.autoNext
        Print("auto-waypoint to the next rare after a kill " .. (db.autoNext and "ON" or "OFF") .. ".")
    elseif cmd == "auto" then
        db.autoShow = not db.autoShow
        Print("auto-show in the Coiled Isle " .. (db.autoShow and "ON" or "OFF") .. ".")
    elseif cmd == "map" then
        zoneMapID = nil; db.mapID = nil
        Print("zone map id: " .. tostring(ZoneMap()))
        TW.MapCommand()
    else
        TW.ModuleHelp(module)
    end
end

-- The old command still works: /crt and /coiled = /tw rares.
SLASH_COILEDRARETRACKER1 = "/crt"
SLASH_COILEDRARETRACKER2 = "/coiled"
SlashCmdList.COILEDRARETRACKER = function(msg) TW.Guard("/crt " .. (msg or ""), Command, msg or "") end

---------------------------------------------------------------------------
-- TippWorks registration
---------------------------------------------------------------------------
local function Progress()
    local n = 0
    for _ in pairs(db.killed) do n = n + 1 end
    return n, #ns.RARES
end

local function Summary(tt)
    local killed, total = Progress()
    local capped = TW.ShardsCapped and TW.ShardsCapped()
    tt:AddLine(("Coiled rares today: %d/%d%s"):format(killed, total, capped and " |cff888888(shards capped)|r" or ""), 1, 1, 1)
end

module = TW.Register({
    key = "rares", aliases = { "rare", "crt" },
    name = "Coiled Isle Rares", addon = ADDON, version = ns.VERSION,
    command = Command, toggle = function(show) Toggle(show) end, summary = Summary, progress = Progress,
    help = {
        { "", "show/hide the rares window (/crt works too)" },
        { "new", "build a new route from where you are" },
        { "next", "waypoint to the next rare on the route" },
        { "clearroute", "remove the route from the map" },
        { "route", "show/hide the route on the map" },
        { "autonext", "auto-waypoint to the next rare after a kill (on/off)" },
        { "auto", "open the window by itself in the Coiled Isle (on/off)" },
        { "reset", "clear today's kills" },
        { "unseen", "clear the 'not up' marks" },
        { "set <rare>", "save the rare's location where you stand" },
        { "clear <rare>", "restore the rare's default location" },
        { "unlock", "move the Target popup (again to lock)" },
        { "mapbuttons", "move the map buttons back to the bottom-left" },
        { "map", "re-find the Coiled Isle map" },
    },
})

function TippWorksRares_OnAddonCompartmentClick() Toggle() end
function TippWorksRares_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff" .. TW.COLOR .. "Tippenhauer Works|r - Coiled Rares")
    Summary(GameTooltip)
    GameTooltip:AddLine("Click: show/hide  |  /tw rares help", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end
function TippWorksRares_OnAddonCompartmentLeave() GameTooltip:Hide() end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        CoiledRareTrackerDB = CoiledRareTrackerDB or {}
        CoiledRareTrackerAccountDB = CoiledRareTrackerAccountDB or {}
        -- Portal spots used to be saved per character; move them warband-wide
        -- (TippWorks-Calls then copies them into TippWorks-Core's settings).
        if CoiledRareTrackerDB.portals then
            CoiledRareTrackerAccountDB.portals = CoiledRareTrackerAccountDB.portals or {}
            for z, p in pairs(CoiledRareTrackerDB.portals) do
                CoiledRareTrackerAccountDB.portals[z] = CoiledRareTrackerAccountDB.portals[z] or p
            end
            CoiledRareTrackerDB.portals = nil
        end
        db = CoiledRareTrackerDB
        ns.db = db
        db.killed = db.killed or {}
        db.custom = db.custom or {}
        db.absent = db.absent or {}
        db.delveDone = db.delveDone or {}
        db.delveQuestIDs = db.delveQuestIDs or {}
        db.shown = nil -- retired: visibility now follows the zone
        if db.autoShow == nil then db.autoShow = true end
        if db.showRoute == nil then db.showRoute = true end
        if db.autoNext == nil then db.autoNext = true end
        for _, r in ipairs(ns.RARES) do byName[r.name] = r end
        CheckReset()
        db.log = nil -- the activity log lives in TippWorks-Core now (/tw log)
        TW.Log("INFO", "TippWorks-Rares v%s loaded", ns.VERSION)
        CreateMainFrame()
        ns.InitRoute()
        ns.InitTargetButton()
        -- Options > AddOns > Tippenhauer Works > Coiled Rares (same as the /tw rares toggles)
        if TW.AddCheckbox then
            TW.AddCheckbox("Coiled Rares", "TW_RARES_AUTOSHOW", "Open by itself on the Coiled Isle",
                "Show the rares window when you arrive on the Coiled Isle (never inside delves). /tw rares auto",
                function() return db.autoShow end, function(v) db.autoShow = v end)
            TW.AddCheckbox("Coiled Rares", "TW_RARES_AUTONEXT", "Waypoint to the next rare after a kill",
                "After a kill, set a waypoint to the next rare on the route. /tw rares autonext",
                function() return db.autoNext end, function(v) db.autoNext = v end)
            TW.AddCheckbox("Coiled Rares", "TW_RARES_ROUTE", "Show the route on the world map",
                "Draw the saved route and numbered pins on the Coiled Isle map. /tw rares route",
                function() return db.showRoute end, function(v) db.showRoute = v; if ns.DrawRoute then ns.DrawRoute() end end)
        end

        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        self:RegisterEvent("ZONE_CHANGED")
        self:RegisterEvent("ZONE_CHANGED_INDOORS")
        self:RegisterEvent("PLAYER_TARGET_CHANGED")
        self:RegisterEvent("RAID_TARGET_UPDATE")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("LOOT_OPENED")

        -- Half-second tick: fast enough to catch a spawn while flying over it.
        -- The map route only redraws when something actually changes.
        local n = 0
        C_Timer.NewTicker(0.5, function() ns.Guard("rare tick", function()
            -- Rare tracking only runs out in the Coiled Isle, never in a delve.
            ns.inZone = InCoiledIsle()
            if ns.inZone then
                CheckUnit("target")
                CheckUnit("mouseover")
                ScanPresence()
                CheckAbsent()
            end
            ns.UpdateTargetButton()
            n = n + 1
            if n % 2 == 0 and frame:IsShown() then ns.Refresh() end
        end) end)
    elseif event:find("^ZONE_CHANGED") or event == "PLAYER_ENTERING_WORLD" then
        -- Only act when crossing the zone edge (or a delve entrance), so closing
        -- the window by hand inside the zone sticks.
        local inZone = InCoiledIsle()
        ns.inZone = inZone
        if inZone ~= wasInZone then
            wasInZone = inZone
            if inZone and db.autoShow then
                Toggle(true)
            elseif not inZone then
                Toggle(false)
            end
            ns.UpdateTargetButton()
        elseif IsInInstance() and frame:IsShown() then
            Toggle(false) -- opened by hand elsewhere, then walked into a delve
        end
    elseif event == "RAID_TARGET_UPDATE" then
        -- Any raid-mark change on your target, whoever made it - shows whether a
        -- skull you placed actually stuck.
        local ok, name = pcall(UnitName, "target")
        if ok and name and not (issecretvalue and issecretvalue(name)) and byName[name] then
            local ok2, icon = pcall(GetRaidTargetIndex, "target")
            ns.Log("MARK", "target %s now has mark %s%s", name, ok2 and tostring(icon) or "?",
                (IsInGroup() and not UnitIsGroupLeader("player") and not UnitIsGroupAssistant("player")) and
                " (you're not leader/assist)" or "")
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingToggle ~= nil then Toggle(pendingToggle); pendingToggle = nil end
        CheckUnit("target")
        ns.Refresh()
        ns.UpdateTargetButton()
    elseif event == "PLAYER_TARGET_CHANGED" then
        CheckUnit("target")
    else
        CheckUnit("target")
    end
end)
