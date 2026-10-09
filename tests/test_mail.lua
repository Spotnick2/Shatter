------------------------------------------------------------
-- test_mail.lua - Mail Mode safety on Forever (port plan M5):
--   * queue ownership: a Solo scan never replaces a Mail queue
--   * attachment identity: the mail is re-matched before each take, and
--     receipt is proven by a NEWLY occupied bag slot, never by "the first
--     copy of that item in the bags"
--   * all 16 receive slots, sparse
--   * item info that arrives late rescans the inbox
--   * mail actions stay off until validated (/shatter mailtest)
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local VEST, BLADE, BOOTS = 2589, 4002, 5005

local function setup(opts)
    opts = opts or {}
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    WoW.AddItem(VEST, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
    WoW.AddItem(BLADE, { name = "Blue Blade", quality = 3, itemLevel = 40, classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON" })
    WoW.AddItem(BOOTS, { name = "Green Boots", quality = 2, itemLevel = 25, classID = 4, subclassID = 2, equipLoc = "INVTYPE_FEET" })
    WoW.inbox = opts.inbox or {
        { sender = "Alpha Smith", subject = "DE please", items = { [1] = { itemID = VEST } } },
    }
    for _, b in ipairs(opts.bags or {}) do WoW.SetBagItem(b[1], b[2], { itemID = b[3] }) end
    WoW.loadAddon()
    WoW.flushTimers()
    if opts.enableActions ~= false then SlashCmdList.SHATTER("mailtest") end
    MailFrame:Show()
    WoW.fire("MAIL_SHOW")
    WoW.flushTimers()
    Shatter.MailMode:StartNewSessionFromLaunchPanel()
    WoW.flushTimers()
    return Shatter.MailSession:Get()
end

-- The client moves attachment `a` of mail `m` into bag/slot.
-- (Within the 2 s take timeout unless a test says otherwise.)
local function deliver(m, a, bag, slot)
    local att = WoW.inbox[m].items[a]
    WoW.inbox[m].items[a] = nil
    WoW.SetBagItem(bag, slot, { itemID = att.itemID })
    WoW.fire("BAG_UPDATE_DELAYED")
    WoW.fire("MAIL_INBOX_UPDATE")
end

local function takes() return WoW.actionsOf("takeInbox") end
local function inputs(session)
    local list = {}
    for _, it in ipairs(session.inputItems or {}) do list[#list + 1] = it end
    return list
end

-- 1. Mail actions are off until validated: nothing is taken.
local session = setup({ enableActions = false })
H.eq(#inputs(session), 1, "the vest is listed")
local label, enabled = Shatter.MailMode:GetPrimaryState()
H.eq(label, "Take Attachments", "primary offers Take Attachments")
H.eq(enabled, false, "...but disabled until validated")
Shatter.AttachmentQueue:TakeNext()
H.eq(#takes(), 0, "no TakeInboxItem while mail actions are off")

-- 2. A duplicate the player already owns is never taken for the received one.
session = setup({ bags = { { 0, 1, VEST } } })   -- an identical vest already in bag 0 slot 1
Shatter.AttachmentQueue:TakeNext()
H.eq(#takes(), 1, "one take")
WoW.fire("BAG_UPDATE_DELAYED")                  -- before the attachment lands
WoW.runTimers(0.3)
local item = inputs(session)[1]
H.check(item.bag == nil, "the existing vest in 0/1 is not claimed as the received one")
deliver(1, 1, 0, 5)
WoW.flushTimers()
H.check(item.bag == 0 and item.slot == 5, "receipt proven by the newly occupied slot 0/5")

-- 3. A take that never lands (bags full) puts the item back, unattributed.
session = setup()
Shatter.AttachmentQueue:TakeNext()
WoW.flushTimers()                               -- timer + timeout, nothing arrived
item = inputs(session)[1]
H.eq(item.bag, nil, "nothing attributed")
H.eq(item.status, "selected", "the item is back in the list to try again")
H.eq(session.pendingAction, nil, "no pending take left behind")

-- 4. The inbox shifted (an earlier mail was deleted): the take follows the
-- mail to its new index instead of taking whatever is at the old one.
session = setup({ inbox = {
    { sender = "Other Person", subject = "hi", items = { [1] = { itemID = BOOTS } } },
    { sender = "Alpha Smith", subject = "DE please", items = { [1] = { itemID = VEST } } },
} })
table.remove(WoW.inbox, 1)                      -- mail 1 vanished; Alpha is now index 1
local vestInput
for _, it in ipairs(inputs(session)) do if it.itemID == VEST then vestInput = it end end
vestInput.selected = true
for _, it in ipairs(inputs(session)) do if it.itemID ~= VEST then it.selected = false end end
Shatter.AttachmentQueue:TakeNext()
local t = takes()[1]
H.check(t and t.index == 1 and t.attachment == 1, "took from the mail's CURRENT index")

-- 5. The attachment is gone from the inbox: refused, nothing taken.
session = setup()
WoW.inbox[1].items[1] = nil
Shatter.AttachmentQueue:TakeNext()
H.eq(#takes(), 0, "attachment no longer there: no take")
H.eq(inputs(session)[1].status, "missing", "marked missing")

-- 6. All 16 receive slots, sparse: a lone attachment in slot 16 is found.
session = setup({ inbox = {
    { sender = "Alpha Smith", subject = "late slot", items = { [16] = { itemID = BLADE }, [3] = { itemID = VEST } } },
} })
local slots = {}
for _, it in ipairs(inputs(session)) do slots[it.sourceAttachmentIndex] = it.itemID end
H.eq(slots[16], BLADE, "attachment in receive slot 16 listed (12 is only the SEND limit)")
H.eq(slots[3], VEST, "sparse slot 3 listed with its own index")

-- 7. Queue ownership: once Mail owns the queue, Solo scans cannot replace it.
session = setup({ bags = { { 1, 1, BOOTS } } })   -- a personal green in the bags
WoW.bags[1].size = 4
Shatter.AttachmentQueue:TakeNext()
deliver(1, 1, 0, 2)
WoW.flushTimers()
H.eq(Shatter.Queue:GetOwner(), "mail", "the mail queue owns the queue")
local q = Shatter.Queue:GetItems()
H.check(#q == 1 and q[1].itemID == VEST, "the queue holds only the mail vest")
Shatter.SoloMode:ScheduleScan("BAG_UPDATE_DELAYED", 0)
WoW.fire("BAG_UPDATE_DELAYED")
WoW.fire("GET_ITEM_INFO_RECEIVED", BOOTS, true)
WoW.flushTimers()
q = Shatter.Queue:GetItems()
H.check(#q == 1 and q[1].itemID == VEST, "bag and item-info events did not let Solo replace the mail queue")
-- Shatter Next in the Mail view disenchants the mail vest, not the boots.
Shatter.MainFrame:SetActiveView("mail")
WoW.click(Shatter.MainFrame.primary, "LeftButton")
local use = WoW.actionsOf("use")[1]
H.check(use and use.bag == 0 and use.slot == 2, "Mail Shatter Next targets the received vest")

-- 8. Switching to Solo hands the queue back; switching to Mail reclaims it.
session = setup({ bags = { { 1, 1, BOOTS } } })
WoW.bags[1].size = 4
Shatter.AttachmentQueue:TakeNext()
deliver(1, 1, 0, 2)
WoW.flushTimers()
Shatter.MainFrame:SetActiveView("solo")
WoW.flushTimers()
H.eq(Shatter.Queue:GetOwner(), "solo", "Solo view owns the queue again")
local hasBoots = false
for _, it in ipairs(Shatter.Queue:GetItems()) do if it.itemID == BOOTS then hasBoots = true end end
H.check(hasBoots, "the Solo queue is rebuilt from the bags")
Shatter.MainFrame:SetActiveView("mail")
H.eq(Shatter.Queue:GetOwner(), "mail", "Mail view reclaims its queue")
-- A Solo item can never be disenchanted from the Mail view.
Shatter.Queue.items = { { mode = Shatter.Constants.MODES.SOLO, bag = 1, slot = 1, itemID = BOOTS, queueId = "x" } }
WoW.actions = {}
WoW.click(Shatter.MainFrame.primary, "LeftButton")
H.eq(#WoW.actionsOf("use"), 0, "a Solo item is refused in the Mail view")

-- 9. Item info missing at scan time: listed as pending, rescanned on arrival.
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.AddItem(VEST, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
WoW.cacheMiss[VEST] = true
WoW.inbox = { { sender = "Alpha Smith", subject = "DE please", items = { [1] = { itemID = VEST } } } }
WoW.loadAddon()
MailFrame:Show()
WoW.fire("MAIL_SHOW")
Shatter.MailMode:StartNewSessionFromLaunchPanel()
WoW.flushTimers()
session = Shatter.MailSession:Get()
H.eq(#inputs(session), 0, "cache miss: not judged yet")
WoW.cacheMiss[VEST] = nil
WoW.fire("GET_ITEM_INFO_RECEIVED", VEST, true)
WoW.flushTimers()
session = Shatter.MailSession:Get()
H.eq(#inputs(session), 1, "rescanned when the item info arrived")

-- 10. The launch panel attaches even if MAIL_SHOW beats the mail frame.
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.loadAddon()
local realMailFrame = MailFrame
rawset(_G, "MailFrame", nil)
WoW.allowGlobal("MailFrame")
WoW.fire("MAIL_SHOW")
rawset(_G, "MailFrame", realMailFrame)
realMailFrame:Show()
WoW.flushTimers()
H.check(Shatter.MailLaunchPanel.frame.parent == realMailFrame, "launch panel attached on a retry")

H.done("test_mail")
