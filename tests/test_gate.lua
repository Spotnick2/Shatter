------------------------------------------------------------
-- test_gate.lua - the Disenchant-spell gate and its lifecycle on Forever:
-- C_SpellBook decides (GetProfessions returns nothing here, the Classic
-- spellbook globals are gone), modules initialize exactly once, and learning
-- or unlearning Enchanting mid-session is followed without a reload.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local function queued() return #(Shatter.Queue:GetItems() or {}) end

WoW.AddItem(2589, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
WoW.SetBagItem(0, 1, { itemID = 2589 })

-- 1. Logs in without Enchanting: disabled, nothing initialized.
WoW.loadAddon()
eq(Shatter.isActive, false, "no Disenchant spell: inactive")
eq(Shatter.disabledNoEnchanting, true, "flagged disabled")
eq(Shatter.MainFrame.frame, nil, "no main frame built for a non-enchanter")

-- Count Events:Register calls from here on: a second module setup would double them.
local registers = 0
local realRegister = Shatter.Events.Register
Shatter.Events.Register = function(...) registers = registers + 1 return realRegister(...) end

-- 2. Learns Enchanting: SPELLS_CHANGED activates.
WoW.enchanter()
WoW.fire("SPELLS_CHANGED")
WoW.flushTimers()
eq(Shatter.isActive, true, "learned mid-session: active without a reload")
check(Shatter.MainFrame.frame ~= nil, "main frame built on activation")
eq(queued(), 1, "the green vest is queued")
local firstRegisters = registers
check(firstRegisters > 0, "modules registered their events")

-- 3. Another SPELLS_CHANGED (it fires often) must not re-run module setup.
WoW.fire("SPELLS_CHANGED")
WoW.fire("SKILL_LINES_CHANGED")
WoW.flushTimers()
eq(registers, firstRegisters, "no second module setup: handlers are not doubled")

-- 4. Unlearns: inactive, window hidden, slash says so.
Shatter.MainFrame.frame:Show()
WoW.knownSpells[13262] = nil
WoW.fire("SPELLS_CHANGED")
eq(Shatter.isActive, false, "unlearned: inactive")
eq(Shatter.MainFrame.frame:IsShown(), false, "window hidden on unlearn")
SlashCmdList.SHATTER("")
check(WoW.chatText():find("not trained", 1, true), "slash feedback after unlearn")

-- 5. Unlearn in combat: the main frame is protected (it parents the secure
-- button), so hiding waits for the end of combat instead of being blocked.
WoW.knownSpells[13262] = true
WoW.fire("SPELLS_CHANGED")
Shatter.MainFrame.frame:Show()
WoW.combat = true
WoW.knownSpells[13262] = nil
H.ok(function() WoW.fire("SPELLS_CHANGED") end, "unlearn in combat does not touch the protected frame")
eq(Shatter.MainFrame.frame:IsShown(), true, "still shown during combat")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(Shatter.MainFrame.frame:IsShown(), false, "hidden once combat ends")

-- 6. A spellbook that is not ready at login reads as "not yet", and the
-- SPELLS_CHANGED that follows settles it.
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.spellbookReady = false
WoW.loadAddon()
eq(Shatter.isActive, false, "spellbook not ready at login: not active yet")
WoW.spellbookReady = true
WoW.fire("SPELLS_CHANGED")
eq(Shatter.isActive, true, "activates when the spellbook arrives")

-- 7. Inactive means inactive everywhere: the minimap button is hidden, its
-- right-click cannot reopen the window, and bag/item events schedule no scan.
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.AddItem(2589, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
WoW.SetBagItem(0, 1, { itemID = 2589 })
WoW.loadAddon()
WoW.flushTimers()
local minimap = Shatter.MinimapButton.button
eq(minimap:IsShown(), true, "minimap button shown while active")
Shatter.SoloMode:ScheduleScan("BEFORE_UNLEARN", 0.2)     -- queued, not yet run
WoW.knownSpells[13262] = nil
WoW.fire("SPELLS_CHANGED")
eq(minimap:IsShown(), false, "minimap button hidden on unlearn")
local queuedBefore = #Shatter.Queue:GetItems()
WoW.SetBagItem(0, 2, { itemID = 2589 })
WoW.fire("BAG_UPDATE_DELAYED")
WoW.fire("GET_ITEM_INFO_RECEIVED", 2589, true)
WoW.flushTimers()
eq(#Shatter.Queue:GetItems(), queuedBefore, "no scan runs while inactive (queued or new)")
minimap:Show()   -- even if something showed it, a right-click must not reopen Shatter
WoW.press(minimap, "RightButton")
eq(Shatter.MainFrame.frame:IsShown(), false, "minimap right-click cannot reopen a disabled Shatter")
WoW.press(minimap, "LeftButton")
eq(Shatter.MainFrame.frame:IsShown(), false, "minimap left-click cannot either")
-- Relearned: the button follows its preference and the queue is rebuilt.
WoW.knownSpells[13262] = true
WoW.fire("SPELLS_CHANGED")
WoW.flushTimers()
eq(minimap:IsShown(), true, "minimap button back on relearn")
eq(#Shatter.Queue:GetItems(), 2, "queue rebuilt on relearn")

-- 8. First activation during combat waits: the secure button cannot be
-- created or configured under lockdown.
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.spellbookReady = false
WoW.loadAddon()
WoW.combat = true
WoW.spellbookReady = true
H.ok(function() WoW.fire("SPELLS_CHANGED") end, "spellbook arrives in combat")
eq(Shatter.isActive, false, "activation waits for the end of combat")
eq(Shatter.MainFrame.frame, nil, "no secure frame built in combat")
SlashCmdList.SHATTER("")
check(WoW.chatText():find("when combat ends", 1, true), "slash explains the wait")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(Shatter.isActive, true, "activated after combat")
check(Shatter.MainFrame.frame ~= nil, "main frame built after combat")

done("test_gate")
