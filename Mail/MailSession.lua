local _, Shatter = ...

local MailSession = {}
Shatter.MailSession = MailSession
Shatter.RegisterModule("MailSession", MailSession)

local function Now()
    return time and time() or 0
end

local function NewSession()
    local selectionModes = Shatter.Constants and Shatter.Constants.MAIL_SELECTION_MODE or {}
    return {
        sessionId = string.format("MAIL:%s:%s", Shatter.Database and Shatter.Database:GetCharacterKey() or "Unknown", Now()),
        mode = Shatter.Constants.MODES.MAIL,
        createdAt = Now(),
        updatedAt = Now(),
        status = Shatter.Constants.MAIL_STATE.CREATING,
        mailboxOpen = false,
        recipientMode = Shatter.Constants.MAIL_RECIPIENT_MODE.ORIGINAL_SENDERS,
        funnelRecipient = "",
        keepRecipient = UnitName and UnitName("player") or "Self",
        mailSelection = {
            mode = selectionModes.ALL or "ALL",
            sender = nil,
            selectedMailIndices = nil,
        },
        sourceMails = {},
        inputItems = {},
        outputRecipients = {},
        pendingAction = nil,
        sessionLog = {},
        unresolved = {
            failedPickups = {},
            failedSends = {},
            materialsMissing = {},
            skippedItems = {},
        },
    }
end

local function GetBucket(db, create)
    if not db then return nil end
    db.sessions = type(db.sessions) == "table" and db.sessions or {}
    db.sessions.byCharacter = type(db.sessions.byCharacter) == "table" and db.sessions.byCharacter or {}
    local key = Shatter.Database and Shatter.Database:GetCharacterKey() or "Unknown-Realm"
    local bucket = db.sessions.byCharacter[key]
    if create and type(bucket) ~= "table" then
        bucket = { activeMail = nil, mailHistory = {} }
        db.sessions.byCharacter[key] = bucket
    end
    if type(bucket) == "table" then
        bucket.mailHistory = type(bucket.mailHistory) == "table" and bucket.mailHistory or {}
    end
    return bucket
end

function MailSession:Initialize()
    if not Shatter.Database then return end
    local db = Shatter.Database:Get()
    db.sessions = type(db.sessions) == "table" and db.sessions or {}
    db.sessions.byCharacter = type(db.sessions.byCharacter) == "table" and db.sessions.byCharacter or {}

    local bucket = GetBucket(db, true)
    if type(db.sessions.activeMail) == "table" and type(bucket.activeMail) ~= "table" then
        bucket.activeMail = db.sessions.activeMail
    end
    db.sessions.activeMail = nil

    if type(db.sessions.mailHistory) == "table" and #db.sessions.mailHistory > 0 then
        for _, entry in ipairs(db.sessions.mailHistory) do
            table.insert(bucket.mailHistory, entry)
        end
        db.sessions.mailHistory = {}
    end
end

function MailSession:Get()
    local db = Shatter.Database and Shatter.Database:Get()
    local bucket = GetBucket(db, false)
    return bucket and bucket.activeMail or nil
end

function MailSession:HasActiveSession()
    local session = self:Get()
    return type(session) == "table" and session.status ~= Shatter.Constants.MAIL_STATE.CLOSED
end

function MailSession:StartNew()
    self:Initialize()
    local db = Shatter.Database:Get()
    local bucket = GetBucket(db, true)
    bucket.activeMail = NewSession()
    table.insert(bucket.activeMail.sessionLog, {
        timestamp = Now(),
        level = "info",
        message = "Mail session created.",
    })
    return bucket.activeMail
end

function MailSession:Ensure()
    self:Initialize()
    local db = Shatter.Database:Get()
    local bucket = GetBucket(db, true)
    if type(bucket.activeMail) ~= "table" or bucket.activeMail.status == Shatter.Constants.MAIL_STATE.CLOSED then
        bucket.activeMail = NewSession()
        table.insert(bucket.activeMail.sessionLog, {
            timestamp = Now(),
            level = "info",
            message = "Mail session created.",
        })
    end
    return bucket.activeMail
end

function MailSession:SetMailboxOpen(open)
    local session = self:Get()
    if not session then return nil end
    session.mailboxOpen = open and true or false
    session.updatedAt = Now()
    if open and session.status == Shatter.Constants.MAIL_STATE.ERROR_PAUSED then
        session.status = Shatter.Constants.MAIL_STATE.SELECTING
    elseif not open and session.status ~= Shatter.Constants.MAIL_STATE.CLOSED then
        self:Log("info", "Mailbox closed; session paused.")
    end
    return session
end

function MailSession:SetStatus(status)
    local session = self:Ensure()
    session.status = status or session.status
    session.updatedAt = Now()
    return session
end

function MailSession:Log(level, message, ...)
    local session = self:Ensure()
    if select("#", ...) > 0 then
        message = string.format(message, ...)
    end
    session.sessionLog = type(session.sessionLog) == "table" and session.sessionLog or {}
    table.insert(session.sessionLog, {
        timestamp = Now(),
        level = level or "info",
        message = tostring(message or ""),
    })
    while #session.sessionLog > 80 do
        table.remove(session.sessionLog, 1)
    end
end

function MailSession:CountSelected()
    local session = self:Get()
    local selected, disenchantable = 0, 0
    if not session then return 0, 0 end
    for _, item in ipairs(session.inputItems or {}) do
        if item.selected then
            selected = selected + 1
            if item.disenchantable then disenchantable = disenchantable + 1 end
        end
    end
    return selected, disenchantable
end

function MailSession:HasUnresolvedWork()
    local session = self:Get()
    if not session then return false end
    for _, item in ipairs(session.inputItems or {}) do
        if item.selected and item.status ~= "skipped" and item.status ~= "disenchanted" and item.status ~= "failed" then
            return true
        end
    end
    for _, bucket in pairs(session.outputRecipients or {}) do
        if bucket.status ~= "sent" and bucket.status ~= "waiting" then
            return true
        end
    end
    return false
end

function MailSession:Close(force)
    local session = self:Get()
    if not session then return true end
    if not force and self:HasUnresolvedWork() then
        return false, "Mail session still has unresolved work."
    end
    session.status = Shatter.Constants.MAIL_STATE.CLOSED
    session.endedAt = Now()
    session.updatedAt = Now()
    local db = Shatter.Database:Get()
    local bucket = GetBucket(db, true)
    table.insert(bucket.mailHistory, session)
    bucket.activeMail = nil
    return true
end

function MailSession:SetRecipientMode(mode, funnelRecipient)
    local session = self:Ensure()
    local recipientModes = Shatter.Constants and Shatter.Constants.MAIL_RECIPIENT_MODE or {}
    if mode ~= recipientModes.FUNNEL and mode ~= recipientModes.KEEP then
        mode = Shatter.Constants.MAIL_RECIPIENT_MODE.ORIGINAL_SENDERS
    end
    session.recipientMode = mode
    if funnelRecipient ~= nil then session.funnelRecipient = funnelRecipient end
    session.updatedAt = Now()
end

function MailSession:SetMailSelection(mode, sender, selectedMailIndices)
    local session = self:Ensure()
    local selectionModes = Shatter.Constants and Shatter.Constants.MAIL_SELECTION_MODE or {}
    local normalized = mode
    if normalized ~= selectionModes.SENDER and normalized ~= selectionModes.POSTAL_SELECTED then
        normalized = selectionModes.ALL or "ALL"
    end
    session.mailSelection = session.mailSelection or {}
    session.mailSelection.mode = normalized
    session.mailSelection.sender = sender and tostring(sender) or nil
    if type(selectedMailIndices) == "table" then
        local map = {}
        for index, selected in pairs(selectedMailIndices) do
            if selected then
                local n = tonumber(index)
                if n and n > 0 then map[n] = true end
            end
        end
        session.mailSelection.selectedMailIndices = next(map) and map or nil
    else
        session.mailSelection.selectedMailIndices = nil
    end
    session.updatedAt = Now()
end

local function IsHeld(item)
    return item.bag and item.slot and item.status ~= "disenchanted"
end

-- Follows received items that the player moved or sorted, by item GUID: the
-- slot saved at receipt says nothing once the bags change. An item whose
-- GUID is no longer in the bags (sold, banked, traded, deleted) stops being
-- held and is left for the player as unresolved. Items received without a
-- GUID (the API failed) keep their slot; callers treat them conservatively.
function MailSession:LocateReceived()
    local session = self:Get()
    if not session or not self:HasActiveSession() then return end
    -- A disenchant in flight consumes its item before the result is
    -- recorded; that is not the item leaving the bags.
    if Shatter.Disenchant and Shatter.Disenchant.pending then return end
    local where
    for _, item in ipairs(session.inputItems or {}) do
        if IsHeld(item) and item.itemGUID then
            if not where then
                where = {}
                for bag = 0, NUM_BAG_SLOTS do
                    for slot = 1, Shatter.API.GetContainerNumSlots(bag) do
                        local guid = Shatter.API.GetBagItemGUID(bag, slot)
                        if guid then where[guid] = { bag = bag, slot = slot } end
                    end
                end
            end
            local found = where[item.itemGUID]
            if not found then
                self:Log("warn", "%s from %s left the bags; not tracked any more.", item.itemLink or item.itemName or "?", item.sourceSender or "?")
                item.bag, item.slot = nil, nil
                item.status = "unresolved"
                item.disenchantStatus = "unresolved"
            elseif found.bag ~= item.bag or found.slot ~= item.slot then
                item.bag, item.slot = found.bag, found.slot
            end
        end
    end
end

-- What the Solo scan must leave out, so a sender's item can never be
-- destroyed as if it were the player's own:
--   slots   { ["bag:slot"] = itemID } for received items, located by GUID
--   itemIDs { [itemID] = true } for received items with no GUID: their slot
--           proves nothing after a move, so every copy is held back
function MailSession:GetReservedSlots()
    local reserved, reservedIDs = {}, {}
    local session = self:Get()
    if not session or not self:HasActiveSession() then return reserved, reservedIDs end
    self:LocateReceived()
    for _, item in ipairs(session.inputItems or {}) do
        if IsHeld(item) then
            reserved[item.bag .. ":" .. item.slot] = item.itemID
            if not item.itemGUID then reservedIDs[item.itemID] = true end
        end
    end
    return reserved, reservedIDs
end

-- Held items received without a GUID, for one itemID.
function MailSession:CountUnverifiedHeld(itemID)
    local session = self:Get()
    local n = 0
    for _, item in ipairs(session and session.inputItems or {}) do
        if IsHeld(item) and not item.itemGUID and item.itemID == itemID then n = n + 1 end
    end
    return n
end

function MailSession:FindInputItem(inputItemId)
    local session = self:Get()
    if not session or not inputItemId then return nil end
    for _, item in ipairs(session.inputItems or {}) do
        if item.inputItemId == inputItemId then return item end
    end
end

function MailSession:FindSourceMail(sourceMailId)
    local session = self:Get()
    if not session or not sourceMailId then return nil end
    for _, mail in ipairs(session.sourceMails or {}) do
        if mail.sourceMailId == sourceMailId then return mail end
    end
end
