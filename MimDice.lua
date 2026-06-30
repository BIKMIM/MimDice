-- Author         : BIK
-- Create Date    : 2023-02-02 오후 05:37:12
-- Last Updated   : 2026-05-30 오후 04:32:22
-- Version        : v1.11.1

---@diagnostic disable: undefined-global, param-type-mismatch, undefined-field, cast-local-type -- 전역 함수 정의 에러, 매개변수 타입 불일치, 정의되지 않은 필드, 로컬 타입 캐스팅 무시

-- UI 리로드 명령어 등록 (편의성 증대)
SLASH_RELOAD3 = "/rl"
SLASH_RELOAD2 = "/리"
SLASH_RELOAD1 = "/fl" -- 영어 오타
SLASH_RELOAD4 = "/기" -- 한글 오타
SLASH_RELOAD5 = "/리로드" -- 한글 풀네임
SlashCmdList["RELOAD"] = ReloadUI -- 실제 UI 리로드 함수 연결
-------------------------------------------------------------------------------------------
---
--- -- 사운드 알림 모듈 초기화
SoundAlert_OnLoad()


-- 전역 변수 선언 (애드온 전체에서 사용될 핵심 데이터 구조)
local rollArray         -- 주사위 굴림 결과 데이터를 저장하는 테이블
local rollNames         -- 각 플레이어가 주사위를 굴린 횟수를 추적하는 테이블 (Key: "Name-Realm")
local fontName          -- 현재 애드온 텍스트에 사용되는 폰트 이름
local fontHeight        -- 현재 애드온 텍스트에 사용되는 폰트 크기
local RankList = {}     -- 주사위 결과 순위 목록을 저장할 변수
MimDice_LastRollTime = 0

-- ===== 서버명 캐싱 =====
-- 던전 로딩 중이나 특정 상황에서 GetRealmName()이 nil을 반환할 수 있으므로
-- 한 번 성공적으로 가져온 서버명을 캐싱하여 재사용
local cachedRealmName = nil

-- 안전한 서버명 가져오기 함수
-- @return string 현재 서버명 (실패 시 "Unknown-Realm" 반환)
local function GetSafeRealmName()
    -- 이미 캐싱된 서버명이 있으면 그것을 사용
    if cachedRealmName then
        return cachedRealmName
    end
    
    -- GetRealmName() 호출 시도
    local realmName = GetRealmName()
    
    -- 성공적으로 가져왔으면 캐싱
    if realmName and realmName ~= "" then
        cachedRealmName = realmName
        return realmName
    end
    
    -- 실패 시 fallback 값 반환
    return "Unknown-Realm"
end
-- ===== 캐싱 로직 끝 =====

-- 상수 정의
local ICON_ALPHA_VISIBLE = 1.0
local ICON_ALPHA_DIMMED = 0.2

-- ===== UNKNOWN_UNIT 안전 처리 =====
-- Blizzard API의 UNKNOWN_UNIT 상수가 nil일 수 있는 환경 대비
local SAFE_UNKNOWN_UNIT = UNKNOWN_UNIT or "Unknown"
-- ===== 상수 안전 처리 끝 =====

-- MimDice 애드온의 설정 및 저장 데이터베이스
-- 게임 종료 시에도 유지되는 영구 저장 공간으로 사용
MimDiceDB = {}

-- 클래스 아이콘 텍스처 정보
IconClassTexture = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
IconClassTextureWithoutBorder = "Interface\\WorldStateFrame\\ICONS-CLASSES"
IconClassTextureCoord = 'CLASS_ICON_TCOORDS'
IconClass = {
    ["WARRIOR"] = "|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:0:64:0:64|t",       -- 전사
    ["MAGE"] = "|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:64:128:0:64|t",       -- 마법사
    ["ROGUE"] = "|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:128:192:0:64|t",     -- 도적
    ["DRUID"] = "|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:192:256:0:64|t",     -- 드루이드
    ["HUNTER"] = "|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:0:64:64:128|t",      -- 사냥꾼
    ["SHAMAN"] = "|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:64:128:64:128|t",     -- 주술사
    ["PRIEST"] = "|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:128:192:64:128|t",   -- 사제
    ["WARLOCK"] = "|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:192:256:64:128|t",  -- 흑마법사
    ["PALADIN"] = "|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:0:64:128:192|t",    -- 성기사
    ["DEATHKNIGHT"] = "|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:64:128:128:192|t", -- 죽음의 기사
    ["MONK"] = "|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:128:192:128:192|t",    -- 수도사
    ["DEMONHUNTER"] = "|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:192:256:128:192|t", -- 악마 사냥꾼
    ["EVOKER"] = "|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:0:64:192:256|t",     -- 기원사
}

-- 메인 이벤트 프레임 생성
local MimFrame = CreateFrame("frame")
MimFrame:RegisterEvent("CHAT_MSG_SYSTEM")
MimFrame:RegisterEvent("ADDON_LOADED")
MimFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

-- 가십 프레임 생성 (개못해정령 기능 관련)
local MimGossipFrame = CreateFrame("frame")
MimGossipFrame:RegisterEvent("ADDON_LOADED")
MimGossipFrame:RegisterEvent("GOSSIP_SHOW")
MimGossipFrame:RegisterEvent("GOSSIP_CLOSED")
MimGossipFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
MimGossipFrame:RegisterEvent("MERCHANT_SHOW")

-- 주사위 굴림 결과 메시지 파싱을 위한 패턴 정의
local pattern = string.gsub(RANDOM_ROLL_RESULT, "[%(%)-]", "%%%1")
pattern = string.gsub(pattern, "%%s", "(.+)")
pattern = string.gsub(pattern, "%%d", "%(%%d+%)")

-- ===== 새로 추가: Secret Value 체크 함수 =====
-- WoW는 한밤부터 보안상 일부 값을 "secret value"로 블랙박스처럼 보호함
-- 이런 값들은 문자열 변환이나 조작이 불가능하므로 사전에 체크해야 함
-- @param value any 체크할 값
-- @return boolean secret value면 true, 아니면 false
local function IsSecretValue(value)
    -- nil이면 secret value가 아님
    if value == nil then
        return false
    end
    
    -- pcall로 tostring 시도 - secret value면 오류 발생
    local success, result = pcall(tostring, value)
    
    -- tostring 실패하면 secret value
    if not success then
        return true
    end
    
    -- 정상적으로 변환되었는지 확인
    -- result가 nil이거나 빈 문자열이 아니면 정상
    return false
end

-- ===== 안전한 문자열 변환 함수 =====
-- secret value를 안전하게 처리하는 tostring 래퍼
-- @param value any 변환할 값
-- @return string 변환된 문자열 (실패 시 빈 문자열)
local function SafeToString(value)
    -- nil 체크
    if value == nil then
        return ""
    end
    
    -- 이미 문자열이면 그대로 반환
    if type(value) == "string" then
        return value
    end
    
    -- secret value 체크
    if IsSecretValue(value) then
        return ""
    end
    
    -- 안전한 변환 시도
    local success, result = pcall(tostring, value)
    if success and result then
        return result
    end
    
    -- 모든 시도 실패 시 빈 문자열
    return ""
end
-- ===== Secret Value 처리 끝 =====

-- 안전한 전역 변수 접근을 위한 유틸리티 함수
-- @param iconName string 아이콘 프레임의 이름
-- @param alpha number 설정할 투명도 (0.0 ~ 1.0)
local function SetClassIconAlpha(iconName, alpha)
    -- _G 테이블에서 해당 이름의 프레임이 존재하는지 확인
    if _G[iconName] then
        _G[iconName]:SetAlpha(alpha)
    end
end

-- 모든 클래스 아이콘의 투명도를 설정하는 함수
-- @param alpha number 설정할 투명도 (0.0 ~ 1.0)
local function SetAllClassIconsAlpha(alpha)
    -- 13개의 클래스 아이콘 모두에 대해 투명도 설정
    for i = 1, 13 do
        SetClassIconAlpha("C_icon" .. i, alpha)
    end
end

-- ===== 서버명 필터링을 위한 유틸리티 함수들 (안전성 강화) =====

-- "이름-서버명" 형태에서 이름만 추출하는 함수
-- @param fullName string "이름-서버명" 형태의 전체 이름
-- @return string 추출된 짧은 이름 (실패 시 원본 반환 또는 빈 문자열)
function GetShortName(fullName)
    -- nil 체크
    if not fullName then 
        return "" 
    end
    
    -- 문자열이 아닌 경우 안전한 변환
    if type(fullName) ~= "string" then
        fullName = SafeToString(fullName)
        if fullName == "" then
            return ""
        end
    end
    
    -- "이름-서버명" 형태에서 이름만 추출
    local shortName = string.match(fullName, "^([^%-]+)")
    
    -- 패턴 매칭 실패 시 원본 반환
    return shortName or fullName
end

-- "이름-서버명" 형태에서 서버명만 추출하는 함수
-- @param fullName string "이름-서버명" 형태의 전체 이름
-- @return string|nil 추출된 서버명 (서버명이 없으면 nil 반환)
function GetRealmFromFullName(fullName)
    -- nil 체크
    if not fullName then 
        return nil 
    end
    
    -- 문자열이 아닌 경우 안전한 변환
    if type(fullName) ~= "string" then
        fullName = SafeToString(fullName)
        if fullName == "" then
            return nil
        end
    end
    
    -- "이름-서버명" 형태에서 서버명만 추출
    local _, realmName = string.match(fullName, "^(.-)%-(.+)$")
    
    -- 서버명 반환 (매칭 실패 시 nil)
    return realmName
end

-- 주어진 fullName의 서버가 현재 플레이어의 서버와 같은지 확인
-- @param fullName string "이름-서버명" 형태의 전체 이름
-- @return boolean 같은 서버면 true, 다르면 false
function IsSameRealm(fullName)
    -- 안전한 서버명 가져오기
    local currentRealm = GetSafeRealmName()
    
    -- fullName에서 서버명 추출
    local playerRealm = GetRealmFromFullName(fullName)
    
    -- 서버명이 없으면 같은 서버로 간주
    if not playerRealm then
        return true
    end
    
    -- 서버명 비교
    return playerRealm == currentRealm
end
-- ===== 서버명 유틸리티 함수 끝 =====

-- 한글 직업명을 영어 직업명으로 변환하는 함수
-- @param koreanClass string 한글 또는 영어 직업명
-- @return string 영어 대문자 직업명 (변환 실패 시 "UNKNOWN")
function ConvertClassToEnglish(koreanClass)
    -- 한글-영어 직업명 매핑 테이블
    local classMap = {
        ["전사"] = "WARRIOR",
        ["성기사"] = "PALADIN",
        ["사냥꾼"] = "HUNTER",
        ["도적"] = "ROGUE",
        ["사제"] = "PRIEST",
        ["죽음의 기사"] = "DEATHKNIGHT",
        ["주술사"] = "SHAMAN",
        ["마법사"] = "MAGE",
        ["흑마법사"] = "WARLOCK",
        ["수도사"] = "MONK",
        ["드루이드"] = "DRUID",
        ["악마 사냥꾼"] = "DEMONHUNTER",
        ["악마사냥꾼"] = "DEMONHUNTER",
        ["기원사"] = "EVOKER"
    }

    -- nil 체크
    if not koreanClass then
        return "UNKNOWN"
    end
    
    -- 문자열이 아닌 경우 방어
    if type(koreanClass) ~= "string" then
        return "UNKNOWN"
    end

    -- 이미 영어라면 그대로 반환
    if classMap[koreanClass] then
        return classMap[koreanClass]
    elseif string.match(koreanClass, "^[A-Z]+$") then
        return koreanClass
    else
        return "UNKNOWN"
    end
end

-- 클래스 이름(영어)에 해당하는 색상 코드 문자열을 반환하는 함수
-- @param Class string 영어 대문자 직업명
-- @return string 색상 코드 문자열
function Mim_GetClassColor(Class)
    -- nil이거나 빈 문자열이거나 UNKNOWN이면 흰색 반환
    if not Class or Class == "" or Class == "UNKNOWN" then
        return "|cffffffff"
    end

    -- 클래스 이름을 대문자로 변환
    Class = strupper(Class)

    -- RAID_CLASS_COLORS 테이블에서 색상 정보 찾기
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[Class] then
        local classColor = RAID_CLASS_COLORS[Class]
        
        -- RGB 값을 0-255 범위의 정수로 변환
        local r = math.floor(classColor.r * 255)
        local g = math.floor(classColor.g * 255)
        local b = math.floor(classColor.b * 255)
        
        -- 16진수 색상 코드 문자열 생성
        return string.format("|cff%02x%02x%02x", r, g, b)
    else
        return "|cffffffff"
    end
end

-- 파티/공대원의 클래스 정보를 기반으로 아이콘 투명도를 설정하는 함수
local function UpdateClassIconsBasedOnParty()
    -- 모든 아이콘을 먼저 진하게 설정
    SetAllClassIconsAlpha(ICON_ALPHA_VISIBLE)
    
    -- 그룹에 속해 있는 경우에만 처리
    if IsInGroup() or IsInRaid() then
        local partyList, _ = GetPlayerList(true)
        local foundClasses = {}
        
        -- 현재 파티/공대에 있는 클래스들을 찾기
        for _, p in ipairs(partyList) do
            if p and p.class then
                local englishClass = ConvertClassToEnglish(p.class)
                if englishClass and englishClass ~= "UNKNOWN" then
                    foundClasses[englishClass] = true
                end
            end
        end
        
        -- 파티에 있는 클래스들의 아이콘을 흐리게 표시
        if foundClasses["WARRIOR"] then SetClassIconAlpha("C_icon1", ICON_ALPHA_DIMMED) end
        if foundClasses["MAGE"] then SetClassIconAlpha("C_icon2", ICON_ALPHA_DIMMED) end
        if foundClasses["ROGUE"] then SetClassIconAlpha("C_icon3", ICON_ALPHA_DIMMED) end
        if foundClasses["DRUID"] then SetClassIconAlpha("C_icon4", ICON_ALPHA_DIMMED) end
        if foundClasses["DEATHKNIGHT"] then SetClassIconAlpha("C_icon5", ICON_ALPHA_DIMMED) end
        if foundClasses["SHAMAN"] then SetClassIconAlpha("C_icon6", ICON_ALPHA_DIMMED) end
        if foundClasses["PRIEST"] then SetClassIconAlpha("C_icon7", ICON_ALPHA_DIMMED) end
        if foundClasses["WARLOCK"] then SetClassIconAlpha("C_icon8", ICON_ALPHA_DIMMED) end
        if foundClasses["PALADIN"] then SetClassIconAlpha("C_icon9", ICON_ALPHA_DIMMED) end
        if foundClasses["MONK"] then SetClassIconAlpha("C_icon10", ICON_ALPHA_DIMMED) end
        if foundClasses["DEMONHUNTER"] then SetClassIconAlpha("C_icon11", ICON_ALPHA_DIMMED) end
        if foundClasses["EVOKER"] then SetClassIconAlpha("C_icon12", ICON_ALPHA_DIMMED) end
        if foundClasses["HUNTER"] then SetClassIconAlpha("C_icon13", ICON_ALPHA_DIMMED) end
    end
end

-- ===== 안전한 UnitFullName 래퍼 함수 =====
-- @param unitId string 유닛 ID
-- @return string "이름-서버명" 형태의 전체 이름
local function GetSafeUnitFullName(unitId)
    if not unitId then
        return ""
    end
    
    -- UnitFullName 호출
    local fullName, realmName = UnitFullName(unitId)
    
    -- fullName이 제대로 반환되었는지 확인
    if fullName and fullName ~= "" then
        -- realmName도 함께 반환되었다면 조합
        if realmName and realmName ~= "" then
            return fullName .. "-" .. realmName
        end
        
        -- fullName만 있고 이미 "-" 포함된 경우
        if string.find(fullName, "-") then
            return fullName
        end
        
        -- fullName만 있고 "-"가 없는 경우
        return fullName .. "-" .. GetSafeRealmName()
    end
    
    -- UnitFullName이 실패한 경우, UnitName으로 대체 시도
    local name = UnitName(unitId)
    if name and name ~= "" then
        return name .. "-" .. GetSafeRealmName()
    end
    
    return ""
end
-- ===== 안전한 UnitFullName 래퍼 끝 =====

-- ===== 현재 파티 또는 공대에 있는 플레이어 목록을 가져오는 함수 =====
-- 이 함수는 애드온의 핵심 기능 중 하나로, 주기적으로 호출됨
-- GROUP_ROSTER_UPDATE 이벤트마다 실행되므로 안정성이 매우 중요
--
-- - 모든 name 변수에 type(name) == "string" 체크 추가
-- - GetRaidRosterInfo, UnitName 등에서 반환되는 name도 Secret Value일 수 있음
-- - 특히 던전 로딩 중, 크로스 서버 동기화 중에 불안정
-- - 이 함수는 매우 자주 호출되므로 CHAT_MSG_SYSTEM보다 더 중요함
--
-- @param unsort boolean true면 정렬하지 않음, false/nil이면 파티/직업/이름 순으로 정렬
-- @return table, table 플레이어 목록 배열, fullName을 키로 하는 맵
function GetPlayerList(unsort)
    local ret = {}           -- 반환할 플레이어 목록 배열
    local retNameMap = {}    -- 중복 체크 및 빠른 접근을 위한 맵 (키: fullName)
    local currentPlayerRealm = GetSafeRealmName()  -- 안전한 서버명 가져오기

    if IsInRaid() then
        -- ===== 공대(Raid)일 경우 =====
        -- 공대는 최대 40명, 8개 파티로 구성
        local numGroupMembers = GetNumGroupMembers()
        
        for i = 1, numGroupMembers do
            -- GetRaidRosterInfo: 공대원 정보를 가져오는 Blizzard API
            -- 반환값: name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, realName
            local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, realName = GetRaidRosterInfo(i)

            -- ===== 🔥 제미니 피드백 반영 (1/4): 공대 name 타입 체크 추가 =====
            -- GetRaidRosterInfo에서 반환되는 name도 Secret Value일 수 있음
            -- 특히 던전 로딩 중, 크로스 서버 동기화 중에 불안정
            -- 
            -- 조건 설명:
            --   name: nil이 아님
            --   type(name) == "string": 문자열 타입임 (Secret Value 아님) ← 🌟 제미니 피드백 핵심!
            --   name ~= "": 빈 문자열이 아님
            --   name ~= SAFE_UNKNOWN_UNIT: "Unknown" 같은 무효한 이름이 아님
            --   class: 직업 정보가 있음
            if name and type(name) == "string" and name ~= "" and name ~= SAFE_UNKNOWN_UNIT and class then
                local shortName, fullName

                -- 이름에 서버명이 포함되어 있는지 확인
                if string.find(name, "-") then
                    fullName = name
                    shortName = GetShortName(name)
                else
                    shortName = name
                    fullName = name .. "-" .. currentPlayerRealm
                end

                -- 중복 체크
                if not retNameMap[fullName] then
                    local englishClass = ConvertClassToEnglish(class)

                    local entry = {
                        ["name"] = shortName,
                        ["fullName"] = fullName,
                        ["class"] = englishClass,
                        ["party"] = subgroup,
                        ["role"] = role
                    }
                    
                    table.insert(ret, entry)
                    retNameMap[fullName] = entry
                end
            end
        end
        
    elseif IsInGroup() then
        -- ===== 파티(Party)일 경우 =====
        -- 파티는 최대 5명 (플레이어 자신 + 파티원 4명)
        
        -- 1. 플레이어 자신 추가
        local player_name = UnitName("player")
        
        
        -- UnitName("player")도 특정 상황에서 Secret Value를 반환할 수 있음
        -- 특히 다음 상황에서 불안정:
        --   - 로딩 화면 중
        --   - 인스턴스 입장 직후
        --   - 크로스 서버 동기화 중
        --   - 전투 중 특정 타이밍
        
        local player_fullName = GetSafeUnitFullName("player")
        
        if not player_fullName or player_fullName == "" then
            player_fullName = (player_name or "Unknown") .. "-" .. currentPlayerRealm
        end

        
        -- 조건 설명:
        --   player_name: nil이 아님
        --   type(player_name) == "string": 문자열 타입임 
        --   player_name ~= "": 빈 문자열이 아님
        --   player_name ~= SAFE_UNKNOWN_UNIT: "Unknown" 같은 무효한 이름이 아님
        if player_name and type(player_name) == "string" and player_name ~= "" and player_name ~= SAFE_UNKNOWN_UNIT then
            local _, player_class = UnitClass("player")
            local player_role = UnitGroupRolesAssigned("player")
            local englishClass = ConvertClassToEnglish(player_class)

            local player_entry = {
                ["name"] = player_name,
                ["fullName"] = player_fullName,
                ["class"] = englishClass,
                ["party"] = 1,
                ["role"] = player_role
            }
            table.insert(ret, player_entry)
            retNameMap[player_fullName] = player_entry
        end

        -- 2. 파티원들 추가
        local numPartyMembers = GetNumSubgroupMembers()  -- 파티원 수 (자신 제외, 최대 4명)
        
        for i = 1, numPartyMembers do
            local unitId = "party" .. i  -- "party1", "party2", "party3", "party4"
            local name = UnitName(unitId)
            
            
            -- 파티원의 UnitName(unitId)도 Secret Value를 반환할 수 있음
            -- 특히 다음 상황에서 위험:
            --   - 파티원이 막 입장한 직후
            --   - 파티원이 막 퇴장한 직후
            --   - 던전 로딩 중
            --   - 크로스 서버 플레이어
            -- 
            -- 이 루프는 매우 자주 실행되므로 방어가 특히 중요!
            
            local fullName = GetSafeUnitFullName(unitId)

            if not fullName or fullName == "" then
                fullName = (name or "Unknown") .. "-" .. currentPlayerRealm
            end

            
            -- 유효성 검사 및 중복 체크 (타입 체크 포함)
            -- 
            -- 조건 설명:
            --   name: nil이 아님
            --   type(name) == "string": 문자열 타입임 ← 🌟 제미니 피드백 핵심!
            --   name ~= "": 빈 문자열 아님
            --   name ~= SAFE_UNKNOWN_UNIT: 무효한 이름 아님
            --   UnitIsPlayer(unitId): 플레이어 유닛임 (펫이나 NPC가 아님)
            --   not retNameMap[fullName]: 중복 아님
            if name and type(name) == "string" and name ~= "" and name ~= SAFE_UNKNOWN_UNIT and UnitIsPlayer(unitId) and not retNameMap[fullName] then
                local _, class = UnitClass(unitId)
                local role = UnitGroupRolesAssigned(unitId)
                local englishClass = ConvertClassToEnglish(class)

                local entry = {
                    ["name"] = GetShortName(fullName),
                    ["fullName"] = fullName,
                    ["class"] = englishClass,
                    ["party"] = 1,
                    ["role"] = role
                }
                table.insert(ret, entry)
                retNameMap[fullName] = entry
            end
        end
        
    else
        -- ===== 솔로(혼자)일 경우 =====
        -- 파티나 공대에 속하지 않은 경우
        
        local player_name = UnitName("player")
        
        
        -- 솔로일 때도 UnitName("player")가 Secret Value를 반환할 수 있음
        -- 특히 다음 상황에서:
        --   - 게임 시작 직후
        --   - 인스턴스에서 나온 직후
        --   - 로딩 화면 중
        
        local player_fullName = GetSafeUnitFullName("player")
        
        if not player_fullName or player_fullName == "" then
            player_fullName = (player_name or "Unknown") .. "-" .. currentPlayerRealm
        end

        
        -- 조건 설명:
        --   player_name: nil이 아님
        --   type(player_name) == "string": 문자열 타입임 ← 🌟 제미니 피드백 완료!
        --   player_name ~= "": 빈 문자열이 아님
        --   player_name ~= SAFE_UNKNOWN_UNIT: "Unknown" 같은 무효한 이름이 아님
        if player_name and type(player_name) == "string" and player_name ~= "" and player_name ~= SAFE_UNKNOWN_UNIT then
            local _, player_class = UnitClass("player")
            local player_role = UnitGroupRolesAssigned("player")
            local englishClass = ConvertClassToEnglish(player_class)

            local player_entry = {
                ["name"] = player_name,
                ["fullName"] = player_fullName,
                ["class"] = englishClass,
                ["party"] = nil,
                ["role"] = player_role
            }
            table.insert(ret, player_entry)
            retNameMap[player_fullName] = player_entry
        end
    end

    -- 정렬
    if not unsort then
        table.sort(ret, function(a, b)
            if not a or not b then
                return false
            end
            
            if a.party and b.party and a.party ~= b.party then
                return a.party < b.party
            end
            
            if a.class and b.class and a.class ~= b.class then
                return a.class < b.class
            end
            
            if a.fullName and b.fullName then
                return a.fullName < b.fullName
            end
            
            return false
        end)
    end

    return ret, retNameMap
end

-- 아직 주사위를 굴리지 않은 플레이어 목록을 생성하고 UI에 표시하는 함수
-- @return string 포맷된 텍스트
function NotRolled()
    if IsInGroup() or IsInRaid() then
        local partyList, _ = GetPlayerList()
        local partyGroups = {}

        for _, p in ipairs(partyList) do
            if p and p.fullName then
                if rollNames[p.fullName] == nil or rollNames[p.fullName] == 0 then
                    local partyNum = p.party or 1
                    
                    if not partyGroups[partyNum] then
                        partyGroups[partyNum] = {}
                    end
                    
                    table.insert(partyGroups[partyNum], p)
                end
            end
        end

        local namesText = ""
        local sortedParties = {}
        for partyNum, _ in pairs(partyGroups) do
            table.insert(sortedParties, partyNum)
        end
        table.sort(sortedParties)

        for _, partyNum in ipairs(sortedParties) do
            local partyMembers = partyGroups[partyNum]

            if IsInRaid() and #partyMembers > 0 then
                namesText = namesText .. string.format("|cff00ff00=== %d파티 ===|r\n", partyNum)
            end

            for _, p in ipairs(partyMembers) do
                if p and p.class and p.fullName then
                    local englishClass = ConvertClassToEnglish(p.class)
                    local classColor = Mim_GetClassColor(englishClass)
                    local classIcon = IconClass[englishClass] or ""

                    local displayName
                    if IsSameRealm(p.fullName) then
                        displayName = p.name
                    else
                        displayName = p.fullName
                    end

                    namesText = namesText .. string.format("%s%s%s|r\n",
                                                            classIcon,
                                                            classColor,
                                                            displayName)
                end
            end
        end

        if namesText ~= "" then
            return namesText
        else
            return "<주사위 모두 굴림>"
        end
    else
        return ""
    end
end

-- GROUP_ROSTER_UPDATE 이벤트 핸들러
function MimDice_GROUP_ROSTER_UPDATE()
    -- 전투 중에도 자주 발동(펫 소환/입퇴장/정신지배 등)하므로 pcall로 감싸
    -- 예상 못한 secret value 등으로 인한 lua error를 차단 (다음 갱신 때 정상화)
    pcall(function()
        GetPlayerList()
        UpdateClassIconsBasedOnParty()
        MimDice_UpdateList()
    end)
end

-- 애드온 초기 로딩 시 호출되는 함수
-- @param self frame 메인 프레임 객체
function MimDice_OnLoad(self)
    -- 서버명 캐싱 초기화
    cachedRealmName = GetRealmName()
    
    -- 저장된 폰트 설정 불러오기
    if MimDiceDB.fontName == nil or MimDiceDB.fontName == "" then
        fontName = "Fonts\\2002.TTF"
    else
        fontName = MimDiceDB.fontName
    end

    if MimDiceDB.fontHeight ~= nil then
        fontHeight = MimDiceDB.fontHeight
    else
        fontHeight = 16
    end

    -- 자동 팝업 설정
    if MimDiceDB.autoPopup == nil then
        MimDiceDB.autoPopup = true
    end

    if MimDiceDB.autoReset == nil then
        MimDiceDB.autoReset = false
    end

    if MimDiceDB.autoResetMinutes == nil then
        MimDiceDB.autoResetMinutes = 5
    end

    -- 폰트 설정 적용
    if _G["RollStrings"] then
        _G["RollStrings"]:SetFont(fontName, fontHeight)
    end

    -- 정렬 버튼 설정
    if _G["UpBtn"] then
        _G["UpBtn"]:SetChecked(true)
        _G["UpBtn"]:Disable()
    end
    if _G["DownBtn"] then
        _G["DownBtn"]:SetChecked(false)
        _G["DownBtn"]:Enable()
    end

    -- 자동 팝업 체크박스 상태 복원
    if _G["AutopopupCheckBox"] then
        _G["AutopopupCheckBox"]:SetChecked(MimDiceDB.autoPopup)
    end

    -- 테이블 초기화
    rollArray = {}
    rollNames = {}

    -- 창 위치와 크기 복원
    local x, y, w, h = MimDiceDB.X, MimDiceDB.Y, MimDiceDB.Width, MimDiceDB.Height
    if not x or not y or not w or not h then
        MimDice_SaveAnchors()
    else
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
        self:SetWidth(w)
        self:SetHeight(h)
    end

    -- 초기 클래스 아이콘 투명도 설정
    UpdateClassIconsBasedOnParty()

    -- 슬래시 명령어 등록
    SLASH_MIMDICE1 = "/mimdice"
    SLASH_MIMDICE2 = "/md"
    SLASH_MIMDICE3 = "/밈"
    SLASH_MIMDICE4 = "/ala"
    SLASH_MIMDICE5 = "/밈주사위"
    SlashCmdList["MIMDICE"] = function (msg)
        MimDice_ShowWindow()
    end
end

-- ===== CHAT_MSG_SYSTEM 이벤트 핸들러 (SECRET VALUE 오류 수정) =====
-- @param msg string 시스템 채팅 메시지
function MimDice_CHAT_MSG_SYSTEM(msg)
    local success, errorMsg = pcall(function()
        -- ===== 1단계: SECRET VALUE 체크 (가장 먼저!) =====
        -- msg가 secret value인지 확인
        -- secret value면 문자열 변환이 불가능하므로 바로 리턴
        if type(msg) ~= "string" then
            -- msg가 문자열이 아니면 처리하지 않음
            return
        end
        
        -- msg가 nil이거나 빈 문자열이면 처리하지 않음
        if not msg or msg == "" then
            return
        end
        
        -- ===== 2단계: 주사위 굴림 메시지 파싱 =====
        local isDiceRollDetected = false

        -- string.gmatch도 secret value를 만나면 오류를 일으킬 수 있으므로
        -- pcall로 한 번 더 감싸기
        local parseSuccess, parseResult = pcall(function()
            for name, roll, minRoll, maxRoll in string.gmatch(msg, pattern) do
                isDiceRollDetected = true

                -- ===== 3단계: 파싱된 값들의 유효성 검사 =====
                -- name도 secret value일 수 있으므로 체크
                if not name or name == "" or type(name) ~= "string" then
                    break
                end
                
                -- roll, minRoll, maxRoll도 안전하게 변환
                local rollNum = tonumber(roll)
                local minRollNum = tonumber(minRoll)
                local maxRollNum = tonumber(maxRoll)
                
                -- 숫자 변환 실패 시 기본값 설정
                if not rollNum then rollNum = 0 end
                if not minRollNum then minRollNum = 0 end
                if not maxRollNum then maxRollNum = 0 end
                
                local actualFullName = nil
                local playerClass = "UNKNOWN"
                local currentPlayerRealm = GetSafeRealmName()

                -- 파티/공대 목록 가져오기
                local partyList, partyNameMap = GetPlayerList(true)
                local potentialPlayers = {}
                
                -- 메시지 이름과 일치하는 플레이어 찾기
                for _, p_entry in ipairs(partyList) do
                    if p_entry and p_entry.fullName then
                        local entryShortName = GetShortName(p_entry.fullName)
                        if entryShortName == name then
                            table.insert(potentialPlayers, p_entry)
                        end
                    end
                end

                -- ===== 4단계: 플레이어 특정 =====
                if #potentialPlayers == 1 then
                    actualFullName = potentialPlayers[1].fullName
                    playerClass = potentialPlayers[1].class
                    
                elseif #potentialPlayers > 1 then
                    -- 기존 굴림 기록 확인
                    for _, p_entry in ipairs(potentialPlayers) do
                        if rollNames[p_entry.fullName] and rollNames[p_entry.fullName] > 0 then
                            actualFullName = p_entry.fullName
                            playerClass = p_entry.class
                            break
                        end
                    end

                    -- 기록으로도 특정할 수 없다면
                    if not actualFullName then
                        -- 현재 서버의 플레이어 우선
                        for _, p_entry in ipairs(potentialPlayers) do
                            if IsSameRealm(p_entry.fullName) then
                                actualFullName = p_entry.fullName
                                playerClass = p_entry.class
                                break
                            end
                        end
                        
                        -- 현재 서버 플레이어가 없다면 첫 번째 후보 선택
                        if not actualFullName then
                            actualFullName = potentialPlayers[1].fullName
                            playerClass = potentialPlayers[1].class
                        end
                    end
                    
                else -- 파티/공대 목록에 없는 플레이어
                    if name == UnitName("player") then
                        actualFullName = GetSafeUnitFullName("player")
                        
                        if not actualFullName or actualFullName == "" then
                            actualFullName = name .. "-" .. currentPlayerRealm
                        end
                        
                        local _, myClass = UnitClass("player")
                        playerClass = ConvertClassToEnglish(myClass)
                    else
                        actualFullName = name .. "-" .. currentPlayerRealm
                    end
                end

                -- 최종 안전장치
                if not actualFullName or actualFullName == "" then
                    actualFullName = name .. "-" .. currentPlayerRealm
                end

                -- 굴림 횟수 증가
                rollNames[actualFullName] = (rollNames[actualFullName] or 0) + 1

                -- 주사위 굴림 결과 저장
                table.insert(rollArray, {
                    Class = playerClass,
                    Name = name,
                    FullName = actualFullName,
                    Roll = rollNum,
                    Min = minRollNum,
                    Max = maxRollNum,
                    Count = rollNames[actualFullName]
                })
                
                -- UI 업데이트
                if MimDiceDB.autoReset then
                    MimDice_LastRollTime = GetTime()
                    local delay = (MimDiceDB.autoResetMinutes or 5) * 60
                    C_Timer.After(delay, function()
                        if MimDiceDB.autoReset and (GetTime() - MimDice_LastRollTime) >= (delay - 1) then
                            MimDice_ClearRolls()
                            local mins = MimDiceDB.autoResetMinutes or 5
                            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MimDice]|r " .. mins .. "분동안 주사위 굴림이 감지되지 않아 주사위를 초기화 합니다.")
                        end
                    end)
                end
                MimDice_UpdateList()
            end
        end)
        
        -- 파싱 과정에서 오류 발생 시
        if not parseSuccess then
            -- secret value로 인한 오류일 가능성이 높음
            -- 조용히 무시 (오류 메시지 출력하지 않음)
            return
        end

        -- 자동 팝업 로직
        if isDiceRollDetected and MimDiceDB.autoPopup then
            if _G["MainWindow"] and not _G["MainWindow"]:IsVisible() then
                _G["MainWindow"]:Show()
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MimDice]|r 주사위 굴림이 감지되어 창을 자동으로 열었습니다.")
            end
        end
    end)

    -- 최상위 오류 발생 시에만 로그 출력
    if not success then
        -- 오류 메시지가 secret value 관련이 아닐 때만 출력
        local errorString = SafeToString(errorMsg)
        if errorString ~= "" and not string.find(errorString, "secret") then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[MimDice 오류]|r " .. errorString)
        end
    end
end
-- ===== CHAT_MSG_SYSTEM 이벤트 핸들러 끝 =====

-- 미니맵 토글 버튼 기능
function ToggleMinimapBtn()
    if _G["MainWindow"] then
        if _G["MainWindow"]:IsVisible() then
            _G["MainWindow"]:Hide()
        else
            _G["MainWindow"]:Show()
        end
    end
end

-- '높은 수' 정렬 버튼 클릭 시 동작
function Sort_Up()
    if _G["UpBtn"] then
        _G["UpBtn"]:SetChecked(true)
        _G["UpBtn"]:Disable()
    end
    if _G["DownBtn"] then
        _G["DownBtn"]:SetChecked(false)
        _G["DownBtn"]:Enable()
    end
    MimDice_UpdateList()
end

-- '낮은 수' 정렬 버튼 클릭 시 동작
function Sort_Down()
    if _G["DownBtn"] then
        _G["DownBtn"]:SetChecked(true)
        _G["DownBtn"]:Disable()
    end
    if _G["UpBtn"] then
        _G["UpBtn"]:SetChecked(false)
        _G["UpBtn"]:Enable()
    end
    MimDice_UpdateList()
end

-- 주사위 결과 정렬 기준 함수
function Choice_Sort(a, b)
    if not a or not b then
        return false
    end
    
    local aRoll = a.Roll or 0
    local bRoll = b.Roll or 0
    
    if _G["UpBtn"] and _G["UpBtn"]:GetChecked() then
        return aRoll < bRoll
    elseif _G["DownBtn"] and _G["DownBtn"]:GetChecked() then
        return aRoll > bRoll
    end
    
    return false
end

-- 주사위 결과 역순 정렬 기준 함수
function Choice_Sort_Reverse(b, a)
    if not a or not b then
        return false
    end
    
    local aRoll = a.Roll or 0
    local bRoll = b.Roll or 0
    
    if _G["UpBtn"] and _G["UpBtn"]:GetChecked() then
        return aRoll < bRoll
    elseif _G["DownBtn"] and _G["DownBtn"]:GetChecked() then
        return aRoll > bRoll
    end
    
    return false
end

-- 스크롤 프레임 창을 업데이트하고 주사위 굴림 결과를 표시하는 함수
function MimDice_UpdateList()
    local success, errorMsg = pcall(function()
        local rollText = ""
        local currentPlayerRealm = GetSafeRealmName()

        table.sort(rollArray, Choice_Sort)

        for i, roll in ipairs(rollArray) do
            if roll then
                roll.Roll = roll.Roll or 0
                roll.Name = roll.Name or "Unknown"
                roll.FullName = roll.FullName or "Unknown"
                roll.Class = roll.Class or "UNKNOWN"
                roll.Min = roll.Min or 0
                roll.Max = roll.Max or 0
                roll.Count = roll.Count or 1
                
                local tied = (rollArray[i + 1] and roll.Roll == rollArray[i + 1].Roll) or
                             (rollArray[i - 1] and roll.Roll == rollArray[i - 1].Roll)

                local diff = false
                local standardNumber = nil
                if _G["DiceEditBox"] then
                    standardNumber = tonumber(_G["DiceEditBox"]:GetText())
                end
                if standardNumber and standardNumber > 0 and roll.Max and standardNumber ~= roll.Max then
                    diff = true
                end

                local brkt = tied and "> " or ""
                local classIcon = IconClass[roll.Class] or ""
                local classColor = Mim_GetClassColor(roll.Class)

                local displayName = roll.Name
                
                if roll.FullName and type(roll.FullName) == "string" and string.find(roll.FullName, "-") then
                    local _, realmPart = string.match(roll.FullName, "^(.-)%-(.+)$")
                    
                    if realmPart and realmPart ~= currentPlayerRealm then
                        displayName = roll.FullName
                    end
                end

                local rollValueColor = tied and "ffff0000" or "ffffcccc"
                local rangeTextColor = diff and "ffff0000" or "ffffcccc"

                local rangeText = ""
                if (roll.Min ~= 0 or roll.Max ~= 0) then
                    rangeText = string.format(" |c%s(%d-%d)|r", rangeTextColor, roll.Min, roll.Max)
                end
                
                local countText = roll.Count > 1 and format(" [%2d번굴림]", roll.Count) or ""

                rollText = string.format("%s|c%s%d|r : %s%s%s|r%s%s\n",
                                 brkt,
                                 rollValueColor,
                                 roll.Roll,
                                 classIcon,
                                 classColor,
                                 displayName,
                                 rangeText,
                                 countText) .. rollText
            end
        end

        -- ===== UI 텍스트 업데이트 =====
        -- 주사위를 굴린 사람이 있을 때만 "아직 안 굴린 사람" 목록 표시
        -- 
        --  Lua 5.1 최신 문법 적용:
        -- [기존] table.getn(rollArray) > 0  ← Lua 5.0 구식 문법 (deprecated)
        -- [수정] #rollArray > 0              ← Lua 5.1 표준 문법
        -- 
        -- # 연산자: 테이블의 길이를 반환 (Lua 5.1+)
        -- table.getn()은 Lua 5.1부터 사용 중단 권고됨
        if #rollArray > 0 then
            if _G["RollStrings"] then
                _G["RollStrings"]:SetText(rollText .. "\n" .. "--- 아직 주사위 안 굴린 사람 ---" .. "\n" .. NotRolled())
            end
        else
            if _G["RollStrings"] then
                _G["RollStrings"]:SetText("굴려굴려 주사위~!")
            end
        end

        local uniqueRollers = 0
        for name, count in pairs(rollNames) do
            if count and count > 0 then
                uniqueRollers = uniqueRollers + 1
            end
        end

        if _G["MimDiceStatusTextFrame"] then
            _G["MimDiceStatusTextFrame"]:SetText(string.format("%d 명 굴림", uniqueRollers))
        end
    end)

    if not success then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[MimDice 업데이트 오류]|r " .. tostring(errorMsg))
    end
end

-- 주사위 결과를 채팅창에 발표하는 함수
function MimDice_RollAnnounce()
    local success, errorMsg = pcall(function()
        local brkt
        local selectedChannel = SelectChannel()
        
        if not selectedChannel or selectedChannel == "SAY" then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00-------주사위결과-------|r")
            
            table.sort(rollArray, Choice_Sort_Reverse)
            local currentPlayerRealm = GetSafeRealmName()

            for i, roll in ipairs(rollArray) do
                if not roll then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[MimDice 오류]|r roll 데이터가 nil입니다.")
                    return
                end
                
                roll.Roll = roll.Roll or 0
                roll.Name = roll.Name or "Unknown"
                roll.FullName = roll.FullName or "Unknown"
                roll.Class = roll.Class or "UNKNOWN"
                roll.Min = roll.Min or 0
                roll.Max = roll.Max or 0
                roll.Count = roll.Count or 1

                local tied = (rollArray[i + 1] and roll.Roll == rollArray[i + 1].Roll) or
                             (rollArray[i - 1] and roll.Roll == rollArray[i - 1].Roll)

                if tied then
                    brkt = "동탈"
                else
                    brkt = "    "
                end

                local standardNumber = nil
                if _G["DiceEditBox"] then
                    standardNumber = tonumber(_G["DiceEditBox"]:GetText())
                end
                local diff = (standardNumber and roll.Max and standardNumber ~= roll.Max)

                local displayName = roll.Name
                if roll.FullName and string.find(roll.FullName, "-") then
                    local _, realmPart = string.match(roll.FullName, "^(.-)%-(.+)$")
                    if realmPart and realmPart ~= currentPlayerRealm then
                        displayName = roll.FullName
                    end
                end

                local classIcon = IconClass[roll.Class] or ""
                local classColor = Mim_GetClassColor(roll.Class) or "|cffffffff"
                
                local rollColorCode = tied and "|cffff0000" or "|cffffcccc"
                local nameColor = diff and "|cffff0000" or classColor
                
                local rangeText = ""
                if (roll.Min ~= 0 or roll.Max ~= 0) then
                    rangeText = string.format(" (%d-%d)", roll.Min, roll.Max)
                end
                
                local countText = ""
                if roll.Count > 1 then
                    countText = string.format(" [%2d번굴림]", roll.Count)
                end

                local finalMessage = brkt .. rollColorCode .. roll.Roll .. "|r : " .. 
                                   classIcon .. nameColor .. displayName .. "|r" .. 
                                   rangeText .. countText

                table.insert(RankList, finalMessage)
                DEFAULT_CHAT_FRAME:AddMessage(finalMessage)
            end
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00----------끝----------|r")
            
        else
            SendChatMessage("-------주사위결과-------", selectedChannel)

            table.sort(rollArray, Choice_Sort_Reverse)
            local currentPlayerRealm = GetSafeRealmName()

            for i, roll in ipairs(rollArray) do
                if not roll then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[MimDice 오류]|r roll 데이터가 nil입니다.")
                    return
                end
                
                roll.Roll = roll.Roll or 0
                roll.Name = roll.Name or "Unknown"
                roll.FullName = roll.FullName or "Unknown"
                roll.Class = roll.Class or "UNKNOWN"
                roll.Min = roll.Min or 0
                roll.Max = roll.Max or 0
                roll.Count = roll.Count or 1

                local tied = (rollArray[i + 1] and roll.Roll == rollArray[i + 1].Roll) or
                             (rollArray[i - 1] and roll.Roll == rollArray[i - 1].Roll)

                if tied then
                    brkt = "동탈"
                else
                    brkt = "    "
                end

                local standardNumber = nil
                if _G["DiceEditBox"] then
                    standardNumber = tonumber(_G["DiceEditBox"]:GetText())
                end
                local diff = (standardNumber and roll.Max and standardNumber ~= roll.Max)

                local displayName = roll.Name
                if roll.FullName and string.find(roll.FullName, "-") then
                    local _, realmPart = string.match(roll.FullName, "^(.-)%-(.+)$")
                    if realmPart and realmPart ~= currentPlayerRealm then
                        displayName = roll.FullName
                    end
                end

                local rollDisplayColor = tied and "동탈" or "    "
                local nameDisplayColor = diff and "[오류]" or ""
                
                local rangeText = ""
                if (roll.Min ~= 0 or roll.Max ~= 0) then
                    rangeText = string.format(" (%d-%d)", roll.Min, roll.Max)
                end
                
                local countText = ""
                if roll.Count > 1 then
                    countText = string.format(" [%2d번굴림]", roll.Count)
                end

                local finalMessage = brkt .. roll.Roll .. " : " .. 
                                   nameDisplayColor .. displayName .. 
                                   rangeText .. countText

                table.insert(RankList, finalMessage)
                SendChatMessage(finalMessage, selectedChannel)
            end
            SendChatMessage("----------끝----------", selectedChannel)
        end
    end)

    if not success then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[MimDice 결과 보고 오류]|r " .. tostring(errorMsg))
    end
end

-- 창 위치와 크기 저장 함수
function MimDice_SaveAnchors()
    if _G["MainWindow"] then
        MimDiceDB.X = _G["MainWindow"]:GetLeft()
        MimDiceDB.Y = _G["MainWindow"]:GetTop()
        MimDiceDB.Width = _G["MainWindow"]:GetWidth()
        MimDiceDB.Height = _G["MainWindow"]:GetHeight()
    end
end

-- 창 띄우기 함수
function MimDice_ShowWindow()
    if _G["MainWindow"] then
        _G["MainWindow"]:Show()
        UpdateClassIconsBasedOnParty()
    end
end

-- 창 닫기 함수
function MimDice_HideWindow()
    if _G["MainWindow"] then
        _G["MainWindow"]:Hide()
    end
    
    MimDiceDB.fontName = fontName
    MimDiceDB.fontHeight = fontHeight
end

-- 주사위 리셋 함수
function MimDice_ClearRolls()
    rollArray = {}
    rollNames = {}
    RankList = {}
    MimDice_LastRollTime = 0
    
    DEFAULT_CHAT_FRAME:AddMessage("주사위가 초기화 되었습니다.")
    
    UpdateClassIconsBasedOnParty()
    MimDice_UpdateList()
end

-- 채팅 채널 선택 함수
function SelectChannel()
    local SendChatMessageChannel
    
    if IsInRaid() and UnitIsGroupLeader("player") then
        SendChatMessageChannel = "RAID_WARNING"
    elseif IsInRaid() then
        SendChatMessageChannel = "RAID"
    elseif IsInGroup() then
        SendChatMessageChannel = "PARTY"
    else
        SendChatMessageChannel = "SAY"
    end
    
    return SendChatMessageChannel
end

-- 더 안전한 버전
function SelectChannelSafe()
    local SendChatMessageChannel
    
    if IsInRaid() and UnitIsGroupLeader("player") then
        SendChatMessageChannel = "RAID_WARNING"
    elseif IsInRaid() then
        SendChatMessageChannel = "RAID"
    elseif IsInGroup() then
        SendChatMessageChannel = "PARTY"
    else
        if UnitAffectingCombat("player") then
            DEFAULT_CHAT_FRAME:AddMessage("주사위 결과:")
            return nil
        else
            SendChatMessageChannel = "SAY"
        end
    end
    
    return SendChatMessageChannel
end

-- 주사위 시작 메시지 전송 함수
function Prefix()
    local success, errorMsg = pcall(function()
        local T_Prefix = "탱커님들 "
        local D_Prefix = "딜러님들 "
        local H_Prefix = "힐러님들 "
        local Dice_Text = "주사위 "
        local Space = " "
        local Num_Dice = _G["DiceEditBox"] and _G["DiceEditBox"]:GetText() or "100"
        local High_Text = "하이 "
        local Low_Text = "로우 "
        local Suffix = _G["MainEditBox"] and _G["MainEditBox"]:GetText() or ""
        local StartLine = "=============================="
        local Final_Text = ""
        local EndLine = "=============================="

        local function T_Check()
            if _G["TankCheckBox"] and _G["TankCheckBox"]:GetChecked() then
                return T_Prefix
            else
                return ""
            end
        end

        local function D_Check()
            if _G["DpsCheckBox"] and _G["DpsCheckBox"]:GetChecked() then
                return D_Prefix
            else
                return ""
            end
        end

        local function H_Check()
            if _G["HealCheckBox"] and _G["HealCheckBox"]:GetChecked() then
                return H_Prefix
            else
                return ""
            end
        end

        local function High_Check()
            if _G["UpBtn"] and _G["UpBtn"]:GetChecked() then
                return High_Text
            else
                return ""
            end
        end

        local function Low_Check()
            if _G["DownBtn"] and _G["DownBtn"]:GetChecked() then
                return Low_Text
            else
                return ""
            end
        end

        Final_Text = T_Check() .. D_Check() .. H_Check() .. Dice_Text .. Num_Dice .. Space .. High_Check() .. Low_Check() .. Suffix

        SendChatMessage(StartLine, SelectChannel())
        SendChatMessage(Final_Text, SelectChannel())
        SendChatMessage(EndLine, SelectChannel())
    end)

    if not success then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[MimDice Prefix 오류]|r " .. tostring(errorMsg))
    end
end

-- 폰트 크기 증가 함수
function FontSizePlus()
    if _G["RollStrings"] then
        fontName, fontHeight, _ = _G["RollStrings"]:GetFont()
        _G["RollStrings"]:SetFont(fontName, fontHeight + 1)
        MimDiceDB.fontName = fontName
        MimDiceDB.fontHeight = fontHeight + 1
    end
end

-- 폰트 크기 감소 함수
function FontSizeMinus()
    if _G["RollStrings"] then
        fontName, fontHeight, _ = _G["RollStrings"]:GetFont()
        _G["RollStrings"]:SetFont(fontName, fontHeight - 1)
        MimDiceDB.fontName = fontName
        MimDiceDB.fontHeight = fontHeight - 1
    end
end

-- 창 위치 및 크기 초기화 함수
function FactoryReset()
    if _G["MainWindow"] then
        _G["MainWindow"]:ClearAllPoints()
        _G["MainWindow"]:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 500, 700)
        _G["MainWindow"]:SetWidth(300)
        _G["MainWindow"]:SetHeight(460)
    end
    
    fontName = "Fonts\\2002.ttf"
    fontHeight = 13
    
    if _G["RollStrings"] then
        _G["RollStrings"]:SetFont(fontName, fontHeight)
    end

    MimDiceDB.fontName = fontName
    MimDiceDB.fontHeight = fontHeight

    -- 전투부활 아이콘도 화면 정중앙으로 위치 초기화 (메인창과 함께 리셋)
    if MimDiceDB.battleRes then
        MimDiceDB.battleRes.iconX = 0
        MimDiceDB.battleRes.iconY = 0
        if SA_RefreshBattleResIconState then SA_RefreshBattleResIconState() end
    end
end

-- 자동 팝업 체크박스 클릭 시 호출되는 함수
function ToggleAutoPopup()
    if _G["AutopopupCheckBox"] then
        MimDiceDB.autoPopup = _G["AutopopupCheckBox"]:GetChecked()

        local status = MimDiceDB.autoPopup and "켜짐" or "꺼짐"
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MimDice]|r 자동 팝업: " .. status)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[MimDice 오류]|r 자동 팝업 체크박스를 찾을 수 없습니다. 애드온 UI 설정을 확인해주세요.")
    end
end

-- ===== MimFrame의 이벤트 처리 스크립트 =====
MimFrame:SetScript("OnEvent", function(self, event, ...)
    local msg = ...

    if (event == "ADDON_LOADED" and msg == "MimDice") then
        self:UnregisterEvent("ADDON_LOADED")
        
        MimDice_OnLoad(self)

        -- LibDBIcon 라이브러리를 사용하여 미니맵 버튼 구현
        local success, errorMsg = pcall(function()
            if LibStub then
                local MimDiceminimap = LibStub("LibDataBroker-1.1"):NewDataObject("MimDice", {
                    type = "data source",
                    text = "MIM DICE",
                    icon = "Interface\\AddOns\\MimDice\\img\\Mim_minimap_icon.tga",
                    
                    OnClick = function(frame, button)
                        if button == "LeftButton" then
                            ToggleMinimapBtn()
                        elseif button == "RightButton" then
                            FactoryReset()
                        end
                    end,
                    
                    OnTooltipShow = function(tooltip)
                        if not tooltip or not tooltip.AddLine then
                            return
                        end
                        tooltip:AddLine("MIM DICE\n좌클릭 : 창 열기/닫기\n우클릭 : 위치,크기 초기화")
                    end,
                })

                local icon = LibStub("LibDBIcon-1.0", true)
                if icon then
                    icon:Register("MimDice", MimDiceminimap, MimDiceDB)
                end
            end
        end)

        if not success then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[MimDice LibDBIcon 오류]|r " .. tostring(errorMsg))
        end

    elseif (event == "CHAT_MSG_SYSTEM") then
        MimDice_CHAT_MSG_SYSTEM(msg)
    end
    
    if (event == "GROUP_ROSTER_UPDATE") then
        MimDice_GROUP_ROSTER_UPDATE()
    end
end)