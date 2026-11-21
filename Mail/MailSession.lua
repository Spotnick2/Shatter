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

-- The bucket of one character (this one unless `key` says otherwise).
local function GetBucket(db, create, key)
    if not db then return nil end
    db.sessions = type(db.sessions) == "table" and db.sessions or {}
    db.sessions.byCharacter = type(db.sessions.byCharacter) == "table" and db.sessions.byCharacter or {}
    key = key or Shatter.Database and Shatter.Database:GetCharacterKey() or "Unknown-Realm"
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

-- "MAIL:<characterKey>:<time>" -> the character that started the session.
local function CharacterKeyOf(session)
    local id = type(session) == "table" and session.sessionId
    return type(id) == "string" and id:match("^MAIL:(.+):%d+$") or nil
end

-- Sessions used to be account-wide. Each old one goes to the character that
-- started it, whoever logs in first; one that names no character stays where
-- it is rather than land on the wrong one.
function MailSession:Initialize()
    if not Shatter.Database then return end
    local db = Shatter.Database:Get()
    db.sessions = type(db.sessions) == "table" and db.sessions or {}
    db.sessions.byCharacter = type(db.sessions.byCharacter) == "table" and db.sessions.byCharacter or {}

    local legacy = db.sessions.activeMail
    local legacyKey = CharacterKeyOf(legacy)
    if legacyKey then
        local bucket = GetBucket(db, true, legacyKey)
        if type(bucket.activeMail) ~= "table" then
            bucket.activeMail = legacy
        else
            table.insert(bucket.mailHistory, legacy)
        end
        db.sessions.activeMail = nil
    end

    if type(db.sessions.mailHistory) == "table" and #db.sessions.mailHistory > 0 then
        local unattributed = {}
        for _, entry in ipairs(db.sessions.mailHistory) do
            local key = CharacterKeyOf(entry)
            if key then
                table.insert(GetBucket(db, true, key).mailHistory, entry)
            else
                table.insert(unattributed, entry)
            end
        end
        db.sessions.mailHistory = unattributed
    end

    -- After that import, which may have filled old keys (#73): the buckets
    -- under this character's full name and an old realm are its own. Once
    -- per login, apart from the settings' adoption (which a skin read can
    -- reach first), and never again in the login: StartNew calls this, and
    -- must not have a parked session moved in under its new one.
    local fullName = Shatter.Database:GetFullName()
    if fullName and self.adoptedFor ~= fullName then
        self.adoptedFor = fullName
        local full = Shatter.Database.OldKeysIn(db.sessions.byCharacter, fullName)
        if #full > 0 then self:AdoptBuckets(full) end
    end
end

local function IsOpen(session)
    return type(session) == "table" and session.status ~= Shatter.Constants.MAIL_STATE.CLOSED
end

-- Anything taken, queued or owed: a session without is safe to close.
local function HasWork(session)
    return (type(session.inputItems) == "table" and next(session.inputItems) ~= nil)
        or (type(session.outputRecipients) == "table" and next(session.outputRecipients) ~= nil)
end

local function Archive(bucket, session)
    if session.status ~= Shatter.Constants.MAIL_STATE.CLOSED then
        session.status = Shatter.Constants.MAIL_STATE.CLOSED
        session.endedAt = session.endedAt or Now()
    end
    table.insert(bucket.mailHistory, session)
end

-- Merges the buckets under `keys`, old keys of this character, into its own.
-- Histories join, in the order the sessions started; a session there that
-- is closed, or open with nothing in it, joins the history. Of the open ones
-- with work, this character's own stays active, else the latest updated
-- takes its place. Any other stays under its old key, its received items
-- still held back (GetReservedSlots), and is adopted at a later login once
-- this character has no session open.
function MailSession:AdoptBuckets(keys)
    local db = Shatter.Database:Get()
    local buckets = db.sessions.byCharacter
    local mine = GetBucket(db, true)
    local parked, merged = {}, false
    for _, key in ipairs(keys) do
        local bucket = buckets[key]
        if type(bucket) == "table" and bucket ~= mine then
            for _, entry in ipairs(type(bucket.mailHistory) == "table" and bucket.mailHistory or {}) do
                table.insert(mine.mailHistory, entry)
                merged = true
            end
            bucket.mailHistory = {}
            local session = bucket.activeMail
            if type(session) == "table" and not (IsOpen(session) and HasWork(session)) then
                Archive(mine, session)
                bucket.activeMail, merged = nil, true
            elseif type(session) == "table" then
                parked[#parked + 1] = key
            end
            if bucket.activeMail == nil then buckets[key] = nil end
        end
    end
    local own = mine.activeMail
    if #parked > 0 and not (IsOpen(own) and HasWork(own)) then
        if type(own) == "table" then Archive(mine, own) end
        local latest
        for _, key in ipairs(parked) do
            local updated = tonumber(buckets[key].activeMail.updatedAt) or 0
            if not latest or updated > (tonumber(buckets[latest].activeMail.updatedAt) or 0) then
                latest = key
            end
        end
        mine.activeMail = buckets[latest].activeMail
        buckets[latest] = nil
        merged = true
    end
    if merged then
        local order = {}
        for i, entry in ipairs(mine.mailHistory) do order[entry] = i end
        table.sort(mine.mailHistory, function(a, b)
            local ta = type(a) == "table" and tonumber(a.createdAt) or 0
            local tb = type(b) == "table" and tonumber(b.createdAt) or 0
            if ta ~= tb then return ta < tb end
            return order[a] < order[b]
        end)
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

-- Never over an active session: its owed-materials ledger would be lost.
-- The player continues it, or closes it (which archives it) first.
function MailSession:StartNew()
    -- Initialize first: what it imports or adopts may be an active session.
    self:Initialize()
    if self:HasActiveSession() then
        return nil, "A mail session is already active: continue it, or close it first."
    end
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

-- Nothing below creates a session: only StartNew (an explicit player
-- choice on the mailbox panel) does. Without one they do nothing.
function MailSession:SetStatus(status)
    local session = self:Get()
    if not session then return nil end
    session.status = status or session.status
    session.updatedAt = Now()
    return session
end

function MailSession:Log(level, message, ...)
    local session = self:Get()
    if not session then return end
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

-- Received items (in the bags, the sender's) whose disenchant failed or
-- that can't be disenchanted: they're still to be dealt with by hand.
-- Selection doesn't matter: it governs intake, and unticking a row (or None)
-- doesn't give a received item back.
function MailSession:CountReceivedFailed()
    local session = self:Get()
    local n = 0
    for _, item in ipairs(session and session.inputItems or {}) do
        if item.disenchantStatus == "failed" then n = n + 1 end
    end
    return n
end

function MailSession:HasUnresolvedWork()
    local session = self:Get()
    if not session then return false end
    for _, item in ipairs(session.inputItems or {}) do
        if item.selected and item.status ~= "skipped" and item.status ~= "disenchanted" and item.status ~= "failed" then
            return true
        end
    end
    -- A received item that failed is still in the bags: an ordinary Close
    -- is refused, so closing over it takes the explicit Confirm Close.
    if self:CountReceivedFailed() > 0 then return true end
    for _, bucket in pairs(session.outputRecipients or {}) do
        if bucket.status ~= "sent" and bucket.status ~= "waiting" and bucket.status ~= "kept" then
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
    local session = self:Get()
    if not session then return end
    local recipientModes = Shatter.Constants and Shatter.Constants.MAIL_RECIPIENT_MODE or {}
    if mode ~= recipientModes.FUNNEL and mode ~= recipientModes.KEEP then
        mode = Shatter.Constants.MAIL_RECIPIENT_MODE.ORIGINAL_SENDERS
    end
    session.recipientMode = mode
    if funnelRecipient ~= nil then session.funnelRecipient = funnelRecipient end
    session.updatedAt = Now()
end

function MailSession:SetMailSelection(mode, sender, selectedMailIndices)
    local session = self:Get()
    if not session then return end
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
    -- The next scan applies it: rows outside it that were never taken go.
    session.mailSelection.changed = true
    session.updatedAt = Now()
end

local function IsHeld(item)
    return item.bag and item.slot and item.status ~= "disenchanted"
end

-- GUID -> { bag, slot } for every bag item, or nil if any occupied slot gave
-- no GUID: a partial picture must not be read as "the item left".
local function MapBagGUIDs()
    local where = {}
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, Shatter.API.GetContainerNumSlots(bag) do
            if Shatter.API.GetContainerItemID(bag, slot) then
                local guid = Shatter.API.GetBagItemGUID(bag, slot)
                if not guid then return nil end
                where[guid] = { bag = bag, slot = slot }
            end
        end
    end
    return where
end

-- Follows received items by item GUID: the slot saved at receipt says
-- nothing once the player moves or sorts. Ownership does not depend on
-- location: an item whose GUID left the bags (banked, traded) is marked
-- away and still searched for, and is held again the moment it returns.
-- Items received without a GUID keep their slot; callers refuse them.
-- Returns true when every received item's location is proven this time;
-- false when it could not look (a disenchant in flight, a slot gave no
-- GUID), and the saved slots may be stale.
function MailSession:LocateReceived()
    local session = self:Get()
    if not session or not self:HasActiveSession() then return true end
    -- A disenchant in flight consumes its item before the result is
    -- recorded; that is not the item leaving the bags.
    if Shatter.Disenchant and Shatter.Disenchant.pending then return false end
    local where
    for _, item in ipairs(session.inputItems or {}) do
        if item.itemGUID and item.status ~= "disenchanted" then
            if not where then
                where = MapBagGUIDs()
                if not where then return false end
            end
            local found = where[item.itemGUID]
            if found then
                item.bag, item.slot = found.bag, found.slot
                if item.away then
                    item.status, item.disenchantStatus = item.away.status, item.away.disenchantStatus
                    item.away = nil
                    -- Work again for the Mail view, even if the session had
                    -- run out of items while this one was away.
                    if item.disenchantStatus == "waiting" then
                        session.status = Shatter.Constants.MAIL_STATE.READY_TO_DISENCHANT
                    end
                    self:Log("info", "%s from %s is back in the bags.", item.itemLink or item.itemName or "?", item.sourceSender or "?")
                end
            elseif not item.away then
                self:Log("warn", "%s from %s left the bags; held again if it returns.", item.itemLink or item.itemName or "?", item.sourceSender or "?")
                item.away = { status = item.status, disenchantStatus = item.disenchantStatus }
                item.bag, item.slot = nil, nil
                item.status = "unresolved"
                item.disenchantStatus = "unresolved"
            end
        end
    end
    return true
end

-- What the Solo scan must leave out, so a sender's item can never be
-- destroyed as if it were the player's own:
--   slots   { ["bag:slot"] = itemID } for received items, located by GUID
--   itemIDs { [itemID] = true } where a slot proves nothing, so every copy
--           is held back: received items with no GUID, and, while their
--           locations could not be proven, every received item (away too)
-- Open sessions under this character's old keys that weren't adopted
-- (several with work, or a first name not answered for, #73): their received
-- items are held back too. By GUID, which is unique, so another character's
-- session holds back nothing of this one's; an item with no GUID, or while
-- the bags can't be read whole, holds back every copy. Read only: locating
-- would mark another character's items as gone.
local function ReserveOldKeys(reserved, reservedIDs)
    local fullName = Shatter.Database and Shatter.Database:GetFullName()
    if not fullName then return end
    local db = Shatter.Database:Get()
    local buckets = type(db.sessions) == "table" and db.sessions.byCharacter
    local full, first = Shatter.Database.OldKeysIn(buckets, fullName)
    local where, looked
    for _, keys in ipairs({ full, first }) do
        for _, key in ipairs(keys) do
            local session = type(buckets[key]) == "table" and buckets[key].activeMail
            if IsOpen(session) then
                for _, item in ipairs(type(session.inputItems) == "table" and session.inputItems or {}) do
                    if item.itemID and (item.received or item.bag) and item.status ~= "disenchanted" then
                        if not item.itemGUID then
                            reservedIDs[item.itemID] = true
                        else
                            if not looked then where, looked = MapBagGUIDs(), true end
                            local found = where and where[item.itemGUID]
                            if found then
                                reserved[found.bag .. ":" .. found.slot] = item.itemID
                            elseif not where then
                                reservedIDs[item.itemID] = true
                            end
                        end
                    end
                end
            end
        end
    end
end

function MailSession:GetReservedSlots()
    local reserved, reservedIDs = {}, {}
    ReserveOldKeys(reserved, reservedIDs)
    local session = self:Get()
    if not session or not self:HasActiveSession() then return reserved, reservedIDs end
    local proven = self:LocateReceived()
    for _, item in ipairs(session.inputItems or {}) do
        if IsHeld(item) then
            reserved[item.bag .. ":" .. item.slot] = item.itemID
            if not item.itemGUID then reservedIDs[item.itemID] = true end
        end
        if not proven and (item.received or item.bag) and item.status ~= "disenchanted" then
            reservedIDs[item.itemID] = true
        end
    end
    return reserved, reservedIDs
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
