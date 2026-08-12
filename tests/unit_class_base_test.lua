local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local displayClasses = {
    followerDruid = {"Druid", "DRUID", 11},
    followerShaman = {"Shaman", "SHAMAN", 7},
    followerHunter = {"Hunter", "HUNTER", 3},
}

local baseClasses = {
    followerDruid = {"PALADIN", 2},
    followerShaman = {"MAGE", 8},
    followerHunter = {"ROGUE", 4},
}

local secretIdentity = {}

UnitClass = function(unit)
    if unit == "secretUnit" then
        return secretIdentity, secretIdentity, secretIdentity
    end
    local class = displayClasses[unit] or {"Warrior", "WARRIOR", 1}
    return unpack(class)
end

UnitClassBase = function(unit)
    return unpack(baseClasses[unit])
end

C_SpecializationInfo = {
    GetSpecialization = function() end,
    GetSpecializationInfo = function() end,
}

local AF = {
    funcs = {
        isValueNonSecret = function(value)
            return value ~= secretIdentity
        end,
    },
    RegisterCallback = function() end,
}
local playerChunk = assert(loadfile("Units/Player.lua"))
playerChunk("AbstractFramework", AF)

for unit, expected in pairs(displayClasses) do
    local classFileName, classID = AF.UnitClassBase(unit)
    assertEqual(classFileName, expected[2], unit .. " display class")
    assertEqual(classID, expected[3], unit .. " display class ID")
end

local secretClass, secretClassID = AF.UnitClassBase("secretUnit")
assertEqual(secretClass, nil, "secret display class")
assertEqual(secretClassID, nil, "secret display class ID")

AF.Copy = function(value)
    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = entry
    end
    return copy
end
AF.TransposeTable = function()
    return {}
end
AF.REGISTERED_ADDONS = {}
AF.GetAddon = function() end
RAID_CLASS_COLORS = {}
C_Item = {
    GetItemQualityColor = function() end,
}
Enum = {
    ItemQuality = {},
}
QuestDifficultyColors = {}

local colorChunk = assert(loadfile("Widgets/Color.lua"))
colorChunk("AbstractFramework", AF)
local unknownRed, unknownGreen, unknownBlue, unknownAlpha =
    AF.GetClassColor(secretIdentity, 0.5, 2)
assertEqual(unknownRed, 0.8, "secret class fallback red")
assertEqual(unknownGreen, 0.8, "secret class fallback green")
assertEqual(unknownBlue, 0.8, "secret class fallback blue")
assertEqual(unknownAlpha, 0.5, "secret class fallback alpha")

local resolvedClass
local vertexColor
local texture = {
    SetVertexColor = function(_, r, g, b)
        vertexColor = {r, g, b}
    end,
}

AF.UnitIsPlayer = function()
    return true
end
AF.GetClassColor = function(class)
    resolvedClass = class
    return 0.1, 0.2, 0.3
end
AF.CreateSecretStatusBar = function()
    return {
        fill = texture,
        unfill = texture,
    }
end

Mixin = function(target, mixin)
    for key, value in pairs(mixin) do
        target[key] = value
    end
end

CreateFrame = function()
    return {
        SetScript = function() end,
    }
end

UnitIsConnected = function() return true end
UnitPower = function() return 1 end
UnitPowerMax = function() return 1 end
UnitPowerType = function() return 0, "MANA" end

local powerBarChunk = assert(loadfile("Widgets_UnitFrames/SecretPowerBar.lua"))
powerBarChunk("AbstractFramework", AF)

local powerBar = AF.CreateSecretPowerBar(nil, "TestPowerBar")
powerBar.unit = "followerDruid"
powerBar:SetupFillColor({
    type = "class_color",
    alpha = 1,
})

assertEqual(resolvedClass, "DRUID", "secret unit-frame widget class")
assertEqual(vertexColor[1], 0.1, "secret unit-frame widget red")
assertEqual(vertexColor[2], 0.2, "secret unit-frame widget green")
assertEqual(vertexColor[3], 0.3, "secret unit-frame widget blue")

powerBar.unit = "secretUnit"
powerBar:SetupFillColor({
    type = "class_color",
    alpha = 1,
})
assertEqual(resolvedClass, nil, "restricted class did not fail closed")
assertEqual(vertexColor[1], 0.1, "restricted class fallback red")
assertEqual(vertexColor[2], 0.2, "restricted class fallback green")
assertEqual(vertexColor[3], 0.3, "restricted class fallback blue")

print("unit class base tests passed")
