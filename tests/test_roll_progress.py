"""주사위 진행 오버레이(RollProgress.lua) 동작 검사 (Lua 5.1).

python tests/test_roll_progress.py
실제 화면 배치, 마우스 드래그, 음원 재생은 게임에서 따로 확인해야 한다.
"""
from pathlib import Path

helper = Path(__file__).with_name('test_sound_regressions.py')
namespace = {'__file__': str(helper)}
exec(compile(helper.read_text(encoding='utf-8').split('\ncurrent =')[0], str(helper), 'exec'), namespace)
source = (helper.parent.parent / 'SoundAlert.lua').read_text(encoding='utf-8-sig')

PRELUDE = r'''
-- 오버레이 프레임: 보이기/숨기기, 글자, 투명도, OnUpdate만 흉내 낸다.
local fm = {}
function fm:Show() self.shown = true end
function fm:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
function fm:IsShown() return self.shown == true end
function fm:SetShown(v) if v then self:Show() else self:Hide() end end
function fm:SetText(t) self.text_ = t end
function fm:GetText() return self.text_ end
function fm:SetAlpha(a) self.alpha = a end
function fm:SetScript(k, f) self.scripts[k] = f end
function fm:GetScript(k) return self.scripts[k] end
function fm:EnableMouse(v) self.mouse = v; mouseCalls = (mouseCalls or 0) + 1; if inCombat then blockedCalls = (blockedCalls or 0) + 1 end end
function fm:SetEditBorder(v) self.border = v end
function fm:StartMoving() startMoves = (startMoves or 0) + 1; self.movingNow = true end
function fm:StopMovingOrSizing() self.movingNow = false end
function fm:GetCenter() return 960, 900 end
function fm:GetTop() return 920 end
function fm:GetStringWidth() return #(self.text_ or "") * 8 end
function fm:SetPoint(...) self.point = {...} end
function fm:SetFont(_, size) self.fontSize = size end
function fm:SetSize(w, h) self.w, self.h = w, h end
function fm:CreateFontString() return NewFrame() end
function fm:CreateTexture() return NewFrame() end
function NewFrame()
    return setmetatable({ scripts = {} }, { __index = function(_, k) if fm[k] then return fm[k] end; if type(k) == "string" and k:match("^%u") then return function() end end end })
end
allFrames = {}
CreateFrame = function() local f = NewFrame(); allFrames[#allFrames + 1] = f; return f end
MimDiceFontPath = function() return "font.ttf" end
RP = MimDiceRollProgress
'''

SCENARIO = r'''
local PREFIX = MimDiceSoundFiles.BUNDLED_PREFIX
local DEFAULT = PREFIX .. "3띠릭(높은소리).mp3"
assert(PREFIX == "Interface\\AddOns\\MimDice\\sounds\\", "bundled prefix is not escaped: " .. PREFIX)

-- 가짜 그룹. members는 fullName 목록, missing은 이름을 못 읽은 사람 수
local group = { members = {}, missing = 0 }
local rolls = {}
local function setMembers(n, prefix)
    group.members = {}
    for i = 1, n do group.members[i] = { fullName = (prefix or "P") .. i } end
end
RP.SetProvider(function()
    return group.members, rolls, group.missing == 0
end)
state.grouped, state.raid, state.size = true, true, 40
state.fileExists = { [DEFAULT] = true }   -- 정확한 경로만 재생 성공
RP.Init(audit.play)

local function frame() return _G.__rp end
local function overlay()
    -- 오버레이는 처음 표시할 때 만들어진다. RP 내부 프레임을 텍스트로 확인한다.
    return RP.__display
end
local shownTexts = {}
local origShow = nil

local function roll(name)
    rolls[name] = (rolls[name] or 0) + 1
    RP.OnRoll(name, rolls[name] == 1)
end
local function doneSounds()
    local n = 0
    for _, p in ipairs(state.plays) do
        if p.kind == "file" and p.value == DEFAULT then n = n + 1 end
    end
    return n
end
local function reset()
    for k in pairs(rolls) do rolls[k] = nil end
    RP.OnReset()
end

local config = RP.GetSettings()
assert(config.enabled and config.soundEnabled and config.duration == 3 and config.fontSize == 22)
assert(config.soundType == "preset" and config.soundKey == DEFAULT)

-- 30명: 재굴림은 집계 제외, 완료 한 번, 정확한 경로 재생
setMembers(30); RP.OnRosterChanged()
for i = 1, 29 do roll("P" .. i) end
roll("P3")
local snap = RP.Snapshot()
assert(snap.rolled == 29 and snap.total == 30)
assert(doneSounds() == 0)
roll("P30")
assert(doneSounds() == 1, "done sound must play once with the exact bundled path")
roll("P30"); roll("P1")
assert(doneSounds() == 1, "re-rolls after completion must not alert again")

-- 같은 구성원으로 이벤트 반복: 다시 울리지 않음
RP.OnRosterChanged(); RP.OnRosterChanged()
assert(doneSounds() == 1)

-- 초기화 후 다시 한 번
reset()
for i = 1, 30 do roll("P" .. i) end
assert(doneSounds() == 2)

-- 완료 후 새 구성원 합류 -> 바로 굴림 -> 다시 완료
group.members[31] = { fullName = "NEW" }
RP.OnRosterChanged()
roll("NEW")
assert(doneSounds() == 3, "new member rolling right after joining must complete again")

-- 인원수가 같은 구성원 교체
group.members[31] = { fullName = "SWAP" }
RP.OnRosterChanged()
roll("SWAP")
assert(doneSounds() == 4, "same-size member swap must be detected")

-- 외부 사람의 굴림은 무시
reset(); setMembers(40); RP.OnRosterChanged()
for i = 1, 39 do roll("P" .. i) end
roll("STRANGER")
assert(RP.Snapshot().rolled == 39 and doneSounds() == 4)

-- 안 굴린 사람이 나가면 완료 한 번
table.remove(group.members, 40)
RP.OnRosterChanged()
assert(doneSounds() == 5, "leaving of the last non-roller completes once")

-- 구성원 정보가 부족하면 완료를 미룬다
reset(); setMembers(5); group.missing = 1; RP.OnRosterChanged()
for i = 1, 5 do roll("P" .. i) end
assert(doneSounds() == 5, "must not complete while a member name is unreadable")
group.missing = 0; RP.OnRosterChanged()
assert(doneSounds() == 6, "deferred completion fires once the roster is readable")

-- 기능 끄기/켜기: 다시 켜도 지난 완료음은 안 남
RP.SetEnabled(false)
assert(MimDiceDB.rollProgress.enabled == false)
RP.SetEnabled(true)
assert(doneSounds() == 6)

-- 소리 끄기: 문구만, 소리 없음
config.soundEnabled = false
reset(); for i = 1, 5 do roll("P" .. i) end
assert(doneSounds() == 6)
config.soundEnabled = true

-- 미리보기는 집계와 저장값을 바꾸지 않는다
reset(); roll("P1")
local before = RP.Snapshot().rolled
RP.PreviewProgress(); RP.PreviewDone()
RP.SetEditing(true); RP.SetEditing(false)
assert(RP.Snapshot().rolled == before and MimDiceDB.rollProgress.enabled == true)
assert(MimDiceDB.rollProgress.locked == true)

-- [늦게 읽히는 새 구성원] A·B 완료 -> C 합류(이름 못 읽음) -> C 이름 확인과 동시에 굴림
reset(); group.members = { { fullName = "A" }, { fullName = "B" } }; group.missing = 0
RP.OnRosterChanged(); roll("A"); roll("B")
local base = doneSounds()
assert(base == 7, "A,B complete: " .. base)
group.missing = 1; RP.OnRosterChanged()          -- C가 들어왔지만 목록엔 A,B만
assert(doneSounds() == base)
group.missing = 0; group.members[3] = { fullName = "C" }
roll("C")                                          -- 구성원 이벤트보다 굴림이 먼저 옴
assert(doneSounds() == base + 1, "late-readable new member must still complete once")
RP.OnRosterChanged(); RP.OnRosterChanged()
assert(doneSounds() == base + 1)
-- 굴린 사람이 나가도 다시 울리지 않음
table.remove(group.members, 1); RP.OnRosterChanged()
assert(doneSounds() == base + 1)

-- [다시 켜기 + 불완전 정보] 꺼진 동안 A·B·C 모두 굴림 -> C 못 읽는 상태에서 켬 -> C 복구
reset(); group.members = { { fullName = "A" }, { fullName = "B" } }; group.missing = 0
RP.OnRosterChanged()
RP.SetEnabled(false)
group.members[3] = { fullName = "C" }
for _, n in ipairs({ "A", "B", "C" }) do rolls[n] = 1 end
local saved = group.members[3]
group.members[3] = nil; group.missing = 1
local before2 = doneSounds()
RP.SetEnabled(true)
group.members[3] = saved; group.missing = 0
RP.OnRosterChanged()
assert(doneSounds() == before2, "re-enabling must not play a finished round's sound after roster recovers")
-- 그 뒤 새 사람이 들어와 굴리면 정상 알림
group.members[4] = { fullName = "D" }; RP.OnRosterChanged(); roll("D")
assert(doneSounds() == before2 + 1)

-- [이름이 1명만 읽힘] A·B 완료 -> 잠깐 A만 조회 -> 복구: 중복 완료음 없음
reset(); RP.SetEnabled(true)
group.members = { { fullName = "A" }, { fullName = "B" } }; group.missing = 0
RP.OnRosterChanged(); roll("A"); roll("B")
local n1 = doneSounds()
group.members = { { fullName = "A" } }; group.missing = 1; RP.OnRosterChanged()
group.members = { { fullName = "A" }, { fullName = "B" } }; group.missing = 0; RP.OnRosterChanged()
assert(doneSounds() == n1, "a temporary 1-name roster must not reset completion history")

-- [다시 켜기 + 목록 1명으로 감소 + 복구]: 지난 완료음 없음
RP.SetEnabled(false)
group.members = { { fullName = "A" } }; group.missing = 1
RP.SetEnabled(true)
RP.OnRosterChanged()
group.members = { { fullName = "A" }, { fullName = "B" } }; group.missing = 0; RP.OnRosterChanged()
assert(doneSounds() == n1, "re-enable waiting state must survive a shrunken roster")

-- [다시 켜기 대기 중 진짜 완료] A·C 굴림, B 남음 -> C 못 읽는 상태에서 켬 -> B 굴림 -> C 복구
reset()
group.members = { { fullName = "A" }, { fullName = "B" }, { fullName = "C" } }; group.missing = 0
RP.OnRosterChanged()
RP.SetEnabled(false)
rolls.A, rolls.C = 1, 1
group.members = { { fullName = "A" }, { fullName = "B" } }; group.missing = 1
RP.SetEnabled(true)
local n2 = doneSounds()
roll("B")
assert(doneSounds() == n2)
group.members[3] = { fullName = "C" }; group.missing = 0; RP.OnRosterChanged()
assert(doneSounds() == n2 + 1, "a real completion during re-enable waiting must alert after recovery")

-- [한 명만 읽힘 + 대기 중 마지막 굴림] A·C 굴림 -> B만 읽히는 상태에서 켬 -> B 굴림 -> A·C 복구
reset()
group.members = { { fullName = "A" }, { fullName = "B" }, { fullName = "C" } }; group.missing = 0
state.size = 3; RP.OnRosterChanged()
RP.SetEnabled(false)
rolls.A, rolls.C = 1, 1
group.members = { { fullName = "B" } }; group.missing = 2
RP.SetEnabled(true)
local n3 = doneSounds()
roll("B")
assert(doneSounds() == n3)
group.members = { { fullName = "A" }, { fullName = "B" }, { fullName = "C" } }; group.missing = 0
RP.OnRosterChanged()
assert(doneSounds() == n3 + 1, "last roll seen while only one name was readable must complete after recovery")
state.size = 40
n2 = doneSounds() - 1

-- 진짜 그룹 탈퇴는 이력을 지운다
state.grouped = false; RP.OnRosterChanged(); state.grouped = true
RP.OnRosterChanged()
assert(doneSounds() == n2 + 1)
roll("A")   -- 재굴림: 숫자/알림 없음
assert(doneSounds() == n2 + 1)

-- 1명 이하/그룹 탈퇴: 정리만, 알림 없음
setMembers(1); RP.OnRosterChanged()
roll("P1")
assert(doneSounds() >= 6)
'''

DISPLAY = r'''
-- 표시 시간: 빠른 연속 굴림은 마지막 굴림부터 다시 센다, 페이드 중 새 굴림은 바로 밝게
local PREFIX = MimDiceSoundFiles.BUNDLED_PREFIX
local group, rolls = {}, {}
for i = 1, 30 do group[i] = { fullName = "P" .. i } end
RP.SetProvider(function() return group, rolls, true end)
state.grouped = true
RP.Init(audit.play)
local display
local realCreate = CreateFrame
allFrames = {}
CreateFrame = function(...) local f = realCreate(...); if not display then display = f end; allFrames[#allFrames + 1] = f; return f end
local function roll(name) rolls[name] = (rolls[name] or 0) + 1; RP.OnRoll(name, rolls[name] == 1) end
local function tick(sec) display.scripts.OnUpdate(display, sec) end

roll("P1")
assert(display and display:IsShown())
tick(2.0); roll("P2"); tick(2.0)
assert(display:IsShown(), "a new roll must restart the 3 second timer")
tick(0.8)   -- 2.8초: 페이드 중
assert(display.alpha < 1)
roll("P3")
assert(display.alpha == 1, "a new roll during fade must restore full opacity")
tick(3.1)
assert(not display:IsShown(), "overlay hides after the duration")

-- 초기화, 기능 끄기는 즉시 숨김
roll("P4"); assert(display:IsShown())
RP.OnReset(); assert(not display:IsShown())
roll("P5"); assert(display:IsShown())
RP.SetEnabled(false); assert(not display:IsShown())
RP.SetEnabled(true)

-- 위치 조정 중에는 사라지지 않는다. 마우스는 별도 손잡이만 받고, 알림 창은 끝까지 클릭 통과
RP.SetEditing(true)
local h = RP._handle
assert(display:IsShown() and h.frame:IsShown() and h.frame.mouse == true)
assert(rawget(display, "mouse") == nil, "the alert frame itself must never take the mouse")
tick(30); assert(display:IsShown())
RP.SetEditing(false)
assert(not h.frame:IsShown() and rawget(display, "mouse") == nil)

-- 사용자 문구/색/배경: 비우면 기본 문구, 적으면 숫자를 붙여 표시
local cfg = RP.GetSettings()
assert(cfg.progressText == "" and cfg.doneText == "" and cfg.bgAlpha == 0)
assert(cfg.progressColor.r == 1 and cfg.doneColor.g == 1 and cfg.bgColor.r == 0)
assert(cfg.progressColor ~= cfg.doneColor)   -- 기본값 표를 함께 쓰지 않음
RP.OnReset()
roll("P6")
assert(display.text:GetText() == "Rolls 6 / 30", tostring(display.text:GetText()))
cfg.progressText, cfg.doneText = "굴려굴려", "다 굴렸다!"
RP.ApplySettings()
assert(display.text:GetText() == "굴려굴려 6 / 30", "ApplySettings must redraw with the new text")
RP.PreviewDone()   -- 실제 알림이 보이는 중이면 미리보기로 덮지 않는다
assert(display.text:GetText() == "굴려굴려 6 / 30")
RP.OnReset(); RP.PreviewDone()
assert(display.text:GetText() == "다 굴렸다! (30 players)", tostring(display.text:GetText()))
cfg.progressText, cfg.doneText = "", ""
-- 잘못 저장된 색/투명도는 기본값으로 복구
MimDiceDB.rollProgress.bgColor, MimDiceDB.rollProgress.bgAlpha = "red", 5
cfg = RP.GetSettings()
assert(cfg.bgColor.r == 0 and cfg.bgAlpha == 1)

-- 게임 방해 방지: 일반 표시는 마우스 설정 함수를 부르지 않는다
RP.OnReset(); RP.SetEditing(false)
local before = mouseCalls or 0
for i = 7, 20 do roll("P" .. i) end
RP.PreviewProgress(); RP.PreviewDone(); RP.ApplySettings()
assert((mouseCalls or 0) == before, "showing the overlay must not touch mouse settings")
assert(rawget(display, "mouse") == nil)

-- 전투 중: 조정 시작 거부, 굴림 표시에도 보호 함수 없음
inCombat = true
InCombatLockdown = function() return true end
assert(RP.SetEditing(true) == false and not h.frame:IsShown() and RP.GetSettings().locked)
for i = 21, 25 do roll("P" .. i) end
assert((blockedCalls or 0) == 0, "EnableMouse must never be called in combat")
inCombat = false
InCombatLockdown = function() return false end

-- 위치 조정 중 전투 잠금이 '이미 걸린 뒤'에 전투 이벤트가 와도 마우스를 잡은 상태가 남지 않는다
RP.SetEditing(true)
assert(h.frame:IsShown())
inCombat = true
InCombatLockdown = function() return true end
RP.OnCombatStart()
assert(not h.frame:IsShown() and RP.GetSettings().locked == true, "combat must close the handle even under lockdown")
roll("P26")   -- 이후 실제 진행 알림: 클릭 통과 유지
assert(display:IsShown() and rawget(display, "mouse") == nil and not h.frame:IsShown())
assert((blockedCalls or 0) == 0)

-- 드래그 도중 전투 진입: 이동이 멈추고 위치가 저장된다. 전투 중 새 이동은 시작하지 않는다
inCombat = false
InCombatLockdown = function() return false end
RP.SetEditing(true)
h.frame.scripts.OnDragStart(h.frame)
assert(rawget(display, "movingNow") == true)
inCombat = true
InCombatLockdown = function() return true end
RP.OnCombatStart()
assert(rawget(display, "movingNow") == false and not h.frame:IsShown())
local moves = startMoves
h.frame.scripts.OnDragStart(h.frame)
assert(startMoves == moves, "no StartMoving in combat")

-- 알림 창이 숨겨지는 모든 경로에서 손잡이도 끝난다 (초기화 / 기능 끄기)
inCombat = false
InCombatLockdown = function() return false end
RP.OnReset(); roll("P27")             -- 실제 진행 표시 중
RP.SetEditing(true)
assert(h.editing and h.frame:IsShown())
RP.OnReset()                           -- 주사위 초기화 -> 표시 창 숨김
assert(not h.editing and not h.frame:IsShown() and RP.GetSettings().locked, "reset must end the handle")
roll("P28"); RP.SetEditing(true)
RP.SetEnabled(false)                   -- 기능 끄기
assert(not h.editing and not h.frame:IsShown())
RP.SetEnabled(true)

-- 전투가 끝나면 다시 조정할 수 있다
inCombat = false
InCombatLockdown = function() return false end
assert(RP.SetEditing(true) == true and h.frame:IsShown())
RP.SetEditing(false)

-- 위치 초기화는 위치만 되돌린다
local c = RP.GetSettings()
c.x, c.y, c.fontSize, c.soundEnabled = 50, -300, 40, false
RP.ResetPosition()
assert(c.x == 0 and c.y == -170 and c.fontSize == 40 and c.soundEnabled == false)
'''

MIGRATION = r'''
-- 처음 형식(enabled/sound/soundFile)에서 이전: false 보존, 직접 적은 파일명 보존
MimDiceDB.rollProgress = { enabled = false, sound = false, soundFile = "my-done.ogg" }
local c = MimDiceRollProgress.GetSettings()
assert(c.enabled == false and c.soundEnabled == false)
assert(c.soundType == "custom" and c.soundFile == "my-done.ogg")
assert(c.sound == nil and c.migratedV2)
-- 다시 불러도 바뀌지 않음, 타입을 바꿔도 다른 값은 남음
c.soundType = "id"; c.soundID = 12345
c = MimDiceRollProgress.GetSettings()
assert(c.soundType == "id" and c.soundFile == "my-done.ogg" and c.soundID == 12345)

-- 예전 기본 전체 경로는 내장 선택으로 이전
local full = MimDiceSoundFiles.BUNDLED_PREFIX .. "3띠릭(높은소리).mp3"
MimDiceDB.rollProgress = { enabled = true, sound = true, soundFile = full }
c = MimDiceRollProgress.GetSettings()
assert(c.soundType == "preset" and c.soundKey == full and c.soundEnabled == true)

-- 커스텀 파일명 재생 경로: 사용자 sound 폴더 파일
state.plays = {}
state.fileExists = { ["sound\\my-done.ogg"] = true }
MimDiceDB.rollProgress = { enabled = true, soundEnabled = true, soundType = "custom", soundFile = "my-done.ogg", migratedV2 = true }
MimDiceRollProgress.Init(audit.play)
MimDiceRollProgress.TestSound()
local ok = false
for _, p in ipairs(state.plays) do if p.value == "sound\\my-done.ogg" then ok = true end end
assert(ok, "custom filename must resolve through the shared sound folders")

-- SoundKit 선택 재생 경로
state.plays = {}
MimDiceDB.rollProgress.soundType, MimDiceDB.rollProgress.soundKey, MimDiceDB.rollProgress.soundIsKit = "preset", 700001, true
MimDiceRollProgress.TestSound()
assert(state.plays[1].kind == "kit" and state.plays[1].value == 700001)
'''

SELFTEST = r'''
-- /밈주사위 테스트: 혼자서 가짜 파티로 진행/완료를 보고, 끝나면 원래 상태로 돌아온다
local queue = {}
C_Timer.After = function(_, f) queue[#queue + 1] = f end
local function runAll() while #queue > 0 do local f = table.remove(queue, 1); f() end end
local realRolls = { Me = 1 }
local realMembers = { { fullName = "Me" }, { fullName = "Friend" } }
local realProvider = function() return realMembers, realRolls, true end
RP.SetProvider(realProvider)
state.grouped, state.size = false, 1   -- 혼자
state.fileExists = { [MimDiceSoundFiles.BUNDLED_PREFIX .. "3띠릭(높은소리).mp3"] = true }
state.plays = {}
RP.Init(audit.play)
RP.RunTest("5")
RP.RunTest("5")   -- 진행 중 다시 입력해도 겹치지 않음
runAll()
local done = 0
for _, p in ipairs(state.plays) do if p.kind == "file" then done = done + 1 end end
assert(done == 1, "self test must play the done sound exactly once: " .. done)
assert(realRolls.Me == 1 and realRolls.Friend == nil, "real roll records must not change")
-- 끝나면 진짜 상태로: 혼자이므로 실제 굴림은 무시된다
RP.OnRoll("Me", true)
local snap = RP.Snapshot()
assert(snap.total == 2 and snap.set.Me, "real provider must be restored")
'''

FIRSTCOMBAT = r'''
-- 로그인 뒤 한 번도 표시하지 않다가 전투 중 첫 굴림: 보호 함수 호출이 없어야 한다
inCombat = true
InCombatLockdown = function() return true end
local group, rolls = {}, {}
for i = 1, 5 do group[i] = { fullName = "P" .. i } end
RP.SetProvider(function() return group, rolls, true end)
state.grouped = true
RP.Init(audit.play)
local before = mouseCalls or 0
for i = 1, 5 do rolls["P" .. i] = 1; RP.OnRoll("P" .. i, true) end
assert((blockedCalls or 0) == 0 and (mouseCalls or 0) == before, "first display in combat must not call EnableMouse")
assert(RP.SetEditing(true) == false)   -- 전투 중 손잡이도 만들지 않는다
assert(RP._handle and RP._handle.frame == nil)
'''

BLOODLUST = (helper.parent.parent / 'BloodlustReminder.lua').read_text(encoding='utf-8-sig') + r'''
-- 블러드 사용 가능 알림: 알림 창은 마우스를 받지 않고, 전투 시작 시 조정 손잡이가 닫힌다
local R = MimDiceBloodlustReminder
R.Init(function() return false, true end, audit.play)
local cfg = R.GetSettings()
local display
for _, f in ipairs(allFrames) do if f.handle then display = f end end
assert(display and display.handle, "reminder display must use the move handle")
local h = display.handle
cfg.locked = false; R.ApplySettings()
assert(h.frame:IsShown() and h.frame.mouse == true and rawget(display, "mouse") == nil)
inCombat = true
InCombatLockdown = function() return true end
MimDiceMoveHandle.EndAllForCombat()   -- 잠금이 이미 걸린 뒤의 전투 이벤트
assert(not h.frame:IsShown() and cfg.locked == true)
R.Test()                               -- 전투 중 표시
assert((blockedCalls or 0) == 0 and rawget(display, "mouse") == nil)
cfg.locked = false; R.ApplySettings() -- 전투 중 조정 시작 시도
assert(cfg.locked == true and not h.frame:IsShown())
-- 알림이 숨겨지면 손잡이도 끝난다
inCombat = false
InCombatLockdown = function() return false end
cfg.locked = false; R.ApplySettings()
assert(h.editing and h.frame:IsShown())
display:Hide()
assert(not h.editing and not h.frame:IsShown() and cfg.locked == true, "hiding the alert must end the handle")
'''

passed = 0
for name, body in (("rules", SCENARIO), ("display", DISPLAY), ("migration", MIGRATION), ("selftest", SELFTEST), ("firstcombat", FIRSTCOMBAT), ("bloodlust", BLOODLUST)):
    vm = namespace['make_vm'](source)
    vm.execute(PRELUDE)
    vm.execute("state.plays = state.plays or {}")
    vm.execute(body)
    passed += 1
print(f"Roll progress: {passed} / 6 scenario groups passed")
