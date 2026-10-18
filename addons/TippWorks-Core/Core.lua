local ADDON, ns = ...

-- Tippenhauer Works core. Every TippWorks addon depends on this one and talks
-- to it through the global TippWorks table (addons can't share their private
-- namespace): shared helpers, one activity log, the /tw command and one
-- minimap launcher for all of them.
local TW = {}
TippWorks = TW
ns.TW = TW

-- The running version. WoW only re-reads the .toc on a full restart, so the
-- number lives here too. Bump both together.
TW.VERSION = "1.2.2"
TW.COLOR = "e6a23c"
TW.WEBSITE = "https://github.com/rtippenhauer/wow-addons"

TW.modules = {} -- by key and alias
TW.order = {}   -- registration order, for menus and help

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
-- Print("text") or a module's own printer from TW.Printer("Curios").
function TW.Printer(label)
    local prefix = ("|cff%sTippWorks|r%s "):format(TW.COLOR, label and (" |cff33ff99" .. label .. ":|r") or ":")
    return function(msg) print(prefix .. tostring(msg)) end
end
TW.Print = TW.Printer()
local Print = TW.Print

-- Guard against Midnight "secret values": anything restricted is treated as unknown.
function TW.Safe(fn, ...)
    local ok, a = pcall(fn, ...)
    if not ok or (issecretvalue and issecretvalue(a)) then return nil end
    return a
end

function TW.IsDelve()
    if C_PartyInfo and C_PartyInfo.IsDelveInProgress and TW.Safe(C_PartyInfo.IsDelveInProgress) then return true end
    local _, instType, diff = GetInstanceInfo()
    return instType == "scenario" and diff == 208
end

-- True for this addon family (and the CoiledRareTracker it replaces).
function TW.IsOurs(addonName)
    return type(addonName) == "string" and (addonName:find("^TippWorks") or addonName == "CoiledRareTracker") and true or false
end

---------------------------------------------------------------------------
-- Modules
-- TippWorks.Register{
--     key = "curios", aliases = { "curiosities" }, name = "Delve Curiosities",
--     addon = "TippWorks-Curios", version = "1.0.0",
--     command = function(rest) end,             -- /tw curios <rest>
--     toggle  = function() end,                 -- launcher menu / compartment click
--     summary = function(tooltip) end,          -- optional launcher tooltip lines
--     help = { { "", "show/hide the panel" }, { "reset", "clear the list" } },
-- }
---------------------------------------------------------------------------
function TW.Register(m)
    TW.modules[m.key] = m
    for _, a in ipairs(m.aliases or {}) do TW.modules[a] = m end
    TW.order[#TW.order + 1] = m
    return m
end

local function ModuleHelp(m)
    Print(("|cffffd100%s|r v%s"):format(m.name, m.version or "?"))
    for _, h in ipairs(m.help or {}) do
        Print(("  /tw %s%s - %s"):format(m.key, h[1] ~= "" and (" " .. h[1]) or "", h[2]))
    end
end
TW.ModuleHelp = ModuleHelp

function TW.Help()
    Print(("Tippenhauer Works v%s - %s"):format(TW.VERSION, TW.WEBSITE))
    for _, m in ipairs(TW.order) do
        Print(("  |cffffd100/tw %s|r - %s  |cff888888(/tw %s help)|r"):format(m.key, m.name, m.key))
    end
    Print("  /tw share group|say|guild|self - where delve clicks are shared  |  /tw portal <zone> - save a Silvermoon portal spot")
    Print("  /tw map - re-find the delve zone maps  |  /tw log - activity log (/tw log clear)  |  /tw minimap - show/hide the minimap button")
    Print("  /tw settings - options (also Options > AddOns > Tippenhauer Works)  |  /tw version - installed TippWorks addons  |  /tw help - this list")
end

local function Versions()
    Print(("TippWorks-Core v%s"):format(TW.VERSION))
    for _, m in ipairs(TW.order) do Print(("%s v%s"):format(m.addon or m.name, m.version or "?")) end
end

function TW.Command(msg)
    local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "help" or cmd == "?" then
        TW.Help()
    elseif cmd == "log" then
        TW.LogCommand(rest:lower())
    elseif cmd == "minimap" then
        TW.ToggleMinimapButton()
    elseif cmd == "share" then
        TW.ShareCommand(rest)
    elseif cmd == "portal" then
        TW.SavePortal(rest)
    elseif cmd == "map" then
        TW.MapCommand()
    elseif cmd == "settings" or cmd == "options" or cmd == "config" then
        TW.OpenSettings()
    elseif cmd == "version" or cmd == "versions" then
        Versions()
    elseif TW.modules[cmd] then
        local m = TW.modules[cmd]
        if rest:lower() == "help" or not m.command then ModuleHelp(m) else m.command(rest) end
    else
        Print("unknown command '" .. cmd .. "' - type /tw help")
    end
end

SLASH_TIPPWORKS1 = "/tw"
SLASH_TIPPWORKS2 = "/tippworks"
SlashCmdList.TIPPWORKS = function(msg) TW.Guard("/tw " .. (msg or ""), TW.Command, msg) end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    TippWorksCoreDB = TippWorksCoreDB or {}
    TippWorksAccountDB = TippWorksAccountDB or {}
    TW.db, TW.account = TippWorksCoreDB, TippWorksAccountDB
    TW.InitLog()
    TW.InitLauncher()
    TW.InitSettings()
end)
