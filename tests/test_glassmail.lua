------------------------------------------------------------
-- test_glassmail.lua - Mail Mode's "Selected mails" with Glass Mail (#49):
-- Shatter reads Glass Mail's public selection API (Glass Mail's
-- docs/PUBLIC-API.md, GlassMail#26) when it is loaded, before Postal's
-- checkboxes. The stub below follows that contract: Get() returns a new
-- { [inboxIndex] = true } table, never nil; OnChange(fn) calls fn() with no
-- arguments, catching its errors; a non-function is ignored.
------------------------------------------------------------

local H = dofile("tests/harness.lua")
dofile("tests/wow_stubs.lua")

local VEST, BLADE, BOOTS = 2589, 4002, 5005
local SM = nil

-- Glass Mail as its API documents it. `selected` is { [inboxIndex] = true }.
local function installGlassMail(selected)
    local gm = { selected = selected or {}, listeners = {}, gets = 0 }
    function gm.fire()
        for _, fn in ipairs(gm.listeners) do pcall(fn) end
    end
    rawset(_G, "GlassMail", { Selection = {
        Get = function()
            gm.gets = gm.gets + 1
            local copy = {}
            for index in pairs(gm.selected) do copy[index] = true end
            return copy
        end,
        OnChange = function(fn)
            if type(fn) == "function" then gm.listeners[#gm.listeners + 1] = fn end
        end,
    } })
    return gm
end
local function removeGlassMail() rawset(_G, "GlassMail", nil) end

local function installPostal(checkedRows)
    WoW.addons.Postal = { loaded = true }
    for row = 1, 7 do
        local cb = CreateFrame("CheckButton")
        cb:Show()
        cb:SetChecked(checkedRows[row] or false)
        rawset(_G, "PostalInboxCB" .. row, cb)
    end
end
local function removePostal()
    for row = 1, 7 do rawset(_G, "PostalInboxCB" .. row, nil) end
end

-- Three mails; Glass Mail (and/or Postal) installed before the addon loads,
-- as `## OptionalDeps: GlassMail` makes it on the client.
local function setup(opts)
    opts = opts or {}
    removeGlassMail()
    removePostal()
    WoW.reset()
    dofile("tests/wow_stubs.lua")
    WoW.enchanter()
    WoW.AddItem(VEST, { name = "Green Vest", quality = 2, itemLevel = 20, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST" })
    WoW.AddItem(BLADE, { name = "Blue Blade", quality = 3, itemLevel = 40, classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON" })
    WoW.AddItem(BOOTS, { name = "Green Boots", quality = 2, itemLevel = 25, classID = 4, subclassID = 2, equipLoc = "INVTYPE_FEET" })
    WoW.inbox = {
        { sender = "Other Person", subject = "hi", items = { [1] = { itemID = BOOTS } } },
        { sender = "Alpha Smith", subject = "DE please", items = { [1] = { itemID = VEST } } },
        { sender = "Beta Jones", subject = "more", items = { [1] = { itemID = BLADE } } },
    }
    local gm = opts.glassMail and installGlassMail(opts.glassMail) or nil
    if opts.postal then installPostal(opts.postal) end
    WoW.loadAddon()
    WoW.flushTimers()
    MailFrame:Show()
    WoW.fire("MAIL_SHOW")
    WoW.flushTimers()
    SM = Shatter.Constants.MAIL_SELECTION_MODE
    return gm
end

local function rowItems()
    local ids = {}
    for _, r in ipairs(Shatter.MailSession:Get().inputItems or {}) do ids[#ids + 1] = r.itemID end
    table.sort(ids)
    return table.concat(ids, ",")
end

local panel = function() return Shatter.MailLaunchPanel end

-- 1. Glass Mail loaded: the option names it, with its count.
local gm = setup({ glassMail = { [2] = true } })
H.eq(Shatter.MailMode:GetSelectionSource(), "Glass Mail", "the source is Glass Mail")
H.eq(panel().processSelected.label:GetText(), "Selected mails (Glass Mail)", "the option is labelled Glass Mail")
H.check(panel().processSelected:IsShown(), "...and shown")
H.eq(panel().selectedCount:GetText(), "(1 selected)", "the count is Glass Mail's selection")

-- 2. The count follows OnChange: one listener, registered once per load.
H.eq(#gm.listeners, 1, "one OnChange listener registered at the mailbox")
gm.selected = { [2] = true, [3] = true }
gm.fire()
H.eq(panel().selectedCount:GetText(), "(2 selected)", "OnChange refreshes the count")
gm.selected = {}
gm.fire()
H.eq(panel().selectedCount:GetText(), "(0 selected)", "...down to none (Clear)")
MailFrame:Hide()
WoW.fire("MAIL_CLOSED")
WoW.flushTimers()
MailFrame:Show()
WoW.fire("MAIL_SHOW")
WoW.flushTimers()
H.eq(#gm.listeners, 1, "a second mailbox visit doesn't register again")

-- 3. Start with two selected mails: only their attachments are listed, and
-- a later inbox shift doesn't change that (the indices became the session's rows).
gm.selected = { [2] = true, [3] = true }
gm.fire()
Shatter.MailMode:SetLaunchMailSelectionMode(SM.POSTAL_SELECTED)
H.eq(Shatter.MailMode:StartNewSessionFromLaunchPanel(), true, "a Glass Mail-selected session starts")
H.eq(rowItems(), table.concat({ VEST, BLADE }, ","), "only the two selected mails' attachments")
H.eq(Shatter.MailSession:Get().mailSelection.mode, "POSTAL_SELECTED", "the saved mode keeps its value")
table.remove(WoW.inbox, 1)
gm.selected = { [1] = true, [2] = true }        -- Glass Mail follows the shift; Shatter no longer reads it
Shatter.MailMode:ScanInbox("TEST")
H.eq(rowItems(), table.concat({ VEST, BLADE }, ","), "after the inbox shifted, still the same two")
local logged = false
for _, line in ipairs(Shatter.MailSession:Get().sessionLog or {}) do
    if tostring(line.message):find("2 mail(s) selected in Glass Mail.", 1, true) then logged = true end
end
H.check(logged, "the session log names Glass Mail")

-- 4. Nothing selected: Start is refused, naming Glass Mail.
gm = setup({ glassMail = {} })
Shatter.MailMode:SetLaunchMailSelectionMode(SM.POSTAL_SELECTED)
local ok, reason = Shatter.MailMode:CheckLaunchOptions(Shatter.MailMode.launchOptions, true)
H.eq(ok, false, "an empty selection is refused")
H.eq(reason, "No mails selected in Glass Mail.", "...with Glass Mail's name")
H.eq(Shatter.MailMode:StartNewSessionFromLaunchPanel(), false, "...and no session starts")

-- 5. Both loaded: Glass Mail is read, Postal's checkboxes are not.
gm = setup({ glassMail = { [3] = true }, postal = { [2] = true } })
H.eq(Shatter.MailMode:GetSelectionSource(), "Glass Mail", "both loaded: Glass Mail")
H.eq(panel().processSelected.label:GetText(), "Selected mails (Glass Mail)", "...in the label")
Shatter.MailMode:SetLaunchMailSelectionMode(SM.POSTAL_SELECTED)
Shatter.MailMode:StartNewSessionFromLaunchPanel()
H.eq(rowItems(), tostring(BLADE), "...and in what is listed (not Postal's checked vest)")
removePostal()

-- 6. Postal only: unchanged, labelled Postal.
setup({ postal = { [2] = true } })
H.eq(Shatter.MailMode:GetSelectionSource(), "Postal", "Postal only: Postal")
H.eq(panel().processSelected.label:GetText(), "Selected mails (Postal)", "...in the label")
H.eq(panel().selectedCount:GetText(), "(1 selected)", "...with Postal's count")
removePostal()

-- 7. Neither: the option is hidden.
setup()
H.eq(Shatter.MailMode:GetSelectionSource(), nil, "neither: no source")
H.check(not panel().processSelected:IsShown(), "...and the option is hidden")

-- 8. A Glass Mail whose Get fails, or returns junk, reads as nothing
-- selected, never a Lua error in Shatter.
gm = setup({ glassMail = { [2] = true } })
GlassMail.Selection.Get = function() error("boom") end
local okCall, selected = pcall(Shatter.MailMode.GetSelectedMailIndices, Shatter.MailMode)
H.check(okCall and type(selected) == "table" and next(selected) == nil, "Get errors: an empty selection")
GlassMail.Selection.Get = function() return { [2] = true, [3] = "yes", x = true } end
selected = Shatter.MailMode:GetSelectedMailIndices()
H.check(selected[2] == true and selected[3] == nil and selected.x == nil, "only numeric indices set to true are taken")
GlassMail.Selection.Get = nil
H.eq(Shatter.MailMode:GetSelectionSource(), nil, "without Get, Glass Mail isn't a source")

-- 9. An older Glass Mail without the API: not a source.
setup()
rawset(_G, "GlassMail", { })
H.eq(Shatter.MailMode:GetSelectionSource(), nil, "Glass Mail without Selection: not a source")
removeGlassMail()

removeGlassMail()
H.done("test_glassmail")
