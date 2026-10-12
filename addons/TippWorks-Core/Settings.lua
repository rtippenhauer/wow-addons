local _, ns = ...
local TW = ns.TW

-- Options > AddOns > Tippenhauer Works, with a sub-page per TippWorks addon.
-- Addons add checkboxes while they load:
--   TW.AddCheckbox("Curiosities", "TW_CURIOS_SOUND", "Dundun: alert sound", "tooltip",
--       function() return db.sound ~= false end, function(v) if v then db.sound = nil else db.sound = false end end)
-- The page is registered at PLAYER_LOGIN, after every addon has added its part.
-- Any Settings API change on Blizzard's side only loses the page, never the addon.
local category
local subs = {}

local function Try(what, fn, ...)
    local ok, a, b = pcall(fn, ...)
    if not ok then TW.Log("SETTINGS", "%s failed: %s", what, tostring(a)) end
    return ok and a, b
end

local function Checkbox(cat, variable, label, tooltip, get, set)
    local setting = Try("setting " .. variable, Settings.RegisterProxySetting, cat, variable,
        Settings.VarType.Boolean, label, true, get, set)
    if setting then Try("checkbox " .. variable, Settings.CreateCheckbox, cat, setting, tooltip) end
end

function TW.AddCheckbox(section, variable, label, tooltip, get, set)
    if not category then return end
    local sub = subs[section]
    if not sub then
        sub = Try("page " .. section, Settings.RegisterVerticalLayoutSubcategory, category, section)
        if not sub then return end
        subs[section] = sub
    end
    Checkbox(sub, variable, label, tooltip, get, set)
end

function TW.OpenSettings()
    if category and Settings.OpenToCategory then
        Try("open", Settings.OpenToCategory, category:GetID())
    else
        TW.Print("the settings page isn't available - use the /tw commands (/tw help).")
    end
end

function TW.InitSettings()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then return end
    category = Try("category", Settings.RegisterVerticalLayoutCategory, "Tippenhauer Works")
    if not category then return end
    Checkbox(category, "TW_CORE_MINIMAP", "Show the minimap button",
        "The gear button by the minimap. Every TippWorks addon is also in the AddOns menu by the minimap.",
        function() return not TW.account.hideMinimap end,
        function(v) TW.SetMinimapButtonShown(v) end)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:SetScript("OnEvent", function()
        Try("register", Settings.RegisterAddOnCategory, category)
    end)
end
