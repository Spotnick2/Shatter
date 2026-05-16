local _, Shatter = ...

local AuctionData = {}
Shatter.AuctionData = AuctionData
Shatter.RegisterModule("AuctionData", AuctionData)

local function ItemString(itemID)
    return "i:" .. tostring(itemID)
end

local function ItemLink(itemID)
    local _, link = GetItemInfo(itemID)
    return link or ("item:" .. tostring(itemID))
end

function AuctionData:GetItemValue(itemID)
    if not itemID then return nil end
    if TSM_API and TSM_API.GetCustomPriceValue then
        local value = TSM_API.GetCustomPriceValue("dbmarket", ItemString(itemID))
        if value and value > 0 then return value, "TSM dbmarket" end
    end
    if AucAdvanced and AucAdvanced.API and AucAdvanced.API.GetMarketValue then
        local value = AucAdvanced.API.GetMarketValue(ItemLink(itemID))
        if value and value > 0 then return value, "Auctioneer" end
    end
    if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemLink then
        local value = Auctionator.API.v1.GetAuctionPriceByItemLink("Shatter", ItemLink(itemID))
        if value and value > 0 then return value, "Auctionator" end
    end
    return nil
end

function AuctionData:IsAvailable()
    return (TSM_API and TSM_API.GetCustomPriceValue)
        or (AucAdvanced and AucAdvanced.API and AucAdvanced.API.GetMarketValue)
        or (Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemLink)
end
