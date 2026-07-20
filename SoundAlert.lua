-- SoundAlert.lua
-- Author         : BIK
-- Description    : 스킬 사용 시 사운드 재생 모듈 (MimDice 확장 독립창 버전)

---@diagnostic disable: undefined-global, param-type-mismatch, undefined-field, cast-local-type

-- =====================================================================
-- 폰트 : 동봉 폰트 목록 + 현재 선택 폰트 (선택은 즉시 저장, 적용은 리로드)
-- =====================================================================
local MIMDICE_FONT_DIR = "Interface\\AddOns\\MimDice\\Fonts\\"
MIMDICE_FONTS = {
    { key = "default",     name = "와우 기본 (2002)" },
    { key = "nanumgothic", name = "나눔고딕", file = "NanumGothic.ttf" },
}

-- 폰트 파일이 실제로 읽히는지 확인 (내 폰트 등록/표시용).
-- 숨은 글자에 폰트를 입혀 보고, 실제로 그 폰트가 됐는지로 판단한다.
local SA_FontProbe
function MimDiceFontValid(file)
    if not file or file == "" then return false end
    if not SA_FontProbe then
        SA_FontProbe = UIParent:CreateFontString(nil, "BACKGROUND")
        SA_FontProbe:Hide()
    end
    SA_FontProbe:SetFont("Fonts\\2002.ttf", 12, "")
    pcall(SA_FontProbe.SetFont, SA_FontProbe, MIMDICE_FONT_DIR .. file, 12, "")
    local cur = SA_FontProbe:GetFont()
    return cur ~= nil and cur:lower():find(file:lower(), 1, true) ~= nil
end

-- 현재 선택된 폰트의 경로. 문제가 있으면 와우 기본(2002)으로
function MimDiceFontPath()
    local sk = MimDiceDB and MimDiceDB.skin
    local key = sk and sk.font
    if key and key ~= "default" then
        if key:sub(1, 5) == "file:" then
            local file = key:sub(6)                    -- 내 폰트 (파일명 등록)
            if MimDiceFontValid(file) then return MIMDICE_FONT_DIR .. file end
        else
            for _, f in ipairs(MIMDICE_FONTS) do
                if f.key == key and f.file then return MIMDICE_FONT_DIR .. f.file end
            end
        end
    end
    return "Fonts\\2002.ttf"
end

-- 현재 선택된 폰트의 표시 이름
function MimDiceFontName()
    local sk = MimDiceDB and MimDiceDB.skin
    local key = (sk and sk.font) or "default"
    if key:sub(1, 5) == "file:" then return key:sub(6) end
    for _, f in ipairs(MIMDICE_FONTS) do
        if f.key == key then return f.name end
    end
    return "와우 기본 (2002)"
end

-- XML 에 박혀 있는 글자들에도 선택한 폰트를 입힌다 (크기/외곽선은 유지)
function MimDiceApplyFontToXML()
    local path = MimDiceFontPath()
    for _, n in ipairs({ "DiceString", "Mim_Dice_Title", "SortTextHigh", "SortTextLow", "version",
                         "RollStrings", "Announce_ButtonText", "Reset_ButtonText", "Start_ButtonText" }) do
        local fs = _G[n]
        if fs and fs.SetFont then
            local _, size, flags = fs:GetFont()
            pcall(fs.SetFont, fs, path, size or 12, flags)
        end
    end
end

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
            { name = "무두질", id = 567417 },
            { name = "친구 접속", id = 567402 },
            { name = "PVP 깃발", id = 567427 },
            { name = "준비완료", id = 558137 },
            { name = "준비해요", id = 543388 },
            { name = "준비됐습니다", id = 544136 },
            { name = "너흰 아직 준비가 안됐다", id = 552503 },
            { name = "당신을 정화하겠어요", id = 617323 },
            { name = "어둠이여 사라져라", id = 617325 },
            { name = "어째서 포기하지 않죠?", id = 573086 },
            { name = "그래 나도 자네를 구할 수 있어 기쁘네", id = 544345 },
            { name = "거기서 봐요 삼촌", id = 635496 },
            { name = "드디어 제가 바라던 모습을 보여주네요", id = 635498 },
            { name = "미안하지만 당신은 눈에 띄어요", id = 635562 },
            { name = "또~ 죽지마세요", id = 563125 },
            { name = "아 결국 오실 줄 알았어요", id = 3049656 },
        }
    }
}

-- =====================================================================
-- 내부 변수 및 초기화
-- =====================================================================
local SA = {}
local SA_OptionWindow = nil
local SA_TabOption = nil
local SA_TabWhisper = nil      -- 귓속말차단 탭
local SA_WhisperWindow = nil   -- 귓속말차단 옵션창
local SA_TabSkin = nil         -- 스킨 탭
local SA_SkinWindow = nil      -- 스킨 옵션창
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
-- duration: 효과 지속시간(초). 블러드는 고정 40s.
local BUFF_DEFS = {
    {
        key = "BLOODLUST", name = "블러드",
        file = "블러드_ACallToArms.mp3",
        color = { 1.00, 0.20, 0.20 },
        duration = 40, dy = 340,
    },
}
local BUFF_DEF_BY_KEY = {}
for _, d in ipairs(BUFF_DEFS) do BUFF_DEF_BY_KEY[d.key] = d end

-- 전투부활(Combat Resurrection) 충전 추적.
-- WoW는 레이드 공용 전투부활 충전 풀을 Rebirth(20484) ID로 관리하며,
-- C_Spell.GetSpellCharges(20484)는 직업 무관하게 그룹 전체 충전 수를 반환한다.
-- ★ 설계 결정: 직업별 스킬 ID나 기계공학 부활 아이템을 개별 추적하지 않는다.
--   인스턴스에서 어떤 소스(직업 스킬/엔지니어링 아이템)로 부활하든 전부 이 '하나의 공용 풀'을
--   깎으므로, 20484의 충전 변화만 보면 모든 소스가 자동 커버된다. (매 시즌 추가 아이템 추적 불필요)
--   외부 API 호출은 전부 pcall 로 감싸 어떤 직업/상황에서도 lua 에러가 안 나게만 한다.
local BREZ_SPELL_ID = 20484   -- 환생 (Rebirth) — 레이드 공용 전투부활 풀 대표 ID

-- 블러드 감지용 디버프 (Sated/Exhaustion 계열 - 적용 시 블러드 직후로 간주)
local BLOODLUST_DEBUFFS = {
    57723,  -- Exhaustion (Heroism)
    57724,  -- Sated (Bloodlust)
    80354,  -- Temporal Displacement (Time Warp)
    95809,  -- Insanity (Ancient Hysteria)
    264689, -- Fatigued (Primal Rage)
    390435, -- Exhaustion (Fury of the Aspects)
}

-- addedAuras에서 aura.spellId가 블러드 계열 디버프인지 확인 (pcall로 secret value 안전 처리)
local function SA_IsBloodlustAura(aura)
    local sid = aura and aura.spellId
    if not sid then return false end
    for j = 1, #BLOODLUST_DEBUFFS do
        if sid == BLOODLUST_DEBUFFS[j] then return true end
    end
    return false
end

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
    if dt.soundFile == nil or dt.soundFile == "" then dt.soundFile = "왜죽었어.mp3" end  -- 빈 값이면 기본 복원
    -- soundKey(내장 preset 전용) / soundName(내장 표시명)은 기본 nil → 내장 미선택 상태
    if dt.showMessage == nil then dt.showMessage = true end     -- 화면 메시지 표시 여부
    if dt.suffix == nil then dt.suffix = " 사망 !!" end
    if dt.fontSize == nil then dt.fontSize = 80 end          -- 크게
    if dt.color == nil then dt.color = { r = 1, g = 0.2, b = 0.2 } end
    if dt.colorA == nil then dt.colorA = 1 end                    -- 죽음 글자 투명도
    if dt.x == nil then dt.x = 0 end                          -- 중앙
    if dt.y == nil then dt.y = 130 end                        -- 마력주입 바 바로 아래
    dt.locked = true   -- 리로드/재접속 시 항상 잠금으로 시작 (편집 상태 유지 안 함)
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
        if bt.soundFile == nil or bt.soundFile == "" then bt.soundFile = d.file end  -- 빈 값이면 기본 복원
        -- soundKey(내장 preset 전용) / soundName(내장 표시명)은 기본 nil → 내장 미선택 상태
        if bt.barEnabled == nil then bt.barEnabled = true end   -- 지속시간 바 표시 여부
        if bt.color == nil then bt.color = { r = d.color[1], g = d.color[2], b = d.color[3] } end
        if bt.x == nil then bt.x = 0 end
        if bt.y == nil then bt.y = d.dy end
        bt.locked = true   -- 리로드/재접속 시 항상 잠금으로 시작 (편집 상태 유지 안 함)
        if bt.width == nil then bt.width = 800 end               -- 크고 잘 보이는 기본 바
        if bt.height == nil then bt.height = 50 end
        if bt.timeFontSize == nil then bt.timeFontSize = 40 end  -- 글씨 크기 (라벨+남은시간 공통)
        if bt.alphaPct == nil then bt.alphaPct = 50 end          -- 바 채움 투명도 (%)
    end

    -- =================================================================
    -- 전투부활 충전 알림: 계정 공용 (사운드만, 모든 클래스 지원)
    -- =================================================================
    if not MimDiceDB.battleRes then MimDiceDB.battleRes = {} end
    local br = MimDiceDB.battleRes
    if br.enabled == nil then br.enabled = false end             -- 마스터 on/off
    if br.soundType == nil then br.soundType = "preset" end      -- 기본: 내장
    if br.soundFile == nil then br.soundFile = "" end
    if br.soundKey == nil then br.soundKey = 563125 end          -- 기본 내장음: 또~ 죽지마세요
    if br.soundName == nil then br.soundName = "또~ 죽지마세요" end
    -- 기본음 변경(573086 → 563125) 1회 반영: 예전 기본값 그대로였던 사용자만 갱신.
    -- (직접 다른 사운드로 바꾼 사용자는 건드리지 않음)
    if not MimDiceDB.brDefaultV2 then
        if br.soundType == "preset" and br.soundKey == 573086 then
            br.soundKey = 563125
            br.soundName = "또~ 죽지마세요"
        end
        MimDiceDB.brDefaultV2 = true
    end
    -- 전투부활 아이콘(충전 수 + 재충전 스와이프) 표시 옵션 (기본 OFF: 다른 애드온과 중복 방지)
    if br.iconEnabled == nil then br.iconEnabled = false end
    if br.iconX == nil then br.iconX = 0 end
    if br.iconY == nil then br.iconY = 0 end     -- 화면 정중앙 (가려지지 않게)
    if br.iconSize == nil then br.iconSize = 40 end
    br.iconLocked = true   -- 리로드/재접속 시 항상 잠금으로 시작 (편집 상태 유지 안 함)

    -- =================================================================
    -- 파티 신청 알림: 계정 공용 (파티 모집 시 신청 오면 화면 메시지 + 사운드)
    -- =================================================================
    if not MimDiceDB.partyAlert then MimDiceDB.partyAlert = {} end
    local pa = MimDiceDB.partyAlert
    if pa.enabled == nil then pa.enabled = true end              -- 마스터 on/off (기본 ON)
    if pa.soundType == nil then pa.soundType = "preset" end
    if pa.soundFile == nil then pa.soundFile = "" end
    if pa.soundKey == nil then pa.soundKey = 3049656 end         -- 기본 내장음: 아 결국 오실 줄 알았어요
    if pa.soundName == nil then pa.soundName = "아 결국 오실 줄 알았어요" end
    if pa.prefix == nil then pa.prefix = "새 파티 신청!" end     -- 사용자 정의 문구
    if pa.fontSize == nil then pa.fontSize = 30 end
    if pa.color == nil then pa.color = { r = 0.3, g = 1, b = 0.3 } end
    if pa.x == nil then pa.x = 0 end
    if pa.y == nil then pa.y = 400 end                           -- 화면 위쪽
    pa.locked = true   -- 리로드/재접속 시 항상 잠금으로 시작 (편집 상태 유지 안 함)
    if pa.duration == nil then pa.duration = 4 end
    if pa.showClass == nil then pa.showClass = true end          -- 직업 표시
    if pa.showSpec == nil then pa.showSpec = true end            -- 특성 표시
    if pa.showItemLevel == nil then pa.showItemLevel = true end  -- 아이템레벨 표시
    if pa.showScore == nil then pa.showScore = true end          -- 쐐기점수 표시
    if pa.showName == nil then pa.showName = true end            -- 닉네임(이름) 표시
    if pa.bgAlpha == nil then pa.bgAlpha = 0.5 end               -- 배경 반투명도(0~1)
    if pa.bgColor == nil then pa.bgColor = { r = 0, g = 0, b = 0 } end   -- 배경 색상 (기본 검정)
    if pa.statColor == nil then pa.statColor = { r = 1, g = 1, b = 1 } end -- 템렙/쐐기 글자색
    if pa.colorA == nil then pa.colorA = 1 end                   -- 알림 글자 전체 투명도
    if pa.statColorA == nil then pa.statColorA = 1 end           -- 템렙/쐐기 색 투명도(배경색과 섞기)
    -- 반복 알림: "once"=신청 올 때 1회 / "repeat"=대기 신청자 있는 동안 repeatInterval초마다 재알림
    if pa.repeatMode == nil then pa.repeatMode = "once" end
    if pa.repeatInterval == nil then pa.repeatInterval = 5 end
    -- 표시 지속: "fade"=duration초 뒤 페이드아웃 / "stay"=대기 신청자 없어질 때까지 계속 표시
    if pa.displayMode == nil then pa.displayMode = "fade" end
    -- 파티장/공대장/부공대장(초대 권한자)이 아니어도 신청 알림 받기
    if pa.alertAnyRole == nil then pa.alertAnyRole = false end
    -- 5인 풀파티 알림: 파티가 5명이 되는 순간 소리 + 와우 작업표시줄 아이콘 반짝임
    if not pa.fullParty then pa.fullParty = {} end
    local fp = pa.fullParty
    if fp.enabled == nil then fp.enabled = true end
    if fp.soundType == nil then fp.soundType = "preset" end
    if fp.soundFile == nil then fp.soundFile = "" end
    if fp.soundKey == nil then fp.soundKey = 635496 end          -- 기본 내장음: 거기서 봐요 삼촌
    if fp.soundName == nil then fp.soundName = "거기서 봐요 삼촌" end
    -- 기본음 변경(알람 567458 → 3049656) 1회 반영: 예전 기본값 그대로였던(테스트 중 저장된) 사용자만 갱신
    if not pa.soundMigrated then
        if pa.soundType == "preset" and pa.soundKey == 567458 then
            pa.soundKey = 3049656
            pa.soundName = "아 결국 오실 줄 알았어요"
        end
        pa.soundMigrated = true
    end
    -- 기본값 OFF→ON 변경 1회 반영: 초기 배포(기본 OFF) 때 설치해 false 가 저장된 사용자를 ON 으로
    if not pa.enabledMigrated then
        pa.enabled = true
        pa.enabledMigrated = true
    end

    -- =================================================================
    -- 저렙 귓속말 차단: 계정 공용 (기준 레벨 미만 캐릭터의 귓속말 숨김)
    -- =================================================================
    if not MimDiceDB.whisperBlock then MimDiceDB.whisperBlock = {} end
    local wb = MimDiceDB.whisperBlock
    if wb.enabled == nil then wb.enabled = true end    -- 마스터 on/off (기본 ON)
    if wb.minLevel == nil then wb.minLevel = 60 end    -- 이 레벨 미만이면 숨김 (만렙 90 기준, 저렙 어뷰징 차단)
    -- 기본값 조정 1회 반영: 켜짐 ON + 레벨 10→60 (공개 전 테스트 데이터 정리)
    if not wb.lvlDefaultV2 then
        wb.enabled = true
        if wb.minLevel == 10 then wb.minLevel = 60 end
        wb.lvlDefaultV2 = true
    end
    -- 어떤 기록도 남기지 않는다: 이전 버전에서 저장된 차단 기록이 있으면 완전 삭제
    wb.log = nil

    -- =================================================================
    -- 스킨: 계정 공용 (플랫 다크 테마, 실시간 적용)
    -- =================================================================
    if not MimDiceDB.skin then MimDiceDB.skin = {} end
    local skn = MimDiceDB.skin
    if skn.enabled == nil then skn.enabled = false end                        -- 기본: 클래식(끄기)
    if skn.preset == nil then skn.preset = "darkgray" end
    if skn.base == nil then skn.base = { r = 0.11, g = 0.11, b = 0.12 } end   -- 제일 진한 배경색
    if skn.accentText == nil then skn.accentText = { r = 0.90, g = 0.90, b = 0.92 } end  -- 강조 글자
    if skn.accentHover == nil then skn.accentHover = { r = 0.42, g = 0.44, b = 0.50 } end -- 강조 배경
    if skn.alpha == nil then skn.alpha = 0.93 end                             -- 배경 투명도
    if not skn.alphaByPreset then skn.alphaByPreset = {} end                  -- 스킨별 투명도 (사용자 조절값 기억)
    if skn.accentTextA == nil then skn.accentTextA = 1 end                    -- 강조 글자 투명도
    if skn.accentHoverA == nil then skn.accentHoverA = 0.30 end               -- 활성 탭 배경 투명도
    if not skn.btnHover then skn.btnHover = { r = 0.42, g = 0.44, b = 0.50 } end -- 버튼 마우스오버/누름 색
    if skn.btnHoverA == nil then skn.btnHoverA = 0.30 end                      -- 버튼 마우스오버 투명도
    if not skn.btnText then skn.btnText = { r = 0.92, g = 0.92, b = 0.92 } end -- 버튼 안 글자색
    if skn.btnTextA == nil then skn.btnTextA = 1 end                           -- 버튼 안 글자 투명도
    if not skn.custom then                                                     -- '커스텀 (내 색)' 슬롯: 사용자가 만진 색 영구 저장
        skn.custom = {
            alpha = 0.93,
            base = { r = 0.11, g = 0.11, b = 0.12 },
            accentText = { r = 0.90, g = 0.90, b = 0.92 },
            accentHover = { r = 0.42, g = 0.44, b = 0.50 },
            btnHover = { r = 0.42, g = 0.44, b = 0.50 },
            btnText = { r = 0.92, g = 0.92, b = 0.92 },
        }
    end
    if skn.font == nil then skn.font = "default" end                         -- 선택 폰트 (리로드 시 적용)
    if not skn.customFonts then skn.customFonts = {} end                      -- 내 폰트 파일명 목록

    -- ── ID 타입 1회 마이그레이션 ──
    -- 예전엔 ID 값을 soundKey 에 저장했는데 내장(preset)과 같은 칸이라 서로 덮어쓰는 문제가 있었다.
    -- ID 전용 칸 soundID 로 분리하고, 기존 id-type 항목의 soundKey 값을 soundID 로 옮긴다.
    -- soundKey 는 이제 내장(preset) 숫자 ID 전용. 숫자가 아닌 문자열(예전 파일명 잔재: "왜죽었어.mp3" 등)이면
    -- 내장 미선택으로 간주하고 제거(표시명도 초기화). 그러면 ID/내장이 서로 깨끗하게 분리된다.
    -- 내장 ID(soundKey) · 직접 ID(soundID)는 모두 '숫자'여야 한다.
    -- 숫자가 아닌 문자열(예전 파일명 잔재)은 ID 로도 내장으로도 인정하지 않고 제거한다.
    local function SA_FixSoundFields(e)
        if not e then return end
        -- 1) soundKey 에 든 파일명 잔재 제거 (+표시명 초기화)
        if type(e.soundKey) == "string" and tonumber(e.soundKey) == nil then
            e.soundKey = nil
            e.soundName = nil
        end
        -- 2) soundID 에 잘못 들어간 파일명/문자열 잔재 제거 (이전 버전 마이그레이션 오류 복구)
        if type(e.soundID) == "string" and tonumber(e.soundID) == nil then
            e.soundID = nil
        end
        -- 3) 진짜 '숫자' ID 가 soundKey 에 저장돼 있던 옛 데이터만 soundID 로 이전
        if e.soundType == "id" and e.soundID == nil and type(e.soundKey) == "number" then
            e.soundID = e.soundKey
            e.soundKey = nil
        end
        -- 4) '내장'인데 선택된 내장음(soundKey)이 없으면 소리가 아예 안 나는 깨진 상태.
        --    커스텀 파일명이 남아 있으면 커스텀으로 복원 (구버전 잔재/미완성 선택 정리)
        if e.soundType == "preset" and e.soundKey == nil
           and type(e.soundFile) == "string" and e.soundFile ~= "" then
            e.soundType = "custom"
        end
    end
    SA_FixSoundFields(MimDiceDB.battleRes)
    SA_FixSoundFields(MimDiceDB.deathTrack)
    SA_FixSoundFields(MimDiceDB.partyAlert)
    SA_FixSoundFields(MimDiceDB.partyAlert.fullParty)
    if MimDiceDB.buffTrack then
        for _, bt in pairs(MimDiceDB.buffTrack) do SA_FixSoundFields(bt) end
    end
    if MimDiceDB.soundAlerts then
        for _, e in ipairs(MimDiceDB.soundAlerts) do SA_FixSoundFields(e) end
    end
end

-- 3가지 타입(preset, custom, id) 지원
-- channel: 재생 사운드 채널 (기본 "Dialog"). 전투 효과음(SFX) 폭주 시 동시재생 제한에 밀려
--          끊기는 현상을 막기 위해 모든 알림을 대화(Dialog) 채널로 통일한다. 미리듣기도 동일 채널.
local function SA_PlaySound(entry, channel)
    if not entry or not entry.enabled then return end
    channel = channel or "Dialog"

    if entry.soundType == "preset" and entry.soundKey then
        if type(entry.soundKey) == "number" and entry.soundKey > 500000 then
            pcall(PlaySoundFile, entry.soundKey, channel)
        else
            pcall(PlaySound, entry.soundKey, channel)
        end
    elseif entry.soundType == "custom" then
        if not entry.soundFile or entry.soundFile == "" then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[MimDice] 커스텀 사운드 파일이 설정되지 않았습니다.|r")
            return
        end
        local path = "Interface\\AddOns\\MimDice\\sounds\\" .. entry.soundFile
        local ok, handle = pcall(PlaySoundFile, path, channel)
        if not ok or not handle then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffff0000[MimDice] 사운드 파일을 재생할 수 없습니다: " .. entry.soundFile .. "|r  "
                .. "|cffffff00(sounds\\ 폴더에 파일이 있는지 확인하세요)|r"
            )
        end
    elseif entry.soundType == "id" and entry.soundID then
        -- 사용자가 직접 입력한 ID 재생 (내장 preset 의 soundKey 와 분리된 전용 칸)
        local numericID = tonumber(entry.soundID)
        if numericID then
            if numericID > 500000 then
                pcall(PlaySoundFile, numericID, channel)
            else
                pcall(PlaySound, numericID, channel)
            end
        end
    end
end

-- =====================================================================
-- 이벤트 감지 (스킬 & 점프 & 블러드 & 마력주입)
-- =====================================================================


-- =====================================================================
-- 죽음 추적 (UNIT_DIED 기반)
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
-- 역할(탱/힐) 구분 없이 단순 카운터로 처리
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

-- 색상 팔레트 (10열 × 4행 = 40): 체계적인 색상환 + 밝기 단계
--  열(가로 10) = 빨 주 노 초 청 파 남 보 분 + 무채색
--  행(세로 4) = 밝기 단계 (1행 연함 → 2행 중간 → 3행 진함 → 4행 어두움)
--  → 세로로 내려가면 같은 색의 명암 단계, 가로로 가면 빨주노초파남보 무지개
local SA_PALETTE_COLS = 10
local SA_COLOR_PRESETS = {
    -- 1행: 연함 (light)
    {1.00,0.60,0.60},{1.00,0.80,0.55},{1.00,0.95,0.60},{0.70,1.00,0.60},{0.65,1.00,0.95},
    {0.60,0.78,1.00},{0.72,0.72,1.00},{0.85,0.65,1.00},{1.00,0.75,0.88},{1.00,1.00,1.00},
    -- 2행: 중간 (medium)
    {1.00,0.20,0.20},{1.00,0.55,0.10},{1.00,0.85,0.10},{0.30,0.85,0.25},{0.15,0.85,0.80},
    {0.20,0.50,1.00},{0.40,0.40,0.95},{0.65,0.35,0.95},{1.00,0.40,0.70},{0.72,0.72,0.72},
    -- 3행: 진함 (deep)
    {0.78,0.12,0.12},{0.82,0.40,0.05},{0.82,0.65,0.05},{0.15,0.58,0.15},{0.05,0.58,0.55},
    {0.10,0.30,0.80},{0.25,0.20,0.72},{0.45,0.18,0.70},{0.82,0.15,0.50},{0.45,0.45,0.45},
    -- 4행: 어두움 (dark)
    {0.45,0.06,0.06},{0.50,0.25,0.03},{0.50,0.40,0.03},{0.08,0.32,0.08},{0.03,0.32,0.30},
    {0.05,0.15,0.45},{0.12,0.10,0.42},{0.26,0.10,0.42},{0.48,0.08,0.28},{0.12,0.12,0.12},
}

-- =====================================================================
-- 스킨 (플랫 다크 테마) - 실시간 적용/해제 (리로드 불필요)
-- 기준색(제일 진한 배경) 하나에서 창/테두리/탭/버튼 색을 비율로 자동 파생하고,
-- 강조 글자색(제목/선택 탭)과 강조 배경(호버/활성 탭)만 따로 고른다.
-- 원리: 무엇을 바꿨는지(플랫화한 버튼, 숨긴 원본 그림)를 전부 등록해 두고
--       색 변경 = 다시 칠하기 / 끄기 = 원본 복원을 즉시 수행.
-- =====================================================================
-- 프리셋: 색 3종 + 배경 투명도(alpha)로 서로 다른 분위기 (Details 스킨 라인업 참고)
-- 다크 그레이 + 와우 13직업 색 테마 (강조색 = 공식 직업색, 배경 = 그 색을 어둡게 깔아낸 색)
local SA_SKIN_PRESETS = {
    { key = "darkgray",    name = "다크 그레이",       alpha = 0.93, base = {0.11,0.11,0.12}, accentText = {0.90,0.90,0.92}, accentHover = {0.42,0.44,0.50} },
    { key = "minimalblack", name = "어둠의 블랙",      alpha = 0.78, base = {0.04,0.04,0.04}, accentText = {0.92,0.92,0.92}, accentHover = {0.32,0.32,0.32} },
    { key = "warrior",     name = "전사 브라운",       alpha = 0.93, base = {0.16,0.14,0.11}, accentText = {0.78,0.61,0.43}, accentHover = {0.43,0.34,0.24} },
    { key = "priest",      name = "사제 화이트",       alpha = 0.93, base = {0.19,0.19,0.19}, accentText = {1.00,1.00,1.00}, accentHover = {0.55,0.55,0.55} },
    { key = "rogue",       name = "도적 옐로우",       alpha = 0.93, base = {0.19,0.18,0.11}, accentText = {1.00,0.96,0.41}, accentHover = {0.55,0.53,0.22} },
    { key = "mage",        name = "마법사 스카이블루", alpha = 0.93, base = {0.08,0.16,0.18}, accentText = {0.25,0.78,0.92}, accentHover = {0.14,0.43,0.51} },
    { key = "monk",        name = "수도사 제이드",     alpha = 0.93, base = {0.05,0.19,0.13}, accentText = {0.00,1.00,0.60}, accentHover = {0.00,0.55,0.33} },
    { key = "warlock",     name = "흑마법사 퍼플",     alpha = 0.93, base = {0.12,0.13,0.18}, accentText = {0.53,0.53,0.93}, accentHover = {0.29,0.29,0.51} },
    { key = "hunter",      name = "사냥꾼 그린",       alpha = 0.93, base = {0.14,0.17,0.11}, accentText = {0.67,0.83,0.45}, accentHover = {0.37,0.46,0.25} },
    { key = "shaman",      name = "주술사 블루",       alpha = 0.93, base = {0.05,0.11,0.17}, accentText = {0.00,0.44,0.87}, accentHover = {0.00,0.24,0.48} },
    { key = "deathknight", name = "죽음의기사 레드",   alpha = 0.93, base = {0.16,0.07,0.08}, accentText = {0.77,0.12,0.23}, accentHover = {0.42,0.06,0.13} },
    { key = "paladin",     name = "성기사 핑크",       alpha = 0.93, base = {0.18,0.13,0.15}, accentText = {0.96,0.55,0.73}, accentHover = {0.53,0.30,0.40} },
    { key = "druid",       name = "드루이드 오렌지",   alpha = 0.93, base = {0.19,0.12,0.06}, accentText = {1.00,0.49,0.04}, accentHover = {0.55,0.27,0.02} },
    { key = "demonhunter", name = "악마사냥꾼 딥퍼플", alpha = 0.93, base = {0.14,0.08,0.16}, accentText = {0.64,0.19,0.79}, accentHover = {0.35,0.10,0.43} },
    { key = "evoker",      name = "기원사 에메랄드",   alpha = 0.93, base = {0.08,0.13,0.12}, accentText = {0.20,0.58,0.50}, accentHover = {0.11,0.32,0.28} },
}
local function SA_SkinPresetByKey(key)
    for _, p in ipairs(SA_SKIN_PRESETS) do if p.key == key then return p end end
    return SA_SKIN_PRESETS[1]
end

local function SA_SkinOn()
    return (MimDiceDB and MimDiceDB.skin and MimDiceDB.skin.enabled) and true or false
end

-- 현재 설정에서 파생 팔레트 계산
local function SA_SkinPal()
    local sk = (MimDiceDB and MimDiceDB.skin) or {}
    local b = sk.base or { r = 0.11, g = 0.11, b = 0.12 }
    local function shade(m, add)
        add = add or 0
        return math.min(1, b.r * m + add), math.min(1, b.g * m + add), math.min(1, b.b * m + add)
    end
    local at = sk.accentText or { r = 1, g = 0.45, b = 0.75 }
    local ah = sk.accentHover or { r = 0.35, g = 0.65, b = 1 }
    local bh = sk.btnHover or ah
    local bt = sk.btnText or { r = 0.92, g = 0.92, b = 0.92 }
    return {
        win    = { b.r, b.g, b.b, sk.alpha or 0.93 },   -- 창 배경 (기준색 + 투명도)
        border = { shade(0.45) },            -- 테두리: 배경보다 두 단계 어둡게
        tab    = { shade(1.6, 0.02) },       -- 탭(비활성)
        btn    = { shade(2.0, 0.05) },       -- 버튼 면
        field  = { shade(0.60) },            -- 입력칸/체크박스 안쪽 (배경보다 어둡게 = 파인 느낌)
        tint   = { shade(2.6, 0.12) },       -- 스크롤바/슬라이더 물들이기 색
        accent = { at.r, at.g, at.b, sk.accentTextA or 1 },      -- 강조 글자 (+투명도)
        hover  = { ah.r, ah.g, ah.b, sk.accentHoverA or 0.30 },     -- 활성 탭 배경 (강조, +투명도)
        btnHover = { bh.r, bh.g, bh.b, sk.btnHoverA or 0.30 },       -- 버튼 마우스오버/누름 (+투명도)
        btnText  = { bt.r, bt.g, bt.b, sk.btnTextA or 1 },           -- 버튼 안 글자색 (+투명도)
    }
end

-- 적용 대상 등록부 (실시간 재색/복구용)
local SA_SkinWins = {}         -- 스킨 대상 창들 (자체 BackdropTemplate 창)
local SA_SkinBtns = {}         -- 플랫화된 버튼들
local SA_SkinChecks = {}       -- 플랫화된 체크박스들
local SA_SkinEdits = {}        -- 플랫화된 입력칸들
local SA_SkinTints = {}        -- 물들인 스크롤바/슬라이더들
local SA_SkinScrollBars = {}   -- 현대식으로 바꾼 스크롤바들
local SA_SkinCloses = {}       -- 플랫화된 닫기(X) 버튼들
local SA_SkinMainState = nil   -- 메인창: 숨긴 원본 그림 목록 + 플랫 덮개

-- 각진 1픽셀 플랫 테두리 백드롭 (동글동글한 툴팁 테두리 대신)
local SA_SKIN_FLAT_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

-- 버튼 플랫화 / 재색 (최초 1회 원본 그림 조각을 전부 수집해 두고 숨김/복원)
-- 요즘 빨간 버튼은 그림이 NormalTexture가 아니라 Left/Center/Right 조각이라
-- 버튼의 텍스처 전부를 대상으로 한다.
local function SA_SkinButtonApply(btn, pal)
    local st = btn.MimDiceSkin
    if not st then
        st = { art = {} }
        btn.MimDiceSkin = st
        local fs = btn:GetFontString()
        if fs then st.fr, st.fg, st.fb = fs:GetTextColor() end
        for _, r in ipairs({ btn:GetRegions() }) do   -- 우리 텍스처를 만들기 전에 수집
            if r:IsObjectType("Texture") then table.insert(st.art, r) end
        end
        st.bd = btn:CreateTexture(nil, "BACKGROUND", nil, 0)   -- 1px 각진 테두리 역할
        st.bd:SetAllPoints()
        st.bg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)   -- 버튼 면
        st.bg:SetPoint("TOPLEFT", 1, -1); st.bg:SetPoint("BOTTOMRIGHT", -1, 1)
        st.hl = btn:CreateTexture(nil, "ARTWORK", nil, 1)     -- 마우스오버 표시 (글자보다 아래 = 불투명해도 글자 보임)
        st.hl:SetPoint("TOPLEFT", 1, -1); st.hl:SetPoint("BOTTOMRIGHT", -1, 1)
        st.hl:Hide()
        btn:HookScript("OnEnter", function() if st.hlOn then st.hl:Show() end end)
        btn:HookScript("OnLeave", function() st.hl:Hide() end)
        st.origPd = btn.GetPushedTexture and btn:GetPushedTexture() or nil   -- 원본 누름 그림 (복원용)
        st.pt = btn:CreateTexture(nil, "ARTWORK")              -- 누르는 동안 표시 (SetPushedTexture 로 관리)
        st.pt:SetPoint("TOPLEFT", 1, -1); st.pt:SetPoint("BOTTOMRIGHT", -1, 1)
        table.insert(SA_SkinBtns, btn)
    end
    pcall(function()
        for _, r in ipairs(st.art) do r:SetAlpha(0) end
        st.bd:SetColorTexture(pal.border[1], pal.border[2], pal.border[3], 1); st.bd:Show()
        st.bg:SetColorTexture(pal.btn[1], pal.btn[2], pal.btn[3], 1); st.bg:Show()
        st.hl:SetColorTexture(pal.btnHover[1], pal.btnHover[2], pal.btnHover[3], pal.btnHover[4] or 0.30); st.hlOn = true
        st.pt:SetColorTexture(pal.btnHover[1], pal.btnHover[2], pal.btnHover[3], math.min(1, (pal.btnHover[4] or 0.30) + 0.25))
        btn:SetPushedTexture(st.pt)
        local fs = btn:GetFontString()
        if fs then fs:SetTextColor(pal.btnText[1], pal.btnText[2], pal.btnText[3], pal.btnText[4] or 1) end
    end)
end

-- 버튼 원상복구 (스킨 끄기)
local function SA_SkinButtonRestore(btn)
    local st = btn.MimDiceSkin
    if not st then return end
    pcall(function()
        for _, r in ipairs(st.art) do r:SetAlpha(1) end
        st.bd:Hide(); st.bg:Hide(); st.hl:Hide(); st.hlOn = false
        if st.pt then
            if st.origPd then btn:SetPushedTexture(st.origPd)   -- 원본 누름 그림 객체 복귀
            else btn:SetPushedTexture("") end
            st.pt:Hide()
        end
        local fs = btn:GetFontString()
        if fs and st.fr then fs:SetTextColor(st.fr, st.fg, st.fb) end
    end)
end

-- 닫기(X) 버튼 플랫화: 빨간 원형 X 그림을 숨기고 각진 X 글자 버튼으로
local function SA_SkinCloseApply(btn, pal)
    local st = btn.MimDiceSkinClose
    if not st then
        st = { art = {} }
        btn.MimDiceSkinClose = st
        for _, r in ipairs({ btn:GetRegions() }) do
            if r:IsObjectType("Texture") then table.insert(st.art, r) end
        end
        st.bd = btn:CreateTexture(nil, "BACKGROUND", nil, 0)
        st.bd:SetPoint("TOPLEFT", 6, -6); st.bd:SetPoint("BOTTOMRIGHT", -6, 6)
        st.bg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
        st.bg:SetPoint("TOPLEFT", 7, -7); st.bg:SetPoint("BOTTOMRIGHT", -7, 7)
        st.hl = btn:CreateTexture(nil, "ARTWORK", nil, 1)     -- X 글자보다 아래
        st.hl:SetPoint("TOPLEFT", 7, -7); st.hl:SetPoint("BOTTOMRIGHT", -7, 7)
        st.hl:Hide()
        btn:HookScript("OnEnter", function() if st.hlOn then st.hl:Show() end end)
        btn:HookScript("OnLeave", function() st.hl:Hide() end)
        -- X 표시: 글자는 창마다 여백이 달라 어긋나 보여서, 선 2개로 직접 그린다 (항상 정중앙)
        st.x1 = btn:CreateLine(nil, "OVERLAY")
        st.x1:SetThickness(1.5)
        st.x1:SetStartPoint("CENTER", st.bg, -3.5, 3.5)
        st.x1:SetEndPoint("CENTER", st.bg, 3.5, -3.5)
        st.x2 = btn:CreateLine(nil, "OVERLAY")
        st.x2:SetThickness(1.5)
        st.x2:SetStartPoint("CENTER", st.bg, -3.5, -3.5)
        st.x2:SetEndPoint("CENTER", st.bg, 3.5, 3.5)
        table.insert(SA_SkinCloses, btn)
    end
    pcall(function()
        for _, r in ipairs(st.art) do r:SetAlpha(0) end
        st.bd:SetColorTexture(pal.border[1], pal.border[2], pal.border[3], 1); st.bd:Show()
        st.bg:SetColorTexture(pal.btn[1], pal.btn[2], pal.btn[3], 1); st.bg:Show()
        st.hl:SetColorTexture(pal.btnHover[1], pal.btnHover[2], pal.btnHover[3], pal.btnHover[4] or 0.30); st.hlOn = true
        st.x1:SetColorTexture(pal.btnText[1], pal.btnText[2], pal.btnText[3], pal.btnText[4] or 1); st.x1:Show()
        st.x2:SetColorTexture(pal.btnText[1], pal.btnText[2], pal.btnText[3], pal.btnText[4] or 1); st.x2:Show()
    end)
end
local function SA_SkinCloseRestore(btn)
    local st = btn.MimDiceSkinClose
    if not st then return end
    pcall(function()
        for _, r in ipairs(st.art) do r:SetAlpha(1) end
        st.bd:Hide(); st.bg:Hide(); st.hl:Hide(); st.x1:Hide(); st.x2:Hide(); st.hlOn = false
    end)
end

-- 체크박스 플랫화: 그림을 숨기고 각진 어두운 박스로.
-- 체크 표시는 우리가 만든 강조색 채움 텍스처로 교체하되,
-- "원본 체크 텍스처 객체"를 저장해 뒀다가 끌 때 그대로 되돌린다.
-- (하이(동전)/로우 등 자기만의 체크 그림을 가진 버튼도 안전하게 복원됨)
local function SA_SkinCheckApply(cb, pal)
    local st = cb.MimDiceSkin
    if not st then
        st = { art = {} }
        cb.MimDiceSkin = st
        st.origCk = cb.GetCheckedTexture and cb:GetCheckedTexture() or nil
        local disChecked = cb.GetDisabledCheckedTexture and cb:GetDisabledCheckedTexture()
        for _, r in ipairs({ cb:GetRegions() }) do
            if r:IsObjectType("Texture") and r ~= st.origCk and r ~= disChecked then
                table.insert(st.art, r)
            end
        end
        st.bd = cb:CreateTexture(nil, "BACKGROUND", nil, 0)
        st.bd:SetPoint("TOPLEFT", 4, -4); st.bd:SetPoint("BOTTOMRIGHT", -4, 4)
        st.bg = cb:CreateTexture(nil, "BACKGROUND", nil, 1)
        st.bg:SetPoint("TOPLEFT", 5, -5); st.bg:SetPoint("BOTTOMRIGHT", -5, 5)
        st.hl = cb:CreateTexture(nil, "ARTWORK", nil, -1)    -- 체크 표시보다 아래
        st.hl:SetPoint("TOPLEFT", 5, -5); st.hl:SetPoint("BOTTOMRIGHT", -5, 5)
        st.hl:Hide()
        cb:HookScript("OnEnter", function() if st.hlOn then st.hl:Show() end end)
        cb:HookScript("OnLeave", function() st.hl:Hide() end)
        st.ck = cb:CreateTexture(nil, "ARTWORK")   -- 강조색 채움 (체크 표시용)
        st.ck:SetPoint("TOPLEFT", 7, -7); st.ck:SetPoint("BOTTOMRIGHT", -7, 7)
        table.insert(SA_SkinChecks, cb)
    end
    for _, r in ipairs(st.art) do pcall(r.SetAlpha, r, 0) end
    pcall(function()
        st.bd:SetColorTexture(pal.border[1], pal.border[2], pal.border[3], 1); st.bd:Show()
        st.bg:SetColorTexture(pal.field[1], pal.field[2], pal.field[3], 1); st.bg:Show()
        st.hl:SetColorTexture(pal.btnHover[1], pal.btnHover[2], pal.btnHover[3], pal.btnHover[4] or 0.30); st.hlOn = true
        st.ck:SetColorTexture(pal.hover[1], pal.hover[2], pal.hover[3], 1)
        cb:SetCheckedTexture(st.ck)                    -- 체크 표시 = 강조색 채움
        st.ck:SetShown(cb:GetChecked() and true or false)
        if st.origCk then st.origCk:SetAlpha(0) end    -- 원본 체크 그림은 잠시 숨김
    end)
end
local function SA_SkinCheckRestore(cb)
    local st = cb.MimDiceSkin
    if not st then return end
    for _, r in ipairs(st.art) do pcall(r.SetAlpha, r, 1) end
    pcall(st.bd.Hide, st.bd)
    pcall(st.bg.Hide, st.bg)
    pcall(st.hl.Hide, st.hl)
    st.hlOn = false
    pcall(function()
        if st.origCk then
            cb:SetCheckedTexture(st.origCk)   -- 원본 체크 텍스처 객체를 그대로 복귀
            st.origCk:SetAlpha(1)
        end
        st.ck:Hide()
    end)
end

-- 입력칸 플랫화: 금테 홈 그림을 숨기고 각진 어두운 칸으로
local function SA_SkinEditApply(eb, pal)
    local st = eb.MimDiceSkin
    if not st then
        local art = {}
        for _, r in ipairs({ eb:GetRegions() }) do
            if r:IsObjectType("Texture") then table.insert(art, r) end
        end
        if #art == 0 then return end   -- 그림 없는 입력칸은 건드릴 것이 없음
        st = { art = art }
        eb.MimDiceSkin = st
        st.bd = eb:CreateTexture(nil, "BACKGROUND", nil, 0)
        st.bd:SetPoint("TOPLEFT", -5, 1); st.bd:SetPoint("BOTTOMRIGHT", 1, -1)
        st.bg = eb:CreateTexture(nil, "BACKGROUND", nil, 1)
        st.bg:SetPoint("TOPLEFT", st.bd, "TOPLEFT", 1, -1)
        st.bg:SetPoint("BOTTOMRIGHT", st.bd, "BOTTOMRIGHT", -1, 1)
        table.insert(SA_SkinEdits, eb)
    end
    pcall(function()
        for _, r in ipairs(st.art) do r:SetAlpha(0) end
        st.bd:SetColorTexture(pal.border[1], pal.border[2], pal.border[3], 1); st.bd:Show()
        st.bg:SetColorTexture(pal.field[1], pal.field[2], pal.field[3], 1); st.bg:Show()
    end)
end
local function SA_SkinEditRestore(eb)
    local st = eb.MimDiceSkin
    if not st then return end
    pcall(function()
        for _, r in ipairs(st.art) do r:SetAlpha(1) end
        st.bd:Hide(); st.bg:Hide()
    end)
end

-- 스크롤바/슬라이더 물들이기: 그림을 회색조로 만들고 팔레트색으로 착색 (복원 가능)
local function SA_SkinTintApply(obj, pal)
    if not obj then return end
    local st = obj.MimDiceSkinTint
    if not st then
        st = {}
        obj.MimDiceSkinTint = st
        local function collect(f, d)
            if d > 4 then return end
            for _, r in ipairs({ f:GetRegions() }) do
                if r:IsObjectType("Texture") then table.insert(st, r) end
            end
            if f.GetThumbTexture then
                local th = f:GetThumbTexture()
                if th then table.insert(st, th) end
            end
            for _, c in ipairs({ f:GetChildren() }) do collect(c, d + 1) end
        end
        collect(obj, 0)
        table.insert(SA_SkinTints, obj)
    end
    for _, r in ipairs(st) do
        pcall(function()
            r:SetDesaturated(true)
            r:SetVertexColor(pal.tint[1], pal.tint[2], pal.tint[3], 1)
        end)
    end
end
local function SA_SkinTintRestore(obj)
    local st = obj.MimDiceSkinTint
    if not st then return end
    for _, r in ipairs(st) do
        pcall(function()
            r:SetDesaturated(false)
            r:SetVertexColor(1, 1, 1, 1)
        end)
    end
end

-- 구형 스크롤바를 현대식으로: 위/아래 화살표 숨김 + 얇은 플랫 트랙/썸
local function SA_SkinScrollBarApply(sb, pal)
    local st = sb.MimDiceSkinSB
    if not st then
        st = {}
        sb.MimDiceSkinSB = st
        local name = sb:GetName()
        st.up = sb.ScrollUpButton or (name and _G[name .. "ScrollUpButton"])
        st.down = sb.ScrollDownButton or (name and _G[name .. "ScrollDownButton"])
        st.track = sb:CreateTexture(nil, "BACKGROUND")
        st.track:SetPoint("TOPLEFT", 5, 16)
        st.track:SetPoint("BOTTOMRIGHT", -5, -16)
        table.insert(SA_SkinScrollBars, sb)
    end
    pcall(function()
        if st.up then st.up:Hide() end
        if st.down then st.down:Hide() end
        st.track:SetColorTexture(pal.field[1], pal.field[2], pal.field[3], 0.8)
        st.track:Show()
        sb:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        local th = sb:GetThumbTexture()
        if th then
            th:SetVertexColor(pal.btn[1], pal.btn[2], pal.btn[3], 1)
            th:SetSize(6, 30)
        end
    end)
end
local function SA_SkinScrollBarRestore(sb)
    local st = sb.MimDiceSkinSB
    if not st then return end
    pcall(function()
        if st.up then st.up:Show() end
        if st.down then st.down:Show() end
        st.track:Hide()
        sb:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
        local th = sb:GetThumbTexture()
        if th then
            th:SetVertexColor(1, 1, 1, 1)
            th:SetSize(18, 24)
        end
    end)
end

-- 창 내부의 위젯(그림 버튼/체크박스/입력칸/스크롤/슬라이더)을 재귀로 찾아 테마 적용
-- (아이콘 버튼/닫기 X/자체 제작 플랫 버튼은 자동 제외)
local function SA_SkinWalk(frame, pal, depth)
    if depth > 6 then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        local ot = child:GetObjectType()
        if ot == "Button" then
            local name = child:GetName()
            local fs = child.GetFontString and child:GetFontString()
            local hasArt = (child.GetNormalTexture and child:GetNormalTexture())
                or child.Left or child.Center or child.Right   -- 요즘 빨간 버튼의 그림 조각
            if child.MimDiceIsClose or (name and name:find("CloseButton")) then
                SA_SkinCloseApply(child, pal)                  -- 닫기(X)는 전용 플랫화
            elseif fs and hasArt then
                SA_SkinButtonApply(child, pal)
            end
        elseif ot == "CheckButton" then
            SA_SkinCheckApply(child, pal)
        elseif ot == "EditBox" then
            SA_SkinEditApply(child, pal)
        elseif ot == "Slider" then
            SA_SkinTintApply(child, pal)
        elseif ot == "ScrollFrame" then
            local name = child:GetName()
            local sb = child.ScrollBar
                or (child.GetScrollBar and child:GetScrollBar())
                or (name and _G[name .. "ScrollBar"])
            if sb then
                if sb.SetThumbTexture then
                    SA_SkinScrollBarApply(sb, pal)   -- 구형: 화살표 숨기고 플랫 트랙/썸
                else
                    SA_SkinTintApply(sb, pal)        -- 신형: 팔레트색으로 착색
                end
            end
        end
        SA_SkinWalk(child, pal, depth + 1)
    end
end

-- 창 하나에 스킨 칠하기 (각진 1px 테두리로 교체) / 원래 모양·색으로 복구
local function SA_SkinWindowApply(win, pal)
    if win.SetBackdrop then
        if not win.MimDiceSkinFlat then
            win:SetBackdrop(SA_SKIN_FLAT_BACKDROP)   -- 각진 테두리로 교체 (색 초기화됨 → 아래서 다시 칠함)
            win.MimDiceSkinFlat = true
        end
        win:SetBackdropColor(pal.win[1], pal.win[2], pal.win[3], pal.win[4])
        win:SetBackdropBorderColor(pal.border[1], pal.border[2], pal.border[3], 1)
    end
    SA_SkinWalk(win, pal, 0)
end
local function SA_SkinWindowRestore(win)
    local orig = win.MimDiceSkinOrig
    if win.SetBackdrop and orig then
        if win.MimDiceSkinFlat then
            if orig.backdrop then win:SetBackdrop(orig.backdrop) end
            win.MimDiceSkinFlat = false
        end
        win:SetBackdropColor(orig.bg[1], orig.bg[2], orig.bg[3], orig.bg[4])
        win:SetBackdropBorderColor(orig.border[1], orig.border[2], orig.border[3], orig.border[4])
    end
end

-- 창 등록: 생성 시 1회 호출. 그 시점의 원래 모양/색을 기억해 뒀다가 끌 때 그대로 복원
local function SA_SkinRegisterWindow(win)
    if not win then return end
    if win.GetBackdropColor and not win.MimDiceSkinOrig then
        win.MimDiceSkinOrig = {
            backdrop = win.GetBackdrop and win:GetBackdrop() or nil,
            bg = { win:GetBackdropColor() },
            border = { win:GetBackdropBorderColor() },
        }
    end
    table.insert(SA_SkinWins, win)
    if SA_SkinOn() then SA_SkinWindowApply(win, SA_SkinPal()) end
end

-- 메인창(블리자드 아트 프레임): 원본 그림 숨기고 플랫 덮개 표시 / 복구
local function SA_SkinMainApply(pal)
    local mw = _G.MainWindow
    if not mw then return end
    local st = SA_SkinMainState
    if not st then
        st = { hidden = {} }
        SA_SkinMainState = st
        pcall(function()
            if mw.NineSlice then table.insert(st.hidden, mw.NineSlice) end
            for _, r in ipairs({ mw:GetRegions() }) do
                if r:IsObjectType("Texture") then
                    local rn = r:GetName()
                    -- 이름 없는 조각(템플릿 그림)과 "MainWindow..." 템플릿 배경만 숨김.
                    -- 직업 아이콘(C_icon..)/역할 아이콘(TankTexture..) 등 이름 있는 커스텀 텍스처는 유지
                    if not rn or rn:find("^MainWindow") then
                        table.insert(st.hidden, r)
                    end
                end
            end
        end)
        local bgf = CreateFrame("Frame", nil, mw, "BackdropTemplate")
        bgf:SetAllPoints()
        bgf:SetFrameLevel(mw:GetFrameLevel())   -- 자식 위젯들 아래에 깔림
        bgf:EnableMouse(false)
        bgf:SetBackdrop(SA_SKIN_FLAT_BACKDROP)  -- 각진 1px 테두리
        st.bgf = bgf
    end
    for _, obj in ipairs(st.hidden) do pcall(obj.SetAlpha, obj, 0) end
    st.bgf:SetBackdropColor(pal.win[1], pal.win[2], pal.win[3], math.min(1, pal.win[4] + 0.04))
    st.bgf:SetBackdropBorderColor(pal.border[1], pal.border[2], pal.border[3], 1)
    st.bgf:Show()
    SA_SkinWalk(mw, pal, 0)
end
local function SA_SkinMainRestore()
    local st = SA_SkinMainState
    if not st then return end
    for _, obj in ipairs(st.hidden) do pcall(obj.SetAlpha, obj, 1) end
    st.bgf:Hide()
end

-- 전체 즉시 재적용 (스킨 탭에서 뭔가 바꿀 때마다 호출 - 리로드 불필요)
-- 전역: 스킨 탭 UI와 로그인 초기화에서 사용
function SA_SkinRefresh()
    if SA_SkinOn() then
        local pal = SA_SkinPal()
        for _, w in ipairs(SA_SkinWins) do SA_SkinWindowApply(w, pal) end
        SA_SkinMainApply(pal)
    else
        for _, w in ipairs(SA_SkinWins) do SA_SkinWindowRestore(w) end
        for _, b in ipairs(SA_SkinBtns) do SA_SkinButtonRestore(b) end
        for _, x in ipairs(SA_SkinCloses) do SA_SkinCloseRestore(x) end
        for _, c in ipairs(SA_SkinChecks) do SA_SkinCheckRestore(c) end
        for _, e in ipairs(SA_SkinEdits) do SA_SkinEditRestore(e) end
        for _, t in ipairs(SA_SkinTints) do SA_SkinTintRestore(t) end
        for _, sb in ipairs(SA_SkinScrollBars) do SA_SkinScrollBarRestore(sb) end
        SA_SkinMainRestore()
    end
    if SA_SkinRefreshTabs then SA_SkinRefreshTabs() end   -- 탭 색/호버 갱신 (아래에서 정의)
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

    local f = CreateFrame("Frame", "MimDice_DeathFrame", UIParent, "BackdropTemplate")
    f:SetSize(500, 60)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    -- 클릭 통과: 전투 중엔 EnableMouse(보호 함수)를 못 꺼서, 편집 상태로 전투에 들어가면
    -- 마우스가 켜진 채 남을 수 있다. 죽음 메시지는 전투 중 표시되므로 클릭이 아래로
    -- 통과되게 해서 어떤 상태든 클릭을 막지 않게 한다. (파티 알림 프레임과 동일 패턴)
    if f.SetPropagateMouseClicks then f:SetPropagateMouseClicks(true) end
    -- 잠금 해제(편집 모드)일 때만 보이는 테두리 (평소엔 투명)
    f:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 18 })
    f:SetBackdropBorderColor(1, 0.85, 0, 0)

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
    -- 기본 폰트 필수: 로그인 시 미리 생성되므로, 표시 전에 SetText("")가 먼저 불리면
    -- "Font not set" 에러 (실제 표시 시 설정값으로 다시 SetFont)
    fs:SetFont(MimDiceFontPath(), 24, "THICKOUTLINE")
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
    -- 페이드 끝나면 프레임을 완전히 숨기고 마우스 비활성 → 빈 영역이 우클릭 가로채지 않도록
    ag:SetScript("OnFinished", function()
        f.text:SetText("")
        f.icon:Hide()
        f:SetAlpha(0)
        if not InCombatLockdown() then f:EnableMouse(false) end  -- 전투 중 보호 함수 차단 회피
        f:Hide()
    end)

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
    f.text:SetFont(MimDiceFontPath(), fs, "THICKOUTLINE")
    f.text:SetText(coloredText)
    f.text:SetAlpha((MimDiceDB and MimDiceDB.deathTrack and MimDiceDB.deathTrack.colorA) or 1)

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
        f:SetBackdropBorderColor(1, 0.85, 0, 0)   -- 테두리 숨김
        if not InCombatLockdown() then f:EnableMouse(false) end  -- 전투 중 보호 함수 차단 회피
        -- 잠금 상태에서 (버튼 미리보기 아닌) 위치잡기 미리보기가 떠 있으면 지움
        if not f.fadeAnim:IsPlaying() and f.previewing and not f.previewOn then
            f.text:SetText("")
            f.icon:Hide()
            f.previewing = false
            f:Hide()
        end
    else
        -- 잠금 해제(편집 모드): 강조 배경(노랑) + 강조 테두리로 이동 가능 표시
        f.bg:SetColorTexture(1, 0.85, 0, 0.35)
        f.bg:Show()
        f:SetBackdropBorderColor(1, 0.85, 0, 1)
        if not InCombatLockdown() then f:EnableMouse(true) end  -- 전투 중 보호 함수 차단 회피
        f.fadeAnim:Stop()
        f:SetAlpha(1)
        f.previewing = true
        -- 위치 조정용 미리보기 (현재 직업색/역할)
        local c = dt.color or { r = 1, g = 0.2, b = 0.2 }
        local suffixColored = "|cff" .. string.format("%02x%02x%02x", (c.r or 1)*255, (c.g or 0.2)*255, (c.b or 0.2)*255)
            .. (dt.suffix or " 사망 !!") .. "|r"
        SA_SetDeathContent(SA_PlayerRoleForPreview(), dt.fontSize or 24, SA_PlayerColoredName() .. suffixColored)
        f:Show()
    end
end

-- =====================================================================
-- 죽음 메시지 설정 팝업 (설정 버튼으로 열림)
-- =====================================================================
-- (SA_DeathConfig 는 위 죽음 프레임 근처에서 미리 선언됨)
local SA_BuffConfigs = {}   -- 버프별 설정창(블러드/마력주입). 상호 닫기용으로 미리 선언.
local SA_BuffBars = {}      -- 버프 바 프레임. 설정창 OnHide에서 참조하므로 미리 선언.

-- 전투부활 아이콘 관련(프레임/설정창/티커) — 다른 설정창의 상호 닫기에서 참조하므로 미리 선언
local SA_BattleResIcon = nil
local SA_BattleResIconConfig = nil
local SA_brIconTicker = nil

-- 죽음 미리보기를 현재 설정으로 그림 (토글 아님, 페이드 없이 계속 표시)
local function SA_RenderDeathPreview()
    local f = SA_EnsureDeathFrame()
    local dt = MimDiceDB and MimDiceDB.deathTrack
    if not dt then return end
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", dt.x or 0, dt.y or 130)
    local name = UnitName("player") or "밈주머니"
    local _, classFile = UnitClass("player")
    local coloredName
    if classFile then
        local c = C_ClassColor and C_ClassColor.GetClassColor(classFile)
        if c then coloredName = "|c" .. c:GenerateHexColor() .. name .. "|r" end
    end
    coloredName = coloredName or ("|cffffffff" .. name .. "|r")
    local col = dt.color or { r = 1, g = 0.2, b = 0.2 }
    local hex = string.format("%02x%02x%02x", (col.r or 1)*255, (col.g or 0.2)*255, (col.b or 0.2)*255)
    SA_SetDeathContent(SA_PlayerRoleForPreview(), dt.fontSize or 24,
        coloredName .. "|cff" .. hex .. (dt.suffix or " 사망 !!") .. "|r")
    f.fadeAnim:Stop()
    f:SetAlpha(1)
    f:Show()
end

-- 설정값 변경 시 미리보기 실시간 갱신
-- - 잠금 해제(위치잡기) 모드면 SA_UpdateDeathFrame이 미리보기 텍스트 갱신
-- - 미리보기 토글 ON이면 현재 설정으로 다시 그림
local function SA_RefreshPreviewIfVisible()
    local f = SA_DeathFrame
    if not f then return end
    local dt = MimDiceDB and MimDiceDB.deathTrack
    if not dt then return end

    if not dt.locked then
        SA_UpdateDeathFrame()
    elseif f.previewOn then
        SA_RenderDeathPreview()
    end
end

-- 공용: 라벨 + 슬라이더 + 직접입력 EditBox 한 세트 생성 (1단위 미세조정 + 타이핑)
-- getFn(): 현재값 반환 / setFn(v): 값 저장 / onChange(): 적용(미리보기 등)
local function SA_MakeNumberSlider(parent, sliderName, y, labelText, minV, maxV, getFn, setFn, onChange)
    -- 라벨 (범위 함께 표시: 예 "바 가로 크기 (100~1900)")
    local lbl = parent:CreateFontString(nil, "OVERLAY")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, y)
    lbl:SetFont(MimDiceFontPath(), 11, "OUTLINE")
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
    edit:SetFont(MimDiceFontPath(), 12, "")
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

    -- 값 적용 (포커스는 유지) — 탭/엔터 이동은 외부 체인에서 처리
    local function applyValue()
        local v = tonumber(edit:GetText())
        if v then
            if v < minV then v = minV elseif v > maxV then v = maxV end
            syncing = true
            s:SetValue(v)       -- OnValueChanged 가 setFn/onChange 처리
            syncing = false
            edit:SetText(tostring(v))
        end
    end
    edit.commit = applyValue
    edit:SetScript("OnEnterPressed", function() applyValue(); edit:ClearFocus() end)
    edit:SetScript("OnEscapePressed", function() edit:ClearFocus() end)
    edit:SetScript("OnEditFocusLost", applyValue)
    s.edit = edit   -- 외부 탭/엔터 체인 연결용

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

-- 입력칸들을 탭/엔터로 순환 연결 (마지막 → 첫번째로 wrap)
local function SA_ChainTabEnter(boxes)
    for i, e in ipairs(boxes) do
        local nextE = boxes[i + 1] or boxes[1]
        local function go()
            if e.commit then e.commit() end
            nextE:SetFocus()
            if nextE.HighlightText then nextE:HighlightText() end
        end
        e:SetScript("OnTabPressed", go)
        e:SetScript("OnEnterPressed", go)
    end
end

-- 위치 X/Y 직접 입력 행 (중앙 = 0,0 / +x 오른쪽, -x 왼쪽 / +y 위, -y 아래)
-- 음수 입력 허용해야 해서 SetNumeric 안 씀. refresh 함수 반환.
local function SA_AddPosRow(parent, y, getX, setX, getY, setY, onChange)
    local lbl = parent:CreateFontString(nil, "OVERLAY")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, y)
    lbl:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    lbl:SetTextColor(0.9, 0.9, 0.9)
    lbl:SetText("위치 (중앙 0,0)   X")

    local function mkBox(getF, setF)
        local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        e:SetSize(50, 20)
        e:SetAutoFocus(false)
        e:SetFont(MimDiceFontPath(), 11, "")
        e:SetMaxLetters(6)
        -- 값 저장(포커스는 유지) — 탭/엔터 이동은 아래에서 따로 처리
        e.commit = function()
            local v = tonumber(e:GetText())
            if v then setF(math.floor(v + 0.5)); if onChange then onChange() end end
            e:SetText(tostring(math.floor((getF() or 0) + 0.5)))
        end
        e:SetScript("OnEditFocusLost", e.commit)
        e:SetScript("OnEscapePressed", function() e:ClearFocus() end)
        return e
    end

    local ex = mkBox(getX, setX)
    ex:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
    local lblY = parent:CreateFontString(nil, "OVERLAY")
    lblY:SetPoint("LEFT", ex, "RIGHT", 12, 0)
    lblY:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    lblY:SetTextColor(0.9, 0.9, 0.9)
    lblY:SetText("Y")
    local ey = mkBox(getY, setY)
    ey:SetPoint("LEFT", lblY, "RIGHT", 8, 0)

    -- 탭/엔터 칸 이동은 외부 SA_ChainTabEnter에서 처리 (ex, ey 반환)
    local refresh = function()
        ex:SetText(tostring(math.floor((getX() or 0) + 0.5)))
        ey:SetText(tostring(math.floor((getY() or 0) + 0.5)))
    end
    return refresh, ex, ey
end

-- 재생 타입 3종 선택 버튼 (내장 / 커스텀 / ID) — 순환 토글 대신 셋을 나란히 보여주고
-- 선택된 것만 금색으로 강조(라디오처럼). onPick(t)=버튼 클릭 시 호출, refresh()=강조 갱신.
-- 첫 버튼 왼쪽 위치 = (x, y). 전체 폭 약 136px.
local function SA_MakeTypeSelector(parent, x, y, getType, onPick)
    local defs = { { t = "preset", label = "내장" }, { t = "custom", label = "커스텀" }, { t = "id", label = "ID" } }
    local btns = {}
    for i, d in ipairs(defs) do
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(44, 22)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i - 1) * 46, y)
        b:SetText(d.label)
        b:GetFontString():SetFont(MimDiceFontPath(), 10, "")
        b.stype = d.t
        b:SetScript("OnClick", function() onPick(d.t) end)
        btns[i] = b
    end
    local function refresh()
        local cur = getType()
        for _, b in ipairs(btns) do
            if b.stype == cur then
                b:LockHighlight()
                b:GetFontString():SetTextColor(1, 0.82, 0)        -- 금색 = 선택됨
            else
                b:UnlockHighlight()
                b:GetFontString():SetTextColor(0.55, 0.55, 0.55)  -- 회색 = 미선택
            end
        end
    end
    return refresh, btns
end

-- 입력칸 플레이스홀더(회색 안내문) 동작 연결. box.placeholder 를 참조해 포커스/빈값 시 표시.
-- "여기에 직접 타이핑" 을 직관적으로 알려주는 용도.
local function SA_WirePlaceholder(box)
    box:HookScript("OnEditFocusGained", function(self)
        if self:GetText() == (self.placeholder or "") then
            self:SetText(""); self:SetTextColor(1, 1, 1)
        end
    end)
    box:HookScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then
            self:SetText(self.placeholder or ""); self:SetTextColor(0.5, 0.5, 0.5)
        end
    end)
end
-- RefreshSoundRow 에서 호출: 현재 값이 있으면 흰색으로, 없으면 회색 플레이스홀더로 표시.
local function SA_SetBoxValue(box, value, placeholder)
    box.placeholder = placeholder
    if value ~= nil and value ~= "" then
        box:SetText(tostring(value)); box:SetTextColor(1, 1, 1)
    else
        box:SetText(placeholder); box:SetTextColor(0.5, 0.5, 0.5)
    end
end

-- 색상환 아래에 붙는 '투명도 % 숫자 입력' 상자 (투명도 있는 색상환에서만 표시)
local SA_AlphaBox
local function SA_AlphaBoxSync(a)   -- 슬라이더로 바꿀 때 숫자칸도 따라가게
    if SA_AlphaBox and SA_AlphaBox:IsShown() and not SA_AlphaBox.eb:HasFocus() then
        SA_AlphaBox.eb:SetText(tostring(math.floor((a or 1) * 100 + 0.5)))
    end
end
local function SA_ShowAlphaBox(getFn, setFn)
    if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
    if not SA_AlphaBox then
        local f = CreateFrame("Frame", nil, ColorPickerFrame)
        f:SetSize(60, 38)
        -- 색 코드(#RRGGBB) 칸 바로 위에 배치. 구조가 다른 구버전이면 창 아래로.
        local hex = ColorPickerFrame.Content and ColorPickerFrame.Content.HexBox
        if hex then
            f:SetPoint("BOTTOMRIGHT", hex, "TOPRIGHT", 0, 4)
        else
            f:SetPoint("TOPRIGHT", ColorPickerFrame, "BOTTOMRIGHT", -10, 2)
        end
        f:SetFrameLevel(ColorPickerFrame:GetFrameLevel() + 10)
        local lb = f:CreateFontString(nil, "OVERLAY")
        lb:SetPoint("TOP", f, "TOP", 0, 0)
        lb:SetFont(MimDiceFontPath(), 11, "OUTLINE")
        lb:SetText("투명도")
        lb:SetTextColor(0.9, 0.9, 0.9)
        local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        eb:SetSize(40, 18)
        eb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 0)
        eb:SetAutoFocus(false)
        eb:SetNumeric(true)
        eb:SetMaxLetters(3)
        eb:SetFont(MimDiceFontPath(), 11, "")
        local pct = f:CreateFontString(nil, "OVERLAY")
        pct:SetPoint("LEFT", eb, "RIGHT", 4, 0)
        pct:SetFont(MimDiceFontPath(), 11, "OUTLINE")
        pct:SetText("%")
        pct:SetTextColor(0.9, 0.9, 0.9)
        f.eb = eb
        eb:SetScript("OnEnterPressed", function(self)
            local v = tonumber(self:GetText())
            if v and f.setFn then
                v = math.max(0, math.min(100, v))
                f.setFn(v / 100)
                self:SetText(tostring(v))
            end
            self:ClearFocus()
        end)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        SA_AlphaBox = f
    end
    SA_AlphaBox.setFn = setFn
    SA_AlphaBox.eb:SetText(tostring(math.floor(((getFn and getFn()) or 1) * 100 + 0.5)))
    SA_AlphaBox.eb:SetCursorPosition(0)
    SA_AlphaBox:Show()
end
local function SA_HideAlphaBox()
    if SA_AlphaBox then SA_AlphaBox:Hide() end
end

-- 와우 내장 색상환의 '# 코드' 칸을 폴링해서 6자리 색코드가 들어오면 applyFn(r,g,b)로 즉시 적용.
-- (이 칸이 붙여넣기 때 OnTextChanged를 안 쏘는 클라 대비 — 이벤트에 의존하지 않는 폴링 방식)
-- 색상환을 SetupColorPickerAndShow로 연 직후에 호출한다.
local function SA_WatchColorPickerHex(applyFn)
    local cp = ColorPickerFrame
    if not cp then return end
    local hb = (cp.Content and cp.Content.HexBox) or cp.hexBox or _G["ColorPickerFrameHexBox"]
    if not hb then   -- 못 찾으면 자식 EditBox 탐색
        for _, parent in ipairs({ cp, cp.Content, cp.Footer }) do
            if parent and parent.GetChildren then
                for _, ch in ipairs({ parent:GetChildren() }) do
                    if ch.GetObjectType and ch:GetObjectType() == "EditBox" then hb = ch; break end
                end
            end
            if hb then break end
        end
    end
    if cp.mimPoller then cp.mimPoller:Cancel(); cp.mimPoller = nil end
    if not hb then return end
    local lastHex
    cp.mimPoller = C_Timer.NewTicker(0.12, function(t)
        if not cp:IsShown() then t:Cancel(); cp.mimPoller = nil; return end
        local raw = (hb:GetText() or ""):gsub("#", ""):gsub("%s", "")
        if raw:match("^%x%x%x%x%x%x$") and raw ~= lastHex then
            lastHex = raw
            local r = tonumber(raw:sub(1, 2), 16) / 255
            local g = tonumber(raw:sub(3, 4), 16) / 255
            local b = tonumber(raw:sub(5, 6), 16) / 255
            applyFn(r, g, b)                    -- 설정에 직접 적용
            pcall(cp.SetColorRGB, cp, r, g, b)  -- 색상환(휠) 시각도 갱신
        end
    end)
end

-- 공용: 색상 한 줄 [라벨] [스와치=색상환 열기] [RRGGBB 코드 입력] [기본색]
-- 색상환은 와우 내장 풀 컬러 팔레트. 드래그하는 동안 실시간으로 미리보기 반영.
-- getFn() → {r,g,b} / setFn(r,g,b) / defaults = {r,g,b} 기본색 / onChange() 미리보기 갱신
-- opacityOpt = { get=fn(0~1), set=fn(a) } : 색상환의 투명도 슬라이더와 연동 (블러드 바 투명도 등)
-- 반환: refresh() - 스와치/코드칸을 현재 값으로 갱신
local function SA_MakeColorRow(win, y, labelText, getFn, setFn, defaults, onChange, opacityOpt)
    local lb = win:CreateFontString(nil, "OVERLAY")
    lb:SetPoint("TOPLEFT", win, "TOPLEFT", 15, y)
    lb:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    lb:SetText(labelText); lb:SetTextColor(0.9, 0.9, 0.9)

    local btn = CreateFrame("Button", nil, win)
    btn:SetSize(30, 18)
    btn:SetPoint("LEFT", lb, "RIGHT", 10, 0)
    local bd = btn:CreateTexture(nil, "BORDER")
    bd:SetAllPoints(); bd:SetColorTexture(0.6, 0.6, 0.6, 1)
    local sw = btn:CreateTexture(nil, "ARTWORK")
    sw:SetPoint("TOPLEFT", 1, -1); sw:SetPoint("BOTTOMRIGHT", -1, 1)
    local hlt = btn:CreateTexture(nil, "HIGHLIGHT")
    hlt:SetPoint("TOPLEFT", -2, 2); hlt:SetPoint("BOTTOMRIGHT", 2, -2)
    hlt:SetColorTexture(1, 1, 1, 0.3)

    local hexBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    hexBox:SetSize(66, 20)
    hexBox:SetPoint("LEFT", btn, "RIGHT", 12, 0)
    hexBox:SetAutoFocus(false); hexBox:SetFont(MimDiceFontPath(), 11, "")
    hexBox:SetMaxLetters(7)   -- '#' 포함 입력 허용

    local defBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    defBtn:SetSize(52, 20)
    defBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -15, y + 4)
    defBtn:SetText("기본색")
    defBtn:GetFontString():SetFont(MimDiceFontPath(), 10, "")

    local function refresh()
        local c = getFn() or { r = 1, g = 1, b = 1 }
        sw:SetColorTexture(c.r or 1, c.g or 1, c.b or 1, 1)
        hexBox.setting = true   -- 아래 SetText가 OnTextChanged를 되먹임하지 않도록 표시
        hexBox:SetText(string.format("%02X%02X%02X",
            math.floor((c.r or 1) * 255 + 0.5),
            math.floor((c.g or 1) * 255 + 0.5),
            math.floor((c.b or 1) * 255 + 0.5)))
        hexBox:SetCursorPosition(0)
        hexBox.setting = false
    end
    local function applyColor(r, g, b)
        setFn(r, g, b)
        refresh()
        if onChange then onChange() end
    end

    btn:SetScript("OnClick", function()
        local c = getFn() or { r = 1, g = 1, b = 1 }
        if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = c.r, g = c.g, b = c.b,
                hasOpacity = opacityOpt ~= nil,
                opacity = opacityOpt and opacityOpt.get() or nil,
                swatchFunc = function()
                    local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                    applyColor(nr, ng, nb)
                end,
                opacityFunc = opacityOpt and function()
                    local a = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or 1
                    opacityOpt.set(a)
                    SA_AlphaBoxSync(a)
                    if onChange then onChange() end
                end or nil,
                cancelFunc = function(prev)
                    if prev then
                        applyColor(prev.r, prev.g, prev.b)
                        if opacityOpt and prev.a then
                            opacityOpt.set(prev.a)
                            if onChange then onChange() end
                        end
                    end
                end,
            })
            -- 색상환의 '# 코드' 칸 붙여넣기 즉시 적용 (엔터 불필요)
            SA_WatchColorPickerHex(function(r, g, b) applyColor(r, g, b) end)
            if opacityOpt then
                SA_ShowAlphaBox(opacityOpt.get, function(a)
                    opacityOpt.set(a)
                    if onChange then onChange() end
                end)
            else
                SA_HideAlphaBox()
            end
        end
    end)

    -- 붙여넣기/타이핑으로 6자리 색코드가 완성되면 엔터 없이도 즉시 적용
    -- (텍스트/커서는 건드리지 않아 입력 흐름을 방해하지 않음)
    hexBox:SetScript("OnTextChanged", function(self)
        if self.setting then return end   -- refresh()가 넣은 값만 무시 (붙여넣기는 userInput=false여도 잡음)
        local t = self:GetText():gsub("#", ""):gsub("%s", "")
        if t:match("^%x%x%x%x%x%x$") then
            local r = tonumber(t:sub(1, 2), 16) / 255
            local g = tonumber(t:sub(3, 4), 16) / 255
            local b = tonumber(t:sub(5, 6), 16) / 255
            setFn(r, g, b)
            sw:SetColorTexture(r, g, b, 1)
            if onChange then onChange() end
        end
    end)

    hexBox:SetScript("OnEnterPressed", function(self)
        local t = self:GetText():gsub("#", ""):gsub("%s", "")
        if t:match("^%x%x%x%x%x%x$") then
            applyColor(tonumber(t:sub(1, 2), 16) / 255,
                       tonumber(t:sub(3, 4), 16) / 255,
                       tonumber(t:sub(5, 6), 16) / 255)
        else
            refresh()   -- 잘못된 입력은 원래 값으로 되돌림
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[MimDice]|r 색상 코드는 6자리로 입력하세요. (예: FF66AA)")
        end
        self:ClearFocus()
    end)
    hexBox:SetScript("OnEscapePressed", function(self) refresh(); self:ClearFocus() end)

    defBtn:SetScript("OnClick", function()
        applyColor(defaults[1], defaults[2], defaults[3])
    end)

    refresh()
    return refresh
end

-- 공용: 이 프레임을 잡고 끌면 본체(MainWindow)가 "점프 없이" 따라오게 연결
-- (StartMoving을 원격 프레임에서 호출하면 본체가 마우스 위치로 끌려오는 문제가 있어
--  커서 이동량만큼만 본체를 옮기는 수동 방식 사용)
local function SA_WireBundleDrag(frame)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        local mw = _G.MainWindow
        if not mw or not mw:IsMovable() then return end
        local scale = mw:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        self.MimDragX = mw:GetLeft() - cx / scale
        self.MimDragY = mw:GetTop() - cy / scale
        self:SetScript("OnUpdate", function(s2)
            local mw2 = _G.MainWindow
            if not mw2 then return end
            local sc = mw2:GetEffectiveScale()
            local x, y = GetCursorPosition()
            mw2:ClearAllPoints()
            mw2:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", s2.MimDragX + x / sc, s2.MimDragY + y / sc)
        end)
    end)
    frame:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        if MimDice_SaveAnchors then MimDice_SaveAnchors() end
    end)
end

local SA_deathTestUntil = 0   -- 죽음 테스트 중복 방지: 이 시각(GetTime)까지 재실행 억제

local function SA_CreateDeathConfig()
    if SA_DeathConfig then return SA_DeathConfig end

    local win = CreateFrame("Frame", "MimDice_DeathConfig", UIParent, "BackdropTemplate")
    win:SetSize(340, 350)
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
    -- (화면 클램프 없음: 메인창처럼 화면 밖으로도 이동 가능 — 번들로 함께 이동)
    -- 설정창을 잡고 끌면 본체(MainWindow)가 점프 없이 한 덩어리로 이동
    SA_WireBundleDrag(win)

    -- 설정창을 닫으면(X/ESC/연쇄) 미리보기 숨김 + 위치 자동 잠금
    win:SetScript("OnHide", function()
        local f = SA_DeathFrame
        if f and f.previewOn then SA_DeathPreviewOff() end
        local dt = MimDiceDB and MimDiceDB.deathTrack
        if dt and not dt.locked then
            dt.locked = true
            SA_UpdateDeathFrame()   -- 편집 표시 정리 (실제 페이드 중 메시지는 유지)
        end
    end)

    local title = win:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", win, "TOP", 0, -12)
    title:SetFont(MimDiceFontPath(), 13, "OUTLINE")
    title:SetText("죽음 알림 설정 (공용)")
    title:SetTextColor(1, 0.82, 0)

    local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    closeBtn.MimDiceIsClose = true   -- 스킨: 닫기(X) 플랫화 대상
    closeBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() win:Hide() end)

    -- ── 재생 사운드 ─────────────────────────
    local soundLabel = win:CreateFontString(nil, "OVERLAY")
    soundLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -36)
    soundLabel:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    soundLabel:SetText("재생 사운드 : 아래 3개 중 하나 선택")
    soundLabel:SetTextColor(0.9, 0.9, 0.9)

    -- 3종 타입 선택 버튼 (내장 / 커스텀 / ID)
    win.typeRefresh = SA_MakeTypeSelector(win, 15, -56,
        function() return MimDiceDB.deathTrack.soundType end,
        function(t) MimDiceDB.deathTrack.soundType = t; win.RefreshSoundRow() end)

    -- 커스텀/ID 입력칸 (직접 타이핑) — 플레이스홀더로 안내
    local soundBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    soundBox:SetSize(135, 22)
    soundBox:SetPoint("TOPLEFT", win, "TOPLEFT", 157, -56)
    soundBox:SetAutoFocus(false)
    soundBox:SetFont(MimDiceFontPath(), 11, "")
    win.soundBox = soundBox
    SA_WirePlaceholder(soundBox)

    -- 내장 선택 시: 사운드 선택 팝업 버튼 (soundBox 자리, 토글로 교체 표시)
    local soundSelectBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    soundSelectBtn:SetSize(135, 22)
    soundSelectBtn:SetPoint("TOPLEFT", win, "TOPLEFT", 157, -56)
    do
        local fs = soundSelectBtn:GetFontString()
        fs:SetFont(MimDiceFontPath(), 10, "")
        fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        fs:ClearAllPoints(); fs:SetPoint("LEFT", 6, 0); fs:SetPoint("RIGHT", -6, 0)
    end
    win.soundSelectBtn = soundSelectBtn
    soundSelectBtn:SetScript("OnClick", function()
        SA_OpenSoundPicker(soundSelectBtn,
            function() return MimDiceDB.deathTrack.soundKey end,
            function(snd)
                local dt = MimDiceDB.deathTrack
                dt.soundType = "preset"; dt.soundKey = snd.id; dt.soundName = snd.name
                win.RefreshSoundRow()
                local was = dt.enabled; dt.enabled = true
                SA_PlaySound(dt); dt.enabled = was
            end)
    end)

    local soundTestBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    soundTestBtn:SetSize(24, 22)
    soundTestBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -15, -56)
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
        win.typeRefresh()
        if dt.soundType == "preset" then
            soundLabel:SetText("내장: 아래에서 사운드 선택 (▶ 미리듣기)")
            soundSelectBtn:Show(); soundBox:Hide()
            soundSelectBtn:SetText(dt.soundName or "사운드 선택...")
        elseif dt.soundType == "id" then
            soundLabel:SetText("ID: 사운드 숫자 ID를 직접 입력")
            soundSelectBtn:Hide(); soundBox:Show()
            SA_SetBoxValue(soundBox, dt.soundID, "예: 567439")
        else
            soundLabel:SetText("커스텀: sounds폴더 파일명 그대로 입력 (대소문자·확장자 구분)")
            soundSelectBtn:Hide(); soundBox:Show()
            SA_SetBoxValue(soundBox, dt.soundFile, "예: MySound.mp3")
        end
    end

    soundBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local dt = MimDiceDB.deathTrack
        if dt.soundType == "id" then
            dt.soundID = tonumber(self:GetText()) or self:GetText()
        else
            dt.soundFile = self:GetText()   -- soundName 은 내장(preset) 표시 전용이라 안 건드림
        end
    end)
    soundBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- ── 화면 메시지 표시 on/off ─────────────
    local enableCb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    enableCb:SetSize(22, 22)
    enableCb:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -86)
    local enableLabel = win:CreateFontString(nil, "OVERLAY")
    enableLabel:SetPoint("LEFT", enableCb, "RIGHT", 2, 0)
    enableLabel:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    enableLabel:SetText("화면에 죽음 메시지 표시")
    enableLabel:SetTextColor(0.9, 0.9, 0.9)
    enableCb:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        MimDiceDB.deathTrack.showMessage = on
        -- 체크는 순수 ON/OFF만 (미리보기 없음). 화면 확인은 위치잠금 해제 또는 테스트 버튼으로.
        if not on then
            SA_DeathPreviewOff()   -- 끄면 혹시 떠 있던 미리보기 즉시 숨김
        end
    end)
    win.enableCb = enableCb

    -- ── 상세 설정 접기/펼치기 (기본: 접힘 = 소리 + 표시 ON/OFF만 보임) ──
    local advBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    advBtn:SetSize(310, 22)
    advBtn:SetPoint("TOP", win, "TOP", 0, -114)
    advBtn:GetFontString():SetFont(MimDiceFontPath(), 10, "")
    local adv = CreateFrame("Frame", nil, win)   -- 상세 위젯 컨테이너 (버튼 높이만큼 아래로)
    adv:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -28)
    adv:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)

    -- 문구 입력
    local suffixLabel = adv:CreateFontString(nil, "OVERLAY")
    suffixLabel:SetPoint("TOPLEFT", adv, "TOPLEFT", 15, -114)
    suffixLabel:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    suffixLabel:SetText("닉네임 뒤 문구 (예: 사망 !!)")
    suffixLabel:SetTextColor(0.9, 0.9, 0.9)

    local suffixBox = CreateFrame("EditBox", nil, adv, "InputBoxTemplate")
    suffixBox:SetSize(200, 22)
    suffixBox:SetPoint("TOPLEFT", adv, "TOPLEFT", 20, -134)
    suffixBox:SetAutoFocus(false)
    suffixBox:SetFont(MimDiceFontPath(), 12, "")
    suffixBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            MimDiceDB.deathTrack.suffix = self:GetText()
            SA_RefreshPreviewIfVisible()
        end
    end)
    suffixBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    win.suffixBox = suffixBox

    -- 글씨 크기 (슬라이더 + 직접 입력)
    local sizeSlider = SA_MakeNumberSlider(adv, "MimDice_DeathSizeSlider", -166, "글씨 크기", 12, 120,
        function() return MimDiceDB.deathTrack.fontSize end,
        function(v) MimDiceDB.deathTrack.fontSize = v end,
        function() SA_RefreshPreviewIfVisible() end)
    win.sizeSlider = sizeSlider

    -- 문구 색상 (색상환 풀 팔레트 + 코드 입력 + 기본색)
    win.colorRefresh = SA_MakeColorRow(adv, -222, "문구 색상",
        function() return MimDiceDB.deathTrack.color end,
        function(r, g, b) MimDiceDB.deathTrack.color = { r = r, g = g, b = b } end,
        { 1, 0.2, 0.2 },
        function() SA_RefreshPreviewIfVisible() end,
        {
            get = function() return MimDiceDB.deathTrack.colorA or 1 end,
            set = function(a) MimDiceDB.deathTrack.colorA = a end,
        })

    -- 위치 X/Y 직접 입력
    local posRefresh, posX, posY = SA_AddPosRow(adv, -258,
        function() return MimDiceDB.deathTrack.x end,
        function(v) MimDiceDB.deathTrack.x = v end,
        function() return MimDiceDB.deathTrack.y end,
        function(v) MimDiceDB.deathTrack.y = v end,
        function() SA_RefreshPreviewIfVisible() end)
    win.posRefresh = posRefresh

    -- 입력칸 탭/엔터 순환: 글씨 크기 → X → Y → (글씨 크기)
    SA_ChainTabEnter({ win.sizeSlider.edit, posX, posY })

    -- 위치 잠금/해제 토글
    local lockBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    lockBtn:SetSize(110, 24)
    lockBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 15, 14)
    lockBtn:GetFontString():SetFont(MimDiceFontPath(), 10, "")
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
            lockBtn:SetText("위치 잠금")
        end
    end

    -- 기본값으로 초기화 (글씨 80, 중앙, 마력주입 바 아래)
    local resetBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    resetBtn:SetSize(70, 24)
    resetBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 155, 14)   -- 340폭 기준 3버튼(110/70/70) 균등 간격 30px
    resetBtn:SetText("기본값")
    resetBtn:GetFontString():SetFont(MimDiceFontPath(), 11, "")
    resetBtn:SetScript("OnClick", function()
        local dt = MimDiceDB.deathTrack
        dt.fontSize, dt.x, dt.y = 80, 0, 130
        dt.color = { r = 1, g = 0.2, b = 0.2 }
        dt.colorA = 1
        dt.locked, dt.showMessage = true, true
        SA_UpdateDeathFrame()
        SA_RefreshDeathConfig()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MimDice]|r 죽음 메시지 설정 초기화됨")
    end)

    -- 테스트: 실제처럼 메시지(페이드로 사라짐) + 사운드 확인 (마스터 off여도 재생)
    local testBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    testBtn:SetSize(70, 24)
    testBtn:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -15, 14)
    testBtn:SetText("테스트")
    testBtn:GetFontString():SetFont(MimDiceFontPath(), 11, "")
    testBtn:SetScript("OnClick", function()
        local dt = MimDiceDB.deathTrack
        -- 테스트 중복 방지: 표시 유지시간 동안 재클릭 무시 (소리 겹침 방지)
        local now = GetTime()
        if now < SA_deathTestUntil then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cffffff00[MimDice]|r 테스트 재생 중입니다 (%.0f초 남음)", SA_deathTestUntil - now))
            return
        end
        SA_deathTestUntil = now + (dt.duration or 3)
        local hadPreview = SA_DeathFrame and SA_DeathFrame.previewOn  -- 상시 미리보기('표시' 체크) 중이면 유지
        SA_RenderDeathPreview()                    -- 본인 이름/직업색으로 즉시 표시
        if not hadPreview then
            local f = SA_DeathFrame
            if f then
                f.fade:SetStartDelay(dt.duration or 3) -- 실제 메시지와 동일한 유지시간 후 페이드
                f.fadeAnim:Play()
            end
        end
        local was = dt.enabled; dt.enabled = true  -- 테스트는 마스터 off여도 강제 재생
        SA_PlaySound(dt); dt.enabled = was
    end)

    -- 상세 설정 접기/펼치기 적용 (접으면 창도 짧아짐)
    local function ApplyAdv()
        local open = MimDiceDB.deathTrack.advOpen and true or false
        adv:SetShown(open)
        win:SetHeight(open and 378 or 190)
        advBtn:SetText(open and "상세 설정 접기" or "상세 설정 열기 : 문구/크기/색/위치")
    end
    win.ApplyAdv = ApplyAdv
    advBtn:SetScript("OnClick", function()
        MimDiceDB.deathTrack.advOpen = not MimDiceDB.deathTrack.advOpen
        ApplyAdv()
    end)
    ApplyAdv()

    SA_SkinRegisterWindow(win)   -- 스킨 대상 등록 (켜져 있으면 즉시 적용)
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
    win.colorRefresh()   -- 색상 스와치/코드칸 갱신
end

function SA_ToggleDeathConfig()
    local win = SA_CreateDeathConfig()
    if win:IsShown() then
        win:Hide()
    else
        for _, w in pairs(SA_BuffConfigs) do if w:IsShown() then w:Hide() end end  -- 겹침 방지
        if SA_BattleResIconConfig and SA_BattleResIconConfig:IsShown() then SA_BattleResIconConfig:Hide() end
        if _G.MimDice_PartyConfig and _G.MimDice_PartyConfig:IsShown() then _G.MimDice_PartyConfig:Hide() end
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
    win:SetSize(340, 416)
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
    -- (화면 클램프 없음: 메인창처럼 화면 밖으로도 이동 가능 — 번들로 함께 이동)
    -- 설정창을 잡고 끌면 본체(MainWindow)가 점프 없이 한 덩어리로 이동
    SA_WireBundleDrag(win)
    win.key = key

    -- 설정창을 닫으면(X/ESC/연쇄) 미리보기 숨김 + 위치 자동 잠금 (실제 발동 카운트다운은 유지)
    win:SetScript("OnHide", function()
        local f = SA_BuffBars[key]
        if f and f.previewOn then f.previewOn = false end
        local bt = MimDiceDB and MimDiceDB.buffTrack and MimDiceDB.buffTrack[key]
        if bt and not bt.locked then bt.locked = true end
        SA_UpdateBuffBar(key)   -- 정책 복귀: 실제 발동 중이면 그대로, 아니면 숨김
    end)

    local title = win:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", win, "TOP", 0, -12)
    title:SetFont(MimDiceFontPath(), 13, "OUTLINE")
    title:SetText(def.name .. " 지속바 설정 (공용)")
    title:SetTextColor(1, 0.82, 0)

    local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    closeBtn.MimDiceIsClose = true   -- 스킨: 닫기(X) 플랫화 대상
    closeBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() win:Hide() end)

    -- 재생 사운드
    local soundLabel = win:CreateFontString(nil, "OVERLAY")
    soundLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -36)
    soundLabel:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    soundLabel:SetText("재생 사운드 : 아래 3개 중 하나 선택")
    soundLabel:SetTextColor(0.9, 0.9, 0.9)

    -- 3종 타입 선택 버튼 (내장 / 커스텀 / ID)
    win.typeRefresh = SA_MakeTypeSelector(win, 15, -56,
        function() return MimDiceDB.buffTrack[key].soundType end,
        function(t) MimDiceDB.buffTrack[key].soundType = t; win.RefreshSoundRow() end)

    -- 커스텀/ID 입력칸 (직접 타이핑)
    local soundBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    soundBox:SetSize(135, 22)
    soundBox:SetPoint("TOPLEFT", win, "TOPLEFT", 157, -56)
    soundBox:SetAutoFocus(false)
    soundBox:SetFont(MimDiceFontPath(), 11, "")
    win.soundBox = soundBox
    SA_WirePlaceholder(soundBox)

    -- 내장 선택 시: 사운드 선택 팝업 버튼 (soundBox 자리, 토글로 교체 표시)
    local soundSelectBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    soundSelectBtn:SetSize(135, 22)
    soundSelectBtn:SetPoint("TOPLEFT", win, "TOPLEFT", 157, -56)
    do
        local fs = soundSelectBtn:GetFontString()
        fs:SetFont(MimDiceFontPath(), 10, "")
        fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        fs:ClearAllPoints(); fs:SetPoint("LEFT", 6, 0); fs:SetPoint("RIGHT", -6, 0)
    end
    win.soundSelectBtn = soundSelectBtn
    soundSelectBtn:SetScript("OnClick", function()
        SA_OpenSoundPicker(soundSelectBtn,
            function() return MimDiceDB.buffTrack[key].soundKey end,
            function(snd)
                local bt = MimDiceDB.buffTrack[key]
                bt.soundType = "preset"; bt.soundKey = snd.id; bt.soundName = snd.name
                win.RefreshSoundRow()
                local was = bt.enabled; bt.enabled = true
                SA_PlaySound(bt); bt.enabled = was
            end)
    end)

    local soundTestBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    soundTestBtn:SetSize(24, 22)
    soundTestBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -15, -56)
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
        win.typeRefresh()
        if bt.soundType == "preset" then
            soundLabel:SetText("내장: 아래에서 사운드 선택 (▶ 미리듣기)")
            soundSelectBtn:Show(); soundBox:Hide()
            soundSelectBtn:SetText(bt.soundName or "사운드 선택...")
        elseif bt.soundType == "id" then
            soundLabel:SetText("ID: 사운드 숫자 ID를 직접 입력")
            soundSelectBtn:Hide(); soundBox:Show()
            SA_SetBoxValue(soundBox, bt.soundID, "예: 567439")
        else
            soundLabel:SetText("커스텀: sounds폴더 파일명 그대로 입력 (대소문자·확장자 구분)")
            soundSelectBtn:Hide(); soundBox:Show()
            SA_SetBoxValue(soundBox, bt.soundFile, "예: MySound.mp3")
        end
    end

    soundBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local bt = MimDiceDB.buffTrack[key]
        if bt.soundType == "id" then
            bt.soundID = tonumber(self:GetText()) or self:GetText()
        else
            bt.soundFile = self:GetText()   -- soundName 은 내장(preset) 표시 전용이라 안 건드림
        end
    end)
    soundBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- 바 표시 체크박스
    local barCb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    barCb:SetSize(22, 22)
    barCb:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -86)
    local barLabel = win:CreateFontString(nil, "OVERLAY")
    barLabel:SetPoint("LEFT", barCb, "RIGHT", 2, 0)
    barLabel:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    barLabel:SetText("화면에 지속시간 바 표시")
    barLabel:SetTextColor(0.9, 0.9, 0.9)
    barCb:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        MimDiceDB.buffTrack[key].barEnabled = on
        local f = SA_BuffBars[key]
        -- 체크는 순수 ON/OFF만 (미리보기 없음). 화면 확인은 위치잠금 해제 또는 테스트 버튼으로.
        if not on and f then
            -- 끄면 화면에서 즉시 숨김 (미리보기/진행 중 바 포함)
            f.previewOn = false
            f.previewing = false
            f.endTime = 0
            f:Hide()
        end
    end)
    win.barCb = barCb

    -- ── 상세 설정 접기/펼치기 (기본: 접힘 = 소리 + 바 표시 ON/OFF만 보임) ──
    local advBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    advBtn:SetSize(310, 22)
    advBtn:SetPoint("TOP", win, "TOP", 0, -114)
    advBtn:GetFontString():SetFont(MimDiceFontPath(), 10, "")
    local adv = CreateFrame("Frame", nil, win)
    adv:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -28)
    adv:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)

    -- 바 색상 (색상환 풀 팔레트 + 코드 입력 + 기본색. 색상환의 투명도 슬라이더 = 바 투명도와 연동)
    win.colorRefresh = SA_MakeColorRow(adv, -112, "바 색상",
        function() return MimDiceDB.buffTrack[key].color end,
        function(r, g, b) MimDiceDB.buffTrack[key].color = { r = r, g = g, b = b } end,
        { def.color[1], def.color[2], def.color[3] },
        function() SA_UpdateBuffBar(key) end,
        {
            get = function() return (MimDiceDB.buffTrack[key].alphaPct or 50) / 100 end,
            set = function(a)
                MimDiceDB.buffTrack[key].alphaPct = math.floor(a * 100 + 0.5)
            end,
        })

    -- 크기/투명도 슬라이더 (가로/세로/글씨/투명도)
    win.wSlider = SA_AddBuffSlider(adv, key, "MimDice_BuffW_" .. key, -148, "바 가로 크기", 100, 1900, "width")
    win.hSlider = SA_AddBuffSlider(adv, key, "MimDice_BuffH_" .. key, -202, "바 세로 크기", 16, 300, "height")
    win.tfSlider = SA_AddBuffSlider(adv, key, "MimDice_BuffTF_" .. key, -256, "글씨 크기 (라벨+남은시간)", 8, 120, "timeFontSize")

    -- 위치 X/Y 직접 입력
    local posRefresh, posX, posY = SA_AddPosRow(adv, -302,
        function() return MimDiceDB.buffTrack[key].x end,
        function(v) MimDiceDB.buffTrack[key].x = v end,
        function() return MimDiceDB.buffTrack[key].y end,
        function(v) MimDiceDB.buffTrack[key].y = v end,
        function() SA_UpdateBuffBar(key) end)
    win.posRefresh = posRefresh

    -- 입력칸 탭/엔터 순환: 가로 → 세로 → 글씨 → 투명도 → X → Y → (가로)
    SA_ChainTabEnter({ win.wSlider.edit, win.hSlider.edit, win.tfSlider.edit, posX, posY })

    -- 위치 잠금/해제
    local lockBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    lockBtn:SetSize(110, 24)
    lockBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 15, 14)
    lockBtn:GetFontString():SetFont(MimDiceFontPath(), 10, "")
    lockBtn:SetScript("OnClick", function()
        local bt = MimDiceDB.buffTrack[key]
        bt.locked = not bt.locked
        SA_UpdateBuffBar(key)
        win.RefreshLockBtn()
    end)
    win.lockBtn = lockBtn
    function win.RefreshLockBtn()
        lockBtn:SetText(MimDiceDB.buffTrack[key].locked and "위치 잠금 해제" or "위치 잠금")
    end

    -- 기본값으로 초기화
    local resetBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    resetBtn:SetSize(70, 24)
    resetBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 155, 14)   -- 340폭 기준 3버튼(110/70/70) 균등 간격 30px
    resetBtn:SetText("기본값")
    resetBtn:GetFontString():SetFont(MimDiceFontPath(), 11, "")
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

    -- 테스트: 실제 발동처럼 사운드 + (바 표시 설정 시) 실제 지속시간 카운트다운 (블러드 40초 → 0.0)
    local previewBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    previewBtn:SetSize(70, 24)
    previewBtn:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -15, 14)
    previewBtn:SetText("테스트")
    previewBtn:GetFontString():SetFont(MimDiceFontPath(), 11, "")
    previewBtn:SetScript("OnClick", function() SA_BuffTest(key) end)

    -- 현재 설정값을 위젯에 반영
    function win.Refresh()
        local bt = MimDiceDB.buffTrack[key]
        win.RefreshSoundRow()
        barCb:SetChecked(bt.barEnabled)
        win.RefreshLockBtn()
        win.wSlider.SyncValue()
        win.hSlider.SyncValue()
        win.tfSlider.SyncValue()
        win.posRefresh()
        win.colorRefresh()   -- 색상 스와치/코드칸 갱신
    end

    -- 상세 설정 접기/펼치기 적용 (접으면 창도 짧아짐)
    local function ApplyAdv()
        local open = MimDiceDB.buffTrack[key].advOpen and true or false
        adv:SetShown(open)
        win:SetHeight(open and 444 or 190)
        advBtn:SetText(open and "상세 설정 접기" or "상세 설정 열기 : 색/크기/위치")
    end
    win.ApplyAdv = ApplyAdv
    advBtn:SetScript("OnClick", function()
        local bt = MimDiceDB.buffTrack[key]
        bt.advOpen = not bt.advOpen
        ApplyAdv()
    end)
    ApplyAdv()

    win:Hide()
    SA_SkinRegisterWindow(win)   -- 스킨 대상 등록
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
        if SA_BattleResIconConfig and SA_BattleResIconConfig:IsShown() then SA_BattleResIconConfig:Hide() end
        if _G.MimDice_PartyConfig and _G.MimDice_PartyConfig:IsShown() then _G.MimDice_PartyConfig:Hide() end
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
    f.bg:Hide()                                  -- 실제 메시지엔 편집 배경/테두리 숨김
    f:SetBackdropBorderColor(1, 0.85, 0, 0)
    -- 사망은 거의 항상 전투 중 → EnableMouse(protected)를 InCombatLockdown으로 가드
    if not InCombatLockdown() then f:EnableMouse(false) end
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
    f:Show()                       -- 설정창에서 숨겨진 상태여도 반드시 표시
    f.fade:SetStartDelay(dt.duration or 3)
    f.fadeAnim:Play()
end

-- 미리보기 (설정 팝업의 "미리보기" 버튼용) - 현재 접속 직업색으로 표시
-- 미리보기 강제 켜기 ("죽음 메시지 표시" 체크 시 위치/모양 확인용)
function SA_DeathPreviewOn()
    local f = SA_EnsureDeathFrame()
    f.previewOn = true
    SA_RenderDeathPreview()
end

-- 미리보기 강제 끄기 (체크 해제 시 화면에서 즉시 숨김)
function SA_DeathPreviewOff()
    local f = SA_DeathFrame
    if not f then return end
    f.previewOn = false
    f.previewing = false
    f.fadeAnim:Stop()
    f.text:SetText("")
    f.icon:Hide()
    f:SetAlpha(0)
    f:Hide()
end

-- 미리보기 토글 (설정창 버튼) - 누르면 켜지고 다시 누르면 꺼짐
function SA_DeathPreview()
    local f = SA_EnsureDeathFrame()
    if f.previewOn then
        SA_DeathPreviewOff()
    else
        SA_DeathPreviewOn()
    end
end

-- =====================================================================
-- 블러드 / 마력주입 지속시간 바
-- (SA_BuffBars 는 위에서 미리 선언됨 - 설정창 OnHide에서 참조)
-- =====================================================================
local function SA_EnsureBuffBar(key)
    if SA_BuffBars[key] then return SA_BuffBars[key] end
    local def = BUFF_DEF_BY_KEY[key]
    local bt = MimDiceDB.buffTrack[key]

    local f = CreateFrame("Frame", "MimDice_BuffBar_" .. key, UIParent, "BackdropTemplate")
    f:SetSize(bt.width or 220, bt.height or 24)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")
    -- 클릭 통과: 블러드 바는 전투 중 표시되는데 전투 중엔 EnableMouse(보호 함수)를 못 끈다.
    -- 편집 상태로 전투에 들어가도 클릭이 아래로 통과되게. (파티 알림 프레임과 동일 패턴)
    if f.SetPropagateMouseClicks then f:SetPropagateMouseClicks(true) end
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
    lbl:SetFont(MimDiceFontPath(), 12, "OUTLINE")
    lbl:SetText(def.name)
    lbl:SetShadowColor(0, 0, 0, 1); lbl:SetShadowOffset(1, -1)
    f.lbl = lbl

    local timeTxt = sb:CreateFontString(nil, "OVERLAY")
    timeTxt:SetPoint("RIGHT", sb, "RIGHT", -6, 0)
    timeTxt:SetFont(MimDiceFontPath(), 13, "OUTLINE")
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
    f.timeTxt:SetFont(MimDiceFontPath(), fs, "OUTLINE")
    f.lbl:SetFont(MimDiceFontPath(), fs, "OUTLINE")   -- 라벨(블러드 등)도 같이 스케일

    if not bt.locked then
        -- 잠금 해제(위치 잡기): 강조 테두리 + 정적 풀 바 + 드래그 가능
        f:SetBackdropColor(0.20, 0.15, 0.00, 0.65)          -- 어두운 노랑빛 배경
        f:SetBackdropBorderColor(1, 0.85, 0, 1)             -- 밝은 노란 테두리 (편집 중 표시)
        f.previewing = true
        f.sb:SetValue(1)
        f.timeTxt:SetText(string.format("%.1f", def.duration))
        f:SetAlpha(1)
        if not InCombatLockdown() then f:EnableMouse(true) end
        f:Show()
    else
        -- 잠금: 일반 테두리
        f:SetBackdropColor(0, 0, 0, 0.25)
        f:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.6)
        if not InCombatLockdown() then f:EnableMouse(false) end
        if f.previewOn then
            -- 미리보기 토글 ON: 정적 풀 바 유지
            f.previewing = true
            f.sb:SetValue(1)
            f.timeTxt:SetText(string.format("%.1f", def.duration))
            f:SetAlpha(1)
            f:Show()
        else
            f.previewing = false
            if f.endTime <= GetTime() then f:Hide() end
        end
    end
end

-- 버프 발동 시 바 시작 (force=true면 활성/표시 여부 무시 - 미리보기용)
local function SA_StartBuffBar(key, duration, force)
    local bt = MimDiceDB and MimDiceDB.buffTrack and MimDiceDB.buffTrack[key]
    if not bt then return end
    if not force and (not bt.enabled or not bt.barEnabled) then return end
    local f = SA_EnsureBuffBar(key)
    SA_UpdateBuffBar(key)
    -- 실제 발동은 편집 테두리 없이 일반 모양으로 카운트다운
    f:SetBackdropColor(0, 0, 0, 0.25)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.6)
    f.duration = duration
    f.endTime = GetTime() + duration
    f.previewing = false
    f:SetAlpha(1)
    f.sb:SetValue(1)
    f.timeTxt:SetText(string.format("%.1f", duration))
    if not InCombatLockdown() then f:EnableMouse(false) end
    f:Show()
end

-- 버프 사운드 재생 (계정 공용, bt.enabled로 게이트)
-- 블러드/마력주입은 길어서 "Dialog" 채널로 재생 → 전투 효과음 폭주에 밀려 끊기는 현상 방지
local function SA_PlayBuff(key)
    local bt = MimDiceDB and MimDiceDB.buffTrack and MimDiceDB.buffTrack[key]
    if not bt or not bt.enabled then return end
    SA_PlaySound(bt, "Dialog")
end

-- 테스트 중복 방지: 사운드(≈지속시간 40초)가 끝나기 전 재클릭은 무시 (소리 겹침 방지)
local SA_buffTestUntil = {}   -- key → 이 시각(GetTime)까지 테스트 재실행 억제

-- 테스트 (설정창 버튼용, 전역): 실제 발동과 동일하게
-- 사운드 + (바 표시 설정 시) 실제 지속시간(블러드 40초) 카운트다운을 0.0까지 표시
function SA_BuffTest(key)
    local bt = MimDiceDB and MimDiceDB.buffTrack and MimDiceDB.buffTrack[key]
    if not bt then return end
    local def = BUFF_DEF_BY_KEY[key]
    local dur = (def and def.duration) or 40
    local now = GetTime()
    if SA_buffTestUntil[key] and now < SA_buffTestUntil[key] then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cffffff00[MimDice]|r 테스트 재생 중입니다 (%.0f초 남음)", SA_buffTestUntil[key] - now))
        return
    end
    SA_buffTestUntil[key] = now + dur
    if bt.barEnabled then
        SA_StartBuffBar(key, dur, true)   -- force: 마스터 off여도 테스트는 표시
        -- 카운트다운 끝난 뒤 표시 정책 복구 ('바 표시' 상시 미리보기/편집 중이면 다시 표시)
        C_Timer.After(dur + 0.2, function() SA_UpdateBuffBar(key) end)
    end
    local was = bt.enabled; bt.enabled = true  -- 테스트는 마스터 off여도 강제 재생
    SA_PlaySound(bt, "Dialog"); bt.enabled = was
end

-- =====================================================================
-- 전투부활 충전 추적 (모든 클래스 지원)
-- =====================================================================
local SA_brLastCharges = nil   -- 마지막 충전 수 (증가 감지용)

-- 현재 충전 수 조회 (없으면 nil) — 직업 무관하게 레이드 공용 풀 조회
local function SA_GetBattleResCharges()
    local ok, info = pcall(C_Spell.GetSpellCharges, BREZ_SPELL_ID)
    if ok and info and info.currentCharges then return info.currentCharges end
    return nil
end

-- 추적 기준값을 현재 충전으로 동기화 (로그인/인스턴스 진입 시 오발동 방지)
local function SA_SyncBattleResCharges()
    SA_brLastCharges = SA_GetBattleResCharges()
end

-- 충전 변화 확인 → 늘었으면 사운드 (SPELL_UPDATE_CHARGES에서 호출)
local function SA_CheckBattleResCharge()
    local br = MimDiceDB and MimDiceDB.battleRes
    if not br or not br.enabled then return end
    local cur = SA_GetBattleResCharges()
    if cur == nil then return end
    if SA_brLastCharges ~= nil and cur > SA_brLastCharges then
        SA_PlaySound(br, "Dialog")   -- 충전이 늘어남 = 전투부활 충전됨
    end
    SA_brLastCharges = cur
end

-- =====================================================================
-- 전투부활 아이콘 (충전 수 + 재충전 스와이프) — 모든 클래스 공용, 옵션 ON/OFF
-- (SA_BattleResIcon / SA_BattleResIconConfig / SA_brIconTicker 는 위에서 미리 선언)
-- =====================================================================

-- 아이콘 프레임 생성 (1회). 전투 중 생성 회피 위해 로그인 시 미리 만든다.
local function SA_EnsureBattleResIcon()
    if SA_BattleResIcon then return SA_BattleResIcon end
    local br = MimDiceDB.battleRes
    local size = (br and br.iconSize) or 40

    local f = CreateFrame("Frame", "MimDice_BattleResIcon", UIParent, "BackdropTemplate")
    f:SetSize(size, size)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")      -- 다른 UI에 안 가리도록 레이어 상향
    f:SetFrameLevel(120)
    -- 클릭 통과: 편집 상태로 전투에 들어가 클릭 설정을 못 되돌려도 클릭이 아래로 통과되게
    if f.SetPropagateMouseClicks then f:SetPropagateMouseClicks(true) end

    -- 편집(이동 가능) 표시용 반투명 노란 헤일로 — 아이콘보다 살짝 크게, 평소엔 숨김
    local editGlow = f:CreateTexture(nil, "BACKGROUND")
    editGlow:SetPoint("TOPLEFT", f, "TOPLEFT", -5, 5)
    editGlow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 5, -5)
    editGlow:SetColorTexture(1, 0.82, 0, 0.35)
    editGlow:Hide()
    f.editGlow = editGlow

    -- 스킬 아이콘 텍스처 (가장자리 살짝 잘라 깔끔하게)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon = icon

    -- 어두운 테두리
    f:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    f:SetBackdropBorderColor(0, 0, 0, 1)

    -- 재충전 스와이프 (쿨다운 프레임)
    local cd = CreateFrame("Cooldown", "MimDice_BattleResIconCD", f, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    cd:SetHideCountdownNumbers(false)
    cd:SetDrawSwipe(true)
    cd:SetDrawEdge(false)
    f.cd = cd

    -- 충전 수 텍스트 (우하단)
    local count = f:CreateFontString(nil, "OVERLAY")
    count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
    count:SetFont(MimDiceFontPath(), 14, "OUTLINE")
    count:SetShadowColor(0, 0, 0, 1); count:SetShadowOffset(1, -1)
    count:SetJustifyH("RIGHT")
    f.count = count

    -- 아이콘 텍스처 적용 (환생 20484) — 로그인 직후 미캐시면 RefreshState에서 재시도
    local okInfo, info = pcall(C_Spell.GetSpellInfo, BREZ_SPELL_ID)
    if okInfo and info and info.iconID then icon:SetTexture(info.iconID); f.iconSet = true end

    -- 드래그(잠금 해제 시) — 위치 저장
    local function savePos(self)
        local x, y = self:GetCenter(); local cx, cy = UIParent:GetCenter()
        if x and cx then
            MimDiceDB.battleRes.iconX = x - cx
            MimDiceDB.battleRes.iconY = y - cy
        end
        local cfg = SA_BattleResIconConfig
        if cfg and cfg:IsShown() and cfg.posRefresh then cfg.posRefresh() end
    end
    -- 드래그(잠금 해제 시). isMoving 중에는 티커가 위치를 안 건드림 → 자석처럼 되돌아가는 문제 방지
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        local b = MimDiceDB.battleRes
        if b and not b.iconLocked then self:StartMoving(); self.isMoving = true end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing(); self.isMoving = false; savePos(self)
    end)

    -- 마우스 호버 툴팁 (클릭은 통과시키되, 올리면 전투부활 정보만 표시) — 전부 pcall 보호
    f:SetScript("OnEnter", function(self)
        pcall(function()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("전투부활", 1, 0.82, 0)
            local ok, info = pcall(C_Spell.GetSpellCharges, BREZ_SPELL_ID)
            if ok and info and info.currentCharges then
                local mx = info.maxCharges and ("/" .. info.maxCharges) or ""
                GameTooltip:AddLine("남은 충전: " .. info.currentCharges .. mx, 1, 1, 1)
                if info.maxCharges and info.currentCharges < info.maxCharges
                   and info.cooldownDuration and info.cooldownDuration > 0 then
                    local remain = (info.cooldownStartTime or 0) + info.cooldownDuration - GetTime()
                    if remain > 0 then
                        GameTooltip:AddLine(string.format("다음 충전까지: %.0f초", remain), 0.7, 0.7, 0.7)
                    end
                end
            else
                GameTooltip:AddLine("충전 정보는 파티/공대에서 표시됩니다", 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)
    end)
    f:SetScript("OnLeave", function() pcall(GameTooltip.Hide, GameTooltip) end)

    f:Hide()
    SA_BattleResIcon = f
    return f
end

-- 마우스 모드 설정 (전부 pcall — 전투 중 호출돼도 taint/에러 안 나게)
--   clickable=false(잠금/표시중): 클릭은 통과(아래 UI·월드 클릭 방해 안 함) + 모션만 받아 툴팁
--   clickable=true (편집중): 클릭/드래그 허용
local function SA_SetBattleResIconMouse(f, clickable)
    -- EnableMouse/SetPropagateMouseClicks 등은 전투 중 보호 함수라 호출하면
    -- ADDON_ACTION_BLOCKED가 뜬다(pcall로도 못 막음). 전투 중엔 건드리지 않고,
    -- 전투가 끝나면 PLAYER_REGEN_ENABLED에서 SA_RefreshBattleResIconState가 다시 적용한다.
    if InCombatLockdown() then return end
    pcall(function()
        f:EnableMouse(true)
        if f.SetMouseClickEnabled then f:SetMouseClickEnabled(clickable) end
        if f.SetMouseMotionEnabled then f:SetMouseMotionEnabled(true) end
        -- 편집중(clickable)엔 프레임이 클릭을 잡아 드래그, 잠금엔 클릭을 아래로 통과
        if f.SetPropagateMouseClicks then f:SetPropagateMouseClicks(not clickable) end
    end)
end

-- 크기/위치/글씨 레이아웃만 적용 (표시 여부와 무관, 재귀 없음)
local function SA_ApplyBattleResIconLayout(f, br)
    if f.isMoving then return end   -- 드래그 중엔 위치/크기 안 건드림 (되돌아가는 문제 방지)
    local size = br.iconSize or 40
    f:SetSize(size, size)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", br.iconX or 0, br.iconY or 0)
    f.count:SetFont(MimDiceFontPath(), math.max(8, math.floor(size * 0.4)), "OUTLINE")
end

-- 편집/미리보기용 정적 표시 (그룹 무관, 충전 3개 가정)
local function SA_ShowBattleResIconStatic(f)
    f.icon:SetDesaturated(false)
    f.count:SetText("3")
    f.cd:Clear()
    f:SetAlpha(1)
    f:Show()
end

-- 아이콘 상태 갱신 (티커/이벤트/설정변경에서 호출) — 전역
-- 표시 규칙:
--   * 마스터(전투부활 br.enabled) 꺼짐 → 무조건 숨김 (전투부활 자체를 안 씀)
--   * 편집(잠금해제) 또는 설정창 열림 → 그룹 무관 정적 표시 (위치잡기용, 별도 미리보기 불필요)
--   * 잠금 + 아이콘 ON → 항상 표시 (풀 읽히면 충전 수/스와이프 라이브, 아니면 아이콘만)
--   * 그 외 → 숨김
function SA_RefreshBattleResIconState()
    local br = MimDiceDB and MimDiceDB.battleRes
    if not br then return end
    local f = SA_BattleResIcon

    -- 마스터(전투부활) 꺼져 있으면 아이콘 자체를 완전히 무시
    if not br.enabled then
        if f then f.editGlow:Hide(); f:Hide() end
        return
    end

    local editing = not br.iconLocked
    local cfgOpen = SA_BattleResIconConfig and SA_BattleResIconConfig:IsShown()
    -- 편집중(드래그)이거나, (설정창 열림 + 아이콘 ON)이면 위치 확인용 정적 표시 (그룹 무관)
    local showStatic = editing or (cfgOpen and br.iconEnabled)

    if not (showStatic or br.iconEnabled) then
        if f then f:Hide() end
        return
    end

    f = SA_EnsureBattleResIcon()
    SA_ApplyBattleResIconLayout(f, br)

    -- 로그인 직후 아이콘이 미캐시였으면 지금 다시 시도
    if not f.iconSet then
        local okS, sinfo = pcall(C_Spell.GetSpellInfo, BREZ_SPELL_ID)
        if okS and sinfo and sinfo.iconID then f.icon:SetTexture(sinfo.iconID); f.iconSet = true end
    end

    -- 편집 모드: 반투명 헤일로 + 노란 테두리 + 클릭(드래그) 허용 / 잠금: 평소 + 클릭 통과(호버 툴팁만)
    if editing then
        f.editGlow:Show()
        f:SetBackdropBorderColor(1, 0.85, 0, 1)
        SA_SetBattleResIconMouse(f, true)
    else
        f.editGlow:Hide()
        f:SetBackdropBorderColor(0, 0, 0, 1)
        SA_SetBattleResIconMouse(f, false)
    end

    -- 편집/설정창 열림 → 정적 표시 (위치잡기용)
    if showStatic then
        SA_ShowBattleResIconStatic(f)
        return
    end

    -- 잠금 + 아이콘 ON이면 항상 표시 (그룹/장소 무관)
    --   충전 풀이 읽히면 충전 수/스와이프 라이브, 안 읽히면(야외 등) 숫자 없이 아이콘만
    if br.iconEnabled then
        local ok, info = pcall(C_Spell.GetSpellCharges, BREZ_SPELL_ID)
        local cur = ok and info and info.currentCharges
        if cur ~= nil then
            f.count:SetText(tostring(cur))
            f.icon:SetDesaturated(cur <= 0)
            if info.maxCharges and cur < info.maxCharges and info.cooldownDuration and info.cooldownDuration > 0 then
                f.cd:SetCooldown(info.cooldownStartTime or 0, info.cooldownDuration)
            else
                f.cd:Clear()
            end
        else
            -- 야외/그룹 밖 등 충전 정보 없음: 아이콘만 표시
            f.count:SetText("")
            f.icon:SetDesaturated(false)
            f.cd:Clear()
        end
        f:SetAlpha(1)
        f:Show()
        return
    end
    f:Hide()
end

-- 설정 변경 시 즉시 반영 (전역: 설정창에서 호출)
function SA_UpdateBattleResIcon()
    SA_RefreshBattleResIconState()
end

-- ── 사운드 선택 팝업 (각 항목 옆 ▶ 미리듣기) ─────────────────────────
-- 기본 UIDropDownMenu는 항목별 보조 버튼을 못 달아서, 스크롤 리스트로 직접 구현.
--   이름 클릭 = 선택(팝업 닫힘) / ▶ 클릭 = 미리듣기(팝업 유지)
local SA_SoundPicker = nil
local SA_SoundPickerOnSelect = nil   -- 항목 선택 시 콜백 func(snd)

local function SA_EnsureSoundPicker()
    if SA_SoundPicker then return SA_SoundPicker end

    -- 모든 내장 사운드 평탄화
    local all = {}
    for _, cat in ipairs(SOUND_CATEGORIES) do
        for _, snd in ipairs(cat.sounds) do all[#all + 1] = snd end
    end

    local p = CreateFrame("Frame", "MimDice_SoundPicker", UIParent, "BackdropTemplate")
    p:SetSize(330, 360)
    p:SetFrameStrata("FULLSCREEN_DIALOG")   -- 설정창보다 위
    p:SetClampedToScreen(true)
    p:SetToplevel(true)
    p:EnableMouse(true)
    -- 기존 설정창과 동일 테마 (검은 반투명 배경 + 회색 테두리)
    p:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    p:SetBackdropColor(0, 0, 0, 0.85)
    p:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    local title = p:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetFont(MimDiceFontPath(), 12, "OUTLINE")
    title:SetText("사운드 선택 (▶ 미리듣기)")
    title:SetTextColor(1, 0.82, 0)

    -- 대화(Dialog) 채널 사용 안내 (최상단)
    local note = p:CreateFontString(nil, "OVERLAY")
    note:SetPoint("TOPLEFT", 12, -28)
    note:SetWidth(306); note:SetJustifyH("LEFT"); note:SetWordWrap(true)
    note:SetFont(MimDiceFontPath(), 10, "")
    note:SetText("· 긴 사운드파일도 재생가능하도록 주음량대신 대화 채널을 사용합니다.")
    note:SetTextColor(0.7, 0.7, 0.7)

    local closeBtn = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    closeBtn.MimDiceIsClose = true   -- 스킨: 닫기(X) 플랫화 대상
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() p:Hide() end)

    local scroll = CreateFrame("ScrollFrame", "MimDice_SoundPickerScroll", p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -64)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(290, #all * 24)
    scroll:SetScrollChild(child)

    p.rows = {}
    for i, snd in ipairs(all) do
        local row = CreateFrame("Button", nil, child)
        row:SetSize(290, 22)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * 24)

        -- 현재 선택된 사운드 표시 (금색)
        local sel = row:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        sel:SetColorTexture(1, 0.82, 0, 0.25)
        sel:Hide()
        row.sel = sel

        -- 마우스 호버 하이라이트 (이름/▶ 어디에 올려도 그 줄이 밝아짐)
        local hl = row:CreateTexture(nil, "ARTWORK")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.12)
        hl:Hide()

        local nameFS = row:CreateFontString(nil, "OVERLAY")
        nameFS:SetPoint("LEFT", 6, 0)
        nameFS:SetPoint("RIGHT", -34, 0)
        nameFS:SetJustifyH("LEFT"); nameFS:SetWordWrap(false)
        nameFS:SetFont(MimDiceFontPath(), 11, "")
        nameFS:SetText(snd.name)

        -- 줄(이름) 클릭 = 선택 후 닫기
        row:SetScript("OnClick", function()
            if SA_SoundPickerOnSelect then SA_SoundPickerOnSelect(snd) end
            p:Hide()
        end)

        -- ▶ 미리듣기 (클릭해도 팝업 유지) — 실제와 동일한 대화(Dialog) 채널로 재생
        local play = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        play:SetSize(24, 18)
        play:SetPoint("RIGHT", -3, 0)
        play:SetText("▶")
        play:GetFontString():SetFont(MimDiceFontPath(), 9, "")
        play:SetScript("OnClick", function()
            SA_PlaySound({ enabled = true, soundType = "preset", soundKey = snd.id }, "Dialog")
        end)

        -- 줄 또는 ▶ 어디에 마우스가 있어도 그 줄 하이라이트 유지
        local function showHL() hl:Show() end
        local function hideHL() if not row:IsMouseOver() and not play:IsMouseOver() then hl:Hide() end end
        row:SetScript("OnEnter", showHL)
        row:SetScript("OnLeave", hideHL)
        play:HookScript("OnEnter", showHL)
        play:HookScript("OnLeave", hideHL)

        p.rows[i] = { row = row, snd = snd }
    end

    tinsert(UISpecialFrames, "MimDice_SoundPicker")   -- ESC로 닫기
    p:Hide()
    SA_SkinRegisterWindow(p)   -- 스킨 대상 등록
    SA_SoundPicker = p
    return p
end

-- 팝업 열기: anchor 아래에 표시. getSel()=현재 선택 id, onSelect(snd)=선택 콜백
function SA_OpenSoundPicker(anchor, getSel, onSelect)
    local p = SA_EnsureSoundPicker()
    -- 같은 버튼 다시 누르면 닫기, 다른 버튼이면 그 버튼으로 이동/재바인딩
    if p:IsShown() and p.anchor == anchor then p:Hide(); return end
    p.anchor = anchor
    SA_SoundPickerOnSelect = onSelect

    local cur = getSel and getSel()
    for _, r in ipairs(p.rows) do
        if cur ~= nil and r.snd.id == cur then r.row.sel:Show() else r.row.sel:Hide() end
    end

    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    p:Show()
    p:Raise()
end

-- ── 전투부활 아이콘 설정창 ────────────────────────────────────────────
local SA_brTestUntil = 0   -- 전투부활 테스트 중복 방지: 이 시각(GetTime)까지 재실행 억제

function SA_CreateBattleResIconConfig()
    if SA_BattleResIconConfig then return SA_BattleResIconConfig end

    local win = CreateFrame("Frame", "MimDice_BRIconConfig", UIParent, "BackdropTemplate")
    win:SetSize(340, 362)
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
    -- (화면 클램프 없음: 메인창처럼 화면 밖으로도 이동 가능 — 번들로 함께 이동)
    -- 설정창을 잡고 끌면 본체(MainWindow)가 점프 없이 한 덩어리로 이동
    SA_WireBundleDrag(win)
    -- 설정창을 닫으면(X/ESC/연쇄) 그룹 정책대로 복귀 + 사운드 팝업 닫기 + 아이콘 위치 자동 잠금
    win:SetScript("OnHide", function()
        if SA_SoundPicker then SA_SoundPicker:Hide() end
        local b = MimDiceDB and MimDiceDB.battleRes
        if b and not b.iconLocked then b.iconLocked = true end
        SA_RefreshBattleResIconState()
    end)

    local title = win:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", win, "TOP", 0, -12)
    title:SetFont(MimDiceFontPath(), 13, "OUTLINE")
    title:SetText("전투부활 설정 (공용)")
    title:SetTextColor(1, 0.82, 0)

    local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    closeBtn.MimDiceIsClose = true   -- 스킨: 닫기(X) 플랫화 대상
    closeBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() win:Hide() end)

    -- ── 재생 사운드 (내장/커스텀/ID) — 메인 옵션창에서 이리로 이동 ──
    local soundLabel = win:CreateFontString(nil, "OVERLAY")
    soundLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -40)
    soundLabel:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    soundLabel:SetText("충전 시 재생 사운드")
    soundLabel:SetTextColor(0.9, 0.9, 0.9)

    -- 3종 타입 선택 버튼 (내장 / 커스텀 / ID)
    win.typeRefresh = SA_MakeTypeSelector(win, 15, -60,
        function() return MimDiceDB.battleRes.soundType end,
        function(t) MimDiceDB.battleRes.soundType = t; win.RefreshSoundRow() end)

    -- 커스텀/ID 입력칸 (직접 타이핑)
    local soundBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    soundBox:SetSize(135, 22)
    soundBox:SetPoint("TOPLEFT", win, "TOPLEFT", 157, -60)
    soundBox:SetAutoFocus(false)
    soundBox:SetFont(MimDiceFontPath(), 11, "")
    SA_WirePlaceholder(soundBox)

    -- 내장 선택 시: 사운드 선택 팝업 버튼 (soundBox 자리, 토글로 교체 표시)
    local soundSelectBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    soundSelectBtn:SetSize(135, 22)
    soundSelectBtn:SetPoint("TOPLEFT", win, "TOPLEFT", 157, -60)
    do
        local fs = soundSelectBtn:GetFontString()
        fs:SetFont(MimDiceFontPath(), 10, "")
        fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        fs:ClearAllPoints(); fs:SetPoint("LEFT", 6, 0); fs:SetPoint("RIGHT", -6, 0)
    end
    soundSelectBtn:SetScript("OnClick", function()
        SA_OpenSoundPicker(soundSelectBtn,
            function() return MimDiceDB.battleRes.soundKey end,
            function(snd)
                local b = MimDiceDB.battleRes
                b.soundType = "preset"; b.soundKey = snd.id; b.soundName = snd.name
                win.RefreshSoundRow()
                SA_PlaySound(b, "Dialog")   -- 선택 시 한 번 들려줌
            end)
    end)

    local testBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    testBtn:SetSize(24, 22)
    testBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -15, -60)
    testBtn:SetText("▶")
    testBtn:SetScript("OnClick", function()
        local b = MimDiceDB.battleRes
        local was = b.enabled; b.enabled = true
        SA_PlaySound(b, "Dialog"); b.enabled = was
    end)

    function win.RefreshSoundRow()
        local b = MimDiceDB.battleRes
        win.typeRefresh()
        if b.soundType == "preset" then
            soundLabel:SetText("내장: 아래에서 사운드 선택 (▶ 미리듣기)")
            soundSelectBtn:Show(); soundBox:Hide()
            soundSelectBtn:SetText(b.soundName or "사운드 선택...")
        elseif b.soundType == "id" then
            soundLabel:SetText("ID: 사운드 숫자 ID를 직접 입력")
            soundSelectBtn:Hide(); soundBox:Show()
            SA_SetBoxValue(soundBox, b.soundID, "예: 567439")
        else
            soundLabel:SetText("커스텀: sounds폴더 파일명 그대로 입력 (대소문자·확장자 구분)")
            soundSelectBtn:Hide(); soundBox:Show()
            SA_SetBoxValue(soundBox, b.soundFile, "예: MySound.mp3")
        end
    end

    soundBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local b = MimDiceDB.battleRes
        if b.soundType == "id" then b.soundID = tonumber(self:GetText()) or self:GetText()
        else b.soundFile = self:GetText() end   -- soundName 은 내장(preset) 표시 전용이라 안 건드림
    end)
    soundBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- ── 아이콘 표시 ON/OFF ──
    local enCb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    enCb:SetSize(24, 24)
    enCb:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -104)
    local enLabel = win:CreateFontString(nil, "OVERLAY")
    enLabel:SetPoint("LEFT", enCb, "RIGHT", 2, 0)
    enLabel:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    enLabel:SetText("전투부활 아이콘 표시 (다른 애드온 쓰면 끄기)")
    enLabel:SetTextColor(0.9, 0.9, 0.9)
    enCb:SetScript("OnClick", function(self)
        MimDiceDB.battleRes.iconEnabled = self:GetChecked() and true or false
        SA_RefreshBattleResIconState()
    end)
    win.enCb = enCb

    -- ── 상세 설정 접기/펼치기 (기본: 접힘 = 소리 + 아이콘 표시 ON/OFF만 보임) ──
    local advBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    advBtn:SetSize(310, 22)
    advBtn:SetPoint("TOP", win, "TOP", 0, -134)
    advBtn:GetFontString():SetFont(MimDiceFontPath(), 10, "")
    local adv = CreateFrame("Frame", nil, win)
    adv:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -28)
    adv:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)

    -- 아이콘 크기 슬라이더
    win.sizeSlider = SA_MakeNumberSlider(adv, "MimDice_BRIconSize", -148, "아이콘 크기", 16, 128,
        function() return MimDiceDB.battleRes.iconSize end,
        function(v) MimDiceDB.battleRes.iconSize = v end,
        function() SA_UpdateBattleResIcon() end)

    -- 위치 X/Y 직접 입력
    local posRefresh, posX, posY = SA_AddPosRow(adv, -210,
        function() return MimDiceDB.battleRes.iconX end,
        function(v) MimDiceDB.battleRes.iconX = v end,
        function() return MimDiceDB.battleRes.iconY end,
        function(v) MimDiceDB.battleRes.iconY = v end,
        function() SA_UpdateBattleResIcon() end)
    win.posRefresh = posRefresh
    SA_ChainTabEnter({ win.sizeSlider.edit, posX, posY })

    -- 안내문
    local hint = adv:CreateFontString(nil, "OVERLAY")
    hint:SetPoint("TOPLEFT", adv, "TOPLEFT", 15, -250)
    hint:SetFont(MimDiceFontPath(), 10, "")
    hint:SetTextColor(0.7, 0.7, 0.7)
    hint:SetWidth(310); hint:SetJustifyH("LEFT")
    hint:SetText("· '위치 잠금 해제' 후 아이콘을 드래그해 옮기세요.")

    -- 위치 잠금/해제
    local lockBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    lockBtn:SetSize(110, 24)
    lockBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 15, 14)
    lockBtn:GetFontString():SetFont(MimDiceFontPath(), 10, "")
    lockBtn:SetScript("OnClick", function()
        local b = MimDiceDB.battleRes
        b.iconLocked = not b.iconLocked
        SA_RefreshBattleResIconState()
        win.RefreshLockBtn()
    end)
    win.lockBtn = lockBtn
    function win.RefreshLockBtn()
        lockBtn:SetText(MimDiceDB.battleRes.iconLocked and "위치 잠금 해제" or "위치 잠금")
    end

    -- 기본값 초기화 (다른 설정창과 동일하게 하단 가운데)
    local resetBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    resetBtn:SetSize(70, 24)
    resetBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 155, 14)   -- 340폭 기준 3버튼(110/70/70) 균등 간격 30px
    resetBtn:SetText("기본값")
    resetBtn:GetFontString():SetFont(MimDiceFontPath(), 11, "")
    resetBtn:SetScript("OnClick", function()
        local b = MimDiceDB.battleRes
        b.iconSize, b.iconX, b.iconY, b.iconLocked = 40, 0, 0, true   -- 화면 정중앙
        SA_RefreshBattleResIconState()
        win.Refresh()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MimDice]|r 전투부활 아이콘 설정 초기화됨")
    end)

    -- 테스트: 실제 충전 알림처럼 사운드 재생 (마스터 off여도 재생, 중복 방지)
    local testBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    testBtn:SetSize(70, 24)
    testBtn:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -15, 14)
    testBtn:SetText("테스트")
    testBtn:GetFontString():SetFont(MimDiceFontPath(), 11, "")
    testBtn:SetScript("OnClick", function()
        local now = GetTime()
        if now < SA_brTestUntil then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cffffff00[MimDice]|r 테스트 재생 중입니다 (%.0f초 남음)", SA_brTestUntil - now))
            return
        end
        SA_brTestUntil = now + 3
        local b = MimDiceDB.battleRes
        local was = b.enabled; b.enabled = true
        SA_PlaySound(b, "Dialog"); b.enabled = was
    end)

    -- 위젯에 현재값 반영
    function win.Refresh()
        local b = MimDiceDB.battleRes
        win.RefreshSoundRow()
        enCb:SetChecked(b.iconEnabled)
        win.sizeSlider.SyncValue()
        win.posRefresh()
        win.RefreshLockBtn()
    end

    -- 상세 설정 접기/펼치기 적용 (접으면 창도 짧아짐)
    local function ApplyAdv()
        local open = MimDiceDB.battleRes.advOpen and true or false
        adv:SetShown(open)
        win:SetHeight(open and 390 or 210)
        advBtn:SetText(open and "상세 설정 접기" or "상세 설정 열기 : 크기/위치")
    end
    win.ApplyAdv = ApplyAdv
    advBtn:SetScript("OnClick", function()
        MimDiceDB.battleRes.advOpen = not MimDiceDB.battleRes.advOpen
        ApplyAdv()
    end)
    ApplyAdv()

    win:Hide()
    SA_SkinRegisterWindow(win)   -- 스킨 대상 등록
    SA_BattleResIconConfig = win
    return win
end

function SA_ToggleBattleResIconConfig()
    local win = SA_CreateBattleResIconConfig()
    if win:IsShown() then
        win:Hide()
    else
        -- 다른 설정창 닫기 (같은 위치 겹침 방지)
        for _, w in pairs(SA_BuffConfigs) do if w:IsShown() then w:Hide() end end
        if SA_DeathConfig and SA_DeathConfig:IsShown() then SA_DeathConfig:Hide() end
        if _G.MimDice_PartyConfig and _G.MimDice_PartyConfig:IsShown() then _G.MimDice_PartyConfig:Hide() end
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", SA_OptionWindow, "TOPRIGHT", 6, 0)
        win.Refresh()
        win:Show()
        SA_RefreshBattleResIconState()   -- 창 열자마자 위치확인용 아이콘 즉시 표시 (티커 0.5초 대기 제거)
    end
end

-- 미리보기 강제 켜기 ("바 표시" 체크 시 위치/모양 확인용)
function SA_BuffPreviewOn(key)
    local f = SA_EnsureBuffBar(key)
    f.previewOn = true
    SA_UpdateBuffBar(key)
end

-- 미리보기 토글 (설정창 버튼) - 누르면 켜지고 다시 누르면 꺼짐. 정적 풀 바로 계속 표시.
function SA_BuffPreview(key)
    local f = SA_EnsureBuffBar(key)
    f.previewOn = not f.previewOn
    if f.previewOn then
        SA_UpdateBuffBar(key)   -- previewOn 반영해서 정적 표시
    else
        f.previewing = false
        f:Hide()
    end
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

    -- 솔로/역할 미지정(NONE)이고 본인이면 특성(spec) 역할로 보정 → 아이콘 표시
    if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then
        local okSelf, isSelf = pcall(UnitIsUnit, unitID, "player")
        if okSelf and isSelf then
            role = SA_PlayerRoleForPreview()
        end
    end

    local _, classFile = UnitClass(unitID)
    if SA_IsSecret(classFile) then classFile = nil end

    SA_ShowDeathMessage(name, role, classFile)
end

-- =====================================================================
-- 파티 신청 알림 (LFG 모집 중 신청 오면 화면 메시지 + 사운드)
-- =====================================================================
local SA_PartyFrame = nil
local SA_PartyConfig = nil   -- 설정창 (아래에서 생성). 드래그 시 참조용 미리 선언.
local SA_paLastCount = 0     -- 직전 신청자 수 (잔상 정리 등에 사용)
local SA_partyRepeatTicker = nil  -- 반복 알림 티커 (repeat 모드)
local SA_partyRepeatInterval = nil  -- 현재 티커 간격(초) — 설정 변경 감지용
local SA_paSeen = {}         -- 이미 알림한 applicantID 집합 (목록 순서를 안 믿고 새 신청자를 ID로 식별)
local SA_paLastShownID = nil -- 마지막으로 표시한 신청자 ID (반복 알림 재표시용)
local SA_paTestUntil = 0     -- 테스트 중복 방지: 이 시각(GetTime)까지 테스트 재실행 억제

-- 최근 신청자 정보 문자열 ([특성아이콘 특성명] 직업색이름  아이템렙  쐐기점수). 전부 pcall 보호.
-- GetApplicantMemberInfo 반환값 순서(확인됨): 1 name, 2 class, 3 locClass, 4 level,
--   5 itemLevel, 6 honor, 7 tank, 8 healer, 9 damager, 10 role, 11 rel, 12 dungeonScore,
--   13 pvpIlvl, 14 ?, 15 ?, 16 specID, ...  (pcall로 감싸면 인덱스가 +1 밀림)
local function SA_PartyApplicantText(appID)
    local pa = MimDiceDB and MimDiceDB.partyAlert
    if not pa or not C_LFGList then return "" end
    local ok, apps = pcall(C_LFGList.GetApplicants)
    if not ok or type(apps) ~= "table" or #apps == 0 then return "" end
    -- 표시 대상: 지정 신청자 → (반복 알림) 마지막 표시했던 신청자가 아직 대기 중이면 그 사람 → 목록 마지막
    -- (GetApplicants() 목록 순서는 "최신이 마지막"이 보장되지 않으므로 순서에 의존하지 않는다)
    local target = appID
    if not target and SA_paLastShownID then
        for _, id in ipairs(apps) do
            if id == SA_paLastShownID then target = id; break end
        end
    end
    target = target or apps[#apps]
    local r = { pcall(C_LFGList.GetApplicantMemberInfo, target, 1) }
    if not r[1] then return "" end              -- r[1] = pcall ok
    local name  = r[2]
    if not name or SA_IsSecret(name) then return "" end
    local class = r[3]
    local ilvl  = r[6]      -- 반환 5 (itemLevel)
    local score = r[13]     -- 반환 12 (dungeonScore, 전체 쐐기점수)
    local specID = r[17]    -- 반환 16 (specID)

    -- 이름 + 서버 (현재 서버가 아니면 서버 표시)
    local realm = (GetRealmName and GetRealmName()) or ""
    local shortName, srv = name, nil
    local di = name:find("%-")
    if di then shortName = name:sub(1, di - 1); srv = name:sub(di + 1) end
    local nameDisp = shortName
    if srv and srv ~= "" and srv ~= realm then nameDisp = shortName .. "-" .. srv end
    local disp = nameDisp
    if class and not SA_IsSecret(class) and C_ClassColor then
        local c = C_ClassColor.GetClassColor(class)
        if c then disp = "|c" .. c:GenerateHexColor() .. nameDisp .. "|r" end
    end

    -- 특성 아이콘(작게 + 여백 크롭) + 특성명
    -- (secret value 방어: SA_IsSecret 를 비교/연산 앞에 둬서 and 단락으로 secret 값 비교를 회피)
    local specStr = ""
    if pa.showSpec and type(specID) == "number" and not SA_IsSecret(specID) and specID > 0 and GetSpecializationInfoByID then
        local okS, _sid, sname, _desc, sicon = pcall(GetSpecializationInfoByID, specID)
        if okS and sname then
            if sicon then
                local isz = math.floor((pa.fontSize or 30) * 0.7 + 0.5)
                specStr = "|T" .. sicon .. ":" .. isz .. ":" .. isz .. ":0:0:64:64:5:59:5:59|t "
            end
            specStr = specStr .. sname .. " "
        end
    end

    -- 이름  템렙620 / 쐐기 2450 점
    local stats = {}
    if pa.showItemLevel and type(ilvl) == "number" and not SA_IsSecret(ilvl) and ilvl > 0 then
        stats[#stats+1] = "템렙" .. math.floor(ilvl)
    end
    if pa.showScore and type(score) == "number" and not SA_IsSecret(score) and score > 0 then
        stats[#stats+1] = "쐐기 " .. score .. " 점"
    end
    -- 세그먼트 조립: [특성아이콘+특성명] [이름] [스탯] — 닉네임 숨김 옵션 반영
    local segs = {}
    if specStr ~= "" then segs[#segs+1] = (specStr:gsub("%s+$", "")) end
    if pa.showName ~= false then segs[#segs+1] = disp end
    if #stats > 0 then
        local sc = pa.statColor or { r = 1, g = 1, b = 1 }
        -- 글자 일부만 진짜 투명하게는 안 되므로, 투명도만큼 배경색 쪽으로 섞어서 표현
        local sa = pa.statColorA or 1
        local bgc = pa.bgColor or { r = 0, g = 0, b = 0 }
        local mr = sc.r * sa + (bgc.r or 0) * (1 - sa)
        local mg = sc.g * sa + (bgc.g or 0) * (1 - sa)
        local mb = sc.b * sa + (bgc.b or 0) * (1 - sa)
        segs[#segs+1] = string.format("|cff%02x%02x%02x%s|r",
            math.floor(mr * 255 + 0.5), math.floor(mg * 255 + 0.5), math.floor(mb * 255 + 0.5),
            table.concat(stats, " / "))
    end
    return table.concat(segs, "  ")
end

-- 미리보기용: 본인 정보 + 현재 표시항목 설정 반영 (실제와 동일한 형식)
local function SA_PartyPreviewText()
    local pa = MimDiceDB and MimDiceDB.partyAlert
    if not pa then return "" end
    local nm = UnitName("player") or "밈주머니"
    local _, cls = UnitClass("player")
    local disp = nm
    if cls and C_ClassColor then
        local c = C_ClassColor.GetClassColor(cls)
        if c then disp = "|c" .. c:GenerateHexColor() .. nm .. "|r" end
    end
    local specStr = ""
    if pa.showSpec and GetSpecialization then
        local si = GetSpecialization()
        if si then
            local _sid, sname, _desc, sicon = GetSpecializationInfo(si)
            if sname then
                if sicon then
                    local isz = math.floor((pa.fontSize or 30) * 0.7 + 0.5)
                    specStr = "|T" .. sicon .. ":" .. isz .. ":" .. isz .. ":0:0:64:64:5:59:5:59|t "
                end
                specStr = specStr .. sname .. " "
            end
        end
    end
    local stats = {}
    if pa.showItemLevel then
        -- 본인 실제 장착 템렙 (조회 실패 시 620)
        local il = 620
        local okI, _overall, equipped = pcall(GetAverageItemLevel)
        if okI and type(equipped) == "number" and equipped > 0 then il = math.floor(equipped) end
        stats[#stats+1] = "템렙" .. il
    end
    if pa.showScore then
        -- 본인 실제 쐐기점수 (조회 실패 시 2450)
        local sc
        local okS, summary = pcall(function()
            return C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary
               and C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
        end)
        if okS and summary and type(summary.currentSeasonScore) == "number" then
            sc = summary.currentSeasonScore
        end
        if not sc then
            local okC, s2 = pcall(function()
                return C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore
                   and C_ChallengeMode.GetOverallDungeonScore()
            end)
            if okC and type(s2) == "number" then sc = s2 end
        end
        stats[#stats+1] = "쐐기 " .. math.floor(sc or 2450) .. " 점"
    end
    local segs = {}
    if specStr ~= "" then segs[#segs+1] = (specStr:gsub("%s+$", "")) end
    if pa.showName ~= false then segs[#segs+1] = disp end
    if #stats > 0 then
        local sc = pa.statColor or { r = 1, g = 1, b = 1 }
        -- 글자 일부만 진짜 투명하게는 안 되므로, 투명도만큼 배경색 쪽으로 섞어서 표현
        local sa = pa.statColorA or 1
        local bgc = pa.bgColor or { r = 0, g = 0, b = 0 }
        local mr = sc.r * sa + (bgc.r or 0) * (1 - sa)
        local mg = sc.g * sa + (bgc.g or 0) * (1 - sa)
        local mb = sc.b * sa + (bgc.b or 0) * (1 - sa)
        segs[#segs+1] = string.format("|cff%02x%02x%02x%s|r",
            math.floor(mr * 255 + 0.5), math.floor(mg * 255 + 0.5), math.floor(mb * 255 + 0.5),
            table.concat(stats, " / "))
    end
    return table.concat(segs, "  ")
end

local function SA_EnsurePartyFrame()
    if SA_PartyFrame then return SA_PartyFrame end
    local f = CreateFrame("Frame", "MimDice_PartyAlertFrame", UIParent)
    f:SetSize(600, 60)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    if f.SetPropagateMouseClicks then f:SetPropagateMouseClicks(true) end

    local function savePos(self)
        local x, y = self:GetCenter(); local cx, cy = UIParent:GetCenter()
        if x and cx and MimDiceDB.partyAlert then
            MimDiceDB.partyAlert.x = x - cx
            MimDiceDB.partyAlert.y = y - cy
        end
        if SA_PartyConfig and SA_PartyConfig:IsShown() and SA_PartyConfig.posRefresh then
            SA_PartyConfig.posRefresh()
        end
    end
    f:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and MimDiceDB.partyAlert and not MimDiceDB.partyAlert.locked then
            self:StartMoving(); self.moving = true
        end
    end)
    f:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing(); self.moving = false; savePos(self) end)
    f:SetScript("OnUpdate", function(self) if self.moving then savePos(self) end end)

    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER")
    -- 기본 폰트 필수: 프레임을 로그인 시 미리 생성하므로, 알림 표시 전에
    -- SetText("")(숨김 정리)가 먼저 불리면 "Font not set" 에러가 남 (표시 시 설정값으로 다시 SetFont)
    fs:SetFont(MimDiceFontPath(), 30, "THICKOUTLINE")
    fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(2, -2)
    f.text = fs

    -- 배경: 텍스트 크기에 맞춰 전체를 감싸는 반투명 검정 (가독성). 항상 표시.
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", fs, "TOPLEFT", -14, 8)
    bg:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 14, -8)
    bg:SetColorTexture(0, 0, 0, 0.5)
    f.bg = bg

    -- 프레임(드래그 판정 영역)을 배경 박스와 일치시킴 — 텍스트 변경 후마다 호출
    -- (프레임이 고정 600x60이면 글자가 길 때 가운데만 드래그되는 버그처럼 보임)
    function f.FitToText()
        local w = (fs:GetStringWidth() or 0) + 28   -- bg 좌우 여백 14+14
        local h = (fs:GetStringHeight() or 0) + 16  -- bg 상하 여백 8+8
        f:SetSize(math.max(w, 40), math.max(h, 24))
    end

    -- 편집(위치잡기)용 노란 "테두리"만 (내부 채움 없음). 평소엔 숨김. bg 둘레 4변.
    local T = 3
    local eb = {}
    for _, k in ipairs({ "top", "bottom", "left", "right" }) do
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 0.82, 0, 1)
        t:Hide()
        eb[k] = t
    end
    eb.top:SetPoint("TOPLEFT", bg, "TOPLEFT", -2, 2)
    eb.top:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 2, 2); eb.top:SetHeight(T)
    eb.bottom:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", -2, -2)
    eb.bottom:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 2, -2); eb.bottom:SetHeight(T)
    eb.left:SetPoint("TOPLEFT", bg, "TOPLEFT", -2, 2)
    eb.left:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", -2, -2); eb.left:SetWidth(T)
    eb.right:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 2, 2)
    eb.right:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 2, -2); eb.right:SetWidth(T)
    f.editBorder = eb
    function f.SetEditBorder(_, shown)
        for _, t in pairs(eb) do if shown then t:Show() else t:Hide() end end
    end

    local ag = f:CreateAnimationGroup()
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1); fade:SetToAlpha(0); fade:SetDuration(1)
    f.fadeAnim = ag; f.fade = fade
    ag:SetScript("OnFinished", function()
        f.text:SetText(""); f:SetAlpha(0)
        if not InCombatLockdown() then f:EnableMouse(false) end
        f:Hide()
    end)

    f:Hide()   -- 로그인 시 미리 생성되므로 명시적으로 숨김 (표시는 Show 경로에서만)
    SA_PartyFrame = f
    return f
end

-- 화면에 파티 신청 알림 표시 (+사운드). preview=true면 마스터 off여도 미리보기
-- appID: 표시할 신청자 ID (실제 알림에서 새 신청자를 특정. nil이면 마지막 표시자/목록 마지막)
local function SA_ShowPartyAlert(preview, appID)
    local pa = MimDiceDB and MimDiceDB.partyAlert
    if not pa then return end
    if not preview and not pa.enabled then return end
    -- 테스트 중복 방지: 표시 유지시간 동안 재클릭 무시 (소리 겹침 방지. 실제 알림은 항상 통과)
    if preview then
        local now = GetTime()
        if now < SA_paTestUntil then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cffffff00[MimDice]|r 테스트 재생 중입니다 (%.0f초 남음)", SA_paTestUntil - now))
            return
        end
        SA_paTestUntil = now + (pa.duration or 4)
    end

    local f = SA_EnsurePartyFrame()
    -- 실제 알림 배경: 검정 반투명 (사용자 지정 알파). 알파 0이면 사실상 배경 없음. 편집 테두리는 숨김
    f.bg:SetColorTexture((pa.bgColor and pa.bgColor.r) or 0, (pa.bgColor and pa.bgColor.g) or 0, (pa.bgColor and pa.bgColor.b) or 0, pa.bgAlpha or 0.5); f.bg:Show()
    f:SetEditBorder(false)
    if not InCombatLockdown() then f:EnableMouse(false) end
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", pa.x or 0, pa.y or 400)
    f.text:SetFont(MimDiceFontPath(), pa.fontSize or 30, "THICKOUTLINE")

    local col = pa.color or { r = 0.3, g = 1, b = 0.3 }
    local hex = string.format("%02x%02x%02x", (col.r or 0.3)*255, (col.g or 1)*255, (col.b or 0.3)*255)
    local msg = "|cff" .. hex .. (pa.prefix or "새 파티 신청!") .. "|r"
    local info = preview and SA_PartyPreviewText() or SA_PartyApplicantText(appID)
    if info and info ~= "" then msg = msg .. "  " .. info end
    f.text:SetText(msg)
    f.text:SetAlpha(pa.colorA or 1)
    f.FitToText()

    f.fadeAnim:Stop(); f:SetAlpha(1); f:Show()
    -- 표시 지속: "stay"(실제 알림) 이면 페이드 없이 계속 표시 (대기 신청자 0되면 SA_CheckPartyApplicants가 숨김)
    -- preview(테스트)는 화면에 남지 않도록 항상 페이드
    if preview or pa.displayMode ~= "stay" then
        f.fade:SetStartDelay(pa.duration or 4); f.fadeAnim:Play()
    end

    -- 사운드 (preview면 강제 재생)
    if preview then
        local was = pa.enabled; pa.enabled = true
        SA_PlaySound(pa, "Dialog"); pa.enabled = was
    else
        SA_PlaySound(pa, "Dialog")
    end
end

-- 위치 편집용 정적 미리보기 (페이드 없이 계속 표시)
local function SA_RenderPartyPreview()
    local pa = MimDiceDB and MimDiceDB.partyAlert
    if not pa then return end
    local f = SA_EnsurePartyFrame()
    -- 편집(위치잡기): 실제 배경(검정 반투명, 알파 그대로)은 유지 + 노란 테두리만 둘러 이동가능 표시
    f.bg:SetColorTexture((pa.bgColor and pa.bgColor.r) or 0, (pa.bgColor and pa.bgColor.g) or 0, (pa.bgColor and pa.bgColor.b) or 0, pa.bgAlpha or 0.5); f.bg:Show()
    f:SetEditBorder(true)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", pa.x or 0, pa.y or 400)
    f.text:SetFont(MimDiceFontPath(), pa.fontSize or 30, "THICKOUTLINE")
    local col = pa.color or { r = 0.3, g = 1, b = 0.3 }
    local hex = string.format("%02x%02x%02x", (col.r or 0.3)*255, (col.g or 1)*255, (col.b or 0.3)*255)
    local info = SA_PartyPreviewText()
    local msg = "|cff" .. hex .. (pa.prefix or "새 파티 신청!") .. "|r"
    if info and info ~= "" then msg = msg .. "  " .. info end
    f.text:SetText(msg)
    f.text:SetAlpha(pa.colorA or 1)
    f.FitToText()
    f.fadeAnim:Stop(); f:SetAlpha(1); f:Show()
end

-- 위치 잠금 상태 반영 (잠금해제=편집 정적표시+드래그, 잠금=숨김)
local function SA_UpdatePartyFrame()
    local pa = MimDiceDB and MimDiceDB.partyAlert
    if not pa then return end
    local f = SA_EnsurePartyFrame()
    if not pa.locked then
        SA_RenderPartyPreview()
        if not InCombatLockdown() then f:EnableMouse(true) end
    else
        f:SetEditBorder(false)   -- 잠금 시 편집 테두리 제거
        if not InCombatLockdown() then f:EnableMouse(false) end
        if not f.fadeAnim:IsPlaying() then f.text:SetText(""); f:Hide() end
    end
end

-- 설정 변경 시: 잠금해제(편집) 중이면 미리보기 즉시 갱신
local function SA_PartyRefreshPreview()
    local pa = MimDiceDB and MimDiceDB.partyAlert
    if pa and not pa.locked then SA_RenderPartyPreview() end
end

-- 파티 알림 프레임 즉시 숨김 (stay 모드 잔상 제거용)
local function SA_HidePartyFrame()
    local f = SA_PartyFrame
    if f then f.fadeAnim:Stop(); f.text:SetText(""); f:Hide() end
end

-- 반복 알림 티커 중지
local function SA_StopPartyRepeat()
    if SA_partyRepeatTicker then SA_partyRepeatTicker:Cancel(); SA_partyRepeatTicker = nil end
    SA_partyRepeatInterval = nil
end

-- 초대 권한 확인: 솔로(내가 모집 등록자) / 파티장·공대장 / 공대부관만 신청자를 처리할 수 있음
-- 일반 파티원·공대원에게도 LFG_LIST_APPLICANT_LIST_UPDATED 이벤트가 오므로 여기서 걸러야 함
local function SA_PartyCanInvite()
    if not IsInGroup() then return true end   -- 그룹 밖 = 모집 글 주인 본인
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

-- 반복 알림 티커 상태 재평가 (신청자 변화·설정 변경 시 호출)
-- repeat 모드 + 대기 신청자 있음 → repeatInterval초마다 재알림. 아니면 중지.
local function SA_UpdatePartyRepeat()
    local pa = MimDiceDB and MimDiceDB.partyAlert
    if not pa or not pa.enabled or pa.repeatMode ~= "repeat" or not C_LFGList
       or (not pa.alertAnyRole and not SA_PartyCanInvite()) then
        SA_StopPartyRepeat(); return
    end
    local ok, count = pcall(C_LFGList.GetNumApplicants)
    if not ok or type(count) ~= "number" or count <= 0 then SA_StopPartyRepeat(); return end
    local interval = math.max(1, pa.repeatInterval or 5)
    if SA_partyRepeatTicker and SA_partyRepeatInterval == interval then return end  -- 이미 동일 간격 동작 중
    SA_StopPartyRepeat()
    SA_partyRepeatInterval = interval
    SA_partyRepeatTicker = C_Timer.NewTicker(interval, function()
        local p = MimDiceDB and MimDiceDB.partyAlert
        if not p or not p.enabled or p.repeatMode ~= "repeat" or not C_LFGList
           or (not p.alertAnyRole and not SA_PartyCanInvite()) then SA_StopPartyRepeat(); return end
        local ok2, c2 = pcall(C_LFGList.GetNumApplicants)
        if not ok2 or type(c2) ~= "number" or c2 <= 0 then
            SA_StopPartyRepeat()
            if p.locked ~= false then SA_HidePartyFrame() end   -- 대기 신청자 없어짐 → 잔상 제거
            return
        end
        SA_ShowPartyAlert(false)   -- 재알림 (글자 + 사운드)
    end)
end

-- LFG 새 신청자 감지 (초대 권한자만: 솔로 모집자/파티장/공대장/부관)
-- 신청자 수 증가가 아니라 "처음 보는 applicantID"로 판정 → 목록 순서/동시 신청/교체에도 정확
local function SA_CheckPartyApplicants()
    local pa = MimDiceDB and MimDiceDB.partyAlert
    if not pa or not pa.enabled then SA_StopPartyRepeat(); return end
    -- 초대 권한자만 알림 (옵션: 일반 파티원/공대원도 받기)
    if not pa.alertAnyRole and not SA_PartyCanInvite() then SA_StopPartyRepeat(); return end
    if not C_LFGList then return end
    local ok, apps = pcall(C_LFGList.GetApplicants)
    if not ok or type(apps) ~= "table" then return end
    local count = #apps

    -- 새 신청자 = SA_paSeen에 없는 ID (여러 명 동시면 마지막 새 ID로 표시)
    local present, newID = {}, nil
    for _, id in ipairs(apps) do
        present[id] = true
        if not SA_paSeen[id] then
            SA_paSeen[id] = true
            newID = id
        end
    end
    -- 목록에서 사라진 ID 정리 (취소 후 재신청도 새 신청으로 다시 감지됨)
    for id in pairs(SA_paSeen) do
        if not present[id] then SA_paSeen[id] = nil end
    end

    if newID then
        SA_paLastShownID = newID
        SA_ShowPartyAlert(false, newID)
    end
    SA_paLastCount = count
    if count <= 0 then
        -- 대기 신청자 없음: 반복 중지 + (편집중이 아니면) stay 잔상 숨김
        SA_StopPartyRepeat()
        SA_paLastShownID = nil
        if pa.locked ~= false then SA_HidePartyFrame() end
    else
        SA_UpdatePartyRepeat()   -- 반복 모드면 티커 유지/시작
    end
end

-- 5인 풀파티 감지: 파티 인원이 5명이 되는 순간 소리 + 와우 작업표시줄 아이콘 반짝임
-- (공격대는 제외. 로그인 시 이미 5인이면 울리지 않도록 기준 인원을 로그인 때 동기화)
local SA_paLastGroupSize = 0
local function SA_SyncGroupSize()
    SA_paLastGroupSize = GetNumGroupMembers() or 0
end
local function SA_CheckFullParty()
    local n = GetNumGroupMembers() or 0
    local pa = MimDiceDB and MimDiceDB.partyAlert
    local fp = pa and pa.fullParty
    if fp and fp.enabled and n == 5 and SA_paLastGroupSize < 5 and not IsInRaid() then
        SA_PlaySound(fp, "Dialog")
        if FlashClientIcon then FlashClientIcon() end   -- 백그라운드면 작업표시줄 와우 아이콘 반짝
    end
    SA_paLastGroupSize = n
end

-- 임시 테스트/토글 슬래시 (옵션창 UI 통합 전 검증용): /밈파티 , /밈파티 test
SLASH_MIMPARTY1 = "/밈파티"
SLASH_MIMPARTY2 = "/mimparty"
SlashCmdList["MIMPARTY"] = function(msg)
    local pa = MimDiceDB and MimDiceDB.partyAlert
    if not pa then return end
    if msg == "test" then
        SA_ShowPartyAlert(true)   -- 미리보기 (마스터 off여도 표시)
        return
    end
    if msg == "dump" then
        -- 진단: 최근 신청자의 GetApplicantMemberInfo 전체 반환값 출력
        -- (특성 specID / 던전별 단수 필드가 있는지 확인용)
        if not C_LFGList then DEFAULT_CHAT_FRAME:AddMessage("[MimDice] C_LFGList 없음") return end
        local ok, apps = pcall(C_LFGList.GetApplicants)
        if not ok or type(apps) ~= "table" or #apps == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("[MimDice] 신청자 없음 (파티 모집 중 신청 받은 상태에서 실행하세요)")
            return
        end
        local id = apps[#apps]
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MimDice] 신청자 정보 덤프|r (appID " .. tostring(id) .. ")")
        local okD, dump = pcall(function()
            return strjoin(" | ", tostringall(C_LFGList.GetApplicantMemberInfo(id, 1)))
        end)
        DEFAULT_CHAT_FRAME:AddMessage(okD and tostring(dump) or "덤프 실패(secret value 등)")
        -- 활동(모집 던전) 정보도 함께
        local okA, aid = pcall(function()
            local e = C_LFGList.GetActiveEntryInfo and C_LFGList.GetActiveEntryInfo()
            return e and e.activityID
        end)
        if okA and aid then DEFAULT_CHAT_FRAME:AddMessage("[MimDice] 내 모집 activityID: " .. tostring(aid)) end
        return
    end
    pa.enabled = not pa.enabled
    if not pa.enabled then
        -- 끌 때 정리: 반복 티커 중지 + (편집중 아니면) 계속표시(stay) 잔상 제거
        SA_StopPartyRepeat()
        if pa.locked ~= false then SA_HidePartyFrame() end
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MimDice]|r 파티 신청 알림: " .. (pa.enabled and "켜짐" or "꺼짐"))
end

-- =====================================================================
-- 파티 신청 알림 설정창 (죽음 알림 패턴 복제 + 표시항목 체크)
-- =====================================================================
local function SA_CreatePartyConfig()
    if SA_PartyConfig then return SA_PartyConfig end

    local win = CreateFrame("Frame", "MimDice_PartyConfig", UIParent, "BackdropTemplate")
    win:SetSize(340, 554)
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
    win:EnableMouse(true); win:SetMovable(true)   -- 클램프 없음: 메인창처럼 화면 밖 이동 가능
    -- 설정창을 잡고 끌면 본체(MainWindow)가 점프 없이 한 덩어리로 이동
    SA_WireBundleDrag(win)
    -- 설정창을 닫으면(X/ESC/연쇄) 사운드 팝업 닫기 + 위치 자동 잠금
    win:SetScript("OnHide", function()
        if SA_SoundPicker then SA_SoundPicker:Hide() end
        local pa = MimDiceDB and MimDiceDB.partyAlert
        if pa and not pa.locked then
            pa.locked = true
            SA_UpdatePartyFrame()   -- 편집 표시 정리
        end
    end)

    local title = win:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", win, "TOP", 0, -12)
    title:SetFont(MimDiceFontPath(), 13, "OUTLINE")
    title:SetText("파티 신청 알림 설정 (공용)")
    title:SetTextColor(1, 0.82, 0)

    local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    closeBtn.MimDiceIsClose = true   -- 스킨: 닫기(X) 플랫화 대상
    closeBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() win:Hide() end)

    -- ── 재생 사운드 ─────────────────────────
    local soundLabel = win:CreateFontString(nil, "OVERLAY")
    soundLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -36)
    soundLabel:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    soundLabel:SetText("재생 사운드 : 아래 3개 중 하나 선택")
    soundLabel:SetTextColor(0.9, 0.9, 0.9)

    win.typeRefresh = SA_MakeTypeSelector(win, 15, -56,
        function() return MimDiceDB.partyAlert.soundType end,
        function(t) MimDiceDB.partyAlert.soundType = t; win.RefreshSoundRow() end)

    local soundBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    soundBox:SetSize(135, 22)
    soundBox:SetPoint("TOPLEFT", win, "TOPLEFT", 157, -56)
    soundBox:SetAutoFocus(false); soundBox:SetFont(MimDiceFontPath(), 11, "")
    win.soundBox = soundBox
    SA_WirePlaceholder(soundBox)

    local soundSelectBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    soundSelectBtn:SetSize(135, 22)
    soundSelectBtn:SetPoint("TOPLEFT", win, "TOPLEFT", 157, -56)
    do
        local fs = soundSelectBtn:GetFontString()
        fs:SetFont(MimDiceFontPath(), 10, ""); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        fs:ClearAllPoints(); fs:SetPoint("LEFT", 6, 0); fs:SetPoint("RIGHT", -6, 0)
    end
    win.soundSelectBtn = soundSelectBtn
    soundSelectBtn:SetScript("OnClick", function()
        SA_OpenSoundPicker(soundSelectBtn,
            function() return MimDiceDB.partyAlert.soundKey end,
            function(snd)
                local pa = MimDiceDB.partyAlert
                pa.soundType = "preset"; pa.soundKey = snd.id; pa.soundName = snd.name
                win.RefreshSoundRow()
                local was = pa.enabled; pa.enabled = true
                SA_PlaySound(pa, "Dialog"); pa.enabled = was
            end)
    end)

    local soundTestBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    soundTestBtn:SetSize(24, 22)
    soundTestBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -15, -56)
    soundTestBtn:SetText("▶")
    soundTestBtn:SetScript("OnClick", function()
        local pa = MimDiceDB.partyAlert
        local was = pa.enabled; pa.enabled = true
        SA_PlaySound(pa, "Dialog"); pa.enabled = was
    end)

    function win.RefreshSoundRow()
        local pa = MimDiceDB.partyAlert
        win.typeRefresh()
        if pa.soundType == "preset" then
            soundLabel:SetText("내장: 아래에서 사운드 선택 (▶ 미리듣기)")
            soundSelectBtn:Show(); soundBox:Hide()
            soundSelectBtn:SetText(pa.soundName or "사운드 선택...")
        elseif pa.soundType == "id" then
            soundLabel:SetText("ID: 사운드 숫자 ID를 직접 입력")
            soundSelectBtn:Hide(); soundBox:Show()
            SA_SetBoxValue(soundBox, pa.soundID, "예: 567458")
        else
            soundLabel:SetText("커스텀: sounds폴더 파일명 그대로 입력")
            soundSelectBtn:Hide(); soundBox:Show()
            SA_SetBoxValue(soundBox, pa.soundFile, "예: MySound.mp3")
        end
    end
    soundBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local pa = MimDiceDB.partyAlert
        if pa.soundType == "id" then pa.soundID = tonumber(self:GetText()) or self:GetText()
        else pa.soundFile = self:GetText() end
    end)
    soundBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- ── 구분선 + 5인 풀파티 + [상세 설정] : 상세 설정 버튼은 항상 제일 아래 ──
    local sep = win:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(0.5, 0.5, 0.5, 0.4)
    sep:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -88)
    sep:SetPoint("TOPRIGHT", win, "TOPRIGHT", -15, -88)
    sep:SetHeight(1)
    local fpg = CreateFrame("Frame", nil, win)   -- 5인 풀파티 묶음 (구분선 아래 고정)
    fpg:SetHeight(56)
    fpg:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -96)
    fpg:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, -96)
    local advBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    advBtn:SetSize(310, 22)
    advBtn:SetPoint("TOP", win, "TOP", 0, -172)
    advBtn:GetFontString():SetFont(MimDiceFontPath(), 10, "")
    local adv = CreateFrame("Frame", nil, win)   -- 상세 위젯 컨테이너 ([상세 설정] 버튼 아래)
    adv:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -118)
    adv:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)

    -- ── 문구 입력 (prefix) ──
    local prefixLabel = adv:CreateFontString(nil, "OVERLAY")
    prefixLabel:SetPoint("TOPLEFT", adv, "TOPLEFT", 15, -84)
    prefixLabel:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    prefixLabel:SetText("화면 문구 (예: 새 파티 신청!)")
    prefixLabel:SetTextColor(0.9, 0.9, 0.9)
    local prefixBox = CreateFrame("EditBox", nil, adv, "InputBoxTemplate")
    prefixBox:SetSize(200, 22)
    prefixBox:SetPoint("TOPLEFT", adv, "TOPLEFT", 20, -104)
    prefixBox:SetAutoFocus(false); prefixBox:SetFont(MimDiceFontPath(), 12, "")
    prefixBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then MimDiceDB.partyAlert.prefix = self:GetText(); SA_PartyRefreshPreview() end
    end)
    prefixBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    win.prefixBox = prefixBox

    -- ── 표시 항목 체크 (특성 / 아이템렙 / 쐐기점수) ──
    local itemLabel = adv:CreateFontString(nil, "OVERLAY")
    itemLabel:SetPoint("TOPLEFT", adv, "TOPLEFT", 15, -132)
    itemLabel:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    itemLabel:SetText("표시 항목")
    itemLabel:SetTextColor(0.9, 0.9, 0.9)

    local function mkShowCb(x, field, text)
        local cb = CreateFrame("CheckButton", nil, adv, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", adv, "TOPLEFT", x, -148)
        cb:SetScript("OnClick", function(self)
            MimDiceDB.partyAlert[field] = self:GetChecked() and true or false
            SA_PartyRefreshPreview()
        end)
        local lb = adv:CreateFontString(nil, "OVERLAY")
        lb:SetPoint("LEFT", cb, "RIGHT", 0, 0)
        lb:SetFont(MimDiceFontPath(), 10, "OUTLINE")
        lb:SetText(text); lb:SetTextColor(0.9, 0.9, 0.9)
        return cb
    end
    win.nameCb  = mkShowCb(15,  "showName",      "닉네임")
    win.specCb  = mkShowCb(85,  "showSpec",      "특성")
    win.ilvlCb  = mkShowCb(140, "showItemLevel", "아이템렙")
    win.scoreCb = mkShowCb(225, "showScore",     "쐐기점수")

    -- ── 글씨 크기 ──
    win.sizeSlider = SA_MakeNumberSlider(adv, "MimDice_PartySizeSlider", -180, "글씨 크기", 12, 120,
        function() return MimDiceDB.partyAlert.fontSize end,
        function(v) MimDiceDB.partyAlert.fontSize = v end,
        function() SA_PartyRefreshPreview() end)

    -- ── 문구 색상 (색상환 풀 팔레트 + 코드 입력 + 기본색) ──
    win.colorRefresh = SA_MakeColorRow(adv, -268, "문구 색상",
        function() return MimDiceDB.partyAlert.color end,
        function(r, g, b) MimDiceDB.partyAlert.color = { r = r, g = g, b = b } end,
        { 0.3, 1, 0.3 },
        function() SA_PartyRefreshPreview() end,
        {
            get = function() return MimDiceDB.partyAlert.colorA or 1 end,
            set = function(a) MimDiceDB.partyAlert.colorA = a end,
        })

    -- ── 템렙/쐐기 글자색 ──
    win.statColorRefresh = SA_MakeColorRow(adv, -294, "템렙/쐐기 색상",
        function() return MimDiceDB.partyAlert.statColor end,
        function(r, g, b) MimDiceDB.partyAlert.statColor = { r = r, g = g, b = b } end,
        { 1, 1, 1 },
        function() SA_PartyRefreshPreview() end,
        {
            get = function() return MimDiceDB.partyAlert.statColorA or 1 end,
            set = function(a) MimDiceDB.partyAlert.statColorA = a end,
        })

    -- ── 배경 색상 (색상환의 투명도 슬라이더 = 배경 투명도와 연동) ──
    win.bgColorRefresh = SA_MakeColorRow(adv, -320, "배경 색상",
        function() return MimDiceDB.partyAlert.bgColor end,
        function(r, g, b) MimDiceDB.partyAlert.bgColor = { r = r, g = g, b = b } end,
        { 0, 0, 0 },
        function() SA_PartyRefreshPreview() end,
        {
            get = function() return MimDiceDB.partyAlert.bgAlpha or 0.5 end,
            set = function(a) MimDiceDB.partyAlert.bgAlpha = a end,
        })


    -- ── 알림 방식: 반복 알림 / 표시 지속 ──
    -- 반복 알림(놓침 방지): 켜면 대기 신청자가 있는 동안 N초마다 재알림, 끄면 신청 올 때 1회만
    local repeatCb = CreateFrame("CheckButton", nil, adv, "UICheckButtonTemplate")
    repeatCb:SetSize(22, 22)
    repeatCb:SetPoint("TOPLEFT", adv, "TOPLEFT", 15, -352)
    local repeatLb = adv:CreateFontString(nil, "OVERLAY")
    repeatLb:SetPoint("LEFT", repeatCb, "RIGHT", 0, 0)
    repeatLb:SetFont(MimDiceFontPath(), 10, "OUTLINE")
    repeatLb:SetText("반복 알림"); repeatLb:SetTextColor(0.9, 0.9, 0.9)
    local repeatBox = CreateFrame("EditBox", nil, adv, "InputBoxTemplate")
    repeatBox:SetSize(38, 20)
    repeatBox:SetPoint("LEFT", repeatCb, "RIGHT", 58, 0)
    repeatBox:SetAutoFocus(false); repeatBox:SetFont(MimDiceFontPath(), 11, "")
    repeatBox:SetNumeric(true); repeatBox:SetMaxLetters(3); repeatBox:SetJustifyH("CENTER")
    local repeatSuffix = adv:CreateFontString(nil, "OVERLAY")
    repeatSuffix:SetPoint("LEFT", repeatBox, "RIGHT", 6, 0)
    repeatSuffix:SetFont(MimDiceFontPath(), 10, "OUTLINE")
    repeatSuffix:SetText("초마다 (끄면 1회만)"); repeatSuffix:SetTextColor(0.7, 0.7, 0.7)
    repeatCb:SetScript("OnClick", function(self)
        MimDiceDB.partyAlert.repeatMode = self:GetChecked() and "repeat" or "once"
        SA_StopPartyRepeat(); SA_UpdatePartyRepeat()
    end)
    repeatBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local v = tonumber(self:GetText())
        if v and v >= 1 then
            MimDiceDB.partyAlert.repeatInterval = v
            SA_StopPartyRepeat(); SA_UpdatePartyRepeat()
        end
    end)
    repeatBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    win.repeatCb = repeatCb; win.repeatBox = repeatBox

    -- 표시 지속: 켜면 N초 뒤 페이드아웃, 끄면 대기 신청자 없어질 때까지 계속 표시
    local displayCb = CreateFrame("CheckButton", nil, adv, "UICheckButtonTemplate")
    displayCb:SetSize(22, 22)
    displayCb:SetPoint("TOPLEFT", adv, "TOPLEFT", 15, -380)
    local displayLb = adv:CreateFontString(nil, "OVERLAY")
    displayLb:SetPoint("LEFT", displayCb, "RIGHT", 0, 0)
    displayLb:SetFont(MimDiceFontPath(), 10, "OUTLINE")
    displayLb:SetText("자동 숨김"); displayLb:SetTextColor(0.9, 0.9, 0.9)
    local durationBox = CreateFrame("EditBox", nil, adv, "InputBoxTemplate")
    durationBox:SetSize(38, 20)
    durationBox:SetPoint("LEFT", displayCb, "RIGHT", 58, 0)
    durationBox:SetAutoFocus(false); durationBox:SetFont(MimDiceFontPath(), 11, "")
    durationBox:SetNumeric(true); durationBox:SetMaxLetters(3); durationBox:SetJustifyH("CENTER")
    local durationSuffix = adv:CreateFontString(nil, "OVERLAY")
    durationSuffix:SetPoint("LEFT", durationBox, "RIGHT", 6, 0)
    durationSuffix:SetFont(MimDiceFontPath(), 10, "OUTLINE")
    durationSuffix:SetText("초 뒤 (끄면 계속표시)"); durationSuffix:SetTextColor(0.7, 0.7, 0.7)
    displayCb:SetScript("OnClick", function(self)
        MimDiceDB.partyAlert.displayMode = self:GetChecked() and "fade" or "stay"
    end)
    durationBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local v = tonumber(self:GetText())
        if v and v >= 1 then MimDiceDB.partyAlert.duration = v end
    end)
    durationBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    win.displayCb = displayCb; win.durationBox = durationBox

    -- ── 파티장이 아니어도 알림 받기 ──
    local anyRoleCb = CreateFrame("CheckButton", nil, adv, "UICheckButtonTemplate")
    anyRoleCb:SetSize(22, 22)
    anyRoleCb:SetPoint("TOPLEFT", adv, "TOPLEFT", 15, -408)
    local anyRoleLb = adv:CreateFontString(nil, "OVERLAY")
    anyRoleLb:SetPoint("LEFT", anyRoleCb, "RIGHT", 0, 0)
    anyRoleLb:SetFont(MimDiceFontPath(), 10, "OUTLINE")
    anyRoleLb:SetText("파티장/공대장/부공대장이 아닐 때도 알림 받기")
    anyRoleLb:SetTextColor(0.9, 0.9, 0.9)
    anyRoleCb:SetScript("OnClick", function(self)
        MimDiceDB.partyAlert.alertAnyRole = self:GetChecked() and true or false
    end)
    win.anyRoleCb = anyRoleCb

    -- ── 5인 풀파티 알림 (소리 + 와우 작업표시줄 아이콘 반짝임) ──
    local fpCb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    fpCb:SetSize(22, 22)
    fpCb:SetPoint("TOPLEFT", fpg, "TOPLEFT", 15, -2)
    local fpLb = win:CreateFontString(nil, "OVERLAY")
    fpLb:SetPoint("LEFT", fpCb, "RIGHT", 0, 0)
    fpLb:SetFont(MimDiceFontPath(), 10, "OUTLINE")
    fpLb:SetText("5인 풀파티 완성 알림 (소리 + 와우 아이콘 반짝임)")
    fpLb:SetTextColor(0.9, 0.9, 0.9)
    fpCb:SetScript("OnClick", function(self)
        MimDiceDB.partyAlert.fullParty.enabled = self:GetChecked() and true or false
    end)
    win.fpCb = fpCb

    -- 풀파티 사운드 선택 (내장/커스텀/ID)
    win.fpTypeRefresh = SA_MakeTypeSelector(fpg, 15, -30,
        function() return MimDiceDB.partyAlert.fullParty.soundType end,
        function(t) MimDiceDB.partyAlert.fullParty.soundType = t; win.RefreshFpSoundRow() end)

    local fpSoundBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    fpSoundBox:SetSize(135, 22)
    fpSoundBox:SetPoint("TOPLEFT", fpg, "TOPLEFT", 157, -30)
    fpSoundBox:SetAutoFocus(false); fpSoundBox:SetFont(MimDiceFontPath(), 11, "")
    win.fpSoundBox = fpSoundBox
    SA_WirePlaceholder(fpSoundBox)

    local fpSelectBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    fpSelectBtn:SetSize(135, 22)
    fpSelectBtn:SetPoint("TOPLEFT", fpg, "TOPLEFT", 157, -30)
    do
        local fs = fpSelectBtn:GetFontString()
        fs:SetFont(MimDiceFontPath(), 10, ""); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        fs:ClearAllPoints(); fs:SetPoint("LEFT", 6, 0); fs:SetPoint("RIGHT", -6, 0)
    end
    win.fpSelectBtn = fpSelectBtn
    fpSelectBtn:SetScript("OnClick", function()
        SA_OpenSoundPicker(fpSelectBtn,
            function() return MimDiceDB.partyAlert.fullParty.soundKey end,
            function(snd)
                local fp = MimDiceDB.partyAlert.fullParty
                fp.soundType = "preset"; fp.soundKey = snd.id; fp.soundName = snd.name
                win.RefreshFpSoundRow()
                local was = fp.enabled; fp.enabled = true
                SA_PlaySound(fp, "Dialog"); fp.enabled = was
            end)
    end)

    local fpTestBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    fpTestBtn:SetSize(24, 22)
    fpTestBtn:SetPoint("TOPRIGHT", fpg, "TOPRIGHT", -15, -30)
    fpTestBtn:SetText("▶")
    fpTestBtn:SetScript("OnClick", function()
        local fp = MimDiceDB.partyAlert.fullParty
        local was = fp.enabled; fp.enabled = true
        SA_PlaySound(fp, "Dialog"); fp.enabled = was
    end)

    function win.RefreshFpSoundRow()
        local fp = MimDiceDB.partyAlert.fullParty
        win.fpTypeRefresh()
        if fp.soundType == "preset" then
            fpSelectBtn:Show(); fpSoundBox:Hide()
            fpSelectBtn:SetText(fp.soundName or "사운드 선택...")
        elseif fp.soundType == "id" then
            fpSelectBtn:Hide(); fpSoundBox:Show()
            SA_SetBoxValue(fpSoundBox, fp.soundID, "예: 635496")
        else
            fpSelectBtn:Hide(); fpSoundBox:Show()
            SA_SetBoxValue(fpSoundBox, fp.soundFile, "예: MySound.mp3")
        end
    end
    fpSoundBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local fp = MimDiceDB.partyAlert.fullParty
        if fp.soundType == "id" then fp.soundID = tonumber(self:GetText()) or self:GetText()
        else fp.soundFile = self:GetText() end
    end)
    fpSoundBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- ── 위치 X/Y ──
    local posRefresh, posX, posY = SA_AddPosRow(adv, -236,
        function() return MimDiceDB.partyAlert.x end,
        function(v) MimDiceDB.partyAlert.x = v end,
        function() return MimDiceDB.partyAlert.y end,
        function(v) MimDiceDB.partyAlert.y = v end,
        function() SA_PartyRefreshPreview() end)
    win.posRefresh = posRefresh
    SA_ChainTabEnter({ win.sizeSlider.edit, posX, posY, repeatBox, durationBox })

    -- ── 위치 잠금 / 기본값 / 미리보기 ──
    local lockBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    lockBtn:SetSize(110, 24)
    lockBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 15, 14)
    lockBtn:GetFontString():SetFont(MimDiceFontPath(), 10, "")
    lockBtn:SetScript("OnClick", function()
        local pa = MimDiceDB.partyAlert
        pa.locked = not pa.locked
        SA_UpdatePartyFrame()
        win.RefreshLockBtn()
    end)
    win.lockBtn = lockBtn
    function win.RefreshLockBtn()
        lockBtn:SetText(MimDiceDB.partyAlert.locked and "위치 잠금 해제" or "위치 잠금")
    end

    local resetBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    resetBtn:SetSize(70, 24)
    resetBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 155, 14)   -- 340폭 기준 3버튼(110/70/70) 균등 간격 30px
    resetBtn:SetText("기본값")
    resetBtn:GetFontString():SetFont(MimDiceFontPath(), 11, "")
    resetBtn:SetScript("OnClick", function()
        local pa = MimDiceDB.partyAlert
        pa.fontSize, pa.x, pa.y = 30, 0, 400
        pa.color = { r = 0.3, g = 1, b = 0.3 }
        pa.prefix = "새 파티 신청!"
        pa.showName, pa.showSpec, pa.showItemLevel, pa.showScore = true, true, true, true
        pa.bgAlpha = 0.5
        pa.bgColor = { r = 0, g = 0, b = 0 }
        pa.statColor = { r = 1, g = 1, b = 1 }
        pa.colorA, pa.statColorA = 1, 1
        pa.repeatMode, pa.repeatInterval = "once", 5
        pa.displayMode, pa.duration = "fade", 4
        pa.alertAnyRole = false
        if pa.fullParty then pa.fullParty.enabled = true end
        pa.locked = true
        SA_StopPartyRepeat()
        SA_UpdatePartyFrame()
        SA_RefreshPartyConfig()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MimDice]|r 파티 신청 알림 설정 초기화됨")
    end)

    -- 테스트: 잠금 상태에서도 실제처럼 글자+소리 확인 (본인 정보로 표시, 페이드로 사라짐)
    local testBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    testBtn:SetSize(70, 24)
    testBtn:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -15, 14)
    testBtn:SetText("테스트")
    testBtn:GetFontString():SetFont(MimDiceFontPath(), 11, "")
    testBtn:SetScript("OnClick", function() SA_ShowPartyAlert(true) end)

    -- 상세 설정 접기/펼치기 적용 (상세 내용은 버튼 아래로 펼쳐지고, 접으면 창이 짧아짐)
    local function ApplyAdv()
        local open = MimDiceDB.partyAlert.advOpen and true or false
        adv:SetShown(open)
        win:SetHeight(open and 600 or 246)
        advBtn:SetText(open and "상세 설정 접기" or "상세 설정 열기 : 문구/크기/색/위치/반복")
    end
    win.ApplyAdv = ApplyAdv
    advBtn:SetScript("OnClick", function()
        MimDiceDB.partyAlert.advOpen = not MimDiceDB.partyAlert.advOpen
        ApplyAdv()
    end)
    ApplyAdv()

    win:Hide()
    SA_SkinRegisterWindow(win)   -- 스킨 대상 등록
    SA_PartyConfig = win
    return win
end

-- 현재 설정값을 팝업 위젯에 반영 (전역: reset 버튼에서도 참조)
function SA_RefreshPartyConfig()
    local win = SA_PartyConfig
    if not win then return end
    local pa = MimDiceDB.partyAlert
    win.RefreshSoundRow()
    win.prefixBox:SetText(pa.prefix or "새 파티 신청!")
    win.nameCb:SetChecked(pa.showName ~= false)
    win.specCb:SetChecked(pa.showSpec)
    win.ilvlCb:SetChecked(pa.showItemLevel)
    win.scoreCb:SetChecked(pa.showScore)
    win.repeatCb:SetChecked(pa.repeatMode == "repeat")
    win.repeatBox:SetText(tostring(pa.repeatInterval or 5))
    win.displayCb:SetChecked(pa.displayMode ~= "stay")   -- 자동숨김(fade)=체크, 계속표시(stay)=해제
    win.durationBox:SetText(tostring(pa.duration or 4))
    win.anyRoleCb:SetChecked(pa.alertAnyRole)
    win.fpCb:SetChecked(pa.fullParty and pa.fullParty.enabled)
    win.RefreshFpSoundRow()
    win.sizeSlider.SyncValue()
    win.posRefresh()
    win.RefreshLockBtn()
    win.colorRefresh()       -- 색상 스와치/코드칸 갱신
    win.statColorRefresh()
    win.bgColorRefresh()
end

function SA_TogglePartyConfig()
    local win = SA_CreatePartyConfig()
    if win:IsShown() then
        win:Hide()
    else
        if SA_DeathConfig and SA_DeathConfig:IsShown() then SA_DeathConfig:Hide() end
        for _, w in pairs(SA_BuffConfigs) do if w:IsShown() then w:Hide() end end
        if SA_BattleResIconConfig and SA_BattleResIconConfig:IsShown() then SA_BattleResIconConfig:Hide() end
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", SA_OptionWindow, "TOPRIGHT", 6, 0)
        SA_RefreshPartyConfig()
        win:Show()
    end
end

-- =====================================================================
-- 저렙 귓속말 차단 (재설계 v3: 종료 카운트/타이머 토큰/공통 secret 게이트 수정)
-- 귓속말 이벤트엔 발신자 레벨이 없어서, 발신자를 잠깐 친구로 등록해 친구목록
-- 갱신에서 레벨을 읽고 즉시 삭제하는 방식으로 확인한다.
--
-- 안전/정확성 원칙:
--  * 상태는 단일값 SA_wbState[name]="safe"|"blocked"|"pending". pending 종료는
--    반드시 SA_wbFinishPending(단일 함수)로만 한다(카운트/임시친구/음소거 일괄 정리).
--  * safe = 기준 레벨 이상 실제 확인 / 내가 먼저 귓말한 상대에만 굳힌다.
--    친구.길드.파티.배틀넷 신뢰는 캐싱하지 않고 매 귓말 동적 확인(관계 변화 즉시 반영).
--    blocked.미확인도 매번 동적 신뢰 판정 -> 나중에 친구가 되면 즉시 통과된다.
--    기준 레벨을 바꾸면 SA_WhisperBlockResetJudgments 로 확정 판정을 비운다.
--  * pending 마다 고유 토큰(SA_wbGen[name]). 5초/토스트 타이머는 토큰이 일치할 때만
--    동작 -> 옵션 OFF 후 재개 등으로 생긴 '오래된 타이머'가 새 pending을 오염 못 함.
--  * 필터/이벤트 둘 다 SA_wbReadable로 player/text 접근 가능성을 먼저 확인한다.
--    부가 정보(flag/guid)만 secret이면 그 값만 제외하고 이름 기반 레벨 확인은 계속한다.
--    player/text가 secret이면 이벤트 쪽 판정은 건너뛰되 채팅창에서는 숨긴다.
--  * 채팅 필터는 멱등. 미확인/확인중/차단은 채팅창에서 완전히 숨긴다.
--  * 이벤트/필터 중 채팅 출력 없음(taint 회피). 진단은 링버퍼 + /밈귓로그.
--    친구목록 가득참 등 알림도 전용 토스트 큐로 보낸다.
--  * 정상(만렙)으로 확인된 원문만 전용 토스트(UIParent 독립, FIFO)에 표시.
--    저렙.시간초과 원문은 폐기(첫 줄도 채팅창에는 표시되지 않음).
-- =====================================================================
local SA_WBFrame = CreateFrame("Frame")
local SA_wbState = {}      -- [name] = "safe" | "blocked" | "pending"
local SA_wbStash = {}      -- [name] = { 원문문자열, ... } (검증된 문자열만)
local SA_wbSysHide = {}    -- 이름 -> 만료시각: 확인 중 시스템 문구 숨김
local SA_wbGen = {}        -- [name] = pending 토큰(테이블) : 오래된 타이머 무효화용
local SA_wbRealms = {}     -- 연결된 서버 목록 (친구 등록 = 레벨 확인 가능 범위)
local SA_wbReady = false   -- 로그인 후 친구목록 첫 스캔 완료 여부
local SA_wbPendingCount = 0
local SA_wbDidMute = false   -- 밈다이스가 실제로 소리를 음소거했는지 (소유권)
local SA_WB_NOTE = "밈다이스-레벨확인"                       -- 임시 친구 식별용 메모
local SA_wbLog = {}        -- 진단 링 버퍼 (이벤트 중 채팅 출력 금지)
local SA_WB_LOG_MAX = 80

-- 진단 기록: 링 버퍼에만 (이벤트/필터 중 호출해도 안전). 확인은 /밈귓로그.
local function SA_wbDbg(msg)
    SA_wbLog[#SA_wbLog + 1] = msg
    if #SA_wbLog > SA_WB_LOG_MAX then table.remove(SA_wbLog, 1) end
end

-- 원래부터 믿을 수 있는 상대인지 (동기.순수. 부작용 없음). 호출 전 SA_wbReadable 통과 가정.
local function SA_wbTrusted(name, flag, guid)
    if flag == "GM" or flag == "DEV" then return "GM" end
    if guid then
        local okB, acc = pcall(function()
            return C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID(guid)
        end)
        if okB and acc then return "배틀넷 친구" end
        local okF, fr = pcall(C_FriendList.IsFriend, guid)
        if okF and fr then return "캐릭터 친구" end
        local okG, gm = pcall(IsGuildMember, guid)
        if okG and gm then return "길드원" end
    end
    if UnitInParty(name) or UnitInRaid(name) then return "파티/공대원" end
    return nil
end

-- 공통 secret 게이트: 핵심값(player/text)은 반드시 읽을 수 있어야 한다.
-- 부가값(flag/guid)만 secret이면 nil로 정규화해 이름 기반 판정은 계속한다.
local function SA_wbReadable(player, text, flag, guid)
    if SA_IsSecret(player) or type(player) ~= "string" then return false end
    if text ~= nil and (SA_IsSecret(text) or type(text) ~= "string") then return false end
    if flag ~= nil and SA_IsSecret(flag) then flag = nil end
    if guid ~= nil and SA_IsSecret(guid) then guid = nil end
    return true, flag, guid
end

-- 우리가 등록한 임시 친구(SA_WB_NOTE)만 골라 삭제 (진짜 친구는 안 건드림)
local function SA_wbRemoveTempFriend(name)
    local num = C_FriendList.GetNumFriends() or 0
    for i = num, 1, -1 do
        local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
        if ok and info and info.notes == SA_WB_NOTE and info.name == name then
            pcall(C_FriendList.RemoveFriendByIndex, i)
        end
    end
end

-- pending 종료 단일 함수: 카운트 감소 + stash 반환 + sysHide/토큰/임시친구 정리 + 음소거 복구.
-- 반드시 state 변경을 이 함수 안에서 한다(호출부가 먼저 바꾸면 카운트가 안 줄던 버그 방지).
local function SA_wbFinishPending(name, newState)
    if SA_wbState[name] ~= "pending" then return nil end
    local stash = SA_wbStash[name]
    SA_wbState[name] = newState
    SA_wbPendingCount = math.max(0, SA_wbPendingCount - 1)
    SA_wbStash[name] = nil
    SA_wbSysHide[name] = nil
    SA_wbGen[name] = nil            -- 남은 5초 타이머 무효화
    SA_wbRemoveTempFriend(name)
    if SA_wbPendingCount <= 0 then
        C_Timer.After(2, function()
            if SA_wbPendingCount <= 0 and SA_wbDidMute then
                pcall(UnmuteSoundFile, 567518); SA_wbDidMute = false
            end
        end)
    end
    return stash
end

-- ── 전용 토스트 (UIParent 독립. FIFO 큐. 세대 토큰으로 타이머 무효화) ──
local SA_wbToast
local SA_wbToastQ = {}
local SA_wbToastBusy = false
local SA_wbToastGen = 0
local function SA_wbEnsureToast()
    if SA_wbToast then return SA_wbToast end
    local f = CreateFrame("Frame", "MimDice_WhisperToast", UIParent, "BackdropTemplate")
    f:SetSize(380, 60)
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    f:SetFrameStrata("HIGH")
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetBackdropColor(0, 0, 0, 0.85)
    f:SetBackdropBorderColor(0.4, 0.7, 1, 1)
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetPoint("TOPLEFT", 12, -10)
    f.text:SetPoint("BOTTOMRIGHT", -12, 10)
    f.text:SetJustifyH("LEFT"); f.text:SetJustifyV("TOP")
    f.text:SetSpacing(3)
    local ag = f:CreateAnimationGroup()
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1); fade:SetToAlpha(0); fade:SetDuration(1.2); fade:SetStartDelay(10)
    f.fadeAnim = ag
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self) self.fadeAnim:Stop(); self:SetAlpha(1) end)
    f:SetScript("OnLeave", function(self) self.fadeAnim:Play() end)
    f:Hide()
    SA_wbToast = f
    return f
end
-- UTF-8 안전 자르기 (한글 바이트 중간을 안 자름)
local function SA_wbTrunc(str, maxChars)
    local bytes, chars, n = 0, 0, #str
    while bytes < n and chars < maxChars do
        local b = str:byte(bytes + 1)
        local step = 1
        if b >= 240 then step = 4 elseif b >= 224 then step = 3 elseif b >= 192 then step = 2 end
        bytes = bytes + step
        chars = chars + 1
    end
    if bytes < n then return str:sub(1, bytes) .. "..." end
    return str
end
-- 마크업/개행 정리 + UTF-8 안전 길이 제한
local function SA_wbSanitize(str)
    if type(str) ~= "string" then return "" end
    str = str:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    str = str:gsub("|H.-|h", ""):gsub("|h", ""):gsub("|T.-|t", "")
    str = str:gsub("[\r\n]+", " ")
    return SA_wbTrunc(str, 100)
end
local function SA_wbToastNext()
    local item = table.remove(SA_wbToastQ, 1)
    if not item then SA_wbToastBusy = false; return end
    SA_wbToastBusy = true
    local f = SA_wbEnsureToast()
    f.text:SetFont(MimDiceFontPath(), 12, "")
    f.text:SetText(item.body)
    f:SetHeight(math.max(56, 26 + (item.lines or 1) * 16))
    f.fadeAnim:Stop(); f:SetAlpha(1); f:Show()
    local gen = SA_wbToastGen
    C_Timer.After(11, function()
        if gen ~= SA_wbToastGen then return end   -- 오래된 타이머 무효
        if f:IsShown() then f.fadeAnim:Stop(); f:Hide() end
        SA_wbToastNext()
    end)
end
local function SA_wbToastEnqueue(body, lines)
    SA_wbToastQ[#SA_wbToastQ + 1] = { body = body, lines = lines or 1 }
    if not SA_wbToastBusy then SA_wbToastNext() end
end
-- 정상 확인된 발신자의 원문(stash)을 큐에 (발신자당 최대 5줄)
local function SA_wbToastPush(name, stash, note)
    if not stash or #stash == 0 then return end
    local lines = { "|cff66ccff밈다이스 - 확인된 귓속말|r" .. (note and (" |cff888888(" .. note .. ")|r") or "") }
    local shown = 0
    for _, text in ipairs(stash) do
        local clean = SA_wbSanitize(text)
        if clean ~= "" then
            shown = shown + 1
            lines[#lines + 1] = "|cffffd200" .. (name or "?") .. ":|r " .. clean
            if shown >= 5 then break end
        end
    end
    if shown == 0 then return end
    SA_wbToastEnqueue(table.concat(lines, "\n"), shown + 1)
end

-- ── 채팅 필터 (멱등.부작용 없음) ──
local function SA_wbChatFilter(self, event, text, ...)
    local wbdb = MimDiceDB and MimDiceDB.whisperBlock
    if not wbdb or not wbdb.enabled then return end
    local player = select(1, ...)
    local flag   = select(5, ...)
    local guid   = select(11, ...)
    local readable
    readable, flag, guid = SA_wbReadable(player, text, flag, guid)
    if not readable then return true end                         -- 판정 불가 메시지는 fail-closed
    local name = Ambiguate(player, "none")
    local state = SA_wbState[name]
    if state == "safe" then return end                       -- 통과 확정 -> 원문 그대로
    if state == "pending" then                               -- 확인 중: 즉시 숨김 (임시친구 오인 방지)
        return true
    end
    -- blocked 또는 미확인: 신뢰 판정을 매번 동적으로 (친구 추가/삭제 즉시 반영)
    if SA_wbTrusted(name, flag, guid) then return end        -- 신뢰 대상 -> 통과
    return true                                                -- 비신뢰 -> 채팅 메시지 완전 숨김
end

-- 레벨 확인 시작 (독립 이벤트 프레임에서 C_Timer.After(0)로 예약 실행)
local function SA_wbStartCheck(name)
    if SA_wbState[name] ~= "pending" then return end
    -- 비연결 서버는 친구 등록이 안 돼 레벨 확인 불가 -> 보호 목적상 차단 처리
    local dash = name:find("-", 1, true)
    if dash and not SA_wbRealms[name:sub(dash + 1)] then
        SA_wbFinishPending(name, "blocked")
        SA_wbDbg(name .. ": 차단 (비연결 서버 - 레벨 확인 불가)")
        return
    end
    SA_wbSysHide[name] = GetTime() + 15
    local token = {}
    SA_wbGen[name] = token              -- API 호출 전에 토큰 배정 (구조적 완전성)
    pcall(MuteSoundFile, 567518)
    SA_wbDidMute = true
    pcall(C_FriendList.AddFriend, name, SA_WB_NOTE)
    C_FriendList.ShowFriends()
    -- 5초 안에 확인 안 되면 보호 목적상 차단 (원문도 폐기)
    C_Timer.After(5, function()
        if SA_wbGen[name] ~= token then return end   -- 오래된 타이머 무효
        if SA_wbState[name] ~= "pending" then return end
        SA_wbFinishPending(name, "blocked")
        SA_wbDbg(name .. ": 차단 (레벨 확인 시간 초과)")
    end)
end

-- 귓말 수신 (이벤트 프레임): 원문 문자열만 메모리에 담고, 확인은 다음 프레임으로.
local function SA_wbOnWhisper(...)
    local wbdb = MimDiceDB and MimDiceDB.whisperBlock
    if not wbdb or not wbdb.enabled then return end
    local text   = select(1, ...)
    local player = select(2, ...)
    local flag   = select(6, ...)
    local guid   = select(12, ...)
    local readable
    readable, flag, guid = SA_wbReadable(player, text, flag, guid)
    if not readable then
        SA_wbDbg("차단 (보호된 player/text로 발신자 판정 불가)")
        return
    end
    local name = Ambiguate(player, "none")
    local state = SA_wbState[name]
    if state == "safe" then return end
    if state ~= "pending" then
        -- blocked 또는 미확인: 신뢰 판정을 매번 동적으로 (관계 변화 즉시 반영, safe로 캐싱 안 함)
        local why = SA_wbTrusted(name, flag, guid)
        if why then
            SA_wbDbg(name .. ": 통과 (" .. why .. ")")       -- 왜 통과했는지 반드시 남긴다 (진단)
            return
        end
        if state == "blocked" then return end                -- 비신뢰 + 이미 차단: 필터가 가림, 원문 안 담음
        -- 미확인 + 비신뢰: 레벨 확인 시작
        SA_wbState[name] = "pending"
        SA_wbPendingCount = SA_wbPendingCount + 1
        C_Timer.After(0, function() SA_wbStartCheck(name) end)
    end
    -- pending: 원문 보관 (readable 통과 = 안전한 문자열)
    if type(text) == "string" and text ~= "" then
        local st = SA_wbStash[name]
        if not st then st = {}; SA_wbStash[name] = st end
        if #st < 20 then st[#st + 1] = text end
    end
end

-- 친구목록 갱신: 대기 발신자의 레벨을 읽고 임시 등록 삭제 -> 통과/차단 결정.
-- 첫 갱신에서도 청소만 하고 끝내지 않고, pending 이 있으면 그 자리에서 판정까지 이어간다.
local function SA_wbOnFriendsUpdate()
    if not SA_wbReady then
        SA_wbReady = true
        local num = C_FriendList.GetNumFriends() or 0
        for i = num, 1, -1 do
            local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
            if ok and info and type(info.name) == "string" then
                if info.notes == SA_WB_NOTE and SA_wbState[info.name] ~= "pending" then
                    pcall(C_FriendList.RemoveFriendByIndex, i)        -- 이전 세션 임시 항목만 청소
                end
                -- 기존 친구를 safe 로 미리 굳히지 않는다: 친구/길드/파티는 매 귓말 동적 확인
            end
        end
    end
    if SA_wbPendingCount <= 0 then return end
    local wbdb = MimDiceDB and MimDiceDB.whisperBlock
    local minLv = (wbdb and wbdb.minLevel) or 60
    local num = C_FriendList.GetNumFriends() or 0
    for i = num, 1, -1 do
        local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
        local name = ok and info and info.name
        if name and info.notes == SA_WB_NOTE and SA_wbState[name] == "pending" then
            local level = info.level
            if type(level) == "number" and level > 0 then   -- 0이면 아직 미갱신 -> 다음 갱신 대기
                if level >= minLv then
                    local ids = SA_wbFinishPending(name, "safe")
                    SA_wbToastPush(name, ids, "레벨 " .. level)
                    SA_wbDbg(name .. ": 통과 (레벨 " .. level .. " >= 기준 " .. minLv .. ")")
                else
                    SA_wbFinishPending(name, "blocked")          -- stash 폐기(반환값 버림)
                    SA_wbDbg(name .. ": 차단 (레벨 " .. level .. " < 기준 " .. minLv .. ")")
                end
            end
        end
    end
end

-- 레벨 확인 중인 이름이 든 시스템 문구 숨김 (필터, 부작용 없음)
local function SA_wbSystemFilter(_, _, msg)
    if SA_IsSecret(msg) or type(msg) ~= "string" then return end
    local now = GetTime()
    for nm, expire in pairs(SA_wbSysHide) do
        if now > expire then
            SA_wbSysHide[nm] = nil
        elseif msg:find(nm, 1, true) then
            return true
        end
    end
end

-- 옵션 OFF/정리: 모든 pending 취소 + 임시친구 전부 제거 + 음소거 복구 + 토스트 무효화 (전역)
function SA_WhisperBlockCancelAll()
    for name, st in pairs(SA_wbState) do
        if st == "pending" then SA_wbState[name] = nil end
    end
    wipe(SA_wbStash); wipe(SA_wbSysHide); wipe(SA_wbGen)
    SA_wbPendingCount = 0
    local num = C_FriendList.GetNumFriends() or 0
    for i = num, 1, -1 do
        local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
        if ok and info and info.notes == SA_WB_NOTE then
            pcall(C_FriendList.RemoveFriendByIndex, i)
        end
    end
    if SA_wbDidMute then pcall(UnmuteSoundFile, 567518); SA_wbDidMute = false end
    SA_wbToastGen = SA_wbToastGen + 1        -- 남은 토스트 타이머 무효화
    wipe(SA_wbToastQ)
    SA_wbToastBusy = false
    if SA_wbToast then SA_wbToast.fadeAnim:Stop(); SA_wbToast:Hide() end
end

-- 기준 레벨 변경 등으로 이전 판정이 무의미해질 때: 확정 판정(safe/blocked)을 모두 비운다 (전역).
-- 다음 귓말부터 새 기준으로 다시 판정한다.
function SA_WhisperBlockResetJudgments()
    SA_WhisperBlockCancelAll()   -- pending/임시친구/음소거/토스트 정리
    wipe(SA_wbState)
    local me = UnitName("player")
    if me then SA_wbState[me] = "safe" end
end

SA_WBFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_WHISPER" then
        SA_wbOnWhisper(...)
    elseif event == "FRIENDLIST_UPDATE" then
        SA_wbOnFriendsUpdate()
    elseif event == "CHAT_MSG_WHISPER_INFORM" then
        -- 내가 먼저 귓말한 상대는 통과. 단 차단 확정된 상대는 답장해도 유지.
        local target = select(2, ...)
        if type(target) == "string" and not SA_IsSecret(target) then
            local tname = Ambiguate(target, "none")
            if SA_wbState[tname] ~= "blocked" then
                if SA_wbState[tname] == "pending" then
                    SA_wbFinishPending(tname, "safe")
                else
                    SA_wbState[tname] = "safe"
                end
            end
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        local msg = ...
        if not SA_IsSecret(msg) and msg == ERR_FRIEND_LIST_FULL then
            SA_wbToastEnqueue("|cffff5555친구 목록이 가득 차 저렙 귓속말 차단이 동작할 수 없습니다.\n친구 자리를 2칸 비워주세요.|r", 2)
        end
    elseif event == "PLAYER_LOGOUT" then
        if SA_wbDidMute then pcall(UnmuteSoundFile, 567518); SA_wbDidMute = false end   -- 리로드/로그아웃 음소거 정리
    end
end)

local SA_wbAddFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
SA_wbAddFilter("CHAT_MSG_WHISPER", SA_wbChatFilter)
SA_wbAddFilter("CHAT_MSG_SYSTEM", SA_wbSystemFilter)

-- 진단 슬래시
SLASH_MIMWHISPER1 = "/밈귓말"
SLASH_MIMWHISPER2 = "/mimwhisper"
SlashCmdList["MIMWHISPER"] = function()
    local wb = MimDiceDB and MimDiceDB.whisperBlock
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "|cff88ccff[밈귓말]|r 차단 %s / 기준: 레벨 %d 미만 숨김 / 최근 판정: /밈귓로그",
        (wb and wb.enabled) and "켜짐" or "꺼짐", (wb and wb.minLevel) or 60))
end
SLASH_MIMWHISPERLOG1 = "/밈귓로그"
SLASH_MIMWHISPERLOG2 = "/mimwhisperlog"
SlashCmdList["MIMWHISPERLOG"] = function()
    DEFAULT_CHAT_FRAME:AddMessage("|cff88ccff[밈귓말] 최근 판정 기록|r (" .. #SA_wbLog .. "건)")
    for _, line in ipairs(SA_wbLog) do
        DEFAULT_CHAT_FRAME:AddMessage("  " .. line)
    end
end

-- 로그인 시 1회 초기화 (PLAYER_LOGIN에서 호출). 채팅 프레임 재등록은 하지 않는다.
local function SA_WhisperBlockInit()
    local realms = GetAutoCompleteRealms()
    if type(realms) == "table" then
        for i = 1, #realms do SA_wbRealms[realms[i]] = true end
    end
    local me = UnitName("player")
    if me then SA_wbState[me] = "safe" end
    SA_WBFrame:RegisterEvent("CHAT_MSG_WHISPER")
    SA_WBFrame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
    SA_WBFrame:RegisterEvent("FRIENDLIST_UPDATE")
    SA_WBFrame:RegisterEvent("CHAT_MSG_SYSTEM")
    SA_WBFrame:RegisterEvent("PLAYER_LOGOUT")
    C_FriendList.ShowFriends()   -- 친구목록 첫 갱신 유도 (임시 항목 청소)
end

local SA_EventFrame = CreateFrame("Frame")
SA_EventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
SA_EventFrame:RegisterEvent("PLAYER_LOGIN")
SA_EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")   -- 인스턴스 진입 시 전투부활 충전 기준값 동기화
SA_EventFrame:RegisterEvent("UNIT_DIED")
SA_EventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")     -- 전투부활 충전 변화 감지
SA_EventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")     -- 전투 종료: 미뤄둔 마우스 모드 재적용
SA_EventFrame:RegisterEvent("LFG_LIST_APPLICANT_LIST_UPDATED")  -- 파티 신청 감지
SA_EventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")              -- 5인 풀파티 감지
SA_EventFrame:RegisterUnitEvent("UNIT_AURA", "player")

SA_EventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        SA_InitDB()
        -- 전투 중 프레임 생성 차단(SetPropagateMouseClicks protected)을 피하기 위해
        -- 로그인 시점(비전투)에 미리 생성
        for _, def in ipairs(BUFF_DEFS) do
            SA_EnsureBuffBar(def.key)
        end
        -- 죽음 프레임도 미리 생성 (첫 사망=전투 중 생성 지연/위험 제거)
        SA_EnsureDeathFrame()
        -- 파티 알림 프레임도 미리 생성 (SetPropagateMouseClicks는 전투 중 보호 → 첫 알림이 전투 중이어도 안전)
        SA_EnsurePartyFrame()
        SA_SyncBattleResCharges()   -- 전투부활 충전 기준값 초기화 (오발동 방지)
        -- 전투부활 아이콘 미리 생성 + 0.5초 주기 갱신 티커 시작
        SA_EnsureBattleResIcon()
        SA_RefreshBattleResIconState()
        if not SA_brIconTicker then
            SA_brIconTicker = C_Timer.NewTicker(0.5, SA_RefreshBattleResIconState)
        end
        -- 저렙 귓속말 차단 초기화 (이벤트 등록 순서 조정 + 임시 친구항목 청소)
        SA_WhisperBlockInit()
        -- 풀파티 기준 인원 동기화 (로그인 시 이미 5인이면 안 울리게)
        SA_SyncGroupSize()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- 인스턴스 진입/이동 시 충전 기준값 재동기화 (진입 직후 충전 변화 오발동 방지)
        SA_SyncBattleResCharges()
        SA_RefreshBattleResIconState()
    elseif event == "LFG_LIST_APPLICANT_LIST_UPDATED" then
        SA_CheckPartyApplicants()
    elseif event == "GROUP_ROSTER_UPDATE" then
        SA_CheckFullParty()
    elseif event == "SPELL_UPDATE_CHARGES" then
        SA_CheckBattleResCharge()
        SA_RefreshBattleResIconState()   -- 충전 변화 즉시 아이콘 반영
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- 전투 종료: 전투 중 미뤄둔 아이콘 마우스 모드(클릭 통과/편집)를 지금 적용
        SA_RefreshBattleResIconState()
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
        -- 블러드 감지: addedAuras에서 직접 읽고 remaining >= 560 으로 신규 적용 확인.
        -- (API 캐시 지연·isFullUpdate 오판 문제 없음)
        local unit, updateInfo = ...
        if unit ~= "player" or not updateInfo or not updateInfo.addedAuras then return end

        for _, aura in ipairs(updateInfo.addedAuras) do
            -- 블러드: Sated/Exhaustion 계열 디버프가 새로 추가되면 방금 블러드 사용됨
            local ok, isLust = pcall(SA_IsBloodlustAura, aura)
            if ok and isLust then
                local ok2, remaining = pcall(function()
                    return aura.expirationTime and (aura.expirationTime - GetTime()) or 0
                end)
                -- 방금 걸린 Sated는 남은 시간이 ~600s. 560 미만이면 이미 있던 것(존 전환 재전송).
                if ok2 and remaining >= 560 then
                    SA_PlayBuff("BLOODLUST")
                    SA_StartBuffBar("BLOODLUST", BUFF_DEF_BY_KEY["BLOODLUST"].duration)
                end
                break
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

-- 탭 켜짐/꺼짐 색상 (사운드/귓말차단/스킨 공용. 스킨 켜짐이면 팔레트 색 사용)
local function SA_SetTabActive(tab, on)
    if not tab then return end
    if SA_SkinOn() then
        local pal = SA_SkinPal()
        if on then
            tab:SetBackdropColor(pal.hover[1], pal.hover[2], pal.hover[3], 0.90)
            tab:SetBackdropBorderColor(pal.border[1], pal.border[2], pal.border[3], 1)
            tab.text:SetTextColor(pal.accent[1], pal.accent[2], pal.accent[3], pal.accent[4] or 1)
        else
            tab:SetBackdropColor(pal.tab[1], pal.tab[2], pal.tab[3], 0.95)
            tab:SetBackdropBorderColor(pal.border[1], pal.border[2], pal.border[3], 1)
            tab.text:SetTextColor(0.62, 0.62, 0.62)
        end
        return
    end
    if on then
        tab:SetBackdropColor(0.5, 0.1, 0.1, 0.9)
        tab:SetBackdropBorderColor(1, 0.82, 0, 1)
        tab.text:SetTextColor(1, 1, 0)
    else
        tab:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
        tab:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        tab.text:SetTextColor(0.6, 0.6, 0.6)
    end
end

-- 탭 3개의 모양(각진/원래 테두리)·색·호버를 현재 스킨 상태에 맞춰 일괄 갱신
-- (전역: SA_SkinRefresh에서 호출)
function SA_SkinRefreshTabs()
    -- 0) 가로 배치: 스킨(각진)일 땐 탭을 살짝 띄우고(+2), 기본 모습일 땐 원래처럼 살짝 겹침(-4).
    --    우측 창들도 탭 위치에 맞춰 함께 움직여서 탭-창 간격이 항상 8px로 일정하게.
    if SA_TabOption and _G.MainWindow then
        -- 스킨 켬: 플랫 1px 테두리라 탭을 메인창에 딱 붙임(0) / 끔: 원래 그림 테두리에 살짝 겹침(-4)
        local tx = SA_SkinOn() and 0 or -4
        SA_TabOption:ClearAllPoints()
        SA_TabOption:SetPoint("TOPLEFT", _G.MainWindow, "TOPRIGHT", tx, -30)
        local wx = tx + 34 + (SA_SkinOn() and 14 or 8)   -- 탭 폭 34 + 우측 창까지 간격 (스킨 켬 14 / 끔 8)
        for _, w in ipairs({ SA_OptionWindow, SA_WhisperWindow }) do
            if w then
                w:ClearAllPoints()
                w:SetPoint("TOPLEFT", _G.MainWindow, "TOPRIGHT", wx, 0)
                w:SetPoint("BOTTOMLEFT", _G.MainWindow, "BOTTOMRIGHT", wx, 0)
            end
        end
        if SA_SkinWindow then   -- 스킨 창은 내용이 많아 고정 높이 (위쪽만 맞춤)
            SA_SkinWindow:ClearAllPoints()
            SA_SkinWindow:SetPoint("TOPLEFT", _G.MainWindow, "TOPRIGHT", wx, 0)
        end
    end
    -- 1) 테두리 모양 전환 (스킨 켬 = 각진 1px / 끔 = 원래 테두리)
    for _, t in ipairs({ SA_TabOption, SA_TabWhisper, SA_TabSkin }) do
        if t and t.SetBackdrop then
            if SA_SkinOn() and not t.MimDiceSkinFlat then
                if not t.MimDiceSkinOrig then
                    t.MimDiceSkinOrig = { backdrop = t.GetBackdrop and t:GetBackdrop() or nil }
                end
                t:SetBackdrop(SA_SKIN_FLAT_BACKDROP)
                t.MimDiceSkinFlat = true
            elseif not SA_SkinOn() and t.MimDiceSkinFlat then
                if t.MimDiceSkinOrig and t.MimDiceSkinOrig.backdrop then
                    t:SetBackdrop(t.MimDiceSkinOrig.backdrop)
                end
                t.MimDiceSkinFlat = false
            end
        end
    end
    -- 2) 색 칠하기 (SetBackdrop이 색을 초기화하므로 반드시 그 뒤에)
    SA_SetTabActive(SA_TabOption, SA_OptionWindow and SA_OptionWindow:IsShown())
    SA_SetTabActive(SA_TabWhisper, SA_WhisperWindow and SA_WhisperWindow:IsShown())
    SA_SetTabActive(SA_TabSkin, SA_SkinWindow and SA_SkinWindow:IsShown())
    -- 3) 호버색
    for _, t in ipairs({ SA_TabOption, SA_TabWhisper, SA_TabSkin }) do
        if t then
            if SA_SkinOn() then
                if not t.MimHover then
                    t.MimHover = t:CreateTexture(nil, "HIGHLIGHT")   -- 마우스오버 시 자동 표시
                    t.MimHover:SetPoint("TOPLEFT", 2, -2)
                    t.MimHover:SetPoint("BOTTOMRIGHT", -2, 2)
                end
                local pal = SA_SkinPal()
                t.MimHover:SetColorTexture(pal.hover[1], pal.hover[2], pal.hover[3], (pal.hover[4] or 0.30) * 0.85)
                t.MimHover:Show()
            elseif t.MimHover then
                t.MimHover:Hide()
            end
        end
    end
end

local function SA_ToggleWindow()
    if SA_OptionWindow:IsShown() then
        SA_OptionWindow:Hide()
        SA_SetTabActive(SA_TabOption, false)
    else
        -- 옵션창들은 같은 자리를 쓰므로 하나만 표시
        if SA_WhisperWindow and SA_WhisperWindow:IsShown() then
            SA_WhisperWindow:Hide()
            SA_SetTabActive(SA_TabWhisper, false)
        end
        if SA_SkinWindow and SA_SkinWindow:IsShown() then
            SA_SkinWindow:Hide()
            SA_SetTabActive(SA_TabSkin, false)
        end
        SA_OptionWindow:Show()
        SA_RefreshList()
        SA_SetTabActive(SA_TabOption, true)
    end
end

local function SA_ToggleWhisperWindow()
    if not SA_WhisperWindow then return end
    if SA_WhisperWindow:IsShown() then
        SA_WhisperWindow:Hide()
        SA_SetTabActive(SA_TabWhisper, false)
    else
        if SA_OptionWindow and SA_OptionWindow:IsShown() then
            SA_OptionWindow:Hide()
            SA_SetTabActive(SA_TabOption, false)
        end
        if SA_SkinWindow and SA_SkinWindow:IsShown() then
            SA_SkinWindow:Hide()
            SA_SetTabActive(SA_TabSkin, false)
        end
        SA_WhisperWindow:Show()
        if SA_RefreshWhisperLog then SA_RefreshWhisperLog() end
        SA_SetTabActive(SA_TabWhisper, true)
    end
end

local function SA_ToggleSkinWindow()
    if not SA_SkinWindow then return end
    if SA_SkinWindow:IsShown() then
        SA_SkinWindow:Hide()
        SA_SetTabActive(SA_TabSkin, false)
    else
        if SA_OptionWindow and SA_OptionWindow:IsShown() then
            SA_OptionWindow:Hide()
            SA_SetTabActive(SA_TabOption, false)
        end
        if SA_WhisperWindow and SA_WhisperWindow:IsShown() then
            SA_WhisperWindow:Hide()
            SA_SetTabActive(SA_TabWhisper, false)
        end
        SA_SkinWindow:Show()
        if SA_RefreshSkinWindow then SA_RefreshSkinWindow() end
        SA_SetTabActive(SA_TabSkin, true)
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

    -- 사운드 탭 (기존 옵션창: 소리/알림 관련)
    SA_TabOption = CreateFrame("Button", "SA_TabOption", mainWin, "BackdropTemplate")
    SA_TabOption:SetSize(34, 80)
    SA_TabOption:SetPoint("TOPLEFT", mainWin, "TOPRIGHT", -4, -30)
    SA_TabOption:SetBackdrop(tabBackdrop)
    SA_TabOption:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    SA_TabOption:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local optText = SA_TabOption:CreateFontString(nil, "OVERLAY")
    optText:SetPoint("CENTER")
    optText:SetFont(MimDiceFontPath(), 12, "OUTLINE")
    optText:SetText("사\n운\n드")
    optText:SetTextColor(0.6, 0.6, 0.6)
    SA_TabOption.text = optText

    SA_TabOption:SetScript("OnClick", SA_ToggleWindow)

    -- 귓말차단 탭 (저렙 귓속말 차단 설정 + 차단 기록)
    SA_TabWhisper = CreateFrame("Button", "SA_TabWhisper", mainWin, "BackdropTemplate")
    SA_TabWhisper:SetSize(34, 100)
    SA_TabWhisper:SetPoint("TOPLEFT", SA_TabOption, "BOTTOMLEFT", 0, -6)
    SA_TabWhisper:SetBackdrop(tabBackdrop)
    SA_TabWhisper:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    SA_TabWhisper:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local wbText = SA_TabWhisper:CreateFontString(nil, "OVERLAY")
    wbText:SetPoint("CENTER")
    wbText:SetFont(MimDiceFontPath(), 12, "OUTLINE")
    wbText:SetText("귓\n말\n차\n단")
    wbText:SetTextColor(0.6, 0.6, 0.6)
    SA_TabWhisper.text = wbText

    SA_TabWhisper:SetScript("OnClick", SA_ToggleWhisperWindow)

    -- 스킨 탭 (플랫 다크 테마 프리셋 + 색 커스텀)
    SA_TabSkin = CreateFrame("Button", "SA_TabSkin", mainWin, "BackdropTemplate")
    SA_TabSkin:SetSize(34, 60)
    SA_TabSkin:SetPoint("TOPLEFT", SA_TabWhisper, "BOTTOMLEFT", 0, -6)
    SA_TabSkin:SetBackdrop(tabBackdrop)
    SA_TabSkin:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    SA_TabSkin:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local skText = SA_TabSkin:CreateFontString(nil, "OVERLAY")
    skText:SetPoint("CENTER")
    skText:SetFont(MimDiceFontPath(), 12, "OUTLINE")
    skText:SetText("스\n킨")
    skText:SetTextColor(0.6, 0.6, 0.6)
    SA_TabSkin.text = skText

    SA_TabSkin:SetScript("OnClick", SA_ToggleSkinWindow)

    -- 스킨이 켜져 있으면 탭 색을 팔레트로 정리
    SA_SkinRefreshTabs()
end

local function SA_CreateWindow()
    local mainWin = _G["MainWindow"]
    if not mainWin then return end

    -- ESC 키로 닫기: 메인창을 UISpecialFrames에 등록 → ESC 시 메인 닫힘 →
    -- OnHide 연동으로 옵션창·죽음/블러드/전투부활 설정창까지 전부 연쇄로 닫힘
    local alreadyReg = false
    for _, n in ipairs(UISpecialFrames) do if n == "MainWindow" then alreadyReg = true break end end
    if not alreadyReg then tinsert(UISpecialFrames, "MainWindow") end

    SA_OptionWindow = CreateFrame("Frame", "SA_OptionWindow", UIParent, "BackdropTemplate")
    -- 너비만 고정하고, 위/아래를 메인창에 앵커 → 옵션창 높이가 메인창 높이를 항상 따라감
    -- (기본값이든 사용자가 리사이즈하든 좌우 창의 위/아래 끝이 항상 맞음)
    SA_OptionWindow:SetWidth(380)
    SA_OptionWindow:SetPoint("TOPLEFT", mainWin, "TOPRIGHT", 38, 0)
    SA_OptionWindow:SetPoint("BOTTOMLEFT", mainWin, "BOTTOMRIGHT", 38, 0)
    SA_OptionWindow:SetFrameStrata("HIGH")   -- 메인창과 동일 레이어 → 자원/재사용바에 안 가리게

    -- 옵션창 드래그하면 메인창도 이동
    SA_WireBundleDrag(SA_OptionWindow)   -- 점프 없는 번들 드래그
    
    -- ★ 메인 창이 닫힐 때 옵션 창(사운드/귓말차단/스킨)도 함께 닫히도록 연동 ★
    mainWin:HookScript("OnHide", function()
        if SA_OptionWindow and SA_OptionWindow:IsShown() then
            SA_OptionWindow:Hide()
            SA_SetTabActive(SA_TabOption, false)
        end
        if SA_WhisperWindow and SA_WhisperWindow:IsShown() then
            SA_WhisperWindow:Hide()
            SA_SetTabActive(SA_TabWhisper, false)
        end
        if SA_SkinWindow and SA_SkinWindow:IsShown() then
            SA_SkinWindow:Hide()
            SA_SetTabActive(SA_TabSkin, false)
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

    -- 옵션창이 닫히면 죽음/버프/전투부활 설정창 + 사운드 선택 팝업도 함께 닫기
    SA_OptionWindow:HookScript("OnHide", function()
        if SA_DeathConfig and SA_DeathConfig:IsShown() then SA_DeathConfig:Hide() end
        for _, w in pairs(SA_BuffConfigs) do if w:IsShown() then w:Hide() end end
        if SA_BattleResIconConfig and SA_BattleResIconConfig:IsShown() then SA_BattleResIconConfig:Hide() end
        if _G.MimDice_PartyConfig and _G.MimDice_PartyConfig:IsShown() then _G.MimDice_PartyConfig:Hide() end
        if SA_SoundPicker and SA_SoundPicker:IsShown() then SA_SoundPicker:Hide() end
    end)

    -- (옛 제목 "스킬 사운드 알림 설정"은 섹션 헤더로 대체되어 제거됨)

    local closeBtn = CreateFrame("Button", nil, SA_OptionWindow, "UIPanelCloseButton")
    closeBtn.MimDiceIsClose = true   -- 스킨: 닫기(X) 플랫화 대상
    closeBtn:SetPoint("TOPRIGHT", SA_OptionWindow, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() SA_ToggleWindow() end)

    -- ── 밈줌 카페 링크 ──────────────────────────
    local cafeLabel = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    cafeLabel:SetFont(MimDiceFontPath(), 11)
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
    urlHint:SetFont(MimDiceFontPath(), 9)
    urlHint:SetTextColor(0.6, 0.6, 0.6)
    urlHint:SetPoint("TOPLEFT", urlPopup, "TOPLEFT", 6, -2)
    urlHint:SetText("Ctrl+C 로 복사, 한번 더 누르면 복사창이 닫힙니다.")

    local urlBox = CreateFrame("EditBox", nil, urlPopup)
    urlBox:SetSize(298, 18)
    urlBox:SetPoint("BOTTOMLEFT", urlPopup, "BOTTOMLEFT", 6, 4)
    urlBox:SetFont(MimDiceFontPath(), 11, "")
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
    optionSectionLabel:SetFont(MimDiceFontPath(), 13, "OUTLINE")
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
    autoPopupLabel:SetFont(MimDiceFontPath(), 11, "OUTLINE")
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
    autoResetMinBox:SetFont(MimDiceFontPath(), 11, "")
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
    autoResetSuffix:SetFont(MimDiceFontPath(), 11, "OUTLINE")
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
    deathSectionLabel:SetFont(MimDiceFontPath(), 13, "OUTLINE")
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
    deathLabel:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    deathLabel:SetText("파티/공대원 사망 시 사운드+메시지")
    deathLabel:SetTextColor(0.9, 0.9, 0.9)

    local deathCfgBtn = CreateFrame("Button", nil, SA_OptionWindow, "UIPanelButtonTemplate")
    deathCfgBtn:SetSize(50, 22)
    deathCfgBtn:SetPoint("TOPRIGHT", SA_OptionWindow, "TOPRIGHT", -15, -116)
    deathCfgBtn:SetText("설정")
    deathCfgBtn:GetFontString():SetFont(MimDiceFontPath(), 11, "")
    deathCfgBtn:SetScript("OnClick", function() SA_ToggleDeathConfig() end)

    -- ── << 블러드 >> 섹션 (모든 직업 공용, 지속시간 바) ──────────────
    local buffSectionLabel = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    buffSectionLabel:SetPoint("TOP", SA_OptionWindow, "TOP", 0, -142)
    buffSectionLabel:SetFont(MimDiceFontPath(), 13, "OUTLINE")
    buffSectionLabel:SetText("블러드 / 전투부활")
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
    bloodLabel:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    bloodLabel:SetText("블러드 (사운드 + 지속시간 바)")
    bloodLabel:SetTextColor(0.9, 0.9, 0.9)

    local bloodCfgBtn = CreateFrame("Button", nil, SA_OptionWindow, "UIPanelButtonTemplate")
    bloodCfgBtn:SetSize(50, 22)
    bloodCfgBtn:SetPoint("TOPRIGHT", SA_OptionWindow, "TOPRIGHT", -15, -160)
    bloodCfgBtn:SetText("설정")
    bloodCfgBtn:GetFontString():SetFont(MimDiceFontPath(), 11, "")
    bloodCfgBtn:SetScript("OnClick", function() SA_ToggleBuffConfig("BLOODLUST") end)

    -- 전투부활 줄: [✓] 전투부활 ............ [설정]  (사운드/아이콘 세부는 전부 "설정" 안으로 이동)
    local brCb = CreateFrame("CheckButton", nil, SA_OptionWindow, "UICheckButtonTemplate")
    brCb:SetSize(22, 22)
    brCb:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 15, -182)
    brCb:SetChecked(MimDiceDB and MimDiceDB.battleRes and MimDiceDB.battleRes.enabled)
    brCb:SetScript("OnClick", function(self)
        if MimDiceDB.battleRes then
            MimDiceDB.battleRes.enabled = self:GetChecked() and true or false
            SA_RefreshBattleResIconState()   -- 마스터 끄면 아이콘도 즉시 숨김
        end
    end)
    local brLabel = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    brLabel:SetPoint("LEFT", brCb, "RIGHT", 2, 0)
    brLabel:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    brLabel:SetText("전투부활 (사운드 + 아이콘)")
    brLabel:SetTextColor(0.9, 0.9, 0.9)

    local brCfgBtn = CreateFrame("Button", nil, SA_OptionWindow, "UIPanelButtonTemplate")
    brCfgBtn:SetSize(50, 22)
    brCfgBtn:SetPoint("TOPRIGHT", SA_OptionWindow, "TOPRIGHT", -15, -182)
    brCfgBtn:SetText("설정")
    brCfgBtn:GetFontString():SetFont(MimDiceFontPath(), 11, "")
    brCfgBtn:SetScript("OnClick", function() SA_ToggleBattleResIconConfig() end)

    -- 파티 신청 줄: [✓] 파티 신청 (사운드+메시지) ..... [설정]
    local paCb = CreateFrame("CheckButton", nil, SA_OptionWindow, "UICheckButtonTemplate")
    paCb:SetSize(22, 22)
    paCb:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 15, -206)
    paCb:SetChecked(MimDiceDB and MimDiceDB.partyAlert and MimDiceDB.partyAlert.enabled)
    paCb:SetScript("OnClick", function(self)
        if MimDiceDB.partyAlert then
            MimDiceDB.partyAlert.enabled = self:GetChecked() and true or false
            if not MimDiceDB.partyAlert.enabled then
                -- 끌 때 정리: 반복 티커 중지 + (편집중 아니면) 계속표시(stay) 잔상 제거
                SA_StopPartyRepeat()
                if MimDiceDB.partyAlert.locked ~= false then SA_HidePartyFrame() end
            end
        end
    end)
    local paLabel = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    paLabel:SetPoint("LEFT", paCb, "RIGHT", 2, 0)
    paLabel:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    paLabel:SetText("파티 신청 (사운드 + 메시지)")
    paLabel:SetTextColor(0.9, 0.9, 0.9)

    local paCfgBtn = CreateFrame("Button", nil, SA_OptionWindow, "UIPanelButtonTemplate")
    paCfgBtn:SetSize(50, 22)
    paCfgBtn:SetPoint("TOPRIGHT", SA_OptionWindow, "TOPRIGHT", -15, -206)
    paCfgBtn:SetText("설정")
    paCfgBtn:GetFontString():SetFont(MimDiceFontPath(), 11, "")
    paCfgBtn:SetScript("OnClick", function() SA_TogglePartyConfig() end)

    -- 구분선
    local divider = SA_OptionWindow:CreateTexture(nil, "ARTWORK")
    divider:SetSize(350, 1)
    divider:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 15, -238)
    divider:SetColorTexture(0.5, 0.5, 0.5, 0.6)

    -- ── << 스킬 사운드 알림 >> 섹션 ─────────────────
    local skillSectionLabel = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    skillSectionLabel:SetPoint("TOP", SA_OptionWindow, "TOP", 0, -250)
    skillSectionLabel:SetFont(MimDiceFontPath(), 13, "OUTLINE")
    skillSectionLabel:SetText("스킬 사운드 알림 (직업별 저장)")
    skillSectionLabel:SetTextColor(1, 0.82, 0)

    local inputLabel = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    inputLabel:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 15, -276)
    inputLabel:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    inputLabel:SetText("1. 추가할 스킬의 이름 또는 ID 입력 (꼭 띄어쓰기 지켜야 함)")
    inputLabel:SetTextColor(0.9, 0.9, 0.9)

    local inputBox = CreateFrame("EditBox", "SA_SpellInput", SA_OptionWindow, "InputBoxTemplate")
    inputBox:SetSize(200, 22)
    inputBox:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 20, -296)
    inputBox:SetAutoFocus(false)
    inputBox:SetFont(MimDiceFontPath(), 12, "")

    local addBtn = CreateFrame("Button", nil, SA_OptionWindow, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 24)
    addBtn:SetPoint("LEFT", inputBox, "RIGHT", 10, 0)
    addBtn:SetText("스킬 추가")
    addBtn:GetFontString():SetFont(MimDiceFontPath(), 11, "")

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
    listTitle:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 15, -336)
    listTitle:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    listTitle:SetText("2. 사운드 개별 설정")
    listTitle:SetTextColor(0.8, 0.8, 0.8)

    local scrollFrame = CreateFrame("ScrollFrame", "SA_ListScrollFrame", SA_OptionWindow, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 10, -356)
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
            spellText:SetFont(MimDiceFontPath(), 11)
            spellText:SetJustifyH("LEFT")
            row.spellText = spellText

            local typeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            typeBtn:SetSize(42, 22)
            typeBtn:SetPoint("LEFT", spellText, "RIGHT", 5, 0)
            typeBtn:GetFontString():SetFont(MimDiceFontPath(), 10, "")
            row.typeBtn = typeBtn
            -- 클릭으로 타입 순환한다는 걸 알리는 툴팁 (좁은 행이라 세그먼트 버튼 대신 안내)
            typeBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("클릭: 사운드 타입 전환", 1, 0.82, 0)
                GameTooltip:AddLine("내장 → 커스텀 → ID 순환", 0.9, 0.9, 0.9)
                GameTooltip:AddLine("커스텀: sounds폴더 파일명 그대로(대소문자·확장자)", 0.7, 0.7, 0.7)
                GameTooltip:AddLine("ID: 사운드 숫자 ID 입력", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            typeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            local soundSelectBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            soundSelectBtn:SetSize(100, 20)
            soundSelectBtn:SetPoint("LEFT", typeBtn, "RIGHT", 5, 0)
            do
                local fs = soundSelectBtn:GetFontString()
                fs:SetFont(MimDiceFontPath(), 9, "")
                fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
                fs:ClearAllPoints(); fs:SetPoint("LEFT", 5, 0); fs:SetPoint("RIGHT", -5, 0)
            end
            row.soundSelectBtn = soundSelectBtn

            local customEdit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            customEdit:SetSize(100, 20)
            customEdit:SetPoint("LEFT", typeBtn, "RIGHT", 15, 0)
            customEdit:SetAutoFocus(false)
            customEdit:SetFont(MimDiceFontPath(), 10, "")
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
            row.spellText:SetFont(MimDiceFontPath(), 12, "OUTLINE")
            row.spellText:SetTextColor(0.5, 1, 0.5)
            row.delBtn:Hide()
        else
            row.spellText:SetFont(MimDiceFontPath(), 11)
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
            -- 타입만 전환하고 각 타입의 저장값은 보존 (다시 돌아와도 유지)
            if entry.soundType == "preset" then
                entry.soundType = "custom"
            elseif entry.soundType == "custom" then
                entry.soundType = "id"
            else
                entry.soundType = "preset"
            end
            SA_RefreshList()
        end)

        -- 타입에 따른 UI 표시
        if entry.soundType == "preset" then
            row.soundSelectBtn:Show()
            row.customEdit:Hide()
            row.soundSelectBtn:SetText(entry.soundName or "사운드 선택...")
            row.soundSelectBtn:SetScript("OnClick", function()
                SA_OpenSoundPicker(row.soundSelectBtn,
                    function() return entry.soundKey end,
                    function(snd)
                        entry.soundKey = snd.id
                        entry.soundName = snd.name
                        row.soundSelectBtn:SetText(snd.name)
                        SA_PlaySound(entry)
                    end)
            end)

        elseif entry.soundType == "custom" then
            row.soundSelectBtn:Hide()
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
            row.soundSelectBtn:Hide()
            row.customEdit:Show()
            if not entry.soundID or entry.soundID == "" then
                row.customEdit:SetText("예: 567439")
                row.customEdit:SetTextColor(0.5, 0.5, 0.5)
            else
                row.customEdit:SetText(tostring(entry.soundID))
                row.customEdit:SetTextColor(1, 1, 1)
            end

            row.customEdit:SetScript("OnEditFocusGained", function(self)
                if self:GetText() == "예: 567439" then self:SetText(""); self:SetTextColor(1,1,1) end
            end)
            row.customEdit:SetScript("OnTextChanged", function(self, userInput)
                if userInput then entry.soundID = tonumber(self:GetText()) or self:GetText() end
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
-- 귓속말차단 옵션창 (탭 2번: 설정 + 쉬운 설명 + 차단 기록)
-- =====================================================================
local function SA_CreateWhisperWindow()
    local mainWin = _G["MainWindow"]
    if not mainWin then return end

    local win = CreateFrame("Frame", "SA_WhisperWindow", UIParent, "BackdropTemplate")
    win:SetWidth(380)
    win:SetPoint("TOPLEFT", mainWin, "TOPRIGHT", 38, 0)
    win:SetPoint("BOTTOMLEFT", mainWin, "BOTTOMRIGHT", 38, 0)
    win:SetFrameStrata("HIGH")
    win:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    win:SetBackdropColor(0, 0, 0, 0.5)
    win:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    win:EnableMouse(true)
    -- 드래그하면 메인창과 한 덩어리로 이동 (사운드 옵션창과 동일)
    SA_WireBundleDrag(win)   -- 점프 없는 번들 드래그
    win:Hide()

    local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    closeBtn.MimDiceIsClose = true   -- 스킨: 닫기(X) 플랫화 대상
    closeBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() SA_ToggleWhisperWindow() end)

    local title = win:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", win, "TOP", 0, -12)
    title:SetFont(MimDiceFontPath(), 14, "OUTLINE")
    title:SetText("저렙 귓속말 차단")
    title:SetTextColor(1, 0.82, 0)

    -- ── 켜기 + 기준 레벨 ──
    local enCb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    enCb:SetSize(24, 24)
    enCb:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -34)
    enCb:SetScript("OnClick", function(self)
        if MimDiceDB.whisperBlock then
            local on = self:GetChecked() and true or false
            MimDiceDB.whisperBlock.enabled = on
            -- 끄면 진행 중이던 레벨 확인/임시 친구/음소거를 즉시 정리
            if not on and SA_WhisperBlockCancelAll then SA_WhisperBlockCancelAll() end
        end
    end)
    win.enCb = enCb
    local enLabel = win:CreateFontString(nil, "OVERLAY")
    enLabel:SetPoint("LEFT", enCb, "RIGHT", 2, 0)
    enLabel:SetFont(MimDiceFontPath(), 12, "OUTLINE")
    enLabel:SetText("차단 켜기 : 레벨")
    enLabel:SetTextColor(0.9, 0.9, 0.9)
    local lvBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    lvBox:SetSize(38, 20)
    lvBox:SetPoint("LEFT", enLabel, "RIGHT", 10, 0)
    lvBox:SetAutoFocus(false); lvBox:SetFont(MimDiceFontPath(), 12, "")
    lvBox:SetNumeric(true); lvBox:SetMaxLetters(3); lvBox:SetJustifyH("CENTER")
    lvBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local v = tonumber(self:GetText())
        if v and v >= 2 and MimDiceDB.whisperBlock and MimDiceDB.whisperBlock.minLevel ~= v then
            MimDiceDB.whisperBlock.minLevel = v
            if SA_WhisperBlockResetJudgments then SA_WhisperBlockResetJudgments() end
        end
    end)
    lvBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    win.lvBox = lvBox
    local lvSuffix = win:CreateFontString(nil, "OVERLAY")
    lvSuffix:SetPoint("LEFT", lvBox, "RIGHT", 6, 0)
    lvSuffix:SetFont(MimDiceFontPath(), 12, "OUTLINE")
    lvSuffix:SetText("미만 귓속말 숨김")
    lvSuffix:SetTextColor(0.9, 0.9, 0.9)

    -- ── 쉬운 설명 ──
    local help = win:CreateFontString(nil, "OVERLAY")
    help:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -70)
    help:SetFont(MimDiceFontPath(), 12, "")
    help:SetTextColor(0.8, 0.8, 0.8)
    help:SetWidth(350); help:SetJustifyH("LEFT"); help:SetWordWrap(true); help:SetSpacing(5)
    help:SetText(
        "ㅁ 위에서 정한 레벨보다 낮은 캐릭터가 보낸 귓속말은\n" ..
        "    화면에 뜨지 않습니다.\n\n" ..
        "ㅁ 배틀넷 친구나, 게임내 친구로 설정되어 있는\n" ..
        "    친구의 귓속말은 볼 수 있습니다.\n\n" ..
        "ㅁ 귓속말 내용은 저장하지 않고 기록도 남기지 않습니다.\n\n" ..
        "ㅁ 낯선 사람의 첫 귓속말은 확인하는 동안 숨겨지고,\n" ..
        "    정상 레벨로 확인되면 화면 위쪽에 원래 내용이 보입니다.\n\n" ..
        "ㅁ 와우 기본 채팅창에서 동작합니다. WIM 처럼 귓속말을\n" ..
        "    자체 창에 따로 그리는 애드온은 가려지지 않을 수 있어요.\n\n" ..
        "ㅁ 다른 애드온에서 귓속말 소리를 재생하도록 설정되어 있다면\n" ..
        "    소리는 날 수 있지만 화면에 표시는 되지 않습니다.\n\n" ..
        "ㅁ 차단이 되지 않는 애드온이 있다면 밈줌까페에 알려주세요.\n\n" ..
        "ㅁ 무언가 나쁜 연락이 왔었다는 기분도 느끼지 않고\n" ..
        "    온전히 와우를 즐겁게 즐길 수 있습니다.\n\n" ..
        "ㅁ 항상 즐거운 와우 생활 되세요~")

    SA_WhisperWindow = win
end

-- 귓말차단 창 위젯 값 동기화 (전역: 탭 열 때 호출)
function SA_RefreshWhisperLog()
    local win = SA_WhisperWindow
    if not win then return end
    local wb = MimDiceDB and MimDiceDB.whisperBlock
    win.enCb:SetChecked(wb and wb.enabled)
    win.lvBox:SetText(tostring((wb and wb.minLevel) or 60))
end

-- =====================================================================
-- 스킨 옵션창 (탭 3번: 프리셋 + 색 커스텀, 바꾸는 즉시 반영)
-- =====================================================================
-- 기준색(진한 배경)용 어두운 색 10종 - 기본 색상판은 밝은 색 위주라 진한 배경용을 한 줄 추가
local SA_SKIN_DARKS = {
    {0.04,0.04,0.04},{0.09,0.09,0.10},{0.11,0.11,0.12},{0.14,0.14,0.16},{0.09,0.11,0.17},
    {0.07,0.10,0.10},{0.12,0.10,0.07},{0.10,0.07,0.10},{0.06,0.09,0.06},{0.13,0.08,0.08},
}
local SA_SkinColorPop = nil

-- 색 선택 팝업 (기본 색상판 40색 + 진한 배경 10색)
local function SA_OpenSkinColorPop(anchor, onPick)
    if not SA_SkinColorPop then
        local p = CreateFrame("Frame", "MimDice_SkinColorPop", UIParent, "BackdropTemplate")
        p:SetFrameStrata("FULLSCREEN_DIALOG")
        p:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        p:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
        p:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        p:EnableMouse(true)
        local SW, GAP = 22, 3
        local all = {}
        for _, rgb in ipairs(SA_COLOR_PRESETS) do all[#all + 1] = rgb end
        for _, rgb in ipairs(SA_SKIN_DARKS) do all[#all + 1] = rgb end
        local rows = math.ceil(#all / 10)
        p:SetSize(10 * (SW + GAP) - GAP + 16, rows * (SW + GAP) - GAP + 16)
        for idx, rgb in ipairs(all) do
            local col = (idx - 1) % 10
            local row = math.floor((idx - 1) / 10)
            local b = CreateFrame("Button", nil, p)
            b:SetSize(SW, SW)
            b:SetPoint("TOPLEFT", 8 + col * (SW + GAP), -(8 + row * (SW + GAP)))
            local t = b:CreateTexture(nil, "ARTWORK")
            t:SetAllPoints(); t:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetPoint("TOPLEFT", -2, 2); hl:SetPoint("BOTTOMRIGHT", 2, -2)
            hl:SetColorTexture(1, 1, 1, 0.35)
            b.rgb = rgb
            b:SetScript("OnClick", function(self)
                if p.onPick then p.onPick(self.rgb) end
                p:Hide()
            end)
        end
        p:Hide()
        SA_SkinColorPop = p
    end
    SA_SkinColorPop.onPick = onPick
    SA_SkinColorPop:ClearAllPoints()
    SA_SkinColorPop:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
    SA_SkinColorPop:Show()
    SA_SkinColorPop:Raise()
end

-- =====================================================================
-- 폰트 고르기 창 : 동봉 폰트 목록(그 폰트로 미리보기) + 내 폰트(파일명 등록)
-- =====================================================================
local SA_FontWindow
local function SA_CreateFontWindow()
    if SA_FontWindow then return SA_FontWindow end
    local win = CreateFrame("Frame", "SA_FontWindow", UIParent, "BackdropTemplate")
    win:SetWidth(340)
    -- 사운드 설정창처럼 고정 위치: 스킨 창 오른쪽에 붙여서, 창 묶음과 같이 움직인다
    win:SetPoint("TOPLEFT", SA_SkinWindow, "TOPRIGHT", 8, 0)
    win:SetPoint("BOTTOMLEFT", SA_SkinWindow, "BOTTOMRIGHT", 8, 0)
    win:SetFrameStrata("DIALOG")
    win:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    win:SetBackdropColor(0, 0, 0, 0.85)
    win:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    win:EnableMouse(true)
    win:Hide()

    local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    closeBtn.MimDiceIsClose = true   -- 스킨: 닫기(X) 플랫화 대상
    closeBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() win:Hide() end)

    local title = win:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", win, "TOP", 0, -12)
    title:SetFont(MimDiceFontPath(), 14, "OUTLINE")
    title:SetText("폰트 고르기")
    title:SetTextColor(1, 0.82, 0)

    local hint = win:CreateFontString(nil, "OVERLAY")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -34)
    hint:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    hint:SetText("누르면 선택되고, 리로드하면 전체에 적용돼요")
    hint:SetTextColor(0.9, 0.9, 0.9)

    -- 폰트 목록 (스크롤)
    local scroll = CreateFrame("ScrollFrame", "SA_FontWindowScroll", win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -54)
    scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -32, 200)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(280, 10)
    scroll:SetScrollChild(content)
    win.content = content
    win.rows = {}

    -- 내 폰트 등록칸
    local addHelp = win:CreateFontString(nil, "OVERLAY")
    addHelp:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 15, 88)
    addHelp:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -15, 88)
    addHelp:SetFont(MimDiceFontPath(), 10, "OUTLINE")
    addHelp:SetJustifyH("LEFT")
    addHelp:SetWordWrap(true)
    addHelp:SetSpacing(3)
    addHelp:SetText("ㅁ 와우의 기본 Fonts 폴더가 아닙니다.\n"
        .. "(거기는 와우 인게임 글자를 설정하는 곳이에요)\n"
        .. "ㅁ 밈다이스 안의 Fonts 폴더에 폰트 파일을 넣어주세요.\n"
        .. "ㅁ 위치는 Interface\\AddOns\\MimDice\\Fonts 입니다.\n"
        .. "ㅁ 폰트 타입은 TTF, OTF 만 가능합니다.\n"
        .. "ㅁ 파일 이름을 정확하게 적고 [추가]를 누른 다음,\n"
        .. "게임을 껐다가 켜야 폰트 로딩이 됩니다.\n"
        .. "ㅁ 폰트를 새로 넣고나서 게임을 완전히 재시작했다면\n"
        .. "폰트 선택 후 리로드하면 폰트가 적용됩니다.")
    addHelp:SetTextColor(0.8, 0.8, 0.8)

    local addBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    addBox:SetSize(210, 20)
    addBox:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 22, 62)
    addBox:SetAutoFocus(false)
    addBox:SetFont(MimDiceFontPath(), 11, "")

    local addBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    addBtn:SetSize(60, 22)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 10, 0)
    addBtn:SetText("추가")
    addBtn:GetFontString():SetFont(MimDiceFontPath(), 11, "")

    local addMsg = win:CreateFontString(nil, "OVERLAY")
    addMsg:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 15, 44)
    addMsg:SetFont(MimDiceFontPath(), 10, "OUTLINE")
    addMsg:SetText("")
    win.addMsg = addMsg

    local function SA_AddCustomFont()
        local sk = MimDiceDB.skin
        local fname = (addBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if fname == "" then return end
        local low = fname:lower()
        if low:find("%.woff2?$") or low:find("%.ttc$") then
            addMsg:SetText("woff/ttc 는 못 써요. ttf 또는 otf 파일이어야 해요")
            addMsg:SetTextColor(1, 0.4, 0.4)
            return
        end
        if not (low:find("%.ttf$") or low:find("%.otf$")) then fname = fname .. ".ttf" end
        for _, f in ipairs(sk.customFonts) do
            if f == fname then
                addMsg:SetText("이미 목록에 있어요")
                addMsg:SetTextColor(1, 0.8, 0.3)
                return
            end
        end
        if MimDiceFontValid(fname) then
            table.insert(sk.customFonts, fname)
            addBox:SetText(""); addBox:ClearFocus()
            addMsg:SetText("추가했어요! 목록에서 눌러 선택하세요")
            addMsg:SetTextColor(0.45, 1, 0.45)
            SA_RefreshFontWindow()
        else
            addMsg:SetText("파일을 못 찾았어요. 폴더에 넣고 게임을 껐다 켰는지 확인하세요")
            addMsg:SetTextColor(1, 0.4, 0.4)
        end
    end
    addBtn:SetScript("OnClick", SA_AddCustomFont)
    addBox:SetScript("OnEnterPressed", SA_AddCustomFont)
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- 리로드 (폰트는 리로드해야 전체에 적용됨)
    local reloadBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    reloadBtn:SetSize(150, 24)
    reloadBtn:SetPoint("BOTTOM", win, "BOTTOM", 0, 12)
    reloadBtn:SetText("리로드하고 적용")
    reloadBtn:GetFontString():SetFont(MimDiceFontPath(), 11, "")
    reloadBtn:SetScript("OnClick", function() ReloadUI() end)

    table.insert(UISpecialFrames, "SA_FontWindow")   -- ESC 키로 닫히게 등록

    SA_SkinRegisterWindow(win)   -- 폰트 창도 스킨 대상
    SA_FontWindow = win
    SA_SkinRefresh()             -- 스킨이 켜져 있으면 방금 만든 창에도 즉시 적용
    return win
end

-- 폰트 창 목록 새로고침 (전역). 각 줄을 그 폰트로 그려서 미리보기가 된다
function SA_RefreshFontWindow()
    local win = SA_FontWindow
    if not win then return end
    local sk = MimDiceDB.skin
    local list = {}
    for _, f in ipairs(MIMDICE_FONTS) do
        table.insert(list, { key = f.key, name = f.name, file = f.file })
    end
    for _, fname in ipairs(sk.customFonts) do
        table.insert(list, { key = "file:" .. fname, name = fname, file = fname, custom = true })
    end
    local rowH = 24
    for i, e in ipairs(list) do
        local row = win.rows[i]
        if not row then
            row = CreateFrame("Button", nil, win.content)
            row:SetSize(280, rowH - 2)
            row:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, -(i - 1) * rowH)
            local selBg = row:CreateTexture(nil, "BACKGROUND")
            selBg:SetAllPoints(); selBg:SetColorTexture(1, 1, 1, 0.10); selBg:Hide()
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
            local fsName = row:CreateFontString(nil, "OVERLAY")
            fsName:SetPoint("LEFT", row, "LEFT", 4, 0)
            fsName:SetPoint("RIGHT", row, "RIGHT", -22, 0)
            fsName:SetJustifyH("LEFT")
            fsName:SetWordWrap(false)
            local del = CreateFrame("Button", nil, row)   -- 내 폰트 지우기 (X)
            del:SetSize(16, 16)
            del:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            local delFs = del:CreateFontString(nil, "OVERLAY")
            delFs:SetPoint("CENTER")
            delFs:SetFont(MimDiceFontPath(), 11, "OUTLINE")
            delFs:SetText("X")
            delFs:SetTextColor(1, 0.4, 0.4)
            local delHl = del:CreateTexture(nil, "HIGHLIGHT")
            delHl:SetAllPoints(); delHl:SetColorTexture(1, 1, 1, 0.15)
            row.selBg = selBg
            row.fsName = fsName
            row.del = del
            win.rows[i] = row
        end
        local path = e.file and (MIMDICE_FONT_DIR .. e.file) or "Fonts\\2002.ttf"
        local okFont = (not e.custom) or MimDiceFontValid(e.file)
        pcall(row.fsName.SetFont, row.fsName, okFont and path or "Fonts\\2002.ttf", 13, "")
        if okFont then
            row.fsName:SetText(e.name .. "  가나다 ABC 123")
        else
            row.fsName:SetText(e.name .. "  (파일이 없어요)")
        end
        if sk.font == e.key then
            row.selBg:Show()
            row.fsName:SetTextColor(0.45, 1, 0.45)
        else
            row.selBg:Hide()
            row.fsName:SetTextColor(0.9, 0.9, 0.9)
        end
        if e.custom then row.del:Show() else row.del:Hide() end
        row:SetScript("OnClick", function()
            MimDiceDB.skin.font = e.key
            SA_RefreshFontWindow()
            SA_RefreshSkinWindow()
        end)
        row.del:SetScript("OnClick", function()
            for idx, f in ipairs(MimDiceDB.skin.customFonts) do
                if f == e.file then table.remove(MimDiceDB.skin.customFonts, idx); break end
            end
            if MimDiceDB.skin.font == e.key then MimDiceDB.skin.font = "default" end
            SA_RefreshFontWindow()
            SA_RefreshSkinWindow()
        end)
        row:Show()
    end
    for i = #list + 1, #win.rows do win.rows[i]:Hide() end
    win.content:SetHeight(#list * rowH)
end

-- 폰트 창 열고 닫기 (전역: 스킨 창의 [폰트 고르기] 버튼)
function SA_ToggleFontWindow()
    local win = SA_CreateFontWindow()
    if win:IsShown() then
        win:Hide()
    else
        SA_RefreshFontWindow()
        win:Show()
    end
end

local function SA_CreateSkinWindow()
    local mainWin = _G["MainWindow"]
    if not mainWin then return end

    local win = CreateFrame("Frame", "SA_SkinWindow", UIParent, "BackdropTemplate")
    win:SetWidth(380)
    win:SetHeight(505)   -- 내용에 맞춘 고정 높이 (메인창 높이와 무관)
    win:SetPoint("TOPLEFT", mainWin, "TOPRIGHT", 38, 0)
    win:SetFrameStrata("HIGH")
    win:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    win:SetBackdropColor(0, 0, 0, 0.5)
    win:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    win:EnableMouse(true)
    SA_WireBundleDrag(win)   -- 점프 없는 번들 드래그
    win:SetScript("OnHide", function()
        if SA_SkinColorPop then SA_SkinColorPop:Hide() end
        if SA_FontWindow then SA_FontWindow:Hide() end   -- 스킨 창 닫으면 폰트 창도 같이
    end)
    win:Hide()

    local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    closeBtn.MimDiceIsClose = true   -- 스킨: 닫기(X) 플랫화 대상
    closeBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() SA_ToggleSkinWindow() end)

    local title = win:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", win, "TOP", 0, -12)
    title:SetFont(MimDiceFontPath(), 14, "OUTLINE")
    title:SetText("스킨")
    title:SetTextColor(1, 0.82, 0)

    -- ── 스킨 적용 체크 (라벨에 현재 프리셋 이름 표시) ──
    local enCb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    enCb:SetSize(24, 24)
    enCb:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -34)
    enCb:SetScript("OnClick", function(self)
        MimDiceDB.skin.enabled = self:GetChecked() and true or false
        SA_SkinRefresh()
        SA_RefreshSkinWindow()
    end)
    win.enCb = enCb
    local enLabel = win:CreateFontString(nil, "OVERLAY")
    enLabel:SetPoint("LEFT", enCb, "RIGHT", 2, 0)
    enLabel:SetFont(MimDiceFontPath(), 12, "OUTLINE")
    enLabel:SetTextColor(0.9, 0.9, 0.9)
    win.enLabel = enLabel

    -- ── 프리셋 목록 ──
    local presetLabel = win:CreateFontString(nil, "OVERLAY")
    presetLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -80)
    presetLabel:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    presetLabel:SetText("기본 스킨 : 누르면 색이 채워지고 바로 적용됩니다")
    presetLabel:SetTextColor(0.9, 0.9, 0.9)

    -- 2열 그리드 (9종). 선택된 프리셋은 강조 테두리 + 이름 녹색
    win.presetRows = {}
    for i, preset in ipairs(SA_SKIN_PRESETS) do
        local col = (i - 1) % 2
        local rowN = math.floor((i - 1) / 2)
        local row = CreateFrame("Button", nil, win)
        row:SetSize(170, 20)
        row:SetPoint("TOPLEFT", win, "TOPLEFT", 15 + col * 178, -98 - rowN * 22)
        local selBg = row:CreateTexture(nil, "BACKGROUND")   -- 선택 표시 (은은한 배경)
        selBg:SetAllPoints(); selBg:SetColorTexture(1, 1, 1, 0.10); selBg:Hide()
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
        local swb = row:CreateTexture(nil, "BORDER")   -- 스와치 테두리
        swb:SetSize(16, 16); swb:SetPoint("LEFT", 2, 0)
        swb:SetColorTexture(0.5, 0.5, 0.5, 1)
        local sw = row:CreateTexture(nil, "ARTWORK")
        sw:SetPoint("TOPLEFT", swb, "TOPLEFT", 1, -1); sw:SetPoint("BOTTOMRIGHT", swb, "BOTTOMRIGHT", -1, 1)
        sw:SetColorTexture(preset.base[1], preset.base[2], preset.base[3], 1)
        local acc = row:CreateTexture(nil, "ARTWORK")   -- 강조색 미리보기 (스와치 안 작은 점)
        acc:SetSize(5, 5); acc:SetPoint("BOTTOMRIGHT", swb, "BOTTOMRIGHT", -2, 2)
        acc:SetColorTexture(preset.accentText[1], preset.accentText[2], preset.accentText[3], 1)
        local nameFs = row:CreateFontString(nil, "OVERLAY")
        nameFs:SetPoint("LEFT", swb, "RIGHT", 7, 0)
        nameFs:SetFont(MimDiceFontPath(), 11, "")
        nameFs:SetText(preset.name)
        nameFs:SetTextColor(0.9, 0.9, 0.9)
        row.selBg = selBg
        row.nameFs = nameFs
        row:SetScript("OnClick", function()
            local sk = MimDiceDB.skin
            sk.preset = preset.key
            sk.enabled = true
            -- 이 스킨에서 사용자가 조절해 둔 투명도가 있으면 그 값, 없으면 스킨 기본 투명도
            sk.alpha = sk.alphaByPreset[preset.key] or preset.alpha or 0.93
            sk.base = { r = preset.base[1], g = preset.base[2], b = preset.base[3] }
            sk.accentText = { r = preset.accentText[1], g = preset.accentText[2], b = preset.accentText[3] }
            sk.accentHover = { r = preset.accentHover[1], g = preset.accentHover[2], b = preset.accentHover[3] }
            sk.btnHover = { r = preset.accentHover[1], g = preset.accentHover[2], b = preset.accentHover[3] }
            sk.btnHoverA = 0.30
            sk.btnText = { r = 0.92, g = 0.92, b = 0.92 }
            sk.btnTextA = 1
            SA_SkinRefresh()
            SA_RefreshSkinWindow()
        end)
        win.presetRows[preset.key] = row
    end

    -- 10번째 칸: '커스텀 (내 색)' - 사용자가 만진 색이 영구 저장되는 슬롯
    do
        local row = CreateFrame("Button", nil, win)
        row:SetSize(170, 20)
        row:SetPoint("TOPLEFT", win, "TOPLEFT", 15 + 178, -98 - 7 * 22)
        local selBg = row:CreateTexture(nil, "BACKGROUND")
        selBg:SetAllPoints(); selBg:SetColorTexture(1, 1, 1, 0.10); selBg:Hide()
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
        local swb = row:CreateTexture(nil, "BORDER")
        swb:SetSize(16, 16); swb:SetPoint("LEFT", 2, 0)
        swb:SetColorTexture(0.5, 0.5, 0.5, 1)
        local sw = row:CreateTexture(nil, "ARTWORK")
        sw:SetPoint("TOPLEFT", swb, "TOPLEFT", 1, -1); sw:SetPoint("BOTTOMRIGHT", swb, "BOTTOMRIGHT", -1, 1)
        local acc = row:CreateTexture(nil, "ARTWORK")
        acc:SetSize(5, 5); acc:SetPoint("BOTTOMRIGHT", swb, "BOTTOMRIGHT", -2, 2)
        local nameFs = row:CreateFontString(nil, "OVERLAY")
        nameFs:SetPoint("LEFT", swb, "RIGHT", 7, 0)
        nameFs:SetFont(MimDiceFontPath(), 11, "")
        nameFs:SetText("커스텀 (내 색)")
        nameFs:SetTextColor(0.9, 0.9, 0.9)
        row.selBg = selBg
        row.nameFs = nameFs
        row.sw = sw
        row.acc = acc
        row:SetScript("OnClick", function()
            local sk = MimDiceDB.skin
            local c = sk.custom
            sk.preset = "custom"
            sk.enabled = true
            sk.alpha = c.alpha or 0.93
            sk.accentTextA = c.accentTextA or 1
            sk.accentHoverA = c.accentHoverA or 0.30
            sk.base = { r = c.base.r, g = c.base.g, b = c.base.b }
            sk.accentText = { r = c.accentText.r, g = c.accentText.g, b = c.accentText.b }
            sk.accentHover = { r = c.accentHover.r, g = c.accentHover.g, b = c.accentHover.b }
            local cbh = c.btnHover or c.accentHover
            sk.btnHover = { r = cbh.r, g = cbh.g, b = cbh.b }
            sk.btnHoverA = c.btnHoverA or 0.30
            local cbt = c.btnText or { r = 0.92, g = 0.92, b = 0.92 }
            sk.btnText = { r = cbt.r, g = cbt.g, b = cbt.b }
            sk.btnTextA = c.btnTextA or 1
            SA_SkinRefresh()
            SA_RefreshSkinWindow()
        end)
        win.presetRows["custom"] = row
    end

    -- 색을 만지는 순간 '커스텀 (내 색)' 스킨으로 저장/전환 (프리셋을 눌러도 내 색이 안 사라짐)
    local function SA_SkinSaveCustom()
        local sk = MimDiceDB.skin
        sk.preset = "custom"
        sk.custom = {
            alpha = sk.alpha or 0.93,
            accentTextA = sk.accentTextA or 1,
            accentHoverA = sk.accentHoverA or 0.30,
            base = { r = sk.base.r, g = sk.base.g, b = sk.base.b },
            accentText = { r = sk.accentText.r, g = sk.accentText.g, b = sk.accentText.b },
            accentHover = { r = sk.accentHover.r, g = sk.accentHover.g, b = sk.accentHover.b },
            btnHover = { r = sk.btnHover.r, g = sk.btnHover.g, b = sk.btnHover.b },
            btnHoverA = sk.btnHoverA or 0.30,
            btnText = { r = sk.btnText.r, g = sk.btnText.g, b = sk.btnText.b },
            btnTextA = sk.btnTextA or 1,
        }
    end

    -- ── 색 커스텀 (스와치는 우측, 클릭하면 색 팝업) ──
    local customLabel = win:CreateFontString(nil, "OVERLAY")
    customLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -298)
    customLabel:SetFont(MimDiceFontPath(), 11, "OUTLINE")
    customLabel:SetText("색 커스텀 : 오른쪽 네모를 눌러 색을 고르세요")
    customLabel:SetTextColor(0.9, 0.9, 0.9)

    local function mkColorRow(y, labelText, getFn, setFn, opacityOpt)
        local lb = win:CreateFontString(nil, "OVERLAY")
        lb:SetPoint("TOPLEFT", win, "TOPLEFT", 20, y)
        lb:SetFont(MimDiceFontPath(), 11, "")
        lb:SetText(labelText)
        lb:SetTextColor(0.85, 0.85, 0.85)
        local btn = CreateFrame("Button", nil, win)
        btn:SetSize(30, 18)
        btn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -20, y + 2)
        local border = btn:CreateTexture(nil, "BORDER")
        border:SetAllPoints(); border:SetColorTexture(0.6, 0.6, 0.6, 1)
        local swatch = btn:CreateTexture(nil, "ARTWORK")
        swatch:SetPoint("TOPLEFT", 1, -1); swatch:SetPoint("BOTTOMRIGHT", -1, 1)
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetPoint("TOPLEFT", -2, 2); hl:SetPoint("BOTTOMRIGHT", 2, -2)
        hl:SetColorTexture(1, 1, 1, 0.3)
        btn.swatch = swatch
        local function onPicked(r, g, b)
            setFn(r, g, b)
            SA_SkinSaveCustom()   -- 색을 만지면 '커스텀 (내 색)'에 저장
            SA_SkinRefresh()
            SA_RefreshSkinWindow()
        end
        btn:SetScript("OnClick", function()
            local cur = getFn()
            -- 와우 내장 색상환(풀 컬러 팔레트). 드래그하는 동안 실시간으로 반영됨
            if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
                ColorPickerFrame:SetupColorPickerAndShow({
                    r = cur.r, g = cur.g, b = cur.b,
                    hasOpacity = opacityOpt ~= nil,
                    opacity = opacityOpt and opacityOpt.get() or nil,
                    swatchFunc = function()
                        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                        onPicked(nr, ng, nb)
                    end,
                    opacityFunc = opacityOpt and function()
                        local a = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or 1
                        opacityOpt.set(a)
                        SA_AlphaBoxSync(a)
                        SA_SkinRefresh()
                    end or nil,
                    cancelFunc = function(prev)
                        if prev then
                            onPicked(prev.r, prev.g, prev.b)
                            if opacityOpt and prev.a then opacityOpt.set(prev.a); SA_SkinRefresh() end
                        end
                    end,
                })
                -- 색상환의 '# 코드' 칸 붙여넣기 즉시 적용 (엔터 불필요)
                SA_WatchColorPickerHex(function(r, g, b) onPicked(r, g, b) end)
                if opacityOpt then
                    SA_ShowAlphaBox(opacityOpt.get, function(a)
                        opacityOpt.set(a)
                        SA_SkinRefresh()
                    end)
                else
                    SA_HideAlphaBox()
                end
            else
                -- 구버전 클라이언트 대비: 격자 색상판
                SA_OpenSkinColorPop(btn, function(rgb) onPicked(rgb[1], rgb[2], rgb[3]) end)
            end
        end)
        return btn
    end
    win.swBase = mkColorRow(-320, "메인 배경 색",
        function() return MimDiceDB.skin.base end,
        function(r, g, b) MimDiceDB.skin.base = { r = r, g = g, b = b } end,
        {
            get = function() return MimDiceDB.skin.alpha or 0.93 end,
            set = function(a)
                local sk = MimDiceDB.skin
                sk.alpha = a
                sk.alphaByPreset[sk.preset] = a               -- 이 스킨의 투명도로 기억
                if sk.preset == "custom" and sk.custom then sk.custom.alpha = a end
            end,
        })
    win.swText = mkColorRow(-346, "활성탭 글자색",
        function() return MimDiceDB.skin.accentText end,
        function(r, g, b) MimDiceDB.skin.accentText = { r = r, g = g, b = b } end,
        {
            get = function() return MimDiceDB.skin.accentTextA or 1 end,
            set = function(a) MimDiceDB.skin.accentTextA = a end,
        })
    win.swHover = mkColorRow(-372, "활성 탭 배경색",
        function() return MimDiceDB.skin.accentHover end,
        function(r, g, b) MimDiceDB.skin.accentHover = { r = r, g = g, b = b } end,
        {
            get = function() return MimDiceDB.skin.accentHoverA or 0.30 end,
            set = function(a) MimDiceDB.skin.accentHoverA = a end,
        })
    win.swBtnHover = mkColorRow(-398, "버튼 마우스오버",
        function() return MimDiceDB.skin.btnHover end,
        function(r, g, b) MimDiceDB.skin.btnHover = { r = r, g = g, b = b } end,
        {
            get = function() return MimDiceDB.skin.btnHoverA or 0.30 end,
            set = function(a) MimDiceDB.skin.btnHoverA = a end,
        })
    win.swBtnText = mkColorRow(-424, "버튼 글자색",
        function() return MimDiceDB.skin.btnText end,
        function(r, g, b) MimDiceDB.skin.btnText = { r = r, g = g, b = b } end,
        {
            get = function() return MimDiceDB.skin.btnTextA or 1 end,
            set = function(a) MimDiceDB.skin.btnTextA = a end,
        })


    -- ── 색 기본값 복원 (현재 스킨의 원래 색/투명도로) ──
    local resetBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    resetBtn:SetSize(110, 22)
    resetBtn:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -468)
    resetBtn:SetText("색 기본값 복원")
    resetBtn:GetFontString():SetFont(MimDiceFontPath(), 10, "")
    resetBtn:SetScript("OnClick", function()
        local sk = MimDiceDB.skin
        local preset = SA_SkinPresetByKey(sk.preset == "custom" and "darkgray" or sk.preset)
        sk.alphaByPreset[sk.preset] = nil                 -- 조절해 둔 투명도도 초기화
        sk.alpha = preset.alpha or 0.93
        sk.accentTextA, sk.accentHoverA = 1, 0.30
        sk.btnHoverA = 0.30
        sk.btnText = { r = 0.92, g = 0.92, b = 0.92 }
        sk.btnTextA = 1
        sk.base = { r = preset.base[1], g = preset.base[2], b = preset.base[3] }
        sk.accentText = { r = preset.accentText[1], g = preset.accentText[2], b = preset.accentText[3] }
        sk.accentHover = { r = preset.accentHover[1], g = preset.accentHover[2], b = preset.accentHover[3] }
        sk.btnHover = { r = preset.accentHover[1], g = preset.accentHover[2], b = preset.accentHover[3] }
        if sk.preset == "custom" then                     -- 커스텀 슬롯은 다크 그레이 값으로 리셋
            sk.custom = {
                alpha = sk.alpha,
                base = { r = sk.base.r, g = sk.base.g, b = sk.base.b },
                accentText = { r = sk.accentText.r, g = sk.accentText.g, b = sk.accentText.b },
                accentHover = { r = sk.accentHover.r, g = sk.accentHover.g, b = sk.accentHover.b },
                btnHover = { r = sk.btnHover.r, g = sk.btnHover.g, b = sk.btnHover.b },
                btnText = { r = sk.btnText.r, g = sk.btnText.g, b = sk.btnText.b },
            }
        end
        SA_SkinRefresh()
        SA_RefreshSkinWindow()
    end)


    -- ── 폰트 고르기 (버튼에 현재 폰트 이름 표시) ──
    local fontBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    fontBtn:SetSize(225, 22)
    fontBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -15, -468)
    fontBtn:SetText("폰트 고르기")
    fontBtn:GetFontString():SetFont(MimDiceFontPath(), 10, "")
    fontBtn:SetScript("OnClick", function() SA_ToggleFontWindow() end)
    win.fontBtn = fontBtn

    SA_SkinRegisterWindow(win)   -- 스킨 창 자신도 스킨 대상
    SA_SkinWindow = win
end

-- 스킨 창 위젯 값 동기화 (전역: 탭 열 때/설정 변경 시 호출)
function SA_RefreshSkinWindow()
    local win = SA_SkinWindow
    if not win then return end
    local sk = MimDiceDB.skin
    local presetName = (sk.preset == "custom") and "커스텀 (내 색)" or SA_SkinPresetByKey(sk.preset).name
    win.enCb:SetChecked(sk.enabled)
    win.enLabel:SetText("스킨 적용 (" .. presetName .. ")")
    -- 커스텀 슬롯 스와치를 저장된 내 색으로 갱신
    local cr = win.presetRows["custom"]
    if cr and sk.custom then
        cr.sw:SetColorTexture(sk.custom.base.r, sk.custom.base.g, sk.custom.base.b, 1)
        cr.acc:SetColorTexture(sk.custom.accentText.r, sk.custom.accentText.g, sk.custom.accentText.b, 1)
    end
    for key, row in pairs(win.presetRows) do
        if key == sk.preset and sk.enabled then
            row.selBg:Show()
            row.nameFs:SetTextColor(0.45, 1, 0.45)
        else
            row.selBg:Hide()
            row.nameFs:SetTextColor(0.9, 0.9, 0.9)
        end
    end
    win.swBase.swatch:SetColorTexture(sk.base.r, sk.base.g, sk.base.b, 1)
    win.swText.swatch:SetColorTexture(sk.accentText.r, sk.accentText.g, sk.accentText.b, 1)
    win.swHover.swatch:SetColorTexture(sk.accentHover.r, sk.accentHover.g, sk.accentHover.b, 1)
    win.swBtnHover.swatch:SetColorTexture(sk.btnHover.r, sk.btnHover.g, sk.btnHover.b, 1)
    local bt = sk.btnText or { r = 0.92, g = 0.92, b = 0.92 }
    win.swBtnText.swatch:SetColorTexture(bt.r, bt.g, bt.b, 1)
    if win.fontBtn then win.fontBtn:SetText("폰트 : " .. MimDiceFontName()) end
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
            SA_CreateWhisperWindow()
            SA_CreateSkinWindow()
            -- 사운드/귓말차단 창 + 메인창에 스킨 적용 (켜져 있을 때만)
            SA_SkinRegisterWindow(SA_OptionWindow)
            SA_SkinRegisterWindow(SA_WhisperWindow)
            SA_SkinRefresh()
            MimDiceApplyFontToXML()   -- XML 에 박힌 글자(제목/하이/로우 등)에 선택 폰트 적용
        else
            C_Timer.After(0.1, TryInit)
        end
    end
    TryInit()
end
