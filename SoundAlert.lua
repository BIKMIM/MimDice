-- SoundAlert.lua
-- Author         : BIK
-- Description    : 스킬 사용 시 사운드 재생 모듈 (MimDice 확장 독립창 버전)

---@diagnostic disable: undefined-global, param-type-mismatch, undefined-field

-- =====================================================================
-- 환경 설정 (커스텀 파일 )
-- =====================================================================
local CUSTOM_SOUND_FILES = {
    "jump.ogg",
    "철수.mp3",
    "살아있는불꽃.ogg",
    "mysound.ogg"
}

-- 내장 사운드
local SOUND_CATEGORIES = {
    {
        name = "내장 사운드",
        sounds = {
            { name = "공격대 경고", id = 567397 },
            { name = "작업 완료", id = 558132 },
            { name = "경매장 열기", id = 567482 },
            { name = "경매장 닫기", id = 567499 },
            { name = "동전", id = 567428 },
            { name = "퀘스트 수락", id = 567400 },
            { name = "퀘스트 실패", id = 567459 },
            { name = "퀘스트 완료", id = 567439 },
            { name = "레벨업", id = 567431 },
            { name = "알람", id = 567458 },
            { name = "귓속말", id = 567421 },
            { name = "파티 초대", id = 567451 },
            { name = "던전 진입", id = 567419 },
            { name = "무작매칭실패", id = 567420 },
            { name = "미니맵 핑", id = 567416 },
            { name = "맵 밝히기", id = 567414 },
            { name = "무두질", id = 567417 },
            { name = "친구 접속", id = 567402 },
            { name = "PVP 깃발", id = 567427 },
            
        }
    }
}

-- =====================================================================
-- 내부 변수 및 초기화
-- =====================================================================
local SA = {}
local SA_OptionWindow = nil
local SA_TabOption = nil
local SA_EntryFrames = {}

-- 시스템(기본) 엔트리 정의 - 표시 순서대로
-- legacyDefaults: 이전 기본 파일명 목록 (이 값으로 저장돼 있으면 새 기본값으로 자동 갱신)
-- defaultEnabled: 처음 생성 시 체크박스 기본값
local SYSTEM_ENTRIES = {
    {
        spellID = "JUMP", spellName = "점프",
        defaultFile = "jump.ogg",
        legacyDefaults = {},
        defaultEnabled = true,
    },
    {
        spellID = "BLOODLUST", spellName = "블러드",
        defaultFile = "블러드_ACallToArms.mp3",
        legacyDefaults = { "bloodlust.ogg" },
        defaultEnabled = false,
    },
    {
        spellID = "POWERINFUSE", spellName = "마력 주입",
        defaultFile = "밀하우스_15초편집.mp3",
        legacyDefaults = { "powerinfusion.ogg", "battle01[53225].mp3" },
        defaultEnabled = false,
    },
}

-- 렌더링 시 시스템 엔트리 정렬용 (작을수록 위)
local SYSTEM_ORDER = {}
for i, def in ipairs(SYSTEM_ENTRIES) do SYSTEM_ORDER[def.spellID] = i end

-- 블러드 감지용 디버프 (Sated/Exhaustion 계열 - 적용 시 블러드 직후로 간주)
-- ※ 리스트로 저장하고 == 비교로만 매칭. WoW의 secret value(보호된 aura.spellId)는
--    테이블 키로 쓸 수 없지만 == 비교는 안전하게 가능. (ActionSounds도 동일 방식)
local BLOODLUST_DEBUFFS = {
    57723,  -- Exhaustion (Heroism)
    57724,  -- Sated (Bloodlust)
    80354,  -- Temporal Displacement (Time Warp)
    95809,  -- Insanity (Ancient Hysteria)
    264689, -- Fatigued (Primal Rage)
    390435, -- Exhaustion (Fury of the Aspects)
}

-- aura.spellId가 블러드 계열 디버프인지 확인 (secret value 안전 처리)
local function SA_IsBloodlustAura(aura)
    local sid = aura and aura.spellId
    if not sid then return false end
    for j = 1, #BLOODLUST_DEBUFFS do
        if sid == BLOODLUST_DEBUFFS[j] then
            return true
        end
    end
    return false
end

-- 마력 주입 (Power Infusion, 사제)
local POWER_INFUSION_SPELL_ID = 10060

function SA_InitDB()
    if not MimDiceDB then MimDiceDB = {} end
    if not MimDiceDB.soundAlerts then
        MimDiceDB.soundAlerts = {}
    end

    local _, playerClass = UnitClass("player")

    -- 시스템 엔트리 체크박스 기본값 1회성 마이그레이션 (계정-캐릭터별 1회)
    -- 이전 버전에서 BLOODLUST/POWERINFUSE를 enabled=true로 만들어 둔 사용자들의
    -- 체크박스를 새 defaultEnabled(false)로 한 번만 동기화.
    -- 이후엔 사용자가 직접 켠 상태를 보존.
    if not MimDiceDB.sysDefaultEnabledMigrated then
        MimDiceDB.sysDefaultEnabledMigrated = {}
    end

    for _, def in ipairs(SYSTEM_ENTRIES) do
        local existing
        for _, entry in ipairs(MimDiceDB.soundAlerts) do
            if entry.spellID == def.spellID and entry.class == playerClass then
                existing = entry
                break
            end
        end

        if existing then
            existing.isSystem = true
            -- 시스템 엔트리 이름은 항상 최신 정의로 갱신 (예: 기본 동작 → 짧은 이름)
            existing.spellName = def.spellName

            -- 체크박스 기본값 1회성 마이그레이션
            local migKey = def.spellID .. ":" .. playerClass
            if not MimDiceDB.sysDefaultEnabledMigrated[migKey] then
                existing.enabled = def.defaultEnabled
                MimDiceDB.sysDefaultEnabledMigrated[migKey] = true
            end

            -- 사운드 파일 마이그레이션:
            -- 비어 있거나 이전 기본값과 일치하면 새 기본값으로 갱신.
            -- 사용자가 직접 바꾼 값은 그대로 보존.
            local current = existing.soundFile or ""
            local shouldMigrate = (current == "")
            if not shouldMigrate and def.legacyDefaults then
                for _, old in ipairs(def.legacyDefaults) do
                    if current == old then shouldMigrate = true; break end
                end
            end
            if shouldMigrate then
                existing.soundType = "custom"
                existing.soundFile = def.defaultFile
                existing.soundKey  = def.defaultFile
                existing.soundName = def.defaultFile
            end
        else
            local migKey = def.spellID .. ":" .. playerClass
            table.insert(MimDiceDB.soundAlerts, {
                spellID = def.spellID,
                spellName = def.spellName,
                soundType = "custom",
                soundKey = def.defaultFile,
                soundFile = def.defaultFile,
                soundName = def.defaultFile,
                class = playerClass,
                enabled = def.defaultEnabled,
                isSystem = true
            })
            MimDiceDB.sysDefaultEnabledMigrated[migKey] = true
        end
    end
end

-- 3가지 타입(preset, custom, id) 지원
local function SA_PlaySound(entry)
    if not entry or not entry.enabled then return end

    if entry.soundType == "preset" and entry.soundKey then
        if type(entry.soundKey) == "number" and entry.soundKey > 500000 then
            pcall(PlaySoundFile, entry.soundKey, "Master")
        else
            pcall(PlaySound, entry.soundKey, "Master")
        end
    elseif entry.soundType == "custom" then
        if not entry.soundFile or entry.soundFile == "" then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[MimDice] 커스텀 사운드 파일이 설정되지 않았습니다.|r")
            return
        end
        local path = "Interface\\AddOns\\MimDice\\sounds\\" .. entry.soundFile
        local ok, handle = pcall(PlaySoundFile, path, "Master")
        if not ok or not handle then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffff0000[MimDice] 사운드 파일을 재생할 수 없습니다: " .. entry.soundFile .. "|r  "
                .. "|cffffff00(sounds\\ 폴더에 파일이 있는지 확인하세요)|r"
            )
        end
    elseif entry.soundType == "id" and entry.soundKey then
        -- 사용자가 직접 입력한 ID 재생
        local numericID = tonumber(entry.soundKey)
        if numericID then
            if numericID > 500000 then
                pcall(PlaySoundFile, numericID, "Master")
            else
                pcall(PlaySound, numericID, "Master")
            end
        end
    end
end

-- =====================================================================
-- 이벤트 감지 (스킬 & 점프 & 블러드 & 마력주입)
-- =====================================================================

-- 시스템 엔트리 한 건을 찾아서 재생 (JUMP/BLOODLUST/POWERINFUSE 등)
local function SA_PlaySystem(spellIDKey)
    if not MimDiceDB or not MimDiceDB.soundAlerts then return end
    local _, playerClass = UnitClass("player")
    for _, entry in ipairs(MimDiceDB.soundAlerts) do
        if entry.spellID == spellIDKey and entry.class == playerClass then
            SA_PlaySound(entry)
            return
        end
    end
end

local SA_EventFrame = CreateFrame("Frame")
SA_EventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
SA_EventFrame:RegisterEvent("PLAYER_LOGIN")
SA_EventFrame:RegisterUnitEvent("UNIT_AURA", "player")

SA_EventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        SA_InitDB()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit ~= "player" then return end
        if not MimDiceDB or not MimDiceDB.soundAlerts then return end

        local _, playerClass = UnitClass("player")
        for _, entry in ipairs(MimDiceDB.soundAlerts) do
            if entry.spellID == spellID and entry.class == playerClass then
                SA_PlaySound(entry)
                break
            end
        end
    elseif event == "UNIT_AURA" then
        -- 다른 사람이 나에게 건 블러드/마력주입 감지
        local unit, updateInfo = ...
        if unit ~= "player" or not updateInfo or not updateInfo.addedAuras then return end

        for i = 1, #updateInfo.addedAuras do
            local aura = updateInfo.addedAuras[i]
            -- aura 필드들이 secret value일 수 있어 pcall 로 감싼다.
            -- 일부 personal/restricted aura는 spellId 등이 보호되어 직접 접근 시 에러 발생.
            local ok, kind = pcall(function()
                if SA_IsBloodlustAura(aura) then return "BLOODLUST" end
                if aura and aura.spellId == POWER_INFUSION_SPELL_ID then return "POWERINFUSE" end
                return nil
            end)

            if ok and kind == "BLOODLUST" then
                -- Sated/Exhaustion 디버프는 10분(600초) 지속.
                -- 막 적용된 직후(잔여 ≥ 560초)면 블러드가 방금 걸렸다는 뜻.
                local okRem, remaining = pcall(function()
                    return aura.expirationTime and (aura.expirationTime - GetTime()) or 0
                end)
                if okRem and remaining and remaining >= 560 then
                    SA_PlaySystem("BLOODLUST")
                end
            elseif ok and kind == "POWERINFUSE" then
                SA_PlaySystem("POWERINFUSE")
            end
        end
    end
end)

hooksecurefunc("JumpOrAscendStart", function()
    if IsSwimming() or IsFlying() or IsFalling() then return end

    if not MimDiceDB or not MimDiceDB.soundAlerts then return end
    local _, playerClass = UnitClass("player")
    
    for _, entry in ipairs(MimDiceDB.soundAlerts) do
        if entry.spellID == "JUMP" and entry.class == playerClass then
            SA_PlaySound(entry)
            break
        end
    end
end)

-- =====================================================================
-- UI 기능 구현
-- =====================================================================

local function SA_ToggleWindow()
    if SA_OptionWindow:IsShown() then
        SA_OptionWindow:Hide()
        SA_TabOption:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
        SA_TabOption:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        SA_TabOption.text:SetTextColor(0.6, 0.6, 0.6)
    else
        SA_OptionWindow:Show()
        SA_RefreshList()
        SA_TabOption:SetBackdropColor(0.5, 0.1, 0.1, 0.9)
        SA_TabOption:SetBackdropBorderColor(1, 0.82, 0, 1)
        SA_TabOption.text:SetTextColor(1, 1, 0)
    end
end

local function SA_CreateTab()
    local mainWin = _G["MainWindow"]
    if not mainWin then return end

    local tabBackdrop = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    }

    SA_TabOption = CreateFrame("Button", "SA_TabOption", mainWin, "BackdropTemplate")
    SA_TabOption:SetSize(34, 65)
    SA_TabOption:SetPoint("TOPLEFT", mainWin, "TOPRIGHT", -4, -30)
    SA_TabOption:SetBackdrop(tabBackdrop)
    SA_TabOption:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    SA_TabOption:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local optText = SA_TabOption:CreateFontString(nil, "OVERLAY")
    optText:SetPoint("CENTER")
    optText:SetFont("Fonts\\2002.ttf", 12, "OUTLINE")
    optText:SetText("옵\n션")
    optText:SetTextColor(0.6, 0.6, 0.6)
    SA_TabOption.text = optText

    SA_TabOption:SetScript("OnClick", SA_ToggleWindow)
end

local function SA_CreateWindow()
    local mainWin = _G["MainWindow"]
    if not mainWin then return end

    SA_OptionWindow = CreateFrame("Frame", "SA_OptionWindow", UIParent, "BackdropTemplate")
    SA_OptionWindow:SetSize(380, 559)
    SA_OptionWindow:SetPoint("TOPLEFT", mainWin, "TOPRIGHT", 38, 0)
    
    -- 옵션창 드래그하면 메인창도 이동
    SA_OptionWindow:RegisterForDrag("LeftButton")
    SA_OptionWindow:SetScript("OnDragStart", function()
        if mainWin:IsMovable() then
            mainWin:StartMoving()
        end
    end)
    SA_OptionWindow:SetScript("OnDragStop", function()
        mainWin:StopMovingOrSizing()
        -- MimDice 메인 애드온에 위치 저장 기능이 있다면 호출하여 위치 고정
        if MimDice_SaveAnchors then MimDice_SaveAnchors() end
    end)
    
    -- ★ 메인 창이 닫힐 때 옵션 창도 함께 닫히도록 연동 ★
    mainWin:HookScript("OnHide", function()
        if SA_OptionWindow and SA_OptionWindow:IsShown() then
            SA_OptionWindow:Hide()
            if SA_TabOption then
                SA_TabOption:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
                SA_TabOption:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
                SA_TabOption.text:SetTextColor(0.6, 0.6, 0.6)
            end
        end
    end)
    
    SA_OptionWindow:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    SA_OptionWindow:SetBackdropColor(0, 0, 0, 0.5)
    SA_OptionWindow:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    SA_OptionWindow:EnableMouse(true)
    SA_OptionWindow:Hide()

    local title = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", SA_OptionWindow, "TOP", 0, -114)
    title:SetFont("Fonts\\2002.ttf", 13, "OUTLINE")
    title:SetText("스킬 사운드 알림 설정")
    title:SetTextColor(1, 0.82, 0)

    local closeBtn = CreateFrame("Button", nil, SA_OptionWindow, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", SA_OptionWindow, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() SA_ToggleWindow() end)

    -- ── 밈줌 카페 링크 ──────────────────────────
    local cafeLabel = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    cafeLabel:SetFont("Fonts\\2002.ttf", 11)
    cafeLabel:SetTextColor(0.6, 0.8, 1)
    cafeLabel:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 6, -8)
    cafeLabel:SetText("네이버 밈줌 카페  |cff4488ffhttps://cafe.naver.com/mimzoom|r")

    local urlPopup = CreateFrame("Frame", nil, SA_OptionWindow, "BackdropTemplate")
    urlPopup:SetSize(310, 36)
    urlPopup:SetPoint("TOPLEFT", cafeLabel, "BOTTOMLEFT", 0, -4)
    urlPopup:SetFrameStrata("DIALOG")
    urlPopup:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    urlPopup:SetBackdropColor(0.05, 0.05, 0.1, 0.98)
    urlPopup:SetBackdropBorderColor(0.4, 0.6, 1, 1)
    urlPopup:Hide()

    local urlHint = urlPopup:CreateFontString(nil, "OVERLAY")
    urlHint:SetFont("Fonts\\2002.ttf", 9)
    urlHint:SetTextColor(0.6, 0.6, 0.6)
    urlHint:SetPoint("TOPLEFT", urlPopup, "TOPLEFT", 6, -2)
    urlHint:SetText("Ctrl+C 로 복사, 한번 더 누르면 복사창이 닫힙니다.")

    local urlBox = CreateFrame("EditBox", nil, urlPopup)
    urlBox:SetSize(298, 18)
    urlBox:SetPoint("BOTTOMLEFT", urlPopup, "BOTTOMLEFT", 6, 4)
    urlBox:SetFont("Fonts\\2002.ttf", 11, "")
    urlBox:SetAutoFocus(false)
    urlBox:SetText("https://cafe.naver.com/mimzoom")
    urlBox:SetScript("OnTextChanged", function(self)
        if self:GetText() ~= "https://cafe.naver.com/mimzoom" then
            self:SetText("https://cafe.naver.com/mimzoom")
            self:HighlightText()
        end
    end)
    urlBox:SetScript("OnEscapePressed", function() urlPopup:Hide() end)

    local cafeLinkBtn = CreateFrame("Button", nil, SA_OptionWindow)
    cafeLinkBtn:SetHeight(16)
    cafeLinkBtn:SetPoint("TOPLEFT",  cafeLabel, "TOPLEFT",  0, 0)
    cafeLinkBtn:SetPoint("BOTTOMRIGHT", cafeLabel, "BOTTOMRIGHT", 0, 0)
    cafeLinkBtn:SetScript("OnClick", function()
        if urlPopup:IsShown() then
            urlPopup:Hide()
        else
            urlPopup:Show()
            urlBox:SetFocus()
            urlBox:HighlightText()
        end
    end)
    cafeLinkBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("클릭하면 주소 복사 창이 열립니다.", 1, 1, 1)
        GameTooltip:Show()
    end)
    cafeLinkBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── 옵션 섹션 ──────────────────────────
    local optionSectionLabel = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    optionSectionLabel:SetPoint("TOP", SA_OptionWindow, "TOP", 0, -32)
    optionSectionLabel:SetFont("Fonts\\2002.ttf", 13, "OUTLINE")
    optionSectionLabel:SetText("<< 옵 션 >>")
    optionSectionLabel:SetTextColor(1, 0.82, 0)

    -- 자동 팝업 체크박스
    local autoPopupCb = CreateFrame("CheckButton", "SA_AutoPopupCheck", SA_OptionWindow, "UICheckButtonTemplate")
    autoPopupCb:SetSize(22, 22)
    autoPopupCb:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 15, -50)
    autoPopupCb:SetChecked(MimDiceDB and MimDiceDB.autoPopup)
    autoPopupCb:SetScript("OnClick", function(self)
        if MimDiceDB then
            MimDiceDB.autoPopup = self:GetChecked()
            -- MimDice 메인의 체크박스도 동기화
            if _G["AutopopupCheckBox"] then
                _G["AutopopupCheckBox"]:SetChecked(MimDiceDB.autoPopup)
            end
            local status = MimDiceDB.autoPopup and "켜짐" or "꺼짐"
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MimDice]|r 자동 팝업: " .. status)
        end
    end)
    local autoPopupLabel = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    autoPopupLabel:SetPoint("LEFT", autoPopupCb, "RIGHT", 2, 0)
    autoPopupLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    autoPopupLabel:SetText("주사위 굴리면 자동으로 창 열기")
    autoPopupLabel:SetTextColor(0.9, 0.9, 0.9)

    -- 자동 리셋 체크박스
    local autoResetCb = CreateFrame("CheckButton", "SA_AutoResetCheck", SA_OptionWindow, "UICheckButtonTemplate")
    autoResetCb:SetSize(22, 22)
    autoResetCb:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 15, -72)
    autoResetCb:SetChecked(MimDiceDB and MimDiceDB.autoReset)

    local autoResetMinBox = CreateFrame("EditBox", "SA_AutoResetMinBox", SA_OptionWindow, "InputBoxTemplate")
    autoResetMinBox:SetSize(30, 20)
    autoResetMinBox:SetPoint("LEFT", autoResetCb, "RIGHT", 4, 0)
    autoResetMinBox:SetAutoFocus(false)
    autoResetMinBox:SetFont("Fonts\\2002.ttf", 11, "")
    autoResetMinBox:SetNumeric(true)
    autoResetMinBox:SetMaxLetters(3)
    autoResetMinBox:SetText(tostring((MimDiceDB and MimDiceDB.autoResetMinutes) or 5))
    autoResetMinBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput and MimDiceDB then
            local val = tonumber(self:GetText())
            if val and val >= 1 then
                MimDiceDB.autoResetMinutes = val
            end
        end
    end)
    autoResetMinBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local autoResetSuffix = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    autoResetSuffix:SetPoint("LEFT", autoResetMinBox, "RIGHT", 4, 0)
    autoResetSuffix:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    autoResetSuffix:SetText("분동안 주사위 굴림 없을 시 초기화")
    autoResetSuffix:SetTextColor(0.9, 0.9, 0.9)

    autoResetCb:SetScript("OnClick", function(self)
        if MimDiceDB then
            MimDiceDB.autoReset = self:GetChecked()
            local mins = MimDiceDB.autoResetMinutes or 5
            local status = MimDiceDB.autoReset and "켜짐" or "꺼짐"
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MimDice]|r 자동 초기화 " .. status .. " (" .. mins .. "분)")
        end
    end)

    local updateTimer = 0
    autoResetCb:SetScript("OnUpdate", function(self, elapsed)
        updateTimer = updateTimer + elapsed
        if updateTimer >= 0.5 then
            updateTimer = 0
            if MimDiceDB and MimDiceDB.autoReset and MimDice_LastRollTime and MimDice_LastRollTime > 0 then
                local delay = (MimDiceDB.autoResetMinutes or 5) * 60
                local remain = delay - (GetTime() - MimDice_LastRollTime)
                if remain > 0 then
                    local m = math.floor(remain / 60)
                    local s = math.floor(remain % 60)
                    autoResetSuffix:SetText(string.format("분동안 주사위 굴림 없을 시 초기화 (|cffffff00%02d:%02d 남음|r)", m, s))
                else
                    autoResetSuffix:SetText("분동안 주사위 굴림 없을 시 초기화")
                end
            else
                autoResetSuffix:SetText("분동안 주사위 굴림 없을 시 초기화")
            end
        end
    end)

    -- 구분선
    local divider = SA_OptionWindow:CreateTexture(nil, "ARTWORK")
    divider:SetSize(350, 1)
    divider:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 15, -110)
    divider:SetColorTexture(0.5, 0.5, 0.5, 0.6)

    -- ── 1. 스킬 입력 영역 ─────────────────
    local inputLabel = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    inputLabel:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 15, -144)
    inputLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    inputLabel:SetText("1. 추가할 스킬의 이름 또는 ID 입력 (꼭 띄어쓰기 지켜야 함)")
    inputLabel:SetTextColor(0.9, 0.9, 0.9)

    local inputBox = CreateFrame("EditBox", "SA_SpellInput", SA_OptionWindow, "InputBoxTemplate")
    inputBox:SetSize(200, 22)
    inputBox:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 20, -164)
    inputBox:SetAutoFocus(false)
    inputBox:SetFont("Fonts\\2002.ttf", 12, "")

    local addBtn = CreateFrame("Button", nil, SA_OptionWindow, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 24)
    addBtn:SetPoint("LEFT", inputBox, "RIGHT", 10, 0)
    addBtn:SetText("스킬 추가")
    addBtn:GetFontString():SetFont("Fonts\\2002.ttf", 11, "")

    local function ExecuteAddSkill()
        local text = inputBox:GetText()
        if text == "" then return end

        local spellName, spellID
        local numID = tonumber(text)
        if numID then
            local info = C_Spell.GetSpellInfo(numID)
            if info then spellID, spellName = numID, info.name end
        else
            local id = C_Spell.GetSpellIDForSpellIdentifier(text)
            if id then
                local info = C_Spell.GetSpellInfo(id)
                if info then spellID, spellName = id, info.name end
            end
        end

        if not spellID then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[MimDice] 해당 이름이나 ID의 스킬을 찾을 수 없습니다.|r")
            return
        end

        local _, playerClass = UnitClass("player")
        for _, entry in ipairs(MimDiceDB.soundAlerts) do
            if entry.spellID == spellID and entry.class == playerClass then
                DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[MimDice] 이미 등록된 스킬입니다.|r")
                inputBox:SetText("")
                return
            end
        end

        table.insert(MimDiceDB.soundAlerts, {
            spellID = spellID,
            spellName = spellName,
            soundType = "preset",
            soundKey = nil,
            soundFile = "",
            soundName = "사운드 선택...",
            class = playerClass,
            enabled = true,
            isSystem = false
        })
        inputBox:SetText("")
        SA_RefreshList()
    end

    addBtn:SetScript("OnClick", ExecuteAddSkill)
    inputBox:SetScript("OnEnterPressed", function()
        ExecuteAddSkill()
        inputBox:ClearFocus()
    end)

    -- ── 2. 목록 스크롤 프레임 ──────────────────────────────────────────
    local listTitle = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    listTitle:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 15, -204)
    listTitle:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    listTitle:SetText("2. 사운드 개별 설정 (현재 접속한 직업 전용)")
    listTitle:SetTextColor(0.8, 0.8, 0.8)

    local scrollFrame = CreateFrame("ScrollFrame", "SA_ListScrollFrame", SA_OptionWindow, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 10, -224)
    scrollFrame:SetPoint("BOTTOMRIGHT", SA_OptionWindow, "BOTTOMRIGHT", -30, 10)

    local scrollChild = CreateFrame("Frame", "SA_ListScrollChild", scrollFrame)
    scrollChild:SetSize(330, 100)
    scrollFrame:SetScrollChild(scrollChild)
    SA_OptionWindow.scrollChild = scrollChild
end

-- =====================================================================
-- 목록 갱신 및 개별 데이터 매핑
-- =====================================================================
function SA_RefreshList()
    if not SA_OptionWindow or not SA_OptionWindow.scrollChild then return end
    SA_InitDB()

    local scrollChild = SA_OptionWindow.scrollChild
    for _, f in ipairs(SA_EntryFrames) do f:Hide() end

    local _, playerClass = UnitClass("player")
    local yOffset = 0
    local rowIndex = 1
    
    local function RenderEntry(entry, idx)
        if not SA_EntryFrames[rowIndex] then
            local row = CreateFrame("Frame", "SA_Row_"..rowIndex, scrollChild)
            row:SetSize(330, 32)
            
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.15, 0.15, 0.15, 0.5)

            local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            cb:SetSize(22, 22)
            cb:SetPoint("LEFT", row, "LEFT", 2, 0)
            row.cb = cb

            local spellText = row:CreateFontString(nil, "OVERLAY")
            spellText:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            spellText:SetSize(85, 14) 
            spellText:SetFont("Fonts\\2002.ttf", 11)
            spellText:SetJustifyH("LEFT")
            row.spellText = spellText

            local typeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            typeBtn:SetSize(42, 22)
            typeBtn:SetPoint("LEFT", spellText, "RIGHT", 5, 0)
            typeBtn:GetFontString():SetFont("Fonts\\2002.ttf", 10, "")
            row.typeBtn = typeBtn

            local dd = CreateFrame("Frame", "SA_DD_"..rowIndex, row, "UIDropDownMenuTemplate")
            dd:SetPoint("LEFT", typeBtn, "RIGHT", -15, -2)
            UIDropDownMenu_SetWidth(dd, 100)
            row.dd = dd

            local customEdit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            customEdit:SetSize(100, 20)
            customEdit:SetPoint("LEFT", typeBtn, "RIGHT", 15, 0)
            customEdit:SetAutoFocus(false)
            customEdit:SetFont("Fonts\\2002.ttf", 10, "")
            row.customEdit = customEdit

            local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            delBtn:SetSize(22, 20)
            delBtn:SetPoint("RIGHT", row, "RIGHT", -5, 0)
            delBtn:SetText("X")
            delBtn:GetFontString():SetTextColor(1, 0.2, 0.2)
            row.delBtn = delBtn

            local testBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            testBtn:SetSize(22, 20)
            testBtn:SetPoint("RIGHT", delBtn, "LEFT", -2, 0)
            testBtn:SetText("▶")
            row.testBtn = testBtn

            SA_EntryFrames[rowIndex] = row
        end

        local row = SA_EntryFrames[rowIndex]
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
        row:Show()

        row.cb:SetChecked(entry.enabled)
        row.cb:SetScript("OnClick", function(self) entry.enabled = self:GetChecked() end)
        
        row.spellText:SetText(entry.spellName)
        if entry.isSystem then
            -- 시스템 엔트리: 연녹색 + 굵은 외곽선
            row.spellText:SetFont("Fonts\\2002.ttf", 12, "OUTLINE")
            row.spellText:SetTextColor(0.5, 1, 0.5)
            row.delBtn:Hide()
        else
            row.spellText:SetFont("Fonts\\2002.ttf", 11)
            row.spellText:SetTextColor(1, 0.82, 0)
            row.delBtn:Show()
            row.delBtn:SetScript("OnClick", function()
                table.remove(MimDiceDB.soundAlerts, idx)
                SA_RefreshList()
            end)
        end

        -- ★ 3단계 토글 로직: 내장 -> 커스텀 -> ID -> 내장 ★
        local typeLabel = "내장"
        if entry.soundType == "custom" then typeLabel = "커스텀" end
        if entry.soundType == "id" then typeLabel = "ID" end
        row.typeBtn:SetText(typeLabel)
        
        row.typeBtn:SetScript("OnClick", function()
            if entry.soundType == "preset" then
                entry.soundType = "custom"
                entry.soundFile = ""
            elseif entry.soundType == "custom" then
                entry.soundType = "id"
                entry.soundKey = ""
            else
                entry.soundType = "preset"
                entry.soundKey = nil
                entry.soundName = "사운드 선택..."
            end
            SA_RefreshList()
        end)

        -- 타입에 따른 UI 표시
        if entry.soundType == "preset" then
            row.dd:Show()
            row.customEdit:Hide()
            UIDropDownMenu_SetText(row.dd, entry.soundName or "사운드 선택...")
            
            UIDropDownMenu_Initialize(row.dd, function(_, level, menuList)
                level = level or 1
                local info = UIDropDownMenu_CreateInfo()
                if level == 1 then
                    for catIdx, cat in ipairs(SOUND_CATEGORIES) do
                        info.text = cat.name
                        info.hasArrow = true
                        info.menuList = "CAT_" .. catIdx
                        info.notCheckable = true
                        UIDropDownMenu_AddButton(info, level)
                    end
                elseif level == 2 then
                    if type(menuList) == "string" and menuList:find("CAT_") then
                        local catIdx = tonumber(menuList:match("CAT_(%d+)"))
                        local cat = SOUND_CATEGORIES[catIdx]
                        if cat then
                            for _, snd in ipairs(cat.sounds) do
                                info.text = snd.name
                                info.notCheckable = false
                                info.checked = (entry.soundKey ~= nil and entry.soundKey == snd.id)
                                info.func = function()
                                    entry.soundKey = snd.id
                                    entry.soundName = snd.name
                                    UIDropDownMenu_SetText(row.dd, snd.name)
                                    CloseDropDownMenus()
                                    SA_PlaySound(entry)
                                end
                                UIDropDownMenu_AddButton(info, level)
                            end
                        end
                    end
                end
            end)
            
        elseif entry.soundType == "custom" then
            row.dd:Hide()
            row.customEdit:Show()
            if not entry.soundFile or entry.soundFile == "" then
                row.customEdit:SetText("예: jump.ogg")
                row.customEdit:SetTextColor(0.5, 0.5, 0.5)
            else
                row.customEdit:SetText(entry.soundFile)
                row.customEdit:SetTextColor(1, 1, 1)
            end
            
            row.customEdit:SetScript("OnEditFocusGained", function(self)
                if self:GetText() == "예: jump.ogg" then self:SetText(""); self:SetTextColor(1,1,1) end
            end)
            row.customEdit:SetScript("OnTextChanged", function(self, userInput)
                if userInput then entry.soundFile = self:GetText() end
            end)
            row.customEdit:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                SA_PlaySound(entry)
            end)
            
        elseif entry.soundType == "id" then
            row.dd:Hide()
            row.customEdit:Show()
            if not entry.soundKey or entry.soundKey == "" then
                row.customEdit:SetText("예: 567439")
                row.customEdit:SetTextColor(0.5, 0.5, 0.5)
            else
                row.customEdit:SetText(tostring(entry.soundKey))
                row.customEdit:SetTextColor(1, 1, 1)
            end
            
            row.customEdit:SetScript("OnEditFocusGained", function(self)
                if self:GetText() == "예: 567439" then self:SetText(""); self:SetTextColor(1,1,1) end
            end)
            row.customEdit:SetScript("OnTextChanged", function(self, userInput)
                if userInput then entry.soundKey = tonumber(self:GetText()) or self:GetText() end
            end)
            row.customEdit:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                SA_PlaySound(entry)
            end)
        end

        row.testBtn:SetScript("OnClick", function() SA_PlaySound(entry) end)

        rowIndex = rowIndex + 1
        yOffset = yOffset + 34
    end

    -- 시스템 엔트리는 SYSTEM_ORDER에 따라 정렬해서 먼저 렌더링
    local sysList = {}
    for i, entry in ipairs(MimDiceDB.soundAlerts) do
        if entry.class == playerClass and entry.isSystem then
            table.insert(sysList, { entry = entry, idx = i, order = SYSTEM_ORDER[entry.spellID] or 999 })
        end
    end
    table.sort(sysList, function(a, b) return a.order < b.order end)
    for _, item in ipairs(sysList) do
        RenderEntry(item.entry, item.idx)
    end

    -- 사용자 추가 스킬은 그 아래에 저장 순서대로
    for i, entry in ipairs(MimDiceDB.soundAlerts) do
        if entry.class == playerClass and not entry.isSystem then
            RenderEntry(entry, i)
        end
    end

    scrollChild:SetHeight(math.max(yOffset, 10))
end

-- =====================================================================
-- 애드온 초기화 호출
-- =====================================================================
function SoundAlert_OnLoad()
    local function TryInit()
        if _G["MainWindow"] then
            SA_InitDB()
            SA_CreateTab()
            SA_CreateWindow()
        else
            C_Timer.After(0.1, TryInit)
        end
    end
    TryInit()
end