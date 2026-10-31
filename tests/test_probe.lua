------------------------------------------------------------
-- test_probe.lua - ShatterProbe on ForeverProbe (#5, #6): it loads as a
-- module, reads Enchanting both ways (and says when they differ, or when a
-- collapsed header hides it), records a Disenchant's events in order, its
-- wait steps finish on the right outcome, its procedures exist, and nothing
-- reaches chat. Local only: CI has no ForeverProbe (FOREVERPROBE_OPTIONAL).
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

WoW.loadForeverProbe()
local ns = {}
assert(loadfile("Tools/ShatterProbe/ShatterProbe.lua"))("ShatterProbe", ns)
WoW.fire("ADDON_LOADED", "ShatterProbe")
local T = ns._test
local chatBefore = #WoW.messages

local function logHas(text)
    for _, line in ipairs(ShatterProbeDB.log) do
        if tostring(line):find(text, 1, true) then return true end
    end
    return false
end

H.check(type(ShatterProbeDB) == "table" and logHas("loaded (1 loads)"), "the module loads and logs to its own table")

-- 1. Enchanting, both ways.
WoW.skillLines = {
    { skillID = 0, name = "Professions", isHeader = true, isCollapsed = false },
    { skillID = 186, name = "Mining", rank = 40, maxRank = 75 },
    { skillID = 333, name = "Enchanting", rank = 87, maxRank = 150 },
}
local rank, idRank, max, idMax, index, collapsed = T.readSkill()
H.eq(rank, 87, "by skill lines: the rank")
H.eq(idRank, 87, "by ID 333: the rank")
H.check(max == 150 and idMax == 150 and index == 3 and collapsed == 0, "...the max, where, no collapsed header")
H.check(logHas("Enchanting: lines 87/150, by ID 87/150, the same"), "...logged as agreeing")
WoW.skillLines[1].isCollapsed = true
rank, idRank = T.readSkill()
H.eq(rank, nil, "a collapsed header hides it from the skill lines")
H.eq(idRank, 87, "...not from the ID read")
H.check(logHas("no Enchanting in 1 lines (1 collapsed header(s))") and logHas("NOT the same"), "...and the log says so")
WoW.skillLines = {}
rank, idRank = T.readSkill()
H.check(rank == nil and idRank == nil, "no Enchanting at all: nil both ways, no error")

-- 2. The recorder: a control that succeeds.
T.watch(true)
local wait = T.outcome("control", "success")
local done = wait()
H.eq(done, false, "the control step waits")
WoW.fire("UNIT_SPELLCAST_SENT", "player", "Green Vest", "cast-1", 13262)
WoW.fire("UNIT_SPELLCAST_START", "player", "cast-1", 13262)
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 13262)
WoW.fire("LOOT_READY")
local result, errors, order
done, result, errors, order = wait()
H.eq(done, true, "...and finishes on SUCCEEDED")
H.eq(result, "succeeded", "...as succeeded")
H.eq(order, "SENT > START > SUCCEEDED > LOOT_READY", "...with the events in order")

-- 3. A flagged item: a UI error, with GetGameMessageInfo, then FAILED.
WoW.advance(5)
WoW.gameErrors[50] = "ERR_CANT_BE_DISENCHANTED"
wait = T.outcome("flagged")
H.eq((wait()), false, "the flagged step waits")
WoW.fire("UI_ERROR_MESSAGE", 50, "Item cannot be disenchanted")
WoW.fire("UNIT_SPELLCAST_FAILED", "player", "cast-2", 13262)
done, result, errors, order = wait()
H.eq(done, true, "...finishes on the refusal")
H.eq(result, "failed", "...as failed")
H.check(errors:find('type 50, "Item cannot be disenchanted" info "ERR_CANT_BE_DISENCHANTED"', 1, true),
    "...with the error's type, text and name (" .. tostring(errors) .. ")")
H.eq(order, "UI_ERROR_MESSAGE > FAILED", "...in the order they came")

-- 4. A refusal with no cast at all (the client refuses the target).
WoW.advance(5)
wait = T.outcome("highlevel")
wait()
WoW.fire("UI_ERROR_MESSAGE", 51, "Your skill is not high enough")
done, result = wait()
H.check(done and result == "refused before casting", "a UI error alone: refused before casting")

-- 5. Another unit's cast is ignored; the control doesn't finish on a failure.
WoW.advance(5)
wait = T.outcome("control2", "success")
wait()
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "target", "cast-3", 13262)
WoW.fire("UNIT_SPELLCAST_FAILED", "player", "cast-4", 13262)
H.eq((wait()), false, "the control waits through another unit's cast and a failure")

-- 6. Off: nothing more is recorded.
local n = #T.recorded
T.watch(false)
WoW.fire("UI_ERROR_MESSAGE", 50, "Item cannot be disenchanted")
H.eq(#T.recorded, n, "watch off: nothing recorded")

-- 7. The refuse procedure run twice without a /reload: the second run's
-- steps wait for new casts, never finish on the first run's.
local R = T.REFUSE
R[1].run()
H.eq((R[2].wait()), false, "run 1: the control waits")
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-5", 13262)
H.eq((R[2].wait()), true, "...finishes on its success")
WoW.fire("UI_ERROR_MESSAGE", 50, "Item cannot be disenchanted")
H.eq((R[4].wait()), true, "run 1: the flagged step finishes on its refusal")
WoW.advance(5)
R[1].run()
H.eq((R[2].wait()), false, "run 2: the control waits, the old success forgotten")
H.eq((R[4].wait()), false, "run 2: the flagged step waits, the old refusal forgotten")
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-6", 13262)
H.eq((R[2].wait()), true, "run 2: a new success finishes the control")

-- 9. loot (#10): the timeline, timed from the first event, and a step that
-- waits out late events (3 s with nothing new).
WoW.advance(5)
local L = T.LOOT
WoW.cvars.autoLootDefault = "1"
H.eq(L[1].run(), true, "loot: starts recording and reads Auto Loot")
H.eq((L[2].check()), true, "...the Auto Loot ON step checks it")
local w = L[3].wait
H.eq((w()), false, "...waits for a Disenchant")
WoW.fire("UNIT_SPELLCAST_SENT", "player", "Green Vest", "c7", 13262)
WoW.advance(1.5)
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c7", 13262)
WoW.advance(0.1)
WoW.fire("BAG_UPDATE_DELAYED")
local line
done, line = w()
H.check(not done and line == "waiting for late events", "...then waits out late events")
WoW.advance(0.4)
WoW.fire("LOOT_READY", true)
WoW.fire("LOOT_OPENED", true, true)
WoW.fire("LOOT_CLOSED")
WoW.advance(2.9)
H.eq((w()), false, "...each event restarts the wait")
WoW.advance(0.2)
done, line = w()
H.eq(done, true, "...done 3 s after the last event")
H.eq(line, "SENT +0.00 (spell 13262 (Disenchant)) > SUCCEEDED +1.50 (spell 13262 (Disenchant)) > BAG_UPDATE_DELAYED +1.60"
    .. " > LOOT_READY +2.00 (autoloot true) > LOOT_OPENED +2.00 (autoLoot true, isFromItem true) > LOOT_CLOSED +2.00",
    "...the timeline: each event, its time and its arguments")
WoW.cvars.autoLootDefault = "0"
H.eq((L[4].check()), true, "the Auto Loot OFF step checks it")
w = L[5].wait
w()
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c8", 13262)
WoW.advance(4)
done, line = w()
H.check(not done and line:find("loot window still open", 1, true), "manual loot: waits for the window to close")
WoW.fire("LOOT_CLOSED")
WoW.advance(3)
H.eq((w()), true, "...then finishes")
w = L[7].wait
w()
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c9", 13262)
WoW.advance(4)
done, line = w()
H.check(not done and line == "1 of 2 Disenchant(s)", "two quick clicks: waits for both")
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c10", 13262)
WoW.advance(3)
H.eq((w()), true, "...then finishes")

-- 10. mail (#26): the frames, a second after the close.
local M = T.MAIL
MailFrame:Show()
H.eq(M[2].run(), "MailFrame shown true visible true, InboxFrame shown true visible true", "mail: the frames while open")
MailFrame:Hide()
H.eq((M[4].wait()), false, "...after the close, waits a second")
WoW.advance(1)
done, line = M[4].wait()
H.check(done and line == "MailFrame shown false visible false, InboxFrame shown true visible false",
    "...then reads #26's state: InboxFrame shown, not visible (" .. tostring(line) .. ")")
H.eq((M[4].check()), true, "...and checks MailFrame is hidden")

-- 11. guid: followed across a drag, a sort and a /reload.
local G = T.GUID
WoW.SetBagItem(0, 1, { itemID = 2589 })
WoW.bags[1].size = 4
G[1].run()
H.check(G[1].check() and ShatterProbeDB.heldGUID:find("^Item%-"), "guid: backpack slot 1's GUID is followed")
WoW.MoveBagItem(0, 1, 1, 3)
local bag, slot, itemID = G[2].run()
H.check(bag == 1 and slot == 3 and itemID == 2589, "...found where it was dragged")
H.eq((G[2].check()), true, "...and the step passes")
WoW.MoveBagItem(1, 3, 0, 5)
H.eq((G[3].check()), true, "...found after a sort")
WoW.bags[0][5] = nil
WoW.SetBagItem(0, 5, { itemID = 2589 })
H.eq((G[5].check()), false, "a new instance of the item (a new GUID) fails")
H.eq(G[5].run(), nil, "...nothing found")

-- 11b. sets (#36): the bag slot call, read for every slot.
local SE = T.SETS
WoW.bags[0][5] = nil
WoW.SetBagItem(0, 6, { itemID = 2589, inSet = true, setList = "Fire" })
local nIn, text = SE[2].run()
H.check(nIn == 1 and text:find("bag 0 slot 6", 1, true) and text:find('"Fire"', 1, true), "sets: finds the item in a set (" .. tostring(text) .. ")")
H.eq((SE[2].check()), true, "...the step passes")
WoW.bags[0][6].inSet = false
H.eq((SE[2].check()), false, "nothing in a set: the step fails")

-- 8. The procedures and commands.
SlashCmdList.FOREVERPROBE("steps sh skill")
local rec = ForeverProbeDB.steps and ForeverProbeDB.steps.records and ForeverProbeDB.steps.records["ShatterProbe/skill"]
H.check(rec and rec.status == "active", "/fp steps sh skill starts")
SlashCmdList.FOREVERPROBE("steps stop")
SlashCmdList.FOREVERPROBE("steps sh refuse")
rec = ForeverProbeDB.steps.records["ShatterProbe/refuse"]
H.check(rec and rec.status == "active", "/fp steps sh refuse starts")
SlashCmdList.FOREVERPROBE("steps stop")
SlashCmdList.FOREVERPROBE("sh clear")
SlashCmdList.FOREVERPROBE("sh skill")
H.check(logHas("Enchanting:"), "/fp sh skill logs after a clear")

for _, name in ipairs({ "loot", "mail", "guid", "next", "looks", "tips", "sets", "ilvl" }) do
    SlashCmdList.FOREVERPROBE("steps sh " .. name)
    rec = ForeverProbeDB.steps.records["ShatterProbe/" .. name]
    H.check(rec and rec.status == "active", "/fp steps sh " .. name .. " starts")
    SlashCmdList.FOREVERPROBE("steps stop")
end

H.eq(#WoW.messages, chatBefore, "nothing reached chat")

-- 12. With Shatter loaded: next, looks and tips drive it from outside, as
-- the owner would (its main frame, /shatter).
local VEST = 2589
WoW.enchanter()
WoW.AddItem(VEST, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
WoW.bags[0][1] = nil
WoW.SetBagItem(0, 3, { itemID = VEST })
WoW.loadAddon()
WoW.flushTimers()
Shatter.MainFrame:Show()
-- 12a. ilvl (#37): each worn slot both ways, what Shatter reads, and Suggest.
local IL = T.ILVL
WoW.equipped = {}
H.eq((IL[1].check()), false, "ilvl: nothing worn, the step fails")
WoW.equipped[5] = { itemID = 2589, level = 27 }
WoW.equipped[4] = { itemID = 2589, level = 1 }   -- shirt
local nWorn, worn = T.readItemLevels()
H.eq(nWorn, 2, "ilvl: reads every worn slot, the shirt too")
H.check(worn:find("slot 5 ", 1, true) and worn:find("current 27, item 20, Shatter 27", 1, true),
    "...with the current level, the item's own and Shatter's (" .. tostring(worn) .. ")")
H.check(worn:find("Suggest 27", 1, true), "...and Suggest, without the shirt")
H.eq((IL[1].check()), true, "...the step passes")
WoW.equipped = {}

local N = T.NEXT
H.eq(N[1].run(), true, "next: finds Shatter Next under ShatterMainFrame")
local button = T.findNext()
H.check(button == Shatter.MainFrame.primary, "...the secure primary button")
H.eq((N[2].wait()), false, "...waits for the click's cast")
WoW.click(button, "LeftButton")
WoW.fire("UNIT_SPELLCAST_SENT", "player", "Green Vest", "c11", 13262)
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c11", 13262)
WoW.advance(2)
local sent, disarmed
done, sent, disarmed, line = N[2].wait()
H.check(done and sent == 1 and disarmed, "...one Disenchant sent, disarmed after")
H.check(line:find('PreClick LeftButton up: type "spell", spell 13262, bag 0, slot 3', 1, true)
    and line:find("PostClick LeftButton up: type nil, spell nil, bag nil, slot nil", 1, true),
    "...armed on the up edge's PreClick, disarmed by its PostClick (" .. line .. ")")
H.eq((N[2].check()), true, "...and the step passes")
WoW.click(button, "RightButton")
sent = N[3].run()
H.eq(sent, 0, "a right click: nothing sent")
H.eq((N[3].check()), true, "...the step passes")
WoW.clickEdge(button, "LeftButton", true)
WoW.fire("UNIT_SPELLCAST_SENT", "player", "Green Vest", "c12", 13262)   -- as if it had cast
H.eq((N[4].run()), 1, "released off the button, a cast would be counted")
H.eq((N[4].check()), false, "...and fail the step")
-- #35: the key. One press, one cast; with the window closed, nothing.
-- (The step starts once Done was pressed: time has moved on in game.)
WoW.advance(1)
N[4].run()
H.eq((N[5].wait()), false, "the key step waits for the cast")
WoW.pressBinding("CLICK ShatterNextButton:LeftButton")
WoW.fire("UNIT_SPELLCAST_SENT", "player", "Green Vest", "c13", 13262)
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c13", 13262)
WoW.advance(2)
done, sent, disarmed = N[5].wait()
H.check(done and sent == 1 and disarmed, "...one key press: one Disenchant, disarmed")
local passed, detail = N[5].check()
H.check(passed and detail:find("ActionButtonUseKeyDown", 1, true), "...the step passes, naming the CVar (" .. tostring(detail) .. ")")
Shatter.MainFrame:RequestShown(false)
WoW.pressBinding("CLICK ShatterNextButton:LeftButton")
H.eq((N[6].run()), 0, "window closed: the key sends nothing")
H.eq((N[6].check()), true, "...the step passes")
Shatter.MainFrame:Show()

local LK = T.LOOKS
H.eq(LK[1].run(), "forever", "looks: remembers the look")
local switched
for _, step in ipairs(LK) do
    if step.text:find("switch to smoked (bright", 1, true) then switched = step.run() end
end
H.eq(switched, "smoked", "...switches through /shatter skin")
H.eq((LK[1].check()), true, "...the first step checks Shatter isn't following Glass UI")
-- Stopped midway and run again: the first backup is kept, not the changed look.
H.eq(LK[1].run(), "forever", "run again with the look changed: the original backup is kept")
H.eq(LK[#LK - 1].run(), "forever", "...and put back")
H.eq(ShatterProbeDB.restore.GLOBAL, nil, "...a verified restore clears the backup")
-- Following Glass UI (Skin.Shown "suite"): no look can be switched, so no
-- step may complete and take a shot under the wrong name.
local realShown = Shatter.Skin.Shown
Shatter.Skin.Shown = function() return "suite" end
H.eq((LK[1].check()), false, "following Glass UI: the first step fails")
local ok, err
for _, step in ipairs(LK) do
    if step.text:find("switch to clear (bright", 1, true) then ok, err = pcall(step.run) end
end
H.check(not ok and tostring(err):find('Shatter shows "suite", not clear', 1, true),
    "...a look step throws (stays, no shot): " .. tostring(err))
Shatter.Skin.Shown = realShown

local TP = T.TIPS
H.eq(TP[1].run(), "always", "tips: sets the tooltips to always")
WoW.showItemTooltip(VEST)
local tipName, tipItem, lines
done, tipName, tipItem, lines = TP[2].wait()
H.check(done and tipName == "GameTooltip" and tipItem == VEST and lines > 1, "...a bag item's tooltip, with Shatter's lines")
H.eq((TP[4].wait()), false, "...the vendor step waits for MerchantFrame")
CreateFrame("GameTooltip", "ItemRefTooltip", UIParent)   -- ItemRef.xml: on the client from login
WoW.showItemTooltip(VEST, ItemRefTooltip)
H.eq((TP[3].wait()), true, "...a chat link's tooltip")
H.eq(TP[8].run(), "modifier", "...then to modifier")
WoW.showItemTooltip(VEST)
done, line = TP[9].wait()
H.check(not done and line:find("without a modifier", 1, true), "...without Shift: waits")
WoW.shift = true
done = TP[9].wait()
H.eq(done, false, "...Shift held, the same lines: still waits")
WoW.showItemTooltip(VEST)
local before, after
done, tipName, tipItem, before, after = TP[9].wait()
H.check(done and after > before, "...rebuilt with Shift: more lines, done")
WoW.shift = false
H.eq(TP[12].run(), "always", "...and the setting goes back")
-- Stopped midway: /fp sh restore puts the original back, once.
SlashCmdList.SHATTER("tooltip never")
TP[1].run()
TP[8].run()
H.eq(ShatterProbeDB.restore.GLOBAL.tooltip, "never", "tips: the original is backed up, for the Global profile")
TP[1].run()
H.eq(ShatterProbeDB.restore.GLOBAL.tooltip, "never", "...run again midway: still the original")
-- The backup belongs to the profile it came from: a Personal profile on this
-- character doesn't take it, and keeps it pending.
local db = Shatter.Database
db:SetProfileScope("PERSONAL")
db:GetSettings().tooltip = "always"
SlashCmdList.FOREVERPROBE("sh restore")
H.eq(db:GetSettings().tooltip, "always", "another profile active: /fp sh restore leaves it alone")
H.eq(ShatterProbeDB.restore.GLOBAL.tooltip, "never", "...and the Global backup stays pending")
H.check(logHas("still backed up for another profile, put back from there: tooltip (GLOBAL)"), "...and says where it belongs")
db:SetProfileScope("GLOBAL")
SlashCmdList.FOREVERPROBE("sh restore")
H.eq(db:GetSettings().tooltip, "never", "back in the Global profile: /fp sh restore puts it back")
H.eq(ShatterProbeDB.restore.GLOBAL, nil, "...and clears the backup")
-- A character's Personal backup is never applied on another character.
db:SetProfileScope("PERSONAL")
local alpha = "PERSONAL " .. db:GetCharacterKey()
SlashCmdList.SHATTER("tooltip never")
TP[1].run()
H.eq(ShatterProbeDB.restore[alpha].tooltip, "never", "a Personal profile's backup is its own")
local name = WoW.player.name
WoW.player.name = "Beta"
db:GetSettings().tooltip = "modifier"
SlashCmdList.FOREVERPROBE("sh restore")
H.eq(db:GetSettings().tooltip, "modifier", "another character (Global): untouched")
H.eq(ShatterProbeDB.restore[alpha].tooltip, "never", "...the first character's backup stays pending")
WoW.player.name = name
SlashCmdList.FOREVERPROBE("sh restore")
H.eq(db:GetSettings().tooltip, "never", "back on the first character: put back")
H.eq(ShatterProbeDB.restore[alpha], nil, "...and cleared")

H.done("test_probe")
