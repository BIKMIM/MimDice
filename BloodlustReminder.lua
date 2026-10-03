-- 블러드 후유증이 없는 전투에서 한 번 알린다. 실제 발동의 40초 바와는 별도 표시다.
-- 오라 조회와 사운드 선택은 MimDice의 공용 기능을 사용한다.
MimDiceBloodlustReminder = {}
local Reminder = MimDiceBloodlustReminder
local L = MimDice_L
local lustClasses = { SHAMAN = true, MAGE = true, EVOKER = true, HUNTER = true }
local defaults = {
    enabled = true, otherClasses = false, soundEnabled = true, textEnabled = true,
    instanceOnly = true,
    soundType = "preset", soundKey = 567458, soundFile = "", message = "",
    fontSize = 48, duration = 5, x = 0, y = 200, locked = true,
}
local queryAuras, playSound, display, events
local inCombat, loading, notified, settling = false, false, false, false
local revision = 0

function Reminder.GetSettings()
    if not MimDiceDB then return nil end
    if type(MimDiceDB.bloodlustReadyAlert) ~= "table" then MimDiceDB.bloodlustReadyAlert = {} end
    local config = MimDiceDB.bloodlustReadyAlert
    for key, value in pairs(defaults) do
        if type(config[key]) ~= type(value) then config[key] = value end
    end
    if type(config.color) ~= "table" then config.color = {} end
    for key, value in pairs({ r = 1, g = 0.82, b = 0 }) do
        if type(config.color[key]) ~= "number" then config.color[key] = value end
    end
    return config
end

local function PublicCall(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, value = pcall(func, ...)
    if not ok or (issecretvalue and issecretvalue(value)) then return nil end
    return value
end

local function CanRemind()
    local config = Reminder.GetSettings()
    if not config or not config.enabled then return false end
    if loading or not inCombat or PublicCall(UnitIsDeadOrGhost, "player") ~= false then return false end
    if config.instanceOnly then
        local ok, inside, instanceType = pcall(IsInInstance)
        if not ok or (issecretvalue and (issecretvalue(inside) or issecretvalue(instanceType))) then return false end
        if not inside or (instanceType ~= "party" and instanceType ~= "raid") then return false end
    end
    if config.otherClasses then return true end
    local _, class = UnitClass("player")
    if issecretvalue and issecretvalue(class) then return false end
    return lustClasses[class] == true
end

function Reminder.Hide()
    if display then display:Hide() end
end

local function EnsureDisplay()
    if display then return display end
    display = CreateFrame("Frame", "MimDice_BloodlustReadyAlert", UIParent)
    display:SetFrameStrata("HIGH")
    display:EnableMouse(false)
    display:SetMovable(true)
    display:SetClampedToScreen(true)
    display:SetUserPlaced(false)
    display:RegisterForDrag("LeftButton")
    display:SetScript("OnDragStart", function(self)
        if not Reminder.GetSettings().locked then self:StartMoving(); self.moving = true end
    end)
    display:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
        self.moving = false
        local x, y = self:GetCenter()
        local cx, cy = UIParent:GetCenter()
        if x and y and cx and cy then
            local config = Reminder.GetSettings()
            config.x, config.y = math.floor(x - cx + 0.5), math.floor(y - cy + 0.5)
        end
        if Reminder.Config then Reminder.Config.posRefresh() end
    end)
    display:SetScript("OnHide", function(self)
        if self.moving then self:GetScript("OnDragStop")(self) end
        if self.pulseFrame then self.pulseFrame:SetScale(1) end
    end)
    display:Hide()
    -- 글씨만 중심을 기준으로 확대한다. 저장 위치와 편집 테두리는 고정한다.
    local pulseFrame = CreateFrame("Frame", nil, display)
    pulseFrame:SetPoint("CENTER", display, "CENTER")
    pulseFrame:SetSize(1, 1)
    pulseFrame:EnableMouse(false)
    display.pulseFrame = pulseFrame
    local text = pulseFrame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER")
    text:SetTextColor(1, 0.82, 0)
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(2, -2)
    display.text = text

    -- 위치 편집 중에는 파티 신청 알림과 같은 노란 사각 테두리로 드래그 영역을 표시한다.
    local editBorder = {}
    for _, edge in ipairs({
        { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
    }) do
        local line = display:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(1, 0.82, 0, 1)
        line:SetPoint(edge[1], display, edge[1], 0, 0)
        line:SetPoint(edge[2], display, edge[2], 0, 0)
        if edge[3] then line:SetHeight(3) else line:SetWidth(3) end
        line:Hide()
        editBorder[#editBorder + 1] = line
    end
    function display:SetEditBorder(shown)
        for _, line in ipairs(editBorder) do line:SetShown(shown) end
    end

    display:SetScript("OnUpdate", function(self, elapsed)
        local config = Reminder.GetSettings()
        if self.preview and not config.locked then
            self.pulseFrame:SetScale(1)
            return
        end
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= config.duration or (not self.preview and not CanRemind()) then
            self:Hide()
            return
        end
        -- 처음에 세 번 빠르게 부풀었다 돌아온 뒤 기본 크기로 유지한다.
        -- 표시 시간이 짧으면 맥박 주기도 함께 줄인다.
        local pulseDuration = math.min(1.2, config.duration * 0.7)
        local scale = 1
        if self.elapsed < pulseDuration then
            local phase = (self.elapsed / pulseDuration * 3) % 1
            local beat
            if phase < 0.25 then
                beat = math.sin(phase / 0.25 * math.pi / 2)
            else
                beat = math.cos((phase - 0.25) / 0.75 * math.pi / 2) ^ 2
            end
            scale = 1 + 0.45 * beat
        end
        self.pulseFrame:SetScale(scale)
        -- 마지막 0.5초만 페이드. 같은 전투에서 반복해서 소리를 내지 않는다.
        self:SetAlpha(math.min(1, (config.duration - self.elapsed) * 2))
    end)
    return display
end

function Reminder.TestSound()
    local config = Reminder.GetSettings()
    if playSound and config then
        local sound = {}
        for key, value in pairs(config) do sound[key] = value end
        sound.enabled = true
        playSound(sound)
    end
end

local function StyleDisplay()
    local config = Reminder.GetSettings()
    local frame = EnsureDisplay()
    if not frame.moving then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", config.x, config.y)
    end
    frame.text:SetFont(MimDiceFontPath(), config.fontSize, "OUTLINE")
    frame.text:SetTextColor(config.color.r, config.color.g, config.color.b)
    frame.text:SetText(config.message ~= "" and config.message or L("Bloodlust / Heroism ready!"))
    frame.pulseFrame:SetScale(1)
    frame:SetSize(math.max(200, frame.text:GetStringWidth() + 30), config.fontSize * 2)
    frame:EnableMouse(not config.locked)
    frame:SetEditBorder(not config.locked)
end

local function Show(preview)
    local config = Reminder.GetSettings()
    if not config then return end
    if config.soundEnabled then Reminder.TestSound() end
    if not config.textEnabled then return end
    local frame = EnsureDisplay()
    StyleDisplay()
    frame.elapsed, frame.preview = 0, preview
    frame:SetAlpha(1)
    frame:Show()
end

function Reminder.Test()
    Show(true)
end

function Reminder.ClosePreview()
    local config = Reminder.GetSettings()
    if config then config.locked = true end
    if display then
        display:EnableMouse(false)
        display:SetEditBorder(false)
    end
    if display and display.preview then display:Hide() end
end

function Reminder.Refresh(present, known)
    if not queryAuras then return end
    if display and display:IsShown() and display.preview then return end
    if settling or not CanRemind() then
        Reminder.Hide()
        return
    end
    if known == nil then present, known = queryAuras() end
    -- 일부 후유증이라도 조회할 수 없다면 '없음'으로 간주하지 않는다.
    if not known then
        Reminder.Hide()
        return
    end
    if present then
        notified = false
        Reminder.Hide()
    elseif not notified then
        notified = true
        Show(false)
    end
end

local function CheckAfterTransition(delay)
    revision = revision + 1
    settling = true
    local expected = revision
    C_Timer.After(delay, function()
        if revision == expected then settling = false; Reminder.Refresh() end
    end)
end

function Reminder.ApplySettings()
    local config = Reminder.GetSettings()
    if not config then return end
    if not config.locked then
        StyleDisplay()
        display.elapsed, display.preview = 0, true
        display:SetAlpha(1)
        display:Show()
    elseif display and display:IsShown() then
        if not config.textEnabled or (not display.preview and not CanRemind()) then
            Reminder.Hide()
        else
            StyleDisplay()
        end
    end
end

function Reminder.Init(auraQuery, soundPlayer)
    queryAuras, playSound = auraQuery, soundPlayer
    Reminder.GetSettings().locked = true
    EnsureDisplay()
    if events then return end
    events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "LOADING_SCREEN_ENABLED", "PLAYER_ENTERING_WORLD", "PLAYER_DEAD",
        "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            Reminder.ClosePreview()
            inCombat, notified = true, false
            CheckAfterTransition(0.2)
        elseif event == "PLAYER_ENTERING_WORLD" then
            loading, notified = false, false
            inCombat = PublicCall(UnitAffectingCombat, "player") == true
            Reminder.Hide()
            CheckAfterTransition(1)
        elseif event == "PLAYER_REGEN_ENABLED" or event == "LOADING_SCREEN_ENABLED" then
            revision = revision + 1
            settling = false
            inCombat, notified = false, false
            loading = event == "LOADING_SCREEN_ENABLED"
            Reminder.Hide()
        elseif event == "PLAYER_DEAD" then
            Reminder.Hide()
        else
            CheckAfterTransition(0.2)
        end
    end)
end

