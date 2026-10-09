local _, Shatter = ...

local AttachmentQueue = {}
Shatter.AttachmentQueue = AttachmentQueue
Shatter.RegisterModule("AttachmentQueue", AttachmentQueue)

local API = Shatter.API
local GetContainerNumSlotsSafe = API.GetContainerNumSlots
local GetContainerItemIDSafe = API.GetContainerItemID

-- What every bag slot held before the take: { ["bag:slot"] = itemID or false }.
local function SnapshotSlots()
    local slots = {}
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetContainerNumSlotsSafe(bag) do
            slots[bag .. ":" .. slot] = GetContainerItemIDSafe(bag, slot) or false
        end
    end
    return slots
end

-- The slot the taken attachment landed in: one that holds the item NOW and
-- held something else (or nothing) before. A copy the player already owned
-- is never mistaken for the received one.
local function FindNewlyOccupiedSlot(itemID, before)
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetContainerNumSlotsSafe(bag) do
            if GetContainerItemIDSafe(bag, slot) == itemID and before[bag .. ":" .. slot] ~= itemID then
                return bag, slot
            end
        end
    end
end

local function InboxItemIDAt(mailIndex, attachmentIndex)
    local link = GetInboxItemLink(mailIndex, attachmentIndex)
    if link then return tonumber(link:match("item:(%d+)")) end
    local _, itemID = GetInboxItem(mailIndex, attachmentIndex)
    return itemID
end

-- Re-finds the input item in the inbox as it is NOW (indices shift as mail
-- is taken or deleted): same sender and subject, same item in the same
-- attachment slot. Returns the current mail index, or nil.
local function RematchMail(item)
    local function matches(mailIndex)
        local _, _, sender, subject = GetInboxHeaderInfo(mailIndex)
        return sender == item.sourceSender and (subject or "") == (item.mailSubject or "")
            and InboxItemIDAt(mailIndex, item.sourceAttachmentIndex) == item.itemID
    end
    local count = GetInboxNumItems() or 0
    local known = item.lastKnownMailIndex
    if known and known <= count and matches(known) then return known end
    for mailIndex = 1, count do
        if matches(mailIndex) then return mailIndex end
    end
    return nil
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

local function IsMailboxOpen()
    local function visible(frame)
        if not frame then return false end
        if frame.IsVisible and frame:IsVisible() then return true end
        if frame.IsShown and frame:IsShown() then return true end
        return false
    end
    return visible(_G.MailFrame) or visible(_G.InboxFrame) or visible(_G.OpenMailFrame) or visible(_G.SendMailFrame)
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
    if session then session.mailboxOpen = IsMailboxOpen() end
    if not session or not session.mailboxOpen then
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus(Shatter.Constants.STATUS.MAILBOX_REQUIRED, true, 3) end
        return false
    end
    if not Shatter.MailMode:AreActionsEnabled() then
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus(Shatter.Constants.STATUS.MAIL_ACTIONS_DISABLED, true, 4) end
        return false
    end
    -- One take at a time: the previous one is proven landed (or failed) first.
    if session.pendingAction then return false end
    local item = self:GetNext()
    if not item then
        if Shatter.MailMode then Shatter.MailMode:PrepareDisenchantQueue() end
        return false
    end
    -- The inbox may have shifted since the scan: take only what still
    -- matches this input item, from wherever it is now.
    local mailIndex = RematchMail(item)
    if not mailIndex then
        item.status = "missing"
        item.disenchantStatus = "missing"
        if Shatter.MailSession then Shatter.MailSession:Log("warn", "Attachment no longer in the inbox: %s from %s.", item.itemLink or item.itemName or "?", item.sourceSender or "?") end
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus("That attachment is no longer in the inbox; rescan.", true, 4) end
        return false
    end
    item.lastKnownMailIndex = mailIndex
    session.status = Shatter.Constants.MAIL_STATE.TAKING
    session.pendingAction = {
        kind = "TAKE_ATTACHMENT",
        inputItemId = item.inputItemId,
        sourceMailId = item.sourceMailId,
        attachmentIndex = item.sourceAttachmentIndex,
        itemID = item.itemID,
        mailIndex = mailIndex,
        startedAt = GetTime and GetTime() or 0,
        beforeSlots = SnapshotSlots(),
    }
    item.status = "taking attachment"
    item.disenchantStatus = "taking"
    if Shatter.MailSession then Shatter.MailSession:Log("info", "Taking attachment from %s: %s.", item.sourceSender or "?", item.itemLink or item.itemName or "?") end
    TakeInboxItem(mailIndex, item.sourceAttachmentIndex)
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
    local bag, slot = FindNewlyOccupiedSlot(pending.itemID, pending.beforeSlots or {})
    local item = Shatter.MailSession and Shatter.MailSession:FindInputItem(pending.inputItemId)
    if not bag then
        if reason ~= "timeout" then return end
        session.pendingAction = nil
        -- Still in the mail: the take failed (bags full, mailbox busy). The
        -- item goes back to the list to try again; nothing is attributed.
        local stillThere = pending.mailIndex and pending.mailIndex <= (GetInboxNumItems() or 0)
            and InboxItemIDAt(pending.mailIndex, pending.attachmentIndex) == pending.itemID
        if item then
            item.status = stillThere and "selected" or "unresolved"
            item.disenchantStatus = stillThere and "detected" or "unresolved"
        end
        session.status = stillThere and Shatter.Constants.MAIL_STATE.SELECTING or Shatter.Constants.MAIL_STATE.ERROR_PAUSED
        if Shatter.MailSession then
            Shatter.MailSession:Log("warn", stillThere and "Attachment was not taken; it is still in the mail." or "Attachment left the mail but did not arrive in a new bag slot.")
        end
        if Shatter.MainFrame then
            Shatter.MainFrame:SetStatus(stillThere and "Attachment not taken (bags full?). Try again." or "Attachment taken, but its bag slot was not found.", true, 4)
            Shatter.MainFrame:Update()
        end
        return
    end
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
