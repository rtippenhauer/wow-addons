local ADDON, ns = ...
ns.VERSION = ns.VERSION or C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?" -- set in Data.lua
local db
local zoneMapID
local byName = {}
local rows = {}
local frame
local pendingToggle
local wasInZone
local SKULL = 8

local ROW_H, WIDTH = 18, 350
local TOP = 54 -- title + tab buttons
ns.WIDTH = WIDTH
local PREFIX = "|cff33ff99Coiled Rares:|r "

local function Print(msg) print(PREFIX .. msg) end

-- Guard against Midnight "secret values": anything restricted in combat is skipped.
local function Safe(fn, ...)
    local ok, a = pcall(fn, ...)
    if not ok then return nil end
    if issecretvalue and issecretvalue(a) then return nil end
    return a
end

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

local function MarkKilled(name, silent)
    if db.killed[name] then return end
    db.killed[name] = time()
    db.absent[name] = nil
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
local function ScanPresence()
    if C_VignetteInfo and C_VignetteInfo.GetVignettes then
        for _, guid in ipairs(C_VignetteInfo.GetVignettes() or {}) do
            local info = C_VignetteInfo.GetVignetteInfo(guid)
            local name = info and info.name
            if name and not (issecretvalue and issecretvalue(name)) and byName[name] then Spotted(name) end
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
        if not isAuto then Print(r.name .. " has no location yet. Stand at it and type /crt set " .. r.name) end
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
-- Targeting + skull. Targeting is protected, so the row itself is a secure
-- /targetexact macro button; the skull is set afterwards from PostClick.
---------------------------------------------------------------------------
local function SkullIfTargeted(r, quiet)
    local name = Safe(UnitName, "target")
    if name ~= r.name then
        if not quiet then Print(r.name .. " isn't in range to target yet.") end
        return
    end
    if Safe(UnitIsDead, "target") then return end
    if Safe(GetRaidTargetIndex, "target") ~= SKULL then
        -- SetRaidTarget toggles when the icon is already set, hence the check above.
        local ok, err = pcall(SetRaidTarget, "target", SKULL)
        C_Timer.After(0.2, function()
            ns.Log("MARK", "skull on %s: %s, icon now %s", r.name, ok and "called" or ("error " .. tostring(err)),
                tostring(Safe(GetRaidTargetIndex, "target")))
        end)
    end
end

-- Whenever you target a rare - by any means - it gets the skull.
local function AutoSkullTarget()
    local name = Safe(UnitName, "target")
    if name and byName[name] then SkullIfTargeted(byName[name], true) end
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
    row:SetAttribute("macrotext1", "/targetexact " .. r.name)
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

local tabs = {}
local function SelectTab(name)
    if not frame then return end
    -- Swapping pages hides/shows the secure rare rows: not allowed in combat.
    if InCombatLockdown() then Print("can't switch tabs in combat.") return end
    db.tab = name
    frame.rares:SetShown(name == "rares")
    frame.delves:SetShown(name == "delves")
    frame.weekly:SetShown(name == "weekly")
    frame.bountiful:SetShown(name == "bountiful")
    local titles = { rares = "Coiled Isle Rares", delves = "Delver's Call Quests",
        weekly = "Weekly Checklist (90)", bountiful = "Bountiful Delves Today" }
    frame.title:SetText(titles[name])
    local heights = {
        rares = TOP + #ns.RARES * ROW_H + 54, -- room for a 2-line footer
        delves = frame.delves.contentHeight + 40,
        weekly = frame.weekly.contentHeight + 40,
        bountiful = frame.bountiful.contentHeight,
    }
    frame:SetHeight(heights[name])
    for key, t in pairs(tabs) do
        if key == name then t:LockHighlight() else t:UnlockHighlight() end
        t:SetEnabled(key ~= name)
    end
    ns.Refresh()
end
ns.SelectTab = SelectTab

local function CreateMainFrame()
    frame = CreateFrame("Frame", "CoiledRareTrackerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, 40 + #ns.RARES * ROW_H + 40)
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
    frame.delves = ns.CreateDelvesPage(frame, -TOP)
    frame.weekly = ns.CreateWeeklyPage(frame, -TOP)
    frame.bountiful = ns.CreateBountifulPage(frame, -TOP)

    local TAB_TEXT = { rares = "Rares", delves = "Delves", weekly = "Weekly", bountiful = "Bountiful" }
    for i, key in ipairs({ "rares", "delves", "weekly", "bountiful" }) do
        local t = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        t:SetSize(78, 20)
        t:SetPoint("TOPLEFT", 10 + (i - 1) * 82, -30)
        t:SetText(TAB_TEXT[key])
        t:SetScript("OnClick", function() SelectTab(key) end)
        tabs[key] = t
    end

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
    local valid = { rares = true, delves = true, weekly = true, bountiful = true }
    SelectTab(valid[db.tab] and db.tab or "rares")
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
    ns.RefreshDelves()
    ns.RefreshWeekly()
    ns.RefreshBountiful()

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
        ns.ShardsCapped() and "\n|cff888888Shards capped (600) this week - rares are optional.|r" or ""))
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

SLASH_COILEDRARETRACKER1 = "/crt"
SLASH_COILEDRARETRACKER2 = "/coiled"
SlashCmdList.COILEDRARETRACKER = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "show" or cmd == "toggle" then
        Toggle(cmd == "show" or nil)
    elseif cmd == "curios" or cmd == "curiosities" then
        local sub = rest:lower()
        if sub == "reset" then ns.ResetCurioRun()
        elseif sub == "scan" then ns.CurioScanReport()
        else ns.ToggleCurios() end
    elseif cmd == "delves" or cmd == "rares" or cmd == "weekly" or cmd == "bountiful" then
        Toggle(true)
        SelectTab(cmd)
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
    elseif cmd == "calls" then
        ns.PrintCalls()
    elseif cmd == "log" then
        ns.LogCommand(rest:lower())
    elseif cmd == "arrow" then
        ns.SetArrowMode(rest:lower())
    elseif cmd == "minimap" then
        ns.ToggleMinimapButton()
    elseif cmd == "stash" then
        -- Shows where (if anywhere) the game exposes the Gilded Stash count.
        local id = db.currencyIDs and db.currencyIDs.stash
        local cur = id and C_CurrencyInfo.GetCurrencyInfo(id)
        if cur then
            Print(("currency '%s' (id %d): have %d, max %d, this week %d/%d"):format(cur.name, id, cur.quantity,
                cur.maxQuantity or 0, cur.quantityEarnedThisWeek or 0, cur.maxWeeklyQuantity or 0))
        else
            Print("no 'Gilded Stash' currency found.")
        end
        local t = ns.DelveTooltipCount("gilded stash")
        Print(t and ("delve map tooltip: \"" .. t[3] .. "\"") or "no Gilded Stash count on any delve map tooltip right now.")
    elseif cmd == "portal" then
        ns.SavePortal(rest)
    elseif cmd == "share" then
        local mode = rest:lower()
        if mode == "group" or mode == "say" or mode == "guild" or mode == "self" then
            db.shareMode = mode
            Print("delve shares now go to: " .. mode .. (mode == "group" and " (party/raid when grouped, otherwise only you)" or "") .. ".")
        else
            Print("delve shares go to: " .. (db.shareMode or "group") .. ". Options: /crt share group | say | guild | self")
        end
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
        ns.ResetMapCache()
        Print("zone map id: " .. tostring(ZoneMap()))
        for _, z in ipairs(ns.DELVE_ZONES) do Print("  " .. z .. ": " .. tostring(ns.FindMapByName(z))) end
    else
        Print("/crt - toggle | /crt calls - Delver's Call status | /crt log - activity log (/crt log clear) | /crt minimap - show/hide minimap button | /crt delves | /crt rares | /crt weekly | /crt bountiful | /crt curios (reset|scan) | /crt arrow auto|tomtom|own|both | /crt share group|say|guild|self | /crt portal <zone> - save a portal spot | /crt new - new route from here | /crt clearroute | /crt next | /crt route - show/hide map route | /crt unseen | /crt unlock - move the target popup | /crt mapbuttons - reset map button position | /crt autonext | /crt reset | /crt set <name> | /crt clear <name> | /crt auto | /crt map")
    end
end

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
        ns.db = CoiledRareTrackerDB
        ns.InitLog()
        -- Portal spots used to be saved per character; move them warband-wide.
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
        CreateMainFrame()
        ns.InitRoute()
        ns.InitTargetButton()
        ns.InitCurios()
        ns.InitMinimap()

        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        self:RegisterEvent("ZONE_CHANGED")
        self:RegisterEvent("ZONE_CHANGED_INDOORS")
        self:RegisterEvent("QUEST_LOG_UPDATE")
        self:RegisterEvent("QUEST_TURNED_IN")
        self:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
        self:RegisterEvent("WEEKLY_REWARDS_UPDATE")
        self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        self:RegisterEvent("PLAYER_TARGET_CHANGED")
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
                if db.tab ~= "rares" and not InCombatLockdown() then SelectTab("rares") end
            elseif not inZone then
                Toggle(false)
            end
            ns.UpdateTargetButton()
        elseif IsInInstance() and frame:IsShown() then
            Toggle(false) -- opened by hand elsewhere, then walked into a delve
        end
    elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_TURNED_IN" then
        ns.RefreshDelves()
    elseif event == "CURRENCY_DISPLAY_UPDATE" or event == "WEEKLY_REWARDS_UPDATE" or event == "PLAYER_EQUIPMENT_CHANGED" then
        ns.RefreshWeekly() -- also tracks shard gains/charge use while the tab is closed
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingToggle ~= nil then Toggle(pendingToggle); pendingToggle = nil end
        CheckUnit("target")
        ns.Refresh()
        ns.UpdateTargetButton()
    elseif event == "PLAYER_TARGET_CHANGED" then
        CheckUnit("target")
        AutoSkullTarget()
    else
        CheckUnit("target")
    end
end)
