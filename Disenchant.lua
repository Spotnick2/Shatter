local _, Shatter = ...

local Disenchant = {
    button = nil,
    pending = nil,
    finalizing = false,
    timeoutSeconds = 8,
}

Shatter.Disenchant = Disenchant
Shatter.RegisterModule("Disenchant", Disenchant)

local function SpellMatches(...)
    local spellID = Shatter.Constants.SPELL_DISENCHANT
    local spellName = GetSpellInfo and GetSpellInfo(spellID)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if value == spellID or (spellName and value == spellName) then
            return true
        end
    end
    return false
end

local function ClearButtonAction(button)
    if not button then return end
    button:SetAttribute("*type1", "macro")
    button:SetAttribute("*macrotext1", "")
end

local function AddResult(result, itemID, count)
    if not itemID or not count or count <= 0 then return end
    result[itemID] = (result[itemID] or 0) + count
end

local function GetSimulatedResult(item)
    local result = {}
    local itemLevel = item and item.itemLevel or 0
    local quality = item and item.quality or 2
    local isOutland = itemLevel >= 80

    if quality >= Shatter.Constants.QUALITY_EPIC then
        AddResult(result, isOutland and 22450 or 20725, 1)
    elseif quality >= Shatter.Constants.QUALITY_RARE then
        AddResult(result, isOutland and 22449 or 14344, 1)
    else
        if isOutland then
            AddResult(result, 22445, math.max(1, math.floor((itemLevel - 80) / 25) + 1))
        elseif itemLevel >= 56 then
            AddResult(result, 16204, 2)
        elseif itemLevel >= 46 then
            AddResult(result, 11176, 2)
        elseif itemLevel >= 36 then
            AddResult(result, 11137, 2)
        elseif itemLevel >= 26 then
            AddResult(result, 11083, 2)
        else
            AddResult(result, 10940, 2)
        end
    end

    return result
end

local function HasInventorySpace()
    for bag = 0, NUM_BAG_SLOTS do
        local free, bagType
        if C_Container and C_Container.GetContainerNumFreeSlots then
            free, bagType = C_Container.GetContainerNumFreeSlots(bag)
        elseif GetContainerNumFreeSlots then
            free, bagType = GetContainerNumFreeSlots(bag)
        end
        if (bagType or 0) == 0 and (free or 0) > 0 then
            return true
        end
    end
    return false
end

function Disenchant:IsSimulationEnabled()
    local settings = Shatter.Database and Shatter.Database:GetSettings()
    return settings and settings.debug == true and settings.simulateDisenchant == true
end

function Disenchant:Initialize()
    if not Shatter.Events then return end
    Shatter.Events:Register("UNIT_SPELLCAST_START", self, self.OnEvent)
    Shatter.Events:Register("UNIT_SPELLCAST_SUCCEEDED", self, self.OnEvent)
    Shatter.Events:Register("UNIT_SPELLCAST_FAILED", self, self.OnEvent)
    Shatter.Events:Register("UNIT_SPELLCAST_FAILED_QUIET", self, self.OnEvent)
    Shatter.Events:Register("UNIT_SPELLCAST_INTERRUPTED", self, self.OnEvent)
    Shatter.Events:Register("LOOT_OPENED", self, self.OnEvent)
    Shatter.Events:Register("LOOT_READY", self, self.OnEvent)
    Shatter.Events:Register("LOOT_CLOSED", self, self.OnEvent)
    Shatter.Events:Register("BAG_UPDATE_DELAYED", self, self.OnEvent)
    Shatter.Events:Register("BAG_UPDATE", self, self.OnEvent)
    Shatter.Events:Register("CHAT_MSG_LOOT", self, self.OnEvent)
    Shatter.Events:Register("CURRENT_SPELL_CAST_CHANGED", self, self.OnEvent)
    Shatter.Events:Register("UI_ERROR_MESSAGE", self, self.OnEvent)
end

function Disenchant:SetButton(button)
    self.button = button
end

function Disenchant:HasPending()
    return self.pending ~= nil
end

function Disenchant:Debug(message, ...)
    if Shatter.Debug then
        Shatter.Debug:Log("debug", message, ...)
    end
end

function Disenchant:Trace(message, ...)
    if Shatter.Debug then
        Shatter.Debug:Log("trace", message, ...)
    end
end

function Disenchant:GetBagItem(bag, slot)
    if Shatter.ItemScanner then
        return Shatter.ItemScanner:BuildItem(bag, slot)
    end
    return nil
end

function Disenchant:PendingItemStillExists()
    if not self.pending or not self.pending.item then return false end
    local item = self.pending.item
    local current = self:GetBagItem(item.bag, item.slot)
    return current and current.itemID == item.itemID
end

function Disenchant:ValidateItem(item)
    if not item then
        return false, "No item selected."
    end
    if not Shatter.ItemScanner or not Shatter.ItemScanner:HasDisenchantSpell() then
        return false, Shatter.Constants.STATUS.MISSING_ENCHANTING
    end

    local current = self:GetBagItem(item.bag, item.slot)
    if not current or current.itemID ~= item.itemID then
        return false, Shatter.Constants.STATUS.ITEM_MISSING
    end

    local ok, reason = Shatter.ItemScanner:IsCandidateDisenchantable(current)
    if not ok then
        return false, "Item is no longer eligible: " .. tostring(reason)
    end
    return true, current
end

function Disenchant:BeginSecureClick(button)
    local item = Shatter.Queue and Shatter.Queue:GetSelected()
    self:Debug("Shatter Next clicked")
    if not button or not item then
        ClearButtonAction(button)
        return
    end
    self:Debug("Selected item: %s bag=%s slot=%s itemID=%s", item.itemLink or item.itemName or "?", tostring(item.bag), tostring(item.slot), tostring(item.itemID))

    if not self:IsSimulationEnabled() and not HasInventorySpace() then
        ClearButtonAction(button)
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus(Shatter.Constants.STATUS.INVENTORY_FULL, true) end
        return
    end

    local valid, currentOrReason = self:ValidateItem(item)
    if not valid then
        ClearButtonAction(button)
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus(currentOrReason, true) end
        self:Debug("Validation failed: %s", tostring(currentOrReason))
        return
    end
    local current = currentOrReason

    if self:IsSimulationEnabled() then
        ClearButtonAction(button)
        self:Simulate(item)
        return
    end

    local spellName = GetSpellInfo and GetSpellInfo(Shatter.Constants.SPELL_DISENCHANT) or "Disenchant"
    local macro = string.format("/cast %s;\n/use %d %d", spellName, current.bag, current.slot)

    button:SetAttribute("*type1", "macro")
    button:SetAttribute("*macrotext1", macro)
    self:Debug("Prepared secure macro: /cast %s ; /use %d %d", tostring(spellName), current.bag, current.slot)

    self.pending = {
        item = current,
        before = Shatter.MaterialTracker and Shatter.MaterialTracker:Snapshot() or {},
        loot = nil,
        succeeded = false,
        bagUpdated = false,
        chatLoot = false,
        startedAt = GetTime and GetTime() or 0,
    }
    self.finalizing = false

    if Shatter.Session then Shatter.Session:BeginAction(item) end
    if Shatter.MainFrame then
        Shatter.MainFrame:SetStatus(Shatter.Constants.STATUS.WAITING_RESULT, false)
        Shatter.MainFrame:Update()
    end
    self:StartTimeout()
end

function Disenchant:StartTimeout()
    local pending = self.pending
    if not pending or not Shatter.Events then return end
    Shatter.Events:After(self.timeoutSeconds, function()
        if self.pending ~= pending or self.finalizing then return end
        self:Debug("Pending timeout reached")
        if self:PendingItemStillExists() then
            self:Fail("Failed: item still exists after timeout.")
        else
            self:Finish("timeout item disappeared")
        end
    end)
end

function Disenchant:Simulate(item)
    if self.pending then return end

    self.pending = {
        item = item,
        before = {},
        loot = nil,
        succeeded = true,
        simulated = true,
        startedAt = GetTime and GetTime() or 0,
    }
    self.finalizing = false

    if Shatter.Session then Shatter.Session:BeginAction(item) end
    if Shatter.MainFrame then
        Shatter.MainFrame:SetStatus("Simulating " .. (item.itemLink or item.itemName or "item") .. "...", false)
        Shatter.MainFrame:Update()
    end

    Shatter.Events:After(0.25, function()
        if not self.pending or not self.pending.simulated then return end
        local result = GetSimulatedResult(item)
        if Shatter.Session then
            Shatter.Session:RecordResult(item, result, { simulated = true })
        end
        if Shatter.Debug then
            Shatter.Debug:Log("debug", "Simulated disenchant result: %s", Shatter.MaterialTracker and Shatter.MaterialTracker:Format(result) or "unknown")
        end
        self.pending = nil
        self.finalizing = false
        if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("SIMULATION_RESULT", 0.1) end
        if Shatter.MainFrame then
            Shatter.MainFrame:SetStatus("Simulated result recorded.", false)
            Shatter.MainFrame:Update()
        end
    end)
end

function Disenchant:Finish()
    if not self.pending or self.finalizing then return end
    self.finalizing = true

    Shatter.Events:After(0.2, function()
        local pending = self.pending
        if not pending then return end

        local result = pending.loot
        local itemDisappeared = not self:PendingItemStillExists()
        if Shatter.MaterialTracker and Shatter.MaterialTracker:IsEmpty(result) then
            result = Shatter.MaterialTracker:Diff(pending.before, Shatter.MaterialTracker:Snapshot())
        end
        self:Debug("Finish check: disappeared=%s result=%s", tostring(itemDisappeared), Shatter.MaterialTracker and Shatter.MaterialTracker:Format(result or {}) or "unknown")

        if Shatter.Session then
            Shatter.Session:RecordResult(pending.item, result or {})
        end

        self.pending = nil
        self.finalizing = false

        if Shatter.Debug then
            Shatter.Debug:Log("debug", "Disenchant result: %s", Shatter.MaterialTracker and Shatter.MaterialTracker:Format(result or {}) or "unknown")
        end

        if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("DISENCHANT_RESOLVED", 0.1) end
        if Shatter.MainFrame then
            Shatter.MainFrame:SetStatus("Disenchanted: " .. (pending.item.itemLink or pending.item.itemName or "item"), false, 3)
            Shatter.MainFrame:Update()
        end
    end)
end

function Disenchant:Fail(reason)
    if not self.pending then return end
    self.pending = nil
    self.finalizing = false
    if Shatter.Session then Shatter.Session:FailPending(reason) end
    if Shatter.MainFrame then
        Shatter.MainFrame:SetStatus(reason or "Disenchant failed", true, 3)
        Shatter.MainFrame:Update()
    end
end

function Disenchant:OnEvent(event, ...)
    if not self.pending then return end
    self:Trace("Event received while pending: %s", tostring(event))

    if event == "LOOT_OPENED" or event == "LOOT_READY" then
        if Shatter.MaterialTracker then
            self.pending.loot = Shatter.MaterialTracker:ReadLoot()
        end
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus(Shatter.Constants.STATUS.WAITING_RESULT, false) end
        return
    elseif event == "LOOT_CLOSED" then
        self:Finish()
        return
    elseif event == "BAG_UPDATE" then
        self.pending.bagUpdated = true
        return
    elseif event == "BAG_UPDATE_DELAYED" then
        self.pending.bagUpdated = true
        if self.pending.succeeded or not self:PendingItemStillExists() then
            self:Finish()
        end
        return
    elseif event == "CHAT_MSG_LOOT" then
        self.pending.chatLoot = true
        return
    elseif event == "CURRENT_SPELL_CAST_CHANGED" then
        if not self.pending.succeeded and not SpellIsTargeting() and self:PendingItemStillExists() then
            self:Trace("Spell targeting ended without success")
        end
        return
    elseif event == "UI_ERROR_MESSAGE" then
        local message = select(2, ...) or select(1, ...)
        self:Trace("UI error: %s", tostring(message))
        return
    end

    local unit = select(1, ...)
    if unit and unit ~= "player" then return end
    if not SpellMatches(...) then return end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        self.pending.succeeded = true
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus(Shatter.Constants.STATUS.WAITING_RESULT, false) end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        self:Fail(Shatter.Constants.STATUS.DISENCHANT_FAILED)
    end
end
