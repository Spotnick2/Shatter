local _, Shatter = ...

local Rows = {}
Shatter.Rows = Rows
Shatter.RegisterModule("Rows", Rows)

function Rows.CreateQueueRow(parent, index)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(34)
    row.index = index
    Shatter.ApplyBackdrop(row, unpack(index % 2 == 0 and Shatter.C.BG_ROW_EVEN or Shatter.C.BG_ROW_ODD))

    row.selectedStripe = row:CreateTexture(nil, "OVERLAY")
    row.selectedStripe:SetWidth(2)
    row.selectedStripe:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    row.selectedStripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 1)
    row.selectedStripe:SetColorTexture(unpack(Shatter.C.ACCENT))
    row.selectedStripe:Hide()

    row.iconBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.iconBorder:SetSize(28, 28)
    row.iconBorder:SetPoint("LEFT", row, "LEFT", 7, 0)
    Shatter.ApplyBackdrop(row.iconBorder, 0, 0, 0, 1)

    row.icon = row.iconBorder:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    row.icon:SetPoint("CENTER", row.iconBorder, "CENTER", 0, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.iconBorder, "RIGHT", 8, 5)
    row.name:SetPoint("RIGHT", row, "RIGHT", -8, 5)
    row.name:SetJustifyH("LEFT")

    row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.meta:SetPoint("LEFT", row.iconBorder, "RIGHT", 8, -8)
    row.meta:SetPoint("RIGHT", row, "RIGHT", -8, -8)
    row.meta:SetJustifyH("LEFT")

    row:SetScript("OnClick", function(self)
        if Shatter.Queue then Shatter.Queue:Select(self.index) end
    end)
    row:SetScript("OnEnter", function(self)
        if not self.selected then
            self:SetBackdropColor(unpack(Shatter.C.BG_HOVER))
        end
        if self.item and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.item.itemLink)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        if not self.selected then
            local color = self.index % 2 == 0 and Shatter.C.BG_ROW_EVEN or Shatter.C.BG_ROW_ODD
            self:SetBackdropColor(unpack(color))
        end
        if GameTooltip then GameTooltip:Hide() end
    end)

    function row:SetSelected(selected)
        self.selected = selected
        if selected then
            self:SetBackdropColor(unpack(Shatter.C.BG_ACTIVE))
            self:SetBackdropBorderColor(0.55, 0.45, 0.05, 1)
            self.selectedStripe:Show()
        else
            local color = self.index % 2 == 0 and Shatter.C.BG_ROW_EVEN or Shatter.C.BG_ROW_ODD
            self:SetBackdropColor(unpack(color))
            if self.item then
                local r, g, b = Shatter.GetQualityColor(self.item.quality)
                self:SetBackdropBorderColor(r * 0.45, g * 0.45, b * 0.45, 0.85)
            else
                self:SetBackdropBorderColor(unpack(Shatter.C.BORDER))
            end
            self.selectedStripe:Hide()
        end
    end

    function row:SetItem(item)
        self.item = item
        if not item then
            self:Hide()
            return
        end
        self:Show()
        self.icon:SetTexture(item.texture or item.itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
        self.name:SetText(item.itemLink or item.itemName or "Unknown item")
        local r, g, b = Shatter.GetQualityColor(item.quality)
        self.name:SetTextColor(r, g, b)
        self:SetBackdropBorderColor(r * 0.45, g * 0.45, b * 0.45, 0.85)
        self.iconBorder:SetBackdropBorderColor(r, g, b, 1)
        self.meta:SetText(string.format("Item Level %s  Bag %d, Slot %d", tostring(item.itemLevel or "?"), item.bag or 0, item.slot or 0))
    end

    return row
end
