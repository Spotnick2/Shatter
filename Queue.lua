local _, Shatter = ...

-- The queue has one owner at a time: "solo" (bag scan) or "mail" (items
-- taken from a mail session, each attributed to its sender). A Solo scan must
-- never replace a Mail queue: Shatter Next would then destroy whatever the
-- bag scan selected and record it against nobody.
local Queue = {
    items = {},
    selectedIndex = 1,
    owner = "solo",
}

Shatter.Queue = Queue
Shatter.RegisterModule("Queue", Queue)

function Queue:Initialize()
    self.items = {}
    self.selectedIndex = 1
    self.owner = "solo"
end

function Queue:GetOwner()
    return self.owner or "solo"
end

-- Hands the queue back to Solo (mail queue finished, session closed, or the
-- player switched to the Solo view) and rebuilds it from the bags.
function Queue:ReleaseToSolo(reason)
    if self.owner == "solo" then return end
    self.owner = "solo"
    self.items = {}
    self.selectedIndex = 1
    if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan(reason or "MAIL_RELEASED", 0.05) end
end

local function SortBagSlot(a, b)
    if (a.bag or 0) ~= (b.bag or 0) then return (a.bag or 0) < (b.bag or 0) end
    if (a.slot or 0) ~= (b.slot or 0) then return (a.slot or 0) < (b.slot or 0) end
    return (a.itemID or 0) < (b.itemID or 0)
end

local function SortQueueItems(items)
    local mode = items and items[1] and items[1].mode
    local modeKey = mode == Shatter.Constants.MODES.MAIL and "mail" or "solo"
    local order = Shatter.Database and Shatter.Database:GetQueueOrder(modeKey) or Shatter.Constants.QUEUE_ORDER.BAG_SLOT
    for _, item in ipairs(items or {}) do
        if Shatter.Session then Shatter.Session:AssignQueueSequence(item) end
    end
    if order == Shatter.Constants.QUEUE_ORDER.FIFO then
        table.sort(items, function(a, b)
            if (a.queueSequence or 0) ~= (b.queueSequence or 0) then return (a.queueSequence or 0) < (b.queueSequence or 0) end
            return SortBagSlot(a, b)
        end)
    elseif order == Shatter.Constants.QUEUE_ORDER.LIFO then
        table.sort(items, function(a, b)
            if (a.queueSequence or 0) ~= (b.queueSequence or 0) then return (a.queueSequence or 0) > (b.queueSequence or 0) end
            return SortBagSlot(a, b)
        end)
    else
        table.sort(items, SortBagSlot)
    end
end

function Queue:SetItems(items, owner)
    owner = owner or "solo"
    if owner == "solo" and self.owner == "mail" then return false end
    self.owner = owner
    local previous = self:GetSelected()
    local previousId = previous and previous.queueId
    self.items = items or {}
    SortQueueItems(self.items)
    self.selectedIndex = 1

    if previousId then
        for index, item in ipairs(self.items) do
            if item.queueId == previousId then
                self.selectedIndex = index
                break
            end
        end
    end
    return true
end

function Queue:GetItems()
    return self.items
end

function Queue:Count()
    return #self.items
end

function Queue:GetSelected()
    return self.items[self.selectedIndex]
end

function Queue:GetNext()
    return self:GetSelected() or self.items[1]
end

function Queue:Select(index)
    index = tonumber(index) or 1
    if index < 1 then index = 1 end
    if index > #self.items then index = #self.items end
    self.selectedIndex = index
    if Shatter.MainFrame then Shatter.MainFrame:Update() end
end

function Queue:SkipSelected()
    local item = self:GetSelected()
    if not item then return end
    if Shatter.Session then Shatter.Session:SkipItem(item) end
    table.remove(self.items, self.selectedIndex)
    if self.selectedIndex > #self.items then self.selectedIndex = #self.items end
    if self.selectedIndex < 1 then self.selectedIndex = 1 end
    if Shatter.MainFrame then
        Shatter.MainFrame:SetStatus(Shatter.Constants.STATUS.ITEM_SKIPPED, false, 2)
        Shatter.MainFrame:Update()
    end
    if item.mode == Shatter.Constants.MODES.MAIL and Shatter.MailMode then
        Shatter.MailMode:SkipQueueItem(item)
    elseif Shatter.SoloMode then
        Shatter.SoloMode:ScheduleScan("ITEM_SKIPPED", 0.05)
    end
end

function Queue:IgnoreSelected()
    local item = self:GetSelected()
    if not item then return end
    if Shatter.Session then Shatter.Session:IgnoreItem(item) end
    Shatter.Database:SetIgnored(item.itemID, true)
    table.remove(self.items, self.selectedIndex)
    if self.selectedIndex > #self.items then self.selectedIndex = #self.items end
    if self.selectedIndex < 1 then self.selectedIndex = 1 end
    if Shatter.MainFrame then Shatter.MainFrame:SetStatus(Shatter.Constants.STATUS.ITEM_IGNORED, false, 2) end
    Shatter.Print(string.format("%s is ignored from now on. Undo it in Settings (Ignored items) or with /shatter unignore %d.",
        item.itemLink or item.itemName or ("Item " .. tostring(item.itemID)), item.itemID))
    if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("ITEM_IGNORED", 0.05) end
end

-- After an unignore (#4): the item is eligible again, so both queues rescan
-- (Mail only during a session with the mailbox open) and Settings redraws.
local function Unignored(reason)
    if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan(reason, 0.05) end
    if Shatter.MailMode and Shatter.MailSession and Shatter.MailSession:HasActiveSession()
        and Shatter.MailMode:IsMailboxOpen() then
        Shatter.MailMode:ScheduleScan(reason, 0.05)
    end
    if Shatter.SettingsUI then Shatter.SettingsUI:Refresh() end
end

-- False when the item wasn't ignored.
function Queue:Unignore(itemID)
    itemID = tonumber(itemID)
    if not itemID or not Shatter.Database:IsIgnored(itemID) then return false end
    Shatter.Database:SetIgnored(itemID, false)
    Unignored("ITEM_UNIGNORED")
    return true
end

-- Returns how many items were ignored.
function Queue:ClearIgnored()
    local count = Shatter.Database:ClearIgnored()
    if count > 0 then Unignored("IGNORED_CLEARED") end
    return count
end
