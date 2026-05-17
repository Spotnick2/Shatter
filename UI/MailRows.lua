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
    row:SetHeight(38)
    row.index = index
    Shatter.ApplyBackdrop(row, unpack(index % 2 == 0 and Shatter.C.BG_ROW_EVEN or Shatter.C.BG_ROW_ODD))

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(22, 22)
    row.check:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.check:SetScript("OnClick", function(self)
        if row.mail then
            row.mail.selected = self:GetChecked() and true or false
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

    row.sender = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.sender:SetPoint("LEFT", row.iconBorder, "RIGHT", 8, 6)
    row.sender:SetPoint("RIGHT", row, "RIGHT", -130, 6)
    row.sender:SetJustifyH("LEFT")
    Shatter.SetTextColor(row.sender, Shatter.C.ACCENT)

    row.subject = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.subject:SetPoint("LEFT", row.iconBorder, "RIGHT", 8, -8)
    row.subject:SetPoint("RIGHT", row, "RIGHT", -130, -8)
    row.subject:SetJustifyH("LEFT")

    row.kind = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.kind:SetPoint("RIGHT", row, "RIGHT", -70, 0)
    row.kind:SetWidth(44)
    row.kind:SetJustifyH("CENTER")

    row.days = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.days:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.days:SetWidth(56)
    row.days:SetJustifyH("RIGHT")

    function row:SetMail(mail)
        self.mail = mail
        if not mail then
            self:Hide()
            return
        end
        self:Show()
        self.check:SetChecked(mail.selected)
        local first = mail.attachments and mail.attachments[1]
        self.icon:SetTexture(first and first.texture or "Interface\\Icons\\INV_Letter_15")
        local r, g, b = Shatter.GetQualityColor(first and first.quality)
        self.iconBorder:SetBackdropBorderColor(r, g, b, 1)
        self.sender:SetText(mail.sender or "Unknown")
        self.subject:SetText((first and (first.itemLink or first.itemName)) or mail.subject or "(no subject)")
        self.kind:SetText(mail.disenchantable and "*" or "-")
        self.kind:SetTextColor(mail.disenchantable and 0.65 or 0.55, mail.disenchantable and 1 or 0.55, mail.disenchantable and 0.20 or 0.55, 1)
        self.days:SetText(mail.daysLeft and string.format("%dd", math.floor(mail.daysLeft)) or "")
        ApplyStatusColor(self.sender, mail.status)
    end

    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(Shatter.C.BG_HOVER))
        if self.mail and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.mail.sender or "Mail", 1, 0.82, 0)
            GameTooltip:AddLine(self.mail.subject or "(no subject)", 0.82, 0.82, 0.82, true)
            GameTooltip:AddLine(self.mail.disenchantable and "Contains disenchantable attachment." or (self.mail.ineligibleReason or "Not disenchantable."), 0.82, 0.82, 0.82, true)
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
