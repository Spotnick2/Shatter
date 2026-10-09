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

-- Slots that hold the item NOW and held something else (or nothing) before.
local function NewlyOccupiedSlots(itemID, before)
    local found = {}
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetContainerNumSlotsSafe(bag) do
            if GetContainerItemIDSafe(bag, slot) == itemID and before[bag .. ":" .. slot] ~= itemID then
                found[#found + 1] = { bag = bag, slot = slot }
            end
        end
    end
    return found
end

local function CountInBags(itemID)
    local n = 0
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetContainerNumSlotsSafe(bag) do
            if GetContainerItemIDSafe(bag, slot) == itemID then n = n + 1 end
        end
    end
    return n
end

local function InboxItemIDAt(mailIndex, attachmentIndex)
    local link = GetInboxItemLink(mailIndex, attachmentIndex)
    if link then return tonumber(link:match("item:(%d+)")) end
    local _, itemID = GetInboxItem(mailIndex, attachmentIndex)
    return itemID
end

-- How many attachments of this item this sender's mails with this subject
-- hold right now. A take that worked lowers it by one.
local function CountInboxMatches(sender, subject, itemID)
    local n = 0
    for mailIndex = 1, GetInboxNumItems() or 0 do
        local _, _, s, subj = GetInboxHeaderInfo(mailIndex)
        if s == sender and (subj or "") == (subject or "") then
            for a = 1, ATTACHMENTS_MAX or 16 do
                if InboxItemIDAt(mailIndex, a) == itemID then n = n + 1 end
            end
        end
    end
    return n
end

-- Re-finds the input item in the inbox as it is NOW (indices shift as mail
-- is taken or deleted): same sender and subject, same item and count in the
-- same attachment slot, and still eligible (no COD, not from a GM) - the
-- scan excluded those, so a substitute must be excluded too. Returns the
-- current mail index, or nil plus a reason ("missing" or "ambiguous").
local function RematchMail(item)
    local function matches(mailIndex)
        local _, _, sender, subject, _, cod, _, _, _, _, _, _, isGM = GetInboxHeaderInfo(mailIndex)
        if sender ~= item.sourceSender or (subject or "") ~= (item.mailSubject or "") then return false end
        if (cod or 0) > 0 or isGM then return false end
        if InboxItemIDAt(mailIndex, item.sourceAttachmentIndex) ~= item.itemID then return false end
        local _, _, _, count = GetInboxItem(mailIndex, item.sourceAttachmentIndex)
        return (count or 1) == (item.count or 1)
    end
    local count = GetInboxNumItems() or 0
    local known = item.lastKnownMailIndex
    if known and known <= count and matches(known) then return known end
    -- The mail moved. Accept a substitute only if exactly one mail fits:
    -- two identical mails from one sender cannot be told apart here.
    local found
    for mailIndex = 1, count do
        if matches(mailIndex) then
            if found then return nil, "ambiguous" end
            found = mailIndex
        end
    end
    if found then return found end
    return nil, "missing"
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
        if item.selected and item.disenchantable and not item.bag and item.status ~= "taken" and item.status ~= "queued for disenchant"
            and item.status ~= "disenchanted" and item.status ~= "missing" and item.status ~= "unresolved" then
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
    local mailIndex, why = RematchMail(item)
    if not mailIndex then
        -- Left out of automatic intake from now on (GetNext skips it): an
        -- ambiguous or vanished attachment needs the player to look.
        item.status = why == "ambiguous" and "unresolved" or "missing"
        item.disenchantStatus = item.status
        if Shatter.MailSession then
            Shatter.MailSession:Log("warn", "%s: %s from %s.",
                why == "ambiguous" and "Several identical mails match; not taking automatically" or "Attachment no longer in the inbox",
                item.itemLink or item.itemName or "?", item.sourceSender or "?")
        end
        if Shatter.MainFrame then
            Shatter.MainFrame:SetStatus(why == "ambiguous" and "Identical mails: take that one by hand." or "That attachment is no longer in the inbox.", true, 4)
        end
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
        sender = item.sourceSender,
        subject = item.mailSubject,
        startedAt = GetTime and GetTime() or 0,
        beforeSlots = SnapshotSlots(),
        beforeBagCount = CountInBags(item.itemID),
        beforeInboxCount = CountInboxMatches(item.sourceSender, item.mailSubject, item.itemID),
    }
    item.status = "taking attachment"
    item.disenchantStatus = "taking"
    if Shatter.MailSession then Shatter.MailSession:Log("info", "Taking attachment from %s: %s.", item.sourceSender or "?", item.itemLink or item.itemName or "?") end
    TakeInboxItem(mailIndex, item.sourceAttachmentIndex)
    -- The callbacks belong to THIS take: a later take must not be resolved
    -- (or timed out) by an earlier one's timers.
    local action = session.pendingAction
    if Shatter.Events then
        Shatter.Events:After(0.8, function() self:ResolvePending("timer", action) end)
        Shatter.Events:After(2.0, function() self:ResolvePending("timeout", action) end)
    end
    return true
end

-- Receipt needs three things to agree: the inbox holds one fewer of this
-- sender's item, the bags hold one more, and exactly one slot newly holds
-- it. A personal copy moved between slots changes neither count, so it can
-- never be taken for the received item; anything ambiguous is left for the
-- player rather than guessed.
function AttachmentQueue:ResolvePending(reason, action)
    local session = Shatter.MailSession and Shatter.MailSession:Get()
    local pending = session and session.pendingAction
    if not pending or pending.kind ~= "TAKE_ATTACHMENT" then return end
    if action and action ~= pending then return end
    local item = Shatter.MailSession and Shatter.MailSession:FindInputItem(pending.inputItemId)
    local leftInbox = CountInboxMatches(pending.sender, pending.subject, pending.itemID) < (pending.beforeInboxCount or 0)
    local arrived = CountInBags(pending.itemID) > (pending.beforeBagCount or 0)
    local candidates = NewlyOccupiedSlots(pending.itemID, pending.beforeSlots or {})
    local bag, slot
    if leftInbox and arrived and #candidates == 1 then
        bag, slot = candidates[1].bag, candidates[1].slot
    end
    if not bag then
        if reason ~= "timeout" then return end
        session.pendingAction = nil
        -- Still in the mail: the take failed (bags full, mailbox busy). The
        -- item goes back to the list to try again; nothing is attributed.
        local stillThere = not leftInbox
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
        -- The instance's identity, so a later move or a personal copy put in
        -- this slot cannot be mistaken for it.
        item.itemGUID = Shatter.API.GetBagItemGUID(bag, slot)
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
