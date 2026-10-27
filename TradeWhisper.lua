-- 거래창이 닫혀도 마지막 내역은 서버의 완료 메시지가 올 때까지 보존한다.
local TW = {}
MimDiceTradeWhisper = TW
local frame = CreateFrame("Frame")
local session
local generation = 0
local outbox, sending = {}, false
local function L(key) return MimDice_L(key) end

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
    if not name or name == "" then return nil end
    return realm and realm ~= "" and (name .. "-" .. realm) or name
end

local function Capture()
    local nextSnap = { target = session.target or TargetName(), gave = {}, got = {} }
    nextSnap.playerMoney = Number(GetPlayerTradeMoney())
    nextSnap.targetMoney = Number(GetTargetTradeMoney())
    if not nextSnap.playerMoney or not nextSnap.targetMoney then return nil end
    for slot = 1, 7 do
        local name, _, count, _, enchant = GetTradePlayerItemInfo(slot)
        local other, _, otherCount, _, _, otherEnchant = GetTradeTargetItemInfo(slot)
        if slot == 7 then
            -- 7번 슬롯의 물건은 이동하지 않는다. 내 물건에 받은 마부는 '받음'이다.
            enchant, otherEnchant = Public(enchant, "string"), Public(otherEnchant, "string")
            if enchant and enchant ~= "" then nextSnap.got[#nextSnap.got + 1] = L("Enchant: ") .. enchant end
            if otherEnchant and otherEnchant ~= "" then nextSnap.gave[#nextSnap.gave + 1] = L("Enchant: ") .. otherEnchant end
        else
            local function Add(items, itemName, itemCount)
                if type(issecretvalue) == "function" and issecretvalue(itemName) then error("unreadable trade item") end
                itemName = Public(itemName, "string")
                if not itemName or itemName == "" then return end
                itemCount = Number(itemCount)
                if not itemCount then error("unreadable trade count") end
                items[#items + 1] = itemName .. (itemCount > 1 and (" x" .. string.format("%.0f", itemCount)) or "")
            end
            Add(nextSnap.gave, name, count)
            Add(nextSnap.got, other, otherCount)
        end
    end
    return nextSnap
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
        -- 평문 이름으로 구성한다. UTF-8 문자 중간을 자르거나 링크를 훼손하지 않는다.
        if #prefix + #token > 250 then
            local shortened = token:sub(1, 250 - #prefix - 3)
            shortened = shortened:gsub("[\194-\244][\128-\191]*$", "")
            token = shortened .. "..."
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

local function RaidHandlesWhisper()
    return MimRaid and MimRaid.TradeAnnounce and MimRaid.cfg and MimRaid.cfg.tradeWhisperEnabled ~= false
end

local function Pump()
    if not MimDiceDB.tradeWhisperEnabled or RaidHandlesWhisper() then
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
        if send then send(item.message, "WHISPER", nil, item.target) end
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
    session = nil -- 중복 완료 신호가 와도 다시 보내지 않는다.
    if not completed or not completed.snapshot or RaidHandlesWhisper() then return end
    if completed.closedAt and GetTime() - completed.closedAt > 5 then return end
    local snap = completed.snapshot
    if not snap.target then return end
    local messages = BuildMessages(snap)
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
        session = { target = TargetName() }
    elseif event == "TRADE_REQUEST_CANCEL" then
        session = nil
    elseif event == "TRADE_CLOSED" then
        if session and not session.closedAt then session.closedAt = GetTime() end
    elseif event == "TRADE_ACCEPT_UPDATE" then
        if not session or session.closedAt then return end
        if Number(first) ~= 1 and Number(second) ~= 1 then session.snapshot = nil; return end
        -- 성공은 수락 여부로 추측하지 않고 UI_INFO_MESSAGE에서만 확정한다.
        local ok, snap = pcall(Capture)
        session.snapshot = ok and snap or nil
    elseif event == "UI_INFO_MESSAGE" or event == "UI_ERROR_MESSAGE" then
        local name
        first = Number(first)
        if first and GetGameMessageInfo then
            local ok, value = pcall(GetGameMessageInfo, first)
            if ok then name = Public(value, "string") end
        end
        second = Public(second, "string")
        if name == "ERR_TRADE_CANCELLED" or (second and second == ERR_TRADE_CANCELLED) then session = nil
        elseif event == "UI_INFO_MESSAGE" and (name == "ERR_TRADE_COMPLETE" or (second and second == ERR_TRADE_COMPLETE)) then Complete()
        elseif event == "UI_ERROR_MESSAGE" and name and name:match("^ERR_TRADE_") then session = nil end
    elseif session and not session.closedAt then
        -- 내용 변경 후에는 다음 수락 시점의 새 스냅샷만 사용한다.
        session.snapshot = nil
    end
end)
frame:RegisterEvent("ADDON_LOADED")
