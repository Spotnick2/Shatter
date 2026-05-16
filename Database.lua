local _, Shatter = ...

local Database = {}
Shatter.Database = Database
Shatter.RegisterModule("Database", Database)

local DEFAULTS = {
    version = 2,
    settings = {
        maxQuality = 3,
        includeSoulbound = false,
        minExpectedValueCopper = 0,
        useAuctionData = false,
        minimap = { hide = false, angle = 225 },
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
            width = 540,
            height = 340,
            scale = 1.0,
        },
    },
    sessions = {
        active = nil,
        history = {},
    },
    debugLog = {},
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

function Database:Initialize()
    ShatterDB = ShatterDB or {}
    local previousVersion = tonumber(ShatterDB.version) or 0
    CopyDefaults(DEFAULTS, ShatterDB)
    if previousVersion < 2 and ShatterDB.settings and ShatterDB.settings.minimap then
        ShatterDB.settings.minimap.hide = false
    end
    ShatterDB.version = DEFAULTS.version
    if ShatterDB.settings and not ShatterDB.settings.debug then
        ShatterDB.settings.traceDebug = false
        ShatterDB.settings.simulateDisenchant = false
    end
    NormalizeQueueOrder(ShatterDB.settings)
    NormalizeWindow(ShatterDB.settings.window)
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

function Database:GetSettings()
    self:Initialize()
    return ShatterDB.settings
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
