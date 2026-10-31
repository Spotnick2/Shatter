------------------------------------------------------------
-- test_keep_item_level.lua - #37: keep possible upgrades. With the setting
-- on, Solo leaves out items at or above an item level, with the reason; off,
-- or on without a level, nothing is filtered (and Settings says so). Suggest
-- fills the level from the lowest item level worn, without the shirt, the
-- tabard or empty slots. Mail mode is unaffected, at the scan and the click.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local LOW, MID, HIGH = 2589, 3011, 4002

local function setup()
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    WoW.AddItem(LOW, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
    WoW.AddItem(MID, { name = "Green Boots", quality = 2, itemLevel = 30, classID = 4, subclassID = 2, equipLoc = "INVTYPE_FEET" })
    WoW.AddItem(HIGH, { name = "Blue Blade", quality = 3, itemLevel = 40, classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON" })
    WoW.SetBagItem(0, 1, { itemID = LOW })
    WoW.SetBagItem(0, 2, { itemID = MID })
    WoW.SetBagItem(0, 3, { itemID = HIGH })
    WoW.loadAddon()
    WoW.flushTimers()
    Shatter.MainFrame:Show()
end

local function queued(itemID)
    for _, item in ipairs(Shatter.Queue:GetItems() or {}) do
        if item.itemID == itemID then return true end
    end
    return false
end

local function keep(on, level)
    local settings = Shatter.Database:GetSettings()
    settings.keepItemLevel = on
    settings.keepItemLevelAtOrAbove = level
end

local function rescan()
    Shatter.SoloMode:ScheduleScan("TEST", 0)
    WoW.flushTimers()
end

local function settingsUI()
    Shatter.SettingsUI:Toggle()
    return Shatter.SettingsUI
end

-- 1. Off by default: every level is queued.
setup()
H.eq(Shatter.Database:GetSettings().keepItemLevel, false, "off by default")
H.eq(Shatter.Database:GetSettings().keepItemLevelAtOrAbove, nil, "...with no level")
H.check(queued(LOW) and queued(MID) and queued(HIGH), "off: every item is queued")

-- 2. On at 30: below is queued; at and above are kept, with the reason.
keep(true, 30)
rescan()
H.eq(queued(LOW), true, "item level 20, below 30: queued")
H.eq(queued(MID), false, "item level 30, at 30: kept")
H.eq(queued(HIGH), false, "item level 40, above 30: kept")
local item = Shatter.ItemScanner:BuildItem(0, 3)
local ok, reason = Shatter.ItemScanner:IsCandidateDisenchantable(item)
H.eq(ok, false, "the kept item isn't eligible")
H.eq(reason, "item level 30 or more (kept)", "...and says why")

-- 3. On without a level: nothing is filtered, and Settings says so.
keep(true, nil)
rescan()
H.check(queued(MID) and queued(HIGH), "on without a level: nothing is kept")
local ui = settingsUI()
H.check(ui.keepLevel:GetChecked(), "the checkbox shows on")
H.eq(ui.keepLevelBox:GetText(), "", "...the box is empty")
H.check(tostring(ui.keepLevelHelp:GetText()):find("No item level set: nothing is kept", 1, true), "...and the help line warns")

-- 4. Typing a level and leaving the box saves it and rescans.
ui.keepLevelBox:SetFocus()
ui.keepLevelBox:SetText("35")
ui.keepLevelBox.scripts.OnEnterPressed(ui.keepLevelBox)
H.eq(Shatter.Database:GetSettings().keepItemLevelAtOrAbove, 35, "the typed level is saved")
WoW.flushTimers()
H.eq(queued(MID), true, "level 35: the item-level-30 boots come back")
H.eq(queued(HIGH), false, "...the item-level-40 blade stays kept")
H.check(tostring(ui.keepLevelHelp:GetText()):find("item level 35 or more", 1, true), "...and the help line says what is kept")

-- 5. Escape reverts what was typed; an invalid level clears it.
ui.keepLevelBox:SetFocus()
ui.keepLevelBox:SetText("12")
ui.keepLevelBox.scripts.OnEscapePressed(ui.keepLevelBox)
H.eq(Shatter.Database:GetSettings().keepItemLevelAtOrAbove, 35, "Escape: the saved level is unchanged")
H.eq(ui.keepLevelBox:GetText(), "35", "...and the box shows it again")
for _, bad in ipairs({ "", "0", "1000", "abc" }) do
    H.eq(Shatter.Database.NormalizeItemLevel(bad), nil, "not an item level: " .. ("%q"):format(bad))
end
H.eq(Shatter.Database.NormalizeItemLevel("30.7"), 30, "a fraction is a whole item level")

-- 6. The checkbox turns it off: everything is queued again.
ui.keepLevel:SetChecked(false)
ui.keepLevel.scripts.OnClick(ui.keepLevel)
WoW.flushTimers()
H.eq(Shatter.Database:GetSettings().keepItemLevel, false, "unticked: off")
H.check(queued(MID) and queued(HIGH), "...and every item is queued again")
H.eq(Shatter.Database:GetSettings().keepItemLevelAtOrAbove, 35, "...the level is remembered")

-- 7. Suggest: the lowest level worn, skipping empty slots, shirt and tabard.
WoW.equipped[1] = { itemID = HIGH, level = 33 }
WoW.equipped[5] = { itemID = HIGH, level = 27 }
WoW.equipped[4] = { itemID = LOW, level = 1 }    -- shirt
WoW.equipped[19] = { itemID = LOW, level = 1 }   -- tabard
WoW.equipped[16] = { itemID = HIGH }             -- no current level: the item's own, 40
H.eq(Shatter.ItemScanner:LowestEquippedItemLevel(), 27, "lowest worn: 27 (shirt and tabard ignored)")
ui.keepLevelSuggest.scripts.OnClick(ui.keepLevelSuggest)
H.eq(Shatter.Database:GetSettings().keepItemLevelAtOrAbove, 27, "Suggest fills in 27")
H.eq(ui.keepLevelBox:GetText(), "27", "...and the box shows it")

-- The link path, when the current-level call is missing.
local current = C_Item.GetCurrentItemLevel
C_Item.GetCurrentItemLevel = nil
H.eq(Shatter.API.GetEquippedItemLevel(1), 40, "without GetCurrentItemLevel: the worn item's link")
H.eq(Shatter.API.GetEquippedItemLevel(2), nil, "...an empty slot is nil")
C_Item.GetCurrentItemLevel = current

-- Nothing worn: Suggest says so and leaves the level alone.
WoW.equipped = {}
H.eq(Shatter.ItemScanner:LowestEquippedItemLevel(), nil, "nothing worn: no suggestion")
ui.keepLevelSuggest.scripts.OnClick(ui.keepLevelSuggest)
H.eq(Shatter.Database:GetSettings().keepItemLevelAtOrAbove, 27, "...the level is unchanged")
H.check(tostring(ui.keepLevelHelp:GetText()):find("Nothing equipped to suggest from", 1, true), "...and the help line says why")

-- 8. Saved after the scan, before the click: the click is refused.
setup()
local selected = Shatter.Queue:GetSelected()
H.check(selected and selected.itemLevel, "an item is selected")
keep(true, selected.itemLevel)
WoW.click(Shatter.MainFrame.primary, "LeftButton")
H.eq(#WoW.actionsOf("cast"), 0, "kept since the scan: no cast")
local shown = tostring(Shatter.MainFrame.status:GetText())
H.check(shown:find(("item level %d or more (kept)"):format(selected.itemLevel), 1, true), "...and the status says why (" .. shown .. ")")

-- 9. Mail mode is unaffected: its items belong to their senders.
local mailItem = Shatter.ItemScanner:BuildItem(0, 3)
mailItem.mode = Shatter.Constants.MODES.MAIL
H.eq(Shatter.ItemScanner:IsCandidateDisenchantable(mailItem), true, "a Mail item at item level 40 is eligible")
local valid = Shatter.Disenchant:ValidateItem({
    mode = Shatter.Constants.MODES.MAIL, bag = 0, slot = 3, itemID = HIGH,
    itemGUID = Shatter.API.GetBagItemGUID(0, 3),
})
H.eq(valid, true, "...and the click check, rebuilding it from the bag, still lets it through")

H.done("test_keep_item_level")
