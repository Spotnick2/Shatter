local _, Shatter = ...

local Events = {}
Shatter.Events = Events
Shatter.RegisterModule("Events", Events)

local handlers = {}
local frame

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
    frame:RegisterEvent(event)
end

function Events:After(delay, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, fn)
    else
        fn()
    end
end
