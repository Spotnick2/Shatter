------------------------------------------------------------
-- test_skin.lua - the look (#14, #23): WoW Forever (default), Clear glass,
-- Smoked glass, Flat.
--   * WoW Forever is the tooltip's backdrop, on a panel of its own under each
--     window; panes, buttons and rows keep a 1 px backdrop, recoloured;
--   * glass is LibGlass-1.0, on a panel of its own under each window;
--   * Flat paints exactly the colours Shatter used before glass;
--   * the switch is live, every way, and safe in combat;
--   * without LibGlass (a git clone without Libs) the glass looks render
--     WoW Forever.
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
-- A fresh saved table each time: the addon writes into it.
local function AsClear() return { savedDB = { settings = { skin = "clear" } } } end

-- 0. Default: WoW Forever, the tooltip's window.
local main = setup()
eq(Shatter.Database:GetSettings().skin, "forever", "WoW Forever is the default")
eq(Skin.Shown(), "forever", "...and is drawn")
eq(Skin.IsGlass(), false, "...without glass")
local fw = Skin.Surface(main.frame)
check(fw.forever and fw.forever:IsShown(), "the window's WoW Forever panel is shown")
check(not fw.panel:IsShown(), "...the glass panel hidden")
check(same(main.frame._backdropColor, CLEAR) and same(main.frame._backdropBorderColor, CLEAR),
    "...and the window's own 1 px backdrop cleared")
eq(fw.forever._backdrop.edgeFile, "Interface\\Tooltips\\UI-Tooltip-Border", "the tooltip's border")
eq(fw.forever._backdrop.bgFile, "Interface\\Tooltips\\UI-Tooltip-Background", "...over the tooltip's background")
check(same(fw.forever._backdropColor, Skin.FOREVER.window), "...in the tooltip's navy")
check(same(main.queuePanel._backdropColor, Skin.FOREVER.pane) and same(main.queuePanel._backdropBorderColor, Skin.FOREVER.edge),
    "a pane: darkened into the window, a slate edge")
check(not Skin.Surface(main.queuePanel).fill:IsShown(), "...no glass fill")
local sb = main.settingsButton
check(same(sb._backdropColor, { 1, 1, 1, 0.08 }) and same(sb._backdropBorderColor, Skin.FOREVER.edge),
    "a button: a faint white fill, a slate edge")
sb._scripts.OnEnter(sb)
check(same(sb._backdropColor, { 1, 1, 1, 0.14 }), "...brighter while hovered")
sb._scripts.OnLeave(sb)
check(same(main.primary._backdropBorderColor, C.ACCENT), "Shatter Next keeps its accent edge")
check(same(main.tabSolo._backdropBorderColor, C.ACCENT), "...as does the active tab")
check(not main.titleBand:IsShown(), "no title band: the border frames the window")
-- Live, to glass and back.
Skin.Set("clear")
check(not fw.forever:IsShown() and fw.panel:IsShown(), "to Clear: the glass panel replaces it")
Skin.Set("flat")
check(not fw.forever:IsShown() and same(main.frame._backdropColor, C.BG_MAIN), "to Flat: the window's own backdrop")
check(main.titleBand:IsShown(), "...with the title band")
Skin.Set("forever")
check(fw.forever:IsShown() and not fw.panel:IsShown(), "back to WoW Forever")
check(same(sb._backdropColor, { 1, 1, 1, 0.08 }), "...its button fills again")

-- 1. Clear glass on the window, a pane, a button and the title.
main = setup(AsClear())
check(Shatter.Glass ~= nil, "LibGlass-1.0 loaded from the TOC")
eq(Shatter.Glass.preset, "pearl", "the material is Pearl (LibGlass r11)")
eq(Shatter.GlassPreset, "pearl", "...and Shatter knows it")
local style = Shatter.Glass.STYLE
local pearlGrain, pearlWash = style.grain, style.wash
eq(pearlGrain, 0, "Pearl has no grain")
eq(Shatter.Database:GetSettings().skin, "clear", "Clear glass, as saved")
local frame = main.frame
local window = Skin.Surface(frame)
check(window and window.panel and window.panel:IsShown(), "the window's glass panel is shown")
check(not window.forever:IsShown(), "...WoW Forever's hidden")
check(same(frame._backdropColor, CLEAR) and same(frame._backdropBorderColor, CLEAR), "...and its square backdrop is cleared")
local tint = Skin.PRESETS.clear.tint
check(same(window.g.tint._color, tint), "the body carries the Clear tint")
eq(window.g.grain:GetAlpha(), 0, "...no grain on the body")
eq(window.g.wash._gradient[3].a, pearlWash, "...and Pearl's own wash")
local rimAlpha = window.g.rim:GetAlpha()
local pane = Skin.Surface(main.queuePanel)
check(pane.fill:IsShown() and same(pane.fill._color, Skin.PRESETS.clear.pane), "the queue pane: translucent Clear fill")
check(pane.fill._masks and #pane.fill._masks == 1, "...rounded by one mask")
local settingsButton = main.settingsButton
local fill = Skin.Surface(settingsButton).fill
check(same(settingsButton._backdropColor, CLEAR) and fill:IsShown() and same(fill._color, { 1, 1, 1, 0.08 }),
    "a button: no backdrop, a faint white fill")
settingsButton._scripts.OnEnter(settingsButton)
check(same(fill._color, { 1, 1, 1, 0.14 }), "...brighter while hovered")
settingsButton._scripts.OnLeave(settingsButton)
check(same(fill._color, { 1, 1, 1, 0.08 }), "...and back")

-- 2. Live to Flat: every surface paints the pre-glass colours.
SlashCmdList.SHATTER("skin flat")
eq(Shatter.Database:GetSettings().skin, "flat", "/shatter skin flat saves the choice")
check(not window.panel:IsShown(), "the glass panel is hidden")
check(same(frame._backdropColor, C.BG_MAIN) and same(frame._backdropBorderColor, C.BORDER), "the window: BG_MAIN, black border")
check(not pane.fill:IsShown() and same(main.queuePanel._backdropColor, C.BG_PANEL), "the pane: BG_PANEL backdrop")
check(not fill:IsShown() and same(settingsButton._backdropColor, { 0.12, 0.12, 0.12, 1 }), "a button: the old grey")
settingsButton._scripts.OnEnter(settingsButton)
check(same(settingsButton._backdropColor, { 0.18, 0.18, 0.18, 1 }), "...the old hover grey")
settingsButton._scripts.OnLeave(settingsButton)
check(same(main.tabSolo._backdropColor, C.BG_ACTIVE) and same(main.tabSolo._backdropBorderColor, C.ACCENT),
    "the Solo tab: active grey, accent border")
check(same(main.primary._backdropBorderColor, C.ACCENT), "Shatter Next keeps its accent border")

-- 3. Smoked: the body and panes darken; the rim never changes.
SlashCmdList.SHATTER("skin smoked")
check(window.panel:IsShown() and same(window.g.tint._color, Skin.PRESETS.smoked.tint), "Smoked tint on the body")
eq(window.g.grain:GetAlpha(), 0, "Smoked: still no grain over Pearl")
check(math.abs(window.g.wash._gradient[3].a - pearlWash * 0.14 / 0.18) < 1e-9, "Smoked wash: Pearl's, scaled as Smoked always was")
check(same(pane.fill._color, Skin.PRESETS.smoked.pane), "Smoked pane")
eq(window.g.rim:GetAlpha(), rimAlpha, "the rim is untouched")
check(Shatter.Glass.STYLE.tint ~= Skin.PRESETS.clear.tint, "STYLE never holds a preset's own table")
check(style.grain == pearlGrain and style.wash == pearlWash, "...and a skin never writes the material's STYLE")

-- 4. Queue rows: odd/even, hover, selected; Flat keeps the quality border.
local VEST = 2589
main = setup({ savedDB = { settings = { skin = "flat" } } })
WoW.AddItem(VEST, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
WoW.SetBagItem(0, 1, { itemID = VEST })
WoW.SetBagItem(0, 2, { itemID = VEST })
WoW.fire("BAG_UPDATE_DELAYED")
WoW.flushTimers()
local row1, row2 = main.rows[1], main.rows[2]
check(same(row1._backdropColor, { 0.22, 0.18, 0.08, 0.98 }) and same(row1._backdropBorderColor, { 0.95, 0.78, 0.08, 1 }),
    "Flat: the selected row, gold")
local r, g, b = Shatter.GetQualityColor(2)
check(same(row2._backdropColor, C.BG_ROW_EVEN) and same(row2._backdropBorderColor, { r * 0.45, g * 0.45, b * 0.45, 0.85 }),
    "Flat: an unselected even row keeps its quality border")
row2._scripts.OnEnter(row2)
check(same(row2._backdropColor, C.BG_HOVER), "Flat: hover")
row2._scripts.OnLeave(row2)
Skin.Set("clear")
local rowFill = Skin.Surface(row2).fill
check(same(row2._backdropBorderColor, CLEAR) and same(rowFill._color, { 1, 1, 1, 0.035 }), "Clear: an even row, a faint stripe")
check(same(Skin.Surface(row1).fill._color, { 1, 0.82, 0, 0.15 }), "Clear: the selected row, an accent wash")
row2._scripts.OnEnter(row2)
check(same(rowFill._color, { 1, 1, 1, 0.07 }), "Clear: hover")
row2._scripts.OnLeave(row2)

-- 5. Switching in combat touches no protected frame (the stubs raise if it
-- does) and repaints Shatter Next in place.
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.combat = true
H.ok(function() SlashCmdList.SHATTER("skin flat") end, "a switch in combat is allowed")
check(same(main.primary._backdropBorderColor, C.ACCENT), "...Shatter Next repainted Flat")
H.ok(function() SlashCmdList.SHATTER("skin smoked") end, "...and back to glass")
H.ok(function() SlashCmdList.SHATTER("skin forever") end, "...and to WoW Forever")
check(same(main.primary._backdropBorderColor, C.ACCENT), "...Shatter Next repainted WoW Forever")
H.ok(function() SlashCmdList.SHATTER("skin smoked") end, "...and back to glass")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")

-- 6. Unknown names: refused by the command, normalised when saved.
SlashCmdList.SHATTER("skin pink")
eq(Shatter.Database:GetSettings().skin, "smoked", "an unknown skin is refused")
check(WoW.chatText():find("Use /shatter skin forever/clear/smoked/flat", 1, true), "...with the choices")
setup({ savedDB = { settings = { skin = "pink" } } })
eq(Shatter.Database:GetSettings().skin, "forever", "an unknown saved skin falls back to WoW Forever")

-- 7. Settings lists the four looks and switches live.
main = setup(AsClear())
Shatter.SettingsUI:Toggle()
local buttons = Shatter.SettingsUI.skinButtons
check(buttons.forever and buttons.clear and buttons.smoked and buttons.flat,
    "Settings offers WoW Forever, Clear glass, Smoked glass and Flat")
check(same(Skin.Surface(buttons.clear).fill._color, { 1, 0.82, 0, 0.18 }), "...the current one marked")
buttons.flat._scripts.OnClick(buttons.flat)
eq(Shatter.Database:GetSettings().skin, "flat", "clicking Flat saves it")
check(not Skin.Surface(main.frame).panel:IsShown(), "...and the window turns flat at once")
check(same(buttons.flat._backdropColor, C.BG_ACTIVE), "...Flat now marked")
buttons.forever._scripts.OnClick(buttons.forever)
eq(Shatter.Database:GetSettings().skin, "forever", "clicking WoW Forever saves it")
check(Skin.Surface(main.frame).forever:IsShown(), "...and the window takes it at once")
check(same(buttons.forever._backdropColor, { 1, 0.82, 0, 0.18 }), "...WoW Forever now marked")

-- 8. The Mail launch panel is a glass window too, and a WoW Forever one.
setup(AsClear())
Shatter.MailLaunchPanel:Create()
local launch = Skin.Surface(Shatter.MailLaunchPanel.frame)
check(launch and launch.panel and launch.panel:IsShown(), "the launch panel has its own glass panel")
check(same(Skin.Surface(Shatter.MailLaunchPanel.startButton).fill._color, { 1, 1, 1, 0.08 }) or
    same(Skin.Surface(Shatter.MailLaunchPanel.startButton).fill._color, { 1, 0.82, 0, 0.15 }),
    "its buttons are glass fills")
Skin.Set("forever")
check(launch.forever:IsShown() and not launch.panel:IsShown(), "...its WoW Forever panel, live")

-- 9. Flat hovers that differ from an ordinary button's, as before glass.
main = setup({ savedDB = { settings = { skin = "flat" } } })
Shatter.MailMode.IsAvailable = function() return true end
main:UpdateTabs()
local tabMail = main.tabMail
tabMail._scripts.OnEnter(tabMail)
check(same(tabMail._backdropColor, { 0.10, 0.10, 0.10, 0.9 }), "Flat: an available Mail tab keeps its own darker hover")
tabMail._scripts.OnLeave(tabMail)
check(same(tabMail._backdropColor, { 0.12, 0.12, 0.12, 1 }), "...and its grey after")
main.activeView = "mail"
main:UpdateTabs()
check(same(tabMail._backdropColor, C.BG_ACTIVE) and same(tabMail._backdropBorderColor, C.ACCENT),
    "the Mail tab is marked active in the Mail view (it never was: UpdateTabs had no tabMail)")
main.activeView = "solo"
main:UpdateTabs()
main.tabRaid._scripts.OnEnter(main.tabRaid)
check(same(main.tabRaid._backdropColor, { 0.10, 0.10, 0.10, 0.9 }), "Flat: the Raid tab's hover")
main.tabRaid._scripts.OnLeave(main.tabRaid)
Shatter.SettingsUI:Toggle()
local flatButton = Shatter.SettingsUI.skinButtons.flat
flatButton._scripts.OnEnter(flatButton)
flatButton._scripts.OnClick(flatButton)
check(same(flatButton._backdropColor, C.BG_ACTIVE), "Flat: a just-chosen option stays BG_ACTIVE under the mouse")

-- 10. Masks only where body_mask_small fits (LibGlass §6): not on the 22 px
-- close button (small both ways) nor the 14 px cast-bar trough.
main = setup(AsClear())
check(Skin.Surface(main.settingsButton).masked and #Skin.Surface(main.settingsButton).fill._masks == 1,
    "an ordinary button is rounded")
check(not Skin.Surface(main.closeButton).masked and Skin.Surface(main.closeButton).fill._masks == nil,
    "the close button's fill stays square")
check(not Skin.Surface(main.castBar).masked and Skin.Surface(main.castBar).fill._masks == nil,
    "the cast-bar trough stays square")
eq(Skin.Maskable(20, 24), false, "Maskable: 20x24 is small both ways")
eq(Skin.Maskable(200, 12), false, "Maskable: under 16 px tall")
eq(Skin.Maskable(66, 22), true, "Maskable: a short, wide button")
eq(Skin.Maskable(0, 0), false, "Maskable: a size not set yet")

-- 11. Painting reads the setting once per Refresh, not on every hover.
local reads = 0
local getSettings = Shatter.Database.GetSettings
Shatter.Database.GetSettings = function(...) reads = reads + 1 return getSettings(...) end
for _ = 1, 5 do
    main.settingsButton._scripts.OnEnter(main.settingsButton)
    main.settingsButton._scripts.OnLeave(main.settingsButton)
end
Shatter.Database.GetSettings = getSettings
eq(reads, 0, "hovering a button doesn't re-read the settings")
Shatter.Database:GetSettings().skin = "flat"
Skin.Refresh()
check(not Skin.Surface(main.frame).panel:IsShown(), "Refresh re-reads the setting")
Skin.Set("clear")

-- 12. A frame registered twice keeps one record and one fill.
local again = CreateFrame("Button", nil, main.frame, "BackdropTemplate")
again:SetSize(80, 22)
Skin.Fill(again, "button", "normal")
local firstFill = Skin.Surface(again).fill
Skin.Fill(again, "button", "field")
check(Skin.Surface(again).fill == firstFill and #firstFill._masks == 1, "re-registering keeps the fill and its one mask")
Skin.Set("smoked")
check(same(firstFill._color, { 0, 0, 0, 0.35 }), "...and Refresh paints the new record")
Skin.Set("clear")

-- 13. Texture methods on frames don't exist on the client, nor frame
-- methods on textures. WowTestKit's implementations answer on any widget,
-- and test_methods' Kit.checkMethods fails on such a pair: the build's
-- widget methods (what it checks against) lack each one.
local known = Kit.data("widgetMethods")
check(not known["Frame:AddMaskTexture"] and known["Texture:AddMaskTexture"], "a frame has no AddMaskTexture")
check(not known["Frame:SetGradient"] and known["Texture:SetGradient"], "a frame has no SetGradient")
check(not known["Texture:CreateMaskTexture"] and known["Frame:CreateMaskTexture"], "a texture has no CreateMaskTexture")

-- 14. No LibGlass (installed from a git clone): a glass look renders WoW
-- Forever, which needs no library.
rawset(_G, "LibStub", nil)
main = setup({ withoutLibs = true, savedDB = { settings = { skin = "clear" } } })
eq(Shatter.Glass, nil, "no library, no glass instance")
eq(Shatter.Database:GetSettings().skin, "clear", "the setting is still Clear")
eq(Skin.IsGlass(), false, "...but Shatter renders no glass")
eq(Skin.Shown(), "forever", "...it renders WoW Forever")
check(Skin.Surface(main.frame).forever:IsShown(), "the window's WoW Forever panel is shown")
check(Skin.Surface(main.frame).panel == nil, "no glass panel was built")
Shatter.SettingsUI:Toggle()
check(same(Shatter.SettingsUI.skinButtons.forever._backdropColor, { 1, 0.82, 0, 0.18 })
    and same(Shatter.SettingsUI.skinButtons.clear._backdropColor, { 1, 1, 1, 0.08 }),
    "Settings marks WoW Forever, the look actually drawn")
SlashCmdList.SHATTER("skin flat")
check(same(main.frame._backdropColor, C.BG_MAIN), "Flat still works without the library")

done("test_skin")
