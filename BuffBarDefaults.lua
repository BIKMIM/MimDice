-- 바를 처음 만들거나 사용자가 기본값을 누를 때만 쓰는 화면 기준값.
-- 저장된 설정은 읽거나 바꾸지 않으며 UIParent의 공개 크기만 사용한다.
MimDiceBuffBarDefaults = {}

local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function ScreenDimension(method)
    if not UIParent or type(UIParent[method]) ~= "function" then return nil end
    local ok, value = pcall(UIParent[method], UIParent)
    if not ok or IsSecret(value) then return nil end
    if type(value) ~= "number" then return nil end
    if value <= 0 or value ~= value or value == math.huge then return nil end
    return value
end

function MimDiceBuffBarDefaults.Get(key)
    -- 화면 크기를 아직 못 읽으면 작은 바 두 개를 화면 중심 가까이에 둔다.
    local width, height, x, bloodY = 100, 50, 0, 22.5
    local screenHeight = ScreenDimension("GetHeight")
    local lowerY
    if screenHeight then
        height = math.min(height, screenHeight)
        -- 기본 위치가 화면 위로 나갈 수 있으면 두 바를 중앙보다 조금 위로 옮긴다.
        -- 아주 작은 화면에서도 반쪽 바 높이와 위쪽 여백은 우선 확보한다.
        local maximumY = math.max(0, screenHeight / 2 - height / 2 - 20)
        bloodY = 500
        if bloodY > maximumY then bloodY = math.min(math.floor(screenHeight * 0.2), maximumY) end
        lowerY = -maximumY
    end
    local screenWidth = ScreenDimension("GetWidth")
    if screenWidth then width = math.min(800, math.max(math.min(100, screenWidth), screenWidth - 40)) end
    local y = key == "POWERINFUSE" and bloodY - 45 or bloodY
    if lowerY then y = math.max(lowerY, y) end
    return { x = x, y = y, width = width, height = height }
end
