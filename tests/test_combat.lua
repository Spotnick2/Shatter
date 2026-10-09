------------------------------------------------------------
-- test_combat.lua - the main window parents the secure Shatter Next button,
-- so the client protects it: under combat lockdown it refuses to show, hide,
-- move, resize or rescale it (porting guide, section 3). The stub raises
-- ADDON_ACTION_BLOCKED for each of those, so any path that reaches one in
-- combat fails here. Requests made in combat wait for PLAYER_REGEN_ENABLED.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local function setup()
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    WoW.AddItem(2589, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
    WoW.SetBagItem(0, 1, { itemID = 2589 })
    WoW.loadAddon()
    WoW.flushTimers()
    return Shatter.MainFrame.frame
end

local function inSpecialFrames()
    for _, name in ipairs(UISpecialFrames) do
        if name == "ShatterMainFrame" then return true end
    end
    return false
end

local function enterCombat()
    WoW.fire("PLAYER_REGEN_DISABLED")   -- fires just before lockdown
    WoW.inCombat = true
end

local function leaveCombat()
    WoW.inCombat = false
    WoW.fire("PLAYER_REGEN_ENABLED")
end

H.check(WoW.frames and setup():IsProtected(), "the main frame is protected (it parents a secure button)")

-- Opening in combat waits; /shatter and the minimap say so.
local frame = setup()
enterCombat()
H.ok(function() SlashCmdList.SHATTER("") end, "toggle in combat raises nothing")
H.eq(frame:IsShown(), false, "not shown during combat")
H.check(WoW.chat():find("opens when combat ends", 1, true), "the player is told it opens after combat")
leaveCombat()
H.eq(frame:IsShown(), true, "shown once combat ends")

-- Closing in combat (title-bar x) waits too.
frame = setup()
Shatter.MainFrame:Show()
enterCombat()
H.ok(function() Shatter.MainFrame:RequestShown(false) end, "close in combat raises nothing")
H.eq(frame:IsShown(), true, "still shown during combat")
leaveCombat()
H.eq(frame:IsShown(), false, "closed once combat ends")

-- Open then close again within the same fight: nothing to do afterwards.
frame = setup()
enterCombat()
Shatter.MainFrame:Show()
Shatter.MainFrame:RequestShown(false)
leaveCombat()
H.eq(frame:IsShown(), false, "open+close in one fight cancels out")

-- Escape: the frame leaves UISpecialFrames for the fight and comes back.
frame = setup()
H.eq(inSpecialFrames(), true, "Escape closes the window out of combat")
enterCombat()
H.eq(inSpecialFrames(), false, "removed from UISpecialFrames in combat (a tainted Hide would be blocked)")
leaveCombat()
H.eq(inSpecialFrames(), true, "restored after combat")
leaveCombat()
local n = 0
for _, name in ipairs(UISpecialFrames) do if name == "ShatterMainFrame" then n = n + 1 end end
H.eq(n, 1, "never listed twice")

-- A drag that combat interrupts: PLAYER_REGEN_DISABLED (before lockdown)
-- stops it and saves; nothing touches the frame under lockdown.
frame = setup()
Shatter.MainFrame:Show()
frame:StartMoving()
enterCombat()
H.eq(frame.moving, false, "drag stopped at PLAYER_REGEN_DISABLED")
leaveCombat()

-- Drag and resize attempts during combat are ignored, not blocked.
frame = setup()
Shatter.MainFrame:Show()
frame:SetScale(1.2)
enterCombat()
local titleDrag
for _, child in ipairs(frame.children) do
    if child.scripts.OnDragStart then titleDrag = child break end
end
H.ok(function()
    titleDrag.scripts.OnDragStart(titleDrag)
    titleDrag.scripts.OnDragStop(titleDrag)
end, "title drag in combat raises nothing")
local grip = Shatter.MainFrame.resizeGrip
H.ok(function()
    grip.scripts.OnMouseDown(grip, "LeftButton")
    grip.scripts.OnMouseUp(grip, "LeftButton")
end, "resize grip in combat raises nothing")
H.ok(function() grip.scripts.OnMouseUp(grip, "RightButton") end, "reset in combat raises nothing")
H.ok(function() Shatter.MainFrame:ApplyPosition() end, "profile/window apply in combat raises nothing")
leaveCombat()
H.eq(frame.scale, 1, "reset applied after combat")

-- Events that update the window in combat (cast results, bag updates) never
-- touch the protected button's visibility.
frame = setup()
Shatter.MainFrame:Show()
enterCombat()
H.ok(function()
    Shatter.MainFrame:SetActiveView("settings")
    Shatter.MainFrame:SetActiveView("solo")
    Shatter.MainFrame:Update()
    WoW.fire("BAG_UPDATE_DELAYED")
    WoW.flushTimers()
end, "view switches and updates in combat raise nothing")
leaveCombat()
H.eq(Shatter.MainFrame.primary:IsShown(), true, "Shatter Next visible again after combat")

-- A mailbox opened in combat (it can happen at the edge of a fight).
frame = setup()
MailFrame:Show()
enterCombat()
H.ok(function() WoW.fire("MAIL_SHOW") WoW.flushTimers() end, "MAIL_SHOW in combat raises nothing")
leaveCombat()

-- Enable/Disable are protected on the secure button: the queue emptying in
-- combat must not disable it there, and the change lands after combat.
frame = setup()
Shatter.MainFrame:Show()
H.eq(Shatter.MainFrame.primary:IsEnabled(), true, "Shatter Next enabled with an item queued")
enterCombat()
WoW.bags[0][1] = nil
H.ok(function() WoW.fire("BAG_UPDATE_DELAYED") WoW.flushTimers() Shatter.MainFrame:Update() end,
    "queue emptied in combat: no protected Enable/Disable")
leaveCombat()
WoW.flushTimers()
H.eq(Shatter.MainFrame.primary:IsEnabled(), false, "disabled after combat once the queue is empty")

-- View changes across combat are replayed: Settings -> Solo in a fight
-- brings Shatter Next back after it.
frame = setup()
Shatter.MainFrame:Show()
Shatter.MainFrame:SetActiveView("settings")
H.eq(Shatter.MainFrame.primary:IsShown(), false, "Settings hides Shatter Next")
enterCombat()
Shatter.MainFrame:SetActiveView("solo")
leaveCombat()
H.eq(Shatter.MainFrame.primary:IsShown(), true, "Solo chosen in combat: Shatter Next shown after it")

-- Solo -> Settings in a fight: hidden after it, and inert meanwhile.
frame = setup()
Shatter.MainFrame:Show()
enterCombat()
Shatter.MainFrame:SetActiveView("settings")
leaveCombat()
H.eq(Shatter.MainFrame.primary:IsShown(), false, "Settings chosen in combat: Shatter Next hidden after it")

H.done("test_combat")
