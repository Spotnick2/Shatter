------------------------------------------------------------
-- test_no_disenchant.lua - items the client says can't be disenchanted (#6):
--   * Data/NoDisenchant.lua, generated from the client's ItemSparse flag;
--   * one check (ItemScanner:CanBeDisenchanted) for the queue, Mail intake,
--     Mail's queue and the tooltip; Constants.USE_NO_DISENCHANT_LIST off
--     brings the items back;
--   * a received Mail item that can't be disenchanted: failed, still the
--     sender's and reserved, the session done but not closable without the
--     confirm;
--   * every UI error is traced, with or without an attempt pending.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

-- Real ids: two the client flags, one green it doesn't.
local WAND, INSIGNIA, SWORD, VEST = 11287, 15200, 864, 2589

local function setup(opts)
    opts = opts or {}
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    WoW.AddItem(WAND, { name = "Lesser Magic Wand", quality = 2, itemLevel = 15, classID = 2, subclassID = 19, equipLoc = "INVTYPE_RANGEDRIGHT" })
    WoW.AddItem(INSIGNIA, { name = "Senior Sergeant's Insignia", quality = 3, itemLevel = 35, classID = 4, subclassID = 0, equipLoc = "INVTYPE_NECK" })
    WoW.AddItem(SWORD, { name = "Knightly Longsword", quality = 2, itemLevel = 38, classID = 2, subclassID = 7, equipLoc = "INVTYPE_2HWEAPON" })
    WoW.AddItem(VEST, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
    WoW.inbox = opts.inbox or {}
    for _, b in ipairs(opts.bags or {}) do WoW.SetBagItem(b[1], b[2], { itemID = b[3] }) end
    WoW.loadAddon()
    WoW.flushTimers()
end

local function queued(id)
    for _, item in ipairs(Shatter.Queue:GetItems()) do
        if item.itemID == id then return true end
    end
    return false
end

-- 1. The generated list: what the generator wrote, and only that.
setup()
local list = Shatter.NoDisenchant
H.check(list and list.ids, "Data/NoDisenchant.lua is loaded from the TOC")
H.check(list.build:match("^%d+%.%d+%.%d+%.%d+$") ~= nil, "...and names one source build (" .. tostring(list.build) .. ")")
local n = 0
for _ in pairs(list.ids) do n = n + 1 end
H.eq(n, list.count, "every id once")
H.check(list.ids[WAND] and list.ids[11288] and list.ids[11289], "the enchanter-made wands")
H.check(list.ids[INSIGNIA], "a PvP insignia")
H.check(list.ids[4614], "a quest pendant")
H.check(not list.ids[SWORD] and not list.ids[744] and not list.ids[763], "unflagged greens aren't listed")
H.check(not list.ids[247789], "a flagged white item isn't (Disenchant takes no whites anyway)")

-- 2. Solo: a flagged item isn't queued; an unflagged green is.
setup({ bags = { { 0, 1, WAND }, { 0, 2, INSIGNIA }, { 0, 3, SWORD } } })
Shatter.SoloMode:ScheduleScan("TEST", 0)
WoW.flushTimers()
H.check(queued(SWORD), "an unflagged green is queued")
H.check(not queued(WAND) and not queued(INSIGNIA), "the wand and the insignia aren't")
local wand = Shatter.ItemScanner:BuildItem(0, 1)
local ok, why = Shatter.ItemScanner:IsCandidateDisenchantable(wand)
H.check(not ok and why == "can't be disenchanted", "...the reason: can't be disenchanted")
H.eq(select(2, Shatter.ItemScanner:CanBeDisenchanted(wand)), "can't be disenchanted", "CanBeDisenchanted says the same")
Shatter.Database:SetIgnored(WAND, true)
H.eq(select(2, Shatter.ItemScanner:IsCandidateDisenchantable(wand)), "ignored", "an ignored item says ignored first")
Shatter.Database:SetIgnored(WAND, false)

-- 3. The tooltip uses the same check.
H.eq(#WoW.showItemTooltip(WAND), 1, "the wand's tooltip: nothing added")
H.check(#WoW.showItemTooltip(SWORD) > 1, "the sword's: what it disenchants into")

-- 4. The switch: off, the flagged items are queued again.
Shatter.Constants.USE_NO_DISENCHANT_LIST = false
Shatter.SoloMode:ScheduleScan("TEST", 0)
WoW.flushTimers()
H.check(queued(WAND) and queued(INSIGNIA), "USE_NO_DISENCHANT_LIST = false: queued again")
Shatter.Constants.USE_NO_DISENCHANT_LIST = true

-- 5. Mail intake: a flagged attachment is never taken.
setup({ inbox = { { sender = "Alpha Smith", subject = "DE please", items = { [1] = { itemID = WAND }, [2] = { itemID = SWORD } } } } })
SlashCmdList.SHATTER("mailtest")
MailFrame:Show()
WoW.fire("MAIL_SHOW")
WoW.flushTimers()
Shatter.MailMode:StartNewSessionFromLaunchPanel()
WoW.flushTimers()
local session = Shatter.MailSession:Get()
local byID = {}
for _, input in ipairs(session.inputItems or {}) do byID[input.itemID] = input end
H.check(byID[SWORD], "the sword is a Mail input")
H.eq(byID[WAND], nil, "the wand isn't: never taken")

-- 6. A received item that can't be disenchanted (a session from before the
-- list): failed, still reserved; the other item goes on; the session is done
-- but an ordinary Close is refused.
setup({ inbox = { { sender = "Alpha Smith", subject = "DE please", items = { [1] = { itemID = VEST }, [2] = { itemID = SWORD } } } } })
SlashCmdList.SHATTER("mailtest")
MailFrame:Show()
WoW.fire("MAIL_SHOW")
WoW.flushTimers()
Shatter.MailMode:StartNewSessionFromLaunchPanel()
WoW.flushTimers()
session = Shatter.MailSession:Get()
Shatter.MailSession:SetRecipientMode(Shatter.Constants.MAIL_RECIPIENT_MODE.KEEP)
local function deliver(a, bag, slot)
    local att = WoW.inbox[1].items[a]
    WoW.inbox[1].items[a] = nil
    WoW.SetBagItem(bag, slot, { itemID = att.itemID })
    WoW.fire("BAG_UPDATE_DELAYED")
    WoW.fire("MAIL_INBOX_UPDATE")
end
Shatter.AttachmentQueue:TakeNext()
deliver(1, 0, 2)
WoW.flushTimers()
Shatter.AttachmentQueue:TakeNext()
deliver(2, 0, 3)
WoW.flushTimers()
byID = {}
for _, input in ipairs(session.inputItems or {}) do byID[input.itemID] = input end
H.check(byID[VEST] and byID[SWORD] and byID[SWORD].bag == 0 and byID[SWORD].slot == 3, "both received")
-- The rule arrives after the sword was received.
Shatter.NoDisenchant.ids[SWORD] = true
Shatter.MailMode:PrepareDisenchantQueue()
H.eq(byID[SWORD].disenchantStatus, "failed", "the sword: failed, not queued")
H.eq(byID[SWORD].sourceSender, "Alpha Smith", "...still Alpha's")
H.check(byID[SWORD].itemGUID ~= nil, "...its GUID kept")
local reserved = Shatter.MailSession:GetReservedSlots()
H.eq(reserved["0:3"], SWORD, "...and its slot still reserved")
H.check(not queued(SWORD) and queued(VEST), "the vest is queued and the sword isn't")
Shatter.MainFrame:SetActiveView("mail")
WoW.click(Shatter.MainFrame.primary, "LeftButton")
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 13262)
WoW.bags[0][2] = nil
WoW.SetBagItem(0, 7, { itemID = 10940, count = 2 })
WoW.fire("BAG_UPDATE_DELAYED")
WoW.flushTimers()
H.eq(byID[VEST].status, "disenchanted", "the vest is disenchanted")
H.eq(session.status, Shatter.Constants.MAIL_STATE.COMPLETE, "nothing left to do: done")
local text, warn = Shatter.MailMode:GetStatus()
H.check(text:find("1 item couldn't be disenchanted and is still in your bags", 1, true) and warn,
    "...but the status says what's left in the bags")
H.eq(Shatter.MailSession:HasUnresolvedWork(), true, "the sword counts as unresolved")
H.eq((Shatter.MailSession:Close()), false, "an ordinary Close is refused")
H.check(Shatter.MailSession:Get() ~= nil, "...the session stays")
H.eq((Shatter.MailSession:Close(true)), true, "Confirm Close (forced) archives it")
H.eq(Shatter.MailSession:Get(), nil, "...no active session")
Shatter.NoDisenchant.ids[SWORD] = nil

-- 7. UI errors are traced, pending or not.
setup()
SlashCmdList.SHATTER("debug")
SlashCmdList.SHATTER("trace")
local logged
local log = Shatter.Debug.Log
Shatter.Debug.Log = function(self, level, message, ...)
    if level == "trace" and message:find("UI error", 1, true) then logged = string.format(message, ...) end
    return log(self, level, message, ...)
end
WoW.fire("UI_ERROR_MESSAGE", 50, "Item cannot be disenchanted")
Shatter.Debug.Log = log
H.check(logged and logged:find("50: Item cannot be disenchanted (attempt: none)", 1, true),
    "a UI error with no attempt pending is traced (" .. tostring(logged) .. ")")

H.done("test_no_disenchant")
