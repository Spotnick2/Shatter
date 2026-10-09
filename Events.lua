local _, Shatter = ...

local Events = {}
Shatter.Events = Events
Shatter.RegisterModule("Events", Events)

local handlers = {}
local frame
local failed = {}

-- Events whose loss would leave a destructive action without its result
-- tracking. If one cannot be registered, Shatter Next refuses to arm.
Events.REQUIRED = {
    UNIT_SPELLCAST_SUCCEEDED = true, UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_FAILED_QUIET = true,
    LOOT_OPENED = true, LOOT_CLOSED = true, BAG_UPDATE_DELAYED = true,
}

function Events:Initialize()
    if frame then return end
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, ...)
        local list = handlers[event]
        if not list then return end
        for _, handler in ipairs(list) do
            if type(handler.fn) == "function" then
                handler.fn(handler.owner, event, ...)
            end
        end
    end)
end

function Events:Register(event, owner, fn)
    if not event or type(fn) ~= "function" then return end
    self:Initialize()
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], { owner = owner, fn = fn })
    if #handlers[event] > 1 or failed[event] then return end
    -- On this client an unknown event name throws, and a refusal returns
    -- false without throwing: both are failures, and both are reported.
    local ok, registered = pcall(frame.RegisterEvent, frame, event)
    if not ok or registered == false then
        failed[event] = ok and "refused" or tostring(registered)
        Shatter.Print(string.format("|cffff4444Could not register %s (%s).|r%s", event, failed[event],
            Events.REQUIRED[event] and " Shatter Next is disabled until this is fixed." or ""))
    end
end

-- The events that could not be registered: { [event] = reason }.
function Events:GetFailed()
    return failed
end

-- False when a required event is missing: destructive actions must not arm.
function Events:IsHealthy()
    for event in pairs(failed) do
        if Events.REQUIRED[event] then return false end
    end
    return true
end

function Events:After(delay, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, fn)
    else
        fn()
    end
end
