-- Compat.lua: the Retail-API adapter for WoW: Forever, loaded first.
--
-- Forever is Vanilla content on the Mainline codebase: the Classic globals
-- Shatter grew up with are gone, and their replacements live in C_* namespaces.
-- Every such call goes through Shatter.API; nothing here is written to _G
-- (an addon-owned global changes capability detection for every other addon).
--
-- Shapes, from the 1.60.1.70334 dump (C:\Projects\References):
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
