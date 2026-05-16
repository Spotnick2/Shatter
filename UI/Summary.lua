local _, Shatter = ...

local SummaryUI = {
    frame = nil,
    lines = {},
}

Shatter.SummaryUI = SummaryUI
Shatter.RegisterModule("SummaryUI", SummaryUI)

function SummaryUI:Create(parent)
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -76)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 44)
    frame:SetFrameLevel(parent:GetFrameLevel() + 20)
    Shatter.ApplyBackdrop(frame, unpack(Shatter.C.BG_PANEL))
    frame:Hide()
    self.frame = frame

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
    title:SetText("Solo Summary")
    Shatter.SetTextColor(title, Shatter.C.ACCENT)

    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    note:SetText("Phase 1 session totals for the current login session.")

    local previous = note
    for i = 1, 12 do
        local line = frame:CreateFontString(nil, "OVERLAY", i <= 5 and "GameFontHighlightSmall" or "GameFontNormalSmall")
        line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, i == 1 and -16 or -7)
        line:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
        line:SetJustifyH("LEFT")
        self.lines[i] = line
        previous = line
    end

    return frame
end

function SummaryUI:Refresh()
    if not self.frame then return end
    local lines = Shatter.Session and Shatter.Session:GetSummaryLines() or { "No summary available." }
    for i, fontString in ipairs(self.lines) do
        fontString:SetText(lines[i] or "")
    end
end

function SummaryUI:Toggle()
    if not self.frame then return end
    if self.frame:IsShown() then
        self.frame:Hide()
        if Shatter.MainFrame then Shatter.MainFrame:SetActiveView("solo") end
    else
        self:Refresh()
        self.frame:Show()
        if Shatter.MainFrame then Shatter.MainFrame:SetActiveView("summary") end
    end
end
