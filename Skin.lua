local _, Shatter = ...

-- What Shatter's windows are made of (#14): Clear glass, Smoked glass, or
-- Flat (the opaque look Shatter always had).
--
-- The glass presets are AltStable's and GlassMailbox's numbers, so the Glass
-- addons look alike side by side. They change the body (tint, grain, wash)
-- and the panes, never the rim: LibGlass GLASS-MATERIAL.md, a darkened rim
-- reads as smoked plastic.
--
-- The switch is live (GlassMailbox's way, not AltStable's reload). Every
-- surface is built once, for both looks:
--   * a window's glass is on its own child panel, shown or hidden (LibGlass
--     has no teardown, so a surface is never applied twice);
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

Skin.PRESETS = {
    clear = {
        tint = { 0.13, 0.16, 0.22, 0.24 }, grain = 0.45, wash = 0.18,
        pane = { 0.04, 0.05, 0.07, 0.62 },
    },
    smoked = {
        tint = { 0.05, 0.06, 0.08, 0.62 }, grain = 0.35, wash = 0.14,
        pane = { 0.03, 0.03, 0.04, 0.80 },
    },
}
-- Every value of the setting, in the order Settings lists them.
Skin.NAMES = { "clear", "smoked", "flat" }
Skin.LABELS = { clear = "Clear glass", smoked = "Smoked glass", flat = "Flat" }

local C = Shatter.C
local ACCENT = C.ACCENT

local function Accent(a) return { ACCENT[1], ACCENT[2], ACCENT[3], a } end
local function White(a) return { 1, 1, 1, a } end
local NONE = { 0, 0, 0, 0 }

-- Filled widgets, per family and state: the Flat backdrop (bg, border, and
-- the bg while hovered, nil = no change) and the glass fill (fill, hover).
local FILLS = {
    button = {
        -- An ordinary button.
        normal = { bg = { 0.12, 0.12, 0.12, 1 }, border = C.BORDER, hover = { 0.18, 0.18, 0.18, 1 },
            fill = White(0.08), fillHover = White(0.14) },
        -- The selected tab or option.
        active = { bg = C.BG_ACTIVE, border = ACCENT, fill = Accent(0.18) },
        -- The chosen value of a Settings option (no accent border in Flat).
        chosen = { bg = C.BG_ACTIVE, border = C.BORDER, hover = { 0.18, 0.18, 0.18, 1 }, fill = Accent(0.18) },
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

-- The current preset, or nil when Shatter renders flat: the Flat skin, or
-- no LibGlass to draw glass with.
local function Preset()
    local settings = Shatter.Database and Shatter.Database:GetSettings()
    local p = settings and Skin.PRESETS[settings.skin]
    return Shatter.Glass and p or nil
end

function Skin.Name()
    local settings = Shatter.Database and Shatter.Database:GetSettings()
    return settings and settings.skin or "clear"
end

function Skin.IsGlass() return Preset() ~= nil end

function Skin.IsValid(name) return name == "flat" or Skin.PRESETS[name] ~= nil end

local function SetColor(fn, target, color)
    fn(target, color[1], color[2], color[3], color[4] or 1)
end

-- The preset's body into this instance's STYLE before an Apply: COPIED, never
-- aliased (AltStable #184: the library fills STYLE in place).
local function PushStyle(p)
    local style = Shatter.Glass.STYLE
    style.tint = { p.tint[1], p.tint[2], p.tint[3], p.tint[4] }
    style.grain, style.wash = p.grain, p.wash
end

-- A rounded mask on `frame`, applied to `texture` (a mask only affects the
-- textures of the frame that owns it, and AddMaskTexture appends: once).
local function Rounded(frame, texture)
    local mask = Shatter.Glass.Mask(frame, "body_mask_small", 8, 1)
    texture:AddMaskTexture(mask)
end

local function Register(frame, record)
    record.frame = frame
    if not byFrame[frame] then surfaces[#surfaces + 1] = record end
    byFrame[frame] = record
    return record
end

local function ApplyWindow(record, p)
    local frame = record.frame
    if p then
        frame:SetBackdropColor(0, 0, 0, 0)
        frame:SetBackdropBorderColor(0, 0, 0, 0)
        local g = record.g
        Shatter.Glass.SetSurfaceTint(g, p.tint[1], p.tint[2], p.tint[3], p.tint[4])
        g.grain:SetAlpha(p.grain)
        g.wash:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, p.wash))
    else
        SetColor(frame.SetBackdropColor, frame, record.flat)
        SetColor(frame.SetBackdropBorderColor, frame, C.BORDER)
    end
    if record.panel then record.panel:SetShown(p ~= nil) end
end

local function ApplyPane(record, p)
    local frame = record.frame
    if p then
        frame:SetBackdropColor(0, 0, 0, 0)
        frame:SetBackdropBorderColor(0, 0, 0, 0)
        SetColor(record.fill.SetColorTexture, record.fill, p.pane)
    else
        SetColor(frame.SetBackdropColor, frame, record.flat)
        SetColor(frame.SetBackdropBorderColor, frame, C.BORDER)
    end
    if record.fill then record.fill:SetShown(p ~= nil) end
end

local function ApplyFill(record, p)
    local frame = record.frame
    local state = FILLS[record.family][record.state] or FILLS[record.family][record.default]
    if p then
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

local function ApplyBand(record, p)
    record.frame:SetShown(p == nil)
end

local APPLY = { window = ApplyWindow, pane = ApplyPane, fill = ApplyFill, band = ApplyBand }

local function Apply(record)
    APPLY[record.kind](record, Preset())
end

-- The window body: Flat is its backdrop in `flat`; glass is a LibGlass
-- panel just under the window's content, built once.
function Skin.Window(frame, flat)
    Shatter.ApplyBackdrop(frame, unpack(flat))
    local record = Register(frame, { kind = "window", flat = flat })
    if Shatter.Glass then
        local panel = CreateFrame("Frame", nil, frame)
        panel:SetAllPoints(frame)
        panel:SetFrameLevel(frame:GetFrameLevel())
        PushStyle(Preset() or Skin.PRESETS.clear)
        record.panel = panel
        record.g = Shatter.Glass.Apply(panel, "large")
    end
    Apply(record)
end

-- A reading pane set into the glass: translucent, rounded, darker with Smoked.
function Skin.Pane(frame, flat)
    Shatter.ApplyBackdrop(frame, unpack(flat))
    local record = Register(frame, { kind = "pane", flat = flat })
    if Shatter.Glass then
        record.fill = frame:CreateTexture(nil, "BACKGROUND")
        record.fill:SetAllPoints(frame)
        Rounded(frame, record.fill)
    end
    Apply(record)
end

-- A filled widget of a FILLS family ("button", "row", "track") in `state`.
-- Buttons and the track are rounded; rows sit inside a pane and stay square.
function Skin.Fill(frame, family, state)
    Shatter.ApplyBackdrop(frame, unpack(FILLS[family][state].bg))
    local record = Register(frame, { kind = "fill", family = family, state = state, default = state })
    if Shatter.Glass then
        record.fill = frame:CreateTexture(nil, "BACKGROUND")
        if family == "row" then
            record.fill:SetAllPoints(frame)
        else
            record.fill:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
            record.fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
            Rounded(frame, record.fill)
        end
    end
    Apply(record)
end

-- A title bar's band: Flat only (the glass's own wash lights the top).
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

-- What Skin built for a frame: { panel, g } for a window, { fill } for a pane
-- or a filled widget, plus its state. For tests and debugging; read only.
function Skin.Surface(frame) return byFrame[frame] end

-- Repaint every surface in the current skin.
function Skin.Refresh()
    for _, record in ipairs(surfaces) do Apply(record) end
end

-- The one setter, for Settings and /shatter skin. False for an unknown name.
function Skin.Set(name)
    if not Skin.IsValid(name) or not Shatter.Database then return false end
    Shatter.Database:GetSettings().skin = name
    Skin.Refresh()
    return true
end
