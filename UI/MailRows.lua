local _, Shatter = ...

local MailRows = {}
Shatter.MailRows = MailRows
Shatter.RegisterModule("MailRows", MailRows)

local function ApplyStatusColor(text, status)
    if status == "failed" or status == "unresolved" then
        text:SetTextColor(unpack(Shatter.C.BAD))
    elseif status == "taken" or status == "ready" or status == "sent" then
        text:SetTextColor(unpack(Shatter.C.GOOD))
    else
        text:SetTextColor(unpack(Shatter.C.ACCENT))
    end
end

function MailRows.CreateInputRow(parent, index)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(42)
    row.index = index
    Shatter.ApplyBackdrop(row, unpack(index % 2 == 0 and Shatter.C.BG_ROW_EVEN or Shatter.C.BG_ROW_ODD))

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(22, 22)
    row.check:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.check:SetScript("OnClick", function(self)
        if row.inputItem then
            row.inputItem.selected = self:GetChecked() and true or false
            if row.inputItem.status == "selected" or row.inputItem.status == "detected" then
                row.inputItem.status = row.inputItem.selected and "selected" or "detected"
            end
            if Shatter.MainFrame then Shatter.MainFrame:Update() end
        end
    end)

    row.iconBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.iconBorder:SetSize(30, 30)
    row.iconBorder:SetPoint("LEFT", row.check, "RIGHT", 5, 0)
    Shatter.ApplyBackdrop(row.iconBorder, 0, 0, 0, 1)
    row.icon = row.iconBorder:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("CENTER", row.iconBorder, "CENTER", 0, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.iconBorder, "RIGHT", 8, 7)
    row.name:SetPoint("RIGHT", row, "RIGHT", -92, 7)
    row.name:SetJustifyH("LEFT")

    row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.meta:SetPoint("LEFT", row.iconBorder, "RIGHT", 8, -9)
    row.meta:SetPoint("RIGHT", row, "RIGHT", -92, -9)
    row.meta:SetJustifyH("LEFT")

    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.status:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.status:SetWidth(80)
    row.status:SetJustifyH("RIGHT")

    function row:SetInputItem(item)
        self.inputItem = item
        if not item then
            self:Hide()
            return
        end
        self:Show()
        self.check:SetChecked(item.selected)
        self.icon:SetTexture(item.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        local r, g, b = Shatter.GetQualityColor(item.quality)
        self.iconBorder:SetBackdropBorderColor(r, g, b, 1)
        self.name:SetText(item.itemLink or item.itemName or "Unknown item")
        self.name:SetTextColor(r, g, b, 1)
        local days = item.daysLeft and string.format("%dd", math.floor(item.daysLeft)) or "?d"
        self.meta:SetText(string.format("From: %s - Mail %s - %s", item.sourceSender or "Unknown", tostring(item.lastKnownMailIndex or "?"), days))
        self.status:SetText(item.status or "detected")
        ApplyStatusColor(self.status, item.status)
    end

    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(Shatter.C.BG_HOVER))
        if self.inputItem and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.inputItem.itemLink then
                GameTooltip:SetHyperlink(self.inputItem.itemLink)
            else
                GameTooltip:SetText(self.inputItem.itemName or "Mail item", 1, 0.82, 0)
            end
            GameTooltip:AddLine("From: " .. tostring(self.inputItem.sourceSender or "Unknown"), 0.82, 0.82, 0.82, true)
            GameTooltip:AddLine("Subject: " .. tostring(self.inputItem.mailSubject or "(no subject)"), 0.82, 0.82, 0.82, true)
            GameTooltip:AddLine("Status: " .. tostring(self.inputItem.status or "detected"), 0.82, 0.82, 0.82, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        local color = self.index % 2 == 0 and Shatter.C.BG_ROW_EVEN or Shatter.C.BG_ROW_ODD
        self:SetBackdropColor(unpack(color))
        if GameTooltip then GameTooltip:Hide() end
    end)
    return row
end

function MailRows.CreateOutputRow(parent, index)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(44)
    row.index = index
    Shatter.ApplyBackdrop(row, unpack(index % 2 == 0 and Shatter.C.BG_ROW_EVEN or Shatter.C.BG_ROW_ODD))

    row.recipient = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.recipient:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -6)
    row.recipient:SetPoint("RIGHT", row, "RIGHT", -90, 0)
    row.recipient:SetJustifyH("LEFT")
    Shatter.SetTextColor(row.recipient, Shatter.C.ACCENT)

    row.materials = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.materials:SetPoint("TOPLEFT", row.recipient, "BOTTOMLEFT", 0, -4)
    row.materials:SetPoint("RIGHT", row, "RIGHT", -90, 0)
    row.materials:SetJustifyH("LEFT")

    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.status:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.status:SetWidth(78)
    row.status:SetJustifyH("RIGHT")

    function row:SetBucket(bucket)
        self.bucket = bucket
        if not bucket then
            self:Hide()
            return
        end
        self:Show()
        self.recipient:SetText(bucket.recipient or "Unknown")
        self.materials:SetText(Shatter.MaterialTracker and Shatter.MaterialTracker:Format(bucket.materialsGenerated) or "No materials yet")
        self.status:SetText(bucket.status or "waiting")
        ApplyStatusColor(self.status, bucket.status)
    end

    return row
end
