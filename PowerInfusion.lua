-- 마력 주입: 블리자드가 실제 오라 적용에 맞춰 소리를 재생한다.
-- 블러드와 별개다. 소리 등록은 ActionSounds와 같은 기준을 따른다.
-- 전투 중만 아니면 등록하고, 로딩 화면(PLAYER_ENTERING_WORLD)마다 새로 등록한다.
-- 레이드 안에서 리로드해도 Map/Chat 제한과 무관하게 바로 다시 등록된다.
-- 새 등록이 성공한 뒤에만 이전 등록을 지운다. 새 등록이 막혀도 기존 소리는 계속 난다.
-- 문구는 지속시간 바 안에 표시한다. 실제 바의 표시와 시간 갱신은
-- Blizzard에 맡기며 소리 재생으로 타이머를 시작하지 않는다.
-- API: Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua,
--      RestrictedActionsDocumentation.lua (wow-ui-source/live, 2026-09-09 확인).

MimDicePowerInfusion = {}
local PI = MimDicePowerInfusion
local SPELL_ID = 10060
local restrictionNames = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map", "Chat" }
local nativeID, nativeSignature, playSound, eventFrame
local nativeStatus = "unavailable"
local baselineKnown, wasPresent = false, false
local loading, suppressUntil = false, 0
local initialized = false
local refreshPending = false
local restrictionSyncQueued = false
local displaySuppressionGeneration = 0

local function L(text)
    return MimDice_L and MimDice_L(text) or text
end

local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

function PI.GetSettings()
    return MimDiceDB and MimDiceDB.buffTrack and MimDiceDB.buffTrack.POWERINFUSE
end

local function GetBarDefaults()
    if MimDiceBuffBarDefaults then return MimDiceBuffBarDefaults.Get("POWERINFUSE") end
    return { x = 0, y = -22.5, width = 100, height = 50 }
end

function PI.InitDB()
    MimDiceDB = MimDiceDB or {}
    MimDiceDB.buffTrack = MimDiceDB.buffTrack or {}
    local settings = PI.GetSettings()
    if not settings then
        settings = {}
        MimDiceDB.buffTrack.POWERINFUSE = settings
    end

    -- 예전 직업별 설정은 공용 설정의 빈 칸에만 옮긴다. 이미 고른 값이 우선이다.
    local legacy
    local _, playerClass
    if UnitClass then _, playerClass = UnitClass("player") end
    for _, entry in ipairs(MimDiceDB.soundAlerts or {}) do
        if entry.spellID == "POWERINFUSE" then
            if not legacy or entry.class == playerClass then legacy = entry end
        end
    end
    if legacy then
        for _, key in ipairs({ "enabled", "soundType", "soundFile", "soundKey", "soundName", "soundID" }) do
            if settings[key] == nil then settings[key] = legacy[key] end
        end
        for index = #MimDiceDB.soundAlerts, 1, -1 do
            if MimDiceDB.soundAlerts[index].spellID == "POWERINFUSE" then
                table.remove(MimDiceDB.soundAlerts, index)
            end
        end
    end

    local barDefaults = GetBarDefaults()
    local defaults = {
        enabled = true, soundType = "preset", soundKey = 567397,
        soundName = "공격대 경고", soundFile = "", showMessage = true,
        message = L("마력 주입!"), fontSize = 50, colorA = 1,
        x = 0, y = 240, locked = true, displayDuration = 3,
        barEnabled = true, width = barDefaults.width, height = barDefaults.height, timeFontSize = 40, alphaPct = 50,
        barX = barDefaults.x, barY = barDefaults.y, barLocked = true, barAdvOpen = false,
    }
    for key, value in pairs(defaults) do
        if settings[key] == nil then settings[key] = value end
    end
    if settings.color == nil then settings.color = { r = 1, g = 0.8, b = 0.2 } end
    -- 문구 색/위치와 바 색/위치는 별개다. 기존 문구 설정을 바 기본값으로 덮지 않는다.
    if settings.barColor == nil then settings.barColor = { r = 0.2, g = 0.6, b = 1 } end
end

-- 소리 등록 기준. ActionSounds와 같이 전투 중인지만 본다.
local function CanAddSound()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, combat = pcall(InCombatLockdown)
    return ok and not IsSecret(combat) and combat == false
end

-- 지속시간 바(AuraContainer) 구성 기준. 바는 모든 애드온 제한이 해제된 때만 만든다.
local function NoRestrictionsActive()
    if type(InCombatLockdown) == "function" then
        local ok, combat = pcall(InCombatLockdown)
        if not ok or IsSecret(combat) or type(combat) ~= "boolean" or combat then return false end
    end
    local getter = C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState
    local types = Enum and Enum.AddOnRestrictionType
    local inactive = Enum and Enum.AddOnRestrictionState and Enum.AddOnRestrictionState.Inactive
    if type(getter) ~= "function" or not types or inactive == nil then return false end
    for _, name in ipairs(restrictionNames) do
        local restrictionType = types[name]
        if restrictionType == nil then return false end
        local ok, state = pcall(getter, restrictionType)
        if not ok or IsSecret(state) or type(state) ~= "number" or state ~= inactive then return false end
    end
    return true
end

local function ResolveSound(settings)
    if settings.soundType == "custom" then
        local file = settings.soundFile
        if type(file) ~= "string" or file == "" then return nil, nil, "empty" end
        local path = MimDiceSoundFiles.Resolve(file)
        if not path then return nil, nil, "unavailable" end
        return { soundFileName = path }, "file:" .. path
    end
    local value = settings.soundType == "id" and settings.soundID or settings.soundKey
    local id = tonumber(value)
    -- MimDice의 기존 재생 규칙: 500000 초과는 파일 ID, 그 이하는 SoundKit ID.
    -- AuraSound는 SoundKit을 받지 않는다. 다른 음원으로 조용히 바꾸지 않는다.
    if not id or id <= 0 or id ~= math.floor(id) then return nil, nil, "empty" end
    if id <= 500000 then return nil, nil, "unsupported" end
    return { soundFileID = id }, "id:" .. tostring(id)
end

local function RemoveSound()
    if not nativeID then return true end
    local remover = C_UnitAuras and C_UnitAuras.RemoveAuraSound
    if type(remover) ~= "function" then return false end
    -- RemoveAuraSound에는 AddAuraSound의 HasRestrictions가 없다. OFF는 즉시 적용.
    local ok = pcall(remover, nativeID)
    if not ok then return false end
    nativeID, nativeSignature = nil, nil
    return true
end

-- forceRefresh: 같은 소리가 등록돼 있어도 새로 등록한다(로딩 화면마다).
-- 기존 등록은 새 등록이 성공한 뒤에만 지운다. 등록이 막히면 기존 소리가 그대로 남는다.
local function SyncSound(forceRefresh)
    local settings = PI.GetSettings()
    if not settings then return end
    forceRefresh = forceRefresh or refreshPending
    local info, signature, issue
    if settings.enabled then info, signature, issue = ResolveSound(settings) end
    local current = nativeID ~= nil and signature == nativeSignature
    if current and not forceRefresh then
        nativeStatus = "ready"
        return
    end
    if not info then
        -- 꺼졌거나 재생할 소리가 없다. 기존 등록만 지운다. (RemoveAuraSound는 제한이 없다)
        refreshPending = false
        if not RemoveSound() then nativeStatus = "unavailable"; return end
        nativeStatus = settings.enabled and issue or "off"
        return
    end
    -- 전투 중에는 등록할 수 없다. 기존 등록은 그대로 두고 전투가 끝난 뒤 다시 시도한다.
    if not CanAddSound() then
        refreshPending = true
        nativeStatus = nativeID and "ready" or "deferred"
        return
    end

    local adder = C_UnitAuras and C_UnitAuras.AddAuraSound
    local remover = C_UnitAuras and C_UnitAuras.RemoveAuraSound
    local trigger = Enum and Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Added
    if type(adder) ~= "function" or type(remover) ~= "function" or trigger == nil then
        -- API 자체가 없는 클라이언트다. 다시 시도해도 달라지지 않는다.
        refreshPending = false
        nativeStatus = "unavailable"
        return
    end
    info.unitToken, info.spellID, info.outputChannel = "player", SPELL_ID, "Dialog"
    local ok, id = pcall(adder, trigger, info)
    if not ok or IsSecret(id) or type(id) ~= "number" then
        -- 새 등록 실패. 기존 등록이 있으면 그 소리가 계속 난다.
        -- 재시도 표시는 켜 둔 채로 두어 다음 동기화(전투 종료, 제한 변경, 지역 이동)에서 다시 시도한다.
        refreshPending = true
        nativeStatus = current and "ready" or "unavailable"
        return
    end
    -- 새 등록이 성공한 뒤에만 이전 등록을 지우고 재시도 표시를 끈다.
    refreshPending = false
    if nativeID and nativeID ~= id then pcall(remover, nativeID) end
    nativeID, nativeSignature, nativeStatus = id, signature, "ready"
end

local function QueryPresence()
    local getter = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if type(getter) ~= "function" then return false, false end
    local restricted = false
    if C_Secrets and type(C_Secrets.ShouldAurasBeSecret) == "function" then
        local ok, value = pcall(C_Secrets.ShouldAurasBeSecret)
        if not ok or IsSecret(value) or type(value) ~= "boolean" then return false, false end
        restricted = value
    end
    if restricted then
        local secrecyGetter = C_Secrets and C_Secrets.GetSpellAuraSecrecy
        local neverSecret = Enum and Enum.SecrecyLevel and Enum.SecrecyLevel.NeverSecret
        if type(secrecyGetter) ~= "function" or neverSecret == nil then return false, false end
        local ok, secrecy = pcall(secrecyGetter, SPELL_ID)
        if not ok or IsSecret(secrecy) or type(secrecy) ~= "number" or secrecy ~= neverSecret then
            return false, false
        end
    end
    local ok, aura = pcall(getter, SPELL_ID)
    if not ok or IsSecret(aura) then return false, false end
    if type(aura) == "nil" then return false, true end
    if type(aura) ~= "table" then return false, false end
    return true, true
end

local function UpdateDisplaySuppression()
    if MimDicePowerInfusionBar then
        MimDicePowerInfusionBar.SetSuppressed(loading or GetTime() < suppressUntil)
    end
end

local function SyncDisplay()
    if MimDicePowerInfusionBar then MimDicePowerInfusionBar.ApplySettings() end
    UpdateDisplaySuppression()
end

local function ScheduleDisplayRelease()
    if not MimDicePowerInfusionBar then return end
    displaySuppressionGeneration = displaySuppressionGeneration + 1
    local generation = displaySuppressionGeneration
    UpdateDisplaySuppression()
    C_Timer.After(3, function()
        if generation == displaySuppressionGeneration and not loading then SyncDisplay() end
    end)
end

local function SyncPresence(suppress)
    local present, known = QueryPresence()
    if not known then
        baselineKnown = false
        return
    end
    local newlyApplied = baselineKnown and not wasPresent and present
    baselineKnown, wasPresent = true, present
    if suppress or loading or GetTime() < suppressUntil or not newlyApplied then return end
    local settings = PI.GetSettings()
    if settings.enabled and not nativeID and playSound then playSound(settings, "Dialog") end
    -- 바는 게임이 실제 오라로 표시한다. 소리나 조회 결과로 고정 타이머를 시작하지 않는다.
end

function PI.ApplySettings()
    if not initialized then return end
    SyncSound()
    SyncDisplay()
end

local function PlayPreviewSound()
    local settings = PI.GetSettings()
    if not settings then return end
    if playSound then
        local preview = {}
        for key, value in pairs(settings) do preview[key] = value end
        preview.enabled = true
        playSound(preview, "Dialog")
    end
end

function PI.UpdateBar()
    if not initialized then return end
    if MimDicePowerInfusionBar then MimDicePowerInfusionBar.ApplySettings() end
    UpdateDisplaySuppression()
end

function PI.PreviewBar()
    if not PI.GetSettings() then return end
    PlayPreviewSound()
    if MimDicePowerInfusionBar then MimDicePowerInfusionBar.Preview() end
end

function PI.CloseBarPreview()
    local settings = PI.GetSettings()
    if settings then settings.barLocked = true end
    if MimDicePowerInfusionBar then MimDicePowerInfusionBar.ClosePreview() end
end

function PI.ResetBarSettings()
    local settings = PI.GetSettings()
    if not settings then return end
    local defaults = GetBarDefaults()
    settings.width, settings.height, settings.timeFontSize, settings.alphaPct = defaults.width, defaults.height, 40, 50
    settings.barX, settings.barY = defaults.x, defaults.y
    settings.barColor = { r = 0.2, g = 0.6, b = 1 }
    settings.message = L("마력 주입!")
    settings.barEnabled = true
    PI.CloseBarPreview()
    PI.UpdateBar()
end

function PI.GetBarStatusText()
    if MimDicePowerInfusionBar then return MimDicePowerInfusionBar.GetStatusText() end
    return L("이 환경에서는 마력 주입 바를 표시할 수 없습니다."), "unavailable"
end

-- 구 문구 설정 호출도 이제 바 안쪽 문구에 적용한다.
PI.Preview = PI.PreviewBar
PI.ClosePreview = PI.CloseBarPreview
PI.UpdateMessage = PI.UpdateBar
PI.GetMessageStatusText = PI.GetBarStatusText

function PI.GetStatusText()
    local text = {
        off = "알림 꺼짐",
        ready = "마력 주입 소리 준비 완료",
        deferred = "전투가 끝나면 소리 설정이 적용됩니다.",
        unavailable = "이 환경에서는 마력 주입 소리를 등록할 수 없습니다.",
        unsupported = "이 효과음 번호는 제한 중 재생을 지원하지 않습니다. 내장 소리나 파일을 골라 주세요.",
        empty = "재생할 소리를 골라 주세요.",
    }
    -- 두 번째 값은 설정창 표시용 공개 상태다. 번역된 문구로 상태를 판정하지 않는다.
    return L(text[nativeStatus] or text.unavailable), nativeStatus
end

function PI.Init(callback)
    playSound = callback or playSound
    PI.InitDB()
    if initialized then PI.ApplySettings(); return end
    initialized = true
    PI.GetSettings().locked = true
    PI.GetSettings().barLocked = true
    suppressUntil = GetTime() + 3
    UpdateDisplaySuppression()
    ScheduleDisplayRelease()
    SyncPresence(true)
    SyncSound()

    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "LOADING_SCREEN_ENABLED",
        "LOADING_SCREEN_DISABLED", "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA", "ENCOUNTER_END", "CVAR_UPDATE" }) do
        eventFrame:RegisterEvent(event)
    end
    -- 오래된 클라이언트에서 신규 이벤트가 없으면 공개 오라 조회만 유지한다.
    if C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState then
        eventFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    end
    eventFrame:SetScript("OnEvent", function(_, event, cvar)
        if event == "CVAR_UPDATE" then
            -- A muted master channel can prevent the initial custom-file probe.
            if type(cvar) == "string" and cvar:lower() == "sound_enableallsound" then SyncSound() end
        elseif event == "UNIT_AURA" then
            -- RegisterUnitEvent로 player만 받는다. 비밀일 수 있는 payload는 읽지 않는다.
            SyncPresence(false)
        elseif event == "LOADING_SCREEN_ENABLED" then
            loading, baselineKnown = true, false
            displaySuppressionGeneration = displaySuppressionGeneration + 1
            UpdateDisplaySuppression()
        elseif event == "PLAYER_ENTERING_WORLD" or event == "LOADING_SCREEN_DISABLED" then
            loading = false
            suppressUntil = GetTime() + 3
            SyncPresence(true)
            -- ActionSounds와 같이 지역에 들어올 때마다 등록을 새로 한다.
            SyncSound(event == "PLAYER_ENTERING_WORLD")
            SyncDisplay()
            ScheduleDisplayRelease()
        elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
            -- 이벤트 dispatch 중에는 제한 API가 일시적인 전환 상태를 반환한다.
            -- 다음 프레임의 확정 상태를 확인하고, 비밀일 수 있는 이벤트 인자는 읽지 않는다.
            if not restrictionSyncQueued then
                restrictionSyncQueued = true
                C_Timer.After(0, function()
                    restrictionSyncQueued = false
                    SyncPresence(true)
                    SyncSound()
                    SyncDisplay()
                end)
            end
        else
            -- 제한 상태 전환은 새 적용이 아니다. 공개된 현재 상태만 기준선으로 저장.
            SyncPresence(true)
            SyncSound()
            SyncDisplay()
        end
    end)
    -- 기존 소리 등록과 이벤트 연결을 마친 뒤 새 바를 구성한다.
    if MimDicePowerInfusionBar then
        MimDicePowerInfusionBar.OnPositionChanged = function(x, y)
            if PI.OnBarPositionChanged then PI.OnBarPositionChanged(x, y) end
        end
        MimDicePowerInfusionBar.Init(PI.GetSettings, NoRestrictionsActive)
    end
end
