local _, Shatter = ...

local MinimapButton = {
    button = nil,
}

Shatter.MinimapButton = MinimapButton
Shatter.RegisterModule("MinimapButton", MinimapButton)

local ICON = "Interface\\Icons\\INV_Enchant_ShardPrismaticLarge"
local DEFAULT_ANGLE = 225

local function GetSettings()
    local settings = Shatter.Database and Shatter.Database:GetSettings()
    settings.minimap = type(settings.minimap) == "table" and settings.minimap or {}
    if settings.minimap.hide == nil then settings.minimap.hide = false end
    settings.minimap.angle = tonumber(settings.minimap.angle) or DEFAULT_ANGLE
    return settings.minimap
end

local function PositionButton(button)
    local settings = GetSettings()
    local angle = settings.angle or DEFAULT_ANGLE
    local radius = 80
    local radians = math.rad(angle)
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * radius, math.sin(radians) * radius)
end

function MinimapButton:Initialize()
    self:Create()
    self:Refresh()
end

function MinimapButton:Create()
    if self.button then return self.button end

    local button = CreateFrame("Button", "ShatterMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button.overlay = button:CreateTexture(nil, "OVERLAY")
    button.overlay:SetSize(53, 53)
    button.overlay:SetPoint("TOPLEFT", button, "TOPLEFT")
    button.overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button.icon = button:CreateTexture(nil, "BACKGROUND")
    button.icon:SetSize(20, 20)
    button.icon:SetPoint("CENTER", button, "CENTER", 0, 1)
    button.icon:SetTexture(ICON)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            if Shatter.MainFrame then
                Shatter.MainFrame:Show()
                if Shatter.SettingsUI then Shatter.SettingsUI:Toggle() end
            end
        else
            Shatter.Toggle()
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Shatter", 1, 0.82, 0)
        GameTooltip:AddLine("Left-click to toggle Shatter.", 0.82, 0.82, 0.82)
        GameTooltip:AddLine("Right-click to open Settings.", 0.82, 0.82, 0.82)
        GameTooltip:AddLine("Drag to move this button.", 0.82, 0.82, 0.82)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            px, py = px / scale, py / scale
            local angle = math.deg(math.atan2(py - my, px - mx))
            GetSettings().angle = angle
            self:ClearAllPoints()
            PositionButton(self)
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        PositionButton(self)
    end)

    self.button = button
    PositionButton(button)
    return button
end

function MinimapButton:Refresh()
    local button = self:Create()
    local settings = GetSettings()
    PositionButton(button)
    if settings.hide then
        button:Hide()
    else
        button:Show()
    end
end

