local _, Shatter = ...

local ReturnQueue = {}
Shatter.ReturnQueue = ReturnQueue
Shatter.RegisterModule("ReturnQueue", ReturnQueue)

local function AddMaterial(bucket, itemID, count)
    if not itemID or not count or count <= 0 then return end
    bucket.materialsGenerated[itemID] = (bucket.materialsGenerated[itemID] or 0) + count
end

function ReturnQueue:GetRecipientForSender(session, sender)
    if session.recipientMode == Shatter.Constants.MAIL_RECIPIENT_MODE.FUNNEL and session.funnelRecipient and session.funnelRecipient ~= "" then
        return session.funnelRecipient
    end
    return sender or UNKNOWN or "Unknown"
end

function ReturnQueue:AddResult(sourceSender, result)
    local session = Shatter.MailSession and Shatter.MailSession:Ensure()
    if not session then return end
    session.outputRecipients = type(session.outputRecipients) == "table" and session.outputRecipients or {}
    local recipient = self:GetRecipientForSender(session, sourceSender)
    local bucket = session.outputRecipients[recipient]
    if not bucket then
        bucket = {
            recipient = recipient,
            sourceSenders = {},
            itemsReceived = 0,
            materialsGenerated = {},
            materialsSent = {},
            status = "ready",
        }
        session.outputRecipients[recipient] = bucket
    end
    bucket.sourceSenders[sourceSender or recipient] = true
    bucket.itemsReceived = (bucket.itemsReceived or 0) + 1
    for itemID, count in pairs(result or {}) do
        AddMaterial(bucket, itemID, count)
    end
    bucket.status = "ready"
    session.status = Shatter.Constants.MAIL_STATE.READY_TO_RETURN
end
