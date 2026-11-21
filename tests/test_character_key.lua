------------------------------------------------------------
-- test_character_key.lua - the character key (#73):
--   * the full name, "First Surname", whether UnitName("player") gives it
--     whole or split; no realm (hidden since the 2026-11-20 hotfix);
--   * old "<full name>-<realm>" entries are this character's: moved on its
--     first login; of several, the hotfix's "-Realm" one;
--   * mail buckets merge after the account-wide import: histories join, an
--     empty open session is archived, one open session with work is active
--     and any other stays reserved under its old key;
--   * old "<first name>-<realm>" entries are only claimed on the player's
--     answer (OldKeyPrompt), asked once; their received items stay reserved
--     meanwhile, whoever logs in first;
--   * an entry already under the new key is never overwritten.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local OLD = "Example Surname-ClassicBetaPvE"
local HOTFIX = "Example Surname-Realm"
local FIRST = "Example-ClassicBetaPvE"
local VEST = 2589

local function load(savedDB, opts)
    opts = opts or {}
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    WoW.AddItem(VEST, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
    if opts.name then WoW.player.name = opts.name end
    if opts.split then
        -- 70374 and later: UnitName("player") may split the name in two.
        UnitName = function(unit)
            if unit == "player" then return WoW.player.name:match("^(%S+) (.+)$") end
        end
    end
    if opts.bags then opts.bags() end
    if opts.before then opts.before() end
    WoW.loadAddon({ savedDB = savedDB })
    WoW.flushTimers()
    return Shatter.Database
end

local function prompt() return Shatter.OldKeyPrompt.frame end
local function prompted() return prompt() ~= nil and prompt():IsShown() end

-- An open mail session holding one received item, by GUID (or none).
local function openSession(id, updatedAt, guid)
    return {
        sessionId = "MAIL:" .. id, status = "ReadyToDisenchant", createdAt = updatedAt, updatedAt = updatedAt,
        inputItems = { { itemID = VEST, received = true, itemGUID = guid, status = "queued", disenchantStatus = "waiting" } },
        outputRecipients = {}, sessionLog = {},
    }
end

-- 1. The key is the full name, whole or split, and has no realm.
local db = load()
eq(db:GetCharacterKey(), "Example Surname", "the key is the full name")
db = load(nil, { split = true })
eq(db:GetCharacterKey(), "Example Surname", "...also when UnitName splits it")
db:SetProfileScope("PERSONAL")
eq(ShatterDB.profileScopeByCharacter["Example Surname"], "PERSONAL", "the profile choice is stored under it")
check(not prompted(), "nothing old: nothing asked")

-- 2. The old full-name key: this character's, so it moves.
db = load({
    characterSettings = { [OLD] = { tooltip = "never" } },
    profileScopeByCharacter = { [OLD] = "PERSONAL" },
})
eq(db:GetProfileScope(), "PERSONAL", "the old profile choice applies")
eq(db:GetSettings().tooltip, "never", "...and the old personal settings with it")
eq(ShatterDB.profileScopeByCharacter[OLD], nil, "the old choice moved")
eq(ShatterDB.characterSettings[OLD], nil, "...and so did the old settings")
check(not prompted(), "a full name is not asked about")

-- 3. Several full-name keys: the hotfix's "-Realm" one, the latest choice;
-- two real realms and no "-Realm": none.
db = load({ profileScopeByCharacter = { [OLD] = "GLOBAL", [HOTFIX] = "PERSONAL" } })
eq(db:GetProfileScope(), "PERSONAL", "of several, the hotfix's -Realm key")
db = load({ profileScopeByCharacter = { [OLD] = "PERSONAL", ["Example Surname-Other Realm"] = "PERSONAL" } })
eq(db:GetProfileScope(), "GLOBAL", "two real realms: neither")

-- 4. An entry under the new key is never overwritten.
db = load({ profileScopeByCharacter = { ["Example Surname"] = "GLOBAL", [OLD] = "PERSONAL" } })
eq(db:GetProfileScope(), "GLOBAL", "the new key's choice stands")
eq(ShatterDB.profileScopeByCharacter[OLD], "PERSONAL", "...and the old one is left alone")

-- 5. Another name, or another surname, is someone else: never taken, never
-- asked about.
db = load({ profileScopeByCharacter = { ["Examples-ClassicBetaPvE"] = "PERSONAL", ["Example Other-ClassicBetaPvE"] = "PERSONAL" } })
eq(db:GetProfileScope(), "GLOBAL", "another name or surname is someone else's")
check(not prompted(), "...and not asked about")

-- 6. Mail buckets under full-name keys merge: histories join in start order,
-- the empty session v1.0.1 opened after the hotfix is archived, and the old
-- session with its received item is active again.
local vestGUID
local active = openSession(OLD .. ":100", 100)
db = load({ sessions = { byCharacter = {
    [OLD] = { activeMail = active, mailHistory = { { sessionId = "MAIL:" .. OLD .. ":10", status = "Closed", createdAt = 10 } } },
    [HOTFIX] = { activeMail = { sessionId = "MAIL:" .. HOTFIX .. ":300", status = "SelectingInput", createdAt = 300, updatedAt = 300, inputItems = {}, outputRecipients = {} },
                 mailHistory = { { sessionId = "MAIL:" .. HOTFIX .. ":200", status = "Closed", createdAt = 200 } } },
} } }, { bags = function()
    WoW.SetBagItem(0, 1, { itemID = VEST })
    vestGUID = WoW.bags[0][1].guid
    active.inputItems[1].itemGUID = vestGUID
end })
local byChar = ShatterDB.sessions.byCharacter
check(Shatter.MailSession:Get() == active, "the old session with work is active")
eq(byChar[OLD], nil, "its old bucket is gone")
eq(byChar[HOTFIX], nil, "...and the hotfix's")
local history = byChar["Example Surname"].mailHistory
eq(#history, 3, "both histories, and the empty session archived")
eq(history[1].createdAt, 10, "in start order: the oldest first")
eq(history[3].createdAt, 300, "...the empty session last")
eq(history[3].status, "Closed", "...closed")
eq((Shatter.MailSession:GetReservedSlots())["0:1"], VEST, "the received item is reserved")

-- 7. Two open sessions with work: the latest updated is active, the other
-- stays under its old key, with its received items still reserved: by GUID
-- where it has one, every copy where it hasn't.
local older = openSession(OLD .. ":100", 100)
local newer = openSession(HOTFIX .. ":300", 300)
local noGUID = 2590
db = load({ sessions = { byCharacter = {
    [OLD] = { activeMail = older, mailHistory = {} },
    [HOTFIX] = { activeMail = newer, mailHistory = {} },
} } }, { bags = function()
    WoW.AddItem(noGUID, { name = "Azure Boots", quality = 2, itemLevel = 22, classID = 4, subclassID = 2, equipLoc = "INVTYPE_FEET" })
    WoW.SetBagItem(0, 1, { itemID = VEST })
    WoW.SetBagItem(0, 2, { itemID = VEST })
    older.inputItems[1].itemGUID = WoW.bags[0][1].guid
    newer.inputItems[1].itemGUID = WoW.bags[0][2].guid
    table.insert(older.inputItems, { itemID = noGUID, received = true, status = "queued" })
end })
byChar = ShatterDB.sessions.byCharacter
check(Shatter.MailSession:Get() == newer, "the latest updated is active")
check(byChar[OLD].activeMail == older, "the other stays under its old key")
local reserved, reservedIDs = Shatter.MailSession:GetReservedSlots()
eq(reserved["0:2"], VEST, "the active session's item is reserved")
eq(reserved["0:1"], VEST, "...and the parked one's, by GUID")
eq(reservedIDs[noGUID], true, "...and every copy of its item with no GUID")
eq(Shatter.MailSession:StartNew(), nil, "Start New is refused over the active one")
check(byChar[OLD].activeMail == older, "...and the parked one is untouched")
-- Closed, then a later login adopts the parked one.
check(Shatter.MailSession:Close(true), "the active session closes")
local saved = ShatterDB
db = load(saved)
check(Shatter.MailSession:Get() == older, "the next login makes the parked session active")
eq(ShatterDB.sessions.byCharacter[OLD], nil, "...and its old bucket goes")

-- 8. Old account-wide sessions are imported, then adopted, in that order,
-- even when Glass UI's look reads the settings (and so the key) first.
local S = { API = 1, reports = {} }
function S.Theme() return { name = "pearl", preset = "pearl" } end
function S.Report(_, state) S.reports[#S.reports + 1] = state end
function S.Look() return { tint = "clear", accent = "gold" } end
function S.Body() return { tint = { 0.13, 0.16, 0.22, 0.24 }, wash = 1, backing = { 0.04, 0.05, 0.07, 0.35 } } end
function S.Accent() return { 1, 0.82, 0 } end
db = load({ sessions = { activeMail = openSession(OLD .. ":100", 100), mailHistory = {} } }, { before = function()
    rawset(_G, "GlassUI", { Suite = S })
end })
rawset(_G, "GlassUI", nil)
check(#S.reports > 0, "Glass UI's look was started")
eq(ShatterDB.sessions.activeMail, nil, "the account-wide session was imported")
local imported = Shatter.MailSession:Get()
eq(imported and imported.sessionId, "MAIL:" .. OLD .. ":100", "...and is this character's active session")
eq(ShatterDB.sessions.byCharacter[OLD], nil, "...under the new key")

-- 9. The first name alone: not taken, but asked. Meanwhile its received
-- item stays reserved.
local firstSession = openSession(FIRST .. ":100", 100)
local firstDB = {
    characterSettings = { [FIRST] = { tooltip = "modifier" } },
    profileScopeByCharacter = { [FIRST] = "PERSONAL" },
    sessions = { byCharacter = { [FIRST] = { activeMail = firstSession, mailHistory = {} } } },
}
local function firstBags()
    WoW.SetBagItem(0, 1, { itemID = VEST })
    firstSession.inputItems[1].itemGUID = WoW.bags[0][1].guid
end
db = load(firstDB, { split = true, bags = firstBags })
eq(db:GetProfileScope(), "GLOBAL", "a first name alone is not taken")
check(prompted(), "...it is asked about")
check(Shatter.OldKeyPrompt.text:GetText():find("\"Example\" on ClassicBetaPvE,", 1, true) ~= nil, "...naming the first name and realm")
check(Shatter.OldKeyPrompt.text:GetText():find("Example Surname's?", 1, true) ~= nil, "...and this character")
eq(Shatter.MailSession:Get(), nil, "its session is not this character's yet")
eq((Shatter.MailSession:GetReservedSlots())["0:1"], VEST, "...but its received item is reserved")

-- 10. Codex on #74: another character with that first name logs in first,
-- with exactly one old key. Asked, it says No: nothing moves, its received
-- item stays reserved, and it isn't asked again.
firstSession = openSession(FIRST .. ":100", 100)
firstDB = {
    characterSettings = { [FIRST] = { tooltip = "modifier" } },
    profileScopeByCharacter = { [FIRST] = "PERSONAL" },
    sessions = { byCharacter = { [FIRST] = { activeMail = firstSession, mailHistory = {} } } },
}
db = load(firstDB, { name = "Example Other", split = true, bags = firstBags })
check(prompted(), "the other character is asked")
eq(db:GetProfileScope(), "GLOBAL", "...and gets nothing before it answers")
Shatter.OldKeyPrompt:Answer(false)
check(not prompted(), "No closes the question")
eq(db:GetProfileScope(), "GLOBAL", "No takes nothing")
check(ShatterDB.sessions.byCharacter[FIRST].activeMail == firstSession, "...the session stays where it was")
eq((Shatter.MailSession:GetReservedSlots())["0:1"], VEST, "...its received item still reserved")
saved = ShatterDB
db = load(saved, { name = "Example Other", split = true })
check(not prompted(), "the other character isn't asked again")

-- 11. Then its owner logs in, is asked, and says Yes: everything comes
-- across, and it isn't asked again.
db = load(saved, { split = true })
check(prompted(), "the owner is asked")
Shatter.OldKeyPrompt:Answer(true)
eq(db:GetProfileScope(), "PERSONAL", "Yes: the profile choice comes across")
eq(db:GetSettings().tooltip, "modifier", "...the settings")
eq(Shatter.MailSession:Get() and Shatter.MailSession:Get().sessionId, "MAIL:" .. FIRST .. ":100", "...and the mail session")
eq(ShatterDB.sessions.byCharacter[FIRST], nil, "...moved, not copied")
db = load(ShatterDB, { split = true })
check(not prompted(), "the owner isn't asked again")

-- 12. Codex on #74: two characters sharing a first name may each own one of
-- its keys. Each key is asked about on its own, the hotfix's "-Realm" one
-- first: No to it, Yes to the other, and only the other comes across.
local mineSession = openSession(FIRST .. ":100", 100)
local theirs = openSession("Example-Realm:300", 300)
db = load({ sessions = { byCharacter = {
    [FIRST] = { activeMail = mineSession, mailHistory = {} },
    ["Example-Realm"] = { activeMail = theirs, mailHistory = {} },
} } }, { split = true })
check(prompted(), "two first-name keys: asked")
local text = Shatter.OldKeyPrompt.text:GetText()
check(text:find("with no realm", 1, true) ~= nil and text:find("(1 of 2)", 1, true) ~= nil, "...the -Realm key first, on its own")
Shatter.OldKeyPrompt:Answer(false)
check(prompted(), "...then the next one")
check(Shatter.OldKeyPrompt.text:GetText():find("on ClassicBetaPvE", 1, true) ~= nil, "...naming its realm")
Shatter.OldKeyPrompt:Answer(true)
check(not prompted(), "...and then done")
check(Shatter.MailSession:Get() == mineSession, "the key said Yes to comes across")
check(ShatterDB.sessions.byCharacter["Example-Realm"].activeMail == theirs, "the key said No to stays for its owner")
eq(ShatterDB.oldKeyAnswers["Example Surname"]["Example-Realm"], "not mine", "each answer is kept")
eq(ShatterDB.oldKeyAnswers["Example Surname"][FIRST], "mine", "...on its own")

-- 13. Codex on #74: a first-name session said Yes to while this character
-- has its own open session waits under its old key, reserved, and is
-- resumed at a later login once the own one is closed.
local own = openSession("Example Surname:400", 400)
local confirmed = openSession(FIRST .. ":100", 100)
db = load({ sessions = { byCharacter = {
    ["Example Surname"] = { activeMail = own, mailHistory = {} },
    [FIRST] = { activeMail = confirmed, mailHistory = {} },
} } }, { split = true, bags = function()
    WoW.SetBagItem(0, 1, { itemID = VEST })
    confirmed.inputItems[1].itemGUID = WoW.bags[0][1].guid
end })
Shatter.OldKeyPrompt:Answer(true)
check(Shatter.MailSession:Get() == own, "Yes while a session is open: the own one stays active")
check(ShatterDB.sessions.byCharacter[FIRST].activeMail == confirmed, "...the confirmed one waits under its old key")
eq((Shatter.MailSession:GetReservedSlots())["0:1"], VEST, "...its received item reserved")
check(Shatter.MailSession:Close(true), "the own session closes")
db = load(ShatterDB, { split = true })
check(not prompted(), "the next login doesn't ask again")
check(Shatter.MailSession:Get() == confirmed, "...and resumes the confirmed session")
eq(ShatterDB.sessions.byCharacter[FIRST], nil, "...from its old key")

-- 14. No name yet: "Unknown", nothing adopted, nothing asked.
db = load({ profileScopeByCharacter = { [OLD] = "PERSONAL", ["Unknown-Realm"] = "PERSONAL" } }, { before = function()
    UnitName = function() return nil end
end })
eq(db:GetCharacterKey(), "Unknown", "no name: Unknown")
eq(ShatterDB.profileScopeByCharacter.Unknown, nil, "...with nothing adopted under it")
eq(ShatterDB.profileScopeByCharacter[OLD], "PERSONAL", "...and the old key left alone")
check(not prompted(), "...and nothing asked")

done("test_character_key")
