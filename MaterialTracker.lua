local _, Shatter = ...

local MaterialTracker = {}
Shatter.MaterialTracker = MaterialTracker
Shatter.RegisterModule("MaterialTracker", MaterialTracker)

local function ParseItemID(link)
    if not link then return nil end
    local itemID = string.match(link, "item:(%d+)")
    return tonumber(itemID)
end

function MaterialTracker:Initialize()
end

function MaterialTracker:GetItemCount(itemID)
    itemID = tonumber(itemID)
    if not itemID then return 0 end
    if C_Item and C_Item.GetItemCount then
        return C_Item.GetItemCount(itemID, false, false, false) or 0
    end
    if GetItemCount then
        return GetItemCount(itemID, false) or 0
    end
    return 0
end

function MaterialTracker:Snapshot()
    local snapshot = {}
    for itemID in pairs(Shatter.Constants.MATERIAL_ITEM_IDS) do
        snapshot[itemID] = self:GetItemCount(itemID)
    end
    return snapshot
end

function MaterialTracker:Diff(before, after)
    local diff = {}
    before = before or {}
    after = after or self:Snapshot()
    for itemID in pairs(Shatter.Constants.MATERIAL_ITEM_IDS) do
        local delta = (after[itemID] or 0) - (before[itemID] or 0)
        if delta > 0 then
            diff[itemID] = delta
        end
    end
    return diff
end

function MaterialTracker:ReadLoot()
    local result = {}
    if not GetNumLootItems then return result end
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local itemID = ParseItemID(link)
        local _, _, quantity = GetLootSlotInfo(slot)
        quantity = tonumber(quantity) or 0
        if itemID and quantity > 0 then
            result[itemID] = (result[itemID] or 0) + quantity
        end
    end
    return result
end

function MaterialTracker:IsEmpty(result)
    if not result then return true end
    for _, count in pairs(result) do
        if count and count > 0 then return false end
    end
    return true
end

function MaterialTracker:Format(result)
    if self:IsEmpty(result) then
        return "No result recorded"
    end
    local parts = {}
    for itemID, count in pairs(result) do
        local name, link = GetItemInfo(itemID)
        table.insert(parts, string.format("%sx%d", link or name or tostring(itemID), count))
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end
