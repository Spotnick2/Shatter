local _, Shatter = ...

-- What Shatter's windows are made of (#14, #23): WoW Forever (the game's own
-- window, the default), Clear glass, Smoked glass, or Flat (the opaque look
-- Shatter always had).
--
-- WoW Forever is Blizzard's tooltip window: UI-Tooltip-Background under the
-- UI-Tooltip-Border edge, in the tooltip's own navy. It needs no LibGlass, so
-- it is also what Clear and Smoked show without it. Its window body is a
-- backdrop panel of its own, like the glass; panes, buttons and rows keep
-- their 1 px backdrop (the layout is Flat's), with the glass's translucent
-- fills and a slate edge.
--
-- The glass is Pearl (Glass.lua). A skin is a body over it: a tint, and
-- grain and wash as factors of the material's own (Pearl has no grain), the
-- way Glass UI's Suite.Body states them. The tints are Glass UI's Suite.BODY
-- numbers (also AltStable's and GlassMailbox's), so the Glass addons look
-- alike side by side. A skin changes the body and the panes, never the rim:
-- LibGlass GLASS-MATERIAL.md, a darkened rim reads as smoked plastic.
--
-- Following Glass UI (Suite.lua): the suite's body replaces WoW Forever,
-- Clear and Smoked, which stay saved for when Shatter doesn't follow. Flat is
-- still the player's: choosing it declines the suite's look.
--
-- The switch is live (GlassMailbox's way, not AltStable's reload). Every
-- surface is built once, for every look:
--   * a window's glass and its WoW Forever body are each on a child panel of
--     their own, shown or hidden (LibGlass has no teardown, so a surface is
--     never applied twice);
--   * a pane or a filled widget keeps its backdrop for Flat and gets a fill
--     texture for glass, masked to a rounded shape where it stands alone.
-- Widgets never pick colours themselves: they tell Skin their state
-- (Skin.Paint, Skin.Hover), Skin remembers it, and Skin.Refresh repaints every
-- registered surface in the current skin. Flat paints exactly the colours the
-- widgets used before glass existed.
--
-- Nothing here shows, hides, moves or resizes a protected frame. The panels,
-- fills and masks are Shatter's own unprotected children and regions, and a
-- backdrop colour is not protected, so a switch in combat is safe; the secure
-- Shatter Next button only has its colours repainted.

local Skin = {}
Shatter.Skin = Skin
Shatter.RegisterModule("Skin", Skin)

-- grain and wash are factors of the instance's STYLE.grain and STYLE.wash.
-- Smoked's are its old absolute numbers over the classic material's (0.35 of
-- 0.45, 0.14 of 0.18), so the classic fallback looks as it always did.
Skin.PRESETS = {
    clear = {
        tint = { 0.13, 0.16, 0.22, 0.24 }, grain = 1, wash = 1,
        pane = { 0.04, 0.05, 0.07, 0.62 },
    },
    smoked = {
        tint = { 0.05, 0.06, 0.08, 0.62 }, grain = 0.35 / 0.45, wash = 0.14 / 0.18,
        pane = { 0.03, 0.03, 0.04, 0.80 },
    },
}
-- Every value of the setting, in the order Settings lists them.
Skin.NAMES = { "forever", "clear", "smoked", "flat" }
-- "suite" is never saved: it is what is shown while Shatter follows Glass UI.
Skin.LABELS = { forever = "WoW Forever", clear = "Clear glass", smoked = "Smoked glass", flat = "Flat",
                suite = "Glass UI" }

local C = Shatter.C
local ACCENT = C.ACCENT

-- The accent's tints, kept so a suite accent (Skin.SetAccent) reaches them.
local accentTints = {}
local function Accent(a)
    local t = { ACCENT[1], ACCENT[2], ACCENT[3], a }
    accentTints[#accentTints + 1] = t
    return t
end
local function White(a) return { 1, 1, 1, a } end
local NONE = { 0, 0, 0, 0 }

-- WoW Forever: the tooltip's backdrop (GameTooltip's 16 px edge and 5 px
-- insets) in its default colours (TOOLTIP_DEFAULT_BACKGROUND_COLOR, a
-- client constant: 0.09, 0.09, 0.19), a pane darkened into it, and the slate
-- edge of everything drawn with Flat's 1 px backdrop.
local FOREVER_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
}
Skin.FOREVER = {
    window = { 0.09, 0.09, 0.19, 0.94 }, border = { 1, 1, 1, 1 },
    pane = { 0, 0, 0, 0.30 }, edge = { 0.32, 0.34, 0.42, 0.90 },
}

-- Filled widgets, per family and state: the Flat backdrop (bg, border, and
-- the bg while hovered, nil = no change) and the glass fill (fill, hover).
local FILLS = {
    button = {
        -- An ordinary button.
        normal = { bg = { 0.12, 0.12, 0.12, 1 }, border = C.BORDER, hover = { 0.18, 0.18, 0.18, 1 },
            fill = White(0.08), fillHover = White(0.14) },
        -- The selected tab or option.
        active = { bg = C.BG_ACTIVE, border = ACCENT, fill = Accent(0.18) },
        -- The chosen value of a Settings option (no accent border in Flat). It
        -- keeps its colour under the mouse: a hover grey would dim it on click.
        chosen = { bg = C.BG_ACTIVE, border = C.BORDER, fill = Accent(0.18) },
        -- An available mode tab that isn't the current view (Mail, Raid): its
        -- own darker hover, as before glass.
        tab = { bg = { 0.12, 0.12, 0.12, 1 }, border = C.BORDER, hover = { 0.10, 0.10, 0.10, 0.9 },
            fill = White(0.08), fillHover = White(0.14) },
        -- An unavailable tab: still hoverable for its tooltip.
        dim = { bg = { 0.08, 0.08, 0.08, 0.7 }, border = C.BORDER, hover = { 0.10, 0.10, 0.10, 0.9 },
            fill = White(0.03), fillHover = White(0.07) },
        -- Shatter Next, ready and not.
        go = { bg = { 0.20, 0.15, 0.03, 1 }, border = ACCENT, hover = { 0.24, 0.20, 0.08, 1 },
            fill = Accent(0.22), fillHover = Accent(0.30) },
        goOff = { bg = { 0.10, 0.10, 0.10, 1 }, border = ACCENT, fill = White(0.04) },
        -- The Mail launch panel's suggested action.
        emphasis = { bg = { 0.20, 0.17, 0.07, 1 }, border = C.BORDER, hover = { 0.24, 0.20, 0.08, 1 },
            fill = Accent(0.15), fillHover = Accent(0.22) },
        disabled = { bg = { 0.10, 0.10, 0.10, 1 }, border = C.BORDER, fill = White(0.04) },
        -- A dropdown-like value field.
        field = { bg = { 0.08, 0.08, 0.08, 1 }, border = C.BORDER, hover = { 0.12, 0.12, 0.12, 1 },
            fill = { 0, 0, 0, 0.35 }, fillHover = { 0, 0, 0, 0.22 } },
    },
    row = {
        odd = { bg = C.BG_ROW_ODD, border = C.BORDER, hover = C.BG_HOVER, fill = NONE, fillHover = White(0.07) },
        even = { bg = C.BG_ROW_EVEN, border = C.BORDER, hover = C.BG_HOVER, fill = White(0.035), fillHover = White(0.07) },
        selected = { bg = { 0.22, 0.18, 0.08, 0.98 }, border = { 0.95, 0.78, 0.08, 1 }, fill = Accent(0.15) },
    },
    -- The cast bar's trough.
    track = {
        normal = { bg = { 0.04, 0.04, 0.04, 0.95 }, border = C.BORDER, fill = { 0, 0, 0, 0.35 } },
    },
}

local surfaces = {}     -- registration order, for Refresh
local byFrame = {}      -- frame -> its record

-- What is drawn: a glass preset (look "glass"), or nil with look "forever"
-- or "flat". Read from the settings once and kept until the next Refresh or
-- Set (GetSettings re-normalizes the whole database, too much for every hover
-- and paint); whatever changes the setting or the profile calls one of them.
local preset, look, resolved = nil, "forever", false

local function Following()
    return Shatter.Suite ~= nil and Shatter.Suite.Offered()
end

-- The saved setting.
function Skin.Name()
    local settings = Shatter.Database and Shatter.Database:GetSettings()
    return settings and settings.skin or "forever"
end

-- What is drawn: the setting, "suite" for glass while following Glass UI, or
-- "forever" for a glass look without LibGlass.
function Skin.Shown()
    local name = Skin.Name()
    if name == "flat" then return "flat" end
    if Following() then return "suite" end
    if Skin.PRESETS[name] and not Shatter.Glass then return "forever" end
    return name
end

local function Resolve()
    if not resolved then
        local shown = Skin.Shown()
        preset = nil
        if shown == "suite" then
            preset = Shatter.Suite.Body()
        elseif Skin.PRESETS[shown] then
            preset = Skin.PRESETS[shown]
        end
        look = preset and "glass" or shown
        resolved = true
    end
    return preset, look
end

function Skin.IsGlass() return (Resolve()) ~= nil end

function Skin.IsValid(name) return name == "flat" or name == "forever" or Skin.PRESETS[name] ~= nil end

local function SetColor(fn, target, color)
    fn(target, color[1], color[2], color[3], color[4] or 1)
end

-- A rounded mask on `frame`, applied to `texture` (a mask only affects the
-- textures of the frame that owns it, and AddMaskTexture appends: once).
local function Rounded(frame, texture)
    local mask = Shatter.Glass.Mask(frame, "body_mask_small", 8, 1)
    texture:AddMaskTexture(mask)
end

-- Whether a w x h box takes body_mask_small (sliced at margin 8). LibGlass
-- GLASS-MATERIAL.md §6: under 16 px on an axis the corners are squeezed (and
-- a margin must never be shrunk to fit), and a sliced mask on a box small in
-- BOTH directions (measured broken at 16-22 px, fine at 32) doesn't render.
-- Those boxes stay square. A size not set yet (0) counts as small.
function Skin.Maskable(w, h)
    w, h = w or 0, h or 0
    return w >= 16 and h >= 16 and (w >= 32 or h >= 32)
end

-- Each frame has one record: a second registration replaces the first in
-- place and keeps what was already built (a window's panel, a fill and its
-- mask): LibGlass has no teardown, and AddMaskTexture appends.
local function Register(frame, record)
    record.frame = frame
    local old = byFrame[frame]
    if old then
        record.panel, record.g, record.fill, record.masked = old.panel, old.g, old.fill, old.masked
        record.forever = old.forever
        for i, r in ipairs(surfaces) do
            if r == old then surfaces[i] = record break end
        end
    else
        surfaces[#surfaces + 1] = record
    end
    byFrame[frame] = record
    return record
end

local function ApplyWindow(record, p, kind)
    local frame = record.frame
    if kind == "forever" then
        frame:SetBackdropColor(0, 0, 0, 0)
        frame:SetBackdropBorderColor(0, 0, 0, 0)
    elseif p then
        frame:SetBackdropColor(0, 0, 0, 0)
        frame:SetBackdropBorderColor(0, 0, 0, 0)
        -- The body over the material: STYLE stays the preset's own (nothing
        -- here writes it), so its grain and wash are the bases.
        local Glass, g = Shatter.Glass, record.g
        local style = Glass.STYLE
        Glass.SetSurfaceTint(g, p.tint[1], p.tint[2], p.tint[3], p.tint[4])
        g.grain:SetAlpha((style.grain or 0) * p.grain)
        local wash = (style.wash or 0) * p.wash
        if Glass.SetWash then
            Glass.SetWash(g, wash)
        else
            g.wash:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, wash))
        end
    else
        SetColor(frame.SetBackdropColor, frame, record.flat)
        SetColor(frame.SetBackdropBorderColor, frame, C.BORDER)
    end
    if record.panel then record.panel:SetShown(p ~= nil) end
    record.forever:SetShown(kind == "forever")
end

local function ApplyPane(record, p, kind)
    local frame = record.frame
    if kind == "forever" then
        SetColor(frame.SetBackdropColor, frame, Skin.FOREVER.pane)
        SetColor(frame.SetBackdropBorderColor, frame, Skin.FOREVER.edge)
    elseif p then
        frame:SetBackdropColor(0, 0, 0, 0)
        frame:SetBackdropBorderColor(0, 0, 0, 0)
        SetColor(record.fill.SetColorTexture, record.fill, p.pane)
    else
        SetColor(frame.SetBackdropColor, frame, record.flat)
        SetColor(frame.SetBackdropBorderColor, frame, C.BORDER)
    end
    if record.fill then record.fill:SetShown(p ~= nil) end
end

-- WoW Forever's 1 px edge for a filled widget: the accent where Flat has it,
-- a row's quality (or nothing), else slate.
local function ForeverEdge(record, state)
    if record.family == "row" then
        if record.state == "selected" then return state.border end
        return record.border or NONE
    end
    if state.border == ACCENT then return ACCENT end
    return Skin.FOREVER.edge
end

local function ApplyFill(record, p, kind)
    local frame = record.frame
    local state = FILLS[record.family][record.state] or FILLS[record.family][record.default]
    if kind == "forever" then
        SetColor(frame.SetBackdropColor, frame, record.hovered and state.fillHover or state.fill)
        SetColor(frame.SetBackdropBorderColor, frame, ForeverEdge(record, state))
        if record.fill then record.fill:SetShown(false) end
    elseif p then
        frame:SetBackdropColor(0, 0, 0, 0)
        frame:SetBackdropBorderColor(0, 0, 0, 0)
        local color = record.hovered and state.fillHover or state.fill
        SetColor(record.fill.SetColorTexture, record.fill, color)
        record.fill:SetShown(color[4] > 0)
    else
        local bg = record.hovered and state.hover or state.bg
        SetColor(frame.SetBackdropColor, frame, bg)
        -- A row's border carries its item's quality, except when selected.
        local border = record.state ~= "selected" and record.border or state.border
        SetColor(frame.SetBackdropBorderColor, frame, border)
        if record.fill then record.fill:SetShown(false) end
    end
end

local function ApplyBand(record, p, kind)
    record.frame:SetShown(kind == "flat")
end

local APPLY = { window = ApplyWindow, pane = ApplyPane, fill = ApplyFill, band = ApplyBand }

local function Apply(record)
    APPLY[record.kind](record, Resolve())
end

-- A plain child panel just under the window's content, built once.
local function Panel(frame)
    local panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    panel:SetAllPoints(frame)
    panel:SetFrameLevel(frame:GetFrameLevel())
    return panel
end

-- The window body: Flat is its backdrop in `flat`; WoW Forever and glass are
-- each a panel just under the window's content, built once.
function Skin.Window(frame, flat)
    Shatter.ApplyBackdrop(frame, unpack(flat))
    local record = Register(frame, { kind = "window", flat = flat })
    if not record.forever then
        record.forever = Panel(frame)
        record.forever:SetBackdrop(FOREVER_BACKDROP)
        SetColor(record.forever.SetBackdropColor, record.forever, Skin.FOREVER.window)
        SetColor(record.forever.SetBackdropBorderColor, record.forever, Skin.FOREVER.border)
    end
    if Shatter.Glass and not record.panel then
        record.panel = Panel(frame)
        record.g = Shatter.Glass.Apply(record.panel, "large")
    end
    Apply(record)
end

-- A reading pane set into the glass: translucent, rounded, darker with Smoked.
function Skin.Pane(frame, flat)
    Shatter.ApplyBackdrop(frame, unpack(flat))
    local record = Register(frame, { kind = "pane", flat = flat })
    if Shatter.Glass and not record.fill then
        record.fill = frame:CreateTexture(nil, "BACKGROUND")
        record.fill:SetAllPoints(frame)
        Rounded(frame, record.fill)
    end
    Apply(record)
end

-- A filled widget of a FILLS family ("button", "row", "track") in `state`.
-- Buttons and the track are inset by the border and rounded when their size
-- (set before this call) takes the mask; rows sit inside a pane and stay
-- square.
function Skin.Fill(frame, family, state)
    Shatter.ApplyBackdrop(frame, unpack(FILLS[family][state].bg))
    local record = Register(frame, { kind = "fill", family = family, state = state, default = state })
    if Shatter.Glass and not record.fill then
        record.fill = frame:CreateTexture(nil, "BACKGROUND")
        if family == "row" then
            record.fill:SetAllPoints(frame)
        else
            record.fill:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
            record.fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
            local w, h = frame:GetSize()
            if Skin.Maskable((w or 0) - 2, (h or 0) - 2) then
                Rounded(frame, record.fill)
                record.masked = true
            end
        end
    end
    Apply(record)
end

-- A title bar's band: Flat only (the glass's own wash lights the top, and
-- WoW Forever's edge frames it).
function Skin.Band(texture)
    Apply(Register(texture, { kind = "band" }))
end

-- A filled widget's state, and (Flat only) a row's border colour; nil keeps
-- the family's border.
function Skin.Paint(frame, state, border)
    local record = byFrame[frame]
    if not record then return end
    record.state = state
    record.border = border
    Apply(record)
end

function Skin.Hover(frame, hovered)
    local record = byFrame[frame]
    if not record then return end
    record.hovered = hovered and true or false
    Apply(record)
end

-- What Skin built for a frame: { panel, g, forever } for a window, { fill } for a pane
-- or a filled widget, plus its state. For tests and debugging; read only.
function Skin.Surface(frame) return byFrame[frame] end

-- Repaint every surface in the current skin (re-reading the setting: a
-- profile switch changes it), and tell Glass UI when Flat came or went.
function Skin.Refresh()
    resolved = false
    for _, record in ipairs(surfaces) do Apply(record) end
    if Shatter.Suite then Shatter.Suite.Report() end
end

-- The one setter, for Settings and /shatter skin. False for an unknown name.
-- While following Glass UI, the looks other than Flat are its to set: they're
-- refused (false, "suite") unless Flat is on, when any one is the way back to
-- the suite's glass.
function Skin.Set(name)
    if not Skin.IsValid(name) or not Shatter.Database then return false end
    local settings = Shatter.Database:GetSettings()
    if name ~= "flat" and settings.skin ~= "flat" and Following() then return false, "suite" end
    settings.skin = name
    Skin.Refresh()
    return true
end

-- The suite's accent ({ r, g, b }), set once before any frame is built
-- (Suite.lua): C.ACCENT and the accent's fill tints, in place.
function Skin.SetAccent(rgb)
    for i = 1, 3 do ACCENT[i] = rgb[i] end
    for _, t in ipairs(accentTints) do
        for i = 1, 3 do t[i] = rgb[i] end
    end
end
