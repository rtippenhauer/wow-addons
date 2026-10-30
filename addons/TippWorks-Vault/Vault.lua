local ADDON, ns = ...
local TW = TippWorks

-- Level 90 weekly gearing: the Weekly checklist and today's Bountiful Delves,
-- as two tabs of one window. Weekly.lua and Bountiful.lua build the pages.

-- The running version. WoW only re-reads the .toc on a full restart, so the
-- number lives here too. Bump both together.
ns.VERSION = "1.1.0"
ns.WIDTH = 350
ns.Print = TW.Printer("Vault")
ns.Log = TW.Log

local win
local TABS = {
    { key = "weekly", label = "Weekly", title = "Weekly Checklist (90)" },
    { key = "bountiful", label = "Bountiful", title = "Bountiful Delves Today" },
}

local function ShowTab(key)
    win.weekly:SetShown(key == "weekly")
    win.bountiful:SetShown(key == "bountiful")
    win:SetHeight(key == "weekly" and (win.weekly.contentHeight + 40) or win.bountiful.contentHeight)
    ns.RefreshWeekly()
    ns.RefreshBountiful(true)
end

local function CreateWindow()
    win = TW.CreateWindow({ name = "TippWorksVaultFrame", title = TABS[1].title, version = ns.VERSION,
        width = ns.WIDTH, db = ns.db, tabs = TABS, onTab = ShowTab })
    win.weekly = ns.CreateWeeklyPage(win, win.top)
    win.bountiful = ns.CreateBountifulPage(win, win.top)
    win:SelectTab(ns.db.tab == "bountiful" and "bountiful" or "weekly")
    win:SetScript("OnShow", function() ShowTab(ns.db.tab or "weekly") end)
    -- Distances, currencies and the vault change while it's open.
    C_Timer.NewTicker(2, function()
        if win:IsShown() then TW.Guard("vault refresh", function() ns.RefreshWeekly(); ns.RefreshBountiful() end) end
    end)
end

local function Toggle(show, tab)
    if not win then return end
    if tab then win:SelectTab(tab) end
    win:Toggle(show)
end

-- /tw vault stash: where (if anywhere) the game exposes the Gilded Stash count.
local function StashReport()
    local id = ns.db.currencyIDs and ns.db.currencyIDs.stash
    local cur = id and C_CurrencyInfo.GetCurrencyInfo(id)
    if cur then
        ns.Print(("currency '%s' (id %d): have %d, max %d, this week %d/%d"):format(cur.name, id, cur.quantity,
            cur.maxQuantity or 0, cur.quantityEarnedThisWeek or 0, cur.maxWeeklyQuantity or 0))
    else
        ns.Print("no 'Gilded Stash' currency found.")
    end
    local t = ns.DelveTooltipCount("gilded stash")
    ns.Print(t and ("delve map tooltip: \"" .. t[3] .. "\"") or "no Gilded Stash count on any delve map tooltip right now.")
end

local function Summary(tt)
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
end

---------------------------------------------------------------------------
-- TippWorks registration, /tw vault, saved data
---------------------------------------------------------------------------
local module
local function Command(rest)
    local sub = (rest:match("^(%S*)") or ""):lower()
    if sub == "" or sub == "show" or sub == "toggle" then Toggle()
    elseif sub == "weekly" or sub == "bountiful" then Toggle(true, sub)
    elseif sub == "stash" then StashReport()
    else TW.ModuleHelp(module) end
end

module = TW.Register({
    key = "vault",
    name = "Weekly Vault (90)", addon = ADDON, version = ns.VERSION,
    command = Command, toggle = function() Toggle() end, summary = Summary,
    help = {
        { "", "show/hide the weekly checklist" },
        { "weekly", "open the Weekly tab" },
        { "bountiful", "open the Bountiful tab (today's Bountiful Delves)" },
        { "stash", "show where the game reports the Gilded Stash count" },
    },
})
-- /tw weekly and /tw bountiful: open that tab.
TW.modules.weekly = setmetatable({ command = function(rest) if rest == "" then Toggle(true, "weekly") else Command(rest) end end }, { __index = module })
TW.modules.bountiful = setmetatable({ command = function(rest) if rest == "" then Toggle(true, "bountiful") else Command(rest) end end }, { __index = module })

function TippWorksVault_OnAddonCompartmentClick(_, button) Toggle(nil, button == "RightButton" and "bountiful" or nil) end
function TippWorksVault_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff" .. TW.COLOR .. "Tippenhauer Works|r - Weekly Vault")
    Summary(GameTooltip)
    GameTooltip:AddLine("Click: weekly  |  Right-click: bountiful  |  /tw vault help", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end
function TippWorksVault_OnAddonCompartmentLeave() GameTooltip:Hide() end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        TippWorksVaultDB = TippWorksVaultDB or {}
        ns.db = TippWorksVaultDB
        -- One-time: carry this week's checklist over from CoiledRareTracker,
        -- whose saved data TippWorks-Rares keeps.
        if not ns.db.migrated then
            local old, oldAcct = CoiledRareTrackerDB, CoiledRareTrackerAccountDB
            if type(old) == "table" then
                ns.db.week = ns.db.week or old.week
                ns.db.currencyIDs = ns.db.currencyIDs or old.currencyIDs
                if old.tab == "weekly" or old.tab == "bountiful" then ns.db.tab = old.tab end
                TW.Log("VAULT", "copied the weekly checklist from CoiledRareTracker")
            end
            if type(oldAcct) == "table" and oldAcct.orinUnlocked and TW.account.orinUnlocked == nil then
                TW.account.orinUnlocked = oldAcct.orinUnlocked
            end
            ns.db.migrated = true
        end
        TW.ShardsCapped = ns.ShardsCapped -- TippWorks-Rares shows "shards capped"
        TW.Log("INFO", "TippWorks-Vault v%s loaded", ns.VERSION)
        CreateWindow()
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
        self:RegisterEvent("WEEKLY_REWARDS_UPDATE")
        self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        self:RegisterEvent("QUEST_TURNED_IN")
    else
        if event == "QUEST_TURNED_IN" then TW.Guard("vault quest", ns.QuestTurnedIn, name) end
        -- Also tracks shard gains and catalyst charges while the window is closed.
        TW.Guard("vault " .. event, ns.RefreshWeekly)
    end
end)
