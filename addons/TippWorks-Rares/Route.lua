local _, ns = ...

-- Draws the saved route on the world map when it is showing the Coiled Isle.
-- The route only changes when New Route is pressed; kills and "not up"
-- rares are dimmed in place.
local overlay, mapButton, clearButton, bar
local lines, pins = {}, {}

local function GetLine(i)
    local l = lines[i]
    if not l then
        l = overlay:CreateLine(nil, "OVERLAY")
        lines[i] = l
    end
    return l
end

local STATE_TEXT = { killed = "Killed today", absent = "Not up (you flew past it)", up = "UP - spotted just now" }

local function GetPin(i)
    local p = pins[i]
    if not p then
        p = CreateFrame("Button", nil, overlay)
        p.bg = p:CreateTexture(nil, "BACKGROUND")
        p.bg:SetAllPoints()
        p.bg:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
        p.text = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        p.text:SetPoint("BOTTOM", p, "TOP", 0, -2)
        p:SetScript("OnClick", function(self) if self.rare then ns.SetWaypoint(self.rare) end end)
        p:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(("#%d  %s"):format(self.order, self.rare.name))
            local st = ns.State(self.rare.name)
            GameTooltip:AddLine(STATE_TEXT[st] or "Not checked yet", 1, 1, 1)
            GameTooltip:AddLine("Click: set waypoint", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        p:SetScript("OnLeave", GameTooltip_Hide)
        pins[i] = p
    end
    return p
end

local function StylePin(pin, state)
    local dim = state == "killed" or state == "absent"
    pin.bg:SetDesaturated(dim)
    pin:SetAlpha(state == "killed" and 0.25 or state == "absent" and 0.4 or 1)
    if state == "up" then
        pin.text:SetTextColor(0.2, 1, 0.2)
    elseif dim then
        pin.text:SetTextColor(0.6, 0.6, 0.6)
    else
        pin.text:SetTextColor(1, 0.9, 0.2)
    end
end

local function OnZoneMap()
    local map = ns.ZoneMap()
    return map and WorldMapFrame:GetMapID() == map
end

function ns.DrawRoute()
    if not overlay and WorldMapFrame then ns.InitRoute() end
    if not overlay or not WorldMapFrame:IsShown() then return end
    for _, l in ipairs(lines) do l:Hide() end
    for _, p in ipairs(pins) do p:Hide() end

    local onZone = OnZoneMap()
    bar:SetShown(onZone)
    clearButton:SetShown(ns.db.route ~= nil)
    if not onZone then return end
    mapButton:SetText(ns.db.route and "New Route" or "Build Route")
    if not ns.db.showRoute then return end

    local canvas = WorldMapFrame.ScrollContainer.Child
    local w, h = canvas:GetSize()
    if not w or w == 0 then return end
    local thick = math.max(2, w / 350)
    local pinSize = math.max(14, w / 45)

    local start, route = ns.GetRoute()
    local prev = start
    for i, p in ipairs(route) do
        local state = ns.State(p.rare.name)
        if prev then
            local l = GetLine(i)
            l:SetThickness(thick)
            if state == "killed" or state == "absent" then
                l:SetColorTexture(0.5, 0.5, 0.5, 0.35)
            elseif prev == start then
                l:SetColorTexture(0.3, 0.8, 1, 0.7) -- leg from where the route was built
            else
                l:SetColorTexture(1, 0.75, 0.1, 0.85)
            end
            l:SetStartPoint("TOPLEFT", overlay, prev.x * w, -prev.y * h)
            l:SetEndPoint("TOPLEFT", overlay, p.x * w, -p.y * h)
            l:Show()
        end
        local pin = GetPin(i)
        pin.rare, pin.order = p.rare, i
        pin:SetSize(pinSize, pinSize)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", overlay, "TOPLEFT", p.x * w, -p.y * h)
        pin.text:SetText(i)
        StylePin(pin, state)
        pin:Show()
        prev = p
    end
end

function ns.InitRoute()
    if overlay or not WorldMapFrame then return end
    local canvas = WorldMapFrame.ScrollContainer.Child
    overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetAllPoints(canvas)
    overlay:SetFrameLevel(canvas:GetFrameLevel() + 2000)

    -- On-map button: left = new route from here, right = show/hide the route.
    -- Both buttons live on one bar: bottom-left by default (Blizzard's own map
    -- buttons sit top-right), shift-drag either button to move it.
    local container = WorldMapFrame.ScrollContainer
    bar = CreateFrame("Frame", nil, container)
    bar:SetSize(204, 22)
    bar:SetFrameLevel(overlay:GetFrameLevel() + 10)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    function ns.PlaceMapButtons()
        bar:ClearAllPoints()
        local pos = ns.db.mapBarPos
        if pos then
            bar:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", pos[1], pos[2])
        else
            bar:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 8, 8)
        end
    end
    ns.PlaceMapButtons()
    local draggedAt = 0
    local function DragStart()
        if IsShiftKeyDown() then bar:StartMoving() end
    end
    local function DragStop()
        bar:StopMovingOrSizing()
        draggedAt = GetTime()
        -- Save relative to the map so it follows the map when it moves or resizes.
        local x, y = bar:GetLeft() - container:GetLeft(), bar:GetBottom() - container:GetBottom()
        ns.db.mapBarPos = { x, y }
        ns.PlaceMapButtons()
    end

    mapButton = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    mapButton:SetSize(100, 22)
    mapButton:SetPoint("LEFT")
    mapButton:RegisterForDrag("LeftButton")
    mapButton:SetScript("OnDragStart", DragStart)
    mapButton:SetScript("OnDragStop", DragStop)
    mapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mapButton:SetScript("OnClick", function(_, btn)
        if GetTime() - draggedAt < 0.3 then return end -- releasing a drag isn't a click
        if btn == "RightButton" then
            ns.db.showRoute = not ns.db.showRoute
            ns.DrawRoute()
        else
            ns.MakeRoute()
        end
    end)
    mapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Coiled Rare Route")
        GameTooltip:AddLine("Left-click: build a new route from where you are", 1, 1, 1)
        GameTooltip:AddLine("Right-click: " .. (ns.db.showRoute and "hide" or "show") .. " the route", 1, 1, 1)
        GameTooltip:AddLine("Shift-drag: move these buttons", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    mapButton:SetScript("OnLeave", GameTooltip_Hide)

    clearButton = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    clearButton:SetSize(100, 22)
    clearButton:SetPoint("LEFT", mapButton, "RIGHT", 4, 0)
    clearButton:RegisterForDrag("LeftButton")
    clearButton:SetScript("OnDragStart", DragStart)
    clearButton:SetScript("OnDragStop", DragStop)
    clearButton:SetText("Clear Route")
    clearButton:SetScript("OnClick", function()
        if GetTime() - draggedAt < 0.3 then return end
        ns.ClearRoute()
    end)
    clearButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Remove the route from the map")
        GameTooltip:AddLine("Kills and 'not up' marks are kept.", 1, 1, 1)
        GameTooltip:AddLine("Shift-drag: move these buttons", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    clearButton:SetScript("OnLeave", GameTooltip_Hide)
    bar:Hide()

    WorldMapFrame:HookScript("OnShow", ns.DrawRoute)
    if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", ns.DrawRoute) end
end
