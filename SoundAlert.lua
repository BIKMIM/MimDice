-- SoundAlert.lua
-- Author         : BIK
-- Description    : 스킬 사용 시 사운드 재생 모듈 (MimDice 확장 독립창 버전)

---@diagnostic disable: undefined-global, param-type-mismatch, undefined-field, cast-local-type

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

-- 시스템(기본) 엔트리 정의 - 표시 순서대로 (직업별 사운드 목록에 표시되는 항목)
-- legacyDefaults: 이전 기본 파일명 목록 (이 값으로 저장돼 있으면 새 기본값으로 자동 갱신)
-- defaultEnabled: 처음 생성 시 체크박스 기본값
-- ※ 블러드/마력주입/죽음추적은 직업별이 아니라 "계정 공용"이라 여기서 제외.
--    - 죽음추적: MimDiceDB.deathTrack
--    - 블러드/마력주입: MimDiceDB.buffTrack (사운드 + 지속시간 바)
local SYSTEM_ENTRIES = {
    {
        spellID = "JUMP", spellName = "점프",
        defaultFile = "jump.ogg",
        legacyDefaults = {},
        defaultEnabled = true,
    },
}

-- 렌더링 시 시스템 엔트리 정렬용 (작을수록 위)
local SYSTEM_ORDER = {}
for i, def in ipairs(SYSTEM_ENTRIES) do SYSTEM_ORDER[def.spellID] = i end

-- 공용 버프(지속시간 바) 정의 - 블러드/마력주입
-- duration: 효과 지속시간(초). 블러드는 고정 40s, 마력주입은 실제 오라값 우선 사용.
local BUFF_DEFS = {
    {
        key = "BLOODLUST", name = "블러드",
        file = "블러드_ACallToArms.mp3",
        color = { 1.00, 0.15, 0.15 },   -- 기본 빨강
        duration = 40, dy = 340,        -- 화면 위쪽 (clamp 안 걸리는 최대치)
    },
    {
        key = "POWERINFUSE", name = "마력 주입",
        file = "밀하우스_15초편집.mp3",
        color = { 0.25, 0.55, 1.00 },   -- 기본 파랑
        duration = 15, dy = 290,        -- 지속 15초 고정, 블러드 바로 아래 (50px = 바 높이만큼 붙음)
    },
}
local BUFF_DEF_BY_KEY = {}
for _, d in ipairs(BUFF_DEFS) do BUFF_DEF_BY_KEY[d.key] = d end

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

    -- =================================================================
    -- 죽음 추적: 계정 공용 설정 (직업별 아님)
    -- =================================================================
    if not MimDiceDB.deathTrack then
        MimDiceDB.deathTrack = {}
    end
    local dt = MimDiceDB.deathTrack

    -- 이전 버전의 직업별 DEATH 엔트리 정리 + 사운드 설정 1회 이전
    for i = #MimDiceDB.soundAlerts, 1, -1 do
        local e = MimDiceDB.soundAlerts[i]
        if e.spellID == "DEATH" then
            if dt.soundFile == nil and e.soundFile then
                dt.soundType = e.soundType
                dt.soundFile = e.soundFile
                dt.soundKey  = e.soundKey
                dt.soundName = e.soundName
            end
            table.remove(MimDiceDB.soundAlerts, i)
        end
    end

    -- 이전 deathMsg(메시지 전용 테이블) 설정을 deathTrack로 이전
    if MimDiceDB.deathMsg then
        local old = MimDiceDB.deathMsg
        if dt.showMessage == nil then dt.showMessage = old.enabled end
        if dt.suffix == nil then dt.suffix = old.suffix end
        if dt.fontSize == nil then dt.fontSize = old.fontSize end
        if dt.color == nil then dt.color = old.color end
        if dt.x == nil then dt.x = old.x end
        if dt.y == nil then dt.y = old.y end
        if dt.locked == nil then dt.locked = old.locked end
        if dt.duration == nil then dt.duration = old.duration end
        MimDiceDB.deathMsg = nil  -- 통합 후 정리
    end

    -- 기본값 채우기
    if dt.enabled == nil then dt.enabled = false end            -- 마스터 on/off (공용)
    if dt.soundType == nil then dt.soundType = "custom" end
    if dt.soundFile == nil then dt.soundFile = "왜죽었어.mp3" end
    if dt.soundKey == nil then dt.soundKey = "왜죽었어.mp3" end
    if dt.soundName == nil then dt.soundName = "왜죽었어.mp3" end
    if dt.showMessage == nil then dt.showMessage = true end     -- 화면 메시지 표시 여부
    if dt.suffix == nil then dt.suffix = " 사망 !!" end
    if dt.fontSize == nil then dt.fontSize = 80 end          -- 크게
    if dt.color == nil then dt.color = { r = 1, g = 0.2, b = 0.2 } end
    if dt.x == nil then dt.x = 0 end                          -- 중앙
    if dt.y == nil then dt.y = 130 end                        -- 마력주입 바 바로 아래
    if dt.locked == nil then dt.locked = true end
    if dt.duration == nil then dt.duration = 3 end

    -- =================================================================
    -- 블러드 / 마력주입: 계정 공용 (사운드 + 지속시간 바)
    -- =================================================================
    if not MimDiceDB.buffTrack then MimDiceDB.buffTrack = {} end
    for _, d in ipairs(BUFF_DEFS) do
        -- 이전 버전의 직업별 사운드 엔트리에서 설정을 1회 가져오고 모두 제거
        local migrated
        for i = #MimDiceDB.soundAlerts, 1, -1 do
            local e = MimDiceDB.soundAlerts[i]
            if e.spellID == d.key then
                if not migrated then
                    migrated = {
                        soundType = e.soundType, soundFile = e.soundFile,
                        soundKey = e.soundKey, soundName = e.soundName, enabled = e.enabled,
                    }
                end
                table.remove(MimDiceDB.soundAlerts, i)
            end
        end

        local bt = MimDiceDB.buffTrack[d.key]
        if not bt then bt = {}; MimDiceDB.buffTrack[d.key] = bt end

        if migrated then
            if bt.soundType == nil then bt.soundType = migrated.soundType end
            if bt.soundFile == nil then bt.soundFile = migrated.soundFile end
            if bt.soundKey  == nil then bt.soundKey  = migrated.soundKey end
            if bt.soundName == nil then bt.soundName = migrated.soundName end
            if bt.enabled   == nil then bt.enabled   = migrated.enabled end
        end

        if bt.enabled == nil then bt.enabled = false end        -- 마스터 on/off
        if bt.soundType == nil then bt.soundType = "custom" end
        if bt.soundFile == nil then bt.soundFile = d.file end
        if bt.soundKey == nil then bt.soundKey = d.file end
        if bt.soundName == nil then bt.soundName = d.file end
        if bt.barEnabled == nil then bt.barEnabled = true end   -- 지속시간 바 표시 여부
        if bt.color == nil then bt.color = { r = d.color[1], g = d.color[2], b = d.color[3] } end
        if bt.x == nil then bt.x = 0 end
        if bt.y == nil then bt.y = d.dy end
        if bt.locked == nil then bt.locked = true end
        if bt.width == nil then bt.width = 800 end               -- 크고 잘 보이는 기본 바
        if bt.height == nil then bt.height = 50 end
        if bt.timeFontSize == nil then bt.timeFontSize = 40 end  -- 글씨 크기 (라벨+남은시간 공통)
        if bt.alphaPct == nil then bt.alphaPct = 50 end          -- 바 채움 투명도 (%)
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


-- =====================================================================
-- 죽음 추적 (UNIT_DIED 기반, DeathTracer 참고하여 변형)
-- =====================================================================

-- secret value 안전 체크 래퍼 (구버전 클라이언트엔 hasanysecretvalues 없을 수 있음)
local function SA_IsSecret(v)
    return type(hasanysecretvalues) == "function" and hasanysecretvalues(v)
end

-- 죽은 유닛 GUID → 사용 가능한 unitID 로 변환
-- UnitTokenFromGUID 우선, 실패 시 본인/공대/파티 순회 fallback
local function SA_GetUnitFromGUID(guid)
    if not guid or SA_IsSecret(guid) then return nil end

    if type(UnitTokenFromGUID) == "function" then
        local token = UnitTokenFromGUID(guid)
        if token then return token end
    end

    if UnitGUID("player") == guid then return "player" end

    if IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitGUID(u) == guid then return u end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local u = "party" .. i
            if UnitGUID(u) == guid then return u end
        end
    end
    return nil
end

-- 와이프 시 사운드 폭주 방지용 throttle (창 단위 카운터)
-- DeathTracer는 역할(탱/힐) 예외가 있지만, 밈다이스는 단순 카운터로 변형
local SA_DeathThrottle = { resetTime = 0, count = 0, max = 3, window = 8 }

local function SA_DeathThrottleAllow()
    local now = GetTime()
    if now > SA_DeathThrottle.resetTime then
        SA_DeathThrottle.count = 0
        SA_DeathThrottle.resetTime = now + SA_DeathThrottle.window
    end
    SA_DeathThrottle.count = SA_DeathThrottle.count + 1
    return SA_DeathThrottle.count <= SA_DeathThrottle.max
end

-- 색상 프리셋 (28색, 7x4). 와우 화면에서 잘 보이는 선명한 색 위주.
-- 색상환 순서 정렬: 열 = 같은 계열(빨/주/노/초/청/파/보), 행 = 밝기(선명→파스텔→진함), 마지막 행 = 무채색
-- 색상 팔레트 (7열×4행 = 28):
--  1~2행 = WoW 13직업 공식 색상(+검정), 3~4행 = 일반색(무지개+무채색)
-- 직업색은 게임 실제값(C_ClassColor) 우선, 실패 시 하드코딩값 폴백.
local SA_CLASS_LIST = {
    { "WARRIOR",     0.78, 0.61, 0.43 }, { "PALADIN",     0.96, 0.55, 0.73 },
    { "HUNTER",      0.67, 0.83, 0.45 }, { "ROGUE",       1.00, 0.96, 0.41 },
    { "PRIEST",      1.00, 1.00, 1.00 }, { "DEATHKNIGHT", 0.77, 0.12, 0.23 },
    { "SHAMAN",      0.00, 0.44, 0.87 }, { "MAGE",        0.25, 0.78, 0.92 },
    { "WARLOCK",     0.53, 0.53, 0.93 }, { "MONK",        0.00, 1.00, 0.60 },
    { "DRUID",       1.00, 0.49, 0.04 }, { "DEMONHUNTER", 0.64, 0.19, 0.79 },
    { "EVOKER",      0.20, 0.58, 0.50 },
}
local SA_COLOR_PRESETS = {}
for _, ci in ipairs(SA_CLASS_LIST) do
    local r, g, b = ci[2], ci[3], ci[4]
    if C_ClassColor and C_ClassColor.GetClassColor then
        local c = C_ClassColor.GetClassColor(ci[1])
        if c then r, g, b = c.r, c.g, c.b end
    end
    SA_COLOR_PRESETS[#SA_COLOR_PRESETS + 1] = { r, g, b }
end
SA_COLOR_PRESETS[#SA_COLOR_PRESETS + 1] = { 0.10, 0.10, 0.10 }   -- 14번째: 검정
-- 3~4행: 일반색 14개
local SA_GENERAL_COLORS = {
    { 1.00, 1.00, 1.00 }, { 1.00, 0.15, 0.15 }, { 1.00, 0.55, 0.10 }, { 1.00, 0.90, 0.15 },
    { 0.30, 0.90, 0.25 }, { 0.15, 0.90, 0.85 }, { 0.25, 0.55, 1.00 },
    { 0.70, 0.40, 1.00 }, { 1.00, 0.35, 0.70 }, { 0.90, 0.20, 0.90 }, { 0.80, 0.80, 0.80 },
    { 0.55, 0.55, 0.55 }, { 0.30, 0.30, 0.30 }, { 0.65, 0.35, 0.12 },
}
for _, g in ipairs(SA_GENERAL_COLORS) do
    SA_COLOR_PRESETS[#SA_COLOR_PRESETS + 1] = g
end

-- =====================================================================
-- 죽음 메시지 화면 표시 (이동 가능 프레임 + 페이드아웃)
-- =====================================================================
local SA_DeathFrame = nil
local SA_DeathConfig = nil   -- 죽음 설정창 (아래에서 생성). 드래그 시 입력칸 갱신 참조용으로 미리 선언.

-- 역할 아이콘 텍스처 좌표 (MimDice.xml과 동일, 정규화 0~1)
-- 폰트는 ~120에서 렌더 한계라 글씨 크기를 120으로 제한 → 아이콘도 그에 맞춰 비례 유지.
local ROLE_TEXCOORD = {
    TANK    = { 0.0,  0.25, 0.26, 0.52 },
    HEALER  = { 0.26, 0.52, 0.0,  0.25 },
    DAMAGER = { 0.52, 0.25, 0.26, 0.52 },  -- 좌>우 = 좌우 반전(메인창과 동일)
}

-- 죽음 메시지 프레임 생성 (최초 1회)
local function SA_EnsureDeathFrame()
    if SA_DeathFrame then return SA_DeathFrame end

    local f = CreateFrame("Frame", "MimDice_DeathFrame", UIParent)
    f:SetSize(500, 60)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")

    -- 현재 위치를 DB에 저장하고, 설정창이 열려있으면 X/Y 입력칸도 실시간 갱신
    local function saveDeathPos(self)
        local x, y = self:GetCenter()
        local cx, cy = UIParent:GetCenter()
        if x and cx and MimDiceDB and MimDiceDB.deathTrack then
            MimDiceDB.deathTrack.x = x - cx
            MimDiceDB.deathTrack.y = y - cy
        end
        if SA_DeathConfig and SA_DeathConfig:IsShown() and SA_DeathConfig.posRefresh then
            SA_DeathConfig.posRefresh()
        end
    end

    -- 드래그 (잠금 해제 상태에서만)
    f:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and MimDiceDB and MimDiceDB.deathTrack and not MimDiceDB.deathTrack.locked then
            self:StartMoving()
            self.moving = true
        end
    end)
    f:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        self.moving = false
        saveDeathPos(self)
    end)
    -- 드래그 중 위치 실시간 갱신
    f:SetScript("OnUpdate", function(self)
        if self.moving then saveDeathPos(self) end
    end)

    -- 잠금 해제 시 보이는 배경 (위치 잡기용)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0.6, 1, 0.25)
    bg:Hide()
    f.bg = bg

    -- 역할 아이콘 (별도 텍스처 - 크기/정렬 직접 제어)
    local icon = f:CreateTexture(nil, "OVERLAY")
    icon:SetTexture("Interface\\LFGFRAME\\UI-LFG-ICON-ROLES")
    icon:Hide()
    f.icon = icon

    -- 가독성 위해 THICKOUTLINE + 그림자
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER")
    fs:SetJustifyH("LEFT")
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(2, -2)
    f.text = fs

    -- 페이드아웃 애니메이션
    local ag = f:CreateAnimationGroup()
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(1)
    f.fadeAnim = ag
    f.fade = fade
    ag:SetScript("OnFinished", function() f.text:SetText(""); f.icon:Hide(); f:SetAlpha(0) end)

    SA_DeathFrame = f
    return f
end

-- 현재 접속한 플레이어의 직업색 닉네임 (미리보기용)
local function SA_PlayerColoredName()
    local name = UnitName("player") or "밈주머니"
    local _, classFile = UnitClass("player")
    if classFile and C_ClassColor then
        local c = C_ClassColor.GetClassColor(classFile)
        if c then return "|c" .. c:GenerateHexColor() .. name .. "|r" end
    end
    return "|cffffffff" .. name .. "|r"
end

-- 현재 접속한 플레이어의 역할 (미리보기용)
-- 그룹 역할(UnitGroupRolesAssigned)은 솔로일 때 "NONE"이라, 그 경우 특성(spec) 역할 사용
local function SA_PlayerRoleForPreview()
    local r = UnitGroupRolesAssigned("player")
    if r == "TANK" or r == "HEALER" or r == "DAMAGER" then return r end
    if GetSpecialization and GetSpecializationRole then
        local spec = GetSpecialization()
        if spec then
            local sr = GetSpecializationRole(spec)
            if sr == "TANK" or sr == "HEALER" or sr == "DAMAGER" then return sr end
        end
    end
    return "DAMAGER"  -- 최종 기본값 (대부분 직업이 딜러)
end

-- 역할 아이콘 + 텍스트를 프레임 중앙에 그룹 정렬. 폰트는 120 제한(렌더 한계)이라 아이콘도 그에 맞춰 비례.
-- role: 역할, fontSize: 글씨 크기, coloredText: 색입혀진 "닉네임+문구"
local function SA_SetDeathContent(role, fontSize, coloredText)
    local f = SA_EnsureDeathFrame()
    local fs = math.min(fontSize or 24, 120)   -- WoW 폰트 렌더 한계
    f.text:SetFont("Fonts\\2002.ttf", fs, "THICKOUTLINE")
    f.text:SetText(coloredText)

    local tc = ROLE_TEXCOORD[role]
    if tc then
        local iconSize = math.floor(fs * 0.9 + 0.5)     -- 글씨 높이에 맞춤
        local gap = math.floor(fs * 0.2 + 0.5)
        f.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        f.icon:SetSize(iconSize, iconSize)
        f.icon:Show()
        -- (아이콘 + gap + 텍스트) 그룹을 프레임 가운데에
        local tw = f.text:GetStringWidth()
        f.icon:ClearAllPoints()
        f.icon:SetPoint("CENTER", f, "CENTER", -(gap + tw) / 2, 0)
        f.text:ClearAllPoints()
        f.text:SetPoint("LEFT", f.icon, "RIGHT", gap, 0)
    else
        f.icon:Hide()
        f.text:ClearAllPoints()
        f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
    end
end

-- 설정값을 프레임에 반영 (위치/폰트/잠금)
function SA_UpdateDeathFrame()
    local f = SA_EnsureDeathFrame()
    local dt = MimDiceDB and MimDiceDB.deathTrack
    if not dt then return end

    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", dt.x or 0, dt.y or 200)

    if dt.locked then
        f.bg:Hide()
        f:EnableMouse(false)
        -- 잠금 상태에서 미리보기가 떠 있으면 지움
        if not f.fadeAnim:IsPlaying() and f.previewing then
            f.text:SetText("")
            f.icon:Hide()
            f.previewing = false
        end
    else
        f.bg:Show()
        f:EnableMouse(true)
        f.fadeAnim:Stop()
        f:SetAlpha(1)
        f.previewing = true
        -- 위치 조정용 미리보기 (현재 직업색/역할)
        local c = dt.color or { r = 1, g = 0.2, b = 0.2 }
        local suffixColored = "|cff" .. string.format("%02x%02x%02x", (c.r or 1)*255, (c.g or 0.2)*255, (c.b or 0.2)*255)
            .. (dt.suffix or " 사망 !!") .. "|r"
        SA_SetDeathContent(SA_PlayerRoleForPreview(), dt.fontSize or 24, SA_PlayerColoredName() .. suffixColored)
    end
end

-- =====================================================================
-- 죽음 메시지 설정 팝업 (⚙ 버튼으로 열림)
-- =====================================================================
-- (SA_DeathConfig 는 위 죽음 프레임 근처에서 미리 선언됨)
local SA_BuffConfigs = {}   -- 버프별 설정창(블러드/마력주입). 상호 닫기용으로 미리 선언.

-- 설정값 변경 시 미리보기 실시간 갱신
-- - 잠금 해제(위치잡기) 모드면 SA_UpdateDeathFrame이 미리보기 텍스트 갱신
-- - 잠금 모드인데 미리보기 메시지가 떠 있으면 새 설정으로 다시 그림
local function SA_RefreshPreviewIfVisible()
    local f = SA_DeathFrame
    if not f then return end
    local dt = MimDiceDB and MimDiceDB.deathTrack
    if not dt then return end

    if not dt.locked then
        SA_UpdateDeathFrame()
        return
    end

    if f:IsShown() and f.fadeAnim and (f.fadeAnim:IsPlaying() or (f:GetAlpha() or 0) > 0.05) then
        local txt = f.text and f.text:GetText()
        if txt and txt ~= "" then
            SA_DeathPreview()
        end
    end
end

-- 공용: 라벨 + 슬라이더 + 직접입력 EditBox 한 세트 생성 (1단위 미세조정 + 타이핑)
-- getFn(): 현재값 반환 / setFn(v): 값 저장 / onChange(): 적용(미리보기 등)
local function SA_MakeNumberSlider(parent, sliderName, y, labelText, minV, maxV, getFn, setFn, onChange)
    -- 라벨 (범위 함께 표시: 예 "바 가로 크기 (100~1900)")
    local lbl = parent:CreateFontString(nil, "OVERLAY")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, y)
    lbl:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    lbl:SetText(labelText .. " (" .. minV .. "~" .. maxV .. ")")
    lbl:SetTextColor(0.9, 0.9, 0.9)

    -- 슬라이더 (좁게) + 우측에 직접 입력칸
    local s = CreateFrame("Slider", sliderName, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y - 22)
    s:SetWidth(190)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(1)
    s:SetObeyStepOnDrag(true)
    _G[sliderName .. "Low"]:SetText("")    -- 범위는 라벨에 표시하므로 숨김
    _G[sliderName .. "High"]:SetText("")
    _G[sliderName .. "Text"]:SetText("")

    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(52, 22)
    edit:SetPoint("LEFT", s, "RIGHT", 18, 0)   -- 슬라이더 바로 우측
    edit:SetAutoFocus(false)
    edit:SetFont("Fonts\\2002.ttf", 12, "")
    edit:SetNumeric(true)
    edit:SetMaxLetters(4)
    edit:SetJustifyH("CENTER")

    local syncing = false
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        setFn(v)
        if not syncing then edit:SetText(tostring(v)) end
        if onChange then onChange() end
    end)

    local function commit()
        local v = tonumber(edit:GetText())
        if v then
            if v < minV then v = minV elseif v > maxV then v = maxV end
            syncing = true
            s:SetValue(v)       -- OnValueChanged 가 setFn/onChange 처리
            syncing = false
            edit:SetText(tostring(v))
        end
        edit:ClearFocus()
    end
    edit:SetScript("OnEnterPressed", commit)
    edit:SetScript("OnEscapePressed", function() edit:ClearFocus() end)
    edit:SetScript("OnEditFocusLost", commit)

    -- 외부에서 현재값으로 갱신할 때 사용
    s.SyncValue = function()
        local v = getFn() or minV
        syncing = true
        s:SetValue(v)
        syncing = false
        edit:SetText(tostring(math.floor(v + 0.5)))
    end
    return s
end

-- 위치 X/Y 직접 입력 행 (중앙 = 0,0 / +x 오른쪽, -x 왼쪽 / +y 위, -y 아래)
-- 음수 입력 허용해야 해서 SetNumeric 안 씀. refresh 함수 반환.
local function SA_AddPosRow(parent, y, getX, setX, getY, setY, onChange)
    local lbl = parent:CreateFontString(nil, "OVERLAY")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, y)
    lbl:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    lbl:SetTextColor(0.9, 0.9, 0.9)
    lbl:SetText("위치 (중앙 0,0)   X")

    local function mkBox(getF, setF)
        local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        e:SetSize(50, 20)
        e:SetAutoFocus(false)
        e:SetFont("Fonts\\2002.ttf", 11, "")
        e:SetMaxLetters(6)
        local function commit()
            local v = tonumber(e:GetText())
            if v then setF(math.floor(v + 0.5)); if onChange then onChange() end end
            e:SetText(tostring(math.floor((getF() or 0) + 0.5)))
            e:ClearFocus()
        end
        e:SetScript("OnEnterPressed", commit)
        e:SetScript("OnEditFocusLost", commit)
        e:SetScript("OnEscapePressed", function() e:ClearFocus() end)
        return e
    end

    local ex = mkBox(getX, setX)
    ex:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
    local lblY = parent:CreateFontString(nil, "OVERLAY")
    lblY:SetPoint("LEFT", ex, "RIGHT", 12, 0)
    lblY:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    lblY:SetTextColor(0.9, 0.9, 0.9)
    lblY:SetText("Y")
    local ey = mkBox(getY, setY)
    ey:SetPoint("LEFT", lblY, "RIGHT", 8, 0)

    return function()
        ex:SetText(tostring(math.floor((getX() or 0) + 0.5)))
        ey:SetText(tostring(math.floor((getY() or 0) + 0.5)))
    end
end

local function SA_CreateDeathConfig()
    if SA_DeathConfig then return SA_DeathConfig end

    local win = CreateFrame("Frame", "MimDice_DeathConfig", UIParent, "BackdropTemplate")
    win:SetSize(340, 470)
    -- 기본 위치: 옵션창 우측 (열 때마다 이 위치로). 드래그로 임시 이동 가능.
    win:SetPoint("TOPLEFT", SA_OptionWindow, "TOPRIGHT", 6, 0)
    win:SetFrameStrata("DIALOG")
    win:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    win:SetBackdropColor(0, 0, 0, 0.5)               -- 옵션창과 동일한 투명도
    win:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)   -- 화면 밖으로 못 나가게
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)

    local title = win:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", win, "TOP", 0, -12)
    title:SetFont("Fonts\\2002.ttf", 13, "OUTLINE")
    title:SetText("죽음 알림 설정 (공용)")
    title:SetTextColor(1, 0.82, 0)

    local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() win:Hide() end)

    -- ── 재생 사운드 ─────────────────────────
    local soundLabel = win:CreateFontString(nil, "OVERLAY")
    soundLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -36)
    soundLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    soundLabel:SetText("재생 사운드 (커스텀: sounds 폴더 파일명 / ID: 숫자)")
    soundLabel:SetTextColor(0.9, 0.9, 0.9)

    local typeBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    typeBtn:SetSize(48, 22)
    typeBtn:SetPoint("TOPLEFT", win, "TOPLEFT", 20, -56)
    typeBtn:GetFontString():SetFont("Fonts\\2002.ttf", 10, "")
    win.typeBtn = typeBtn

    local soundBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    soundBox:SetSize(175, 22)
    soundBox:SetPoint("LEFT", typeBtn, "RIGHT", 12, 0)
    soundBox:SetAutoFocus(false)
    soundBox:SetFont("Fonts\\2002.ttf", 11, "")
    win.soundBox = soundBox

    local soundTestBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    soundTestBtn:SetSize(24, 22)
    soundTestBtn:SetPoint("LEFT", soundBox, "RIGHT", 6, 0)
    soundTestBtn:SetText("▶")
    soundTestBtn:SetScript("OnClick", function()
        local dt = MimDiceDB.deathTrack
        local was = dt.enabled
        dt.enabled = true            -- 테스트는 마스터 off여도 재생
        SA_PlaySound(dt)
        dt.enabled = was
    end)

    function win.RefreshSoundRow()
        local dt = MimDiceDB.deathTrack
        typeBtn:SetText(dt.soundType == "id" and "ID" or "커스텀")
        if dt.soundType == "id" then
            soundBox:SetText(dt.soundKey and tostring(dt.soundKey) or "")
        else
            soundBox:SetText(dt.soundFile or "")
        end
    end

    typeBtn:SetScript("OnClick", function()
        local dt = MimDiceDB.deathTrack
        dt.soundType = (dt.soundType == "custom") and "id" or "custom"
        win.RefreshSoundRow()
    end)
    soundBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local dt = MimDiceDB.deathTrack
        if dt.soundType == "id" then
            dt.soundKey = tonumber(self:GetText()) or self:GetText()
        else
            dt.soundFile = self:GetText()
            dt.soundName = self:GetText()
        end
    end)
    soundBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- ── 화면 메시지 표시 on/off ─────────────
    local enableCb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    enableCb:SetSize(22, 22)
    enableCb:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -86)
    local enableLabel = win:CreateFontString(nil, "OVERLAY")
    enableLabel:SetPoint("LEFT", enableCb, "RIGHT", 2, 0)
    enableLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    enableLabel:SetText("화면에 죽음 메시지 표시")
    enableLabel:SetTextColor(0.9, 0.9, 0.9)
    enableCb:SetScript("OnClick", function(self)
        MimDiceDB.deathTrack.showMessage = self:GetChecked() and true or false
    end)
    win.enableCb = enableCb

    -- 문구 입력
    local suffixLabel = win:CreateFontString(nil, "OVERLAY")
    suffixLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -114)
    suffixLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    suffixLabel:SetText("닉네임 뒤 문구 (예: 사망 !!)")
    suffixLabel:SetTextColor(0.9, 0.9, 0.9)

    local suffixBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    suffixBox:SetSize(200, 22)
    suffixBox:SetPoint("TOPLEFT", win, "TOPLEFT", 20, -134)
    suffixBox:SetAutoFocus(false)
    suffixBox:SetFont("Fonts\\2002.ttf", 12, "")
    suffixBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            MimDiceDB.deathTrack.suffix = self:GetText()
            SA_RefreshPreviewIfVisible()
        end
    end)
    suffixBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    win.suffixBox = suffixBox

    -- 글씨 크기 (슬라이더 + 직접 입력)
    local sizeSlider = SA_MakeNumberSlider(win, "MimDice_DeathSizeSlider", -166, "글씨 크기", 12, 120,
        function() return MimDiceDB.deathTrack.fontSize end,
        function(v) MimDiceDB.deathTrack.fontSize = v end,
        function() SA_RefreshPreviewIfVisible() end)
    win.sizeSlider = sizeSlider

    -- 색상 프리셋 그리드 (7 x 4)
    local colorLabel = win:CreateFontString(nil, "OVERLAY")
    colorLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -222)
    colorLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    colorLabel:SetText("문구 색상")
    colorLabel:SetTextColor(0.9, 0.9, 0.9)

    win.swatches = {}
    local SWATCH = 26
    local GAP = 4
    local startX, startY = 20, -242
    for idx, rgb in ipairs(SA_COLOR_PRESETS) do
        local colN = (idx - 1) % 7
        local rowN = math.floor((idx - 1) / 7)
        local sw = CreateFrame("Button", nil, win)
        sw:SetSize(SWATCH, SWATCH)
        sw:SetPoint("TOPLEFT", win, "TOPLEFT", startX + colN * (SWATCH + GAP), startY - rowN * (SWATCH + GAP))

        -- 선택 표시용 흰 테두리(BACKGROUND): 색 텍스처보다 2px 크게 깔아 가장자리만 보이게
        local sel = sw:CreateTexture(nil, "BACKGROUND")
        sel:SetPoint("TOPLEFT", -2, 2)
        sel:SetPoint("BOTTOMRIGHT", 2, -2)
        sel:SetColorTexture(1, 1, 1, 1)
        sel:Hide()
        sw.sel = sel

        local tex = sw:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
        sw.tex = tex

        sw:SetScript("OnClick", function()
            MimDiceDB.deathTrack.color = { r = rgb[1], g = rgb[2], b = rgb[3] }
            for _, other in ipairs(win.swatches) do other.sel:Hide() end
            sw.sel:Show()
            SA_RefreshPreviewIfVisible()
        end)
        win.swatches[idx] = sw
    end

    -- 위치 X/Y 직접 입력
    win.posRefresh = SA_AddPosRow(win, -368,
        function() return MimDiceDB.deathTrack.x end,
        function(v) MimDiceDB.deathTrack.x = v end,
        function() return MimDiceDB.deathTrack.y end,
        function(v) MimDiceDB.deathTrack.y = v end,
        function() SA_RefreshPreviewIfVisible() end)

    -- 위치 잠금/해제 토글
    local lockBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    lockBtn:SetSize(110, 24)
    lockBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 15, 14)
    lockBtn:GetFontString():SetFont("Fonts\\2002.ttf", 10, "")
    lockBtn:SetScript("OnClick", function()
        local dt = MimDiceDB.deathTrack
        dt.locked = not dt.locked
        SA_UpdateDeathFrame()
        win.RefreshLockBtn()
    end)
    win.lockBtn = lockBtn

    function win.RefreshLockBtn()
        if MimDiceDB.deathTrack.locked then
            lockBtn:SetText("위치 잠금 해제")
        else
            lockBtn:SetText("위치 잠금(드래그끝)")
        end
    end

    -- 기본값으로 초기화 (글씨 80, 중앙, 마력주입 바 아래)
    local resetBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    resetBtn:SetSize(70, 24)
    resetBtn:SetPoint("BOTTOM", win, "BOTTOM", 0, 14)
    resetBtn:SetText("기본값")
    resetBtn:GetFontString():SetFont("Fonts\\2002.ttf", 11, "")
    resetBtn:SetScript("OnClick", function()
        local dt = MimDiceDB.deathTrack
        dt.fontSize, dt.x, dt.y = 80, 0, 130
        dt.color = { r = 1, g = 0.2, b = 0.2 }
        dt.locked, dt.showMessage = true, true
        SA_UpdateDeathFrame()
        SA_RefreshDeathConfig()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MimDice]|r 죽음 메시지 설정 초기화됨")
    end)

    -- 미리보기(테스트) 버튼
    local testBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    testBtn:SetSize(90, 24)
    testBtn:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -15, 14)
    testBtn:SetText("미리보기")
    testBtn:GetFontString():SetFont("Fonts\\2002.ttf", 11, "")
    testBtn:SetScript("OnClick", function()
        SA_DeathPreview()
    end)

    win:Hide()  -- 생성 직후 숨김 (CreateFrame 기본은 표시 상태 → 첫 클릭에 닫히는 문제 방지)
    SA_DeathConfig = win
    return win
end

-- 현재 설정값을 팝업 위젯에 반영 (전역: SA_CreateDeathConfig 내부 reset 버튼에서도 참조)
function SA_RefreshDeathConfig()
    local win = SA_DeathConfig
    if not win then return end
    local dt = MimDiceDB.deathTrack

    win.RefreshSoundRow()
    win.enableCb:SetChecked(dt.showMessage)
    win.suffixBox:SetText(dt.suffix or " 사망 !!")
    win.sizeSlider.SyncValue()
    win.posRefresh()
    win.RefreshLockBtn()

    -- 현재 색과 일치하는 스와치 선택 표시
    local cc = dt.color or { r = 1, g = 0.2, b = 0.2 }
    for idx, rgb in ipairs(SA_COLOR_PRESETS) do
        local match = math.abs(rgb[1] - (cc.r or 0)) < 0.02
            and math.abs(rgb[2] - (cc.g or 0)) < 0.02
            and math.abs(rgb[3] - (cc.b or 0)) < 0.02
        if win.swatches[idx] then
            if match then win.swatches[idx].sel:Show() else win.swatches[idx].sel:Hide() end
        end
    end
end

function SA_ToggleDeathConfig()
    local win = SA_CreateDeathConfig()
    if win:IsShown() then
        win:Hide()
    else
        for _, w in pairs(SA_BuffConfigs) do if w:IsShown() then w:Hide() end end  -- 겹침 방지
        -- 열 때마다 옵션창 우측 기본 위치로 초기화 (화면 밖으로 사라져도 복구됨)
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", SA_OptionWindow, "TOPRIGHT", 6, 0)
        SA_RefreshDeathConfig()
        win:Show()
    end
end

-- =====================================================================
-- 버프 지속바 설정 팝업 (블러드 / 마력주입 공용, 탭 전환)
-- (SA_BuffConfig 지역변수는 위 죽음 설정창 근처에서 미리 선언됨)
-- =====================================================================

-- 버프별 설정창 (블러드/마력주입 각각 별도 창) - SA_BuffConfigs는 위에서 선언됨

-- 버프 설정용 슬라이더 한 세트 (공용 SA_MakeNumberSlider 래퍼)
local function SA_AddBuffSlider(win, key, sliderName, y, labelText, minV, maxV, field)
    return SA_MakeNumberSlider(win, sliderName, y, labelText, minV, maxV,
        function() return MimDiceDB.buffTrack[key][field] end,
        function(v) MimDiceDB.buffTrack[key][field] = v end,
        function() SA_UpdateBuffBar(key) end)
end

local function SA_CreateBuffConfig(key)
    if SA_BuffConfigs[key] then return SA_BuffConfigs[key] end
    local def = BUFF_DEF_BY_KEY[key]

    local win = CreateFrame("Frame", "MimDice_BuffConfig_" .. key, UIParent, "BackdropTemplate")
    win:SetSize(340, 580)
    win:SetPoint("TOPLEFT", SA_OptionWindow, "TOPRIGHT", 6, 0)
    win:SetFrameStrata("DIALOG")
    win:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    win:SetBackdropColor(0, 0, 0, 0.5)
    win:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)   -- 화면 밖으로 못 나가게
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win.key = key

    local title = win:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", win, "TOP", 0, -12)
    title:SetFont("Fonts\\2002.ttf", 13, "OUTLINE")
    title:SetText(def.name .. " 지속바 설정 (공용)")
    title:SetTextColor(1, 0.82, 0)

    local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() win:Hide() end)

    -- 재생 사운드
    local soundLabel = win:CreateFontString(nil, "OVERLAY")
    soundLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -36)
    soundLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    soundLabel:SetText("재생 사운드 (커스텀: 파일명 / ID: 숫자)")
    soundLabel:SetTextColor(0.9, 0.9, 0.9)

    local typeBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    typeBtn:SetSize(48, 22)
    typeBtn:SetPoint("TOPLEFT", win, "TOPLEFT", 20, -56)
    typeBtn:GetFontString():SetFont("Fonts\\2002.ttf", 10, "")

    local soundBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    soundBox:SetSize(175, 22)
    soundBox:SetPoint("LEFT", typeBtn, "RIGHT", 12, 0)
    soundBox:SetAutoFocus(false)
    soundBox:SetFont("Fonts\\2002.ttf", 11, "")
    win.soundBox = soundBox

    local soundTestBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    soundTestBtn:SetSize(24, 22)
    soundTestBtn:SetPoint("LEFT", soundBox, "RIGHT", 6, 0)
    soundTestBtn:SetText("▶")
    soundTestBtn:SetScript("OnClick", function()
        local bt = MimDiceDB.buffTrack[key]
        local was = bt.enabled
        bt.enabled = true
        SA_PlaySound(bt)
        bt.enabled = was
    end)

    function win.RefreshSoundRow()
        local bt = MimDiceDB.buffTrack[key]
        typeBtn:SetText(bt.soundType == "id" and "ID" or "커스텀")
        if bt.soundType == "id" then
            soundBox:SetText(bt.soundKey and tostring(bt.soundKey) or "")
        else
            soundBox:SetText(bt.soundFile or "")
        end
    end

    typeBtn:SetScript("OnClick", function()
        local bt = MimDiceDB.buffTrack[key]
        bt.soundType = (bt.soundType == "custom") and "id" or "custom"
        win.RefreshSoundRow()
    end)
    soundBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local bt = MimDiceDB.buffTrack[key]
        if bt.soundType == "id" then
            bt.soundKey = tonumber(self:GetText()) or self:GetText()
        else
            bt.soundFile = self:GetText()
            bt.soundName = self:GetText()
        end
    end)
    soundBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- 바 표시 체크박스
    local barCb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    barCb:SetSize(22, 22)
    barCb:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -86)
    local barLabel = win:CreateFontString(nil, "OVERLAY")
    barLabel:SetPoint("LEFT", barCb, "RIGHT", 2, 0)
    barLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    barLabel:SetText("화면에 지속시간 바 표시")
    barLabel:SetTextColor(0.9, 0.9, 0.9)
    barCb:SetScript("OnClick", function(self)
        MimDiceDB.buffTrack[key].barEnabled = self:GetChecked() and true or false
    end)
    win.barCb = barCb

    -- 바 색상 그리드 (28색)
    local colorLabel = win:CreateFontString(nil, "OVERLAY")
    colorLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -112)
    colorLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    colorLabel:SetText("바 색상")
    colorLabel:SetTextColor(0.9, 0.9, 0.9)

    win.swatches = {}
    local SWATCH, GAP = 26, 4
    local startX, startY = 20, -132
    for idx, rgb in ipairs(SA_COLOR_PRESETS) do
        local colN = (idx - 1) % 7
        local rowN = math.floor((idx - 1) / 7)
        local sw = CreateFrame("Button", nil, win)
        sw:SetSize(SWATCH, SWATCH)
        sw:SetPoint("TOPLEFT", win, "TOPLEFT", startX + colN * (SWATCH + GAP), startY - rowN * (SWATCH + GAP))

        local sel = sw:CreateTexture(nil, "BACKGROUND")
        sel:SetPoint("TOPLEFT", -2, 2)
        sel:SetPoint("BOTTOMRIGHT", 2, -2)
        sel:SetColorTexture(1, 1, 1, 1)
        sel:Hide()
        sw.sel = sel

        local tex = sw:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)

        sw:SetScript("OnClick", function()
            MimDiceDB.buffTrack[key].color = { r = rgb[1], g = rgb[2], b = rgb[3] }
            for _, other in ipairs(win.swatches) do other.sel:Hide() end
            sw.sel:Show()
            SA_UpdateBuffBar(key)
        end)
        win.swatches[idx] = sw
    end

    -- 크기/투명도 슬라이더 (가로/세로/글씨/투명도)
    win.wSlider = SA_AddBuffSlider(win, key, "MimDice_BuffW_" .. key, -256, "바 가로 크기", 100, 1900, "width")
    win.hSlider = SA_AddBuffSlider(win, key, "MimDice_BuffH_" .. key, -310, "바 세로 크기", 16, 300, "height")
    win.tfSlider = SA_AddBuffSlider(win, key, "MimDice_BuffTF_" .. key, -364, "글씨 크기 (라벨+남은시간)", 8, 120, "timeFontSize")
    win.aSlider = SA_AddBuffSlider(win, key, "MimDice_BuffA_" .. key, -418, "바 투명도 (%)", 10, 100, "alphaPct")

    -- 위치 X/Y 직접 입력
    win.posRefresh = SA_AddPosRow(win, -464,
        function() return MimDiceDB.buffTrack[key].x end,
        function(v) MimDiceDB.buffTrack[key].x = v end,
        function() return MimDiceDB.buffTrack[key].y end,
        function(v) MimDiceDB.buffTrack[key].y = v end,
        function() SA_UpdateBuffBar(key) end)

    -- 위치 잠금/해제
    local lockBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    lockBtn:SetSize(110, 24)
    lockBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 15, 14)
    lockBtn:GetFontString():SetFont("Fonts\\2002.ttf", 10, "")
    lockBtn:SetScript("OnClick", function()
        local bt = MimDiceDB.buffTrack[key]
        bt.locked = not bt.locked
        SA_UpdateBuffBar(key)
        win.RefreshLockBtn()
    end)
    win.lockBtn = lockBtn
    function win.RefreshLockBtn()
        lockBtn:SetText(MimDiceDB.buffTrack[key].locked and "위치 잠금 해제" or "위치 잠금(드래그끝)")
    end

    -- 기본값으로 초기화
    local resetBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    resetBtn:SetSize(70, 24)
    resetBtn:SetPoint("BOTTOM", win, "BOTTOM", 0, 14)
    resetBtn:SetText("기본값")
    resetBtn:GetFontString():SetFont("Fonts\\2002.ttf", 11, "")
    resetBtn:SetScript("OnClick", function()
        local d = BUFF_DEF_BY_KEY[key]
        local bt = MimDiceDB.buffTrack[key]
        bt.width, bt.height, bt.timeFontSize, bt.alphaPct = 800, 50, 40, 50
        bt.x, bt.y = 0, d.dy
        bt.color = { r = d.color[1], g = d.color[2], b = d.color[3] }
        bt.barEnabled, bt.locked = true, true
        SA_UpdateBuffBar(key)
        win.Refresh()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MimDice]|r " .. d.name .. " 바 설정 초기화됨")
    end)

    -- 미리보기
    local previewBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    previewBtn:SetSize(90, 24)
    previewBtn:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -15, 14)
    previewBtn:SetText("미리보기")
    previewBtn:GetFontString():SetFont("Fonts\\2002.ttf", 11, "")
    previewBtn:SetScript("OnClick", function() SA_BuffPreview(key) end)

    -- 현재 설정값을 위젯에 반영
    function win.Refresh()
        local bt = MimDiceDB.buffTrack[key]
        win.RefreshSoundRow()
        barCb:SetChecked(bt.barEnabled)
        win.RefreshLockBtn()
        win.wSlider.SyncValue()
        win.hSlider.SyncValue()
        win.tfSlider.SyncValue()
        win.aSlider.SyncValue()
        win.posRefresh()
        local cc = bt.color or { r = 1, g = 0.2, b = 0.2 }
        for i, rgb in ipairs(SA_COLOR_PRESETS) do
            local match = math.abs(rgb[1] - (cc.r or 0)) < 0.02
                and math.abs(rgb[2] - (cc.g or 0)) < 0.02
                and math.abs(rgb[3] - (cc.b or 0)) < 0.02
            if win.swatches[i] then
                if match then win.swatches[i].sel:Show() else win.swatches[i].sel:Hide() end
            end
        end
    end

    win:Hide()
    SA_BuffConfigs[key] = win
    return win
end

function SA_ToggleBuffConfig(key)
    local win = SA_CreateBuffConfig(key)
    if win:IsShown() then
        win:Hide()
    else
        -- 다른 설정창들 닫기 (같은 위치에 겹침 방지)
        for k, w in pairs(SA_BuffConfigs) do if k ~= key and w:IsShown() then w:Hide() end end
        if SA_DeathConfig and SA_DeathConfig:IsShown() then SA_DeathConfig:Hide() end
        -- 열 때마다 옵션창 우측 기본 위치로 초기화 (화면 밖으로 사라져도 복구됨)
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", SA_OptionWindow, "TOPRIGHT", 6, 0)
        win.Refresh()
        win:Show()
    end
end

-- 실제 죽음 메시지 표시
local function SA_ShowDeathMessage(name, role, classFile)
    local dt = MimDiceDB and MimDiceDB.deathTrack
    if not dt or not dt.showMessage then return end

    local f = SA_EnsureDeathFrame()
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", dt.x or 0, dt.y or 200)

    -- 닉네임 직업색
    local coloredName
    if classFile and not SA_IsSecret(classFile) then
        local c = C_ClassColor and C_ClassColor.GetClassColor(classFile)
        if c then
            coloredName = "|c" .. c:GenerateHexColor() .. name .. "|r"
        end
    end
    if not coloredName then
        coloredName = "|cffffffff" .. name .. "|r"
    end

    -- 문구 색
    local col = dt.color or { r = 1, g = 0.2, b = 0.2 }
    local hex = string.format("%02x%02x%02x", (col.r or 1) * 255, (col.g or 0.2) * 255, (col.b or 0.2) * 255)
    local suffixColored = "|cff" .. hex .. (dt.suffix or " 사망 !!") .. "|r"

    SA_SetDeathContent(role, dt.fontSize or 24, coloredName .. suffixColored)

    -- 표시 후 페이드아웃
    f.previewing = false
    f.fadeAnim:Stop()
    f:SetAlpha(1)
    f.fade:SetStartDelay(dt.duration or 3)
    f.fadeAnim:Play()
end

-- 미리보기 (설정 팝업의 "미리보기" 버튼용) - 현재 접속 직업색으로 표시
function SA_DeathPreview()
    local dt = MimDiceDB and MimDiceDB.deathTrack
    if not dt then return end
    local was = dt.showMessage
    dt.showMessage = true             -- 미리보기는 항상 보이게
    local name = UnitName("player") or "밈주머니"
    local _, classFile = UnitClass("player")
    SA_ShowDeathMessage(name, SA_PlayerRoleForPreview(), classFile)
    dt.showMessage = was
end

-- =====================================================================
-- 블러드 / 마력주입 지속시간 바
-- =====================================================================
local SA_BuffBars = {}

local function SA_EnsureBuffBar(key)
    if SA_BuffBars[key] then return SA_BuffBars[key] end
    local def = BUFF_DEF_BY_KEY[key]
    local bt = MimDiceDB.buffTrack[key]

    local f = CreateFrame("Frame", "MimDice_BuffBar_" .. key, UIParent, "BackdropTemplate")
    f:SetSize(bt.width or 220, bt.height or 24)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    f:SetBackdropColor(0, 0, 0, 0.25)               -- 반투명 배경 (전투화면 안 가리게)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.6)

    local sb = CreateFrame("StatusBar", nil, f)
    sb:SetPoint("TOPLEFT", 4, -4)
    sb:SetPoint("BOTTOMRIGHT", -4, 4)
    sb:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(1)
    f.sb = sb

    -- 채워지지 않은 빈 트랙 (반투명)
    local track = sb:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0.1, 0.1, 0.1, 0.25)
    f.track = track

    local lbl = sb:CreateFontString(nil, "OVERLAY")
    lbl:SetPoint("LEFT", sb, "LEFT", 6, 0)
    lbl:SetFont("Fonts\\2002.ttf", 12, "OUTLINE")
    lbl:SetText(def.name)
    lbl:SetShadowColor(0, 0, 0, 1); lbl:SetShadowOffset(1, -1)
    f.lbl = lbl

    local timeTxt = sb:CreateFontString(nil, "OVERLAY")
    timeTxt:SetPoint("RIGHT", sb, "RIGHT", -6, 0)
    timeTxt:SetFont("Fonts\\2002.ttf", 13, "OUTLINE")
    timeTxt:SetShadowColor(0, 0, 0, 1); timeTxt:SetShadowOffset(1, -1)
    f.timeTxt = timeTxt

    -- 현재 위치를 DB에 저장하고, 설정창이 열려있으면 X/Y 입력칸도 실시간 갱신
    local function savePos(self)
        local x, y = self:GetCenter(); local cx, cy = UIParent:GetCenter()
        if x and cx then
            MimDiceDB.buffTrack[key].x = x - cx
            MimDiceDB.buffTrack[key].y = y - cy
        end
        local cfg = SA_BuffConfigs[key]
        if cfg and cfg:IsShown() and cfg.posRefresh then cfg.posRefresh() end
    end

    f:SetScript("OnMouseDown", function(self, btn)
        local b = MimDiceDB.buffTrack[key]
        if btn == "LeftButton" and b and not b.locked then
            self:StartMoving()
            self.moving = true
        end
    end)
    f:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        self.moving = false
        savePos(self)
    end)

    f.endTime = 0
    f.duration = 0
    f:Hide()

    -- 매 프레임: 드래그 중이면 위치 실시간 갱신, 아니면 카운트다운
    f:SetScript("OnUpdate", function(self)
        if self.moving then savePos(self); return end
        if self.previewing then return end   -- 위치 잡기용 정적 미리보기면 카운트 안 함
        local remain = self.endTime - GetTime()
        if remain <= 0 then
            self:Hide()
            return
        end
        self.sb:SetValue(self.duration > 0 and (remain / self.duration) or 0)
        self.timeTxt:SetText(string.format("%.1f", remain))
    end)

    SA_BuffBars[key] = f
    return f
end

-- 설정값 반영 (위치/크기/색) + 잠금 해제 시 위치잡기용 정적 미리보기
function SA_UpdateBuffBar(key)
    local bt = MimDiceDB and MimDiceDB.buffTrack and MimDiceDB.buffTrack[key]
    if not bt then return end
    local def = BUFF_DEF_BY_KEY[key]
    local f = SA_EnsureBuffBar(key)
    f:SetSize(bt.width or 220, bt.height or 24)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", bt.x or 0, bt.y or -150)
    local c = bt.color or { r = 1, g = 0.2, b = 0.2 }
    f.sb:SetStatusBarColor(c.r, c.g, c.b, (bt.alphaPct or 70) / 100)   -- 사용자 투명도
    local fs = bt.timeFontSize or 14
    f.timeTxt:SetFont("Fonts\\2002.ttf", fs, "OUTLINE")
    f.lbl:SetFont("Fonts\\2002.ttf", fs, "OUTLINE")   -- 라벨(블러드 등)도 같이 스케일

    if not bt.locked then
        -- 위치 잡기: 정적 풀 바 표시
        f.previewing = true
        f.sb:SetValue(1)
        f.timeTxt:SetText(string.format("%.1f", def.duration))
        f:SetAlpha(1)
        f:EnableMouse(true)
        f:Show()
    else
        f.previewing = false
        f:EnableMouse(false)
        if f.endTime <= GetTime() then f:Hide() end
    end
end

-- 버프 발동 시 바 시작 (force=true면 활성/표시 여부 무시 - 미리보기용)
local function SA_StartBuffBar(key, duration, force)
    local bt = MimDiceDB and MimDiceDB.buffTrack and MimDiceDB.buffTrack[key]
    if not bt then return end
    if not force and (not bt.enabled or not bt.barEnabled) then return end
    local f = SA_EnsureBuffBar(key)
    SA_UpdateBuffBar(key)
    f.duration = duration
    f.endTime = GetTime() + duration
    f.previewing = false
    f:SetAlpha(1)
    f.sb:SetValue(1)
    f.timeTxt:SetText(string.format("%.1f", duration))
    f:EnableMouse(false)
    f:Show()
end

-- 버프 사운드 재생 (계정 공용, bt.enabled로 게이트)
local function SA_PlayBuff(key)
    local bt = MimDiceDB and MimDiceDB.buffTrack and MimDiceDB.buffTrack[key]
    if not bt or not bt.enabled then return end
    SA_PlaySound(bt)
end

-- 미리보기 (설정창 버튼) - 활성/표시 무관하게 바를 잠깐 보여줌
function SA_BuffPreview(key)
    local def = BUFF_DEF_BY_KEY[key]
    if def then SA_StartBuffBar(key, def.duration, true) end
end

local function SA_HandleUnitDied(deadGUID)
    -- 죽음 추적 OFF면 GUID 해석/throttle 전에 바로 종료 (계정 공용 설정)
    local dt = MimDiceDB and MimDiceDB.deathTrack
    if not dt or not dt.enabled then return end
    if not deadGUID or SA_IsSecret(deadGUID) then return end

    local unitID = SA_GetUnitFromGUID(deadGUID)
    if not unitID or SA_IsSecret(unitID) then return end

    -- 거짓 죽음(Feign Death) 등 필터: 실제로 죽은 상태인지 확인
    local isDead = UnitIsDead(unitID)
    if SA_IsSecret(isDead) or not isDead then return end

    -- 파티/공대원 또는 본인일 때만
    if not (UnitInParty(unitID) or UnitInRaid(unitID) or UnitIsUnit(unitID, "player")) then
        return
    end

    if not SA_DeathThrottleAllow() then return end

    -- 사운드 재생 (dt.enabled 이미 true 확인됨)
    SA_PlaySound(dt)

    -- 화면 메시지 (이름/역할/직업이 secret이면 안전하게 fallback)
    local name = UnitName(unitID)
    if SA_IsSecret(name) or not name then name = "???" end

    local role = UnitGroupRolesAssigned(unitID)
    if SA_IsSecret(role) then role = nil end

    local _, classFile = UnitClass(unitID)
    if SA_IsSecret(classFile) then classFile = nil end

    SA_ShowDeathMessage(name, role, classFile)
end

local SA_EventFrame = CreateFrame("Frame")
SA_EventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
SA_EventFrame:RegisterEvent("PLAYER_LOGIN")
SA_EventFrame:RegisterEvent("UNIT_DIED")
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
                    SA_PlayBuff("BLOODLUST")
                    SA_StartBuffBar("BLOODLUST", BUFF_DEF_BY_KEY["BLOODLUST"].duration)  -- 블러드는 고정 40s
                end
            elseif ok and kind == "POWERINFUSE" then
                SA_PlayBuff("POWERINFUSE")
                SA_StartBuffBar("POWERINFUSE", BUFF_DEF_BY_KEY["POWERINFUSE"].duration)  -- 고정 15초
            end
        end
    elseif event == "UNIT_DIED" then
        -- 파티/공대원/본인 사망 감지
        local deadGUID = ...
        SA_HandleUnitDied(deadGUID)
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
    SA_OptionWindow:SetSize(380, 672)
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

    -- 옵션창이 닫히면 죽음/버프 설정창도 함께 닫기 (우측에 붙어있으므로)
    SA_OptionWindow:HookScript("OnHide", function()
        if SA_DeathConfig and SA_DeathConfig:IsShown() then SA_DeathConfig:Hide() end
        for _, w in pairs(SA_BuffConfigs) do if w:IsShown() then w:Hide() end end
    end)

    -- (옛 제목 "스킬 사운드 알림 설정"은 섹션 헤더로 대체되어 제거됨)

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
    optionSectionLabel:SetText("옵 션")
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

    -- ── << 죽음 알림 >> 섹션 (모든 직업 공용) ──────────────
    local deathSectionLabel = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    deathSectionLabel:SetPoint("TOP", SA_OptionWindow, "TOP", 0, -98)
    deathSectionLabel:SetFont("Fonts\\2002.ttf", 13, "OUTLINE")
    deathSectionLabel:SetText("죽음 알림")
    deathSectionLabel:SetTextColor(1, 0.82, 0)

    local deathCb = CreateFrame("CheckButton", "SA_DeathCheck", SA_OptionWindow, "UICheckButtonTemplate")
    deathCb:SetSize(22, 22)
    deathCb:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 15, -116)
    deathCb:SetChecked(MimDiceDB and MimDiceDB.deathTrack and MimDiceDB.deathTrack.enabled)
    deathCb:SetScript("OnClick", function(self)
        if MimDiceDB and MimDiceDB.deathTrack then
            MimDiceDB.deathTrack.enabled = self:GetChecked() and true or false
            local status = MimDiceDB.deathTrack.enabled and "켜짐" or "꺼짐"
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MimDice]|r 죽음 알림: " .. status)
        end
    end)
    local deathLabel = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    deathLabel:SetPoint("LEFT", deathCb, "RIGHT", 2, 0)
    deathLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    deathLabel:SetText("파티/공대원 사망 시 사운드+메시지")
    deathLabel:SetTextColor(0.9, 0.9, 0.9)

    local deathCfgBtn = CreateFrame("Button", nil, SA_OptionWindow, "UIPanelButtonTemplate")
    deathCfgBtn:SetSize(50, 22)
    deathCfgBtn:SetPoint("TOPRIGHT", SA_OptionWindow, "TOPRIGHT", -15, -116)
    deathCfgBtn:SetText("설정")
    deathCfgBtn:GetFontString():SetFont("Fonts\\2002.ttf", 11, "")
    deathCfgBtn:SetScript("OnClick", function() SA_ToggleDeathConfig() end)

    -- ── << 블러드 / 마력주입 >> 섹션 (모든 직업 공용, 지속시간 바) ──────────────
    local buffSectionLabel = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    buffSectionLabel:SetPoint("TOP", SA_OptionWindow, "TOP", 0, -142)
    buffSectionLabel:SetFont("Fonts\\2002.ttf", 13, "OUTLINE")
    buffSectionLabel:SetText("블러드 / 마력주입")
    buffSectionLabel:SetTextColor(1, 0.82, 0)

    local bloodCb = CreateFrame("CheckButton", "SA_BloodCheck", SA_OptionWindow, "UICheckButtonTemplate")
    bloodCb:SetSize(22, 22)
    bloodCb:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 15, -160)
    bloodCb:SetChecked(MimDiceDB and MimDiceDB.buffTrack and MimDiceDB.buffTrack.BLOODLUST and MimDiceDB.buffTrack.BLOODLUST.enabled)
    bloodCb:SetScript("OnClick", function(self)
        if MimDiceDB and MimDiceDB.buffTrack and MimDiceDB.buffTrack.BLOODLUST then
            MimDiceDB.buffTrack.BLOODLUST.enabled = self:GetChecked() and true or false
        end
    end)
    local bloodLabel = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    bloodLabel:SetPoint("LEFT", bloodCb, "RIGHT", 2, 0)
    bloodLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    bloodLabel:SetText("블러드 (사운드 + 지속시간 바)")
    bloodLabel:SetTextColor(0.9, 0.9, 0.9)

    local bloodCfgBtn = CreateFrame("Button", nil, SA_OptionWindow, "UIPanelButtonTemplate")
    bloodCfgBtn:SetSize(50, 22)
    bloodCfgBtn:SetPoint("TOPRIGHT", SA_OptionWindow, "TOPRIGHT", -15, -160)
    bloodCfgBtn:SetText("설정")
    bloodCfgBtn:GetFontString():SetFont("Fonts\\2002.ttf", 11, "")
    bloodCfgBtn:SetScript("OnClick", function() SA_ToggleBuffConfig("BLOODLUST") end)

    local piCb = CreateFrame("CheckButton", "SA_PICheck", SA_OptionWindow, "UICheckButtonTemplate")
    piCb:SetSize(22, 22)
    piCb:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 15, -182)
    piCb:SetChecked(MimDiceDB and MimDiceDB.buffTrack and MimDiceDB.buffTrack.POWERINFUSE and MimDiceDB.buffTrack.POWERINFUSE.enabled)
    piCb:SetScript("OnClick", function(self)
        if MimDiceDB and MimDiceDB.buffTrack and MimDiceDB.buffTrack.POWERINFUSE then
            MimDiceDB.buffTrack.POWERINFUSE.enabled = self:GetChecked() and true or false
        end
    end)
    local piLabel = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    piLabel:SetPoint("LEFT", piCb, "RIGHT", 2, 0)
    piLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    piLabel:SetText("마력 주입 (사운드 + 지속시간 바)")
    piLabel:SetTextColor(0.9, 0.9, 0.9)

    local piCfgBtn = CreateFrame("Button", nil, SA_OptionWindow, "UIPanelButtonTemplate")
    piCfgBtn:SetSize(50, 22)
    piCfgBtn:SetPoint("TOPRIGHT", SA_OptionWindow, "TOPRIGHT", -15, -182)
    piCfgBtn:SetText("설정")
    piCfgBtn:GetFontString():SetFont("Fonts\\2002.ttf", 11, "")
    piCfgBtn:SetScript("OnClick", function() SA_ToggleBuffConfig("POWERINFUSE") end)

    -- 구분선
    local divider = SA_OptionWindow:CreateTexture(nil, "ARTWORK")
    divider:SetSize(350, 1)
    divider:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 15, -212)
    divider:SetColorTexture(0.5, 0.5, 0.5, 0.6)

    -- ── << 스킬 사운드 알림 >> 섹션 ─────────────────
    local skillSectionLabel = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    skillSectionLabel:SetPoint("TOP", SA_OptionWindow, "TOP", 0, -224)
    skillSectionLabel:SetFont("Fonts\\2002.ttf", 13, "OUTLINE")
    skillSectionLabel:SetText("스킬 사운드 알림 (직업별 저장)")
    skillSectionLabel:SetTextColor(1, 0.82, 0)

    local inputLabel = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    inputLabel:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 15, -250)
    inputLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    inputLabel:SetText("1. 추가할 스킬의 이름 또는 ID 입력 (꼭 띄어쓰기 지켜야 함)")
    inputLabel:SetTextColor(0.9, 0.9, 0.9)

    local inputBox = CreateFrame("EditBox", "SA_SpellInput", SA_OptionWindow, "InputBoxTemplate")
    inputBox:SetSize(200, 22)
    inputBox:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 20, -270)
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
    listTitle:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 15, -310)
    listTitle:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    listTitle:SetText("2. 사운드 개별 설정")
    listTitle:SetTextColor(0.8, 0.8, 0.8)

    local scrollFrame = CreateFrame("ScrollFrame", "SA_ListScrollFrame", SA_OptionWindow, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 10, -330)
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