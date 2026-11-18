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
SOUNDKIT = {
    UI_RAID_BOSS_WHISPER_WARNING = 700001, LFG_ROLE_CHECK = 700002,
    IG_MAINMENU_OPEN = 700003, UI_BNET_TOAST = 567458,
    RAID_WARNING = 8959, READY_CHECK = 8960, TELL_MESSAGE = 3081,
    IG_PLAYER_INVITE = 880, MAP_PING = 3175, IG_QUEST_LIST_COMPLETE = 878,
}
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
state.timers = {}
C_Timer = { After = function(d, f) table.insert(state.timers, { at = state.now + d, f = f }) end, NewTicker = function() return { Cancel = function() end } end }
C_Secrets = {
    ShouldAurasBeSecret = function() return state.restricted end,
    GetSpellAuraSecrecy = function() return state.secrecy or 0 end,
}
function runTimers()
    local list = state.timers; state.timers = {}
    for _, t in ipairs(list) do if t.at <= state.now then t.f() else table.insert(state.timers, t) end end
end
state.meter = {}
Enum.DamageMeterSessionType = { Current = 1 }
Enum.DamageMeterType = { Interrupts = 7 }
C_DamageMeter = {
    IsDamageMeterAvailable = function() return true end,
    GetCombatSessionFromType = function()
        if state.sessionUnknown then return nil end
        return { combatSources = state.sessionRows or {} }
    end,
    GetCombatSessionSourceFromType = function(st, mt, guid)
        if state.meterError then error("meter") end
        if state.meterSecret then return SECRET end
        local v = state.meter[guid]
        if v == nil then return nil end
        if v == "secret" then return { totalAmount = SECRET } end
        if type(v) == "table" then return { totalAmount = SECRET, combatSpells = v } end
        return { totalAmount = v, combatSpells = {} }
    end,
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
    event = SA_EventFrame:GetScript("OnEvent"), presetSounds = SA.GetPresetSounds,
    setPreset = SA.SetPresetSound, lockForCombat = SA.LockAllEditingForCombat,
}
MimDiceBloodlustReminder = { Refresh = function()
    state.readyCalls = state.readyCalls + 1
    if state.readyError then error("ready reminder failure") end
end }
'''


def make_vm(source):
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.execute(MOCK)
    for name in ("BuffBarDefaults.lua", "SoundFiles.lua", "SoundList.lua", "MoveHandle.lua", "PowerInfusion.lua", "RollProgress.lua", "RollProgressConfig.lua"):
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
case("interrupt: pet success, secret result alone is silent", '''
audit.interruptAttempt('pet', 19647)
audit.interruptResult('nameplate1', 'pet-guid'); assert(#state.plays == 1)
audit.interruptAttempt('player', 2139)
audit.interruptResult(SECRET, SECRET); assert(#state.plays == 1)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: secret result + public meter increase plays once", '''
state.meter['player-guid'] = 2
audit.interruptAttempt('player', 2139)
audit.interruptResult(SECRET, SECRET); assert(#state.plays == 0)
state.meter['player-guid'] = 3
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1); assert(#state.plays == 1)
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1); assert(#state.plays == 1)
audit.interruptResult('focus', SECRET); assert(#state.plays == 1)
''')
case("interrupt: first ever kick (no row -> row) counts via meter", '''
audit.interruptAttempt('player', 2139)
audit.interruptResult(SECRET, SECRET)
state.meter['player-guid'] = 1
state.now = state.now + 0.5; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: someone else kicked first (my meter unchanged) is silent", '''
state.meter['player-guid'] = 2; state.meter['other-guid'] = 1
audit.interruptAttempt('player', 2139)
audit.interruptResult(SECRET, SECRET)
state.meter['other-guid'] = 2
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 1; runTimers(); assert(#state.plays == 0)
''')
case("interrupt: secret meter, error, missing baseline are silent", '''
state.meter['player-guid'] = 'secret'
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.meter['player-guid'] = 5; audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
assert(#state.plays == 0)
state.meterError = true
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.now = state.now + 1; runTimers(); assert(#state.plays == 0)
state.meterError = false; state.meterSecret = true
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.now = state.now + 1; runTimers(); assert(#state.plays == 0)
''')
case("interrupt: meter increase without interrupt result is silent", '''
state.meter['player-guid'] = 0
audit.interruptAttempt('player', 2139)
state.meter['player-guid'] = 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1); assert(#state.plays == 0)
''')
case("interrupt: late meter after evidence window and reset are silent", '''
state.meter['player-guid'] = 0
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.now = state.now + 1.1; state.meter['player-guid'] = 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1); assert(#state.plays == 0)
state.meter['player-guid'] = 1
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
audit.event(nil, 'LOADING_SCREEN_ENABLED')
state.meter['player-guid'] = 2; state.now = state.now + 0.5; runTimers()
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1); assert(#state.plays == 0)
''')
case("interrupt: public self result before cast event", '''
audit.interruptResult('target', 'player-guid'); assert(#state.plays == 0)
state.now = state.now + 0.05
audit.interruptAttempt('player', 2139); assert(#state.plays == 1)
audit.interruptResult('focus', 'player-guid'); assert(#state.plays == 1)
''')
case("interrupt: channel natural end (nil interrupter) is silent", '''
audit.interruptAttempt('player', 2139)
audit.interruptResult('target', nil); audit.interruptResult('target', ''); assert(#state.plays == 0)
audit.interruptResult('target', 'player-guid'); assert(#state.plays == 1)
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
case("interrupt: combat - secret amount, first kick (row appears)", '''
audit.event(nil, 'PLAYER_ENTERING_WORLD')
audit.interruptAttempt('player', 2139)
audit.interruptResult(SECRET, SECRET); assert(#state.plays == 0)
state.meter['player-guid'] = { 101 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1); assert(#state.plays == 1)
''')
case("interrupt: combat - secret amount, new spell list grows / same spell silent", '''
state.meter['player-guid'] = { 101 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.meter['player-guid'] = { 101, 202 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1); assert(#state.plays == 1)
state.now = state.now + 2
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.meter['player-guid'] = { 101, 202 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: meter already increased before cast event (baseline kept from earlier)", '''
state.meter['player-guid'] = 2
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.meter['player-guid'] = 3
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1); assert(#state.plays == 0)
audit.interruptAttempt('player', 2139); assert(#state.plays == 0)
audit.interruptResult(SECRET, SECRET); assert(#state.plays == 1)
''')
case("interrupt: secret result before cast event, then meter", '''
state.meter['player-guid'] = 2
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptResult(SECRET, SECRET)
audit.interruptAttempt('player', 2139); assert(#state.plays == 0)
state.meter['player-guid'] = 3
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1); assert(#state.plays == 1)
''')
case("interrupt: duplicate notice after success is not reused by next kick", '''
state.class = 'PALADIN'; state.spec = 2
audit.interruptAttempt('player', 375576)
audit.interruptResult('target', 'player-guid'); assert(#state.plays == 1)
state.now = state.now + 0.36
audit.interruptResult('focus', 'player-guid')
state.now = state.now + 0.05
audit.interruptAttempt('player', 96231); assert(#state.plays == 1)
''')
case("interrupt: unknown first read then old total appears is silent", '''
state.sessionUnknown = true
audit.event(nil, 'PLAYER_ENTERING_WORLD')
audit.interruptAttempt('player', 2139)
audit.interruptResult(SECRET, SECRET)
state.sessionUnknown = false; state.meter['player-guid'] = 5
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 1; runTimers(); assert(#state.plays == 0)
''')
case("interrupt: meter reset discards pending attempt and secret result", '''
state.meter['player-guid'] = 4
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
audit.event(nil, 'DAMAGE_METER_RESET')
state.meter['player-guid'] = 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 1; runTimers(); assert(#state.plays == 0)
''')
case("interrupt: next pull first kick (session id 1 -> 2) plays", '''
state.meter['player-guid'] = { 101, 202 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 30
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.meter['player-guid'] = { 303 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 2); assert(#state.plays == 1)
''')
case("interrupt: next pull - session start, then kick result, then meter", '''
state.meter['player-guid'] = { 101, 202 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 30
audit.interruptAttempt('player', 2139)
state.meter['player-guid'] = nil
audit.event(nil, 'DAMAGE_METER_CURRENT_SESSION_UPDATED')
audit.interruptResult(SECRET, SECRET)
state.meter['player-guid'] = { 303 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 2); assert(#state.plays == 1)
''')
case("interrupt: kick result before session start is previous-combat evidence (silent)", '''
state.meter['player-guid'] = { 101, 202 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 30
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.now = state.now + 0.1
audit.event(nil, 'DAMAGE_METER_CURRENT_SESSION_UPDATED')
state.meter['player-guid'] = { 303 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 2)
state.now = state.now + 1; runTimers(); assert(#state.plays == 0)
''')
case("interrupt: opener kick in the same frame as session start plays", '''
state.meter['player-guid'] = { 101, 202 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 30
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
audit.event(nil, 'DAMAGE_METER_CURRENT_SESSION_UPDATED')
state.meter['player-guid'] = { 303 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 2); assert(#state.plays == 1)
''')
case("interrupt: mid-combat session event with spell list growth still counts", '''
state.meter['player-guid'] = { 101 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.event(nil, 'DAMAGE_METER_CURRENT_SESSION_UPDATED')
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.meter['player-guid'] = { 101, 202 }
audit.event(nil, 'DAMAGE_METER_CURRENT_SESSION_UPDATED'); assert(#state.plays == 1)
''')
case("interrupt: normal kick +2 meter leftover is not reused", '''
state.meter['player-guid'] = 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.meter['player-guid'] = 3
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1); assert(#state.plays == 1)
state.now = state.now + 0.4
audit.interruptAttempt('player', 96231); audit.interruptResult('target', SECRET)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: previous-combat public self result dropped at session start", '''
state.now = state.now + 5
audit.interruptResult('target', 'player-guid', 'old')
audit.event(nil, 'DAMAGE_METER_CURRENT_SESSION_UPDATED')
state.now = state.now + 0.05
audit.interruptAttempt('player', 2139); assert(#state.plays == 0)
''')
case("interrupt: known limit - kick within 1.35s after Divine Toll counted as the toll", '''
state.class = 'PALADIN'; state.spec = 2
state.meter['player-guid'] = 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('player', 375576); audit.interruptResult('target', SECRET)
state.meter['player-guid'] = { 1, 2 }
state.meter['player-guid'] = 2
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1); assert(#state.plays == 1)
state.now = state.now + 0.8
audit.interruptAttempt('player', 96231); audit.interruptResult('target', SECRET)
state.meter['player-guid'] = 3
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1); assert(#state.plays == 1)
state.now = state.now + 2
audit.interruptAttempt('player', 96231); audit.interruptResult('target', SECRET)
state.meter['player-guid'] = 4
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1); assert(#state.plays == 2)
''')
case("interrupt: next pull - other player's kick only is silent", '''
state.meter['player-guid'] = { 101, 202 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 30
audit.event(nil, 'DAMAGE_METER_CURRENT_SESSION_UPDATED')
state.meter['player-guid'] = nil
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 2)
state.now = state.now + 1; runTimers(); assert(#state.plays == 0)
''')
case("interrupt: target + nameplate duplicate secret notices, then meter", '''
state.meter['player-guid'] = 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('player', 2139)
audit.interruptResult('target', SECRET); audit.interruptResult('nameplate1', SECRET)
state.meter['player-guid'] = 2
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1); assert(#state.plays == 1)
state.now = state.now + 0.05
state.meter['player-guid'] = 2
audit.interruptAttempt('player', 2139); audit.interruptResult('target', SECRET)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: late meter of a public success is not reused by next failed kick", '''
state.class = 'PALADIN'; state.spec = 2
state.meter['player-guid'] = 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('player', 375576)
audit.interruptResult('target', 'player-guid'); assert(#state.plays == 1)
state.meter['player-guid'] = 2
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 0.4
audit.interruptAttempt('player', 96231); audit.interruptResult('target', SECRET)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: duplicate notice arriving after next kick (same cast id) is ignored", '''
audit.interruptAttempt('player', 2139)
audit.interruptResult('target', 'player-guid', 'cast-A'); assert(#state.plays == 1)
state.now = state.now + 0.05
audit.interruptAttempt('player', 2139)
audit.interruptResult('focus', 'player-guid', 'cast-A'); assert(#state.plays == 1)
audit.interruptResult('target', 'player-guid', 'cast-B'); assert(#state.plays == 2)
''')
case("interrupt: Divine Toll extra targets after next kick are the same use", '''
state.class = 'PALADIN'; state.spec = 2
audit.interruptAttempt('player', 375576)
audit.interruptResult('target', 'player-guid', 'c1'); assert(#state.plays == 1)
state.now = state.now + 0.05
audit.interruptAttempt('player', 96231)
audit.interruptResult('nameplate2', 'player-guid', 'c2'); assert(#state.plays == 1)
''')
case("interrupt: my row exists in session but source lookup nil stays unknown", '''
state.sessionRows = { { isLocalPlayer = true } }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.meter['player-guid'] = { 101, 202 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 1; runTimers(); assert(#state.plays == 0)
''')
case("interrupt: pet replaced - new pet record not credited to old attempt", '''
state.meter['pet-guid'] = 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('pet', 19647); audit.interruptResult(SECRET, SECRET)
state.petGuid = 'pet-guid-2'; state.meter['pet-guid-2'] = { 1 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 1; runTimers(); assert(#state.plays == 0)
''')
case("interrupt: row with zero count / empty list is not a success", '''
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.meter['player-guid'] = 0
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 1; runTimers(); assert(#state.plays == 0)
state.meter['player-guid'] = nil
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.meter['player-guid'] = {}
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 1; runTimers(); assert(#state.plays == 0)
''')
case("interrupt: Divine Toll +2 meter is one use, not reused by next failed kick", '''
state.class = 'PALADIN'; state.spec = 2
state.meter['player-guid'] = 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('player', 375576)
audit.interruptResult('target', SECRET); audit.interruptResult('nameplate2', SECRET)
state.meter['player-guid'] = 3
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1); assert(#state.plays == 1)
state.now = state.now + 0.4
audit.interruptAttempt('player', 96231); audit.interruptResult('target', SECRET)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: reverse-order success registers cast id", '''
audit.interruptResult('target', 'player-guid', 'c1')
audit.interruptAttempt('player', 31935); assert(#state.plays == 1)
state.now = state.now + 0.7
audit.interruptAttempt('player', 96231)
audit.interruptResult('focus', 'player-guid', 'c1'); assert(#state.plays == 1)
''')
case("interrupt: meter-path success registers cast id", '''
state.meter['player-guid'] = 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('player', 2139); audit.interruptResult('target', SECRET, 'c9')
state.meter['player-guid'] = 2
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1); assert(#state.plays == 1)
state.now = state.now + 0.7
audit.interruptAttempt('player', 2139)
audit.interruptResult('focus', 'player-guid', 'c9'); assert(#state.plays == 1)
''')
case("interrupt: session start then session id change is one switch (no reuse)", '''
state.meter['player-guid'] = { 101, 202 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 30
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.meter['player-guid'] = { 303 }
audit.event(nil, 'DAMAGE_METER_CURRENT_SESSION_UPDATED'); assert(#state.plays == 1)
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 2); assert(#state.plays == 1)
state.now = state.now + 0.05
audit.interruptAttempt('player', 96231); audit.interruptResult('target', SECRET)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: public first success, then session id change, next failed kick silent", '''
state.meter['player-guid'] = { 101, 202 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 30
audit.event(nil, 'DAMAGE_METER_CURRENT_SESSION_UPDATED')
audit.interruptAttempt('player', 2139); audit.interruptResult('target', 'player-guid', 'p1')
assert(#state.plays == 1)
state.meter['player-guid'] = { 303 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 2)
state.now = state.now + 0.05
audit.interruptAttempt('player', 96231); audit.interruptResult('target', SECRET)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: later real session change after stale switch flag still rebases", '''
state.meter['player-guid'] = { 101, 202 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.event(nil, 'DAMAGE_METER_CURRENT_SESSION_UPDATED')
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 30
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.meter['player-guid'] = { 303 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 2); assert(#state.plays == 1)
''')
case("interrupt: session start, old id update in between, then new id (no reuse)", '''
state.meter['player-guid'] = { 101, 202 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 30
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.meter['player-guid'] = { 303 }
audit.event(nil, 'DAMAGE_METER_CURRENT_SESSION_UPDATED'); assert(#state.plays == 1)
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 2); assert(#state.plays == 1)
state.now = state.now + 0.05
audit.interruptAttempt('player', 96231); audit.interruptResult('target', SECRET)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: stale switch wait expires before next combat", '''
state.meter['player-guid'] = { 101, 202 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.event(nil, 'DAMAGE_METER_CURRENT_SESSION_UPDATED')
state.now = state.now + 30
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.meter['player-guid'] = { 303 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 2); assert(#state.plays == 1)
''')
case("interrupt: same switch with session id 4.99s late does not reuse", '''
state.meter['player-guid'] = { 101, 202 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 30
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.meter['player-guid'] = { 303 }
audit.event(nil, 'DAMAGE_METER_CURRENT_SESSION_UPDATED'); assert(#state.plays == 1)
state.now = state.now + 4.99
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 2); assert(#state.plays == 1)
state.now = state.now + 0.05
audit.interruptAttempt('player', 96231); audit.interruptResult('target', SECRET)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: same switch with session id 5.01s late does not reuse", '''
state.meter['player-guid'] = { 101, 202 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 30
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.meter['player-guid'] = { 303 }
audit.event(nil, 'DAMAGE_METER_CURRENT_SESSION_UPDATED'); assert(#state.plays == 1)
state.now = state.now + 5.01
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 2); assert(#state.plays == 1)
state.now = state.now + 0.05
audit.interruptAttempt('player', 96231); audit.interruptResult('target', SECRET)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: same switch with session id 6s late does not reuse", '''
state.meter['player-guid'] = { 101, 202 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 30
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.meter['player-guid'] = { 303 }
audit.event(nil, 'DAMAGE_METER_CURRENT_SESSION_UPDATED'); assert(#state.plays == 1)
state.now = state.now + 6
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 2); assert(#state.plays == 1)
state.now = state.now + 0.05
audit.interruptAttempt('player', 96231); audit.interruptResult('target', SECRET)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: same switch with session id 60s late does not reuse", '''
state.meter['player-guid'] = { 101, 202 }
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 30
audit.interruptAttempt('player', 2139); audit.interruptResult(SECRET, SECRET)
state.meter['player-guid'] = { 303 }
audit.event(nil, 'DAMAGE_METER_CURRENT_SESSION_UPDATED'); assert(#state.plays == 1)
state.now = state.now + 60
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 2); assert(#state.plays == 1)
state.now = state.now + 0.05
audit.interruptAttempt('player', 96231); audit.interruptResult('target', SECRET)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: public success meter 0.99s late is not reused by next failed kick", '''
state.meter['player-guid'] = 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('player', 31935)
audit.interruptResult('target', 'player-guid', 'a1'); assert(#state.plays == 1)
state.now = state.now + 0.99
audit.interruptAttempt('player', 96231)
state.meter['player-guid'] = 2
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptResult('target', SECRET)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: public success meter 1.01s late is not reused by next failed kick", '''
state.meter['player-guid'] = 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('player', 31935)
audit.interruptResult('target', 'player-guid', 'a1'); assert(#state.plays == 1)
state.now = state.now + 1.01
audit.interruptAttempt('player', 96231)
state.meter['player-guid'] = 2
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptResult('target', SECRET)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: public success meter 4.99s late is not reused by next failed kick", '''
state.meter['player-guid'] = 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('player', 31935)
audit.interruptResult('target', 'player-guid', 'a1'); assert(#state.plays == 1)
state.now = state.now + 4.99
audit.interruptAttempt('player', 96231)
state.meter['player-guid'] = 2
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptResult('target', SECRET)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: public success meter 6s late is not reused by next failed kick", '''
state.meter['player-guid'] = 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('player', 31935)
audit.interruptResult('target', 'player-guid', 'a1'); assert(#state.plays == 1)
state.now = state.now + 6
audit.interruptAttempt('player', 96231)
state.meter['player-guid'] = 2
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptResult('target', SECRET)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: after late meter is paid, a real next success still plays", '''
state.meter['player-guid'] = 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('player', 31935)
audit.interruptResult('target', 'player-guid', 'a1'); assert(#state.plays == 1)
state.now = state.now + 3
state.meter['player-guid'] = 2
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1); assert(#state.plays == 1)
state.now = state.now + 1
audit.interruptAttempt('player', 96231); audit.interruptResult('target', SECRET)
state.meter['player-guid'] = 3
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1); assert(#state.plays == 2)
''')
case("interrupt: Divine Toll public success, late +1 meter after failed kick 2s later", '''
state.class = 'PALADIN'; state.spec = 2
state.meter['player-guid'] = 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('player', 375576)
audit.interruptResult('target', 'player-guid', 't1'); assert(#state.plays == 1)
state.now = state.now + 2
audit.interruptAttempt('player', 96231); audit.interruptResult('target', SECRET)
state.meter['player-guid'] = 1 + 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: Divine Toll public success, late +2 meter after failed kick 2s later", '''
state.class = 'PALADIN'; state.spec = 2
state.meter['player-guid'] = 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('player', 375576)
audit.interruptResult('target', 'player-guid', 't1'); assert(#state.plays == 1)
state.now = state.now + 2
audit.interruptAttempt('player', 96231); audit.interruptResult('target', SECRET)
state.meter['player-guid'] = 1 + 2
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: Divine Toll public success, late +3 meter after failed kick 2s later", '''
state.class = 'PALADIN'; state.spec = 2
state.meter['player-guid'] = 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('player', 375576)
audit.interruptResult('target', 'player-guid', 't1'); assert(#state.plays == 1)
state.now = state.now + 2
audit.interruptAttempt('player', 96231); audit.interruptResult('target', SECRET)
state.meter['player-guid'] = 1 + 3
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: Divine Toll late records split over two updates", '''
state.class = 'PALADIN'; state.spec = 2
state.meter['player-guid'] = 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
audit.interruptAttempt('player', 375576)
audit.interruptResult('target', 'player-guid', 't1'); assert(#state.plays == 1)
state.now = state.now + 2
audit.interruptAttempt('player', 96231); audit.interruptResult('target', SECRET)
state.meter['player-guid'] = 2
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.meter['player-guid'] = 3
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 1; runTimers(); assert(#state.plays == 1)
''')
case("interrupt: protection paladin Divine Toll", '''
state.class = 'PALADIN'; state.spec = 2
audit.interruptAttempt('player', 375576); state.now = state.now + 0.3
audit.interruptResult('target', SECRET); assert(#state.plays == 0)
audit.interruptResult('target', nil); audit.interruptResult('target', 'other-guid'); assert(#state.plays == 0)
state.now = state.now + 1; runTimers(); assert(#state.plays == 0)
audit.interruptAttempt('player', 375576)
audit.interruptResult('target', 'player-guid'); assert(#state.plays == 1)
audit.interruptResult('focus', 'player-guid'); audit.interruptResult('nameplate2', 'player-guid')
assert(#state.plays == 1)
state.meter['player-guid'] = 1
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.meter['player-guid'] = 4
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1)
state.now = state.now + 60
audit.interruptAttempt('player', 375576)
audit.interruptResult('target', SECRET); audit.interruptResult('nameplate3', SECRET)
state.meter['player-guid'] = 6
audit.event(nil, 'DAMAGE_METER_COMBAT_SESSION_UPDATED', 7, 1); assert(#state.plays == 2)
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
case("chat sound: built-in selection is not reverted by legacy migration", '''
local entry = { channelTarget = '4', soundType = 'preset', soundKey = nil, soundFile = 'old-alert.ogg' }
MimDiceDB.chatSound.customChannels = { entry }
MimDiceDB.soundTypeMigrationV1 = nil
SA_InitDB()
assert(entry.soundType == 'custom')
entry.soundType = 'preset'
SA_InitDB()
assert(entry.soundType == 'preset' and entry.soundFile == 'old-alert.ogg')
entry.soundKey = 635496
SA_InitDB()
assert(entry.soundType == 'preset' and entry.soundKey == 635496)
''')
case("soundkit catalog: only curated, existing, non-duplicate effects are listed", '''
local found, testSound = {}, nil
for _, sound in ipairs(audit.presetSounds()) do
    found[sound.id] = (found[sound.id] or 0) + 1
    if sound.id == 700002 then testSound = sound end
end
assert(found[700001] == nil)   -- 소리가 안 나는 보스 귓속말 경고는 뺐다
assert(found[700002] == 1)
assert(found[700003] == nil)   -- 목록에 없는 UI 소리는 빠진다
assert(found[567458] == 1)     -- 기존 내장음과 같은 번호는 중복 추가하지 않는다
assert(testSound.isSoundKit and testSound.name == '역할 확인')
local picked = { enabled = true }
audit.setPreset(picked, testSound)
assert(picked.soundType == 'preset' and picked.soundIsKit and picked.soundKey == 700002)
audit.play(picked)
assert(#state.plays == 1 and state.plays[1].kind == 'kit' and state.plays[1].value == 700002)
''')
case("soundkit catalog: legacy file equivalents stay unique without changing saved sounds", '''
local found, names = {}, {}
for _, sound in ipairs(audit.presetSounds()) do
    found[sound.id] = true
    names[sound.name] = (names[sound.name] or 0) + 1
end
for _, id in ipairs({8959, 8960, 3081, 880, 3175, 878}) do
    assert(not found[id])
end
for _, id in ipairs({567397, 558137, 567421, 567451, 567416, 567439}) do
    assert(found[id])
end
assert(names['퀘스트 완료'] == 1)
local saved = {enabled = true, soundType = 'preset', soundKey = 878,
    soundName = '퀘스트 완료', soundIsKit = true}
MimDiceDB.chatSound.channels.WHISPER = saved
SA_InitDB()
audit.play(saved)
assert(saved.soundKey == 878 and saved.soundIsKit and saved.soundType == 'preset')
assert(#state.plays == 1 and state.plays[1].kind == 'kit' and state.plays[1].value == 878)
''')
case("bundled sfx: listed, kept by migration, and played as a file", '''
local prefix = MimDiceSoundFiles.BUNDLED_PREFIX
local sfx
for _, sound in ipairs(audit.presetSounds()) do
    if sound.id == prefix .. '7뾰옹.mp3' then sfx = sound end
end
assert(sfx and sfx.isBundled and sfx.name == '뾰옹')
local entry = { enabled = true, channelTarget = '4' }
audit.setPreset(entry, sfx)
MimDiceDB.chatSound.customChannels = { entry }
SA_InitDB()
assert(entry.soundType == 'preset' and entry.soundKey == prefix .. '7뾰옹.mp3')
audit.play(entry)
assert(#state.plays == 1 and state.plays[1].kind == 'file' and state.plays[1].value == prefix .. '7뾰옹.mp3')
''')
case("bundled sfx: typed custom filename of a bundled file keeps working", '''
local entry = { enabled = true, channelTarget = '4', soundType = 'custom', soundFile = '짤.mp3' }
MimDiceDB.chatSound.customChannels = { entry }
SA_InitDB()
assert(entry.soundType == 'custom' and entry.soundFile == '짤.mp3' and entry.soundKey == nil)
audit.play(entry)
assert(#state.plays >= 1 and state.plays[1].kind == 'file')
assert(state.plays[1].value:find('짤.mp3', 1, true))
''')
case("legacy formats: numeric strings recover, valid values and custom names stay", '''
local cs = MimDiceDB.chatSound
cs.channels.BN_WHISPER = { enabled = true, soundType = 'preset', soundKey = '18019', soundName = '배틀넷 알림', soundFile = '돌진.mp3', isSystem = true }
cs.channels.WHISPER = { enabled = true, soundType = 'preset', soundKey = 567402, soundName = '친구 접속', soundFile = '' , isSystem = true }
cs.channels.GUILD = { enabled = true, soundType = 'id', soundKey = 12345, soundFile = '', isSystem = true }          -- 옛 ID 형식
cs.channels.PARTY = { enabled = true, soundType = 'id', soundID = '54321', soundFile = '', isSystem = true }          -- 숫자 문자열 ID
cs.channels.RAID = { enabled = true, soundType = 'custom', soundFile = 'battle01[53225].mp3', soundKey = 567397, isSystem = true }
cs.channels.SAY = { enabled = true, soundType = 'preset', soundKey = 'broken.mp3', soundName = '예전 이름', isSystem = true }
for _ = 1, 3 do SA_InitDB() end   -- 여러 번 불러도 결과가 같아야 한다
local c = cs.channels
assert(c.BN_WHISPER.soundKey == 18019 and c.BN_WHISPER.soundFile == '돌진.mp3' and c.BN_WHISPER.soundType == 'preset')
assert(c.WHISPER.soundKey == 567402)
assert(c.GUILD.soundType == 'id' and c.GUILD.soundID == 12345)
assert(c.PARTY.soundID == 54321)
assert(c.RAID.soundType == 'custom' and c.RAID.soundFile == 'battle01[53225].mp3' and c.RAID.soundKey == 567397)
assert(c.SAY.soundKey == nil)   -- 복구할 수 없는 값만 정리
for _, k in ipairs({ 'BN_WHISPER', 'WHISPER', 'GUILD', 'PARTY', 'RAID' }) do
    state.plays = {}
    audit.play(c[k], 'Dialog')
    assert(#state.plays >= 1, k .. ' must still play')
end
assert(state.plays[1].kind == 'file')
''')
case("combat start: every unlocked position editor is locked", '''
MimDiceDB.deathTrack.locked = false
MimDiceDB.partyAlert.locked = false
MimDiceDB.battleRes.iconLocked = false
MimDiceDB.buffTrack.BLOODLUST.locked = false
audit.lockForCombat()
assert(MimDiceDB.deathTrack.locked and MimDiceDB.partyAlert.locked)
assert(MimDiceDB.battleRes.iconLocked and MimDiceDB.buffTrack.BLOODLUST.locked)
audit.lockForCombat()   -- 이미 잠겨 있으면 아무것도 안 함
''')
case("power infusion: SoundKit selection reports native AuraSound limitation", '''
local settings = MimDicePowerInfusion.GetSettings()
settings.enabled = true
settings.soundType = 'preset'
settings.soundKey = 700001
settings.soundIsKit = true
MimDicePowerInfusion.Init(audit.play)
local _, status = MimDicePowerInfusion.GetStatusText()
assert(status == 'unsupported')
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
