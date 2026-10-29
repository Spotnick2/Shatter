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

-- 7. The procedures and commands.
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

H.eq(#WoW.messages, chatBefore, "nothing reached chat")

H.done("test_probe")
