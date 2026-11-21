local _, Shatter = ...

local Database = {}
Shatter.Database = Database
Shatter.RegisterModule("Database", Database)

local DEFAULTS = {
    version = 2,
    settings = {
        maxQuality = 3,
        includeSoulbound = false,
        -- Keep possible upgrades (#37): Solo leaves out items at or above
        -- keepItemLevelAtOrAbove (optional, a whole item level) while on.
        keepItemLevel = false,
        -- Value rules (#38), Solo only. onlyAboveVendorPrice: an item is
        -- eligible only if its expected materials are worth more than its
        -- vendor price. keepAuctionValue: an item whose own auction value is
        -- at or above keepAuctionValueAtOrAboveCopper (optional) is kept.
        onlyAboveVendorPrice = false,
        keepAuctionValue = false,
        minExpectedValueCopper = 0,
        useAuctionData = false,
        minimap = { hide = false, angle = 225 },
        -- The look (Skin.lua): "clear" or "smoked" glass, or "flat".
        skin = "forever",
        -- Item tooltips (Tooltip.lua): "always", "modifier" (Shift, Alt or
        -- Ctrl held) or "never".
        tooltip = "always",
        debug = false,
        traceDebug = false,
        simulateDisenchant = false,
        ignoredItems = {},
        queueOrder = {
            solo = "BAG_SLOT",
            mail = "FIFO",
            raid = "FIFO",
        },
        window = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = 0,
            width = 660,
            height = 440,
            scale = 1.0,
        },
        mail = {
            launchPanelVisible = true,
        },
    },
    sessions = {
        active = nil,
        activeMail = nil,
        history = {},
        mailHistory = {},
        byCharacter = {},
    },
    debugLog = {},
    characterSettings = {},
    profileScopeByCharacter = {},
}

local function Clamp(value, minValue, maxValue)
    value = tonumber(value)
    if not value then return minValue end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function WindowDefaults()
    local window = Shatter.Constants and Shatter.Constants.WINDOW or {}
    return {
        width = window.DEFAULT_WIDTH or 620,
        height = window.DEFAULT_HEIGHT or 380,
        minWidth = window.MIN_WIDTH or 560,
        minHeight = window.MIN_HEIGHT or 340,
        maxWidth = window.MAX_WIDTH or 900,
        maxHeight = window.MAX_HEIGHT or 650,
        minScale = window.MIN_SCALE or 0.75,
        maxScale = window.MAX_SCALE or 1.5,
    }
end

local function NormalizeWindow(window)
    local defaults = WindowDefaults()
    window.point = window.point or "CENTER"
    window.relativePoint = window.relativePoint or "CENTER"
    window.x = tonumber(window.x) or 0
    window.y = tonumber(window.y) or 0
    window.width = Clamp(window.width or defaults.width, defaults.minWidth, defaults.maxWidth)
    window.height = Clamp(window.height or defaults.height, defaults.minHeight, defaults.maxHeight)
    window.scale = Clamp(window.scale or 1, defaults.minScale, defaults.maxScale)
end

local function NormalizeQueueOrder(settings)
    local constants = Shatter.Constants and Shatter.Constants.QUEUE_ORDER or {}
    settings.queueOrder = type(settings.queueOrder) == "table" and settings.queueOrder or {}
    local valid = {
        [constants.BAG_SLOT or "BAG_SLOT"] = true,
        [constants.FIFO or "FIFO"] = true,
        [constants.LIFO or "LIFO"] = true,
    }
    if not valid[settings.queueOrder.solo] then settings.queueOrder.solo = constants.BAG_SLOT or "BAG_SLOT" end
    if not valid[settings.queueOrder.mail] then settings.queueOrder.mail = constants.FIFO or "FIFO" end
    if not valid[settings.queueOrder.raid] then settings.queueOrder.raid = constants.FIFO or "FIFO" end
end

local function CopyDefaults(defaults, target)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            CopyDefaults(value, target[key])
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function CopyTable(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            copy[key] = CopyTable(value)
        else
            copy[key] = value
        end
    end
    return copy
end

-- A whole item level from 1 to MAX_KEEP_ITEM_LEVEL, or nil.
function Database.NormalizeItemLevel(value)
    value = tonumber(value)
    if not value then return nil end
    value = math.floor(value)
    if value < 1 or value > Shatter.Constants.MAX_KEEP_ITEM_LEVEL then return nil end
    return value
end

-- A whole number of gold from 1 to MAX_KEEP_AUCTION_GOLD, in copper, or nil.
function Database.NormalizeAuctionValue(copper)
    copper = tonumber(copper)
    if not copper then return nil end
    local gold = math.floor(copper / 10000)
    if gold < 1 or gold > Shatter.Constants.MAX_KEEP_AUCTION_GOLD then return nil end
    return gold * 10000
end

local function NormalizeSettings(settings)
    settings = settings or {}
    CopyDefaults(DEFAULTS.settings, settings)
    if not settings.debug then
        settings.traceDebug = false
        settings.simulateDisenchant = false
    end
    NormalizeQueueOrder(settings)
    NormalizeWindow(settings.window)
    settings.keepItemLevel = settings.keepItemLevel == true
    settings.keepItemLevelAtOrAbove = Database.NormalizeItemLevel(settings.keepItemLevelAtOrAbove)
    settings.onlyAboveVendorPrice = settings.onlyAboveVendorPrice == true
    settings.keepAuctionValue = settings.keepAuctionValue == true
    settings.keepAuctionValueAtOrAboveCopper = Database.NormalizeAuctionValue(settings.keepAuctionValueAtOrAboveCopper)
    if not Shatter.Skin.IsValid(settings.skin) then
        settings.skin = DEFAULTS.settings.skin
    end
    if not Shatter.Constants.TOOLTIP_MODES[settings.tooltip] then
        settings.tooltip = DEFAULTS.settings.tooltip
    end
    return settings
end

-- The logged-in character's full name, "First Surname". UnitName("player")
-- gives it whole or split into first name and surname (porting guide,
-- "Characters have surnames"); the parts are joined the way Blizzard's own
-- Forever NameUtil.FormatUnitNameForDisplay joins them.
local function PlayerFullName()
    if not UnitName then return nil end
    local name, surname = UnitName("player")
    if type(name) ~= "string" or name == "" then return nil end
    if type(surname) == "string" and surname ~= "" then
        name = name .. " " .. surname
    end
    return name
end

-- Keys before #73 were "<name>-<realm>": the full name, or the first name
-- alone when the client split UnitName (70374 and later). From the
-- 2026-11-20 hotfix, which hides the realm (GetRealmName() returns ""), they
-- were "<name>-Realm". A name holds no "-", so it is what comes before one.
local function NameOfOldKey(key)
    return type(key) == "string" and key:match("^([^-]+)%-") or nil
end

-- The old keys in `store` written under this character's full name, and
-- under its first name alone (none when the name has no surname). Sorted, so
-- every pass takes them in the same order.
function Database.OldKeysIn(store, fullName)
    local full, first = {}, {}
    if type(store) ~= "table" or type(fullName) ~= "string" then return full, first end
    local firstName = fullName:match("^(%S+)")
    for key in pairs(store) do
        local name = NameOfOldKey(key)
        if name == fullName then
            full[#full + 1] = key
        elseif name == firstName and firstName ~= fullName then
            first[#first + 1] = key
        end
    end
    table.sort(full)
    table.sort(first)
    return full, first
end

-- Of several old keys of this character in one table, the one to take: the
-- only one, else the hotfix's "<name>-Realm" (written once the others could
-- no longer be read, so the latest choice), else none.
local function PickOldKey(keys)
    if #keys == 1 then return keys[1] end
    local latest
    for _, key in ipairs(keys) do
        if key:match("^[^-]+%-Realm$") then
            if latest then return nil end
            latest = key
        end
    end
    return latest
end

-- Moves one of `keys` in `store` to the new key, unless that has one.
local function Adopt(store, fullName, keys)
    if type(store) ~= "table" or store[fullName] ~= nil then return end
    local present = {}
    for _, key in ipairs(keys) do
        if store[key] ~= nil then present[#present + 1] = key end
    end
    local old = PickOldKey(present)
    if old then store[fullName], store[old] = store[old], nil end
end

-- Once per character and session: the settings and profile choice saved
-- under its full name and an old realm. Names are unique across the region,
-- so those are this character's. Mail buckets are MailSession's (adopted in
-- its Initialize, after the account-wide import), and keys under the first
-- name alone wait for the player's answer (UI/OldKeyPrompt.lua).
local adopted = {}
local function AdoptFullNameKeys(fullName)
    if adopted[fullName] or type(ShatterDB) ~= "table" then return end
    adopted[fullName] = true
    for _, store in ipairs({ ShatterDB.characterSettings, ShatterDB.profileScopeByCharacter }) do
        Adopt(store, fullName, (Database.OldKeysIn(store, fullName)))
    end
end

-- The full name, or nil while the client has none yet.
function Database:GetFullName()
    return PlayerFullName()
end

-- The key of this character's data in ShatterDB: its full name. No realm:
-- Forever hides it since the 2026-11-20 hotfix, and names are unique across
-- the region.
function Database:GetCharacterKey()
    local name = PlayerFullName()
    if not name then return "Unknown" end
    AdoptFullNameKeys(name)
    return name
end

local function OldKeyStores()
    local sessions = type(ShatterDB.sessions) == "table" and ShatterDB.sessions or {}
    return { ShatterDB.characterSettings, ShatterDB.profileScopeByCharacter, sessions.byCharacter }
end

-- Old keys under this character's first name alone that it hasn't answered
-- for. Another character may share the first name, so only the player can
-- say whose they are.
function Database:GetFirstNameKeys()
    local fullName = PlayerFullName()
    if not fullName or type(ShatterDB) ~= "table" then return {} end
    local answers = type(ShatterDB.oldKeyAnswers) == "table" and ShatterDB.oldKeyAnswers[fullName]
    answers = type(answers) == "table" and answers or {}
    local seen, keys = {}, {}
    for _, store in ipairs(OldKeyStores()) do
        local _, first = Database.OldKeysIn(store, fullName)
        for _, key in ipairs(first) do
            if not seen[key] and answers[key] == nil then
                seen[key] = true
                keys[#keys + 1] = key
            end
        end
    end
    table.sort(keys)
    return keys
end

-- The player's answer for `keys`, kept so they are asked once. Mine: their
-- settings, profile choice and mail sessions move to this character.
function Database:AnswerFirstNameKeys(keys, mine)
    local fullName = PlayerFullName()
    if not fullName or type(ShatterDB) ~= "table" then return end
    ShatterDB.oldKeyAnswers = type(ShatterDB.oldKeyAnswers) == "table" and ShatterDB.oldKeyAnswers or {}
    local answers = type(ShatterDB.oldKeyAnswers[fullName]) == "table" and ShatterDB.oldKeyAnswers[fullName] or {}
    ShatterDB.oldKeyAnswers[fullName] = answers
    for _, key in ipairs(keys) do answers[key] = mine and "mine" or "not mine" end
    if not mine then return end
    Adopt(ShatterDB.characterSettings, fullName, keys)
    Adopt(ShatterDB.profileScopeByCharacter, fullName, keys)
    if Shatter.MailSession then Shatter.MailSession:AdoptBuckets(keys) end
end

function Database:Initialize()
    ShatterDB = ShatterDB or {}
    local previousVersion = tonumber(ShatterDB.version) or 0
    CopyDefaults(DEFAULTS, ShatterDB)
    if previousVersion < 2 and ShatterDB.settings and ShatterDB.settings.minimap then
        ShatterDB.settings.minimap.hide = false
    end
    ShatterDB.version = DEFAULTS.version
    ShatterDB.characterSettings = type(ShatterDB.characterSettings) == "table" and ShatterDB.characterSettings or {}
    ShatterDB.profileScopeByCharacter = type(ShatterDB.profileScopeByCharacter) == "table" and ShatterDB.profileScopeByCharacter or {}
    ShatterDB.sessions = type(ShatterDB.sessions) == "table" and ShatterDB.sessions or {}
    ShatterDB.sessions.history = type(ShatterDB.sessions.history) == "table" and ShatterDB.sessions.history or {}
    ShatterDB.sessions.mailHistory = type(ShatterDB.sessions.mailHistory) == "table" and ShatterDB.sessions.mailHistory or {}
    ShatterDB.sessions.byCharacter = type(ShatterDB.sessions.byCharacter) == "table" and ShatterDB.sessions.byCharacter or {}
    -- The answers to OldKeyPrompt, by character; absent until the first.
    if ShatterDB.oldKeyAnswers ~= nil and type(ShatterDB.oldKeyAnswers) ~= "table" then
        ShatterDB.oldKeyAnswers = nil
    end
    NormalizeSettings(ShatterDB.settings)
    for _, settings in pairs(ShatterDB.characterSettings) do
        if type(settings) == "table" then
            NormalizeSettings(settings)
        end
    end
end

-- Persistence canary, called once per session from Core's module setup
-- (Initialize itself re-runs from every getter). One entry per load, never defaulted: if SavedVariables
-- stop loading back (as on Forever builds through 69977), the list stays at
-- one entry however often the game is started. Read it after a FULL client
-- exit; /reload hands the table back in memory and proves nothing.
function Database:StampLoad()
    local stamps = type(ShatterDB.loadStamps) == "table" and ShatterDB.loadStamps or {}
    local version, build = GetBuildInfo()
    stamps[#stamps + 1] = { time = time(), build = tostring(version) .. "." .. tostring(build) }
    local max = Shatter.Constants and Shatter.Constants.MAX_LOAD_STAMPS or 30
    while #stamps > max do table.remove(stamps, 1) end
    ShatterDB.loadStamps = stamps
end

function Database:GetQueueOrder(mode)
    local settings = self:GetSettings()
    NormalizeQueueOrder(settings)
    mode = mode or "solo"
    return settings.queueOrder[mode] or (Shatter.Constants and Shatter.Constants.QUEUE_ORDER.BAG_SLOT) or "BAG_SLOT"
end

function Database:SetQueueOrder(mode, order)
    local settings = self:GetSettings()
    NormalizeQueueOrder(settings)
    mode = mode or "solo"
    settings.queueOrder[mode] = order
    NormalizeQueueOrder(settings)
end

function Database:Get()
    ShatterDB = ShatterDB or {}
    return ShatterDB
end

function Database:GetProfileScope()
    self:Initialize()
    local scopes = ShatterDB.profileScopeByCharacter
    local key = self:GetCharacterKey()
    local scope = scopes[key]
    local constants = Shatter.Constants and Shatter.Constants.PROFILE_SCOPE or {}
    if scope ~= (constants.PERSONAL or "PERSONAL") then
        scope = constants.GLOBAL or "GLOBAL"
    end
    return scope
end

function Database:GetGlobalSettings()
    self:Initialize()
    return NormalizeSettings(ShatterDB.settings)
end

function Database:GetPersonalSettings()
    self:Initialize()
    local key = self:GetCharacterKey()
    ShatterDB.characterSettings = type(ShatterDB.characterSettings) == "table" and ShatterDB.characterSettings or {}
    if type(ShatterDB.characterSettings[key]) ~= "table" then
        ShatterDB.characterSettings[key] = CopyTable(self:GetGlobalSettings())
    end
    return NormalizeSettings(ShatterDB.characterSettings[key])
end

function Database:GetSettings()
    self:Initialize()
    local constants = Shatter.Constants and Shatter.Constants.PROFILE_SCOPE or {}
    if self:GetProfileScope() == (constants.PERSONAL or "PERSONAL") then
        return self:GetPersonalSettings()
    end
    return self:GetGlobalSettings()
end

function Database:SetProfileScope(scope)
    self:Initialize()
    local constants = Shatter.Constants and Shatter.Constants.PROFILE_SCOPE or {}
    local global = constants.GLOBAL or "GLOBAL"
    local personal = constants.PERSONAL or "PERSONAL"
    if scope ~= personal then scope = global end
    local key = self:GetCharacterKey()
    ShatterDB.profileScopeByCharacter[key] = scope
    if scope == personal then
        self:GetPersonalSettings()
    end
    return scope
end

-- Measured disenchant results, account-wide (see DisenchantTables). Absent
-- until the first real disenchant is recorded; `create` makes it.
function Database:GetYields(create)
    ShatterDB = ShatterDB or {}
    if type(ShatterDB.yields) ~= "table" then
        if not create then return nil end
        ShatterDB.yields = {}
    end
    return ShatterDB.yields
end

function Database:ResetYields()
    ShatterDB = ShatterDB or {}
    ShatterDB.yields = nil
end

-- Learning mode's raw disenchant log (#40), account-wide:
-- { enabled = bool, entries = { ... } }. Absent until it is first turned on;
-- `create` makes it.
function Database:GetYieldLog(create)
    ShatterDB = ShatterDB or {}
    local log = ShatterDB.yieldLog
    if type(log) ~= "table" then
        if not create then return nil end
        log = {}
        ShatterDB.yieldLog = log
    end
    log.enabled = log.enabled == true
    if type(log.entries) ~= "table" then log.entries = {} end
    return log
end

-- The item level Solo keeps from (#37): nil while the setting is off or has
-- no level.
function Database:GetKeepItemLevel()
    local settings = self:GetSettings()
    if not settings.keepItemLevel then return nil end
    return Database.NormalizeItemLevel(settings.keepItemLevelAtOrAbove)
end

-- The auction value at or above which items are kept (#38), in copper, or
-- nil when the rule is off or has no amount.
function Database:GetKeepAuctionValue()
    local settings = self:GetSettings()
    if not settings.keepAuctionValue then return nil end
    return Database.NormalizeAuctionValue(settings.keepAuctionValueAtOrAboveCopper)
end

function Database:IsIgnored(itemID)
    itemID = tonumber(itemID)
    if not itemID then return false end
    local settings = self:GetSettings()
    return settings.ignoredItems[itemID] == true
end

function Database:SetIgnored(itemID, ignored)
    itemID = tonumber(itemID)
    if not itemID then return end
    local settings = self:GetSettings()
    settings.ignoredItems[itemID] = ignored and true or nil
end

-- Every ignored itemID, ascending (#4). The saved shape stays [itemID] = true.
function Database:GetIgnoredItems()
    local list = {}
    for itemID, ignored in pairs(self:GetSettings().ignoredItems) do
        itemID = tonumber(itemID)
        if itemID and ignored == true then list[#list + 1] = itemID end
    end
    table.sort(list)
    return list
end

-- Forgets every ignored item; returns how many there were.
function Database:ClearIgnored()
    local ignoredItems = self:GetSettings().ignoredItems
    local count = 0
    for itemID in pairs(ignoredItems) do
        ignoredItems[itemID] = nil
        count = count + 1
    end
    return count
end

function Database:SaveWindow(frame)
    if not frame then return end
    local settings = self:GetSettings()
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    settings.window.point = point or "CENTER"
    settings.window.relativePoint = relativePoint or "CENTER"
    settings.window.x = x or 0
    settings.window.y = y or 0
    settings.window.width = frame:GetWidth() or settings.window.width
    settings.window.height = frame:GetHeight() or settings.window.height
    settings.window.scale = frame:GetScale() or 1
    NormalizeWindow(settings.window)
end

function Database:ApplyWindow(frame)
    if not frame then return end
    local window = self:GetSettings().window
    NormalizeWindow(window)
    frame:SetSize(window.width, window.height)
    frame:ClearAllPoints()
    frame:SetPoint(window.point or "CENTER", UIParent, window.relativePoint or "CENTER", window.x or 0, window.y or 0)
    frame:SetScale(window.scale or 1)
end

function Database:ResetWindow()
    local settings = self:GetSettings()
    settings.window.point = "CENTER"
    settings.window.relativePoint = "CENTER"
    settings.window.x = 0
    settings.window.y = 0
    settings.window.width = DEFAULTS.settings.window.width
    settings.window.height = DEFAULTS.settings.window.height
    settings.window.scale = 1
    NormalizeWindow(settings.window)
    if Shatter.MainFrame then
        Shatter.MainFrame:ApplyPosition()
    end
end
