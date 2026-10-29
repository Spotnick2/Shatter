local _, Shatter = ...

-- What an item disenchants into, on its tooltip wherever it appears: bags,
-- bank, loot, chat links, vendors, the auction house (#3).
--
-- The Mainline hook: TooltipDataProcessor.AddTooltipPostCall(Item, fn), which
-- the client runs as fn(tooltip, tooltipData) after the tooltip has added its
-- own lines, on every rebuild (Blizzard_SharedXMLGame/Tooltip/
-- TooltipDataHandler.lua:199; tooltipData.id is the itemID, TooltipUtil.lua:9).
-- A rebuild clears the lines first, so they're never added twice. Classic's
-- OnTooltipSetItem isn't used. The post call can't be removed, so it is
-- registered once, at the first activation, and checks Shatter.isActive.
--
-- The lines are added at once or not at all: an uncached material shows as
-- "Item <id>" and is requested, never added later to a tooltip that may have
-- moved on. The estimate is the queue's own (DisenchantTables:GetExpected,
-- measured odds included), kept a few seconds per item, since the hook runs
-- on every refresh. Forbidden tooltips are left alone. The required-skill
-- line waits for #5.
--
-- Shown for items Disenchant takes at all (green or better weapons and
-- armor, not denylisted) whatever the queue's filters, except an ignored item.
--
-- "With Shift, Alt or Ctrl" has to follow a key pressed or released while the
-- tooltip is open. A bag button rebuilds its tooltip every TOOLTIP_UPDATE_TIME
-- on its own (owner.UpdateTooltip, GameTooltip.lua:456), but a chat link's
-- ItemRefTooltip only rebuilds when asked (ItemRef.lua:351). So on
-- MODIFIER_STATE_CHANGED an open tooltip still showing the same item, whose
-- owner doesn't refresh it, is rebuilt with RefreshData, the client's own
-- rebuild (GameTooltip.lua:958). Not RefreshDataNextUpdate: it sets
-- updateTooltipTimer, which turns on ItemRefTooltip's comparison timer.

local Tooltip = {}
Shatter.Tooltip = Tooltip
Shatter.RegisterModule("Tooltip", Tooltip)

local CACHE_SECONDS = 10
local cache = {}        -- itemID -> { at, estimate (false: none) }
local registered = false
-- In modifier mode: tooltip -> { itemID, lines (shown?) }, for the rebuild.
local modifierShown = setmetatable({}, { __mode = "k" })

-- The item's estimate, or nil when the tooltip shouldn't show one.
local function EstimateFor(itemID)
    local hit = cache[itemID]
    local now = GetTime()
    if hit and now - hit.at < CACHE_SECONDS then return hit.estimate or nil end
    local estimate = false
    local name, link, quality, itemLevel, _, _, _, _, equipLoc, _, _, classID, subclassID = Shatter.API.GetItemInfo(itemID)
    -- Uncached: the tooltip shows it again once its data is in.
    if not name then return nil end
    local item = { itemID = itemID, itemLink = link, quality = quality, itemLevel = itemLevel,
                   equipLoc = equipLoc, classID = classID, subclassID = subclassID }
    if quality and quality >= Shatter.Constants.QUALITY_UNCOMMON
        and not Shatter.Constants.NON_DISENCHANTABLE[itemID]
        and Shatter.ItemScanner:IsDisenchantableKind(item) then
        local e = Shatter.DisenchantTables:GetExpected(item)
        if e and e.materials and #e.materials > 0 then estimate = e end
    end
    cache[itemID] = { at = now, estimate = estimate }
    return estimate or nil
end

-- A material's label: icon and quality-coloured name, or "Item <id>" until
-- the client has it.
local function MaterialLabel(itemID)
    local name, _, quality = Shatter.API.GetItemInfo(itemID)
    local _, _, _, _, icon = Shatter.API.GetItemInfoInstant(itemID)
    local prefix = icon and ("|T" .. icon .. ":0|t ") or ""
    if not name then
        C_Item.RequestLoadItemDataByID(itemID)
        return prefix .. "Item " .. itemID, 0.82, 0.82, 0.82
    end
    local r, g, b = Shatter.GetQualityColor(quality)
    return prefix .. name, r, g, b
end

local function Amount(entry)
    local low, high = entry.minAmount or 1, entry.maxAmount or entry.minAmount or 1
    if low == high then return "x" .. low end
    return string.format("x%d-%d", low, high)
end

-- The lines, added to `tooltip`.
function Tooltip:AddLines(tooltip, estimate)
    local accent = Shatter.C.ACCENT
    local note = estimate.measured and string.format(" (measured, %d)", estimate.samples or 0)
        or estimate.uncertain and " (estimate)" or ""
    tooltip:AddLine("Disenchants into" .. note, accent[1], accent[2], accent[3])
    local materials = {}
    for _, entry in ipairs(estimate.materials) do materials[#materials + 1] = entry end
    table.sort(materials, function(a, b)
        if (a.chance or 0) ~= (b.chance or 0) then return (a.chance or 0) > (b.chance or 0) end
        return a.itemID < b.itemID
    end)
    for _, entry in ipairs(materials) do
        local label, r, g, b = MaterialLabel(entry.itemID)
        local chance = math.floor((entry.chance or 0) * 100 + 0.5)
        tooltip:AddDoubleLine("  " .. label, string.format("%d%%  %s", chance, Amount(entry)), r, g, b, 1, 1, 1)
    end
    if estimate.expectedValueCopper then
        tooltip:AddDoubleLine("  Expected value", Shatter.DisenchantTables:FormatMoney(estimate.expectedValueCopper),
            0.82, 0.82, 0.82, 1, 1, 1)
    end
end

local function OnItemTooltip(tooltip, data)
    if not Shatter.isActive or not tooltip or type(data) ~= "table" then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    modifierShown[tooltip] = nil
    local itemID = tonumber(data.id)
    local mode = Shatter.Database:GetSettings().tooltip
    if not itemID or mode == "never" or Shatter.Database:IsIgnored(itemID) then return end
    local estimate = EstimateFor(itemID)
    if not estimate then return end
    local wanted = mode ~= "modifier" or IsModifierKeyDown() == true
    if mode == "modifier" then modifierShown[tooltip] = { itemID = itemID, lines = wanted } end
    if wanted then Tooltip:AddLines(tooltip, estimate) end
end

-- A modifier pressed or released: rebuild the open tooltips that now show
-- the wrong thing and won't rebuild by themselves.
local function OnModifierChanged()
    if not Shatter.isActive or Shatter.Database:GetSettings().tooltip ~= "modifier" then return end
    local wanted = IsModifierKeyDown() == true
    local stale = {}
    for tooltip, state in pairs(modifierShown) do
        if state.lines ~= wanted and tooltip:IsShown() and not (tooltip.IsForbidden and tooltip:IsForbidden())
            and tooltip.RefreshData and tooltip.GetPrimaryTooltipData then
            local owner = tooltip:GetOwner()
            local data = tooltip:GetPrimaryTooltipData()
            if not (owner and owner.UpdateTooltip) and type(data) == "table"
                and data.type == Enum.TooltipDataType.Item and tonumber(data.id) == state.itemID then
                stale[#stale + 1] = tooltip
            end
        end
    end
    -- Rebuilt after the loop: the rebuild rewrites modifierShown.
    for _, tooltip in ipairs(stale) do tooltip:RefreshData() end
end

-- Once, at the first activation. A client without the processor gets nothing.
function Tooltip:Initialize()
    if registered then return end
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType) then
        return
    end
    registered = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        local ok, err = pcall(OnItemTooltip, tooltip, data)
        if not ok and Shatter.Debug then Shatter.Debug:Log("debug", "Tooltip failed: %s", tostring(err)) end
    end)
    local events = CreateFrame("Frame")
    events:RegisterEvent("MODIFIER_STATE_CHANGED")
    events:SetScript("OnEvent", function()
        local ok, err = pcall(OnModifierChanged)
        if not ok and Shatter.Debug then Shatter.Debug:Log("debug", "Tooltip refresh failed: %s", tostring(err)) end
    end)
end

-- Forget cached estimates (measured odds or prices changed).
function Tooltip:Reset() cache = {} end

-- The one setter, for Settings and /shatter tooltip.
function Tooltip:SetMode(mode)
    if not Shatter.Constants.TOOLTIP_MODES[mode] then return false end
    Shatter.Database:GetSettings().tooltip = mode
    return true
end
