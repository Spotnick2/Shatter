local _, Shatter = ...

Shatter.C = {
    BG_MAIN = { 0.06, 0.06, 0.06, 0.96 },
    BG_PANEL = { 0.08, 0.08, 0.08, 0.96 },
    BG_HEADER = { 0.11, 0.11, 0.11, 1.00 },
    BG_ROW_ODD = { 0.06, 0.06, 0.06, 1.00 },
    BG_ROW_EVEN = { 0.09, 0.09, 0.09, 1.00 },
    BG_HOVER = { 0.16, 0.16, 0.16, 0.90 },
    BG_ACTIVE = { 0.20, 0.20, 0.20, 1.00 },
    BORDER = { 0, 0, 0, 1 },
    SEP = { 0.22, 0.22, 0.22, 1 },
    TEXT_DIM = { 0.50, 0.50, 0.50 },
    TEXT_NORM = { 0.82, 0.82, 0.82 },
    TEXT_BRIGHT = { 1.00, 1.00, 1.00 },
    ACCENT = { 1.00, 0.82, 0.00 },
    ACCENT2 = { 0.00, 0.80, 1.00 },
    BAD = { 1.00, 0.25, 0.25 },
    GOOD = { 0.35, 1.00, 0.45 },
}

function Shatter.ApplyBackdrop(frame, r, g, b, a)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        tile = true,
        tileSize = 8,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(r or 0, g or 0, b or 0, a or 1)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
end

function Shatter.ApplyBGOnly(frame, r, g, b, a)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", tile = true, tileSize = 8 })
    frame:SetBackdropColor(r or 0, g or 0, b or 0, a or 1)
end

function Shatter.SetTextColor(fontString, color)
    if fontString and color then
        fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
end

function Shatter.GetQualityColor(quality)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color then
        return color.r, color.g, color.b
    end
    return 0.82, 0.82, 0.82
end

function Shatter.ColorText(text, color)
    if not color then return tostring(text or "") end
    return string.format("|cff%02x%02x%02x%s|r", (color[1] or 1) * 255, (color[2] or 1) * 255, (color[3] or 1) * 255, tostring(text or ""))
end
