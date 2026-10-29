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

-- A fake result for /shatter sim, from the same Vanilla rules the estimates
-- use: the most likely material, at its minimum amount. No rule, no result.
local function GetSimulatedResult(item)
    local result = {}
    local estimate = Shatter.DisenchantTables and Shatter.DisenchantTables:GetExpected(item)
    local top = estimate and estimate.materials and estimate.materials[1]
    if top then
        AddResult(result, top.itemID, top.minAmount or 1)
    end
    return result
end
Disenchant._GetSimulatedResult = GetSimulatedResult

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
    -- A mail item must be the very instance received: a personal copy moved
    -- into its slot has the same itemID. Without a GUID nothing proves which
    -- copy is there, so the mail action is refused.
    if item.mode == Shatter.Constants.MODES.MAIL then
        if not item.itemGUID then
            return false, Shatter.Constants.STATUS.MAIL_ITEM_UNVERIFIED
        end
        if Shatter.API.GetBagItemGUID(item.bag, item.slot) ~= item.itemGUID then
            return false, Shatter.Constants.STATUS.MAIL_ITEM_MOVED
        end
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
    -- The item must come from the queue the visible view owns: a Mail view
    -- disenchants only attributed mail items, the Solo view only bag items.
    local view = Shatter.MainFrame and Shatter.MainFrame.activeView
    local wantMode = view == "mail" and Shatter.Constants.MODES.MAIL or Shatter.Constants.MODES.SOLO
    local owner = Shatter.Queue:GetOwner()
    if item.mode ~= wantMode or (wantMode == Shatter.Constants.MODES.MAIL) ~= (owner == "mail") then
        ClearButtonAction(button)
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus(Shatter.Constants.STATUS.QUEUE_MISMATCH, true, 3) end
        return
    end
    if wantMode == Shatter.Constants.MODES.MAIL and not Shatter.MailMode:AreActionsEnabled() then
        ClearButtonAction(button)
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus(Shatter.Constants.STATUS.MAIL_ACTIONS_DISABLED, true, 4) end
        return
    end
    -- Another spell's item cursor would take this item (Blizzard targets
    -- target-bag/slot whenever SpellCanTargetItem is true), and a cast in
    -- progress (cast or channel) makes this one fail.
    if SpellIsTargeting() or UnitCastingInfo("player") or UnitChannelInfo("player") then
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
    -- ValidateItem rebuilt the item from the bag slot (as Solo, unattributed).
    -- Keep the queued item's identity: a mail item's result must be credited
    -- to its sender.
    for _, key in ipairs({ "mode", "sourceId", "sourceSender", "sourceMailId", "queueId", "queueSequence" }) do
        current[key] = item[key]
    end

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
            self:Finish("timeout")
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

-- `trigger` says what ended the attempt ("loot closed", "bag update",
-- "timeout"), for the late-loot trace (#10).
function Disenchant:Finish(trigger)
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

        -- Measured yields learn only from this cast's loot window, with the
        -- item gone: a bag diff can include anything else that arrived.
        -- Recorded before the session result, which rebuilds a Mail queue
        -- (and its estimates) synchronously.
        if itemDisappeared and Shatter.DisenchantTables then
            Shatter.DisenchantTables:RecordYield(pending.item, pending.loot)
        end
        if Shatter.Session then
            Shatter.Session:RecordResult(pending.item, result or {})
        end

        self.pending = nil
        self.finalizing = false
        -- Kept for the late-loot trace only (#10); never persisted.
        self.lastResolved = {
            itemID = pending.item.itemID, at = GetTime(), by = trigger or "?",
            lootEvent = pending.lootEvent == true,
            lootRead = not (Shatter.MaterialTracker and Shatter.MaterialTracker:IsEmpty(pending.loot)),
        }

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

-- Item ids and counts, plainly: "10940x2 10978x1", or "nothing".
local function LootText(loot)
    local parts = {}
    for itemID, count in pairs(loot or {}) do parts[#parts + 1] = itemID .. "x" .. count end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, " ") or "nothing"
end

-- #10: a loot window that opens after the attempt resolved isn't measured,
-- and one that opens while the NEXT attempt is pending is taken as that
-- attempt's (the handler below doesn't wait for success). Neither is fixed
-- before the order is observed on Forever: until then, with tracing on, every
-- loot event says what it read, how long after which attempt resolved (and
-- whether that attempt had a loot event, and read any loot), and what is
-- pending now. Built only while tracing: Debug:Log formats before it checks.
function Disenchant:TraceLoot(event, ...)
    local settings = Shatter.Database and Shatter.Database:GetSettings()
    if not (settings and settings.traceDebug) then return end
    local flags = ""
    if event == "LOOT_OPENED" then
        local autoLoot, isFromItem = ...
        flags = string.format(" (autoLoot %s, isFromItem %s)", tostring(autoLoot), tostring(isFromItem))
    elseif event == "LOOT_READY" then
        flags = string.format(" (autoloot %s)", tostring((...)))
    end
    local reads = ""
    if event ~= "LOOT_CLOSED" and Shatter.MaterialTracker then
        reads = ", reads " .. LootText(Shatter.MaterialTracker:ReadLoot())
    end
    local last, p = self.lastResolved, self.pending
    local since = last and string.format("%.2f s after item %s resolved (%s; loot event %s, loot read %s)",
        GetTime() - last.at, tostring(last.itemID), last.by, last.lootEvent and "yes" or "none",
        last.lootRead and "yes" or "none") or "no attempt resolved yet"
    local now = p and string.format("attempt %s pending, %s", tostring(p.item and p.item.itemID),
        p.succeeded and "succeeded" or "not succeeded") or "nothing pending"
    self:Trace("Loot event %s%s%s; %s; %s", event, flags, reads, since, now)
end

function Disenchant:OnEvent(event, ...)
    if event == "LOOT_READY" or event == "LOOT_OPENED" or event == "LOOT_CLOSED" then
        self:TraceLoot(event, ...)
    end
    -- Every error is traced, pending or not: a refusal may arrive after the
    -- cast's FAILED has cleared the attempt (Nov 4: which error, in which
    -- order, for the "can't be disenchanted" learning #6 deferred).
    if event == "UI_ERROR_MESSAGE" then
        local errorType, message = ...
        local p = self.pending
        self:Trace("UI error %s: %s (attempt: %s)", tostring(errorType), tostring(message),
            p and string.format("item %s%s%s", tostring(p.item and p.item.itemID),
                p.simulated and ", simulated" or "", p.succeeded and ", succeeded" or "") or "none")
        return
    end
    if not self.pending then return end
    self:Trace("Event received while pending: %s", tostring(event))

    if event == "LOOT_OPENED" or event == "LOOT_READY" then
        self.pending.lootEvent = true
        -- Autoloot can empty slots between LOOT_READY and LOOT_OPENED, so a
        -- later read may miss what an earlier one saw: keep the most seen
        -- of each item rather than the last read.
        if Shatter.MaterialTracker then
            local loot = self.pending.loot or {}
            for itemID, count in pairs(Shatter.MaterialTracker:ReadLoot()) do
                loot[itemID] = math.max(loot[itemID] or 0, count)
            end
            self.pending.loot = loot
        end
        if Shatter.MainFrame then Shatter.MainFrame:SetStatus(Shatter.Constants.STATUS.WAITING_RESULT, false) end
        return
    elseif event == "LOOT_CLOSED" then
        self:Finish("loot closed")
        return
    elseif event == "BAG_UPDATE" then
        self.pending.bagUpdated = true
        return
    elseif event == "BAG_UPDATE_DELAYED" then
        self.pending.bagUpdated = true
        if self.pending.succeeded or not self:PendingItemStillExists() then
            self:Finish("bag update")
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
