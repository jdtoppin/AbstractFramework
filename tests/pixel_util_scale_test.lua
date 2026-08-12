local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local physicalWidth, physicalHeight

GetPhysicalScreenSize = function()
    return physicalWidth, physicalHeight
end

local objectMethods = {}

local function createScriptObject()
    return setmetatable({}, {__index = objectMethods})
end

function objectMethods:CreateTexture()
    return createScriptObject()
end

function objectMethods:CreateMaskTexture()
    return createScriptObject()
end

CreateFrame = function()
    return createScriptObject()
end

local AF = {
    NewQueue = function()
        return {}
    end,
    CreateBasicEventHandler = function() end,
    RegisterCallback = function() end,
}

assert(loadfile("Utils/Math.lua"))("AbstractFramework", AF)
assert(loadfile("Utils/PixelUtil.lua"))("AbstractFramework", AF)

local cases = {
    {label = "1080p", width = 1920, height = 1080, expected = 0.71},
    {label = "1440p", width = 2560, height = 1440, expected = 0.71},
    {label = "4K", width = 3840, height = 2160, expected = 0.71},
    {label = "5K", width = 5120, height = 2880, expected = 0.71},
    {label = "720p", width = 1280, height = 720, expected = 1.07},
    {label = "low-resolution clamp", width = 640, height = 480, expected = 1.5},
}

for _, case in ipairs(cases) do
    physicalWidth = case.width
    physicalHeight = case.height
    assertEqual(AF.GetBestScale(), case.expected, case.label .. " automatic scale")
end

print("pixel util scale tests passed")
