local _, Shatter = ...

local RaidMode = {}
Shatter.RaidMode = RaidMode
Shatter.RegisterModule("RaidMode", RaidMode)

function RaidMode:Initialize()
    -- Planned for Phase 4. Kept as a module so trade/session code has a home.
end

function RaidMode:IsAvailable()
    return false
end
