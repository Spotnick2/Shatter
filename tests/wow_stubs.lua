------------------------------------------------------------
-- wow_stubs.lua
--
-- The WoW: Forever surface Shatter uses, so the addon loads and runs under
-- stock Lua 5.1 with no client. Drive it through the exported `WoW`:
--
--     dofile("tests/wow_stubs.lua")          -- FIRST, in every test file
--     WoW.knownSpells[13262] = true
--     WoW.SetBagItem(0, 1, { itemID = 2589, ... })
--     local ns = WoW.loadAddon()             -- TOC order, then PLAYER_LOGIN
--
-- The mechanics come from WowTestKit (tests/kit.lua loads the commit
-- tests/kit.pin names; its README is the reference): strict globals, secrets,
-- event names checked against the pinned build, widgets that record every
-- method called (a method the build lacks reads as nil), protected frames in
-- combat, print (with the stray-"|" check done() fails on), timers and the
-- clock (WoW.now, WoW.advance, WoW.flushTimers), WoW.fire, check / eq / done.
--
-- This file adds Shatter's own client APIs, each verified present on build
-- 1.60.1.70334 (the API dump in C:\Projects\WoW\References\Forever\api and the
-- client UI source), and what Shatter's tests rely on beyond the kit, each
-- with its reason. On top of the kit's strictness:
--   * KNOWN_ABSENT models a client with the Blizzard_Deprecated* fallbacks
--     switched off (CVar loadDeprecationFallbacks), which is the state an
--     addon must survive: those names read as nil.
--   * Writing a Blizzard-owned global (SlashCmdList, UISpecialFrames, ...)
--     is an error: the write taints every secure macro on this client
--     (porting guide, section 3). Write fields, never the table. The addon
--     may create only the globals in ALLOWED_WRITES.
--   * SetBackdrop* exist only on frames created with BackdropTemplate (it is
--     a mixin), and SetHyperlink / SetBagItem only on GameTooltipTemplate
--     tooltips (TooltipDataHandler.lua mixin).
--   * A protected frame's refused call RAISES ADDON_ACTION_BLOCKED, so any
--     path that reaches one in combat fails the test.
-- Never add something because a test failed; confirm it exists first.
------------------------------------------------------------

dofile("tests/kit.lua")
local Methods = WoW.Methods

local MEASURED_BUILD = "70334"

------------------------------------------------------------
-- State, reset by WoW.reset() with the kit's
------------------------------------------------------------

local function reset()
    WoW.now           = 1000  -- GetTime(); the tests' times are relative to it
    WoW.epoch         = 1790000000
    WoW.build         = MEASURED_BUILD
    WoW.version       = "v0.2.0-alpha"
    WoW.player        = { name = "Example Surname", realm = "ClassicBetaPvE", class = "MAGE" }
    WoW.cvars         = { ActionButtonUseKeyDown = "1" }
    WoW.knownSpells   = {}  -- [spellID] = true
    WoW.spellNames    = { [13262] = "Disenchant", [7411] = "Enchanting" }
    WoW.spellbookReady = true
    WoW.items         = {}  -- [itemID] = { name, quality, itemLevel, classID, subclassID, equipLoc, sellPrice, icon }
    WoW.cacheMiss     = {}  -- [itemID] = true -> C_Item.GetItemInfo returns nothing
    WoW.itemRequests  = {}  -- itemIDs passed to C_Item.RequestLoadItemDataByID
    WoW.bags          = {}  -- [bag] = { size = n, [slot] = { itemID, count, locked, bound } }
    WoW.inbox         = {}  -- list of { sender, subject, items = { [attachmentIndex] = { itemID, count } } }
    WoW.loot          = {}  -- list of { link, count, name }
    WoW.casting       = nil -- { name, startMs, endMs, spellID }
    WoW.channeling    = nil -- { name, startMs, endMs, spellID }
    WoW.targeting     = false
    WoW.castRefused   = false
    WoW.shift         = false
    WoW.alt           = false
    WoW.ctrl          = false
    WoW.tooltipPostCalls = {}  -- [tooltipType] = { fn, ... } (TooltipDataProcessor)
    WoW.tooltipRefreshes = 0   -- RefreshData calls
    WoW.skillLines    = {}  -- C_SkillInfo rows: { skillID, name, rank, maxRank, isHeader, isCollapsed }
    WoW.gameErrors    = {}  -- [errorType] = errorName (GetGameMessageInfo)
    WoW.playerAuras   = {}  -- [spellID] = AuraData (C_UnitAuras.GetPlayerAuraBySpellID)
    WoW.aurasSecret   = false -- true: an aura read throws, as a secret aura does once tested (combat)
    WoW.cursorX, WoW.cursorY = 0, 0   -- GetCursorPosition (the kit's)
    WoW.addons        = {}  -- [name] = { loaded = bool, loadable = bool }
    WoW.badEvents     = {}  -- RegisterEvent throws (a test's injected fault)
    WoW.refusedEvents = {}  -- RegisterEvent returns false (a test's injected refusal)
    WoW.canUseSets    = true -- C_EquipmentSet.CanUseEquipmentSets (#36)
    WoW.equipped      = {}  -- [inventory slot] = { itemID, level } (#37); level is the current item level
    WoW.linkLevels    = {}  -- [itemID] = the level C_Item.GetDetailedItemLevelInfo reads from a link (#37)
    WoW.equipmentSetIDs = {}
    WoW.actions       = {}  -- gameplay actions the client performed: { kind, ... }
    WoW.macroRuns     = {}  -- macro text the secure handler executed
    WoW.globalWrites  = {}  -- [name] = true for every global the addon assigned
    WoW.scriptErrors  = {}  -- errors raised by click scripts (the client reports and continues)
    for bag = 0, 4 do WoW.bags[bag] = { size = bag == 0 and 16 or 0 } end
end
table.insert(WoW.onReset, reset)
reset()

------------------------------------------------------------
-- Test helpers
------------------------------------------------------------

-- Every printed line, joined: what the player read in chat.
function WoW.chatText() return table.concat(WoW.chat, "\n") end

-- The kit's flushTimers runs the timers due once; Shatter's tests flush the
-- chains too (a timer that schedules the next: test_secure's recorded result
-- schedules the rescan that empties the queue), as many rounds as it takes,
-- at most `rounds` (10), as this stub did before the kit.
local coreFlush = WoW.flushTimers
function WoW.flushTimers(upTo, rounds)
    for _ = 1, rounds or 10 do
        if #WoW.timers == 0 then return end
        coreFlush(upTo)
    end
end

function WoW.link(itemID)
    local item = WoW.items[itemID]
    local name = item and item.name or ("Item " .. itemID)
    return "|cff1eff00|Hitem:" .. itemID .. "::::::::60:::::::|h[" .. name .. "]|h|r"
end

function WoW.AddItem(itemID, info)
    info.name = info.name or ("Item " .. itemID)
    WoW.items[itemID] = info
end

-- Each item placed in the bags is a new instance with its own GUID.
local nextItemGUID = 0
function WoW.SetBagItem(bag, slot, info)
    local b = WoW.bags[bag]
    if slot > b.size then b.size = slot end
    if info and not info.guid then
        nextItemGUID = nextItemGUID + 1
        info.guid = string.format("Item-1-0-%016X", nextItemGUID)
    end
    b[slot] = info
end

-- The player drags an item to another slot: same instance, same GUID. An
-- occupied destination swaps, as the client does.
function WoW.MoveBagItem(fromBag, fromSlot, toBag, toSlot)
    local moving = WoW.bags[fromBag][fromSlot]
    local other = WoW.bags[toBag][toSlot]
    WoW.bags[fromBag][fromSlot] = other
    if toSlot > WoW.bags[toBag].size then WoW.bags[toBag].size = toSlot end
    WoW.bags[toBag][toSlot] = moving
end

function WoW.actionsOf(kind)
    local out = {}
    for _, a in ipairs(WoW.actions) do if a.kind == kind then out[#out + 1] = a end end
    return out
end

local function itemIDFrom(item)
    if type(item) == "number" then return item end
    if type(item) == "string" then return tonumber(item:match("item:(%d+)")) or tonumber(item) end
    return nil
end

------------------------------------------------------------
-- Widgets: what Shatter needs beyond the kit's core
------------------------------------------------------------

local function hasTemplate(template, name)
    return type(template) == "string" and (("," .. template:gsub("%s", "") .. ","):find("," .. name .. ",", 1, true)) ~= nil
end

-- A protected frame refuses these in combat. The kit's list, plus what this
-- stub refused before the kit: SetScale (WowTestKit #83), SetParent,
-- StartSizing, and the button's Enable / Disable / SetEnabled (protected in
-- SimpleButtonAPIDocumentation: IsProtectedFunction).
for _, m in ipairs({ "SetScale", "SetParent", "StartSizing", "Enable", "Disable", "SetEnabled" }) do
    WoW.PROTECTED[m] = true
end
-- ...and the refusal raises, as this stub's did: any path that reaches one in
-- combat fails the test where the call is made (the kit records it in
-- WoW.blocked and carries on, as the client does in game).
function WoW.refused(w, what)
    if WoW.combat and WoW.isProtected(w) then
        table.insert(WoW.blocked, (w._name or w._type) .. ":" .. what)
        error("ADDON_ACTION_BLOCKED: " .. what .. " on a protected frame in combat", 3)
    end
end

-- A test's injected faults: an event whose registration throws, or one the
-- client refuses (returns false). Both measured shapes, porting guide
-- section 3; the kit's own check (unknown names throw) still runs.
local coreRegisterEvent = Methods.RegisterEvent
function Methods.RegisterEvent(w, event)
    if WoW.badEvents[event] then error("Attempt to register unknown event \"" .. tostring(event) .. "\"", 3) end
    if WoW.refusedEvents[event] then return false end
    return coreRegisterEvent(w, event)
end

-- Methods the kit doesn't implement (each in the dump's widget methods).
function Methods.GetSize(w) return w._width, w._height end   -- WowTestKit #78
function Methods.GetNumPoints(w) return #w._points end
function Methods.SetScale(w, s) w._scale = s end
function Methods.GetScale(w) return w._scale or 1 end
function Methods.SetResizeBounds(w, minW, minH, maxW, maxH) w._resizeBounds = { minW, minH, maxW, maxH } end
function Methods.StartMoving(w) w._moving = true end
function Methods.StartSizing(w) w._sizing = true end
function Methods.StopMovingOrSizing(w) w._moving, w._sizing = false, false end
function Methods.RegisterForClicks(w, ...) w._registeredClicks = { ... } end
function Methods.GetTexture(t) return t._file end
function Methods.GetStringWidth(fs) return #(type(fs._text) == "string" and fs._text or "") * 6 end
function Methods.GetMinMaxValues(b) return b._min or 0, b._max or 0 end
function Methods.SetScrollChild(sf, c) sf._scrollChild = c end
function Methods.GetScrollChild(sf) return sf._scrollChild end
function Methods.SetVerticalScroll(sf, v) sf._vscroll = v end
function Methods.GetVerticalScroll(sf) return sf._vscroll or 0 end
function Methods.GetVerticalScrollRange(sf) return sf._vscrollRange or 0 end
-- As the client does, focus changes fire OnEditFocusGained / OnEditFocusLost.
function Methods.SetFocus(e)
    if e._focus then return end
    e._focus = true
    local fn = e._scripts.OnEditFocusGained
    if fn then fn(e) end
end
function Methods.ClearFocus(e)
    if not e._focus then return end
    e._focus = false
    local fn = e._scripts.OnEditFocusLost
    if fn then fn(e) end
end
function Methods.HasFocus(e) return e._focus or false end

-- GameTooltip's own (C) methods: the lines it holds, and its owner.
function Methods.SetOwner(tt, owner, anchor) tt._owner, tt._lines, tt._tooltipData = owner, {}, nil end
function Methods.GetOwner(tt) return tt._owner end
function Methods.AddLine(tt, text) tt._lines = tt._lines or {}; tt._lines[#tt._lines + 1] = text end
function Methods.AddDoubleLine(tt, l, r) tt._lines = tt._lines or {}; tt._lines[#tt._lines + 1] = tostring(l) .. "\t" .. tostring(r) end
function Methods.ClearLines(tt) tt._lines = {} end
function Methods.NumLines(tt) return #(tt._lines or {}) end
-- GameTooltip:SetText replaces the lines; everything else's is the kit's.
local coreSetText = Methods.SetText
function Methods.SetText(w, text, ...)
    if w._type == "GameTooltip" then
        w._lines, w._tooltipData = { text }, nil
        return
    end
    return coreSetText(w, text, ...)
end

-- A mixin's methods, installed on the widget by its template as Lua does
-- (Mixin copies them onto the frame), recorded for Kit.checkMethods like the
-- kit's own: test_methods allows each pair, naming the Blizzard file.
local function installMixin(w, mixin)
    for k, fn in pairs(mixin) do
        rawset(w, k, function(self, ...)
            WoW.methodsCalled[self._type .. ":" .. k] = true
            return fn(self, ...)
        end)
    end
end

-- BackdropTemplateMixin (Blizzard_SharedXML/Backdrop.lua).
local BackdropMixin = {}
function BackdropMixin:SetBackdrop(b) self._backdrop = b end
function BackdropMixin:SetBackdropColor(...) self._backdropColor = { ... } end
function BackdropMixin:SetBackdropBorderColor(...) self._backdropBorderColor = { ... } end
WoW.templates.BackdropTemplate = function(w) installMixin(w, BackdropMixin) end

-- GameTooltipDataMixin (Blizzard_GameTooltip/Mainline/GameTooltip.lua:951,
-- over TooltipDataHandlerMixin, Blizzard_SharedXMLGame/Tooltip/
-- TooltipDataHandler.lua): the setters, the data the tooltip was built from,
-- and the rebuild from it (fresh lines, post calls again).
local TooltipMixin = {}
function TooltipMixin:SetHyperlink(link) self._lines, self._tooltipData = { link }, nil end
function TooltipMixin:SetBagItem(bag, slot) self._lines, self._tooltipData = { "bag " .. bag .. " " .. slot }, nil end
function TooltipMixin:GetPrimaryTooltipData() return self._tooltipData end
function TooltipMixin:RefreshData()
    WoW.tooltipRefreshes = WoW.tooltipRefreshes + 1
    if self._tooltipData then WoW.showItemTooltip(self._tooltipData.id, self) end
end
-- GameTooltipTemplate (Blizzard_GameTooltip/Mainline/GameTooltip.xml:4): the
-- mixin, and its numbered lines ($parentTextLeftN / RightN, GameTooltipText).
WoW.templates.GameTooltipTemplate = function(w)
    w._lines = {}
    installMixin(w, TooltipMixin)
    if w._name then
        for i = 1, 30 do
            for _, side in ipairs({ "Left", "Right" }) do
                local name = w._name .. "Text" .. side .. i
                local fs = WoW.addRegion(w, WoW.newWidget("FontString", w, name))
                fs._fontTemplate = "GameTooltipText"
                rawset(_G, name, fs)
            end
        end
    end
end

-- What templates provide as fields (wow-ui-source, forever branch, 70959).
local function textRegion(w, font)
    local fs = WoW.addRegion(w, WoW.newWidget("FontString", w, w._name and (w._name .. "Text")))
    fs._fontTemplate = font
    return fs
end
-- CheckButtonTemplates.xml:54: $parentText, GameFontNormalSmall.
WoW.templates.UICheckButtonTemplate = function(w) w.Text = textRegion(w, "GameFontNormalSmall") end
-- SecureUIPanelTemplates.xml: ButtonText $parentText, NormalFont GameFontNormal.
WoW.templates.UIPanelButtonTemplate = function(w) w.Text = textRegion(w, "GameFontNormal") end

------------------------------------------------------------
-- Secure click dispatch, modelled on SecureActionButton_OnClick
-- (Blizzard_FrameXML/SecureTemplates.lua, forever branch): the client calls
-- PreClick, OnClick and PostClick for EVERY registered edge; OnClick performs
-- the action only on the edge where `down == useOnKeyDown`. The kit's secure
-- action doesn't resolve modified attributes (*type1, *spell1,
-- *target-bag1...) or press-and-hold's typerelease, which Shatter Next uses:
-- this template's OnClick does.
------------------------------------------------------------

local BUTTON_SUFFIX = { LeftButton = "1", RightButton = "2", MiddleButton = "3" }

local function registeredFor(w, button, down)
    for _, spec in ipairs(w._registeredClicks or {}) do
        if spec == "AnyUp" and not down then return true end
        if spec == "AnyDown" and down then return true end
        if spec == button .. (down and "Down" or "Up") then return true end
    end
    return false
end

local function modifiedAttribute(w, base, button)
    local n = BUTTON_SUFFIX[button] or ""
    local attrs = w._attrs or {}
    for _, key in ipairs({ "*" .. base .. n, base .. n, "*" .. base .. "*", base }) do
        local v = attrs[key]
        if v ~= nil then return v end
    end
    return nil
end

local function runMacro(text)
    WoW.macroRuns[#WoW.macroRuns + 1] = text
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local spell = line:match("^/cast%s+(.-);?%s*$")
        if spell and spell ~= "" then WoW.actions[#WoW.actions + 1] = { kind = "cast", spell = spell } end
        local bag, slot = line:match("^/use%s+(%d+)%s+(%d+)")
        if bag then WoW.actions[#WoW.actions + 1] = { kind = "use", bag = tonumber(bag), slot = tonumber(slot) } end
    end
end

-- type=spell (SECURE_ACTIONS.spell -> CastSpellByID), then OnActionButtonClick
-- targets target-bag/target-slot ONLY while the spell awaits an item target.
local function runSpell(w, button)
    local spell = modifiedAttribute(w, "spell", button)
    local spellID = tonumber(spell)
    WoW.actions[#WoW.actions + 1] = { kind = "cast", spell = spellID or spell }
    -- A refused cast (moving, already casting) raises no cursor of its own,
    -- but a cursor some OTHER spell left up still takes the item.
    if not WoW.castRefused then WoW.targeting = true end
    if WoW.targeting then
        local bag = modifiedAttribute(w, "target-bag", button)
        local slot = modifiedAttribute(w, "target-slot", button)
        if slot then
            WoW.actions[#WoW.actions + 1] = { kind = "use", bag = tonumber(bag), slot = tonumber(slot) }
            WoW.targeting = false
        end
    end
end

-- SecureActionButton_OnClick. Returns true when the secure action ran.
local function secureOnClick(w, button, down)
    -- SecureActionButton_ShouldUseOnKeyDown: the attribute, else the CVar.
    local useOnKeyDown = (w._attrs or {}).useOnKeyDown
    if useOnKeyDown == nil then useOnKeyDown = WoW.cvars.ActionButtonUseKeyDown == "1" end
    if (down and useOnKeyDown) or (not down and not useOnKeyDown) then
        local kind = modifiedAttribute(w, "type", button)
        if kind == "macro" then
            local text = modifiedAttribute(w, "macrotext", button)
            if text and text ~= "" then runMacro(text) return true end
        elseif kind == "spell" then
            runSpell(w, button)
            return true
        end
    elseif not down and WoW.cvars.ActionButtonUseKeyHeldSpell == "1" then
        -- Press-and-hold release resolves "typerelease", not "type".
        local kind = modifiedAttribute(w, "typerelease", button)
        if kind == "spell" then runSpell(w, button) return true end
    end
    return false
end
WoW.templates.SecureActionButtonTemplate = function(w)
    w._protected = true
    w._scripts.OnClick = secureOnClick
end

-- One mouse edge. Returns true when the secure action ran. A mouse can't
-- click what isn't visible; a bound key can (`viaBinding`, below).
function WoW.clickEdge(w, button, down, viaBinding)
    if (not viaBinding and not w:IsVisible()) or w._disabled then return false end
    if not registeredFor(w, button, down) then return false end
    -- A script error is reported and the click carries on: an error in
    -- PreClick does not cancel the secure action that follows it.
    if w._scripts.PreClick then
        local ok, err = pcall(w._scripts.PreClick, w, button, down)
        if not ok then WoW.scriptErrors[#WoW.scriptErrors + 1] = err end
    end
    -- An ordinary button's OnClick runs on every edge it registered for; the
    -- down == useOnKeyDown filter lives inside SecureActionButton_OnClick.
    local acted = false
    if w._scripts.OnClick then
        local r = w._scripts.OnClick(w, button, down)
        acted = w._scripts.OnClick == secureOnClick and r == true
    end
    if w._scripts.PostClick then w._scripts.PostClick(w, button, down) end
    return acted
end

-- A key bound with `CLICK <name>:<button>` (Bindings.xml): its press and
-- release reach the named button, even hidden (measured on Forever by
-- Apotheca, 70009). `repeats` extra down edges model a held key.
function WoW.pressBinding(action, repeats)
    local name, button = action:match("^CLICK ([^:]+):(%w+)$")
    local w = assert(name and rawget(_G, name), "no button for binding " .. tostring(action))
    local acted = WoW.clickEdge(w, button, true, true)
    for _ = 1, repeats or 0 do acted = WoW.clickEdge(w, button, true, true) or acted end
    return WoW.clickEdge(w, button, false, true) or acted
end

-- A whole press: down edge, then up edge (the kit's WoW.click is one edge).
function WoW.press(w, button)
    button = button or "LeftButton"
    local a = WoW.clickEdge(w, button, true)
    local b = WoW.clickEdge(w, button, false)
    return a or b
end

------------------------------------------------------------
-- Blizzard frames and constants that exist at login
------------------------------------------------------------

Minimap = CreateFrame("Minimap", "Minimap", UIParent)
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent, "GameTooltipTemplate")
MailFrame = CreateFrame("Frame", "MailFrame", UIParent)
InboxFrame = CreateFrame("Frame", "InboxFrame", MailFrame)
OpenMailFrame = CreateFrame("Frame", "OpenMailFrame", UIParent)
SendMailFrame = CreateFrame("Frame", "SendMailFrame", MailFrame)
WoW.setShown(MailFrame, false)
WoW.setShown(OpenMailFrame, false)
WoW.setShown(SendMailFrame, false)
-- The chat frame: its lines go through print, so WoW.chat has them all and
-- done() checks each for a stray "|".
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) print(tostring(msg)) end }
UISpecialFrames = {}
SlashCmdList = {}

NUM_BAG_SLOTS = 4
ATTACHMENTS_MAX = 16
ATTACHMENTS_MAX_SEND = 12
ITEM_SOULBOUND = "Soulbound"
UNKNOWN = "Unknown"
ITEM_QUALITY_COLORS = {}
for q, rgb in pairs({ [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 },
                      [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 } }) do
    ITEM_QUALITY_COLORS[q] = { r = rgb[1], g = rgb[2], b = rgb[3], hex = "|cffffffff" }
end
Enum = {
    SpellBookSpellBank = { Player = 0, Pet = 1 },
    ItemClass = { Weapon = 2, Armor = 4 },
    -- TooltipInfoSharedDocumentation.lua: Item = 0, Spell = 1, ...
    TooltipDataType = { Item = 0, Spell = 1, Unit = 2 },
    BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5, Keyring = -1 },
}

function GameTooltip_Hide() GameTooltip:Hide() end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end

------------------------------------------------------------
-- Game state
------------------------------------------------------------

function time() return WoW.epoch end
function IsShiftKeyDown() return WoW.shift end
-- dump 5496: Shift, Alt or Ctrl.
function IsModifierKeyDown() return WoW.shift or WoW.alt or WoW.ctrl or false end
function GetBuildInfo() return "1.60.1", WoW.build, "Oct 6 2026", 16001, "", " " end
function GetCVarBool(name) return WoW.cvars[name] == "1" end
-- Key bindings: WoW.bindings[action] = key (GetBindingKey, dump).
WoW.bindings = {}
function GetBindingKey(action) return WoW.bindings[action] end
function GetCVar(name) return WoW.cvars[name] end
C_CVar = {
    GetCVar = function(name) return WoW.cvars[name] end,
    GetCVarBool = function(name) return WoW.cvars[name] == "1" end,
}
function UnitName(unit)
    if unit == "player" then return WoW.player.name, nil end
    return nil
end
function GetRealmName() return WoW.player.realm end
function GetNormalizedRealmName() return (WoW.player.realm:gsub("%s", "")) end
function UnitGUID(unit) if unit == "player" then return "Player-1-00000001" end end
-- dump 6405: className, classFilename, classID.
local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
function UnitClass(unit)
    if unit ~= "player" then return nil end
    local class = WoW.player.class
    return class:sub(1, 1) .. class:sub(2):lower(), class, CLASS_IDS[class]
end
-- Present on this client but returns nothing (measured, porting guide 960).
function GetProfessions() return nil end
function GetProfessionInfo() return nil end
function SpellIsTargeting() return WoW.targeting end
function SpellCanTargetItem() return WoW.targeting end
function UnitCastingInfo(unit)
    local c = unit == "player" and WoW.casting
    if not c then return nil end
    return c.name, c.name, 136244, c.startMs, c.endMs, false, "cast-1", false, c.spellID
end
-- Channels are reported here, not by UnitCastingInfo (dump 6403).
function UnitChannelInfo(unit)
    local c = unit == "player" and WoW.channeling
    if not c then return nil end
    return c.name, c.name, 136244, c.startMs, c.endMs, false, false, c.spellID, false, 0
end

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strlower = string.lower
strupper = string.upper
strsplit = function(sep, s)
    local out, start = {}, 1
    while true do
        local i = s:find(sep, start, true)
        if not i then out[#out + 1] = s:sub(start) break end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + #sep
    end
    return unpack(out)
end
tinsert, tremove = table.insert, table.remove
format = string.format

------------------------------------------------------------
-- Namespaces (shapes from the 70334 dump)
------------------------------------------------------------

-- Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:199: a post call runs
-- as fn(tooltip, tooltipData) once the tooltip has processed its lines. There
-- is no way to remove one. WoW.showItemTooltip plays the client's part.
TooltipDataProcessor = { AllTypes = "ALL" }
function TooltipDataProcessor.AddTooltipPostCall(tooltipType, fn)
    local list = WoW.tooltipPostCalls[tooltipType] or {}
    WoW.tooltipPostCalls[tooltipType] = list
    list[#list + 1] = fn
end
-- Shows `itemID` on `tooltip` (GameTooltip by default) the way the client
-- does: fresh lines, the item's own line, then every Item post call.
function WoW.showItemTooltip(itemID, tooltip)
    tooltip = tooltip or GameTooltip
    tooltip:ClearLines()
    tooltip:AddLine("[item " .. itemID .. "]")
    local data = { type = Enum.TooltipDataType.Item, id = itemID, hyperlink = WoW.link(itemID) }
    tooltip._tooltipData = data
    tooltip:Show()
    for _, fn in ipairs(WoW.tooltipPostCalls[Enum.TooltipDataType.Item] or {}) do fn(tooltip, data) end
    return tooltip._lines
end

-- dump 3414-3417, 9141: SkillLineAttributes tables; an index past the end, or
-- an unknown ID, gives nil. A collapsed header hides the lines under it (the
-- Skills tab's behaviour; to be measured, #5).
C_SkillInfo = {}
local function visibleSkillLines()
    local list, hidden = {}, false
    for _, line in ipairs(WoW.skillLines) do
        if line.isHeader then
            list[#list + 1] = line
            hidden = line.isCollapsed == true
        elseif not hidden then
            list[#list + 1] = line
        end
    end
    return list
end
function C_SkillInfo.GetNumSkillLines() return #visibleSkillLines() end
function C_SkillInfo.GetSkillLineInfo(index) return visibleSkillLines()[index] end
function C_SkillInfo.GetSkillLineInfoByID(id)
    for _, line in ipairs(WoW.skillLines) do
        if line.skillID == id then return line end
    end
end
-- dump 4911.
function GetGameMessageInfo(errorType) return WoW.gameErrors[errorType] end

C_ClassColor = {}
-- dump 768: a colorRGB (a ColorMixin: r, g, b fields) by class filename.
local CLASS_COLORS = { MAGE = { 0.25, 0.78, 0.92 }, PRIEST = { 1, 1, 1 }, WARRIOR = { 0.78, 0.61, 0.43 } }
function C_ClassColor.GetClassColor(className)
    local c = CLASS_COLORS[className]
    if c then return { r = c[1], g = c[2], b = c[3] } end
end

C_AddOns = {}
function C_AddOns.GetAddOnMetadata(name, key)
    if name == "Shatter" and key == "Version" then return WoW.version end
    return nil
end
function C_AddOns.IsAddOnLoaded(name)
    local a = WoW.addons[name]
    return a and a.loaded or false, a and a.loaded or false
end
-- dump 183: name, title, notes, loadable, reason, security. The name is
-- not optional: a missing addon still returns it, with reason "MISSING".
function C_AddOns.GetAddOnInfo(name)
    local a = WoW.addons[name]
    if not a then return name, name, "", false, "MISSING", "INSECURE" end
    return name, name, "", a.loadable ~= false, a.loadable == false and "DISABLED" or nil
end
function C_AddOns.LoadAddOn(name)
    local a = WoW.addons[name]
    if a and a.loadable ~= false then a.loaded = true return true end
    return false, "MISSING"
end

C_Spell = {}
-- By ID this always resolves, known or not (porting guide section 2).
function C_Spell.GetSpellName(spellID) return WoW.spellNames[spellID] end
function C_Spell.GetSpellInfo(spellID)
    local name = WoW.spellNames[spellID]
    if not name then return nil end
    return { name = name, spellID = spellID, iconID = 136244, castTime = 3000, minRange = 0, maxRange = 0 }
end

C_UnitAuras = {}
-- An AuraData table or nil (dump 70334 and 70938). In combat the client
-- makes auras secret, and testing one throws; aurasSecret models that as a
-- throw from the call itself (porting guide, "Auras go dark").
function C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    if WoW.aurasSecret then error("Auras cannot be accessed when secret while tainted by 'Shatter'", 2) end
    return WoW.playerAuras[spellID]
end

C_SpellBook = {}
function C_SpellBook.IsSpellInSpellBook(spellID, spellBank, includeOverrides)
    if not WoW.spellbookReady then return false end
    return WoW.knownSpells[spellID] or false
end
function C_SpellBook.IsSpellKnown(spellID, spellBank)
    if not WoW.spellbookReady then return false end
    return WoW.knownSpells[spellID] or false
end

C_Item = {}
-- Classic tuple order, 18 returns; NOTHING at all on a cache miss.
function C_Item.GetItemInfo(item)
    local id = itemIDFrom(item)
    local i = id and WoW.items[id]
    if not i or WoW.cacheMiss[id] then return end
    return i.name, WoW.link(id), i.quality, i.itemLevel, i.reqLevel or 1,
        i.classID == 2 and "Weapon" or "Armor", "Misc", 1, i.equipLoc or "INVTYPE_CHEST",
        i.icon or 134400, i.sellPrice or 0, i.classID, i.subclassID or 0, i.bindType or 2, 0, nil, false
end
-- No return: the client fetches the item and fires GET_ITEM_INFO_RECEIVED.
-- Recorded here; a test clears WoW.cacheMiss and fires the event itself.
function C_Item.RequestLoadItemDataByID(item)
    WoW.itemRequests[#WoW.itemRequests + 1] = itemIDFrom(item)
end
-- Seven returns, no cache needed.
function C_Item.GetItemInfoInstant(item)
    local id = itemIDFrom(item)
    local i = id and WoW.items[id]
    if not i then return end
    return id, i.classID == 2 and "Weapon" or "Armor", "Misc", i.equipLoc or "INVTYPE_CHEST",
        i.icon or 134400, i.classID, i.subclassID or 0
end
function C_Item.GetItemCount(item, includeBank, includeUses, includeReagentBank, includeAccountBank)
    local id = itemIDFrom(item)
    local n = 0
    for bag = 0, 4 do
        local b = WoW.bags[bag]
        for slot = 1, b.size do
            if b[slot] and b[slot].itemID == id then n = n + (b[slot].count or 1) end
        end
    end
    return n
end
-- ItemLocation as Blizzard_ObjectAPI/Mainline/ItemLocation.lua builds it
-- (the C side reads bagID/slotIndex).
ItemLocation = {}
local ItemLocationMixin = {}
ItemLocationMixin.__index = ItemLocationMixin
function ItemLocation:CreateFromBagAndSlot(bagID, slotIndex)
    return setmetatable({ bagID = bagID, slotIndex = slotIndex }, ItemLocationMixin)
end
function ItemLocation:CreateFromEquipmentSlot(equipmentSlotIndex)
    return setmetatable({ equipmentSlotIndex = equipmentSlotIndex }, ItemLocationMixin)
end
function ItemLocationMixin:GetBagAndSlot() return self.bagID, self.slotIndex end
function ItemLocationMixin:IsBagAndSlot() return self.bagID ~= nil and self.slotIndex ~= nil end
function ItemLocationMixin:GetEquipmentSlot() return self.equipmentSlotIndex end
function ItemLocationMixin:IsEquipmentSlot() return self.equipmentSlotIndex ~= nil end
local function bagItemAt(location)
    local b = location and location.bagID and WoW.bags[location.bagID]
    return b and location.slotIndex and b[location.slotIndex]
end
local function equippedAt(location)
    return location and location.equipmentSlotIndex and WoW.equipped[location.equipmentSlotIndex]
end
function C_Item.DoesItemExist(location) return (bagItemAt(location) or equippedAt(location)) ~= nil end
-- dump 2222: optional number.
function C_Item.GetCurrentItemLevel(location)
    local s = equippedAt(location) or bagItemAt(location)
    if not s then return nil end
    if s.level == false then return nil end   -- not available (yet)
    if s.level then return s.level end
    local i = WoW.items[s.itemID]
    return i and i.itemLevel
end
-- dump 2226: actualItemLevel, previewLevel, sparseItemLevel; nothing on a
-- cache miss. WoW.linkLevels[itemID] models an instance level in its link.
function C_Item.GetDetailedItemLevelInfo(item)
    local id = itemIDFrom(item)
    local i = id and WoW.items[id]
    if not i or WoW.cacheMiss[id] then return end
    return WoW.linkLevels[id] or i.itemLevel, false, i.itemLevel
end
-- What the player wears in an inventory slot (dump: GetInventoryItemLink).
function GetInventoryItemLink(unit, slot)
    local worn = unit == "player" and WoW.equipped[slot]
    return worn and WoW.link(worn.itemID) or nil
end
-- dump 2232: non-optional WOWGUID; an empty location is a usage error.
function C_Item.GetItemGUID(location)
    local s = bagItemAt(location)
    if not s then error("C_Item.GetItemGUID: invalid item location", 2) end
    return s.guid
end
function C_Item.GetItemIconByID(item) local i = WoW.items[itemIDFrom(item)] return i and (i.icon or 134400) end
function C_Item.GetItemQualityColor(q)
    local c = ITEM_QUALITY_COLORS[q]
    return c.r, c.g, c.b, c.hex
end

C_Container = {}
function C_Container.GetContainerNumSlots(bag) local b = WoW.bags[bag] return b and b.size or 0 end
function C_Container.GetContainerNumFreeSlots(bag)
    local b = WoW.bags[bag]
    if not b then return 0, 0 end
    local free = 0
    for slot = 1, b.size do if not b[slot] then free = free + 1 end end
    return free, 0
end
-- A struct, not the old tuple (porting guide section 2).
-- dump 1561, 1569: whether sets can be used, and their IDs (a table).
C_EquipmentSet = {
    CanUseEquipmentSets = function() return WoW.canUseSets end,
    GetEquipmentSetIDs = function() return WoW.equipmentSetIDs or {} end,
}
-- dump 1168: inSet, setList. A slot's `inSet`/`setList` model it (sets are
-- unmeasured on Forever, #36).
function C_Container.GetContainerItemEquipmentSetInfo(bag, slot)
    local b = WoW.bags[bag]
    local s = b and b[slot]
    if not s then return false, "" end
    return s.inSet == true, s.setList or ""
end
function C_Container.GetContainerItemInfo(bag, slot)
    local b = WoW.bags[bag]
    local s = b and b[slot]
    if not s then return nil end
    local i = WoW.items[s.itemID] or {}
    return {
        iconFileID = i.icon or 134400, stackCount = s.count or 1, isLocked = s.locked or false,
        quality = i.quality, isReadable = false, hasLoot = false, hyperlink = WoW.link(s.itemID),
        isFiltered = false, hasNoValue = false, itemID = s.itemID, isBound = s.bound or false,
    }
end
function C_Container.GetContainerItemLink(bag, slot)
    local s = WoW.bags[bag] and WoW.bags[bag][slot]
    return s and WoW.link(s.itemID) or nil
end
function C_Container.GetContainerItemID(bag, slot)
    local s = WoW.bags[bag] and WoW.bags[bag][slot]
    return s and s.itemID or nil
end
-- Protected: from addon code this is ADDON_ACTION_FORBIDDEN (measured on TBC
-- Anniversary and the reason for the secure macro button).
function C_Container.UseContainerItem()
    error("ADDON_ACTION_FORBIDDEN: UseContainerItem() from addon code", 2)
end
function C_Container.PickupContainerItem(bag, slot)
    WoW.actions[#WoW.actions + 1] = { kind = "pickup", bag = bag, slot = slot }
end

-- Mail (all survivors as globals)
function GetInboxNumItems() return #WoW.inbox, #WoW.inbox end
function GetInboxHeaderInfo(index)
    local m = WoW.inbox[index]
    if not m then return nil end
    local count = 0
    for a = 1, ATTACHMENTS_MAX do if m.items and m.items[a] then count = count + 1 end end
    return nil, nil, m.sender, m.subject or "", m.money or 0, m.cod or 0, 30, count > 0 and count or nil,
        m.read or false, m.returned or false, false, true, m.isGM or false
end
function GetInboxItem(index, attachment)
    local m = WoW.inbox[index]
    local a = m and m.items and m.items[attachment]
    if not a then return nil end
    local i = WoW.items[a.itemID] or {}
    return i.name, a.itemID, i.icon or 134400, a.count or 1, i.quality, true
end
function GetInboxItemLink(index, attachment)
    local m = WoW.inbox[index]
    local a = m and m.items and m.items[attachment]
    return a and WoW.link(a.itemID) or nil
end
function TakeInboxItem(index, attachment)
    WoW.actions[#WoW.actions + 1] = { kind = "takeInbox", index = index, attachment = attachment }
end

-- Loot
function GetNumLootItems() return #WoW.loot end
function GetLootSlotLink(slot) local l = WoW.loot[slot] return l and l.link end
function GetLootSlotInfo(slot)
    local l = WoW.loot[slot]
    if not l then return nil end
    return 134400, l.name or "", l.count or 1, nil, 2, false, false, nil, true
end

------------------------------------------------------------
-- Loading, the way the client does it
------------------------------------------------------------

local function readText(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return text
end

-- The embedded LibGlass-1.0 is not in the repo (.pkgmeta externals fetch it;
-- Tools/deploy.ps1 copies it): tests load the checkout at $LIBGLASS, else the
-- sibling ../LibGlass, through its XML's own <Script> list, so a missing file
-- fails here as it would in the client.
WoW.LIBGLASS = os.getenv("LIBGLASS") or "../LibGlass"
local function libFiles(xmlPath)
    local root = WoW.LIBGLASS
    local xml = readText(root .. "/" .. xmlPath:match("[^/]+$"))
    assert(xml, "LibGlass checkout not found at " .. root .. " (clone github.com/Spotnick2/LibGlass there or set LIBGLASS)")
    local files = {}
    for script in xml:gsub("<!%-%-.-%-%->", ""):gmatch('<Script%s+file="([^"]+)"') do
        files[#files + 1] = root .. "/" .. script:gsub("\\", "/")
    end
    return files
end

-- `withoutLibs`: an install from a git clone, with no Libs folder.
local function tocFiles(withoutLibs)
    local files = {}
    for _, line in ipairs(Kit.tocLines("Shatter.toc")) do
        local file = line:gsub("\\", "/")
        if file:match("%.xml$") then
            if not withoutLibs then
                for _, script in ipairs(libFiles(file)) do files[#files + 1] = script end
            end
        else
            files[#files + 1] = file
        end
    end
    return files
end
WoW.tocFiles = tocFiles

------------------------------------------------------------
-- Strict globals
------------------------------------------------------------

local KNOWN_ABSENT = {
    -- Removed on this client (dump + porting guide), or only provided by the
    -- Blizzard_Deprecated* fallbacks the addon must not depend on.
    GetItemInfo = true, GetItemInfoInstant = true, GetItemCount = true, GetItemIcon = true,
    GetSpellInfo = true, GetSpellBookItemName = true, BOOKTYPE_SPELL = true,
    IsSpellKnown = true, IsPlayerSpell = true,
    GetAddOnMetadata = true, GetAddOnInfo = true, IsAddOnLoaded = true, LoadAddOn = true,
    GetContainerNumSlots = true, GetContainerItemInfo = true, GetContainerItemLink = true,
    GetContainerItemID = true, GetContainerNumFreeSlots = true, UseContainerItem = true,
    PickupContainerItem = true, MouseIsOver = true, MAX_PLAYER_LEVEL = true,
    -- Optional third-party addons: absent unless a test installs them.
    TSM_API = true, Auctionator = true, AucAdvanced = true, Postal = true, Postal_Select = true,
    Gargul = true, GL = true, GlassUI = true, GlassMail = true,
    -- The probe host and its modules' saved tables (Tools/ShatterProbe).
    ForeverProbe = true, ForeverProbeDB = true, ShatterProbeDB = true,
    -- The addon's own globals, nil until it creates them / SavedVariables load.
    Shatter = true, ShatterDB = true,
    -- Embedded LibStub (LibGlass-1.0's bundled copy) reads it before creating it.
    LibStub = true,
}
-- Postal's inbox checkboxes and Shatter's own scan tooltip lines past the
-- template's 30 read as nil too.
setmetatable(KNOWN_ABSENT, { __index = function(_, k)
    if type(k) == "string" and (k:match("^PostalInboxCB%d+$") or k:match("^ShatterScanTooltip")) then return true end
end })

function WoW.allowGlobal(name) rawset(KNOWN_ABSENT, name, true) end

-- Blizzard-owned tables: assigning the global (even to itself) taints.
local PROTECTED_GLOBALS = {
    SlashCmdList = true, UISpecialFrames = true, StaticPopupDialogs = true,
    UIParent = true, GameTooltip = true, DEFAULT_CHAT_FRAME = true,
}

-- The only globals the addon may create.
local ALLOWED_WRITES = { Shatter = true, ShatterDB = true, SLASH_SHATTER1 = true, SLASH_SHATTER2 = true, LibStub = true,
    ["BINDING_NAME_CLICK ShatterNextButton:LeftButton"] = true }

local addonLoading = false

-- Rejected writes to existing globals (rawset already holds them, so
-- __newindex never sees a reassignment): catch those by snapshot.
local function snapshotProtected()
    local snap = {}
    for k in pairs(PROTECTED_GLOBALS) do snap[k] = rawget(_G, k) end
    return snap
end

-- Runs every TOC file with ("Shatter", ns), hands it the SavedVariables, then
-- fires ADDON_LOADED and (unless opts.login == false) PLAYER_LOGIN.
function WoW.loadAddon(opts)
    opts = opts or {}
    local ns = {}
    local before = snapshotProtected()
    addonLoading = true
    for _, path in ipairs(tocFiles(opts.withoutLibs)) do
        local chunk = assert(loadfile(path))
        chunk("Shatter", ns)
    end
    addonLoading = false
    for k, v in pairs(before) do
        assert(rawget(_G, k) == v, "addon replaced Blizzard global " .. k)
    end
    rawset(_G, "ShatterDB", opts.savedDB)
    WoW.fire("ADDON_LOADED", "Shatter")
    if opts.login ~= false then WoW.fire("PLAYER_LOGIN") end
    return ns
end

-- ForeverProbe, the private local probe host (Tools/ShatterProbe's tests):
-- its TOC's files from $FOREVERPROBE, else ../ForeverProbe, then its
-- ADDON_LOADED. In CI (FOREVERPROBE_OPTIONAL=1) a missing checkout skips the
-- calling test file; locally it's an error.
function WoW.loadForeverProbe()
    local root = (os.getenv("FOREVERPROBE") or "../ForeverProbe"):gsub("\\", "/"):gsub("/$", "")
    local toc = io.open(root .. "/ForeverProbe.toc", "rb")
    if not toc then
        if os.getenv("FOREVERPROBE_OPTIONAL") == "1" then
            io.write("SKIPPED: ForeverProbe isn't here (private, local only); the probe tests run locally\n")
            os.exit(0)
        end
        error("ForeverProbe checkout not found at " .. root .. ": clone it there or set FOREVERPROBE", 0)
    end
    local files = {}
    for line in toc:read("*a"):gmatch("[^\r\n]+") do
        if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = root .. "/" .. line end
    end
    toc:close()
    for _, file in ipairs(files) do assert(loadfile(file))("ForeverProbe", {}) end
    WoW.fire("ADDON_LOADED", "ForeverProbe")
    return rawget(_G, "ForeverProbe")
end

-- Most tests want an active enchanter with an empty backpack.
function WoW.enchanter()
    WoW.knownSpells[13262] = true
    WoW.knownSpells[7411] = true
end

Kit.strict(KNOWN_ABSENT)
-- The kit's strict globals check reads; this stub checks writes too.
getmetatable(_G).__newindex = function(t, k, v)
    if addonLoading then
        if PROTECTED_GLOBALS[k] then
            error("write to Blizzard global '" .. tostring(k) .. "' taints secure macros", 2)
        end
        WoW.globalWrites[k] = true
        if not ALLOWED_WRITES[k] then
            error("addon created undeclared global '" .. tostring(k) .. "'", 2)
        end
    end
    rawset(t, k, v)
end
