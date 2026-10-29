------------------------------------------------------------
-- test_late_loot.lua - a loot window after the attempt resolved (#10).
-- Diagnostic only until the order is observed on Forever:
--   * with tracing on, every loot event is traced with what it read, how
--     long after which attempt resolved, and what is pending now;
--   * a late window records no yield (nothing learned from it);
--   * a window while the NEXT attempt is pending is still taken as that
--     attempt's: the known exposure, pinned here so the fix flips it;
--   * with tracing off, nothing extra is read.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local VEST, BOOTS, DUST = 2589, 5005, 10940

local function setup()
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    WoW.AddItem(VEST, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
    WoW.AddItem(BOOTS, { name = "Green Boots", quality = 2, itemLevel = 18, classID = 4, subclassID = 2, equipLoc = "INVTYPE_FEET" })
    WoW.AddItem(DUST, { name = "Strange Dust", quality = 1, itemLevel = 1, classID = 7, subclassID = 12, equipLoc = "" })
    WoW.SetBagItem(0, 3, { itemID = VEST })
    WoW.SetBagItem(0, 4, { itemID = BOOTS })
    WoW.loadAddon()
    WoW.flushTimers()
    Shatter.MainFrame:Show()
    SlashCmdList.SHATTER("debug")
    SlashCmdList.SHATTER("trace")
    return Shatter.MainFrame.primary
end

local function traced(text)
    for _, entry in ipairs(ShatterDB.debugLog or {}) do
        if entry.message:find(text, 1, true) then return entry.message end
    end
end

local DUST_LOOT = { { link = WoW.link(DUST), count = 2, name = "Strange Dust" } }

-- RecordYield calls, counted.
local records = 0
local function spy()
    local real = Shatter.DisenchantTables.RecordYield
    Shatter.DisenchantTables.RecordYield = function(...)
        records = records + 1
        return real(...)
    end
end

-- The selected item is cast on and consumed, and the bag update comes first:
-- the attempt resolves 0.2 s later without a loot window.
local function castBagFirst(button)
    local item = Shatter.Queue:GetSelected()
    WoW.click(button, "LeftButton")
    WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-" .. item.itemID, 13262)
    WoW.bags[item.bag][item.slot] = nil
    WoW.fire("BAG_UPDATE_DELAYED")
    WoW.runTimers(0.2)
    return item
end

-- 1. The ordinary order (loot window, then close): one yield, and the trace
-- names the attempt the window belongs to.
local button = setup()
spy()
local first = Shatter.Queue:GetSelected()
WoW.click(button, "LeftButton")
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 13262)
WoW.bags[first.bag][first.slot] = nil
WoW.loot = DUST_LOOT
WoW.fire("LOOT_READY", false)
WoW.fire("LOOT_OPENED", false, true)
H.check(traced("Loot event LOOT_OPENED (autoLoot false, isFromItem true), reads 10940x2; no attempt resolved yet; attempt "
    .. first.itemID .. " pending, succeeded"), "the window is traced with its flags, what it read and the attempt")
WoW.loot = {}
WoW.fire("LOOT_CLOSED")
WoW.runTimers(0.2)
H.eq(records, 1, "loot first: one yield recorded")
local n = Shatter.Database:GetYields()["2:4:16-20"].n

-- 2. The bag update first, then a late window with nothing pending: traced,
-- nothing learned.
WoW.runTimers(0.2)                          -- the queue's rescan
local second = castBagFirst(button)
local before = records
WoW.runTimers(0.3)
WoW.loot = DUST_LOOT
WoW.fire("LOOT_READY", false)
WoW.fire("LOOT_OPENED", false, true)
local line = traced("Loot event LOOT_OPENED (autoLoot false, isFromItem true), reads 10940x2; 0.30 s after item "
    .. second.itemID .. " resolved (bag update; loot event none, loot read none); nothing pending")
H.check(line, "a late window: traced after the attempt that resolved without one")
WoW.loot = {}
WoW.fire("LOOT_CLOSED")
WoW.runTimers(0.5)
H.eq(records, before, "...no yield recorded from it")
H.eq(Shatter.Database:GetYields()["2:4:16-20"].n, n, "...the measured bucket unchanged")

-- 3. A's late window while B is pending: today B takes A's loot. The known
-- exposure (#10), pinned so the fix flips this test.
button = setup()
WoW.SetBagItem(0, 5, { itemID = VEST })
Shatter.SoloMode:ScheduleScan("TEST", 0)
WoW.flushTimers()
local a = castBagFirst(button)
WoW.runTimers(0.2)                          -- the queue's rescan
local b = Shatter.Queue:GetSelected()
H.check(b and not (b.bag == a.bag and b.slot == a.slot), "B is another item")
WoW.click(button, "LeftButton")             -- B pending, not succeeded yet
WoW.loot = DUST_LOOT
WoW.fire("LOOT_READY", false)
H.check(traced("resolved (bag update; loot event none, loot read none); attempt " .. b.itemID .. " pending, not succeeded"),
    "A's late window while B is pending: the trace says so")
H.eq(Shatter.Disenchant.pending and Shatter.Disenchant.pending.loot and Shatter.Disenchant.pending.loot[DUST], 2,
    "KNOWN EXPOSURE (#10): B's attempt takes A's loot today")
WoW.loot = {}

-- 4. Tracing off: a loot event reads nothing extra.
button = setup()
SlashCmdList.SHATTER("trace")
local reads = 0
local readLoot = Shatter.MaterialTracker.ReadLoot
Shatter.MaterialTracker.ReadLoot = function(...) reads = reads + 1 return readLoot(...) end
WoW.loot = DUST_LOOT
WoW.fire("LOOT_READY", false)
WoW.fire("LOOT_OPENED", false, true)
Shatter.MaterialTracker.ReadLoot = readLoot
H.eq(reads, 0, "tracing off, nothing pending: no loot read")
H.eq(Shatter.Disenchant.lastResolved, nil, "...and nothing resolved to compare with")

H.done("test_late_loot")
