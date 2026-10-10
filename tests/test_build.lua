------------------------------------------------------------
-- test_build.lua - the measured-build constant, the persistence canary,
-- price integrations that never take Shatter down, and the minimap drag
-- in the minimap's own coordinate space.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

-- This literal is the point: it must be edited by hand together with the
-- constant after re-measuring a new client build (porting guide, section 0).
local MEASURED = "1.60.1.70338"

WoW.enchanter()
WoW.loadAddon()
H.eq(Shatter.Constants.MEASURED_ON_BUILD, MEASURED, "MEASURED_ON_BUILD matches the measured build")
H.check(not WoW.chat():find("Shatter was measured on", 1, true), "no notice on the measured build")

-- Another build: one line at login.
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.build = "70400"
WoW.loadAddon()
H.check(WoW.chat():find("This client is 1.60.1.70400; Shatter was measured on " .. MEASURED, 1, true),
    "a different build is announced at login")

-- Activation that comes later still announces it, once: a spellbook not
-- ready at login, then SPELLS_CHANGED (and more of them)...
local function notices()
    local n, from = 0, 1
    local chat = WoW.chat()
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
WoW.spellbookReady = false
WoW.loadAddon()
H.eq(notices(), 0, "spellbook not ready at login: no notice yet")
WoW.spellbookReady = true
WoW.fire("SPELLS_CHANGED")
WoW.fire("SPELLS_CHANGED")
H.eq(notices(), 1, "late spellbook: announced once on activation")

-- ...and first activation deferred by combat (a reload in combat).
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.build = "70400"
WoW.inCombat = true
WoW.loadAddon()
H.eq(notices(), 0, "activation waiting for combat: no notice yet")
WoW.inCombat = false
WoW.fire("PLAYER_REGEN_ENABLED")
H.eq(notices(), 1, "combat-deferred activation: announced once when it completes")

-- Non-enchanters stay quiet (no notice for an addon that does nothing there).
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.build = "70400"
WoW.loadAddon()
H.check(not WoW.chat():find("Shatter was measured on", 1, true), "inactive characters get no build notice")

-- loadStamps: one entry per load, carried by the SavedVariables table, never
-- defaulted. Three "game starts" handing the table back give three stamps.
local saved
for run = 1, 3 do
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    WoW.loadAddon({ savedDB = saved })
    saved = ShatterDB
    H.eq(#saved.loadStamps, run, "load " .. run .. ": " .. run .. " stamp(s)")
end
H.eq(saved.loadStamps[3].build, MEASURED, "each stamp records the build")

-- A fresh table (SavedVariables not read back) starts again at one.
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.loadAddon()
H.eq(#ShatterDB.loadStamps, 1, "nothing loaded back: a single stamp")

-- Capped so the file cannot grow without bound.
local many = { loadStamps = {} }
for i = 1, 40 do many.loadStamps[i] = { time = i, build = "x" } end
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.loadAddon({ savedDB = many })
H.eq(#ShatterDB.loadStamps, Shatter.Constants.MAX_LOAD_STAMPS, "stamps capped")

-- Price integrations: an erroring third-party API means "no price".
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
rawset(_G, "Auctionator", { API = { v1 = { GetAuctionPriceByItemLink = function() error("Auctionator broke") end } } })
WoW.loadAddon()
local ok, value = pcall(Shatter.AuctionData.GetItemValue, Shatter.AuctionData, 16204)
H.check(ok and value == nil, "a throwing price API reads as no price")
rawset(_G, "Auctionator", { API = { v1 = { GetAuctionPriceByItemLink = function() return 1234 end } } })
local v, source = Shatter.AuctionData:GetItemValue(16204)
H.eq(v, 1234, "Auctionator price used")
H.eq(source, "Auctionator", "source named")
rawset(_G, "Auctionator", nil)

-- Minimap drag: the angle is computed in the minimap's own space. With the
-- minimap at scale 2 (Edit Mode) and the cursor straight to its right in
-- screen pixels, the angle must be 0, not skewed by UIParent's scale.
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.loadAddon()
Minimap.scale = 2
-- Minimap:GetCenter() is (500, 400) in its own space = (1000, 800) on screen.
WoW.cursor = { 1100, 800 }
local button = Shatter.MinimapButton.button
button.scripts.OnDragStart(button)
button.scripts.OnUpdate(button)
button.scripts.OnDragStop(button)
local angle = Shatter.Database:GetSettings().minimap.angle
H.check(math.abs(angle) < 0.01, "cursor right of the minimap: angle 0 at minimap scale 2 (got " .. tostring(angle) .. ")")

H.done("test_build")
