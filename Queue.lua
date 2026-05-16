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

function Queue:SetItems(items)
    local previous = self:GetSelected()
    local previousId = previous and previous.queueId
    self.items = items or {}
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
