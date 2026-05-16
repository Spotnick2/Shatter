local _, Shatter = ...

local GargulIntegration = {}
Shatter.GargulIntegration = GargulIntegration
Shatter.RegisterModule("GargulIntegration", GargulIntegration)

function GargulIntegration:IsAvailable()
    return _G.Gargul ~= nil or _G.GL ~= nil
end
