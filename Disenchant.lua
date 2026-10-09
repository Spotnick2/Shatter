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
    local spellName = Shatter.API.GetSpellName(spellID)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if value == spellID or (spellName and value == spellName) then
            return true
        end
    end
    return false
end

-- The secure action. type=spell runs CastSpellByID(13262) (no localized
-- name involved), and Blizzard's own OnActionButtonClick then uses
-- target-bag/target-slot ONLY while the spell is waiting for an item target
-- (SpellCanTargetItem; Blizzard_FrameXML/SecureTemplates.lua). A cast that
-- never starts therefore never uses - equips - the item, which the old
-- "/cast Disenchant" + "/use bag slot" macro could.
--
-- The button acts on the mouse-UP edge only: its useOnKeyDown attribute is
-- false (set at creation), which SecureActionButton_OnClick reads before the
-- ActionButtonUseKeyDown CVar. Shatter's own PreClick/PostClick work runs on
-- that edge and for the left button only (Disenchant:IsActionEdge).
--
-- Attributes cannot change in combat. The button is armed in PreClick and
-- disarmed in PostClick of the same click, so it is never left armed; in
-- combat it stays disarmed and Shatter Next does nothing.
local function ClearButtonAction(button)
    if not button or InCombatLockdown() then return false end
    button:SetAttribute("*type1", nil)
    button:SetAttribute("*spell1", nil)
    button:SetAttribute("*target-bag1", nil)
    button:SetAttribute("*target-slot1", nil)
    return true
end

-- "*type1" goes last: until it is set the secure handler has no action, so
-- an error part-way through leaves nothing to dispatch.
local function ArmButton(button, bag, slot)
    button:SetAttribute("*target-bag1", bag)
    button:SetAttribute("*target-slot1", slot)
    button:SetAttribute("*spell1", Shatter.Constants.SPELL_DISENCHANT)
    button:SetAttribute("*type1", "spell")
end

-- True for the one edge on which the secure button acts: left button, up.
function Disenchant:IsActionEdge(mouseButton, down)
    return mouseButton == "LeftButton" and not down
end

function Disenchant:Disarm(button)
    return ClearButtonAction(button or self.button)
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
        free, bagType = Shatter.API.GetContainerNumFreeSlots(bag)
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
    Shatter.Events:Register("UNIT_SPELLCAST_STOP", self, self.OnEvent)
    Shatter.Events:Register("UNIT_SPELLCAST_DELAYED", self, self.OnEvent)
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
    if current.isLocked then
        return false, Shatter.Constants.STATUS.ITEM_LOCKED
    end

    local ok, reason = Shatter.ItemScanner:IsCandidateDisenchantable(current)
    if not ok then
        return false, "Item is no longer eligible: " .. tostring(reason)
    end
    return true, current
end

function Disenchant:BeginSecureClick(button)
    local item = Shatter.Queue and Shatter.Queue:GetSelected()
    self:Trace("Shatter Next clicked")
    if not button or not item or not Shatter.isActive or not Shatter.Events:IsHealthy() then
        ClearButtonAction(button)
        return
    end
    if InCombatLockdown() then
        -- Attributes are locked: the button stays disarmed and does nothing.
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus(Shatter.Constants.STATUS.IN_COMBAT, true, 3) end
        return
    end
    if self.pending then
        ClearButtonAction(button)
        return
    end
    -- Another spell's item cursor would take this item (Blizzard targets
    -- target-bag/slot whenever SpellCanTargetItem is true), and a cast in
    -- progress makes this one fail.
    if SpellIsTargeting() or UnitCastingInfo("player") then
        ClearButtonAction(button)
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus(Shatter.Constants.STATUS.BUSY_CASTING, true, 3) end
        return
    end
    self:Trace("Selected item: %s bag=%s slot=%s itemID=%s", item.itemLink or item.itemName or "?", tostring(item.bag), tostring(item.slot), tostring(item.itemID))

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

    -- Everything that tracks the result is set up BEFORE the button is armed.
    -- An error in PreClick does not cancel the secure action, so a failure
    -- here must leave the button disarmed and nothing pending.
    local ok, err = pcall(function()
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
        self:StartTimeout()
    end)
    if not ok then
        self.pending = nil
        self.finalizing = false
        ClearButtonAction(button)
        Shatter.Print("|cffff4444Shatter Next was not started:|r " .. tostring(err))
        return
    end

    ArmButton(button, current.bag, current.slot)
    self:Trace("Armed Disenchant on bag %d slot %d", current.bag, current.slot)

    -- Presentation only; an error here no longer affects what the click does.
    if Shatter.MainFrame then
        pcall(function()
            Shatter.MainFrame:SetStatus(Shatter.Constants.STATUS.WAITING_RESULT, false)
            Shatter.MainFrame:ShowCastBar("Starting Disenchant...", 0, "pulse")
            Shatter.MainFrame:Update()
        end)
    end
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
        Shatter.MainFrame:ShowCastBar("Simulating: " .. (item.itemLink or item.itemName or "item"), 0.25, "timed")
        Shatter.MainFrame:Update()
    end

    Shatter.Events:After(0.25, function()
        if not self.pending or not self.pending.simulated then return end
        local result = GetSimulatedResult(item)
        if Shatter.Session then
            Shatter.Session:RecordResult(item, result, { simulated = true })
        end
        if Shatter.Debug then
            Shatter.Debug:Log("trace", "Simulated disenchant result: %s", Shatter.MaterialTracker and Shatter.MaterialTracker:Format(result) or "unknown")
        end
        self.pending = nil
        self.finalizing = false
        if item.mode ~= Shatter.Constants.MODES.MAIL and Shatter.SoloMode then
            Shatter.SoloMode:ScheduleScan("SIMULATION_RESULT", 0.1)
        end
        if Shatter.MainFrame then
            Shatter.MainFrame:HideCastBar()
            Shatter.MainFrame:SetStatus("Simulated result recorded.", false)
            Shatter.MainFrame:Update()
        end
    end)
end

function Disenchant:Finish()
    ClearButtonAction(self.button)
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
        self:Trace("Finish check: disappeared=%s result=%s", tostring(itemDisappeared), Shatter.MaterialTracker and Shatter.MaterialTracker:Format(result or {}) or "unknown")

        if Shatter.Session then
            Shatter.Session:RecordResult(pending.item, result or {})
        end

        self.pending = nil
        self.finalizing = false

        if Shatter.Debug then
            Shatter.Debug:Log("trace", "Disenchant result: %s", Shatter.MaterialTracker and Shatter.MaterialTracker:Format(result or {}) or "unknown")
        end

        if pending.item.mode ~= Shatter.Constants.MODES.MAIL and Shatter.SoloMode then
            Shatter.SoloMode:ScheduleScan("DISENCHANT_RESOLVED", 0.1)
        end
        if Shatter.MainFrame then
            Shatter.MainFrame:HideCastBar()
            Shatter.MainFrame:SetStatus("Disenchanted: " .. (pending.item.itemLink or pending.item.itemName or "item"), false, 3)
            Shatter.MainFrame:Update()
        end
    end)
end

function Disenchant:Fail(reason)
    ClearButtonAction(self.button)
    if not self.pending then return end
    self.pending = nil
    self.finalizing = false
    if Shatter.Session then Shatter.Session:FailPending(reason) end
    if Shatter.MainFrame then
        Shatter.MainFrame:HideCastBar()
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
        if Shatter.MainFrame then
            Shatter.MainFrame:SetStatus(Shatter.Constants.STATUS.WAITING_RESULT, false)
            Shatter.MainFrame:ShowWaitingForResult(self.pending.item, self.timeoutSeconds)
        end
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
        if Shatter.MainFrame then
            local name, _, _, startTimeMS, endTimeMS = UnitCastingInfo and UnitCastingInfo("player")
            Shatter.MainFrame:ShowCastProgress(name or "Disenchanting...", self.pending.item, startTimeMS, endTimeMS)
        end
    elseif event == "UNIT_SPELLCAST_STOP" then
        if not self.pending.succeeded and Shatter.MainFrame then
            Shatter.MainFrame:ShowWaitingForResult(self.pending.item, self.timeoutSeconds)
        end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        self:Fail(Shatter.Constants.STATUS.DISENCHANT_FAILED)
    end
end
