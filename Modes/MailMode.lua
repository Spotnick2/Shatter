local _, Shatter = ...

local MailMode = {
    scanScheduled = false,
}

Shatter.MailMode = MailMode
Shatter.RegisterModule("MailMode", MailMode)

local function IsMailboxOpen()
    return MailFrame and MailFrame:IsShown()
end

function MailMode:Initialize()
    if not Shatter.Events then return end
    Shatter.Events:Register("MAIL_SHOW", self, self.OnEvent)
    Shatter.Events:Register("MAIL_CLOSED", self, self.OnEvent)
    Shatter.Events:Register("MAIL_INBOX_UPDATE", self, self.OnEvent)
    Shatter.Events:Register("BAG_UPDATE_DELAYED", self, self.OnEvent)
    Shatter.Events:Register("MAIL_SEND_SUCCESS", self, self.OnEvent)
    Shatter.Events:Register("UI_ERROR_MESSAGE", self, self.OnEvent)
end

function MailMode:IsAvailable()
    local session = Shatter.MailSession and Shatter.MailSession:Get()
    return IsMailboxOpen() or session ~= nil
end

function MailMode:OnEvent(event, ...)
    if event == "MAIL_SHOW" then
        self:ActivateFromMailbox()
    elseif event == "MAIL_CLOSED" then
        if Shatter.MailSession then Shatter.MailSession:SetMailboxOpen(false) end
        if Shatter.MainFrame then Shatter.MainFrame:Update() end
    elseif event == "MAIL_INBOX_UPDATE" then
        self:ScheduleScan("MAIL_INBOX_UPDATE", 0.2)
    elseif event == "BAG_UPDATE_DELAYED" then
        if Shatter.AttachmentQueue then Shatter.AttachmentQueue:ResolvePending("BAG_UPDATE_DELAYED") end
    elseif event == "MAIL_SEND_SUCCESS" then
        if Shatter.MailSession then Shatter.MailSession:Log("info", "Mail send succeeded.") end
        if Shatter.MainFrame then Shatter.MainFrame:Update() end
    elseif event == "UI_ERROR_MESSAGE" then
        local message = select(2, ...) or select(1, ...)
        local session = Shatter.MailSession and Shatter.MailSession:Get()
        if session and session.status == Shatter.Constants.MAIL_STATE.TAKING and Shatter.MailSession then
            Shatter.MailSession:Log("warn", "Mailbox error: %s", tostring(message))
        end
    end
end

function MailMode:ActivateFromMailbox()
    local session = Shatter.MailSession and Shatter.MailSession:SetMailboxOpen(true)
    if session then
        session.status = Shatter.Constants.MAIL_STATE.CREATING
        Shatter.MailSession:Log("info", "Mailbox opened; Mail Mode active.")
    end
    if Shatter.MainFrame then
        Shatter.MainFrame:Show()
        Shatter.MainFrame:SetActiveView("mail")
    end
    self:ScheduleScan("MAIL_SHOW", 0.15)
    if Shatter.Events then
        Shatter.Events:After(0.5, function() self:ScheduleScan("MAIL_SHOW_DELAYED", 0) end)
        Shatter.Events:After(1.0, function() self:ScheduleScan("MAIL_SHOW_DELAYED", 0) end)
    end
end

function MailMode:ScheduleScan(reason, delay)
    if self.scanScheduled then return end
    self.scanScheduled = true
    if Shatter.Events then
        Shatter.Events:After(delay or 0.2, function()
            self.scanScheduled = false
            self:ScanInbox(reason or "SCHEDULED")
        end)
    else
        self.scanScheduled = false
        self:ScanInbox(reason or "DIRECT")
    end
end

function MailMode:ScanInbox(reason)
    if not IsMailboxOpen() then
        if Shatter.MailSession then
            local session = Shatter.MailSession:SetMailboxOpen(false)
            session.status = Shatter.Constants.MAIL_STATE.ERROR_PAUSED
        end
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus(Shatter.Constants.STATUS.MAILBOX_REQUIRED, true, 3) end
        return
    end
    if Shatter.MailSession then Shatter.MailSession:SetMailboxOpen(true) end
    local session = Shatter.InboxScanner and Shatter.InboxScanner:Scan()
    if Shatter.Debug then Shatter.Debug:Log("debug", "Mail scan completed. Reason: %s.", tostring(reason or "UNKNOWN")) end
    if Shatter.MainFrame then
        Shatter.MainFrame:SetStatus("Mail inbox scanned.", false, 2)
        Shatter.MainFrame:Update()
    end
    return session
end

function MailMode:SelectMails(mode)
    local session = Shatter.MailSession and Shatter.MailSession:Get()
    if not session then return end
    for _, mail in ipairs(session.inputMails or {}) do
        if mode == "all" then
            mail.selected = true
        elseif mode == "none" then
            mail.selected = false
        else
            mail.selected = mail.disenchantable and true or false
        end
    end
    if Shatter.MailSession then Shatter.MailSession:Log("info", "Selection changed: %s.", mode or "disenchantable") end
    if Shatter.MainFrame then Shatter.MainFrame:Update() end
end

function MailMode:SetRecipientMode(mode)
    if Shatter.MailSession then Shatter.MailSession:SetRecipientMode(mode) end
    if Shatter.MainFrame then Shatter.MainFrame:Update() end
end

function MailMode:SetFunnelRecipient(name)
    local session = Shatter.MailSession and Shatter.MailSession:Ensure()
    if not session then return end
    session.funnelRecipient = name or ""
    if Shatter.MainFrame then Shatter.MainFrame:Update() end
end

function MailMode:PrepareDisenchantQueue()
    local session = Shatter.MailSession and Shatter.MailSession:Ensure()
    if not session then return end
    local items = {}
    for inputItemId, input in pairs(session.inputItems or {}) do
        if input.disenchantStatus == "waiting" and input.bag and input.slot and Shatter.ItemScanner then
            local item = Shatter.ItemScanner:BuildItem(input.bag, input.slot)
            if item and item.itemID == input.itemID then
                item.mode = Shatter.Constants.MODES.MAIL
                item.sourceId = inputItemId
                item.sourceSender = input.sourceSender
                item.sourceMailId = input.sourceMailId
                item.queueId = string.format("mail:%s:%d:%d:%d", inputItemId, item.bag or 0, item.slot or 0, item.itemID or 0)
                if Shatter.DisenchantTables then
                    local estimate = Shatter.DisenchantTables:GetExpected(item)
                    item.expectedMats = estimate and estimate.materials or nil
                    item.expectedValueCopper = estimate and estimate.expectedValueCopper or nil
                    item.valueSource = estimate and estimate.valueSource or nil
                    item.expectedEstimate = estimate
                end
                table.insert(items, item)
            else
                input.disenchantStatus = "unresolved"
            end
        end
    end
    if Shatter.Queue then Shatter.Queue:SetItems(items) end
    if #items > 0 then
        session.status = Shatter.Constants.MAIL_STATE.READY_TO_DISENCHANT
        if Shatter.MailSession then Shatter.MailSession:Log("info", "Disenchant queue ready: %d item%s.", #items, #items == 1 and "" or "s") end
    elseif self:HasReturnMaterials(session) then
        session.status = Shatter.Constants.MAIL_STATE.READY_TO_RETURN
    else
        session.status = Shatter.Constants.MAIL_STATE.COMPLETE
    end
    if Shatter.MainFrame then Shatter.MainFrame:Update() end
end

function MailMode:HasReturnMaterials(session)
    for _, bucket in pairs(session and session.outputRecipients or {}) do
        for _, count in pairs(bucket.materialsGenerated or {}) do
            if count and count > 0 then return true end
        end
    end
    return false
end

function MailMode:OnDisenchantResult(item, result)
    local session = Shatter.MailSession and Shatter.MailSession:Ensure()
    local input = session and item and item.sourceId and session.inputItems[item.sourceId]
    if input then
        input.disenchantStatus = "done"
        if Shatter.ReturnQueue then Shatter.ReturnQueue:AddResult(input.sourceSender, result or {}) end
        if Shatter.MailSession then Shatter.MailSession:Log("info", "Disenchanted %s for %s.", item.itemLink or item.itemName or "item", input.sourceSender or "?") end
    end
    self:PrepareDisenchantQueue()
end

function MailMode:OnDisenchantFailed(item, reason)
    local session = Shatter.MailSession and Shatter.MailSession:Ensure()
    local input = session and item and item.sourceId and session.inputItems[item.sourceId]
    if input then input.disenchantStatus = "failed" end
    if Shatter.MailSession then Shatter.MailSession:Log("warn", "Disenchant failed: %s", tostring(reason or "unknown")) end
    self:PrepareDisenchantQueue()
end

function MailMode:SkipQueueItem(item)
    local session = Shatter.MailSession and Shatter.MailSession:Ensure()
    local input = session and item and item.sourceId and session.inputItems[item.sourceId]
    if input then input.disenchantStatus = "skipped" end
    if Shatter.MailSession then Shatter.MailSession:Log("info", "Skipped mail item.") end
    self:PrepareDisenchantQueue()
end

function MailMode:GetPrimaryState()
    local session = Shatter.MailSession and Shatter.MailSession:Get()
    if not session then return "Scan Inbox", true end
    if session.status == Shatter.Constants.MAIL_STATE.SCANNING or session.status == Shatter.Constants.MAIL_STATE.TAKING then
        return "Waiting...", false
    end
    if session.status == Shatter.Constants.MAIL_STATE.READY_TO_DISENCHANT then
        return "Shatter Next", Shatter.Queue and Shatter.Queue:Count() > 0
    end
    if session.status == Shatter.Constants.MAIL_STATE.READY_TO_RETURN then
        return "Send Ready Mats", true
    end
    if session.status == Shatter.Constants.MAIL_STATE.COMPLETE then
        return "Done", false
    end
    if Shatter.AttachmentQueue and Shatter.AttachmentQueue:GetNext() then
        return "Take Attachments", session.mailboxOpen
    end
    return "Scan Inbox", session.mailboxOpen
end

function MailMode:HandlePrimaryClick()
    local label = self:GetPrimaryState()
    if label == "Take Attachments" then
        if Shatter.AttachmentQueue then Shatter.AttachmentQueue:TakeNext() end
    elseif label == "Scan Inbox" then
        self:ScanInbox("PRIMARY")
    elseif label == "Send Ready Mats" then
        if Shatter.MailSender then Shatter.MailSender:PrepareNext() end
    end
end

function MailMode:GetStatus()
    local session = Shatter.MailSession and Shatter.MailSession:Get()
    if not session then return "Open the mailbox to start Mail Mode.", false end
    if not session.mailboxOpen then return "Mailbox closed - Mail session paused.", true end
    if session.status == Shatter.Constants.MAIL_STATE.READY_TO_DISENCHANT then return "Mail items ready to disenchant.", false end
    if session.status == Shatter.Constants.MAIL_STATE.READY_TO_RETURN then return "Materials ready to return.", false end
    if session.status == Shatter.Constants.MAIL_STATE.COMPLETE then return "Mail session complete.", false end
    if session.status == Shatter.Constants.MAIL_STATE.TAKING then return "Taking attachment...", false end
    return "Mail Mode active.", false
end

function MailMode:CloseSession(force)
    local ok, reason = Shatter.MailSession and Shatter.MailSession:Close(force)
    if not ok then
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus(reason, true, 4) end
        return false
    end
    if Shatter.MainFrame then
        Shatter.MainFrame:SetActiveView("solo")
        Shatter.MainFrame:SetStatus("Mail session closed.", false, 3)
    end
    return true
end
