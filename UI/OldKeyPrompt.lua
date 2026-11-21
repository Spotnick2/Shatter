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

-- What one old key says: the first name, and where it was saved ("Realm" is
-- the hotfix's placeholder, not a realm).
local function Describe(key)
    local name, realm = key:match("^([^-]+)%-(.+)$")
    if realm == "Realm" then
        return name or "?", "after the realm change of 2026-11-20, so with no realm"
    end
    return name or "?", "on " .. (realm or "?") .. ", before the realm change of 2026-11-20"
end

-- One old key at a time: two characters sharing a first name may each own
-- one of them (Codex on #74), so each is answered on its own.
function OldKeyPrompt:ShowNext()
    local key = self.keys and self.keys[1]
    if not key then
        self.keys = nil
        if self.frame then self.frame:Hide() end
        return false
    end
    self:Create()
    local first, where = Describe(key)
    local count = self.total > 1 and string.format(" (%d of %d)", self.total - #self.keys + 1, self.total) or ""
    self.text:SetText(string.format(
        "Shatter has settings or a mail session saved for \"%s\" %s%s. "
            .. "Another character with that first name may have saved them.\n\nAre they %s's?",
        first, where, count, Shatter.Database:GetFullName() or "this character"))
    self.frame:Show()
    return true
end

-- Shows the question when there is anything to ask; true if it did.
function OldKeyPrompt:Check()
    local db = Shatter.Database
    if not (db and db:GetFullName()) then return false end
    local keys = db:GetFirstNameKeys()
    if #keys == 0 then return false end
    self.keys, self.total = keys, #keys
    return self:ShowNext()
end

function OldKeyPrompt:Answer(mine)
    local key = self.keys and table.remove(self.keys, 1)
    if key and not Shatter.Database:AnswerFirstNameKey(key, mine) then
        Shatter.Print("Another character already said " .. key .. " was theirs.")
    elseif mine then
        Shatter.Print("Taken back: what was saved as " .. tostring(key) .. ". Type /reload to apply it everywhere.")
    else
        Shatter.Print("Left for its owner: " .. tostring(key) .. ". Items received in its mail session stay reserved, so Shatter won't disenchant them.")
    end
    self:ShowNext()
end
