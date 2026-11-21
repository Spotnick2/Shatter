local _, Shatter = ...

-- Asks once whether data saved under this character's first name alone is
-- its own (#73). Keys before #73 were "<name>-<realm>", and while the client
-- split UnitName the name was the first name, which another character may
-- share. Shatter's own frame, not a StaticPopup (Blizzard's popups can
-- taint), and never parented to the main frame.
local OldKeyPrompt = {}
Shatter.OldKeyPrompt = OldKeyPrompt

local function CreateButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, 24)
    Shatter.Skin.Fill(button, "button", "normal")
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.text:SetAllPoints()
    button.text:SetJustifyH("CENTER")
    button.text:SetText(text)
    Shatter.SetTextColor(button.text, Shatter.C.TEXT_NORM)
    button:SetScript("OnEnter", function(self) Shatter.Skin.Hover(self, true) end)
    button:SetScript("OnLeave", function(self) Shatter.Skin.Hover(self, false) end)
    return button
end

function OldKeyPrompt:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(380, 150)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -160)
    frame:SetFrameStrata("DIALOG")
    Shatter.Skin.Window(frame, Shatter.C.BG_PANEL)
    frame:Hide()
    self.frame = frame

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
    title:SetText("Shatter")
    Shatter.SetTextColor(title, Shatter.C.ACCENT)

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    text:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    self.text = text

    self.yes = CreateButton(frame, "Yes, they're mine", 150)
    self.yes:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -4, 12)
    self.yes:SetScript("OnClick", function() OldKeyPrompt:Answer(true) end)
    self.no = CreateButton(frame, "No", 150)
    self.no:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 4, 12)
    self.no:SetScript("OnClick", function() OldKeyPrompt:Answer(false) end)
    return frame
end

-- "Example", and the realms its keys name ("Realm" is the hotfix's
-- placeholder, not a realm).
local function Describe(keys)
    local first, realms, seen = nil, {}, {}
    for _, key in ipairs(keys) do
        local name, realm = key:match("^([^-]+)%-(.+)$")
        first = first or name
        if realm and realm ~= "Realm" and not seen[realm] then
            seen[realm] = true
            realms[#realms + 1] = realm
        end
    end
    return first or "?", realms
end

-- Shows the question when there is anything to ask; true if it did.
function OldKeyPrompt:Check()
    local db = Shatter.Database
    local fullName = db and db:GetFullName()
    if not fullName then return false end
    local keys = db:GetFirstNameKeys()
    if #keys == 0 then return false end
    self.keys = keys
    self:Create()
    local first, realms = Describe(keys)
    local where = #realms > 0 and (" (" .. table.concat(realms, ", ") .. ")") or ""
    self.text:SetText(string.format(
        "Shatter has settings or mail sessions saved for \"%s\"%s, from before the realm change of 2026-11-20. "
            .. "Another character with that first name may have saved them.\n\nAre they %s's?",
        first, where, fullName))
    self.frame:Show()
    return true
end

function OldKeyPrompt:Answer(mine)
    local keys = self.keys or {}
    self.keys = nil
    if self.frame then self.frame:Hide() end
    Shatter.Database:AnswerFirstNameKeys(keys, mine)
    if mine then
        Shatter.Print("Your earlier settings and mail sessions are back. Type /reload to apply them everywhere.")
    else
        Shatter.Print("Left for the character they belong to. Its mail items stay reserved, so Shatter won't disenchant them.")
    end
end
