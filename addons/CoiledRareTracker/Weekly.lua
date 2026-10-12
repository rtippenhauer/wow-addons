local _, ns = ...

-- "Weekly" tab: the level-90 Season 2 weekly gearing checklist (from the
-- Weekly Gearing Guide PDF, verified Oct 9 2026). Reads the game where it can
-- (currencies, Great Vault, equipped tier); the rest are click-to-check.
local ROW_H = 20
local page, rows = nil, {}
local wk, acct -- this character's week; warband-wide (Orin unlock)

---------------------------------------------------------------------------
-- Currencies, found by name so no ids go stale
---------------------------------------------------------------------------
local CURRENCY_NAMES = {
    shards = "Coffer Key Shards",
    keys = "Restored Coffer Key",
    manaflux = "Venomblight Manaflux",
    voidcore = "Nebulous Voidcore",
    marl = "Voidlight Marl",
    veteran = "Veteran Mistcrest",
    stash = "Gilded Stash",
}

local scanned = false -- one scan per session; a name that isn't a currency stays missing
local function FindCurrencies()
    ns.db.currencyIDs = ns.db.currencyIDs or {}
    local ids, missing = ns.db.currencyIDs, false
    for key in pairs(CURRENCY_NAMES) do if not ids[key] then missing = true end end
    if not missing or scanned then return ids end
    scanned = true
    local want = {}
    for key, name in pairs(CURRENCY_NAMES) do if not ids[key] then want[name:lower()] = key end end
    for id = 2500, 4500 do
        local info = C_CurrencyInfo.GetCurrencyInfo(id)
        local key = info and info.name and want[info.name:lower()]
        if key then ids[key] = id; want[info.name:lower()] = nil end
    end
    return ids
end

local function Currency(key)
    local id = FindCurrencies()[key]
    return id and C_CurrencyInfo.GetCurrencyInfo(id)
end

---------------------------------------------------------------------------
-- Week bookkeeping
---------------------------------------------------------------------------
local function CheckWeek()
    local db = ns.db
    db.week = db.week or {}
    wk = db.week
    local now = time()
    if wk.resetAt and now >= wk.resetAt then
        local carry = { lastShards = wk.lastShards, lastManaflux = wk.lastManaflux }
        wipe(wk)
        wk.lastShards, wk.lastManaflux = carry.lastShards, carry.lastManaflux
        ns.Print("new week! Weekly checklist reset - start by visiting the Great Vault.")
    end
    local secs = C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset()
    if secs then wk.resetAt = now + secs end
    wk.checks = wk.checks or {}
    wk.counts = wk.counts or {}
end

-- Shards earned this week: the currency's own weekly counter when it has
-- one, otherwise every increase we see (converting to keys isn't counted).
local function TrackShards()
    local info = Currency("shards")
    if not info then return end
    if wk.lastShards and info.quantity > wk.lastShards then
        wk.shardsSeen = (wk.shardsSeen or 0) + (info.quantity - wk.lastShards)
    end
    wk.lastShards = info.quantity
end

local function TrackManaflux()
    local info = Currency("manaflux")
    if not info then return end
    if wk.lastManaflux and info.quantity < wk.lastManaflux then wk.checks.catalystUsed = true end
    wk.lastManaflux = info.quantity
end

---------------------------------------------------------------------------
-- Readers
---------------------------------------------------------------------------
local function ShardsEarned()
    local info = Currency("shards")
    if not info then return end
    return (info.maxWeeklyQuantity or 0) > 0 and info.quantityEarnedThisWeek or (wk.shardsSeen or 0)
end

-- Once 600 are earned this week, rares (50 shards each) add nothing.
function ns.ShardsCapped()
    if not wk then CheckWeek() end
    local earned = ShardsEarned()
    return earned ~= nil and earned >= 600
end

local function ShardsText()
    local info = Currency("shards")
    if not info then return "?", false end
    local earned = ShardsEarned()
    local keys = Currency("keys")
    local extra = keys and ("  |cff888888(%d keys)|r"):format(keys.quantity) or ""
    return ("%d/600%s"):format(earned, extra), earned >= 600
end

local function VaultClaimText()
    local has = C_WeeklyRewards and C_WeeklyRewards.HasAvailableRewards and C_WeeklyRewards.HasAvailableRewards()
    if has then
        wk.vaultHad = true
        return "|cffff6060claim it!|r", false
    end
    if wk.checks.vault or wk.vaultHad then return "claimed", true end
    return "nothing waiting", true
end

local function DelvesVault()
    if not (C_WeeklyRewards and C_WeeklyRewards.GetActivities and Enum.WeeklyRewardChestThresholdType) then return end
    local acts = C_WeeklyRewards.GetActivities(Enum.WeeklyRewardChestThresholdType.World)
    if not acts or #acts == 0 then return end
    table.sort(acts, function(a, b) return a.threshold < b.threshold end)
    local progress, tiers, slots = 0, {}, 0
    for _, a in ipairs(acts) do
        progress = math.max(progress, a.progress or 0)
        if (a.progress or 0) >= a.threshold then
            slots = slots + 1
            tiers[#tiers + 1] = "T" .. (a.level or "?")
        else
            tiers[#tiers + 1] = "-"
        end
    end
    local top = acts[#acts]
    local done = top and (top.progress or 0) >= top.threshold and (top.level or 0) >= 8
    return ("%d/8  |cff888888slots %s|r"):format(math.min(progress, 8), table.concat(tiers, " ")), done
end

local TIER_SLOTS = { 1, 3, 5, 7, 10 } -- head, shoulders, chest, legs, hands
local function TierPieces()
    local bySet, best = {}, 0
    for _, slot in ipairs(TIER_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        local setID = link and select(16, C_Item.GetItemInfo(link))
        if setID and setID > 0 then
            bySet[setID] = (bySet[setID] or 0) + 1
            best = math.max(best, bySet[setID])
        end
    end
    return best
end

local function CatalystText()
    local info = Currency("manaflux")
    local charges = info and ("%d/8 charges"):format(info.quantity) or "? charges"
    local pieces = TierPieces()
    return ("%s  |cff888888tier %d/5|r"):format(charges, pieces), pieces >= 4
end

-- Nebulous Voidcore has a season cap that grows each week; "at cap" means
-- this week's core (Orin's) has been obtained. Owned = still to spend.
local function VoidcoreText()
    local info = Currency("voidcore")
    if not info then return end
    local earned = info.totalEarned or 0
    local cap = info.maxQuantity or 0
    if earned > 0 then acct.orinUnlocked = true end -- can't have one without the unlock
    local owned = info.quantity > 0 and ("  |cffffd100%d to spend|r"):format(info.quantity) or ""
    if cap > 0 and earned >= cap then
        return ("|cff33ff33got it|r |cff888888(%d/%d)|r%s"):format(earned, cap, owned), true
    end
    if cap > 0 then
        return ("|cffffd100buy from Orin|r |cff888888(%d/%d)|r%s"):format(earned, cap, owned), false
    end
end

local function CanAfford()
    local out = {}
    local gold = GetMoney() / 10000
    out[#out + 1] = (gold >= 5000 and "|cff33ff33" or "|cff888888") .. ("gold %s|r"):format(BreakUpLargeNumbers(math.floor(gold)))
    local marl, vet = Currency("marl"), Currency("veteran")
    if marl then out[#out + 1] = (marl.quantity >= 2000 and "|cff33ff33" or "|cff888888") .. ("Marl %s|r"):format(BreakUpLargeNumbers(marl.quantity)) end
    if vet then out[#out + 1] = (vet.quantity >= 100 and "|cff33ff33" or "|cff888888") .. ("Veteran crests %d|r"):format(vet.quantity) end
    return "You have: " .. table.concat(out, ", ")
end

---------------------------------------------------------------------------
-- The checklist
---------------------------------------------------------------------------
local ORIN = { zone = "Silvermoon City", x = 40.0, y = 64.7 }

local function OpenVault()
    if InCombatLockdown() then return end
    if not WeeklyRewardsFrame then pcall(C_AddOns.LoadAddOn, "Blizzard_WeeklyRewards") end
    if WeeklyRewardsFrame then pcall(ShowUIPanel, WeeklyRewardsFrame) end
end

local function OrinWaypoint()
    local map = ns.FindMapByName(ORIN.zone)
    if map and C_Map.CanSetUserWaypointOnMap(map) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, ORIN.x / 100, ORIN.y / 100))
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        ns.Print("waypoint set to Orin Straylight (Silvermoon 40.0, 64.7).")
    end
end

-- kind: "auto" (read from the game), "check" (click), "count" (left +1 / right -1)
local ITEMS = {
    { key = "vault", label = "Visit the Great Vault", kind = "auto", read = VaultClaimText,
      click = function() OpenVault() end, manual = true,
      tip = { "Claim LAST week's reward after Tuesday reset: one item.",
              "With 3+ slots unlocked you can take a Nebulous Voidcore instead.",
              "Nothing useful? Take Thalassian Tokens of Merit (vendor beside the Vault).",
              "Click: open the Great Vault window.  Right-click: mark claimed." } },
    { key = "shards", label = "Coffer Key Shards", kind = "auto", read = ShardsText,
      tip = { "600 per character per week = 6 Restored Coffer Keys (100 shards each).",
              "Coiled Isle rares give 50 each. Combine at a delve or with Naleidea.",
              "Journey rank 6 also unlocks 2 weekly vendor keys." } },
    { key = "rares", label = "Coiled Isle rares today", kind = "auto",
      read = function()
          local n = 0
          for _ in pairs(ns.db.killed) do n = n + 1 end
          if ns.ShardsCapped() then
              return ("|cff888888not needed - shards capped (%d/%d)|r"):format(n, #ns.RARES), true
          end
          return ("%d/%d"):format(n, #ns.RARES), n >= #ns.RARES
      end,
      click = function() ns.SelectTab("rares") end,
      tip = { "50 shards each, once a day - only worth it until you hit 600 shards for the week.",
              "Once capped this row is ticked off; kill them anyway for rep, mounts or the achievement.",
              "Click: switch to the Rares tab." } },
    { key = "delves", label = "Delves for the Vault (T8+)", kind = "auto", read = DelvesVault,
      fallbackCount = 8,
      tip = { "2 / 4 / 8 delves unlock 1 / 2 / 3 Vault choices for next week.",
              "Eight Tier 8+ runs = three 305 Hero 1/6 choices.",
              "Normal delves count - no Bountiful or key needed for Vault credit.",
              "If T11 is reliable: 4 Tier 11 clears for Gilded Stashes, rest at T8+." } },
    { key = "catalyst", label = "Use the Manaflux (Catalyst)", kind = "auto", read = CatalystText, manual = true,
      tip = { "Venomblight Manaflux charges arrive every two weeks, max 8 stored.",
              "One charge turns eligible armor into tier at its current track/rank.",
              "Head, shoulders, chest, hands, legs count for 2- and 4-piece.",
              "Right-click: mark a charge used this week (auto when charges drop)." } },
    { key = "orin", label = "Orin's weekly Voidcore", kind = "check",
      click = function() OrinWaypoint() end, read = VoidcoreText, extraTip = CanAfford,
      tip = { "Orin Straylight, Silvermoon 40.0, 64.7 - left-click sets a waypoint.",
              "Each character: 5,000 gold, 2,000 Voidlight Marl or 100 Veteran Mistcrests -> 1 core.",
              "Warband unlock (once): Decimus' 'In the Catalyst's Shadow', then Orin's",
              "'Prismatic Potential' (10 Elementary Voidcore Shards), research, then",
              "'Umbral Blessings of the Catalyst'.",
              "Read from the Nebulous Voidcore season cap: at cap = this week's core is yours.",
              "Right-click: mark bought.  Shift-right-click: toggle 'warband unlocked'." } },
    { key = "bountiful", label = "Keyed Bountiful clears", kind = "count",
      tip = { "Spend Restored Coffer Keys on Bountiful Coffers.",
              "A key opens the coffer - not needed for entry or Vault credit.",
              "Left-click +1, right-click -1." } },
    { key = "map", label = "Weekly bounty map used (T8+)", kind = "check",
      tip = { "Delver's Bounty drops weekly; use it for the Hidden Trove (305 Hero 1/6 at T8+).",
              "Right-click to toggle." } },
    { key = "stash", label = "T11 Gilded Stashes", kind = "count", max = 4,
      read = function()
          -- 1) a currency that tracks it, 2) the count on a delve map tooltip.
          local cur = Currency("stash")
          if cur and (cur.maxQuantity or 0) > 0 then
              local n = (cur.maxWeeklyQuantity or 0) > 0 and cur.quantityEarnedThisWeek or cur.quantity
              local cap = (cur.maxWeeklyQuantity or 0) > 0 and cur.maxWeeklyQuantity or cur.maxQuantity
              return ("%d/%d |cff888888(game)|r"):format(n, cap), n >= cap
          end
          local t = ns.DelveTooltipCount and ns.DelveTooltipCount("gilded stash")
          if t then return ("%d/%d |cff888888(map)|r"):format(t[1], t[2]), t[1] >= t[2] end
      end,
      tip = { "Journey rank 4+: up to 4 per week from Tier 11, finished with revives left.",
              "Hero/Myth crests, no key needed.",
              "Read from the game when it shows the count; otherwise left-click +1, right-click -1." } },
}

local function Status(it)
    local c = wk.checks
    if it.kind == "auto" then
        local text, done = it.read()
        if it.key == "delves" and not text then
            local n = wk.counts.delves or 0
            return ("%d/8 |cff888888(manual)|r"):format(n), n >= 8
        end
        if it.key == "catalyst" and c.catalystUsed then return text .. "  |cff33ff33used|r", true end
        if it.key == "vault" and c.vault then return "claimed", true end
        return text or "?", done
    elseif it.kind == "check" then
        if it.read then
            local text, done = it.read()
            if text then return c[it.key] and "|cff33ff33bought|r" or text, done or c[it.key] end
        end
        if it.key == "orin" and not acct.orinUnlocked then
            return c.orin and "|cff33ff33bought|r" or "|cffffd100unlock first?|r", c.orin
        end
        return c[it.key] and "|cff33ff33done|r" or "to do", c[it.key]
    else
        if it.read then
            local text, done = it.read()
            if text then return text, done end
        end
        local n = wk.counts[it.key] or 0
        return it.max and ("%d/%d"):format(n, it.max) or tostring(n), it.max and n >= it.max
    end
end

local function OnClick(self, btn)
    local it = self.item
    local c = wk.checks
    if btn == "RightButton" then
        if it.key == "orin" and IsShiftKeyDown() then
            acct.orinUnlocked = not acct.orinUnlocked or nil
            ns.Print("Orin's Voidcore " .. (acct.orinUnlocked and "marked unlocked for your warband." or "marked not unlocked yet."))
        elseif it.kind == "count" or (it.key == "delves" and not DelvesVault()) then
            wk.counts[it.key] = math.max(0, (wk.counts[it.key] or 0) - 1)
        elseif it.key == "catalyst" then
            c.catalystUsed = not c.catalystUsed or nil
        else
            c[it.key] = not c[it.key] or nil
        end
    else
        if it.click then it.click()
        elseif it.kind == "count" or (it.key == "delves" and not DelvesVault()) then
            wk.counts[it.key] = math.min(it.max or 99, (wk.counts[it.key] or 0) + 1)
        elseif it.kind == "check" then
            c[it.key] = not c[it.key] or nil
        end
    end
    ns.RefreshWeekly()
end

function ns.CreateWeeklyPage(parent, top)
    acct = CoiledRareTrackerAccountDB
    page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    local y = top
    for i, it in ipairs(ITEMS) do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(ns.WIDTH - 20, ROW_H)
        b:SetPoint("TOPLEFT", 10, y)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b.item = it
        b.check = b:CreateTexture(nil, "OVERLAY")
        b.check:SetSize(14, 14)
        b.check:SetPoint("LEFT", 2, 0)
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.label:SetPoint("LEFT", 20, 0)
        b.label:SetText(it.label)
        b.status = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.status:SetPoint("RIGHT", -4, 0)
        b:SetScript("OnClick", OnClick)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(it.label)
            for _, line in ipairs(it.tip) do GameTooltip:AddLine(line, 1, 1, 1, true) end
            if it.extraTip then GameTooltip:AddLine(it.extraTip(), 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        rows[i] = b
        y = y - ROW_H
    end
    page.note = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    page.note:SetPoint("TOPLEFT", 14, y - 6)
    page.note:SetWidth(ns.WIDTH - 28)
    page.note:SetJustifyH("LEFT")
    page.footer = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.footer:SetPoint("BOTTOMLEFT", 12, 12)
    page.contentHeight = -y + 44
    page:Hide()
    return page
end

-- Dated items from the guide (NA reset days).
local UPCOMING = {
    { 2026, 10, 13, "Oct 13 (12.1.5): start 'Ancient Depths, Ancient Venom' - Venomstone research." },
    { 2026, 10, 20, "Oct 20: Venomstones unlock (10 per capped weapon/trinket/neck); crest cap lifted." },
}

function ns.RefreshWeekly()
    CheckWeek()
    TrackShards()
    TrackManaflux()
    if not page or not page:IsShown() then return end
    local done = 0
    for _, b in ipairs(rows) do
        local text, ok = Status(b.item)
        b.status:SetText(text)
        b.check:SetTexture(ok and "Interface\\RaidFrame\\ReadyCheck-Ready" or "Interface\\RaidFrame\\ReadyCheck-Waiting")
        b.label:SetTextColor(ok and 0.6 or 1, ok and 0.6 or 0.82, ok and 0.6 or 0)
        if ok then done = done + 1 end
    end
    local notes = {}
    if UnitLevel("player") < 90 then notes[#notes + 1] = "|cffff6060This checklist is for level 90 characters.|r" end
    local now = time()
    for _, u in ipairs(UPCOMING) do
        local t = time({ year = u[1], month = u[2], day = u[3], hour = 23 })
        if now < t + 7 * 86400 then notes[#notes + 1] = (now < t and "Upcoming: " or "New: ") .. u[4] end
    end
    page.note:SetText(table.concat(notes, "\n"))
    local secs = (wk.resetAt or now) - now
    page.footer:SetText(("%d/%d done  |  weekly reset in %dd %dh"):format(
        done, #rows, math.floor(secs / 86400), math.floor(secs % 86400 / 3600)))
end
