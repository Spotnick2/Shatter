local _, Shatter = ...

local MainFrame = {
    frame = nil,
    rows = {},
    statusOverride = nil,
    statusIsError = false,
    stickyStatus = nil,
    stickyStatusIsError = false,
    stickyStatusUntil = 0,
    settingsOpen = false,
    activeView = "solo",
}

Shatter.MainFrame = MainFrame
Shatter.RegisterModule("MainFrame", MainFrame)

local TITLE_H = 32
local ROWS = 6

local WINDOW = Shatter.Constants.WINDOW
local FRAME_W = WINDOW.DEFAULT_WIDTH
local FRAME_H = WINDOW.DEFAULT_HEIGHT
local MIN_W = WINDOW.MIN_WIDTH
local MIN_H = WINDOW.MIN_HEIGHT
local MAX_W = WINDOW.MAX_WIDTH
local MAX_H = WINDOW.MAX_HEIGHT
local MIN_SCALE = WINDOW.MIN_SCALE
local MAX_SCALE = WINDOW.MAX_SCALE
local CONTENT_TOP = 76
local CONTENT_BOTTOM = 52

local function Clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function CreateButton(parent, text, width, secure)
    local template = secure and "SecureActionButtonTemplate,BackdropTemplate" or "BackdropTemplate"
    local button = CreateFrame("Button", nil, parent, template)
    button:SetSize(width or 100, 26)
    button:RegisterForClicks("LeftButtonUp")
    Shatter.ApplyBackdrop(button, 0.12, 0.12, 0.12, 1)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.text:SetAllPoints()
    button.text:SetJustifyH("CENTER")
    button.text:SetText(text)
    button:SetScript("OnEnter", function(self) if self:IsEnabled() then self:SetBackdropColor(0.18, 0.18, 0.18, 1) end end)
    button:SetScript("OnLeave", function(self) self:SetBackdropColor(0.12, 0.12, 0.12, 1) end)
    return button
end

local function SetShown(frame, shown)
    if not frame then return end
    if shown then
        frame:Show()
    else
        frame:Hide()
    end
end

function MainFrame:ClampGeometry()
    if not self.frame then return end
    local width = Clamp(self.frame:GetWidth() or FRAME_W, MIN_W, MAX_W)
    local height = Clamp(self.frame:GetHeight() or FRAME_H, MIN_H, MAX_H)
    if width ~= self.frame:GetWidth() or height ~= self.frame:GetHeight() then
        self.frame:SetSize(width, height)
    end
    local scale = Clamp(self.frame:GetScale() or 1, MIN_SCALE, MAX_SCALE)
    if scale ~= self.frame:GetScale() then
        self.frame:SetScale(scale)
    end
end

function MainFrame:SaveGeometry()
    self:ClampGeometry()
    if Shatter.Database then Shatter.Database:SaveWindow(self.frame) end
end

function MainFrame:Layout()
    if not self.frame or not self.queuePanel or not self.detailPanel then return end
    if self.layouting then return end
    self.layouting = true
    self:ClampGeometry()
    local width = self.frame:GetWidth() or FRAME_W
    local detailWidth = Clamp(math.floor(width * 0.38), 230, 300)

    self.detailPanel:ClearAllPoints()
    self.detailPanel:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -10, -CONTENT_TOP)
    self.detailPanel:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -10, CONTENT_BOTTOM)
    self.detailPanel:SetWidth(detailWidth)

    self.queuePanel:ClearAllPoints()
    self.queuePanel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 10, -CONTENT_TOP)
    self.queuePanel:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 10, CONTENT_BOTTOM)
    self.queuePanel:SetPoint("RIGHT", self.detailPanel, "LEFT", -8, 0)

    if self.status then
        self.status:ClearAllPoints()
        self.status:SetPoint("LEFT", self.footer, "LEFT", 0, 0)
        self.status:SetPoint("RIGHT", self.primary, "LEFT", -10, 0)
    end
    self.layouting = false
end

function MainFrame:ResetGeometry()
    if Shatter.Database then
        Shatter.Database:ResetWindow()
    else
        self.frame:SetSize(FRAME_W, FRAME_H)
        self.frame:SetScale(1)
        self.frame:ClearAllPoints()
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    self:Layout()
    self:SetStatus("Window size, scale, and position reset.", false, 3)
end

function MainFrame:CreateResizeGrip(parent)
    local grip = CreateFrame("Button", nil, parent, "BackdropTemplate")
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -3, 3)
    grip:RegisterForClicks("RightButtonUp")
    grip:EnableMouse(true)

    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    local normal = grip:GetNormalTexture()
    if normal then
        normal:SetVertexColor(0.78, 0.78, 0.78, 0.9)
    end
    local highlight = grip:GetHighlightTexture()
    if highlight then
        highlight:SetVertexColor(1, 0.82, 0.22, 0.75)
    end

    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText("Resize Shatter", 1, 0.82, 0)
        GameTooltip:AddLine("Click and drag to resize this window.", 0.82, 0.82, 0.82, true)
        GameTooltip:AddLine("Hold SHIFT while dragging to scale the window instead.", 0.82, 0.82, 0.82, true)
        GameTooltip:AddLine("Right-Click to reset the window size, scale, and position to their defaults.", 0.82, 0.82, 0.82, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    grip:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            if IsShiftKeyDown and IsShiftKeyDown() then
                self.scaling = true
                self.startX, self.startY = GetCursorPosition()
                self.startScale = parent:GetScale() or 1
                self:SetScript("OnUpdate", function(self)
                    local x, y = GetCursorPosition()
                    local delta = ((x - self.startX) - (y - self.startY)) / 500
                    parent:SetScale(Clamp(self.startScale + delta, MIN_SCALE, MAX_SCALE))
                end)
            else
                parent:StartSizing("BOTTOMRIGHT")
            end
        end
    end)
    grip:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            MainFrame:ResetGeometry()
            return
        end
        if self.scaling then
            self.scaling = nil
            self:SetScript("OnUpdate", nil)
        else
            parent:StopMovingOrSizing()
        end
        MainFrame:SaveGeometry()
        MainFrame:Layout()
    end)

    return grip
end

function MainFrame:Initialize()
    self:Create()
end

function MainFrame:Create()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "ShatterMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    if frame.SetResizable then frame:SetResizable(true) end
    if frame.SetMinResize then frame:SetMinResize(MIN_W, MIN_H) end
    if frame.SetMaxResize then frame:SetMaxResize(MAX_W, MAX_H) end
    frame:EnableMouse(true)
    frame:Hide()
    Shatter.ApplyBackdrop(frame, unpack(Shatter.C.BG_MAIN))
    table.insert(UISpecialFrames, "ShatterMainFrame")
    self.frame = frame

    if Shatter.Database then Shatter.Database:ApplyWindow(frame) end

    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(TITLE_H)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if Shatter.Database then Shatter.Database:SaveWindow(frame) end
    end)

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(unpack(Shatter.C.BG_HEADER))

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    title:SetText("Shatter")
    Shatter.SetTextColor(title, Shatter.C.ACCENT)
    self.title = title

    local simBadge = CreateFrame("Frame", nil, titleBar, "BackdropTemplate")
    simBadge:SetSize(72, 15)
    simBadge:SetPoint("LEFT", title, "RIGHT", 8, 0)
    Shatter.ApplyBackdrop(simBadge, 0.16, 0.10, 0.02, 0.88)
    simBadge:SetBackdropBorderColor(0.70, 0.48, 0.07, 0.78)
    simBadge.text = simBadge:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    simBadge.text:SetAllPoints()
    simBadge.text:SetJustifyH("CENTER")
    simBadge.text:SetText("SIMULATION")
    simBadge.text:SetTextColor(1.00, 0.78, 0.18, 0.95)
    simBadge:Hide()
    self.simBadge = simBadge

    local iconReserve = CreateFrame("Frame", nil, titleBar, "BackdropTemplate")
    iconReserve:SetSize(22, 22)
    iconReserve:SetPoint("LEFT", titleBar, "LEFT", 8, 0)
    Shatter.ApplyBackdrop(iconReserve, 0.03, 0.03, 0.03, 1)
    local headerIcon = iconReserve:CreateTexture(nil, "ARTWORK")
    headerIcon:SetPoint("CENTER", iconReserve, "CENTER", 0, 0)
    headerIcon:SetSize(18, 18)
    headerIcon:SetTexture("Interface\\Icons\\INV_Enchant_ShardPrismaticLarge")
    headerIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local close = CreateButton(titleBar, "x", 22)
    close:SetPoint("RIGHT", titleBar, "RIGHT", -7, 0)
    close:SetScript("OnClick", function() frame:Hide() end)

    local tabSolo = CreateButton(frame, "Solo", 68)
    tabSolo:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -TITLE_H - 7)
    tabSolo:SetBackdropColor(unpack(Shatter.C.BG_ACTIVE))
    tabSolo:SetBackdropBorderColor(unpack(Shatter.C.ACCENT))
    Shatter.SetTextColor(tabSolo.text, Shatter.C.ACCENT)
    self.tabSolo = tabSolo

    local tabMail = CreateButton(frame, "Mail", 68)
    tabMail:SetPoint("LEFT", tabSolo, "RIGHT", 6, 0)
    tabMail:SetBackdropColor(0.08, 0.08, 0.08, 0.7)
    Shatter.SetTextColor(tabMail.text, Shatter.C.TEXT_DIM)
    tabMail:SetScript("OnClick", function() self:SetStatus("Mail Mode is planned for Phase 3.", false) end)
    tabMail:SetScript("OnEnter", function(selfButton)
        selfButton:SetBackdropColor(0.10, 0.10, 0.10, 0.9)
        GameTooltip:SetOwner(selfButton, "ANCHOR_RIGHT")
        GameTooltip:SetText("Mail Mode", 1, 0.82, 0)
        GameTooltip:AddLine("Planned for Phase 3. Disabled in the Phase 1 Solo MVP.", 0.82, 0.82, 0.82, true)
        GameTooltip:Show()
    end)
    tabMail:SetScript("OnLeave", function(selfButton)
        selfButton:SetBackdropColor(0.08, 0.08, 0.08, 0.7)
        GameTooltip:Hide()
    end)

    local tabRaid = CreateButton(frame, "Raid", 68)
    tabRaid:SetPoint("LEFT", tabMail, "RIGHT", 6, 0)
    tabRaid:SetBackdropColor(0.08, 0.08, 0.08, 0.7)
    Shatter.SetTextColor(tabRaid.text, Shatter.C.TEXT_DIM)
    tabRaid:SetScript("OnClick", function() self:SetStatus("Raid / Trade Mode is planned for Phase 4.", false) end)
    tabRaid:SetScript("OnEnter", function(selfButton)
        selfButton:SetBackdropColor(0.10, 0.10, 0.10, 0.9)
        GameTooltip:SetOwner(selfButton, "ANCHOR_RIGHT")
        GameTooltip:SetText("Raid / Trade Mode", 1, 0.82, 0)
        GameTooltip:AddLine("Planned for Phase 4. Disabled in the Phase 1 Solo MVP.", 0.82, 0.82, 0.82, true)
        GameTooltip:Show()
    end)
    tabRaid:SetScript("OnLeave", function(selfButton)
        selfButton:SetBackdropColor(0.08, 0.08, 0.08, 0.7)
        GameTooltip:Hide()
    end)

    local queuePanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    queuePanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -76)
    queuePanel:SetSize(350, 252)
    Shatter.ApplyBackdrop(queuePanel, unpack(Shatter.C.BG_PANEL))
    self.queuePanel = queuePanel

    local queueTitle = queuePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    queueTitle:SetPoint("TOPLEFT", queuePanel, "TOPLEFT", 8, -7)
    queueTitle:SetText("Queue")
    Shatter.SetTextColor(queueTitle, Shatter.C.ACCENT)

    local previous
    for i = 1, ROWS do
        local row = Shatter.Rows.CreateQueueRow(queuePanel, i)
        row:SetPoint("LEFT", queuePanel, "LEFT", 6, 0)
        row:SetPoint("RIGHT", queuePanel, "RIGHT", -6, 0)
        if previous then
            row:SetPoint("TOP", previous, "BOTTOM", 0, -2)
        else
            row:SetPoint("TOP", queuePanel, "TOP", 0, -30)
        end
        self.rows[i] = row
        previous = row
    end

    local detailPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    detailPanel:SetPoint("TOPLEFT", queuePanel, "TOPRIGHT", 8, 0)
    detailPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, CONTENT_BOTTOM)
    Shatter.ApplyBackdrop(detailPanel, unpack(Shatter.C.BG_PANEL))
    self.detailPanel = detailPanel

    detailPanel.iconBorder = CreateFrame("Frame", nil, detailPanel, "BackdropTemplate")
    detailPanel.iconBorder:SetSize(42, 42)
    detailPanel.iconBorder:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 8, -11)
    Shatter.ApplyBackdrop(detailPanel.iconBorder, 0, 0, 0, 1)

    detailPanel.icon = detailPanel.iconBorder:CreateTexture(nil, "ARTWORK")
    detailPanel.icon:SetSize(38, 38)
    detailPanel.icon:SetPoint("CENTER", detailPanel.iconBorder, "CENTER", 0, 0)
    detailPanel.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    detailPanel.name = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detailPanel.name:SetPoint("TOPLEFT", detailPanel.iconBorder, "TOPRIGHT", 8, -2)
    detailPanel.name:SetPoint("RIGHT", detailPanel, "RIGHT", -10, 0)
    detailPanel.name:SetJustifyH("LEFT")

    detailPanel.meta = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailPanel.meta:SetPoint("TOPLEFT", detailPanel.name, "BOTTOMLEFT", 0, -6)
    detailPanel.meta:SetPoint("RIGHT", detailPanel, "RIGHT", -10, 0)
    detailPanel.meta:SetJustifyH("LEFT")

    detailPanel.location = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detailPanel.location:SetPoint("TOPLEFT", detailPanel.meta, "BOTTOMLEFT", 0, -4)
    detailPanel.location:SetPoint("RIGHT", detailPanel, "RIGHT", -10, 0)
    detailPanel.location:SetJustifyH("LEFT")

    detailPanel.expected = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detailPanel.expected:SetPoint("TOPLEFT", detailPanel.iconBorder, "BOTTOMLEFT", 0, -17)
    detailPanel.expected:SetPoint("RIGHT", detailPanel, "RIGHT", -10, 0)
    detailPanel.expected:SetJustifyH("LEFT")
    detailPanel.expected:SetText("Expected materials: unknown")

    detailPanel.results = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailPanel.results:SetPoint("TOPLEFT", detailPanel.expected, "BOTTOMLEFT", 0, -18)
    detailPanel.results:SetPoint("RIGHT", detailPanel, "RIGHT", -10, 0)
    detailPanel.results:SetJustifyH("LEFT")

    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 10)
    footer:SetHeight(32)
    self.footer = footer

    self.status = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.status:SetPoint("LEFT", footer, "LEFT", 0, 0)
    self.status:SetPoint("RIGHT", footer, "RIGHT", -410, 0)
    self.status:SetJustifyH("LEFT")

    local settings = CreateButton(footer, "Settings", 78)
    settings:SetPoint("RIGHT", footer, "RIGHT", 0, 0)
    settings:SetScript("OnClick", function()
        if self.activeView ~= "solo" then
            self:SetActiveView("solo")
        elseif Shatter.SettingsUI then
            Shatter.SettingsUI:Toggle()
        end
    end)
    self.settingsButton = settings

    local summary = CreateButton(footer, "Summary", 78)
    summary:SetPoint("RIGHT", settings, "LEFT", -6, 0)
    summary:SetScript("OnClick", function()
        if Shatter.SummaryUI then Shatter.SummaryUI:Toggle() end
    end)
    self.summaryButton = summary

    local skip = CreateButton(footer, "Skip", 58)
    skip:SetPoint("RIGHT", summary, "LEFT", -6, 0)
    skip:SetScript("OnClick", function()
        if Shatter.Queue then Shatter.Queue:SkipSelected() end
    end)
    self.skipButton = skip

    local ignore = CreateButton(footer, "Ignore", 64)
    ignore:SetPoint("RIGHT", skip, "LEFT", -6, 0)
    ignore:SetScript("OnClick", function()
        if Shatter.Queue then Shatter.Queue:IgnoreSelected() end
    end)
    self.ignoreButton = ignore

    local primary = CreateButton(footer, "Shatter Next", 110, true)
    primary:SetPoint("RIGHT", ignore, "LEFT", -8, 0)
    primary:SetHeight(30)
    primary:SetBackdropColor(0.20, 0.15, 0.03, 1)
    primary:SetBackdropBorderColor(unpack(Shatter.C.ACCENT))
    primary:SetScript("PreClick", function(button)
        if Shatter.Disenchant then Shatter.Disenchant:BeginSecureClick(button) end
    end)
    primary:SetScript("PostClick", function()
        self:Update()
    end)
    self.primary = primary
    if Shatter.Disenchant then Shatter.Disenchant:SetButton(primary) end

    self.resizeGrip = self:CreateResizeGrip(frame)

    if Shatter.SettingsUI then Shatter.SettingsUI:Create(frame) end
    if Shatter.SummaryUI then Shatter.SummaryUI:Create(frame) end

    frame:SetScript("OnSizeChanged", function()
        self:Layout()
    end)

    frame:SetScript("OnShow", function()
        if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("WINDOW_OPENED", 0.05) end
        self:Layout()
        self:Update()
    end)

    self:Layout()

    return frame
end

function MainFrame:ApplyPosition()
    if self.frame and Shatter.Database then
        Shatter.Database:ApplyWindow(self.frame)
        self:Layout()
    end
end

function MainFrame:Show()
    self:Create()
    self.frame:Show()
end

function MainFrame:Toggle()
    self:Create()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
    end
end

function MainFrame:SetStatus(text, isError, duration)
    self.statusOverride = text
    self.statusIsError = isError and true or false
    if duration and duration > 0 then
        self.stickyStatus = text
        self.stickyStatusIsError = isError and true or false
        self.stickyStatusUntil = (GetTime and GetTime() or 0) + duration
    end
    if self.status then
        self.status:SetText(text or "")
        Shatter.SetTextColor(self.status, isError and Shatter.C.BAD or Shatter.C.TEXT_NORM)
    end
end

function MainFrame:SetSettingsOpen(open)
    self:SetActiveView(open and "settings" or "solo")
end

function MainFrame:SetActiveView(view)
    self.activeView = view or "solo"
    self.settingsOpen = self.activeView == "settings"
    local summaryOpen = self.activeView == "summary"
    local settings = Shatter.Database and Shatter.Database:GetSettings()
    local simulation = settings and settings.debug and settings.simulateDisenchant

    SetShown(self.queuePanel, self.activeView == "solo")
    SetShown(self.detailPanel, self.activeView == "solo")
    SetShown(self.primary, self.activeView == "solo")
    SetShown(self.ignoreButton, self.activeView == "solo")
    SetShown(self.skipButton, self.activeView == "solo")
    SetShown(self.summaryButton, self.activeView ~= "settings")

    if self.settingsButton and self.settingsButton.text then
        self.settingsButton.text:SetText(self.activeView == "solo" and "Settings" or "Back")
    end
    if Shatter.SettingsUI and Shatter.SettingsUI.frame then
        SetShown(Shatter.SettingsUI.frame, self.activeView == "settings")
    end
    if Shatter.SummaryUI and Shatter.SummaryUI.frame then
        SetShown(Shatter.SummaryUI.frame, summaryOpen)
        if summaryOpen then Shatter.SummaryUI:Refresh() end
    end

    if simulation then
        self:SetStatus("Simulation mode enabled - no items will be disenchanted.", false)
    elseif self.settingsOpen then
        self:SetStatus("Settings", false)
    elseif summaryOpen then
        self:SetStatus("Summary", false)
    else
        self:Update()
    end
end

function MainFrame:GetBaseStatus()
    local settings = Shatter.Database and Shatter.Database:GetSettings()
    settings = settings or {}
    local simulation = settings.debug and settings.simulateDisenchant
    if Shatter.Disenchant and Shatter.Disenchant:HasPending() then
        return Shatter.Constants.STATUS.WAITING_RESULT, false
    end
    if simulation then
        return "Simulation mode enabled - no items will be disenchanted.", false
    end
    if Shatter.ItemScanner and not simulation and not Shatter.ItemScanner:HasDisenchantSpell() then
        return Shatter.Constants.STATUS.MISSING_ENCHANTING, true
    end
    if not Shatter.Queue or Shatter.Queue:Count() == 0 then
        return Shatter.Constants.STATUS.NO_ITEMS, false
    end
    return Shatter.Constants.STATUS.READY, false
end

function MainFrame:Update()
    if not self.frame then return end
    local settings = Shatter.Database and Shatter.Database:GetSettings()
    settings = settings or {}
    local simulation = settings.debug and settings.simulateDisenchant
    SetShown(self.simBadge, simulation)

    if self.activeView ~= "solo" then
        if simulation then
            self:SetStatus("Simulation mode enabled - no items will be disenchanted.", false)
        else
            self:SetStatus(self.activeView == "settings" and "Settings" or "Summary", false)
        end
        return
    end

    local items = Shatter.Queue and Shatter.Queue:GetItems() or {}
    local selected = Shatter.Queue and Shatter.Queue:GetSelected()

    for i, row in ipairs(self.rows) do
        row.index = i
        row:SetItem(items[i])
        row:SetSelected(i == (Shatter.Queue and Shatter.Queue.selectedIndex or 1))
    end

    local detail = self.detailPanel
    if selected then
        detail.icon:SetTexture(selected.texture or selected.itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
        detail.name:SetText(selected.itemLink or selected.itemName or "Unknown item")
        local r, g, b = Shatter.GetQualityColor(selected.quality)
        detail.name:SetTextColor(r, g, b)
        if detail.iconBorder then detail.iconBorder:SetBackdropBorderColor(r, g, b, 1) end
        local qualityLabel = Shatter.Constants.QUALITY_LABELS[selected.quality] or ("Quality " .. tostring(selected.quality or "?"))
        detail.meta:SetText(string.format("%s - Item Level %s", qualityLabel, tostring(selected.itemLevel or "?")))
        detail.location:SetText(string.format("Bag %d, Slot %d%s", selected.bag or 0, selected.slot or 0, selected.isSoulbound and " - Soulbound" or ""))
        detail.expected:SetText("Expected materials will be available once disenchant tables are added.")
        detail.results:SetText(Shatter.Session and Shatter.Session:FormatSummary() or "")
    else
        detail.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        if detail.iconBorder then detail.iconBorder:SetBackdropBorderColor(unpack(Shatter.C.BORDER)) end
        detail.name:SetText("No item selected")
        Shatter.SetTextColor(detail.name, Shatter.C.TEXT_DIM)
        detail.meta:SetText("")
        detail.location:SetText("")
        detail.expected:SetText("Expected materials: none")
        detail.results:SetText(Shatter.Session and Shatter.Session:FormatSummary() or "")
    end

    local now = GetTime and GetTime() or 0
    local status, isError
    if self.stickyStatus and now < (self.stickyStatusUntil or 0) then
        status, isError = self.stickyStatus, self.stickyStatusIsError
    else
        self.stickyStatus = nil
        status, isError = self:GetBaseStatus()
        if self.statusOverride then
            status, isError = self.statusOverride, self.statusIsError
        end
    end
    self:SetStatus(status, isError)
    self.statusOverride = nil
    self.statusIsError = false

    local pending = Shatter.Disenchant and Shatter.Disenchant:HasPending()
    local canAct = selected and Shatter.ItemScanner and (simulation or Shatter.ItemScanner:HasDisenchantSpell()) and not (Shatter.Disenchant and Shatter.Disenchant:HasPending())
    SetShown(self.ignoreButton, not pending)
    SetShown(self.skipButton, not pending)
    if self.primary then
        local label = simulation and "Simulate Next" or "Shatter Next"
        self.primary.text:SetText(pending and "Waiting..." or label)
        if canAct then
            self.primary:Enable()
            Shatter.SetTextColor(self.primary.text, Shatter.C.ACCENT)
            self.primary:SetBackdropColor(0.20, 0.15, 0.03, 1)
        else
            self.primary:Disable()
            Shatter.SetTextColor(self.primary.text, Shatter.C.TEXT_DIM)
            self.primary:SetBackdropColor(0.10, 0.10, 0.10, 1)
        end
    end
end
