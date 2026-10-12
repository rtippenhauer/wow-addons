local _, ns = ...
local TW = ns.TW

-- One minimap button for every TippWorks addon (drag it around the edge),
-- plus its entry in Blizzard's AddOns compartment.
-- Left-click: menu of the installed TippWorks addons. Right-click: /tw help.
local ICON = "Interface\\Icons\\INV_Misc_Gear_01"
local btn

local function OpenMenu(owner)
    if #TW.order == 0 then TW.Help() return end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        -- Very old client fallback: open the first addon.
        if TW.order[1].toggle then TW.order[1].toggle() end
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("|cff" .. TW.COLOR .. "Tippenhauer Works|r")
        for _, m in ipairs(TW.order) do
            if m.toggle then
                root:CreateButton(m.name, function() TW.Guard(m.key .. " toggle", m.toggle) end)
            end
        end
        root:CreateDivider()
        root:CreateButton("Activity log", function() TW.LogCommand("") end)
        root:CreateButton("Help (/tw help)", TW.Help)
    end)
end

local function Click(owner, button)
    if button == "RightButton" then TW.Help() else OpenMenu(owner) end
end

local function Summary(tt)
    tt:AddLine("|cff" .. TW.COLOR .. "Tippenhauer Works|r")
    for _, m in ipairs(TW.order) do
        if m.summary then
            local ok, err = pcall(m.summary, tt)
            if not ok then TW.Log("ERROR", "%s summary: %s", m.key, tostring(err)) end
        else
            tt:AddLine(m.name, 1, 1, 1)
        end
    end
    if #TW.order == 0 then tt:AddLine("No TippWorks addons enabled yet.", 1, 1, 1) end
    tt:AddLine("Left-click: menu  |  Right-click: commands", 0.6, 0.6, 0.6)
    tt:AddLine("Drag: move around the minimap  |  /tw minimap: hide", 0.6, 0.6, 0.6)
end

local function Place()
    local angle = math.rad(TW.account.minimapAngle or 225)
    local r = (Minimap:GetWidth() / 2) + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    TW.account.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
    Place()
end

function TW.InitLauncher()
    btn = CreateFrame("Button", "TippWorksMinimapButton", Minimap)
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

    btn:SetScript("OnClick", Click)
    btn:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        Summary(GameTooltip)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    Place()
    btn:SetShown(not TW.account.hideMinimap)
end

function TW.ToggleMinimapButton()
    TW.account.hideMinimap = not TW.account.hideMinimap or nil
    btn:SetShown(not TW.account.hideMinimap)
    TW.Print("minimap button " .. (TW.account.hideMinimap and "hidden (still in the AddOns menu by the minimap)." or "shown."))
end

-- Blizzard's AddOns compartment (the menu button by the minimap); named in the .toc.
function TippWorks_OnAddonCompartmentClick(_, button)
    Click(btn, button) -- context menus open at the cursor; the owner is just a parent frame
end

function TippWorks_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    Summary(GameTooltip)
    GameTooltip:Show()
end

function TippWorks_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
