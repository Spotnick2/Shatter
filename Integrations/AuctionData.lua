local _, Shatter = ...

local AuctionData = {}
Shatter.AuctionData = AuctionData
Shatter.RegisterModule("AuctionData", AuctionData)

local function ItemString(itemID)
    return "i:" .. tostring(itemID)
end

local function ItemLink(itemID)
    local _, link = Shatter.API.GetItemInfo(itemID)
    return link or ("item:" .. tostring(itemID))
end

-- Best effort only. Auctionator supports Forever; TSM refuses to load on
-- this client (WOW_PROJECT_ID 18), and Auctioneer is unverified. A third-party
-- API that errors is treated as having no price, never as a Shatter failure.
local function Try(fn, ...)
    local ok, value = pcall(fn, ...)
    if ok and type(value) == "number" and value > 0 then return value end
    return nil
end

function AuctionData:GetItemValue(itemID)
    if not itemID then return nil end
    if TSM_API and TSM_API.GetCustomPriceValue then
        local value = Try(TSM_API.GetCustomPriceValue, "dbmarket", ItemString(itemID))
        if value then return value, "TSM dbmarket" end
    end
    if AucAdvanced and AucAdvanced.API and AucAdvanced.API.GetMarketValue then
        local value = Try(AucAdvanced.API.GetMarketValue, ItemLink(itemID))
        if value then return value, "Auctioneer" end
    end
    if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemLink then
        local value = Try(Auctionator.API.v1.GetAuctionPriceByItemLink, "Shatter", ItemLink(itemID))
        if value then return value, "Auctionator" end
    end
    return nil
end

function AuctionData:IsAvailable()
    return (TSM_API and TSM_API.GetCustomPriceValue)
        or (AucAdvanced and AucAdvanced.API and AucAdvanced.API.GetMarketValue)
        or (Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemLink)
end
