------------------------------------------------------------
-- test_essences.lua - #39: three lesser essences make one greater. An
-- essence with no price of its own takes the other size's (lesser = greater
-- / 3, greater = lesser x 3), and the estimate names it; a price of its own
-- always wins. The tooltip, the main frame and the value filter use it.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local VEST, BLADE, DUST = 2589, 4003, 10940
local LESSER_MAGIC, GREATER_MAGIC = 10938, 10939

local prices = {}
local function price(list)
    prices = list
    Shatter.Tooltip:Reset()
end

local function setup()
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    -- Item level 20 armor: 20% Greater Magic Essence, 1-2. Item level 10
    -- weapon: 80% Lesser Magic Essence, 1-2.
    WoW.AddItem(VEST, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
    WoW.AddItem(BLADE, { name = "Green Blade", quality = 2, itemLevel = 10, classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON" })
    WoW.AddItem(DUST, { name = "Strange Dust", quality = 1, itemLevel = 1, classID = 7, subclassID = 12, equipLoc = "" })
    WoW.AddItem(LESSER_MAGIC, { name = "Lesser Magic Essence", quality = 2, itemLevel = 1, classID = 7, subclassID = 12, equipLoc = "" })
    WoW.AddItem(GREATER_MAGIC, { name = "Greater Magic Essence", quality = 2, itemLevel = 1, classID = 7, subclassID = 12, equipLoc = "" })
    for lesser, greater in pairs(Shatter and Shatter.Constants and Shatter.Constants.ESSENCE_GREATER or {}) do
        WoW.items[lesser] = WoW.items[lesser] or { name = "Lesser " .. lesser }
        WoW.items[greater] = WoW.items[greater] or { name = "Greater " .. greater }
    end
    rawset(_G, "Auctionator", { API = { v1 = { GetAuctionPriceByItemLink = function(_, link)
        return prices[tonumber(link:match("item:(%d+)"))]
    end } } })
    WoW.loadAddon()
    WoW.flushTimers()
    prices = {}
end

local function estimate(itemID)
    local _, link, quality, itemLevel, _, _, _, _, equipLoc, _, _, classID = Shatter.API.GetItemInfo(itemID)
    return Shatter.DisenchantTables:GetExpected({ itemID = itemID, itemLink = link, quality = quality,
        itemLevel = itemLevel, equipLoc = equipLoc, classID = classID })
end

local function material(e, itemID)
    for _, entry in ipairs(e and e.materials or {}) do
        if entry.itemID == itemID then return entry end
    end
end

setup()
local T, C = Shatter.DisenchantTables, Shatter.Constants

-- 1. The pairs: five tiers, lesser to greater, both sizes tracked materials.
local tiers = 0
for lesser, greater in pairs(C.ESSENCE_GREATER) do
    tiers = tiers + 1
    H.check(C.MATERIAL_ITEM_IDS[lesser] and C.MATERIAL_ITEM_IDS[greater], "both sizes are materials: " .. lesser .. "/" .. greater)
end
H.eq(tiers, 5, "five essence tiers")
H.eq(C.ESSENCE_LESSER_PER_GREATER, 3, "three lesser to one greater")

-- 2. Every tier, both ways: one size priced, the other derives it.
for lesser, greater in pairs(C.ESSENCE_GREATER) do
    price({ [greater] = 3000 })
    local v, source, from = T:GetMaterialValue(lesser)
    H.eq(v, 1000, "lesser " .. lesser .. " = greater / 3")
    H.eq(source, "Auctionator", "...from the same source")
    H.eq(from, greater, "...naming the greater")
    price({ [lesser] = 1000 })
    v, source, from = T:GetMaterialValue(greater)
    H.eq(v, 3000, "greater " .. greater .. " = lesser x 3")
    H.eq(from, lesser, "...naming the lesser")
end

-- 3. Its own price first; neither priced, no price; not an essence, no pair.
price({ [LESSER_MAGIC] = 1500, [GREATER_MAGIC] = 3000 })
local v, _, from = T:GetMaterialValue(LESSER_MAGIC)
H.eq(v, 1500, "both priced: the lesser keeps its own")
H.eq(from, nil, "...not derived")
v, _, from = T:GetMaterialValue(GREATER_MAGIC)
H.eq(v, 3000, "both priced: the greater keeps its own")
H.eq(from, nil, "...not derived")
price({})
H.eq(T:GetMaterialValue(LESSER_MAGIC), nil, "neither priced: no price")
price({ [GREATER_MAGIC] = 3000 })
H.eq(T:GetMaterialValue(DUST), nil, "dust has no other size")

-- 4. The estimate: a vest's greater essence priced from the lesser.
price({ [LESSER_MAGIC] = 1000 })
local e = estimate(VEST)
local m = material(e, GREATER_MAGIC)
H.eq(m and m.valueCopper, 3000, "the vest's greater essence: 3 x the lesser")
H.eq(m and m.valueFrom, LESSER_MAGIC, "...priced from the lesser")
H.eq(e.expectedValueCopper, 0.20 * 1.5 * 3000, "the expected value counts it")
H.eq(e.valueDerived, true, "the estimate says a price is derived")
H.eq(T:FormatDerivedPrices(e), "Greater Magic Essence from Lesser Magic Essence", "...and which")
H.check(T:FormatEstimate(e):find("(Greater Magic Essence from Lesser Magic Essence)", 1, true), "the text estimate says so")

price({ [GREATER_MAGIC] = 3000 })
e = estimate(BLADE)
m = material(e, LESSER_MAGIC)
H.eq(m and m.valueCopper, 1000, "the blade's lesser essence: the greater / 3")
H.eq(e.expectedValueCopper, 0.80 * 1.5 * 1000, "...in the expected value")
H.eq(T:FormatDerivedPrices(e), "Lesser Magic Essence from Greater Magic Essence", "...named")

price({ [LESSER_MAGIC] = 1500, [GREATER_MAGIC] = 3000 })
e = estimate(BLADE)
H.eq(e.expectedValueCopper, 0.80 * 1.5 * 1500, "both priced: the blade's own lesser price")
H.eq(e.valueDerived, nil, "...nothing derived")
H.eq(T:FormatDerivedPrices(e), nil, "...nothing named")

price({})
e = estimate(BLADE)
H.eq(e.expectedValueCopper, nil, "nothing priced: no value, as before")

-- 5. The tooltip shows the derived value.
price({ [LESSER_MAGIC] = 1000 })
local lines = WoW.showItemTooltip(VEST)
local valueLine
for _, line in ipairs(lines) do if tostring(line):find("Expected value", 1, true) then valueLine = line end end
H.check(valueLine and valueLine:find(T:FormatMoney(0.20 * 1.5 * 3000), 1, true), "the tooltip's value uses the derived price (" .. tostring(valueLine) .. ")")

-- 6. The value filter: the blade's dust is priced at 1c, its essence only
-- through the greater. At 1g minimum, the derived price keeps it queued.
local function queued(itemID)
    for _, item in ipairs(Shatter.Queue:GetItems() or {}) do
        if item.itemID == itemID then return item end
    end
end
setup()
WoW.SetBagItem(0, 1, { itemID = BLADE })
local settings = Shatter.Database:GetSettings()
settings.useAuctionData = true
settings.minExpectedValueCopper = 10000
price({ [DUST] = 1 })
Shatter.MainFrame:Show()
Shatter.SoloMode:ScheduleScan("TEST", 0)
WoW.flushTimers()
H.check(not queued(BLADE), "only the dust priced: under 1g, left out")
price({ [DUST] = 1, [GREATER_MAGIC] = 30000 })
Shatter.SoloMode:ScheduleScan("TEST", 0)
WoW.flushTimers()
local item = queued(BLADE)
H.check(item, "the lesser essence priced from the greater: over 1g, queued")
H.eq(item and item.expectedValueCopper, 0.80 * 1.5 * 10000 + 0.20 * 1.5 * 1, "...at the derived value")

-- 7. The main frame names the derived price under the source.
Shatter.Queue:Select(1)
Shatter.MainFrame:Update()
local text = Shatter.MainFrame.detailPanel.valueText:GetText() or ""
H.check(text:find("Source: Auctionator (Lesser Magic Essence from Greater Magic Essence)", 1, true), "the detail names the derived price (" .. text .. ")")

rawset(_G, "Auctionator", nil)
H.done("test_essences")
