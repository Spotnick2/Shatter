local _, Shatter = ...

local SettingsUI = {
    frame = nil,
}

Shatter.SettingsUI = SettingsUI
Shatter.RegisterModule("SettingsUI", SettingsUI)

local function CreatePanelButton(parent, text, width)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 90, 22)
    Shatter.ApplyBackdrop(btn, 0.12, 0.12, 0.12, 1)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetAllPoints()
    btn.text:SetJustifyH("CENTER")
    btn.text:SetText(text)
    btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.18, 0.18, 0.18, 1) end)
    btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.12, 0.12, 0.12, 1) end)
    return btn
end

local function SetShown(frame, shown)
    if not frame then return end
    if shown then
        frame:Show()
    else
        frame:Hide()
    end
end

function SettingsUI:Create(parent)
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -76)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 52)
    frame:SetFrameLevel(parent:GetFrameLevel() + 20)
    Shatter.ApplyBackdrop(frame, unpack(Shatter.C.BG_PANEL))
    frame:Hide()
    self.frame = frame

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 8)
    self.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 260)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self)
        content:SetWidth(math.max(1, self:GetWidth()))
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local maxScroll = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, current - delta * 18)))
    end)
    self.content = content

    local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
    title:SetText("Settings")
    Shatter.SetTextColor(title, Shatter.C.ACCENT)

    local maxLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    maxLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    maxLabel:SetText("Maximum quality")

    local uncommon = CreatePanelButton(content, "Uncommon", 82)
    uncommon:SetPoint("TOPLEFT", maxLabel, "BOTTOMLEFT", 0, -8)
    local rare = CreatePanelButton(content, "Rare", 64)
    rare:SetPoint("LEFT", uncommon, "RIGHT", 6, 0)
    local epic = CreatePanelButton(content, "Epic", 64)
    epic:SetPoint("LEFT", rare, "RIGHT", 6, 0)

    local function SetQuality(quality)
        Shatter.Database:GetSettings().maxQuality = quality
        self:Refresh()
        if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("SETTINGS_MAX_QUALITY", 0.05) end
    end
    uncommon:SetScript("OnClick", function() SetQuality(2) end)
    rare:SetScript("OnClick", function() SetQuality(3) end)
    epic:SetScript("OnClick", function() SetQuality(4) end)
    self.qualityButtons = { [2] = uncommon, [3] = rare, [4] = epic }

    local orderLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    orderLabel:SetPoint("TOPLEFT", uncommon, "BOTTOMLEFT", 0, -10)
    orderLabel:SetText("Solo queue order")

    local bagSlot = CreatePanelButton(content, "Bag / Slot", 78)
    bagSlot:SetPoint("TOPLEFT", orderLabel, "BOTTOMLEFT", 0, -8)
    local fifo = CreatePanelButton(content, "First In, First Out", 118)
    fifo:SetPoint("LEFT", bagSlot, "RIGHT", 6, 0)
    local lifo = CreatePanelButton(content, "Last In, First Out", 118)
    lifo:SetPoint("LEFT", fifo, "RIGHT", 6, 0)

    local function SetQueueOrder(order)
        if Shatter.Database then Shatter.Database:SetQueueOrder("solo", order) end
        self:Refresh()
        if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("SETTINGS_QUEUE_ORDER", 0.05) end
    end
    bagSlot:SetScript("OnClick", function() SetQueueOrder(Shatter.Constants.QUEUE_ORDER.BAG_SLOT) end)
    fifo:SetScript("OnClick", function() SetQueueOrder(Shatter.Constants.QUEUE_ORDER.FIFO) end)
    lifo:SetScript("OnClick", function() SetQueueOrder(Shatter.Constants.QUEUE_ORDER.LIFO) end)
    self.queueOrderButtons = {
        [Shatter.Constants.QUEUE_ORDER.BAG_SLOT] = bagSlot,
        [Shatter.Constants.QUEUE_ORDER.FIFO] = fifo,
        [Shatter.Constants.QUEUE_ORDER.LIFO] = lifo,
    }

    local orderHelp = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    orderHelp:SetPoint("TOPLEFT", bagSlot, "BOTTOMLEFT", 0, -6)
    orderHelp:SetPoint("RIGHT", content, "RIGHT", -12, 0)
    orderHelp:SetJustifyH("LEFT")
    orderHelp:SetText("Controls the Solo queue processing order.")

    local soulbound = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    soulbound:SetPoint("TOPLEFT", orderHelp, "BOTTOMLEFT", -4, -8)
    soulbound:SetSize(24, 24)
    soulbound.label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    soulbound.label:SetPoint("LEFT", soulbound, "RIGHT", 4, 0)
    soulbound.label:SetText("Include soulbound items")
    soulbound:SetScript("OnClick", function(self)
        Shatter.Database:GetSettings().includeSoulbound = self:GetChecked() and true or false
        if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("SETTINGS_SOULBOUND", 0.05) end
    end)
    self.soulbound = soulbound

    local debug = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    debug:SetPoint("TOPLEFT", soulbound, "BOTTOMLEFT", 0, -6)
    debug:SetSize(24, 24)
    debug.label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    debug.label:SetPoint("LEFT", debug, "RIGHT", 4, 0)
    debug.label:SetText("Debug logging")
    debug:SetScript("OnClick", function(self)
        local settings = Shatter.Database:GetSettings()
        settings.debug = self:GetChecked() and true or false
        if not settings.debug then
            settings.traceDebug = false
            settings.simulateDisenchant = false
        end
        SettingsUI:Refresh()
        if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("SETTINGS_DEBUG", 0.05) end
    end)
    self.debug = debug

    local trace = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    trace:SetPoint("TOPLEFT", debug, "BOTTOMLEFT", 0, -6)
    trace:SetSize(24, 24)
    trace.label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    trace.label:SetPoint("LEFT", trace, "RIGHT", 4, 0)
    trace.label:SetText("Trace logging")
    trace:SetScript("OnClick", function(self)
        Shatter.Database:GetSettings().traceDebug = self:GetChecked() and true or false
        SettingsUI:Refresh()
    end)
    self.trace = trace

    local simulate = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    simulate:SetPoint("TOPLEFT", trace, "BOTTOMLEFT", 0, -6)
    simulate:SetSize(24, 24)
    simulate.label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    simulate.label:SetPoint("LEFT", simulate, "RIGHT", 4, 0)
    simulate.label:SetText("Development simulation: fake results, no casting")
    simulate:SetScript("OnClick", function(self)
        Shatter.Database:GetSettings().simulateDisenchant = self:GetChecked() and true or false
        if Shatter.Session then Shatter.Session:ResetSimulatedItems() end
        if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("SETTINGS_SIMULATION", 0.05) end
        if Shatter.MainFrame then Shatter.MainFrame:Update() end
    end)
    self.simulate = simulate

    local note = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", simulate, "BOTTOMLEFT", 4, -10)
    note:SetPoint("RIGHT", content, "RIGHT", -12, 0)
    note:SetJustifyH("LEFT")
    note:SetText("Expected materials and value thresholds are reserved for Phase 2. Mail and Raid modes are reserved for later phases.")

    self:Refresh()
    return frame
end

function SettingsUI:Refresh()
    if not self.frame then return end
    local settings = Shatter.Database:GetSettings()
    if self.soulbound then self.soulbound:SetChecked(settings.includeSoulbound) end
    if self.debug then self.debug:SetChecked(settings.debug) end
    if self.trace then self.trace:SetChecked(settings.traceDebug) end
    if self.simulate then self.simulate:SetChecked(settings.simulateDisenchant) end
    SetShown(self.trace, settings.debug or settings.traceDebug)
    SetShown(self.trace and self.trace.label, settings.debug or settings.traceDebug)
    SetShown(self.simulate, settings.debug or settings.simulateDisenchant)
    SetShown(self.simulate and self.simulate.label, settings.debug or settings.simulateDisenchant)
    for quality, button in pairs(self.qualityButtons or {}) do
        if quality == settings.maxQuality then
            button:SetBackdropColor(unpack(Shatter.C.BG_ACTIVE))
            Shatter.SetTextColor(button.text, Shatter.C.ACCENT)
        else
            button:SetBackdropColor(0.12, 0.12, 0.12, 1)
            Shatter.SetTextColor(button.text, Shatter.C.TEXT_NORM)
        end
    end
    local order = Shatter.Database and Shatter.Database:GetQueueOrder("solo") or Shatter.Constants.QUEUE_ORDER.BAG_SLOT
    for value, button in pairs(self.queueOrderButtons or {}) do
        if value == order then
            button:SetBackdropColor(unpack(Shatter.C.BG_ACTIVE))
            Shatter.SetTextColor(button.text, Shatter.C.ACCENT)
        else
            button:SetBackdropColor(0.12, 0.12, 0.12, 1)
            Shatter.SetTextColor(button.text, Shatter.C.TEXT_NORM)
        end
    end
end

function SettingsUI:Toggle()
    if not self.frame then return end
    if self.frame:IsShown() then
        self.frame:Hide()
        if Shatter.MainFrame then Shatter.MainFrame:SetSettingsOpen(false) end
    else
        self:Refresh()
        self.frame:Show()
        if Shatter.MainFrame then Shatter.MainFrame:SetSettingsOpen(true) end
    end
end
