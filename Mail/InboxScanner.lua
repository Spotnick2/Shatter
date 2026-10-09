local _, Shatter = ...

local InboxScanner = {
    -- itemIDs whose item info was not cached at scan time; a
    -- GET_ITEM_INFO_RECEIVED for one of them rescans the inbox.
    pendingItemIDs = {},
}
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
        local infoName, _, infoQuality, _, _, _, _, _, _, infoTexture = Shatter.API.GetItemInfo(link)
        itemID = itemID or tonumber(string.match(link, "item:(%d+)"))
        name = name or infoName
        quality = quality or infoQuality
        texture = texture or infoTexture
    end
    if not itemID and not link and not name then return nil end

    local infoName, itemLink, infoQuality, itemLevel, _, className, subclassName, _, equipLoc, itemTexture, _, classID, subclassID = Shatter.API.GetItemInfo(link or itemID)
    if not infoName and itemID then
        -- Cache miss: zero returns. Don't judge eligibility on missing data;
        -- remember it and rescan when the client delivers it.
        InboxScanner.pendingItemIDs[itemID] = true
        return {
            attachmentIndex = attachmentIndex, itemID = itemID, itemLink = link,
            itemName = name or ("item:" .. tostring(itemID)), texture = texture, count = count or 1,
            quality = quality, infoPending = true, disenchantable = false,
            ineligibleReason = "item info pending", status = "pending",
        }
    end
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

local function MailMatchesSelection(session, mailIndex, header)
    local selection = session and session.mailSelection or nil
    local selectionModes = Shatter.Constants and Shatter.Constants.MAIL_SELECTION_MODE or {}
    local mode = selection and selection.mode or selectionModes.ALL or "ALL"
    if mode == (selectionModes.SENDER or "SENDER") then
        local sender = selection and selection.sender
        return sender and header and header.sender and sender == header.sender or false
    end
    if mode == (selectionModes.POSTAL_SELECTED or "POSTAL_SELECTED") then
        local selected = selection and selection.selectedMailIndices
        return type(selected) == "table" and selected[mailIndex] == true
    end
    return true
end

local function Fingerprint(header, attachments)
    local parts = { header.sender or "", header.subject or "", tostring(header.money or 0), tostring(header.cod or 0), tostring(header.itemCount or 0) }
    for _, attachment in ipairs(attachments or {}) do
        table.insert(parts, tostring(attachment.itemID or "?") .. "x" .. tostring(attachment.count or 0))
    end
    return table.concat(parts, "|")
end

local function FindPreviousItem(previousItems, mail, attachment)
    for _, existing in ipairs(previousItems or {}) do
        if existing.itemID == attachment.itemID
            and existing.sourceSender == mail.sender
            and existing.mailSubject == mail.subject
            and existing.sourceAttachmentIndex == attachment.attachmentIndex then
            return existing
        end
    end
end

local function ShouldCarryForward(item)
    if not item then return false end
    if item.bag and item.slot then return true end
    if item.selected and item.disenchantable and item.status ~= "disenchanted" and item.status ~= "failed" and item.status ~= "skipped" then
        return true
    end
    return item.status == "taken"
        or item.status == "queued for disenchant"
        or item.status == "disenchanted"
        or item.status == "failed"
        or item.status == "skipped"
end

local function RefreshCarriedForwardSource(item, sourceMails)
    if not item then return end
    for _, mail in ipairs(sourceMails or {}) do
        if mail.sender == item.sourceSender and mail.subject == item.mailSubject then
            item.sourceMailId = mail.sourceMailId
            item.lastKnownMailIndex = mail.mailIndex
            item.daysLeft = mail.daysLeft or item.daysLeft
            return
        end
    end
end

function InboxScanner:Scan()
    local session = Shatter.MailSession and Shatter.MailSession:Ensure()
    if not session then return nil end
    session.status = Shatter.Constants.MAIL_STATE.SCANNING
    local previousItems = session.inputItems or {}
    session.sourceMails = {}
    session.inputItems = {}
    session.updatedAt = time and time() or 0

    local count = GetInboxCount()
    local scannedAttachments = 0
    local eligibleAttachments = 0
    for mailIndex = 1, count do
        local header = GetHeader(mailIndex)
        if header and MailMatchesSelection(session, mailIndex, header) then
            local attachments = {}
            local disenchantable = false
            -- Every receive slot (16 here, 12 is the SEND limit), each checked:
            -- a count of attachments says nothing about which slots hold
            -- them once some have been taken.
            for attachmentIndex = 1, ATTACHMENTS_MAX or 16 do
                local attachment = ReadAttachment(mailIndex, attachmentIndex)
                if attachment then
                    attachment.sourceAttachmentIndex = attachmentIndex
                    table.insert(attachments, attachment)
                    if attachment.disenchantable then disenchantable = true end
                    scannedAttachments = scannedAttachments + 1
                end
            end
            local fingerprint = Fingerprint(header, attachments)
            local mail = {
                sourceMailId = string.format("mail:%d:%d:%s", session.createdAt or 0, mailIndex, fingerprint),
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
                fingerprint = fingerprint,
                status = disenchantable and "queued" or "skipped",
                ineligibleReason = disenchantable and nil or "No disenchantable attachments",
            }
            table.insert(session.sourceMails, mail)

            for _, attachment in ipairs(attachments) do
                if attachment.disenchantable and not header.isGM and (header.cod or 0) == 0 then
                    eligibleAttachments = eligibleAttachments + 1
                    local previous = FindPreviousItem(previousItems, mail, attachment)
                    if previous then previous.__shatterSeen = true end
                    local inputItemId = previous and previous.inputItemId or string.format("mailitem:%s:%d:%d", mail.sourceMailId, attachment.attachmentIndex, attachment.itemID or 0)
                    local item = {
                        inputItemId = inputItemId,
                        itemID = attachment.itemID,
                        itemLink = attachment.itemLink,
                        itemName = attachment.itemName,
                        texture = attachment.texture,
                        count = attachment.count or 1,
                        quality = attachment.quality,
                        itemLevel = attachment.itemLevel,
                        classID = attachment.classID,
                        subclassID = attachment.subclassID,
                        equipLoc = attachment.equipLoc,
                        expectedEstimate = attachment.expectedEstimate,
                        disenchantable = true,
                        selected = (not previous) or previous.selected ~= false,
                        status = previous and previous.status or "selected",
                        sourceMailId = mail.sourceMailId,
                        sourceSender = mail.sender,
                        mailSubject = mail.subject,
                        sourceAttachmentIndex = attachment.attachmentIndex,
                        lastKnownMailIndex = mail.mailIndex,
                        daysLeft = mail.daysLeft,
                        bag = previous and previous.bag or nil,
                        slot = previous and previous.slot or nil,
                        disenchantStatus = previous and previous.disenchantStatus or "detected",
                    }
                    table.insert(session.inputItems, item)
                end
            end
        end
    end
    for _, previous in ipairs(previousItems or {}) do
        if previous.__shatterSeen then
            previous.__shatterSeen = nil
        elseif ShouldCarryForward(previous) then
            RefreshCarriedForwardSource(previous, session.sourceMails)
            table.insert(session.inputItems, previous)
        end
    end
    session.status = Shatter.Constants.MAIL_STATE.SELECTING
    if Shatter.MailSession then
        local selected, de = Shatter.MailSession:CountSelected()
        Shatter.MailSession:Log("info", "Scanned %d mails, %d attachments. Selected %d of %d disenchantable items.", count, scannedAttachments, selected, eligibleAttachments)
    end
    return session
end
