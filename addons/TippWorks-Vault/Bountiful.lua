local _, ns = ...
local TW = TippWorks

-- Bountiful tab: today's Bountiful Delves, read live from each zone's map
-- (the same delve markers the world map draws), with the version shown in
-- the marker's tooltip, the closest flight point and a click-to-waypoint.
local ROW_H, MAX_ROWS = 32, 12 -- two lines: name / version + flight point
local page, rows = nil, {}
local list = {}

local function Clean(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    text = strtrim(text)
    return text ~= "" and text or nil
end

-- Every text line in a delve marker's tooltip (Blizzard puts the story /
-- variant name there).
local function TooltipLines(info)
    local lines = {}
    local function add(t)
        t = Clean(t)
        if t then for line in t:gmatch("[^\n]+") do lines[#lines + 1] = strtrim(line) end end
    end
    add(info.description)
    local set = info.tooltipWidgetSet
    if set and C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID then
        for _, w in ipairs(C_UIWidgetManager.GetAllWidgetsBySetID(set) or {}) do
            local ok, vis = pcall(C_UIWidgetManager.GetTextWithStateWidgetVisualizationInfo, w.widgetID)
            if ok and vis then add(vis.text) end
        end
    end
    return lines
end

-- The line that names the version: one mentioning story/variant, else the
-- first line that isn't just repeating "Bountiful".
local function Variant(lines)
    for _, l in ipairs(lines) do
        if l:lower():find("story") or l:lower():find("variant") then
            return (l:gsub("^[Ss]tory[^:]*:%s*", ""):gsub("^[Vv]ariant[^:]*:%s*", ""))
        end
    end
    for _, l in ipairs(lines) do
        if not l:lower():find("bountiful") then return l end
    end
end

-- First "x/y" count on any delve marker tooltip line matching pattern
-- (e.g. the weekly Gilded Stash count). Cached for 30s.
local found, foundAt = {}, {}
function ns.DelveTooltipCount(pattern)
    if foundAt[pattern] and GetTime() - foundAt[pattern] < 30 then return found[pattern] end
    foundAt[pattern] = GetTime()
    found[pattern] = nil
    if not (C_AreaPoiInfo and C_AreaPoiInfo.GetDelvesForMap) then return end
    for _, zone in ipairs(TW.DELVE_ZONES) do
        local map = TW.FindMapByName(zone)
        for _, poi in ipairs(map and C_AreaPoiInfo.GetDelvesForMap(map) or {}) do
            local info = C_AreaPoiInfo.GetAreaPOIInfo(map, poi)
            for _, line in ipairs(info and TooltipLines(info) or {}) do
                if line:lower():find(pattern) then
                    local a, b = line:match("(%d+)%s*/%s*(%d+)")
                    if a then
                        found[pattern] = { tonumber(a), tonumber(b), line }
                        return found[pattern]
                    end
                end
            end
        end
    end
end

local function Scan()
    wipe(list)
    if not (C_AreaPoiInfo and C_AreaPoiInfo.GetDelvesForMap) then return false end
    for _, zone in ipairs(TW.DELVE_ZONES) do
        local map = TW.FindMapByName(zone)
        if map then
            for _, poi in ipairs(C_AreaPoiInfo.GetDelvesForMap(map) or {}) do
                local info = C_AreaPoiInfo.GetAreaPOIInfo(map, poi)
                local atlas = info and info.atlasName and info.atlasName:lower() or ""
                if info and info.position and atlas:find("bountiful") then
                    local lines = TooltipLines(info)
                    list[#list + 1] = {
                        name = Clean(info.name) or "Delve", zone = zone, bountiful = true,
                        x = info.position.x * 100, y = info.position.y * 100,
                        variant = Variant(lines), lines = lines,
                    }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.zone ~= b.zone then return a.zone < b.zone end
        return a.name < b.name
    end)
    return true
end

local function KeysText()
    local id = ns.db.currencyIDs and ns.db.currencyIDs.keys
    local info = id and C_CurrencyInfo.GetCurrencyInfo(id)
    return info and ("  |  keys: %d"):format(info.quantity) or ""
end

function ns.CreateBountifulPage(parent, top)
    page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    for i = 1, MAX_ROWS do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(ns.WIDTH - 20, ROW_H)
        b:SetPoint("TOPLEFT", 10, top - (i - 1) * ROW_H)
        b:RegisterForClicks("LeftButtonUp")
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.name:SetPoint("TOPLEFT", 4, -1)
        b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.sub:SetPoint("BOTTOMLEFT", 14, 3)
        b.sub:SetWidth(ns.WIDTH - 40)
        b.sub:SetJustifyH("LEFT")
        b.sub:SetWordWrap(false)
        b:SetScript("OnClick", function(self) if self.delve then TW.ActivateDelve(self.delve) end end)
        b:SetScript("OnEnter", function(self)
            local d = self.delve
            if not d then return end
            local fp, yards = TW.ClosestFlightPoint(d)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(d.name .. "  |cffffd100Bountiful|r")
            GameTooltip:AddLine(("%s  %.1f, %.1f"):format(d.zone, d.x, d.y), 1, 1, 1)
            if d.variant then GameTooltip:AddLine("Version: " .. d.variant, 1, 1, 1, true) end
            for _, l in ipairs(d.lines) do
                if l ~= d.variant then GameTooltip:AddLine(l, 0.8, 0.8, 0.8, true) end
            end
            if fp then GameTooltip:AddLine("Closest flight: " .. fp .. (yards and (" (~%d yd)"):format(yards) or ""), 1, 1, 1) end
            GameTooltip:AddLine("Click: waypoint (portal first from Silvermoon), share, directions", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        b:Hide()
        rows[i] = b
    end
    page.empty = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    page.empty:SetPoint("TOPLEFT", 14, top - 4)
    page.empty:SetWidth(ns.WIDTH - 28)
    page.empty:SetJustifyH("LEFT")
    page.footer = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.footer:SetPoint("BOTTOMLEFT", 12, 12)
    page.top = -top
    page.contentHeight = -top + 4 * ROW_H + 24
    page:Hide()
    return page
end

local lastScan = 0
function ns.RefreshBountiful(force)
    if not page or not page:IsShown() then return end
    -- Bountiful delves change once a day; rescanning every 30s is plenty.
    local supported = true
    if force or GetTime() - lastScan > 30 then
        supported = Scan()
        lastScan = GetTime()
    end
    for i, row in ipairs(rows) do
        local d = list[i]
        row.delve = d
        if d then
            local fp = TW.ClosestFlightPoint(d)
            row.name:SetText(d.name .. "  |cff888888" .. d.zone .. "|r")
            row.sub:SetText((d.variant and ("|cffffffff" .. d.variant .. "|r") or "|cff888888version: hover|r")
                .. (fp and ("  |cff888888via " .. fp .. "|r") or ""))
            row:Show()
        else
            row:Hide()
        end
    end
    local shown = math.min(#list, MAX_ROWS)
    if #list == 0 then
        page.empty:SetText(supported
            and "No Bountiful Delves found on the Midnight zone maps.\nOpen the world map once (or /tw map) if zone maps haven't loaded yet."
            or "This game version doesn't expose delve map markers to addons.")
        page.empty:Show()
    else
        page.empty:Hide()
    end
    local h = page.top + math.max(shown, 3) * ROW_H + 40
    if math.abs((page.contentHeight or 0) - h) > 1 then
        page.contentHeight = h
        if not InCombatLockdown() then page:GetParent():SetHeight(h) end
    end
    page.footer:SetText(("%d Bountiful today%s"):format(#list, KeysText()))
end
