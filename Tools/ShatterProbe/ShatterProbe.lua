-- ShatterProbe: Shatter's throwaway measurement module, on ForeverProbe
-- (/fp sh). Born a module (#5, #6).
--
-- /fp steps sh skill (#5): how this client gives the Enchanting skill.
--   - C_SkillInfo.GetNumSkillLines + GetSkillLineInfo(i) (a SkillLineAttributes
--     table; measured by sibling addons) against GetSkillLineInfoByID(333)
--     (in the dump, unmeasured);
--   - with the header Enchanting sits under collapsed, then expanded.
-- /fp steps sh refuse (#5, #6): what a Disenchant looks like, cast by hand:
--   - a control green the game should accept (positive evidence: it goes,
--     materials come);
--   - an item the client flags as never disenchantable (a wand, an insignia);
--   - optionally a high-level item at low skill.
--   Every spellcast event of the player, UI_ERROR_MESSAGE (with
--   GetGameMessageInfo when present), LOOT_READY and BAG_UPDATE_DELAYED are
--   recorded in order. Conclusions only as far as the observations go.
-- Commands: /fp sh skill, watch on|off, events, clear.

local ADDON, NS = ...
local MAX_LOG = 3000
local ENCHANTING = 333
local DISENCHANT = 13262

local Probe = ForeverProbe:Module("ShatterProbe", { api = 1, cmd = "sh" })
local Show = Probe.Show

local function say(msg) Probe:Say(msg) end
local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- A plain number, or nil (absent or secret).
local function num(v)
    if secret(v) or type(v) ~= "number" then return nil end
    return v
end

-- Enchanting by walking the skill lines: rank, maxRank, the index it was at,
-- and how many collapsed headers there were (one may hide it).
local function bySkillLines()
    local ok, count = Probe:Try("C_SkillInfo.GetNumSkillLines", C_SkillInfo and C_SkillInfo.GetNumSkillLines)
    count = ok and num(count) or nil
    if not count then say("skill lines: unreadable") return nil end
    local collapsed = 0
    for i = 1, count do
        local got, info = Probe:Try("C_SkillInfo.GetSkillLineInfo", C_SkillInfo.GetSkillLineInfo, i)
        if got and type(info) == "table" and not secret(info) then
            if info.isHeader == true and info.isCollapsed == true then collapsed = collapsed + 1 end
            if num(info.skillID) == ENCHANTING then
                say(("skill lines: Enchanting at %d of %d: rank %s / %s, %d collapsed header(s) before it")
                    :format(i, count, Show(info.rank), Show(info.maxRank), collapsed))
                return num(info.rank), num(info.maxRank), i, collapsed
            end
        end
    end
    say(("skill lines: no Enchanting in %d lines (%d collapsed header(s))"):format(count, collapsed))
    return nil, nil, nil, collapsed
end

-- Enchanting by its skill line ID.
local function byID()
    local ok, info = Probe:Try("C_SkillInfo.GetSkillLineInfoByID", C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID, ENCHANTING)
    if not ok then return nil end
    if type(info) ~= "table" or secret(info) then
        say("by ID 333: " .. Show(info))
        return nil
    end
    say(("by ID 333: %s, rank %s / %s"):format(Show(info.name), Show(info.rank), Show(info.maxRank)))
    return num(info.rank), num(info.maxRank)
end

-- Both reads, and whether they agree.
local function readSkill()
    local rank, max, index, collapsed = bySkillLines()
    local idRank, idMax = byID()
    local agree = rank ~= nil and rank == idRank and max == idMax
    say(("Enchanting: lines %s/%s, by ID %s/%s, %s"):format(Show(rank), Show(max), Show(idRank), Show(idMax),
        agree and "the same" or "NOT the same"))
    return rank, idRank, max, idMax, index, collapsed
end

-- The event recorder: { t, event, text } in arrival order.
local recorded = {}
local recorder = CreateFrame("Frame")
local WATCHED = {
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED",
    "UI_ERROR_MESSAGE", "LOOT_READY", "BAG_UPDATE_DELAYED",
}
local watching = false

local function record(event, ...)
    local text
    if event == "UI_ERROR_MESSAGE" then
        local errorType, message = ...
        local info = ""
        local fn = rawget(_G, "GetGameMessageInfo")
        if type(fn) == "function" and num(errorType) then
            local ok, a, b, c = pcall(fn, errorType)
            info = ok and (" info " .. Show(a) .. " " .. Show(b) .. " " .. Show(c)) or (" info ERROR " .. tostring(a))
        end
        text = ("type %s, %s%s"):format(Show(errorType), Show(message), info)
    elseif event:find("^UNIT_SPELLCAST") then
        local unit = ...
        if unit ~= "player" then return end
        -- SENT is (unit, target, castGUID, spellID); the rest (unit, castGUID, spellID).
        local spellID = event == "UNIT_SPELLCAST_SENT" and select(4, ...) or select(3, ...)
        text = "spell " .. Show(spellID)
        if spellID == DISENCHANT then text = text .. " (Disenchant)" end
    else
        text = ""
    end
    recorded[#recorded + 1] = { t = GetTime(), event = event, text = text,
        disenchant = text:find("(Disenchant)", 1, true) ~= nil }
    say(event .. " " .. text)
end

recorder:SetScript("OnEvent", function(_, event, ...) record(event, ...) end)

local function watch(on)
    if on and not watching then
        Probe:RegisterEvents(recorder, WATCHED)
    elseif not on and watching then
        for _, event in ipairs(WATCHED) do recorder:UnregisterEvent(event) end
    end
    watching = on
    say("watching " .. (on and "on" or "off"))
    return watching
end

-- What happened since `t0`: did a Disenchant succeed or fail, and which UI
-- errors came, in order, as one line.
local function since(t0)
    local succeeded, failed, errors, order = false, false, {}, {}
    for _, r in ipairs(recorded) do
        if r.t >= t0 then
            order[#order + 1] = r.event:gsub("^UNIT_SPELLCAST_", "")
            if r.disenchant and r.event == "UNIT_SPELLCAST_SUCCEEDED" then succeeded = true end
            if r.disenchant and (r.event == "UNIT_SPELLCAST_FAILED" or r.event == "UNIT_SPELLCAST_INTERRUPTED") then failed = true end
            if r.event == "UI_ERROR_MESSAGE" then errors[#errors + 1] = r.text end
        end
    end
    return succeeded, failed, table.concat(errors, " | "), table.concat(order, " > ")
end

-- A wait step: done once a Disenchant succeeded, failed, or a UI error came
-- since the step started polling. Its returns are the step's result. A fresh
-- run of the procedure (its first step) forgets every boundary, so a restart
-- without a /reload never finishes on the earlier run's casts.
local marks = {}
local function freshRun()
    for key in pairs(marks) do marks[key] = nil end
end
local function outcome(key, want)
    return function()
        if not watching then watch(true) end
        marks[key] = marks[key] or GetTime()
        local ok, bad, errors, order = since(marks[key])
        local done = (want == "success" and ok) or (want ~= "success" and (ok or bad or errors ~= ""))
        if done then
            return true, ok and "succeeded" or (bad and "failed" or "refused before casting"), errors, order
        end
        return false, "waiting for a Disenchant"
    end
end

Probe:Steps("skill", {
    title = "Reading the Enchanting skill (#5)",
    { text = "Reading your Enchanting skill two ways.", auto = true, run = readSkill },
    { text = "Open the character sheet's Skills tab and collapse the header Enchanting is under "
        .. "(Professions). Then press Run.", button = "Run", run = readSkill },
    { text = "Expand that header again, then press Run.", button = "Run", run = readSkill },
    { text = "Does the Skills tab show the same Enchanting rank as the console's last \"Enchanting:\" line (/fp)?", ask = true },
    { text = "Type /reload to save the results.", reload = true },
})

local REFUSE = {
    title = "What a refused Disenchant looks like (#5, #6)",
    { text = "Recording every cast, UI error and loot event from now on.", auto = true,
      run = function() freshRun() watch(true) return readSkill() end },
    { text = "The control: pick a green weapon or armor piece the game should accept. Cast Disenchant "
        .. "from the spellbook and click it. Type its name in the Note box.",
      wait = outcome("control", "success"), timeout = 300 },
    { text = "Did that item go, and did materials arrive?", ask = true },
    { text = "Now an item the game flags: a Lesser Magic Wand, Greater Magic Wand, Lesser Mystic Wand or "
        .. "a PvP insignia. Cast Disenchant from the spellbook and click it. Type its name in the Note box.",
      wait = outcome("flagged"), timeout = 300 },
    { text = "Is that item still in your bags?", ask = true, screenshot = "flagged item, after" },
    { text = "Optional, for #5: if this character's Enchanting is low (under 150), try the highest item "
        .. "level green, blue or epic you have (40 or more). Note the item and its level. Otherwise Skip.",
      wait = outcome("highlevel"), timeout = 300 },
    { text = "Was it disenchanted?", ask = true },
    { text = "Type /reload to save the results.", reload = true },
}
Probe:Steps("refuse", REFUSE)

Probe:Command("skill", function() readSkill() end, "read Enchanting both ways")
Probe:Command("watch", function(args)
    watch(args ~= "off")
end, "on|off: record casts, UI errors and loot events")
Probe:Command("events", function()
    for _, r in ipairs(recorded) do say(("%.2f %s %s"):format(r.t, r.event, r.text)) end
    say(#recorded .. " recorded")
end, "list what was recorded this session")
Probe:Command("clear", function() Probe:ClearLog(); say("log cleared") end, "empty the saved log")

local boot = CreateFrame("Frame")
Probe:RegisterEvents(boot, { "ADDON_LOADED" })
boot:SetScript("OnEvent", function(_, _, name)
    if name ~= ADDON then return end
    Probe:Ready()
    if type(ShatterProbeDB) ~= "table" then ShatterProbeDB = {} end
    if type(ShatterProbeDB.log) ~= "table" then ShatterProbeDB.log = {} end
    Probe:UseLog(ShatterProbeDB.log, MAX_LOG)
    ShatterProbeDB.loads = (ShatterProbeDB.loads or 0) + 1
    say("loaded (" .. ShatterProbeDB.loads .. " loads). /fp sh for the commands, /fp steps for the procedures")
end)

NS._test = { Probe = Probe, readSkill = readSkill, watch = watch, since = since, outcome = outcome,
             recorded = recorded, REFUSE = REFUSE }
