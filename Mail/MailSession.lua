local _, Shatter = ...

local MailSession = {}
Shatter.MailSession = MailSession
Shatter.RegisterModule("MailSession", MailSession)

local function Now()
    return time and time() or 0
end

local function NewSession()
    return {
        sessionId = string.format("MAIL:%s:%s", Shatter.Database and Shatter.Database:GetCharacterKey() or "Unknown", Now()),
        mode = Shatter.Constants.MODES.MAIL,
        createdAt = Now(),
        updatedAt = Now(),
        status = Shatter.Constants.MAIL_STATE.CREATING,
        mailboxOpen = false,
        recipientMode = Shatter.Constants.MAIL_RECIPIENT_MODE.ORIGINAL_SENDERS,
        funnelRecipient = "",
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

function MailSession:Initialize()
    if not Shatter.Database then return end
    local db = Shatter.Database:Get()
    db.sessions = type(db.sessions) == "table" and db.sessions or {}
    db.sessions.mailHistory = type(db.sessions.mailHistory) == "table" and db.sessions.mailHistory or {}
end

function MailSession:Get()
    local db = Shatter.Database and Shatter.Database:Get()
    return db and db.sessions and db.sessions.activeMail
end

function MailSession:Ensure()
    self:Initialize()
    local db = Shatter.Database:Get()
    if type(db.sessions.activeMail) ~= "table" or db.sessions.activeMail.status == Shatter.Constants.MAIL_STATE.CLOSED then
        db.sessions.activeMail = NewSession()
        table.insert(db.sessions.activeMail.sessionLog, {
            timestamp = Now(),
            level = "info",
            message = "Mail session created.",
        })
    end
    return db.sessions.activeMail
end

function MailSession:SetMailboxOpen(open)
    local session = self:Ensure()
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
    db.sessions.mailHistory = type(db.sessions.mailHistory) == "table" and db.sessions.mailHistory or {}
    table.insert(db.sessions.mailHistory, session)
    db.sessions.activeMail = nil
    return true
end

function MailSession:SetRecipientMode(mode, funnelRecipient)
    local session = self:Ensure()
    if mode ~= Shatter.Constants.MAIL_RECIPIENT_MODE.FUNNEL then
        mode = Shatter.Constants.MAIL_RECIPIENT_MODE.ORIGINAL_SENDERS
    end
    session.recipientMode = mode
    if funnelRecipient ~= nil then session.funnelRecipient = funnelRecipient end
    session.updatedAt = Now()
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
