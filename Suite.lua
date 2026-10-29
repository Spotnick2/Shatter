local _, Shatter = ...

-- Following Glass UI (..\GlassUI, its docs/SUITE.md and SUITE-LOOK.md).
--
-- Glass UI owns the Glass suite's look and which addons follow it; Shatter is
-- one of its dynamic members (GlassUI #164). With Glass UI loaded and its
-- "Use Glass UI appearance" on for Shatter, the windows' glass takes the
-- suite's body (Suite.Body: its tint, wash factor) and the accent its accent
-- (Suite.Accent). The material is Pearl either way (Glass.lua).
--
-- Asked ONCE per session, at the first activation, before any window is
-- built: an inactive character (no Disenchant) never reads ShatterDB, so it
-- doesn't ask either. Not live (the owner, 2026-10-29: a /reload is fine): a
-- suite change waits for a reload, and the report says so (`live = false`),
-- so Glass UI's page compares the look reported here with its current one.
--
-- While following, Clear and Smoked are suspended, not lost: they stay saved
-- for a session that doesn't follow. Flat stays the player's, live as ever:
-- it is reported as declined ("its own look by its choice"), and Clear or
-- Smoked is the way back. The accent is set once, before the frames are
-- built, so a Flat chosen before the reload keeps Shatter's gold until the
-- next one. The body's backing is never painted (the panes keep their own
-- colours), so the report claims it as Shatter's own.

local Suite = {}
Shatter.Suite = Suite
Shatter.RegisterModule("Suite", Suite)

local ADDON = "Shatter"
-- The suite's tints, as Shatter's skins (for the panes): class is Clear glass
-- in the class colour.
local SKINS = { clear = "clear", smoked = "smoked", class = "clear" }

local api                -- GlassUI.Suite, when it speaks API 1
local started = false
local answered = false   -- Theme told us a preset: Glass UI's switch is on for Shatter
local offered = false    -- ...and Pearl was built, so the suite's body is ours unless Flat
local reason             -- why the preset was asked for and not built
local look               -- { tint, accent }: what this session built from the suite
local body               -- the suite's body, in Skin.PRESETS' shape

-- Glass UI's suite API when it speaks version 1; anything else counts as absent
-- (a released Glass UI without Suite included).
local function SuiteAPI()
    local G = rawget(_G, "GlassUI")
    if type(G) ~= "table" then return nil end
    local S = rawget(G, "Suite")
    if type(S) ~= "table" or rawget(S, "API") ~= 1 then return nil end
    if type(rawget(S, "Theme")) ~= "function" or type(rawget(S, "Report")) ~= "function" then
        return nil
    end
    return S
end

-- One of the suite's optional functions, feature-detected on its own.
local function Call(name, ...)
    local fn = api and rawget(api, name)
    if type(fn) ~= "function" then return nil end
    local ok, r = pcall(fn, ...)
    if ok then return r end
end

local function IsColor(c, n)
    if type(c) ~= "table" then return false end
    for i = 1, n do
        if type(c[i]) ~= "number" or c[i] < 0 or c[i] > 1 then return false end
    end
    return true
end

local function ClassColor()
    local ok, _, class = pcall(UnitClass, "player")
    if not ok or type(class) ~= "string" or not C_ClassColor then return nil end
    local got, color = pcall(C_ClassColor.GetClassColor, class)
    if got and type(color) == "table" and type(color.r) == "number" then
        return color.r, color.g, color.b
    end
end

-- The body for a suite tint: Glass UI's numbers (Suite.Body, the one owner of
-- them), else our own skin's. A class body is the class colour times its
-- shade, at Clear's alpha (the surface's built one).
local function BuildBody(tint)
    local own = Shatter.Skin.PRESETS[SKINS[tint]]
    local b = Call("Body", tint)
    local color
    if type(b) == "table" and type(b.wash) == "number" then
        if IsColor(b.tint, 4) then
            color = { b.tint[1], b.tint[2], b.tint[3], b.tint[4] }
        elseif b.tint == nil and type(b.classShade) == "number" then
            local r, g, bl = ClassColor()
            if r then
                local s = b.classShade
                color = { r * s, g * s, bl * s, Shatter.Skin.PRESETS.clear.tint[4] }
            end
        end
    end
    if not color then
        return { tint = own.tint, grain = own.grain, wash = own.wash, pane = own.pane }
    end
    return { tint = color, grain = 1, wash = b.wash, pane = own.pane }
end

-- The first activation: ask Glass UI, and when it says Pearl, take the suite's
-- body and (unless Flat is on) its accent. Then paint and report.
function Suite.Start()
    if started then return end
    started = true
    api = SuiteAPI()
    if not api then return end
    local ok, answer = pcall(api.Theme, ADDON)
    if ok and type(answer) == "table" and type(answer.preset) == "string" then
        answered = true
        if not Shatter.Glass or (Shatter.GlassMinor or 0) < Shatter.PEARL_MINOR then
            reason = "library-too-old"
        elseif answer.preset ~= "pearl" or Shatter.GlassPreset ~= "pearl" then
            reason = "build-failed"
        else
            offered = true
            local current = Call("Look")
            local tint = type(current) == "table" and SKINS[current.tint] and current.tint or "clear"
            local accent = type(current) == "table" and type(current.accent) == "string" and current.accent or "gold"
            body = BuildBody(tint)
            look = { tint = tint, accent = "gold" }
            if Shatter.Skin.Name() ~= "flat" then
                local rgb = Call("Accent", accent)
                if IsColor(rgb, 3) then
                    Shatter.Skin.SetAccent(rgb)
                    look.accent = accent
                end
            end
        end
    end
    Shatter.Skin.Refresh()
end

-- Glass UI offered its look and this session built it: Clear and Smoked are
-- suspended. Flat may still be on (Skin.Shown says which).
function Suite.Offered() return offered end

-- The suite's body, in Skin.PRESETS' shape, while offered.
function Suite.Body() return offered and body or nil end

-- What this session built from the suite: { tint, accent }, a copy, or nil.
function Suite.Look()
    if not look then return nil end
    return { tint = look.tint, accent = look.accent }
end

-- Glass UI's own page. True when it opened.
function Suite.Open() return Call("Open") == true end

-- Shatter's settings, for Glass UI's page.
function Suite.OpenOptions()
    local main = Shatter.MainFrame
    if not Shatter.isActive or not main then return end
    main:Show()
    local settings = Shatter.SettingsUI
    if settings and settings.frame and not settings.frame:IsShown() then settings:Toggle() end
end

-- What Shatter shows, for Glass UI's page: on the first activation, then
-- whenever Flat comes or goes (Skin.Refresh). Plain values only.
function Suite.Report()
    if not api or not started then return end
    local state = { api = 1, live = false, minor = Shatter.GlassMinor, options = Suite.OpenOptions }
    if answered then
        if reason then
            state.reason = reason
        elseif Shatter.Skin.Name() == "flat" then
            state.declined = "Flat"
        else
            state.built = "pearl"
            state.look = { tint = look.tint, accent = look.accent }
            state.own = { backing = true }
        end
    end
    pcall(api.Report, ADDON, state)
end
