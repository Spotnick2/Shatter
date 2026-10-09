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
-- above it gets the top bracket's estimate marked uncertain. These are the
-- Vanilla rates, not Forever's; measured yields (below) correct them per
-- bracket as the player disenchants. Expected amounts use the midpoint of
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

-- Measured yields (ShatterDB.yields): real disenchants counted per rule
-- bucket, so a few dozen casts cover a whole bracket. From
-- MIN_YIELD_SAMPLES on, a bucket's estimate blends its measurements with the
-- table, weighted as YIELD_PRIOR_WEIGHT disenchants: a rare material the
-- player has not seen yet (a 5% shard, a 0.5% Nexus Crystal) keeps a share
-- instead of vanishing, and the measurements dominate as they grow.
Tables.MIN_YIELD_SAMPLES = 20
Tables.YIELD_PRIOR_WEIGHT = 20

local function RuleMatches(rule, item)
    local quality, classID, low, high = rule[1], rule[2], rule[3], rule[4]
    return item.quality == quality and item.itemLevel >= low and item.itemLevel <= high and (not classID or classID == item.classID)
end

-- A saved bucket in the shape RecordYield writes; anything else (a
-- hand-edited or future SavedVariables) is ignored rather than trusted.
local function IsValidBucket(bucket)
    if type(bucket) ~= "table" or type(bucket.materials) ~= "table" then return false end
    if type(bucket.quality) ~= "number" or type(bucket.n) ~= "number"
        or type(bucket.minLevel) ~= "number" or type(bucket.maxLevel) ~= "number" then return false end
    for _, m in pairs(bucket.materials) do
        if type(m) ~= "table" or type(m.drops) ~= "number" or type(m.total) ~= "number" then return false end
    end
    return true
end

local QUALITY_NAMES = { [2] = "Uncommon", [3] = "Rare", [4] = "Epic" }
local CLASS_NAMES = { [ARMOR] = "armor", [WEAPON] = "weapon" }

-- The rule bucket an item falls in: quality, class (only where the rules
-- tell classes apart) and the item-level band every matching rule shares.
-- The open-ended top band is split at VANILLA_MAX_ITEM_LEVEL, so items
-- beyond Vanilla neither borrow nor skew Vanilla's measurements.
-- Returns the key and the bucket's description, or nil without a rule.
function Tables:GetBucket(item)
    if not item or not item.quality or not item.itemLevel then return nil end
    local minLevel, maxLevel, classed
    for _, rule in ipairs(RULES) do
        if RuleMatches(rule, item) then
            local low, high = rule[3], rule[4]
            minLevel = math.max(minLevel or low, low)
            maxLevel = math.min(maxLevel or high, high)
            if rule[2] then classed = true end
        end
    end
    if not minLevel then return nil end
    if item.itemLevel > self.VANILLA_MAX_ITEM_LEVEL then
        minLevel = math.max(minLevel, self.VANILLA_MAX_ITEM_LEVEL + 1)
    else
        maxLevel = math.min(maxLevel, self.VANILLA_MAX_ITEM_LEVEL)
    end
    local classID = classed and item.classID or nil
    return string.format("%d:%s:%d-%d", item.quality, tostring(classID or "any"), minLevel, maxLevel),
        { quality = item.quality, classID = classID, minLevel = minLevel, maxLevel = maxLevel }
end

-- One real disenchant's loot. Only a clean observation counts: at least one
-- looted item, every one a disenchanting material, and an item with a
-- bucket. Returns true when recorded.
function Tables:RecordYield(item, loot)
    if type(loot) ~= "table" or not next(loot) or not Shatter.Database then return false end
    for itemID, count in pairs(loot) do
        if not C.MATERIAL_ITEM_IDS[itemID] or (tonumber(count) or 0) <= 0 then return false end
    end
    local key, info = self:GetBucket(item)
    if not key then return false end
    local yields = Shatter.Database:GetYields(true)
    local bucket = yields[key]
    if not IsValidBucket(bucket) then
        bucket = { quality = info.quality, classID = info.classID, minLevel = info.minLevel, maxLevel = info.maxLevel, n = 0, materials = {} }
        yields[key] = bucket
    end
    bucket.n = bucket.n + 1
    for itemID, count in pairs(loot) do
        local m = bucket.materials[itemID] or { drops = 0, total = 0 }
        m.drops = m.drops + 1
        m.total = m.total + count
        m.minAmount = math.min(m.minAmount or count, count)
        m.maxAmount = math.max(m.maxAmount or count, count)
        bucket.materials[itemID] = m
    end
    return true
end

-- How many disenchants the item's bucket has measured, plus (from
-- MIN_YIELD_SAMPLES on) the table's estimate entries blended with them:
-- (measured + weight * table) / (n + weight), per material in either.
function Tables:GetMeasured(item, tableResults)
    local key = self:GetBucket(item)
    local yields = key and Shatter.Database and Shatter.Database:GetYields()
    local bucket = yields and yields[key]
    if not IsValidBucket(bucket) then return 0, nil end
    local n = bucket.n
    if n < self.MIN_YIELD_SAMPLES then return n, nil end
    local weight = self.YIELD_PRIOR_WEIGHT
    local results = {}
    for itemID, entry in pairs(tableResults or {}) do
        results[itemID] = {
            itemID = itemID, chance = weight * entry.chance / (n + weight),
            expectedAmount = weight * entry.expectedAmount / (n + weight),
            minAmount = entry.minAmount, maxAmount = entry.maxAmount,
        }
    end
    for itemID, m in pairs(bucket.materials) do
        local entry = results[itemID]
        if not entry then
            entry = { itemID = itemID, chance = 0, expectedAmount = 0 }
            results[itemID] = entry
        end
        entry.chance = entry.chance + m.drops / (n + weight)
        entry.expectedAmount = entry.expectedAmount + m.total / (n + weight)
        entry.minAmount = math.min(entry.minAmount or m.minAmount or 1, m.minAmount or entry.minAmount or 1)
        entry.maxAmount = math.max(entry.maxAmount or m.maxAmount or 1, m.maxAmount or entry.maxAmount or 1)
    end
    return n, results
end

-- Chat lines for /shatter yields: every measured bucket, Uncommon to Epic.
function Tables:FormatYields()
    local yields = Shatter.Database and Shatter.Database:GetYields()
    local keys = {}
    for key, bucket in pairs(yields or {}) do
        if IsValidBucket(bucket) and bucket.n > 0 then keys[#keys + 1] = key end
    end
    if #keys == 0 then return { "No disenchants measured yet." } end
    table.sort(keys, function(a, b)
        local x, y = yields[a], yields[b]
        if x.quality ~= y.quality then return x.quality < y.quality end
        if x.minLevel ~= y.minLevel then return x.minLevel < y.minLevel end
        return tostring(x.classID) < tostring(y.classID)
    end)
    local lines = {}
    for _, key in ipairs(keys) do
        local b = yields[key]
        local mats = {}
        for itemID, m in pairs(b.materials or {}) do mats[#mats + 1] = { itemID = itemID, m = m } end
        table.sort(mats, function(p, q) return p.m.drops > q.m.drops end)
        local parts = {}
        for _, e in ipairs(mats) do
            local name = Shatter.API.GetItemInfo(e.itemID)
            parts[#parts + 1] = string.format("%s %d%% x%.1f", name or ("item:" .. e.itemID),
                math.floor(e.m.drops / b.n * 100 + 0.5), e.m.total / e.m.drops)
        end
        local band = b.maxLevel >= TOP and (b.minLevel .. "+") or (b.minLevel .. "-" .. b.maxLevel)
        lines[#lines + 1] = string.format("%s %s %s: %d%s - %s",
            QUALITY_NAMES[b.quality] or ("quality " .. tostring(b.quality)), CLASS_NAMES[b.classID] or "any", band,
            b.n, b.n >= self.MIN_YIELD_SAMPLES and "" or " (table used)", table.concat(parts, ", "))
    end
    return lines
end


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
        if RuleMatches(rule, item) then
            AddEstimate(results, rule[5], rule[6], rule[7], rule[8])
            found = true
        end
    end
    if not found then return nil end
    local uncertain = item.itemLevel > Tables.VANILLA_MAX_ITEM_LEVEL
    local samples, measured = self:GetMeasured(item, results)
    if measured then
        results = measured
        uncertain = false
    end

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
    return {
        materials = list, expectedValueCopper = expectedValue, valueSource = valueSource, uncertain = uncertain,
        measured = measured ~= nil, samples = samples,
    }
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

