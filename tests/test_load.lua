------------------------------------------------------------
-- test_load.lua - the addon loads in TOC order under the strict Forever
-- stubs, creates no stray globals, and a character without Enchanting gets
-- slash feedback and nothing else.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

H.ok(function() WoW.loadAddon() end, "TOC-order load and PLAYER_LOGIN as a non-enchanter")
eq(Shatter.isReady, true, "ready after login")
eq(Shatter.disabledNoEnchanting, true, "no Disenchant spell: disabled")
eq(type(SlashCmdList.SHATTER), "function", "slash handler is a field of SlashCmdList")
eq(SLASH_SHATTER1, "/shatter", "/shatter registered")

SlashCmdList.SHATTER("")
check(WoW.chatText():find("Enchanting is not trained", 1, true), "non-enchanter gets slash feedback")
eq(#WoW.actions, 0, "no gameplay actions")

for name in pairs(WoW.globalWrites) do
    -- LibStub: the embedded LibGlass-1.0's bundled copy, shared by design.
    -- BINDING_NAME_*: Shatter Next's label in Key Bindings (#35).
    check(name == "Shatter" or name == "LibStub" or name:match("^SLASH_SHATTER%d$")
        or name == "BINDING_NAME_CLICK ShatterNextButton:LeftButton", "only declared globals written: " .. name)
end

done("test_load")
