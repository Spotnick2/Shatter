local _, Shatter = ...

local MailLaunchPanel = {
    frame = nil,
    toggle = nil,
}

Shatter.MailLaunchPanel = MailLaunchPanel
Shatter.RegisterModule("MailLaunchPanel", MailLaunchPanel)

local function IsFrameVisible(frame)
    if not frame then return false end
    if frame.IsVisible and frame:IsVisible() then return true end
    if frame.IsShown and frame:IsShown() then return true end
    return false
end

local function IsMailboxOpen()
    return IsFrameVisible(_G.MailFrame) or IsFrameVisible(_G.InboxFrame) or IsFrameVisible(_G.OpenMailFrame) or IsFrameVisible(_G.SendMailFrame)
end

local function GetSettings()
    if not Shatter.Database then return nil end
    local settings = Shatter.Database:GetSettings()
    settings.mail = type(settings.mail) == "table" and settings.mail or {}
    if settings.mail.launchPanelVisible == nil then
        settings.mail.launchPanelVisible = true
    end
    return settings
end

local function IsPanelPreferredVisible()
    local settings = GetSettings()
    return not settings or settings.mail.launchPanelVisible ~= false
end

local function SetPanelPreferredVisible(shown)
    local settings = GetSettings()
    if not settings then return end
    settings.mail.launchPanelVisible = shown and true or false
end

local function ApplyButtonState(button, enabled)
    if not button then return end
    if enabled then
        button:Enable()
        button:SetBackdropColor(0.12, 0.12, 0.12, 1)
        Shatter.SetTextColor(button.text, Shatter.C.ACCENT)
    else
        button:Disable()
        button:SetBackdropColor(0.10, 0.10, 0.10, 1)
        Shatter.SetTextColor(button.text, Shatter.C.TEXT_DIM)
    end
end

local function CreateActionButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 200, 24)
    Shatter.ApplyBackdrop(button, 0.12, 0.12, 0.12, 1)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.text:SetAllPoints()
    button.text:SetJustifyH("CENTER")
    button.text:SetText(text)
    button:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            self:SetBackdropColor(0.18, 0.18, 0.18, 1)
        end
    end)
    button:SetScript("OnLeave", function(self)
        if self:IsEnabled() then
            self:SetBackdropColor(0.12, 0.12, 0.12, 1)
        else
            self:SetBackdropColor(0.10, 0.10, 0.10, 1)
        end
    end)
    return button
end

function MailLaunchPanel:UpdateToggleVisual()
    if not self.toggle then return end
    if self.frame and self.frame:IsShown() then
        self.toggle:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
        self.toggle:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    else
        self.toggle:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
        self.toggle:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    end
end

function MailLaunchPanel:AttachToMailbox()
    if not _G.MailFrame then return false end
    self:Create()
    self.frame:SetParent(_G.MailFrame)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPLEFT", _G.MailFrame, "TOPRIGHT", 8, -12)

    self.toggle:SetParent(_G.MailFrame)
    self.toggle:ClearAllPoints()
    self.toggle:SetPoint("TOPLEFT", _G.MailFrame, "TOPRIGHT", -2, -34)
    return true
end

function MailLaunchPanel:Create()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(250, 356)
    Shatter.ApplyBackdrop(frame, unpack(Shatter.C.BG_PANEL))
    frame:SetFrameStrata("MEDIUM")
    frame:Hide()
    self.frame = frame

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
    title:SetText("Shatter Mail")
    Shatter.SetTextColor(title, Shatter.C.ACCENT)
    self.title = title

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -1)
    close:SetScript("OnClick", function()
        SetPanelPreferredVisible(false)
        frame:Hide()
        MailLaunchPanel:UpdateToggleVisual()
    end)
    self.closeButton = close

    self.mailboxStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.mailboxStatus:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)
    self.mailboxStatus:SetText("Mailbox unavailable")

    self.sessionStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.sessionStatus:SetPoint("TOPLEFT", self.mailboxStatus, "BOTTOMLEFT", 0, -4)
    self.sessionStatus:SetText("No active session.")

    local startButton = CreateActionButton(frame, "Start New Session", 220)
    startButton:SetPoint("TOPLEFT", self.sessionStatus, "BOTTOMLEFT", 0, -10)
    startButton:SetScript("OnClick", function()
        if Shatter.MailMode then
            Shatter.MailMode:StartNewSessionFromLaunchPanel()
        end
        MailLaunchPanel:Refresh()
    end)
    self.startButton = startButton

    local continueButton = CreateActionButton(frame, "Continue Existing Session", 220)
    continueButton:SetPoint("TOPLEFT", startButton, "BOTTOMLEFT", 0, -8)
    continueButton:SetScript("OnClick", function()
        if Shatter.MailMode then
            Shatter.MailMode:ContinueSessionFromLaunchPanel()
        end
        MailLaunchPanel:Refresh()
    end)
    self.continueButton = continueButton

    local sep1 = frame:CreateTexture(nil, "ARTWORK")
    sep1:SetTexture("Interface\\Buttons\\WHITE8X8")
    sep1:SetColorTexture(0.22, 0.22, 0.22, 1)
    sep1:SetPoint("TOPLEFT", continueButton, "BOTTOMLEFT", 0, -10)
    sep1:SetPoint("TOPRIGHT", continueButton, "BOTTOMRIGHT", 0, -10)
    sep1:SetHeight(1)

    local processTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    processTitle:SetPoint("TOPLEFT", sep1, "BOTTOMLEFT", 0, -10)
    processTitle:SetText("Process")
    Shatter.SetTextColor(processTitle, Shatter.C.ACCENT)
    self.processTitle = processTitle

    local processAll = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    processAll:SetPoint("TOPLEFT", processTitle, "BOTTOMLEFT", 0, -6)
    processAll:SetText("(o) All Mail")
    self.processAll = processAll

    local processSender = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    processSender:SetPoint("TOPLEFT", processAll, "BOTTOMLEFT", 0, -4)
    processSender:SetText("( ) Mail from: Select Sender (Pass 2)")
    self.processSender = processSender

    local returnTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    returnTitle:SetPoint("TOPLEFT", processSender, "BOTTOMLEFT", 0, -14)
    returnTitle:SetText("Return Mats")
    Shatter.SetTextColor(returnTitle, Shatter.C.ACCENT)
    self.returnTitle = returnTitle

    local returnOriginal = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    returnOriginal:SetPoint("TOPLEFT", returnTitle, "BOTTOMLEFT", 0, -6)
    returnOriginal:SetText("(o) Original Sender")
    self.returnOriginal = returnOriginal

    local returnFunnel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    returnFunnel:SetPoint("TOPLEFT", returnOriginal, "BOTTOMLEFT", 0, -4)
    returnFunnel:SetText("( ) Funnel to: Select Recipient (Pass 2)")
    self.returnFunnel = returnFunnel

    local keepMats = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    keepMats:SetPoint("TOPLEFT", returnFunnel, "BOTTOMLEFT", 0, -4)
    keepMats:SetText("( ) Keep Materials (Pass 2)")
    self.keepMats = keepMats

    local sep2 = frame:CreateTexture(nil, "ARTWORK")
    sep2:SetTexture("Interface\\Buttons\\WHITE8X8")
    sep2:SetColorTexture(0.22, 0.22, 0.22, 1)
    sep2:SetPoint("TOPLEFT", keepMats, "BOTTOMLEFT", 0, -10)
    sep2:SetPoint("TOPRIGHT", keepMats, "BOTTOMRIGHT", 0, -10)
    sep2:SetHeight(1)

    local foot = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    foot:SetPoint("TOPLEFT", sep2, "BOTTOMLEFT", 0, -10)
    foot:SetPoint("TOPRIGHT", sep2, "BOTTOMRIGHT", 0, -10)
    foot:SetJustifyH("CENTER")
    foot:SetText("Session remains active until closed.")
    self.footnote = foot

    local toggle = CreateFrame("Button", nil, UIParent)
    toggle:SetSize(20, 20)
    toggle:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    toggle:SetScript("OnClick", function()
        local shown = not (MailLaunchPanel.frame and MailLaunchPanel.frame:IsShown())
        SetPanelPreferredVisible(shown)
        if shown then
            MailLaunchPanel.frame:Show()
        else
            MailLaunchPanel.frame:Hide()
        end
        MailLaunchPanel:Refresh()
    end)
    toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if MailLaunchPanel.frame and MailLaunchPanel.frame:IsShown() then
            GameTooltip:AddLine("Hide Shatter Mail panel", 1, 0.82, 0)
        else
            GameTooltip:AddLine("Show Shatter Mail panel", 1, 0.82, 0)
        end
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", function() GameTooltip_Hide() end)
    toggle:Hide()
    self.toggle = toggle
    self:UpdateToggleVisual()

    return frame
end

function MailLaunchPanel:Refresh()
    if not self.frame then return end
    local mailboxOpen = IsMailboxOpen()
    local hasSession = Shatter.MailSession and Shatter.MailSession:HasActiveSession()

    if mailboxOpen then
        self.mailboxStatus:SetText("Mailbox ready")
        Shatter.SetTextColor(self.mailboxStatus, Shatter.C.GOOD)
    else
        self.mailboxStatus:SetText("Mailbox unavailable")
        Shatter.SetTextColor(self.mailboxStatus, Shatter.C.BAD)
    end

    if hasSession then
        self.sessionStatus:SetText("Session active.")
        Shatter.SetTextColor(self.sessionStatus, Shatter.C.TEXT_NORM)
    else
        self.sessionStatus:SetText("No active session.")
        Shatter.SetTextColor(self.sessionStatus, Shatter.C.TEXT_DIM)
    end

    ApplyButtonState(self.startButton, mailboxOpen)
    ApplyButtonState(self.continueButton, mailboxOpen and hasSession)
    self:UpdateToggleVisual()
end

function MailLaunchPanel:ShowForMailbox()
    if not self:AttachToMailbox() then return end
    self.toggle:Show()
    if IsPanelPreferredVisible() then
        self.frame:Show()
    else
        self.frame:Hide()
    end
    self:Refresh()
end

function MailLaunchPanel:HideForMailboxClose()
    if self.frame then
        self.frame:Hide()
    end
    if self.toggle then
        self.toggle:Hide()
    end
end

function MailLaunchPanel:Initialize()
    self:Create()
end
