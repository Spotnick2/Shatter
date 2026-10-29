local _, Shatter = ...

local Rows = {}
Shatter.Rows = Rows
Shatter.RegisterModule("Rows", Rows)

function Rows.CreateQueueRow(parent, index)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(34)
    row.index = index
    row.parity = index % 2 == 0 and "even" or "odd"
    Shatter.Skin.Fill(row, "row", row.parity)

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
        Shatter.Skin.Hover(self, true)
        if self.item and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.item.itemLink)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        Shatter.Skin.Hover(self, false)
        if GameTooltip then GameTooltip:Hide() end
    end)

    -- Flat: the row's border is its item's quality, dimmed.
    local function QualityBorder(self)
        if not self.item then return nil end
        local r, g, b = Shatter.GetQualityColor(self.item.quality)
        return { r * 0.45, g * 0.45, b * 0.45, 0.85 }
    end

    function row:SetSelected(selected)
        self.selected = selected
        Shatter.Skin.Paint(self, selected and "selected" or self.parity, QualityBorder(self))
        if selected then
            self.selectedStripe:Show()
            self.selectedStripe:SetWidth(3)
        else
            self.selectedStripe:Hide()
            self.selectedStripe:SetWidth(2)
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
        Shatter.Skin.Paint(self, self.selected and "selected" or self.parity, QualityBorder(self))
        self.iconBorder:SetBackdropBorderColor(r, g, b, 1)
        self.meta:SetText(string.format("Item Level %s  Bag %d, Slot %d", tostring(item.itemLevel or "?"), item.bag or 0, item.slot or 0))
    end

    return row
end
