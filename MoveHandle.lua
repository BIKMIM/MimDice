-- 위치 조정용 손잡이 (공용)
-- 화면 알림 창은 마우스를 아예 받지 않는다(만들 때 기본값 = 클릭 통과, EnableMouse를 부르지 않음).
-- 위치 조정은 그 위에 겹치는 별도 손잡이 창이 맡는다.
--   · 손잡이는 전투 밖에서 처음 만들 때 한 번만 마우스를 켠다.
--   · 조정 끝 = 손잡이 숨기기. 숨기기(Hide)는 전투 중에도 막히지 않으므로,
--     전투 잠금이 이미 걸린 뒤에 전투 이벤트를 받아도 클릭을 막는 상태가 남지 않는다.
--   · 전투 중에는 조정 시작과 이동 시작을 하지 않는다.
MimDiceMoveHandle = {}
local MH = MimDiceMoveHandle
local handles = {}

local function InCombat()
    return InCombatLockdown and InCombatLockdown() and true or false
end
MH.InCombat = InCombat

-- target: 옮길 알림 창 / opts.onStop(): 이동이 끝나면 위치 저장
-- opts.onCombat(): 전투로 조정이 끝났을 때 / opts.onHidden(): 알림 창이 숨겨져 조정이 끝났을 때
-- 손잡이는 알림 창의 자식이라, 알림 창이 숨겨지면 함께 숨겨진다(숨은 창은 마우스를 받지 않음).
-- 그래도 조정 상태가 남지 않도록 알림 창의 OnHide에서 h:TargetHidden()을 불러 끝낸다.
function MH.Create(target, opts)
    opts = opts or {}
    local h = { target = target, opts = opts, editing = false }

    function h:Ensure()
        if self.frame then return true end
        if InCombat() then return false end   -- 마우스를 켜는 생성은 전투 밖에서만
        local f = CreateFrame("Frame", nil, target)
        f:SetFrameStrata("DIALOG")
        f:SetAllPoints(target)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function()
            if InCombat() or not h.editing then return end
            target:SetMovable(true)
            target:StartMoving()
            h.moving = true
        end)
        f:SetScript("OnDragStop", function() h:StopMoving() end)
        f:SetScript("OnHide", function() h:StopMoving() end)
        -- 노란 사각 테두리 = 끌 수 있는 영역
        for _, edge in ipairs({
            { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
            { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
        }) do
            local line = f:CreateTexture(nil, "OVERLAY")
            line:SetColorTexture(1, 0.82, 0, 1)
            line:SetPoint(edge[1], f, edge[1], 0, 0)
            line:SetPoint(edge[2], f, edge[2], 0, 0)
            if edge[3] then line:SetHeight(2) else line:SetWidth(2) end
        end
        f:Hide()
        self.frame = f
        return true
    end

    function h:StopMoving()
        if not self.moving then return end
        self.moving = false
        target:StopMovingOrSizing()
        if target.SetUserPlaced then target:SetUserPlaced(false) end
        if opts.onStop then opts.onStop() end
    end

    -- 조정 시작. 전투 중이면 시작하지 않고 false
    function h:Begin()
        if InCombat() or not self:Ensure() then return false end
        self.editing = true
        self.frame:Show()
        return true
    end

    -- 조정 끝. 전투 중에도 안전 (숨기기만 한다)
    function h:End()
        self.editing = false
        if self.frame then self.frame:Hide() end
        self:StopMoving()
    end

    -- 알림 창이 숨겨졌을 때 (초기화, 표시 시간 끝, 기능 끄기 등)
    function h:TargetHidden()
        if not (self.editing or self.moving) then return end
        self:End()
        if opts.onHidden then pcall(opts.onHidden) end
    end

    handles[#handles + 1] = h
    return h
end

-- 전투가 시작되면 모든 손잡이를 닫는다. 잠금이 이미 걸린 뒤에 와도 Hide는 안전하다.
function MH.EndAllForCombat()
    for _, h in ipairs(handles) do
        if h.editing or h.moving then
            h:End()
            if h.opts.onCombat then pcall(h.opts.onCombat) end
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function() MH.EndAllForCombat() end)
