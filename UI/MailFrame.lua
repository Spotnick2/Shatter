local _, Shatter = ...

local MailFrame = {
    frame = nil,
    inputRows = {},
    outputRows = {},
}

Shatter.MailFrame = MailFrame
Shatter.RegisterModule("MailFrame", MailFrame)

local function CreateButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 82, 22)
    Shatter.Skin.Fill(button, "button", "normal")
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.text:SetAllPoints()
    button.text:SetJustifyH("CENTER")
    button.text:SetText(text)
    button:SetScript("OnEnter", function(self) if self:IsEnabled() then Shatter.Skin.Hover(self, true) end end)
    button:SetScript("OnLeave", function(self) Shatter.Skin.Hover(self, false) end)
    return button
end

local function SetShown(frame, shown)
    if not frame then return end
    if shown then frame:Show() else frame:Hide() end
end

function MailFrame:Create(parent)
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -76)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 72)
    frame:Hide()
    self.frame = frame

    local left = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    Shatter.Skin.Pane(left, Shatter.C.BG_PANEL)
    self.inputPanel = left
    local right = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    Shatter.Skin.Pane(right, Shatter.C.BG_PANEL)
    self.outputPanel = right

    self.inputTitle = left:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.inputTitle:SetPoint("TOPLEFT", left, "TOPLEFT", 8, -7)
    Shatter.SetTextColor(self.inputTitle, Shatter.C.ACCENT)

    self.outputTitle = right:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.outputTitle:SetPoint("TOPLEFT", right, "TOPLEFT", 8, -7)
    self.outputTitle:SetText("Output Queue")
    Shatter.SetTextColor(self.outputTitle, Shatter.C.ACCENT)

    local scan = CreateButton(left, "Scan Inbox", 78)
    scan:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 8, 8)
    scan:SetScript("OnClick", function() if Shatter.MailMode then Shatter.MailMode:ScanInbox("BUTTON") end end)
    self.scanButton = scan

    local all = CreateButton(left, "All", 44)
    all:SetPoint("LEFT", scan, "RIGHT", 6, 0)
    all:SetScript("OnClick", function() if Shatter.MailMode then Shatter.MailMode:SelectInputItems("all") end end)
    self.allButton = all

    local none = CreateButton(left, "None", 50)
    none:SetPoint("LEFT", all, "RIGHT", 6, 0)
    none:SetScript("OnClick", function() if Shatter.MailMode then Shatter.MailMode:SelectInputItems("none") end end)
    self.noneButton = none

    local de = CreateButton(left, "Disenchantable", 96)
    de:SetPoint("LEFT", none, "RIGHT", 6, 0)
    de:SetScript("OnClick", function() if Shatter.MailMode then Shatter.MailMode:SelectInputItems("disenchantable") end end)
    self.deButton = de

    local returnMode = CreateButton(right, "Return", 64)
    returnMode:SetPoint("TOPRIGHT", right, "TOPRIGHT", -86, -5)
    returnMode:SetScript("OnClick", function() if Shatter.MailMode then Shatter.MailMode:SetRecipientMode(Shatter.Constants.MAIL_RECIPIENT_MODE.ORIGINAL_SENDERS) end end)
    self.returnMode = returnMode

    local funnelMode = CreateButton(right, "Funnel", 64)
    funnelMode:SetPoint("LEFT", returnMode, "RIGHT", 6, 0)
    funnelMode:SetScript("OnClick", function() if Shatter.MailMode then Shatter.MailMode:SetRecipientMode(Shatter.Constants.MAIL_RECIPIENT_MODE.FUNNEL) end end)
    self.funnelMode = funnelMode

    local closeSession = CreateButton(right, "Close Session", 92)
    closeSession:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -8, 8)
    closeSession:SetScript("OnClick", function()
        local closed = Shatter.MailMode and Shatter.MailMode:CloseSession(MailFrame.confirmClose)
        MailFrame.confirmClose = closed and false or not MailFrame.confirmClose
        MailFrame:Refresh()
    end)
    self.closeSession = closeSession

    self.funnelLabel = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.funnelLabel:SetPoint("TOPLEFT", self.outputTitle, "BOTTOMLEFT", 0, -10)
    self.funnelLabel:SetText("Funnel target:")

    local edit = CreateFrame("EditBox", nil, right, "InputBoxTemplate")
    edit:SetSize(145, 22)
    edit:SetPoint("LEFT", self.funnelLabel, "RIGHT", 8, 0)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if Shatter.MailMode then Shatter.MailMode:SetFunnelRecipient(self:GetText()) end
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        if Shatter.MailMode then Shatter.MailMode:SetFunnelRecipient(self:GetText()) end
    end)
    self.funnelEdit = edit

    local inputScroll = CreateFrame("ScrollFrame", nil, left, "UIPanelScrollFrameTemplate")
    inputScroll:SetPoint("TOPLEFT", left, "TOPLEFT", 6, -30)
    inputScroll:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -25, 38)
    inputScroll:EnableMouseWheel(true)
    inputScroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local maxScroll = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, current - delta * 24)))
    end)
    self.inputScroll = inputScroll
    self.inputContent = CreateFrame("Frame", nil, inputScroll)
    self.inputContent:SetSize(1, 1)
    inputScroll:SetScrollChild(self.inputContent)
    inputScroll:SetScript("OnSizeChanged", function(self) MailFrame.inputContent:SetWidth(math.max(1, self:GetWidth())) end)

    local outputScroll = CreateFrame("ScrollFrame", nil, right, "UIPanelScrollFrameTemplate")
    outputScroll:SetPoint("TOPLEFT", right, "TOPLEFT", 6, -55)
    outputScroll:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -25, 72)
    outputScroll:EnableMouseWheel(true)
    outputScroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local maxScroll = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, current - delta * 24)))
    end)
    self.outputScroll = outputScroll
    self.outputContent = CreateFrame("Frame", nil, outputScroll)
    self.outputContent:SetSize(1, 1)
    outputScroll:SetScrollChild(self.outputContent)
    outputScroll:SetScript("OnSizeChanged", function(self) MailFrame.outputContent:SetWidth(math.max(1, self:GetWidth())) end)

    self.log = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.log:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 8, 8)
    self.log:SetPoint("BOTTOMRIGHT", closeSession, "LEFT", -8, 0)
    self.log:SetJustifyH("LEFT")
    self.log:SetJustifyV("BOTTOM")

    return frame
end

function MailFrame:Layout()
    if not self.frame then return end
    local width = self.frame:GetWidth() or 1
    local leftWidth = math.floor(width * 0.47)
    self.inputPanel:ClearAllPoints()
    self.inputPanel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
    self.inputPanel:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 0, 0)
    self.inputPanel:SetWidth(leftWidth)
    self.outputPanel:ClearAllPoints()
    self.outputPanel:SetPoint("TOPLEFT", self.inputPanel, "TOPRIGHT", 8, 0)
    self.outputPanel:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)
end

local function EnsureRows(rows, count, content, factory)
    local previous = rows[#rows]
    for i = #rows + 1, count do
        local row = factory(content, i)
        row:SetPoint("LEFT", content, "LEFT", 0, 0)
        row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        if previous then
            row:SetPoint("TOP", previous, "BOTTOM", 0, -2)
        else
            row:SetPoint("TOP", content, "TOP", 0, 0)
        end
        rows[i] = row
        previous = row
    end
end

function MailFrame:Refresh()
    if not self.frame then return end
    local session = Shatter.MailSession and Shatter.MailSession:Get()
    local inputItems = session and session.inputItems or {}
    local selected, de = Shatter.MailSession and Shatter.MailSession:CountSelected() or 0, 0
    if Shatter.MailSession then selected, de = Shatter.MailSession:CountSelected() end
    self.inputTitle:SetText(string.format("Input Queue (%d)", #inputItems))
    EnsureRows(self.inputRows, math.max(#inputItems, 1), self.inputContent, Shatter.MailRows.CreateInputRow)
    self.inputContent:SetHeight(math.max(1, #inputItems * 44))
    for i, row in ipairs(self.inputRows) do
        row.index = i
        row:SetInputItem(inputItems[i])
    end

    local mode = session and session.recipientMode or Shatter.Constants.MAIL_RECIPIENT_MODE.ORIGINAL_SENDERS
    if mode == Shatter.Constants.MAIL_RECIPIENT_MODE.FUNNEL then
        self.outputTitle:SetText("Output Queue (Funnel)")
    elseif mode == Shatter.Constants.MAIL_RECIPIENT_MODE.KEEP then
        self.outputTitle:SetText("Output Queue (Keep)")
    else
        self.outputTitle:SetText("Output Queue")
    end
    SetShown(self.funnelLabel, mode == Shatter.Constants.MAIL_RECIPIENT_MODE.FUNNEL)
    SetShown(self.funnelEdit, mode == Shatter.Constants.MAIL_RECIPIENT_MODE.FUNNEL)
    if session and self.funnelEdit and not self.funnelEdit:HasFocus() then
        self.funnelEdit:SetText(session.funnelRecipient or "")
    end
    if self.closeSession and self.closeSession.text then
        self.closeSession.text:SetText(self.confirmClose and "Confirm Close" or "Close Session")
    end

    local buckets = {}
    for _, bucket in pairs(session and session.outputRecipients or {}) do
        table.insert(buckets, bucket)
    end
    table.sort(buckets, function(a, b) return tostring(a.recipient) < tostring(b.recipient) end)
    EnsureRows(self.outputRows, math.max(#buckets, 1), self.outputContent, Shatter.MailRows.CreateOutputRow)
    self.outputContent:SetHeight(math.max(1, #buckets * 46))
    for i, row in ipairs(self.outputRows) do
        row:SetBucket(buckets[i])
    end

    local lines = {}
    local log = session and session.sessionLog or {}
    for i = math.max(1, #log - 3), #log do
        if log[i] then table.insert(lines, log[i].message) end
    end
    if #lines == 0 then
        table.insert(lines, "Open the mailbox to scan incoming mail.")
    end
    self.log:SetText(table.concat(lines, "\n"))
end
