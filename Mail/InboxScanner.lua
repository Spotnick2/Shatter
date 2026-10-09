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

local function IsPostalSelection(session)
    local selection = session and session.mailSelection
    local selectionModes = Shatter.Constants and Shatter.Constants.MAIL_SELECTION_MODE or {}
    return selection and selection.mode == (selectionModes.POSTAL_SELECTED or "POSTAL_SELECTED") or false
end

-- What an attachment is, without its mail's inbox index: identical
-- attachments in identical mails share it.
local function AttachmentKey(sender, subject, attachmentIndex, itemID)
    return table.concat({ sender or "", subject or "", tostring(attachmentIndex or 0), tostring(itemID or 0) }, "\031")
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
        -- Just chosen: the mails Postal has checked now. After that scan the
        -- selection is the session's own rows (Postal's indices shift as soon
        -- as mail is removed), decided per attachment in Scan.
        if selection.changed then
            local selected = selection.selectedMailIndices
            return type(selected) == "table" and selected[mailIndex] == true
        end
        return true
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

-- Taken from the mail: in the bags (or away from them), no longer an inbox
-- attachment. Rows saved before this flag existed have only the slot.
local function IsReceived(item)
    return item.received or item.bag ~= nil
end

local function FindPreviousItem(previousItems, mail, attachment)
    for _, existing in ipairs(previousItems or {}) do
        -- One-to-one: a previous row already matched this scan is not reused
        -- for an identical attachment in another identical mail. A received
        -- row is never matched to an attachment still in the inbox; it
        -- carries forward whole, GUID and all.
        if not existing.__shatterSeen and not IsReceived(existing)
            and existing.itemID == attachment.itemID
            and existing.sourceSender == mail.sender
            and existing.mailSubject == mail.subject
            and existing.sourceAttachmentIndex == attachment.attachmentIndex then
            return existing
        end
    end
end

-- Only ever listed by a scan: never taken, nothing in progress.
local function IsUntouched(item)
    return not IsReceived(item) and (item.status == "selected" or item.status == "unresolved" or item.status == "missing")
end

local function ShouldCarryForward(item)
    if not item then return false end
    if IsReceived(item) then return true end
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
    local session = Shatter.MailSession and Shatter.MailSession:Get()
    if not session then return nil end
    session.status = Shatter.Constants.MAIL_STATE.SCANNING
    local previousItems = session.inputItems or {}
    session.sourceMails = {}
    session.inputItems = {}
    session.updatedAt = time and time() or 0

    -- `changed`: the selection was just set (session start, or changed on
    -- Continue), and this scan applies it.
    local selection = session.mailSelection or {}
    local reset = selection.changed
    -- Postal "Selected mails" after the scan that read Postal's checks: an
    -- attachment belongs only while a listed, not yet received row matches
    -- it. Each row matches once; an identical attachment in an unchecked
    -- mail never joins, nor does one arriving after the row was received.
    local remaining, members, matches
    if IsPostalSelection(session) and not reset then
        remaining, members, matches = {}, {}, {}
        for _, row in ipairs(previousItems) do
            if not IsReceived(row) then
                local key = AttachmentKey(row.sourceSender, row.mailSubject, row.sourceAttachmentIndex, row.itemID)
                remaining[key] = (remaining[key] or 0) + 1
                members[key] = remaining[key]
            end
        end
    end

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
                if attachment and remaining then
                    local key = AttachmentKey(header.sender, header.subject, attachmentIndex, attachment.itemID)
                    if header.isGM or (header.cod or 0) > 0 then
                        attachment = nil          -- never a row, so never a member
                    else
                        matches[key] = (matches[key] or 0) + 1
                        if (remaining[key] or 0) > 0 then
                            remaining[key] = remaining[key] - 1
                        else
                            attachment = nil      -- not one the player selected
                        end
                    end
                end
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
    if members then
        -- More matching attachments than selected rows: an unchecked twin is
        -- in the inbox and no scan can tell which mail is which. No known
        -- index, so the take re-finds the mail and pauses on the ambiguity.
        for _, item in ipairs(session.inputItems) do
            local key = AttachmentKey(item.sourceSender, item.mailSubject, item.sourceAttachmentIndex, item.itemID)
            if (matches[key] or 0) > (members[key] or 0) then item.lastKnownMailIndex = nil end
        end
    end
    for _, previous in ipairs(previousItems or {}) do
        if previous.__shatterSeen then
            previous.__shatterSeen = nil
        elseif reset and IsUntouched(previous) then
            -- Outside the new selection and never taken: no longer listed.
            -- Received items and everything after them stay.
        elseif ShouldCarryForward(previous) then
            RefreshCarriedForwardSource(previous, session.sourceMails)
            table.insert(session.inputItems, previous)
        end
    end
    if reset then
        selection.changed = nil
        -- Postal's indices are spent: from here on the rows are the selection.
        if IsPostalSelection(session) then selection.selectedMailIndices = nil end
    end
    session.status = Shatter.Constants.MAIL_STATE.SELECTING
    if Shatter.MailSession then
        local selected, de = Shatter.MailSession:CountSelected()
        Shatter.MailSession:Log("info", "Scanned %d mails, %d attachments. Selected %d of %d disenchantable items.", count, scannedAttachments, selected, eligibleAttachments)
    end
    return session
end
