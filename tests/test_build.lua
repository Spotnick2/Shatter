------------------------------------------------------------
-- test_build.lua - the measured-build constant, the persistence canary,
-- price integrations that never take Shatter down, and the minimap drag
-- in the minimap's own coordinate space.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

-- This literal is the point: it must be edited by hand together with the
-- constant after re-measuring a new client build (porting guide, section 0).
local MEASURED = "1.60.1.71037"
-- A dev copy: the TOC still carries the packager's token (assembled, since
-- the packager rewrites the token wherever it appears).
local DEV = "@" .. "project-version" .. "@"

WoW.enchanter()
WoW.loadAddon()
eq(Shatter.Constants.MEASURED_ON_BUILD, MEASURED, "MEASURED_ON_BUILD matches the measured build")
check(not WoW.chatText():find("Shatter was measured on", 1, true), "no notice on the measured build")

-- Another build, in a dev copy: one line at login.
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.build = "70400"
WoW.version = DEV
WoW.loadAddon()
eq(Shatter.VERSION, "dev", "an unpackaged TOC reads as dev")
check(WoW.chatText():find("This client is 1.60.1.70400; Shatter was measured on " .. MEASURED, 1, true),
    "dev copy: a different build is announced at login")

-- A deployed dev copy: Tools/deploy.ps1 stamps "dev-<revision>" (or "dev"
-- without git) into the deployed TOC. The reminder is for exactly this copy.
for _, version in ipairs({ "dev-7442134", "dev" }) do
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    WoW.build = "70400"
    WoW.version = version
    WoW.loadAddon()
    check(WoW.chatText():find("This client is 1.60.1.70400; Shatter was measured on " .. MEASURED, 1, true),
        "deployed " .. version .. ": a different build is announced at login")
end

-- A packaged release says nothing on another build (#61): the note is for
-- the developer, not players. "develop"-like text doesn't count as dev.
for _, version in ipairs({ "v1.0.0", "v1.0.1-beta1", "development" }) do
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    WoW.build = "70400"
    WoW.version = version
    WoW.loadAddon()
    check(not WoW.chatText():find("Shatter was measured on", 1, true), version .. " on another build: no notice")
end

-- Activation that comes later still announces it, once: a spellbook not
-- ready at login, then SPELLS_CHANGED (and more of them)...
local function notices()
    local n, from = 0, 1
    local chat = WoW.chatText()
    while true do
        local at = chat:find("Shatter was measured on", from, true)
        if not at then return n end
        n, from = n + 1, at + 1
    end
end
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.build = "70400"
WoW.version = DEV
WoW.spellbookReady = false
WoW.loadAddon()
eq(notices(), 0, "spellbook not ready at login: no notice yet")
WoW.spellbookReady = true
WoW.fire("SPELLS_CHANGED")
WoW.fire("SPELLS_CHANGED")
eq(notices(), 1, "late spellbook: announced once on activation")

-- ...and first activation deferred by combat (a reload in combat).
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.build = "70400"
WoW.version = DEV
WoW.combat = true
WoW.loadAddon()
eq(notices(), 0, "activation waiting for combat: no notice yet")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(notices(), 1, "combat-deferred activation: announced once when it completes")

-- Non-enchanters stay quiet (no notice for an addon that does nothing there).
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.build = "70400"
WoW.version = DEV
WoW.loadAddon()
check(not WoW.chatText():find("Shatter was measured on", 1, true), "inactive characters get no build notice")

-- loadStamps: one entry per load, carried by the SavedVariables table, never
-- defaulted. Three "game starts" handing the table back give three stamps.
local saved
for run = 1, 3 do
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    WoW.loadAddon({ savedDB = saved })
    saved = ShatterDB
    eq(#saved.loadStamps, run, "load " .. run .. ": " .. run .. " stamp(s)")
end
eq(saved.loadStamps[3].build, MEASURED, "each stamp records the build")

-- A fresh table (SavedVariables not read back) starts again at one.
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.loadAddon()
eq(#ShatterDB.loadStamps, 1, "nothing loaded back: a single stamp")

-- Capped so the file cannot grow without bound.
local many = { loadStamps = {} }
for i = 1, 40 do many.loadStamps[i] = { time = i, build = "x" } end
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.loadAddon({ savedDB = many })
eq(#ShatterDB.loadStamps, Shatter.Constants.MAX_LOAD_STAMPS, "stamps capped")

-- Price integrations: an erroring third-party API means "no price".
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
rawset(_G, "Auctionator", { API = { v1 = { GetAuctionPriceByItemLink = function() error("Auctionator broke") end } } })
WoW.loadAddon()
local ok, value = pcall(Shatter.AuctionData.GetItemValue, Shatter.AuctionData, 16204)
check(ok and value == nil, "a throwing price API reads as no price")
rawset(_G, "Auctionator", { API = { v1 = { GetAuctionPriceByItemLink = function() return 1234 end } } })
local v, source = Shatter.AuctionData:GetItemValue(16204)
eq(v, 1234, "Auctionator price used")
eq(source, "Auctionator", "source named")
rawset(_G, "Auctionator", nil)

-- Minimap drag: the angle is computed in the minimap's own space. With the
-- minimap at scale 2 (Edit Mode) and the cursor straight to its right in
-- screen pixels, the angle must be 0, not skewed by UIParent's scale.
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.loadAddon()
-- The minimap laid out at (400..600, 300..500) in its own space, so its
-- center is (500, 400) there = (1000, 800) on screen at effective scale 2.
Minimap._left, Minimap._right, Minimap._bottom, Minimap._top = 400, 600, 300, 500
Minimap._escale = 2
WoW.cursorX, WoW.cursorY = 1100, 800
local button = Shatter.MinimapButton.button
button._scripts.OnDragStart(button)
button._scripts.OnUpdate(button)
button._scripts.OnDragStop(button)
local angle = Shatter.Database:GetSettings().minimap.angle
check(math.abs(angle) < 0.01, "cursor right of the minimap: angle 0 at minimap scale 2 (got " .. tostring(angle) .. ")")

done("test_build")
