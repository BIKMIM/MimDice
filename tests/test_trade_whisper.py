"""Exercise real trade-whisper code in Lua 5.1; no messages leave this mock."""
import argparse
from pathlib import Path
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--lua-python', type=Path)
parser.add_argument('--compare-head', action='store_true')
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
case('acceptance reset alone never sends; server completion still sends', '''
enable(); begin(); fire('TRADE_ACCEPT_UPDATE',0,0); assert(#sent==0)
complete(); assert(#sent==1)
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
case('trade error alone never sends; a corrected trade may still complete', '''
enable(); begin(); fire('UI_ERROR_MESSAGE',3); assert(#sent==0)
complete(); assert(#sent==1)
''')
case('unrelated UI error does not discard actual completed trade', '''
enable(); begin(); fire('UI_ERROR_MESSAGE',4); complete(); assert(#sent==1)
''')
case('old closed candidate expires', '''
enable(); begin(); fire('TRADE_CLOSED'); advance(6); complete(); assert(#sent==0)
''')
case('new trade cannot reuse the previous partner or snapshot', '''
enable(); begin(); fire('TRADE_CLOSED'); targetName='Next'; targetMoney=0
fire('TRADE_SHOW'); complete(); assert(#sent==0)
''')
case('changed money refreshes both sides before server completion', '''
enable(); begin(); targetMoney=2000000; fire('TRADE_MONEY_CHANGED')
complete(); assert(#sent==1 and sent[1].message:find('200g',1,true))
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
case('oversized item name and count are preserved in UTF8 chunks', '''
enable(); targetMoney=0; playerItems[1]={name=string.rep('가',200), count=12}
begin(); complete(); advance(10); assert(#sent>1)
local result=''
for _,msg in ipairs(sent) do
    assert(#msg.message<=250)
    result=result..msg.message:sub(#'[Trade complete] '+1)
end
assert(result=='Sent: '..string.rep('가',200)..' x12')
''')
case('large money beyond signed 32 bit', '''
enable(); targetMoney=3500000000; begin(); complete()
assert(sent[1].message:find('350000g',1,true))
''')
case('enchant service and slot 7 item are excluded', '''
enable(); targetMoney=0
playerItems[7]={name='My sword',enchant='ReceivedEnchant'}
targetItems[7]={name='Their sword',enchant='SentEnchant'}
begin(); complete(); assert(#sent==0)
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
case('MimDice sends its own receipt even when another addon is loaded', '''
enable(); MimRaid={cfg={tradeWhisperEnabled=true},TradeAnnounce={}}
begin(); complete(); assert(#sent==1)
MimRaid.cfg.tradeWhisperEnabled=false; begin(); complete(); assert(#sent==2)
''')
for side, field, text in (
    ('give item', 'playerItems[1]={name="Gift",count=3}; targetMoney=0', 'Sent: Gift x3'),
    ('receive item', 'targetItems[1]={name="Gift",count=3}; targetMoney=0', 'Received: Gift x3'),
    ('give gold', 'playerMoney=90000; targetMoney=0', 'Sent gold: 9g'),
    ('receive gold', 'targetMoney=90000', 'Received gold: 9g'),
):
    for accepted in ('1,0', '0,1', '0,0', 'nil,nil'):
        case(f'{side}: ordinary whisper, no recipient addon, accept {accepted}', f'''
enable(); {field}; fire('TRADE_SHOW'); fire('TRADE_ACCEPT_UPDATE',{accepted})
fire('TRADE_CLOSED'); complete(); advance(10)
assert(#sent==1 and sent[1].target=='Partner-OtherRealm')
assert(sent[1].message:find('{text}',1,true))
''')
    case(f'{side}: change event and server completion without accept event', f'''
enable(); targetMoney=0; fire('TRADE_SHOW'); {field}
fire('TRADE_TARGET_ITEM_CHANGED',1); fire('TRADE_CLOSED'); complete(); advance(10)
assert(#sent==1 and sent[1].message:find('{text}',1,true))
''')
case('full NPC name fallback never guesses selected target', '''
enable(); targetName=nil
GetUnitName=function(unit,full) assert(unit=='NPC' and full); return 'Other-ActualRealm' end
begin(); complete(); assert(#sent==1 and sent[1].target=='Other-ActualRealm')
''')
case('other addon enabled while receipt queued does not discard it', '''
enable(); locked=true; begin(); complete()
MimRaid={cfg={tradeWhisperEnabled=true},TradeAnnounce={}}
locked=false; advance(1); assert(#sent==1)
''')
case('received item arrives after acceptance; last changed snapshot is sent', '''
enable(); targetMoney=0; begin()
targetItems[1]={name='LateGift',count=2}; fire('TRADE_TARGET_ITEM_CHANGED',1)
fire('TRADE_CLOSED'); complete(); assert(#sent==1)
assert(sent[1].message:find('Received: LateGift x2',1,true))
''')
case('both directions and currencies appear in one completed receipt', '''
enable(); playerMoney=10000; targetMoney=20000
playerItems[1]={name='Given',count=2}; targetItems[1]={name='Taken',count=4}
begin(); complete(); advance(10)
local message=''; for _,entry in ipairs(sent) do message=message..entry.message end
for _,token in ipairs({'Received gold: 2g','Sent gold: 1g','Received: Taken x4','Sent: Given x2'}) do
    assert(message:find(token,1,true))
end
''')
case('removed offered item is not included in receipt', '''
enable(); playerItems[1]={name='Removed',count=1}; begin()
playerItems[1]=nil; fire('TRADE_PLAYER_ITEM_CHANGED',1); complete()
assert(#sent==1 and not sent[1].message:find('Removed',1,true))
''')
case('invalid refreshed data cannot send previous contents', '''
enable(); begin(); targetMoney=SECRET; fire('TRADE_MONEY_CHANGED')
complete(); assert(#sent==0)
''')
case('cancel after receiving-only preview never emits a receipt', '''
enable(); targetMoney=0; targetItems[1]={name='Unreceived',count=1}
begin(); fire('TRADE_REQUEST_CANCEL'); fire('TRADE_CLOSED'); complete(); advance(10)
assert(#sent==0)
''')
case('hidden trade UI teardown cannot erase received-only snapshot', '''
enable(); targetMoney=0; targetItems[1]={name='ReceivedGift',count=1}; begin()
TradeFrame={IsShown=function() return false end}
targetItems={}; fire('TRADE_TARGET_ITEM_CHANGED',1); fire('TRADE_ACCEPT_UPDATE',0,0)
fire('TRADE_CLOSED'); complete(); assert(#sent==1)
assert(sent[1].message:find('Received: ReceivedGift',1,true))
''')
case('sent-only slots cleared after both accept while UI still visible', '''
enable(); targetMoney=0; playerItems[1]={name='SentGift',count=3}
begin(); fire('TRADE_ACCEPT_UPDATE',1,1)
playerItems={}; fire('TRADE_PLAYER_ITEM_CHANGED',1)
fire('TRADE_CLOSED'); complete(); assert(#sent==1)
assert(sent[1].message:find('Sent: SentGift x3',1,true))
''')
case('sent-only teardown API failure after both accept preserves final offer', '''
enable(); targetMoney=0; playerItems[1]={name='SentGift',count=1}
begin(); fire('TRADE_ACCEPT_UPDATE',1,1)
GetTradePlayerItemInfo=function() error('trade already closing') end
fire('TRADE_PLAYER_ITEM_CHANGED',1); fire('TRADE_CLOSED'); complete()
assert(#sent==1 and sent[1].message:find('Sent: SentGift',1,true))
''')
case('NPC disappears before close with only one accepted', '''
enable(); targetMoney=0; playerItems[1]={name='SentGift',count=1}; begin()
UnitExists=function(unit) assert(unit=='NPC'); return false end
playerItems={}; fire('TRADE_PLAYER_ITEM_CHANGED',1); fire('TRADE_ACCEPT_UPDATE',0,0)
fire('TRADE_CLOSED'); complete(); assert(#sent==1)
''')
case('real offer removal resets acceptance and does not report the old item', '''
enable(); playerItems[1]={name='Removed',count=1}; begin()
fire('TRADE_ACCEPT_UPDATE',1,1)
playerItems={}; fire('TRADE_PLAYER_ITEM_CHANGED',1); fire('TRADE_ACCEPT_UPDATE',0,0)
fire('TRADE_ACCEPT_UPDATE',1,1); fire('TRADE_CLOSED'); complete()
assert(#sent==1 and not sent[1].message:find('Removed',1,true))
''')
case('offer replacement after acceptance reset uses new item and quantity', '''
enable(); targetMoney=0; playerItems[1]={name='Old',count=1}; begin()
fire('TRADE_ACCEPT_UPDATE',1,1)
playerItems[1]={name='New',count=5}; fire('TRADE_PLAYER_ITEM_CHANGED',1)
fire('TRADE_ACCEPT_UPDATE',0,0); fire('TRADE_ACCEPT_UPDATE',1,1)
fire('TRADE_CLOSED'); complete()
assert(#sent==1 and sent[1].message:find('Sent: New x5',1,true))
assert(not sent[1].message:find('Old',1,true))
''')
case('both accepted and cancelled still does not send', '''
enable(); targetMoney=0; playerItems[1]={name='NotGiven',count=1}; begin()
fire('TRADE_ACCEPT_UPDATE',1,1); playerItems={}; fire('TRADE_PLAYER_ITEM_CHANGED',1)
fire('TRADE_REQUEST_CANCEL'); fire('TRADE_CLOSED'); complete(); assert(#sent==0)
''')
case('diagnostic trace is bounded and never includes partner or item names', '''
enable(); targetMoney=0; playerItems[1]={name='PrivateGift',count=1}; begin()
for i=1,40 do fire('TRADE_PLAYER_ITEM_CHANGED',1) end
fire('TRADE_ACCEPT_UPDATE',1,1); playerItems={}; fire('TRADE_PLAYER_ITEM_CHANGED',1)
fire('TRADE_CLOSED'); complete()
local lines={}
DEFAULT_CHAT_FRAME={AddMessage=function(_,line) lines[#lines+1]=line end}
MimDiceTradeWhisper.PrintDebug()
assert(#lines>0 and #lines<=32)
local joined=table.concat(lines,' ')
assert(joined:find('accepted offer kept',1,true) and joined:find('send called',1,true))
assert(not joined:find('PrivateGift',1,true) and not joined:find('Partner',1,true))
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
def run_case(source, name, code):
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

if args.compare_head:
    import subprocess
    baseline = subprocess.check_output(['git','show','HEAD:TradeWhisper.lua'],cwd=ROOT).decode('utf-8-sig')
    failures=[]
    for name,code in cases:
        try:
            run_case(baseline,name,code)
        except AssertionError:
            failures.append(name)
    print(f'Before fix: {len(failures)}/{len(cases)} scenarios failed')
    for name in failures:
        print(f'  {name}')
for name,code in cases:
    run_case(source,name,code)
print(f'Trade whisper: {len(cases)}/{len(cases)} mocked Lua 5.1 scenarios passed')
