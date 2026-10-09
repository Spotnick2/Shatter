local _, Shatter = ...

local MailMode = {
    scanScheduled = false,
    launchOptions = nil,
    launchSenders = {},
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

local function GetInboxCount()
    if not GetInboxNumItems then return 0 end
    return GetInboxNumItems() or 0
end

local function CollectSenders()
    local seen = {}
    local list = {}
    if not GetInboxHeaderInfo then return list end
    for mailIndex = 1, GetInboxCount() do
        local sender = select(3, GetInboxHeaderInfo(mailIndex))
        if sender and sender ~= "" and not seen[sender] then
            seen[sender] = true
            table.insert(list, sender)
        end
    end
    table.sort(list)
    return list
end

local function CountEntries(map)
    local count = 0
    for _, selected in pairs(map or {}) do
        if selected then count = count + 1 end
    end
    return count
end

local function CopyMap(source)
    if type(source) ~= "table" then return nil end
    local copy = {}
    for key, value in pairs(source) do
        if value then copy[key] = true end
    end
    return next(copy) and copy or nil
end

local API = Shatter.API

local function IsAddOnLoadedSafe(name)
    local ok, loaded = pcall(API.IsAddOnLoaded, name)
    return ok and loaded and true or false
end

local function IsAddOnInstalledSafe(name)
    local ok, addonName = pcall(API.GetAddOnInfo, name)
    return ok and addonName ~= nil and addonName ~= "" and addonName ~= "MISSING"
end

local function TryLoadAddOnSafe(name)
    if IsAddOnLoadedSafe(name) then return true end
    local ok, loaded = pcall(API.LoadAddOn, name)
    return ok and loaded and true or false
end

-- Mail actions (taking attachments, disenchanting mail items) stay off until
-- the mail flow has been validated in game on Forever (SPEC.md Phase 0).
-- `/shatter mailtest` turns them on for the current session only.
MailMode.ACTIONS_VALIDATED = false
MailMode.actionsEnabledForSession = false

function MailMode:AreActionsEnabled()
    return MailMode.ACTIONS_VALIDATED or MailMode.actionsEnabledForSession
end

function MailMode:SetActionsEnabledForSession(enabled)
    MailMode.actionsEnabledForSession = enabled and true or false
    if Shatter.MainFrame then Shatter.MainFrame:Update() end
end

function MailMode:Initialize()
    local modes = Shatter.Constants and Shatter.Constants.MAIL_SELECTION_MODE or {}
    local recipients = Shatter.Constants and Shatter.Constants.MAIL_RECIPIENT_MODE or {}
    self.launchOptions = {
        selectionMode = modes.ALL or "ALL",
        sender = nil,
        recipientMode = recipients.ORIGINAL_SENDERS or "ORIGINAL_SENDERS",
        funnelRecipient = "",
    }
    self.launchSenders = {}
    if not Shatter.Events then return end
    Shatter.Events:Register("MAIL_SHOW", self, self.OnEvent)
    Shatter.Events:Register("MAIL_CLOSED", self, self.OnEvent)
    Shatter.Events:Register("MAIL_INBOX_UPDATE", self, self.OnEvent)
    Shatter.Events:Register("BAG_UPDATE_DELAYED", self, self.OnEvent)
    Shatter.Events:Register("GET_ITEM_INFO_RECEIVED", self, self.OnEvent)
    Shatter.Events:Register("MAIL_SEND_SUCCESS", self, self.OnEvent)
    Shatter.Events:Register("UI_ERROR_MESSAGE", self, self.OnEvent)
end

function MailMode:IsAvailable()
    local hasSession = Shatter.MailSession and Shatter.MailSession:HasActiveSession()
    return IsMailboxOpen() or hasSession
end

function MailMode:IsPostalAvailable()
    if _G.Postal or _G.Postal_Select or _G.PostalInboxCB1 then
        return true
    end
    if IsAddOnLoadedSafe("Postal") then
        return true
    end
    return IsAddOnInstalledSafe("Postal")
end

function MailMode:IsPostalSelectionReady()
    return _G.PostalInboxCB1 ~= nil
end

function MailMode:GetPostalSelectedMailIndices()
    local selected = {}
    if not self:IsPostalAvailable() then
        return selected
    end
    if IsMailboxOpen() and not self:IsPostalSelectionReady() then
        TryLoadAddOnSafe("Postal")
    end
    local pageNum = InboxFrame and InboxFrame.pageNum or 1
    local base = math.max(0, ((pageNum or 1) - 1) * 7)
    for row = 1, 7 do
        local check = _G["PostalInboxCB" .. row]
        if check and check.GetChecked and check:IsShown() and check:GetChecked() then
            local mailIndex = base + row
            selected[mailIndex] = true
        end
    end
    return selected
end

function MailMode:GetLaunchSenders()
    return self.launchSenders or {}
end

function MailMode:RefreshLaunchSenders()
    if not IsMailboxOpen() then
        self.launchSenders = {}
        return
    end
    self.launchSenders = CollectSenders()
    if self.launchOptions and self.launchOptions.selectionMode == (Shatter.Constants and Shatter.Constants.MAIL_SELECTION_MODE.SENDER or "SENDER") then
        local sender = self.launchOptions.sender
        if sender then
            local exists = false
            for _, value in ipairs(self.launchSenders) do
                if value == sender then
                    exists = true
                    break
                end
            end
            if not exists then
                self.launchOptions.sender = self.launchSenders[1]
            end
        elseif #self.launchSenders > 0 then
            self.launchOptions.sender = self.launchSenders[1]
        end
    end
end

function MailMode:LoadLaunchOptionsFromSession()
    local session = Shatter.MailSession and Shatter.MailSession:Get()
    if not session or not self.launchOptions then return end
    local selection = session.mailSelection or {}
    local selectionModes = Shatter.Constants and Shatter.Constants.MAIL_SELECTION_MODE or {}
    local recipients = Shatter.Constants and Shatter.Constants.MAIL_RECIPIENT_MODE or {}
    local mode = selection.mode
    if mode ~= selectionModes.SENDER and mode ~= selectionModes.POSTAL_SELECTED then
        mode = selectionModes.ALL or "ALL"
    end
    local recipientMode = session.recipientMode
    if recipientMode ~= recipients.FUNNEL and recipientMode ~= recipients.KEEP then
        recipientMode = recipients.ORIGINAL_SENDERS or "ORIGINAL_SENDERS"
    end
    self.launchOptions.selectionMode = mode
    self.launchOptions.sender = selection.sender
    self.launchOptions.recipientMode = recipientMode
    self.launchOptions.funnelRecipient = session.funnelRecipient or ""
    self.launchOptions.selectedMailIndices = CopyMap(selection.selectedMailIndices)
end

function MailMode:SetLaunchMailSelectionMode(mode)
    if not self.launchOptions then return end
    local modes = Shatter.Constants and Shatter.Constants.MAIL_SELECTION_MODE or {}
    if mode ~= modes.SENDER and mode ~= modes.POSTAL_SELECTED then
        mode = modes.ALL or "ALL"
    end
    self.launchOptions.selectionMode = mode
    if mode == modes.SENDER and (not self.launchOptions.sender or self.launchOptions.sender == "") then
        self:RefreshLaunchSenders()
        self.launchOptions.sender = self.launchSenders[1]
    end
    if Shatter.MailLaunchPanel then Shatter.MailLaunchPanel:Refresh() end
end

function MailMode:SetLaunchSender(sender)
    if not self.launchOptions then return end
    self.launchOptions.sender = sender and tostring(sender) or nil
    if Shatter.MailLaunchPanel then Shatter.MailLaunchPanel:Refresh() end
end

function MailMode:SetLaunchRecipientMode(mode)
    if not self.launchOptions then return end
    local recipients = Shatter.Constants and Shatter.Constants.MAIL_RECIPIENT_MODE or {}
    if mode ~= recipients.FUNNEL and mode ~= recipients.KEEP then
        mode = recipients.ORIGINAL_SENDERS or "ORIGINAL_SENDERS"
    end
    self.launchOptions.recipientMode = mode
    if Shatter.MailLaunchPanel then Shatter.MailLaunchPanel:Refresh() end
end

function MailMode:SetLaunchFunnelRecipient(name)
    if not self.launchOptions then return end
    self.launchOptions.funnelRecipient = name and tostring(name) or ""
    if Shatter.MailLaunchPanel then Shatter.MailLaunchPanel:Refresh() end
end

function MailMode:GetLaunchContext()
    if IsMailboxOpen() and (#(self.launchSenders or {}) == 0) then
        self:RefreshLaunchSenders()
    end
    local modes = Shatter.Constants and Shatter.Constants.MAIL_SELECTION_MODE or {}
    local selectionMode = self.launchOptions and self.launchOptions.selectionMode or (modes.ALL or "ALL")
    local postalSelected = self:GetPostalSelectedMailIndices()
    return {
        mailboxOpen = IsMailboxOpen(),
        hasSession = Shatter.MailSession and Shatter.MailSession:HasActiveSession() or false,
        senders = self:GetLaunchSenders(),
        postalAvailable = self:IsPostalAvailable(),
        postalSelectionReady = self:IsPostalSelectionReady(),
        postalSelectedCount = CountEntries(postalSelected),
        selectionMode = selectionMode,
        selectedSender = self.launchOptions and self.launchOptions.sender or nil,
        recipientMode = self.launchOptions and self.launchOptions.recipientMode or (Shatter.Constants and Shatter.Constants.MAIL_RECIPIENT_MODE.ORIGINAL_SENDERS),
        funnelRecipient = self.launchOptions and self.launchOptions.funnelRecipient or "",
    }
end

function MailMode:OnEvent(event, ...)
    if not Shatter.isActive then return end
    if event == "MAIL_SHOW" then
        self:ActivateFromMailbox()
    elseif event == "MAIL_CLOSED" then
        if Shatter.MailSession then Shatter.MailSession:SetMailboxOpen(false) end
        if Shatter.MailLaunchPanel then Shatter.MailLaunchPanel:HideForMailboxClose() end
        if Shatter.MainFrame then Shatter.MainFrame:Update() end
    elseif event == "MAIL_INBOX_UPDATE" then
        self:RefreshLaunchSenders()
        if Shatter.MailSession and Shatter.MailSession:HasActiveSession() then
            self:ScheduleScan("MAIL_INBOX_UPDATE", 0.2)
        end
        if Shatter.MailLaunchPanel and IsMailboxOpen() then
            Shatter.MailLaunchPanel:Refresh()
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local itemID = ...
        local pending = Shatter.InboxScanner and Shatter.InboxScanner.pendingItemIDs
        if itemID and pending and pending[itemID] then
            pending[itemID] = nil
            if Shatter.MailSession and Shatter.MailSession:HasActiveSession() and IsMailboxOpen() then
                self:ScheduleScan("ITEM_INFO", 0.3)
            end
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        if Shatter.MailSession and Shatter.MailSession:HasActiveSession() and Shatter.AttachmentQueue then
            Shatter.AttachmentQueue:ResolvePending("BAG_UPDATE_DELAYED")
            -- The player may have moved or sorted received items: follow
            -- them (by GUID) so the Mail queue targets where they are now.
            if Shatter.Queue and Shatter.Queue:GetOwner() == "mail" and not (Shatter.Disenchant and Shatter.Disenchant.pending) then
                self:PrepareDisenchantQueue()
            end
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
        self:LoadLaunchOptionsFromSession()
        Shatter.MailSession:SetMailboxOpen(true)
        session.status = Shatter.Constants.MAIL_STATE.CREATING
        Shatter.MailSession:Log("info", "Mailbox opened; Mail Mode active.")
    end
    self:RefreshLaunchSenders()
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
    local options = self.launchOptions or {}
    local selectionMode = options.selectionMode or (Shatter.Constants and Shatter.Constants.MAIL_SELECTION_MODE.ALL) or "ALL"
    local sender = options.sender
    local selectedMailIndices = nil
    if selectionMode == ((Shatter.Constants and Shatter.Constants.MAIL_SELECTION_MODE.SENDER) or "SENDER") and (not sender or sender == "") then
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus("Select a sender for Mail from filter.", true, 3) end
        return false
    end
    if selectionMode == ((Shatter.Constants and Shatter.Constants.MAIL_SELECTION_MODE.SENDER) or "SENDER") and #(self.launchSenders or {}) == 0 then
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus("No mailbox senders were detected for Mail from filter.", true, 4) end
        return false
    end
    if selectionMode == ((Shatter.Constants and Shatter.Constants.MAIL_SELECTION_MODE.POSTAL_SELECTED) or "POSTAL_SELECTED") then
        selectedMailIndices = self:GetPostalSelectedMailIndices()
        if CountEntries(selectedMailIndices) == 0 then
            if Shatter.MainFrame then Shatter.MainFrame:SetStatus("No Postal selected mails on the current inbox page.", true, 4) end
            return false
        end
    end
    if options.recipientMode == ((Shatter.Constants and Shatter.Constants.MAIL_RECIPIENT_MODE.FUNNEL) or "FUNNEL")
        and (not options.funnelRecipient or options.funnelRecipient == "") then
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus("Set a funnel recipient before starting this session.", true, 4) end
        return false
    end

    local session, why = Shatter.MailSession:StartNew()
    if not session then
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus(why, true, 4) end
        return false
    end
    Shatter.MailSession:SetMailboxOpen(true)
    session.status = Shatter.Constants.MAIL_STATE.CREATING
    Shatter.MailSession:SetRecipientMode(options.recipientMode, options.funnelRecipient)
    session.keepRecipient = UnitName and UnitName("player") or "Self"
    Shatter.MailSession:SetMailSelection(selectionMode, sender, selectedMailIndices)
    self.launchOptions.selectedMailIndices = CopyMap(selectedMailIndices)
    Shatter.MailSession:Log("info", "New mail session started from mailbox panel.")
    if selectionMode == ((Shatter.Constants and Shatter.Constants.MAIL_SELECTION_MODE.SENDER) or "SENDER") then
        Shatter.MailSession:Log("info", "Mail selection: sender '%s'.", tostring(sender))
    elseif selectionMode == ((Shatter.Constants and Shatter.Constants.MAIL_SELECTION_MODE.POSTAL_SELECTED) or "POSTAL_SELECTED") then
        Shatter.MailSession:Log("info", "Mail selection: %d Postal-selected mail(s) on current page.", CountEntries(selectedMailIndices))
    else
        Shatter.MailSession:Log("info", "Mail selection: all mail.")
    end
    self:ScanInbox("SESSION_START")
    if Shatter.MainFrame then
        Shatter.MainFrame:Show()
        Shatter.MainFrame:SetActiveView("mail")
    end
    if Shatter.MailLaunchPanel then Shatter.MailLaunchPanel:Refresh() end
    return true
end

function MailMode:ContinueSessionFromLaunchPanel()
    local session = Shatter.MailSession and Shatter.MailSession:Get()
    if not session or session.status == Shatter.Constants.MAIL_STATE.CLOSED then return false end
    self:LoadLaunchOptionsFromSession()
    if IsMailboxOpen() then
        Shatter.MailSession:SetMailboxOpen(true)
    end
    Shatter.MailSession:Log("info", "Mail session resumed from mailbox panel.")
    self:ScanInbox("SESSION_RESUME")
    if Shatter.MainFrame then
        Shatter.MainFrame:Show()
        Shatter.MainFrame:SetActiveView("mail")
    end
    if Shatter.MailLaunchPanel then Shatter.MailLaunchPanel:Refresh() end
    return true
end

function MailMode:ScheduleScan(reason, delay)
    if self.scanScheduled then return end
    self.scanScheduled = true
    if Shatter.Events then
        Shatter.Events:After(delay or 0.2, function()
            self.scanScheduled = false
            if not Shatter.isActive then return end
            self:ScanInbox(reason or "SCHEDULED")
        end)
    else
        self.scanScheduled = false
        self:ScanInbox(reason or "DIRECT")
    end
end

function MailMode:ScanInbox(reason)
    if not (Shatter.MailSession and Shatter.MailSession:Get()) then
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus("Start a mail session from the mailbox panel first.", true, 3) end
        return
    end
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
    -- A rescan (every MAIL_INBOX_UPDATE) resets the session to selecting; if
    -- taken items are already waiting and nothing is left to take, the
    -- disenchant queue is still the next step, so rebuild it.
    if session and Shatter.AttachmentQueue and not Shatter.AttachmentQueue:GetNext() then
        for _, input in ipairs(session.inputItems or {}) do
            if input.disenchantStatus == "waiting" and input.bag then
                self:PrepareDisenchantQueue()
                break
            end
        end
    end
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
    local session = Shatter.MailSession and Shatter.MailSession:Get()
    if not session then return end
    session.funnelRecipient = name or ""
    if Shatter.MainFrame then Shatter.MainFrame:Update() end
end

function MailMode:PrepareDisenchantQueue()
    local session = Shatter.MailSession and Shatter.MailSession:Get()
    if not session then return end
    Shatter.MailSession:LocateReceived()
    local items = {}
    for _, input in ipairs(session.inputItems or {}) do
        if input.disenchantStatus == "waiting" and input.bag and input.slot and Shatter.ItemScanner then
            local item = Shatter.ItemScanner:BuildItem(input.bag, input.slot)
            if item and item.itemID == input.itemID then
                item.mode = Shatter.Constants.MODES.MAIL
                item.sourceId = input.inputItemId
                item.sourceSender = input.sourceSender
                item.sourceMailId = input.sourceMailId
                item.itemGUID = input.itemGUID
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
    if Shatter.Queue then
        -- Background callers (inbox rescans, take timers) refresh a Mail
        -- queue but never take the queue from the Solo view; selecting the
        -- Mail view claims it (MainFrame:SetActiveView).
        local view = Shatter.MainFrame and Shatter.MainFrame.activeView
        if #items > 0 then
            if view == "mail" or Shatter.Queue:GetOwner() == "mail" then
                Shatter.Queue:SetItems(items, "mail")
            end
        else
            Shatter.Queue:ReleaseToSolo("MAIL_QUEUE_EMPTY")
        end
    end
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
    local input = item and item.sourceId and Shatter.MailSession and Shatter.MailSession:FindInputItem(item.sourceId)
    if input then
        input.disenchantStatus = "failed"
        input.status = "failed"
    end
    if Shatter.MailSession then Shatter.MailSession:Log("warn", "Disenchant failed: %s", tostring(reason or "unknown")) end
    self:PrepareDisenchantQueue()
end

function MailMode:SkipQueueItem(item)
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
        return "Shatter Next", self:AreActionsEnabled() and Shatter.Queue and Shatter.Queue:GetOwner() == "mail" and Shatter.Queue:Count() > 0
    end
    if session.status == Shatter.Constants.MAIL_STATE.READY_TO_RETURN then
        return "Send Ready Mats", true
    end
    if session.status == Shatter.Constants.MAIL_STATE.COMPLETE then
        return "Done", false
    end
    if Shatter.AttachmentQueue and Shatter.AttachmentQueue:GetNext() then
        session.mailboxOpen = mailboxOpen
        return "Take Attachments", self:AreActionsEnabled()
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
    if Shatter.Queue then Shatter.Queue:ReleaseToSolo("MAIL_SESSION_CLOSED") end
    if Shatter.MainFrame then
        Shatter.MainFrame:SetActiveView("solo")
        Shatter.MainFrame:SetStatus("Mail session closed.", false, 3)
    end
    if Shatter.MailLaunchPanel then Shatter.MailLaunchPanel:Refresh() end
    return true
end
