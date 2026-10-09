local _, Shatter = ...

local Tables = {}
Shatter.DisenchantTables = Tables
Shatter.RegisterModule("DisenchantTables", Tables)

local C = Shatter.Constants

local ARMOR = C.ITEM_CLASS_ARMOR
local WEAPON = C.ITEM_CLASS_WEAPON

-- Vanilla disenchanting, as Shatter's own compact rules:
-- { quality, classID or nil (any), minItemLevel, maxItemLevel, materialID, chance, minAmount, maxAmount }
-- Brackets per (quality, class) are contiguous and never overlap
-- (tests/test_tables.lua checks both). The top brackets are open-ended up to
-- TOP; Vanilla content ends at item level VANILLA_MAX_ITEM_LEVEL, so an item
-- above it gets the top bracket's estimate marked uncertain. None of these
-- rates has been measured on Forever yet. Expected amounts use the midpoint of
-- each min-max range, an approximation: the real spread is not always uniform
-- (an epic's 1-2 Nexus Crystals lean towards 2), so values read slightly low.
local TOP = 1000
Tables.VANILLA_MAX_ITEM_LEVEL = 92

local RULES = {
    -- Uncommon: dust (armor-heavy), essence (weapon-heavy), and a small shard chance.
    { 2, ARMOR, 5, 15, 10940, 0.80, 1, 2 }, { 2, WEAPON, 5, 15, 10940, 0.20, 1, 2 },
    { 2, ARMOR, 16, 20, 10940, 0.75, 2, 3 }, { 2, WEAPON, 16, 20, 10940, 0.20, 2, 3 },
    { 2, ARMOR, 21, 25, 10940, 0.75, 4, 6 }, { 2, WEAPON, 21, 25, 10940, 0.15, 4, 6 },
    { 2, ARMOR, 26, 30, 11083, 0.75, 1, 2 }, { 2, WEAPON, 26, 30, 11083, 0.20, 1, 2 },
    { 2, ARMOR, 31, 35, 11083, 0.75, 2, 5 }, { 2, WEAPON, 31, 35, 11083, 0.20, 2, 5 },
    { 2, ARMOR, 36, 40, 11137, 0.75, 1, 2 }, { 2, WEAPON, 36, 40, 11137, 0.20, 1, 2 },
    { 2, ARMOR, 41, 45, 11137, 0.75, 2, 5 }, { 2, WEAPON, 41, 45, 11137, 0.20, 2, 5 },
    { 2, ARMOR, 46, 50, 11176, 0.75, 1, 2 }, { 2, WEAPON, 46, 50, 11176, 0.20, 1, 2 },
    { 2, ARMOR, 51, 55, 11176, 0.75, 2, 5 }, { 2, WEAPON, 51, 55, 11176, 0.20, 2, 5 },
    { 2, ARMOR, 56, 60, 16204, 0.75, 1, 2 }, { 2, WEAPON, 56, 60, 16204, 0.20, 1, 2 },
    { 2, ARMOR, 61, TOP, 16204, 0.75, 2, 5 }, { 2, WEAPON, 61, TOP, 16204, 0.20, 2, 5 },

    { 2, ARMOR, 5, 15, 10938, 0.20, 1, 2 }, { 2, WEAPON, 5, 15, 10938, 0.80, 1, 2 },
    { 2, ARMOR, 16, 20, 10939, 0.20, 1, 2 }, { 2, WEAPON, 16, 20, 10939, 0.75, 1, 2 },
    { 2, ARMOR, 21, 25, 10998, 0.15, 1, 2 }, { 2, WEAPON, 21, 25, 10998, 0.75, 1, 2 },
    { 2, ARMOR, 26, 30, 11082, 0.20, 1, 2 }, { 2, WEAPON, 26, 30, 11082, 0.75, 1, 2 },
    { 2, ARMOR, 31, 35, 11134, 0.20, 1, 2 }, { 2, WEAPON, 31, 35, 11134, 0.75, 1, 2 },
    { 2, ARMOR, 36, 40, 11135, 0.20, 1, 2 }, { 2, WEAPON, 36, 40, 11135, 0.75, 1, 2 },
    { 2, ARMOR, 41, 45, 11174, 0.20, 1, 2 }, { 2, WEAPON, 41, 45, 11174, 0.75, 1, 2 },
    { 2, ARMOR, 46, 50, 11175, 0.20, 1, 2 }, { 2, WEAPON, 46, 50, 11175, 0.75, 1, 2 },
    { 2, ARMOR, 51, 55, 16202, 0.20, 1, 2 }, { 2, WEAPON, 51, 55, 16202, 0.75, 1, 2 },
    { 2, ARMOR, 56, 60, 16203, 0.20, 1, 2 }, { 2, WEAPON, 56, 60, 16203, 0.75, 1, 2 },
    { 2, ARMOR, 61, TOP, 16203, 0.20, 2, 3 }, { 2, WEAPON, 61, TOP, 16203, 0.75, 2, 3 },

    { 2, ARMOR, 16, 20, 10978, 0.05, 1, 1 }, { 2, WEAPON, 16, 20, 10978, 0.05, 1, 1 },
    { 2, ARMOR, 21, 25, 10978, 0.10, 1, 1 }, { 2, WEAPON, 21, 25, 10978, 0.10, 1, 1 },
    { 2, ARMOR, 26, 30, 11084, 0.05, 1, 1 }, { 2, WEAPON, 26, 30, 11084, 0.05, 1, 1 },
    { 2, ARMOR, 31, 35, 11138, 0.05, 1, 1 }, { 2, WEAPON, 31, 35, 11138, 0.05, 1, 1 },
    { 2, ARMOR, 36, 40, 11139, 0.05, 1, 1 }, { 2, WEAPON, 36, 40, 11139, 0.05, 1, 1 },
    { 2, ARMOR, 41, 45, 11177, 0.05, 1, 1 }, { 2, WEAPON, 41, 45, 11177, 0.05, 1, 1 },
    { 2, ARMOR, 46, 50, 11178, 0.05, 1, 1 }, { 2, WEAPON, 46, 50, 11178, 0.05, 1, 1 },
    { 2, ARMOR, 51, 55, 14343, 0.05, 1, 1 }, { 2, WEAPON, 51, 55, 14343, 0.05, 1, 1 },
    { 2, ARMOR, 56, TOP, 14344, 0.05, 1, 1 }, { 2, WEAPON, 56, TOP, 14344, 0.05, 1, 1 },

    -- Rare: one shard; from 56 a small Nexus Crystal chance.
    { 3, nil, 1, 25, 10978, 1.00, 1, 1 }, { 3, nil, 26, 30, 11084, 1.00, 1, 1 },
    { 3, nil, 31, 35, 11138, 1.00, 1, 1 }, { 3, nil, 36, 40, 11139, 1.00, 1, 1 },
    { 3, nil, 41, 45, 11177, 1.00, 1, 1 }, { 3, nil, 46, 50, 11178, 1.00, 1, 1 },
    { 3, nil, 51, 55, 14343, 1.00, 1, 1 },
    { 3, nil, 56, 60, 14344, 0.995, 1, 1 }, { 3, nil, 56, 60, 20725, 0.005, 1, 1 },
    { 3, nil, 61, TOP, 14344, 0.99, 1, 1 }, { 3, nil, 61, TOP, 20725, 0.01, 1, 1 },

    -- Epic: shards in quantity up to 55, Nexus Crystals from 56.
    { 4, nil, 40, 45, 11177, 1.00, 2, 4 }, { 4, nil, 46, 50, 11178, 1.00, 2, 4 },
    { 4, nil, 51, 55, 14343, 1.00, 2, 4 },
    { 4, nil, 56, 60, 20725, 1.00, 1, 1 }, { 4, nil, 61, TOP, 20725, 1.00, 1, 2 },
}
Tables.RULES = RULES


local function Average(minAmount, maxAmount)
    return ((minAmount or 1) + (maxAmount or minAmount or 1)) / 2
end

local function AddEstimate(results, itemID, chance, minAmount, maxAmount)
    local expected = chance * Average(minAmount, maxAmount)
    local entry = results[itemID]
    if not entry then
        entry = { itemID = itemID, chance = 0, minAmount = minAmount, maxAmount = maxAmount, expectedAmount = 0 }
        results[itemID] = entry
    end
    entry.chance = entry.chance + chance
    entry.expectedAmount = entry.expectedAmount + expected
    entry.minAmount = math.min(entry.minAmount or minAmount, minAmount or 1)
    entry.maxAmount = math.max(entry.maxAmount or maxAmount, maxAmount or minAmount or 1)
end

function Tables:GetExpected(item)
    if not item or not item.quality or not item.itemLevel then return nil end
    local results = {}
    local found = false
    for _, rule in ipairs(RULES) do
        local quality, classID, minLevel, maxLevel, itemID, chance, minAmount, maxAmount = unpack(rule)
        if item.quality == quality and item.itemLevel >= minLevel and item.itemLevel <= maxLevel and (not classID or classID == item.classID) then
            AddEstimate(results, itemID, chance, minAmount, maxAmount)
            found = true
        end
    end
    if not found then return nil end
    local uncertain = item.itemLevel > Tables.VANILLA_MAX_ITEM_LEVEL

    local list = {}
    local expectedValue, valueSource
    for _, entry in pairs(results) do
        if Shatter.AuctionData then
            local value, source = Shatter.AuctionData:GetItemValue(entry.itemID)
            if value then
                entry.valueCopper = value
                expectedValue = (expectedValue or 0) + entry.expectedAmount * value
                valueSource = valueSource or source
            end
        end
        table.insert(list, entry)
    end
    table.sort(list, function(a, b) return (a.expectedAmount or 0) > (b.expectedAmount or 0) end)
    return { materials = list, expectedValueCopper = expectedValue, valueSource = valueSource, uncertain = uncertain }
end

function Tables:FormatMoney(copper)
    copper = tonumber(copper)
    if not copper then return nil end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperOnly = math.floor(copper % 100)
    if gold > 0 then return string.format("%dg %02ds %02dc", gold, silver, copperOnly) end
    if silver > 0 then return string.format("%ds %02dc", silver, copperOnly) end
    return string.format("%dc", copperOnly)
end

function Tables:FormatEstimate(estimate)
    if not estimate or not estimate.materials or #estimate.materials == 0 then
        return "Expected materials: unavailable for this item."
    end
    local lines = { "Expected materials:" }
    for _, entry in ipairs(estimate.materials) do
        local name, link = Shatter.API.GetItemInfo(entry.itemID)
        local label = link or name or ("item:" .. tostring(entry.itemID))
        local chance = math.floor((entry.chance or 0) * 100 + 0.5)
        table.insert(lines, string.format("%s x%.2f (%d%%, %d-%d)", label, entry.expectedAmount or 0, chance, entry.minAmount or 1, entry.maxAmount or 1))
    end
    if estimate.expectedValueCopper then
        table.insert(lines, "Expected value: " .. self:FormatMoney(estimate.expectedValueCopper) .. (estimate.valueSource and (" via " .. estimate.valueSource) or ""))
    else
        table.insert(lines, "Expected value: no pricing source")
    end
    return table.concat(lines, "\n")
end

