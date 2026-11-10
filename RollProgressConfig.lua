-- 주사위 진행 알림 설정창. 블러드 사용 가능 알림 설정창과 같은 부품을 쓴다.
local RP = MimDiceRollProgress
local L = MimDice_L

function RP.CreateConfig(parent, helpers)
    local win = CreateFrame("Frame", "MimDice_RollProgressConfig", UIParent, "BackdropTemplate")
    RP.Config = win
    win:SetSize(340, 512)
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
    -- 설정창을 닫으면 위치 조정을 끝내고 클릭 통과 상태로 돌린다.
    win:SetScript("OnHide", function() RP.ClosePreview(); if win.RefreshEditBtn then win.RefreshEditBtn() end end)

    local settings = RP.GetSettings
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
    local title = Label("Roll progress alert", -12, 18)
    title:SetFont(MimDiceFontPath(), 13, "OUTLINE")
    title:SetJustifyH("CENTER")
    title:SetTextColor(1, 0.82, 0)
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close.MimDiceIsClose = true
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() win:Hide() end)

    -- 사용 여부 / 완료음 사용
    local function Checkbox(caption, x, y, onClick)
        local cb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", win, "TOPLEFT", x, y)
        local label = win:CreateFontString(nil, "OVERLAY")
        label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        label:SetFont(MimDiceFontPath(), 11, "OUTLINE")
        label:SetText(L(caption))
        label:SetTextColor(0.9, 0.9, 0.9)
        cb:SetScript("OnClick", onClick)
        return cb
    end
    local enabledCb = Checkbox("Use roll progress alert", 15, -38, function(self)
        RP.SetEnabled(self:GetChecked())
        if parent and parent.rollProgressCb then parent.rollProgressCb:SetChecked(settings().enabled) end
        win.RefreshEditBtn()
    end)
    local soundCb = Checkbox("Play done sound", 15, -62, function(self)
        settings().soundEnabled = self:GetChecked() and true or false
    end)

    -- 완료 알림음: 내장/커스텀/ID (다른 알림과 같은 방식)
    local commitSound
    local typeRefresh = helpers.MakeTypeSelector(win, 15, -92,
        function() return settings().soundType end,
        function(value)
            commitSound()
            settings().soundType = value   -- 다른 타입의 입력값은 지우지 않는다
            win.RefreshSoundRow()
        end)
    local soundBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    soundBox:SetSize(135, 22)
    soundBox:SetPoint("TOPLEFT", win, "TOPLEFT", 157, -92)
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
    selectSound:SetPoint("TOPLEFT", win, "TOPLEFT", 157, -92)
    do
        -- 긴 소리 이름이 버튼 밖(옆 ID 버튼, ▶ 버튼)으로 넘치지 않게 버튼 안쪽 폭으로 자른다.
        local fs = selectSound:GetFontString()
        fs:SetFont(MimDiceFontPath(), 10, "")
        fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        fs:ClearAllPoints(); fs:SetPoint("LEFT", 6, 0); fs:SetPoint("RIGHT", -6, 0)
    end
    selectSound:SetScript("OnClick", function()
        helpers.OpenSoundPicker(selectSound,
            function() return settings().soundKey end,
            function(sound)
                helpers.SetPresetSound(settings(), sound)
                win.RefreshSoundRow()
                RP.TestSound()
            end)
    end)
    local listen = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    listen:SetPoint("TOPRIGHT", win, "TOPRIGHT", -15, -92)
    listen:SetSize(24, 22)
    listen:SetText("▶")
    listen:SetScript("OnClick", function() commitSound(); RP.TestSound() end)
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

    -- 화면 문구 (비워 두면 기본 문구). 숫자는 자동으로 붙는다.
    local function TextBox(field, x, y, width, placeholder)
        local box = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
        box:SetPoint("TOPLEFT", win, "TOPLEFT", x, y)
        box:SetSize(width, 22)
        box:SetAutoFocus(false)
        box:SetFont(MimDiceFontPath(), 11, "")
        box:SetMaxLetters(60)
        box:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            local value = self:GetText()
            if value == self.placeholder then value = "" end
            settings()[field] = value:match("^%s*(.-)%s*$")
            RP.ApplySettings()
        end)
        box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        helpers.WirePlaceholder(box)
        return box
    end
    local progressLabel = Label("Progress text (count is added)", -122)
    progressLabel:SetWidth(150)
    local doneLabel = win:CreateFontString(nil, "OVERLAY")
    doneLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 172, -122)
    doneLabel:SetSize(155, 16)
    doneLabel:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    doneLabel:SetJustifyH("LEFT")
    doneLabel:SetTextColor(0.9, 0.9, 0.9)
    doneLabel:SetText(L("Done text"))
    local progressBox = TextBox("progressText", 20, -140, 142, L("Rolls"))
    local doneBox = TextBox("doneText", 177, -140, 148, L("Everyone has rolled"))

    local progressColor = helpers.MakeColorRow(win, -174, L("Progress text color"),
        function() return settings().progressColor end,
        function(r, g, b) settings().progressColor = { r = r, g = g, b = b } end,
        { 1, 0.82, 0 }, RP.ApplySettings)
    local doneColor = helpers.MakeColorRow(win, -200, L("Done text color"),
        function() return settings().doneColor end,
        function(r, g, b) settings().doneColor = { r = r, g = g, b = b } end,
        { 0.3, 1, 0.3 }, RP.ApplySettings)
    local bgColor = helpers.MakeColorRow(win, -226, L("배경 색상"),
        function() return settings().bgColor end,
        function(r, g, b) settings().bgColor = { r = r, g = g, b = b } end,
        { 0, 0, 0 }, RP.ApplySettings,
        {
            get = function() return settings().bgAlpha end,
            set = function(a) settings().bgAlpha = a end,
        })

    local font = helpers.MakeNumberSlider(win, "MimDice_RollProgressFont", -254, L("Font size"), 12, 60,
        function() return settings().fontSize end,
        function(value) settings().fontSize = value end, RP.ApplySettings)
    local duration = helpers.MakeNumberSlider(win, "MimDice_RollProgressDuration", -308, L("Display duration (seconds)"), 1, 10,
        function() return settings().duration end,
        function(value) settings().duration = value end, RP.ApplySettings)
    local posRefresh, posX, posY = helpers.AddPosRow(win, -362,
        function() return settings().x end, function(value) settings().x = value end,
        function() return settings().y end, function(value) settings().y = value end, RP.ApplySettings)
    win.posRefresh = posRefresh
    helpers.ChainTabEnter({ progressBox, doneBox, font.edit, duration.edit, posX, posY })

    local help = Label("Shows how many members rolled when someone rolls for the first time, then alerts once when everyone has rolled. Only you can see it.", -396, 42)
    help:SetFont(MimDiceFontPath(), 10, "")
    help:SetTextColor(0.7, 0.7, 0.7)

    -- 아래 버튼 두 줄: [진행 미리보기] [완료 미리보기] / [위치 조정] [위치 초기화]
    local function Button(caption, point, x, y, width, onClick)
        local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        b:SetPoint(point, win, point, x, y)
        b:SetSize(width, 24)
        b:SetText(L(caption))
        b:GetFontString():SetFont(MimDiceFontPath(), 10, "")
        b:SetScript("OnClick", onClick)
        return b
    end
    Button("Preview progress", "BOTTOMLEFT", 15, 44, 150, function() RP.PreviewProgress() end)
    Button("Preview done", "BOTTOMRIGHT", -15, 44, 150, function() commitSound(); RP.PreviewDone() end)
    local edit = Button("Move position", "BOTTOMLEFT", 15, 14, 150, function()
        local config = settings()
        RP.SetEditing(config.locked)
        win.RefreshEditBtn()
    end)
    function win.RefreshEditBtn()
        edit:SetText(settings().locked and L("Move position") or L("Finish moving"))
    end
    Button("Reset position", "BOTTOMRIGHT", -15, 14, 150, function()
        RP.ResetPosition()
        posRefresh()
    end)

    function win.Refresh()
        local config = settings()
        enabledCb:SetChecked(config.enabled)
        soundCb:SetChecked(config.soundEnabled)
        win.RefreshSoundRow()
        helpers.SetBoxValue(progressBox, config.progressText, L("Rolls"))
        helpers.SetBoxValue(doneBox, config.doneText, L("Everyone has rolled"))
        progressColor()
        doneColor()
        bgColor()
        font.SyncValue()
        duration.SyncValue()
        posRefresh()
        win.RefreshEditBtn()
    end
    win:Hide()
    helpers.SkinRegisterWindow(win)
    return win
end
