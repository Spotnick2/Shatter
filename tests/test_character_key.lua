------------------------------------------------------------
-- test_character_key.lua - the character key (#73):
--   * the full name, "First Surname", whether UnitName("player") gives it
--     whole or split; no realm (hidden since the 2026-11-20 hotfix);
--   * a character's old "<name>-<realm>" entries are found on its first
--     login: settings and profile choice copied, the session bucket moved;
--   * a first name shared by several old keys takes none of them;
--   * an entry already under the new key is never overwritten.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local function load(savedDB, split)
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    if split then
        -- 70374 and later: UnitName("player") may split the name in two.
        UnitName = function(unit)
            if unit == "player" then return "Example", "Surname" end
        end
    end
    WoW.loadAddon({ savedDB = savedDB })
    WoW.flushTimers()
    return Shatter.Database
end

local function personal(tooltip)
    return { tooltip = tooltip }
end

-- 1. The key is the full name, whole or split, and has no realm.
local db = load()
eq(db:GetCharacterKey(), "Example Surname", "the key is the full name")
db = load(nil, true)
eq(db:GetCharacterKey(), "Example Surname", "...also when UnitName splits it")
db:SetProfileScope("PERSONAL")
eq(ShatterDB.profileScopeByCharacter["Example Surname"], "PERSONAL", "the profile choice is stored under it")

-- 2. The old full-name key, with its realm: everything comes across.
local bucket = { activeMail = { sessionId = "MAIL:Example Surname-ClassicBetaPvE:100", status = "SELECTING" }, mailHistory = {} }
db = load({
    characterSettings = { ["Example Surname-ClassicBetaPvE"] = personal("never") },
    profileScopeByCharacter = { ["Example Surname-ClassicBetaPvE"] = "PERSONAL" },
    sessions = { byCharacter = { ["Example Surname-ClassicBetaPvE"] = bucket } },
})
eq(db:GetProfileScope(), "PERSONAL", "the old profile choice applies")
eq(db:GetSettings().tooltip, "never", "...and the old personal settings with it")
check(ShatterDB.characterSettings["Example Surname-ClassicBetaPvE"] ~= nil, "the old settings stay where they were")
eq(ShatterDB.profileScopeByCharacter["Example Surname-ClassicBetaPvE"], "PERSONAL", "...and so does the old choice")
check(Shatter.MailSession:Get() == bucket.activeMail, "the active mail session is found")
eq(ShatterDB.sessions.byCharacter["Example Surname-ClassicBetaPvE"], nil, "the session bucket moved, not copied")

-- 3. The first name alone (a split UnitName before the hotfix), or the
-- "-Realm" key the hotfix made: the only match, so it is this character's.
db = load({
    characterSettings = { ["Example-ClassicBetaPvE"] = personal("modifier") },
    profileScopeByCharacter = { ["Example-Realm"] = "PERSONAL" },
}, true)
eq(db:GetProfileScope(), "PERSONAL", "the only match by first name is taken")
eq(db:GetSettings().tooltip, "modifier", "...in each table")

-- 4. Several matches: a single full-name one wins.
db = load({
    profileScopeByCharacter = { ["Example-ClassicBetaPvE"] = "GLOBAL", ["Example Surname-ClassicBetaPvE"] = "PERSONAL" },
})
eq(db:GetProfileScope(), "PERSONAL", "the full-name match wins over a first-name one")

-- 5. A first name shared by two old keys, with no full-name one: neither is
-- taken, since either may be another character's.
db = load({
    profileScopeByCharacter = { ["Example-ClassicBetaPvE"] = "PERSONAL", ["Example-Realm"] = "PERSONAL" },
    characterSettings = { ["Example-ClassicBetaPvE"] = personal("never"), ["Example-Realm"] = personal("never") },
})
eq(db:GetProfileScope(), "GLOBAL", "an ambiguous first name: Global, as for a new character")
eq(ShatterDB.characterSettings["Example Surname"], nil, "...and no settings copied")

-- 6. Another character's keys are never taken: not a prefix, not another
-- surname.
db = load({
    profileScopeByCharacter = { ["Examples-ClassicBetaPvE"] = "PERSONAL", ["Example Other-ClassicBetaPvE"] = "PERSONAL" },
})
eq(db:GetProfileScope(), "GLOBAL", "another name, or another surname, is someone else")

-- 7. An entry under the new key is never overwritten by an old one.
db = load({
    profileScopeByCharacter = { ["Example Surname"] = "GLOBAL", ["Example Surname-ClassicBetaPvE"] = "PERSONAL" },
    sessions = { byCharacter = {
        ["Example Surname"] = { mailHistory = { { sessionId = "MAIL:Example Surname:200", status = "CLOSED" } } },
        ["Example Surname-ClassicBetaPvE"] = { mailHistory = {} },
    } },
})
eq(db:GetProfileScope(), "GLOBAL", "the new key's choice stands")
eq(#ShatterDB.sessions.byCharacter["Example Surname"].mailHistory, 1, "...and its session bucket")
check(ShatterDB.sessions.byCharacter["Example Surname-ClassicBetaPvE"] ~= nil, "the old bucket is left alone")

-- 8. No name yet: "Unknown", and nothing is migrated under it.
db = load({ profileScopeByCharacter = { ["Example Surname-ClassicBetaPvE"] = "PERSONAL" } })
local unitName = UnitName
UnitName = function() return nil end
eq(db:GetCharacterKey(), "Unknown", "no name: Unknown")
eq(ShatterDB.profileScopeByCharacter.Unknown, nil, "...with nothing migrated under it")
UnitName = unitName

done("test_character_key")
