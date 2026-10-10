local _, Shatter = ...

local MainFrame = {
    frame = nil,
    rows = {},
    statusOverride = nil,
    statusIsError = false,
    stickyStatus = nil,
    stickyStatusIsError = false,
    stickyStatusUntil = 0,
    settingsOpen = false,
    activeView = "solo",
}

Shatter.MainFrame = MainFrame
Shatter.RegisterModule("MainFrame", MainFrame)

local TITLE_H = 32
local ROWS = 6

local WINDOW = Shatter.Constants.WINDOW
local FRAME_W = WINDOW.DEFAULT_WIDTH
local FRAME_H = WINDOW.DEFAULT_HEIGHT
local MIN_W = WINDOW.MIN_WIDTH
local MIN_H = WINDOW.MIN_HEIGHT
local MAX_W = WINDOW.MAX_WIDTH
local MAX_H = WINDOW.MAX_HEIGHT
local MIN_SCALE = WINDOW.MIN_SCALE
local MAX_SCALE = WINDOW.MAX_SCALE
local CONTENT_TOP = 76
local CONTENT_BOTTOM = 72

local function Clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function CreateButton(parent, text, width, secure)
    local template = secure and "SecureActionButtonTemplate,BackdropTemplate" or "BackdropTemplate"
    local button = CreateFrame("Button", nil, parent, template)
    button:SetSize(width or 100, 26)
    if secure then
        -- Both edges, as the porting guide prescribes; useOnKeyDown = false
        -- pins the secure action to the up edge whatever the player's
        -- ActionButtonUseKeyDown, so Shatter knows which edge acts. No
        -- typerelease: with one, press-and-hold release would cast twice.
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:SetAttribute("useOnKeyDown", false)
    else
        button:RegisterForClicks("LeftButtonUp")
    end
    Shatter.Skin.Fill(button, "button", "normal")
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.text:SetAllPoints()
    button.text:SetJustifyH("CENTER")
    button.text:SetText(text)
    button:SetScript("OnEnter", function(self)
        if self:IsEnabled() then Shatter.Skin.Hover(self, true) end
        if self.mailDisabledReason and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.mailDisabledReason, 1, 0.82, 0, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        Shatter.Skin.Hover(self, false)
        if self.mailDisabledReason and GameTooltip then GameTooltip:Hide() end
    end)
    return button
end

-- The main frame parents the secure Shatter Next button, so it, the footer
-- and the button are protected: under combat lockdown the client refuses to
-- show, hide, move, resize or rescale them. Such changes are recorded and
-- applied on PLAYER_REGEN_ENABLED (MainFrame:OnCombatEvent).
-- Enable/Disable are protected on the secure button too.
local function SetButtonEnabled(button, enabled)
    if not button then return end
    enabled = enabled and true or false
    if InCombatLockdown() and button:IsProtected() then
        if button:IsEnabled() ~= enabled then MainFrame.updateAfterCombat = true end
        return
    end
    if enabled then button:Enable() else button:Disable() end
end

local function SetShown(frame, shown)
    if not frame then return end
    if InCombatLockdown() and frame:IsProtected() then
        if frame:IsShown() ~= (shown and true or false) then MainFrame.updateAfterCombat = true end
        return
    end
    if shown then
        frame:Show()
    else
        frame:Hide()
    end
end

local function CreateDetailLabel(parent, anchor, x, y, text)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -8)
    label:SetText(text)
    Shatter.SetTextColor(label, Shatter.C.ACCENT)
    return label
end

local function CreateDetailText(parent, template)
    local text = parent:CreateFontString(nil, "OVERLAY", template or "GameFontDisableSmall")
    text:SetJustifyH("LEFT")
    text:SetTextColor(0.72, 0.72, 0.72, 1)
    return text
end

local function StripColorCodes(text)
    text = tostring(text or "")
    text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = string.gsub(text, "|r", "")
    return text
end

local function FormatChance(chance)
    return string.format("%d%%", math.floor((chance or 0) * 100 + 0.5))
end

local function FormatExpectedQuantity(amount)
    return string.format("x%.2f", amount or 0)
end

local function FormatRange(minAmount, maxAmount)
    minAmount = minAmount or 1
    maxAmount = maxAmount or minAmount
    if minAmount == maxAmount then return tostring(minAmount) end
    return string.format("%d-%d", minAmount, maxAmount)
end

local function FormatPriceSource(source)
    if not source or source == "" then return "Unknown" end
    if source == "TSM dbmarket" then return "TSM dbmarket" end
    if string.find(source, "TSM", 1, true) then return "TSM market" end
    if string.find(source, "Auctionator", 1, true) then return "Auctionator" end
    if string.find(source, "Auctioneer", 1, true) then return "Auctioneer" end
    return source
end

local function FormatMoneyWithIcons(copper)
    copper = tonumber(copper)
    if not copper then return nil end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperOnly = math.floor(copper % 100)
    local coinSize = 11
    local parts = {}
    if gold > 0 then
        table.insert(parts, string.format("%d |TInterface\\MoneyFrame\\UI-GoldIcon:%d:%d:0:0|t", gold, coinSize, coinSize))
    end
    if silver > 0 or gold > 0 then
        table.insert(parts, string.format("%d |TInterface\\MoneyFrame\\UI-SilverIcon:%d:%d:0:0|t", silver, coinSize, coinSize))
    end
    table.insert(parts, string.format("%d |TInterface\\MoneyFrame\\UI-CopperIcon:%d:%d:0:0|t", copperOnly, coinSize, coinSize))
    return table.concat(parts, " ")
end

local function GetSessionSummary()
    local session = Shatter.Session and Shatter.Session.active
    if not session or not session.summary then
        return "Done: 0   Skipped: 0", "Ignored: 0   Failed: 0"
    end
    local summary = session.summary
    return string.format("Done: %d   Skipped: %d", summary.itemsDisenchanted or 0, summary.itemsSkipped or 0),
        string.format("Ignored: %d   Failed: %d", summary.itemsIgnored or 0, summary.itemsFailed or 0)
end

local function HasSessionWork()
    local summary = Shatter.Session and Shatter.Session.active and Shatter.Session.active.summary
    if not summary then return false end
    return (summary.itemsDisenchanted or 0) > 0
        or (summary.itemsSkipped or 0) > 0
        or (summary.itemsIgnored or 0) > 0
        or (summary.itemsFailed or 0) > 0
        or not (Shatter.MaterialTracker and Shatter.MaterialTracker:IsEmpty(summary.materialsGenerated))
end
local function SortedMaterials(materials)
    local list = {}
    for itemID, count in pairs(materials or {}) do
        if count and count > 0 then
            table.insert(list, { itemID = itemID, count = count })
        end
    end
    table.sort(list, function(a, b) return (a.itemID or 0) < (b.itemID or 0) end)
    return list
end

local function UpdateGenerated(detail)
    if not detail then return end
    local summary = Shatter.Session and Shatter.Session.active and Shatter.Session.active.summary
    local line1, line2 = GetSessionSummary()
    if detail.sessionText then
        detail.sessionText:SetText((line1 or "") .. "   |   " .. (line2 or ""))
    end
    local list = SortedMaterials(summary and summary.materialsGenerated)
    local hasMaterials = #list > 0
    if detail.generatedEmpty then
        detail.generatedEmpty:SetText(hasMaterials and "" or "No materials yet")
        SetShown(detail.generatedEmpty, not hasMaterials)
    end
    for i, slot in ipairs(detail.generatedSlots or {}) do
        local entry = list[i]
        if entry then
            slot:Show()
            local name, link, _, _, _, _, _, _, _, texture = Shatter.API.GetItemInfo(entry.itemID)
            slot.itemLink = link
            slot.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            slot.count:SetText(tostring(entry.count))
        else
            slot:Hide()
            slot.itemLink = nil
        end
    end
    if detail.generatedMore then
        local extra = math.max(0, #list - #(detail.generatedSlots or {}))
        detail.generatedMore:SetText(extra > 0 and ("+" .. tostring(extra) .. " more") or "")
        SetShown(detail.generatedMore, extra > 0)
    end
end

local function UpdateDetailSections(detail, selected)
    if not detail then return end
    local selectedId = selected and selected.queueId
    if detail.scroll and selectedId ~= detail.lastSelectedId then
        detail.scroll:SetVerticalScroll(0)
    end
    detail.lastSelectedId = selectedId

    if not selected then
        local hasWork = HasSessionWork()
        SetShown(detail.materialLabel, false)
        if detail.materialEmpty then
            if hasWork then
                detail.materialEmpty:SetText("Queue complete")
            else
                detail.materialEmpty:SetText("No eligible items\nNo disenchantable items match your current settings.")
            end
            SetShown(detail.materialEmpty, true)
        end
        for _, row in ipairs(detail.materialRows or {}) do row.frame:Hide() end
        SetShown(detail.valueLabel, false)
        SetShown(detail.valueText, false)
        SetShown(detail.sessionLabel, hasWork)
        SetShown(detail.sessionText, hasWork)
    else
        SetShown(detail.materialLabel, true)
        SetShown(detail.valueLabel, true)
        SetShown(detail.valueText, true)
        SetShown(detail.sessionLabel, true)
        SetShown(detail.sessionText, true)
        local estimate = selected.expectedEstimate
        local materials = estimate and estimate.materials
        local hasMaterials = materials and #materials > 0
        if detail.materialLabel then
            local label = "Expected Materials"
            if estimate and estimate.measured then
                label = string.format("Expected Materials (measured, %d)", estimate.samples)
            elseif estimate and estimate.uncertain then
                label = "Expected Materials (unverified)"
            end
            detail.materialLabel:SetText(label)
        end
        if detail.materialEmpty then
            detail.materialEmpty:SetText(hasMaterials and "" or "No estimate for this item.")
            SetShown(detail.materialEmpty, not hasMaterials)
        end
        for i, row in ipairs(detail.materialRows or {}) do
            local entry = hasMaterials and materials[i]
            if entry then
                row.frame:Show()
                row.chance:SetText(FormatChance(entry.chance))
                local name, link = Shatter.API.GetItemInfo(entry.itemID)
                row.name:SetText(StripColorCodes(link or name or ("item:" .. tostring(entry.itemID))))
                local r, g, b = Shatter.GetQualityColor(select(3, Shatter.API.GetItemInfo(entry.itemID)))
                row.name:SetTextColor(r, g, b, 1)
                row.meta:SetText(string.format("%s   Range: %s", FormatExpectedQuantity(entry.expectedAmount), FormatRange(entry.minAmount, entry.maxAmount)))
                local _, _, _, _, _, _, _, _, _, texture = Shatter.API.GetItemInfo(entry.itemID)
                row.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            else
                row.frame:Hide()
            end
        end

        if estimate and estimate.expectedValueCopper then
            detail.valueText:SetText("Expected DE Value: " .. (FormatMoneyWithIcons(estimate.expectedValueCopper) or tostring(estimate.expectedValueCopper)) .. "\nSource: " .. FormatPriceSource(estimate.valueSource))
        else
            detail.valueText:SetText("Unavailable")
        end
    end

end

function MainFrame:EnsureQueueRows(count)
    if not self.queueContent then return end
    count = math.max(count or 0, ROWS)
    local previous = self.rows[#self.rows]
    for i = #self.rows + 1, count do
        local row = Shatter.Rows.CreateQueueRow(self.queueContent, i)
        row:SetPoint("LEFT", self.queueContent, "LEFT", 0, 0)
        row:SetPoint("RIGHT", self.queueContent, "RIGHT", 0, 0)
        if previous then
            row:SetPoint("TOP", previous, "BOTTOM", 0, -2)
        else
            row:SetPoint("TOP", self.queueContent, "TOP", 0, 0)
        end
        self.rows[i] = row
        previous = row
    end
end

function MainFrame:ClampGeometry()
    if not self.frame then return end
    local width = Clamp(self.frame:GetWidth() or FRAME_W, MIN_W, MAX_W)
    local height = Clamp(self.frame:GetHeight() or FRAME_H, MIN_H, MAX_H)
    if width ~= self.frame:GetWidth() or height ~= self.frame:GetHeight() then
        self.frame:SetSize(width, height)
    end
    local scale = Clamp(self.frame:GetScale() or 1, MIN_SCALE, MAX_SCALE)
    if scale ~= self.frame:GetScale() then
        self.frame:SetScale(scale)
    end
end

function MainFrame:SaveGeometry()
    if InCombatLockdown() then
        self.saveGeometryAfterCombat = true
        return
    end
    self:ClampGeometry()
    if Shatter.Database then Shatter.Database:SaveWindow(self.frame) end
end

function MainFrame:HideCastBar()
    if not self.castBar then return end
    self.castBar:Hide()
    self.castBar:SetScript("OnUpdate", nil)
    self.castBar.mode = nil
end

function MainFrame:ShowCastBar(label, duration, mode)
    if not self.castBar then return end
    local bar = self.castBar
    duration = duration or 0
    bar.mode = mode or "timed"
    bar.startedAt = GetTime and GetTime() or 0
    bar.duration = duration
    bar.label:SetText(label or "")
    bar.fill:SetWidth(1)
    bar:Show()
    bar:SetScript("OnUpdate", function(self)
        local now = GetTime and GetTime() or 0
        local width = self:GetWidth() or 1
        local progress = 0
        if self.mode == "pulse" then
            progress = 0.18 + (math.sin(now * 5) + 1) * 0.32
        elseif (self.duration or 0) > 0 then
            progress = Clamp((now - (self.startedAt or now)) / self.duration, 0, 1)
        end
        self.fill:SetWidth(math.max(1, width * progress))
    end)
end

function MainFrame:ShowCastProgress(spellName, item, startTimeMS, endTimeMS)
    local now = GetTime and GetTime() or 0
    local startTime = startTimeMS and startTimeMS / 1000 or now
    local endTime = endTimeMS and endTimeMS / 1000 or (now + 1.5)
    local duration = math.max(0.1, endTime - startTime)
    local label = spellName or "Disenchanting..."
    if item and (item.itemLink or item.itemName) then
        label = string.format("%s: %s", label, item.itemLink or item.itemName)
    end
    self:ShowCastBar(label, duration, "timed")
    self.castBar.startedAt = startTime
end

function MainFrame:ShowWaitingForResult(item, duration)
    local label = "Waiting for result..."
    if item and (item.itemLink or item.itemName) then
        label = string.format("Waiting for result: %s", item.itemLink or item.itemName)
    end
    self:ShowCastBar(label, duration or 0, duration and "timed" or "pulse")
end

function MainFrame:Layout()
    if not self.frame or not self.queuePanel or not self.detailPanel then return end
    if InCombatLockdown() then
        self.layoutAfterCombat = true
        return
    end
    if self.layouting then return end
    self.layouting = true
    self:ClampGeometry()
    local width = self.frame:GetWidth() or FRAME_W
    local detailWidth = Clamp(math.floor(width * 0.38), 230, 300)

    self.detailPanel:ClearAllPoints()
    self.detailPanel:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -10, -CONTENT_TOP)
    self.detailPanel:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -10, CONTENT_BOTTOM)
    self.detailPanel:SetWidth(detailWidth)

    self.queuePanel:ClearAllPoints()
    self.queuePanel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 10, -CONTENT_TOP)
    self.queuePanel:SetPoint("RIGHT", self.detailPanel, "LEFT", -8, 0)
    self.queuePanel:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 10, CONTENT_BOTTOM)

    if self.status then
        self.status:ClearAllPoints()
        self.status:SetPoint("LEFT", self.footer, "LEFT", 0, 0)
        self.status:SetPoint("RIGHT", self.primary, "LEFT", -10, 0)
    end
    if self.castBar then
        self.castBar:ClearAllPoints()
        self.castBar:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 10, 48)
        self.castBar:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -30, 48)
        self.castBar:SetHeight(14)
    end
    if Shatter.MailFrame then Shatter.MailFrame:Layout() end
    self.layouting = false
end

function MainFrame:ResetGeometry()
    if InCombatLockdown() then
        self.resetGeometryAfterCombat = true
        self:SetStatus("The window resets when combat ends.", false, 3)
        return
    end
    if Shatter.Database then
        Shatter.Database:ResetWindow()
    else
        self.frame:SetSize(FRAME_W, FRAME_H)
        self.frame:SetScale(1)
        self.frame:ClearAllPoints()
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    self:Layout()
    self:SetStatus("Window size, scale, and position reset.", false, 3)
end

function MainFrame:CreateResizeGrip(parent)
    local grip = CreateFrame("Button", nil, parent, "BackdropTemplate")
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -3, 3)
    grip:RegisterForClicks("RightButtonUp")
    grip:EnableMouse(true)

    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    local normal = grip:GetNormalTexture()
    if normal then
        normal:SetVertexColor(0.78, 0.78, 0.78, 0.9)
    end
    local highlight = grip:GetHighlightTexture()
    if highlight then
        highlight:SetVertexColor(1, 0.82, 0.22, 0.75)
    end

    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText("Resize Shatter", 1, 0.82, 0)
        GameTooltip:AddLine("Click and drag to resize this window.", 0.82, 0.82, 0.82, true)
        GameTooltip:AddLine("Hold SHIFT while dragging to scale the window instead.", 0.82, 0.82, 0.82, true)
        GameTooltip:AddLine("Right-Click to reset the window size, scale, and position to their defaults.", 0.82, 0.82, 0.82, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    grip:SetScript("OnMouseDown", function(self, button)
        if InCombatLockdown() then return end
        if button == "LeftButton" then
            if IsShiftKeyDown and IsShiftKeyDown() then
                self.scaling = true
                self.startX, self.startY = GetCursorPosition()
                self.startScale = parent:GetScale() or 1
                self:SetScript("OnUpdate", function(self)
                    if InCombatLockdown() then
                        self.scaling = nil
                        self:SetScript("OnUpdate", nil)
                        MainFrame.saveGeometryAfterCombat = true
                        return
                    end
                    local x, y = GetCursorPosition()
                    local delta = ((x - self.startX) - (y - self.startY)) / 500
                    parent:SetScale(Clamp(self.startScale + delta, MIN_SCALE, MAX_SCALE))
                end)
            else
                parent:StartSizing("BOTTOMRIGHT")
            end
        end
    end)
    grip:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            MainFrame:ResetGeometry()
            return
        end
        if self.scaling then
            self.scaling = nil
            self:SetScript("OnUpdate", nil)
        elseif InCombatLockdown() then
            MainFrame.stopMovingAfterCombat = true
            return
        else
            parent:StopMovingOrSizing()
        end
        MainFrame:SaveGeometry()
        MainFrame:Layout()
    end)

    return grip
end

function MainFrame:Initialize()
    self:Create()
    if Shatter.Events then
        Shatter.Events:Register("PLAYER_REGEN_DISABLED", self, self.OnCombatEvent)
        Shatter.Events:Register("PLAYER_REGEN_ENABLED", self, self.OnCombatEvent)
    end
end

local SPECIAL_FRAME_NAME = "ShatterMainFrame"

-- Writes entries of Blizzard's UISpecialFrames, never the table itself.
local function SetEscapeCloses(enabled)
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == SPECIAL_FRAME_NAME then table.remove(UISpecialFrames, i) end
    end
    if enabled then table.insert(UISpecialFrames, SPECIAL_FRAME_NAME) end
end

-- Asks for the window to be shown or hidden; in combat the request waits.
function MainFrame:RequestShown(shown)
    if not self.frame then return end
    if InCombatLockdown() then
        if self.frame:IsShown() ~= shown then
            self.shownAfterCombat = shown
            Shatter.Print(shown and "Shatter opens when combat ends." or "Shatter closes when combat ends.")
        elseif self.shownAfterCombat ~= nil then
            self.shownAfterCombat = nil
            Shatter.Print(shown and "Shatter stays open." or "Shatter stays closed.")
        end
        return
    end
    self.shownAfterCombat = nil
    if shown then self.frame:Show() else self.frame:Hide() end
end

function MainFrame:OnCombatEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Escape runs CloseSpecialWindows over UISpecialFrames; an entry an
        -- addon put there taints that pass, and Hide() on this protected
        -- frame would then be blocked. Leave the list for the fight.
        SetEscapeCloses(false)
        -- This event arrives just before lockdown: finish a drag while we can.
        if self.frame and not InCombatLockdown() then
            if self.resizeGrip and self.resizeGrip.scaling then
                self.resizeGrip.scaling = nil
                self.resizeGrip:SetScript("OnUpdate", nil)
            end
            self.frame:StopMovingOrSizing()
            self:SaveGeometry()
        end
        return
    end

    -- PLAYER_REGEN_ENABLED: apply everything that waited.
    SetEscapeCloses(true)
    if not self.frame then return end
    if self.stopMovingAfterCombat then
        self.stopMovingAfterCombat = nil
        self.frame:StopMovingOrSizing()
        self.saveGeometryAfterCombat = true
    end
    if self.resetGeometryAfterCombat then
        self.resetGeometryAfterCombat = nil
        self.applyWindowAfterCombat = nil
        self:ResetGeometry()
    elseif self.applyWindowAfterCombat then
        self.applyWindowAfterCombat = nil
        self:ApplyPosition()
    end
    if self.saveGeometryAfterCombat then
        self.saveGeometryAfterCombat = nil
        self:SaveGeometry()
    end
    if self.shownAfterCombat ~= nil then
        local shown = self.shownAfterCombat
        self.shownAfterCombat = nil
        if shown and not Shatter.isActive then shown = false end
        self:RequestShown(shown)
    end
    if self.layoutAfterCombat then
        self.layoutAfterCombat = nil
        self:Layout()
    end
    if self.updateAfterCombat then
        self.updateAfterCombat = nil
        -- Re-apply the current view: it decides which protected widgets are
        -- shown (Shatter Next among them), then refreshes their state.
        self:SetActiveView(self.activeView)
        self:Update()
    end
end

function MainFrame:Create()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "ShatterMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    frame:EnableMouse(true)
    frame:Hide()
    Shatter.Skin.Window(frame, Shatter.C.BG_MAIN)
    SetEscapeCloses(true)
    self.frame = frame

    if Shatter.Database then Shatter.Database:ApplyWindow(frame) end

    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(TITLE_H)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        frame:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        if InCombatLockdown() then
            self.stopMovingAfterCombat = true
            return
        end
        frame:StopMovingOrSizing()
        if Shatter.Database then Shatter.Database:SaveWindow(frame) end
    end)

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(unpack(Shatter.C.BG_HEADER))
    Shatter.Skin.Band(titleBg)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    title:SetText("Shatter")
    Shatter.SetTextColor(title, Shatter.C.ACCENT)
    self.title = title

    local simBadge = CreateFrame("Frame", nil, titleBar, "BackdropTemplate")
    simBadge:SetSize(72, 15)
    simBadge:SetPoint("LEFT", title, "RIGHT", 8, 0)
    Shatter.ApplyBackdrop(simBadge, 0.16, 0.10, 0.02, 0.88)
    simBadge:SetBackdropBorderColor(0.70, 0.48, 0.07, 0.78)
    simBadge.text = simBadge:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    simBadge.text:SetAllPoints()
    simBadge.text:SetJustifyH("CENTER")
    simBadge.text:SetText("SIMULATION")
    simBadge.text:SetTextColor(1.00, 0.78, 0.18, 0.95)
    simBadge:Hide()
    self.simBadge = simBadge

    local iconReserve = CreateFrame("Frame", nil, titleBar, "BackdropTemplate")
    iconReserve:SetSize(22, 22)
    iconReserve:SetPoint("LEFT", titleBar, "LEFT", 8, 0)
    Shatter.ApplyBackdrop(iconReserve, 0.03, 0.03, 0.03, 1)
    local headerIcon = iconReserve:CreateTexture(nil, "ARTWORK")
    headerIcon:SetPoint("CENTER", iconReserve, "CENTER", 0, 0)
    headerIcon:SetSize(18, 18)
    headerIcon:SetTexture("Interface\\Icons\\INV_Enchant_ShardBrilliantLarge")
    headerIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local close = CreateButton(titleBar, "x", 22)
    self.closeButton = close
    close:SetPoint("RIGHT", titleBar, "RIGHT", -7, 0)
    close:SetScript("OnClick", function() self:RequestShown(false) end)

    local tabSolo = CreateButton(frame, "Solo", 68)
    tabSolo:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -TITLE_H - 7)
    Shatter.Skin.Paint(tabSolo, "active")
    Shatter.SetTextColor(tabSolo.text, Shatter.C.ACCENT)
    tabSolo:SetScript("OnClick", function() self:SetActiveView("solo") end)
    self.tabSolo = tabSolo

    local tabMail = CreateButton(frame, "Mail", 68)
    self.tabMail = tabMail
    tabMail:SetPoint("LEFT", tabSolo, "RIGHT", 6, 0)
    Shatter.Skin.Paint(tabMail, "dim")
    Shatter.SetTextColor(tabMail.text, Shatter.C.TEXT_DIM)
    tabMail:SetScript("OnClick", function()
        if Shatter.MailMode and Shatter.MailMode:IsAvailable() then
            self:SetActiveView("mail")
        else
            self:SetStatus("Open the mailbox to start Mail Mode.", false, 3)
        end
    end)
    tabMail:SetScript("OnEnter", function(selfButton)
        Shatter.Skin.Hover(selfButton, true)
        GameTooltip:SetOwner(selfButton, "ANCHOR_RIGHT")
        GameTooltip:SetText("Mail Mode", 1, 0.82, 0)
        GameTooltip:AddLine("Opens automatically at the mailbox. Sessions stay active until you close them.", 0.82, 0.82, 0.82, true)
        GameTooltip:Show()
    end)
    tabMail:SetScript("OnLeave", function(selfButton)
        Shatter.Skin.Hover(selfButton, false)
        MainFrame:UpdateTabs()
        GameTooltip:Hide()
    end)

    local tabRaid = CreateButton(frame, "Raid", 68)
    self.tabRaid = tabRaid
    tabRaid:SetPoint("LEFT", tabMail, "RIGHT", 6, 0)
    Shatter.Skin.Paint(tabRaid, "dim")
    Shatter.SetTextColor(tabRaid.text, Shatter.C.TEXT_DIM)
    tabRaid:SetScript("OnClick", function() self:SetStatus("Raid / Trade Mode is planned for Phase 4.", false) end)
    tabRaid:SetScript("OnEnter", function(selfButton)
        Shatter.Skin.Hover(selfButton, true)
        GameTooltip:SetOwner(selfButton, "ANCHOR_RIGHT")
        GameTooltip:SetText("Raid / Trade Mode", 1, 0.82, 0)
        GameTooltip:AddLine("Planned for Phase 4. Disabled in the Phase 1 Solo MVP.", 0.82, 0.82, 0.82, true)
        GameTooltip:Show()
    end)
    tabRaid:SetScript("OnLeave", function(selfButton)
        Shatter.Skin.Hover(selfButton, false)
        MainFrame:UpdateTabs()
        GameTooltip:Hide()
    end)

    local queuePanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    queuePanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -76)
    queuePanel:SetSize(350, 252)
    Shatter.Skin.Pane(queuePanel, Shatter.C.BG_PANEL)
    self.queuePanel = queuePanel

    local queueTitle = queuePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    queueTitle:SetPoint("TOPLEFT", queuePanel, "TOPLEFT", 8, -7)
    queueTitle:SetText("Queue")
    Shatter.SetTextColor(queueTitle, Shatter.C.ACCENT)
    self.queueTitle = queueTitle

    local queueScroll = CreateFrame("ScrollFrame", nil, queuePanel, "UIPanelScrollFrameTemplate")
    queueScroll:SetPoint("TOPLEFT", queuePanel, "TOPLEFT", 6, -30)
    queueScroll:SetPoint("BOTTOMRIGHT", queuePanel, "BOTTOMRIGHT", -25, 7)
    queueScroll:EnableMouseWheel(true)
    queueScroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local maxScroll = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, current - delta * 24)))
    end)
    self.queueScroll = queueScroll

    local queueContent = CreateFrame("Frame", nil, queueScroll)
    queueContent:SetSize(1, 1)
    queueScroll:SetScrollChild(queueContent)
    queueScroll:SetScript("OnSizeChanged", function(self)
        queueContent:SetWidth(math.max(1, self:GetWidth()))
    end)
    self.queueContent = queueContent

    local previous
    for i = 1, ROWS do
        local row = Shatter.Rows.CreateQueueRow(queueContent, i)
        row:SetPoint("LEFT", queueContent, "LEFT", 0, 0)
        row:SetPoint("RIGHT", queueContent, "RIGHT", 0, 0)
        if previous then
            row:SetPoint("TOP", previous, "BOTTOM", 0, -2)
        else
            row:SetPoint("TOP", queueContent, "TOP", 0, 0)
        end
        self.rows[i] = row
        previous = row
    end

    local detailPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    detailPanel:SetPoint("TOPLEFT", queuePanel, "TOPRIGHT", 8, 0)
    detailPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, CONTENT_BOTTOM)
    Shatter.Skin.Pane(detailPanel, Shatter.C.BG_PANEL)
    self.detailPanel = detailPanel

    detailPanel.selectedLabel = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detailPanel.selectedLabel:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 8, -9)
    detailPanel.selectedLabel:SetPoint("RIGHT", detailPanel, "RIGHT", -10, 0)
    detailPanel.selectedLabel:SetJustifyH("LEFT")
    detailPanel.selectedLabel:SetText("")

    detailPanel.selectedMeta = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailPanel.selectedMeta:SetPoint("TOPLEFT", detailPanel.selectedLabel, "BOTTOMLEFT", 0, -5)
    detailPanel.selectedMeta:SetPoint("RIGHT", detailPanel, "RIGHT", -10, 0)
    detailPanel.selectedMeta:SetJustifyH("LEFT")

    local detailScroll = CreateFrame("ScrollFrame", nil, detailPanel, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT", detailPanel.selectedMeta, "BOTTOMLEFT", 0, -14)
    detailScroll:SetPoint("BOTTOMRIGHT", detailPanel, "BOTTOMRIGHT", -25, 102)
    detailScroll:EnableMouseWheel(true)
    detailScroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local maxScroll = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, current - delta * 20)))
    end)
    detailPanel.scroll = detailScroll

    local detailContent = CreateFrame("Frame", nil, detailScroll)
    detailContent:SetSize(1, 150)
    detailScroll:SetScrollChild(detailContent)
    detailScroll:SetScript("OnSizeChanged", function(self)
        detailContent:SetWidth(math.max(1, self:GetWidth()))
    end)
    detailPanel.content = detailContent

    detailPanel.materialLabel = detailContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detailPanel.materialLabel:SetPoint("TOPLEFT", detailContent, "TOPLEFT", 0, 0)
    detailPanel.materialLabel:SetText("Expected Materials")
    Shatter.SetTextColor(detailPanel.materialLabel, Shatter.C.ACCENT)

    detailPanel.materialEmpty = CreateDetailText(detailContent, "GameFontDisableSmall")
    detailPanel.materialEmpty:SetPoint("TOPLEFT", detailPanel.materialLabel, "BOTTOMLEFT", 0, -3)
    detailPanel.materialEmpty:SetPoint("RIGHT", detailContent, "RIGHT", -4, 0)
    detailPanel.materialEmpty:SetText("Unavailable until disenchant tables are added.")

    detailPanel.materialRows = {}
    local previousMaterial
    for i = 1, 3 do
        local row = CreateFrame("Frame", nil, detailContent)
        row:SetHeight(24)
        row:SetPoint("LEFT", detailContent, "LEFT", 0, 0)
        row:SetPoint("RIGHT", detailContent, "RIGHT", -4, 0)
        if previousMaterial then
            row:SetPoint("TOP", previousMaterial, "BOTTOM", 0, -1)
        else
            row:SetPoint("TOP", detailPanel.materialLabel, "BOTTOM", 0, -4)
        end

        row.chance = CreateDetailText(row, "GameFontDisableSmall")
        row.chance:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        row.chance:SetWidth(29)
        row.chance:SetJustifyH("RIGHT")

        row.iconBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
        row.iconBorder:SetSize(16, 16)
        row.iconBorder:SetPoint("TOPLEFT", row.chance, "TOPRIGHT", 7, 0)
        Shatter.ApplyBackdrop(row.iconBorder, 0, 0, 0, 1)
        row.icon = row.iconBorder:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(14, 14)
        row.icon:SetPoint("CENTER", row.iconBorder, "CENTER", 0, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.name = CreateDetailText(row, "GameFontDisableSmall")
        row.name:SetPoint("TOPLEFT", row.iconBorder, "TOPRIGHT", 7, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetNonSpaceWrap(false)

        row.meta = CreateDetailText(row, "GameFontDisableSmall")
        row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
        row.meta:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.meta:SetJustifyH("LEFT")
        row.meta:SetTextColor(0.62, 0.62, 0.62, 1)

        row.frame = row
        detailPanel.materialRows[i] = row
        previousMaterial = row
    end

    detailPanel.valueLabel = CreateDetailLabel(detailContent, detailPanel.materialRows[3], 0, -8, "Value")
    detailPanel.valueText = CreateDetailText(detailContent, "GameFontDisableSmall")
    detailPanel.valueText:SetPoint("TOPLEFT", detailPanel.valueLabel, "BOTTOMLEFT", 0, -2)
    detailPanel.valueText:SetPoint("RIGHT", detailContent, "RIGHT", -4, 0)
    detailPanel.valueText:SetNonSpaceWrap(false)
    detailPanel.valueText:SetText("Unavailable")

    detailPanel.sessionLabel = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detailPanel.sessionLabel:SetPoint("BOTTOMLEFT", detailPanel, "BOTTOMLEFT", 8, 82)
    detailPanel.sessionLabel:SetText("Session")
    Shatter.SetTextColor(detailPanel.sessionLabel, Shatter.C.ACCENT)

    detailPanel.sessionText = CreateDetailText(detailPanel, "GameFontHighlightSmall")
    detailPanel.sessionText:SetPoint("TOPLEFT", detailPanel.sessionLabel, "BOTTOMLEFT", 0, -2)
    detailPanel.sessionText:SetPoint("RIGHT", detailPanel, "RIGHT", -10, 0)
    detailPanel.sessionText:SetNonSpaceWrap(false)

    local generated = CreateFrame("Frame", nil, detailPanel)
    generated:SetPoint("BOTTOMLEFT", detailPanel, "BOTTOMLEFT", 8, 8)
    generated:SetPoint("BOTTOMRIGHT", detailPanel, "BOTTOMRIGHT", -8, 8)
    generated:SetHeight(54)
    detailPanel.generated = generated

    generated.label = generated:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    generated.label:SetPoint("TOPLEFT", generated, "TOPLEFT", 0, 0)
    generated.label:SetText("Generated")
    Shatter.SetTextColor(generated.label, Shatter.C.ACCENT)

    detailPanel.generatedEmpty = CreateDetailText(generated, "GameFontDisableSmall")
    detailPanel.generatedEmpty:SetPoint("TOPLEFT", generated.label, "BOTTOMLEFT", 0, -8)
    detailPanel.generatedEmpty:SetText("No materials yet")

    detailPanel.generatedSlots = {}
    local previousGeneratedSlot
    for i = 1, 4 do
        local slot = CreateFrame("Button", nil, generated, "BackdropTemplate")
        slot:SetSize(26, 34)
        if previousGeneratedSlot then
            slot:SetPoint("LEFT", previousGeneratedSlot, "RIGHT", 10, 0)
        else
            slot:SetPoint("TOPLEFT", generated.label, "BOTTOMLEFT", 0, -4)
        end
        Shatter.ApplyBackdrop(slot, 0, 0, 0, 1)
        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetSize(22, 22)
        slot.icon:SetPoint("TOP", slot, "TOP", 0, -2)
        slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        slot.count = slot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        slot.count:SetPoint("TOP", slot.icon, "BOTTOM", 0, -1)
        slot.count:SetTextColor(0.86, 0.86, 0.86, 1)
        slot:SetScript("OnEnter", function(self)
            if self.itemLink and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.itemLink)
                GameTooltip:Show()
            end
        end)
        slot:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        slot:Hide()
        detailPanel.generatedSlots[i] = slot
        previousGeneratedSlot = slot
    end

    detailPanel.generatedMore = generated:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detailPanel.generatedMore:SetPoint("LEFT", previousGeneratedSlot, "RIGHT", 10, 5)
    detailPanel.generatedMore:SetTextColor(1.00, 0.82, 0.18, 1)
    detailPanel.generatedMore:Hide()

    local castBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    castBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 48)
    castBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 48)
    castBar:SetHeight(14)
    Shatter.Skin.Fill(castBar, "track", "normal")
    castBar.fill = castBar:CreateTexture(nil, "ARTWORK")
    castBar.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    castBar.fill:SetColorTexture(0.85, 0.58, 0.10, 0.78)
    castBar.fill:SetPoint("TOPLEFT", castBar, "TOPLEFT", 1, -1)
    castBar.fill:SetPoint("BOTTOMLEFT", castBar, "BOTTOMLEFT", 1, 1)
    castBar.fill:SetWidth(1)
    castBar.label = castBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    castBar.label:SetPoint("LEFT", castBar, "LEFT", 6, 0)
    castBar.label:SetPoint("RIGHT", castBar, "RIGHT", -6, 0)
    castBar.label:SetJustifyH("LEFT")
    castBar.label:SetTextColor(1.00, 0.82, 0.18, 1)
    castBar:Hide()
    self.castBar = castBar

    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 10)
    footer:SetHeight(32)
    self.footer = footer

    self.status = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.status:SetPoint("LEFT", footer, "LEFT", 0, 0)
    self.status:SetPoint("RIGHT", footer, "RIGHT", -410, 0)
    self.status:SetJustifyH("LEFT")

    local settings = CreateButton(footer, "Settings", 78)
    settings:SetPoint("RIGHT", footer, "RIGHT", 0, 0)
    settings:SetScript("OnClick", function()
        if self.activeView == "settings" or self.activeView == "summary" then
            if Shatter.MailMode and Shatter.MailMode:IsAvailable() then
                self:SetActiveView("mail")
            else
                self:SetActiveView("solo")
            end
        elseif Shatter.SettingsUI then
            Shatter.SettingsUI:Toggle()
        end
    end)
    self.settingsButton = settings

    local summary = CreateButton(footer, "Summary", 78)
    summary:SetPoint("RIGHT", settings, "LEFT", -6, 0)
    summary:SetScript("OnClick", function()
        if Shatter.SummaryUI then Shatter.SummaryUI:Toggle() end
    end)
    self.summaryButton = summary

    local skip = CreateButton(footer, "Skip", 58)
    skip:SetPoint("RIGHT", summary, "LEFT", -6, 0)
    skip:SetScript("OnClick", function()
        if Shatter.Queue then Shatter.Queue:SkipSelected() end
    end)
    self.skipButton = skip

    local ignore = CreateButton(footer, "Ignore", 64)
    ignore:SetPoint("RIGHT", skip, "LEFT", -6, 0)
    ignore:SetScript("OnClick", function()
        if Shatter.Queue then Shatter.Queue:IgnoreSelected() end
    end)
    self.ignoreButton = ignore

    local primary = CreateButton(footer, "Shatter Next", 110, true)
    primary:SetPoint("RIGHT", ignore, "LEFT", -8, 0)
    primary:SetHeight(30)
    Shatter.Skin.Paint(primary, "go")
    primary:SetScript("PreClick", function(button, mouseButton, down)
        -- Every registered edge and mouse button arrives here; only the one
        -- the secure handler acts on may arm or change state.
        if not Shatter.Disenchant or not Shatter.Disenchant:IsActionEdge(mouseButton, down) then return end
        -- Only the Solo and Mail views act; Settings and Summary hide the queue.
        if self.activeView ~= "solo" and self.activeView ~= "mail" then
            Shatter.Disenchant:Disarm(button)
            return
        end
        if self.activeView == "mail" then
            local label = Shatter.MailMode and Shatter.MailMode:GetPrimaryState()
            if label == "Shatter Next" then
                Shatter.Disenchant:BeginSecureClick(button)
            else
                Shatter.Disenchant:Disarm(button)
            end
        elseif Shatter.Disenchant then
            Shatter.Disenchant:BeginSecureClick(button)
        end
    end)
    primary:SetScript("PostClick", function(button, mouseButton, down)
        if not Shatter.Disenchant or not Shatter.Disenchant:IsActionEdge(mouseButton, down) then return end
        -- The secure action has run (or not); never leave the button armed.
        Shatter.Disenchant:Disarm(button)
        if self.activeView == "mail" and Shatter.MailMode then
            local label = Shatter.MailMode:GetPrimaryState()
            if label ~= "Shatter Next" then
                Shatter.MailMode:HandlePrimaryClick()
            end
        end
        self:Update()
    end)
    self.primary = primary
    if Shatter.Disenchant then Shatter.Disenchant:SetButton(primary) end

    self.resizeGrip = self:CreateResizeGrip(frame)

    if Shatter.MailFrame then Shatter.MailFrame:Create(frame) end
    if Shatter.SettingsUI then Shatter.SettingsUI:Create(frame) end
    if Shatter.SummaryUI then Shatter.SummaryUI:Create(frame) end

    frame:SetScript("OnSizeChanged", function()
        self:Layout()
    end)

    frame:SetScript("OnShow", function()
        if Shatter.SoloMode then Shatter.SoloMode:ScheduleScan("WINDOW_OPENED", 0.05) end
        self:Layout()
        self:Update()
    end)

    self:Layout()

    return frame
end

function MainFrame:ApplyPosition()
    if InCombatLockdown() then
        self.applyWindowAfterCombat = true
        return
    end
    if self.frame and Shatter.Database then
        Shatter.Database:ApplyWindow(self.frame)
        self:Layout()
    end
end

function MainFrame:Show()
    if not Shatter.isActive then return end
    self:Create()
    self:RequestShown(true)
end

function MainFrame:Toggle()
    if not Shatter.isActive then return end
    self:Create()
    -- In combat a second toggle inverts the queued request, not the frame.
    local shown = self.shownAfterCombat
    if shown == nil then shown = self.frame:IsShown() end
    self:RequestShown(not shown)
end

function MainFrame:SetStatus(text, isError, duration)
    self.statusOverride = text
    self.statusIsError = isError and true or false
    if duration and duration > 0 then
        self.stickyStatus = text
        self.stickyStatusIsError = isError and true or false
        self.stickyStatusUntil = (GetTime and GetTime() or 0) + duration
    end
    if self.status then
        self.status:SetText(text or "")
        Shatter.SetTextColor(self.status, isError and Shatter.C.BAD or Shatter.C.TEXT_NORM)
    end
end

function MainFrame:SetSettingsOpen(open)
    self:SetActiveView(open and "settings" or "solo")
end

function MainFrame:SetActiveView(view)
    local previous = self.activeView
    self.activeView = view or "solo"
    -- The view decides who owns the queue: Solo takes it back from a Mail
    -- session (the mail items stay attributed in the session and return when
    -- the Mail view is opened again).
    if Shatter.Queue then
        if self.activeView == "solo" and Shatter.Queue:GetOwner() == "mail" then
            Shatter.Queue:ReleaseToSolo("SOLO_VIEW")
        elseif self.activeView == "mail" and previous ~= "mail" and Shatter.MailSession and Shatter.MailMode then
            local session = Shatter.MailSession:Get()
            if session and session.status == Shatter.Constants.MAIL_STATE.READY_TO_DISENCHANT then
                Shatter.MailMode:PrepareDisenchantQueue()
            end
        end
    end
    self.settingsOpen = self.activeView == "settings"
    local summaryOpen = self.activeView == "summary"
    local settings = Shatter.Database and Shatter.Database:GetSettings()
    local simulation = settings and settings.debug and settings.simulateDisenchant
    local isSolo = self.activeView == "solo"
    local isMail = self.activeView == "mail"

    SetShown(self.queuePanel, isSolo)
    SetShown(self.detailPanel, isSolo)
    SetShown(Shatter.MailFrame and Shatter.MailFrame.frame, isMail)
    SetShown(self.primary, isSolo or isMail)
    SetShown(self.ignoreButton, isSolo or isMail)
    SetShown(self.skipButton, isSolo or isMail)
    SetShown(self.summaryButton, self.activeView ~= "settings")
    SetShown(self.status, self.activeView ~= "settings")

    if self.settingsButton and self.settingsButton.text then
        self.settingsButton.text:SetText((isSolo or isMail) and "Settings" or "Back")
    end
    if Shatter.SettingsUI and Shatter.SettingsUI.frame then
        SetShown(Shatter.SettingsUI.frame, self.activeView == "settings")
    end
    if Shatter.SummaryUI and Shatter.SummaryUI.frame then
        SetShown(Shatter.SummaryUI.frame, summaryOpen)
        if summaryOpen then Shatter.SummaryUI:Refresh() end
    end

    self:UpdateTabs()

    if isMail then
        if Shatter.MailFrame then Shatter.MailFrame:Refresh() end
        self:Update()
    elseif simulation then
        self:SetStatus("Simulation mode enabled - no items will be disenchanted.", false)
    elseif self.settingsOpen then
        self:SetStatus("", false)
    elseif summaryOpen then
        self:SetStatus("Summary", false)
    else
        self:Update()
    end
end

function MainFrame:UpdateTabs()
    -- `idle`: the state of an available tab that isn't the current view. Solo
    -- is an ordinary button; Mail and Raid have their own hover.
    local function Style(button, active, disabled, idle)
        if not button then return end
        if active then
            Shatter.Skin.Paint(button, "active")
            Shatter.SetTextColor(button.text, Shatter.C.ACCENT)
        elseif disabled then
            Shatter.Skin.Paint(button, "dim")
            Shatter.SetTextColor(button.text, Shatter.C.TEXT_DIM)
        else
            Shatter.Skin.Paint(button, idle)
            Shatter.SetTextColor(button.text, Shatter.C.TEXT_NORM)
        end
    end
    Style(self.tabSolo, self.activeView == "solo", false, "normal")
    Style(self.tabMail, self.activeView == "mail", not (Shatter.MailMode and Shatter.MailMode:IsAvailable()), "tab")
    Style(self.tabRaid, false, true, "tab")
end

function MainFrame:GetBaseStatus()
    if self.activeView == "mail" and Shatter.MailMode then
        return Shatter.MailMode:GetStatus()
    end
    local settings = Shatter.Database and Shatter.Database:GetSettings()
    settings = settings or {}
    local simulation = settings.debug and settings.simulateDisenchant
    if Shatter.Disenchant and Shatter.Disenchant:HasPending() then
        return Shatter.Constants.STATUS.WAITING_RESULT, false
    end
    if simulation then
        return "Simulation mode enabled - no items will be disenchanted.", false
    end
    if Shatter.ItemScanner and not simulation and not Shatter.ItemScanner:HasDisenchantSpell() then
        return Shatter.Constants.STATUS.MISSING_ENCHANTING, true
    end
    if not Shatter.Queue or Shatter.Queue:Count() == 0 then
        return Shatter.Constants.STATUS.NO_ITEMS, false
    end
    return Shatter.Constants.STATUS.READY, false
end

function MainFrame:Update()
    if not self.frame then return end
    local settings = Shatter.Database and Shatter.Database:GetSettings()
    settings = settings or {}
    local simulation = settings.debug and settings.simulateDisenchant
    SetShown(self.simBadge, simulation)
    self:UpdateTabs()

    if self.activeView == "mail" then
        if Shatter.MailFrame then Shatter.MailFrame:Refresh() end
        local now = GetTime and GetTime() or 0
        local status, isError = self:GetBaseStatus()
        if self.stickyStatus and now < (self.stickyStatusUntil or 0) then
            status, isError = self.stickyStatus, self.stickyStatusIsError
        else
            self.stickyStatus = nil
            if self.statusOverride then
                status, isError = self.statusOverride, self.statusIsError
            end
        end
        self:SetStatus(status, isError)
        self.statusOverride = nil
        self.statusIsError = false

        local label, enabled
        if Shatter.MailMode then
            label, enabled = Shatter.MailMode:GetPrimaryState()
        end
        local pending = Shatter.Disenchant and Shatter.Disenchant:HasPending()
        if pending then
            label, enabled = "Waiting...", false
        end
        if self.primary then
            self.primary.text:SetText(label or "Scan Inbox")
            if label == "Open Mailbox" then
                self.primary.mailDisabledReason = "Open the Blizzard mailbox to take the selected attachments."
            elseif (label == "Take Attachments" or label == "Shatter Next") and Shatter.MailMode and not Shatter.MailMode:AreActionsEnabled() then
                self.primary.mailDisabledReason = Shatter.Constants.STATUS.MAIL_ACTIONS_DISABLED
            else
                self.primary.mailDisabledReason = nil
            end
            if enabled then
                SetButtonEnabled(self.primary, true)
                Shatter.SetTextColor(self.primary.text, Shatter.C.ACCENT)
                Shatter.Skin.Paint(self.primary, "go")
            else
                SetButtonEnabled(self.primary, false)
                Shatter.SetTextColor(self.primary.text, Shatter.C.TEXT_DIM)
                Shatter.Skin.Paint(self.primary, "goOff")
            end
        end
        SetShown(self.ignoreButton, false)
        SetShown(self.skipButton, label == "Shatter Next" and not pending)
        return
    end

    if self.activeView ~= "solo" then
        if simulation then
            self:SetStatus("Simulation mode enabled - no items will be disenchanted.", false)
        else
            self:SetStatus(self.activeView == "settings" and "" or "Summary", false)
        end
        return
    end

    local items = Shatter.Queue and Shatter.Queue:GetItems() or {}
    local selected = Shatter.Queue and Shatter.Queue:GetSelected()
    local itemCount = #items

    if self.queueTitle then
        self.queueTitle:SetText(string.format("Queue (%d)", itemCount))
    end
    self:EnsureQueueRows(itemCount)
    if self.queueContent then
        self.queueContent:SetHeight(math.max(1, itemCount * 36))
    end
    if self.queueScroll then
        local maxScroll = self.queueScroll:GetVerticalScrollRange() or 0
        if (self.queueScroll:GetVerticalScroll() or 0) > maxScroll then
            self.queueScroll:SetVerticalScroll(maxScroll)
        end
    end

    for i, row in ipairs(self.rows) do
        row.index = i
        row:SetItem(items[i])
        row:SetSelected(i == (Shatter.Queue and Shatter.Queue.selectedIndex or 1))
    end

    local detail = self.detailPanel
    if selected then
        local qualityLabel = Shatter.Constants.QUALITY_LABELS[selected.quality] or ("Quality " .. tostring(selected.quality or "?"))
        detail.selectedLabel:SetText("Selected Item")
        Shatter.SetTextColor(detail.selectedLabel, Shatter.C.ACCENT)
        detail.selectedMeta:SetText(string.format("%s - Item Level %s - Bag %d, Slot %d%s", qualityLabel, tostring(selected.itemLevel or "?"), selected.bag or 0, selected.slot or 0, selected.isSoulbound and " - Soulbound" or ""))
        UpdateDetailSections(detail, selected)
    else
        if HasSessionWork() then
            detail.selectedLabel:SetText("Queue complete")
            Shatter.SetTextColor(detail.selectedLabel, Shatter.C.ACCENT)
            detail.selectedMeta:SetText(select(1, GetSessionSummary()) .. "   " .. select(2, GetSessionSummary()))
        else
            detail.selectedLabel:SetText("No eligible items")
            Shatter.SetTextColor(detail.selectedLabel, Shatter.C.ACCENT)
            detail.selectedMeta:SetText("No disenchantable items match your current settings.")
        end
        UpdateDetailSections(detail, nil)
    end
    UpdateGenerated(detail)

    local now = GetTime and GetTime() or 0
    local status, isError
    if self.stickyStatus and now < (self.stickyStatusUntil or 0) then
        status, isError = self.stickyStatus, self.stickyStatusIsError
    else
        self.stickyStatus = nil
        status, isError = self:GetBaseStatus()
        if self.statusOverride then
            status, isError = self.statusOverride, self.statusIsError
        end
    end
    self:SetStatus(status, isError)
    self.statusOverride = nil
    self.statusIsError = false

    local pending = Shatter.Disenchant and Shatter.Disenchant:HasPending()
    local canAct = selected and Shatter.ItemScanner and (simulation or Shatter.ItemScanner:HasDisenchantSpell()) and not (Shatter.Disenchant and Shatter.Disenchant:HasPending())
    SetShown(self.ignoreButton, not pending)
    SetShown(self.skipButton, not pending)
    if self.primary then
        local label = simulation and "Simulate Next" or "Shatter Next"
        self.primary.text:SetText(pending and "Waiting..." or label)
        if canAct then
            SetButtonEnabled(self.primary, true)
            Shatter.SetTextColor(self.primary.text, Shatter.C.ACCENT)
            Shatter.Skin.Paint(self.primary, "go")
        else
            SetButtonEnabled(self.primary, false)
            Shatter.SetTextColor(self.primary.text, Shatter.C.TEXT_DIM)
            Shatter.Skin.Paint(self.primary, "goOff")
        end
    end
end
