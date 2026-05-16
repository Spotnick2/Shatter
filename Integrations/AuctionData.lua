local _, Shatter = ...

local AuctionData = {}
Shatter.AuctionData = AuctionData
Shatter.RegisterModule("AuctionData", AuctionData)

function AuctionData:GetItemValue()
    return nil
end

function AuctionData:IsAvailable()
    return false
end
