------------------------------------------------------------
-- test_tooltip.lua - what an item disenchants into, on its tooltip (#3):
--   * one TooltipDataProcessor Item post call, registered at activation;
--   * the materials by falling chance, with amounts; the value only with a
--     price source;
--   * nothing for items Disenchant doesn't take, ignored items, forbidden
--     tooltips, an uncached item, or an inactive character;
--   * the setting: always, with Shift/Alt/Ctrl, never.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local VEST, CLOTH, POTION, DUST, ESSENCE, SHARD = 2589, 2592, 118, 10940, 10939, 10978

local function setup(opts)
    opts = opts or {}
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    if opts.enchanter ~= false then WoW.enchanter() end
    WoW.AddItem(VEST, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
    WoW.AddItem(CLOTH, { name = "Plain Shirt", quality = 1, itemLevel = 20, classID = 4, subclassID = 1, equipLoc = "INVTYPE_BODY" })
    WoW.AddItem(POTION, { name = "Minor Healing Potion", quality = 1, itemLevel = 5, classID = 0, subclassID = 1, equipLoc = "" })
    WoW.AddItem(DUST, { name = "Strange Dust", quality = 1, itemLevel = 1, classID = 7, subclassID = 12, equipLoc = "", icon = 132858 })
    WoW.AddItem(ESSENCE, { name = "Greater Magic Essence", quality = 2, itemLevel = 1, classID = 7, subclassID = 12, equipLoc = "" })
    WoW.AddItem(SHARD, { name = "Small Glimmering Shard", quality = 3, itemLevel = 1, classID = 7, subclassID = 12, equipLoc = "" })
    WoW.loadAddon({ savedDB = opts.savedDB })
    WoW.flushTimers()
end

local function has(lines, text)
    for _, line in ipairs(lines) do
        if tostring(line):find(text, 1, true) then return true end
    end
    return false
end

-- 1. A green vest: the header, then the materials by falling chance.
setup()
local calls = WoW.tooltipPostCalls[Enum.TooltipDataType.Item]
H.eq(calls and #calls, 1, "one Item post call registered at activation")
local lines = WoW.showItemTooltip(VEST)
H.eq(lines[2], "Disenchants into", "the header follows the item's own lines")
H.check(lines[3]:find("Strange Dust", 1, true) and lines[3]:find("75%  x2-3", 1, true), "Strange Dust first: 75%, 2-3")
H.check(lines[3]:find("|T132858:0|t", 1, true), "...with its icon")
H.check(lines[4]:find("Greater Magic Essence", 1, true) and lines[4]:find("20%  x1-2", 1, true), "then the essence: 20%, 1-2")
H.check(lines[5]:find("Small Glimmering Shard", 1, true) and lines[5]:find("5%  x1", 1, true), "then the shard: 5%, 1")
H.eq(#lines, 5, "no value line without a price source")

-- 2. With a price source, the expected value.
rawset(_G, "Auctionator", { API = { v1 = { GetAuctionPriceByItemLink = function(_, link)
    if link:find("Strange Dust", 1, true) then return 1000 end
end } } })
Shatter.Tooltip:Reset()
lines = WoW.showItemTooltip(VEST)
H.check(lines[6] and lines[6]:find("Expected value", 1, true), "a price source adds the expected value")
local expected = Shatter.DisenchantTables:FormatMoney(0.75 * 2.5 * 1000)
H.check(lines[6]:find(expected, 1, true), "...the chance times the average amount times the price (" .. expected .. ")")
rawset(_G, "Auctionator", nil)
Shatter.Tooltip:Reset()

-- 3. Nothing for items Disenchant doesn't take.
H.eq(#WoW.showItemTooltip(CLOTH), 1, "a white item: nothing")
H.eq(#WoW.showItemTooltip(POTION), 1, "a potion: nothing")
H.eq(#WoW.showItemTooltip(DUST), 1, "a material: nothing")
Shatter.Constants.NON_DISENCHANTABLE[VEST] = true
Shatter.Tooltip:Reset()
H.eq(#WoW.showItemTooltip(VEST), 1, "a denylisted item: nothing")
Shatter.Constants.NON_DISENCHANTABLE[VEST] = nil
Shatter.Tooltip:Reset()

-- 4. Nothing for an ignored item, a forbidden tooltip or an uncached item.
Shatter.Database:SetIgnored(VEST, true)
H.eq(#WoW.showItemTooltip(VEST), 1, "an ignored item: nothing")
Shatter.Database:SetIgnored(VEST, false)
GameTooltip.IsForbidden = function() return true end
H.eq(#WoW.showItemTooltip(VEST), 1, "a forbidden tooltip: nothing")
GameTooltip.IsForbidden = nil
WoW.cacheMiss[VEST] = true
Shatter.Tooltip:Reset()
H.eq(#WoW.showItemTooltip(VEST), 1, "an uncached item: nothing until its data is in")
WoW.cacheMiss[VEST] = nil
H.eq(#WoW.showItemTooltip(VEST), 5, "...then the lines")

-- 5. An uncached material is named by its ID and requested.
WoW.cacheMiss[ESSENCE] = true
lines = WoW.showItemTooltip(VEST)
H.check(lines[4]:find("Item 10939", 1, true), "an uncached material: shown by its ID")
local requested = false
for _, id in ipairs(WoW.itemRequests) do requested = requested or id == ESSENCE end
H.check(requested, "...and requested")
WoW.cacheMiss[ESSENCE] = nil

-- 6. A rebuilt tooltip doesn't add the lines twice.
lines = WoW.showItemTooltip(VEST)
lines = WoW.showItemTooltip(VEST)
H.eq(#lines, 5, "a rebuild starts from fresh lines: one set")

-- 7. The setting: with a modifier, never, always.
SlashCmdList.SHATTER("tooltip modifier")
H.eq(Shatter.Database:GetSettings().tooltip, "modifier", "/shatter tooltip modifier saves it")
H.eq(#WoW.showItemTooltip(VEST), 1, "...no lines without a modifier")
WoW.alt = true
H.eq(#WoW.showItemTooltip(VEST), 5, "...lines while Alt is held")
WoW.alt = false
SlashCmdList.SHATTER("tooltip never")
WoW.shift = true
H.eq(#WoW.showItemTooltip(VEST), 1, "never: nothing, even with Shift held")
WoW.shift = false
WoW.messages = {}
SlashCmdList.SHATTER("tooltip sometimes")
H.eq(Shatter.Database:GetSettings().tooltip, "never", "an unknown mode is refused")
H.check(WoW.chat():find("Use /shatter tooltip always|modifier|never", 1, true), "...with the choices")
SlashCmdList.SHATTER("tooltip always")
H.eq(#WoW.showItemTooltip(VEST), 5, "always: the lines")

-- 8. Settings offers the three modes.
Shatter.MainFrame:Show()
Shatter.SettingsUI:Toggle()
local buttons = Shatter.SettingsUI.tooltipButtons
H.check(buttons.always and buttons.modifier and buttons.never, "Settings offers Always, With Shift/Alt/Ctrl and Never")
buttons.never.scripts.OnClick(buttons.never)
H.eq(Shatter.Database:GetSettings().tooltip, "never", "clicking Never saves it")
H.eq(Shatter.Skin.Surface(buttons.never).state, "chosen", "...and marks it")
buttons.always.scripts.OnClick(buttons.always)

-- 9. Activating again (SPELLS_CHANGED) doesn't register a second post call.
WoW.fire("SPELLS_CHANGED")
WoW.flushTimers()
H.eq(#WoW.tooltipPostCalls[Enum.TooltipDataType.Item], 1, "still one post call")

-- 10. Unlearned mid-session: the post call stays but adds nothing.
WoW.knownSpells[13262] = nil
WoW.fire("SPELLS_CHANGED")
WoW.flushTimers()
H.eq(Shatter.isActive, false, "Disenchant unlearned: inactive")
H.eq(#WoW.showItemTooltip(VEST), 1, "...and tooltips stay as they are")

-- 11. An inactive character never registers, and keeps ShatterDB nil.
setup({ enchanter = false })
H.eq(WoW.tooltipPostCalls[Enum.TooltipDataType.Item], nil, "a non-enchanter registers nothing")
H.eq(rawget(_G, "ShatterDB"), nil, "...and has no ShatterDB")

-- 12. A saved mode that isn't one falls back to always.
setup({ savedDB = { settings = { tooltip = "sometimes" } } })
H.eq(Shatter.Database:GetSettings().tooltip, "always", "an unknown saved mode: always")

H.done("test_tooltip")
