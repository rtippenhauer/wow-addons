local ADDON, ns = ...

-- Minimap button (drag it around the edge) + Blizzard's AddOns compartment
-- entry. Left-click: toggle the window. Right-click: Weekly tab.
local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local btn

local function Open(button)
    if button == "RightButton" then
        ns.Toggle(true)
        ns.SelectTab("weekly")
    else
        ns.Toggle()
    end
end

local function Summary(tt)
    tt:AddLine("Coiled Rare Tracker")
    local killed = 0
    for _ in pairs(ns.db.killed) do killed = killed + 1 end
    local capped = ns.ShardsCapped and ns.ShardsCapped()
    tt:AddLine(("Rares today: %d/%d%s"):format(killed, #ns.RARES, capped and " |cff888888(shards capped)|r" or ""), 1, 1, 1)
    local id = ns.db.currencyIDs and ns.db.currencyIDs.shards
    local info = id and C_CurrencyInfo.GetCurrencyInfo(id)
    if info then
        local earned = (info.maxWeeklyQuantity or 0) > 0 and info.quantityEarnedThisWeek
            or (ns.db.week and ns.db.week.shardsSeen) or 0
        tt:AddLine(("Coffer Key Shards: %d/600"):format(earned), 1, 1, 1)
    end
    if C_WeeklyRewards and C_WeeklyRewards.HasAvailableRewards and C_WeeklyRewards.HasAvailableRewards() then
        tt:AddLine("Great Vault: reward waiting!", 1, 0.4, 0.4)
    end
    tt:AddLine("Left-click: open/close  |  Right-click: Weekly", 0.6, 0.6, 0.6)
    tt:AddLine("Drag: move around the minimap  |  /crt minimap: hide", 0.6, 0.6, 0.6)
end

local function Place()
    local angle = math.rad(CoiledRareTrackerAccountDB.minimapAngle or 210)
    local r = (Minimap:GetWidth() / 2) + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    CoiledRareTrackerAccountDB.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
    Place()
end

function ns.InitMinimap()
    local acct = CoiledRareTrackerAccountDB
    btn = CreateFrame("Button", "CoiledRareTrackerMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("CENTER")
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    btn:SetScript("OnClick", function(_, button) Open(button) end)
    btn:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        Summary(GameTooltip)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    Place()
    btn:SetShown(not acct.hideMinimap)
end

function ns.ToggleMinimapButton()
    local acct = CoiledRareTrackerAccountDB
    acct.hideMinimap = not acct.hideMinimap or nil
    btn:SetShown(not acct.hideMinimap)
    ns.Print("minimap button " .. (acct.hideMinimap and "hidden (still in the AddOns menu by the minimap)." or "shown."))
end

-- Blizzard's AddOns compartment (the menu button by the minimap); named in the .toc.
function CoiledRareTracker_OnAddonCompartmentClick(_, button)
    Open(button)
end

function CoiledRareTracker_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    Summary(GameTooltip)
    GameTooltip:Show()
end

function CoiledRareTracker_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
