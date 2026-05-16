local _, Shatter = ...

local SoloMode = {
    scanScheduled = false,
    scanReasons = {},
    scanReasonText = nil,
    isScanning = false,
    rescanAfterCurrent = false,
    lastEligibleCount = nil,
    lastSelectedQueueId = nil,
}

Shatter.SoloMode = SoloMode
Shatter.RegisterModule("SoloMode", SoloMode)

function SoloMode:Initialize()
    if not Shatter.Events then return end
    Shatter.Events:Register("BAG_UPDATE_DELAYED", self, self.OnEvent)
    Shatter.Events:Register("GET_ITEM_INFO_RECEIVED", self, self.OnEvent)
    self:ScheduleScan("PLAYER_LOGIN", 0)
end

function SoloMode:OnEvent(event)
    if event == "BAG_UPDATE_DELAYED" or event == "GET_ITEM_INFO_RECEIVED" then
        if Shatter.Disenchant and Shatter.Disenchant:HasPending() then return end
        self:ScheduleScan(event, event == "BAG_UPDATE_DELAYED" and 0.15 or 0.25)
    end
end

local function AddReason(self, reason)
    reason = reason or "UNKNOWN"
    if not self.scanReasons[reason] then
        self.scanReasons[reason] = true
        if self.scanReasonText and self.scanReasonText ~= "" then
            self.scanReasonText = self.scanReasonText .. ", " .. reason
        else
            self.scanReasonText = reason
        end
    end
end

function SoloMode:ScheduleScan(reason, delay)
    AddReason(self, reason)
    if Shatter.Debug then Shatter.Debug:Log("trace", "Solo scan scheduled. Reason: %s", self.scanReasonText or reason or "UNKNOWN") end

    if self.isScanning then
        self.rescanAfterCurrent = true
        return
    end
    if self.scanScheduled then return end
    self.scanScheduled = true
    if Shatter.Events then
        Shatter.Events:After(delay or 0.2, function()
            self.scanScheduled = false
            self:Rescan(self.scanReasonText or reason or "UNKNOWN")
        end)
    else
        self.scanScheduled = false
        self:Rescan(self.scanReasonText or reason or "UNKNOWN")
    end
end

function SoloMode:ScheduleRescan(delay, reason)
    self:ScheduleScan(reason or "SCHEDULE_RESCAN", delay)
end

local function IsImportantReason(reason)
    if not reason then return false end
    return string.find(reason, "SETTINGS", 1, true)
        or string.find(reason, "IGNORED", 1, true)
        or string.find(reason, "SKIPPED", 1, true)
        or string.find(reason, "DISENCHANT", 1, true)
        or string.find(reason, "MANUAL", 1, true)
        or string.find(reason, "SIMULATION", 1, true)
end

function SoloMode:Rescan(reason)
    if not Shatter.ItemScanner or not Shatter.Queue then return end
    if self.isScanning then
        self.rescanAfterCurrent = true
        AddReason(self, reason or "REENTERED_SCAN")
        return
    end

    self.isScanning = true
    reason = reason or self.scanReasonText or "DIRECT"
    self.scanReasonText = nil
    self.scanReasons = {}

    local scanned = Shatter.ItemScanner:ScanBags()
    local items = scanned
    local settings = Shatter.Database and Shatter.Database:GetSettings()
    local simulation = settings and settings.debug and settings.simulateDisenchant
    if Shatter.Session then
        items = {}
        for _, item in ipairs(scanned) do
            local simulated = simulation and Shatter.Session:IsQueueItemSimulated(item.queueId)
            local skipped = Shatter.Session:IsQueueItemSkipped(item.queueId)
            if not simulated and not skipped then
                table.insert(items, item)
            end
        end
    end
    Shatter.Queue:SetItems(items)
    local selected = Shatter.Queue:GetSelected()
    local selectedQueueId = selected and selected.queueId or nil
    if Shatter.Session then Shatter.Session:SetQueuedCount(#items) end
    if Shatter.MainFrame then Shatter.MainFrame:Update() end

    local countChanged = self.lastEligibleCount ~= #items
    local selectedChanged = self.lastSelectedQueueId ~= selectedQueueId
    local important = IsImportantReason(reason)
    if Shatter.Debug then
        if settings and settings.traceDebug then
            Shatter.Debug:Log("trace", "Solo scan completed: %d eligible item%s. Selected: %s. Reason: %s.", #items, #items == 1 and "" or "s", selectedQueueId or "none", reason)
        elseif countChanged or selectedChanged or important then
            Shatter.Debug:Log("debug", "Solo scan updated: %d eligible item%s. Reason: %s.", #items, #items == 1 and "" or "s", reason)
        end
    end
    self.lastEligibleCount = #items
    self.lastSelectedQueueId = selectedQueueId
    self.isScanning = false

    if self.rescanAfterCurrent then
        self.rescanAfterCurrent = false
        self:ScheduleScan("FOLLOW_UP", 0.15)
    end
end
