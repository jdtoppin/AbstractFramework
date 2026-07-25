local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local cosmeticClasses = {
    followerDruid = {"Paladin", "PALADIN", 2},
    followerShaman = {"Mage", "MAGE", 8},
    followerHunter = {"Rogue", "ROGUE", 4},
}

local baseClasses = {
    followerDruid = {"DRUID", 11},
    followerShaman = {"SHAMAN", 7},
    followerHunter = {"HUNTER", 3},
}

UnitClass = function(unit)
    local class = cosmeticClasses[unit] or {"Warrior", "WARRIOR", 1}
    return unpack(class)
end

C_SpecializationInfo = {
    GetSpecialization = function() end,
    GetSpecializationInfo = function() end,
}

local function loadFramework(nativeUnitClassBase)
    UnitClassBase = nativeUnitClassBase

    local AF = {
        RegisterCallback = function() end,
    }
    local chunk = assert(loadfile("Units/Player.lua"))
    chunk("AbstractFramework", AF)
    return AF
end

local AF = loadFramework(function(unit)
    return unpack(baseClasses[unit])
end)

for unit, expected in pairs(baseClasses) do
    local classFileName, classID = AF.UnitClassBase(unit)
    assertEqual(classFileName, expected[1], unit .. " base class")
    assertEqual(classID, expected[2], unit .. " base class ID")
end

local legacyAF = loadFramework(nil)
local classFileName, classID = legacyAF.UnitClassBase("followerDruid")
assertEqual(classFileName, "PALADIN", "legacy class fallback")
assertEqual(classID, 2, "legacy class ID fallback")

print("unit class base tests passed")
