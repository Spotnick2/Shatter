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
-- The rest of Shatter's in-game checks (#31), one procedure each:
--   loot (#10)  the loot events' order and timing for a Disenchant, with
--               autoloot on, off (slow to loot), and two quick clicks;
--   mail (#26)  MailFrame / InboxFrame after the mailbox closes, and Shatter's
--               status then and after reopening;
--   guid        an item's GUID across a drag, a bag sort and a /reload;
--   sets (#36)  equipment sets: the client's, and Shatter leaving their items out;
--   next        Shatter Next: one left click, one cast, disarmed after; a
--               right click and a press released off the button cast nothing;
--   looks (#28, #24)  each look over a bright and a dark background, and the
--               Mail launch panel, as screenshots;
--   tips (#27)  where the "Disenchants into" lines show, and the modifier
--               setting on an open tooltip, as screenshots.
-- looks and tips change Shatter's settings through /shatter and put them back;
-- after a procedure stopped midway, /fp sh restore does, in the same profile.
-- Commands: /fp sh skill, watch on|off, events, clear, restore.

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
    "UI_ERROR_MESSAGE", "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED", "BAG_UPDATE_DELAYED",
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
    elseif event == "LOOT_READY" then
        text = "autoloot " .. Show((...))
    elseif event == "LOOT_OPENED" then
        local autoLoot, isFromItem = ...
        text = ("autoLoot %s, isFromItem %s"):format(Show(autoLoot), Show(isFromItem))
    elseif event == "CLICK" then
        text = ...
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

-- One of Shatter's settings (Shatter is a global, Core.lua), or nil.
local function setting(key)
    local addon = rawget(_G, "Shatter")
    local db = type(addon) == "table" and addon.Database
    local settings = db and db:GetSettings()
    return type(settings) == "table" and settings[key] or nil
end

-- A /shatter command, as the owner would type it (Shatter keeps nothing in _G).
local function shatter(args)
    local fn = SlashCmdList and SlashCmdList.SHATTER
    if type(fn) ~= "function" then say("/shatter: Shatter isn't loaded") return false end
    fn(args)
    return true
end

local function autoLoot()
    local ok, on = Probe:Try("C_CVar.GetCVarBool", C_CVar and C_CVar.GetCVarBool, "autoLootDefault")
    return ok and on == true
end

-- Everything since `t0` as one line, timed from the first event:
-- "SENT +0.00 > SUCCEEDED +1.51 > LOOT_READY +1.60 (autoloot true) > ...".
local function timeline(t0)
    local parts, first = {}, nil
    for _, r in ipairs(recorded) do
        if r.t >= t0 then
            first = first or r.t
            local name = r.event:gsub("^UNIT_SPELLCAST_", "")
            parts[#parts + 1] = ("%s +%.2f%s"):format(name, r.t - first, r.text ~= "" and (" (" .. r.text .. ")") or "")
        end
    end
    return table.concat(parts, " > ")
end

-- Counts since `t0`: Disenchants sent, succeeded and failed, loot windows
-- closed, and when the last event came.
local function tally(t0)
    local c = { sent = 0, succeeded = 0, failed = 0, lootClosed = 0, last = t0 }
    for _, r in ipairs(recorded) do
        if r.t >= t0 then
            c.last = r.t
            if r.disenchant and r.event == "UNIT_SPELLCAST_SENT" then c.sent = c.sent + 1 end
            if r.disenchant and r.event == "UNIT_SPELLCAST_SUCCEEDED" then c.succeeded = c.succeeded + 1 end
            if r.disenchant and (r.event == "UNIT_SPELLCAST_FAILED" or r.event == "UNIT_SPELLCAST_INTERRUPTED") then
                c.failed = c.failed + 1
            end
            if r.event == "LOOT_CLOSED" then c.lootClosed = c.lootClosed + 1 end
        end
    end
    return c
end

-- A loot step: done once `want` Disenchants succeeded since the step began
-- (and a loot window closed, when `closed`), then nothing came for SETTLE
-- seconds, so a late loot window is still caught. The result is the timeline.
local SETTLE = 3
local function settled(key, want, closed)
    return function()
        if not watching then watch(true) end
        marks[key] = marks[key] or GetTime()
        local c = tally(marks[key])
        if c.succeeded >= want and (not closed or c.lootClosed > 0) and GetTime() - c.last >= SETTLE then
            return true, timeline(marks[key])
        end
        if c.succeeded >= want and (not closed or c.lootClosed > 0) then return false, "waiting for late events" end
        return false, ("%d of %d Disenchant(s)%s"):format(c.succeeded, want,
            (closed and c.succeeded >= want) and ", loot window still open" or "")
    end
end

local LOOT = {
    title = "Loot events around a Disenchant (#10)",
    { text = "Recording casts and loot events. Also type /shatter trace once (chat says \"Trace logging "
        .. "enabled.\"), so Shatter's own view goes to its saved log.", auto = true,
      run = function() freshRun() watch(true) return autoLoot() end },
    { text = "Turn Auto Loot ON (Esc > Options > Controls), then press Next.",
      check = function() return autoLoot(), "autoLootDefault" end },
    { text = "Disenchant one green with Shatter Next, and loot nothing else until this step finishes.",
      wait = settled("auto", 1), timeout = 300 },
    { text = "Turn Auto Loot OFF, then press Next.",
      check = function() return not autoLoot(), "autoLootDefault" end },
    { text = "Disenchant one green with Shatter Next. When the loot window opens, count to three, then "
        .. "take the materials.", wait = settled("manual", 1, true), timeout = 300 },
    { text = "Did Shatter count those materials (its status line, or the session summary)?", ask = true,
      screenshot = "Shatter after a slow manual loot" },
    { text = "Turn Auto Loot back ON. Queue at least two items, then click Shatter Next, and click it "
        .. "again the moment it allows.", wait = settled("quick", 2), timeout = 300 },
    { text = "Type /reload to save the results.", reload = true },
}
Probe:Steps("loot", LOOT)

-- MailFrame and InboxFrame, shown and visible.
local function mailFrames()
    local function state(name)
        local f = rawget(_G, name)
        if not f then return name .. " absent" end
        return ("%s shown %s visible %s"):format(name, Show(f:IsShown()), Show(f:IsVisible()))
    end
    local text = state("MailFrame") .. ", " .. state("InboxFrame")
    say("mail frames: " .. text)
    return text
end

local MAIL = {
    title = "The mailbox after it closes (#26)",
    { text = "Open Shatter (/shatter). Go to a mailbox and open it.", event = "MAIL_SHOW" },
    { text = "Reading the mail frames.", auto = true, run = function() freshRun() return mailFrames() end },
    { text = "In Shatter's Mail panel, start a session. Then close the mailbox (Esc).", event = "MAIL_CLOSED" },
    { text = "Reading the mail frames a second after the close.",
      wait = function()
          marks.mailClosed = marks.mailClosed or GetTime()
          if GetTime() - marks.mailClosed < 1 then return false, "reading in a second" end
          return true, mailFrames()
      end,
      check = function()
          local f = rawget(_G, "MailFrame")
          return f ~= nil and not f:IsVisible(), "MailFrame hidden"
      end, timeout = 30 },
    { text = "Does Shatter's status ask you to open the mailbox (\"Open the mailbox to continue Mail Mode.\" "
        .. "or \"Mailbox not detected…\")?", ask = true, screenshot = "Shatter, mailbox closed" },
    { text = "Open the mailbox again.", event = "MAIL_SHOW" },
    { text = "Did the session carry on (the status no longer asks for the mailbox)?", ask = true,
      screenshot = "Shatter, mailbox reopened" },
    { text = "Type /reload to save the results.", reload = true },
}
Probe:Steps("mail", MAIL)

-- The GUID at a bag slot, or nil.
local function guidAt(bag, slot)
    local loc = ItemLocation and ItemLocation:CreateFromBagAndSlot(bag, slot)
    if not (loc and C_Item.DoesItemExist(loc)) then return nil end
    local ok, guid = Probe:Try("C_Item.GetItemGUID", C_Item.GetItemGUID, loc)
    if ok and type(guid) == "string" and not secret(guid) then return guid end
    return nil
end

-- Where the followed GUID is now: bag, slot and item ID, or nil.
local function findHeld()
    local held = ShatterProbeDB and ShatterProbeDB.heldGUID
    if not held then say("guid: nothing followed yet") return nil end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            if guidAt(bag, slot) == held then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local itemID = type(info) == "table" and info.itemID or nil
                say(("guid %s: bag %d slot %d, item %s"):format(held, bag, slot, Show(itemID)))
                return bag, slot, itemID
            end
        end
    end
    say(("guid %s: not in the bags"):format(held))
    return nil
end

local GUID = {
    title = "An item's GUID across a drag, a sort and a /reload",
    { text = "Put a green weapon or armor piece in the first slot of your backpack, then press Run.",
      button = "Run", run = function()
          local guid = guidAt(0, 1)
          ShatterProbeDB.heldGUID = guid
          return findHeld()
      end, check = function() return ShatterProbeDB.heldGUID ~= nil, "a GUID in backpack slot 1" end },
    { text = "Drag it to another slot (any bag), then press Run.", button = "Run", run = findHeld,
      check = function()
          local bag, slot = findHeld()
          return bag ~= nil and not (bag == 0 and slot == 1), "found elsewhere"
      end },
    { text = "Sort your bags (the backpack's sort button), then press Run.", button = "Run", run = findHeld,
      check = function() return findHeld() ~= nil, "found after the sort" end },
    { text = "Type /reload.", reload = true },
    { text = "Looking for it again.", auto = true, run = findHeld,
      check = function() return findHeld() ~= nil, "found after the /reload" end },
}
Probe:Steps("guid", GUID)

-- Equipment sets (#36): whether the client has them, and what the bag
-- slot call says for an item saved in one.
local function readSets()
    local okCan, can = Probe:Try("C_EquipmentSet.CanUseEquipmentSets", C_EquipmentSet and C_EquipmentSet.CanUseEquipmentSets)
    local okIDs, ids = Probe:Try("C_EquipmentSet.GetEquipmentSetIDs", C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs)
    local inSet = {}
    local fn = C_Container.GetContainerItemEquipmentSetInfo
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local ok, yes, list = Probe:Try("GetContainerItemEquipmentSetInfo", fn, bag, slot)
            if ok and yes == true then inSet[#inSet + 1] = ("bag %d slot %d (%s)"):format(bag, slot, Show(list)) end
        end
    end
    local text = ("CanUseEquipmentSets %s, %s set(s), in a set: %s"):format(okCan and Show(can) or "ERROR",
        okIDs and type(ids) == "table" and #ids or "?", #inSet > 0 and table.concat(inSet, "; ") or "none")
    say("sets: " .. text)
    return #inSet, text
end

local SETS = {
    title = "Equipment sets (#36)",
    { text = "Open the character sheet. Is there an equipment manager (saved sets)?", ask = true,
      screenshot = "character sheet" },
    { text = "Save a set that includes a green or better weapon or armor piece, then take that item off "
        .. "into your bags. Press Run.", button = "Run", run = readSets,
      check = function() return readSets() > 0, "an item in a set, in the bags" end },
    { text = "Open Shatter (/shatter). Is that item left out of the queue?", ask = true, screenshot = "Shatter's queue" },
    { text = "Delete the set (or take the item out of it), then press Run.", button = "Run", run = readSets },
    { text = "Is the item back in Shatter's queue?", ask = true },
    { text = "Type /reload to save the results.", reload = true },
}
Probe:Steps("sets", SETS)

-- Shatter Next: the secure button under ShatterMainFrame (the only one with
-- useOnKeyDown set). Every click edge is recorded, with the button's action
-- attributes after Shatter's PreClick (armed?) and PostClick (disarmed?).
local nextButton
local function attrs(b)
    return ("type %s, spell %s, bag %s, slot %s"):format(Show(b:GetAttribute("*type1")), Show(b:GetAttribute("*spell1")),
        Show(b:GetAttribute("*target-bag1")), Show(b:GetAttribute("*target-slot1")))
end
local function findNext()
    if nextButton then return nextButton end
    local function walk(frame)
        for _, child in ipairs({ frame:GetChildren() }) do
            if child.GetAttribute and child:GetAttribute("useOnKeyDown") == false then return child end
            local found = walk(child)
            if found then return found end
        end
    end
    local main = rawget(_G, "ShatterMainFrame")
    nextButton = main and walk(main) or nil
    if nextButton then
        for _, phase in ipairs({ "PreClick", "PostClick" }) do
            nextButton:HookScript(phase, function(b, mouse, down)
                if watching then record("CLICK", ("%s %s %s: %s"):format(phase, Show(mouse, true), down and "down" or "up", attrs(b))) end
            end)
        end
    end
    say("Shatter Next " .. (nextButton and "found" or "not found (open Shatter first)"))
    return nextButton
end

-- Disenchants sent since `key`'s mark, the timeline, and whether the button
-- is disarmed now; then the mark moves on, for the next step.
local function sinceMark(key, nextKey)
    local t0 = marks[key] or GetTime()
    local c = tally(t0)
    local disarmed = nextButton ~= nil and nextButton:GetAttribute("*type1") == nil
    marks[nextKey] = GetTime()
    return c.sent, disarmed, timeline(t0)
end

-- A step that waits for one click's cast (or failure) and 2 s of quiet,
-- counting from `key`'s mark; then the mark moves to `nextKey`.
local function castWait(key, nextKey)
    return function()
        marks[key] = marks[key] or GetTime()
        local c = tally(marks[key])
        if c.succeeded + c.failed == 0 or GetTime() - c.last < 2 then return false, "waiting for the cast" end
        local sent, disarmed, line = sinceMark(key, nextKey)
        return true, sent, disarmed, line
    end
end
local function castCheck(key)
    return function()
        local c = tally(marks[key])
        local disarmed = nextButton:GetAttribute("*type1") == nil
        return c.sent == 1 and disarmed, ("%d Disenchant(s) sent, %s, ActionButtonUseKeyDown %s"):format(c.sent,
            disarmed and "disarmed" or "STILL ARMED", Show(GetCVar("ActionButtonUseKeyDown")))
    end
end

local NEXT = {
    title = "Shatter Next: one click, one cast",
    { text = "Open Shatter (/shatter) in the Solo view, with at least two items queued, then press Find.",
      button = "Find", run = function() freshRun() watch(true) return findNext() ~= nil end,
      check = function() return nextButton ~= nil, "Shatter Next found" end },
    { text = "Left-click Shatter Next once.", wait = castWait("left", "right"), check = castCheck("left"), timeout = 300 },
    { text = "Right-click Shatter Next once, then press Done.", button = "Done",
      run = function() return sinceMark("right", "off") end,
      check = function() return tally(marks.right).sent == 0, "nothing cast" end },
    { text = "Press the left button on Shatter Next, move the mouse off it, release, then press Done.",
      button = "Done", run = function() return sinceMark("off", "key") end,
      check = function() return tally(marks.off).sent == 0, "nothing cast" end },
    -- #35: Shatter acts on the release (useOnKeyDown pinned false); a key
    -- must deliver it. If it doesn't, nothing casts and this times out.
    { text = "Bind a key to Shatter Next (Options > Keybindings > Shatter), close the options, then press "
        .. "the key once.", wait = castWait("key", "hidden"), check = castCheck("key"), timeout = 300 },
    { text = "Close Shatter's window, press the key once, then press Done.", button = "Done",
      run = function() return sinceMark("hidden", "after") end,
      check = function() return tally(marks.hidden).sent == 0, "nothing cast with the window closed" end },
    { text = "Type /reload to save the results.", reload = true },
}
Probe:Steps("next", NEXT)

-- The settings looks and tips change: backed up once, put back at their end.
-- A backup belongs to the Shatter profile it was taken from (Global, or one
-- character's Personal), while ShatterProbeDB is account-wide: so backups are
-- kept per profile, and only the active profile's are restored. A backup
-- stays until its restore is verified, so a procedure stopped midway (Stop,
-- or another one started) and run again never overwrites the original;
-- /fp sh restore puts back what is pending for the active profile.
local RESTORED = { "skin", "tooltip" }

-- The active profile: "GLOBAL", or "PERSONAL <name-realm>"; nil without Shatter.
local function profile()
    local addon = rawget(_G, "Shatter")
    local db = type(addon) == "table" and addon.Database
    if not db then return nil end
    if db:GetProfileScope() == "PERSONAL" then return "PERSONAL " .. db:GetCharacterKey() end
    return "GLOBAL"
end

local function backups(create)
    local id = profile()
    if not id then return nil end
    ShatterProbeDB.restore = type(ShatterProbeDB.restore) == "table" and ShatterProbeDB.restore or {}
    if create and type(ShatterProbeDB.restore[id]) ~= "table" then ShatterProbeDB.restore[id] = {} end
    return ShatterProbeDB.restore[id], id
end

local function remember(key)
    local saved, id = backups(true)
    if not saved then say("Shatter isn't loaded: nothing to back up") return nil end
    if saved[key] ~= nil then
        say(("Shatter's %s (%s): keeping the earlier backup, %s"):format(key, id, Show(saved[key])))
    else
        saved[key] = setting(key)
        say(("Shatter's %s (%s) was %s"):format(key, id, Show(saved[key])))
    end
    return saved[key]
end

local function putBack(key)
    local saved, id = backups(false)
    local value = saved and saved[key]
    if value == nil then return setting(key) end
    shatter(key .. " " .. value)
    local now = setting(key)
    if now == value then
        saved[key] = nil
        if next(saved) == nil then ShatterProbeDB.restore[id] = nil end
    end
    say(("Shatter's %s (%s) put back: %s%s"):format(key, id, Show(now),
        now == value and "" or (", not " .. Show(value) .. " (still backed up: /fp sh restore)")))
    return now
end

-- Backups for profiles other than the active one, as "skin (GLOBAL) clear".
local function pendingElsewhere()
    local list, active = {}, profile()
    for id, saved in pairs(type(ShatterProbeDB.restore) == "table" and ShatterProbeDB.restore or {}) do
        if id ~= active and type(saved) == "table" then
            for key, value in pairs(saved) do list[#list + 1] = ("%s (%s) %s"):format(key, id, Show(value)) end
        end
    end
    table.sort(list)
    return list
end

-- The look Shatter shows (Skin.Shown: "suite" while it follows Glass UI,
-- "forever" for a glass look without LibGlass), or nil.
local function shownLook()
    local addon = rawget(_G, "Shatter")
    local skins = type(addon) == "table" and addon.Skin
    return skins and skins.Shown and skins.Shown() or nil
end

-- A shot labelled with a look Shatter isn't showing would mislead: unless
-- the look shows, the step throws and stays, so no shot is taken.
local function skin(name)
    return function()
        shatter("skin " .. name)
        local shown = shownLook()
        if shown ~= name then error(("Shatter shows %s, not %s: Skip this look"):format(Show(shown), name), 0) end
        return shown
    end
end

local LOOK_NAMES = { "forever", "clear", "smoked", "flat" }
local LOOKS = {
    title = "Shatter's looks (#28, #24)",
    { text = "Open Shatter (/shatter) and put its window over a bright background (snow, sky, a lit wall). "
        .. "If Shatter follows Glass UI's look, turn that off in Glass UI first: the looks can't be "
        .. "switched while it does. Then press Run.", button = "Run", run = function() return remember("skin") end,
      check = function()
          local shown = shownLook()
          return shown ~= nil and shown ~= "suite", "Shatter shows " .. Show(shown)
      end },
}
for _, background in ipairs({ "bright", "dark" }) do
    if background == "dark" then
        LOOKS[#LOOKS + 1] = { text = "Now move the window over a dark background (a night sky, a cave), then press Next." }
    end
    for _, name in ipairs(LOOK_NAMES) do
        LOOKS[#LOOKS + 1] = { text = ("Press Run to switch to %s (%s background)."):format(name, background),
            button = "Run", run = skin(name), screenshot = background .. ", " .. name }
    end
end
LOOKS[#LOOKS + 1] = { text = "Go to a mailbox and open it.", event = "MAIL_SHOW" }
-- The client shows MailFrame after MAIL_SHOW (#26), so the shot waits for Next.
LOOKS[#LOOKS + 1] = { text = "Once Shatter's Mail launch panel shows beside the mailbox, press Next.",
    screenshot = "mail launch panel" }
LOOKS[#LOOKS + 1] = { text = "Press Run to put your look back.", button = "Run", run = function() return putBack("skin") end }
LOOKS[#LOOKS + 1] = { text = "Type /reload to save the results.", reload = true }
Probe:Steps("looks", LOOKS)

-- A tooltip showing an item (with `frame` shown, when given): its name, the
-- item ID and its line count; nil otherwise.
local function itemTip(tipName, frame)
    local tip = rawget(_G, tipName)
    if not (tip and tip:IsVisible()) then return nil end
    if frame then
        local f = rawget(_G, frame)
        if not (f and f:IsVisible()) then return nil end
    end
    local data = tip.GetPrimaryTooltipData and tip:GetPrimaryTooltipData()
    if type(data) ~= "table" or secret(data) or data.type ~= Enum.TooltipDataType.Item then return nil end
    return data.id, tip:NumLines()
end

local function tipWait(tipName, frame)
    return function()
        local itemID, lines = itemTip(tipName, frame)
        if not itemID then return false, "waiting for an item tooltip" .. (frame and (" with " .. frame .. " open") or "") end
        return true, tipName, itemID, lines
    end
end

-- With the modifier setting: the same item's tooltip, first without a
-- modifier, then with one held, and more lines with it.
local function modifierWait(key, tipName)
    return function()
        local itemID, lines = itemTip(tipName)
        if not itemID then return false, "waiting for an item tooltip" end
        local base = marks[key]
        if not IsModifierKeyDown() then
            marks[key] = { itemID = itemID, lines = lines }
            return false, ("%d lines without a modifier: now hold Shift"):format(lines)
        end
        if not base or base.itemID ~= itemID then return false, "first without a modifier" end
        if lines <= base.lines then return false, ("still %d lines with Shift held"):format(lines) end
        return true, tipName, itemID, base.lines, lines
    end
end

local TIPS = {
    title = "Disenchant tooltips (#27)",
    { text = "Setting Shatter's tooltips to always.", auto = true,
      run = function() freshRun() remember("tooltip") shatter("tooltip always") return setting("tooltip") end },
    { text = "Hover a green or better weapon or armor piece in your bags, and keep the mouse on it.",
      wait = tipWait("GameTooltip"), timeout = 300, screenshot = "bags" },
    { text = "Click an item link in chat (a green or better weapon or armor) so its own tooltip opens.",
      wait = tipWait("ItemRefTooltip"), timeout = 300, screenshot = "chat link" },
    { text = "At a vendor, hover one of its weapons or armor pieces (Skip if none here).",
      wait = tipWait("GameTooltip", "MerchantFrame"), timeout = 300, screenshot = "vendor" },
    { text = "At the bank, hover a weapon or armor piece in the bank (Skip if none here).",
      wait = tipWait("GameTooltip", "BankFrame"), timeout = 300, screenshot = "bank" },
    { text = "At the auction house, hover a weapon or armor in its list (Skip if none here).",
      wait = tipWait("GameTooltip", "AuctionHouseFrame"), timeout = 300, screenshot = "auction house" },
    { text = "In a loot window, hover a green or better weapon or armor (Skip if none here).",
      wait = tipWait("GameTooltip", "LootFrame"), timeout = 300, screenshot = "loot" },
    { text = "Setting Shatter's tooltips to only with Shift, Alt or Ctrl.", auto = true,
      run = function() shatter("tooltip modifier") return setting("tooltip") end },
    { text = "Hover a bag item without any modifier, then, still hovering, hold Shift.",
      wait = modifierWait("modBag", "GameTooltip"), timeout = 300, screenshot = "Shift on a bag item" },
    { text = "Click an item link in chat, then hold Shift (the mouse anywhere).",
      wait = modifierWait("modLink", "ItemRefTooltip"), timeout = 300, screenshot = "Shift on a chat link" },
    { text = "In these screenshots' tooltips, was any line cut off or too long (long material names)?", ask = true },
    { text = "Putting your tooltip setting back.", auto = true, run = function() return putBack("tooltip") end },
    { text = "Type /reload to save the results.", reload = true },
}
Probe:Steps("tips", TIPS)

Probe:Command("skill", function() readSkill() end, "read Enchanting both ways")
Probe:Command("watch", function(args)
    watch(args ~= "off")
end, "on|off: record casts, UI errors and loot events")
Probe:Command("events", function()
    for _, r in ipairs(recorded) do say(("%.2f %s %s"):format(r.t, r.event, r.text)) end
    say(#recorded .. " recorded")
end, "list what was recorded this session")
Probe:Command("clear", function() Probe:ClearLog(); say("log cleared") end, "empty the saved log")
Probe:Command("restore", function()
    for _, key in ipairs(RESTORED) do putBack(key) end
    for _, line in ipairs(pendingElsewhere()) do
        say("still backed up for another profile, put back from there: " .. line)
    end
end, "put back the look and tooltip setting a stopped looks or tips changed (active profile)")

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
    -- Shatter's profile isn't known yet here: list every pending backup.
    for id, saved in pairs(type(ShatterProbeDB.restore) == "table" and ShatterProbeDB.restore or {}) do
        for key, value in pairs(type(saved) == "table" and saved or {}) do
            say(("Shatter's %s (%s) is still backed up (%s): /fp sh restore in that profile puts it back")
                :format(key, id, Show(value)))
        end
    end
end)

NS._test = { Probe = Probe, readSkill = readSkill, watch = watch, since = since, outcome = outcome,
             recorded = recorded, REFUSE = REFUSE, LOOT = LOOT, MAIL = MAIL, GUID = GUID, NEXT = NEXT,
             LOOKS = LOOKS, TIPS = TIPS, SETS = SETS, timeline = timeline, findNext = findNext }
