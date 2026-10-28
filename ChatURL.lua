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
local function SplitTrailingPunctuation(url)
    local trailing = ""

    -- WoW 특수 시퀀스(|r, |c 등)가 URL 뒤에 붙은 경우 분리
    local pipePos = url:find("|")
    if pipePos then
        trailing = url:sub(pipePos) .. trailing
        url = url:sub(1, pipePos - 1)
    end

    local openParen = select(2, url:gsub("%(", ""))
    local closeParen = select(2, url:gsub("%)", ""))
    local openBracket = select(2, url:gsub("%[", ""))
    local closeBracket = select(2, url:gsub("%]", ""))

    while #url > 0 do
        local last = url:sub(-1)
        if last:find("[.,;:!?]") then
            trailing = last .. trailing
            url = url:sub(1, -2)
        elseif last == ")" and closeParen > openParen then
            trailing = last .. trailing
            url = url:sub(1, -2)
            closeParen = closeParen - 1
        elseif last == "]" and closeBracket > openBracket then
            trailing = last .. trailing
            url = url:sub(1, -2)
            closeBracket = closeBracket - 1
        elseif last:find("[}>\"']") then
            trailing = last .. trailing
            url = url:sub(1, -2)
        else
            break
        end
    end
    return url, trailing
end

local function FormatOneURL(url)
    local u, trailing = SplitTrailingPunctuation(url)
    if #u == 0 then return url end
    -- 하이퍼링크 태그 파이프 이스케이프
    local escaped = u:gsub("|", "||")
    -- 전용 하이퍼링크 접두사 mimdiceurl: 사용 (|cff149bfd 하늘색 링크)
    return "|cff149bfd|Hmimdiceurl:" .. escaped .. "|h[" .. u .. "]|h|r" .. trailing
end

local function FormatURLsInPlainText(text)
    -- 깨진 링크 구간(|H 또는 |h가 닫히지 않고 남아있음)은 보수적으로 변환하지 않고 보존
    if text:find("|[Hh]") then
        return text
    end

    local low = text:lower()
    if not (low:find("://") or low:find("www%.") or low:find("discord%.gg/") or low:find("discord%.com/invite/")) then
        return text
    end

    -- 공백 기준 단어 매칭 및 대소문자 무관 접두사 인식 (원문의 대소문자는 완전 보존)
    local result = text:gsub("(%S+)", function(word)
        -- 1. http:// or https:// (대소문자 무관)
        local prefix, url = word:match("^(.-)([hH][tT][tT][pP][sS]?://%S+)$")
        if not url then
            -- 2. www. (대소문자 무관)
            prefix, url = word:match("^(.-)([wW][wW][wW]%.%S+)$")
        end
        if not url then
            -- 3. discord.gg/ (대소문자 무관)
            prefix, url = word:match("^(.-)([dD][iI][sS][cC][oO][rR][dD]%.[gG][gG]/%S+)$")
        end
        if not url then
            -- 4. discord.com/invite/ (대소문자 무관)
            prefix, url = word:match("^(.-)([dD][iI][sS][cC][oO][rR][dD]%.[cC][oO][mM]/[iI][nN][vV][iI][tT][eE]/%S+)$")
        end

        if url then
            return prefix .. FormatOneURL(url)
        end
        return word
    end)
    return result
end

local function FindNextHyperlink(s, startPos)
    local s1, e1 = s:find("|c%x%x%x%x%x%x%x%x|H.-|h.-|h|r", startPos)
    local s2, e2 = s:find("|H.-|h.-|h", startPos)
    if s1 and s2 then
        if s1 <= s2 then return s1, e1 end
        return s2, e2
    elseif s1 then
        return s1, e1
    elseif s2 then
        return s2, e2
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
-- 5. 하이퍼링크 클릭 처리 (중복 방지, 좌클릭 전용, 전용 mimdiceurl: 처리)
-- =====================================================================
local lastClickTime = 0
local lastClickURL = nil

local function HandleMimDiceURLClick(rawLink, text, button)
    -- 1. 활성화 여부 확인
    if not CU.IsEnabled() then return false end

    -- 2. 마우스 왼쪽 버튼 클릭만 허용 (우클릭 등 배제)
    if button and button ~= "" and button ~= "LeftButton" then
        return false
    end

    -- 3. 링크 타입 및 유효성 확인 ("mimdiceurl:" 접두사는 11글자)
    local link = PublicString(rawLink)
    if not link or link:sub(1, 11) ~= "mimdiceurl:" then
        return false
    end

    -- 4. 11번째 글자 이후(12번째부터)가 실제 URL 본문
    local u = link:sub(12):gsub("||", "|")
    if not u or u == "" then return false end

    -- 5. 동일 프레임/시점 중복 호출 방지 가드 (LinkUtil과 SetItemRef 동시 실행 차단)
    local now = (GetTime and GetTime()) or 0
    if now == lastClickTime and lastClickURL == u then
        return true
    end
    lastClickTime = now
    lastClickURL = u

    -- 6. 복사창 열기
    CU.ShowCopyBox(u)

    -- 7. 불필요하게 뜬 빈 툴팁 닫기
    if ItemRefTooltip and ItemRefTooltip:IsShown() then
        ItemRefTooltip:Hide()
    end
    return true
end

-- LinkUtil 등록
if LinkUtil and LinkUtil.RegisterLinkHandler and LinkUtil.IsLinkHandlerRegistered then
    if not LinkUtil.IsLinkHandlerRegistered("mimdiceurl") then
        LinkUtil.RegisterLinkHandler("mimdiceurl", function(link, text, button)
            HandleMimDiceURLClick(link, text, button)
        end)
    end
end

-- SetItemRef 보안 후킹 (LinkUtil이 없는 환경 또는 추가 보완용)
if hooksecurefunc then
    hooksecurefunc("SetItemRef", function(link, text, button, chatFrame)
        HandleMimDiceURLClick(link, text, button)
    end)
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
