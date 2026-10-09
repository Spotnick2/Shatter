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
    WoW.click(button, "LeftButton")
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
H.eq(key(2, ARMOR, 20), "2:4:16-20", "uncommon armor 20")
H.eq(key(2, WEAPON, 20), "2:2:16-20", "uncommon weapon 20: its own bucket")
H.eq(key(2, ARMOR, 58), "2:4:56-60", "uncommon armor 58: the shard rule's 56+ narrowed to 56-60")
H.eq(key(3, WEAPON, 33), "3:any:31-35", "rare: no class split")
H.eq(key(4, ARMOR, 30), nil, "no rule, no bucket")

-- 2. A real disenchant read from the loot window is recorded.
local button = setup()
H.eq(yields(), nil, "nothing measured before the first disenchant")
disenchant(button, { { link = WoW.link(DUST), count = 2, name = "Strange Dust" } })
local bucket = yields() and yields()["2:4:16-20"]
H.check(bucket and bucket.n == 1, "one disenchant measured in its bucket")
H.check(bucket and bucket.materials[DUST] and bucket.materials[DUST].drops == 1 and bucket.materials[DUST].total == 2,
    "the dust: dropped once, 2 of them")

-- 3. Not recorded: a result seen only as a bag change, a loot window with
-- anything but materials, a simulated disenchant.
button = setup()
disenchant(button, nil)
H.eq(yields(), nil, "bag change only: not measured")
button = setup()
disenchant(button, { { link = WoW.link(DUST), count = 2, name = "Strange Dust" }, { link = WoW.link(VEST), count = 1, name = "Green Vest" } })
H.eq(yields(), nil, "a loot window with a non-material: not measured")
button = setup()
local settings = Shatter.Database:GetSettings()
settings.debug, settings.simulateDisenchant = true, true
WoW.click(button, "LeftButton")
WoW.flushTimers()
H.eq(yields(), nil, "simulated: not measured")

-- 4. Below the threshold the table decides; from it on, the measured odds.
setup()
local vest = { quality = 2, classID = ARMOR, itemLevel = 20 }
local function measure(n, drops, total)
    ShatterDB.yields = { ["2:4:16-20"] = { quality = 2, classID = ARMOR, minLevel = 16, maxLevel = 20, n = n,
        materials = { [ESSENCE] = { drops = drops, total = total, minAmount = 1, maxAmount = 3 } } } }
end
measure(T.MIN_YIELD_SAMPLES - 1, T.MIN_YIELD_SAMPLES - 1, 40)
local e = T:GetExpected(vest)
H.eq(e.measured, false, "below the threshold: the built-in table")
H.eq(e.samples, T.MIN_YIELD_SAMPLES - 1, "...with the sample count")
H.check(e.materials[1].itemID == DUST, "...whose top material for armor is dust")
measure(T.MIN_YIELD_SAMPLES, T.MIN_YIELD_SAMPLES / 2, T.MIN_YIELD_SAMPLES)
e = T:GetExpected(vest)
H.eq(e.measured, true, "at the threshold: measured")
H.eq(#e.materials, 1, "only what was measured")
H.check(e.materials[1].itemID == ESSENCE and math.abs(e.materials[1].chance - 0.5) < 1e-9
    and math.abs(e.materials[1].expectedAmount - 1) < 1e-9, "measured odds: 50%, one per disenchant on average")
H.eq(T:GetExpected({ quality = 2, classID = WEAPON, itemLevel = 20 }).measured, false, "another bucket keeps the table")

-- 5. /shatter yields lists the buckets; /shatter yields reset clears them.
button = setup()
disenchant(button, { { link = WoW.link(DUST), count = 2, name = "Strange Dust" } })
SlashCmdList.SHATTER("yields")
H.check(WoW.chat():find("Uncommon armor 16-20: 1 (table used) - Strange Dust 100% x2.0", 1, true), "the bucket is listed")
SlashCmdList.SHATTER("yields reset")
H.eq(yields(), nil, "reset clears the measurements")
SlashCmdList.SHATTER("yields")
H.check(WoW.chat():find("No disenchants measured yet.", 1, true), "an empty list says so")

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
H.eq(Shatter.Queue:GetOwner(), "mail", "Mail owns the queue")
H.eq(#Shatter.Queue:GetItems(), 2, "both vests queued")
H.eq(mailEstimates()[1], false, "one short of the threshold: the table")
disenchant(button, { { link = WoW.link(DUST), count = 2, name = "Strange Dust" } })
H.eq(yields()["2:4:16-20"].n, T.MIN_YIELD_SAMPLES, "the mail disenchant is measured")
local left = Shatter.Queue:GetItems()
H.eq(#left, 1, "one vest left in the Mail queue")
H.eq(left[1] and left[1].expectedEstimate and left[1].expectedEstimate.measured, true,
    "the remaining vest already uses the measured odds")

-- 7. Mail: /shatter yields reset refreshes the Mail queue's estimates and
-- leaves Mail the owner.
mailSetup()
seedDust(T.MIN_YIELD_SAMPLES)
Shatter.MailMode:PrepareDisenchantQueue()
H.eq(mailEstimates()[1], true, "measured before the reset")
SlashCmdList.SHATTER("yields reset")
WoW.flushTimers()
H.eq(Shatter.Queue:GetOwner(), "mail", "Mail still owns the queue")
local after = mailEstimates()
H.check(#after == 2 and after[1] == false and after[2] == false, "both vests back on the built-in table")

H.done("test_yields")
