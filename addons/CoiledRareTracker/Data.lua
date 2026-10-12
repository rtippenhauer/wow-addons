local _, ns = ...

-- The running version. Kept here, not just in the .toc, because WoW only
-- re-reads the .toc on a full restart - after a /reload the .toc's number
-- would still be the old one. Bump both together.
ns.VERSION = "1.9.5"

-- Coordinates are the usual map percentages (as shown by TomTom / guides).
-- Source: Method.gg / Icy Veins Coiled Isle rare guides (Midnight 12.1).
-- Szarith the Fanged is inside the Underbelly (north Vaults of Atal'Utek);
-- stand at it and type  /crt set Szarith  to record its spot.
ns.ZONE_NAME = "Coiled Isle"

ns.RARES = {
    { name = "Farthik the Plunderer", x = 53.78, y = 72.06 },
    { name = "Siltmouth",             x = 50.25, y = 69.27 },
    { name = "Kari'zah the Forgotten", x = 24.93, y = 73.70 },
    { name = "Lockjaw",               x = 31.78, y = 56.70 },
    { name = "Hisstara",              x = 44.15, y = 50.39 },
    { name = "Garsecg",               x = 69.44, y = 44.85 },
    { name = "Nar'zira",              x = 52.37, y = 43.10 },
    { name = "Coin-Eye Skully",       x = 57.29, y = 68.47 },
    { name = "Big Mon",               x = 69.92, y = 63.49 },
    { name = "Sss'alik",              x = 57.37, y = 40.17 },
    { name = "Destra",                x = 52.27, y = 32.43 },
    { name = "Szarith the Fanged",    x = nil,   y = nil, note = "Underbelly (Vaults of Atal'Utek)" },
}

-- uiMapID from guide /way links; still verified by name at runtime.
ns.ZONE_MAP_ID = 2512

---------------------------------------------------------------------------
-- Delves and their "Delver's Call" intro quests (completed by finishing the
-- delve on any tier). quest = the part of the title after "Delver's Call: ".
-- questID where known (Wowhead); the rest are matched by title in your log.
-- Coordinates: Season 1 delve guides; Coiled Isle delves are Season 2 adds.
---------------------------------------------------------------------------
-- All ten Delver's Call quest ids; matched to delves by their in-game title.
ns.DELVERS_CALL_IDS = { 93372, 93384, 93385, 93409, 93410, 93416, 93421, 93427, 93428, 93386 }
ns.CALL_HOLD_LEVEL = 87 -- leveling plan: finish on Tier 1, hand in around 87-88

ns.DELVE_ZONES = {
    "Eversong Woods", "Silvermoon City", "Isle of Quel'Danas",
    "Zul'Aman", "Harandar", "Voidstorm", "Coiled Isle",
}

-- pickup = where the Delver's Call object actually is (in-game verified list,
-- Oct 2026). The click waypoint goes there, not to the entrance.
ns.DELVES = {
    { zone = "Eversong Woods", name = "The Shadow Enclave", quest = "Shadow Enclave", questID = 93372, x = 45.5, y = 86.0,
      pickup = { "Eversong Woods", 50.8, 40.0, "banner on the bridge platform" } },
    { zone = "Silvermoon City", name = "Collegiate Calamity", quest = "Collegiate Calamity", questID = 93384, x = 40.6, y = 53.7,
      turnin = "Naleidea Rivergleam",
      pickup = { "Silvermoon City", 41.8, 61.4, "floating book (Agitated Tome) at ground level" } },
    { zone = "Silvermoon City", name = "The Darkway", quest = "The Darkway", x = 52.2, y = 78.0,
      pickup = { "Silvermoon City", 52.2, 78.0, "poster beside the entrance" } },
    { zone = "Isle of Quel'Danas", name = "Parhelion Plaza", quest = "Parhelion Plaza", x = 46.8, y = 40.9,
      pickup = { "Silvermoon City", 52.5, 77.9, "banner by the Quel'Danas portal, beside The Darkway pickup" } },
    { zone = "Zul'Aman", name = "Twilight Crypts", quest = "Twilight Crypts", questID = 93410, x = 25.4, y = 84.4,
      turnin = "Tavikko",
      pickup = { "Zul'Aman", 43.7, 67.3, "poster on the large tree" } },
    { zone = "Zul'Aman", name = "Atal'Aman", quest = "Atal'Aman", questID = 93409, x = 63.7, y = 80.1,
      inside = "the body near the beginning of the delve - loot/interact with it" },
    { zone = "Harandar", name = "The Grudge Pit", quest = "The Grudge Pit", x = 70.4, y = 64.8,
      pickup = { "Harandar", 71.1, 52.1, "banner attached to a vertical branch" } },
    { zone = "Harandar", name = "The Gulf of Memory", quest = "The Gulf of Memory", questID = 93416, x = 36.7, y = 49.6,
      pickup = { "Harandar", 52.8, 51.7, "banner above the cave, near a small tree" } },
    { zone = "Voidstorm", name = "Sunkiller Sanctum", quest = "Sunkiller Sanctum", questID = 93427, x = 54.8, y = 47.1,
      turnin = "Perodius",
      pickup = { "Voidstorm", 42.7, 70.7, "body beside a flagpole" } },
    { zone = "Voidstorm", name = "Shadowguard Point", quest = "Shadowguard Point", x = 37.1, y = 49.1,
      pickup = { "Voidstorm", 37.6, 51.9, "standing flagpole" } },
    -- The Coiled Isle delves (Ring of Glory 71.35, 56.54; Gnarldor Isle 64.54, 77.58)
    -- are level 90 only with no Delver's Call, so they're not on this leveling list.
    -- They still appear on the Bountiful tab (read live from the map).
}

-- Flight masters (Midnight Flight Master achievement guide). Silvermoon's
-- coordinates weren't published; Coiled Isle's aren't known yet.
ns.FLIGHT_POINTS = {
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

---------------------------------------------------------------------------
-- Delve pickups tracked on the "Curiosities" panel (matched against map
-- marker names, case-insensitive). Add a pattern here if one is missed.
---------------------------------------------------------------------------
ns.CURIO_PATTERNS = {
    { "curiosit", "Curiosity" },   -- Mislaid Curiosity
    { "sturdy chest", "Sturdy Chest" },
    { "heavy trunk", "Heavy Trunk" },
    { "trove", "Trove" },
}

---------------------------------------------------------------------------
-- Getting to each delve zone, from Silvermoon City (the Midnight hub).
-- portal = where to stand in Silvermoon (sets a waypoint when you're there).
-- Sources: noobtoboss / games.gg / Method travel guides - check in game.
---------------------------------------------------------------------------
ns.MAP_HINTS = { ["Silvermoon City"] = 2393 }

ns.TRAVEL = {
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
