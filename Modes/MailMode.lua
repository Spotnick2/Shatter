local _, Shatter = ...

local MailMode = {
    scanScheduled = false,
}

Shatter.MailMode = MailMode
Shatter.RegisterModule("MailMode", MailMode)

local function IsMailboxOpen()
    local function visible(frame)
        if not frame then return false end
        if frame.IsVisible and frame:IsVisible() then return true end
        if frame.IsShown and frame:IsShown() then return true end
        return false
    end
    return visible(_G.MailFrame) or visible(_G.InboxFrame) or visible(_G.OpenMailFrame) or visible(_G.SendMailFrame)
end

local function SyncMailboxState(session)
    if not session then return false end
    local open = IsMailboxOpen() and true or false
    session.mailboxOpen = open
    return open
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
    local hasSession = Shatter.MailSession and Shatter.MailSession:HasActiveSession()
    return IsMailboxOpen() or hasSession
end

function MailMode:OnEvent(event, ...)
    if event == "MAIL_SHOW" then
        self:ActivateFromMailbox()
    elseif event == "MAIL_CLOSED" then
        if Shatter.MailSession then Shatter.MailSession:SetMailboxOpen(false) end
        if Shatter.MailLaunchPanel then Shatter.MailLaunchPanel:HideForMailboxClose() end
        if Shatter.MainFrame then Shatter.MainFrame:Update() end
    elseif event == "MAIL_INBOX_UPDATE" then
        if Shatter.MailSession and Shatter.MailSession:HasActiveSession() then
            self:ScheduleScan("MAIL_INBOX_UPDATE", 0.2)
        end
        if Shatter.MailLaunchPanel and IsMailboxOpen() then
            Shatter.MailLaunchPanel:Refresh()
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        if Shatter.MailSession and Shatter.MailSession:HasActiveSession() and Shatter.AttachmentQueue then
            Shatter.AttachmentQueue:ResolvePending("BAG_UPDATE_DELAYED")
        end
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
    local session = Shatter.MailSession and Shatter.MailSession:Get()
    if session then
        Shatter.MailSession:SetMailboxOpen(true)
        session.status = Shatter.Constants.MAIL_STATE.CREATING
        Shatter.MailSession:Log("info", "Mailbox opened; Mail Mode active.")
    end
    if Shatter.MailLaunchPanel then
        Shatter.MailLaunchPanel:ShowForMailbox()
    end
    if Shatter.MainFrame and Shatter.MainFrame.frame and Shatter.MainFrame.frame:IsShown() then
        Shatter.MainFrame:SetActiveView("mail")
    end
end

function MailMode:StartNewSessionFromLaunchPanel()
    if not IsMailboxOpen() then
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus(Shatter.Constants.STATUS.MAILBOX_REQUIRED, true, 3) end
        return false
    end
    local session = Shatter.MailSession and Shatter.MailSession:StartNew()
    if not session then return false end
    Shatter.MailSession:SetMailboxOpen(true)
    session.status = Shatter.Constants.MAIL_STATE.CREATING
    Shatter.MailSession:Log("info", "New mail session started from mailbox panel.")
    if Shatter.MailLaunchPanel then Shatter.MailLaunchPanel:Refresh() end
    if Shatter.MainFrame and Shatter.MainFrame.frame and Shatter.MainFrame.frame:IsShown() then
        Shatter.MainFrame:Update()
    end
    return true
end

function MailMode:ContinueSessionFromLaunchPanel()
    local session = Shatter.MailSession and Shatter.MailSession:Get()
    if not session or session.status == Shatter.Constants.MAIL_STATE.CLOSED then return false end
    if IsMailboxOpen() then
        Shatter.MailSession:SetMailboxOpen(true)
    end
    Shatter.MailSession:Log("info", "Mail session resumed from mailbox panel.")
    if Shatter.MailLaunchPanel then Shatter.MailLaunchPanel:Refresh() end
    if Shatter.MainFrame and Shatter.MainFrame.frame and Shatter.MainFrame.frame:IsShown() then
        Shatter.MainFrame:Update()
    end
    return true
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
            if session then
                session.status = Shatter.Constants.MAIL_STATE.ERROR_PAUSED
            end
        end
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus(Shatter.Constants.STATUS.MAILBOX_REQUIRED, true, 3) end
        return
    end
    if Shatter.MailSession and Shatter.MailSession:Get() then
        Shatter.MailSession:SetMailboxOpen(true)
    end
    local session = Shatter.InboxScanner and Shatter.InboxScanner:Scan()
    if Shatter.Debug then Shatter.Debug:Log("debug", "Mail scan completed. Reason: %s.", tostring(reason or "UNKNOWN")) end
    if Shatter.MailLaunchPanel then Shatter.MailLaunchPanel:Refresh() end
    if Shatter.MainFrame then
        Shatter.MainFrame:SetStatus("Mail inbox scanned.", false, 2)
        Shatter.MainFrame:Update()
    end
    return session
end

function MailMode:SelectInputItems(mode)
    local session = Shatter.MailSession and Shatter.MailSession:Get()
    if not session then return end
    for _, item in ipairs(session.inputItems or {}) do
        if mode == "all" then
            item.selected = true
        elseif mode == "none" then
            item.selected = false
        else
            item.selected = item.disenchantable and true or false
        end
        if item.status == "selected" or item.status == "detected" then
            item.status = item.selected and "selected" or "detected"
        end
    end
    if Shatter.MailSession then Shatter.MailSession:Log("info", "Selection changed: %s.", mode or "disenchantable") end
    if Shatter.MainFrame then Shatter.MainFrame:Update() end
end

function MailMode:SelectMails(mode)
    self:SelectInputItems(mode)
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
    for _, input in ipairs(session.inputItems or {}) do
        if input.disenchantStatus == "waiting" and input.bag and input.slot and Shatter.ItemScanner then
            local item = Shatter.ItemScanner:BuildItem(input.bag, input.slot)
            if item and item.itemID == input.itemID then
                item.mode = Shatter.Constants.MODES.MAIL
                item.sourceId = input.inputItemId
                item.sourceSender = input.sourceSender
                item.sourceMailId = input.sourceMailId
                item.queueId = string.format("mail:%s:%d:%d:%d", input.inputItemId, item.bag or 0, item.slot or 0, item.itemID or 0)
                if Shatter.DisenchantTables then
                    local estimate = Shatter.DisenchantTables:GetExpected(item)
                    item.expectedMats = estimate and estimate.materials or nil
                    item.expectedValueCopper = estimate and estimate.expectedValueCopper or nil
                    item.valueSource = estimate and estimate.valueSource or nil
                    item.expectedEstimate = estimate
                end
                table.insert(items, item)
                input.status = "queued for disenchant"
            else
                input.disenchantStatus = "unresolved"
                input.status = "failed"
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
    local input = item and item.sourceId and Shatter.MailSession and Shatter.MailSession:FindInputItem(item.sourceId)
    if input then
        input.disenchantStatus = "done"
        input.status = "disenchanted"
        if Shatter.ReturnQueue then Shatter.ReturnQueue:AddResult(input.sourceSender, result or {}) end
        if Shatter.MailSession then Shatter.MailSession:Log("info", "Disenchanted %s for %s.", item.itemLink or item.itemName or "item", input.sourceSender or "?") end
    end
    self:PrepareDisenchantQueue()
end

function MailMode:OnDisenchantFailed(item, reason)
    local session = Shatter.MailSession and Shatter.MailSession:Ensure()
    local input = item and item.sourceId and Shatter.MailSession and Shatter.MailSession:FindInputItem(item.sourceId)
    if input then
        input.disenchantStatus = "failed"
        input.status = "failed"
    end
    if Shatter.MailSession then Shatter.MailSession:Log("warn", "Disenchant failed: %s", tostring(reason or "unknown")) end
    self:PrepareDisenchantQueue()
end

function MailMode:SkipQueueItem(item)
    local session = Shatter.MailSession and Shatter.MailSession:Ensure()
    local input = item and item.sourceId and Shatter.MailSession and Shatter.MailSession:FindInputItem(item.sourceId)
    if input then
        input.disenchantStatus = "skipped"
        input.status = "skipped"
    end
    if Shatter.MailSession then Shatter.MailSession:Log("info", "Skipped mail item.") end
    self:PrepareDisenchantQueue()
end

function MailMode:GetPrimaryState()
    local session = Shatter.MailSession and Shatter.MailSession:Get()
    if not session then return "Scan Inbox", true end
    local mailboxOpen = SyncMailboxState(session)
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
        session.mailboxOpen = mailboxOpen
        return "Take Attachments", true
    end
    return mailboxOpen and "Scan Inbox" or "Open Mailbox", mailboxOpen
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
    local mailboxOpen = SyncMailboxState(session)
    if not mailboxOpen and Shatter.AttachmentQueue and Shatter.AttachmentQueue:GetNext() then
        return "Mailbox not detected. Click Take Attachments to retry, or reopen the mailbox.", true
    end
    if not mailboxOpen then return "Open the mailbox to continue Mail Mode.", true end
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
    if Shatter.MailLaunchPanel then Shatter.MailLaunchPanel:Refresh() end
    return true
end
