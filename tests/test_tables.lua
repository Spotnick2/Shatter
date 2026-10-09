------------------------------------------------------------
-- test_tables.lua - the Vanilla disenchant rules: no Outland materials,
-- brackets that never overlap or leave gaps, the right material at every
-- bracket edge, uncertainty above Vanilla's item levels, and a simulation
-- that draws from the same rules.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.loadAddon()

local T = Shatter.DisenchantTables
local C = Shatter.Constants
local ARMOR, WEAPON = C.ITEM_CLASS_ARMOR, C.ITEM_CLASS_WEAPON
local OUTLAND = { [22445] = true, [22446] = true, [22447] = true, [22448] = true, [22449] = true, [22450] = true }

-- Every output is a known Vanilla material; no Outland material anywhere.
for _, rule in ipairs(T.RULES) do
    local material = rule[5]
    H.check(not OUTLAND[material], "no Outland material in the rules: " .. material)
    H.check(C.MATERIAL_ITEM_IDS[material], "rule output is a tracked material: " .. material)
end
for id in pairs(OUTLAND) do
    H.check(not C.MATERIAL_ITEM_IDS[id], "no Outland material tracked: " .. id)
end

-- For each (quality, class, material), the brackets never overlap.
local spans = {}
for _, r in ipairs(T.RULES) do
    local key = r[1] .. ":" .. tostring(r[2]) .. ":" .. r[5]
    spans[key] = spans[key] or {}
    table.insert(spans[key], { r[3], r[4] })
end
for key, list in pairs(spans) do
    table.sort(list, function(a, b) return a[1] < b[1] end)
    for i = 2, #list do
        H.check(list[i][1] > list[i - 1][2], "no overlapping brackets for " .. key)
    end
end

local function item(quality, classID, ilvl)
    return { quality = quality, classID = classID, itemLevel = ilvl }
end

local function materials(quality, classID, ilvl)
    local e = T:GetExpected(item(quality, classID, ilvl))
    local out = {}
    for _, m in ipairs(e and e.materials or {}) do out[m.itemID] = m end
    return out, e
end

-- Every item level from 5 to 100 has an uncommon estimate: no gaps.
for ilvl = 5, 100 do
    local m = materials(2, ARMOR, ilvl)
    H.check(next(m) ~= nil, "uncommon armor ilvl " .. ilvl .. " has an estimate")
    m = materials(2, WEAPON, ilvl)
    H.check(next(m) ~= nil, "uncommon weapon ilvl " .. ilvl .. " has an estimate")
end
for ilvl = 1, 100 do
    H.check(next((materials(3, ARMOR, ilvl))) ~= nil, "rare ilvl " .. ilvl .. " has an estimate")
end
for ilvl = 40, 100 do
    H.check(next((materials(4, WEAPON, ilvl))) ~= nil, "epic ilvl " .. ilvl .. " has an estimate")
end

-- Bracket edges.
local m = materials(2, ARMOR, 60)
H.check(m[16204] and m[16204].maxAmount == 2, "uncommon 60: Illusion Dust 1-2")
m = materials(2, ARMOR, 61)
H.check(m[16204] and m[16204].maxAmount == 5, "uncommon 61: Illusion Dust 2-5")
H.check(m[16203] and m[16203].maxAmount == 3, "uncommon 61: Greater Eternal Essence 2-3")
H.check(m[14344] ~= nil, "uncommon 61: Large Brilliant Shard chance")
m = materials(2, WEAPON, 70)
H.check(m[16203] and m[16203].chance == 0.75, "uncommon weapon 70: essence-heavy, Vanilla essence (not Planar)")
m = materials(3, ARMOR, 55)
H.check(m[14343] and not m[20725], "rare 55: Small Brilliant Shard, no Nexus")
m = materials(3, ARMOR, 56)
H.check(m[14344] and m[20725], "rare 56: Large Brilliant Shard with a Nexus chance")
m = materials(3, WEAPON, 66)
H.check(m[14344] and not m[22448], "rare 66: Large Brilliant Shard (TBC gave Small Prismatic)")
m = materials(4, ARMOR, 55)
H.check(m[14343] and m[14343].maxAmount == 4, "epic 55: Small Brilliant Shard 2-4")
m = materials(4, ARMOR, 56)
H.check(m[20725] and m[20725].maxAmount == 1, "epic 56: one Nexus Crystal")
m = materials(4, WEAPON, 92)
H.check(m[20725] and m[20725].maxAmount == 2, "epic 92 (Naxxramas): Nexus Crystal 1-2, not Void Crystal")

-- Outcome chances sum to 1 at every level (a missing or duplicated row
-- shows up here even when some material is still present).
local function total(quality, classID, ilvl)
    local e = T:GetExpected(item(quality, classID, ilvl))
    local sum = 0
    for _, m in ipairs(e and e.materials or {}) do sum = sum + m.chance end
    return sum
end
for ilvl = 5, 100 do
    for _, cls in ipairs({ ARMOR, WEAPON }) do
        local t = total(2, cls, ilvl)
        H.check(math.abs(t - 1) < 0.011, string.format("uncommon %s ilvl %d: chances sum to 1 (got %.3f)", cls == ARMOR and "armor" or "weapon", ilvl, t))
    end
end
for ilvl = 1, 100 do
    H.check(math.abs(total(3, ARMOR, ilvl) - 1) < 0.001, "rare ilvl " .. ilvl .. ": chances sum to 1")
end
for ilvl = 40, 100 do
    H.check(math.abs(total(4, WEAPON, ilvl) - 1) < 0.001, "epic ilvl " .. ilvl .. ": chances sum to 1")
end

-- Exact outcomes on both sides of every transition, written out
-- independently of the rule table: { materialID, chance, min, max }.
local EXPECT = {
    -- uncommon armor
    { 2, ARMOR, 15, { { 10940, 0.80, 1, 2 }, { 10938, 0.20, 1, 2 } } },
    { 2, ARMOR, 16, { { 10940, 0.75, 2, 3 }, { 10939, 0.20, 1, 2 }, { 10978, 0.05, 1, 1 } } },
    { 2, ARMOR, 20, { { 10940, 0.75, 2, 3 }, { 10939, 0.20, 1, 2 }, { 10978, 0.05, 1, 1 } } },
    { 2, ARMOR, 21, { { 10940, 0.75, 4, 6 }, { 10998, 0.15, 1, 2 }, { 10978, 0.10, 1, 1 } } },
    { 2, ARMOR, 50, { { 11176, 0.75, 1, 2 }, { 11175, 0.20, 1, 2 }, { 11178, 0.05, 1, 1 } } },
    { 2, ARMOR, 51, { { 11176, 0.75, 2, 5 }, { 16202, 0.20, 1, 2 }, { 14343, 0.05, 1, 1 } } },
    { 2, ARMOR, 55, { { 11176, 0.75, 2, 5 }, { 16202, 0.20, 1, 2 }, { 14343, 0.05, 1, 1 } } },
    { 2, ARMOR, 56, { { 16204, 0.75, 1, 2 }, { 16203, 0.20, 1, 2 }, { 14344, 0.05, 1, 1 } } },
    { 2, ARMOR, 60, { { 16204, 0.75, 1, 2 }, { 16203, 0.20, 1, 2 }, { 14344, 0.05, 1, 1 } } },
    { 2, ARMOR, 61, { { 16204, 0.75, 2, 5 }, { 16203, 0.20, 2, 3 }, { 14344, 0.05, 1, 1 } } },
    -- uncommon weapon
    { 2, WEAPON, 15, { { 10940, 0.20, 1, 2 }, { 10938, 0.80, 1, 2 } } },
    { 2, WEAPON, 16, { { 10940, 0.20, 2, 3 }, { 10939, 0.75, 1, 2 }, { 10978, 0.05, 1, 1 } } },
    { 2, WEAPON, 21, { { 10940, 0.15, 4, 6 }, { 10998, 0.75, 1, 2 }, { 10978, 0.10, 1, 1 } } },
    { 2, WEAPON, 51, { { 11176, 0.20, 2, 5 }, { 16202, 0.75, 1, 2 }, { 14343, 0.05, 1, 1 } } },
    { 2, WEAPON, 56, { { 16204, 0.20, 1, 2 }, { 16203, 0.75, 1, 2 }, { 14344, 0.05, 1, 1 } } },
    { 2, WEAPON, 61, { { 16204, 0.20, 2, 5 }, { 16203, 0.75, 2, 3 }, { 14344, 0.05, 1, 1 } } },
    -- rare
    { 3, ARMOR, 55, { { 14343, 1.00, 1, 1 } } },
    { 3, ARMOR, 56, { { 14344, 0.995, 1, 1 }, { 20725, 0.005, 1, 1 } } },
    { 3, WEAPON, 60, { { 14344, 0.995, 1, 1 }, { 20725, 0.005, 1, 1 } } },
    { 3, WEAPON, 61, { { 14344, 0.99, 1, 1 }, { 20725, 0.01, 1, 1 } } },
    -- epic
    { 4, ARMOR, 40, { { 11177, 1.00, 2, 4 } } },
    { 4, ARMOR, 45, { { 11177, 1.00, 2, 4 } } },
    { 4, ARMOR, 46, { { 11178, 1.00, 2, 4 } } },
    { 4, WEAPON, 50, { { 11178, 1.00, 2, 4 } } },
    { 4, WEAPON, 51, { { 14343, 1.00, 2, 4 } } },
    { 4, ARMOR, 55, { { 14343, 1.00, 2, 4 } } },
    { 4, ARMOR, 56, { { 20725, 1.00, 1, 1 } } },
    { 4, WEAPON, 60, { { 20725, 1.00, 1, 1 } } },
    { 4, WEAPON, 61, { { 20725, 1.00, 1, 2 } } },
    { 4, ARMOR, 92, { { 20725, 1.00, 1, 2 } } },
}
for _, case in ipairs(EXPECT) do
    local quality, cls, ilvl, outcomes = case[1], case[2], case[3], case[4]
    local got = materials(quality, cls, ilvl)
    local label = string.format("q%d %s ilvl %d", quality, cls == ARMOR and "armor" or "weapon", ilvl)
    local n = 0
    for _ in pairs(got) do n = n + 1 end
    H.eq(n, #outcomes, label .. ": number of outcomes")
    for _, o in ipairs(outcomes) do
        local m = got[o[1]]
        H.check(m and math.abs(m.chance - o[2]) < 1e-9 and m.minAmount == o[3] and m.maxAmount == o[4],
            string.format("%s: material %d at %.3f, %d-%d", label, o[1], o[2], o[3], o[4]))
    end
end

-- Uncertainty: above Vanilla's top item level the estimate is flagged.
local _, e = materials(4, ARMOR, 92)
H.eq(e.uncertain, false, "ilvl 92 is Vanilla: not flagged")
_, e = materials(4, ARMOR, 93)
H.eq(e.uncertain, true, "ilvl 93: flagged unverified")

-- No rule (an epic below 40): no estimate, and the item is still eligible.
H.eq(T:GetExpected(item(4, ARMOR, 30)), nil, "low epic: no estimate")
local candidate = { itemID = 99999, quality = 3, itemLevel = 30, classID = ARMOR, equipLoc = "INVTYPE_CHEST" }
Shatter.Database:GetSettings().maxQuality = 4
candidate.quality = 4
H.check(Shatter.ItemScanner:IsCandidateDisenchantable(candidate), "no estimate never removes an eligible item")

-- Simulation results come from the same rules.
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.AddItem(4002, { name = "Epic Blade", quality = 4, itemLevel = 83, classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON" })
WoW.SetBagItem(0, 1, { itemID = 4002 })
WoW.loadAddon()
local settings = Shatter.Database:GetSettings()
settings.maxQuality, settings.debug, settings.simulateDisenchant = 4, true, true
Shatter.SoloMode:ScheduleScan("TEST", 0)
WoW.flushTimers()
local recorded
local real = Shatter.Session.RecordResult
Shatter.Session.RecordResult = function(self, it, result, opts) recorded = result return real(self, it, result, opts) end
Shatter.MainFrame:Show()
WoW.click(Shatter.MainFrame.primary, "LeftButton")
WoW.flushTimers()
H.check(recorded and recorded[20725] == 1, "simulated epic 83: a Nexus Crystal (TBC sim gave a Void Crystal)")

-- A weapon simulates its most likely material (essence), and an item with
-- no rule simulates an empty result rather than inventing one.
local simulate = Shatter.Disenchant._GetSimulatedResult
H.eq(type(simulate), "function", "simulation hook exposed for tests")
local r = simulate(item(2, WEAPON, 58))
H.check(r[16203] == 1 and r[16204] == nil, "uncommon weapon 58: Greater Eternal Essence (essence-heavy)")
r = simulate(item(2, ARMOR, 58))
H.check(r[16204] == 1 and r[16203] == nil, "uncommon armor 58: Illusion Dust (dust-heavy)")
H.eq(next(simulate(item(4, ARMOR, 30))), nil, "no rule: empty simulated result")
H.eq(#WoW.actions, 0, "simulation touched nothing")

H.done("test_tables")
