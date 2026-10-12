local _, ns = ...
local TW = ns.TW

-- Shared delve travel help for TippWorks-Calls and TippWorks-Vault: map ids
-- by zone name, closest flight master, Silvermoon portals, waypoint + share +
-- "how do I get there" for one delve.
-- Sources: noobtoboss / games.gg / Method travel guides - check in game.

TW.CALL_HOLD_LEVEL = 87 -- leveling plan: finish Delver's Calls on Tier 1, hand in around 87-88

TW.DELVE_ZONES = {
    "Eversong Woods", "Silvermoon City", "Isle of Quel'Danas",
    "Zul'Aman", "Harandar", "Voidstorm", "Coiled Isle",
}

-- Flight masters (Midnight Flight Master achievement guide). Silvermoon's
-- coordinates weren't published; Coiled Isle's aren't known yet.
TW.FLIGHT_POINTS = {
    ["Eversong Woods"] = { { "Fairbreeze Village", 44.68, 44.99 }, { "Tranquillen", 47.78, 67.17 } },
    ["Silvermoon City"] = { { "Silvermoon City flight master" } },
    ["Isle of Quel'Danas"] = { { "Terrace of the Sun", 57.58, 33.8 } },
    ["Zul'Aman"] = {
        { "Atal'Aman", 39.91, 40.94 }, { "Torntusk Overlook", 44.84, 65.41 }, { "Amani'Zar Village", 44.01, 33.63 },
        { "Shadebasin Watch", 47.3, 25.53 }, { "Camp Stonewash", 38.88, 23.2 },
    },
    ["Harandar"] = {
        { "Har'athir", 69.39, 52.56 }, { "Har'kuai", 64.6, 23.2 }, { "Har'mara", 35.53, 23.77 },
        { "Har'alnor", 31.74, 67.44 }, { "The Den (behind the waterfall)", 70.77, 52.97 },
    },
    ["Voidstorm"] = {
        { "Howling Ridge", 51.14, 69.25 }, { "Locus Point", 42.27, 73.71 }, { "The Ingress", 36.91, 58.96 },
    },
}

-- Getting to each delve zone, from Silvermoon City (the Midnight hub).
-- portal = where to stand in Silvermoon (sets a waypoint when you're there).
TW.MAP_HINTS = { ["Silvermoon City"] = 2393, ["Coiled Isle"] = 2512 }

TW.TRAVEL = {
    ["Silvermoon City"] = { "You're in the hub - the delve is inside the city." },
    ["Eversong Woods"] = { "Fly out of Silvermoon - Eversong Woods surrounds the city." },
    ["Isle of Quel'Danas"] = { "Fly north from Silvermoon across the water to the Isle of Quel'Danas." },
    ["Zul'Aman"] = { "No portal: fly east out of Silvermoon through Eversong Woods into Zul'Aman." },
    ["Harandar"] = {
        "Take the Harandar portal in Silvermoon (36.9, 68.2) - near the Voidstorm portal and the Catalyst.",
        "Also a portal at Fairbreeze Village in Eversong Woods (45.3, 47.3).",
        "Coming back: the tree portal in Harandar's central cave returns to Silvermoon.",
        -- Confirmed in game (saved by standing on it, Oct 2026).
        portal = { name = "Portal to Harandar", x = 36.9, y = 68.2 },
    },
    ["Voidstorm"] = {
        "Take the Voidstorm portal on the west side of Silvermoon (35.3, 65.5), by the Catalyst.",
        "Unlocked by Magister Umbric's story chapter (ends at Magisters' Terrace on Quel'Danas).",
        portal = { name = "Portal to Voidstorm", x = 35.3, y = 65.5 },
    },
    ["Coiled Isle"] = {
        "Hearth there - set your Hearthstone at the Coiled Isle inn.",
        "Going back: the portal in the Coiled Isle tavern takes you to Silvermoon.",
        "(Guides also mention a portal in Astalor's Sanctum, the Prey hub - only if you've unlocked it.)",
        hearth = true,
    },
}

---------------------------------------------------------------------------
-- Map ids by zone name (no hard-coded ids for the Midnight zones). The game
-- calls some zones "The X" (The Coiled Isle); both spellings match.
---------------------------------------------------------------------------
local function Same(mapName, name)
    return mapName == name or mapName == "The " .. name
end

local mapIndex
local function BuildMapIndex()
    mapIndex = {}
    for id = 2300, 3500 do
        local info = C_Map.GetMapInfo(id)
        if info and info.name and info.name ~= "" then
            local cur = mapIndex[info.name]
            -- Prefer the zone-level map over floors, micro-maps and duplicates.
            if not cur or (info.mapType == Enum.UIMapType.Zone and cur.type ~= Enum.UIMapType.Zone) then
                mapIndex[info.name] = { id = id, type = info.mapType }
            end
        end
    end
end

function TW.FindMapByName(name)
    local maps = TW.db.maps
    if not maps then maps = {}; TW.db.maps = maps end
    local hint = TW.MAP_HINTS[name]
    if hint then
        local info = C_Map.GetMapInfo(hint)
        if info and Same(info.name, name) then return hint end
    end
    local saved = maps[name]
    if saved then
        local info = C_Map.GetMapInfo(saved)
        if info and Same(info.name, name) then return saved end
    end
    -- Where the player is standing is the most trustworthy answer.
    local m = C_Map.GetBestMapForUnit("player")
    while m and m > 0 do
        local info = C_Map.GetMapInfo(m)
        if info and Same(info.name, name) and info.mapType == Enum.UIMapType.Zone then
            maps[name] = m
            return m
        end
        m = info and info.parentMapID
    end
    if not mapIndex then BuildMapIndex() end
    local hit = mapIndex[name] or mapIndex["The " .. name]
    if hit then maps[name] = hit.id end
    return hit and hit.id
end

local closestFP = {}
function TW.ResetMapCache()
    mapIndex = nil
    wipe(closestFP)
    if TW.db.maps then wipe(TW.db.maps) end
end

-- True if any map in the player's chain has this name (works whether a
-- city is its own zone or a sub-map of the zone around it).
function TW.PlayerIsIn(name)
    local m = C_Map.GetBestMapForUnit("player")
    while m and m > 0 do
        local info = C_Map.GetMapInfo(m)
        if info and Same(info.name, name) then return true end
        m = info and info.parentMapID
    end
    return false
end

local function World(map, x, y)
    if map then
        local _, w = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x / 100, y / 100))
        if w then return w.x, w.y, true end
    end
    return x, y, false
end

-- d = { name, zone, x, y } (map percent). Returns name, yards-or-nil.
function TW.ClosestFlightPoint(d)
    local ck = ("%s@%s,%.1f,%.1f"):format(d.name, d.zone, d.x, d.y)
    local c = closestFP[ck]
    if c then return c.name, c.yards end
    local fps = TW.FLIGHT_POINTS[d.zone]
    if not fps then return end
    local map = TW.FindMapByName(d.zone)
    local dx, dy, inYards = World(map, d.x, d.y)
    local best, bestD
    for _, fp in ipairs(fps) do
        if fp[2] then
            local fx, fy = World(map, fp[2], fp[3])
            local dist = math.sqrt((fx - dx) ^ 2 + (fy - dy) ^ 2)
            if not bestD or dist < bestD then best, bestD = fp[1], dist end
        elseif not best then
            best = fp[1]
        end
    end
    closestFP[ck] = { name = best, yards = inYards and bestD or nil }
    return best, inYards and bestD or nil
end

---------------------------------------------------------------------------
-- Portals in Silvermoon. A spot saved in game (/tw portal <zone>) beats the
-- guide's, and is warband-wide: a portal is in the same place for every alt.
---------------------------------------------------------------------------
function TW.PortalFor(zone)
    local saved = TW.account.portals and TW.account.portals[zone]
    if saved then return { name = "Portal to " .. zone .. " (your saved spot)", x = saved.x, y = saved.y } end
    local travel = TW.TRAVEL[zone]
    return travel and travel.portal
end

function TW.SavePortal(query)
    query = (query or ""):lower()
    local zone
    for _, z in ipairs(TW.DELVE_ZONES) do
        if query ~= "" and z:lower():find(query, 1, true) then zone = z break end
    end
    if not zone then TW.Print("usage: /tw portal <zone>  e.g. /tw portal harandar  (stand on the portal in Silvermoon)") return end
    local sm = TW.FindMapByName("Silvermoon City")
    local p = sm and C_Map.GetPlayerMapPosition(sm, "player")
    if not p then TW.Print("stand in Silvermoon City, on the portal, then try again.") return end
    TW.account.portals = TW.account.portals or {}
    TW.account.portals[zone] = { x = p.x * 100, y = p.y * 100 }
    TW.Print(("saved the %s portal at %.1f, %.1f for all your characters - delve clicks from Silvermoon will point here."):format(zone, p.x * 100, p.y * 100))
end

---------------------------------------------------------------------------
-- Sharing: /tw share group|say|guild|self. "group" = party/raid when
-- grouped, otherwise only you see it.
---------------------------------------------------------------------------
function TW.ShareCommand(mode)
    mode = (mode or ""):lower()
    if mode == "group" or mode == "say" or mode == "guild" or mode == "self" then
        TW.db.shareMode = mode
        TW.Print("delve shares now go to: " .. mode .. (mode == "group" and " (party/raid when grouped, otherwise only you)" or "") .. ".")
    else
        TW.Print("delve shares go to: " .. (TW.db.shareMode or "group") .. ". Options: /tw share group | say | guild | self")
    end
end

local function ChatChannel()
    local mode = TW.db.shareMode or "group"
    if mode == "self" then return end
    if mode == "say" then return "SAY" end
    if mode == "guild" then return IsInGuild() and "GUILD" or nil end
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function Send(msg, channel)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    pcall(send, msg, channel)
end

local function ShareLine(d, pinSet)
    local fp = TW.ClosestFlightPoint(d)
    local label = d.bountiful
        and ("Bountiful delve: " .. d.name .. (d.variant and (" (" .. d.variant .. ")") or ""))
        or ("Delver's Call: " .. d.quest)
    local msg = ("%s - %s %.1f, %.1f%s"):format(
        label, d.zone, d.x, d.y, fp and (" (closest flight: " .. fp .. ")") or "")
    -- Only link the pin we just placed, never a stale one from earlier.
    local link = pinSet and C_Map.GetUserWaypointHyperlink and C_Map.GetUserWaypointHyperlink()
    if link then msg = msg .. " " .. link end
    return msg
end

local function SetDelveWaypoint(d)
    local map = TW.FindMapByName(d.zone)
    if not map then
        TW.Print("couldn't find the " .. d.zone .. " map - try /tw map once you're there.")
        return false
    end
    if TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(map, d.x / 100, d.y / 100, { title = d.name })
    end
    if C_Map.CanSetUserWaypointOnMap(map) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, d.x / 100, d.y / 100))
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        return true, true
    end
    TW.Print("Blizzard won't place a map pin on " .. d.zone .. " - use the coordinates below.")
    return true, false
end

local callTipShown
local function Describe(d)
    local Print = TW.Print
    local fp, yards = TW.ClosestFlightPoint(d)
    Print(("|cffffd100%s|r (%s %.1f, %.1f)"):format(d.name, d.zone, d.x, d.y))
    local travel = TW.TRAVEL[d.zone]
    if travel and not TW.PlayerIsIn(d.zone) then
        Print("  |cff66ccffGetting there:|r")
        for _, line in ipairs(travel) do Print("    " .. line) end
        if travel.hearth then
            local bind = GetBindLocation and GetBindLocation()
            if bind and bind ~= "" then Print("    Your Hearthstone is set to: |cffffffff" .. bind .. "|r") end
        end
    end
    if fp then
        Print("  Then fly to: " .. fp .. (yards and (" (~%d yd from the entrance)"):format(yards) or ""))
    end
    Print("  Look for: the delve entrance - the swirling delve portal / delve icon at the waypoint.")
    if d.variant then Print("  Version today: |cffffffff" .. d.variant .. "|r") end
    if d.bountiful then
        Print("  Bountiful today: bring a Restored Coffer Key for the Bountiful Coffer at the end.")
        Print("  (The key is only for the coffer - entry and Great Vault credit don't need one.)")
    end
    if d.quest and d.stage == "run" then
        Print("  |cff66ccffStep 2:|r you have the Call - run the delve, any tier (Tier 1 is fine).")
        Print(("  Afterwards keep the finished quest in your log until level %d, then click again to turn in."):format(TW.CALL_HOLD_LEVEL))
    elseif d.quest then
        if d.pickupWhat then
            Print(("  |cff66ccffQuest pickup:|r %s - %s %.1f, %.1f (waypoint set here)"):format(
                d.pickupWhat, d.zone, d.x, d.y))
        elseif d.inside then
            Print("  |cff66ccffQuest pickup:|r INSIDE the delve - " .. d.inside .. ".")
        end
        Print("  Accept the Call before you complete that delve. Leveling: finish it on Tier 1,")
        Print(("  then keep the finished quest in your log until about level %d-88."):format(TW.CALL_HOLD_LEVEL))
        if d.turnin then Print("  Turn in to: " .. d.turnin) end
        if not callTipShown then
            callTipShown = true
            Print("  |cff888888Can't see the pickup on an alt? Minimap tracking -> enable 'Track Warband Completed Quests'.")
            Print("  Your warband also needs 'Void Walk With Me' (end of Eversong's Shadowfall story) done once.|r")
        end
    end
    if d.note then Print("  Note: " .. d.note) end
end

-- Waypoint (or the Silvermoon portal first), share, and explain.
function TW.ActivateDelve(d)
    -- Standing in Silvermoon and the zone has a portal there: point at the
    -- portal first; click again once you're through for the entrance.
    local portal = TW.PortalFor(d.zone)
    if portal and TW.PlayerIsIn("Silvermoon City") and not TW.PlayerIsIn(d.zone) then
        local sm = TW.FindMapByName("Silvermoon City")
        if sm and C_Map.CanSetUserWaypointOnMap(sm) then
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(sm, portal.x / 100, portal.y / 100))
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            TW.Print(("waypoint set to the %s (%.1f, %.1f) - click %s again once you're through."):format(
                portal.name, portal.x, portal.y, d.name))
            Describe(d)
            return
        end
    end
    local ok, pinSet = SetDelveWaypoint(d)
    if not ok then return end
    local msg = ShareLine(d, pinSet)
    if IsShiftKeyDown() then
        local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
        if open then open(msg) end
    else
        local channel = ChatChannel()
        if channel then
            Send(msg, channel)
        else
            -- Make it unmistakable that nobody else saw this.
            TW.Print("|cff888888[Only you can see this]|r " .. msg)
            TW.Print("|cff888888Not sent - you're not in a group. Shift-click to post it yourself, or /tw share say|guild.|r")
        end
    end
    Describe(d)
end

-- /tw map: forget cached map ids and show what each delve zone resolves to.
function TW.MapCommand()
    TW.ResetMapCache()
    for _, z in ipairs(TW.DELVE_ZONES) do TW.Print("  " .. z .. ": " .. tostring(TW.FindMapByName(z))) end
end
