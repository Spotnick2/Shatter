local _, Shatter = ...

local ItemScanner = {}
Shatter.ItemScanner = ItemScanner
Shatter.RegisterModule("ItemScanner", ItemScanner)

local API = Shatter.API

-- C_Container.GetContainerItemInfo returns a struct on this client; isBound
-- replaces the old tooltip scan for "Soulbound" (localized text).
local function GetContainerItemSafe(bag, slot)
    local info = API.GetContainerItemInfo(bag, slot)
    if type(info) ~= "table" then return nil end
    return info.itemID, info.hyperlink, info.iconFileID, info.stackCount, info.isBound and true or false, info.isLocked and true or false
end

local function ParseItemID(link)
    if not link then return nil end
    return tonumber(string.match(link, "item:(%d+)"))
end

local function GetInstantInfo(item)
    local _, _, _, equipLoc, icon, classID, subclassID = API.GetItemInfoInstant(item)
    return equipLoc, icon, classID, subclassID
end

function ItemScanner:HasDisenchantSpell()
    return API.IsSpellKnown(Shatter.Constants.SPELL_DISENCHANT)
end

function ItemScanner:IsCandidateDisenchantable(item)
    local settings = Shatter.Database:GetSettings()
    if not item or not item.itemID then return false, "missing item" end
    if Shatter.Database:IsIgnored(item.itemID) then return false, "ignored" end
    if Shatter.Constants.NON_DISENCHANTABLE[item.itemID] then return false, "denylisted" end
    if not item.quality or item.quality < Shatter.Constants.QUALITY_UNCOMMON then return false, "quality too low" end
    if item.quality > (settings.maxQuality or Shatter.Constants.DEFAULT_MAX_QUALITY) then return false, "quality too high" end
    if item.isSoulbound and not settings.includeSoulbound then return false, "soulbound" end

    local classID = item.classID
    local equipLoc = item.equipLoc
    local isEquipmentClass = classID == Shatter.Constants.ITEM_CLASS_WEAPON or classID == Shatter.Constants.ITEM_CLASS_ARMOR
    if classID and not isEquipmentClass then
        return false, "not weapon or armor"
    end
    if not equipLoc or not Shatter.Constants.DISENCHANT_EQUIP_LOCS[equipLoc] then
        return false, "not equipment"
    end

    return true
end

function ItemScanner:BuildItem(bag, slot)
    local itemID, link, texture, count, isBound, isLocked = GetContainerItemSafe(bag, slot)
    itemID = itemID or ParseItemID(link)
    if not itemID and not link then return nil end

    local name, itemLink, quality, itemLevel, _, className, subclassName, _, equipLoc, itemTexture, _, classID, subclassID = API.GetItemInfo(link or itemID)
    local instantEquipLoc, instantTexture, instantClassID, instantSubclassID = GetInstantInfo(link or itemID)

    if not name then
        return nil, "item info pending"
    end

    local item = {
        mode = Shatter.Constants.MODES.SOLO,
        sourceId = nil,
        bag = bag,
        slot = slot,
        itemID = itemID,
        itemLink = itemLink or link,
        itemName = name,
        texture = itemTexture or instantTexture or texture,
        itemTexture = itemTexture or instantTexture or texture,
        count = count or 1,
        quality = quality,
        itemLevel = itemLevel,
        className = className,
        subclassName = subclassName,
        classID = classID or instantClassID,
        subclassID = subclassID or instantSubclassID,
        equipLoc = equipLoc or instantEquipLoc,
        isSoulbound = isBound,
        isLocked = isLocked,
        expectedMats = nil,
        expectedValueCopper = nil,
        status = "queued",
    }
    item.queueId = string.format("solo:%d:%d:%d", bag or 0, slot or 0, itemID or 0)
    return item
end

function ItemScanner:ScanBags()
    local items = {}
    local pendingInfo = false
    local reserved, reservedIDs = {}, {}
    if Shatter.MailSession then reserved, reservedIDs = Shatter.MailSession:GetReservedSlots() end

    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, API.GetContainerNumSlots(bag) do
            local item, reason = self:BuildItem(bag, slot)
            if item and (reserved[bag .. ":" .. slot] == item.itemID or reservedIDs[item.itemID]) then
                item = nil   -- received for a mail session: not the player's to disenchant here
            elseif item then
                local ok = self:IsCandidateDisenchantable(item)
                if ok then
                    if Shatter.DisenchantTables then
                        local estimate = Shatter.DisenchantTables:GetExpected(item)
                        item.expectedMats = estimate and estimate.materials or nil
                        item.expectedValueCopper = estimate and estimate.expectedValueCopper or nil
                        item.valueSource = estimate and estimate.valueSource or nil
                        item.expectedEstimate = estimate
                    end
                    local settings = Shatter.Database and Shatter.Database:GetSettings() or {}
                    local threshold = tonumber(settings.minExpectedValueCopper) or 0
                    local valueAllowed = true
                    if settings.useAuctionData and threshold > 0 and item.expectedValueCopper then
                        valueAllowed = item.expectedValueCopper >= threshold
                    end
                    if valueAllowed then
                        table.insert(items, item)
                    end
                end
            elseif reason == "item info pending" then
                pendingInfo = true
            end
        end
    end

    table.sort(items, function(a, b)
        if a.quality ~= b.quality then return (a.quality or 0) > (b.quality or 0) end
        if (a.itemLevel or 0) ~= (b.itemLevel or 0) then return (a.itemLevel or 0) > (b.itemLevel or 0) end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)

    return items, pendingInfo
end
