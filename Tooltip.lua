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

local Tooltip = {}
Shatter.Tooltip = Tooltip
Shatter.RegisterModule("Tooltip", Tooltip)

local CACHE_SECONDS = 10
local cache = {}        -- itemID -> { at, estimate (false: none) }
local registered = false

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

-- Whether the setting lets the lines show right now.
local function Wanted()
    local mode = Shatter.Database:GetSettings().tooltip
    if mode == "never" then return false end
    if mode == "modifier" then return IsModifierKeyDown() == true end
    return true
end

local function OnItemTooltip(tooltip, data)
    if not Shatter.isActive or not tooltip or type(data) ~= "table" then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local itemID = tonumber(data.id)
    if not itemID or not Wanted() or Shatter.Database:IsIgnored(itemID) then return end
    local estimate = EstimateFor(itemID)
    if estimate then Tooltip:AddLines(tooltip, estimate) end
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
end

-- Forget cached estimates (measured odds or prices changed).
function Tooltip:Reset() cache = {} end

-- The one setter, for Settings and /shatter tooltip.
function Tooltip:SetMode(mode)
    if not Shatter.Constants.TOOLTIP_MODES[mode] then return false end
    Shatter.Database:GetSettings().tooltip = mode
    return true
end
