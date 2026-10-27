"""Exercise real trade-whisper code in Lua 5.1; no messages leave this mock."""
import argparse
from pathlib import Path
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--lua-python', type=Path)
args = parser.parse_args()
if args.lua_python:
    sys.path.insert(0, str(args.lua_python))
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''
now, sent, timers = 100, {}, {}
SECRET = {}
function issecretvalue(v) return rawequal(v, SECRET) end
function GetTime() return now end
function MimDice_L(s) return s end
function UnitFullName(unit) assert(unit == 'NPC'); return targetName, realm end
targetName, realm = 'Partner', 'OtherRealm'
playerMoney, targetMoney, playerItems, targetItems = 0, 1234500, {}, {}
function GetPlayerTradeMoney() return playerMoney end
function GetTargetTradeMoney() return targetMoney end
function GetTradePlayerItemInfo(slot)
    local it = playerItems[slot] or {}
    return it.name, nil, it.count, nil, it.enchant
end
function GetTradeTargetItemInfo(slot)
    local it = targetItems[slot] or {}
    return it.name, nil, it.count, nil, nil, it.enchant
end
ERR_TRADE_COMPLETE, ERR_TRADE_CANCELLED = 'complete-localized', 'cancel-localized'
function GetGameMessageInfo(id)
    return ({[1]='ERR_TRADE_COMPLETE', [2]='ERR_TRADE_CANCELLED', [3]='ERR_TRADE_BAG', [4]='ERR_ABILITY_COOLDOWN'})[id]
end
C_ChatInfo = {
    InChatMessagingLockdown = function() return locked end,
    SendChatMessage = function(msg, channel, language, target)
        assert(not locked and channel == 'WHISPER')
        sent[#sent+1] = { message=msg, target=target, time=now }
    end,
}
C_Timer = { After = function(delay, fn) timers[#timers+1] = {at=now+delay, fn=fn} end }
function advance(delta)
    local finish = now + delta
    while true do
        table.sort(timers, function(a,b) return a.at < b.at end)
        if not timers[1] or timers[1].at > finish then break end
        local timer = table.remove(timers, 1); now = timer.at; timer.fn()
    end
    now = finish
end
function CreateFrame()
    frame = { events={} }
    function frame:RegisterEvent(event) self.events[event]=true end
    function frame:UnregisterEvent(event) self.events[event]=nil end
    function frame:SetScript(_, fn) self.handler=fn end
    return frame
end
function fire(event, ...)
    if frame.events[event] then frame.handler(frame, event, ...) end
end
function enable()
    MimDiceDB.tradeWhisperEnabled=true; MimDiceTradeWhisper.ApplySettings()
end
function begin()
    fire('TRADE_SHOW'); fire('TRADE_ACCEPT_UPDATE', 1, 0)
end
function complete() fire('UI_INFO_MESSAGE', 1, ERR_TRADE_COMPLETE) end
'''

cases = []


def case(name, code):
    cases.append((name, code))


case('default OFF and no trade event subscriptions', '''
assert(MimDiceDB.tradeWhisperEnabled == false)
assert(next(frame.events) == nil)
begin(); complete(); assert(#sent==0)
''')
case('existing ON and unrelated settings survive initialization', '''
MimDiceDB.tradeWhisperEnabled=true; MimDiceDB.custom='keep'
MimDiceTradeWhisper.ApplySettings()
assert(frame.events.TRADE_SHOW and MimDiceDB.custom=='keep')
''')
case('server completion after close, one-sided accept, duplicate completion', '''
enable(); begin(); fire('TRADE_CLOSED'); fire('TRADE_CLOSED')
assert(#sent==0); complete(); complete(); advance(5)
assert(#sent==1 and sent[1].target=='Partner-OtherRealm')
assert(sent[1].message:find('123g 45s 0c', 1, true))
''')
case('server completion before close', '''
enable(); begin(); complete(); fire('TRADE_CLOSED'); complete(); assert(#sent==1)
''')
case('accept and close alone never mean success', '''
enable(); begin(); fire('TRADE_ACCEPT_UPDATE',1,1); fire('TRADE_CLOSED'); advance(20)
assert(#sent==0)
''')
case('withdrawn acceptance invalidates earlier contents', '''
enable(); begin(); fire('TRADE_ACCEPT_UPDATE',0,0); complete(); assert(#sent==0)
''')
case('failed snapshot cannot retain an earlier valid snapshot', '''
enable(); begin()
GetTradeTargetItemInfo=function() error('temporarily unavailable') end
fire('TRADE_ACCEPT_UPDATE',1,0); complete(); assert(#sent==0)
''')
case('cancel request clears completed candidate', '''
enable(); begin(); fire('TRADE_REQUEST_CANCEL'); complete(); assert(#sent==0)
''')
case('localized cancel signal clears candidate', '''
enable(); begin(); fire('UI_INFO_MESSAGE',nil,ERR_TRADE_CANCELLED); complete(); assert(#sent==0)
''')
case('trade failure clears candidate', '''
enable(); begin(); fire('UI_ERROR_MESSAGE',3); complete(); assert(#sent==0)
''')
case('unrelated UI error does not discard actual completed trade', '''
enable(); begin(); fire('UI_ERROR_MESSAGE',4); complete(); assert(#sent==1)
''')
case('old closed candidate expires', '''
enable(); begin(); fire('TRADE_CLOSED'); advance(6); complete(); assert(#sent==0)
''')
case('new trade cannot reuse the previous partner or snapshot', '''
enable(); begin(); fire('TRADE_CLOSED'); targetName='Next'; fire('TRADE_SHOW'); complete(); assert(#sent==0)
''')
case('changed money invalidates prior snapshot and recaptures new value', '''
enable(); begin(); targetMoney=2000000; fire('TRADE_MONEY_CHANGED')
complete(); assert(#sent==0)
begin(); complete(); assert(#sent==1 and sent[1].message:find('200g',1,true))
''')
case('long Korean item lists retain both sides, valid UTF8, and byte limit', '''
enable(); targetMoney=0
for i=1,6 do
    playerItems[i]={name=string.rep('보낸아이템',5)..i, count=i}
    targetItems[i]={name=string.rep('받은아이템',5)..i, count=i}
end
begin(); complete(); advance(20)
assert(#sent>1)
for i,msg in ipairs(sent) do
    assert(#msg.message<=250 and msg.target=='Partner-OtherRealm')
    if i>1 then assert(msg.time - sent[i-1].time >= 1) end
end
''')
case('oversized item name is shortened safely', '''
enable(); targetMoney=0; playerItems[1]={name=string.rep('가',200), count=1}
begin(); complete(); assert(#sent==1 and #sent[1].message<=250)
''')
case('large money beyond signed 32 bit', '''
enable(); targetMoney=3500000000; begin(); complete()
assert(sent[1].message:find('350000g',1,true))
''')
case('enchant service has correct direction, slot 7 item is not transferred', '''
enable(); targetMoney=0
playerItems[7]={name='My sword',enchant='ReceivedEnchant'}
targetItems[7]={name='Their sword',enchant='SentEnchant'}
begin(); complete()
assert(sent[1].message:find('Received: Enchant: ReceivedEnchant',1,true))
assert(sent[1].message:find('Sent: Enchant: SentEnchant',1,true))
assert(not sent[1].message:find('sword',1,true))
''')
case('empty trade sends nothing', '''
enable(); targetMoney=0; begin(); complete(); assert(#sent==0)
''')
case('missing target does not guess current target', '''
enable(); targetName=nil; begin(); complete(); assert(#sent==0)
''')
for field in ('targetName', 'realm', 'targetMoney'):
    case(f'secret {field} does not send', f'''
enable(); {field}=SECRET; begin(); complete(); assert(#sent==0)
''')
case('secret item count discards snapshot', '''
enable(); playerItems[1]={name='Item',count=SECRET}; begin(); complete(); assert(#sent==0)
''')
case('secret item name discards snapshot', '''
enable(); playerItems[1]={name=SECRET,count=1}; begin(); complete(); assert(#sent==0)
''')
case('secret event arguments do not throw or complete', '''
enable(); begin(); fire('UI_INFO_MESSAGE',SECRET,SECRET); assert(#sent==0)
''')
case('MimRaid enabled suppresses duplicate, disabled allows MimDice', '''
enable(); MimRaid={cfg={tradeWhisperEnabled=true},TradeAnnounce={}}
begin(); complete(); assert(#sent==0)
MimRaid.cfg.tradeWhisperEnabled=false; begin(); complete(); assert(#sent==1)
''')
case('OFF clears queued sends and all subscriptions', '''
enable(); locked=true; begin(); complete(); assert(#sent==0)
MimDiceDB.tradeWhisperEnabled=false; MimDiceTradeWhisper.ApplySettings()
assert(next(frame.events)==nil); locked=false; advance(5); assert(#sent==0)
''')
case('chat lockdown defers message until allowed', '''
enable(); locked=true; begin(); complete(); advance(3); assert(#sent==0)
locked=false; advance(1); assert(#sent==1)
''')
case('queued messages expire rather than leaking into a later encounter', '''
enable(); locked=true; begin(); complete(); advance(121)
locked=false; advance(1); assert(#sent==0 and #timers==0)
''')
case('consecutive trades preserve recipients in deferred messages', '''
enable(); locked=true; begin(); complete()
targetName='Second'; begin(); complete(); locked=false; advance(3)
assert(#sent==2 and sent[1].target=='Partner-OtherRealm' and sent[2].target=='Second-OtherRealm')
''')
case('disable then reenable invalidates previous timer generation', '''
enable(); locked=true; begin(); complete()
MimDiceDB.tradeWhisperEnabled=false; MimDiceTradeWhisper.ApplySettings()
enable(); targetName='Second'; begin(); complete(); locked=false; advance(3)
assert(#sent==1 and sent[1].target=='Second-OtherRealm')
''')

source = (ROOT / 'TradeWhisper.lua').read_text(encoding='utf-8-sig')
for name, code in cases:
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.execute(MOCK)
    if name.startswith('existing ON'):
        vm.execute("MimDiceDB={tradeWhisperEnabled=true,custom='keep'}")
    vm.execute(source)
    vm.execute("fire('ADDON_LOADED','MimDice')")
    try:
        vm.execute(code)
        for message in vm.globals().sent.values():
            message.message.encode('utf-8')
    except Exception as exc:
        raise AssertionError(f'{name}: {exc}') from exc
print(f'Trade whisper: {len(cases)}/{len(cases)} mocked Lua 5.1 scenarios passed')
