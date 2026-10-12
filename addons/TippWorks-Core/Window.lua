local _, ns = ...
local TW = ns.TW

-- The standard TippWorks window: dark backdrop, title, version, close button,
-- optional tab buttons, position saved per character.
--   local win = TW.CreateWindow({
--       name = "TippWorksVaultFrame", title = "Weekly Checklist (90)", version = "1.0.0",
--       width = 350, db = db,                       -- db.pos is saved here
--       tabs = { { key = "weekly", label = "Weekly", title = "Weekly Checklist (90)" }, ... },
--       onTab = function(key) end,                  -- after a tab is selected
--   })
--   win.top   -> y offset (negative) where page content starts
--   win:SelectTab(key), win:Toggle([show])
function TW.CreateWindow(o)
    local f = CreateFrame("Frame", o.name, UIParent, "BackdropTemplate")
    f:SetSize(o.width or 350, 200)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.8)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        o.db.pos = { p, rp, x, y }
    end)
    local pos = o.db.pos
    if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 0) end
    -- Escape closes it like Blizzard's own panels.
    if o.name then tinsert(UISpecialFrames, o.name) end

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.title:SetText(o.title or "")
    local ver = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ver:SetPoint("TOPRIGHT", -30, -13)
    ver:SetText("v" .. (o.version or "?"))
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)

    f.tabs = {}
    f.top = o.tabs and -54 or -34
    for i, t in ipairs(o.tabs or {}) do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(78, 20)
        b:SetPoint("TOPLEFT", 10 + (i - 1) * 82, -30)
        b:SetText(t.label)
        b:SetScript("OnClick", function() f:SelectTab(t.key) end)
        f.tabs[t.key] = { button = b, def = t }
    end

    function f:SelectTab(key)
        if not self.tabs[key] then return end
        o.db.tab = key
        for k, t in pairs(self.tabs) do
            if k == key then t.button:LockHighlight() else t.button:UnlockHighlight() end
            t.button:SetEnabled(k ~= key)
        end
        self.title:SetText(self.tabs[key].def.title or o.title or "")
        if o.onTab then o.onTab(key) end
    end

    function f:Toggle(show)
        if show == nil then show = not self:IsShown() end
        self:SetShown(show)
    end

    f:Hide()
    return f
end
