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
H.eq(Shatter.isActive, false, "no Disenchant spell: inactive")
H.eq(Shatter.disabledNoEnchanting, true, "flagged disabled")
H.eq(Shatter.MainFrame.frame, nil, "no main frame built for a non-enchanter")

-- Count Events:Register calls from here on: a second module setup would double them.
local registers = 0
local realRegister = Shatter.Events.Register
Shatter.Events.Register = function(...) registers = registers + 1 return realRegister(...) end

-- 2. Learns Enchanting: SPELLS_CHANGED activates.
WoW.enchanter()
WoW.fire("SPELLS_CHANGED")
WoW.flushTimers()
H.eq(Shatter.isActive, true, "learned mid-session: active without a reload")
H.check(Shatter.MainFrame.frame ~= nil, "main frame built on activation")
H.eq(queued(), 1, "the green vest is queued")
local firstRegisters = registers
H.check(firstRegisters > 0, "modules registered their events")

-- 3. Another SPELLS_CHANGED (it fires often) must not re-run module setup.
WoW.fire("SPELLS_CHANGED")
WoW.fire("SKILL_LINES_CHANGED")
WoW.flushTimers()
H.eq(registers, firstRegisters, "no second module setup: handlers are not doubled")

-- 4. Unlearns: inactive, window hidden, slash says so.
Shatter.MainFrame.frame:Show()
WoW.knownSpells[13262] = nil
WoW.fire("SPELLS_CHANGED")
H.eq(Shatter.isActive, false, "unlearned: inactive")
H.eq(Shatter.MainFrame.frame:IsShown(), false, "window hidden on unlearn")
SlashCmdList.SHATTER("")
H.check(WoW.chat():find("not trained", 1, true), "slash feedback after unlearn")

-- 5. Unlearn in combat: the main frame is protected (it parents the secure
-- button), so hiding waits for the end of combat instead of being blocked.
WoW.knownSpells[13262] = true
WoW.fire("SPELLS_CHANGED")
Shatter.MainFrame.frame:Show()
WoW.inCombat = true
WoW.knownSpells[13262] = nil
H.ok(function() WoW.fire("SPELLS_CHANGED") end, "unlearn in combat does not touch the protected frame")
H.eq(Shatter.MainFrame.frame:IsShown(), true, "still shown during combat")
WoW.inCombat = false
WoW.fire("PLAYER_REGEN_ENABLED")
H.eq(Shatter.MainFrame.frame:IsShown(), false, "hidden once combat ends")

-- 6. A spellbook that is not ready at login reads as "not yet", and the
-- SPELLS_CHANGED that follows settles it.
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.spellbookReady = false
WoW.loadAddon()
H.eq(Shatter.isActive, false, "spellbook not ready at login: not active yet")
WoW.spellbookReady = true
WoW.fire("SPELLS_CHANGED")
H.eq(Shatter.isActive, true, "activates when the spellbook arrives")

H.done("test_gate")
