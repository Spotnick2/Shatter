------------------------------------------------------------
-- test_value_rules.lua - #38: two value rules, both off by default and Solo
-- only.
--   * "Only if worth more than vendoring": an item whose expected materials
--     are worth no more than its vendor price is left out. Without prices,
--     nothing is left out; a partial value (some materials unpriced) only
--     ever lets an item in.
--   * "Keep valuable items": an item worth at least the amount on the
--     auction house is kept. An unpriced item isn't.
-- Both give their reason, are judged again at the click, and sit with the
-- existing minimum expected value.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

-- Three item level 20 green vests: 75% Strange Dust 2-3, 20% Greater Magic
-- Essence 1-2, 5% Small Glimmering Shard 1. With dust at 2s, the greater at
-- 10s and the shard at 5s: 1.875 x 200 + 0.3 x 1000 + 0.05 x 500 = 700.
local CHEAP, EVEN, DEAR = 2589, 2590, 2591
local DUST, GREATER, SHARD = 10940, 10939, 10978
local FULL = { [DUST] = 200, [GREATER] = 1000, [SHARD] = 500 }

local prices = {}
local priceLinks = {}

local function setup(sell)
    sell = sell or {}
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    local function vest(id, name, price)
        WoW.AddItem(id, { name = name, quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST", sellPrice = price })
    end
    vest(CHEAP, "Cheap Vest", sell.cheap or 100)
    vest(EVEN, "Even Vest", sell.even or 700)
    vest(DEAR, "Dear Vest", sell.dear or 1500)
    WoW.AddItem(DUST, { name = "Strange Dust", quality = 1, itemLevel = 1, classID = 7, subclassID = 12, equipLoc = "" })
    WoW.AddItem(GREATER, { name = "Greater Magic Essence", quality = 2, itemLevel = 1, classID = 7, subclassID = 12, equipLoc = "" })
    WoW.AddItem(SHARD, { name = "Small Glimmering Shard", quality = 3, itemLevel = 1, classID = 7, subclassID = 12, equipLoc = "" })
    WoW.SetBagItem(0, 1, { itemID = CHEAP })
    WoW.SetBagItem(0, 2, { itemID = EVEN })
    WoW.SetBagItem(0, 3, { itemID = DEAR })
    prices, priceLinks = {}, {}
    rawset(_G, "Auctionator", { API = { v1 = { GetAuctionPriceByItemLink = function(_, link)
        priceLinks[#priceLinks + 1] = link
        return prices[tonumber(link:match("item:(%d+)"))]
    end } } })
    WoW.loadAddon()
    WoW.flushTimers()
    Shatter.MainFrame:Show()
end

local function rescan()
    Shatter.SoloMode:ScheduleScan("TEST", 0)
    WoW.flushTimers()
end

local function price(list)
    prices = {}
    for id, v in pairs(list) do prices[id] = v end
    rescan()
end

local function queued(itemID)
    for _, item in ipairs(Shatter.Queue:GetItems() or {}) do
        if item.itemID == itemID then return true end
    end
    return false
end

local function why(itemID)
    for slot = 1, 3 do
        local item = Shatter.ItemScanner:BuildItem(0, slot)
        if item and item.itemID == itemID then
            return select(2, Shatter.ItemScanner:IsCandidateDisenchantable(item))
        end
    end
end

local function settings() return Shatter.Database:GetSettings() end

-- 1. Off by default; with prices, everything is still queued.
setup()
H.eq(settings().onlyAboveVendorPrice, false, "vendor rule off by default")
H.eq(settings().keepAuctionValue, false, "keep valuable off by default")
H.eq(settings().keepAuctionValueAtOrAboveCopper, nil, "...with no amount")
price(FULL)
H.check(queued(CHEAP) and queued(EVEN) and queued(DEAR), "off: every vest is queued")
H.eq(Shatter.ItemScanner:BuildItem(0, 3).sellPrice, 1500, "the scanned item carries its vendor price")

-- 2. Vendor rule on, full prices: above is queued; equal and below are left out.
settings().onlyAboveVendorPrice = true
rescan()
H.check(queued(CHEAP), "materials 7s, vendor 1s: queued")
H.check(not queued(EVEN), "materials 7s, vendor 7s: left out (not more than vendoring)")
H.check(not queued(DEAR), "materials 7s, vendor 15s: left out")
H.eq(why(DEAR), "worth more to vendor (15s 00c)", "...with the reason")
H.eq(why(EVEN), "worth more to vendor (7s 00c)", "...the equal one too")

-- 3. No prices: the rule can't judge, nothing is left out.
price({})
H.check(queued(CHEAP) and queued(EVEN) and queued(DEAR), "no prices: every vest is queued")

-- 4. Partial prices (no essence price): 1.875 x 200 + 0.05 x 500 = 400, a
-- lower bound. It lets the cheap vest in and never leaves the others out.
price({ [DUST] = 200, [SHARD] = 500 })
local estimate = Shatter.DisenchantTables:GetExpected(Shatter.ItemScanner:BuildItem(0, 3))
H.eq(estimate.expectedValueCopper, 400, "partial: the priced materials only")
H.eq(estimate.valuePartial, true, "...marked partial")
H.check(queued(CHEAP), "partial 4s above vendor 1s: queued")
H.check(queued(DEAR), "partial 4s below vendor 15s: can't judge, queued")
H.check(queued(EVEN), "partial 4s below vendor 7s: queued")
price(FULL)
H.eq(Shatter.DisenchantTables:GetExpected(Shatter.ItemScanner:BuildItem(0, 3)).valuePartial, nil, "full prices: not partial")
-- An essence priced through its other size (#39) counts as priced.
price({ [DUST] = 200, [10938] = 1000 / 3, [SHARD] = 500 })
H.eq(Shatter.DisenchantTables:GetExpected(Shatter.ItemScanner:BuildItem(0, 3)).valuePartial, nil, "the greater priced from the lesser: not partial")
H.check(not queued(DEAR), "...so the dear vest is judged and left out")

-- 5. An item a vendor won't buy: disenchanting always wins.
setup({ dear = 0 })
settings().onlyAboveVendorPrice = true
price(FULL)
H.check(queued(DEAR), "no vendor price: queued")

-- 6. Keep valuable: at, above and below the amount; unpriced.
setup()
settings().keepAuctionValue = true
settings().keepAuctionValueAtOrAboveCopper = 10000
price({ [CHEAP] = 9999, [EVEN] = 10000, [DEAR] = 25000 })
H.check(queued(CHEAP), "worth 99s 99c, keeping at 1g: queued")
H.check(not queued(EVEN), "worth 1g: kept")
H.check(not queued(DEAR), "worth 2g 50s: kept")
H.eq(why(DEAR), "worth 2g 50s 00c on the auction house (kept)", "...with the reason")
price({ [CHEAP] = 9999 })
H.check(queued(EVEN) and queued(DEAR), "unpriced items aren't kept")
-- The item's own link is what's priced.
priceLinks = {}
local own = Shatter.ItemScanner:BuildItem(0, 1)
own.itemLink = "|cff1eff00|Hitem:" .. CHEAP .. "::::::::60:::1:1234::::|h[Cheap Vest of the Eagle]|h|r"
Shatter.ItemScanner:CheckValueRules(own)
H.eq(priceLinks[1], own.itemLink, "the item's own link is priced (a suffix of its own)")

-- 6b. A soulbound item can't be auctioned: priced or not, it isn't kept,
-- though the vendor rule still judges it.
settings().includeSoulbound = true
WoW.bags[0][3].bound = true
price({ [DEAR] = 25000 })
H.check(queued(DEAR), "a soulbound item worth 2g 50s: not kept, queued")
settings().onlyAboveVendorPrice = true
price({ [DUST] = 200, [GREATER] = 1000, [SHARD] = 500, [DEAR] = 25000 })
H.eq(why(DEAR), "worth more to vendor (15s 00c)", "...the vendor rule still leaves it out")
settings().onlyAboveVendorPrice = false
WoW.bags[0][3].bound = nil
settings().includeSoulbound = false

-- 7. Keep valuable on without an amount: nothing kept, and Settings says so.
price({ [CHEAP] = 9999, [EVEN] = 10000, [DEAR] = 25000 })
settings().keepAuctionValueAtOrAboveCopper = nil
rescan()
H.check(queued(EVEN) and queued(DEAR), "no amount: nothing kept")
Shatter.SettingsUI:Toggle()
local ui = Shatter.SettingsUI
ui:Refresh()
H.check(tostring(ui.valueRulesHelp:GetText()):find("No amount set", 1, true), "...and the help line warns")

-- 8. Settings: typing an amount and Enter saves it and rescans; Escape
-- reverts; nonsense clears it; the checkboxes.
ui.keepValueBox:SetFocus()
ui.keepValueBox:SetText("2")
ui.keepValueBox.scripts.OnEnterPressed(ui.keepValueBox)
H.eq(settings().keepAuctionValueAtOrAboveCopper, 20000, "2 + Enter: kept at 2g")
WoW.flushTimers()
H.check(queued(EVEN) and not queued(DEAR), "...rescanned: 1g queued, 2g 50s kept")
H.check(tostring(ui.valueRulesHelp:GetText()):find("worth 2g or more", 1, true), "...and the help line says so")
ui.keepValueBox:SetFocus()
ui.keepValueBox:SetText("9")
ui.keepValueBox.scripts.OnEscapePressed(ui.keepValueBox)
H.eq(settings().keepAuctionValueAtOrAboveCopper, 20000, "Escape: the amount is unchanged")
H.eq(ui.keepValueBox:GetText(), "2", "...and the box shows it again")
ui.keepValueBox:SetFocus()
ui.keepValueBox:SetText("0")
ui.keepValueBox.scripts.OnEnterPressed(ui.keepValueBox)
H.eq(settings().keepAuctionValueAtOrAboveCopper, nil, "0: no amount")
H.eq(Shatter.Database.NormalizeAuctionValue(1000000000), nil, "over 99999g: no amount")
H.eq(Shatter.Database.NormalizeAuctionValue(25000), 20000, "whole gold only")
ui.keepValue:SetChecked(false)
ui.keepValue.scripts.OnClick(ui.keepValue)
H.eq(settings().keepAuctionValue, false, "the keep checkbox turns it off")
ui.vendorRule:SetChecked(true)
ui.vendorRule.scripts.OnClick(ui.vendorRule)
H.eq(settings().onlyAboveVendorPrice, true, "the vendor checkbox turns it on")
price(FULL)
H.check(queued(CHEAP) and not queued(DEAR), "...and rescans")

-- 9. No pricing addon: the help line says the rules can't judge.
rawset(_G, "Auctionator", nil)
ui:Refresh()
H.check(tostring(ui.valueRulesHelp:GetText()):find("No pricing addon", 1, true), "no pricing addon: the help line says so")
rescan()
H.check(queued(CHEAP) and queued(EVEN) and queued(DEAR), "...and nothing is left out")

-- 10. With the existing minimum: each leaves out what it leaves out.
setup()
settings().useAuctionData = true
settings().minExpectedValueCopper = 500
settings().onlyAboveVendorPrice = true
price(FULL)
H.check(queued(CHEAP), "materials 7s over a 5s minimum and a 1s vendor price: queued")
H.check(not queued(DEAR), "over the minimum but under the vendor price: left out")
settings().minExpectedValueCopper = 1000
rescan()
H.check(not queued(CHEAP), "under a 10s minimum: left out, whatever the vendor price")
settings().keepAuctionValue = true
settings().keepAuctionValueAtOrAboveCopper = 10000
settings().minExpectedValueCopper = 0
price({ [DUST] = 200, [GREATER] = 1000, [SHARD] = 500, [CHEAP] = 50000 })
H.check(not queued(CHEAP), "worth 5g on the auction house: kept, though worth disenchanting")
H.eq(why(CHEAP), "worth 5g 00s 00c on the auction house (kept)", "...keeping says why first")

-- 11. Since the scan, before the click: refused, with the reason.
setup()
price(FULL)
local selected = Shatter.Queue:GetSelected()
H.check(selected, "an item is selected")
settings().keepAuctionValue = true
settings().keepAuctionValueAtOrAboveCopper = 10000
prices[selected.itemID] = 30000
WoW.click(Shatter.MainFrame.primary, "LeftButton")
H.eq(#WoW.actionsOf("cast"), 0, "valuable since the scan: no cast")
local shown = tostring(Shatter.MainFrame.status:GetText())
H.check(shown:find("on the auction house (kept)", 1, true), "...and the status says why (" .. shown .. ")")
settings().keepAuctionValue = false
settings().onlyAboveVendorPrice = true
WoW.items[selected.itemID].sellPrice = 5000
WoW.click(Shatter.MainFrame.primary, "LeftButton")
H.eq(#WoW.actionsOf("cast"), 0, "worth more to vendor since the scan: no cast")
shown = tostring(Shatter.MainFrame.status:GetText())
H.check(shown:find("worth more to vendor", 1, true), "...and the status says why (" .. shown .. ")")

-- 12. Mail mode is unaffected: its items belong to their senders.
settings().keepAuctionValue = true
prices[DEAR] = 30000
local mailItem = Shatter.ItemScanner:BuildItem(0, 3)
mailItem.mode = Shatter.Constants.MODES.MAIL
H.eq(Shatter.ItemScanner:IsCandidateDisenchantable(mailItem), true, "a valuable Mail item, worth more to vendor, is eligible")
local valid = Shatter.Disenchant:ValidateItem({
    mode = Shatter.Constants.MODES.MAIL, bag = 0, slot = 3, itemID = DEAR,
    itemGUID = Shatter.API.GetBagItemGUID(0, 3),
})
H.eq(valid, true, "...and at the click")

rawset(_G, "Auctionator", nil)
H.done("test_value_rules")
