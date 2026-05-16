local _, Shatter = ...

local Queue = {
    items = {},
    selectedIndex = 1,
}

Shatter.Queue = Queue
Shatter.RegisterModule("Queue", Queue)

function Queue:Initialize()
    self.items = {}
    self.selectedIndex = 1
end

local function SortBagSlot(a, b)
    if (a.bag or 0) ~= (b.bag or 0) then return (a.bag or 0) < (b.bag or 0) end
    if (a.slot or 0) ~= (b.slot or 0) then return (a.slot or 0) < (b.slot or 0) end
    return (a.itemID or 0) < (b.itemID or 0)
end

local function SortQueueItems(items)
    local order = Shatter.Database and Shatter.Database:GetQueueOrder("solo") or Shatter.Constants.QUEUE_ORDER.BAG_SLOT
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

function Queue:SetItems(items)
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
    if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("ITEM_SKIPPED", 0.05) end
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
    if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("ITEM_IGNORED", 0.05) end
end
