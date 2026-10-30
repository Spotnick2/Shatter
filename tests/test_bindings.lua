------------------------------------------------------------
-- test_bindings.lua - Shatter Next's key binding (#35): one CLICK binding on
-- the named secure button, labelled for Key Bindings; one key press is one
-- cast, through the same path as a mouse click, whatever the player's
-- ActionButtonUseKeyDown; a key does nothing while the button is hidden (a
-- binding clicks a hidden button, measured on Forever); the bound key shows
-- on the button and in its tooltip.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local VEST, BLADE = 2589, 4002
local BINDING = "CLICK ShatterNextButton:LeftButton"

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

local function casts() return #WoW.actionsOf("cast") end
local function armed(button)
    return button:GetAttribute("*type1") ~= nil or button:GetAttribute("*target-slot1") ~= nil
end

-- 1. The binding, its label and its button.
local xml = assert(io.open("Bindings.xml")):read("*a")
local bound = {}
for name, category in xml:gmatch('<Binding name="([^"]+)" category="([^"]+)"/>') do bound[#bound + 1] = { name, category } end
H.eq(#bound, 1, "Bindings.xml: one binding")
H.check(bound[1] and bound[1][1] == BINDING and bound[1][2] == "Shatter", "...CLICK ShatterNextButton:LeftButton, in Shatter's category")
local button = setup()
H.eq(_G["BINDING_NAME_" .. BINDING], "Shatter Next", "its label in Key Bindings")
H.check(rawget(_G, "ShatterNextButton") == button, "the binding names the secure Shatter Next button")

-- 2. One press, one cast on the selected item, on either ActionButtonUseKeyDown.
for _, cvar in ipairs({ "0", "1" }) do
    button = setup({ cvars = { ActionButtonUseKeyDown = cvar } })
    local item = Shatter.Queue:GetSelected()
    WoW.pressBinding(BINDING)
    H.eq(casts(), 1, "one key press, one cast (cvar " .. cvar .. ")")
    local uses = WoW.actionsOf("use")
    H.check(#uses == 1 and uses[1].bag == item.bag and uses[1].slot == item.slot, "...on the selected item (cvar " .. cvar .. ")")
    H.eq(armed(button), false, "...disarmed after (cvar " .. cvar .. ")")
end
button = setup()
WoW.pressBinding(BINDING, 3)
H.eq(casts(), 1, "a held key (repeated presses, one release): one cast")

-- 3. Hidden, nothing: the window closed, or the Settings view (no button).
button = setup()
Shatter.MainFrame:RequestShown(false)
H.eq(button:IsVisible(), false, "the window is closed")
WoW.pressBinding(BINDING)
H.eq(casts(), 0, "window closed: a key press casts nothing")
H.eq(#WoW.actionsOf("use"), 0, "...targets nothing")
H.eq(armed(button), false, "...and leaves the button disarmed")
button = setup()
Shatter.MainFrame:SetActiveView("settings")
WoW.pressBinding(BINDING)
H.eq(casts(), 0, "Settings view: nothing")

-- 4. Mail view: a hidden window doesn't take or send either.
button = setup()
local handled = 0
local realHandle = Shatter.MailMode.HandlePrimaryClick
Shatter.MailMode.HandlePrimaryClick = function(...) handled = handled + 1 return realHandle(...) end
Shatter.MainFrame:SetActiveView("mail")
Shatter.MainFrame:RequestShown(false)
WoW.pressBinding(BINDING)
H.eq(handled, 0, "Mail view, window closed: the key runs nothing")
Shatter.MainFrame:Show()
Shatter.MainFrame:SetActiveView("mail")
WoW.pressBinding(BINDING)
H.eq(handled, 1, "...shown: the key does what a click does")
Shatter.MailMode.HandlePrimaryClick = realHandle

-- 5. The bound key on the button and in its tooltip; text only.
button = setup()
H.eq(button.hotkey:GetText(), "", "unbound: no key text")
H.check(button.tooltip[2]:find("Options > Keybindings > Shatter", 1, true), "...the tooltip says where to bind it")
WoW.bindings[BINDING] = "CTRL-SHIFT-F"
WoW.fire("UPDATE_BINDINGS")
H.eq(button.hotkey:GetText(), "csF", "bound: the key shows as an action bar's does")
H.eq(button.tooltip[2], "Key: CTRL-SHIFT-F.", "...and in the tooltip")
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.inCombat = true
WoW.bindings[BINDING] = "F9"
H.ok(function() WoW.fire("UPDATE_BINDINGS") end, "rebinding in combat raises nothing")
H.eq(button.hotkey:GetText(), "F9", "...and updates the text")
WoW.inCombat = false
WoW.fire("PLAYER_REGEN_ENABLED")

H.done("test_bindings")
