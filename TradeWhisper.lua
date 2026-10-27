-- 거래창이 닫혀도 마지막 내역은 서버의 완료 메시지가 올 때까지 보존한다.
local TW = {}
MimDiceTradeWhisper = TW
local frame = CreateFrame("Frame")
local session
local generation = 0
local outbox, sending = {}, false
local trace = {}
local function L(key) return MimDice_L(key) end

local function Trace(reason)
    local snap = session and session.snapshot
    trace[#trace + 1] = string.format("%.2f %s [give=%d get=%d accepted=%s]", GetTime(), reason,
        snap and #snap.gave or 0, snap and #snap.got or 0,
        session and session.bothAccepted and "both" or "no")
    if #trace > 32 then table.remove(trace, 1) end
end

function TW.PrintDebug()
    for _, line in ipairs(trace) do DEFAULT_CHAT_FRAME:AddMessage("[MimDice Trade] " .. line) end
end

local function Public(value, kind)
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    if type(value) ~= kind then return nil end
    return value
end

local function Number(value)
    value = Public(value, "number")
    if not value or value ~= value or value < 0 or value == math.huge then return nil end
    return value
end

local function TargetName()
    local name, realm = UnitFullName("NPC")
    if type(issecretvalue) == "function" and issecretvalue(realm) then return nil end
    name, realm = Public(name, "string"), Public(realm, "string")
    if not name or name == "" then
        local full = GetUnitName and Public(GetUnitName("NPC", true), "string")
        return full and full ~= "" and full or nil
    end
    return realm and realm ~= "" and (name .. "-" .. realm) or name
end

local function Capture()
    local nextSnap = { target = session.target or TargetName(), gave = {}, got = {} }
    nextSnap.playerMoney = Number(GetPlayerTradeMoney())
    nextSnap.targetMoney = Number(GetTargetTradeMoney())
    if not nextSnap.playerMoney or not nextSnap.targetMoney then return nil end
    -- 실제로 주고받는 1~6번 슬롯만 기록한다. 7번 마법부여 서비스는 제외한다.
    local function Add(items, itemName, itemCount)
        if type(issecretvalue) == "function" and issecretvalue(itemName) then error("unreadable trade item") end
        itemName = Public(itemName, "string")
        if not itemName or itemName == "" then return end
        itemCount = Number(itemCount)
        if not itemCount then error("unreadable trade count") end
        items[#items + 1] = itemName .. (itemCount > 1 and (" x" .. string.format("%.0f", itemCount)) or "")
    end
    for slot = 1, 6 do
        local name, _, count = GetTradePlayerItemInfo(slot)
        local other, _, otherCount = GetTradeTargetItemInfo(slot)
        Add(nextSnap.gave, name, count)
        Add(nextSnap.got, other, otherCount)
    end
    return nextSnap
end

local function CanReadTrade()
    if TradeFrame and not TradeFrame:IsShown() then return false end
    if UnitExists and Public(UnitExists("NPC"), "boolean") == false then return false end
    return true
end

local function RefreshSnapshot(force)
    if not session or session.closedAt then return end
    -- 완료 직전 UI가 먼저 닫히면 API는 빈 슬롯을 반환할 수 있다.
    if not CanReadTrade() then Trace("snapshot: trade unavailable"); return end
    -- 양쪽 수락 뒤 발생하는 슬롯 정리는 최종 내역에 덮어쓰지 않는다.
    -- 실제 품목 변경은 수락 해제/재수락 이벤트에서 다시 읽는다.
    if session.bothAccepted and session.snapshot and not force then Trace("snapshot: accepted offer kept"); return end
    local ok, snap = pcall(Capture)
    session.snapshot = ok and snap or nil
    Trace(session.snapshot and "snapshot: captured" or "snapshot: unreadable")
end

local function Money(copper)
    return string.format(L("%.0fg %.0fs %.0fc"), math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

local function BuildMessages(snap)
    local tokens = {}
    if snap.targetMoney > 0 then tokens[#tokens + 1] = L("Received gold: ") .. Money(snap.targetMoney) end
    if snap.playerMoney > 0 then tokens[#tokens + 1] = L("Sent gold: ") .. Money(snap.playerMoney) end
    for _, item in ipairs(snap.got) do tokens[#tokens + 1] = L("Received: ") .. item end
    for _, item in ipairs(snap.gave) do tokens[#tokens + 1] = L("Sent: ") .. item end
    local messages, current = {}, L("[Trade complete] ")
    local prefix = current
    for _, token in ipairs(tokens) do
        -- 긴 이름도 생략하지 않고 UTF-8 문자 경계에서 나눠 기록한다.
        if #prefix + #token > 250 and current ~= prefix then
            messages[#messages + 1] = current
            current = prefix
        end
        while #prefix + #token > 250 do
            local cut = 250 - #prefix
            local byte = token:byte(cut + 1)
            while byte and byte >= 128 and byte <= 191 do
                cut = cut - 1
                byte = token:byte(cut + 1)
            end
            messages[#messages + 1] = prefix .. token:sub(1, cut)
            token = token:sub(cut + 1)
        end
        local joined = current .. (current ~= prefix and " / " or "") .. token
        if #joined > 250 then
            messages[#messages + 1] = current
            current = prefix .. token
        else current = joined end
    end
    if current ~= prefix then messages[#messages + 1] = current end
    return messages
end

local function Pump()
    if not MimDiceDB.tradeWhisperEnabled then
        outbox, sending = {}, false
        return
    end
    while outbox[1] and GetTime() >= outbox[1].expires do table.remove(outbox, 1) end
    if not outbox[1] then sending = false; return end
    local locked
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        locked = C_ChatInfo.InChatMessagingLockdown()
    else
        locked = IsEncounterInProgress and IsEncounterInProgress()
    end
    if not locked then
        local item = table.remove(outbox, 1)
        local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
        if send then send(item.message, "WHISPER", nil, item.target); Trace("whisper: send called") end
    end
    -- 긴 내역은 1초 간격으로 전송한다. 제한 중인 내역은 최대 2분 대기한다.
    if #outbox > 0 then
        sending = true
        local expected = generation
        C_Timer.After(1, function() if generation == expected then Pump() end end)
    else sending = false end
end

local function Complete()
    local completed = session
    Trace("server: complete")
    session = nil -- 중복 완료 신호가 와도 다시 보내지 않는다.
    if not completed or not completed.snapshot then return end
    if completed.closedAt and GetTime() - completed.closedAt > 5 then return end
    local snap = completed.snapshot
    if not snap.target then return end
    local messages = BuildMessages(snap)
    Trace("receipt chunks: " .. #messages)
    for _, message in ipairs(messages) do
        outbox[#outbox + 1] = { message = message, target = snap.target, expires = GetTime() + 120 }
    end
    if not sending then Pump() end
end

local events = { "TRADE_SHOW", "TRADE_CLOSED", "TRADE_ACCEPT_UPDATE", "TRADE_REQUEST_CANCEL",
    "TRADE_MONEY_CHANGED", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE" }

function TW.ApplySettings()
    generation = generation + 1
    session = nil
    outbox, sending = {}, false
    for _, event in ipairs(events) do
        if MimDiceDB and MimDiceDB.tradeWhisperEnabled then frame:RegisterEvent(event)
        else frame:UnregisterEvent(event) end
    end
end

frame:SetScript("OnEvent", function(_, event, first, second)
    if event == "ADDON_LOADED" then
        if Public(first, "string") ~= "MimDice" then return end
        MimDiceDB = MimDiceDB or {}
        if MimDiceDB.tradeWhisperEnabled == nil then MimDiceDB.tradeWhisperEnabled = false end
        frame:UnregisterEvent("ADDON_LOADED")
        TW.ApplySettings()
    elseif event == "TRADE_SHOW" then
        trace = {}
        session = { target = TargetName() }
        Trace(event)
        RefreshSnapshot()
    elseif event == "TRADE_REQUEST_CANCEL" then
        Trace(event)
        session = nil
    elseif event == "TRADE_CLOSED" then
        Trace(event)
        if session and not session.closedAt then session.closedAt = GetTime() end
    elseif event == "TRADE_ACCEPT_UPDATE" then
        if not session or session.closedAt then return end
        if not CanReadTrade() then Trace(event .. ": trade unavailable"); return end
        session.bothAccepted = Number(first) == 1 and Number(second) == 1
        Trace(event)
        -- 수락 상태 값/거래 방향과 무관하게 내역을 보존한다. 성공은 서버 신호로만 확정한다.
        RefreshSnapshot(true)
    elseif event == "UI_INFO_MESSAGE" or event == "UI_ERROR_MESSAGE" then
        local name
        first = Number(first)
        if first and GetGameMessageInfo then
            local ok, value = pcall(GetGameMessageInfo, first)
            if ok then name = Public(value, "string") end
        end
        second = Public(second, "string")
        if name then Trace(event .. ": " .. name) end
        if name == "ERR_TRADE_CANCELLED" or (second and second == ERR_TRADE_CANCELLED) then session = nil
        elseif event == "UI_INFO_MESSAGE" and (name == "ERR_TRADE_COMPLETE" or (second and second == ERR_TRADE_COMPLETE)) then Complete() end
        -- 거래 중 아이템을 올리지 못한 오류 등은 취소가 아니다. 수정 뒤 같은 거래가 완료될 수 있다.
    elseif session and not session.closedAt then
        Trace(event)
        RefreshSnapshot()
    end
end)
frame:RegisterEvent("ADDON_LOADED")
