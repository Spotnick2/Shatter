------------------------------------------------------------
-- test_suite.lua - following Glass UI (Suite.lua; Glass UI's docs/SUITE.md):
--   * asked once, at the first activation, before any window is built;
--   * following: the suite's body and accent, Clear/Smoked suspended,
--     reported as built Pearl, not live;
--   * Flat declines, live both ways; not following keeps Shatter's skins;
--   * a missing library is a failed build; an inactive character never asks.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for i = 1, 4 do
        if math.abs((a[i] or 1) - (b[i] or 1)) > 1e-9 then return false end
    end
    return true
end

-- Glass UI's Suite, API 1, with its own numbers (GlassUI Suite.BODY / ACCENTS).
local BODY = {
    clear  = { tint = { 0.13, 0.16, 0.22, 0.24 }, wash = 1, backing = { 0.04, 0.05, 0.07, 0.35 } },
    smoked = { tint = { 0.05, 0.06, 0.08, 0.62 }, wash = 0.14 / 0.18, backing = { 0.04, 0.05, 0.07, 0.92 } },
    class  = { classShade = 0.6, wash = 1, backing = { 0.04, 0.05, 0.07, 0.35 } },
}
local ACCENTS = { gold = { 1, 0.82, 0 }, ice = { 0.65, 0.835, 0.905 } }

local function fakeGlassUI(opts)
    opts = opts or {}
    local S = { API = opts.api or 1, asked = 0, reports = {} }
    function S.Theme(addon)
        S.asked, S.askedFor = S.asked + 1, addon
        if opts.following == false then return nil, "not-following" end
        return { name = "pearl", preset = "pearl" }
    end
    function S.Report(addon, state) S.reports[#S.reports + 1] = { addon = addon, state = state } end
    function S.Look() return { tint = opts.tint or "clear", accent = opts.accent or "gold" } end
    function S.Body(tint)
        local b = BODY[tint]
        return b and { tint = b.tint and { unpack(b.tint) }, classShade = b.classShade, wash = b.wash,
                       backing = { unpack(b.backing) } }
    end
    function S.Accent(name) local c = ACCENTS[name] return c and { unpack(c) } end
    function S.Open() S.opened = true return true end
    rawset(_G, "GlassUI", { Suite = S })
    return S
end

local function setup(opts)
    opts = opts or {}
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    if opts.enchanter ~= false then WoW.enchanter() end
    if opts.class then WoW.player.class = opts.class end
    if opts.noLib then rawset(_G, "LibStub", nil) end
    -- A Glass UI from an earlier setup must not linger.
    if opts.suite == false then rawset(_G, "GlassUI", nil) end
    local S = opts.suite ~= false and fakeGlassUI(opts) or nil
    WoW.loadAddon({ savedDB = opts.savedDB, withoutLibs = opts.noLib })
    WoW.flushTimers()
    if Shatter.isActive then Shatter.MainFrame:Show() end
    return S, Shatter.MainFrame
end

local function last(S) return S.reports[#S.reports] and S.reports[#S.reports].state end

-- 1. Following, smoked and ice: the suite's body and accent.
local S, main = setup({ tint = "smoked", accent = "ice" })
local Skin, C = Shatter.Skin, Shatter.C
eq(S.asked, 1, "Theme asked once")
eq(S.askedFor, "Shatter", "...for Shatter")
local state = last(S)
eq(S.reports[#S.reports].addon, "Shatter", "the report is Shatter's")
eq(state.api, 1, "report: api 1")
eq(state.built, "pearl", "report: built Pearl")
eq(state.live, false, "report: not live (a suite change waits for a /reload)")
eq(state.minor, Shatter.GlassMinor, "report: the library's MINOR")
check(state.look and state.look.tint == "smoked" and state.look.accent == "ice", "report: the look built, smoked and ice")
check(state.own and state.own.backing == true, "report: the backing is Shatter's own (never painted)")
eq(state.declined, nil, "report: nothing declined")
eq(type(state.options), "function", "report: an options function")
eq(Skin.Shown(), "suite", "Shatter shows Glass UI's look")
eq(Shatter.Database:GetSettings().skin, "forever", "...and the saved skin (the default) is untouched")
local window = Skin.Surface(main.frame)
check(window.panel:IsShown() and same(window.g.tint._color, BODY.smoked.tint), "the body is the suite's smoked tint")
check(math.abs(window.g.wash._gradient[3].a - Shatter.Glass.STYLE.wash * BODY.smoked.wash) < 1e-9,
    "...its wash a factor of Pearl's")
check(same(Skin.Surface(main.queuePanel).fill._color, Skin.PRESETS.smoked.pane), "panes take Smoked's")
check(same(C.ACCENT, ACCENTS.ice), "the accent is the suite's ice")
check(same(Skin.Surface(main.tabSolo).fill._color, { ACCENTS.ice[1], ACCENTS.ice[2], ACCENTS.ice[3], 0.18 }),
    "the active tab's accent fill is ice")

-- WoW Forever, Clear and Smoked are Glass UI's to set.
SlashCmdList.SHATTER("skin smoked")
eq(Shatter.Database:GetSettings().skin, "forever", "/shatter skin smoked is refused while following")
check(WoW.chatText():find("follows Glass UI's look", 1, true), "...and says where to set it")
eq(select(2, Skin.Set("forever")), "suite", "...and so is WoW Forever")
check(window.forever and not window.forever:IsShown(), "...whose window body stays hidden")

-- Settings: Glass UI and Flat.
Shatter.SettingsUI:Toggle()
local buttons = Shatter.SettingsUI.skinButtons
check(buttons.suite and buttons.flat and not buttons.clear and not buttons.smoked and not buttons.forever,
    "Settings offers Glass UI and Flat")
check(same(Skin.Surface(buttons.suite).fill._color, { ACCENTS.ice[1], ACCENTS.ice[2], ACCENTS.ice[3], 0.18 }),
    "...Glass UI marked")
buttons.suite._scripts.OnClick(buttons.suite)
eq(S.opened, true, "clicking the chosen Glass UI opens Glass UI's page")

-- Flat declines, live; Clear brings the suite's glass back.
local reports = #S.reports
buttons.flat._scripts.OnClick(buttons.flat)
eq(Shatter.Database:GetSettings().skin, "flat", "Flat is still the player's")
check(not window.panel:IsShown(), "...the window turns flat at once")
check(#S.reports > reports and last(S).declined == "Flat" and last(S).built == nil, "...reported as declined")
buttons.suite._scripts.OnClick(buttons.suite)
eq(Skin.Shown(), "suite", "Glass UI from Flat: back to the suite's look")
check(window.panel:IsShown() and same(window.g.tint._color, BODY.smoked.tint), "...its body again")
eq(last(S).built, "pearl", "...reported as built")
SlashCmdList.SHATTER("skin flat")
SlashCmdList.SHATTER("skin smoked")
eq(Skin.Shown(), "suite", "/shatter skin smoked from Flat goes back to the suite too")
eq(Shatter.Database:GetSettings().skin, "smoked", "...saving Smoked for a session that doesn't follow")

-- The options function opens Shatter's settings.
Shatter.SettingsUI:Toggle()
check(not Shatter.SettingsUI.frame:IsShown(), "settings closed")
last(S).options()
check(Shatter.SettingsUI.frame:IsShown(), "Glass UI's page opens Shatter's settings")

-- 2. A class tint: the class colour times its shade, at Clear's alpha.
S, main = setup({ tint = "class", class = "MAGE" })
window = Shatter.Skin.Surface(main.frame)
check(same(window.g.tint._color, { 0.25 * 0.6, 0.78 * 0.6, 0.92 * 0.6, 0.24 }), "class: the mage colour, shaded")
eq(last(S).look.tint, "class", "...reported as class")

-- 3. Not following: Shatter's own skins, gold, still reported.
S, main = setup({ following = false, accent = "ice" })
Skin, C = Shatter.Skin, Shatter.C
eq(Skin.Shown(), "forever", "not following: Shatter's own look, WoW Forever")
check(same(C.ACCENT, ACCENTS.gold), "...in Shatter's gold")
state = last(S)
check(state and state.built == nil and state.declined == nil and state.reason == nil, "...reported, nothing built from the suite")
SlashCmdList.SHATTER("skin smoked")
eq(Shatter.Database:GetSettings().skin, "smoked", "...and /shatter skin smoked works")

-- 4. Flat at login: declined, and the accent stays gold until a reload.
S, main = setup({ savedDB = { settings = { skin = "flat" } }, accent = "ice" })
Skin, C = Shatter.Skin, Shatter.C
eq(last(S).declined, "Flat", "Flat at login: declined")
check(same(C.ACCENT, ACCENTS.gold), "...the accent stays gold")
SlashCmdList.SHATTER("skin clear")
eq(Skin.Shown(), "suite", "choosing glass follows the suite")
check(last(S).built == "pearl" and last(S).look.accent == "gold",
    "...reported with the gold it built, so Glass UI asks for a /reload")

-- 5. No library: a failed build, WoW Forever.
S, main = setup({ noLib = true })
eq(Shatter.Glass, nil, "no LibGlass")
eq(last(S).reason, "library-too-old", "a missing library is reported as library-too-old")
eq(last(S).built, nil, "...nothing built")
eq(Shatter.Skin.Shown(), "forever", "...and Shatter draws WoW Forever")
eq(Shatter.Suite.Offered(), false, "...without following")

-- 6. An inactive character (no Disenchant) never asks, and keeps ShatterDB nil.
S = setup({ enchanter = false })
eq(Shatter.isActive, false, "a character without Disenchant stays inactive")
eq(S.asked, 0, "...never asks Glass UI")
eq(#S.reports, 0, "...never reports")
eq(rawget(_G, "ShatterDB"), nil, "...and never creates ShatterDB")

-- 7. A Glass UI speaking another API counts as absent.
S = setup({ api = 2 })
eq(S.asked, 0, "API 2 is not asked")
eq(Shatter.Skin.Shown(), "forever", "...Shatter keeps its own look")

-- 8. No Glass UI at all.
setup({ suite = false })
eq(Shatter.Suite.Offered(), false, "no Glass UI: not following")
eq(rawget(_G, "GlassUI"), nil, "no GlassUI global")
eq(Shatter.Skin.Shown(), "forever", "...WoW Forever, the default")
eq(Shatter.Database:GetSettings().skin, "forever", "...saved as the default")

done("test_suite")
