------------------------------------------------------------
-- test_equipment_sets.lua - #36: gear saved in an equipment set never
-- reaches the queue. Judged per bag slot (C_Container.
-- GetContainerItemEquipmentSetInfo), so a second copy outside the set is
-- still queued; the queue follows set changes; a click on an item put in a
-- set after the scan is refused; without the call, or with sets disabled,
-- nothing is filtered.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local VEST, BLADE = 2589, 4002

local function setup(opts)
    opts = opts or {}
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    WoW.AddItem(VEST, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
    WoW.AddItem(BLADE, { name = "Blue Blade", quality = 3, itemLevel = 40, classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON" })
    WoW.SetBagItem(0, 1, { itemID = VEST, inSet = true, setList = "Fire Resistance" })
    WoW.SetBagItem(0, 2, { itemID = VEST })
    WoW.SetBagItem(0, 3, { itemID = BLADE })
    if opts.noSetCall then C_Container.GetContainerItemEquipmentSetInfo = nil end
    if opts.canUseSets ~= nil then WoW.canUseSets = opts.canUseSets end
    WoW.loadAddon()
    WoW.flushTimers()
    Shatter.MainFrame:Show()
end

local function queued(bag, slot)
    for _, item in ipairs(Shatter.Queue:GetItems() or {}) do
        if item.bag == bag and item.slot == slot then return true end
    end
    return false
end

-- 1. Per slot: the set's vest stays out, the other copy and the blade go in.
setup()
H.eq(queued(0, 1), false, "the vest in a set isn't queued")
H.eq(queued(0, 2), true, "...a second vest, not in the set, is")
H.eq(queued(0, 3), true, "...and so is the blade")
local ok, reason = Shatter.ItemScanner:IsCandidateDisenchantable(Shatter.ItemScanner:BuildItem(0, 1))
H.check(not ok and reason == "in an equipment set", "...with the reason (" .. tostring(reason) .. ")")

-- 2. The queue follows the sets.
WoW.bags[0][3].inSet = true
WoW.fire("EQUIPMENT_SETS_CHANGED")
WoW.flushTimers()
H.eq(queued(0, 3), false, "the blade saved in a set: out after EQUIPMENT_SETS_CHANGED")
WoW.bags[0][1].inSet = false
WoW.fire("EQUIPMENT_SETS_CHANGED")
WoW.flushTimers()
H.eq(queued(0, 1), true, "the vest removed from its set: back")

-- 3. Put in a set after the scan, before the click: the click is refused.
setup()
local selected = Shatter.Queue:GetSelected()
H.check(selected and not (selected.bag == 0 and selected.slot == 1), "an item outside the set is selected")
WoW.bags[selected.bag][selected.slot].inSet = true
WoW.click(Shatter.MainFrame.primary, "LeftButton")
H.eq(#WoW.actionsOf("cast"), 0, "saved in a set since the scan: no cast")
local shown = Shatter.MainFrame.status:GetText()
H.check(tostring(shown):find("in an equipment set", 1, true), "...and the status says why (" .. tostring(shown) .. ")")

-- 4. Without the call (sets unmeasured on Forever), nothing is filtered.
setup({ noSetCall = true })
H.eq(queued(0, 1), true, "no set call: the vest is queued (fail open)")
H.eq(Shatter.API.IsInEquipmentSet(0, 1), nil, "...the adapter says it can't tell")

-- 5. A call that throws or answers oddly can't tell either.
C_Container.GetContainerItemEquipmentSetInfo = function() error("boom") end
H.eq(Shatter.API.IsInEquipmentSet(0, 1), nil, "a throwing call: can't tell")
C_Container.GetContainerItemEquipmentSetInfo = function() return 1, "x" end
H.eq(Shatter.API.IsInEquipmentSet(0, 1), nil, "a non-boolean answer: can't tell")

-- 6. Sets disabled (CanUseEquipmentSets false): nothing is filtered, even
-- with the slot call answering true; the same without the capability call,
-- or with one that throws or answers oddly.
setup({ canUseSets = false })
H.eq(queued(0, 1), true, "sets disabled: the vest is queued")
H.eq(Shatter.API.IsInEquipmentSet(0, 1), nil, "...the adapter says it can't tell")
local okCan = C_EquipmentSet.CanUseEquipmentSets
C_EquipmentSet.CanUseEquipmentSets = nil
H.eq(Shatter.API.IsInEquipmentSet(0, 1), nil, "no capability call: can't tell")
C_EquipmentSet.CanUseEquipmentSets = function() error("boom") end
H.eq(Shatter.API.IsInEquipmentSet(0, 1), nil, "a throwing capability call: can't tell")
C_EquipmentSet.CanUseEquipmentSets = function() return 1 end
H.eq(Shatter.API.IsInEquipmentSet(0, 1), nil, "a non-boolean capability: can't tell")
C_EquipmentSet.CanUseEquipmentSets = okCan
WoW.canUseSets = true
H.eq(Shatter.API.IsInEquipmentSet(0, 1), true, "...and with sets usable, the slot is in a set")

H.done("test_equipment_sets")
