------------------------------------------------------------
-- test_learning.lua - learning mode (#40): with /shatter learn on, every
-- disenchant whose loot window Shatter read is logged raw in
-- ShatterDB.yieldLog, flagged where it doesn't fit the table; learned
-- yields are unchanged by it; it is off by default and hidden from the
-- command list.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local VEST, BLADE, DUST, SOUL_DUST, SHARD = 2589, 4002, 10940, 11083, 10978
local ARMOR, WEAPON = 4, 2

-- `items`: { [itemID] = info } for the bag, from slot 3 on.
local function setup(items, savedDB)
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    WoW.AddItem(DUST, { name = "Strange Dust", quality = 1, itemLevel = 1, classID = 7, subclassID = 12, equipLoc = "" })
    WoW.AddItem(SOUL_DUST, { name = "Soul Dust", quality = 1, itemLevel = 1, classID = 7, subclassID = 12, equipLoc = "" })
    WoW.AddItem(VEST, { name = "Green Vest", quality = 2, itemLevel = 20, classID = ARMOR, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
    WoW.SetBagItem(0, 3, { itemID = VEST })
    for itemID, info in pairs(items or {}) do
        WoW.AddItem(itemID, info)
        WoW.SetBagItem(0, 4, { itemID = itemID })
    end
    WoW.loadAddon(savedDB and { savedDB = savedDB } or nil)
    WoW.flushTimers()
    Shatter.MainFrame:Show()
    return Shatter.MainFrame.primary
end

local function lootOf(...)
    local loot = {}
    for i = 1, select("#", ...), 2 do
        local itemID, count = select(i, ...)
        loot[#loot + 1] = { link = WoW.link(itemID), count = count, name = "item" .. itemID }
    end
    return loot
end

-- One disenchant of the selected item; `loot` is what the loot window shows
-- (nil: no loot window, only the bag change).
local function disenchant(button, loot)
    local item = Shatter.Queue:GetSelected()
    WoW.click(button, "LeftButton")
    WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 13262)
    WoW.bags[item.bag][item.slot] = nil
    if loot then
        WoW.loot = loot
        WoW.fire("LOOT_OPENED")
        WoW.SetBagItem(0, 10, { itemID = DUST, count = 2 })
        WoW.loot = {}
        WoW.fire("LOOT_CLOSED")
    else
        WoW.SetBagItem(0, 10, { itemID = DUST, count = 2 })
        WoW.fire("BAG_UPDATE_DELAYED")
    end
    WoW.flushTimers()
end

local function entries()
    local log = ShatterDB.yieldLog
    return log and log.entries or {}
end

-- A canonical text of a table, for comparing learned yields.
local function dump(v)
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. dump(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- 1. Off by default: nothing is logged, and nothing is created.
local button = setup()
disenchant(button, lootOf(DUST, 2))
H.eq(ShatterDB.yieldLog, nil, "off by default: no log is created")
H.check(ShatterDB.yields and ShatterDB.yields["2:4:16-20"], "...while learned yields still count it")

-- 2. Hidden: not in the command list, and no Settings control.
SlashCmdList.SHATTER("help")
H.check(not WoW.chat():find("learn", 1, true), "the command list doesn't mention learn")
H.check(not (Shatter.SettingsUI and Shatter.SettingsUI.learnCheck), "Settings has no learning-mode control")

-- 3. On: a clean disenchant is logged with every field.
button = setup()
WoW.epoch = 1790001234
SlashCmdList.SHATTER("learn on")
H.eq(ShatterDB.yieldLog.enabled, true, "learn on: enabled")
H.check(WoW.chat():find("Learning mode is on: 0 disenchants logged", 1, true), "...and it says so")
disenchant(button, lootOf(DUST, 2))
local e = entries()[1]
H.eq(#entries(), 1, "one disenchant, one entry")
H.check(e and e.itemID == VEST and e.itemLevel == 20 and e.quality == 2 and e.classID == ARMOR
    and e.subclassID == 2 and e.equipLoc == "INVTYPE_CHEST", "the item: id, level, quality, class, subclass, slot")
H.check(e and e.loot[DUST] == 2 and dump(e.loot) == dump({ [DUST] = 2 }), "the loot: each item and its count")
H.eq(e and e.build, "1.60.1." .. WoW.build, "the client build")
H.eq(e and e.time, 1790001234, "the date")
H.eq(e and e.mode, "SOLO", "the mode")
H.check(e and not e.unmatched and not e.unknownLoot and not e.surprise, "a clean disenchant has no flag")
H.eq(e and e.currentItemLevel, nil, "no instance level when it matches the generic one")

-- 4. Flags. Each scenario's learned yields match the same run with the log off.
local function run(items, loot, learn)
    local b = setup(items)
    if learn then SlashCmdList.SHATTER("learn on") end
    disenchant(b, loot)
    return entries()[1], dump(ShatterDB.yields)
end
local EPIC = { [BLADE] = { name = "Old Epic", quality = 4, itemLevel = 30, classID = WEAPON, subclassID = 7, equipLoc = "INVTYPE_WEAPON" } }
-- 4a. An item no rule matches: logged and flagged. (An epic below item level
-- 40; past the default quality cap, and the vest goes so it is selected.)
do
    local b = setup()
    WoW.bags[0][3] = nil
    WoW.AddItem(BLADE, EPIC[BLADE])
    WoW.SetBagItem(0, 4, { itemID = BLADE })
    Shatter.Database:GetSettings().maxQuality = 4
    SlashCmdList.SHATTER("learn on")
    Shatter.Rescan()
    WoW.flushTimers()
    H.eq(Shatter.Queue:GetSelected() and Shatter.Queue:GetSelected().itemID, BLADE, "the epic is queued")
    disenchant(b, lootOf(SHARD, 1))
    e = entries()[1]
    H.check(e and e.itemID == BLADE and e.unmatched == true, "an unmatched item is logged and flagged")
    H.check(e and not e.surprise, "...and not also a surprise (nothing is predicted)")
    H.eq(ShatterDB.yields, nil, "...while learned yields still don't record it")
end

-- 4b. A non-material in the loot.
local onEntry, onYields = run(nil, lootOf(DUST, 2, VEST, 1), true)
local _, offYields = run(nil, lootOf(DUST, 2, VEST, 1), false)
H.check(onEntry and onEntry.unknownLoot == true and onEntry.loot[VEST] == 1 and onEntry.loot[DUST] == 2,
    "a non-material in the loot: logged, with every item, and flagged")
H.check(onEntry and not onEntry.surprise, "...a non-material is not a surprise")
H.eq(onYields, offYields, "...learned yields are the same as with the log off")
H.eq(onYields, "nil", "...(which reject it)")

-- 4c. A material the table never predicts for the item: Soul Dust from a
-- level 20 green (the table has it from 26).
onEntry, onYields = run(nil, lootOf(DUST, 1, SOUL_DUST, 1), true)
_, offYields = run(nil, lootOf(DUST, 1, SOUL_DUST, 1), false)
H.check(onEntry and onEntry.surprise == true and not onEntry.unknownLoot, "a material outside the prediction: a surprise")
H.eq(onYields, offYields, "...learned yields are the same as with the log off")

-- 4d. A clean one: the same yields either way.
onEntry, onYields = run(nil, lootOf(DUST, 2), true)
_, offYields = run(nil, lootOf(DUST, 2), false)
H.eq(onYields, offYields, "a clean disenchant: learned yields the same as with the log off")

-- 5. Not logged: a result seen only as a bag change, and a simulated one.
button = setup()
SlashCmdList.SHATTER("learn on")
disenchant(button, nil)
H.eq(#entries(), 0, "a bag change only: not logged (no loot read)")
button = setup()
SlashCmdList.SHATTER("learn on")
local settings = Shatter.Database:GetSettings()
settings.debug, settings.simulateDisenchant = true, true
WoW.click(button, "LeftButton")
WoW.flushTimers()
H.eq(#entries(), 0, "simulated: not logged")

-- 6. The instance's own item level is kept when it differs.
do
    setup()
    local T = Shatter.DisenchantTables
    SlashCmdList.SHATTER("learn on")
    H.eq(T:LogDisenchant({ itemID = VEST, quality = 2, itemLevel = 20, currentItemLevel = 24, classID = ARMOR }, { [DUST] = 1 }), true,
        "logged directly")
    H.eq(entries()[1].currentItemLevel, 24, "the instance level, where it differs")
end

-- 7. The cap drops the oldest entries.
do
    setup()
    local T = Shatter.DisenchantTables
    SlashCmdList.SHATTER("learn on")
    local max = Shatter.Constants.YIELD_LOG_MAX
    Shatter.Constants.YIELD_LOG_MAX = 3
    for i = 1, 5 do
        WoW.epoch = 1790000000 + i
        T:LogDisenchant({ itemID = VEST, quality = 2, itemLevel = 20, classID = ARMOR }, { [DUST] = i })
    end
    Shatter.Constants.YIELD_LOG_MAX = max
    H.eq(#entries(), 3, "capped at YIELD_LOG_MAX")
    H.check(entries()[1].loot[DUST] == 3 and entries()[3].loot[DUST] == 5, "the oldest dropped, the newest kept, in order")
end

-- 8. Off stops logging and keeps the entries; clear empties them and keeps
-- the switch.
button = setup()
SlashCmdList.SHATTER("learn on")
disenchant(button, lootOf(DUST, 2))
SlashCmdList.SHATTER("learn off")
H.eq(ShatterDB.yieldLog.enabled, false, "learn off: disabled")
H.check(WoW.chat():find("Learning mode is off: 1 disenchant logged", 1, true), "...and it says so, with the count")
WoW.SetBagItem(0, 5, { itemID = VEST })
Shatter.Rescan()
WoW.flushTimers()
disenchant(button, lootOf(DUST, 2))
H.eq(#entries(), 1, "off: the next disenchant isn't logged, the first is kept")
SlashCmdList.SHATTER("learn on")
SlashCmdList.SHATTER("learn clear")
H.eq(#entries(), 0, "learn clear: empties the log")
H.eq(ShatterDB.yieldLog.enabled, true, "...and keeps it on")
SlashCmdList.SHATTER("learn bogus")
H.check(WoW.chat():find("Use /shatter learn on|off|clear.", 1, true), "an unknown argument shows the usage")

-- 9. /shatter learn lists the flagged entries, newest first.
button = setup()
SlashCmdList.SHATTER("learn on")
disenchant(button, lootOf(DUST, 1, SOUL_DUST, 1))
SlashCmdList.SHATTER("learn")
local chat = WoW.chat()
H.check(chat:find("Learning mode is on: 1 disenchant logged (the last 2000 are kept), 1 flagged.", 1, true), "the status line")
H.check(chat:find("Green Vest (Uncommon armor, item level 20): Soul Dust x1, Strange Dust x1 - a material the table doesn't predict", 1, true),
    "the flagged entry, with its loot and why")

-- 10. A Mail item's sender is never stored.
do
    setup()
    local T = Shatter.DisenchantTables
    SlashCmdList.SHATTER("learn on")
    T:LogDisenchant({ itemID = VEST, quality = 2, itemLevel = 20, classID = ARMOR, mode = "MAIL",
        sourceSender = "Some Sender", sourceMailId = "mail:1", sourceId = "Some Sender", mailSubject = "Hi" }, { [DUST] = 1 })
    local text = dump(entries()[1])
    H.check(entries()[1].mode == "MAIL" and not text:find("Some Sender", 1, true) and not text:find("mail:1", 1, true)
        and not text:find("Hi", 1, true), "a Mail item's entry has no sender, mail or subject")
end

-- 10b. The switch and the entries are saved: loaded back (a /reload or a new
-- login), learning mode is still on and adds to the same log.
button = setup(nil, { yieldLog = { enabled = true, entries = { { itemID = VEST, itemLevel = 20, quality = 2, loot = { [DUST] = 1 } } } } })
disenchant(button, lootOf(DUST, 2))
H.check(ShatterDB.yieldLog.enabled == true and #entries() == 2 and entries()[1].loot[DUST] == 1 and entries()[2].loot[DUST] == 2,
    "a saved log that is on: still on after loading, and the next disenchant is added")
button = setup(nil, { yieldLog = { enabled = false, entries = { { itemID = VEST, itemLevel = 20, quality = 2, loot = { [DUST] = 1 } } } } })
disenchant(button, lootOf(DUST, 2))
H.check(ShatterDB.yieldLog.enabled == false and #entries() == 1, "a saved log that is off: stays off, entries kept")

-- 11. A malformed saved log is replaced rather than trusted.
button = setup(nil, { yieldLog = "junk" })
H.eq(Shatter.Database:GetYieldLog(), nil, "a log that isn't a table reads as none")
disenchant(button, lootOf(DUST, 2))
H.eq(ShatterDB.yieldLog, "junk", "...so nothing is logged, and it isn't touched until learn on")
SlashCmdList.SHATTER("learn on")
H.check(type(ShatterDB.yieldLog) == "table" and ShatterDB.yieldLog.enabled == true and #entries() == 0, "learn on starts a fresh log")
button = setup(nil, { yieldLog = { enabled = "yes", entries = "x" } })
H.eq(Shatter.Database:GetYieldLog().enabled, false, "an enabled flag that isn't true reads as off")
H.eq(type(Shatter.Database:GetYieldLog().entries), "table", "entries that aren't a table start empty")

H.done("test_learning")
