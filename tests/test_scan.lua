------------------------------------------------------------
-- test_scan.lua - the Solo bag scan on Forever's item APIs: C_Item tuples,
-- the container struct (isBound instead of a localized tooltip scan), and the
-- cache-miss path where C_Item.GetItemInfo returns nothing at all.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local function queuedIDs()
    local ids = {}
    for _, item in ipairs(Shatter.Queue:GetItems() or {}) do ids[item.itemID] = true end
    return ids
end

WoW.enchanter()
WoW.AddItem(2589, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
WoW.AddItem(3001, { name = "Bound Bracers", quality = 2, itemLevel = 30, classID = 4, subclassID = 2, equipLoc = "INVTYPE_WRIST" })
WoW.AddItem(4002, { name = "Blue Blade", quality = 3, itemLevel = 40, classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON" })
WoW.AddItem(5003, { name = "Linen Cloth", quality = 1, itemLevel = 5, classID = 7, subclassID = 5, equipLoc = "" })
WoW.AddItem(6004, { name = "Green Potion", quality = 2, itemLevel = 30, classID = 0, subclassID = 1, equipLoc = "" })
WoW.AddItem(7005, { name = "Slow Gloves", quality = 2, itemLevel = 25, classID = 4, subclassID = 2, equipLoc = "INVTYPE_HAND" })
WoW.SetBagItem(0, 1, { itemID = 2589 })
WoW.SetBagItem(0, 2, { itemID = 3001, bound = true })
WoW.SetBagItem(0, 3, { itemID = 4002 })
WoW.SetBagItem(0, 4, { itemID = 5003, count = 20 })
WoW.SetBagItem(0, 5, { itemID = 6004 })
WoW.SetBagItem(0, 6, { itemID = 7005 })
WoW.cacheMiss[7005] = true

H.ok(function() WoW.loadAddon() WoW.flushTimers() end, "login and first scan")
local ids = queuedIDs()
H.check(ids[2589], "uncommon armor queued")
H.check(ids[4002], "rare weapon queued")
H.check(not ids[3001], "soulbound (isBound from the container struct) excluded by default")
H.check(not ids[5003], "common trade goods excluded")
H.check(not ids[6004], "non-equipment green excluded (class/slot from C_Item.GetItemInfoInstant)")
H.check(not ids[7005], "cache miss: not queued yet")

-- The item data arrives: GET_ITEM_INFO_RECEIVED schedules a rescan.
WoW.cacheMiss[7005] = nil
WoW.fire("GET_ITEM_INFO_RECEIVED", 7005, true)
WoW.flushTimers()
H.check(queuedIDs()[7005], "cache resolved: queued after GET_ITEM_INFO_RECEIVED")

-- Including soulbound items brings the bracers in.
Shatter.Database:GetSettings().includeSoulbound = true
Shatter.SoloMode:ScheduleScan("SETTINGS", 0)
WoW.flushTimers()
H.check(queuedIDs()[3001], "soulbound queued when the setting allows it")

-- The version comes from C_AddOns; an unpackaged copy reads "dev".
H.eq(Shatter.VERSION, "v0.2.0-alpha", "version from C_AddOns.GetAddOnMetadata")
WoW.version = "@" .. "project-version" .. "@"
H.eq(Shatter.API.GetAddOnVersion("Shatter"), "dev", "unsubstituted token reads as dev")

-- The main frame uses SetResizeBounds with the documented bounds.
local bounds = Shatter.MainFrame.frame.resizeBounds
H.check(bounds and bounds[1] == 620 and bounds[2] == 400 and bounds[3] == 900 and bounds[4] == 650,
    "SetResizeBounds(620, 400, 900, 650)")

H.done("test_scan")
