-- Author      : BIK
-- Create Date : 2023-01-28 오후 7:11:08
-- 리로드할때 /rl 만 쳐도 됨
SLASH_RELOAD3 = "/rl" -- 영어 줄임말
SLASH_RELOAD2 = "/리" -- 한글 줄임말
SLASH_RELOAD1 = "/fl" -- 영어 오타
SLASH_RELOAD4 = "/기" -- 한글 오타
SLASH_RELOAD5 = "/리로드" -- 한글 풀네임
SlashCmdList["RELOAD"] = ReloadUI -- 실제 함수 동작 부분
-------------------------------------------------------------------------------------------

---@diagnostic disable: undefined-global, param-type-mismatch, undefined-field, cast-local-type -- global 함수 정의에러 무시
local TOCNAME, Mim = ...
local L = setmetatable({}, {
    __index = function(_, k)
        return Mim.L[k]
    end
})

-- 최대파티 수
Mim.MAXRARITY = 6
-- 와우 클래식용
Mim.CLASSIC_ERA = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
Mim.BCC = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC


-- 플레이어 가져오기
function Mim.GetPlayerList(unsort)
    local count, start
    local prefix
    local ret = {}
    local retName = {}

	-- 레이드 인지 확인하고 레이드면 앞에 "raid" 붙이기 레이드는 1부터 시작
    if IsInRaid() then
        prefix = "raid"
        count = MAX_RAID_MEMBERS
        start = 1
    else -- 파티 붙이기 파티는 0부터 시작
        prefix = "party"
        count = MAX_PARTY_MEMBERS
        start = 0
    end


	-- 말머리 + 플레이어로 설정
    for index = start, count do
        local guildName, guildRankName
        local id
        if index > 0 then
            id = prefix .. index
        else
            id = "player"
        end

		-- 이름이랑 클래스 확인
        local name = GetUnitName(id)
        local _, englishClass = UnitClass(id)


		-- 길드 내 랭크 권한 확인
        local rank = ""
        if IsInGuild() and UnitIsInMyGuild(id) then
            rank = "<" .. GuildControlGetRankName(C_GuildInfo.GetGuildRankOrder(UnitGUID(id))) .. ">"
        else
            guildName, guildRankName = GetGuildInfo(id)
            if guildName and guildRankName then
                rank = "<" .. guildName .. " / " .. guildRankName .. ">"
            end
        end

		-- 이름이 비어있지 않으면
        if name ~= nil then

			-- 이름, 랭크, 직업 등록
            local entry = {
                ["name"] = name,
                ["rank"] = rank,
                ["class"] = englishClass,
            }
            tinsert(ret, entry)
            retName[name] = entry
        end
    end

	-- 정렬이 안되어 있으면 정렬
    if unsort then
        sort(ret, function(a, b) return (a.class < b.class or (a.class == b.class and a.name < b.name)) end)
    end
	-- 플레이어 리스트, 이름 반환
    return ret, retName
end


-- Init
function Mim.Init()
	-- 다국어 지원
    L = Mim.GetLocale()
	
	-- 로딩되면 기본적으로 Up 정렬
	UpBtn:SetChecked(true)

	-- 이벤트 수신
	Mim.Tool.RegisterEvent("ADDON_LOADED", Event_ADDON_LOADED)
	Mim.Tool.RegisterEvent("CHAT_MSG_SYSTEM", Event_CHAT_MSG_SYSTEM)

	-- 테이블 생성
    Mim.rollArray = {}
    Mim.rollNames = {}

    -- using strings from GlobalStrings.lua
    Mim.PatternRoll = Mim.Tool.CreatePattern(RANDOM_ROLL_RESULT)

    -- settings
    if not MimDiceDB then MimDiceDB = {} end -- fresh DB
	Mim.DB = MimDiceDB
    local x, y, w, h = Mim.DB.X, Mim.DB.Y, Mim.DB.Width, Mim.DB.Height
    if not x or not y or not w or not h then
        Mim.SaveAnchors()
    else
        MainWindow:ClearAllPoints()
        MainWindow:SetPoint("TOPLEFT", SharedTooltipTemplate, "BOTTOMLEFT", x, y)
        MainWindow:SetWidth(w)
        MainWindow:SetHeight(h)
    end

    -- 슬래시 커맨드
	SLASH_MIMDICE1 = "/mimdice"
	SLASH_MIMDICE2 = "/md"
	SLASH_MIMDICE3 = "/밈"
	SLASH_MIMDICE4 = "/ala"
	SLASH_MIMDICE5 = "/밈주사위"
	SlashCmdList["MIMDICE"] = function (msg)
		-- 주사위 창 띄우기
			MimDice_ShowWindow()
    Mim.Tool.OnUpdate(Mim.Timers)
	end
end


-- 로딩
local function Event_ADDON_LOADED(arg1)
    if arg1 == TOCNAME then
        Mim.Init()
    end
    Mim.Tool.AddDataBrocker(Mim.IconDice, Mim.MenuButtonClick, Mim.MenuToolTip)
end

local function Event_START_LOOT_ROLL(arg1, _, arg3)
    --START_LOOT_ROLL: rollID, rollTime, lootHandle
    if Mim.DB.AutoLootRolls then
        Mim.LootHistoryShow(arg1)
    end
    if arg3 then -- loothandle CAN be nil
        Mim.LootHistoryHandle[arg3] = true
        Mim.LootHistoryCountHandle = Mim.LootHistoryCountHandle + 1
    end
    Mim.LootHistoryCloseTimer = 0
end

local function Event_LOOT_ROLLS_COMPLETE(arg1)
    --LOOT_ROLLS_COMPLETE: lootHandle
    if Mim.LootHistoryHandle[arg1] == true then
        Mim.LootHistoryHandle[arg1] = nil
        Mim.LootHistoryCountHandle = Mim.LootHistoryCountHandle - 1
        if Mim.LootHistoryCountHandle <= 0 then
            Mim.LootHistoryCountHandle = 0
            wipe(Mim.LootHistoryHandle)
            Mim.LootHistoryCloseTimer = time() + (Mim.DB.AutoCloseDelay or 5)
        end
    end
end

local function Event_CHAT_MSG_SYSTEM(arg1)
    for name, roll, min, max in string.gmatch(arg1, Mim.PatternRoll) do
        --출력(".."..이름.." "..현재주사위.." "..최소값.." "..최대값)
        Mim.AddRoll(name, roll, min, max)
    end
end

function Mim.AddRoll(name, roll, min, max)
    local ok = false
    if name == "*" then
        for i = 1, 5 do
            Mim.AddRoll("rndneed" .. i, tostring(random(1, 100)), "1", "100")
            Mim.AddRoll("rndgreed" .. i, tostring(random(1, 50)), "1", "50")
        end
        return
    end

    if Mim.IsRaidRoll and min == "1" and tonumber(max) == #Mim.IsRaidRoll and name == GetUnitName("player") then
        roll = tonumber(roll)
        Mim.AddChat(Mim.MSGPREFIX .. string.format(L["MsgRaidRoll"], Mim.IsRaidRoll[roll].name, roll))
        Mim.IsRaidRoll = nil
        return
    end

    if not Mim.AllowInInstance() then
        return
    end

    -- 두번굴림 확인 전에 굴렸으면 1이상으로 표시
    if Mim.DB.NeedAndGreed then
        if (Mim.DB.IgnoreDouble == false or rollNames[name] == nil or rollNames[name] == 0) and
                ((low == "1" and high == "50") or (low == "1" and high == "100")) then
            ok = true
        end
    else
        if (Mim.DB.IgnoreDouble == false or rollNames[name] == nil or rollNames[name] == 0) and
                (Mim.DB.RejectOutBounds == false or (low == "1" and high == "100")) then
            ok = true
        end
    end

    if ok then

        if Mim.DB.PromoteRolls and tonumber(roll) == 69 then
            roll = "101"
        end

        rollNames[name] = rollNames[name] and rollNames[name] + 1 or 1
        table.insert(rollArray, {
            Name = name,
            Roll = tonumber(roll),
            Min = tonumber(min),
            Max = tonumber(max),
            Count = rollNames[name]
        })

        Mim.ShowWindow(1)

        if Mim.allRolled and Mim.DB.AutmaticAnnounce then
            Mim.BtnAnnounce()
        elseif Mim.Countdown then
            Mim.StartCountdown(Mim.DB.CDRefresh)
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage(string.format(RMimTC.MSGPREFIX .. L["MsgCheat"], name, roll, min, max), Mim.DB.ColorChat.r, Mim.DB.ColorChat.g, Mim.DB.ColorChat.b, Mim.DB.ColorChat.a)
    end
end

		-- 주사위 몇명 굴렸는지에 대한 기본설정값
		-- ["%d Roll(s)"] = "%d Roll(s)",
		-- 주사위가 초기화 되었다는 메세지에 대한 기본설정값
		-- ["All rolls have been cleared."] = "All rolls have been cleared."

		







-- Event handler



-- -- 이벤트 핸들러
-- function MimDice_CHAT_MSG_SYSTEM(msg)

-- 	-- GlobalStrings 이용해서 이름,주사위,최소값,최대값 불러오는 부분
-- 	for name, roll, minRoll, maxRoll in string.gmatch(msg, pattern) do
-- 	-- 두번 굴림 확인. 한번 굴렸으면 1 이상이 됨.
-- 		rollNames[name] = rollNames[name] and rollNames[name] + 1 or 1
-- 	-- rollArray 테이블에 데이터 입력
-- 	 	table.insert(rollArray, {
-- 			-- 이름
-- 			Name = name,
-- 			-- 주사위 값
-- 			Roll = tonumber(roll),
-- 			-- 주사위 최소값	
-- 			Min = tonumber(minRoll),
-- 			-- 주사위 최대값
-- 			Max = tonumber(maxRoll),
-- 			-- 몇명굴렸는지 카운트
-- 			Count = rollNames[name]
-- 		}) 
-- 		-- 이벤트 수신하면 창 띄우기
-- 		MimDice_ShowWindow()
-- 	end
-- end



-- 높은수 버튼 한번 누르면 비활성화
function Sort_Up()
	UpBtn:SetChecked(true)
	DownBtn:SetChecked(false)
	UpBtn:Disable()
	DownBtn:Enable()
	MimDice_UpdateList()
end

-- 낮은수 버튼 한번 누르면 비활성화
function Sort_Down()
	DownBtn:SetChecked(true)
	UpBtn:SetChecked(false)
	DownBtn:Disable()
	UpBtn:Enable()
	MimDice_UpdateList()
end

-- 정렬버튼 고르기 내용 부분
function Choice_Sort(a, b)
	if UpBtn:GetChecked(true) then
		return a.Roll < b.Roll
	elseif DownBtn:GetChecked(true) then
		return a.Roll > b.Roll
	end
end



function Mim.FormatRollText(roll, _, partyName)
	local Num_Dice = DiceEditBox:GetText()
    local colorTied = Mim.Tool.RGBtoEscape(Mim.DB.ColorNormal)
    local colorCheat = ((roll.Min ~= 1 or roll.Max ~= Num_Dice) or (roll.Count > 1)) and Mim.Tool.RGBtoEscape(Mim.DB.ColorCheat) or colorTied
    
    local colorName
    local iconClass
    local colorRank = Mim.Tool.RGBtoEscape(Mim.DB.ColorGuild)
    local rank = ""

    if partyName[roll.Name] and partyName[roll.Name].class then
        colorName = "|c" .. RAID_CLASS_COLORS[partyName[roll.Name].class].colorStr
        iconClass = Mim.Tool.IconClass[partyName[roll.Name].class]
    end
    if colorName == nil or Mim.DB.ColorName == false then colorName = colorCheat end
    if iconClass == nil or Mim.DB.ShowClassIcon == false then iconClass = "" end
    if Mim.DB.ColorName == false then colorRank = colorCheat end

    if Mim.DB.ShowGuildRank and partyName[roll.Name] and partyName[roll.Name].rank then
        rank = " " .. partyName[roll.Name].rank
    end

    local txtCount = roll.Count > 1 and format(" [%d]", roll.Count) or ""

    return "|Hplayer:" .. roll.Name .. "|h" ..
            colorTied .. string.format("%3d", roll.Roll) .. ": " ..
            iconClass .. colorName .. roll.Name .. colorRank .. rank .. "|r " ..
            colorCheat .. txtRange .. "|r " ..
            colorCheat .. txtCount .. "|h\n"
end


function Mim.UpdateRollList()
    local rollText = ""

    local party, partyName = Mim.GetPlayerList()

    table.sort(rollArray, Choice_Sort)

    -- 포맷 설정 및 주사위 출력, 동점 확인
    if Mim.DB.NeedAndGreed then
        local rtxt = ""
        rollText = Mim.Tool.RGBtoEscape(Mim.DB.ColorInfo) .. L["TxtNeed"] .. "\n" .. rtxt
        rtxt = ""
        rollText = rollText .. "\n" .. Mim.Tool.RGBtoEscape(Mim.DB.ColorInfo) .. L["TxtGreed"] .. "\n" .. rtxt
    else
        for _, roll in pairs(rollArray) do
            rollText = Mim.FormatRollText(roll, party, partyName) .. rollText
        end
    end

    if IsInGroup() then
        rollText = rollText .. Mim.Tool.RGBtoEscape(Mim.DB.ColorInfo) .. L["TxtLine"] .. "\n"
        local gtxt = Mim.Tool.RGBtoEscape(Mim.DB.ColorInfo)
        local missClasses = {}
        Mim.allRolled = true
        for _, p in ipairs(party) do
            if rollNames[p.name] == nil or rollNames[p.name] == 0 then
                local iconClass = Mim.Tool.IconClass[partyName[p.name].class]
                local rank = ""
                if iconClass == nil or Mim.DB.ShowClassIcon == false then
                    iconClass = ""
                else
                    missClasses[partyName[p.name].class] = missClasses[partyName[p.name].class] and missClasses[partyName[p.name].class] + 1 or 1
                end
                if Mim.DB.ShowGuildRank and partyName[p.name] and partyName[p.name].rank then
                    rank = " " .. partyName[p.name].rank
                end
                gtxt = gtxt .. "|Hplayer:" .. p.name .. "|h" .. iconClass .. p.name .. rank .. "|h\n"
                Mim.allRolled = false
            end
        end
        local ctxt = ""
        if Mim.CLASSIC_ERA then
            local isHorde = (UnitFactionGroup("player")) == "Horde"
            for _, class in pairs(Mim.Tool.Classes) do
                --클래스 카운트하고 호드 주술사, 얼라이언스 성기사 체크
                if not (isHorde and class == "PALADIN") and not (not isHorde and class == "SHAMAN") then
                    ctxt = ctxt .. Mim.Tool.IconClass[class] .. (missClasses[class] or 0) .. " "
                end
            end
            if ctxt ~= "" then ctxt = ctxt .. "\n" .. L["TxtLine"] .. "\n" end
        end

        rollText = rollText .. ctxt .. gtxt
    end

	-- 롤스트링 스크롤프레임에 rollText 입력
    RollStrings:SetText(rollText)
	-- 몇명 굴렸는지 입력
	MimDiceStatusTextFrame:SetText(string.format(L["%d Roll(s)"], table.getn(rollArray)))
end


-- function Mim.NotRolled()
--     if IsInGroup() or IsInRaid() then
--         local party = Mim.GetPlayerList()
--         local names = ""
--         for _, p in ipairs(party) do
--             if Mim.rollNames[p.name] == nil or Mim.rollNames[p.name] == 0 then
--                 names = names .. ", " .. p.name
--             end
--         end
--         names = string.sub(names, 3)

--         if names ~= "" then
--             Mim.AddChat(Mim.MSGPREFIX .. string.format(L["MsgNotRolled"], L["pass"]))
--             Mim.AddChat(names)
--         end
--     end
-- end

-- function Mim.RollAnnounce(numbers)
--     local winNum = 0
--     local winName = ""
--     local max = -1
--     local addPrefix = ""
--     local msg = ""
--     local list = {}
--     numbers = (tonumber(numbers) or Mim.DB.AnnounceList or 1)
--     if numbers == 1 then numbers = 0 end

--     table.sort(Mim.rollArray, Mim.SortRollsRev)

--     if Mim.DB.NeedAndGreed then
--         for _, roll in pairs(Mim.rollArray) do
--             if (Mim.DB.AnnounceIgnoreDouble == false or roll.Count == 1) and
--                     (roll.Roll > 0 and roll.Low == 1 and roll.High == 100) then
--                 if roll.Roll == max then
--                     winNum = winNum + 1
--                     winName = winName .. ", " .. roll.Name
--                 elseif roll.Roll > max then
--                     max = roll.Roll
--                     winNum = 1
--                     winName = roll.Name
--                 end
--                 if numbers > 0 then
--                     numbers = numbers - 1
--                     tinsert(list, roll.Roll .. " " .. roll.Name .. " (" .. roll.Low .. "-" .. roll.High .. ")")
--                 end
--             end
--         end

--         if winNum == 0 then
--             for _, roll in pairs(Mim.rollArray) do
--                 if (Mim.DB.AnnounceIgnoreDouble == false or roll.Count == 1) and
--                         (roll.Roll == 0 or (roll.Low == 1 and roll.High == 50)) then

--                     if roll.Roll == max then
--                         winNum = winNum + 1
--                         winName = winName .. ", " .. roll.Name
--                     elseif roll.Roll > max then
--                         max = roll.Roll
--                         winNum = 1
--                         winName = roll.Name
--                     end
--                     if numbers > 0 then
--                         numbers = numbers - 1
--                         tinsert(list, roll.Roll .. " " .. roll.Name .. " (" .. roll.Low .. "-" .. roll.High .. ")")
--                     end
--                 end
--             end
--             addPrefix = L["TxtGreed"] .. "! "
--         else
--             addPrefix = L["TxtNeed"] .. "! "
--         end

--     else
--         for _, roll in pairs(Mim.rollArray) do

--             if (Mim.DB.AnnounceIgnoreDouble == false or roll.Count == 1) and
--                     (Mim.DB.AnnounceRejectOutBounds == false or (roll.Low == 1 and roll.High == 100)) then

--                 if roll.Roll == max and roll.Roll ~= 0 then
--                     winNum = winNum + 1
--                     winName = winName .. ", " .. roll.Name
--                 elseif roll.Roll > max and roll.Roll ~= 0 then
--                     max = roll.Roll
--                     winNum = 1
--                     winName = roll.Name
--                 end
--                 if numbers > 0 then
--                     numbers = numbers - 1
--                     tinsert(list, roll.Roll .. " " .. roll.Name .. " (" .. roll.Low .. "-" .. roll.High .. ")")
--                 end
--             end
--         end
--     end

--     if winNum == 1 and Mim.lastItem == nil then
--         msg = Mim.MSGPREFIX .. addPrefix .. string.format(L["MsgAnnounce"], winName, max)
--     elseif winNum == 1 and Mim.lastItem ~= nil then
--         msg = Mim.MSGPREFIX .. addPrefix .. string.format(L["MsgAnnounceItem"], winName, Mim.lastItem, max)
--     elseif winNum > 1 and Mim.lastItem == nil then
--         msg = Mim.MSGPREFIX .. addPrefix .. string.format(L["MsgAnnounceTie"], winName, max)
--     elseif winNum > 1 and Mim.lastItem ~= nil then
--         msg = Mim.MSGPREFIX .. addPrefix .. string.format(L["MsgAnnounceTieItem"], winName, Mim.lastItem, max)
--     elseif Mim.Countdown then
--         msg = Mim.MSGPREFIX .. L["MsgForcedAnnounce"]
--     end

--     Mim.AddChat(msg)
--     for _, out in ipairs(list) do
--         Mim.AddChat(out)
--     end


--     Mim.StopCountdown()
-- end

-- 위치 저장
function MimDice_SaveAnchors()
	MimDiceDB.X = MainWindow:GetLeft()
	MimDiceDB.Y = MainWindow:GetTop()
	MimDiceDB.Width = MainWindow:GetWidth()
	MimDiceDB.Height = MainWindow:GetHeight()
end

-- 창 띄우기
function MimDice_ShowWindow()
	MainWindow:Show()
	MimDice_UpdateList()
end

-- 몇명 굴렸는지 확인
function RolledPerson(msg)
    MimDiceStatusTextFrame:SetText(msg)
end

-- 주사위 리셋
function MimDice_ClearRolls()
	rollArray = {}
	rollNames = {}
	DEFAULT_CHAT_FRAME:AddMessage(L["All rolls have been cleared."])
	MimDice_UpdateList()

end



-- 역할별 문장
function Prefix()
	local T_Prefix = "탱커님들 "
	local D_Prefix = "딜러님들 "
	local H_Prefix = "힐러님들 "
	local Dice_Text = "주사위 "
	local Space = " "
	local Num_Dice = DiceEditBox:GetText()
	local High_Text = "하이"
	local Low_Text = "로우"
	local Suffix = MainEditBox:GetText()
	local StartLine = "=============================="
	
	local Final_Text = ""
	
	local function T_Check()
		if TankCheckBox:GetChecked(true) then
			return T_Prefix
		else
			return ""
		end
	end

	local function D_Check()
		if DpsCheckBox:GetChecked(true) then
			return D_Prefix
		else
			return ""
		end
	end

	local function H_Check()
		if HealCheckBox:GetChecked(true) then
			return H_Prefix
		else
			return ""
		end
	end

	local function High_Check()
		if UpBtn:GetChecked(true) then
			return High_Text
		else
			return ""
		end
	end

	local function Low_Check()
		if DownBtn:GetChecked(true) then
			return Low_Text
		else
			return ""
		end
	end

	Final_Text = T_Check()  .. D_Check() .. H_Check() .. Dice_Text .. Num_Dice .. Space .. High_Check() .. Low_Check() .. Suffix
	

	local function SendMessage_ChoiceChannel()
		if IsInRaid() == true then
	 	SendChatMessage(Final_Text,"RAID_WARNING")  -- 레이드 공지로 얘기하기
	 	SendChatMessage(StartLine,"RAID_WARNING")	-- ======================= 줄 긋는 부분		

		elseif IsInRaid() == false and IsInGroup() == true then
			SendChatMessage(Final_Text,"INSTANCE_CHAT") -- 인던채팅으로 얘기하기
			SendChatMessage(StartLine,"INSTANCE_CHAT")	-- ======================= 줄 긋는 부분

		elseif IsInRaid() == false and IsInGroup() == false then
			SendChatMessage(Final_Text,"SAY")	-- 일반채팅으로 얘기하기
			SendChatMessage(StartLine,"SAY")	-- ======================= 줄 긋는 부분
		end
	end

	SendMessage_ChoiceChannel()
	
end


--local lastCountDown
-- function Mim.Timers()
--     if Mim.LootHistoryCloseTimer > 0 and Mim.LootHistoryCloseTimer < time() and Mim.LootHistoryCountHandle <= 0 then
--         if Mim.DB.AutoCloseLootRolls then
--             LootHistoryFrame_CollapseAll(LootHistoryFrame)
--             LootHistoryFrame:Hide()
--         end
--         Mim.LootHistoryCloseTimer = 0
--         Mim.LootHistoryCountHandle = 0
--     end

--     if Mim.Countdown ~= nil then
--         local sec = math.floor(Mim.Countdown - GetTime() + 0.999)
--         if sec > 5 then
--             sec = math.floor((sec + 9) / 10) * 10
--         end

--         if sec ~= lastCountDown then
--             lastCountDown = sec
--             if sec > 0 then
--                 Mim.AddChat(Mim.MSGPREFIX .. sec)
--             else
--                 Mim.RollAnnounce()
--                 Mim.lastItem = nil
--                 if Mim.DB.ClearOnAnnounce then
--                     Mim.ClearRolls()
--                 end
--                 if Mim.DB.CloseOnAnnounce then
--                     Mim.HideWindow()
--                 end
--                 Mim.Countdown = nil
--                 lastCountDown = nil
--             end
--         end
--     end
-- end

-- function Mim.StaMimountdown(x)
--     local ti = GetTime() + (x or Mim.DB.DefaultCD)
--     if Mim.Countdown == nil or Mim.Countdown < ti then
--         Mim.Countdown = ti
--     end
-- end

-- function Mim.StopCountdown()
--     Mim.Countdown = nil
-- end