------------------------------------------------------------
-- test_ignored.lua - ignored items (#4):
--   * Ignore says how to undo it; Skip and Ignore say which is which;
--   * Settings lists them, Remove brings one back into the queue at once,
--     Reset all asks again in place, then clears them all;
--   * /shatter ignored and /shatter unignore <itemID or link>;
--   * an uncached item is requested and shown once it arrives;
--   * settings.ignoredItems keeps its [itemID] = true shape.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local VEST, BOOTS, SWORD = 2589, 2590, 2591
local function setup()
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    WoW.AddItem(VEST, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
    WoW.AddItem(BOOTS, { name = "Azure Boots", quality = 2, itemLevel = 22, classID = 4, subclassID = 2, equipLoc = "INVTYPE_FEET" })
    WoW.AddItem(SWORD, { name = "Bronze Sword", quality = 2, itemLevel = 18, classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON" })
    WoW.SetBagItem(0, 1, { itemID = VEST })
    WoW.SetBagItem(0, 2, { itemID = BOOTS })
    WoW.SetBagItem(0, 3, { itemID = SWORD })
    WoW.loadAddon()
    WoW.flushTimers()
    Shatter.MainFrame:Show()
    WoW.fire("BAG_UPDATE_DELAYED")
    WoW.flushTimers()
    return Shatter.MainFrame
end

local function queued(itemID)
    for _, item in ipairs(Shatter.Queue:GetItems()) do
        if item.itemID == itemID then return true end
    end
    return false
end

local function selectItem(itemID)
    for i, item in ipairs(Shatter.Queue:GetItems()) do
        if item.itemID == itemID then Shatter.Queue.selectedIndex = i return end
    end
    error("not queued: " .. itemID)
end

local function ignore(itemID)
    selectItem(itemID)
    Shatter.Queue:IgnoreSelected()
    WoW.flushTimers()
end

-- 1. Ignore: out of the queue for good, and it says how to undo it.
local main = setup()
H.check(queued(VEST) and queued(BOOTS) and queued(SWORD), "three items queued")
ignore(VEST)
H.check(not queued(VEST), "Ignore takes the item out of the queue")
H.eq(Shatter.Database:IsIgnored(VEST), true, "...and saves it")
H.check(WoW.chat():find("/shatter unignore 2589", 1, true), "...and says how to undo it")
WoW.fire("BAG_UPDATE_DELAYED")
WoW.flushTimers()
H.check(not queued(VEST), "a rescan keeps it out")
H.eq(ShatterDB.settings.ignoredItems[VEST], true, "the saved shape is still [itemID] = true")

-- Skip and Ignore say which is which.
main.skipButton.scripts.OnEnter(main.skipButton)
H.check(GameTooltip.lines[1] == "Skip" and GameTooltip.lines[2]:find("/reload", 1, true), "Skip's tooltip: until a /reload")
main.skipButton.scripts.OnLeave(main.skipButton)
main.ignoreButton.scripts.OnEnter(main.ignoreButton)
H.check(GameTooltip.lines[1] == "Ignore" and GameTooltip.lines[2]:find("Settings", 1, true), "Ignore's tooltip: until removed in Settings")
main.ignoreButton.scripts.OnLeave(main.ignoreButton)

-- 2. Settings lists it; Remove brings it back at once.
Shatter.SettingsUI:Toggle()
local ui = Shatter.SettingsUI
H.eq(ui.ignoredLabel:GetText(), "Ignored items (1)", "Settings: the count")
local row = ui.ignoredRows[1]
H.check(row and row:IsShown() and row.itemID == VEST, "...one row, the vest")
H.check(row.text:GetText():find("Green Vest", 1, true), "...shown by its link")
H.check(not ui.ignoredEmpty:IsShown() and ui.resetIgnored:IsShown(), "...with Reset all, no empty note")
row.remove.scripts.OnClick(row.remove)
WoW.flushTimers()
H.eq(Shatter.Database:IsIgnored(VEST), false, "Remove forgets it")
H.eq(ShatterDB.settings.ignoredItems[VEST], nil, "...in the saved table too")
H.check(queued(VEST), "...and it is back in the queue at once")
H.check(not row:IsShown() and ui.ignoredEmpty:IsShown(), "...the list is empty again")
H.check(not ui.resetIgnored:IsShown(), "...and Reset all is hidden")
H.eq(ui.ignoredLabel:GetText(), "Ignored items", "...no count")

-- 3. Reset all asks again in place, then clears every entry.
ignore(VEST)
ignore(SWORD)
ui:Refresh()
H.eq(ui.ignoredLabel:GetText(), "Ignored items (2)", "two ignored")
H.check(ui.ignoredRows[1].itemID == SWORD and ui.ignoredRows[2].itemID == VEST, "...alphabetical: Bronze Sword, Green Vest")
local reset = ui.resetIgnored
reset.scripts.OnClick(reset)
H.eq(reset.text:GetText(), "Click to confirm", "the first click asks again")
H.eq(#Shatter.Database:GetIgnoredItems(), 2, "...and clears nothing")
WoW.runTimers(6)
H.eq(reset.text:GetText(), "Reset all", "unconfirmed, it disarms after a few seconds")
reset.scripts.OnClick(reset)
reset.scripts.OnClick(reset)
WoW.flushTimers()
H.eq(#Shatter.Database:GetIgnoredItems(), 0, "two clicks clear every ignored item")
H.check(queued(VEST) and queued(SWORD), "...and both are back in the queue")

-- 4. The slash commands.
SlashCmdList.SHATTER("ignored")
H.check(WoW.chat():find("No ignored items.", 1, true), "/shatter ignored with none")
ignore(BOOTS)
ignore(SWORD)
WoW.messages = {}
SlashCmdList.SHATTER("ignored")
H.check(WoW.chat():find("Ignored items (2):", 1, true) and WoW.chat():find("(2590)", 1, true)
    and WoW.chat():find("(2591)", 1, true), "/shatter ignored lists them with their IDs")
SlashCmdList.SHATTER("unignore 2590")
WoW.flushTimers()
H.eq(Shatter.Database:IsIgnored(BOOTS), false, "/shatter unignore <itemID>")
H.check(queued(BOOTS), "...back in the queue")
SlashCmdList.SHATTER("unignore " .. WoW.link(SWORD))
WoW.flushTimers()
H.eq(Shatter.Database:IsIgnored(SWORD), false, "/shatter unignore <link>")
WoW.messages = {}
SlashCmdList.SHATTER("unignore 2590")
H.check(WoW.chat():find("isn't ignored", 1, true), "an item that isn't ignored is said so")
WoW.messages = {}
SlashCmdList.SHATTER("unignore vest")
H.check(WoW.chat():find("Use /shatter unignore", 1, true), "anything else gets the usage")

-- 5. An uncached item is requested, and shown when it arrives.
main = setup()
ignore(VEST)
WoW.cacheMiss[VEST] = true
Shatter.SettingsUI:Toggle()
ui = Shatter.SettingsUI
H.eq(ui.ignoredRows[1].text:GetText(), "Item 2589", "uncached: shown by its ID")
local requested = false
for _, id in ipairs(WoW.itemRequests) do requested = requested or id == VEST end
H.check(requested, "...and its data requested")
WoW.cacheMiss[VEST] = nil
WoW.fire("GET_ITEM_INFO_RECEIVED", VEST, true)
H.check(ui.ignoredRows[1].text:GetText():find("Green Vest", 1, true), "...its link once the data arrives")

-- 6. A long list grows the settings' scroll content.
local base = ui.content:GetHeight()
ignore(BOOTS)
ignore(SWORD)
ui:Refresh()
H.check(ui.content:GetHeight() > base, "more rows, taller content")

-- 7. With a mail session: the Mail queue rescans only while the mailbox is
-- open, and nothing errors either way (the client has no IsMailboxOpen
-- global: MailMode's own check is used).
main = setup()
WoW.inbox = { { sender = "Alpha Smith", subject = "DE please", items = { [1] = { itemID = BOOTS } } } }
MailFrame:Show()
WoW.fire("MAIL_SHOW")
WoW.flushTimers()
Shatter.MailMode:StartNewSessionFromLaunchPanel()
WoW.flushTimers()
H.check(Shatter.MailSession:HasActiveSession(), "a mail session is active")
local mailScans = {}
local scheduleScan = Shatter.MailMode.ScheduleScan
Shatter.MailMode.ScheduleScan = function(self, reason, ...)
    mailScans[#mailScans + 1] = reason
    return scheduleScan(self, reason, ...)
end
ignore(VEST)
Shatter.SettingsUI:Toggle()
ui = Shatter.SettingsUI
H.ok(function() ui.ignoredRows[1].remove.scripts.OnClick(ui.ignoredRows[1].remove) end,
    "mailbox open: Remove doesn't error")
H.eq(mailScans[#mailScans], "ITEM_UNIGNORED", "...and rescans the Mail queue")
H.check(ui.ignoredEmpty:IsShown(), "...and Settings redraws")

MailFrame:Hide()
WoW.fire("MAIL_CLOSED")
WoW.flushTimers()
H.check(Shatter.MailSession:HasActiveSession(), "the session outlives the closed mailbox")
-- The queue may be the session's now, so the item is ignored directly.
Shatter.Database:SetIgnored(VEST, true)
ui:Refresh()
local scansBefore = #mailScans
H.ok(function() SlashCmdList.SHATTER("unignore 2589") end, "mailbox closed: /shatter unignore doesn't error")
H.eq(#mailScans, scansBefore, "...and doesn't rescan the Mail queue (#26)")
H.eq(Shatter.Database:IsIgnored(VEST), false, "...the item is no longer ignored")
H.check(ui.ignoredEmpty:IsShown(), "...Settings redraws")
Shatter.Database:SetIgnored(VEST, true)
ui:Refresh()
H.ok(function()
    ui.resetIgnored.scripts.OnClick(ui.resetIgnored)
    ui.resetIgnored.scripts.OnClick(ui.resetIgnored)
end, "mailbox closed: Reset all doesn't error")
H.eq(#Shatter.Database:GetIgnoredItems(), 0, "...and clears the list")
Shatter.MailMode.ScheduleScan = scheduleScan

H.done("test_ignored")
