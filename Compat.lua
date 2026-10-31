-- Compat.lua: the Retail-API adapter for WoW: Forever, loaded first.
--
-- Forever is Vanilla content on the Mainline codebase: the Classic globals
-- Shatter grew up with are gone, and their replacements live in C_* namespaces.
-- Every such call goes through Shatter.API; nothing here is written to _G
-- (an addon-owned global changes capability detection for every other addon).
--
-- Shapes, from the 1.60.1.70334 dump (C:\Projects\WoW\References\Forever\api):
--   C_Item.GetItemInfo         Classic 18-value tuple; returns NOTHING on a cache miss
--   C_Item.GetItemInfoInstant  Classic 7-value tuple; no cache needed
--   C_Container.GetContainerItemInfo   a STRUCT (itemID, hyperlink, stackCount,
--                                      isLocked, isBound, ...), not the old tuple
--   C_Spell.GetSpellName       by ID always resolves, localized
--   C_SpellBook.IsSpellInSpellBook     spellBank optional (Player by default)
--
-- Calls dispatch through the namespace at call time, so a hook another addon
-- installs on C_Item etc. is seen. Only the contracts Shatter consumes are here.

local _, Shatter = ...

local API = {}
Shatter.API = API

-- Items
function API.GetItemInfo(item)
    return C_Item.GetItemInfo(item)
end

function API.GetItemInfoInstant(item)
    return C_Item.GetItemInfoInstant(item)
end

function API.GetItemCount(itemID)
    return C_Item.GetItemCount(itemID, false, false, false, false) or 0
end

-- Spells
function API.GetSpellName(spellID)
    return C_Spell.GetSpellName(spellID)
end

function API.IsSpellKnown(spellID)
    return C_SpellBook.IsSpellInSpellBook(spellID) and true or false
end

-- AddOns
function API.GetAddOnMetadata(addon, field)
    return C_AddOns.GetAddOnMetadata(addon, field)
end

function API.IsAddOnLoaded(addon)
    return C_AddOns.IsAddOnLoaded(addon)
end

function API.GetAddOnInfo(addon)
    return C_AddOns.GetAddOnInfo(addon)
end

function API.LoadAddOn(addon)
    return C_AddOns.LoadAddOn(addon)
end

-- Containers
function API.GetContainerNumSlots(bag)
    return C_Container.GetContainerNumSlots(bag) or 0
end

function API.GetContainerNumFreeSlots(bag)
    return C_Container.GetContainerNumFreeSlots(bag)
end

-- The struct, or nil for an empty slot.
function API.GetContainerItemInfo(bag, slot)
    return C_Container.GetContainerItemInfo(bag, slot)
end

function API.GetContainerItemID(bag, slot)
    return C_Container.GetContainerItemID(bag, slot)
end

-- The item instance's GUID: it follows the item when the player moves or
-- sorts it, unlike the slot or the itemID. ItemLocation is Blizzard_ObjectAPI
-- (loaded on every game type); C_Item.GetItemGUID is in the dump but not yet
-- measured here, so any failure is nil and callers fall back conservatively.
function API.GetBagItemGUID(bag, slot)
    if not (C_Item.GetItemGUID and C_Item.DoesItemExist and ItemLocation) then return nil end
    local ok, guid = pcall(function()
        local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
        if not C_Item.DoesItemExist(location) then return nil end
        return C_Item.GetItemGUID(location)
    end)
    if ok and type(guid) == "string" and guid ~= "" then return guid end
    return nil
end

-- Whether the bag slot's item is in one of the player's equipment sets
-- (C_Container.GetContainerItemEquipmentSetInfo -> inSet, setList; dump
-- 70532). Sets are unmeasured on Forever (#36): with sets unusable
-- (C_EquipmentSet.CanUseEquipmentSets not a plain true), or the call absent,
-- failing or not a plain boolean, it is nil, and the caller doesn't filter.
function API.IsInEquipmentSet(bag, slot)
    local canUse = C_EquipmentSet and C_EquipmentSet.CanUseEquipmentSets
    if not canUse then return nil end
    local okCan, usable = pcall(canUse)
    if not (okCan and usable == true) then return nil end
    local fn = C_Container.GetContainerItemEquipmentSetInfo
    if not fn then return nil end
    local ok, inSet = pcall(fn, bag, slot)
    if ok and type(inSet) == "boolean" then return inSet end
    return nil
end

-- An item instance's own level (#37): C_Item.GetCurrentItemLevel on its
-- location (dump 2222, optional), else C_Item.GetDetailedItemLevelInfo on its
-- link (dump 2226, may return nothing), else C_Item.GetItemInfo's. nil when
-- none can say.
local function PositiveLevel(ok, level)
    if ok and type(level) == "number" and level > 0 then return level end
    return nil
end
local function InstanceItemLevel(location, link)
    local level
    if location and C_Item.GetCurrentItemLevel then
        level = PositiveLevel(pcall(C_Item.GetCurrentItemLevel, location))
    end
    if not level and link and C_Item.GetDetailedItemLevelInfo then
        level = PositiveLevel(pcall(C_Item.GetDetailedItemLevelInfo, link))
    end
    if not level and link then
        local ok, _, _, _, itemLevel = pcall(API.GetItemInfo, link)
        level = PositiveLevel(ok, itemLevel)
    end
    return level
end

local function Location(create, ...)
    if not (ItemLocation and ItemLocation[create]) then return nil end
    local ok, location = pcall(ItemLocation[create], ItemLocation, ...)
    return ok and location or nil
end

-- What's worn in an inventory slot (#37): its level, and whether the slot
-- holds anything. A worn item whose level can't be read yet is nil, true;
-- only an empty slot is nil, false.
function API.GetEquippedItemLevel(slot)
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    local location = Location("CreateFromEquipmentSlot", slot)
    local occupied = link ~= nil
    if not occupied and location and C_Item.DoesItemExist then
        local ok, exists = pcall(C_Item.DoesItemExist, location)
        occupied = ok and exists == true
    end
    if not occupied then return nil, false end
    return InstanceItemLevel(location, link), true
end

-- The level of the item instance in a bag slot (#37), or nil.
function API.GetBagItemLevel(bag, slot, link)
    return InstanceItemLevel(Location("CreateFromBagAndSlot", bag, slot), link)
end

-- The version from the TOC. An unpackaged copy still carries the packager's
-- token; assemble it at runtime, because the packager rewrites the whole token
-- wherever it appears in shipped files.
function API.GetAddOnVersion(addon)
    local ok, version = pcall(API.GetAddOnMetadata, addon, "Version")
    if not ok or type(version) ~= "string" or version == "" or version == "@" .. "project-version" .. "@" then
        return "dev"
    end
    return version
end
