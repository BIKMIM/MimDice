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
    -- 반복 알림: "once"=신청 올 때 1회 / "repeat"=대기 신청자 있는 동안 repeatInterval초마다 재알림
    if pa.repeatMode == nil then pa.repeatMode = "once" end
    if pa.repeatInterval == nil then pa.repeatInterval = 5 end
    -- 표시 지속: "fade"=duration초 뒤 페이드아웃 / "stay"=대기 신청자 없어질 때까지 계속 표시
    if pa.displayMode == nil then pa.displayMode = "fade" end
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
    fs:SetFont("Fonts\\2002.ttf", 24, "THICKOUTLINE")
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
    lbl:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    lbl:SetTextColor(0.9, 0.9, 0.9)
    lbl:SetText("위치 (중앙 0,0)   X")

    local function mkBox(getF, setF)
        local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        e:SetSize(50, 20)
        e:SetAutoFocus(false)
        e:SetFont("Fonts\\2002.ttf", 11, "")
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
    lblY:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
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
        b:GetFontString():SetFont("Fonts\\2002.ttf", 10, "")
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

local SA_deathTestUntil = 0   -- 죽음 테스트 중복 방지: 이 시각(GetTime)까지 재실행 억제

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
    -- (화면 클램프 없음: 메인창처럼 화면 밖으로도 이동 가능 — 번들로 함께 이동)
    win:RegisterForDrag("LeftButton")
    -- 설정창을 잡고 끌면 본체(MainWindow)를 움직임 → 옵션창·설정창이 앵커로 붙어 하나로 뭉쳐 이동
    win:SetScript("OnDragStart", function()
        local mw = _G.MainWindow
        if mw and mw:IsMovable() then mw:StartMoving() end
    end)
    win:SetScript("OnDragStop", function()
        local mw = _G.MainWindow
        if mw then mw:StopMovingOrSizing() end
        if MimDice_SaveAnchors then MimDice_SaveAnchors() end
    end)

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
    soundBox:SetFont("Fonts\\2002.ttf", 11, "")
    win.soundBox = soundBox
    SA_WirePlaceholder(soundBox)

    -- 내장 선택 시: 사운드 선택 팝업 버튼 (soundBox 자리, 토글로 교체 표시)
    local soundSelectBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    soundSelectBtn:SetSize(135, 22)
    soundSelectBtn:SetPoint("TOPLEFT", win, "TOPLEFT", 157, -56)
    do
        local fs = soundSelectBtn:GetFontString()
        fs:SetFont("Fonts\\2002.ttf", 10, "")
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
    enableLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
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
    local SWATCH = 24
    local GAP = 4
    local startX, startY = 18, -242
    for idx, rgb in ipairs(SA_COLOR_PRESETS) do
        local colN = (idx - 1) % SA_PALETTE_COLS
        local rowN = math.floor((idx - 1) / SA_PALETTE_COLS)
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
    local posRefresh, posX, posY = SA_AddPosRow(win, -368,
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
            lockBtn:SetText("위치 잠금")
        end
    end

    -- 기본값으로 초기화 (글씨 80, 중앙, 마력주입 바 아래)
    local resetBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    resetBtn:SetSize(70, 24)
    resetBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 155, 14)   -- 340폭 기준 3버튼(110/70/70) 균등 간격 30px
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

    -- 테스트: 실제처럼 메시지(페이드로 사라짐) + 사운드 확인 (마스터 off여도 재생)
    local testBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    testBtn:SetSize(70, 24)
    testBtn:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -15, 14)
    testBtn:SetText("테스트")
    testBtn:GetFontString():SetFont("Fonts\\2002.ttf", 11, "")
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
    -- (화면 클램프 없음: 메인창처럼 화면 밖으로도 이동 가능 — 번들로 함께 이동)
    win:RegisterForDrag("LeftButton")
    -- 설정창을 잡고 끌면 본체(MainWindow)를 움직임 → 옵션창·설정창이 앵커로 붙어 하나로 뭉쳐 이동
    win:SetScript("OnDragStart", function()
        local mw = _G.MainWindow
        if mw and mw:IsMovable() then mw:StartMoving() end
    end)
    win:SetScript("OnDragStop", function()
        local mw = _G.MainWindow
        if mw then mw:StopMovingOrSizing() end
        if MimDice_SaveAnchors then MimDice_SaveAnchors() end
    end)
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
    soundBox:SetFont("Fonts\\2002.ttf", 11, "")
    win.soundBox = soundBox
    SA_WirePlaceholder(soundBox)

    -- 내장 선택 시: 사운드 선택 팝업 버튼 (soundBox 자리, 토글로 교체 표시)
    local soundSelectBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    soundSelectBtn:SetSize(135, 22)
    soundSelectBtn:SetPoint("TOPLEFT", win, "TOPLEFT", 157, -56)
    do
        local fs = soundSelectBtn:GetFontString()
        fs:SetFont("Fonts\\2002.ttf", 10, "")
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
    barLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
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

    -- 바 색상 그리드 (28색)
    local colorLabel = win:CreateFontString(nil, "OVERLAY")
    colorLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -112)
    colorLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    colorLabel:SetText("바 색상")
    colorLabel:SetTextColor(0.9, 0.9, 0.9)

    win.swatches = {}
    local SWATCH, GAP = 24, 4
    local startX, startY = 18, -132
    for idx, rgb in ipairs(SA_COLOR_PRESETS) do
        local colN = (idx - 1) % SA_PALETTE_COLS
        local rowN = math.floor((idx - 1) / SA_PALETTE_COLS)
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
    local posRefresh, posX, posY = SA_AddPosRow(win, -464,
        function() return MimDiceDB.buffTrack[key].x end,
        function(v) MimDiceDB.buffTrack[key].x = v end,
        function() return MimDiceDB.buffTrack[key].y end,
        function(v) MimDiceDB.buffTrack[key].y = v end,
        function() SA_UpdateBuffBar(key) end)
    win.posRefresh = posRefresh

    -- 입력칸 탭/엔터 순환: 가로 → 세로 → 글씨 → 투명도 → X → Y → (가로)
    SA_ChainTabEnter({ win.wSlider.edit, win.hSlider.edit, win.tfSlider.edit, win.aSlider.edit, posX, posY })

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
        lockBtn:SetText(MimDiceDB.buffTrack[key].locked and "위치 잠금 해제" or "위치 잠금")
    end

    -- 기본값으로 초기화
    local resetBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    resetBtn:SetSize(70, 24)
    resetBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 155, 14)   -- 340폭 기준 3버튼(110/70/70) 균등 간격 30px
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

    -- 테스트: 실제 발동처럼 사운드 + (바 표시 설정 시) 실제 지속시간 카운트다운 (블러드 40초 → 0.0)
    local previewBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    previewBtn:SetSize(70, 24)
    previewBtn:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -15, 14)
    previewBtn:SetText("테스트")
    previewBtn:GetFontString():SetFont("Fonts\\2002.ttf", 11, "")
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
    count:SetFont("Fonts\\2002.ttf", 14, "OUTLINE")
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
    pcall(function()
        f:EnableMouse(true)
        if f.SetMouseClickEnabled then f:SetMouseClickEnabled(clickable) end
        if f.SetMouseMotionEnabled then f:SetMouseMotionEnabled(true) end
    end)
end

-- 크기/위치/글씨 레이아웃만 적용 (표시 여부와 무관, 재귀 없음)
local function SA_ApplyBattleResIconLayout(f, br)
    if f.isMoving then return end   -- 드래그 중엔 위치/크기 안 건드림 (되돌아가는 문제 방지)
    local size = br.iconSize or 40
    f:SetSize(size, size)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", br.iconX or 0, br.iconY or 0)
    f.count:SetFont("Fonts\\2002.ttf", math.max(8, math.floor(size * 0.4)), "OUTLINE")
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
    title:SetFont("Fonts\\2002.ttf", 12, "OUTLINE")
    title:SetText("사운드 선택 (▶ 미리듣기)")
    title:SetTextColor(1, 0.82, 0)

    -- 대화(Dialog) 채널 사용 안내 (최상단)
    local note = p:CreateFontString(nil, "OVERLAY")
    note:SetPoint("TOPLEFT", 12, -28)
    note:SetWidth(306); note:SetJustifyH("LEFT"); note:SetWordWrap(true)
    note:SetFont("Fonts\\2002.ttf", 10, "")
    note:SetText("· 긴 사운드파일도 재생가능하도록 주음량대신 대화 채널을 사용합니다.")
    note:SetTextColor(0.7, 0.7, 0.7)

    local closeBtn = CreateFrame("Button", nil, p, "UIPanelCloseButton")
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
        nameFS:SetFont("Fonts\\2002.ttf", 11, "")
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
        play:GetFontString():SetFont("Fonts\\2002.ttf", 9, "")
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
    win:RegisterForDrag("LeftButton")
    -- 설정창을 잡고 끌면 본체(MainWindow)를 움직임 → 옵션창·설정창이 앵커로 붙어 하나로 뭉쳐 이동
    win:SetScript("OnDragStart", function()
        local mw = _G.MainWindow
        if mw and mw:IsMovable() then mw:StartMoving() end
    end)
    win:SetScript("OnDragStop", function()
        local mw = _G.MainWindow
        if mw then mw:StopMovingOrSizing() end
        if MimDice_SaveAnchors then MimDice_SaveAnchors() end
    end)
    -- 설정창을 닫으면(X/ESC/연쇄) 그룹 정책대로 복귀 + 사운드 팝업 닫기 + 아이콘 위치 자동 잠금
    win:SetScript("OnHide", function()
        if SA_SoundPicker then SA_SoundPicker:Hide() end
        local b = MimDiceDB and MimDiceDB.battleRes
        if b and not b.iconLocked then b.iconLocked = true end
        SA_RefreshBattleResIconState()
    end)

    local title = win:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", win, "TOP", 0, -12)
    title:SetFont("Fonts\\2002.ttf", 13, "OUTLINE")
    title:SetText("전투부활 설정 (공용)")
    title:SetTextColor(1, 0.82, 0)

    local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() win:Hide() end)

    -- ── 재생 사운드 (내장/커스텀/ID) — 메인 옵션창에서 이리로 이동 ──
    local soundLabel = win:CreateFontString(nil, "OVERLAY")
    soundLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -40)
    soundLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
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
    soundBox:SetFont("Fonts\\2002.ttf", 11, "")
    SA_WirePlaceholder(soundBox)

    -- 내장 선택 시: 사운드 선택 팝업 버튼 (soundBox 자리, 토글로 교체 표시)
    local soundSelectBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    soundSelectBtn:SetSize(135, 22)
    soundSelectBtn:SetPoint("TOPLEFT", win, "TOPLEFT", 157, -60)
    do
        local fs = soundSelectBtn:GetFontString()
        fs:SetFont("Fonts\\2002.ttf", 10, "")
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
    enLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    enLabel:SetText("전투부활 아이콘 표시 (다른 애드온 쓰면 끄기)")
    enLabel:SetTextColor(0.9, 0.9, 0.9)
    enCb:SetScript("OnClick", function(self)
        MimDiceDB.battleRes.iconEnabled = self:GetChecked() and true or false
        SA_RefreshBattleResIconState()
    end)
    win.enCb = enCb

    -- 아이콘 크기 슬라이더
    win.sizeSlider = SA_MakeNumberSlider(win, "MimDice_BRIconSize", -148, "아이콘 크기", 16, 128,
        function() return MimDiceDB.battleRes.iconSize end,
        function(v) MimDiceDB.battleRes.iconSize = v end,
        function() SA_UpdateBattleResIcon() end)

    -- 위치 X/Y 직접 입력
    local posRefresh, posX, posY = SA_AddPosRow(win, -210,
        function() return MimDiceDB.battleRes.iconX end,
        function(v) MimDiceDB.battleRes.iconX = v end,
        function() return MimDiceDB.battleRes.iconY end,
        function(v) MimDiceDB.battleRes.iconY = v end,
        function() SA_UpdateBattleResIcon() end)
    win.posRefresh = posRefresh
    SA_ChainTabEnter({ win.sizeSlider.edit, posX, posY })

    -- 안내문
    local hint = win:CreateFontString(nil, "OVERLAY")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -250)
    hint:SetFont("Fonts\\2002.ttf", 10, "")
    hint:SetTextColor(0.7, 0.7, 0.7)
    hint:SetWidth(310); hint:SetJustifyH("LEFT")
    hint:SetText("· '위치 잠금 해제' 후 아이콘을 드래그해 옮기세요.")

    -- 위치 잠금/해제
    local lockBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    lockBtn:SetSize(110, 24)
    lockBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 15, 14)
    lockBtn:GetFontString():SetFont("Fonts\\2002.ttf", 10, "")
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
    resetBtn:GetFontString():SetFont("Fonts\\2002.ttf", 11, "")
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
    testBtn:GetFontString():SetFont("Fonts\\2002.ttf", 11, "")
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

    win:Hide()
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
    if #stats > 0 then segs[#segs+1] = table.concat(stats, " / ") end
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
    if #stats > 0 then segs[#segs+1] = table.concat(stats, " / ") end
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
    fs:SetFont("Fonts\\2002.ttf", 30, "THICKOUTLINE")
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
    f.bg:SetColorTexture(0, 0, 0, pa.bgAlpha or 0.5); f.bg:Show()
    f:SetEditBorder(false)
    if not InCombatLockdown() then f:EnableMouse(false) end
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", pa.x or 0, pa.y or 400)
    f.text:SetFont("Fonts\\2002.ttf", pa.fontSize or 30, "THICKOUTLINE")

    local col = pa.color or { r = 0.3, g = 1, b = 0.3 }
    local hex = string.format("%02x%02x%02x", (col.r or 0.3)*255, (col.g or 1)*255, (col.b or 0.3)*255)
    local msg = "|cff" .. hex .. (pa.prefix or "새 파티 신청!") .. "|r"
    local info = preview and SA_PartyPreviewText() or SA_PartyApplicantText(appID)
    if info and info ~= "" then msg = msg .. "  " .. info end
    f.text:SetText(msg)
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
    f.bg:SetColorTexture(0, 0, 0, pa.bgAlpha or 0.5); f.bg:Show()
    f:SetEditBorder(true)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", pa.x or 0, pa.y or 400)
    f.text:SetFont("Fonts\\2002.ttf", pa.fontSize or 30, "THICKOUTLINE")
    local col = pa.color or { r = 0.3, g = 1, b = 0.3 }
    local hex = string.format("%02x%02x%02x", (col.r or 0.3)*255, (col.g or 1)*255, (col.b or 0.3)*255)
    local info = SA_PartyPreviewText()
    local msg = "|cff" .. hex .. (pa.prefix or "새 파티 신청!") .. "|r"
    if info and info ~= "" then msg = msg .. "  " .. info end
    f.text:SetText(msg)
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
       or not SA_PartyCanInvite() then
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
           or not SA_PartyCanInvite() then SA_StopPartyRepeat(); return end
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
    if not SA_PartyCanInvite() then SA_StopPartyRepeat(); return end
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
    win:EnableMouse(true); win:SetMovable(true)   -- 클램프 없음: 메인창처럼 화면 밖 이동 가능
    win:RegisterForDrag("LeftButton")
    -- 설정창을 잡고 끌면 본체(MainWindow)를 움직임 → 옵션창·설정창이 앵커로 붙어 하나로 뭉쳐 이동
    win:SetScript("OnDragStart", function()
        local mw = _G.MainWindow
        if mw and mw:IsMovable() then mw:StartMoving() end
    end)
    win:SetScript("OnDragStop", function()
        local mw = _G.MainWindow
        if mw then mw:StopMovingOrSizing() end
        if MimDice_SaveAnchors then MimDice_SaveAnchors() end
    end)
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
    title:SetFont("Fonts\\2002.ttf", 13, "OUTLINE")
    title:SetText("파티 신청 알림 설정 (공용)")
    title:SetTextColor(1, 0.82, 0)

    local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() win:Hide() end)

    -- ── 재생 사운드 ─────────────────────────
    local soundLabel = win:CreateFontString(nil, "OVERLAY")
    soundLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -36)
    soundLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    soundLabel:SetText("재생 사운드 : 아래 3개 중 하나 선택")
    soundLabel:SetTextColor(0.9, 0.9, 0.9)

    win.typeRefresh = SA_MakeTypeSelector(win, 15, -56,
        function() return MimDiceDB.partyAlert.soundType end,
        function(t) MimDiceDB.partyAlert.soundType = t; win.RefreshSoundRow() end)

    local soundBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    soundBox:SetSize(135, 22)
    soundBox:SetPoint("TOPLEFT", win, "TOPLEFT", 157, -56)
    soundBox:SetAutoFocus(false); soundBox:SetFont("Fonts\\2002.ttf", 11, "")
    win.soundBox = soundBox
    SA_WirePlaceholder(soundBox)

    local soundSelectBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    soundSelectBtn:SetSize(135, 22)
    soundSelectBtn:SetPoint("TOPLEFT", win, "TOPLEFT", 157, -56)
    do
        local fs = soundSelectBtn:GetFontString()
        fs:SetFont("Fonts\\2002.ttf", 10, ""); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
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

    -- ── 문구 입력 (prefix) ──
    local prefixLabel = win:CreateFontString(nil, "OVERLAY")
    prefixLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -84)
    prefixLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    prefixLabel:SetText("화면 문구 (예: 새 파티 신청!)")
    prefixLabel:SetTextColor(0.9, 0.9, 0.9)
    local prefixBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    prefixBox:SetSize(200, 22)
    prefixBox:SetPoint("TOPLEFT", win, "TOPLEFT", 20, -104)
    prefixBox:SetAutoFocus(false); prefixBox:SetFont("Fonts\\2002.ttf", 12, "")
    prefixBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then MimDiceDB.partyAlert.prefix = self:GetText(); SA_PartyRefreshPreview() end
    end)
    prefixBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    win.prefixBox = prefixBox

    -- ── 표시 항목 체크 (특성 / 아이템렙 / 쐐기점수) ──
    local itemLabel = win:CreateFontString(nil, "OVERLAY")
    itemLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -132)
    itemLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    itemLabel:SetText("표시 항목")
    itemLabel:SetTextColor(0.9, 0.9, 0.9)

    local function mkShowCb(x, field, text)
        local cb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", win, "TOPLEFT", x, -148)
        cb:SetScript("OnClick", function(self)
            MimDiceDB.partyAlert[field] = self:GetChecked() and true or false
            SA_PartyRefreshPreview()
        end)
        local lb = win:CreateFontString(nil, "OVERLAY")
        lb:SetPoint("LEFT", cb, "RIGHT", 0, 0)
        lb:SetFont("Fonts\\2002.ttf", 10, "OUTLINE")
        lb:SetText(text); lb:SetTextColor(0.9, 0.9, 0.9)
        return cb
    end
    win.nameCb  = mkShowCb(15,  "showName",      "닉네임")
    win.specCb  = mkShowCb(85,  "showSpec",      "특성")
    win.ilvlCb  = mkShowCb(140, "showItemLevel", "아이템렙")
    win.scoreCb = mkShowCb(225, "showScore",     "쐐기점수")

    -- ── 글씨 크기 ──
    win.sizeSlider = SA_MakeNumberSlider(win, "MimDice_PartySizeSlider", -180, "글씨 크기", 12, 120,
        function() return MimDiceDB.partyAlert.fontSize end,
        function(v) MimDiceDB.partyAlert.fontSize = v end,
        function() SA_PartyRefreshPreview() end)

    -- ── 색상 그리드 ──
    local colorLabel = win:CreateFontString(nil, "OVERLAY")
    colorLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -236)
    colorLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    colorLabel:SetText("문구 색상")
    colorLabel:SetTextColor(0.9, 0.9, 0.9)
    win.swatches = {}
    local SWATCH, GAP = 24, 4
    local startX, startY = 18, -256
    for idx, rgb in ipairs(SA_COLOR_PRESETS) do
        local colN = (idx - 1) % SA_PALETTE_COLS
        local rowN = math.floor((idx - 1) / SA_PALETTE_COLS)
        local sw = CreateFrame("Button", nil, win)
        sw:SetSize(SWATCH, SWATCH)
        sw:SetPoint("TOPLEFT", win, "TOPLEFT", startX + colN*(SWATCH+GAP), startY - rowN*(SWATCH+GAP))
        local sel = sw:CreateTexture(nil, "BACKGROUND")
        sel:SetPoint("TOPLEFT", -2, 2); sel:SetPoint("BOTTOMRIGHT", 2, -2)
        sel:SetColorTexture(1, 1, 1, 1); sel:Hide(); sw.sel = sel
        local tex = sw:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(); tex:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
        sw:SetScript("OnClick", function()
            MimDiceDB.partyAlert.color = { r = rgb[1], g = rgb[2], b = rgb[3] }
            for _, o in ipairs(win.swatches) do o.sel:Hide() end
            sw.sel:Show()
            SA_PartyRefreshPreview()
        end)
        win.swatches[idx] = sw
    end

    -- ── 배경 투명도 (실제 알림 배경 검정 반투명도, 0=배경없음) ──
    local bgLabel = win:CreateFontString(nil, "OVERLAY")
    bgLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -374)
    bgLabel:SetFont("Fonts\\2002.ttf", 10, "OUTLINE")
    bgLabel:SetText("배경 투명도"); bgLabel:SetTextColor(0.9, 0.9, 0.9)
    local bgBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    bgBox:SetSize(38, 20)
    bgBox:SetPoint("LEFT", bgLabel, "RIGHT", 12, 0)
    bgBox:SetAutoFocus(false); bgBox:SetFont("Fonts\\2002.ttf", 11, "")
    bgBox:SetNumeric(true); bgBox:SetMaxLetters(3); bgBox:SetJustifyH("CENTER")
    local bgSuffix = win:CreateFontString(nil, "OVERLAY")
    bgSuffix:SetPoint("LEFT", bgBox, "RIGHT", 6, 0)
    bgSuffix:SetFont("Fonts\\2002.ttf", 10, "OUTLINE")
    bgSuffix:SetText("% (0=배경없음, 실제 알림에 적용)"); bgSuffix:SetTextColor(0.7, 0.7, 0.7)
    bgBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local v = tonumber(self:GetText())
        if v then
            v = math.max(0, math.min(100, v))
            MimDiceDB.partyAlert.bgAlpha = v / 100
            SA_PartyRefreshPreview()
        end
    end)
    bgBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    win.bgBox = bgBox

    -- ── 알림 방식: 반복 알림 / 표시 지속 ──
    -- 반복 알림(놓침 방지): 켜면 대기 신청자가 있는 동안 N초마다 재알림, 끄면 신청 올 때 1회만
    local repeatCb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    repeatCb:SetSize(22, 22)
    repeatCb:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -406)
    local repeatLb = win:CreateFontString(nil, "OVERLAY")
    repeatLb:SetPoint("LEFT", repeatCb, "RIGHT", 0, 0)
    repeatLb:SetFont("Fonts\\2002.ttf", 10, "OUTLINE")
    repeatLb:SetText("반복 알림"); repeatLb:SetTextColor(0.9, 0.9, 0.9)
    local repeatBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    repeatBox:SetSize(38, 20)
    repeatBox:SetPoint("LEFT", repeatCb, "RIGHT", 58, 0)
    repeatBox:SetAutoFocus(false); repeatBox:SetFont("Fonts\\2002.ttf", 11, "")
    repeatBox:SetNumeric(true); repeatBox:SetMaxLetters(3); repeatBox:SetJustifyH("CENTER")
    local repeatSuffix = win:CreateFontString(nil, "OVERLAY")
    repeatSuffix:SetPoint("LEFT", repeatBox, "RIGHT", 6, 0)
    repeatSuffix:SetFont("Fonts\\2002.ttf", 10, "OUTLINE")
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
    local displayCb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    displayCb:SetSize(22, 22)
    displayCb:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -434)
    local displayLb = win:CreateFontString(nil, "OVERLAY")
    displayLb:SetPoint("LEFT", displayCb, "RIGHT", 0, 0)
    displayLb:SetFont("Fonts\\2002.ttf", 10, "OUTLINE")
    displayLb:SetText("자동 숨김"); displayLb:SetTextColor(0.9, 0.9, 0.9)
    local durationBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    durationBox:SetSize(38, 20)
    durationBox:SetPoint("LEFT", displayCb, "RIGHT", 58, 0)
    durationBox:SetAutoFocus(false); durationBox:SetFont("Fonts\\2002.ttf", 11, "")
    durationBox:SetNumeric(true); durationBox:SetMaxLetters(3); durationBox:SetJustifyH("CENTER")
    local durationSuffix = win:CreateFontString(nil, "OVERLAY")
    durationSuffix:SetPoint("LEFT", durationBox, "RIGHT", 6, 0)
    durationSuffix:SetFont("Fonts\\2002.ttf", 10, "OUTLINE")
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

    -- ── 위치 X/Y ──
    local posRefresh, posX, posY = SA_AddPosRow(win, -468,
        function() return MimDiceDB.partyAlert.x end,
        function(v) MimDiceDB.partyAlert.x = v end,
        function() return MimDiceDB.partyAlert.y end,
        function(v) MimDiceDB.partyAlert.y = v end,
        function() SA_PartyRefreshPreview() end)
    win.posRefresh = posRefresh
    SA_ChainTabEnter({ win.sizeSlider.edit, bgBox, repeatBox, durationBox, posX, posY })

    -- ── 위치 잠금 / 기본값 / 미리보기 ──
    local lockBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    lockBtn:SetSize(110, 24)
    lockBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 15, 14)
    lockBtn:GetFontString():SetFont("Fonts\\2002.ttf", 10, "")
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
    resetBtn:GetFontString():SetFont("Fonts\\2002.ttf", 11, "")
    resetBtn:SetScript("OnClick", function()
        local pa = MimDiceDB.partyAlert
        pa.fontSize, pa.x, pa.y = 30, 0, 400
        pa.color = { r = 0.3, g = 1, b = 0.3 }
        pa.prefix = "새 파티 신청!"
        pa.showName, pa.showSpec, pa.showItemLevel, pa.showScore = true, true, true, true
        pa.bgAlpha = 0.5
        pa.repeatMode, pa.repeatInterval = "once", 5
        pa.displayMode, pa.duration = "fade", 4
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
    testBtn:GetFontString():SetFont("Fonts\\2002.ttf", 11, "")
    testBtn:SetScript("OnClick", function() SA_ShowPartyAlert(true) end)

    win:Hide()
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
    win.bgBox:SetText(tostring(math.floor((pa.bgAlpha or 0.5) * 100 + 0.5)))
    win.repeatCb:SetChecked(pa.repeatMode == "repeat")
    win.repeatBox:SetText(tostring(pa.repeatInterval or 5))
    win.displayCb:SetChecked(pa.displayMode ~= "stay")   -- 자동숨김(fade)=체크, 계속표시(stay)=해제
    win.durationBox:SetText(tostring(pa.duration or 4))
    win.sizeSlider.SyncValue()
    win.posRefresh()
    win.RefreshLockBtn()
    local cc = pa.color or { r = 0.3, g = 1, b = 0.3 }
    for idx, rgb in ipairs(SA_COLOR_PRESETS) do
        local match = math.abs(rgb[1]-(cc.r or 0))<0.02 and math.abs(rgb[2]-(cc.g or 0))<0.02 and math.abs(rgb[3]-(cc.b or 0))<0.02
        if win.swatches[idx] then
            if match then win.swatches[idx].sel:Show() else win.swatches[idx].sel:Hide() end
        end
    end
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
-- 저렙 귓속말 차단
-- 귓속말 이벤트에는 발신자의 레벨 정보가 없다. 대신 친구 목록에는 레벨이
-- 표시되는 점을 이용한다: 발신자를 잠깐 친구로 등록 → 친구목록 갱신에서
-- 레벨 확인 → 즉시 삭제. 확인하는 동안 그 귓말은 채팅창에서 보류(필터)하고,
-- 기준 레벨 이상이면 원래 채팅창으로 복원, 미만이면 그대로 숨긴다.
-- 친구/길드원/파티·공대원/BNet친구/GM, 그리고 내가 먼저 귓말한 상대는 검사 없이 통과.
-- (친구 등록이 불가능한 비연결 서버 발신자는 레벨 확인이 불가 → 통과)
-- =====================================================================
local SA_WBFrame = CreateFrame("Frame")
local SA_wbSafe = {}       -- 통과 확정 발신자 (재검사 안 함)
local SA_wbPending = {}    -- 레벨 확인 대기: [이름] = { [lineID] = {n=인자수, 인자...} }
local SA_wbHidden = {}     -- 숨길 채팅 lineID 집합
local SA_wbBlocked = {}    -- 차단 확정 발신자 (답장해도 통과 안 됨. 리로드/차단 끄기 전까지 유지)
local SA_wbSysHide = {}    -- 이름 → 만료시각: 레벨 확인 중 "친구 등록/접속/삭제" 시스템 문구 숨김용
local SA_wbRealms = {}     -- 우리와 연결된 서버 목록 (친구 등록 가능 범위)
local SA_wbReady = false   -- 로그인 후 친구목록 첫 스캔 완료 여부
local SA_WB_NOTE = "밈다이스-레벨확인"   -- 임시 친구 식별용 메모
local SA_wbDebug = false   -- 진단 모드 (/밈귓말 debug): 통과/차단 사유를 채팅에 표시. 저장 안 됨

local function SA_wbDbg(msg)
    if SA_wbDebug then DEFAULT_CHAT_FRAME:AddMessage("|cff88ccff[밈귓말]|r " .. msg) end
end

-- 원래부터 믿을 수 있는 상대인지. 맞으면 사유 문자열, 아니면 nil (진단 표시용)
local function SA_wbTrusted(name, flag, guid)
    if flag == "GM" or flag == "DEV" then return "GM" end
    if guid and not SA_IsSecret(guid) then
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

-- 보류했던 귓말을 원래 채팅창(+외부 귓속말 창)으로 복원
local function SA_wbReplay(ids)
    for id, args in pairs(ids) do
        SA_wbHidden[id] = nil
        local frames = { GetFramesRegisteredForEvent("CHAT_MSG_WHISPER") }
        for j = 1, #frames do
            local cf = frames[j]
            local fname = cf.GetName and cf:GetName()
            if type(fname) == "string" and fname:find("^ChatFrame") then
                if ChatFrame_MessageEventHandler then
                    ChatFrame_MessageEventHandler(cf, "CHAT_MSG_WHISPER", unpack(args, 1, args.n))
                elseif cf.MessageEventHandler then
                    cf:MessageEventHandler("CHAT_MSG_WHISPER", unpack(args, 1, args.n))
                end
            end
        end
        -- 외부 귓속말 창들은 기본 채팅 경로를 안 쓰므로 직접 전달
        local msg, sender = args[1], args[2]
        if type(msg) == "string" and type(sender) == "string" then
            local im = _G.EnhanceQoL and _G.EnhanceQoL.ChatIM          -- '즉시 대화' 창
            if im and im.enabled and im.AddMessage then
                pcall(im.AddMessage, im, sender, msg)
            end
        end
        local wimE = _G.WIM and _G.WIM.modules and _G.WIM.modules.WhisperEngine   -- WIM
        if wimE and wimE.CHAT_MSG_WHISPER then
            pcall(wimE.CHAT_MSG_WHISPER, wimE, unpack(args, 1, args.n))
        end
    end
end

-- 대기가 모두 끝나면 잠깐 꺼뒀던 효과음 복구
-- ("접속했습니다" 문구/효과음이 약간 늦게 올 수 있어 2초 여유. 문구는 SA_wbSysHide 필터가 처리)
local function SA_wbRestoreSystem()
    if next(SA_wbPending) then return end
    C_Timer.After(2, function()
        if not next(SA_wbPending) then pcall(UnmuteSoundFile, 567518) end
    end)
end

-- 귓말 수신: 레벨 확인이 필요한 상대면 메시지 보류 + 임시 친구 등록
local function SA_wbOnWhisper(...)
    local wbdb = MimDiceDB and MimDiceDB.whisperBlock
    if not wbdb or not wbdb.enabled then return end
    local player = select(2, ...)
    local flag   = select(6, ...)
    local lineID = select(11, ...)
    local guid   = select(12, ...)
    if SA_IsSecret(player) or SA_IsSecret(lineID) or type(lineID) ~= "number" then return end
    local name = Ambiguate(player, "none")
    -- 이미 레벨 확인 중인 상대의 추가 귓말: 신뢰 검사보다 먼저 보류 처리
    -- (레벨 확인용 '임시 친구 등록' 상태를 신뢰 검사가 진짜 친구로 착각하는 것 방지)
    local pend = SA_wbPending[name]
    if pend then
        if not pend[lineID] then pend[lineID] = { n = select("#", ...), ... } end
        SA_wbHidden[lineID] = true
        SA_wbDbg(name .. ": 레벨 확인 중... (추가 귓말도 보류)")
        return
    end
    -- 차단 확정자는 통과목록보다 우선 (답장 등으로 통과목록에 들어갔어도 무시)
    if SA_wbSafe[name] and not SA_wbBlocked[name] then
        SA_wbDbg(name .. ": 통과 (세션 통과목록 - 친구였거나 내가 귓말한 상대)")
        return
    end
    if not SA_wbBlocked[name] then
        local why = SA_wbTrusted(name, flag, guid)
        if why then
            SA_wbSafe[name] = true
            SA_wbDbg(name .. ": 통과 (" .. why .. ")")
            return
        end
    end
    -- 비연결 서버는 친구 등록이 안 돼 레벨 확인 불가 → 통과
    local dash = name:find("-", 1, true)
    if dash and not SA_wbRealms[name:sub(dash + 1)] then
        SA_wbDbg(name .. ": 통과 (비연결 서버 - 레벨 확인 불가)")
        return
    end

    local p = SA_wbPending[name]
    if not p then
        p = {}
        SA_wbPending[name] = p
        SA_wbDbg(name .. ": 레벨 확인 중... (귓말 보류)")
        SA_wbSysHide[name] = GetTime() + 15            -- 이 이름이 든 시스템 문구(친구 등록/접속/삭제) 잠깐 숨김
        pcall(MuteSoundFile, 567518)                   -- "친구 접속" 효과음 잠깐 음소거
        pcall(C_FriendList.AddFriend, name, SA_WB_NOTE)
        -- 5초 안에 레벨 확인이 안 되면(귓말 직후 접속종료·친구목록 가득 참 등) 수상하므로 차단 유지
        -- (귓말 쓰고 바로 게임을 꺼서 확인을 회피하는 수법 방지)
        C_Timer.After(5, function()
            if not SA_wbPending[name] then return end
            SA_wbPending[name] = nil
            SA_wbBlocked[name] = true   -- 확인 회피 = 차단 확정 (답장해도 유지)
            SA_wbDbg(name .. ": 차단 유지 (5초 내 레벨 확인 실패 - 접속종료/친구목록 가득참 등)")
            -- 아무 기록/알림 없이 조용히 차단 유지 (lineID 필터가 계속 숨김)
            SA_wbRestoreSystem()
        end)
    end
    if not p[lineID] then p[lineID] = { n = select("#", ...), ... } end
    SA_wbHidden[lineID] = true
end

-- 친구목록 갱신: 대기 중인 발신자의 레벨을 읽고 임시 등록 삭제 → 통과/숨김 결정
local function SA_wbOnFriendsUpdate()
    if not SA_wbReady then
        -- 로그인 첫 갱신: 이전 세션의 임시 항목 청소 + 기존 친구는 통과 목록으로
        SA_wbReady = true
        local num = C_FriendList.GetNumFriends() or 0
        for i = num, 1, -1 do
            local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
            if ok and info then
                if info.notes == SA_WB_NOTE then
                    pcall(C_FriendList.RemoveFriendByIndex, i)
                elseif type(info.name) == "string" then
                    SA_wbSafe[info.name] = true
                end
            end
        end
        return
    end
    if not next(SA_wbPending) then return end
    local wbdb = MimDiceDB and MimDiceDB.whisperBlock
    local minLv = (wbdb and wbdb.minLevel) or 10
    local num = C_FriendList.GetNumFriends() or 0
    for i = num, 1, -1 do
        local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
        local name = ok and info and info.name
        if name and SA_wbPending[name] and info.notes == SA_WB_NOTE then
            local level = info.level
            -- 등록 직후 갱신에는 레벨이 0으로 옴 → 다음 갱신을 기다림
            if type(level) == "number" and level > 0 then
                pcall(C_FriendList.RemoveFriendByIndex, i)
                local ids = SA_wbPending[name]
                SA_wbPending[name] = nil
                if level >= minLv then
                    SA_wbSafe[name] = true
                    SA_wbBlocked[name] = nil   -- 레벨업해서 기준을 넘겼으면 차단 해제
                    SA_wbDbg(name .. ": 통과 (레벨 " .. level .. " >= 기준 " .. minLv .. ")")
                    SA_wbReplay(ids)   -- 기준 이상 → 보류했던 귓말 복원
                else
                    SA_wbBlocked[name] = true  -- 차단 확정 (답장해도 유지)
                    SA_wbDbg(name .. ": 차단 (레벨 " .. level .. " < 기준 " .. minLv .. ")")
                end
                -- 기준 미만 → 아무 기록/알림 없이 조용히 숨김 유지
                SA_wbRestoreSystem()
            end
        end
    end
end

SA_WBFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_WHISPER" then
        SA_wbOnWhisper(...)
    elseif event == "FRIENDLIST_UPDATE" then
        SA_wbOnFriendsUpdate()
    elseif event == "CHAT_MSG_WHISPER_INFORM" then
        -- 내가 먼저 귓말한 상대는 통과 목록으로. 단, 이미 차단 확정된 상대는 답장해도 통과 안 됨
        local target = select(2, ...)
        if not SA_IsSecret(target) then
            local tname = Ambiguate(target, "none")
            if SA_wbBlocked[tname] then
                SA_wbDbg(tname .. ": 차단 유지 (차단된 상대에게 답장해도 통과되지 않음)")
            elseif not SA_wbSafe[tname] then
                SA_wbSafe[tname] = true
                SA_wbDbg(tname .. ": 통과목록 추가 (내가 귓말을 보낸 상대)")
            end
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        local msg = ...
        if not SA_IsSecret(msg) and msg == ERR_FRIEND_LIST_FULL then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[MimDice]|r 친구 목록이 가득 차 저렙 귓속말 차단이 동작할 수 없습니다. 친구 자리를 2칸 비워주세요.")
        end
    end
end)

-- 숨김 대상 lineID면 채팅창에 표시하지 않음
local function SA_wbChatFilter(_, _, _, _, _, _, _, _, _, _, _, _, lineID)
    if SA_IsSecret(lineID) then return end
    if type(lineID) == "number" and SA_wbHidden[lineID] then return true end
end
-- 레벨 확인 중인 이름이 들어간 시스템 문구("친구 목록에 등록/삭제", "게임에 접속") 숨김.
-- 필터 방식이라 채팅 탭이 몇 개든 전부 적용됨.
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

local SA_wbAddFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
SA_wbAddFilter("CHAT_MSG_WHISPER", SA_wbChatFilter)
SA_wbAddFilter("CHAT_MSG_SYSTEM", SA_wbSystemFilter)

-- 진단용 슬래시: /밈귓말 (상태 표시) , /밈귓말 debug (통과/차단 사유를 채팅에 표시 - 세션 한정, 저장 안 됨)
SLASH_MIMWHISPER1 = "/밈귓말"
SLASH_MIMWHISPER2 = "/mimwhisper"
SlashCmdList["MIMWHISPER"] = function(msg)
    if msg == "debug" or msg == "디버그" then
        SA_wbDebug = not SA_wbDebug
        DEFAULT_CHAT_FRAME:AddMessage("|cff88ccff[밈귓말]|r 진단 모드 "
            .. (SA_wbDebug and "켜짐: 귓말이 올 때마다 통과/차단 사유를 표시합니다" or "꺼짐"))
    else
        local wb = MimDiceDB and MimDiceDB.whisperBlock
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff88ccff[밈귓말]|r 차단 %s / 기준: 레벨 %d 미만 숨김 / 진단 모드: /밈귓말 debug",
            (wb and wb.enabled) and "켜짐" or "꺼짐", (wb and wb.minLevel) or 60))
    end
end

-- 로그인 시 1회 초기화 (SA_EventFrame의 PLAYER_LOGIN에서 호출)
local function SA_WhisperBlockInit()
    -- 연결된 서버 목록 (이 범위만 친구 등록 = 레벨 확인 가능)
    local realms = GetAutoCompleteRealms()
    if type(realms) == "table" then
        for i = 1, #realms do SA_wbRealms[realms[i]] = true end
    end
    local me = UnitName("player")
    if me then SA_wbSafe[me] = true end
    -- 기본 채팅창보다 우리 핸들러가 귓말을 먼저 받도록 등록 순서 조정
    -- (이미 등록된 프레임들을 잠깐 내렸다가 우리 등록 뒤에 다시 올림)
    local frames = { GetFramesRegisteredForEvent("CHAT_MSG_WHISPER") }
    for j = 1, #frames do
        local f = frames[j]
        if not f:IsForbidden() then f:UnregisterEvent("CHAT_MSG_WHISPER") end
    end
    SA_WBFrame:RegisterEvent("CHAT_MSG_WHISPER")
    for j = 1, #frames do
        local f = frames[j]
        if not f:IsForbidden() then f:RegisterEvent("CHAT_MSG_WHISPER") end
    end
    SA_WBFrame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
    SA_WBFrame:RegisterEvent("FRIENDLIST_UPDATE")
    SA_WBFrame:RegisterEvent("CHAT_MSG_SYSTEM")
    C_FriendList.ShowFriends()   -- 친구목록 첫 갱신 유도 (임시 항목 청소용)

    -- '즉시 대화' 창(EnhanceQoL ChatIM) 호환:
    -- 이 창은 채팅 필터를 거치지 않고 원본 이벤트를 직접 그리는데,
    -- 표시 직전에 자체 무시목록 검사를 하므로 그 검사에 우리 판단(보류/차단)을 끼워 넣는다.
    -- → 메시지·알림 효과음·창 깜빡임까지 한 번에 건너뜀.
    -- (위의 등록 순서 조정 덕에 우리 핸들러가 먼저 실행되어 보류 상태가 항상 선반영됨)
    local eqol = _G.EnhanceQoL
    if eqol then
        if not eqol.Ignore then eqol.Ignore = {} end
        local ig = eqol.Ignore
        local origCheck = ig.CheckIgnore
        ig.CheckIgnore = function(selfIg, pname, ...)
            local wbdb = MimDiceDB and MimDiceDB.whisperBlock
            if wbdb and wbdb.enabled and type(pname) == "string" and not SA_IsSecret(pname) then
                local short = Ambiguate(pname, "none")
                if SA_wbPending[short] or SA_wbBlocked[short] then return true end
            end
            if origCheck then return origCheck(selfIg, pname, ...) end
            return nil
        end
    end
end

local SA_EventFrame = CreateFrame("Frame")
SA_EventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
SA_EventFrame:RegisterEvent("PLAYER_LOGIN")
SA_EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")   -- 인스턴스 진입 시 전투부활 충전 기준값 동기화
SA_EventFrame:RegisterEvent("UNIT_DIED")
SA_EventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")     -- 전투부활 충전 변화 감지
SA_EventFrame:RegisterEvent("LFG_LIST_APPLICANT_LIST_UPDATED")  -- 파티 신청 감지
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
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- 인스턴스 진입/이동 시 충전 기준값 재동기화 (진입 직후 충전 변화 오발동 방지)
        SA_SyncBattleResCharges()
        SA_RefreshBattleResIconState()
    elseif event == "LFG_LIST_APPLICANT_LIST_UPDATED" then
        SA_CheckPartyApplicants()
    elseif event == "SPELL_UPDATE_CHARGES" then
        SA_CheckBattleResCharge()
        SA_RefreshBattleResIconState()   -- 충전 변화 즉시 아이콘 반영
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

-- 탭 켜짐/꺼짐 색상 (사운드/귓말차단 공용)
local function SA_SetTabActive(tab, on)
    if not tab then return end
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

local function SA_ToggleWindow()
    if SA_OptionWindow:IsShown() then
        SA_OptionWindow:Hide()
        SA_SetTabActive(SA_TabOption, false)
    else
        -- 두 옵션창은 같은 자리를 쓰므로 하나만 표시
        if SA_WhisperWindow and SA_WhisperWindow:IsShown() then
            SA_WhisperWindow:Hide()
            SA_SetTabActive(SA_TabWhisper, false)
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
        SA_WhisperWindow:Show()
        if SA_RefreshWhisperLog then SA_RefreshWhisperLog() end
        SA_SetTabActive(SA_TabWhisper, true)
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
    optText:SetFont("Fonts\\2002.ttf", 12, "OUTLINE")
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
    wbText:SetFont("Fonts\\2002.ttf", 12, "OUTLINE")
    wbText:SetText("귓\n말\n차\n단")
    wbText:SetTextColor(0.6, 0.6, 0.6)
    SA_TabWhisper.text = wbText

    SA_TabWhisper:SetScript("OnClick", SA_ToggleWhisperWindow)
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
    
    -- ★ 메인 창이 닫힐 때 옵션 창(사운드/귓말차단)도 함께 닫히도록 연동 ★
    mainWin:HookScript("OnHide", function()
        if SA_OptionWindow and SA_OptionWindow:IsShown() then
            SA_OptionWindow:Hide()
            SA_SetTabActive(SA_TabOption, false)
        end
        if SA_WhisperWindow and SA_WhisperWindow:IsShown() then
            SA_WhisperWindow:Hide()
            SA_SetTabActive(SA_TabWhisper, false)
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

    -- ── << 블러드 >> 섹션 (모든 직업 공용, 지속시간 바) ──────────────
    local buffSectionLabel = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    buffSectionLabel:SetPoint("TOP", SA_OptionWindow, "TOP", 0, -142)
    buffSectionLabel:SetFont("Fonts\\2002.ttf", 13, "OUTLINE")
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
    bloodLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    bloodLabel:SetText("블러드 (사운드 + 지속시간 바)")
    bloodLabel:SetTextColor(0.9, 0.9, 0.9)

    local bloodCfgBtn = CreateFrame("Button", nil, SA_OptionWindow, "UIPanelButtonTemplate")
    bloodCfgBtn:SetSize(50, 22)
    bloodCfgBtn:SetPoint("TOPRIGHT", SA_OptionWindow, "TOPRIGHT", -15, -160)
    bloodCfgBtn:SetText("설정")
    bloodCfgBtn:GetFontString():SetFont("Fonts\\2002.ttf", 11, "")
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
    brLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    brLabel:SetText("전투부활 (사운드 + 아이콘)")
    brLabel:SetTextColor(0.9, 0.9, 0.9)

    local brCfgBtn = CreateFrame("Button", nil, SA_OptionWindow, "UIPanelButtonTemplate")
    brCfgBtn:SetSize(50, 22)
    brCfgBtn:SetPoint("TOPRIGHT", SA_OptionWindow, "TOPRIGHT", -15, -182)
    brCfgBtn:SetText("설정")
    brCfgBtn:GetFontString():SetFont("Fonts\\2002.ttf", 11, "")
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
    paLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    paLabel:SetText("파티 신청 (사운드 + 메시지)")
    paLabel:SetTextColor(0.9, 0.9, 0.9)

    local paCfgBtn = CreateFrame("Button", nil, SA_OptionWindow, "UIPanelButtonTemplate")
    paCfgBtn:SetSize(50, 22)
    paCfgBtn:SetPoint("TOPRIGHT", SA_OptionWindow, "TOPRIGHT", -15, -206)
    paCfgBtn:SetText("설정")
    paCfgBtn:GetFontString():SetFont("Fonts\\2002.ttf", 11, "")
    paCfgBtn:SetScript("OnClick", function() SA_TogglePartyConfig() end)

    -- 구분선
    local divider = SA_OptionWindow:CreateTexture(nil, "ARTWORK")
    divider:SetSize(350, 1)
    divider:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 15, -238)
    divider:SetColorTexture(0.5, 0.5, 0.5, 0.6)

    -- ── << 스킬 사운드 알림 >> 섹션 ─────────────────
    local skillSectionLabel = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    skillSectionLabel:SetPoint("TOP", SA_OptionWindow, "TOP", 0, -250)
    skillSectionLabel:SetFont("Fonts\\2002.ttf", 13, "OUTLINE")
    skillSectionLabel:SetText("스킬 사운드 알림 (직업별 저장)")
    skillSectionLabel:SetTextColor(1, 0.82, 0)

    local inputLabel = SA_OptionWindow:CreateFontString(nil, "OVERLAY")
    inputLabel:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 15, -276)
    inputLabel:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
    inputLabel:SetText("1. 추가할 스킬의 이름 또는 ID 입력 (꼭 띄어쓰기 지켜야 함)")
    inputLabel:SetTextColor(0.9, 0.9, 0.9)

    local inputBox = CreateFrame("EditBox", "SA_SpellInput", SA_OptionWindow, "InputBoxTemplate")
    inputBox:SetSize(200, 22)
    inputBox:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 20, -296)
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
    listTitle:SetPoint("TOPLEFT", SA_OptionWindow, "TOPLEFT", 15, -336)
    listTitle:SetFont("Fonts\\2002.ttf", 11, "OUTLINE")
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
            spellText:SetFont("Fonts\\2002.ttf", 11)
            spellText:SetJustifyH("LEFT")
            row.spellText = spellText

            local typeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            typeBtn:SetSize(42, 22)
            typeBtn:SetPoint("LEFT", spellText, "RIGHT", 5, 0)
            typeBtn:GetFontString():SetFont("Fonts\\2002.ttf", 10, "")
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
                fs:SetFont("Fonts\\2002.ttf", 9, "")
                fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
                fs:ClearAllPoints(); fs:SetPoint("LEFT", 5, 0); fs:SetPoint("RIGHT", -5, 0)
            end
            row.soundSelectBtn = soundSelectBtn

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
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function()
        if mainWin:IsMovable() then mainWin:StartMoving() end
    end)
    win:SetScript("OnDragStop", function()
        mainWin:StopMovingOrSizing()
        if MimDice_SaveAnchors then MimDice_SaveAnchors() end
    end)
    win:Hide()

    local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() SA_ToggleWhisperWindow() end)

    local title = win:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", win, "TOP", 0, -12)
    title:SetFont("Fonts\\2002.ttf", 14, "OUTLINE")
    title:SetText("저렙 귓속말 차단")
    title:SetTextColor(1, 0.82, 0)

    -- ── 켜기 + 기준 레벨 ──
    local enCb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    enCb:SetSize(24, 24)
    enCb:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -34)
    enCb:SetScript("OnClick", function(self)
        if MimDiceDB.whisperBlock then
            MimDiceDB.whisperBlock.enabled = self:GetChecked() and true or false
        end
    end)
    win.enCb = enCb
    local enLabel = win:CreateFontString(nil, "OVERLAY")
    enLabel:SetPoint("LEFT", enCb, "RIGHT", 2, 0)
    enLabel:SetFont("Fonts\\2002.ttf", 12, "OUTLINE")
    enLabel:SetText("차단 켜기 : 레벨")
    enLabel:SetTextColor(0.9, 0.9, 0.9)
    local lvBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    lvBox:SetSize(38, 20)
    lvBox:SetPoint("LEFT", enLabel, "RIGHT", 10, 0)
    lvBox:SetAutoFocus(false); lvBox:SetFont("Fonts\\2002.ttf", 12, "")
    lvBox:SetNumeric(true); lvBox:SetMaxLetters(3); lvBox:SetJustifyH("CENTER")
    lvBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local v = tonumber(self:GetText())
        if v and v >= 2 and MimDiceDB.whisperBlock then MimDiceDB.whisperBlock.minLevel = v end
    end)
    lvBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    win.lvBox = lvBox
    local lvSuffix = win:CreateFontString(nil, "OVERLAY")
    lvSuffix:SetPoint("LEFT", lvBox, "RIGHT", 6, 0)
    lvSuffix:SetFont("Fonts\\2002.ttf", 12, "OUTLINE")
    lvSuffix:SetText("미만 귓속말 숨김")
    lvSuffix:SetTextColor(0.9, 0.9, 0.9)

    -- ── 쉬운 설명 ──
    local help = win:CreateFontString(nil, "OVERLAY")
    help:SetPoint("TOPLEFT", win, "TOPLEFT", 15, -70)
    help:SetFont("Fonts\\2002.ttf", 12, "")
    help:SetTextColor(0.8, 0.8, 0.8)
    help:SetWidth(350); help:SetJustifyH("LEFT"); help:SetWordWrap(true); help:SetSpacing(5)
    help:SetText(
        "ㅁ 위에서 정한 레벨보다 낮은 캐릭터가 보낸 귓속말은\n" ..
        "    화면에 뜨지 않습니다.\n\n" ..
        "ㅁ 아무 알림도 나오지 않게 조용하게\n" ..
        "    저렙 귓속말이 차단됩니다.\n\n" ..
        "ㅁ 귓속말 내용은 저장하지 않고 기록도 남기지 않습니다.\n\n" ..
        "ㅁ EnhanceQoL 이나 WIM 같은 귓속말 애드온을\n" ..
        "    쓰더라도 해당 애드온보다 먼저 귓속말을 차단해서\n" ..
        "    화면에 표시하지 않습니다.\n\n" ..
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
-- 애드온 초기화 호출
-- =====================================================================
function SoundAlert_OnLoad()
    local function TryInit()
        if _G["MainWindow"] then
            SA_InitDB()
            SA_CreateTab()
            SA_CreateWindow()
            SA_CreateWhisperWindow()
        else
            C_Timer.After(0.1, TryInit)
        end
    end
    TryInit()
end