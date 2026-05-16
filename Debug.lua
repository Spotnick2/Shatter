local _, Shatter = ...

local Debug = {}
Shatter.Debug = Debug
Shatter.RegisterModule("Debug", Debug)

local MAX_LOG = 200

function Debug:Initialize()
    local db = Shatter.Database and Shatter.Database:Get()
    if db and type(db.debugLog) ~= "table" then
        db.debugLog = {}
    end
end

function Debug:Log(level, message, ...)
    level = level or "debug"
    if select("#", ...) > 0 then
        message = string.format(tostring(message), ...)
    end

    local settings = Shatter.Database and Shatter.Database:GetSettings()
    if level == "trace" and settings and not settings.traceDebug then
        return
    end
    if level == "debug" and settings and not settings.debug then
        return
    end

    local line = string.format("[%s] %s", level, tostring(message))
    local db = Shatter.Database and Shatter.Database:Get()
    if db then
        db.debugLog = db.debugLog or {}
        table.insert(db.debugLog, { time = time and time() or 0, level = level, message = tostring(message) })
        while #db.debugLog > MAX_LOG do
            table.remove(db.debugLog, 1)
        end
    end

    if level == "warn" or level == "error" or (settings and settings.debug and level ~= "trace") or (settings and settings.traceDebug and level == "trace") then
        Shatter.Print(line)
    end
end

function Debug:Trace(message, ...)
    self:Log("trace", message, ...)
end

function Debug:Dump()
    local db = Shatter.Database and Shatter.Database:Get()
    if not db or not db.debugLog then return end
    for _, entry in ipairs(db.debugLog) do
        Shatter.Print(string.format("[%s] %s", entry.level or "debug", entry.message or ""))
    end
end
