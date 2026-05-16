local _, Shatter = ...

local MailMode = {}
Shatter.MailMode = MailMode
Shatter.RegisterModule("MailMode", MailMode)

function MailMode:Initialize()
    -- Planned for Phase 3. Kept as a module so the architecture is stable early.
end

function MailMode:IsAvailable()
    return false
end
