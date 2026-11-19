------------------------------------------------------------
-- test_yields.lua - measured disenchant yields: only a real, clean loot
-- window is recorded, per rule bucket; from MIN_YIELD_SAMPLES on the
-- measured odds replace the built-in table; /shatter yields lists and
-- resets them.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local VEST, BLADE, DUST, ESSENCE = 2589, 4002, 10940, 10938
local ARMOR, WEAPON = 4, 2

local function setup()
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    WoW.AddItem(VEST, { name = "Green Vest", quality = 2, itemLevel = 20, classID = ARMOR, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
    WoW.AddItem(DUST, { name = "Strange Dust", quality = 1, itemLevel = 1, classID = 7, subclassID = 12, equipLoc = "" })
    WoW.SetBagItem(0, 3, { itemID = VEST })
    WoW.loadAddon()
    WoW.flushTimers()
    Shatter.MainFrame:Show()
    return Shatter.MainFrame.primary
end

-- One disenchant of the vest; `loot` is what the loot window shows (nil:
-- no loot window, only the bag change).
local function disenchant(button, loot)
    local item = Shatter.Queue:GetSelected()
    WoW.press(button, "LeftButton")
    WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 13262)
    WoW.bags[item.bag][item.slot] = nil
    if loot then
        WoW.loot = loot
        WoW.fire("LOOT_OPENED")
        WoW.SetBagItem(0, 10, { itemID = DUST, count = 2 })
        WoW.loot = {}
        WoW.fire("LOOT_CLOSED")
    else
        WoW.SetBagItem(0, 10, { itemID = DUST, count = 2 })
        WoW.fire("BAG_UPDATE_DELAYED")
    end
    WoW.flushTimers()
end

local function yields() return Shatter.Database:GetYields() end

-- 1. Buckets: the band every matching rule shares; class only where the
-- rules tell classes apart.
setup()
local T = Shatter.DisenchantTables
local function key(quality, classID, itemLevel) return (T:GetBucket({ quality = quality, classID = classID, itemLevel = itemLevel })) end
eq(key(2, ARMOR, 20), "2:4:16-20", "uncommon armor 20")
eq(key(2, WEAPON, 20), "2:2:16-20", "uncommon weapon 20: its own bucket")
eq(key(2, ARMOR, 58), "2:4:56-60", "uncommon armor 58: the shard rule's 56+ narrowed to 56-60")
eq(key(3, WEAPON, 33), "3:any:31-35", "rare: no class split")
-- #58: up to 20, the client's Forever-only rare brackets, armor and weapon apart.
eq(key(3, ARMOR, 10), "3:4:1-15", "rare armor 10: Forever bracket")
eq(key(3, WEAPON, 15), "3:2:1-15", "rare weapon 15: its own bucket")
eq(key(3, WEAPON, 16), "3:2:16-20", "rare weapon 16")
eq(key(3, ARMOR, 20), "3:4:16-20", "rare armor 20")
eq(key(3, ARMOR, 21), "3:any:21-25", "rare 21: the Vanilla bracket, no class split")
eq(key(4, ARMOR, 30), nil, "no rule, no bucket")
eq(key(2, ARMOR, 70), "2:4:61-92", "the open top band stops at Vanilla's last item level")
eq(key(2, ARMOR, 100), "2:4:93-1000", "...and items beyond Vanilla get their own bucket")

-- 2. A real disenchant read from the loot window is recorded.
local button = setup()
eq(yields(), nil, "nothing measured before the first disenchant")
disenchant(button, { { link = WoW.link(DUST), count = 2, name = "Strange Dust" } })
local bucket = yields() and yields()["2:4:16-20"]
check(bucket and bucket.n == 1, "one disenchant measured in its bucket")
check(bucket and bucket.materials[DUST] and bucket.materials[DUST].drops == 1 and bucket.materials[DUST].total == 2,
    "the dust: dropped once, 2 of them")

-- 3. Not recorded: a result seen only as a bag change, a loot window with
-- anything but materials, a simulated disenchant.
button = setup()
disenchant(button, nil)
eq(yields(), nil, "bag change only: not measured")
button = setup()
disenchant(button, { { link = WoW.link(DUST), count = 2, name = "Strange Dust" }, { link = WoW.link(VEST), count = 1, name = "Green Vest" } })
eq(yields(), nil, "a loot window with a non-material: not measured")
button = setup()
local settings = Shatter.Database:GetSettings()
settings.debug, settings.simulateDisenchant = true, true
WoW.press(button, "LeftButton")
WoW.flushTimers()
eq(yields(), nil, "simulated: not measured")

-- 4. Below the threshold the table decides; from it on, the measured odds
-- blended with the table, weighted as YIELD_PRIOR_WEIGHT disenchants.
setup()
local vest = { quality = 2, classID = ARMOR, itemLevel = 20 }
local function measure(n, drops, total)
    ShatterDB.yields = { ["2:4:16-20"] = { quality = 2, classID = ARMOR, minLevel = 16, maxLevel = 20, n = n,
        materials = { [ESSENCE] = { drops = drops, total = total, minAmount = 1, maxAmount = 3 } } } }
end
measure(T.MIN_YIELD_SAMPLES - 1, T.MIN_YIELD_SAMPLES - 1, 40)
local e = T:GetExpected(vest)
eq(e.measured, false, "below the threshold: the built-in table")
eq(e.samples, T.MIN_YIELD_SAMPLES - 1, "...with the sample count")
check(e.materials[1].itemID == DUST, "...whose top material for armor is dust")
measure(T.MIN_YIELD_SAMPLES, T.MIN_YIELD_SAMPLES / 2, T.MIN_YIELD_SAMPLES)
e = T:GetExpected(vest)
eq(e.measured, true, "at the threshold: measured")
local function entry(estimate, itemID)
    for _, m in ipairs(estimate.materials) do if m.itemID == itemID then return m end end
end
local function near(a, b) return a and math.abs(a - b) < 1e-9 end
local w, n = T.YIELD_PRIOR_WEIGHT, T.MIN_YIELD_SAMPLES
local ess = entry(e, ESSENCE)
check(ess and near(ess.chance, (n / 2) / (n + w)) and near(ess.expectedAmount, n / (n + w)),
    "a measured material: its drops and amounts over n + weight")
local dust = entry(e, DUST)
check(dust and near(dust.chance, w * 0.75 / (n + w)) and near(dust.expectedAmount, w * 0.75 * 2.5 / (n + w)),
    "a table material never measured: the table's share, weighted")
local shard = entry(e, 10978)
check(shard and near(shard.chance, w * 0.05 / (n + w)), "a rare shard not seen yet keeps its share instead of vanishing")
measure(1000, 500, 1000)
ess = entry(T:GetExpected(vest), ESSENCE)
check(ess and math.abs(ess.chance - 0.5) < 0.01, "many measurements dominate the table")
eq(T:GetExpected({ quality = 2, classID = WEAPON, itemLevel = 20 }).measured, false, "another bucket keeps the table")
ShatterDB.yields = { ["2:4:61-92"] = { quality = 2, classID = ARMOR, minLevel = 61, maxLevel = 92, n = 50,
    materials = { [16204] = { drops = 40, total = 120, minAmount = 2, maxAmount = 5 } } } }
eq(T:GetExpected({ quality = 2, classID = ARMOR, itemLevel = 70 }).measured, true, "ilvl 70 uses the 61-92 measurements")
local beyond = T:GetExpected({ quality = 2, classID = ARMOR, itemLevel = 100 })
check(beyond.measured == false and beyond.uncertain == true, "ilvl 100 does not: still the table, still unverified")
ShatterDB.yields = { ["3:4:1-15"] = { quality = 3, classID = ARMOR, minLevel = 1, maxLevel = 15, n = T.MIN_YIELD_SAMPLES,
    materials = { [DUST] = { drops = 16, total = 40, minAmount = 2, maxAmount = 3 } } } }
local forever = T:GetExpected({ quality = 3, classID = ARMOR, itemLevel = 15 })
check(forever.measured == true and forever.uncertain == false, "a measured Forever rare bracket is no longer uncertain (#58)")
eq(T:GetExpected({ quality = 3, classID = WEAPON, itemLevel = 15 }).uncertain, true, "...the weapon bracket still is")

-- 4b. Boosted Disenchanting (#57): the aura at the cast's start or with its
-- loot, or an aura read that fails (secret), keeps the cast out of the
-- measurements; it is still a result, and a disenchant without it is
-- measured as before.
local BOOST = Shatter.Constants.SPELL_BOOSTED_DISENCHANTING
eq(BOOST, 1283701, "the aura is 1283701, not the Salvager's craft or use spell")
local DUST_LOOT = { { link = WoW.link(DUST), count = 2, name = "Strange Dust" } }
button = setup()
SlashCmdList.SHATTER("learn on")
WoW.playerAuras[BOOST] = { spellId = BOOST, name = "Boosted Disenchanting" }
disenchant(button, DUST_LOOT)
eq(yields(), nil, "boosted from the start: not measured")
local logged = ShatterDB.yieldLog.entries
check(#logged == 1 and logged[1].boosted == true and logged[1].loot[DUST] == 2, "...but logged raw, flagged boosted")
SlashCmdList.SHATTER("learn")
check(WoW.chatText():find("1 disenchant logged (the last 2000 are kept), 0 flagged, 1 under Boosted Disenchanting.", 1, true),
    "/shatter learn counts the boosted disenchants")
button = setup()
local item = Shatter.Queue:GetSelected()
WoW.press(button, "LeftButton")
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 13262)
WoW.bags[item.bag][item.slot] = nil
WoW.playerAuras[BOOST] = { spellId = BOOST }
WoW.loot = DUST_LOOT
WoW.fire("LOOT_OPENED")
WoW.playerAuras[BOOST] = nil
WoW.SetBagItem(0, 10, { itemID = DUST, count = 2 })
WoW.loot = {}
WoW.fire("LOOT_CLOSED")
WoW.flushTimers()
eq(yields(), nil, "the aura arriving mid-cast, gone by the end: not measured")
button = setup()
WoW.aurasSecret = true
disenchant(button, DUST_LOOT)
eq(yields(), nil, "an aura read that fails: unknown, not measured")
eq(Shatter.Disenchant._ReadBoost(), nil, "...the read says unknown rather than not boosted")
WoW.aurasSecret = false
eq(Shatter.Disenchant._ReadBoost(), false, "no aura: not boosted")
button = setup()
WoW.playerAuras[12345] = { spellId = 12345 }
disenchant(button, DUST_LOOT)
check(yields() and yields()["2:4:16-20"] and yields()["2:4:16-20"].n == 1, "another aura: measured as usual")
button = setup()
SlashCmdList.SHATTER("learn on")
disenchant(button, DUST_LOOT)
eq(ShatterDB.yieldLog.entries[1].boosted, false, "an unboosted disenchant is logged boosted = false")
eq(T:RecordYield({ quality = 2, classID = ARMOR, itemLevel = 20 }, { [DUST] = 2 }), false,
    "RecordYield without a boost reading (nil) does not record")

-- 5. /shatter yields lists the buckets; /shatter yields reset clears them.
button = setup()
disenchant(button, { { link = WoW.link(DUST), count = 2, name = "Strange Dust" } })
SlashCmdList.SHATTER("yields")
check(WoW.chatText():find("Uncommon armor 16-20: 1 (table used) - Strange Dust 100% x2.0", 1, true), "the bucket is listed")
SlashCmdList.SHATTER("yields reset")
eq(yields(), nil, "reset clears the measurements")
SlashCmdList.SHATTER("yields")
check(WoW.chatText():find("No disenchants measured yet.", 1, true), "an empty list says so")

-- 5b. Autoloot empties a slot between LOOT_READY and LOOT_OPENED: the
-- later, partial read does not drop the shard the first one saw.
button = setup()
local SHARD = 10978
WoW.AddItem(SHARD, { name = "Small Glimmering Shard", quality = 2, itemLevel = 1, classID = 7, subclassID = 12, equipLoc = "" })
WoW.press(button, "LeftButton")
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 13262)
WoW.bags[0][3] = nil
WoW.loot = { { link = WoW.link(DUST), count = 2, name = "Strange Dust" }, { link = WoW.link(SHARD), count = 1, name = "Small Glimmering Shard" } }
WoW.fire("LOOT_READY")
WoW.loot = { { link = WoW.link(DUST), count = 2, name = "Strange Dust" } }
WoW.fire("LOOT_OPENED")
WoW.SetBagItem(0, 10, { itemID = DUST, count = 2 })
WoW.SetBagItem(0, 11, { itemID = SHARD, count = 1 })
WoW.loot = {}
WoW.fire("LOOT_CLOSED")
WoW.flushTimers()
bucket = yields() and yields()["2:4:16-20"]
check(bucket and bucket.n == 1 and bucket.materials[SHARD] and bucket.materials[SHARD].drops == 1
    and bucket.materials[DUST] and bucket.materials[DUST].total == 2, "the shard and the dust, each counted once")

-- 5c. A malformed saved bucket is neither listed nor trusted, and the next
-- disenchant starts that bucket over.
button = setup()
ShatterDB.yields = { ["2:4:16-20"] = { quality = 2, n = "25", materials = { [DUST] = { drops = "x" } } },
    junk = "not a bucket" }
SlashCmdList.SHATTER("yields")
check(WoW.chatText():find("No disenchants measured yet.", 1, true), "malformed buckets: /shatter yields lists none, no error")
eq(T:GetExpected(vest).measured, false, "a malformed bucket leaves the table in charge")
disenchant(button, { { link = WoW.link(DUST), count = 2, name = "Strange Dust" } })
bucket = yields()["2:4:16-20"]
check(bucket.n == 1 and bucket.minLevel == 16 and bucket.materials[DUST].drops == 1, "recording replaces it with a fresh bucket")

-- 5d. One bad material entry costs only that entry: the scan does not
-- error, the listing skips it, and recording keeps the other samples.
button = setup()
ShatterDB.yields = { ["2:4:16-20"] = { quality = 2, classID = ARMOR, minLevel = 16, maxLevel = 20, n = 30,
    materials = { [DUST] = { drops = 24, total = 60, minAmount = 2, maxAmount = 3 },
        [ESSENCE] = { drops = 6, total = 6, minAmount = "x" },
        [SHARD] = { drops = 0, total = 0 } } } }
local ok, est = pcall(T.GetExpected, T, vest)
check(ok and est.measured and entry(est, DUST) and not entry(est, ESSENCE), "a bad minAmount is skipped, not a Lua error")
SlashCmdList.SHATTER("yields")
local chat = WoW.chatText()
check(chat:find("Uncommon armor 16-20: 30 - Strange Dust 80% x2.5", 1, true)
    and not chat:find("Strange Dust 80% x2.5,", 1, true),
    "the listing shows only the good entry (no zero-drop division)")
disenchant(button, { { link = WoW.link(DUST), count = 2, name = "Strange Dust" } })
bucket = yields()["2:4:16-20"]
check(bucket.n == 31 and bucket.materials[DUST].drops == 25 and bucket.materials[ESSENCE] == nil and bucket.materials[SHARD] == nil,
    "recording keeps the 30 samples and drops only the bad entries")

-- 5e. Buckets saved before the top band split (61-1000) move to 61-92 at
-- load, merging into one the new code already started.
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.loadAddon({ savedDB = { yields = {
    ["2:4:61-1000"] = { quality = 2, classID = ARMOR, minLevel = 61, maxLevel = 1000, n = 30,
        materials = { [16204] = { drops = 30, total = 90, minAmount = 2, maxAmount = 5 } } },
    ["2:2:61-1000"] = { quality = 2, classID = WEAPON, minLevel = 61, maxLevel = 1000, n = 4,
        materials = { [16203] = { drops = 3, total = 6, minAmount = 2, maxAmount = 2 } } },
    ["2:2:61-92"] = { quality = 2, classID = WEAPON, minLevel = 61, maxLevel = 92, n = 2,
        materials = { [16203] = { drops = 2, total = 6, minAmount = 3, maxAmount = 3 } } },
} } })
WoW.flushTimers()
local y = yields()
eq(y["2:4:61-1000"], nil, "the old armor key is gone")
check(y["2:4:61-92"] and y["2:4:61-92"].n == 30 and y["2:4:61-92"].maxLevel == 92, "...its 30 samples now in 61-92")
eq(T:GetExpected({ quality = 2, classID = ARMOR, itemLevel = 70 }).samples, 30, "and an ilvl 70 item uses them")
local wpn = y["2:2:61-92"]
check(y["2:2:61-1000"] == nil and wpn.n == 6 and wpn.materials[16203].drops == 5 and wpn.materials[16203].total == 12
    and wpn.materials[16203].minAmount == 2 and wpn.materials[16203].maxAmount == 3, "the old weapon bucket merges into the new one")

-- 5f. #58: the rare 1-25 bucket is dropped at load (its samples have no
-- item level to split them by); other rare buckets stay.
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.loadAddon({ savedDB = { yields = {
    ["3:any:1-25"] = { quality = 3, minLevel = 1, maxLevel = 25, n = 12,
        materials = { [10978] = { drops = 12, total = 12, minAmount = 1, maxAmount = 1 } } },
    ["3:any:26-30"] = { quality = 3, minLevel = 26, maxLevel = 30, n = 5,
        materials = { [11084] = { drops = 5, total = 5, minAmount = 1, maxAmount = 1 } } },
    ["2:4:16-20"] = { quality = 2, classID = ARMOR, minLevel = 16, maxLevel = 20, n = 3,
        materials = { [DUST] = { drops = 3, total = 6, minAmount = 2, maxAmount = 2 } } },
} } })
WoW.flushTimers()
y = yields()
eq(y["3:any:1-25"], nil, "the old rare 1-25 bucket is dropped")
check(y["3:any:26-30"] and y["3:any:26-30"].n == 5, "the rare 26-30 bucket stays")
check(y["2:4:16-20"] and y["2:4:16-20"].n == 3, "uncommon buckets stay")

-- Mail: two vests from one sender, both received and queued by Mail.
local function mailSetup()
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    WoW.AddItem(VEST, { name = "Green Vest", quality = 2, itemLevel = 20, classID = ARMOR, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
    WoW.AddItem(DUST, { name = "Strange Dust", quality = 1, itemLevel = 1, classID = 7, subclassID = 12, equipLoc = "" })
    WoW.inbox = { { sender = "Alpha Smith", subject = "DE please", items = { [1] = { itemID = VEST }, [2] = { itemID = VEST } } } }
    WoW.loadAddon()
    WoW.flushTimers()
    SlashCmdList.SHATTER("mailtest")
    MailFrame:Show()
    WoW.fire("MAIL_SHOW")
    WoW.flushTimers()
    Shatter.MailMode:StartNewSessionFromLaunchPanel()
    WoW.flushTimers()
    for a, slot in ipairs({ 2, 3 }) do
        Shatter.AttachmentQueue:TakeNext()
        WoW.inbox[1].items[a] = nil
        WoW.SetBagItem(0, slot, { itemID = VEST })
        WoW.fire("BAG_UPDATE_DELAYED")
        WoW.fire("MAIL_INBOX_UPDATE")
        WoW.flushTimers()
    end
    Shatter.MainFrame:SetActiveView("mail")
    return Shatter.MainFrame.primary
end
local function seedDust(n)
    ShatterDB.yields = { ["2:4:16-20"] = { quality = 2, classID = ARMOR, minLevel = 16, maxLevel = 20, n = n,
        materials = { [DUST] = { drops = n, total = 2 * n, minAmount = 2, maxAmount = 2 } } } }
end
local function mailEstimates()
    local out = {}
    for _, it in ipairs(Shatter.Queue:GetItems()) do
        out[#out + 1] = it.expectedEstimate and it.expectedEstimate.measured
    end
    return out
end

-- 6. Mail: the disenchant that reaches the threshold already counts for
-- the next queued item (recorded before Mail rebuilds its queue).
button = mailSetup()
seedDust(T.MIN_YIELD_SAMPLES - 1)
Shatter.MailMode:PrepareDisenchantQueue()
eq(Shatter.Queue:GetOwner(), "mail", "Mail owns the queue")
eq(#Shatter.Queue:GetItems(), 2, "both vests queued")
eq(mailEstimates()[1], false, "one short of the threshold: the table")
disenchant(button, { { link = WoW.link(DUST), count = 2, name = "Strange Dust" } })
eq(yields()["2:4:16-20"].n, T.MIN_YIELD_SAMPLES, "the mail disenchant is measured")
local left = Shatter.Queue:GetItems()
eq(#left, 1, "one vest left in the Mail queue")
eq(left[1] and left[1].expectedEstimate and left[1].expectedEstimate.measured, true,
    "the remaining vest already uses the measured odds")

-- 7. Mail: /shatter yields reset refreshes the Mail queue's estimates and
-- leaves Mail the owner.
mailSetup()
seedDust(T.MIN_YIELD_SAMPLES)
Shatter.MailMode:PrepareDisenchantQueue()
eq(mailEstimates()[1], true, "measured before the reset")
SlashCmdList.SHATTER("yields reset")
WoW.flushTimers()
eq(Shatter.Queue:GetOwner(), "mail", "Mail still owns the queue")
local after = mailEstimates()
check(#after == 2 and after[1] == false and after[2] == false, "both vests back on the built-in table")

done("test_yields")
