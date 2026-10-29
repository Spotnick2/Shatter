local _, Shatter = ...

local SettingsUI = {
    frame = nil,
}

Shatter.SettingsUI = SettingsUI
Shatter.RegisterModule("SettingsUI", SettingsUI)

local function CreatePanelButton(parent, text, width)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 90, 22)
    Shatter.Skin.Fill(btn, "button", "normal")
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetAllPoints()
    btn.text:SetJustifyH("CENTER")
    btn.text:SetText(text)
    btn:SetScript("OnEnter", function(self) Shatter.Skin.Hover(self, true) end)
    btn:SetScript("OnLeave", function(self) Shatter.Skin.Hover(self, false) end)
    return btn
end

local function SetShown(frame, shown)
    if not frame then return end
    if shown then
        frame:Show()
    else
        frame:Hide()
    end
end

local function AddTooltip(frame, title, text)
    if not frame then return end
    frame:SetScript("OnEnter", function(self)
        Shatter.Skin.Hover(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 0.82, 0)
        if text and text ~= "" then
            GameTooltip:AddLine(text, 0.82, 0.82, 0.82, true)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        Shatter.Skin.Hover(self, false)
        GameTooltip:Hide()
    end)
end

function SettingsUI:Create(parent)
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -76)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 52)
    frame:SetFrameLevel(parent:GetFrameLevel() + 20)
    Shatter.Skin.Pane(frame, Shatter.C.BG_PANEL)
    frame:Hide()
    self.frame = frame

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 8)
    self.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 430)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self)
        content:SetWidth(math.max(1, self:GetWidth()))
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local maxScroll = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, current - delta * 18)))
    end)
    self.content = content

    local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
    title:SetText("Settings")
    Shatter.SetTextColor(title, Shatter.C.ACCENT)

    local skinLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    skinLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    skinLabel:SetText("Look")
    self.skinButtons = {}
    -- Following Glass UI (Suite.lua), its look replaces Clear and Smoked:
    -- "Glass UI" goes back to it from Flat, or opens Glass UI's page.
    local following = Shatter.Suite and Shatter.Suite.Offered()
    local names = following and { "suite", "flat" } or Shatter.Skin.NAMES
    local previousSkin
    for _, name in ipairs(names) do
        local button = CreatePanelButton(content, Shatter.Skin.LABELS[name], name == "flat" and 64 or 96)
        if previousSkin then
            button:SetPoint("LEFT", previousSkin, "RIGHT", 6, 0)
        else
            button:SetPoint("TOPLEFT", skinLabel, "BOTTOMLEFT", 0, -8)
        end
        button:SetScript("OnClick", function()
            if name ~= "suite" then
                Shatter.Skin.Set(name)
            elseif Shatter.Skin.Shown() == "suite" then
                Shatter.Suite.Open()
            else
                Shatter.Skin.Set("clear")
            end
            self:Refresh()
        end)
        self.skinButtons[name] = button
        previousSkin = button
    end
    AddTooltip(self.skinButtons.clear, "Clear glass", "Light, translucent glass. Changes apply immediately.")
    AddTooltip(self.skinButtons.smoked, "Smoked glass", "Darker glass, easier to read over a bright world.")
    AddTooltip(self.skinButtons.suite, "Glass UI", "Shatter follows the Glass suite's look, set in Glass UI (/glassui). "
        .. "Click again to open Glass UI. Changes made there apply after a /reload.")
    AddTooltip(self.skinButtons.flat, "Flat", "Shatter's opaque dark panels.")
    if not Shatter.Glass then
        self.skinNote = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        self.skinNote:SetPoint("LEFT", previousSkin, "RIGHT", 8, 0)
        self.skinNote:SetText("LibGlass missing: flat only")
    end

    local maxLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local profileLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- What items disenchant into, on their tooltips (Tooltip.lua, #3).
    local tooltipLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tooltipLabel:SetPoint("TOPLEFT", self.skinButtons[names[1]], "BOTTOMLEFT", 0, -12)
    tooltipLabel:SetText("Item tooltips: what an item disenchants into")
    self.tooltipButtons = {}
    local previousTooltip
    for _, mode in ipairs(Shatter.Constants.TOOLTIP_MODE_NAMES) do
        local label = Shatter.Constants.TOOLTIP_MODE_LABELS[mode]
        local button = CreatePanelButton(content, label, mode == "modifier" and 150 or 64)
        if previousTooltip then
            button:SetPoint("LEFT", previousTooltip, "RIGHT", 6, 0)
        else
            button:SetPoint("TOPLEFT", tooltipLabel, "BOTTOMLEFT", 0, -8)
        end
        button:SetScript("OnClick", function()
            Shatter.Tooltip:SetMode(mode)
            self:Refresh()
        end)
        self.tooltipButtons[mode] = button
        previousTooltip = button
    end
    AddTooltip(self.tooltipButtons.always, "Always", "Show the materials, their chances and the expected value on every disenchantable item's tooltip.")
    AddTooltip(self.tooltipButtons.modifier, "With Shift, Alt or Ctrl", "Show them only while Shift, Alt or Ctrl is held when the tooltip opens.")
    AddTooltip(self.tooltipButtons.never, "Never", "Keep item tooltips as they are.")

    profileLabel:SetPoint("TOPLEFT", self.tooltipButtons.always, "BOTTOMLEFT", 0, -12)
    profileLabel:SetText("Settings profile")

    local globalProfile = CreatePanelButton(content, "Global", 82)
    globalProfile:SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", 0, -8)
    local personalProfile = CreatePanelButton(content, "Personal", 82)
    personalProfile:SetPoint("LEFT", globalProfile, "RIGHT", 6, 0)

    local function SetProfile(scope)
        if Shatter.Database then Shatter.Database:SetProfileScope(scope) end
        Shatter.Skin.Refresh()
        self:Refresh()
        if Shatter.MainFrame then
            Shatter.MainFrame:ApplyPosition()
            Shatter.MainFrame:Update()
        end
        if Shatter.MinimapButton then Shatter.MinimapButton:Refresh() end
        if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("SETTINGS_PROFILE", 0.05) end
    end
    globalProfile:SetScript("OnClick", function() SetProfile(Shatter.Constants.PROFILE_SCOPE.GLOBAL) end)
    personalProfile:SetScript("OnClick", function() SetProfile(Shatter.Constants.PROFILE_SCOPE.PERSONAL) end)
    AddTooltip(globalProfile, "Global profile", "Use one shared Shatter settings profile for all characters. This is the default.")
    AddTooltip(personalProfile, "Personal profile", "Use this character's own Shatter settings profile. The first time it is selected, it starts as a copy of your current Global profile.")
    self.profileButtons = {
        [Shatter.Constants.PROFILE_SCOPE.GLOBAL] = globalProfile,
        [Shatter.Constants.PROFILE_SCOPE.PERSONAL] = personalProfile,
    }

    local profileHelp = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    profileHelp:SetPoint("TOPLEFT", globalProfile, "BOTTOMLEFT", 0, -6)
    profileHelp:SetPoint("RIGHT", content, "RIGHT", -12, 0)
    profileHelp:SetJustifyH("LEFT")
    profileHelp:SetText("Global is shared by all characters. Personal only changes this character.")

    maxLabel:SetPoint("TOPLEFT", profileHelp, "BOTTOMLEFT", 0, -10)
    maxLabel:SetText("Maximum quality")

    local uncommon = CreatePanelButton(content, "Uncommon", 82)
    uncommon:SetPoint("TOPLEFT", maxLabel, "BOTTOMLEFT", 0, -8)
    local rare = CreatePanelButton(content, "Rare", 64)
    rare:SetPoint("LEFT", uncommon, "RIGHT", 6, 0)
    local epic = CreatePanelButton(content, "Epic", 64)
    epic:SetPoint("LEFT", rare, "RIGHT", 6, 0)

    local function SetQuality(quality)
        Shatter.Database:GetSettings().maxQuality = quality
        self:Refresh()
        if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("SETTINGS_MAX_QUALITY", 0.05) end
    end
    uncommon:SetScript("OnClick", function() SetQuality(2) end)
    rare:SetScript("OnClick", function() SetQuality(3) end)
    epic:SetScript("OnClick", function() SetQuality(4) end)
    AddTooltip(uncommon, "Maximum quality: Uncommon", "Only queue uncommon items. Rare and epic items are excluded from Solo Mode scans.")
    AddTooltip(rare, "Maximum quality: Rare", "Queue uncommon and rare disenchantable items. This is the default Solo Mode behavior.")
    AddTooltip(epic, "Maximum quality: Epic", "Allow epic disenchantable items in the Solo queue. Use this carefully.")
    self.qualityButtons = { [2] = uncommon, [3] = rare, [4] = epic }

    local orderLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    orderLabel:SetPoint("TOPLEFT", uncommon, "BOTTOMLEFT", 0, -10)
    orderLabel:SetText("Solo queue order")

    local bagSlot = CreatePanelButton(content, "Bag / Slot", 78)
    bagSlot:SetPoint("TOPLEFT", orderLabel, "BOTTOMLEFT", 0, -8)
    local fifo = CreatePanelButton(content, "First In, First Out", 118)
    fifo:SetPoint("LEFT", bagSlot, "RIGHT", 6, 0)
    local lifo = CreatePanelButton(content, "Last In, First Out", 118)
    lifo:SetPoint("LEFT", fifo, "RIGHT", 6, 0)

    local function SetQueueOrder(order)
        if Shatter.Database then Shatter.Database:SetQueueOrder("solo", order) end
        self:Refresh()
        if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("SETTINGS_QUEUE_ORDER", 0.05) end
    end
    bagSlot:SetScript("OnClick", function() SetQueueOrder(Shatter.Constants.QUEUE_ORDER.BAG_SLOT) end)
    fifo:SetScript("OnClick", function() SetQueueOrder(Shatter.Constants.QUEUE_ORDER.FIFO) end)
    lifo:SetScript("OnClick", function() SetQueueOrder(Shatter.Constants.QUEUE_ORDER.LIFO) end)
    AddTooltip(bagSlot, "Bag / Slot order", "Process items by bag index and slot number. This is predictable and matches how items are arranged in your bags.")
    AddTooltip(fifo, "First In, First Out", "Process items in the order Shatter first saw them in the current Solo session.")
    AddTooltip(lifo, "Last In, First Out", "Process the newest items Shatter added to the current Solo session first.")
    self.queueOrderButtons = {
        [Shatter.Constants.QUEUE_ORDER.BAG_SLOT] = bagSlot,
        [Shatter.Constants.QUEUE_ORDER.FIFO] = fifo,
        [Shatter.Constants.QUEUE_ORDER.LIFO] = lifo,
    }

    local orderHelp = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    orderHelp:SetPoint("TOPLEFT", bagSlot, "BOTTOMLEFT", 0, -6)
    orderHelp:SetPoint("RIGHT", content, "RIGHT", -12, 0)
    orderHelp:SetJustifyH("LEFT")
    orderHelp:SetText("Controls the Solo queue processing order.")

    local valueLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueLabel:SetPoint("TOPLEFT", orderHelp, "BOTTOMLEFT", 0, -10)
    valueLabel:SetText("Minimum expected value")

    local valueOff = CreatePanelButton(content, "Off", 44)
    valueOff:SetPoint("TOPLEFT", valueLabel, "BOTTOMLEFT", 0, -8)
    local value1g = CreatePanelButton(content, "1g", 44)
    value1g:SetPoint("LEFT", valueOff, "RIGHT", 6, 0)
    local value5g = CreatePanelButton(content, "5g", 44)
    value5g:SetPoint("LEFT", value1g, "RIGHT", 6, 0)
    local value10g = CreatePanelButton(content, "10g", 50)
    value10g:SetPoint("LEFT", value5g, "RIGHT", 6, 0)

    local function SetThreshold(value)
        Shatter.Database:GetSettings().minExpectedValueCopper = value or 0
        self:Refresh()
        if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("SETTINGS_VALUE_THRESHOLD", 0.05) end
    end
    valueOff:SetScript("OnClick", function() SetThreshold(0) end)
    value1g:SetScript("OnClick", function() SetThreshold(10000) end)
    value5g:SetScript("OnClick", function() SetThreshold(50000) end)
    value10g:SetScript("OnClick", function() SetThreshold(100000) end)
    AddTooltip(valueOff, "No minimum value", "Do not require a minimum expected disenchant value.")
    AddTooltip(value1g, "Minimum expected value: 1g", "When value filtering is enabled, only queue items with expected disenchant materials worth at least 1 gold.")
    AddTooltip(value5g, "Minimum expected value: 5g", "When value filtering is enabled, only queue items with expected disenchant materials worth at least 5 gold.")
    AddTooltip(value10g, "Minimum expected value: 10g", "When value filtering is enabled, only queue items with expected disenchant materials worth at least 10 gold.")
    self.valueButtons = {
        [0] = valueOff,
        [10000] = value1g,
        [50000] = value5g,
        [100000] = value10g,
    }

    local valueHelp = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    valueHelp:SetPoint("LEFT", value10g, "RIGHT", 10, 0)
    valueHelp:SetPoint("RIGHT", content, "RIGHT", -12, 0)
    valueHelp:SetJustifyH("LEFT")
    valueHelp:SetText("Uses optional TSM, Auctioneer, or Auctionator prices when available.")

    local soulbound = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    soulbound:SetPoint("TOPLEFT", valueOff, "BOTTOMLEFT", -4, -8)
    soulbound:SetSize(24, 24)
    soulbound.label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    soulbound.label:SetPoint("LEFT", soulbound, "RIGHT", 4, 0)
    soulbound.label:SetText("Include soulbound items")
    soulbound:SetScript("OnClick", function(self)
        Shatter.Database:GetSettings().includeSoulbound = self:GetChecked() and true or false
        if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("SETTINGS_SOULBOUND", 0.05) end
    end)
    AddTooltip(soulbound, "Include soulbound items", "Allow soulbound disenchantable equipment in the Solo queue. Leave this off if you only want tradable items.")
    self.soulbound = soulbound

    local minimap = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    minimap:SetPoint("TOPLEFT", soulbound, "BOTTOMLEFT", 0, -6)
    minimap:SetSize(24, 24)
    minimap.label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    minimap.label:SetPoint("LEFT", minimap, "RIGHT", 4, 0)
    minimap.label:SetText("Show minimap button")
    minimap:SetScript("OnClick", function(self)
        local settings = Shatter.Database:GetSettings()
        settings.minimap = type(settings.minimap) == "table" and settings.minimap or {}
        settings.minimap.hide = not self:GetChecked()
        if Shatter.MinimapButton then Shatter.MinimapButton:Refresh() end
    end)
    AddTooltip(minimap, "Show minimap button", "Show or hide Shatter's minimap button. The button toggles Shatter and can be dragged around the minimap.")
    self.minimap = minimap

    local useValues = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    useValues:SetPoint("TOPLEFT", minimap, "BOTTOMLEFT", 0, -6)
    useValues:SetSize(24, 24)
    useValues.label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    useValues.label:SetPoint("LEFT", useValues, "RIGHT", 4, 0)
    useValues.label:SetText("Filter queue by expected value")
    useValues:SetScript("OnClick", function(self)
        Shatter.Database:GetSettings().useAuctionData = self:GetChecked() and true or false
        if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("SETTINGS_VALUE_FILTER", 0.05) end
    end)
    AddTooltip(useValues, "Filter by expected value", "Use installed TSM, Auctioneer, or Auctionator prices to filter the queue by the selected minimum expected value. Items stay visible if no pricing data is available.")
    self.useValues = useValues

    -- Ignored items (#4): what Ignore put away, each with Remove, and Reset
    -- all. Reset asks again in place, not through a StaticPopup (Blizzard's
    -- popups can taint), and the list grows the scroll content.
    local ignoredLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ignoredLabel:SetPoint("TOPLEFT", useValues, "BOTTOMLEFT", 4, -12)
    self.ignoredLabel = ignoredLabel

    local resetIgnored = CreatePanelButton(content, "Reset all", 96)
    resetIgnored:SetPoint("LEFT", ignoredLabel, "RIGHT", 10, 0)
    resetIgnored:SetScript("OnClick", function(button)
        if button.armed then
            button.armed = nil
            Shatter.Queue:ClearIgnored()
        else
            -- Armed for a few seconds; a later click re-arms with its own token.
            button.armed = true
            local token = (button.armToken or 0) + 1
            button.armToken = token
            C_Timer.After(5, function()
                if button.armToken ~= token or not button.armed then return end
                button.armed = nil
                SettingsUI:RefreshIgnored()
            end)
        end
        SettingsUI:RefreshIgnored()
    end)
    AddTooltip(resetIgnored, "Reset all", "Forget every ignored item, so they can be queued again. Click twice to confirm.")
    self.resetIgnored = resetIgnored

    local ignoredList = CreateFrame("Frame", nil, content)
    ignoredList:SetPoint("TOPLEFT", ignoredLabel, "BOTTOMLEFT", 0, -8)
    ignoredList:SetPoint("RIGHT", content, "RIGHT", -12, 0)
    ignoredList:SetHeight(16)
    self.ignoredList = ignoredList
    self.ignoredRows = {}
    self.ignoredEmpty = ignoredList:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.ignoredEmpty:SetPoint("TOPLEFT", ignoredList, "TOPLEFT", 0, -2)
    self.ignoredEmpty:SetText("None. Ignore keeps an item out of the queue for good; it is listed here.")
    -- Names that weren't cached come in later.
    Shatter.Events:Register("GET_ITEM_INFO_RECEIVED", self, function()
        if self.ignoredLoading and self.frame:IsShown() then self:RefreshIgnored() end
    end)

    local debug = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    debug:SetPoint("TOPLEFT", ignoredList, "BOTTOMLEFT", -4, -8)
    debug:SetSize(24, 24)
    debug.label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    debug.label:SetPoint("LEFT", debug, "RIGHT", 4, 0)
    debug.label:SetText("Debug logging")
    debug:SetScript("OnClick", function(self)
        local settings = Shatter.Database:GetSettings()
        settings.debug = self:GetChecked() and true or false
        if not settings.debug then
            settings.traceDebug = false
            settings.simulateDisenchant = false
        end
        SettingsUI:Refresh()
        if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("SETTINGS_DEBUG", 0.05) end
    end)
    AddTooltip(debug, "Debug logging", "Print important Shatter state changes such as settings changes and failures. Routine disenchant event details require Trace logging.")
    self.debug = debug

    local trace = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    trace:SetPoint("TOPLEFT", debug, "BOTTOMLEFT", 0, -6)
    trace:SetSize(24, 24)
    trace.label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    trace.label:SetPoint("LEFT", trace, "RIGHT", 4, 0)
    trace.label:SetText("Trace logging")
    trace:SetScript("OnClick", function(self)
        Shatter.Database:GetSettings().traceDebug = self:GetChecked() and true or false
        SettingsUI:Refresh()
    end)
    AddTooltip(trace, "Trace logging", "Print verbose scan, secure button, and disenchant event details for troubleshooting. This can be noisy and is intended for short debugging sessions.")
    self.trace = trace

    local simulate = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    simulate:SetPoint("TOPLEFT", trace, "BOTTOMLEFT", 0, -6)
    simulate:SetSize(24, 24)
    simulate.label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    simulate.label:SetPoint("LEFT", simulate, "RIGHT", 4, 0)
    simulate.label:SetText("Development simulation: fake results, no casting")
    simulate:SetScript("OnClick", function(self)
        Shatter.Database:GetSettings().simulateDisenchant = self:GetChecked() and true or false
        if Shatter.Session then Shatter.Session:ResetSimulatedItems() end
        if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("SETTINGS_SIMULATION", 0.05) end
        if Shatter.MainFrame then Shatter.MainFrame:Update() end
    end)
    AddTooltip(simulate, "Development simulation", "Record fake disenchant results without casting Disenchant or consuming items. This is a development/testing mode only.")
    self.simulate = simulate

    local note = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", simulate, "BOTTOMLEFT", 4, -10)
    note:SetPoint("RIGHT", content, "RIGHT", -12, 0)
    note:SetJustifyH("LEFT")
    note:SetText("Expected materials use built-in disenchant tables. Value filters use optional TSM, Auctioneer, or Auctionator prices when available. Mail and Raid modes are reserved for later phases.")

    self:Refresh()
    return frame
end

-- The scroll content's height without the ignored list's rows.
local CONTENT_HEIGHT = 500
local IGNORED_ROW = 24

local function IgnoredRow(self, index)
    local row = self.ignoredRows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, self.ignoredList)
    row:SetHeight(IGNORED_ROW)
    row:SetPoint("TOPLEFT", self.ignoredList, "TOPLEFT", 0, -(index - 1) * IGNORED_ROW)
    row:SetPoint("RIGHT", self.ignoredList, "RIGHT", 0, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.remove = CreatePanelButton(row, "Remove", 64)
    row.remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.remove:SetScript("OnClick", function() Shatter.Queue:Unignore(row.itemID) end)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
    row.text:SetJustifyH("LEFT")
    self.ignoredRows[index] = row
    return row
end

-- One ignored item: its link (or name), icon, and whether it is still loading.
local function DescribeIgnored(itemID)
    local name, link = Shatter.API.GetItemInfo(itemID)
    local _, _, _, _, icon = Shatter.API.GetItemInfoInstant(itemID)
    if not name then
        C_Item.RequestLoadItemDataByID(itemID)
        return { itemID = itemID, text = "Item " .. itemID, icon = icon, loading = true }
    end
    return { itemID = itemID, text = link or name, sortName = strlower(name), icon = icon }
end

-- Alphabetical; items still loading go last, by ID.
local function IgnoredOrder(a, b)
    if a.sortName and b.sortName then
        if a.sortName ~= b.sortName then return a.sortName < b.sortName end
        return a.itemID < b.itemID
    end
    if a.sortName or b.sortName then return a.sortName ~= nil end
    return a.itemID < b.itemID
end

function SettingsUI:RefreshIgnored()
    if not self.ignoredList then return end
    local entries, loading = {}, false
    for _, itemID in ipairs(Shatter.Database:GetIgnoredItems()) do
        local entry = DescribeIgnored(itemID)
        loading = loading or entry.loading == true
        entries[#entries + 1] = entry
    end
    table.sort(entries, IgnoredOrder)
    self.ignoredLoading = loading
    self.ignoredLabel:SetText(#entries > 0 and string.format("Ignored items (%d)", #entries) or "Ignored items")
    for i, entry in ipairs(entries) do
        local row = IgnoredRow(self, i)
        row.itemID = entry.itemID
        row.icon:SetTexture(entry.icon or 134400)
        row.text:SetText(entry.text)
        row:Show()
    end
    for i = #entries + 1, #self.ignoredRows do self.ignoredRows[i]:Hide() end
    SetShown(self.ignoredEmpty, #entries == 0)
    if #entries == 0 then self.resetIgnored.armed = nil end
    SetShown(self.resetIgnored, #entries > 0)
    local armed = self.resetIgnored.armed
    self.resetIgnored.text:SetText(armed and "Click to confirm" or "Reset all")
    Shatter.Skin.Paint(self.resetIgnored, armed and "emphasis" or "normal")
    local height = math.max(16, #entries * IGNORED_ROW)
    self.ignoredList:SetHeight(height)
    self.content:SetHeight(CONTENT_HEIGHT + height)
end

function SettingsUI:Refresh()
    if not self.frame then return end
    self:RefreshIgnored()
    local settings = Shatter.Database:GetSettings()
    if self.soulbound then self.soulbound:SetChecked(settings.includeSoulbound) end
    if self.minimap then self.minimap:SetChecked(not (settings.minimap and settings.minimap.hide)) end
    if self.useValues then self.useValues:SetChecked(settings.useAuctionData) end
    if self.debug then self.debug:SetChecked(settings.debug) end
    if self.trace then self.trace:SetChecked(settings.traceDebug) end
    if self.simulate then self.simulate:SetChecked(settings.simulateDisenchant) end
    for mode, button in pairs(self.tooltipButtons or {}) do
        local chosen = mode == settings.tooltip
        Shatter.Skin.Paint(button, chosen and "chosen" or "normal")
        Shatter.SetTextColor(button.text, chosen and Shatter.C.ACCENT or Shatter.C.TEXT_NORM)
    end
    for name, button in pairs(self.skinButtons or {}) do
        local chosen = name == Shatter.Skin.Shown()
        Shatter.Skin.Paint(button, chosen and "chosen" or "normal")
        Shatter.SetTextColor(button.text, chosen and Shatter.C.ACCENT or Shatter.C.TEXT_NORM)
    end
    local profileScope = Shatter.Database and Shatter.Database:GetProfileScope() or Shatter.Constants.PROFILE_SCOPE.GLOBAL
    for scope, button in pairs(self.profileButtons or {}) do
        if scope == profileScope then
            Shatter.Skin.Paint(button, "chosen")
            Shatter.SetTextColor(button.text, Shatter.C.ACCENT)
        else
            Shatter.Skin.Paint(button, "normal")
            Shatter.SetTextColor(button.text, Shatter.C.TEXT_NORM)
        end
    end
    SetShown(self.trace, settings.debug or settings.traceDebug)
    SetShown(self.trace and self.trace.label, settings.debug or settings.traceDebug)
    SetShown(self.simulate, settings.debug or settings.simulateDisenchant)
    SetShown(self.simulate and self.simulate.label, settings.debug or settings.simulateDisenchant)
    for quality, button in pairs(self.qualityButtons or {}) do
        if quality == settings.maxQuality then
            Shatter.Skin.Paint(button, "chosen")
            Shatter.SetTextColor(button.text, Shatter.C.ACCENT)
        else
            Shatter.Skin.Paint(button, "normal")
            Shatter.SetTextColor(button.text, Shatter.C.TEXT_NORM)
        end
    end
    local order = Shatter.Database and Shatter.Database:GetQueueOrder("solo") or Shatter.Constants.QUEUE_ORDER.BAG_SLOT
    for value, button in pairs(self.queueOrderButtons or {}) do
        if value == order then
            Shatter.Skin.Paint(button, "chosen")
            Shatter.SetTextColor(button.text, Shatter.C.ACCENT)
        else
            Shatter.Skin.Paint(button, "normal")
            Shatter.SetTextColor(button.text, Shatter.C.TEXT_NORM)
        end
    end
    local threshold = tonumber(settings.minExpectedValueCopper) or 0
    for value, button in pairs(self.valueButtons or {}) do
        if value == threshold then
            Shatter.Skin.Paint(button, "chosen")
            Shatter.SetTextColor(button.text, Shatter.C.ACCENT)
        else
            Shatter.Skin.Paint(button, "normal")
            Shatter.SetTextColor(button.text, Shatter.C.TEXT_NORM)
        end
    end
end

function SettingsUI:Toggle()
    if not self.frame then return end
    if self.frame:IsShown() then
        self.frame:Hide()
        if Shatter.MainFrame then Shatter.MainFrame:SetSettingsOpen(false) end
    else
        self:Refresh()
        self.frame:Show()
        if Shatter.MainFrame then Shatter.MainFrame:SetSettingsOpen(true) end
    end
end
