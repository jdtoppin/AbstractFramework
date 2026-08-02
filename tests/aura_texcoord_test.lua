local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local function assertApproxEqual(actual, expected, message)
    if math.abs(actual - expected) > 0.000001 then
        error(("%s: expected %.6f, got %.6f"):format(message, expected, actual), 2)
    end
end

C_Texture = {
    GetAtlasExists = function()
        return false
    end,
}

local AF = {
    noop_true = function()
        return true
    end,
    Unpack8 = function(values)
        return values[1], values[2], values[3], values[4],
            values[5], values[6], values[7], values[8]
    end,
}

local textureChunk = assert(loadfile("Widgets/Texture.lua"))
textureChunk("AbstractFramework", AF)

assertEqual(type(AF.ReCalcTexCoordForAura), "function", "public aura texcoord helper")

local calls = 0
local coordinates
local aura = {
    icon = {
        SetTexCoord = function(_, ...)
            calls = calls + 1
            coordinates = {...}
        end,
    },
}

AF.ReCalcTexCoordForAura(aura, 200, 100)

assertEqual(calls, 1, "valid resize update count")
assertEqual(#coordinates, 8, "texture coordinate count")

local expectedWideCoordinates = {
    0.12, 0.31,
    0.12, 0.69,
    0.88, 0.31,
    0.88, 0.69,
}
for index, expected in ipairs(expectedWideCoordinates) do
    assertApproxEqual(coordinates[index], expected, "wide aura coordinate " .. index)
end

AF.ReCalcTexCoordForAura(aura, 100, 200)

assertEqual(calls, 2, "second valid resize update count")
local expectedTallCoordinates = {
    0.31, 0.12,
    0.31, 0.88,
    0.69, 0.12,
    0.69, 0.88,
}
for index, expected in ipairs(expectedTallCoordinates) do
    assertApproxEqual(coordinates[index], expected, "tall aura coordinate " .. index)
end

AF.ReCalcTexCoordForAura(aura, 100, 0)
AF.ReCalcTexCoordForAura(aura, nil, 100)
AF.ReCalcTexCoordForAura(nil, 100, 100)
AF.ReCalcTexCoordForAura({}, 100, 100)
AF.ReCalcTexCoordForAura({icon = {}}, 100, 100)

assertEqual(calls, 2, "invalid resize inputs leave the last valid texcoords unchanged")

print("aura texcoord tests passed")
