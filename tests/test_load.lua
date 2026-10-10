------------------------------------------------------------
-- test_load.lua - the addon loads in TOC order under the strict Forever
-- stubs, creates no stray globals, and a character without Enchanting gets
-- slash feedback and nothing else.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

H.ok(function() WoW.loadAddon() end, "TOC-order load and PLAYER_LOGIN as a non-enchanter")
H.eq(Shatter.isReady, true, "ready after login")
H.eq(Shatter.disabledNoEnchanting, true, "no Disenchant spell: disabled")
H.eq(type(SlashCmdList.SHATTER), "function", "slash handler is a field of SlashCmdList")
H.eq(SLASH_SHATTER1, "/shatter", "/shatter registered")

SlashCmdList.SHATTER("")
H.check(WoW.chat():find("Enchanting is not trained", 1, true), "non-enchanter gets slash feedback")
H.eq(#WoW.actions, 0, "no gameplay actions")

for name in pairs(WoW.globalWrites) do
    -- LibStub: the embedded LibGlass-1.0's bundled copy, shared by design.
    H.check(name == "Shatter" or name == "LibStub" or name:match("^SLASH_SHATTER%d$"), "only declared globals written: " .. name)
end

H.done("test_load")
