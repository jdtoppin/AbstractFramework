local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function splitComma(value)
    local values = {}
    local start = 1

    while true do
        local comma = value:find(",", start, true)
        if not comma then
            values[#values + 1] = value:sub(start)
            break
        end
        values[#values + 1] = value:sub(start, comma - 1)
        start = comma + 1
    end

    return unpack(values)
end

strsplit = function(delimiter, value)
    assertEqual(delimiter, ",", "test delimiter")
    return splitComma(value)
end

wipe = function(target)
    for key in pairs(target) do
        target[key] = nil
    end
end

hooksecurefunc = function() end

local textureMethods = {}
local textureMetatable = {__index = textureMethods}
local frameMethods = {}
local frameMetatable = {__index = frameMethods}

function frameMethods:CreateTexture()
    return setmetatable({}, textureMetatable)
end

function frameMethods:CreateMaskTexture()
    return setmetatable({}, textureMetatable)
end


CreateFrame = function()
    return setmetatable({}, frameMetatable)
end

local secret = {}
local AF = {
    funcs = {
        isValueNonSecret = function(value)
            return value ~= secret
        end,
    },
    NewQueue = function()
        return {
            isEmpty = function()
                return true
            end,
        }
    end,
    CreateBasicEventHandler = function() end,
    RegisterCallback = function() end,
}

local pixelUtilChunk = assert(loadfile("Utils/PixelUtil.lua"))
pixelUtilChunk("AbstractFramework", AF)

local parent = {}

local function CreateRegion()
    local region = {
        clearCount = 0,
        nativePoints = {
            {"CENTER", parent, "CENTER", 12, 34},
        },
    }

    function region:GetParent()
        return parent
    end

    function region:GetEffectiveScale()
        return 1
    end

    function region:ClearAllPoints()
        self.clearCount = self.clearCount + 1
        self.nativePoints = {}
    end

    function region:SetPoint(...)
        self.nativePoints[#self.nativePoints + 1] = {...}
    end

    return region
end

local function AssertLoaded(pos, expected, message)
    local region = CreateRegion()
    assertEqual(AF.LoadPosition(region, pos), true, message .. " result")
    assertEqual(region.clearCount, 1, message .. " clear count")
    assertEqual(#region.nativePoints, 1, message .. " point count")

    local point = region.nativePoints[1]
    for index = 1, 5 do
        assertEqual(point[index], expected[index], message .. " value " .. index)
    end

    local ledger = region._points[expected[1]]
    for index = 1, 5 do
        assertEqual(ledger[index], expected[index], message .. " ledger " .. index)
    end
end

AssertLoaded(
    {"TOPRIGHT", -4, -40},
    {"TOPRIGHT", parent, "TOPRIGHT", -4, -40},
    "three-field table"
)
AssertLoaded(
    {"TOPLEFT", "BOTTOMLEFT", 7.5, -8.5},
    {"TOPLEFT", parent, "BOTTOMLEFT", 7.5, -8.5},
    "four-field table"
)
AssertLoaded(
    " TOPRIGHT, -4, -40 ",
    {"TOPRIGHT", parent, "TOPRIGHT", -4, -40},
    "three-field string"
)
AssertLoaded(
    "TOPLEFT,BOTTOMLEFT,7.5,-8.5",
    {"TOPLEFT", parent, "BOTTOMLEFT", 7.5, -8.5},
    "four-field string"
)

local function AssertRejected(pos, message)
    local region = CreateRegion()
    local originalPoints = region.nativePoints

    assertEqual(AF.LoadPosition(region, pos), false, message .. " result")
    assertEqual(region.clearCount, 0, message .. " clear count")
    assertEqual(region.nativePoints, originalPoints, message .. " native points")
    assertEqual(region._points, nil, message .. " ledger")
    assertEqual(region._useOriginalPoints, nil, message .. " original-point flag")
end

AssertRejected({"TOPRIGHT", -4}, "missing table offset")
AssertRejected({"NOT_A_POINT", -4, -40}, "invalid table anchor")
AssertRejected({"TOPRIGHT", -4, -40, 0, 1}, "extra table field")
AssertRejected({"TOPRIGHT", secret, -40}, "secret table offset")
AssertRejected(secret, "secret position")
AssertRejected("TOPRIGHT,-4", "missing string offset")
AssertRejected("NOT_A_POINT,-4,-40", "invalid string anchor")
AssertRejected("TOPRIGHT,-4,-40,0,1", "extra string field")

print("load position tests passed")
