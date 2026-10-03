-- 마력 주입 고정 알림 설정. 바 안에 사용자 문구와 남은 시간을 표시한다.
local PI = MimDicePowerInfusion
local L = MimDice_L

function PI.CreateConfig(parent, helpers)
    local layout = helpers.Layout
    local win = CreateFrame("Frame", "MimDice_BuffConfig_POWERINFUSE", UIParent, "BackdropTemplate")
    win.key = "POWERINFUSE"
    win:SetSize(layout.width, layout.collapsedHeight)
    win:SetPoint("TOPLEFT", parent, "TOPRIGHT", 6, 0)
    win:SetFrameStrata("DIALOG")
    win:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    win:SetBackdropColor(0, 0, 0, 0.5)
    win:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    win:EnableMouse(true)
    win:SetMovable(true)
    helpers.WireBundleDrag(win)
    win:SetScript("OnHide", function()
        PI.CloseBarPreview()
    end)

    local function settings() return PI.GetSettings() end
    local function label(container, y, text, height)
        local fs = container:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("TOPLEFT", container, "TOPLEFT", 15, y)
        fs:SetFont(MimDiceFontPath(), 11, "OUTLINE")
        fs:SetTextColor(0.9, 0.9, 0.9)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetSize(310, height or 16)
        fs:SetText(text)
        return fs
    end

    local title = label(win, -12, L("마력 주입") .. L(" 지속바 설정 (공용)"), 18)
    title:ClearAllPoints()
    title:SetPoint("TOP", win, "TOP", 0, -12)
    title:SetFont(MimDiceFontPath(), 13, "OUTLINE")
    title:SetJustifyH("CENTER")
    title:SetTextColor(1, 0.82, 0)
    local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    closeBtn.MimDiceIsClose = true
    closeBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() win:Hide() end)

    local soundLabel = label(win, -36, "", 16)
    soundLabel:SetWordWrap(false)
    local commitSound
    win.typeRefresh = helpers.MakeTypeSelector(win, 15, layout.soundY,
        function() return settings().soundType end,
        function(soundType)
            commitSound()
            settings().soundType = soundType
            PI.ApplySettings()
            win.RefreshSoundRow()
        end)

    local soundBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    soundBox:SetSize(135, 22)
    soundBox:SetPoint("TOPLEFT", win, "TOPLEFT", 157, layout.soundY)
    soundBox:SetAutoFocus(false)
    soundBox:SetFont(MimDiceFontPath(), 11, "")
    win.soundBox = soundBox
    soundBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self.dirty = true end
    end)
    commitSound = function()
        if not soundBox.dirty then return end
        soundBox.dirty = false
        local config = settings()
        local value = soundBox:GetText():match("^%s*(.-)%s*$")
        if value == soundBox.placeholder then value = "" end
        if soundBox.editType == "id" then
            config.soundID = tonumber(value) or value
        elseif soundBox.editType == "custom" then
            config.soundFile = value
        else
            return
        end
        PI.ApplySettings()
        win.RefreshStatus()
    end
    soundBox:SetScript("OnEnterPressed", function(self) commitSound(); self:ClearFocus() end)
    soundBox:SetScript("OnEditFocusLost", commitSound)
    soundBox:SetScript("OnEscapePressed", function(self)
        self.dirty = false
        self:ClearFocus()
        win.RefreshSoundRow()
    end)
    helpers.WirePlaceholder(soundBox)

    -- 미리듣기는 저장된 ON/OFF를 바꾸지 않고 사본으로 재생한다.
    local function listen()
        commitSound()
        local preview = {}
        for key, value in pairs(settings()) do preview[key] = value end
        preview.enabled = true
        helpers.PlaySound(preview, "Dialog")
    end
    local soundSelectBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    soundSelectBtn:SetSize(135, 22)
    soundSelectBtn:SetPoint("TOPLEFT", win, "TOPLEFT", 157, layout.soundY)
    local selectText = soundSelectBtn:GetFontString()
    selectText:SetFont(MimDiceFontPath(), 10, "")
    selectText:SetJustifyH("LEFT")
    selectText:SetWordWrap(false)
    selectText:ClearAllPoints()
    selectText:SetPoint("LEFT", 6, 0)
    selectText:SetPoint("RIGHT", -6, 0)
    soundSelectBtn:SetScript("OnClick", function()
        helpers.OpenSoundPicker(soundSelectBtn,
            function() return settings().soundKey end,
            function(sound)
                local config = settings()
                config.soundType, config.soundKey, config.soundName = "preset", sound.id, sound.name
                PI.ApplySettings()
                win.RefreshSoundRow()
                listen()
            end)
    end)
    win.soundSelectBtn = soundSelectBtn
    local listenBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    listenBtn:SetSize(24, 22)
    listenBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -15, layout.soundY)
    listenBtn:SetText("▶")
    listenBtn:SetScript("OnClick", listen)

    -- 정상일 때는 블러드와 같은 화면. 필요한 안내만 하단에 추가한다.
    local noticeText = label(win, 0, "")
    noticeText:SetHeight(0)
    noticeText:SetWordWrap(true)
    noticeText:SetTextColor(0.9, 0.8, 0.55)
    noticeText:Hide()
    win.noticeText = noticeText
    local noticeHeight, previousNotice = 0, ""
    function win.RefreshStatus()
        local notices = {}
        if settings().enabled then
            local soundText, soundStatus = PI.GetStatusText()
            local barText, barStatus = PI.GetBarStatusText()
            if soundStatus ~= "ready" and soundStatus ~= "off" then
                notices[#notices + 1] = soundText
            end
            if settings().barEnabled and barStatus ~= "ready" and barStatus ~= "off" then
                notices[#notices + 1] = barText
            end
        end
        local text = table.concat(notices, "\n")
        if text == previousNotice then return end
        previousNotice = text
        noticeText:SetText(text)
        noticeText:SetShown(text ~= "")
        -- 애드온의 공개 안내 문구만 측정해 긴 번역도 하단 버튼과 겹치지 않게 한다.
        noticeHeight = text ~= "" and math.ceil(noticeText:GetStringHeight()) or 0
        win.ApplyAdv()
    end

    function win.RefreshSoundRow()
        local config = settings()
        win.typeRefresh()
        soundBox.dirty = false
        soundBox.editType = config.soundType
        if config.soundType == "preset" then
            soundLabel:SetText(L("내장: 아래에서 사운드 선택 (▶ 미리듣기)"))
            soundSelectBtn:Show()
            soundBox:Hide()
            soundSelectBtn:SetText(helpers.PresetSoundName(config))
        elseif config.soundType == "id" then
            soundLabel:SetText(L("ID: 사운드 숫자 ID를 직접 입력"))
            soundSelectBtn:Hide()
            soundBox:Show()
            helpers.SetBoxValue(soundBox, config.soundID, L("예: 567439"))
        else
            soundLabel:SetText(L("커스텀: _retail_\\sound 또는 sounds의 파일명"))
            soundSelectBtn:Hide()
            soundBox:Show()
            helpers.SetBoxValue(soundBox, config.soundFile, L("예: MySound.mp3"))
        end
        win.RefreshStatus()
    end

    local barCb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    barCb:SetSize(22, 22)
    barCb:SetPoint("TOPLEFT", win, "TOPLEFT", 15, layout.barY)
    local barLabel = label(win, layout.barY, L("화면에 지속시간 바 표시"))
    barLabel:ClearAllPoints()
    barLabel:SetPoint("LEFT", barCb, "RIGHT", 2, 0)
    barLabel:SetWidth(280)
    barLabel:SetJustifyV("MIDDLE")
    barCb:SetScript("OnClick", function(self)
        settings().barEnabled = self:GetChecked() and true or false
        PI.UpdateBar()
        win.RefreshStatus()
    end)
    win.barCb = barCb

    label(win, layout.messageLabelY, L("바 안에 표시할 문구"))
    local messageBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    messageBox:SetSize(300, 22)
    messageBox:SetPoint("TOPLEFT", win, "TOPLEFT", 20, layout.messageY)
    messageBox:SetAutoFocus(false)
    messageBox:SetFont(MimDiceFontPath(), 12, "")
    messageBox:SetMaxLetters(120)
    messageBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            settings().message = self:GetText()
            PI.UpdateBar()
        end
    end)
    messageBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    messageBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    win.messageBox = messageBox

    local barAdvBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    barAdvBtn:SetSize(310, 22)
    barAdvBtn:SetPoint("TOP", win, "TOP", 0, layout.advancedButtonY)
    barAdvBtn:GetFontString():SetFont(MimDiceFontPath(), 10, "")
    local barAdvanced = CreateFrame("Frame", nil, win)
    barAdvanced:SetPoint("TOPLEFT", win, "TOPLEFT", 0, layout.advancedY)
    barAdvanced:SetSize(layout.width, 220)
    win.barAdvanced, win.barAdvBtn = barAdvanced, barAdvBtn
    win.barColorRefresh = helpers.MakeColorRow(barAdvanced, layout.colorY, L("바 색상"),
        function() return settings().barColor end,
        function(r, g, b) settings().barColor = { r = r, g = g, b = b } end,
        { 0.2, 0.6, 1 }, PI.UpdateBar,
        { get = function() return (settings().alphaPct or 50) / 100 end,
          set = function(value) settings().alphaPct = math.floor(value * 100 + 0.5) end })
    win.wSlider = helpers.MakeNumberSlider(barAdvanced, "MimDice_PowerInfusionBarWidth", layout.widthY,
        L("바 가로 크기"), 100, 1900,
        function() return settings().width end,
        function(value) settings().width = value end, PI.UpdateBar)
    win.hSlider = helpers.MakeNumberSlider(barAdvanced, "MimDice_PowerInfusionBarHeight", layout.heightY,
        L("바 세로 크기"), 16, 300,
        function() return settings().height end,
        function(value) settings().height = value end, PI.UpdateBar)
    win.tfSlider = helpers.MakeNumberSlider(barAdvanced, "MimDice_PowerInfusionBarFontSize", layout.fontY,
        L("글씨 크기 (라벨+남은시간)"), 8, 120,
        function() return settings().timeFontSize end,
        function(value) settings().timeFontSize = value end, PI.UpdateBar)
    local barPosRefresh, barPosX, barPosY = helpers.AddPosRow(barAdvanced, layout.positionY,
        function() return settings().barX end, function(value) settings().barX = value end,
        function() return settings().barY end, function(value) settings().barY = value end,
        PI.UpdateBar)
    win.barPosRefresh = barPosRefresh
    PI.OnBarPositionChanged = function()
        if win:IsShown() then win.barPosRefresh() end
    end
    helpers.ChainTabEnter({ win.wSlider.edit, win.hSlider.edit, win.tfSlider.edit, barPosX, barPosY })

    local lockBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    lockBtn:SetSize(110, 24)
    lockBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 15, 14)
    lockBtn:GetFontString():SetFont(MimDiceFontPath(), 10, "")
    function win.RefreshLockBtn()
        lockBtn:SetText(settings().barLocked and L("위치 잠금 해제") or L("위치 잠금"))
    end
    lockBtn:SetScript("OnClick", function()
        settings().barLocked = not settings().barLocked
        PI.UpdateBar()
        win.RefreshLockBtn()
    end)
    win.lockBtn = lockBtn
    local resetBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    resetBtn:SetSize(70, 24)
    resetBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 155, 14)
    resetBtn:SetText(L("기본값"))
    resetBtn:GetFontString():SetFont(MimDiceFontPath(), 11, "")
    resetBtn:SetScript("OnClick", function()
        PI.ResetBarSettings()
        win.Refresh()
    end)
    win.resetBarBtn = resetBtn
    local testBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    testBtn:SetSize(70, 24)
    testBtn:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -15, 14)
    testBtn:SetText(L("테스트"))
    testBtn:GetFontString():SetFont(MimDiceFontPath(), 11, "")
    testBtn:SetScript("OnClick", function()
        commitSound()
        PI.PreviewBar()
    end)
    win.testBtn = testBtn

    function win.ApplyAdv()
        local barOpen = settings().barAdvOpen and true or false
        barAdvanced:SetShown(barOpen)
        local baseHeight = barOpen and layout.expandedHeight or layout.collapsedHeight
        noticeText:ClearAllPoints()
        noticeText:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -(baseHeight - 38))
        win:SetHeight(baseHeight + (noticeHeight > 0 and noticeHeight + 12 or 0))
        barAdvBtn:SetText(barOpen and L("상세 설정 접기") or L("상세 설정 열기 : 색/크기/위치"))
    end
    barAdvBtn:SetScript("OnClick", function()
        settings().barAdvOpen = not settings().barAdvOpen
        win.ApplyAdv()
    end)
    function win.Refresh()
        win.RefreshSoundRow()
        barCb:SetChecked(settings().barEnabled)
        messageBox:SetText(settings().message or L("마력 주입!"))
        win.wSlider.SyncValue()
        win.hSlider.SyncValue()
        win.tfSlider.SyncValue()
        win.barColorRefresh()
        win.barPosRefresh()
        win.RefreshLockBtn()
        win.ApplyAdv()
    end
    -- 지역 이동 뒤 등록 대기/완료 상태를 열린 설정창에도 반영한다.
    local elapsedSinceStatus = 0
    win:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceStatus = elapsedSinceStatus + elapsed
        if elapsedSinceStatus < 0.5 then return end
        elapsedSinceStatus = 0
        win.RefreshStatus()
    end)
    win.Refresh()
    helpers.SkinRegisterWindow(win)
    win:Hide()
    return win
end
