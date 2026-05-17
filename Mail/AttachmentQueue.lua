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
    for _, item in ipairs(session.inputItems or {}) do
        if item.selected and item.disenchantable and not item.bag and item.status ~= "taken" and item.status ~= "queued for disenchant" and item.status ~= "disenchanted" then
            return item
        end
    end
end

function AttachmentQueue:TakeNext()
    local session = Shatter.MailSession and Shatter.MailSession:Ensure()
    if not session or not session.mailboxOpen then
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus(Shatter.Constants.STATUS.MAILBOX_REQUIRED, true, 3) end
        return false
    end
    local item = self:GetNext()
    if not item then
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
        inputItemId = item.inputItemId,
        sourceMailId = item.sourceMailId,
        attachmentIndex = item.sourceAttachmentIndex,
        itemID = item.itemID,
        startedAt = GetTime and GetTime() or 0,
        beforeCounts = SnapshotItemCounts(),
    }
    item.status = "taking attachment"
    item.disenchantStatus = "taking"
    if Shatter.MailSession then Shatter.MailSession:Log("info", "Taking attachment from %s: %s.", item.sourceSender or "?", item.itemLink or item.itemName or "?") end
    TakeInboxItem(item.lastKnownMailIndex, item.sourceAttachmentIndex)
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
    local item = Shatter.MailSession and Shatter.MailSession:FindInputItem(pending.inputItemId)
    if item then
        item.status = "taken"
        item.bag = bag
        item.slot = slot
        item.disenchantStatus = "waiting"
        if Shatter.MailSession then Shatter.MailSession:Log("info", "Attachment ready in Bag %d, Slot %d.", bag, slot) end
    end
    session.pendingAction = nil
    if self:GetNext() then
        session.status = Shatter.Constants.MAIL_STATE.SELECTING
    elseif Shatter.MailMode then
        Shatter.MailMode:PrepareDisenchantQueue()
    end
    if Shatter.MainFrame then Shatter.MainFrame:Update() end
end
