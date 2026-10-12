local ADDON, ns = ...

-- Activity log: records WHY the addon did things (curiosity seen/vanished,
-- party sync, raid marks, blocked actions, our own Lua errors) so a strange
-- moment can be looked at afterwards. /crt log shows it in a copyable box.
local MAX = 400
local buffer = {} -- lines logged before SavedVariables load

local function Store()
    return ns.db and ns.db.log or buffer
end

function ns.Log(cat, fmt, ...)
    local ok, text = pcall(string.format, fmt, ...)
    if not ok then text = tostring(fmt) end
    local log = Store()
    log[#log + 1] = ("%s [%s] %s"):format(date("%m-%d %H:%M:%S"), cat, text)
    while #log > MAX do table.remove(log, 1) end
end

-- Runs fn, logging (and still reporting to the normal error handler) any error.
function ns.Guard(where, fn, ...)
    local n, args = select("#", ...), { ... }
    local ok, err = xpcall(function() return fn(unpack(args, 1, n)) end,
        function(e) return tostring(e) .. "\n" .. debugstack(2, 6, 0) end)
    if not ok then
        ns.Log("ERROR", "%s: %s", where, err)
        geterrorhandler()(err)
    end
end

local viewer
local function ShowLog()
    if not viewer then
        viewer = CreateFrame("Frame", "CoiledRareTrackerLog", UIParent, "BackdropTemplate")
        viewer:SetSize(620, 380)
        viewer:SetPoint("CENTER")
        viewer:SetFrameStrata("DIALOG")
        viewer:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        viewer:SetBackdropColor(0, 0, 0, 0.92)
        viewer:SetMovable(true)
        viewer:EnableMouse(true)
        viewer:RegisterForDrag("LeftButton")
        viewer:SetScript("OnDragStart", viewer.StartMoving)
        viewer:SetScript("OnDragStop", viewer.StopMovingOrSizing)
        local title = viewer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText("Coiled Rare Tracker log  |cff888888(Ctrl+A, Ctrl+C to copy)|r")
        local close = CreateFrame("Button", nil, viewer, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        local scroll = CreateFrame("ScrollFrame", nil, viewer, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -32)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontSmall or ChatFontNormal)
        edit:SetWidth(570)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() viewer:Hide() end)
        scroll:SetScrollChild(edit)
        viewer.edit, viewer.scroll = edit, scroll
    end
    local log = Store()
    viewer.edit:SetText(#log > 0 and table.concat(log, "\n") or "(nothing logged yet)")
    viewer:Show()
    viewer.edit:HighlightText()
    viewer.edit:SetFocus()
    C_Timer.After(0, function() viewer.scroll:SetVerticalScroll(viewer.scroll:GetVerticalScrollRange()) end)
end

function ns.LogCommand(arg)
    if arg == "clear" then
        wipe(Store())
        ns.Print("log cleared.")
    else
        ShowLog()
    end
end

function ns.InitLog()
    ns.db.log = ns.db.log or {}
    for _, line in ipairs(buffer) do ns.db.log[#ns.db.log + 1] = line end
    wipe(buffer)
    ns.Log("INFO", "loaded v%s on %s (%s)", ns.VERSION or "?",
        UnitName("player") or "?", GetRealmName() or "?")
    -- Blizzard blocking one of our calls (taint) shows up here too.
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("ADDON_ACTION_BLOCKED")
    ev:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    -- Any raid-mark change on your target, whoever made it - shows whether a
    -- mark you placed (e.g. a star on your companion) actually stuck.
    ev:RegisterEvent("RAID_TARGET_UPDATE")
    ev:SetScript("OnEvent", function(_, event, who, func)
        if event == "RAID_TARGET_UPDATE" then
            local ok, name = pcall(UnitName, "target")
            if ok and name and not (issecretvalue and issecretvalue(name)) then
                local ok2, icon = pcall(GetRaidTargetIndex, "target")
                ns.Log("MARK", "target %s now has mark %s%s", name, ok2 and tostring(icon) or "?",
                    (IsInGroup() and not UnitIsGroupLeader("player") and not UnitIsGroupAssistant("player")) and
                    " (you're not leader/assist)" or "")
            end
        elseif who == ADDON then
            ns.Log("BLOCKED", "%s: %s", event, tostring(func))
        end
    end)
end
