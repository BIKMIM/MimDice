-- ChatURL.lua
-- Author         : BIK
-- Description    : 채팅창 웹 주소(URL) 감지 및 클릭 복사 모듈

---@diagnostic disable: undefined-global, param-type-mismatch, undefined-field, cast-local-type

local CU = {}
MimDiceChatURL = CU

local function L(key)
    if type(MimDice_L) == "function" then
        return MimDice_L(key)
    end
    return key
end

-- =====================================================================
-- 1. 안전한 비밀 값(Secret Value) 및 타입 검사 (DEVGUIDE.md 준수)
-- =====================================================================
local function PublicString(val)
    if type(issecretvalue) == "function" and issecretvalue(val) then return nil end
    if type(val) ~= "string" then return nil end
    return val
end

-- =====================================================================
-- 2. 설정 확인 및 활성화 토글 (비활성화 시 창 닫기 및 타이머 취소)
-- =====================================================================
local copyFrame
local focusTimer

function CU.IsEnabled()
    if not MimDiceDB then return true end
    if not MimDiceDB.chatURL then
        MimDiceDB.chatURL = { enabled = true }
    end
    return MimDiceDB.chatURL.enabled ~= false
end

function CU.SetEnabled(enabled)
    if not MimDiceDB then MimDiceDB = {} end
    if not MimDiceDB.chatURL then MimDiceDB.chatURL = {} end
    local newState = (enabled and true or false)
    MimDiceDB.chatURL.enabled = newState

    if not newState then
        if focusTimer and focusTimer.Cancel then
            focusTimer:Cancel()
            focusTimer = nil
        end
        if copyFrame and copyFrame:IsShown() then
            copyFrame:Hide()
        end
    end
end

-- =====================================================================
-- 3. URL 인식 및 하이퍼링크 분리/변환 로직
-- =====================================================================
-- 일반 텍스트를 [글자 구간]과 [WoW 표시 코드 구간]으로 나눈 뒤, 글자 구간에서만 URL을 찾는다.
-- 표시 코드(|c, |r, |T…|t, |A…|a 등)는 주소에 섞이지 않고, 코드 바로 뒤의 주소도 인식된다.
local URL_PREFIXES = {
    "[hH][tT][tT][pP][sS]?://",
    "[wW][wW][wW]%.",
    "[dD][iI][sS][cC][oO][rR][dD]%.[gG][gG]/",
    "[dD][iI][sS][cC][oO][rR][dD]%.[cC][oO][mM]/[iI][nN][vV][iI][tT][eE]/",
}

-- 끝에 붙은 문장부호만 주소에서 뗀다.
-- 경로 부분: . , ; : ! ? 는 문장부호로 본다.
-- 쿼리(?)·해시(#) 부분: 값의 일부일 수 있으므로 . , 만 뗀다. (예: ?x=wow! 보존)
-- 닫는 괄호와 작은따옴표는 짝이 맞지 않을 때만 뗀다.
--   (예: Doom_(1993) · ?q='wow' 보존, (주소) · '주소' 의 바깥 기호 제거)
-- " > } 는 주소에 그대로 쓸 수 없는 문자이므로 항상 뗀다.
-- hasOpenQuote: URL 직전의 앞쪽 접두사가 여는 작은따옴표로 끝나는지 여부 (예: 'https:// 또는 ('https://)
local function SplitTrailingPunctuation(url, hasOpenQuote)
    local trailing = ""
    local inQuery = url:find("[?#]") ~= nil
    local openParen = select(2, url:gsub("%(", ""))
    local closeParen = select(2, url:gsub("%)", ""))
    local openBracket = select(2, url:gsub("%[", ""))
    local closeBracket = select(2, url:gsub("%]", ""))
    local openQuote = (hasOpenQuote == true)

    while #url > 0 do
        local last = url:sub(-1)
        local strip = false
        if last == "." or last == "," then
            strip = true
        elseif last:find("[;:!?]") then
            -- 쿼리 시작 문자 ? 자체가 맨 끝이면 빈 쿼리이므로 문장부호로 본다.
            if not inQuery or (last == "?" and not url:sub(1, -2):find("[?#]")) then
                strip = true
            end
        elseif last == ")" and closeParen > openParen then
            strip = true
            closeParen = closeParen - 1
        elseif last == "]" and closeBracket > openBracket then
            strip = true
            closeBracket = closeBracket - 1
        elseif last == "'" then
            if openQuote then
                strip = true
                openQuote = false
            else
                local qCount = select(2, url:gsub("'", ""))
                if qCount % 2 == 1 then
                    strip = true
                end
            end
        elseif last:find("[}>\"]") then
            strip = true
        end
        if not strip then break end
        trailing = last .. trailing
        url = url:sub(1, -2)
        inQuery = url:find("[?#]") ~= nil
    end
    return url, trailing
end

-- 접두사 뒤에 실제 내용이 한 글자 이상 있어야 주소로 본다. ("www." "https://" 단독은 제외)
local function HasBody(u)
    for _, p in ipairs(URL_PREFIXES) do
        if u:match("^" .. p .. ".") then return true end
    end
    return false
end

-- 주소 본문에는 파이프가 없으므로 링크 데이터·표시 문구에 그대로 넣어도 안전하다.
-- 문장부호를 뗀 뒤에 검사하므로 "www." 가 "www" 로 잘린 링크도 생기지 않는다.
local function FormatOneURL(url, hasOpenQuote)
    local u, trailing = SplitTrailingPunctuation(url, hasOpenQuote)
    if not HasBody(u) then return url end
    return "|cff149bfd|Hmimdiceurl:" .. u .. "|h[" .. u .. "]|h|r" .. trailing
end

-- 한 단어(공백 사이 문자열, 파이프 없음)에서 URL 시작 위치를 찾는다.
local function FindURLInWord(word)
    local bestPos
    for _, p in ipairs(URL_PREFIXES) do
        local pos = word:find(p)
        if pos and (not bestPos or pos < bestPos) then bestPos = pos end
    end
    if not bestPos then return nil end
    local prefix = word:sub(1, bestPos - 1)
    -- "abcwww.x" 처럼 글자에 바로 붙은 경우는 주소로 보지 않는다. 기호 뒤((, [, : 등)는 허용.
    if prefix ~= "" and prefix:match("[%w_]$") then return nil end
    return prefix, word:sub(bestPos)
end

-- 표시 코드가 없는 순수 글자 구간에서 URL을 링크로 바꾼다.
-- prefix가 여는 작은따옴표로 끝나는지 확인 (예: 'https:// 또는 ('https://)
-- O'Reilly: 처럼 영문자 뒤의 아포스트로피는 여는 인용부호로 보지 않는다.
local function HasEnclosingQuote(prefix)
    if not prefix or prefix == "" then return false end
    if prefix:sub(-1) == "'" then
        local prev = prefix:sub(-2, -2)
        if prev == "" or not prev:match("[%w_]") then
            return true
        end
    end
    return false
end

-- 표시 코드가 없는 순수 글자 구간에서 URL을 링크로 바꾼다.
local function FormatURLsInRun(run)
    return (run:gsub("%S+", function(word)
        local prefix, url = FindURLInWord(word)
        if url then
            local hasOpenQuote = HasEnclosingQuote(prefix)
            return prefix .. FormatOneURL(url, hasOpenQuote)
        end
        return word
    end))
end

-- pos 위치(파이프)에서 시작하는 표시 코드의 끝 위치를 돌려준다.
-- 끝을 찾을 수 없는 아이콘 코드면 nil (구간 전체를 원문 보존).
local function EscapeEnd(text, pos)
    local nextChar = text:sub(pos + 1, pos + 1)
    if nextChar == "c" then
        local e = select(2, text:find("^|c%x%x%x%x%x%x%x%x", pos))
        if e then return e end
        e = select(2, text:find("^|cn[^:|]*:", pos))   -- |cnRED_FONT_COLOR: 형식
        if e then return e end
        return pos + 1
    elseif nextChar == "T" or nextChar == "A" or nextChar == "K" then
        -- 아이콘(|T…|t), 아틀라스(|A…|a), 보호된 이름(|K…|k)은 닫는 코드까지 한 구간
        local close = "|" .. nextChar:lower()
        local s = text:find(close, pos + 2, true)
        if not s then return nil end
        return s + 1
    elseif nextChar == "" then
        return pos
    end
    return pos + 1   -- ||, |r, |n 등 두 글자 코드
end

local function FormatURLsInPlainText(text)
    -- 깨진 링크 구간(|H 또는 |h가 닫히지 않고 남아있음)은 보수적으로 변환하지 않고 보존
    if text:gsub("||", ""):find("|[Hh]") then   -- 글자 그대로의 파이프(||) 뒤 h(예: ||https://)는 제외
        return text
    end

    local low = text:lower()
    if not (low:find("://") or low:find("www%.") or low:find("discord%.gg/") or low:find("discord%.com/invite/")) then
        return text
    end

    local out = {}
    local pos, len = 1, #text
    while pos <= len do
        local pipe = text:find("|", pos, true)
        if not pipe then
            out[#out + 1] = FormatURLsInRun(text:sub(pos))
            break
        end
        if pipe > pos then
            out[#out + 1] = FormatURLsInRun(text:sub(pos, pipe - 1))
        end
        local codeEnd = EscapeEnd(text, pipe)
        if not codeEnd then
            return text   -- 닫히지 않은 아이콘 코드: 해석하지 않고 원문 보존
        end
        out[#out + 1] = text:sub(pipe, codeEnd)
        pos = codeEnd + 1
    end
    return table.concat(out)
end

-- 이스케이프되지 않은 특정 태그(|h, |r)를 탐색 (중간의 ||는 2글자 건너뜀)
local function FindUnescapedTag(s, tag, startPos)
    local pos = startPos
    local len = #s
    local tagLen = #tag
    while pos <= len do
        if s:sub(pos, pos + 1) == "||" then
            pos = pos + 2
        elseif s:sub(pos, pos + tagLen - 1) == tag then
            return pos, pos + tagLen - 1
        else
            local nextPipe = s:find("|", pos + 1, true)
            if not nextPipe then break end
            pos = nextPipe
        end
    end
    return nil, nil
end

-- pos 위치에서 시작하는 올바른 하이퍼링크의 끝 위치를 반환 (|H...|h...|h 또는 |c...|H...|h...|h|r)
local function MatchHyperlinkAt(s, pos)
    local cur = pos
    local hasColor = false
    if s:sub(cur, cur + 1) == "|c" then
        local colorEnd = s:find("^|c%x%x%x%x%x%x%x%x", cur)
        if colorEnd then
            cur = cur + 10
            hasColor = true
        end
    end

    if s:sub(cur, cur + 1) ~= "|H" then
        return nil
    end

    -- 링크 데이터 끝 (|h) 탐색
    local h1_start, h1_end = FindUnescapedTag(s, "|h", cur + 2)
    if not h1_start then return nil end

    -- 링크 표시문구 끝 (|h) 탐색 (내부의 ||hello 등은 이스케이프된 파이프로 통과)
    local h2_start, h2_end = FindUnescapedTag(s, "|h", h1_end + 1)
    if not h2_start then return nil end

    if hasColor then
        if s:sub(h2_end + 1, h2_end + 2) == "|r" then
            return h2_end + 2
        end
    end
    return h2_end
end

local function FindNextHyperlink(s, startPos)
    local pos = startPos
    local len = #s
    while pos <= len do
        if s:sub(pos, pos + 1) == "||" then
            pos = pos + 2
        else
            local linkEnd = MatchHyperlinkAt(s, pos)
            if linkEnd then
                return pos, linkEnd
            end
            local nextPipe = s:find("|", pos + 1, true)
            if not nextPipe then break end
            pos = nextPipe
        end
    end
    return nil, nil
end

function CU.FormatURLsInMessage(msg)
    local text = PublicString(msg)
    if not text or text == "" then return msg, false end

    local parts = {}
    local currentPos = 1
    local len = #text

    while currentPos <= len do
        local linkStart, linkEnd = FindNextHyperlink(text, currentPos)
        if linkStart then
            if linkStart > currentPos then
                local plain = text:sub(currentPos, linkStart - 1)
                parts[#parts + 1] = FormatURLsInPlainText(plain)
            end
            parts[#parts + 1] = text:sub(linkStart, linkEnd)
            currentPos = linkEnd + 1
        else
            local plain = text:sub(currentPos)
            parts[#parts + 1] = FormatURLsInPlainText(plain)
            break
        end
    end

    local newText = table.concat(parts)
    return newText, (newText ~= text)
end

-- =====================================================================
-- 4. 복사 팝업창 UI (Copy Frame)
-- =====================================================================
local function EnsureCopyFrame()
    if copyFrame then return copyFrame end

    local f = CreateFrame("Frame", "MimDice_URLCopyFrame", UIParent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:SetSize(420, 75)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetScript("OnHide", function()
        if focusTimer and focusTimer.Cancel then
            focusTimer:Cancel()
            focusTimer = nil
        end
    end)

    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.95)
    f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -10)
    title:SetText(L("웹 주소 복사"))
    title:SetTextColor(1, 0.82, 0)

    local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
    hint:SetText(L("Ctrl+C 로 복사하세요"))
    hint:SetTextColor(0.8, 0.8, 0.8)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    eb:SetAutoFocus(false)
    eb:SetSize(380, 22)
    eb:SetPoint("CENTER", f, "CENTER", 0, -2)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnEnterPressed", function() f:Hide() end) -- 채팅 전송 방지

    f.editBox = eb
    copyFrame = f

    -- ESC 키로 닫힐 수 있도록 와우 특수 프레임에 등록
    if _G.UISpecialFrames and not tContains(_G.UISpecialFrames, "MimDice_URLCopyFrame") then
        tinsert(_G.UISpecialFrames, "MimDice_URLCopyFrame")
    end

    return copyFrame
end

function CU.ShowCopyBox(rawUrl)
    if not CU.IsEnabled() then return end
    local url = PublicString(rawUrl)
    if not url or url == "" then return end

    local f = EnsureCopyFrame()
    if not f or not f.editBox then return end

    if focusTimer and focusTimer.Cancel then
        focusTimer:Cancel()
        focusTimer = nil
    end

    f.editBox:SetText(url)
    f:Show()

    if C_Timer and C_Timer.NewTimer then
        focusTimer = C_Timer.NewTimer(0, function()
            focusTimer = nil
            if f:IsShown() and f.editBox and CU.IsEnabled() then
                f.editBox:SetFocus()
                f.editBox:HighlightText()
            end
        end)
    else
        f.editBox:SetFocus()
        f.editBox:HighlightText()
    end
end

-- =====================================================================
-- 5. 하이퍼링크 클릭 처리 (전용 mimdiceurl: 링크, 왼쪽 클릭만, 경로 하나)
-- =====================================================================
local URL_LINK_PREFIX = "mimdiceurl:"   -- 11글자, 주소는 12번째 글자부터

local function OpenFromLink(rawLink, button)
    if not CU.IsEnabled() then return end
    local btn = PublicString(button)
    if btn and btn ~= "LeftButton" then return end   -- 오른쪽 클릭 등은 무시

    local link = PublicString(rawLink)
    if not link or link:sub(1, #URL_LINK_PREFIX) ~= URL_LINK_PREFIX then return end
    local url = link:sub(#URL_LINK_PREFIX + 1)
    if url == "" then return end

    CU.ShowCopyBox(url)
end

-- LinkUtil 처리기 인자: (link, text, linkData, contextData)
-- 클릭한 버튼은 contextData.button 에 들어 있다.
local function ButtonFromContext(contextData)
    if type(issecretvalue) == "function" and issecretvalue(contextData) then return nil end
    if type(contextData) ~= "table" then return nil end
    return contextData.button
end

CU.OpenFromLink = OpenFromLink           -- 검사용
CU.ButtonFromContext = ButtonFromContext -- 검사용

if LinkUtil and LinkUtil.RegisterLinkHandler and LinkUtil.IsLinkHandlerRegistered then
    -- 지원 클라이언트: 링크 처리기 하나로만 처리한다. (빈 툴팁도 열리지 않음)
    if not LinkUtil.IsLinkHandlerRegistered("mimdiceurl") then
        LinkUtil.RegisterLinkHandler("mimdiceurl", function(link, text, linkData, contextData)
            OpenFromLink(link, ButtonFromContext(contextData))
            if LinkProcessorResponse then return LinkProcessorResponse.Handled end
        end)
    end
    CU.clickPath = "LinkUtil"
elseif hooksecurefunc then
    -- 처리기 등록이 없는 클라이언트에서만 SetItemRef 후처리 훅을 쓴다.
    hooksecurefunc("SetItemRef", function(link, text, button)
        if type(issecretvalue) == "function" and issecretvalue(link) then return end
        if type(link) ~= "string" or link:sub(1, #URL_LINK_PREFIX) ~= URL_LINK_PREFIX then return end
        OpenFromLink(link, button)
        if ItemRefTooltip and ItemRefTooltip:IsShown() then ItemRefTooltip:Hide() end
    end)
    CU.clickPath = "SetItemRef"
end

-- =====================================================================
-- 6. 채팅 이벤트 필터 등록
-- =====================================================================
local CHAT_EVENTS = {
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING",           -- 공격대 경보(/rw)
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_COMMUNITIES_CHANNEL",
}

local function ChatMessageURLFilter(self, event, msg, ...)
    if not CU.IsEnabled() then return false end
    local text = PublicString(msg)
    if not text then return false end

    local newMsg, changed = CU.FormatURLsInMessage(text)
    if changed then
        return false, newMsg, ...
    end
    return false
end

for _, event in ipairs(CHAT_EVENTS) do
    ChatFrame_AddMessageEventFilter(event, ChatMessageURLFilter)
end

-- =====================================================================
-- 7. 모듈 초기화
-- =====================================================================
function CU.Init()
    if not MimDiceDB then MimDiceDB = {} end
    if not MimDiceDB.chatURL then
        MimDiceDB.chatURL = { enabled = true }
    end
end

local loaderFrame = CreateFrame("Frame")
loaderFrame:RegisterEvent("ADDON_LOADED")
loaderFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "MimDice" then
        CU.Init()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
