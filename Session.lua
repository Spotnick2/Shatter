local _, Shatter = ...

local Session = {
    active = nil,
}

Shatter.Session = Session
Shatter.RegisterModule("Session", Session)

local function NewSession(mode)
    return {
        sessionId = string.format("%s:%s", mode or "SOLO", time and time() or 0),
        mode = mode or Shatter.Constants.MODES.SOLO,
        startedAt = time and time() or 0,
        endedAt = nil,
        state = "READY",
        items = {},
        materialDeltas = {},
        sourceAttribution = {},
        simulatedQueueIds = {},
        skippedQueueIds = {},
        queuedItemSequences = {},
        nextQueueSequence = 0,
        pendingAction = nil,
        summary = {
            itemsQueued = 0,
            itemsDisenchanted = 0,
            itemsSkipped = 0,
            itemsIgnored = 0,
            itemsFailed = 0,
            materialsGenerated = {},
            unresolvedMaterials = {},
        },
    }
end

function Session:Initialize()
    self.active = nil
end

function Session:Ensure(mode)
    if not self.active or self.active.mode ~= mode then
        self.active = NewSession(mode)
        local db = Shatter.Database and Shatter.Database:Get()
        if db then db.sessions.active = self.active end
    end
    return self.active
end

function Session:GetActive()
    return self.active
end

function Session:SetQueuedCount(count)
    local session = self:Ensure(Shatter.Constants.MODES.SOLO)
    session.summary.itemsQueued = count or 0
end

function Session:AssignQueueSequence(item)
    if not item or not item.queueId then return 0 end
    local session = self:Ensure(item.mode or Shatter.Constants.MODES.SOLO)
    session.queuedItemSequences = session.queuedItemSequences or {}
    if not session.queuedItemSequences[item.queueId] then
        session.nextQueueSequence = (session.nextQueueSequence or 0) + 1
        session.queuedItemSequences[item.queueId] = session.nextQueueSequence
    end
    item.queueSequence = session.queuedItemSequences[item.queueId]
    return item.queueSequence
end

function Session:BeginAction(item)
    local session = self:Ensure(item and item.mode or Shatter.Constants.MODES.SOLO)
    session.pendingAction = item
    session.state = "CASTING"
end

function Session:RecordResult(item, result, options)
    options = options or {}
    local session = self:Ensure(item and item.mode or Shatter.Constants.MODES.SOLO)
    session.pendingAction = nil
    session.state = "READY"
    session.summary.itemsDisenchanted = session.summary.itemsDisenchanted + 1
    if options.simulated and item and item.queueId then
        session.simulatedQueueIds[item.queueId] = true
    end

    local entry = {
        time = time and time() or 0,
        itemID = item and item.itemID,
        itemLink = item and item.itemLink,
        result = result or {},
        simulated = options.simulated and true or false,
    }
    table.insert(session.items, entry)

    for itemID, count in pairs(result or {}) do
        session.summary.materialsGenerated[itemID] = (session.summary.materialsGenerated[itemID] or 0) + count
    end
end

function Session:IsQueueItemSimulated(queueId)
    local session = self.active
    if not session or not session.simulatedQueueIds or not queueId then return false end
    return session.simulatedQueueIds[queueId] == true
end

function Session:IsQueueItemSkipped(queueId)
    local session = self.active
    if not session or not session.skippedQueueIds or not queueId then return false end
    return session.skippedQueueIds[queueId] == true
end

function Session:SkipItem(item)
    local session = self:Ensure(item and item.mode or Shatter.Constants.MODES.SOLO)
    if item and item.queueId then
        session.skippedQueueIds[item.queueId] = true
    end
    session.summary.itemsSkipped = (session.summary.itemsSkipped or 0) + 1
end

function Session:IgnoreItem(item)
    local session = self:Ensure(item and item.mode or Shatter.Constants.MODES.SOLO)
    session.summary.itemsIgnored = (session.summary.itemsIgnored or 0) + 1
end

function Session:ResetSimulatedItems()
    local session = self.active
    if session then
        session.simulatedQueueIds = {}
    end
end

function Session:ResetSkippedItems()
    local session = self.active
    if session then
        session.skippedQueueIds = {}
    end
end

function Session:FailPending(reason)
    local session = self:Ensure(Shatter.Constants.MODES.SOLO)
    session.state = "ERROR"
    session.summary.itemsFailed = session.summary.itemsFailed + 1
    if session.pendingAction then
        session.pendingAction.failureReason = reason
    end
    session.pendingAction = nil
end

function Session:FormatSummary()
    local session = self.active
    if not session then return "No active session." end
    local materials = Shatter.MaterialTracker and Shatter.MaterialTracker:Format(session.summary.materialsGenerated) or "None"
    return string.format("Disenchanted: %d  Skipped: %d  Ignored: %d  Failed: %d  Materials: %s", session.summary.itemsDisenchanted or 0, session.summary.itemsSkipped or 0, session.summary.itemsIgnored or 0, session.summary.itemsFailed or 0, materials)
end

function Session:GetSummaryLines()
    local session = self.active
    if not session then
        return { "No active Solo session yet." }
    end

    local lines = {
        string.format("Queued this scan: %d", session.summary.itemsQueued or 0),
        string.format("Disenchanted: %d", session.summary.itemsDisenchanted or 0),
        string.format("Skipped: %d", session.summary.itemsSkipped or 0),
        string.format("Ignored: %d", session.summary.itemsIgnored or 0),
        string.format("Failed: %d", session.summary.itemsFailed or 0),
        "Materials:",
    }

    if Shatter.MaterialTracker and not Shatter.MaterialTracker:IsEmpty(session.summary.materialsGenerated) then
        for itemID, count in pairs(session.summary.materialsGenerated) do
            local name, link = GetItemInfo(itemID)
            table.insert(lines, string.format("  %s x%d", link or name or tostring(itemID), count))
        end
    else
        table.insert(lines, "  No materials recorded yet.")
    end

    return lines
end
