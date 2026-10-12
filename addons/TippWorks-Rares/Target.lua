local _, ns = ...

-- Addons can't target on their own: targeting needs your click or key press.
-- So when a rare is spotted this secure button pops up; click it or press its
-- key binding (Options > Keybindings > AddOns) to target + skull the rare.
local btn
local unlocked = false

local function Best()
    if not ns.inZone then return end -- not outside the Coiled Isle / in delves
    local pCont, pWorld = ns.PlayerWorldPos()
    local best, bestD
    for _, r in ipairs(ns.RARES) do
        if ns.State(r.name) == "up" then
            local d = ns.DistanceTo(r, pCont, pWorld) or 99999
            if not bestD or d < bestD then best, bestD = r, d end
        end
    end
    return best
end

function ns.UpdateTargetButton()
    if not btn or InCombatLockdown() then return end -- secure: frozen in combat
    local r = Best()
    if unlocked then
        btn.label:SetText("Drag me - /crt unlock to lock")
        btn:Show()
        return
    end
    if not r then
        btn.rare = nil
        btn:Hide()
        return
    end
    if btn.rare ~= r then
        btn.rare = r
        btn:SetAttribute("macrotext1", "/targetexact " .. r.name)
        btn.label:SetText("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:16|t  Target: " .. r.name)
    end
    btn:Show()
end

function ns.ToggleTargetButtonLock()
    if InCombatLockdown() then ns.Print("can't move it in combat.") return end
    unlocked = not unlocked
    ns.UpdateTargetButton()
    ns.Print(unlocked and "target popup unlocked - drag it where you want." or "target popup locked.")
end

function ns.InitTargetButton()
    btn = CreateFrame("Button", "CoiledRareTrackerTargetButton", UIParent, "SecureActionButtonTemplate,BackdropTemplate")
    btn:SetSize(260, 34)
    local pos = ns.db.targetPos
    if pos then
        btn:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        btn:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    btn:SetBackdropColor(0.1, 0.3, 0.1, 0.9)
    btn:SetBackdropBorderColor(0.3, 1, 0.3)
    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    btn.label:SetPoint("CENTER")
    btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("type1", "macro")
    btn:SetScript("PostClick", function(self, _, down)
        if (down and true or false) ~= GetCVarBool("ActionButtonUseKeyDown") then return end
        if self.rare then
            ns.SkullIfTargeted(self.rare)
            ns.CheckUnit("target")
        end
    end)

    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        if unlocked and not InCombatLockdown() then self:StartMoving() end
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        ns.db.targetPos = { p, rp, x, y }
    end)
    btn:Hide()
end

BINDING_HEADER_COILEDRARETRACKER = "Tippenhauer Works - Coiled Rares"
_G["BINDING_NAME_CLICK CoiledRareTrackerTargetButton:LeftButton"] = "Target spotted rare (+ skull)"
