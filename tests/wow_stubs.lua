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
-- Three kinds of strictness, all on purpose:
--   * Reading a global this file doesn't define is an error. The stub is the
--     list of APIs verified present on build 1.60.1.70291 (the API dump in
--     C:\Projects\References and the client UI source), so it models the
--     ABSENCES too. KNOWN_ABSENT models a client with the Blizzard_Deprecated*
--     fallbacks switched off (CVar loadDeprecationFallbacks), which is the
--     state an addon must survive.
--   * Widgets have no catch-all: a method not defined here is nil, and calling
--     it errors exactly as the client does. Every method below was checked
--     against the dump's widget methods; SetBackdrop* exist only on frames
--     created with BackdropTemplate (it is a mixin), and SetHyperlink /
--     SetBagItem only on GameTooltips (TooltipDataHandler.lua mixin).
--   * Writing a Blizzard-owned global (SlashCmdList, UISpecialFrames, ...)
--     is an error: the write taints every secure macro on this client
--     (porting guide, section 3). Write fields, never the table.
-- Never add something because a test failed; confirm it exists first.
------------------------------------------------------------

WoW = {}
local WoW = WoW

local MEASURED_BUILD = "70291"

function WoW.reset()
    WoW.frames        = {}  -- every frame created, in order
    WoW.events        = {}  -- [frame] = { [event] = true }
    WoW.time          = 1000
    WoW.epoch         = 1790000000
    WoW.inCombat      = false
    WoW.build         = MEASURED_BUILD
    WoW.version       = "v0.2.0-alpha"
    WoW.player        = { name = "Example Surname", realm = "ClassicBetaPvE" }
    WoW.cvars         = { ActionButtonUseKeyDown = "1" }
    WoW.knownSpells   = {}  -- [spellID] = true
    WoW.spellNames    = { [13262] = "Disenchant", [7411] = "Enchanting" }
    WoW.spellbookReady = true
    WoW.items         = {}  -- [itemID] = { name, quality, itemLevel, classID, subclassID, equipLoc, sellPrice, icon }
    WoW.cacheMiss     = {}  -- [itemID] = true -> C_Item.GetItemInfo returns nothing
    WoW.bags          = {}  -- [bag] = { size = n, [slot] = { itemID, count, locked, bound } }
    WoW.inbox         = {}  -- list of { sender, subject, items = { [attachmentIndex] = { itemID, count } } }
    WoW.loot          = {}  -- list of { link, count, name }
    WoW.casting       = nil -- { name, startMs, endMs, spellID }
    WoW.targeting     = false
    WoW.castRefused   = false
    WoW.shift         = false
    WoW.cursor        = { 0, 0 }
    WoW.addons        = {}  -- [name] = { loaded = bool, loadable = bool }
    WoW.messages      = {}
    WoW.timers        = {}
    WoW.badEvents     = {}  -- RegisterEvent throws
    WoW.refusedEvents = {}  -- RegisterEvent returns false
    WoW.actions       = {}  -- gameplay actions the client performed: { kind, ... }
    WoW.macroRuns     = {}  -- macro text the secure handler executed
    WoW.globalWrites  = {}  -- [name] = true for every global the addon assigned
    WoW.scriptErrors  = {}  -- errors raised by click scripts (the client reports and continues)
    for bag = 0, 4 do WoW.bags[bag] = { size = bag == 0 and 16 or 0 } end
end
WoW.reset()

------------------------------------------------------------
-- Test helpers
------------------------------------------------------------

function WoW.fire(event, ...)
    for _, frame in ipairs(WoW.frames) do
        local events = WoW.events[frame]
        if events and events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

function WoW.flushTimers(maxRounds)
    for _ = 1, maxRounds or 10 do
        local list = WoW.timers
        if #list == 0 then return end
        WoW.timers = {}
        for _, t in ipairs(list) do t.fn() end
    end
end

function WoW.advance(seconds) WoW.time = WoW.time + seconds end

function WoW.chat() return table.concat(WoW.messages, "\n") end

function WoW.link(itemID)
    local item = WoW.items[itemID]
    local name = item and item.name or ("Item " .. itemID)
    return "|cff1eff00|Hitem:" .. itemID .. "::::::::60:::::::|h[" .. name .. "]|h|r"
end

function WoW.AddItem(itemID, info)
    info.name = info.name or ("Item " .. itemID)
    WoW.items[itemID] = info
end

function WoW.SetBagItem(bag, slot, info)
    local b = WoW.bags[bag]
    if slot > b.size then b.size = slot end
    b[slot] = info
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
-- Widgets
------------------------------------------------------------

local Widget = {}
local WidgetMeta = { __index = Widget }

-- A frame is protected when it is secure or holds a secure frame anywhere
-- below it (measured: a parent of secure buttons is protected, section 3).
local function isProtected(w)
    if w.secure then return true end
    for _, child in ipairs(w.children) do
        if isProtected(child) then return true end
    end
    return false
end

local function guard(w, what)
    if WoW.inCombat and isProtected(w) then
        error("ADDON_ACTION_BLOCKED: " .. what .. " on a protected frame in combat", 3)
    end
end

local function hasTemplate(template, name)
    return type(template) == "string" and (("," .. template:gsub("%s", "") .. ","):find("," .. name .. ",", 1, true)) ~= nil
end

local Backdrop = {}
function Backdrop:SetBackdrop(b) self.backdrop = b end
function Backdrop:SetBackdropColor(...) self.backdropColor = { ... } end
function Backdrop:SetBackdropBorderColor(...) self.backdropBorderColor = { ... } end

local Tooltip = {}
function Tooltip:SetOwner(owner, anchor) self.owner = owner self.lines = {} end
function Tooltip:SetText(t) self.lines = { t } end
function Tooltip:AddLine(t) self.lines[#self.lines + 1] = t end
function Tooltip:AddDoubleLine(l, r) self.lines[#self.lines + 1] = tostring(l) .. "\t" .. tostring(r) end
function Tooltip:ClearLines() self.lines = {} end
function Tooltip:NumLines() return #self.lines end
function Tooltip:SetHyperlink(link) self.lines = { link } end
function Tooltip:SetBagItem(bag, slot) self.lines = { "bag " .. bag .. " " .. slot } end

local newWidget

local function child(parent, kind, name)
    local c = newWidget(kind, name, parent)
    parent.children[#parent.children + 1] = c
    return c
end

function newWidget(kind, name, parent, template)
    local w = setmetatable({
        kind = kind, name = name, parent = parent, template = template,
        shown = true, scripts = {}, hooks = {}, attrs = {}, points = {}, children = {},
        scale = 1, alpha = 1, _text = "", checked = false, enabled = true,
        width = 0, height = 0, level = 1,
        secure = hasTemplate(template, "SecureActionButtonTemplate"),
    }, WidgetMeta)
    if name then rawset(_G, name, w) end
    WoW.frames[#WoW.frames + 1] = w
    if hasTemplate(template, "BackdropTemplate") then
        for k, fn in pairs(Backdrop) do w[k] = fn end
    end
    if kind == "GameTooltip" then
        w.lines = {}
        for k, fn in pairs(Tooltip) do w[k] = fn end
        if hasTemplate(template, "GameTooltipTemplate") and name then
            for i = 1, 30 do
                child(w, "FontString", name .. "TextLeft" .. i)
                child(w, "FontString", name .. "TextRight" .. i)
            end
        end
    end
    -- What templates provide as fields (read from wow-ui-source, forever branch).
    if hasTemplate(template, "UICheckButtonTemplate") then
        w.Text = child(w, "FontString")
    elseif hasTemplate(template, "UIPanelScrollFrameTemplate") then
        w.ScrollBar = child(w, "Slider")
    elseif hasTemplate(template, "UIPanelButtonTemplate") then
        w.Text = child(w, "FontString")
    end
    return w
end

-- Geometry and visibility
function Widget:SetSize(wd, h) guard(self, "SetSize") self.width, self.height = wd, h end
function Widget:SetWidth(wd) guard(self, "SetWidth") self.width = wd end
function Widget:SetHeight(h) guard(self, "SetHeight") self.height = h end
function Widget:GetWidth() return self.width end
function Widget:GetHeight() return self.height end
function Widget:GetSize() return self.width, self.height end
function Widget:SetPoint(...) guard(self, "SetPoint") self.points[#self.points + 1] = { ... } end
function Widget:ClearAllPoints() guard(self, "ClearAllPoints") self.points = {} end
function Widget:GetPoint(i)
    local p = self.points[i or 1] or { "CENTER", nil, "CENTER", 0, 0 }
    return p[1], p[2], p[3], p[4], p[5]
end
function Widget:GetNumPoints() return #self.points end
function Widget:SetAllPoints() guard(self, "SetAllPoints") end
function Widget:GetCenter() return 500, 400 end
function Widget:GetLeft() return 400 end
function Widget:GetRight() return 600 end
function Widget:GetTop() return 500 end
function Widget:GetBottom() return 300 end
function Widget:Show()
    guard(self, "Show")
    local was = self.shown
    self.shown = true
    if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Widget:Hide()
    guard(self, "Hide")
    local was = self.shown
    self.shown = false
    if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:IsShown() return self.shown end
function Widget:IsVisible()
    local f = self
    while f do
        if not f.shown then return false end
        f = f.parent
    end
    return true
end
function Widget:SetScale(s) guard(self, "SetScale") self.scale = s end
function Widget:GetScale() return self.scale end
function Widget:GetEffectiveScale()
    local s, f = 1, self
    while f do s = s * (f.scale or 1) f = f.parent end
    return s
end
function Widget:SetAlpha(a) self.alpha = a end
function Widget:GetAlpha() return self.alpha end
function Widget:SetParent(p) guard(self, "SetParent") self.parent = p end
function Widget:GetParent() return self.parent end
function Widget:GetName() return self.name end
function Widget:GetObjectType() return self.kind end
function Widget:IsForbidden() return false end
function Widget:IsProtected() return isProtected(self), self.secure end
function Widget:SetFrameStrata(s) self.strata = s end
function Widget:GetFrameStrata() return self.strata or "MEDIUM" end
function Widget:SetFrameLevel(l) self.level = l end
function Widget:GetFrameLevel() return self.level end
function Widget:SetToplevel() end
function Widget:SetClampedToScreen() guard(self, "SetClampedToScreen") end
function Widget:SetMovable(v) self.movable = v end
function Widget:SetResizable(v) self.resizable = v end
function Widget:SetResizeBounds(minW, minH, maxW, maxH) self.resizeBounds = { minW, minH, maxW, maxH } end
function Widget:StartMoving() guard(self, "StartMoving") self.moving = true end
function Widget:StartSizing() guard(self, "StartSizing") self.sizing = true end
function Widget:StopMovingOrSizing() guard(self, "StopMovingOrSizing") self.moving, self.sizing = false, false end
function Widget:RegisterForDrag(...) self.drag = { ... } end
function Widget:EnableMouse(v) self.mouse = v end
function Widget:EnableMouseWheel(v) self.mouseWheel = v end
function Widget:IsMouseOver() return false end

-- Scripts and events
function Widget:SetScript(name, fn) self.scripts[name] = fn end
function Widget:GetScript(name) return self.scripts[name] end
function Widget:HookScript(name, fn)
    local prev = self.scripts[name]
    self.scripts[name] = function(...)
        if prev then prev(...) end
        return fn(...)
    end
end
-- Unknown names throw, refused ones return false (both measured, section 3).
function Widget:RegisterEvent(event)
    if WoW.badEvents[event] then error("Attempt to register unknown event \"" .. event .. "\"") end
    if WoW.refusedEvents[event] then return false end
    WoW.events[self] = WoW.events[self] or {}
    WoW.events[self][event] = true
    return true
end
function Widget:UnregisterEvent(event) if WoW.events[self] then WoW.events[self][event] = nil end end
function Widget:UnregisterAllEvents() WoW.events[self] = nil end
function Widget:IsEventRegistered(event) return WoW.events[self] and WoW.events[self][event] or false end

-- Secure attributes: blocked on a protected frame in combat. Raising here
-- (rather than silently dropping the write) makes such a call fail the suite.
function Widget:SetAttribute(k, v) guard(self, "SetAttribute") self.attrs[k] = v end
function Widget:GetAttribute(k) return self.attrs[k] end
function Widget:RegisterForClicks(...) guard(self, "RegisterForClicks") self.clicks = { ... } end

-- Buttons
-- Protected (SimpleButtonAPIDocumentation: IsProtectedFunction).
function Widget:Enable() guard(self, "Enable") self.enabled = true end
function Widget:Disable() guard(self, "Disable") self.enabled = false end
function Widget:SetEnabled(v) guard(self, "SetEnabled") self.enabled = v and true or false end
function Widget:IsEnabled() return self.enabled end
function Widget:SetNormalTexture(t) self.normalTexture = t end
function Widget:SetPushedTexture(t) self.pushedTexture = t end
function Widget:SetHighlightTexture(t) self.highlightTexture = t end
function Widget:GetNormalTexture() self.normalTex = self.normalTex or child(self, "Texture") return self.normalTex end
function Widget:GetHighlightTexture() self.highlightTex = self.highlightTex or child(self, "Texture") return self.highlightTex end
function Widget:Click(button, down)
    if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton", down) end
end

-- Regions
function Widget:CreateFontString(name) return child(self, "FontString", name) end
function Widget:CreateTexture(name) return child(self, "Texture", name) end
function Widget:SetText(t) self._text = t == nil and "" or tostring(t) end
function Widget:GetText() return self._text end
function Widget:SetFormattedText(fmt, ...) self._text = string.format(fmt, ...) end
function Widget:GetStringWidth() return #(self._text or "") * 6 end
function Widget:SetTextColor(...) self.textColor = { ... } end
function Widget:SetFontObject(f) self.fontObject = f end
function Widget:SetJustifyH(j) self.justifyH = j end
function Widget:SetJustifyV(j) self.justifyV = j end
function Widget:SetWordWrap(v) self.wordWrap = v end
function Widget:SetNonSpaceWrap(v) self.nonSpaceWrap = v end
function Widget:SetMaxLines(n) self.maxLines = n end
function Widget:SetTexture(t) self.texture = t end
function Widget:GetTexture() return self.texture end
function Widget:SetColorTexture(...) self.colorTexture = { ... } end
function Widget:SetTexCoord(...) self.texCoord = { ... } end
function Widget:SetVertexColor(...) self.vertexColor = { ... } end
function Widget:SetBlendMode(m) self.blendMode = m end
function Widget:SetDrawLayer(l) self.drawLayer = l end

-- Check buttons, scroll frames, sliders, status bars, edit boxes
function Widget:SetChecked(v) self.checked = v and true or false end
function Widget:GetChecked() return self.checked end
function Widget:SetScrollChild(c) self.scrollChild = c end
function Widget:GetScrollChild() return self.scrollChild end
function Widget:SetVerticalScroll(v) self.vscroll = v end
function Widget:GetVerticalScroll() return self.vscroll or 0 end
function Widget:GetVerticalScrollRange() return self.vscrollRange or 0 end
function Widget:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
function Widget:GetMinMaxValues() return self.min or 0, self.max or 0 end
function Widget:SetValue(v) self.value = v end
function Widget:GetValue() return self.value or 0 end
function Widget:SetStatusBarTexture(t) self.statusBarTexture = t end
function Widget:SetStatusBarColor(...) self.statusBarColor = { ... } end
function Widget:SetAutoFocus(v) self.autoFocus = v end
function Widget:SetMaxLetters(n) self.maxLetters = n end
function Widget:SetTextInsets() end
function Widget:SetMultiLine(v) self.multiLine = v end
function Widget:SetFocus() self.focus = true end
function Widget:ClearFocus() self.focus = false end
function Widget:HasFocus() return self.focus or false end
function Widget:HighlightText() end
function Widget:SetCursorPosition() end
function Widget:SetNumeric(v) self.numeric = v end

-- ScrollingMessageFrame-ish chat frame
function WoW.chatFrame()
    return {
        AddMessage = function(_, msg) WoW.messages[#WoW.messages + 1] = tostring(msg) end,
    }
end

function CreateFrame(kind, name, parent, template)
    local w = newWidget(kind, name, parent, template)
    if parent then parent.children[#parent.children + 1] = w end
    return w
end

------------------------------------------------------------
-- Secure click dispatch, modelled on SecureActionButton_OnClick
-- (Blizzard_FrameXML/SecureTemplates.lua, forever branch): the client calls
-- PreClick, OnClick and PostClick for EVERY registered edge; OnClick performs
-- the action only on the edge where `down == useOnKeyDown`.
------------------------------------------------------------

local BUTTON_SUFFIX = { LeftButton = "1", RightButton = "2", MiddleButton = "3" }

local function registeredFor(w, button, down)
    for _, spec in ipairs(w.clicks or {}) do
        if spec == "AnyUp" and not down then return true end
        if spec == "AnyDown" and down then return true end
        if spec == button .. (down and "Down" or "Up") then return true end
    end
    return false
end

local function modifiedAttribute(w, base, button)
    local n = BUTTON_SUFFIX[button] or ""
    for _, key in ipairs({ "*" .. base .. n, base .. n, "*" .. base .. "*", base }) do
        local v = w.attrs[key]
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

-- One mouse edge. Returns true when the secure action ran.
function WoW.clickEdge(w, button, down)
    if not w:IsVisible() or not w.enabled then return false end
    if not registeredFor(w, button, down) then return false end
    -- A script error is reported and the click carries on: an error in
    -- PreClick does not cancel the secure action that follows it.
    if w.scripts.PreClick then
        local ok, err = pcall(w.scripts.PreClick, w, button, down)
        if not ok then WoW.scriptErrors[#WoW.scriptErrors + 1] = err end
    end
    -- An ordinary button's OnClick runs on every edge it registered for; the
    -- down == useOnKeyDown filter lives inside SecureActionButton_OnClick.
    if not w.secure then
        if w.scripts.OnClick then w.scripts.OnClick(w, button, down) end
        if w.scripts.PostClick then w.scripts.PostClick(w, button, down) end
        return false
    end
    -- SecureActionButton_ShouldUseOnKeyDown: the attribute, else the CVar.
    local useOnKeyDown = w.attrs.useOnKeyDown
    if useOnKeyDown == nil then useOnKeyDown = WoW.cvars.ActionButtonUseKeyDown == "1" end
    local acted = false
    if (down and useOnKeyDown) or (not down and not useOnKeyDown) then
        local kind = w.secure and modifiedAttribute(w, "type", button)
        if kind == "macro" then
            local text = modifiedAttribute(w, "macrotext", button)
            if text and text ~= "" then runMacro(text) acted = true end
        elseif kind == "spell" then
            runSpell(w, button)
            acted = true
        end
    elseif not down and w.secure and WoW.cvars.ActionButtonUseKeyHeldSpell == "1" then
        -- Press-and-hold release resolves "typerelease", not "type".
        local kind = modifiedAttribute(w, "typerelease", button)
        if kind == "spell" then runSpell(w, button) acted = true end
    end
    if w.scripts.PostClick then w.scripts.PostClick(w, button, down) end
    return acted
end

-- A whole press: down edge, then up edge.
function WoW.click(w, button)
    button = button or "LeftButton"
    local a = WoW.clickEdge(w, button, true)
    local b = WoW.clickEdge(w, button, false)
    return a or b
end

------------------------------------------------------------
-- Blizzard frames and constants that exist at login
------------------------------------------------------------

UIParent = newWidget("Frame", "UIParent")
Minimap = newWidget("Frame", "Minimap", UIParent)
GameTooltip = newWidget("GameTooltip", "GameTooltip", UIParent)
MailFrame = newWidget("Frame", "MailFrame", UIParent)
MailFrame.shown = false
InboxFrame = newWidget("Frame", "InboxFrame", MailFrame)
OpenMailFrame = newWidget("Frame", "OpenMailFrame", UIParent)
OpenMailFrame.shown = false
SendMailFrame = newWidget("Frame", "SendMailFrame", MailFrame)
SendMailFrame.shown = false
DEFAULT_CHAT_FRAME = WoW.chatFrame()
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
    BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5, Keyring = -1 },
}

function GameTooltip_Hide() GameTooltip:Hide() end

------------------------------------------------------------
-- Game state
------------------------------------------------------------

function GetTime() return WoW.time end
function time() return WoW.epoch end
function InCombatLockdown() return WoW.inCombat end
function IsShiftKeyDown() return WoW.shift end
function GetCursorPosition() return WoW.cursor[1], WoW.cursor[2] end
function GetBuildInfo() return "1.60.1", WoW.build, "Oct 6 2026", 16001, "", " " end
function GetCVarBool(name) return WoW.cvars[name] == "1" end
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
-- Namespaces (shapes from the 70291 dump)
------------------------------------------------------------

C_Timer = {}
function C_Timer.After(delay, fn) WoW.timers[#WoW.timers + 1] = { delay = delay, fn = fn } end

C_AddOns = {}
function C_AddOns.GetAddOnMetadata(name, key)
    if name == "Shatter" and key == "Version" then return WoW.version end
    return nil
end
function C_AddOns.IsAddOnLoaded(name)
    local a = WoW.addons[name]
    return a and a.loaded or false, a and a.loaded or false
end
function C_AddOns.GetAddOnInfo(name)
    local a = WoW.addons[name]
    if not a then return nil, nil, nil, false, "MISSING" end
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
    return nil, nil, m.sender, m.subject or "", m.money or 0, 0, 30, count > 0 and count or nil,
        m.read or false, false, false, true, false
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
    Gargul = true, GL = true,
    -- The addon's own globals, nil until it creates them / SavedVariables load.
    Shatter = true, ShatterDB = true,
}

-- Blizzard-owned tables: assigning the global (even to itself) taints.
local PROTECTED_GLOBALS = {
    SlashCmdList = true, UISpecialFrames = true, StaticPopupDialogs = true,
    UIParent = true, GameTooltip = true, DEFAULT_CHAT_FRAME = true,
}

-- The only globals the addon may create.
local ALLOWED_WRITES = { Shatter = true, ShatterDB = true, SLASH_SHATTER1 = true, SLASH_SHATTER2 = true }

function WoW.allowGlobal(name) KNOWN_ABSENT[name] = true end

local strict = false
local addonLoading = false

setmetatable(_G, {
    __index = function(_, k)
        if not strict or KNOWN_ABSENT[k] then return nil end
        -- Postal's inbox checkboxes and Shatter's own scan tooltip lines.
        if type(k) == "string" and (k:match("^PostalInboxCB%d+$") or k:match("^ShatterScanTooltip")) then return nil end
        error("read of undefined global '" .. tostring(k) ..
            "' - stub it (only if the dump/source confirms it exists) or add it to " ..
            "KNOWN_ABSENT in tests/wow_stubs.lua", 2)
    end,
    __newindex = function(t, k, v)
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
    end,
})

-- Rejected writes to existing globals (rawset already holds them, so
-- __newindex never sees a reassignment): catch those by snapshot.
local function snapshotProtected()
    local snap = {}
    for k in pairs(PROTECTED_GLOBALS) do snap[k] = rawget(_G, k) end
    return snap
end

------------------------------------------------------------
-- Loading, the way the client does it
------------------------------------------------------------

local function tocFiles()
    local f = assert(io.open("Shatter.toc", "rb"), "run from the repo root")
    local text = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    local files = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local file = line:match("^%s*([^#%s].-)%s*$")
        if file then files[#files + 1] = (file:gsub("\\", "/")) end
    end
    return files
end
WoW.tocFiles = tocFiles

-- Runs every TOC file with ("Shatter", ns), hands it the SavedVariables, then
-- fires ADDON_LOADED and (unless opts.login == false) PLAYER_LOGIN.
function WoW.loadAddon(opts)
    opts = opts or {}
    local ns = {}
    local before = snapshotProtected()
    addonLoading = true
    for _, path in ipairs(tocFiles()) do
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

-- Most tests want an active enchanter with an empty backpack.
function WoW.enchanter()
    WoW.knownSpells[13262] = true
    WoW.knownSpells[7411] = true
end

strict = true
