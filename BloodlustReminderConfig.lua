-- 사용 가능 알림의 소리/메시지/모양은 블러드 발동 알림과 독립적으로 저장한다.
local Reminder = MimDiceBloodlustReminder
local L = MimDice_L

function Reminder.CreateConfig(parent, helpers)
    local win = CreateFrame("Frame", "MimDice_BloodlustReadyConfig", UIParent, "BackdropTemplate")
    Reminder.Config = win
    win:SetSize(340, 490)
    win:SetPoint("TOPLEFT", parent, "TOPRIGHT", 6, 0)
    win:SetFrameStrata("DIALOG")
    win:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    win:SetBackdropColor(0, 0, 0, 0.5)
    win:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    win:EnableMouse(true)
    win:SetMovable(true)
    helpers.WireBundleDrag(win)
    win:SetScript("OnHide", Reminder.ClosePreview)

    local settings = Reminder.GetSettings
    local function Label(text, y, height)
        local fs = win:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("TOPLEFT", win, "TOPLEFT", 15, y)
        fs:SetSize(310, height or 16)
        fs:SetFont(MimDiceFontPath(), 11, "OUTLINE")
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetTextColor(0.9, 0.9, 0.9)
        fs:SetText(L(text))
        return fs
    end
    local title = Label("Bloodlust ready alert", -12, 18)
    title:SetFont(MimDiceFontPath(), 13, "OUTLINE")
    title:SetJustifyH("CENTER")
    title:SetTextColor(1, 0.82, 0)
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close.MimDiceIsClose = true
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() win:Hide() end)

    local checks = {}
    local function Checkbox(field, caption, x, y)
        local cb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", win, "TOPLEFT", x, y)
        local label = win:CreateFontString(nil, "OVERLAY")
        label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        label:SetFont(MimDiceFontPath(), 11, "OUTLINE")
        label:SetText(L(caption))
        label:SetTextColor(0.9, 0.9, 0.9)
        cb:SetScript("OnClick", function(self)
            settings()[field] = self:GetChecked() and true or false
            Reminder.ApplySettings()
        end)
        checks[field] = cb
    end
    Checkbox("instanceOnly", "Only in dungeons and raids", 15, -38)
    Checkbox("otherClasses", "Also alert on classes without Bloodlust", 15, -66)
    Checkbox("soundEnabled", "Play sound", 15, -94)
    Checkbox("textEnabled", "Show message", 175, -94)

    local commitSound
    local typeRefresh = helpers.MakeTypeSelector(win, 15, -124,
        function() return settings().soundType end,
        function(value)
            commitSound()
            settings().soundType = value
            win.RefreshSoundRow()
        end)
    local soundBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    soundBox:SetSize(135, 22)
    soundBox:SetPoint("TOPLEFT", win, "TOPLEFT", 157, -124)
    soundBox:SetAutoFocus(false)
    soundBox:SetFont(MimDiceFontPath(), 11, "")
    soundBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self.dirty = true end
    end)
    commitSound = function()
        if not soundBox.dirty then return end
        soundBox.dirty = false
        local value = soundBox:GetText():match("^%s*(.-)%s*$")
        if value == soundBox.placeholder then value = "" end
        if soundBox.editType == "id" then settings().soundID = tonumber(value) or value
        elseif soundBox.editType == "custom" then settings().soundFile = value end
    end
    soundBox:SetScript("OnEnterPressed", function(self) commitSound(); self:ClearFocus() end)
    soundBox:SetScript("OnEditFocusLost", commitSound)
    soundBox:SetScript("OnEscapePressed", function(self)
        self.dirty = false
        self:ClearFocus()
        win.RefreshSoundRow()
    end)
    helpers.WirePlaceholder(soundBox)
    local selectSound = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    selectSound:SetSize(135, 22)
    selectSound:SetPoint("TOPLEFT", win, "TOPLEFT", 157, -124)
    selectSound:GetFontString():SetFont(MimDiceFontPath(), 10, "")
    selectSound:GetFontString():SetWordWrap(false)
    selectSound:SetScript("OnClick", function()
        helpers.OpenSoundPicker(selectSound,
            function() return settings().soundKey end,
            function(sound)
                settings().soundKey, settings().soundName = sound.id, sound.name
                win.RefreshSoundRow()
                Reminder.TestSound()
            end)
    end)
    local listen = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    listen:SetPoint("TOPRIGHT", win, "TOPRIGHT", -15, -124)
    listen:SetSize(24, 22)
    listen:SetText("▶")
    listen:SetScript("OnClick", function() commitSound(); Reminder.TestSound() end)
    function win.RefreshSoundRow()
        local config = settings()
        typeRefresh()
        soundBox.dirty, soundBox.editType = false, config.soundType
        local preset = config.soundType == "preset"
        selectSound:SetShown(preset)
        soundBox:SetShown(not preset)
        if preset then
            selectSound:SetText(helpers.PresetSoundName(config))
        elseif config.soundType == "id" then
            helpers.SetBoxValue(soundBox, config.soundID, L("예: 567439"))
        else
            helpers.SetBoxValue(soundBox, config.soundFile, L("예: MySound.mp3"))
        end
    end

    Label("Ready alert message", -154)
    local message = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    message:SetPoint("TOPLEFT", win, "TOPLEFT", 20, -174)
    message:SetSize(300, 22)
    message:SetAutoFocus(false)
    message:SetFont(MimDiceFontPath(), 12, "")
    message:SetMaxLetters(120)
    message:SetScript("OnTextChanged", function(self, userInput)
        if userInput then settings().message = self:GetText(); Reminder.ApplySettings() end
    end)
    message:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    message:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    helpers.WirePlaceholder(message)

    local colorRefresh = helpers.MakeColorRow(win, -212, L("Message color"),
        function() return settings().color end,
        function(r, g, b) settings().color = { r = r, g = g, b = b } end,
        { 1, 0.82, 0 }, Reminder.ApplySettings)
    local font = helpers.MakeNumberSlider(win, "MimDice_LustReadyFont", -254, L("Font size"), 12, 128,
        function() return settings().fontSize end,
        function(value) settings().fontSize = value end, Reminder.ApplySettings)
    local duration = helpers.MakeNumberSlider(win, "MimDice_LustReadyDuration", -308, L("Display duration (seconds)"), 1, 30,
        function() return settings().duration end,
        function(value) settings().duration = value end, Reminder.ApplySettings)
    local posRefresh, posX, posY = helpers.AddPosRow(win, -362,
        function() return settings().x end, function(value) settings().x = value end,
        function() return settings().y end, function(value) settings().y = value end, Reminder.ApplySettings)
    win.posRefresh = posRefresh
    helpers.ChainTabEnter({ font.edit, duration.edit, posX, posY })

    local help = Label("When your lockout is absent on combat entry or expires in combat, alerts once. Does not check spell or pet cooldowns.", -396, 42)
    help:SetFont(MimDiceFontPath(), 10, "")
    help:SetTextColor(0.7, 0.7, 0.7)
    local lock = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    lock:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 15, 14)
    lock:SetSize(110, 24)
    lock:GetFontString():SetFont(MimDiceFontPath(), 10, "")
    lock:SetScript("OnClick", function()
        if settings().locked then settings().locked = false; Reminder.ApplySettings()
        else Reminder.ClosePreview() end
        win.RefreshLockBtn()
    end)
    function win.RefreshLockBtn()
        lock:SetText(settings().locked and L("위치 잠금 해제") or L("위치 잠금"))
    end
    local reset = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    reset:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 155, 14)
    reset:SetSize(70, 24)
    reset:SetText(L("기본값"))
    reset:SetScript("OnClick", function()
        local config = settings()
        config.fontSize, config.duration, config.x, config.y = 48, 5, 0, 200
        config.color, config.message = { r = 1, g = 0.82, b = 0 }, ""
        Reminder.ClosePreview()
        Reminder.ApplySettings()
        win.Refresh()
    end)
    local test = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    test:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -15, 14)
    test:SetSize(70, 24)
    test:SetText(L("테스트"))
    test:SetScript("OnClick", function() commitSound(); Reminder.Test() end)

    function win.Refresh()
        local config = settings()
        for field, cb in pairs(checks) do cb:SetChecked(config[field]) end
        win.RefreshSoundRow()
        helpers.SetBoxValue(message, config.message, L("Bloodlust / Heroism ready!"))
        colorRefresh()
        font.SyncValue()
        duration.SyncValue()
        posRefresh()
        win.RefreshLockBtn()
    end
    win:Hide()
    helpers.SkinRegisterWindow(win)
    return win
end
