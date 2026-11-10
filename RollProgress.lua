-- 주사위 진행 오버레이
-- 파티/공대 구성원이 처음 굴릴 때마다 "굴린 인원 / 전체 인원"을 잠깐 보여 준다.
-- 연달아 굴리면 마지막으로 굴린 사람 기준으로 표시 시간을 다시 센다.
-- 현재 구성원이 모두 굴리면 완료 문구와 함께 지정한 소리를 한 번 울린다.
-- 내 화면에만 표시하며 채팅으로는 보내지 않는다.
MimDiceRollProgress = {}
local RP = MimDiceRollProgress
local L = MimDice_L

local FADE_SECONDS = 0.4
local DEFAULT_SOUND = "Interface\\AddOns\\MimDice\\sounds\\3띠릭(높은소리).mp3"
local DEFAULT_X, DEFAULT_Y = 0, -170   -- 화면 위 가운데 기준

local defaults = {
    enabled = true, soundEnabled = true,
    soundType = "preset", soundFile = "", fontSize = 22, duration = 3,
    progressText = "", doneText = "", bgAlpha = 0,
    x = DEFAULT_X, y = DEFAULT_Y, locked = true,
}

local playSound           -- SoundAlert의 공통 재생 함수 (SA_PlaySound)
local provider            -- function() return members, rollNames, rosterComplete end
local display
-- 완료 알림을 이미 알린 구성원 묶음. 지금 구성원이 모두 이 안에 있으면 다시 알리지 않는다.
-- (같은 사람 재굴림, 이벤트 반복, 굴린 사람이 나간 경우) 새 사람이 섞이면 다시 알릴 수 있다.
local announcedSet = nil
-- 기능을 다시 켠 뒤, 구성원 정보가 온전해질 때까지 기준 상태 확정을 미룬다.
local rearmPending = false
local rearmSawRoll = false   -- 대기 중에 구성원의 첫 굴림이 있었는가 (있으면 복구 후 완료를 판단)

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- ── 설정 ─────────────────────────────────────────────────────────────
function RP.GetSettings()
    if type(MimDiceDB) ~= "table" then return nil end
    if type(MimDiceDB.rollProgress) ~= "table" then MimDiceDB.rollProgress = {} end
    local config = MimDiceDB.rollProgress

    -- 처음 만든 형식(enabled / sound / soundFile)에서 한 번만 옮긴다.
    if not config.migratedV2 then
        if type(config.sound) == "boolean" and config.soundEnabled == nil then
            config.soundEnabled = config.sound
        end
        local old = config.soundFile
        if config.soundType == nil and type(old) == "string" and old ~= "" then
            if MimDiceSoundFiles and MimDiceSoundFiles.IsBundledPath(old) then
                config.soundType, config.soundKey = "preset", old
                config.soundFile = ""
            else
                config.soundType = "custom"   -- 사용자가 직접 적은 파일명은 그대로 둔다
            end
        end
        config.sound = nil
        config.migratedV2 = true
    end

    -- 비어 있거나 자료형이 맞지 않는 칸에만 기본값을 넣는다. (false는 그대로 둔다)
    for key, value in pairs(defaults) do
        if type(config[key]) ~= type(value) then config[key] = value end
    end
    -- 내장 소리는 숫자(내장/SoundKit)나 밈다이스 파일 경로(문자열) 둘 다 가능하다.
    if type(config.soundKey) == "string" and tonumber(config.soundKey) then config.soundKey = tonumber(config.soundKey) end
    if type(config.soundID) == "string" and tonumber(config.soundID) then config.soundID = tonumber(config.soundID) end
    if config.soundKey == nil or (type(config.soundKey) ~= "number" and type(config.soundKey) ~= "string") then
        config.soundKey, config.soundName, config.soundIsKit = DEFAULT_SOUND, "띠릭(높은소리)", nil
    end
    if config.soundType ~= "preset" and config.soundType ~= "custom" and config.soundType ~= "id" then
        config.soundType = "preset"
    end
    -- 색은 표마다 따로 만든다 (기본값 표를 여러 설정이 함께 쓰지 않게)
    local function Color(key, r, g, b)
        local c = config[key]
        if type(c) ~= "table" or type(c.r) ~= "number" or type(c.g) ~= "number" or type(c.b) ~= "number" then
            config[key] = { r = r, g = g, b = b }
        end
    end
    Color("progressColor", 1, 0.82, 0)
    Color("doneColor", 0.3, 1, 0.3)
    Color("bgColor", 0, 0, 0)
    config.bgAlpha = math.max(0, math.min(1, config.bgAlpha))
    config.fontSize = math.max(12, math.min(60, config.fontSize))
    config.duration = math.max(1, math.min(10, config.duration))
    return config
end

-- ── 표시 ─────────────────────────────────────────────────────────────
-- 알림 창은 마우스를 전혀 받지 않는다(EnableMouse를 부르지 않음 = 기본 클릭 통과).
-- 위치 조정은 MoveHandle의 별도 손잡이가 맡는다. 전투 중 보호 함수 호출이 생기지 않는다.
local handle

local function EnsureDisplay()
    if display then return display end
    display = CreateFrame("Frame", "MimDice_RollProgress", UIParent)
    display:SetFrameStrata("HIGH")
    display:SetMovable(true)
    display:SetClampedToScreen(true)  -- 해상도/배율이 바뀌어도 화면 안에 둔다

    local bg = display:CreateTexture(nil, "BACKGROUND")   -- 사용자가 고른 배경색 (기본: 투명)
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0)
    display.bg = bg

    local text = display:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER")
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    text:SetWordWrap(false)
    display.text = text

    handle = MimDiceMoveHandle.Create(display, {
        onStop = function() RP.SavePosition() end,
        onCombat = function()   -- 전투가 시작돼 조정이 끝났다
            local c = RP.GetSettings()
            if c then c.locked = true end
            if display.kind == "preview" then display.elapsed = 0; display:Hide() end
            if RP.Config and RP.Config.RefreshEditBtn then RP.Config.RefreshEditBtn() end
        end,
        onHidden = function()   -- 초기화/기능 끄기 등으로 알림 창이 숨겨졌다
            local c = RP.GetSettings()
            if c then c.locked = true end
            if RP.Config and RP.Config.RefreshEditBtn then RP.Config.RefreshEditBtn() end
        end,
    })
    RP._handle = handle   -- 테스트 확인용
    display:SetScript("OnHide", function() handle:TargetHidden() end)

    display:SetScript("OnUpdate", function(self, elapsed)
        local config = RP.GetSettings()
        if not config then self:Hide(); return end
        if not config.locked then self:SetAlpha(1); return end   -- 위치 조정 중에는 사라지지 않는다
        self.elapsed = (self.elapsed or 0) + elapsed
        local remain = config.duration - self.elapsed
        if remain <= 0 then self:Hide(); return end
        self:SetAlpha(math.min(1, remain / FADE_SECONDS))
    end)
    display:Hide()
    return display
end

-- 저장 기준점은 하나: 화면 위 가운데(TOP)에서 오버레이 위 가운데까지의 거리.
function RP.SavePosition()
    if not display then return end
    local config = RP.GetSettings()
    local x, top = display:GetCenter(), display:GetTop()
    local cx, ptop = UIParent:GetCenter(), UIParent:GetTop()
    if config and x and top and cx and ptop then
        config.x = math.floor(x - cx + 0.5)
        config.y = math.floor(top - ptop + 0.5)
    end
    if RP.Config and RP.Config.posRefresh then RP.Config.posRefresh() end
end

-- 문구: 비워 두면 기본 문구. 진행은 "문구 3 / 30", 완료는 "문구 (30명)"으로 붙인다.
local function ProgressText(config, rolled, total)
    if config.progressText ~= "" then
        return string.format("%s %d / %d", config.progressText, rolled, total)
    end
    return string.format(L("Rolls %d / %d"), rolled, total)
end
local function DoneText(config, total)
    if config.doneText ~= "" then
        return config.doneText .. " " .. string.format(L("(%d players)"), total)
    end
    return string.format(L("Everyone has rolled (%d players)"), total)
end

-- which: "progress" 진행 / "done" 완료. 인자를 빼면 마지막 표시를 현재 설정으로 다시 그린다.
local function Style(which, a, b)
    local config = RP.GetSettings()
    local frame = EnsureDisplay()
    if which then frame.which, frame.a, frame.b = which, a, b end
    which = frame.which or "progress"
    if not (handle and handle.moving) then
        frame:ClearAllPoints()
        frame:SetPoint("TOP", UIParent, "TOP", config.x, config.y)
    end
    local path = MimDiceFontPath and MimDiceFontPath() or STANDARD_TEXT_FONT
    frame.text:SetFont(path, config.fontSize, "OUTLINE")
    local color
    if which == "done" then
        frame.text:SetText(DoneText(config, frame.a or 30))
        color = config.doneColor
    else
        frame.text:SetText(ProgressText(config, frame.a or 12, frame.b or 30))
        color = config.progressColor
    end
    frame.text:SetTextColor(color.r, color.g, color.b)
    frame.bg:SetColorTexture(config.bgColor.r, config.bgColor.g, config.bgColor.b, config.bgAlpha)
    -- 긴 문구/영어 번역도 잘리지 않게 글자 폭에 맞춰 영역을 넓힌다.
    local width = (frame.text:GetStringWidth() or 0) + 40
    frame:SetSize(math.max(240, width), config.fontSize * 2)
end

-- kind: "live" 실제 알림 / "preview" 미리보기
local function Show(kind, which, a, b)
    local frame = EnsureDisplay()
    -- 실제 알림 표시 중에는 미리보기로 덮지 않는다. 실제 알림은 미리보기를 덮는다.
    if kind == "preview" and frame:IsShown() and frame.kind == "live" then return false end
    Style(which, a, b)
    frame.kind, frame.elapsed = kind, 0
    frame:SetAlpha(1)   -- 사라지는 중이었어도 바로 원래 밝기로
    frame:Show()
    return true
end

local function HideDisplay()
    if display then
        display.elapsed = 0
        display:Hide()
    end
end

local function PlayDone(config)
    if not playSound or not config.soundEnabled then return end
    local copy = {}
    for key, value in pairs(config) do copy[key] = value end
    copy.enabled = true   -- 사본만 켠다. 저장된 설정은 바꾸지 않는다.
    pcall(playSound, copy, "Dialog")
end

-- ── 집계 ─────────────────────────────────────────────────────────────
local function Snapshot()
    if not provider then return nil end
    local ok, members, rollNames, rosterComplete = pcall(provider)
    if not ok or type(members) ~= "table" then return nil end
    local set, names, rolled = {}, {}, 0
    for _, p in ipairs(members) do
        local name = p and p.fullName
        if not IsSecret(name) and type(name) == "string" and name ~= "" and not set[name] then
            set[name] = true
            names[#names + 1] = name
            local n = type(rollNames) == "table" and rollNames[name] or nil
            if not IsSecret(n) and type(n) == "number" and n > 0 then rolled = rolled + 1 end
        end
    end
    table.sort(names)
    return {
        set = set, total = #names, rolled = rolled,
        complete = rosterComplete == true,   -- 이름을 못 읽은 사람이 있으면 false
        signature = table.concat(names, "\n"),
    }
end
RP.Snapshot = Snapshot

local testMode = false   -- 혼자 시험하기 중이면 가짜 파티로 본다

local function InGroup()
    if testMode then return true end
    local ok, inGroup = pcall(IsInGroup)
    if not ok or IsSecret(inGroup) then return false end
    return inGroup == true
end

-- 실제로 그룹을 떠났거나 혼자가 됐는지. 값을 읽을 수 없으면 "모름"(nil)
local function GroupGone()
    if testMode then return false end
    local ok, inGroup = pcall(IsInGroup)
    if not ok or IsSecret(inGroup) or type(inGroup) ~= "boolean" then return nil end
    if not inGroup then return true end
    local okN, n = pcall(GetNumGroupMembers)
    if not okN or IsSecret(n) or type(n) ~= "number" then return nil end
    return n < 2
end

local function IsSubset(set, of)
    if not of then return false end
    for name in pairs(set) do
        if not of[name] then return false end
    end
    return true
end

-- 굴림과 구성원 변경이 함께 쓰는 상태 판단.
-- newRoll: 지금 구성원이 처음 굴려서 호출됐는가
local function Sync(snap, config, newRoll)
    local allRolled = snap.rolled > 0 and snap.rolled == snap.total
    local announced = allRolled and IsSubset(snap.set, announcedSet)

    if rearmPending then
        -- 다시 켠 직후: 정보가 온전할 때 지금 상태를 기준으로만 삼고 소리는 내지 않는다.
        -- 그 사이 실제 새 굴림으로 완료됐다면 아래에서 정상적으로 알린다.
        if not snap.complete then
            if newRoll then
                rearmSawRoll = true
                Show("live", "progress", snap.rolled, snap.total)
            end
            return
        end
        rearmPending = false
        local sawRoll = rearmSawRoll
        rearmSawRoll = false
        if not newRoll and not sawRoll then
            announcedSet = allRolled and snap.set or nil
            return
        end
    end

    if allRolled and snap.complete and not announced then
        announcedSet = snap.set
        Show("live", "done", snap.total)
        PlayDone(config)
        return
    end
    if newRoll and not announced then
        -- 구성원 정보가 부족해 완료를 미룬 경우에도 진행 숫자는 보여 준다.
        Show("live", "progress", snap.rolled, snap.total)
    end
end

local function ClearState()
    announcedSet, rearmPending, rearmSawRoll = nil, false, false
    if display and display.kind == "live" then HideDisplay() end
end

-- 주사위 기록 직후 호출
function RP.OnRoll(fullName, isFirstRoll)
    local config = RP.GetSettings()
    if not config or not (config.enabled or testMode) or not InGroup() then return end
    local snap = Snapshot()
    if not snap then return end
    if snap.total < 2 then
        -- 이름이 한 명만 읽히는 상태. 실제 그룹이 유지되고 굴린 사람이 구성원이면
        -- 다시 켜기 대기 중의 첫 굴림 사실만 기억하고, 완료 판단은 정보 복구 후에 한다.
        if rearmPending and isFirstRoll == true and not IsSecret(fullName)
           and type(fullName) == "string" and snap.set[fullName] and GroupGone() == false then
            rearmSawRoll = true
        end
        return
    end
    -- 지금 구성원이 아닌 사람(주변 사람)의 굴림이나 같은 사람의 재굴림은 숫자/표시 시간을 바꾸지 않는다.
    -- 다만 구성원 정보가 그사이 바뀌었을 수 있으므로 상태 판단은 같이 한다.
    local member = not IsSecret(fullName) and type(fullName) == "string" and snap.set[fullName] == true
    Sync(snap, config, member and isFirstRoll == true)
end

-- 파티/공대 구성 변경 시 호출
function RP.OnRosterChanged()
    local config = RP.GetSettings()
    if not config or not config.enabled then return end
    -- 진짜로 그룹을 떠났거나 혼자일 때만 이력을 지운다.
    -- 이름을 잠깐 못 읽어 목록이 줄어든 경우에는 완료 이력과 다시 켜기 대기를 그대로 둔다.
    if GroupGone() == true then
        ClearState()
        rearmPending = true   -- 다시 들어오면 그때 상태를 조용히 기준으로 삼는다
        return
    end
    local snap = Snapshot()
    if not snap or snap.total < 2 then return end
    Sync(snap, config, false)
end

-- 주사위 초기화
function RP.OnReset()
    ClearState()
end

-- ── 설정창/미리보기 ─────────────────────────────────────────────────
function RP.SetEnabled(on)
    local config = RP.GetSettings()
    if not config then return end
    config.enabled = on and true or false
    if not config.enabled then
        config.locked = true
        if handle then handle:End() end
        HideDisplay()
        return
    end
    -- 다시 켜면 지금 상태만 맞춘다. 꺼져 있던 동안 끝난 판의 완료 소리는 내지 않는다.
    announcedSet, rearmPending, rearmSawRoll = nil, true, false
    local snap = InGroup() and Snapshot() or nil
    if snap and snap.total >= 2 then Sync(snap, config, false) end
end

function RP.PreviewProgress()
    if not RP.GetSettings() then return end
    Show("preview", "progress", 12, 30)
end

function RP.PreviewDone()
    local config = RP.GetSettings()
    if not config then return end
    if Show("preview", "done", 30) then PlayDone(config) end
end

function RP.TestSound()
    local config = RP.GetSettings()
    if not playSound or not config then return end
    local copy = {}
    for key, value in pairs(config) do copy[key] = value end
    copy.enabled = true
    pcall(playSound, copy, "Dialog")
end

-- 위치 조정 시작/끝
function RP.SetEditing(on)
    local config = RP.GetSettings()
    if not config then return false end
    if on then
        local frame = EnsureDisplay()
        if not handle:Begin() then   -- 전투 중에는 조정을 시작하지 않는다
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[MimDice]|r " .. L("You can move it after combat."))
            end
            config.locked = true
            return false
        end
        config.locked = false
        if not (frame:IsShown() and frame.kind == "live") then
            Style("progress", 12, 30)
            frame.kind = "preview"
        else
            Style()
        end
        frame.elapsed = 0
        frame:SetAlpha(1)
        frame:Show()
    else
        config.locked = true
        if handle then handle:End() end
        if display and display.kind == "preview" then HideDisplay() end
    end
    return true
end

function RP.ClosePreview()
    RP.SetEditing(false)
end

function RP.ResetPosition()
    local config = RP.GetSettings()
    if not config then return end
    config.x, config.y = DEFAULT_X, DEFAULT_Y   -- 위치만 되돌린다
    RP.ApplySettings()
end

-- 설정값이 바뀌었을 때 화면에 반영
function RP.ApplySettings()
    local config = RP.GetSettings()
    if not config or not display then return end
    if display:IsShown() or not config.locked then
        Style()
    end
end

-- 전투 시작 처리 (테스트용 진입점). 실제로는 MoveHandle이 PLAYER_REGEN_DISABLED에서 부른다.
function RP.OnCombatStart()
    MimDiceMoveHandle.EndAllForCombat()
end

function RP.Init(soundPlayer, rosterProvider)
    playSound = soundPlayer or playSound
    provider = rosterProvider or provider
    local config = RP.GetSettings()
    if config then config.locked = true end   -- 접속할 때는 항상 조정 상태를 끈다
end

function RP.SetProvider(rosterProvider)
    if testMode then RP.testSavedProvider = rosterProvider; return end
    provider = rosterProvider
end

-- ── 혼자 시험하기 (/밈주사위 테스트) ───────────────────────────────
-- 가짜 파티원이 차례로 굴린 것처럼 흘려보내 실제 오버레이와 완료음을 확인한다.
-- 진짜 주사위 기록/순위/목록에는 아무것도 남기지 않고, 끝나면 원래 상태로 돌린다.
local testToken = 0
local function Say(text)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MimDice]|r " .. text) end
end

local function EndTest(token)
    if token ~= testToken or not testMode then return end
    testMode = false
    provider = RP.testSavedProvider
    announcedSet, rearmPending, rearmSawRoll = RP.testSaved[1], RP.testSaved[2], RP.testSaved[3]
    RP.testSavedProvider, RP.testSaved = nil, nil
    Say(L("Roll progress test finished."))
end

function RP.RunTest(count)
    local config = RP.GetSettings()
    if not config then return end
    if testMode then Say(L("A roll progress test is already running.")); return end
    count = math.max(2, math.min(40, tonumber(count) or 5))

    testToken = testToken + 1
    local token = testToken
    testMode = true
    RP.testSavedProvider = provider
    RP.testSaved = { announcedSet, rearmPending, rearmSawRoll }
    announcedSet, rearmPending, rearmSawRoll = nil, false, false

    local members, rolls = {}, {}
    for i = 1, count do members[i] = { fullName = "MimDiceTest" .. i } end
    provider = function() return members, rolls, true end

    if not config.enabled then Say(L("Roll progress alert is off. Showing the test anyway.")) end
    Say(string.format(L("Roll progress test: %d members roll in turn."), count))

    -- 앞쪽은 빠르게(표시 시간이 이어지는지), 중간에 한 번 같은 사람 재굴림, 마지막은 조금 쉬고 굴림
    local delay = 0
    for i = 1, count do
        delay = delay + ((i == count) and 1.5 or 0.6)
        local name = members[i].fullName
        C_Timer.After(delay, function()
            if token ~= testToken or not testMode then return end
            rolls[name] = (rolls[name] or 0) + 1
            RP.OnRoll(name, rolls[name] == 1)
            if i == 2 then   -- 재굴림은 숫자/표시 시간을 바꾸지 않는다
                rolls[members[1].fullName] = rolls[members[1].fullName] + 1
                RP.OnRoll(members[1].fullName, false)
            end
        end)
    end
    C_Timer.After(delay + config.duration + 1, function() EndTest(token) end)
end
