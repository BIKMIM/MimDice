"""Run the real ChatURL.lua in Lua 5.1 with small WoW stubs.

python tests/test_chat_url.py
Checks URL parsing, each click path on its own, and the on/off setting.
In-game /rw receive -> click -> Ctrl+C -> paste still needs a manual check.
"""
from pathlib import Path
from lupa.lua51 import LuaRuntime

SOURCE = (Path(__file__).resolve().parent.parent / 'ChatURL.lua').read_text(encoding='utf-8-sig')

STUBS = r'''
log = { setText = {}, shown = 0, hidden = 0, focus = 0, timers = {}, hooks = {}, filters = {} }
local function noop() end
local Frame = {}
Frame.__index = function(t, k)
    if Frame[k] then return Frame[k] end
    return noop
end
function Frame:Show() self.shown = true; if rawget(self, "isCopy") then log.shown = log.shown + 1 end end
function Frame:Hide()
    if rawget(self, "shown") and rawget(self, "isCopy") then log.hidden = log.hidden + 1 end
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Frame:IsShown() return self.shown end
function Frame:SetScript(n, f) self.scripts[n] = f end
function Frame:SetText(v) if rawget(self, "isEdit") then table.insert(log.setText, v) end end
function Frame:SetFocus() log.focus = log.focus + 1 end
function Frame:CreateFontString() return setmetatable({ scripts = {} }, Frame) end
function CreateFrame(kind, name)
    local f = setmetatable({ scripts = {}, shown = false }, Frame)
    if name == "MimDice_URLCopyFrame" then f.isCopy = true end
    if kind == "EditBox" then f.isEdit = true end
    return f
end
UIParent = CreateFrame("Frame")
UISpecialFrames = {}
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
tinsert = table.insert
C_Timer = { NewTimer = function(_, fn)
    local t = { fn = fn, cancelled = false }
    function t:Cancel() self.cancelled = true end
    table.insert(log.timers, t)
    return t
end }
function RunTimers()
    local list = log.timers; log.timers = {}
    for _, t in ipairs(list) do if not t.cancelled then t.fn() end end
end
function ChatFrame_AddMessageEventFilter(event, fn) log.filters[event] = fn end
function hooksecurefunc(name, fn) log.hooks[name] = fn end
function issecretvalue(v) return type(v) == "table" and v.__secret == true end
MimDiceDB = { chatURL = { enabled = true } }
'''

WITH_LINKUTIL = r'''
LinkProcessorResponse = { Handled = "HANDLED" }
LinkUtil = { handlers = {} }
function LinkUtil.IsLinkHandlerRegistered(t) return LinkUtil.handlers[t] ~= nil end
function LinkUtil.RegisterLinkHandler(t, fn) LinkUtil.handlers[t] = fn end
'''

failures = []


def check(name, got, expected):
    if got != expected:
        failures.append(f'{name}\n  got:      {got!r}\n  expected: {expected!r}')


def load(linkutil):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    if linkutil:
        lua.execute(WITH_LINKUTIL)
    lua.execute(SOURCE)
    return lua


def link(u, trailing=''):
    return f'|cff149bfd|Hmimdiceurl:{u}|h[{u}]|h|r{trailing}'


# ---------------------------------------------------------------- parsing
lua = load(True)
fmt = lua.eval('function(m) local r = MimDiceChatURL.FormatURLsInMessage(m); return r end')

cases = [
    ('plain', '일반 텍스트', '일반 텍스트'),
    ('rw discord', '공략: https://discord.gg/AbC', '공략: ' + link('https://discord.gg/AbC')),
    ('bare discord', 'discord.gg/AbC 오세요', link('discord.gg/AbC') + ' 오세요'),
    ('invite', 'https://discord.com/invite/Wow', link('https://discord.com/invite/Wow')),
    ('upper www', 'WWW.EXAMPLE.COM/a', link('WWW.EXAMPLE.COM/a')),
    ('mixed discord', 'Discord.gg/AbC', link('Discord.gg/AbC')),
    ('upper https', 'HTTPS://discord.gg/AbC', link('HTTPS://discord.gg/AbC')),
    ('color wrap', '|cffff0000https://discord.gg/AbC|r',
     '|cffff0000' + link('https://discord.gg/AbC') + '|r'),
    ('url after |r', 'https://discord.gg/AbC|rhttps://discord.gg/DeF',
     link('https://discord.gg/AbC') + '|r' + link('https://discord.gg/DeF')),
    ('query !', 'https://example.com/a?x=wow!', link('https://example.com/a?x=wow!')),
    ('query ;', 'https://example.com/a?x=1;', link('https://example.com/a?x=1;')),
    ('path !', 'https://example.com/a!', link('https://example.com/a', '!')),
    ('sentence dot', 'https://example.com/path?a=1&b=2.', link('https://example.com/path?a=1&b=2', '.')),
    ('outer paren', '(https://example.com/raid)', '(' + link('https://example.com/raid') + ')'),
    ('inner paren', 'https://en.wikipedia.org/wiki/Doom_(1993)', link('https://en.wikipedia.org/wiki/Doom_(1993)')),
    ('hash', 'https://example.com/#Sec', link('https://example.com/#Sec')),
    ('item + url', '|cffa335ee|Hitem:1::|h[검]|h|r 공략 https://discord.gg/X',
     '|cffa335ee|Hitem:1::|h[검]|h|r 공략 ' + link('https://discord.gg/X')),
    ('broken link', '|Hitem:123|h[broken discord.gg/AbC', '|Hitem:123|h[broken discord.gg/AbC'),
    ('glued word', 'abcwww.example.com', 'abcwww.example.com'),
    ('prefix only', 'https:// 입니다', 'https:// 입니다'),
    ('korean after space', 'https://a.com 입니다', link('https://a.com') + ' 입니다'),
    # 표시 코드 바로 뒤의 주소
    ('after texture', '|TInterface\\Icons\\INV_Misc_QuestionMark:0|thttps://discord.gg/AbC',
     '|TInterface\\Icons\\INV_Misc_QuestionMark:0|t' + link('https://discord.gg/AbC')),
    ('after atlas', '|A:raidicon:14:14|ahttps://discord.gg/AbC',
     '|A:raidicon:14:14|a' + link('https://discord.gg/AbC')),
    ('after new color', '|cnRED_FONT_COLOR:discord.gg/AbC|r',
     '|cnRED_FONT_COLOR:' + link('discord.gg/AbC') + '|r'),
    ('after escaped pipe', 'a||https://a.com', 'a||' + link('https://a.com')),
    ('texture path not linked', '|Twww.fake:0|t 텍스트', '|Twww.fake:0|t 텍스트'),
    ('unclosed texture kept', '|Tpath:0 https://a.com', '|Tpath:0 https://a.com'),
    # 따옴표
    ('query quotes', "https://example.com/?q='wow'", link("https://example.com/?q='wow'")),
    ('wrapped in quotes', "'https://example.com/a'", "'" + link('https://example.com/a') + "'"),
    ('double quotes', '"https://example.com/a"', '"' + link('https://example.com/a') + '"'),
    # 접두사만 있는 경우
    ('www only', 'www. 입니다', 'www. 입니다'),
    ('www only end', '주소는 www.', '주소는 www.'),
    ('https only dot', 'https://.', 'https://.'),
    # || 뒤 대문자 주소 연속
    ('escaped pipe with uppercase', '||HTTPS://a.com||https://b.com||https://c.com',
     '||' + link('HTTPS://a.com') + '||' + link('https://b.com') + '||' + link('https://c.com')),
    # 주소 내부 작은따옴표 + 바깥 인용부호
    ('quotes with apostrophe inside query', "'https://example.com/?name=O\'Reilly'",
     "'" + link("https://example.com/?name=O\'Reilly") + "'"),
    # O'Reilly 접두사 뒤 따옴표 쿼리 URL
    ('apostrophe in prefix with quoted query', "O'Reilly:https://example.com/?q='wow'",
     "O'Reilly:" + link("https://example.com/?q='wow'")),
    # 하이퍼링크 텍스트 내 || 포함 및 뒤이어 오는 URL
    ('hyperlink with escaped pipe in text', "|Hitem:1|h[||hello]|h https://discord.gg/AbC",
     "|Hitem:1|h[||hello]|h " + link("https://discord.gg/AbC")),
    ('hyperlink with four pipes in text', "|Hitem:1|h[||||hello]|h https://discord.gg/AbC",
     "|Hitem:1|h[||||hello]|h " + link("https://discord.gg/AbC")),
    ('hyperlink with escaped H and r in text', "|Hitem:1|h[||H||r]|h https://discord.gg/AbC",
     "|Hitem:1|h[||H||r]|h " + link("https://discord.gg/AbC")),
    ('url immediately after hyperlink without space', "|Hitem:1|h[검]|hhttps://discord.gg/AbC",
     "|Hitem:1|h[검]|h" + link("https://discord.gg/AbC")),
    ('player link followed by url', "|cff0070dd|Hplayer:BIK|h[BIK]|h|r: https://discord.gg/AbC",
     "|cff0070dd|Hplayer:BIK|h[BIK]|h|r: " + link("https://discord.gg/AbC")),
    # 색상 코드 경계의 작은따옴표 문맥 보존
    ('color wrapped with outer quotes', "'|cffff0000https://example.com/?name=O\'Reilly'|r",
     "'|cffff0000" + link("https://example.com/?name=O\'Reilly") + "'|r"),
    ('named color wrapped with outer quotes', "'|cnRED_FONT_COLOR:https://example.com/?name=O\'Reilly'|r",
     "'|cnRED_FONT_COLOR:" + link("https://example.com/?name=O\'Reilly") + "'|r"),
    ('prefix with quote and color wrap', "공략: '|cffff0000https://example.com/?name=O\'Reilly'|r",
     "공략: '|cffff0000" + link("https://example.com/?name=O\'Reilly") + "'|r"),
    ('word glued before color code ignored', "abc|cffff0000www.example.com|r",
     "abc|cffff0000www.example.com|r"),
    ('multiple color codes with apostrophe prefix', "O|cffff0000'|rhttps://example.com/?q='wow'",
     "O|cffff0000'|r" + link("https://example.com/?q='wow'")),
    ('color code before apostrophe with preceding letter', "O|cffff0000'https://example.com/?q='wow'",
     "O|cffff0000'" + link("https://example.com/?q='wow'")),
]
for name, src, expected in cases:
    once = fmt(src)
    check(f'format: {name}', once, expected)
    check(f'idempotent: {name}', fmt(once), once)

# filter keeps the rest of the arguments for raid warnings
lua.execute('''
local f = log.filters.CHAT_MSG_RAID_WARNING
rwResult = { f(nil, "CHAT_MSG_RAID_WARNING", "https://discord.gg/AbC", "공대장", "x") }
''')
rw = lua.eval('rwResult')
check('rw filter registered', lua.eval('log.filters.CHAT_MSG_RAID_WARNING ~= nil'), True)
check('rw filter msg', rw[2], link('https://discord.gg/AbC'))
check('rw filter sender', rw[3], '공대장')
check('secret message untouched', lua.eval('select(2, log.filters.CHAT_MSG_SAY(nil, "E", {__secret=true}))'), None)

# ---------------------------------------------------------------- LinkUtil path only
check('linkutil: chosen path', lua.eval('MimDiceChatURL.clickPath'), 'LinkUtil')
check('linkutil: no SetItemRef hook', lua.eval('log.hooks.SetItemRef == nil'), True)
lua.execute('''
local h = LinkUtil.handlers.mimdiceurl
r1 = h("mimdiceurl:https://discord.gg/AbC", "[x]", {}, { button = "LeftButton" })
RunTimers()
''')
check('linkutil left: handled', lua.eval('r1'), 'HANDLED')
check('linkutil left: set once', list(lua.eval('log.setText').values()), ['https://discord.gg/AbC'])
check('linkutil left: focus once', lua.eval('log.focus'), 1)

lua.execute('''
log.setText = {}
r2 = LinkUtil.handlers.mimdiceurl("mimdiceurl:https://discord.gg/R", "[x]", {}, { button = "RightButton" })
''')
check('linkutil right: ignored', len(lua.eval('log.setText')), 0)
check('linkutil right: still handled (no empty tooltip)', lua.eval('r2'), 'HANDLED')

lua.execute('''
MimDiceChatURL.SetEnabled(false)
log.setText = {}
LinkUtil.handlers.mimdiceurl("mimdiceurl:https://discord.gg/Off", "[x]", {}, { button = "LeftButton" })
''')
check('disabled: ignored', len(lua.eval('log.setText')), 0)
check('disabled: open window closed', lua.eval('log.hidden') >= 1, True)

# turning off while a focus timer is pending
lua.execute('''
MimDiceChatURL.SetEnabled(true)
log.focus = 0
LinkUtil.handlers.mimdiceurl("mimdiceurl:https://a.com", "[x]", {}, { button = "LeftButton" })
MimDiceChatURL.SetEnabled(false)
RunTimers()
''')
check('off cancels pending focus', lua.eval('log.focus'), 0)

# ---------------------------------------------------------------- SetItemRef fallback only
lua2 = load(False)
check('fallback: chosen path', lua2.eval('MimDiceChatURL.clickPath'), 'SetItemRef')
lua2.execute('''
log.hooks.SetItemRef("mimdiceurl:https://discord.gg/AbC", "[x]", "LeftButton")
log.hooks.SetItemRef("item:123", "[x]", "LeftButton")
log.hooks.SetItemRef("mimdiceurl:https://discord.gg/R", "[x]", "RightButton")
RunTimers()
''')
check('fallback: only left url opened once', list(lua2.eval('log.setText').values()), ['https://discord.gg/AbC'])
check('fallback: focus once', lua2.eval('log.focus'), 1)

if failures:
    print(f'{len(failures)} FAILED')
    for f in failures:
        print(f)
    raise SystemExit(1)
print(f'chat url: all {len(cases) * 2 + 18} checks passed')
