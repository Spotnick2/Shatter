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

local function ApplyButtonState(button, enabled, emphasis)
    if not button then return end
    if enabled then
        button:Enable()
        if emphasis == "primary" then
            button._normalColor = { 0.20, 0.17, 0.07, 1 }
            button._hoverColor = { 0.24, 0.20, 0.08, 1 }
            Shatter.SetTextColor(button.text, Shatter.C.ACCENT)
        else
            button._normalColor = { 0.12, 0.12, 0.12, 1 }
            button._hoverColor = { 0.18, 0.18, 0.18, 1 }
            Shatter.SetTextColor(button.text, Shatter.C.TEXT_NORM)
        end
        button:SetBackdropColor(unpack(button._normalColor))
    else
        button:Disable()
        button:SetBackdropColor(0.10, 0.10, 0.10, 1)
        Shatter.SetTextColor(button.text, Shatter.C.TEXT_DIM)
        button._normalColor = { 0.10, 0.10, 0.10, 1 }
        button._hoverColor = { 0.10, 0.10, 0.10, 1 }
    end
end

local function SetShown(frame, shown)
    if not frame then return end
    if shown then frame:Show() else frame:Hide() end
end

local function CreateActionButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 200, 24)
    Shatter.ApplyBackdrop(button, 0.12, 0.12, 0.12, 1)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.text:SetAllPoints()
    button.text:SetJustifyH("CENTER")
    button.text:SetText(text)
    button._normalColor = { 0.12, 0.12, 0.12, 1 }
    button._hoverColor = { 0.18, 0.18, 0.18, 1 }
    button:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            local hover = self._hoverColor or { 0.18, 0.18, 0.18, 1 }
            self:SetBackdropColor(unpack(hover))
        end
    end)
    button:SetScript("OnLeave", function(self)
        if self:IsEnabled() then
            local normal = self._normalColor or { 0.12, 0.12, 0.12, 1 }
            self:SetBackdropColor(unpack(normal))
        else
            self:SetBackdropColor(0.10, 0.10, 0.10, 1)
        end
    end)
    return button
end

local function CreateRadioButton(parent, label)
    local button = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    button:SetSize(22, 22)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.label:SetPoint("LEFT", button, "RIGHT", 2, 0)
    button.label:SetJustifyH("LEFT")
    button.label:SetText(label or "")
    return button
end

local function CreateValueButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 130, 20)
    Shatter.ApplyBackdrop(button, 0.08, 0.08, 0.08, 1)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    button.text:SetPoint("LEFT", button, "LEFT", 6, 0)
    button.text:SetPoint("RIGHT", button, "RIGHT", -14, 0)
    button.text:SetJustifyH("LEFT")
    button.text:SetText(text or "")
    button.arrow = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    button.arrow:SetPoint("RIGHT", button, "RIGHT", -4, 0)
    button.arrow:SetText("v")
    button:SetScript("OnEnter", function(self) self:SetBackdropColor(0.12, 0.12, 0.12, 1) end)
    button:SetScript("OnLeave", function(self) self:SetBackdropColor(0.08, 0.08, 0.08, 1) end)
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
    frame:SetSize(250, 336)
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
    self.mailboxStatus:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    self.mailboxStatus:SetText("Mailbox unavailable")

    self.sessionStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.sessionStatus:SetPoint("TOPLEFT", self.mailboxStatus, "BOTTOMLEFT", 0, -3)
    self.sessionStatus:SetText("No active session.")

    local startButton = CreateActionButton(frame, "Start New Session", 220)
    startButton:SetPoint("TOPLEFT", self.sessionStatus, "BOTTOMLEFT", 0, -8)
    startButton:SetScript("OnClick", function()
        MailLaunchPanel:CommitFunnelEdit()
        if Shatter.MailMode then
            Shatter.MailMode:StartNewSessionFromLaunchPanel()
        end
        MailLaunchPanel:Refresh()
    end)
    self.startButton = startButton

    local continueButton = CreateActionButton(frame, "Continue Existing Session", 220)
    continueButton:SetPoint("TOPLEFT", startButton, "BOTTOMLEFT", 0, -6)
    continueButton:SetScript("OnClick", function()
        MailLaunchPanel:CommitFunnelEdit()
        if Shatter.MailMode then
            Shatter.MailMode:ContinueSessionFromLaunchPanel()
        end
        MailLaunchPanel:Refresh()
    end)
    self.continueButton = continueButton

    local sep1 = frame:CreateTexture(nil, "ARTWORK")
    sep1:SetTexture("Interface\\Buttons\\WHITE8X8")
    sep1:SetColorTexture(0.22, 0.22, 0.22, 1)
    sep1:SetPoint("TOPLEFT", continueButton, "BOTTOMLEFT", 0, -8)
    sep1:SetPoint("TOPRIGHT", continueButton, "BOTTOMRIGHT", 0, -8)
    sep1:SetHeight(1)

    local processTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    processTitle:SetPoint("TOPLEFT", sep1, "BOTTOMLEFT", 0, -8)
    processTitle:SetText("Process")
    Shatter.SetTextColor(processTitle, Shatter.C.ACCENT)
    self.processTitle = processTitle

    local processAll = CreateRadioButton(frame, "All Mail")
    processAll:SetPoint("TOPLEFT", processTitle, "BOTTOMLEFT", -2, -3)
    processAll:SetScript("OnClick", function()
        if Shatter.MailMode then
            Shatter.MailMode:SetLaunchMailSelectionMode(Shatter.Constants.MAIL_SELECTION_MODE.ALL)
        end
    end)
    self.processAll = processAll

    local processSender = CreateRadioButton(frame, "Mail from:")
    processSender:SetPoint("TOPLEFT", processAll, "BOTTOMLEFT", 0, -2)
    processSender:SetScript("OnClick", function()
        if Shatter.MailMode then
            Shatter.MailMode:SetLaunchMailSelectionMode(Shatter.Constants.MAIL_SELECTION_MODE.SENDER)
        end
    end)
    self.processSender = processSender

    local senderButton = CreateValueButton(frame, "Select Sender", 132)
    senderButton:SetPoint("LEFT", processSender.label, "RIGHT", 4, 0)
    senderButton:SetScript("OnClick", function()
        if not Shatter.MailMode then return end
        local senders = Shatter.MailMode:GetLaunchSenders() or {}
        if #senders == 0 then return end
        local current = (Shatter.MailMode:GetLaunchContext() or {}).selectedSender
        local index = 0
        for i, sender in ipairs(senders) do
            if sender == current then
                index = i
                break
            end
        end
        index = (index % #senders) + 1
        Shatter.MailMode:SetLaunchSender(senders[index])
    end)
    self.senderButton = senderButton

    local processPostal = CreateRadioButton(frame, "Selected mails (Postal)")
    processPostal:SetPoint("TOPLEFT", processSender, "BOTTOMLEFT", 0, -2)
    processPostal:SetScript("OnClick", function()
        if Shatter.MailMode then
            Shatter.MailMode:SetLaunchMailSelectionMode(Shatter.Constants.MAIL_SELECTION_MODE.POSTAL_SELECTED)
        end
    end)
    self.processPostal = processPostal

    local postalCount = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    postalCount:SetPoint("LEFT", processPostal.label, "RIGHT", 6, 0)
    postalCount:SetJustifyH("LEFT")
    self.postalCount = postalCount

    local returnTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    returnTitle:SetPoint("TOPLEFT", processSender, "BOTTOMLEFT", 0, -10)
    returnTitle:SetText("Return Mats")
    Shatter.SetTextColor(returnTitle, Shatter.C.ACCENT)
    self.returnTitle = returnTitle

    local returnOriginal = CreateRadioButton(frame, "Send to original sender")
    returnOriginal:SetPoint("TOPLEFT", returnTitle, "BOTTOMLEFT", -2, -3)
    returnOriginal:SetScript("OnClick", function()
        if Shatter.MailMode then
            Shatter.MailMode:SetLaunchRecipientMode(Shatter.Constants.MAIL_RECIPIENT_MODE.ORIGINAL_SENDERS)
        end
    end)
    self.returnOriginal = returnOriginal

    local returnFunnel = CreateRadioButton(frame, "Funnel to:")
    returnFunnel:SetPoint("TOPLEFT", returnOriginal, "BOTTOMLEFT", 0, -2)
    returnFunnel:SetScript("OnClick", function()
        if Shatter.MailMode then
            Shatter.MailMode:SetLaunchRecipientMode(Shatter.Constants.MAIL_RECIPIENT_MODE.FUNNEL)
        end
    end)
    self.returnFunnel = returnFunnel

    local funnelEdit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    funnelEdit:SetSize(132, 20)
    funnelEdit:SetPoint("LEFT", returnFunnel.label, "RIGHT", 4, 0)
    funnelEdit:SetAutoFocus(false)
    funnelEdit:SetTextInsets(6, 16, 0, 0)
    funnelEdit._isPlaceholder = false
    local funnelArrow = funnelEdit:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    funnelArrow:SetPoint("RIGHT", funnelEdit, "RIGHT", -6, 0)
    funnelArrow:SetText("v")
    self.funnelArrow = funnelArrow
    funnelEdit:SetScript("OnEditFocusGained", function(self)
        if self._isPlaceholder then
            self:SetText("")
            self._isPlaceholder = false
            self:SetTextColor(unpack(Shatter.C.TEXT_NORM))
        end
    end)
    funnelEdit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if Shatter.MailMode then
            local text = self:GetText() or ""
            if self._isPlaceholder then
                text = ""
            end
            Shatter.MailMode:SetLaunchFunnelRecipient(text)
        end
    end)
    funnelEdit:SetScript("OnEditFocusLost", function(self)
        if Shatter.MailMode then
            local text = self:GetText() or ""
            if self._isPlaceholder then
                text = ""
            end
            Shatter.MailMode:SetLaunchFunnelRecipient(text)
        end
    end)
    self.funnelEdit = funnelEdit

    local keepMats = CreateRadioButton(frame, "Keep materials")
    keepMats:SetPoint("TOPLEFT", returnFunnel, "BOTTOMLEFT", 0, -2)
    keepMats:SetScript("OnClick", function()
        if Shatter.MailMode then
            Shatter.MailMode:SetLaunchRecipientMode(Shatter.Constants.MAIL_RECIPIENT_MODE.KEEP)
        end
    end)
    self.keepMats = keepMats

    local sep2 = frame:CreateTexture(nil, "ARTWORK")
    sep2:SetTexture("Interface\\Buttons\\WHITE8X8")
    sep2:SetColorTexture(0.22, 0.22, 0.22, 1)
    sep2:SetPoint("TOPLEFT", keepMats, "BOTTOMLEFT", 2, -6)
    sep2:SetPoint("TOPRIGHT", keepMats, "BOTTOMRIGHT", 190, -6)
    sep2:SetHeight(1)

    local foot = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    foot:SetPoint("TOPLEFT", sep2, "BOTTOMLEFT", 0, -6)
    foot:SetPoint("TOPRIGHT", sep2, "BOTTOMRIGHT", 0, -6)
    foot:SetJustifyH("CENTER")
    foot:SetText("Session remains active until you close it.")
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

-- A name typed into the funnel box without Enter is still the player's
-- choice (clicking a button does not take the box's focus away): commit it
-- before Start or Continue reads the options.
function MailLaunchPanel:CommitFunnelEdit()
    local edit = self.funnelEdit
    if not edit or edit._isPlaceholder or not Shatter.MailMode then return end
    Shatter.MailMode:SetLaunchFunnelRecipient(strtrim(edit:GetText() or ""))
    edit:ClearFocus()
end

function MailLaunchPanel:Refresh()
    if not self.frame then return end
    local context = Shatter.MailMode and Shatter.MailMode:GetLaunchContext() or {}
    local mailboxOpen = context.mailboxOpen and true or false
    local hasSession = context.hasSession and true or false
    local selectionMode = context.selectionMode
    local recipientMode = context.recipientMode
    local sender = context.selectedSender
    local funnelRecipient = context.funnelRecipient or ""

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

    if hasSession then
        -- One session at a time: close the active one to start another.
        ApplyButtonState(self.continueButton, mailboxOpen and hasSession, "primary")
        ApplyButtonState(self.startButton, false, "secondary")
    else
        ApplyButtonState(self.startButton, mailboxOpen, "primary")
        ApplyButtonState(self.continueButton, mailboxOpen and hasSession, "secondary")
    end

    if self.processAll then
        self.processAll:SetChecked(selectionMode == Shatter.Constants.MAIL_SELECTION_MODE.ALL)
        self.processSender:SetChecked(selectionMode == Shatter.Constants.MAIL_SELECTION_MODE.SENDER)
        self.processPostal:SetChecked(selectionMode == Shatter.Constants.MAIL_SELECTION_MODE.POSTAL_SELECTED)
    end

    if self.senderButton and self.senderButton.text then
        self.senderButton.text:SetText(sender or "Select Sender")
        self.senderButton:Enable()
        if not mailboxOpen then
            self.senderButton:Disable()
        end
    end
    SetShown(self.senderButton, selectionMode == Shatter.Constants.MAIL_SELECTION_MODE.SENDER)

    if self.postalCount then
        if context.postalAvailable then
            self.postalCount:SetText(string.format("(%d selected)", context.postalSelectedCount or 0))
            self.postalCount:SetTextColor(unpack(Shatter.C.TEXT_DIM))
            self.processPostal:Show()
            self.postalCount:Show()
            if not context.postalSelectionReady then
                self.postalCount:SetText("(Select module inactive)")
                self.postalCount:SetTextColor(unpack(Shatter.C.BAD))
            end
        else
            self.processPostal:Hide()
            self.postalCount:Hide()
            if selectionMode == Shatter.Constants.MAIL_SELECTION_MODE.POSTAL_SELECTED and Shatter.MailMode then
                Shatter.MailMode:SetLaunchMailSelectionMode(Shatter.Constants.MAIL_SELECTION_MODE.ALL)
            end
        end
    end

    if self.returnTitle then
        self.returnTitle:ClearAllPoints()
        if context.postalAvailable then
            self.returnTitle:SetPoint("TOPLEFT", self.processPostal, "BOTTOMLEFT", 0, -10)
        else
            self.returnTitle:SetPoint("TOPLEFT", self.processSender, "BOTTOMLEFT", 0, -10)
        end
    end

    if self.returnOriginal then
        self.returnOriginal:SetChecked(recipientMode == Shatter.Constants.MAIL_RECIPIENT_MODE.ORIGINAL_SENDERS)
        self.returnFunnel:SetChecked(recipientMode == Shatter.Constants.MAIL_RECIPIENT_MODE.FUNNEL)
        self.keepMats:SetChecked(recipientMode == Shatter.Constants.MAIL_RECIPIENT_MODE.KEEP)
    end

    if self.funnelEdit and not self.funnelEdit:HasFocus() then
        if funnelRecipient and funnelRecipient ~= "" then
            self.funnelEdit:SetText(funnelRecipient)
            self.funnelEdit._isPlaceholder = false
        else
            self.funnelEdit:SetText("Select Recipient")
            self.funnelEdit._isPlaceholder = true
        end
    end
    if self.funnelEdit then
        if recipientMode == Shatter.Constants.MAIL_RECIPIENT_MODE.FUNNEL then
            if self.funnelEdit.Enable then self.funnelEdit:Enable() end
            if self.funnelEdit._isPlaceholder then
                self.funnelEdit:SetTextColor(unpack(Shatter.C.TEXT_DIM))
            else
                self.funnelEdit:SetTextColor(unpack(Shatter.C.TEXT_NORM))
            end
        else
            if self.funnelEdit.Disable then self.funnelEdit:Disable() end
            self.funnelEdit:SetTextColor(unpack(Shatter.C.TEXT_DIM))
        end
    end
    SetShown(self.funnelEdit, true)

    self:UpdateToggleVisual()
end

function MailLaunchPanel:ShowForMailbox(attempt)
    if not self:AttachToMailbox() then
        -- MAIL_SHOW can arrive before the mail frame is ready: try again
        -- shortly, a few times, while the mailbox is still open.
        attempt = (attempt or 0) + 1
        if attempt <= 5 and Shatter.Events then
            Shatter.Events:After(0.1, function() self:ShowForMailbox(attempt) end)
        end
        return
    end
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
