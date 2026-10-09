------------------------------------------------------------
-- test_events.lua - event registration on this client: an unknown name
-- throws, a refusal returns false (porting guide, section 3). Both are
-- reported, and losing a required event stops Shatter Next from arming.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

WoW.enchanter()
WoW.AddItem(2589, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
WoW.SetBagItem(0, 1, { itemID = 2589 })
WoW.refusedEvents.LOOT_OPENED = true
WoW.badEvents.CHAT_MSG_LOOT = true

H.ok(function() WoW.loadAddon() WoW.flushTimers() end, "a throwing RegisterEvent does not abort login")
H.eq(Shatter.isActive, true, "still active")
local failed = Shatter.Events:GetFailed()
H.eq(failed.LOOT_OPENED, "refused", "a false return is recorded as a refusal")
H.check(failed.CHAT_MSG_LOOT ~= nil, "a throw is recorded")
H.check(WoW.chat():find("Could not register LOOT_OPENED", 1, true), "refusal reported in chat")
H.check(WoW.chat():find("Shatter Next is disabled", 1, true), "required event: the user is told why")
H.eq(Shatter.Events:IsHealthy(), false, "a required event is missing")

-- Shatter Next must not arm a macro without its result tracking.
Shatter.MainFrame.frame:Show()
local button = Shatter.MainFrame.primary
WoW.click(button, "LeftButton")
H.eq(#WoW.actionsOf("use"), 0, "no item used")
H.eq(#WoW.actionsOf("cast"), 0, "no cast")

-- A non-required event failing leaves Shatter Next usable.
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.badEvents.CHAT_MSG_LOOT = true
WoW.AddItem(2589, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
WoW.SetBagItem(0, 1, { itemID = 2589 })
WoW.loadAddon()
WoW.flushTimers()
H.eq(Shatter.Events:IsHealthy(), true, "an optional event missing is not fatal")
Shatter.MainFrame.frame:Show()
WoW.click(Shatter.MainFrame.primary, "LeftButton")
H.eq(#WoW.actionsOf("use"), 1, "healthy: the same click uses the queued item")

-- A refused UNIT_SPELLCAST_FAILED_QUIET is just as fatal: Disenchant treats
-- it as a failure signal, and without it a failed cast stays pending.
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.refusedEvents.UNIT_SPELLCAST_FAILED_QUIET = true
WoW.loadAddon()
H.eq(Shatter.Events:IsHealthy(), false, "UNIT_SPELLCAST_FAILED_QUIET is required")

H.done("test_events")
