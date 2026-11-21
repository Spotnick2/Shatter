------------------------------------------------------------
-- test_methods.lua - every widget method Shatter (and the LibGlass-1.0 it
-- embeds) calls exists on that widget type in the pinned client build
-- (WowTestKit's Kit.checkMethods, against tests/kit.pin's build).
--
-- The exercise reaches as much of the UI as is cheap: load as an enchanter
-- with items in the bags and the inbox, every registered event, the main
-- window in each view and each look, the mailbox, a tooltip, the minimap
-- button's drag, every /shatter command, and every script of every frame
-- the addon made. A method a Blizzard mixin adds in Lua is allowed by name,
-- with the file that adds it.
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

local VEST, BLADE, DUST = 2589, 4002, 10940
WoW.enchanter()
WoW.AddItem(VEST, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST", sellPrice = 120 })
WoW.AddItem(BLADE, { name = "Blue Blade", quality = 3, itemLevel = 40, classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON", sellPrice = 900 })
WoW.AddItem(DUST, { name = "Strange Dust", quality = 1, itemLevel = 10, classID = 7 })
WoW.SetBagItem(0, 1, { itemID = VEST })
WoW.SetBagItem(0, 2, { itemID = BLADE })
WoW.inbox = { { sender = "Alpha Smith", subject = "DE please", items = { [1] = { itemID = VEST } } } }

WoW.loadAddon()
WoW.flushTimers()
WoW.fireAllRegistered()
WoW.flushTimers()
WoW.step(0.1)

local main = Shatter.MainFrame
main:Show()
WoW.step(0.1)
for _, view in ipairs({ "solo", "settings", "summary", "mail", "solo" }) do
    main:SetActiveView(view)
    main:Update()
    WoW.step(0.1)
end
for _, look in ipairs({ "clear", "smoked", "flat", "forever" }) do
    SlashCmdList.SHATTER("skin " .. look)
    WoW.flushTimers()
    WoW.step(0.1)
end

-- Shatter Next, once, and the result landing.
WoW.press(main.primary, "LeftButton")
WoW.fire("UNIT_SPELLCAST_START", "player", "cast-1", 13262)
WoW.step(0.5)
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 13262)
WoW.bags[0][1] = nil
WoW.SetBagItem(0, 10, { itemID = DUST, count = 2 })
WoW.fire("BAG_UPDATE_DELAYED")
WoW.flushTimers()
WoW.step(0.1)

-- The mailbox: the launch panel, a session, the Mail view.
SlashCmdList.SHATTER("mailtest")
MailFrame:Show()
WoW.fire("MAIL_SHOW")
WoW.flushTimers()
Shatter.MailMode:StartNewSessionFromLaunchPanel()
WoW.flushTimers()
main:SetActiveView("mail")
main:Update()
WoW.step(0.1)

-- An item tooltip, in each tooltip mode.
for _, mode in ipairs({ "always", "modifier", "never", "always" }) do
    SlashCmdList.SHATTER("tooltip " .. mode)
    WoW.showItemTooltip(BLADE)
end
-- ...and an open tooltip following the modifier key (its rebuild).
SlashCmdList.SHATTER("tooltip modifier")
WoW.showItemTooltip(BLADE)
WoW.alt = true
WoW.fire("MODIFIER_STATE_CHANGED", "LALT", 1)
WoW.alt = false
WoW.fire("MODIFIER_STATE_CHANGED", "LALT", 0)
SlashCmdList.SHATTER("tooltip always")

-- The minimap button's drag.
Minimap._left, Minimap._right, Minimap._bottom, Minimap._top = 400, 600, 300, 500
local mb = Shatter.MinimapButton.button
if mb._scripts.OnDragStart then mb._scripts.OnDragStart(mb) end
if mb._scripts.OnUpdate then mb._scripts.OnUpdate(mb, 0.02) end
if mb._scripts.OnDragStop then mb._scripts.OnDragStop(mb) end

-- Every /shatter command.
for _, cmd in ipairs({ "help", "scan", "debug", "trace", "trace", "debug", "sim", "simreset", "sim",
                       "yields", "yields reset", "learn", "learn on", "learn clear", "learn off",
                       "ignored", "unignore " .. BLADE, "tooltip", "skin", "reset", "mailtest", "", "" }) do
    SlashCmdList.SHATTER(cmd)
    WoW.flushTimers()
    WoW.step(0.1)
end
main:Show()
main:SetActiveView("settings")
WoW.step(0.1)

-- Every script of every frame Shatter made, once, out of combat: hovers,
-- clicks, drags, focus, keys, wheel. A script that errors fails here.
local ARGS = {
    OnEnter = {}, OnLeave = {}, OnClick = { "LeftButton", false }, OnMouseDown = { "LeftButton" },
    OnMouseUp = { "LeftButton" }, OnDragStart = { "LeftButton" }, OnDragStop = {},
    OnMouseWheel = { -1 }, OnEditFocusGained = {}, OnEditFocusLost = {}, OnEnterPressed = {},
    OnEscapePressed = {}, OnTextChanged = { true }, OnValueChanged = { 1, true }, OnSizeChanged = { 600, 400 },
    OnShow = {}, OnHide = {}, OnUpdate = { 0.02 },
}
local ORDER = { "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp", "OnDragStart", "OnDragStop", "OnMouseWheel",
                "OnEditFocusGained", "OnTextChanged", "OnEnterPressed", "OnEscapePressed", "OnEditFocusLost",
                "OnValueChanged", "OnSizeChanged", "OnUpdate", "OnClick", "OnShow", "OnHide" }
local widgets = {}
for _, w in ipairs(WoW.widgets) do widgets[#widgets + 1] = w end
local ran, failures = 0, {}
for _, w in ipairs(widgets) do
    for _, name in ipairs(ORDER) do
        local fn = w._scripts[name]
        -- The secure button's OnClick is the client's own (the template's).
        if fn and not (name == "OnClick" and w._protected) then
            ran = ran + 1
            local ok, err = WoW.rawpcall(fn, w, unpack(ARGS[name]))
            if not ok then failures[#failures + 1] = name .. " on " .. (w._name or w._type) .. ": " .. tostring(err) end
            WoW.flushTimers()
        end
    end
end
check(ran >= 200, "the sweep ran the frames' scripts (" .. ran .. ")")
eq(#failures, 0, "every script runs without an error" .. (failures[1] and (": " .. failures[1]) or ""))
WoW.step(0.1)

-- Shatter runs each module's setup in SafeCall (Core.lua), which reports an
-- error in chat and carries on: a missing method there would otherwise only
-- shrink what the check below sees.
local failedLine
for _, line in ipairs(WoW.chat) do
    if line:find(" failed:|r", 1, true) then failedLine = line break end
end
check(failedLine == nil, "no part of Shatter failed while exercised" .. (failedLine and (": " .. failedLine) or ""))

local recorded = Kit.checkMethods({ allow = {
    ["Frame:SetBackdrop"] = "BackdropTemplateMixin (Blizzard_SharedXML/Backdrop.lua), BackdropTemplate frames only",
    ["Frame:SetBackdropColor"] = "BackdropTemplateMixin (Blizzard_SharedXML/Backdrop.lua)",
    ["Frame:SetBackdropBorderColor"] = "BackdropTemplateMixin (Blizzard_SharedXML/Backdrop.lua)",
    ["Button:SetBackdrop"] = "BackdropTemplateMixin (Blizzard_SharedXML/Backdrop.lua), BackdropTemplate buttons only",
    ["Button:SetBackdropColor"] = "BackdropTemplateMixin (Blizzard_SharedXML/Backdrop.lua)",
    ["Button:SetBackdropBorderColor"] = "BackdropTemplateMixin (Blizzard_SharedXML/Backdrop.lua)",
    ["GameTooltip:SetHyperlink"] = "TooltipDataHandlerMixin (Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua), via GameTooltipTemplate",
    ["GameTooltip:GetPrimaryTooltipData"] = "TooltipDataHandlerMixin (Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua)",
    ["GameTooltip:RefreshData"] = "GameTooltipDataMixin (Blizzard_GameTooltip/Mainline/GameTooltip.lua:959)",
} })
check(recorded >= 140, "the exercise reached the windows (" .. recorded .. " recorded)")

done("test_methods")
