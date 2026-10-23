local _, ns = ...

-- The running version. Kept here, not just in the .toc, because WoW only
-- re-reads the .toc on a full restart - after a /reload the .toc's number
-- would still be the old one. Bump both together.
ns.VERSION = "1.0.4"

-- Coordinates are the usual map percentages (as shown by TomTom / guides).
-- Source: Method.gg / Icy Veins Coiled Isle rare guides (Midnight 12.1).
-- Szarith the Fanged is inside the Underbelly (north Vaults of Atal'Utek);
-- stand at it and type  /tw rares set Szarith  to record its spot.
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
