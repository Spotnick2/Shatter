------------------------------------------------------------
-- test_skin.lua - the look (#14): Clear glass (default), Smoked glass, Flat.
--   * glass is LibGlass-1.0, on a panel of its own under each window;
--   * Flat paints exactly the colours Shatter used before glass;
--   * the switch is live, both ways, and safe in combat;
--   * without LibGlass (a git clone without Libs) every skin renders flat.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local Skin, C
local function setup(opts)
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    WoW.loadAddon(opts)
    WoW.flushTimers()
    Shatter.MainFrame:Show()
    Skin, C = Shatter.Skin, Shatter.C
    return Shatter.MainFrame
end

local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for i = 1, 4 do
        if math.abs((a[i] or 1) - (b[i] or 1)) > 1e-9 then return false end
    end
    return true
end
local CLEAR = { 0, 0, 0, 0 }

-- 1. Default: Clear glass on the window, a pane, a button and the title.
local main = setup()
H.check(Shatter.Glass ~= nil, "LibGlass-1.0 loaded from the TOC")
H.eq(Shatter.Database:GetSettings().skin, "clear", "Clear glass is the default")
local frame = main.frame
local window = Skin.Surface(frame)
H.check(window and window.panel and window.panel:IsShown(), "the window's glass panel is shown")
H.check(same(frame.backdropColor, CLEAR) and same(frame.backdropBorderColor, CLEAR), "...and its square backdrop is cleared")
local tint = Skin.PRESETS.clear.tint
H.check(same(window.g.tint.colorTexture, tint), "the body carries the Clear tint")
local rimAlpha = window.g.rim:GetAlpha()
local pane = Skin.Surface(main.queuePanel)
H.check(pane.fill:IsShown() and same(pane.fill.colorTexture, Skin.PRESETS.clear.pane), "the queue pane: translucent Clear fill")
H.check(pane.fill.masks and #pane.fill.masks == 1, "...rounded by one mask")
local settingsButton = main.settingsButton
local fill = Skin.Surface(settingsButton).fill
H.check(same(settingsButton.backdropColor, CLEAR) and fill:IsShown() and same(fill.colorTexture, { 1, 1, 1, 0.08 }),
    "a button: no backdrop, a faint white fill")
settingsButton.scripts.OnEnter(settingsButton)
H.check(same(fill.colorTexture, { 1, 1, 1, 0.14 }), "...brighter while hovered")
settingsButton.scripts.OnLeave(settingsButton)
H.check(same(fill.colorTexture, { 1, 1, 1, 0.08 }), "...and back")

-- 2. Live to Flat: every surface paints the pre-glass colours.
SlashCmdList.SHATTER("skin flat")
H.eq(Shatter.Database:GetSettings().skin, "flat", "/shatter skin flat saves the choice")
H.check(not window.panel:IsShown(), "the glass panel is hidden")
H.check(same(frame.backdropColor, C.BG_MAIN) and same(frame.backdropBorderColor, C.BORDER), "the window: BG_MAIN, black border")
H.check(not pane.fill:IsShown() and same(main.queuePanel.backdropColor, C.BG_PANEL), "the pane: BG_PANEL backdrop")
H.check(not fill:IsShown() and same(settingsButton.backdropColor, { 0.12, 0.12, 0.12, 1 }), "a button: the old grey")
settingsButton.scripts.OnEnter(settingsButton)
H.check(same(settingsButton.backdropColor, { 0.18, 0.18, 0.18, 1 }), "...the old hover grey")
settingsButton.scripts.OnLeave(settingsButton)
H.check(same(main.tabSolo.backdropColor, C.BG_ACTIVE) and same(main.tabSolo.backdropBorderColor, C.ACCENT),
    "the Solo tab: active grey, accent border")
H.check(same(main.primary.backdropBorderColor, C.ACCENT), "Shatter Next keeps its accent border")

-- 3. Smoked: the body and panes darken; the rim never changes.
SlashCmdList.SHATTER("skin smoked")
H.check(window.panel:IsShown() and same(window.g.tint.colorTexture, Skin.PRESETS.smoked.tint), "Smoked tint on the body")
H.eq(window.g.grain:GetAlpha(), Skin.PRESETS.smoked.grain, "Smoked grain")
H.eq(window.g.wash.gradient[3].a, Skin.PRESETS.smoked.wash, "Smoked wash")
H.check(same(pane.fill.colorTexture, Skin.PRESETS.smoked.pane), "Smoked pane")
H.eq(window.g.rim:GetAlpha(), rimAlpha, "the rim is untouched")
H.check(Shatter.Glass.STYLE.tint ~= Skin.PRESETS.clear.tint, "STYLE holds a copy of the tint, never the preset itself")

-- 4. Queue rows: odd/even, hover, selected; Flat keeps the quality border.
local VEST = 2589
main = setup({ savedDB = { settings = { skin = "flat" } } })
WoW.AddItem(VEST, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
WoW.SetBagItem(0, 1, { itemID = VEST })
WoW.SetBagItem(0, 2, { itemID = VEST })
WoW.fire("BAG_UPDATE_DELAYED")
WoW.flushTimers()
local row1, row2 = main.rows[1], main.rows[2]
H.check(same(row1.backdropColor, { 0.22, 0.18, 0.08, 0.98 }) and same(row1.backdropBorderColor, { 0.95, 0.78, 0.08, 1 }),
    "Flat: the selected row, gold")
local r, g, b = Shatter.GetQualityColor(2)
H.check(same(row2.backdropColor, C.BG_ROW_EVEN) and same(row2.backdropBorderColor, { r * 0.45, g * 0.45, b * 0.45, 0.85 }),
    "Flat: an unselected even row keeps its quality border")
row2.scripts.OnEnter(row2)
H.check(same(row2.backdropColor, C.BG_HOVER), "Flat: hover")
row2.scripts.OnLeave(row2)
Skin.Set("clear")
local rowFill = Skin.Surface(row2).fill
H.check(same(row2.backdropBorderColor, CLEAR) and same(rowFill.colorTexture, { 1, 1, 1, 0.035 }), "Clear: an even row, a faint stripe")
H.check(same(Skin.Surface(row1).fill.colorTexture, { 1, 0.82, 0, 0.15 }), "Clear: the selected row, an accent wash")
row2.scripts.OnEnter(row2)
H.check(same(rowFill.colorTexture, { 1, 1, 1, 0.07 }), "Clear: hover")
row2.scripts.OnLeave(row2)

-- 5. Switching in combat touches no protected frame (the stubs raise if it
-- does) and repaints Shatter Next in place.
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.inCombat = true
H.ok(function() SlashCmdList.SHATTER("skin flat") end, "a switch in combat is allowed")
H.check(same(main.primary.backdropBorderColor, C.ACCENT), "...Shatter Next repainted Flat")
H.ok(function() SlashCmdList.SHATTER("skin smoked") end, "...and back to glass")
WoW.inCombat = false
WoW.fire("PLAYER_REGEN_ENABLED")

-- 6. Unknown names: refused by the command, normalised when saved.
SlashCmdList.SHATTER("skin pink")
H.eq(Shatter.Database:GetSettings().skin, "smoked", "an unknown skin is refused")
H.check(WoW.chat():find("Use /shatter skin clear|smoked|flat", 1, true), "...with the choices")
setup({ savedDB = { settings = { skin = "pink" } } })
H.eq(Shatter.Database:GetSettings().skin, "clear", "an unknown saved skin falls back to Clear")

-- 7. Settings lists the three skins and switches live.
main = setup()
Shatter.SettingsUI:Toggle()
local buttons = Shatter.SettingsUI.skinButtons
H.check(buttons.clear and buttons.smoked and buttons.flat, "Settings offers Clear glass, Smoked glass and Flat")
H.check(same(Skin.Surface(buttons.clear).fill.colorTexture, { 1, 0.82, 0, 0.18 }), "...the current one marked")
buttons.flat.scripts.OnClick(buttons.flat)
H.eq(Shatter.Database:GetSettings().skin, "flat", "clicking Flat saves it")
H.check(not Skin.Surface(main.frame).panel:IsShown(), "...and the window turns flat at once")
H.check(same(buttons.flat.backdropColor, C.BG_ACTIVE), "...Flat now marked")

-- 8. The Mail launch panel is a glass window too.
setup()
Shatter.MailLaunchPanel:Create()
local launch = Skin.Surface(Shatter.MailLaunchPanel.frame)
H.check(launch and launch.panel and launch.panel:IsShown(), "the launch panel has its own glass panel")
H.check(same(Skin.Surface(Shatter.MailLaunchPanel.startButton).fill.colorTexture, { 1, 1, 1, 0.08 }) or
    same(Skin.Surface(Shatter.MailLaunchPanel.startButton).fill.colorTexture, { 1, 0.82, 0, 0.15 }),
    "its buttons are glass fills")

-- 9. No LibGlass (installed from a git clone): flat, whatever the setting.
rawset(_G, "LibStub", nil)
main = setup({ withoutLibs = true })
H.eq(Shatter.Glass, nil, "no library, no glass instance")
H.eq(Shatter.Database:GetSettings().skin, "clear", "the setting is still Clear")
H.eq(Skin.IsGlass(), false, "...but Shatter renders flat")
H.check(same(main.frame.backdropColor, C.BG_MAIN), "the window keeps its Flat backdrop")
H.check(Skin.Surface(main.frame).panel == nil, "no glass panel was built")

H.done("test_skin")
