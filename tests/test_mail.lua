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

-- 11. Switching to Solo never makes a received mail item the player's own.
session = setup({ bags = { { 1, 1, BOOTS } } })
WoW.bags[1].size = 4
Shatter.AttachmentQueue:TakeNext()
deliver(1, 1, 0, 2)
WoW.flushTimers()
Shatter.MainFrame:SetActiveView("solo")
WoW.flushTimers()
local soloHasVest = false
for _, it in ipairs(Shatter.Queue:GetItems()) do if it.itemID == VEST then soloHasVest = true end end
H.eq(soloHasVest, false, "the received vest is reserved: not in the Solo queue")

-- 12. A real mail disenchant is credited to its sender.
session = setup()
Shatter.AttachmentQueue:TakeNext()
deliver(1, 1, 0, 2)
WoW.flushTimers()
Shatter.MainFrame:SetActiveView("mail")
WoW.click(Shatter.MainFrame.primary, "LeftButton")
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 13262)
WoW.bags[0][2] = nil
WoW.SetBagItem(0, 7, { itemID = 10940, count = 2 })      -- Strange Dust
WoW.fire("BAG_UPDATE_DELAYED")
WoW.flushTimers()
item = inputs(session)[1]
H.eq(item.status, "disenchanted", "the mail input is marked disenchanted")
local credited = false
for _, bucket in pairs(session.outputRecipients or {}) do
    if bucket.sourceSenders and bucket.sourceSenders["Alpha Smith"] and (bucket.materialsGenerated[10940] or 0) > 0 then credited = true end
end
H.check(credited, "the materials are credited to the sender")

-- 13. A personal copy MOVED to a new slot while a take is pending is not
-- the received item (no inbox or bag count change).
session = setup({ bags = { { 0, 1, VEST } } })
Shatter.AttachmentQueue:TakeNext()                  -- the take never lands
WoW.bags[0][1] = nil
WoW.SetBagItem(0, 9, { itemID = VEST })              -- player moves their own vest
WoW.fire("BAG_UPDATE_DELAYED")
WoW.runTimers(3)
item = inputs(session)[1]
H.eq(item.bag, nil, "a moved personal copy is not attributed to the sender")
H.eq(item.status, "selected", "the attachment is still in the mail: back to the list")

-- 14. Two identical mails keep separate rows across rescans.
session = setup({ inbox = {
    { sender = "Alpha Smith", subject = "DE please", items = { [1] = { itemID = VEST } } },
    { sender = "Alpha Smith", subject = "DE please", items = { [1] = { itemID = VEST } } },
} })
local rows = inputs(session)
H.eq(#rows, 2, "two identical mails: two rows")
rows[2].selected = false
Shatter.MailMode:ScanInbox("TEST")
rows = inputs(Shatter.MailSession:Get())
H.eq(#rows, 2, "still two rows after a rescan (nothing duplicated)")
H.check(rows[1].inputItemId ~= rows[2].inputItemId, "distinct identities")
local deselected = 0
for _, r in ipairs(rows) do if r.selected == false then deselected = deselected + 1 end end
H.eq(deselected, 1, "the deselected one stays deselected, the other stays selected")

-- 15. The original mail vanished: an otherwise identical COD mail is not a
-- substitute (the scan excluded it), and two identical candidates are
-- ambiguous - nothing is taken in either case.
session = setup()
WoW.inbox[1] = { sender = "Alpha Smith", subject = "DE please", cod = 5000, items = { [1] = { itemID = VEST } } }
Shatter.AttachmentQueue:TakeNext()
H.eq(#takes(), 0, "COD look-alike: no take")
session = setup({ inbox = {
    { sender = "Other Person", subject = "x", items = { [1] = { itemID = BOOTS } } },
    { sender = "Other Person", subject = "y", items = { [1] = { itemID = BOOTS } } },
    { sender = "Alpha Smith", subject = "DE please", items = { [1] = { itemID = VEST } } },
} })                                                -- the vest's mail is index 3
for _, it in ipairs(inputs(session)) do it.selected = it.itemID == VEST end
WoW.inbox = {
    { sender = "Alpha Smith", subject = "DE please", items = { [1] = { itemID = VEST } } },
    { sender = "Alpha Smith", subject = "DE please", items = { [1] = { itemID = VEST } } },
}
Shatter.AttachmentQueue:TakeNext()
H.eq(#takes(), 0, "two identical candidates: ambiguous, no take")

-- 16. An earlier take's timeout never resolves a later take.
session = setup({ inbox = {
    { sender = "Alpha Smith", subject = "A", items = { [1] = { itemID = VEST } } },
    { sender = "Alpha Smith", subject = "B", items = { [1] = { itemID = BOOTS } } },
} })
Shatter.AttachmentQueue:TakeNext()                  -- take A at t=0
WoW.runTimers(0.1)
deliver(1, 1, 0, 2)                                 -- A lands, resolved by the bag event
H.eq(session.pendingAction, nil, "A resolved")
WoW.runTimers(1.8)                                  -- t=1.9
Shatter.AttachmentQueue:TakeNext()                  -- take B
local pendingB = session.pendingAction
WoW.runTimers(0.2)                                  -- t=2.1: A's timeout fires
H.check(session.pendingAction == pendingB, "A's timeout did not clear take B")
deliver(2, 1, 0, 3)                                 -- B lands
WoW.flushTimers()
local bootsRow
for _, r in ipairs(inputs(session)) do if r.itemID == BOOTS then bootsRow = r end end
H.check(bootsRow and bootsRow.bag == 0 and bootsRow.slot == 3, "B attributed when it lands")

-- 17. A missing attachment does not block the next one.
session = setup({ inbox = {
    { sender = "Alpha Smith", subject = "A", items = { [1] = { itemID = VEST } } },
    { sender = "Alpha Smith", subject = "B", items = { [1] = { itemID = BOOTS } } },
} })
WoW.inbox[1].items[1] = nil                         -- A's attachment vanished
Shatter.AttachmentQueue:TakeNext()                  -- marks A missing
Shatter.AttachmentQueue:TakeNext()                  -- moves on to B
local t2 = takes()[1]
H.check(t2 and t2.index == 2, "the next selected attachment is taken")

-- Helpers for the ownership-across-moves cases.
local function soloSlotsOf(itemID)
    local out = {}
    for _, it in ipairs(Shatter.Queue:GetItems()) do
        if it.itemID == itemID then out[#out + 1] = it.bag .. ":" .. it.slot end
    end
    table.sort(out)
    return table.concat(out, ",")
end
local function receiveVest(opts, bag, slot)
    local s = setup(opts)
    Shatter.AttachmentQueue:TakeNext()
    deliver(1, 1, bag or 0, slot or 2)
    WoW.flushTimers()
    return s
end
local function mailClick()
    Shatter.MainFrame:SetActiveView("mail")
    WoW.actions = {}
    WoW.click(Shatter.MainFrame.primary, "LeftButton")
    return WoW.actionsOf("use")[1]
end

-- 18. A received item the player moves stays the sender's: the Solo view
-- does not pick it up at its new slot, and Mail targets it there.
session = receiveVest()
WoW.MoveBagItem(0, 2, 0, 9)
WoW.fire("BAG_UPDATE_DELAYED")
WoW.flushTimers()
Shatter.MainFrame:SetActiveView("solo")
WoW.flushTimers()
H.eq(soloSlotsOf(VEST), "", "a moved mail vest is still reserved (not in the Solo queue)")
use = mailClick()
H.check(use and use.bag == 0 and use.slot == 9, "Mail Shatter Next follows the vest to 0/9")

-- 19. A personal copy and the mail copy swap slots: Solo gets the personal
-- one (now in the mail copy's old slot), Mail gets the received one.
session = receiveVest({ bags = { { 0, 1, VEST } } }, 0, 5)
WoW.MoveBagItem(0, 5, 0, 1)                         -- swaps the two vests
WoW.fire("BAG_UPDATE_DELAYED")
WoW.flushTimers()
Shatter.MainFrame:SetActiveView("solo")
WoW.flushTimers()
H.eq(soloSlotsOf(VEST), "0:5", "Solo holds only the personal vest, at its new slot")
use = mailClick()
H.check(use and use.bag == 0 and use.slot == 1, "Mail targets the received vest at 0/1, not the personal one")

-- 20. A stale Mail queue never hits a personal copy moved into its slot:
-- refused until the bags settle, then it follows the received vest.
session = receiveVest({ bags = { { 0, 1, VEST } } }, 0, 2)
Shatter.MainFrame:SetActiveView("mail")
WoW.MoveBagItem(0, 2, 0, 9)                         -- mail vest away...
WoW.MoveBagItem(0, 1, 0, 2)                         -- ...personal vest into its slot
WoW.runTimers(3)                                    -- let the sticky "inbox scanned" status lapse
WoW.actions = {}
WoW.click(Shatter.MainFrame.primary, "LeftButton")
H.eq(#WoW.actionsOf("use"), 0, "the personal vest in the old slot is not disenchanted")
H.check(Shatter.MainFrame.status:GetText():find("moved", 1, true), "status says the mail item moved")
WoW.fire("BAG_UPDATE_DELAYED")
WoW.flushTimers()
use = mailClick()
H.check(use and use.bag == 0 and use.slot == 9, "after the bag update, Mail targets the received vest")

-- 21. A received item that leaves the bags is no longer reserved or queued.
session = receiveVest()
WoW.bags[0][2] = nil                                -- sold / deleted
WoW.fire("BAG_UPDATE_DELAYED")
WoW.flushTimers()
item = inputs(session)[1]
H.eq(item.status, "unresolved", "an item gone from the bags is left for the player")
H.eq(item.bag, nil, "and holds no slot")

-- 22. Without an item GUID (API unavailable) nothing proves which copy is
-- the sender's: every copy is held back from Solo, and Mail refuses -
-- whether the personal copy goes, or the received one goes and a personal
-- copy takes its slot (counts match there, identity does not).
local savedGUID = C_Item.GetItemGUID
session = receiveVest({ bags = { { 0, 1, VEST } } }, 0, 5)
C_Item.GetItemGUID = nil
inputs(session)[1].itemGUID = nil                   -- as if receipt had found no GUID
Shatter.MainFrame:SetActiveView("solo")
WoW.flushTimers()
H.eq(soloSlotsOf(VEST), "", "no GUID: no copy of the item reaches the Solo queue")
WoW.runTimers(3)
use = mailClick()
H.eq(use, nil, "no GUID: Mail refuses")
H.check(Shatter.MainFrame.status:GetText():find("no item GUID", 1, true), "status explains why")
WoW.bags[0][1] = nil                                -- the personal copy goes
use = mailClick()
H.eq(use, nil, "no GUID, only one copy left: still refused")
C_Item.GetItemGUID = savedGUID
session = receiveVest({ bags = { { 0, 1, VEST } } }, 0, 5)
C_Item.GetItemGUID = nil
inputs(session)[1].itemGUID = nil
Shatter.MailMode:PrepareDisenchantQueue()           -- the queued item loses its GUID too
WoW.bags[0][5] = nil                                -- the received vest is banked...
WoW.MoveBagItem(0, 1, 0, 5)                         -- ...and the personal one takes its slot
use = mailClick()
H.eq(use, nil, "no GUID: a personal copy in the received slot is refused")
C_Item.GetItemGUID = savedGUID

-- 23. A background inbox rescan never takes the queue from the Solo view,
-- including a scan scheduled before the switch; Mail reclaims it.
session = receiveVest({ bags = { { 1, 1, BOOTS } } })
WoW.bags[1].size = 4
WoW.fire("MAIL_INBOX_UPDATE")                       -- schedules a scan (0.2 s)
Shatter.MainFrame:SetActiveView("solo")
WoW.flushTimers()
H.eq(Shatter.Queue:GetOwner(), "solo", "a scan scheduled before the switch leaves Solo the owner")
WoW.fire("MAIL_INBOX_UPDATE")
WoW.flushTimers()
H.eq(Shatter.Queue:GetOwner(), "solo", "a later inbox rescan leaves Solo the owner")
H.eq(soloSlotsOf(BOOTS), "1:1", "Solo still shows its own items")
Shatter.MainFrame:SetActiveView("mail")
H.eq(Shatter.Queue:GetOwner(), "mail", "selecting Mail reclaims the queue")
local mq = Shatter.Queue:GetItems()
H.check(#mq == 1 and mq[1].itemID == VEST, "with the mail vest")

-- 24. A received item that leaves the bags (banked) and comes back is the
-- sender's again: reserved before Solo can see it, and queued for Mail.
session = receiveVest({ bags = { { 1, 1, BOOTS } } })
local vestInstance = WoW.bags[0][2]
WoW.bags[0][2] = nil                                -- to the bank
WoW.fire("BAG_UPDATE_DELAYED")
WoW.flushTimers()
H.eq(inputs(session)[1].status, "unresolved", "away from the bags: unresolved")
WoW.bags[0][7] = vestInstance                       -- back from the bank, same GUID
WoW.fire("BAG_UPDATE_DELAYED")
Shatter.MainFrame:SetActiveView("solo")
Shatter.SoloMode:ScheduleScan("TEST", 0)
WoW.flushTimers()
H.eq(soloSlotsOf(BOOTS), "1:1", "Solo scanned the bags")
H.eq(soloSlotsOf(VEST), "", "the returning vest is reserved before Solo exposes it")
item = inputs(session)[1]
H.check(item.bag == 0 and item.slot == 7, "found again at 0/7")
H.eq(item.disenchantStatus, "waiting", "and waiting to be disenchanted again")
use = mailClick()
H.check(use and use.bag == 0 and use.slot == 7, "Mail targets it where it came back")

-- 25. A GUID lookup that fails for a moment is not "the item left", and
-- while locations are unproven every copy of a received item is held back
-- from Solo: one moved during the failure, and one returning from the bank.
session = receiveVest({ bags = { { 1, 1, BOOTS } } })
local workingGUID = C_Item.GetItemGUID
C_Item.GetItemGUID = function() error("lookup failed") end
WoW.fire("BAG_UPDATE_DELAYED")
WoW.flushTimers()
item = inputs(session)[1]
H.check(item.bag == 0 and item.slot == 2 and item.status ~= "unresolved", "a failed lookup keeps the item held where it was")
WoW.MoveBagItem(0, 2, 0, 9)                         -- moved while lookups fail
WoW.fire("BAG_UPDATE_DELAYED")
Shatter.MainFrame:SetActiveView("solo")
Shatter.SoloMode:ScheduleScan("TEST", 0)
WoW.flushTimers()
H.eq(soloSlotsOf(BOOTS), "1:1", "Solo scanned the bags")
H.eq(soloSlotsOf(VEST), "", "lookup failing: the moved vest is not offered to Solo")
WoW.runTimers(3)
WoW.actions = {}
WoW.click(Shatter.MainFrame.primary, "LeftButton")
local soloUse = WoW.actionsOf("use")[1]
H.check(not (soloUse and soloUse.bag == 0 and soloUse.slot == 9), "a Solo click cannot destroy the sender's vest")
C_Item.GetItemGUID = workingGUID
-- Away, then back while lookups fail.
session = receiveVest({ bags = { { 1, 1, BOOTS } } })
local awayVest = WoW.bags[0][2]
WoW.bags[0][2] = nil
WoW.fire("BAG_UPDATE_DELAYED")
WoW.flushTimers()
H.eq(inputs(session)[1].status, "unresolved", "the vest is away")
C_Item.GetItemGUID = function() error("lookup failed") end
WoW.bags[0][6] = awayVest
WoW.fire("BAG_UPDATE_DELAYED")
Shatter.MainFrame:SetActiveView("solo")
Shatter.SoloMode:ScheduleScan("TEST", 0)
WoW.flushTimers()
H.eq(soloSlotsOf(BOOTS), "1:1", "Solo scanned the bags")
H.eq(soloSlotsOf(VEST), "", "lookup failing: a returning vest is not offered to Solo")
C_Item.GetItemGUID = workingGUID

-- 26. Two identical mails, take / rescan / take: the received row is never
-- matched to the attachment still in the inbox, and both keep their GUIDs.
session = setup({ inbox = {
    { sender = "Alpha Smith", subject = "DE please", items = { [1] = { itemID = VEST } } },
    { sender = "Alpha Smith", subject = "DE please", items = { [1] = { itemID = VEST } } },
} })
Shatter.AttachmentQueue:TakeNext()
deliver(1, 1, 0, 2)
WoW.flushTimers()                                   -- includes the inbox rescan
Shatter.MailMode:ScanInbox("TEST")
Shatter.AttachmentQueue:TakeNext()
deliver(2, 1, 0, 3)
WoW.flushTimers()
local guids, slotsSeen = {}, {}
for _, r in ipairs(inputs(Shatter.MailSession:Get())) do
    if r.itemGUID then guids[#guids + 1] = r.itemGUID end
    if r.bag then slotsSeen[#slotsSeen + 1] = r.bag .. ":" .. r.slot end
end
table.sort(slotsSeen)
H.eq(#guids, 2, "both received vests keep their GUIDs")
H.check(guids[1] ~= guids[2], "two distinct instances")
H.eq(table.concat(slotsSeen, ","), "0:2,0:3", "each row in its own slot")
use = mailClick()
H.check(use and use.bag == 0 and (use.slot == 2 or use.slot == 3), "Mail disenchants a received vest")


-- 27. Nothing but Start New Session creates a mail session: not a send
-- result, not logging, not the Scan Inbox button with no session.
WoW.reset()
dofile("tests/wow_stubs.lua")
WoW.enchanter()
WoW.inbox = { { sender = "Alpha Smith", subject = "DE please", items = { [1] = { itemID = VEST } } } }
WoW.loadAddon()
MailFrame:Show()
WoW.fire("MAIL_SHOW")
WoW.flushTimers()
H.eq(Shatter.MailSession:Get(), nil, "opening the mailbox creates no session")
WoW.fire("MAIL_SEND_SUCCESS")
Shatter.MailSession:Log("info", "anything")
Shatter.MailSession:SetStatus(Shatter.Constants.MAIL_STATE.SELECTING)
H.eq(Shatter.MailSession:Get(), nil, "a send result, a log line or a status creates no session")
Shatter.MailMode:ScanInbox("BUTTON")
WoW.flushTimers()
H.eq(Shatter.MailSession:Get(), nil, "Scan Inbox without a session creates none")
H.check(Shatter.MainFrame.status:GetText():find("Start a mail session", 1, true), "and says how to start one")


-- 28. Start New Session never replaces an active session (its ledger would
-- be lost): refused, and the panel's button is disabled; closing archives
-- it, and then a new one starts.
session = setup()
local first = Shatter.MailSession:Get()
H.eq(Shatter.MailMode:StartNewSessionFromLaunchPanel(), false, "Start New is refused while a session is active")
H.check(Shatter.MailSession:Get() == first, "the active session is untouched")
Shatter.MailLaunchPanel:Refresh()
H.eq(Shatter.MailLaunchPanel.startButton:IsEnabled(), false, "the panel disables Start New Session")
H.eq(Shatter.MailLaunchPanel.continueButton:IsEnabled(), true, "and offers Continue")
H.check(Shatter.MailSession:Close(true), "the session closes")
local history = ShatterDB.sessions.byCharacter[Shatter.Database:GetCharacterKey()].mailHistory
H.check(history[#history] == first, "closing archives it to the history")
H.eq(Shatter.MailMode:StartNewSessionFromLaunchPanel(), true, "then a new session starts")
H.check(Shatter.MailSession:Get() ~= first, "a different session")

H.done("test_mail")
