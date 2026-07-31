local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local levels = {
    player = 69,
    party1 = 70,
    party2 = 71,
}
local effectiveMaxLevel = 70
local capCalls = 0

local AF = {
    funcs = {},
    noop = function() end,
}
local environment = {
    _G = false,
    AbstractFramework = AF,
    C_CVar = {
        GetCVarBool = function() end,
    },
    GameRulesUtil = {
        GetEffectiveMaxLevelForPlayer = function()
            capCalls = capCalls + 1
            return effectiveMaxLevel
        end,
    },
    UnitLevel = function(unit)
        return levels[unit]
    end,
    bit = {
        band = function() end,
    },
}
setmetatable(environment, {__index = _G})
environment._G = environment

local chunk, loadError = loadfile("Units/Common.lua")
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("AbstractFramework", AF)

assertEqual(AF.IsMaxLevel(), false, "default player below cap")
assertEqual(AF.IsMaxLevel("party1"), true, "arbitrary unit at cap")
assertEqual(AF.IsMaxLevel("party2"), true, "arbitrary unit above cap")
assertEqual(capCalls, 3, "effective cap queried for every comparison")

effectiveMaxLevel = 69
assertEqual(AF.IsMaxLevel(), true, "updated effective cap")

print("is_max_level_compat_test.lua: ok")
