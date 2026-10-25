local _, ns = ...
local TW = ns.TW

-- The standard TippWorks window: dark backdrop, title, version, close button,
-- optional tab buttons, position saved per character.
--   local win = TW.CreateWindow({
--       name = "TippWorksVaultFrame", title = "Weekly Checklist (90)", version = "1.0.0",
--       width = 350, db = db,                       -- db.pos is saved here
--       keepOnEscape = true,                        -- optional: Escape doesn't close it
--       tabs = { { key = "weekly", label = "Weekly", title = "Weekly Checklist (90)" }, ... },
--       onTab = function(key) end,                  -- after a tab is selected
--       flatTabs = true,                            -- optional: text tabs with counts (win:SetTabCount)
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
    -- Escape closes it like Blizzard's own panels - unless it's meant to stay up
    -- through a run (closing the map with Escape closes these too).
    if o.name and not o.keepOnEscape then tinsert(UISpecialFrames, o.name) end

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
    local order = {}
    if o.flatTabs then
        -- Flat tabs: text sized to the label, an accent underline on the selected one,
        -- and an optional count after the label (f:SetTabCount).
        local r, g, bl = tonumber(TW.COLOR:sub(1, 2), 16) / 255, tonumber(TW.COLOR:sub(3, 4), 16) / 255, tonumber(TW.COLOR:sub(5, 6), 16) / 255
        local rule = f:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(1, 1, 1, 0.12)
        rule:SetHeight(1)
        rule:SetPoint("TOPLEFT", 8, -50)
        rule:SetPoint("TOPRIGHT", -8, -50)
        for _, t in ipairs(o.tabs or {}) do
            local b = CreateFrame("Button", nil, f)
            b:SetHeight(20)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            b.text:SetPoint("CENTER", 0, 1)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.08)
            b.line = b:CreateTexture(nil, "ARTWORK")
            b.line:SetColorTexture(r, g, bl, 1)
            b.line:SetHeight(2)
            b.line:SetPoint("BOTTOMLEFT", 0, 0)
            b.line:SetPoint("BOTTOMRIGHT", 0, 0)
            b:SetScript("OnClick", function() f:SelectTab(t.key) end)
            f.tabs[t.key] = { button = b, def = t }
            order[#order + 1] = f.tabs[t.key]
        end
    else
        for i, t in ipairs(o.tabs or {}) do
            local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            b:SetSize(78, 20)
            b:SetPoint("TOPLEFT", 10 + (i - 1) * 82, -30)
            b:SetText(t.label)
            b:SetScript("OnClick", function() f:SelectTab(t.key) end)
            f.tabs[t.key] = { button = b, def = t }
        end
    end

    -- Flat tabs: label colors and widths change with the selection and the counts.
    local function Layout()
        local x = 10
        for _, t in ipairs(order) do
            local b, sel = t.button, o.db.tab == t.def.key
            local count = t.count and t.count > 0 and (" " .. t.count) or ""
            b.text:SetText(t.def.label .. count)
            if sel then b.text:SetTextColor(1, 1, 1)
            elseif t.count == 0 then b.text:SetTextColor(0.45, 0.45, 0.45)
            else b.text:SetTextColor(1, 0.82, 0) end
            b.line:SetShown(sel)
            b:SetWidth((tonumber(b.text:GetStringWidth()) or 40) + 16)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", x, -30)
            x = x + b:GetWidth() + 2
        end
    end

    -- Flat tabs only: show a count after a tab's label (nil hides it; 0 dims the tab).
    function f:SetTabCount(key, n)
        local t = self.tabs[key]
        if not t or t.count == n then return end
        t.count = n
        Layout()
    end

    function f:SelectTab(key)
        if not self.tabs[key] then return end
        o.db.tab = key
        if o.flatTabs then Layout()
        else
            for k, t in pairs(self.tabs) do
                if k == key then t.button:LockHighlight() else t.button:UnlockHighlight() end
                t.button:SetEnabled(k ~= key)
            end
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
