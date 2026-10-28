"""Exercise the real settings constructors and transitions in Lua 5.1.

python tests/test_settings_ui.py --lua-python PATH
WoW rendering and the actual gear texture still require an in-game check.
"""
from pathlib import Path

# Reuse the upstream sound-test WoW stubs without rerunning its scenarios.
helper = Path(__file__).with_name('test_sound_regressions.py')
namespace = {'__file__': str(helper)}
exec(compile(helper.read_text(encoding='utf-8').split('\ncurrent =')[0], str(helper), 'exec'), namespace)
source = (helper.parent.parent / 'SoundAlert.lua').read_text(encoding='utf-8-sig')
scenarios = r'''
local frames = {}
local methods = {}
local function noop() end
local function object(kind, name, parent)
    local o = { kind = kind, name = name, parent = parent, children = {}, regions = {},
        scripts = {}, shown = true, width = 380, height = 518, points = {},
        bg = {0,0,0,0.8}, border = {0.6,0.6,0.6,1} }
    setmetatable(o, { __index = function(_, k)
        if methods[k] then return methods[k] end
        if k:match('^Set') or k:match('^Enable') or k:match('^Register') or
            k:match('^Clear') or k:match('^Stop') then return noop end
    end })
    if parent then table.insert(parent.children, o) end
    if name then _G[name] = o end
    table.insert(frames, o)
    return o
end
function CreateFrame(kind, name, parent, template)
    local f = object(kind, name, parent)
    if template == 'UIPanelScrollFrameTemplate' then
        f.ScrollBar = object('Slider', nil, f)
    end
    return f
end
function methods:SetParent(parent)
    if self.parent then
        for i, c in ipairs(self.parent.children) do
            if c == self then table.remove(self.parent.children, i); break end
        end
    end
    self.parent = parent; table.insert(parent.children, self)
end
function methods:GetParent() return self.parent end
function methods:GetName() return self.name end
function methods:GetObjectType() return self.kind end
function methods:IsObjectType(kind) return self.kind == kind end
function methods:GetChildren() return unpack(self.children) end
function methods:GetRegions() return unpack(self.regions) end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:SetSize(w,h) self.width=w; self.height=h end
function methods:GetEffectiveScale() return 1 end
function methods:GetFrameLevel() return self.level or 1 end
function methods:GetFrameStrata() return 'HIGH' end
function methods:SetFrameLevel(v) self.level=v end
function methods:SetScript(k,fn) self.scripts[k]=fn end
function methods:GetScript(k) return self.scripts[k] end
function methods:HookScript(k,fn)
    local old=self.scripts[k]
    self.scripts[k]=function(...) if old then old(...) end; fn(...) end
end
function methods:Hide()
    if not self.shown then return end
    self.shown=false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:Show()
    if self.shown then return end
    self.shown=true
    if self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:IsShown() return self.shown end
function methods:SetPoint(...) table.insert(self.points, {...}) end
function methods:ClearAllPoints() self.points={} end
function methods:SetBackdrop(v) self.backdrop=v end
function methods:GetBackdrop() return self.backdrop end
function methods:SetBackdropColor(...) self.bg={...} end
function methods:GetBackdropColor() return unpack(self.bg) end
function methods:SetBackdropBorderColor(...) self.border={...} end
function methods:GetBackdropBorderColor() return unpack(self.border) end
function methods:CreateFontString() local f=object('FontString'); table.insert(self.regions,f); return f end
function methods:CreateTexture() local t=object('Texture'); table.insert(self.regions,t); return t end
function methods:CreateLine() return object('Line') end
function methods:GetFontString()
    if not self.fontString then self.fontString=self:CreateFontString() end
    return self.fontString
end
function methods:SetFont(...) self.font={...}; return true end
function methods:GetFont() return unpack(self.font or {'Fonts\2002.ttf',12,''}) end
function methods:SetText(v) self.textValue=v end
function methods:GetText() return self.textValue or '' end
function methods:SetChecked(v) self.checked=v end
function methods:GetChecked() return self.checked end
function methods:GetNormalTexture() return nil end
function methods:GetHighlightTexture() return nil end
function methods:GetPushedTexture() return nil end
function methods:GetDisabledTexture() return nil end
function methods:GetThumbTexture() return nil end
function methods:GetValue() return 1 end
function methods:GetMinMaxValues() return 0,100 end
function methods:GetVerticalScrollRange() return 0 end
function methods:GetVerticalScroll() return self.verticalScroll or 0 end
function methods:SetVerticalScroll(value) self.verticalScroll = value end
function methods:SetScrollChild(v) self.scrollChild=v end
function methods:GetStringWidth() return 100 end
function methods:GetStringHeight() return self.stringHeight or 14 end
function methods:IsMouseOver() return false end
function methods:HasFocus() return false end
function methods:SetTexture(v) self.texture=v end
function methods:SetVertexColor(...) self.vertex={...} end
function methods:SetColorTexture(...) end
function methods:SetHighlightTexture(...) end
UIParent=CreateFrame('Frame'); MainWindow=CreateFrame('Frame','MainWindow',UIParent)
MainWindow:SetHeight(518)
tinsert=table.insert
GameTooltip=CreateFrame('Frame')
UIDropDownMenu_SetWidth=noop
UIDropDownMenu_SetSelectedValue=noop
UIDropDownMenu_SetText=noop
UIDropDownMenu_Initialize=noop
function MimDice_GetLanguageSetting() return 'auto' end
function MimDice_GetLanguage() return 'koKR' end
function MimDice_GetLocaleName() return '한국어' end
function MimDiceApplyFontToXML() end
MimDiceBloodlustReminder.GetSettings=function() return {enabled=false} end
function GetLocale() return 'koKR' end
MimDiceSoundFiles.CheckDialogChannel=function() end
function deepCopy(t) if type(t)~='table' then return t end
    local c={} for k,v in pairs(t) do c[k]=deepCopy(v) end return c end
function same(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
-- Populate existing user choices after the old initializer has established its schema.
MimDiceDB.skin.enabled=false
MimDiceDB.skin.font='nanumgothic'
MimDiceDB.skin.base={r=.17,g=.24,b=.31,a=.8}
MimDiceDB.interruptAlert.enabled=false
MimDiceDB.interruptAlert.soundFile='my-interrupt.ogg'
MimDiceDB.chatSound.ignoreSelf=false
MimDiceDB.chatSound.muteDefaultWhisper=false
MimDiceDB.chatSound.channels.WHISPER.enabled=true
MimDiceDB.chatSound.channels.WHISPER.soundType='id'
MimDiceDB.chatSound.channels.WHISPER.soundID=12345
-- Initialize normal legacy bookkeeping before measuring changes made by this UI.
SA_InitDB()
local before=deepCopy(MimDiceDB)
local expectedFirst=MimDiceDB.settingsTab or 'alerts'
SoundAlert_OnLoad()
local sa=settingsAudit
assert(sa.SettingsWindow and #sa.SettingsTabs==3)
assert(not sa.SettingsWindow:IsShown())
assert(same(before,MimDiceDB), 'constructors changed existing settings')
assert(SA_TabOption==nil and SA_TabChat==nil and SA_TabSkin==nil)
local pages={SA_OptionWindow,SA_ChatWindow,SA_SkinWindow}
for _,p in ipairs(pages) do assert(p:GetParent()==sa.SettingsWindow and p:GetBackdrop()==nil) end
local function check(key)
    assert(sa.SettingsWindow:IsShown() and sa.SettingsTab==key)
    assert(SA_OptionWindow:IsShown()==(key=='alerts'))
    assert(SA_ChatWindow:IsShown()==(key=='chat'))
    assert(SA_SkinWindow:IsShown()==(key=='appearance'))
end
sa.ToggleSettings(); check(expectedFirst)
sa.SettingsTabs[2]:GetScript('OnClick')(); check('chat')
sa.SettingsTabs[3]:GetScript('OnClick')(); check('appearance')
sa.ToggleSettings(); assert(not sa.SettingsWindow:IsShown())
for _,p in ipairs(pages) do assert(not p:IsShown()) end
sa.ToggleSettings(); check('appearance')
MainWindow:Hide(); assert(not sa.SettingsWindow:IsShown())
MainWindow:Show(); assert(not sa.SettingsWindow:IsShown())
sa.ToggleSettings(); check('appearance')
sa.SettingsWindow:Hide(); MimDiceDB.settingsTab='unknown-old-tab'
sa.ToggleSettings(); check('alerts')
-- Repeat close/reopen and tab cycles with both skin modes.
for _,enabled in ipairs({true,false,true,false}) do
    MimDiceDB.skin.enabled=enabled; SA_SkinRefresh()
    for _,key in ipairs({'chat','appearance','alerts'}) do
        sa.SelectSettingsTab(key); check(key)
        for _,p in ipairs(pages) do assert(p:GetBackdrop()==nil) end
        sa.ToggleSettings(); sa.ToggleSettings(); check(key)
    end
end
MainWindow:SetHeight(200); SA_SkinRefreshTabs(); assert(sa.SettingsWindow:GetHeight()==600)
MainWindow:SetHeight(800); SA_SkinRefreshTabs(); assert(sa.SettingsWindow:GetHeight()==800)
-- One scroll child owns both the introduction and the dynamic sound rows.
local page = SA_OptionWindow
assert(page.pageScroll:GetParent()==page)
assert(page.pageScroll.scrollChild==page.content)
assert(page.body:GetParent()==page.content)
assert(page.scrollChild:GetParent()==page.body)
assert(SA_ListScrollFrame==nil, 'nested list scrollbar still exists')
page.pageScroll:SetHeight(180)
SA_RefreshList()
local originalHeight = page.content:GetHeight()
local count = #MimDiceDB.soundAlerts
for i=1,20 do
    table.insert(MimDiceDB.soundAlerts, {class='MAGE', spellID=90000+i,
        spellName='Extra '..i, soundType='custom', soundFile='test.ogg', enabled=true})
end
SA_RefreshList()
assert(page.content:GetHeight()==originalHeight+20*34, 'full-page range did not grow with rows')
page.pageScroll:SetVerticalScroll(page.content:GetHeight()-180)
for i=#MimDiceDB.soundAlerts,count+1,-1 do table.remove(MimDiceDB.soundAlerts,i) end
SA_RefreshList()
assert(page.content:GetHeight()==originalHeight)
assert(page.pageScroll:GetVerticalScroll()==originalHeight-180, 'deleting rows left an empty scrolled area')
page.soundFolderHelp.stringHeight=84
SA_RefreshList()
assert(page.content:GetHeight()==originalHeight+70, 'wrapped help text was omitted from scroll range')
page.pageScroll:SetHeight(2000)
page.pageScroll:GetScript('OnSizeChanged')(page.pageScroll)
assert(page.pageScroll:GetVerticalScroll()==0, 'resizing did not clamp scroll position')
MimDiceDB.settingsTab=before.settingsTab
MimDiceDB.skin.enabled=before.skin.enabled
assert(same(before,MimDiceDB), 'navigation or skin refresh changed user settings')
'''
for restored in (False, True):
    vm = namespace['make_vm'](source + '\nsettingsAudit = SA')
    scenario = scenarios
    if restored:
        scenario = scenario.replace('MimDiceDB.skin.enabled=false',
            "MimDiceDB.skin.enabled=true; MimDiceDB.settingsTab='chat'", 1)
    vm.execute(scenario)
print('Settings UI: constructors, tab switching, close/reopen, main hide, invalid tab, skin modes, resizing and saved settings passed')

