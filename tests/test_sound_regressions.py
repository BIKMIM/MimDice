"""Run actual addon code with mocked WoW APIs using lupa.lua51.

python tests/test_sound_regressions.py [--lua-python PATH]
The mock verifies dispatch and settings; it cannot verify audible WoW playback.
"""

import argparse
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--lua-python", type=Path)
args = parser.parse_args()
if args.lua_python:
    sys.path.insert(0, str(args.lua_python))
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''
state = { now = 100, size = 4, homeSize = 4, raid = false,
    grouped = true, homeGrouped = true, leader = false, assistant = false,
    homeLeader = false, homeAssistant = false, empowered = false,
    class = "MAGE", guid = "player-guid", petGuid = "pet-guid",
    dialog = "1", restricted = false, auras = {}, plays = {}, flashes = 0,
    bars = 0, notices = 0, readyCalls = 0 }
SECRET = {}
function issecretvalue(v) return v == SECRET end
function hasanysecretvalues(v) return false end
function MimDice_L(s) return s end
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
Enum = { SecrecyLevel = { NeverSecret = 0 } }
SlashCmdList, UISpecialFrames, StaticPopupDialogs = {}, {}, {}
function wipe(t) for k in pairs(t) do t[k] = nil end end
function GetTime() return state.now end
function GetCVar() return state.dialog end
function InCombatLockdown() return false end
function UnitClass() return "Mage", state.class end
function UnitGUID(unit) return unit == "pet" and state.petGuid or state.guid end
function IsInRaid(category) return state.raid end
function IsInGroup(category)
    if category == LE_PARTY_CATEGORY_HOME then return state.homeGrouped end
    if category == LE_PARTY_CATEGORY_INSTANCE then return state.instanceGrouped or false end
    return state.grouped
end
function GetNumGroupMembers(category)
    if category == LE_PARTY_CATEGORY_HOME then return state.homeSize end
    return state.size
end
function UnitIsGroupLeader(unit, category)
    return category == LE_PARTY_CATEGORY_HOME and state.homeLeader or
        (category == nil and state.leader or false)
end
function UnitIsGroupAssistant(unit, category)
    return category == LE_PARTY_CATEGORY_HOME and state.homeAssistant or
        (category == nil and state.assistant or false)
end
function LFGListUtil_IsEntryEmpowered() return state.empowered end
function GetSpecialization() return state.spec or 1 end
function IsSwimming() return false end
function IsFlying() return false end
function IsFalling() return false end
function FlashClientIcon() state.flashes = state.flashes + 1 end
function PlaySound(id, channel)
    table.insert(state.plays, { kind = "kit", value = id, channel = channel })
    return true, #state.plays
end
function PlaySoundFile(file, channel)
    table.insert(state.plays, { kind = "file", value = file, channel = channel })
    if type(file) == "string" and state.fileExists then
        return state.fileExists[file] == true, #state.plays
    end
    return true, #state.plays
end
function StaticPopup_Visible() return false end
function StaticPopup_Show() state.notices = state.notices + 1; return true end
function StaticPopup_Hide() end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
C_Secrets = {
    ShouldAurasBeSecret = function() return state.restricted end,
    GetSpellAuraSecrecy = function() return state.secrecy or 0 end,
}
C_UnitAuras = { GetPlayerAuraBySpellID = function(id) return state.auras[id] end }
local methods = {}
function methods:SetScript(key, callback) self.scripts[key] = callback end
function methods:GetScript(key) return self.scripts[key] end
function methods:GetWidth() return 1920 end
function methods:GetHeight() return 1080 end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:RegisterUnitEvent(event) self.events[event] = true end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:CreateFontString() return CreateFrame() end
function methods:CreateTexture() return CreateFrame() end
function CreateFrame()
    return setmetatable({ scripts = {}, events = {} }, { __index = function(_, key)
        return methods[key] or function() end
    end })
end
UIParent = CreateFrame()
hooks = {}
function hooksecurefunc(name, callback) hooks[name] = callback end
'''
EXPORT = r'''
SA_StartBuffBar = function() state.bars = state.bars + 1 end
audit = {
    play = SA_PlaySound, syncParty = SA_SyncGroupSize, fullParty = SA_CheckFullParty,
    permission = SA_PartyCanReceiveAlerts, interruptAttempt = SA_RecordInterruptAttempt,
    interruptResult = SA_HandleInterruptResult, auraSync = SA_SyncBloodlustAuraPresence,
    event = SA_EventFrame:GetScript("OnEvent"),
}
MimDiceBloodlustReminder = { Refresh = function()
    state.readyCalls = state.readyCalls + 1
    if state.readyError then error("ready reminder failure") end
end }
'''


def make_vm(source):
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.execute(MOCK)
    for name in ("BuffBarDefaults.lua", "SoundFiles.lua", "PowerInfusion.lua"):
        vm.execute((ROOT / name).read_text(encoding="utf-8-sig"))
    vm.execute(source + "\n" + EXPORT)
    vm.execute("SA_InitDB()")
    return vm


cases = []


def case(name, code):
    cases.append((name, code))


case("full party: ordinary member", '''
audit.syncParty(); state.size = 5; audit.fullParty()
assert(#state.plays == 1 and state.flashes == 1)
audit.fullParty(); assert(#state.plays == 1)
''')
case("full party: applicant master OFF", '''
MimDiceDB.partyAlert.enabled = false
audit.syncParty(); state.size = 5; audit.fullParty()
assert(#state.plays == 1 and state.flashes == 1)
''')
case("full party: instance group without HOME group", '''
state.homeSize = 0; state.homeGrouped = false; state.instanceGrouped = true
audit.syncParty(); state.size = 5; audit.fullParty()
assert(#state.plays == 1)
''')
case("full party: disabled, raid and already-full suppression", '''
MimDiceDB.partyAlert.fullParty.enabled = false
audit.syncParty(); state.size = 5; audit.fullParty(); assert(#state.plays == 0)
MimDiceDB.partyAlert.fullParty.enabled = true
state.size = 4; audit.fullParty(); state.raid = true
state.size = 5; audit.fullParty(); assert(#state.plays == 0)
state.raid = false; audit.syncParty(); audit.fullParty(); assert(#state.plays == 0)
state.size = 4; audit.fullParty(); state.size = 5; audit.fullParty()
assert(#state.plays == 1)
''')
case("party permission: previous leader and member behavior", '''
assert(not audit.permission())
state.leader = true; assert(audit.permission())
state.leader = false; state.assistant = true; assert(audit.permission())
state.assistant = false; MimDiceDB.partyAlert.alertAnyRole = true
assert(audit.permission())
MimDiceDB.partyAlert.alertAnyRole = false; state.grouped = false
assert(audit.permission())
''')
case("raid permission: HOME rights and exact master toggle", '''
state.raid = true; state.leader = true; assert(not audit.permission())
state.empowered = true; assert(audit.permission())
MimDiceDB.partyAlert.enabled = false; assert(not audit.permission())
MimDiceDB.partyAlert.enabled = true; state.empowered = false
MimDiceDB.partyAlert.alertAnyRole = true; assert(audit.permission())
state.homeGrouped = false; assert(not audit.permission())
''')
case("raid permission: unloaded group-finder UI fallback", '''
state.raid = true; LFGListUtil_IsEntryEmpowered = nil
assert(not audit.permission())
state.homeLeader = true; assert(audit.permission())
state.homeLeader = false; state.homeAssistant = true; assert(audit.permission())
''')
for sound_type, fields, kind, value in (
    ("preset", "soundKey = 567397", "file", "567397"),
    ("preset", "soundKey = 12345", "kit", "12345"),
    ("id", "soundID = '635496'", "file", "635496"),
    ("id", "soundID = '12345'", "kit", "12345"),
    ("custom", "soundFile = 'jump.ogg'", "file", "'sound\\\\jump.ogg'"),
):
    for dialog in ("0", "1"):
        case(f"sound dispatch: {sound_type} {fields}, Dialog={dialog}", f'''
state.dialog = '{dialog}'
MimDiceDB.partyAlert.enabled = false
audit.play({{ enabled = true, soundType = '{sound_type}', {fields} }})
assert(#state.plays == 1)
assert(state.plays[1].kind == '{kind}' and state.plays[1].value == {value})
assert(state.plays[1].channel == 'Dialog' and state.notices == 0)
''')
case("sound dispatch: per-alert OFF and invalid/empty selection", '''
audit.play({ enabled = false, soundType = 'preset', soundKey = 635496 })
audit.play({ enabled = true, soundType = 'custom', soundFile = '' })
audit.play({ enabled = true, soundType = 'id', soundID = 'invalid' })
assert(#state.plays == 0)
''')
case("custom files: external lookup then bundled fallback", r'''
state.fileExists = { ['Interface\\AddOns\\MimDice\\sounds\\jump.ogg'] = true }
audit.play({ enabled = true, soundType = 'custom', soundFile = 'jump.ogg' })
assert(#state.plays == 3)
assert(state.plays[3].value == 'Interface\\AddOns\\MimDice\\sounds\\jump.ogg')
''')
case("skill event: class, player and enabled selection", '''
MimDiceDB.partyAlert.enabled = false
MimDiceDB.soundAlerts = {
    { spellID = 123, class = 'MAGE', enabled = true, soundType = 'id', soundID = 635496 },
    { spellID = 456, class = 'MAGE', enabled = false, soundType = 'id', soundID = 635496 },
}
audit.event(nil, 'UNIT_SPELLCAST_SUCCEEDED', 'player', nil, 123)
assert(#state.plays == 1)
audit.event(nil, 'UNIT_SPELLCAST_SUCCEEDED', 'party1', nil, 123)
audit.event(nil, 'UNIT_SPELLCAST_SUCCEEDED', 'player', nil, 456)
state.class = 'WARRIOR'
audit.event(nil, 'UNIT_SPELLCAST_SUCCEEDED', 'player', nil, 123)
assert(#state.plays == 1)
''')
case("skill event: secret arguments do not error or play", '''
audit.event(nil, 'UNIT_SPELLCAST_SUCCEEDED', SECRET, nil, 123)
audit.event(nil, 'UNIT_SPELLCAST_SUCCEEDED', 'player', nil, SECRET)
assert(#state.plays == 0)
''')
case("jump: existing player setting", '''
hooks.JumpOrAscendStart(); assert(#state.plays == 1)
MimDiceDB.soundAlerts[1].enabled = false
hooks.JumpOrAscendStart(); assert(#state.plays == 1)
''')
case("interrupt: real player success and duplicate suppression", '''
audit.interruptAttempt('player', 2139)
audit.interruptResult('target', 'player-guid'); assert(#state.plays == 1)
audit.interruptResult('focus', 'player-guid'); assert(#state.plays == 1)
''')
case("interrupt: pet success and secret result", '''
audit.interruptAttempt('pet', 19647)
audit.interruptResult('nameplate1', 'pet-guid'); assert(#state.plays == 1)
audit.interruptAttempt('player', 2139)
audit.interruptResult(SECRET, SECRET); assert(#state.plays == 2)
''')
case("interrupt: other player, timeout, mere cast, disabled", '''
audit.interruptAttempt('player', 2139); assert(#state.plays == 0)
audit.interruptResult('target', 'other-guid'); assert(#state.plays == 0)
state.now = state.now + 0.26
audit.interruptResult('target', 'player-guid'); assert(#state.plays == 0)
MimDiceDB.interruptAlert.enabled = false
audit.interruptAttempt('player', 2139)
audit.interruptResult('target', 'player-guid'); assert(#state.plays == 0)
''')
case("interrupt: protection paladin Divine Toll", '''
state.class = 'PALADIN'; state.spec = 2
audit.interruptAttempt('player', 375576); state.now = state.now + 0.3
audit.interruptResult('target', SECRET); assert(#state.plays == 1)
audit.interruptResult('focus', SECRET); assert(#state.plays == 1)
''')
for restricted in (False, True):
    for spell_id in (57723, 57724, 80354, 95809, 160455, 264689, 390435):
        case(f"bloodlust: applied aura {spell_id}, restricted={restricted}", f'''
state.restricted = {str(restricted).lower()}
audit.auraSync(true)
state.auras[{spell_id}] = {{ expirationTime = state.now + 600 }}
audit.event(nil, 'UNIT_AURA', SECRET, SECRET)
assert(#state.plays == 1 and state.bars == 1)
audit.event(nil, 'UNIT_AURA', SECRET, SECRET)
assert(#state.plays == 1 and state.bars == 1)
''')
case("bloodlust: new reminder failure cannot suppress application", '''
audit.auraSync(true); state.readyError = true
state.auras[57723] = { expirationTime = state.now + 600 }
audit.event(nil, 'UNIT_AURA', SECRET, SECRET)
assert(#state.plays == 1 and state.bars == 1)
''')
case("bloodlust: existing lockout, no aura and old aura", '''
state.auras[57723] = { expirationTime = state.now + 600 }
audit.auraSync(true); audit.auraSync(false); assert(#state.plays == 0)
state.auras = {}; audit.auraSync(false); assert(#state.plays == 0)
state.auras[57723] = { expirationTime = state.now + 500 }
audit.auraSync(false); assert(#state.plays == 0)
''')
case("bloodlust: inaccessible aura does not fabricate an application", '''
audit.auraSync(true)
state.restricted = true; state.secrecy = 1
state.auras[57723] = { expirationTime = state.now + 600 }
audit.auraSync(false); assert(#state.plays == 0)
''')
case("bloodlust: disabled setting, unchanged channel and user file", '''
local bt = MimDiceDB.buffTrack.BLOODLUST
bt.enabled = false; audit.auraSync(true)
state.auras[57723] = { expirationTime = state.now + 600 }
audit.auraSync(false); assert(#state.plays == 0)
state.auras = {}; audit.auraSync(false); bt.enabled = true; bt.soundFile = 'my-lust.ogg'
state.now = state.now + 3
state.auras[57723] = { expirationTime = state.now + 600 }
audit.auraSync(false)
assert(#state.plays == 1 and state.plays[1].value == 'sound\\\\my-lust.ogg')
assert(state.plays[1].channel == 'Dialog')
''')
case("settings: preserve previous ON/OFF and custom/preset/ID selections", '''
MimDiceDB.interruptAlert = { enabled = false, soundType = 'custom', soundFile = '철수.mp3' }
MimDiceDB.buffTrack.BLOODLUST = { enabled = false, soundType = 'id', soundID = 635496 }
MimDiceDB.partyAlert.fullParty = { enabled = false, soundType = 'preset', soundKey = 635496 }
MimDiceDB.soundAlerts = { { spellID = 123, class = 'MAGE', enabled = true,
    soundType = 'custom', soundFile = 'my-skill.ogg' } }
SA_InitDB(); SA_InitDB()
assert(not MimDiceDB.interruptAlert.enabled and MimDiceDB.interruptAlert.soundFile == '철수.mp3')
assert(not MimDiceDB.buffTrack.BLOODLUST.enabled and MimDiceDB.buffTrack.BLOODLUST.soundID == 635496)
assert(not MimDiceDB.partyAlert.fullParty.enabled and MimDiceDB.partyAlert.fullParty.soundKey == 635496)
assert(MimDiceDB.soundAlerts[1].soundFile == 'my-skill.ogg' and MimDiceDB.soundAlerts[1].enabled)
''')


current = (ROOT / "SoundAlert.lua").read_text(encoding="utf-8-sig")
compile_vm = LuaRuntime()
compile_source = compile_vm.eval("function(s, name) local f, err = loadstring(s, name); assert(f, err) end")
lua_files = list(ROOT.glob("*.lua")) + list((ROOT / "Locales").glob("*.lua"))
for path in lua_files:
    compile_source(path.read_text(encoding="utf-8-sig"), str(path))
print(f"Lua 5.1 syntax: {len(lua_files)} files passed")

baseline = subprocess.check_output(
    ["git", "show", "HEAD:SoundAlert.lua"], cwd=ROOT
).decode("utf-8-sig")
baseline_failures = []
for name, code in cases:
    vm = make_vm(baseline)
    try:
        vm.execute(code)
    except Exception:
        baseline_failures.append(name)
print(f"Before fix: {len(baseline_failures)} / {len(cases)} scenarios failed")
for name in baseline_failures:
    print(f"  {name}")

for name, code in cases:
    vm = make_vm(current)
    try:
        vm.execute(code)
    except Exception as exc:
        raise AssertionError(f"{name}: {exc}") from exc
print(f"After fix: {len(cases)} / {len(cases)} scenarios passed")
