-- Author      : BIK
-- Create Date : 2023-01-28 오후 7:11:08

---@diagnostic disable: undefined-global, param-type-mismatch, undefined-field, cast-local-type -- global 함수 정의에러 무시

-- 리로드할때 /rl 만 쳐도 됨
SLASH_RELOAD3 = "/rl"
SLASH_RELOAD2 = "/리"
SLASH_RELOAD1 = "/fl" -- 영어 오타
SLASH_RELOAD4 = "/기" -- 한글 오타
SLASH_RELOAD5 = "/리로드" -- 한글 풀네임
SlashCmdList["RELOAD"] = ReloadUI -- 실제 함수 동작 부분
-------------------------------------------------------------------------------------------

-- 테이블 생성
local rollArray
local rollNames
local EnglishClass

-- 라이브러리 불러오기
local LibDB		= LibStub("LibDataBroker-1.1")
local LibDBIcon	= LibStub("LibDBIcon-1.0")
-- local LibWindow = LibStub("LibWindow-1.1")


-- 이벤트 프레임 생성
local MimFrame = CreateFrame("frame")
MimFrame:RegisterEvent("CHAT_MSG_SYSTEM")
MimFrame:RegisterEvent("ADDON_LOADED")

MimFrame:SetScript("OnEvent", function(self, event, ...)
	local msg = ...
	if (event == "ADDON_LOADED" and msg == "MimDice") then
		self:UnregisterEvent("ADDON_LOADED")
		MimDice_OnLoad(self)
	elseif (event == "CHAT_MSG_SYSTEM") then
		MimDice_CHAT_MSG_SYSTEM(msg);
	end
end)


-- /주사위 했을 때 나오는 문자열 정리 
-- RollTrackerClassic GlobalStrings 에서 값 가져옴.
local pattern = string.gsub(RANDOM_ROLL_RESULT, "[%(%)-]", "%%%1")
pattern = string.gsub(pattern, "%%s", "(.+)")
pattern = string.gsub(pattern, "%%d", "%(%%d+%)")


-- 다국어지원
local locales = {
	koKR = {
		["All rolls have been cleared."] = "주사위가 초기화 되었습니다.",
		["%d Roll(s)"] = "%d 명 굴림",
	},
	esES = {
		["All rolls have been cleared."] = "Todas las tiradas han sido borradas.",
		["%d Roll(s)"] = "%d Tiradas",
	},
	frFR = {
		["All rolls have been cleared."] = "Tous les jets ont été effacés.",
		["%d Roll(s)"] = "%d Jet(s)",
	},
	ruRU = {
		["All rolls have been cleared."] = "Все броски костей очищены.",
		["%d Roll(s)"] = "%d броска(ов)",
	},
	zhCN = {
		["All rolls have been cleared."] = "所有骰子已被清除。",
		["%d Roll(s)"] = "%d个骰子",
	},
	zhTW = {
		["All rolls have been cleared."] = "所有擲骰紀錄已被清除。",
		["%d Roll(s)"] = "共計 %d 人擲骰",
	},
}
local L = locales[GetLocale()] or {}
setmetatable(L, {
	__index = {
		-- 주사위 몇명 굴렸는지에 대한 기본설정값
		["%d Roll(s)"] = "%d Roll(s)",
		-- 주사위가 초기화 되었다는 메세지에 대한 기본설정값
		["All rolls have been cleared."] = "All rolls have been cleared.",
	},
})



-- 처음 로딩
function MimDice_OnLoad(self)

	-- 로딩되면 기본적으로 Up 정렬
	UpBtn:SetChecked(true)

	-- 주사위 테이블, 이름 테이블 만들기
	rollArray = {}
	rollNames = {}

	-- DB 없으면 DB 만들기
	if not MimDiceDB then MimDiceDB = {} end 
	local x, y, w, h = MimDiceDB.window_X, MimDiceDB.window_Y, MimDiceDB.window_Width, MimDiceDB.window_Height
	if not x or not y or not w or not h then
		MimDice_SaveAnchors()
	else
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
		self:SetWidth(w)
		self:SetHeight(h)
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
	end
end


-- LibDBIcon 라이브러리 써서 미니맵 버튼 구현
if not MimDiceDB_Minimap then MimDiceDB_Minimap = {} end
	local miniButton = LibStub("LibDataBroker-1.1"):NewDataObject("MimDice", {
		type = "data source",
		text = "MIM DICE",
		icon = "Interface\\AddOns\\MimDice\\img\\Mim_minimap_icon.tga",
		OnClick = function(self, btn)
			ToggleMinimapBtn()
		end,
		OnTooltipShow = function(tooltip)
			if not tooltip or not tooltip.AddLine then return end
			tooltip:AddLine("MIM DICE")
		end,
		})
		local icon = LibStub("LibDBIcon-1.0", true)
		icon:Register("MimDice", miniButton, MimDiceDB_Minimap)
		MimDiceDB_Minimap["hide"] = false
		icon:Show("MimDice")
	
	-- 미니맵 토글버튼 Show/hide
		function ToggleMinimapBtn()
			if MainWindow:IsVisible() == true then
				MainWindow:Hide()
			else
				MainWindow:Show()
			end
		end

	-- 이벤트 핸들러
	function MimDice_CHAT_MSG_SYSTEM(msg)

	-- GlobalStrings 이용해서 이름,주사위,최소값,최대값 불러오는 부분
	for name, roll, minRoll, maxRoll in string.gmatch(msg, pattern) do
	-- 두번 굴림 확인. 한번 굴렸으면 1 이상이 됨.
		rollNames[name] = rollNames[name] and rollNames[name] + 1 or 1
		_, EnglishClass = UnitClass(name)
	-- rollArray 테이블에 데이터 입력
	 	table.insert(rollArray, {
            
            --클래스
            Class = EnglishClass,
			-- 이름
			Name = name,
			-- 주사위 값
			Roll = tonumber(roll),
			-- 주사위 최소값	
			Min = tonumber(minRoll),
			-- 주사위 최대값
			Max = tonumber(maxRoll),
			-- 몇명굴렸는지 카운트
			Count = rollNames[name]
		}) 

		-- 이벤트 수신하면 창 띄우기
		MimDice_ShowWindow()
	end
end


-- 클래스 아이콘 불러와서 자르기
IconClassTexture="Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
IconClassTextureWithoutBorder="Interface\\WorldStateFrame\\ICONS-CLASSES"
IconClassTextureCoord='CLASS_ICON_TCOORDS'
IconClass={
  ["WARRIOR"]=	"|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:0:64:0:64|t",
  ["MAGE"]=		"|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:64:128:0:64|t",
  ["ROGUE"]=	"|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:128:192:0:64|t",
  ["DRUID"]=	"|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:192:256:0:64|t",
  ["HUNTER"]=	"|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:0:64:64:128|t",
  ["SHAMAN"]=	"|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:64:128:64:128|t",
  ["PRIEST"]=	"|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:128:192:64:128|t",
  ["WARLOCK"]=	"|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:192:256:64:128|t",
  ["PALADIN"]=	"|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:0:64:128:192|t",
  ["DEATHKNIGHT"]=	"|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:64:128:128:192|t",
  ["MONK"]=	"|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:128:192:128:192|t",
  ["DEMONHUNTER"]=	"|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:192:256:128:192|t",
  ["EVOKER"]=	"|TInterface\\WorldStateFrame\\ICONS-CLASSES:0:0:0:0:256:256:0:64:192:256|t",
}

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

-- 정렬버튼 오름차순, 내림차순
function Choice_Sort(a, b)
	if UpBtn:GetChecked(true) then
		return a.Roll < b.Roll
	elseif DownBtn:GetChecked(true) then
		return a.Roll > b.Roll
	end
end


-- 주사위 결과 순위 변수
local RankList = {}

-- 스크롤 프레임 창 업데이트
function MimDice_UpdateList()
	
	-- 롤텍스트 비워놓기
	local rollText = ""

	-- 순서 정리
	table.sort(rollArray, Choice_Sort)
	
	-- 주사위 포맷 출력, 동점 확인
	for i, roll in pairs(rollArray) do
		
		-- 중복 확인해서 중복이면 빨강색으로 체크
		-- rollArray(클래스,이름,주사위,최소,최대값) 의 다음사람 and 현재주사위 == rollArray의 다음사람의 주사위
		local tied = (rollArray[i + 1] and roll.Roll == rollArray[i + 1].Roll) or 
					 (rollArray[i - 1] and roll.Roll == rollArray[i - 1].Roll)

		-- 기준값이랑 다른 주사위를 굴리면 색상 변경
		local standardNumber = tonumber(DiceEditBox:GetText())
		local diff = (standardNumber ~= roll.Max)
		local brkt
		
		
		
		
		-- 6개의 값 포맷
		rollText = string.format("|c%s%d|r : |c%s%s|r%s%s|r\n",
							  
			--1.  주사위숫자 동점체크 색상문자 (동점이면 빨강색 or 동점 아니면 살구색)
			tied and "FFFF0000".."> " or "ffffcccc",

			--2.  주사위 숫자 
			roll.Roll,
				
			--3.  기준값이랑 다른 주사위를 굴리면 색상 변경
			diff and  "FFFF0000" or "ffffcccc",

			-- 클래스
			IconClass[roll.Class] .. Mim_GetClassColor(roll.Class).. roll.Name,

			--5. (최소값이 0이 아니거나 최대값이 0이 아님) and (숫자~숫자) 형식이면, 최소값, 최대값 표시하고 아니라면 빈칸
			(roll.Min ~= 0 or roll.Max ~= 0) and format(" (%d-%d)", roll.Min, roll.Max) or "",

			--6. 롤카운트가 1이상이면 숫자+카운트로 rollText에 표시
			roll.Count > 1 and format(" [%2d번굴림]", roll.Count) or "") .. rollText


			if tied == true then
				brkt =  "> "
			else brkt = ""
			end

			tinsert(RankList, brkt .. roll.Roll .. " " .. roll.Name .. " (" .. roll.Min .. "-" .. roll.Max .. ")")
			

	end
	-- 롤스트링 스크롤프레임에 rollText 입력
	RollStrings:SetText(rollText)
	-- 몇명 굴렸는지 입력
	MimDiceStatusTextFrame:SetText(string.format(L["%d Roll(s)"], table.getn(rollArray)))

end


-- 결과 보고
function MimDice_RollAnnounce()
	local Rank1 = "1등"
	local Rank2 = "2등"
	local Rank3 = "3등"
	local Rank4 = "4등"
	local Rank5 = "5등"
	local Rank6 = "6등"
	local Rank7 = "7등"
	local Rank8= "8등"
	local Rank9= "9등"
	local Rank10 = "10등"
	local Rank11 = "11등"
	local Rank12 = "12등"
	local Rank13 = "13등"
	local Rank14 = "14등"
	local Rank15 = "15등"
	local Rank16 = "16등"
	local Rank17 = "17등"
	local Rank18 = "18등"
	local Rank19 = "19등"
	local Rank20 = "20등"

local i = #RankList
local pass

for pass = 1, i, 1 do
	if #RankList >= 1 then
		if string.find(RankList[i], "> ") == nil then  -- 첫번째에 동탈 없으면==
			print(Rank1 .. RankList[i])					-- 첫번째가 1등
			break
		elseif string.find(RankList[i], "> ") ~= nil then -- 첫째에 동탈 있으면 ~=
			if string.find(RankList[i-pass], "> ") == nil then -- 두번째에 동탈 있나보고 없으면==
				print(Rank1 .. RankList[i-pass])					-- 두번째가 1등
				break
				end
			end
		end
	end
end






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

-- 창 닫기
function MimDice_HideWindow()
	MainWindow:Hide()
	MimDice_ClearRolls()
end

-- 몇명 굴렸는지 확인
function RolledPerson(msg)
    MimDiceStatusTextFrame:SetText(msg)
end

-- 주사위 리셋
function MimDice_ClearRolls()
	rollArray = {}
	rollNames = {}
	RankList = {}
	DEFAULT_CHAT_FRAME:AddMessage(L["All rolls have been cleared."])
	MimDice_UpdateList()
end

-- 채팅메세지 보낼 채널 선택
function SelectChannel()
    local SendChatMessageChannel
    if IsInRaid() then
        SendChatMessageChannel = "RAID_WARNING"
	elseif IsInRaid() then
			SendChatMessageChannel = "RAID"
    elseif IsInGroup() then
        SendChatMessageChannel = "PARTY"
	else SendChatMessageChannel = "RAID_WARNING"
    end
    return SendChatMessageChannel
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
	
	-- 탱커 체크
	local function T_Check()
		if TankCheckBox:GetChecked(true) then
			return T_Prefix
		else
			return ""
		end
	end

	-- 딜러 체크
	local function D_Check()
		if DpsCheckBox:GetChecked(true) then
			return D_Prefix
		else
			return ""
		end
	end

	-- 힐러 체크
	local function H_Check()
		if HealCheckBox:GetChecked(true) then
			return H_Prefix
		else
			return ""
		end
	end

	-- 정렬 하이 체크
	local function High_Check()
		if UpBtn:GetChecked(true) then
			return High_Text
		else
			return ""
		end
	end

	-- 정렬 로우 체크
	local function Low_Check()
		if DownBtn:GetChecked(true) then
			return Low_Text
		else
			return ""
		end
	end

	-- 최종 메세지 조합
	Final_Text = T_Check()  .. D_Check() .. H_Check() .. Dice_Text .. Num_Dice .. Space .. High_Check() .. Low_Check() .. Suffix

	-- 채팅 메세지 선택하고, 메세지 보낼 채널 선택
	 SendChatMessage(Final_Text,SelectChannel())
	 SendChatMessage(StartLine,SelectChannel())
end

-- 클래스 글자 색깔
function Mim_GetClassColor(Class)

    local ClassColor = ""
    local Red, Green, Blue

    Class = strupper(Class)

    if RAID_CLASS_COLORS[Class] ~= nil then
        Red = RAID_CLASS_COLORS[Class].r
        Green = RAID_CLASS_COLORS[Class].g
        Blue = RAID_CLASS_COLORS[Class].b
        ClassColor = "|c" .. string.format("%2x%2x%2x%2x", 255, Red * 255, Green * 255, Blue * 255)
    end
    return ClassColor
end

