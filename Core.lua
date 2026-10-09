local ADDON_NAME, Shatter = ...

Shatter = Shatter or {}
_G.Shatter = Shatter

Shatter.ADDON_NAME = ADDON_NAME
Shatter.VERSION = Shatter.API.GetAddOnVersion(ADDON_NAME)
Shatter.modules = Shatter.modules or {}
Shatter.isReady = false
Shatter.disabledNoEnchanting = false
Shatter.isActive = false

local PREFIX = "|cffffd200Shatter|r"

function Shatter.Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. ": " .. tostring(message))
    end
end

function Shatter.RegisterModule(name, module)
    if not name or not module then return end
    Shatter.modules[name] = module
end

local function SafeCall(label, fn, ...)
    if type(fn) ~= "function" then return true end
    local ok, err = pcall(fn, ...)
    if not ok then
        Shatter.Print("|cffff4444" .. tostring(label) .. " failed:|r " .. tostring(err))
    end
    return ok
end

-- The gate is the Disenchant spell itself (C_SpellBook, via Shatter.API).
-- GetProfessions exists on this client but returns nothing, and the Classic
-- spellbook globals are gone, so neither is consulted.
local function HasDisenchant()
    local ok, known = pcall(Shatter.API.IsSpellKnown, Shatter.Constants.SPELL_DISENCHANT)
    return ok and known == true
end

-- Module setup runs exactly once per session: Events:Register appends
-- handlers and Session:Initialize resets the active session, so a second run
-- would double every handler.
local modulesInitialized = false

local function InitializeModules()
    if modulesInitialized then return end
    modulesInitialized = true
    if Shatter.Database then
        SafeCall("Database", Shatter.Database.Initialize, Shatter.Database)
        SafeCall("Database", Shatter.Database.StampLoad, Shatter.Database)
    end
    if Shatter.Debug then SafeCall("Debug", Shatter.Debug.Initialize, Shatter.Debug) end
    if Shatter.Events then SafeCall("Events", Shatter.Events.Initialize, Shatter.Events) end
    if Shatter.MaterialTracker then SafeCall("MaterialTracker", Shatter.MaterialTracker.Initialize, Shatter.MaterialTracker) end
    if Shatter.Queue then SafeCall("Queue", Shatter.Queue.Initialize, Shatter.Queue) end
    if Shatter.Session then SafeCall("Session", Shatter.Session.Initialize, Shatter.Session) end
    if Shatter.MailSession then SafeCall("MailSession", Shatter.MailSession.Initialize, Shatter.MailSession) end
    if Shatter.MailSender then SafeCall("MailSender", Shatter.MailSender.Initialize, Shatter.MailSender) end
    if Shatter.Disenchant then SafeCall("Disenchant", Shatter.Disenchant.Initialize, Shatter.Disenchant) end
    if Shatter.MainFrame then SafeCall("MainFrame", Shatter.MainFrame.Initialize, Shatter.MainFrame) end
    if Shatter.MailLaunchPanel then SafeCall("MailLaunchPanel", Shatter.MailLaunchPanel.Initialize, Shatter.MailLaunchPanel) end
    if Shatter.MinimapButton then SafeCall("MinimapButton", Shatter.MinimapButton.Initialize, Shatter.MinimapButton) end
    if Shatter.SummaryUI then SafeCall("SummaryUI", Shatter.SummaryUI.Initialize, Shatter.SummaryUI) end
    if Shatter.SoloMode then SafeCall("SoloMode", Shatter.SoloMode.Initialize, Shatter.SoloMode) end
    if Shatter.MailMode then SafeCall("MailMode", Shatter.MailMode.Initialize, Shatter.MailMode) end
    if Shatter.RaidMode then SafeCall("RaidMode", Shatter.RaidMode.Initialize, Shatter.RaidMode) end
end

-- Hides the UI after Enchanting is unlearned. Data stays; module handlers stay
-- registered but every user-facing path checks Shatter.isActive. In combat
-- the main frame is protected (it parents the secure button), so the hide
-- waits for PLAYER_REGEN_ENABLED.
local function Deactivate()
    if Shatter.MainFrame and Shatter.MainFrame.frame then
        if InCombatLockdown() then
            Shatter.pendingDeactivateHide = true
        else
            SafeCall("MainFrame", Shatter.MainFrame.frame.Hide, Shatter.MainFrame.frame)
        end
    end
    if Shatter.MailLaunchPanel and Shatter.MailLaunchPanel.HideForMailboxClose then
        SafeCall("MailLaunchPanel", Shatter.MailLaunchPanel.HideForMailboxClose, Shatter.MailLaunchPanel)
    end
    local minimapButton = Shatter.MinimapButton and Shatter.MinimapButton.button
    if minimapButton then minimapButton:Hide() end
end

-- After a reactivation (unlearn, then learn again): the minimap button
-- follows its saved preference again and the queue is rebuilt.
local function Reactivate()
    if Shatter.MinimapButton and Shatter.MinimapButton.Refresh then
        SafeCall("MinimapButton", Shatter.MinimapButton.Refresh, Shatter.MinimapButton)
    end
    if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("REACTIVATED", 0.1) end
end

-- One line when the client is not the build these notes and the adapter
-- were measured on: something may have moved (porting guide, s0).
local function CheckBuild()
    local version, build = GetBuildInfo()
    local current = tostring(version) .. "." .. tostring(build)
    if current ~= Shatter.Constants.MEASURED_ON_BUILD then
        Shatter.Print(string.format("|cffffaa00This client is %s; Shatter was measured on %s.|r Report anything odd.",
            current, Shatter.Constants.MEASURED_ON_BUILD))
    end
end

-- Called at PLAYER_LOGIN and again on SPELLS_CHANGED / SKILL_LINES_CHANGED,
-- so a character who learns (or unlearns) Enchanting mid-session follows
-- without a reload. A spellbook that is not ready yet at login answers
-- "unknown" here; SPELLS_CHANGED arrives once it is and settles it.
function Shatter.EvaluateCapability()
    local known = HasDisenchant()
    if known then
        -- First activation builds the secure Shatter Next button, which the
        -- client refuses to create or configure in combat: wait it out.
        if not modulesInitialized and InCombatLockdown() then
            Shatter.pendingActivation = true
            Shatter.isReady = true
            return
        end
        Shatter.pendingActivation = nil
        local wasActive = Shatter.isActive
        local firstTime = not modulesInitialized
        Shatter.disabledNoEnchanting = false
        Shatter.isActive = true
        InitializeModules()
        -- Once, on the first activation, wherever it happens (login, a late
        -- spellbook, the end of combat); inactive characters stay quiet.
        if firstTime then CheckBuild() end
        if not wasActive and not firstTime then
            Reactivate()
        end
        if not wasActive and Shatter.isReady and Shatter.MainFrame and Shatter.MainFrame.Update then
            SafeCall("MainFrame", Shatter.MainFrame.Update, Shatter.MainFrame)
        end
    else
        local wasActive = Shatter.isActive
        Shatter.disabledNoEnchanting = true
        Shatter.isActive = false
        if wasActive then Deactivate() end
    end
    Shatter.isReady = true
end

function Shatter.Initialize()
    Shatter.EvaluateCapability()
end

function Shatter.Toggle()
    if not Shatter.isReady then
        Shatter.Print("Addon is still loading.")
        return
    end
    if Shatter.pendingActivation then
        Shatter.Print("Shatter finishes loading when combat ends.")
        return
    end
    if Shatter.disabledNoEnchanting then
        Shatter.Print("Disabled on this character: Enchanting is not trained.")
        return
    end
    if Shatter.MainFrame then
        Shatter.MainFrame:Toggle()
    end
end

function Shatter.Rescan()
    if Shatter.disabledNoEnchanting then
        Shatter.Print("Cannot scan: Enchanting is not trained on this character.")
        return
    end
    if Shatter.SoloMode then
        Shatter.SoloMode:ScheduleScan("MANUAL", 0)
    end
end

SLASH_SHATTER1 = "/shatter"
SLASH_SHATTER2 = "/shat"

SlashCmdList.SHATTER = function(message)
    message = message and strlower(strtrim(message)) or ""

    if message == "help" or message == "?" then
        Shatter.Print("Commands: /shatter, /shatter scan, /shatter yields, /shatter yields reset, /shatter debug, /shatter trace, /shatter sim, /shatter simreset, /shatter reset, /shatter mailtest")
        return
    elseif Shatter.pendingActivation then
        Shatter.Print("Shatter finishes loading when combat ends.")
        return
    elseif Shatter.disabledNoEnchanting then
        Shatter.Print("Disabled on this character: Enchanting is not trained.")
        return
    elseif message == "scan" then
        Shatter.Rescan()
        if Shatter.MainFrame then Shatter.MainFrame:Show() end
        return
    elseif message == "debug" then
        if Shatter.Database then
            local settings = Shatter.Database:GetSettings()
            settings.debug = not settings.debug
            if not settings.debug then settings.traceDebug = false end
            Shatter.Print("Debug logging " .. (settings.debug and "enabled." or "disabled."))
            if Shatter.SettingsUI then Shatter.SettingsUI:Refresh() end
        end
        return
    elseif message == "trace" then
        if Shatter.Database then
            local settings = Shatter.Database:GetSettings()
            settings.traceDebug = not settings.traceDebug
            if settings.traceDebug then settings.debug = true end
            Shatter.Print("Trace logging " .. (settings.traceDebug and "enabled." or "disabled."))
            if Shatter.SettingsUI then Shatter.SettingsUI:Refresh() end
        end
        return
    elseif message == "sim" or message == "simulate" then
        if Shatter.Database then
            local settings = Shatter.Database:GetSettings()
            if not settings.simulateDisenchant then
                settings.debug = true
                settings.simulateDisenchant = true
            else
                settings.simulateDisenchant = false
            end
            if Shatter.Session then Shatter.Session:ResetSimulatedItems() end
            if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("SIMULATION_TOGGLED", 0.05) end
            if Shatter.SettingsUI then Shatter.SettingsUI:Refresh() end
            Shatter.Print("Disenchant simulation " .. (settings.simulateDisenchant and "enabled. No items will be destroyed." or "disabled."))
        end
        return
    elseif message == "mailtest" then
        if Shatter.MailMode then
            local enabled = not Shatter.MailMode.actionsEnabledForSession
            Shatter.MailMode:SetActionsEnabledForSession(enabled)
            Shatter.Print(enabled
                and "Mail actions ENABLED for this session (validation testing). They turn off at /reload."
                or "Mail actions disabled.")
        end
        return
    elseif message == "yields" then
        if Shatter.DisenchantTables then
            Shatter.Print("Measured disenchants (from " .. Shatter.DisenchantTables.MIN_YIELD_SAMPLES .. " per bracket they adjust the built-in table):")
            for _, line in ipairs(Shatter.DisenchantTables:FormatYields()) do Shatter.Print("  " .. line) end
        end
        return
    elseif message == "yields reset" then
        if not Shatter.Database then return end
        Shatter.Database:ResetYields()
        -- A Mail queue keeps its owner; a Solo scan would skip it.
        if Shatter.Queue and Shatter.Queue:GetOwner() == "mail" and Shatter.MailMode then
            Shatter.MailMode:PrepareDisenchantQueue()
        else
            Shatter.Rescan()
        end
        Shatter.Print("Measured disenchants cleared; estimates use the built-in table.")
        return
    elseif message == "simreset" then
        if Shatter.Session then Shatter.Session:ResetSimulatedItems() end
        if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("SIMULATION_RESET", 0.05) end
        Shatter.Print("Simulation queue reset.")
        return
    elseif message == "reset" then
        if Shatter.Database then
            Shatter.Database:ResetWindow()
            Shatter.Print("Window position reset.")
        end
        return
    end

    Shatter.Toggle()
end

-- The bootstrap frame lives outside the gate, so capability changes reach a
-- character that logged in without Enchanting.
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("SKILL_LINES_CHANGED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
local loggedIn = false
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        loggedIn = true
        Shatter.Initialize()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if Shatter.pendingActivation then
            Shatter.EvaluateCapability()
        end
        if Shatter.pendingDeactivateHide then
            Shatter.pendingDeactivateHide = nil
            if not Shatter.isActive and Shatter.MainFrame and Shatter.MainFrame.frame then
                SafeCall("MainFrame", Shatter.MainFrame.frame.Hide, Shatter.MainFrame.frame)
            end
        end
    elseif loggedIn then
        Shatter.EvaluateCapability()
    end
end)
