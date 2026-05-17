local _, Shatter = ...

local InboxScanner = {}
Shatter.InboxScanner = InboxScanner
Shatter.RegisterModule("InboxScanner", InboxScanner)

local function GetInboxCount()
    if not GetInboxNumItems then return 0 end
    local count = GetInboxNumItems()
    return count or 0
end

local function GetHeader(index)
    if not GetInboxHeaderInfo then return nil end
    local packageIcon, stationeryIcon, sender, subject, money, cod, daysLeft, itemCount, wasRead, wasReturned, textCreated, canReply, isGM = GetInboxHeaderInfo(index)
    return {
        packageIcon = packageIcon,
        stationeryIcon = stationeryIcon,
        sender = sender or UNKNOWN or "Unknown",
        subject = subject or "",
        money = money or 0,
        cod = cod or 0,
        daysLeft = daysLeft,
        itemCount = itemCount or 0,
        wasRead = wasRead,
        wasReturned = wasReturned,
        textCreated = textCreated,
        canReply = canReply,
        isGM = isGM,
    }
end

local function ReadAttachment(mailIndex, attachmentIndex)
    local name, itemID, texture, count, quality
    if GetInboxItem then
        name, itemID, texture, count, quality = GetInboxItem(mailIndex, attachmentIndex)
    end
    local link = GetInboxItemLink and GetInboxItemLink(mailIndex, attachmentIndex)
    if link and (not itemID or not name) then
        local infoName, _, infoQuality, _, _, _, _, _, _, infoTexture = GetItemInfo(link)
        itemID = itemID or tonumber(string.match(link, "item:(%d+)"))
        name = name or infoName
        quality = quality or infoQuality
        texture = texture or infoTexture
    end
    if not itemID and not link and not name then return nil end

    local infoName, itemLink, infoQuality, itemLevel, _, className, subclassName, _, equipLoc, itemTexture, _, classID, subclassID = GetItemInfo(link or itemID)
    local item = {
        attachmentIndex = attachmentIndex,
        itemID = itemID,
        itemLink = itemLink or link,
        itemName = infoName or name or ("item:" .. tostring(itemID or "?")),
        texture = itemTexture or texture,
        count = count or 1,
        quality = infoQuality or quality,
        itemLevel = itemLevel,
        className = className,
        subclassName = subclassName,
        equipLoc = equipLoc,
        classID = classID,
        subclassID = subclassID,
        isSoulbound = false,
        status = "queued",
    }
    local ok, reason = Shatter.ItemScanner and Shatter.ItemScanner:IsCandidateDisenchantable(item)
    item.disenchantable = ok and true or false
    item.ineligibleReason = ok and nil or reason
    if Shatter.DisenchantTables and ok then
        item.expectedEstimate = Shatter.DisenchantTables:GetExpected(item)
    end
    return item
end

local function Fingerprint(header, attachments)
    local parts = { header.sender or "", header.subject or "", tostring(header.money or 0), tostring(header.cod or 0), tostring(header.itemCount or 0) }
    for _, attachment in ipairs(attachments or {}) do
        table.insert(parts, tostring(attachment.itemID or "?") .. "x" .. tostring(attachment.count or 0))
    end
    return table.concat(parts, "|")
end

function InboxScanner:Scan()
    local session = Shatter.MailSession and Shatter.MailSession:Ensure()
    if not session then return nil end
    session.status = Shatter.Constants.MAIL_STATE.SCANNING
    session.inputMails = {}
    session.updatedAt = time and time() or 0

    local count = GetInboxCount()
    for mailIndex = 1, count do
        local header = GetHeader(mailIndex)
        if header then
            local attachments = {}
            local disenchantable = false
            for attachmentIndex = 1, math.min(header.itemCount or 0, 12) do
                local attachment = ReadAttachment(mailIndex, attachmentIndex)
                if attachment then
                    attachment.sourceAttachmentIndex = attachmentIndex
                    table.insert(attachments, attachment)
                    if attachment.disenchantable then disenchantable = true end
                end
            end
            local mail = {
                mailId = string.format("mail:%d:%d", session.createdAt or 0, mailIndex),
                sender = header.sender,
                normalizedSender = header.sender,
                subject = header.subject,
                mailIndex = mailIndex,
                lastSeenAt = time and time() or 0,
                daysLeft = header.daysLeft,
                hasMoney = (header.money or 0) > 0,
                codAmount = header.cod or 0,
                selected = disenchantable and not header.isGM and (header.cod or 0) == 0,
                attachments = attachments,
                disenchantable = disenchantable,
                fingerprint = Fingerprint(header, attachments),
                status = disenchantable and "queued" or "skipped",
                ineligibleReason = disenchantable and nil or "No disenchantable attachments",
            }
            table.insert(session.inputMails, mail)
        end
    end
    session.status = Shatter.Constants.MAIL_STATE.SELECTING
    if Shatter.MailSession then
        local selected, de = Shatter.MailSession:CountSelected()
        Shatter.MailSession:Log("info", "Scanned %d incoming mails. Selected %d (%d disenchantable).", count, selected, de)
    end
    return session
end
