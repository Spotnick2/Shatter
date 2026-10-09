------------------------------------------------------------
-- test_secure.lua - the Shatter Next secure button on Forever.
--
-- The stub dispatches clicks the way SecureActionButton_OnClick does
-- (Blizzard_FrameXML/SecureTemplates.lua, forever branch): PreClick and
-- PostClick for every registered edge, the action only where
-- down == useOnKeyDown, type=spell -> cast, then target-bag/slot used only
-- while the spell waits for an item. These tests pin what Shatter does on
-- top of that: one left click, one cast, one item; nothing on any other edge
-- or button; never left armed; nothing at all in combat.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local VEST, BLADE = 2589, 4002

local function setup(opts)
    opts = opts or {}
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    for k, v in pairs(opts.cvars or {}) do WoW.cvars[k] = v end
    WoW.AddItem(VEST, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
    WoW.AddItem(BLADE, { name = "Blue Blade", quality = 3, itemLevel = 40, classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON" })
    WoW.SetBagItem(0, 3, { itemID = VEST })
    WoW.SetBagItem(1, 1, { itemID = BLADE })
    WoW.bags[1].size = 4
    WoW.loadAddon()
    WoW.flushTimers()
    Shatter.MainFrame:Show()
    return Shatter.MainFrame.primary
end

local function selected() return Shatter.Queue:GetSelected() end
local function casts() return #WoW.actionsOf("cast") end
local function uses() return WoW.actionsOf("use") end
local function armed(button)
    return button:GetAttribute("*type1") ~= nil or button:GetAttribute("*target-slot1") ~= nil
end

-- Registration: both edges, the action pinned to the up edge, no typerelease.
local button = setup()
H.check(button.clicks[1] == "AnyUp" and button.clicks[2] == "AnyDown", "registers both mouse edges")
H.eq(button:GetAttribute("useOnKeyDown"), false, "useOnKeyDown attribute pins the action to the up edge")
H.eq(button:GetAttribute("*typerelease1"), nil, "no typerelease (press-and-hold release would cast twice)")
H.eq(armed(button), false, "idle button is disarmed")

-- One left click, under either ActionButtonUseKeyDown setting.
for _, cvar in ipairs({ "0", "1" }) do
    button = setup({ cvars = { ActionButtonUseKeyDown = cvar } })
    local item = selected()
    H.check(item ~= nil, "an item is selected (cvar " .. cvar .. ")")
    WoW.click(button, "LeftButton")
    H.eq(casts(), 1, "one cast per click (cvar " .. cvar .. ")")
    local u = uses()
    H.eq(#u, 1, "one item targeted (cvar " .. cvar .. ")")
    H.check(u[1] and u[1].bag == item.bag and u[1].slot == item.slot, "the queued item's slot is targeted (cvar " .. cvar .. ")")
    H.eq((WoW.actions[1] or {}).spell, 13262, "cast by spell ID: no localized name involved (cvar " .. cvar .. ")")
    H.eq(armed(button), false, "disarmed after the click (cvar " .. cvar .. ")")
    H.check(Shatter.Disenchant:HasPending(), "pending result tracking started (cvar " .. cvar .. ")")
end

-- The down edge alone (released outside the button) changes nothing.
button = setup()
WoW.clickEdge(button, "LeftButton", true)
H.eq(#WoW.actions, 0, "down edge: no action")
H.eq(Shatter.Disenchant:HasPending(), false, "down edge: no pending state")
H.eq(button:IsEnabled(), true, "down edge: button not disabled before the acting edge")
H.eq(armed(button), false, "down edge: not armed")

-- Right and middle clicks do nothing.
button = setup()
WoW.click(button, "RightButton")
WoW.click(button, "MiddleButton")
H.eq(#WoW.actions, 0, "right/middle click: no action")
H.eq(Shatter.Disenchant:HasPending(), false, "right/middle click: no pending state")

-- Press-and-hold enabled: still exactly one cast.
button = setup({ cvars = { ActionButtonUseKeyHeldSpell = "1" } })
WoW.click(button, "LeftButton")
H.eq(casts(), 1, "ActionButtonUseKeyHeldSpell on: one cast")
H.eq(#uses(), 1, "ActionButtonUseKeyHeldSpell on: one item")

-- A cast the client refuses never uses (equips) the item, and the failure
-- clears the pending state.
button = setup()
WoW.castRefused = true
WoW.click(button, "LeftButton")
H.eq(casts(), 1, "refused cast: the cast was attempted")
H.eq(#uses(), 0, "refused cast: the item is NOT used (no accidental equip)")
WoW.fire("UNIT_SPELLCAST_FAILED", "player", "cast-1", 13262)
H.eq(Shatter.Disenchant:HasPending(), false, "UNIT_SPELLCAST_FAILED clears pending")

-- Another spell's item cursor is up: refuse rather than hand it our item.
button = setup()
WoW.targeting = true
WoW.click(button, "LeftButton")
H.eq(#WoW.actions, 0, "existing targeting cursor: nothing armed, nothing used")
H.check(Shatter.MainFrame.status:GetText():find("current spell", 1, true), "status explains the refusal")

-- Already casting something else: refuse.
button = setup()
WoW.casting = { name = "Hearthstone", startMs = 0, endMs = 10000, spellID = 8690 }
WoW.click(button, "LeftButton")
H.eq(#WoW.actions, 0, "casting another spell: refused")

-- Channeling (UnitChannelInfo, not UnitCastingInfo): refuse too.
button = setup()
WoW.channeling = { name = "Fishing", startMs = 0, endMs = 20000, spellID = 7620 }
WoW.click(button, "LeftButton")
H.eq(#WoW.actions, 0, "channeling a spell: refused")
H.check(Shatter.MainFrame.status:GetText():find("current spell", 1, true), "status explains the channel refusal")

-- A locked item (being moved/traded) is not targeted.
button = setup()
local item = selected()
WoW.bags[item.bag][item.slot].locked = true
WoW.click(button, "LeftButton")
H.eq(#WoW.actions, 0, "locked item: refused")

-- The slot no longer holds the queued item (bags shuffled): refused.
button = setup()
item = selected()
WoW.bags[item.bag][item.slot] = nil
WoW.click(button, "LeftButton")
H.eq(#WoW.actions, 0, "moved item: refused")

-- In combat the button cannot be armed: nothing happens, nothing errors.
button = setup()
WoW.inCombat = true
H.ok(function() WoW.click(button, "LeftButton") end, "click in combat raises nothing")
H.eq(#WoW.actions, 0, "combat: no action")
H.eq(Shatter.Disenchant:HasPending(), false, "combat: no pending state")
WoW.inCombat = false

-- A full successful disenchant, then a click with nothing left: no action.
button = setup()
WoW.SetBagItem(1, 1, nil)                       -- only the vest remains
Shatter.SoloMode:ScheduleScan("TEST", 0)
WoW.flushTimers()
item = selected()
WoW.click(button, "LeftButton")
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 13262)
WoW.bags[item.bag][item.slot] = nil
WoW.SetBagItem(0, 10, { itemID = 10940, count = 2 })   -- Strange Dust lands
WoW.fire("BAG_UPDATE_DELAYED")
WoW.flushTimers()
H.eq(Shatter.Disenchant:HasPending(), false, "result recorded, pending cleared")
H.eq(selected(), nil, "queue empty")
local before = #WoW.actions
WoW.click(button, "LeftButton")
H.eq(#WoW.actions, before, "nothing queued: the click does nothing (never left armed)")

-- Settings and Summary hide the queue: Shatter Next does nothing there, even
-- if the button is still shown (e.g. a view change deferred by combat).
button = setup()
Shatter.MainFrame.activeView = "settings"
WoW.click(button, "LeftButton")
H.eq(#WoW.actions, 0, "settings view: no action")

-- A failure while preparing result tracking must leave the button disarmed:
-- an error in PreClick does NOT cancel the secure action that follows.
button = setup()
Shatter.MaterialTracker.Snapshot = function() error("injected snapshot failure") end
WoW.click(button, "LeftButton")
H.eq(#WoW.actions, 0, "preparation failed: no cast, no item used")
H.eq(Shatter.Disenchant:HasPending(), false, "preparation failed: nothing pending")
H.eq(armed(button), false, "preparation failed: disarmed")
H.check(WoW.chat():find("was not started", 1, true), "the failure is reported")

-- Simulation never touches the game.
button = setup()
local settings = Shatter.Database:GetSettings()
settings.debug, settings.simulateDisenchant = true, true
WoW.click(button, "LeftButton")
WoW.flushTimers()
H.eq(#WoW.actions, 0, "simulation: no cast, no item used")
H.eq(armed(button), false, "simulation: never armed")

H.done("test_secure")
