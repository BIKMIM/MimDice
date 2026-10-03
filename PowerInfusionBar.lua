-- 실제 마력 주입 시간은 Blizzard AuraContainer에 맡긴다.
-- 비밀 오라, 표시 여부, StatusBar 값, 시간 문구를 읽어 발동을 추정하지 않는다.
-- 일반 프레임의 15초 카운트다운은 설정창 테스트에만 사용한다.

MimDicePowerInfusionBar = {}
local Bar = MimDicePowerInfusionBar
local settingsSource, canConfigure, host, container, nativeVisual, previewVisual
local initialized, creationAttempted, available = false, false, false
local suppressed, previewUntil = true, 0
local appliedStyle, status
local PREVIEW_DURATION = 15

local function L(value)
    return MimDice_L and MimDice_L(value) or value
end

local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function Settings()
    return type(settingsSource) == "function" and settingsSource() or settingsSource
end

local function GetBarDefaults()
    if MimDiceBuffBarDefaults then return MimDiceBuffBarDefaults.Get("POWERINFUSE") end
    return { x = 0, y = -22.5, width = 100, height = 50 }
end

local function CanConfigureBar()
    if type(canConfigure) ~= "function" or not canConfigure() then return false end
    local getter = C_Secrets and C_Secrets.ShouldAurasBeSecret
    if type(getter) ~= "function" then return false end
    local ok, restricted = pcall(getter)
    return ok and not IsSecret(restricted) and type(restricted) == "boolean" and not restricted
end

local function GetStyle(settings)
    local color = settings.barColor or {}
    return {
        font = MimDiceFontPath and MimDiceFontPath() or "Fonts\\2002.ttf",
        size = math.max(8, math.min(120, tonumber(settings.timeFontSize) or 40)),
        label = settings.message or L("마력 주입!"),
        r = color.r or 0.2, g = color.g or 0.6, b = color.b or 1,
        alpha = math.max(0, math.min(100, tonumber(settings.alphaPct) or 50)) / 100,
    }
end

local function StylesMatch(a, b)
    if not a or not b then return false end
    for key, value in pairs(a) do
        if b[key] ~= value then return false end
    end
    return true
end

local function ApplyStyle(visual, style)
    visual.sb:SetStatusBarColor(style.r, style.g, style.b, style.alpha)
    visual.label:SetFont(style.font, style.size, "OUTLINE")
    -- 실제 시간 문구의 폭은 읽지 않는다. 공개된 설정 글씨 크기로 공간을 예약한다.
    visual.label:SetPoint("RIGHT", visual.sb, "RIGHT", -(style.size * 3 + 20), 0)
    visual.label:SetWordWrap(false)
    visual.label:SetJustifyH("LEFT")
    visual.label:SetText(style.label)
    visual.time:SetFont(style.font, style.size, "OUTLINE")
end

local function CreateNativeBackdrop(frame)
    -- AuraButton 자식에는 외부 Lua 레이아웃 스크립트가 허용되지 않는다.
    -- BackdropTemplate의 OnLoad/OnSizeChanged 대신 정적인 텍스처만 배치한다.
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
    background:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    background:SetColorTexture(0, 0, 0, 0.25)
    local anchors = {
        { "TOPLEFT", "TOPRIGHT", 1, -1, -1, -1 },
        { "BOTTOMLEFT", "BOTTOMRIGHT", 1, 1, -1, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, -1, 1, 1 },
        { "TOPRIGHT", "BOTTOMRIGHT", -1, -1, -1, 1 },
    }
    for index, points in ipairs(anchors) do
        local edge = frame:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(0.4, 0.4, 0.4, 0.6)
        edge:SetPoint(points[1], frame, points[1], points[3], points[4])
        edge:SetPoint(points[2], frame, points[2], points[5], points[6])
        if index <= 2 then edge:SetHeight(1) else edge:SetWidth(1) end
    end
end

local function CreateVisual(parent, name, style, native)
    local frame = CreateFrame("Frame", name, parent, not native and "BackdropTemplate" or nil)
    frame:EnableMouse(false)
    if native then
        CreateNativeBackdrop(frame)
    else
        frame:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame:SetBackdropColor(0, 0, 0, 0.25)
        frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.6)
    end

    local sb = CreateFrame("StatusBar", nil, frame)
    sb:EnableMouse(false)
    sb:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    sb:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    sb:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    local track = sb:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0.1, 0.1, 0.1, 0.25)

    local label = sb:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT", sb, "LEFT", 6, 0)
    label:SetTextColor(1, 1, 1, 1)
    label:SetShadowColor(0, 0, 0, 1)
    label:SetShadowOffset(1, -1)
    local time = sb:CreateFontString(nil, "OVERLAY")
    time:SetPoint("RIGHT", sb, "RIGHT", -6, 0)
    time:SetTextColor(1, 1, 1, 1)
    time:SetShadowColor(0, 0, 0, 1)
    time:SetShadowOffset(1, -1)

    local visual = { frame = frame, sb = sb, label = label, time = time }
    ApplyStyle(visual, style)
    return visual
end

local function DurationTextOptions()
    -- 포맷터는 시간을 읽는 Lua 콜백이 아니라 게임 소유 객체다.
    -- 미지원 클라이언트는 기본 시간 표시에 맡기며 바 전체를 실패시키지 않는다.
    if not C_StringUtil or type(C_StringUtil.CreateNumericRuleFormatter) ~= "function" then return nil end
    local ok, formatter = pcall(function()
        local created = C_StringUtil.CreateNumericRuleFormatter()
        created:AddBreakpoint({ threshold = 0, step = 0.1, format = "%.1f" })
        return created
    end)
    if ok then return { textFormatter = formatter } end
end

local function EnsureContainer(style)
    if container then return true end
    if creationAttempted then return false end
    creationAttempted = true
    -- 제한 사전 검사가 차단 오류를 예방한다. pcall은 일반 Lua 오류만 처리한다.
    local ok = pcall(function()
        if not C_AddOns or type(C_AddOns.IsAddOnLoaded) ~= "function" then return end
        if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
            if type(C_AddOns.LoadAddOn) ~= "function" then return end
            C_AddOns.LoadAddOn("Blizzard_AuraContainer")
        end
        if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then return end
        if not AuraContainerSortMethod or AuraContainerSortMethod.ExpirationOnly == nil
            or not AuraContainerSortDirection or AuraContainerSortDirection.Reverse == nil
            or not Enum or not Enum.StatusBarTimerDirection
            or Enum.StatusBarTimerDirection.RemainingTime == nil then return end

        local candidate = CreateFrame("AuraContainer", nil, host, "CustomAuraContainerTemplate")
        if type(candidate.AddAuraSlot) ~= "function" or type(candidate.SetEnabled) ~= "function"
            or type(candidate.SetUnit) ~= "function" then return end
        candidate:SetAllPoints(host)
        candidate:SetEnabled(false)
        candidate:SetUnit("player")
        local configuredVisual
        candidate:AddAuraSlot("powerInfusionBar", "HELPFUL", {
            candidateFilters = { includeSpellIDs = { [10060] = true } },
            -- 여러 사제가 적용한 마주 중 가장 늦게 끝나는 실제 오라를 게임이 선택한다.
            sortMethod = AuraContainerSortMethod.ExpirationOnly,
            sortDirection = AuraContainerSortDirection.Reverse,
            initializeFrame = function(button)
                -- securecallfunction 밖으로 오류가 새지 않게 콜백 안에서 처리한다.
                local configured, visual = pcall(function()
                    button:SetAllPoints(host)
                    button:EnableMouse(false)
                    local created = CreateVisual(button, nil, style, true)
                    created.frame:SetAllPoints(button)
                    button:SetDurationBar(created.sb, { direction = Enum.StatusBarTimerDirection.RemainingTime })
                    button:SetDurationText(created.time, DurationTextOptions())
                    return created
                end)
                if configured then configuredVisual = visual end
            end,
        })
        if not configuredVisual then candidate:Hide(); return end
        candidate:SetEnabled(true)
        candidate:Show()
        nativeVisual, container = configuredVisual, candidate
    end)
    if not ok or not container then host:Hide(); return false end
    appliedStyle = style
    return true
end

local function RefreshVisibility()
    if not initialized then return end
    local settings = Settings()
    local editing = settings.barLocked == false
    local showPreview = settings.barEnabled and not suppressed and (editing or GetTime() < previewUntil)
    if showPreview then
        previewVisual.frame:Show()
    else
        previewVisual.frame:Hide()
    end
    if available and not suppressed and not showPreview and settings.enabled and settings.barEnabled then
        host:Show()
    else
        -- 제한 중에도 애드온 소유 부모만 조절한다. 실제 슬롯 상태는 읽지 않는다.
        host:Hide()
    end
end

local function PositionHost(settings, defaults)
    defaults = defaults or GetBarDefaults()
    host:ClearAllPoints()
    host:SetPoint("CENTER", UIParent, "CENTER", settings.barX or defaults.x, settings.barY or defaults.y)
end

local function SavePosition(frame)
    local x, y = frame:GetCenter()
    local cx, cy = UIParent:GetCenter()
    if IsSecret(x) or IsSecret(y) or IsSecret(cx) or IsSecret(cy) then return end
    if type(x) ~= "number" or type(y) ~= "number" or type(cx) ~= "number" or type(cy) ~= "number" then return end
    local settings = Settings()
    settings.barX, settings.barY = x - cx, y - cy
    PositionHost(settings)
    if type(Bar.OnPositionChanged) == "function" then Bar.OnPositionChanged(settings.barX, settings.barY) end
end

local function StopMoving()
    if previewVisual and previewVisual.frame.moving then
        previewVisual.frame:StopMovingOrSizing()
        previewVisual.frame.moving = false
        SavePosition(previewVisual.frame)
    end
end

local function ConfigurePreview(settings, style, defaults)
    local frame = previewVisual.frame
    local editing = settings.barLocked == false
    if not editing or not settings.barEnabled then StopMoving() end
    frame:SetSize(math.max(1, tonumber(settings.width) or defaults.width), math.max(1, tonumber(settings.height) or defaults.height))
    if not frame.moving then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", settings.barX or defaults.x, settings.barY or defaults.y)
    end
    ApplyStyle(previewVisual, style)
    frame:EnableMouse(editing and settings.barEnabled == true)
    if editing then
        frame:SetBackdropColor(0.20, 0.15, 0, 0.65)
        frame:SetBackdropBorderColor(1, 0.85, 0, 1)
    else
        frame:SetBackdropColor(0, 0, 0, 0.25)
        frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.6)
    end
    local remaining = editing and PREVIEW_DURATION or math.max(0, previewUntil - GetTime())
    previewVisual.sb:SetValue(remaining / PREVIEW_DURATION)
    previewVisual.time:SetText(string.format("%.1f", remaining))
end

function Bar.ApplySettings()
    if not initialized then return end
    local settings = Settings()
    local style = GetStyle(settings)
    local defaults = GetBarDefaults()
    if not settings.barEnabled then previewUntil = 0 end
    PositionHost(settings, defaults)
    host:SetSize(math.max(1, tonumber(settings.width) or defaults.width), math.max(1, tonumber(settings.height) or defaults.height))
    ConfigurePreview(settings, style, defaults)
    available = container ~= nil and StylesMatch(appliedStyle, style)
    if available then
        status = "ready"
    elseif not settings.enabled or not settings.barEnabled then
        status = "off"
    elseif creationAttempted and not container then
        status = "unavailable"
    elseif not CanConfigureBar() then
        status = "deferred"
    elseif not EnsureContainer(style) then
        status = "unavailable"
    else
        local ok = StylesMatch(appliedStyle, style) or pcall(ApplyStyle, nativeVisual, style)
        if ok then
            appliedStyle, available, status = style, true, "ready"
        else
            status = "deferred"
        end
    end
    RefreshVisibility()
end

function Bar.Init(settings, configureCheck)
    settingsSource, canConfigure = settings, configureCheck
    if not initialized then
        host = CreateFrame("Frame", "MimDicePowerInfusionBarHost", UIParent)
        host:SetFrameStrata("MEDIUM")
        host:SetClampedToScreen(true)
        host:EnableMouse(false)
        host:Hide()
        previewVisual = CreateVisual(UIParent, "MimDicePowerInfusionBarPreview", GetStyle(Settings()))
        local frame = previewVisual.frame
        frame:SetFrameStrata("MEDIUM")
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        if frame.SetPropagateMouseClicks then frame:SetPropagateMouseClicks(true) end
        previewVisual.sb:SetMinMaxValues(0, 1)
        frame:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" and Settings().barLocked == false and Settings().barEnabled then
                self:StartMoving()
                self.moving = true
            end
        end)
        frame:SetScript("OnMouseUp", function()
            StopMoving()
        end)
        frame:SetScript("OnUpdate", function(self)
            if self.moving then SavePosition(self); return end
            if Settings().barLocked == false then return end
            local remaining = previewUntil - GetTime()
            if remaining <= 0 then
                previewUntil = 0
                RefreshVisibility()
            else
                previewVisual.sb:SetValue(remaining / PREVIEW_DURATION)
                previewVisual.time:SetText(string.format("%.1f", remaining))
            end
        end)
        frame:Hide()
        initialized = true
    end
    Bar.ApplySettings()
end

function Bar.SetSuppressed(value)
    value = value == true
    if suppressed == value then return end
    suppressed = value
    if suppressed then
        previewUntil = 0
        StopMoving()
    end
    RefreshVisibility()
end

function Bar.Preview()
    if not initialized then return end
    previewUntil = Settings().barEnabled and GetTime() + PREVIEW_DURATION or 0
    Bar.ApplySettings()
end

function Bar.ClosePreview()
    if not initialized then return end
    StopMoving()
    Settings().barLocked = true
    previewUntil = 0
    Bar.ApplySettings()
end

function Bar.GetStatusText()
    local settings = Settings()
    if settings and (not settings.enabled or not settings.barEnabled) then return L("지속시간 바 꺼짐"), "off" end
    if status == "ready" then return L("마력 주입을 받으면 남은 시간을 바로 표시합니다."), "ready" end
    if status == "deferred" then return L("안전한 지역으로 이동하면 바 설정이 적용됩니다."), "deferred" end
    return L("이 환경에서는 마력 주입 바를 표시할 수 없습니다."), "unavailable"
end
