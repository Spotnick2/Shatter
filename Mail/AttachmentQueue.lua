local _, Shatter = ...

local AttachmentQueue = {}
Shatter.AttachmentQueue = AttachmentQueue
Shatter.RegisterModule("AttachmentQueue", AttachmentQueue)

local function GetContainerNumSlotsSafe(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
    if GetContainerNumSlots then return GetContainerNumSlots(bag) or 0 end
    return 0
end

local function GetContainerItemIDSafe(bag, slot)
    if C_Container and C_Container.GetContainerItemID then return C_Container.GetContainerItemID(bag, slot) end
    if GetContainerItemID then return GetContainerItemID(bag, slot) end
end

local function SnapshotItemCounts()
    local counts = {}
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetContainerNumSlotsSafe(bag) do
            local itemID = GetContainerItemIDSafe(bag, slot)
            if itemID then
                counts[itemID] = (counts[itemID] or 0) + 1
            end
        end
    end
    return counts
end

local function FindBagSlotForItem(itemID)
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetContainerNumSlotsSafe(bag) do
            if GetContainerItemIDSafe(bag, slot) == itemID then
                return bag, slot
            end
        end
    end
end

function AttachmentQueue:GetNext()
    local session = Shatter.MailSession and Shatter.MailSession:Get()
    if not session then return nil end
    for _, mail in ipairs(session.inputMails or {}) do
        if mail.selected and mail.status ~= "taken" and mail.status ~= "done" then
            for _, attachment in ipairs(mail.attachments or {}) do
                if attachment.disenchantable and not attachment.taken and attachment.status ~= "taken" then
                    return mail, attachment
                end
            end
        end
    end
end

function AttachmentQueue:TakeNext()
    local session = Shatter.MailSession and Shatter.MailSession:Ensure()
    if not session or not session.mailboxOpen then
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus(Shatter.Constants.STATUS.MAILBOX_REQUIRED, true, 3) end
        return false
    end
    local mail, attachment = self:GetNext()
    if not mail or not attachment then
        if Shatter.MailMode then Shatter.MailMode:PrepareDisenchantQueue() end
        return false
    end
    if not TakeInboxItem then
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus("TakeInboxItem API unavailable.", true, 3) end
        return false
    end
    session.status = Shatter.Constants.MAIL_STATE.TAKING
    session.pendingAction = {
        kind = "TAKE_ATTACHMENT",
        mailId = mail.mailId,
        attachmentIndex = attachment.attachmentIndex,
        itemID = attachment.itemID,
        startedAt = GetTime and GetTime() or 0,
        beforeCounts = SnapshotItemCounts(),
    }
    mail.status = "taking"
    attachment.status = "taking"
    if Shatter.MailSession then Shatter.MailSession:Log("info", "Taking attachment from %s: %s.", mail.sender or "?", attachment.itemLink or attachment.itemName or "?") end
    TakeInboxItem(mail.mailIndex, attachment.attachmentIndex)
    if Shatter.Events then
        Shatter.Events:After(0.8, function() self:ResolvePending("timer") end)
        Shatter.Events:After(2.0, function() self:ResolvePending("timeout") end)
    end
    return true
end

function AttachmentQueue:ResolvePending(reason)
    local session = Shatter.MailSession and Shatter.MailSession:Get()
    local pending = session and session.pendingAction
    if not pending or pending.kind ~= "TAKE_ATTACHMENT" then return end
    local bag, slot = FindBagSlotForItem(pending.itemID)
    if not bag then
        if reason ~= "timeout" then return end
        session.status = Shatter.Constants.MAIL_STATE.ERROR_PAUSED
        if Shatter.MailSession then Shatter.MailSession:Log("warn", "Could not find taken attachment in bags.") end
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus("Attachment taken, but bag slot was not found.", true, 3) end
        session.pendingAction = nil
        return
    end
    for _, mail in ipairs(session.inputMails or {}) do
        if mail.mailId == pending.mailId then
            for _, attachment in ipairs(mail.attachments or {}) do
                if attachment.attachmentIndex == pending.attachmentIndex then
                    attachment.taken = true
                    attachment.status = "taken"
                    attachment.bag = bag
                    attachment.slot = slot
                    mail.status = "taken"
                    local inputItemId = string.format("mailitem:%s:%d", mail.mailId, attachment.attachmentIndex)
                    attachment.inputItemId = inputItemId
                    session.inputItems[inputItemId] = {
                        inputItemId = inputItemId,
                        sourceSender = mail.sender,
                        sourceMailId = mail.mailId,
                        sourceAttachmentIndex = attachment.attachmentIndex,
                        itemID = attachment.itemID,
                        itemLink = attachment.itemLink,
                        itemName = attachment.itemName,
                        count = attachment.count or 1,
                        bag = bag,
                        slot = slot,
                        disenchantStatus = "waiting",
                    }
                    if Shatter.MailSession then Shatter.MailSession:Log("info", "Attachment ready in Bag %d, Slot %d.", bag, slot) end
                    break
                end
            end
        end
    end
    session.pendingAction = nil
    if self:GetNext() then
        session.status = Shatter.Constants.MAIL_STATE.SELECTING
    elseif Shatter.MailMode then
        Shatter.MailMode:PrepareDisenchantQueue()
    end
    if Shatter.MainFrame then Shatter.MainFrame:Update() end
end
