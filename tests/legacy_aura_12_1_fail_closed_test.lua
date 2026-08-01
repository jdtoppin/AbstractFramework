local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function makeSlot()
    local slot = {
        clearCount = 0,
        setCalls = {},
    }

    function slot:ClearAura()
        self.clearCount = self.clearCount + 1
    end

    function slot:SetAura(unit, auraInstanceID)
        self.setCalls[#self.setCalls + 1] = {unit, auraInstanceID}
    end

    return slot
end

local function findUpvalue(func, targetName)
    local index = 1
    while true do
        local name, value = debug.getupvalue(func, index)
        if not name then return nil end
        if name == targetName then return value end
        index = index + 1
    end
end

local function loadAuraHarness(interfaceVersion)
    local enumerationCalls = 0
    local filterCalls = 0

    local function makeFormatter()
        return setmetatable({}, {
            __index = function()
                return function() end
            end,
        })
    end

    local AF = {
        isRetail = true,
    }
    local environment = setmetatable({
        C_StringUtil = {
            CreateNumericRuleFormatter = makeFormatter,
            CreateSecondsFormatter = makeFormatter,
        },
        C_UnitAuras = {
            GetAuraApplicationDisplayCount = function() end,
            GetAuraDataByAuraInstanceID = function() end,
            GetAuraDispelTypeColor = function() end,
            GetAuraDuration = function() end,
            GetUnitAuraInstanceIDs = function()
                enumerationCalls = enumerationCalls + 1
                if interfaceVersion == nil or interfaceVersion >= 120100 then
                    error("Retail 12.1 legacy aura enumeration")
                end
                return {101}
            end,
            IsAuraFilteredOutByInstanceID = function()
                filterCalls = filterCalls + 1
                return false
            end,
        },
        Enum = {
            SecondsFormatterAbbreviation = {OneLetter = 1},
            SecondsFormatterInterval = {Seconds = 1, Days = 2},
            SecondsFormatterIntervalWhitespace = {Strip = 1},
            StatusBarInterpolation = {Immediate = 1},
            StatusBarTimerDirection = {ElapsedTime = 1},
            UnitAuraSortDirection = {Normal = 1},
            UnitAuraSortRule = {Default = 1},
        },
        GetBuildInfo = function()
            return "test", "test", "test", interfaceVersion
        end,
        Mixin = function(target, mixin)
            for key, value in pairs(mixin) do
                target[key] = value
            end
            return target
        end,
    }, {__index = _G})
    environment._G = environment

    environment.CreateFrame = function(_, name, parent)
        local frame = {
            name = name,
            parent = parent,
            registeredEvents = {},
            scripts = {},
            unregisterCount = 0,
        }

        function frame:RegisterUnitEvent(event, unit)
            self.registeredEvents[event] = unit
        end

        function frame:SetScript(script, callback)
            self.scripts[script] = callback
        end

        function frame:UnregisterAllEvents()
            self.registeredEvents = {}
            self.unregisterCount = self.unregisterCount + 1
        end

        return frame
    end

    local chunk = assert(loadfile("Widgets_UnitFrames/Aura.lua"))
    setfenv(chunk, environment)
    chunk("AbstractFramework", AF)

    return AF, function()
        return enumerationCalls, filterCalls
    end
end

local function testRetail12_1FailsClosed(interfaceVersion, label)
    local AF, getCallCounts = loadAuraHarness(interfaceVersion)
    local auraMixin = assert(findUpvalue(AF.InitAura, "AF_SecretAuraMixin"))
    local directAura = {clearCount = 0}
    function directAura:ClearAura()
        self.clearCount = self.clearCount + 1
    end
    auraMixin.SetAura(directAura, "player", 101)
    assertEqual(directAura.clearCount, 1,
        label .. " direct instance-ID aura clear")

    local auraList = AF.CreateSecretAuraList({}, "AFClosedAuras", "HARMFUL")
    local partition = {
        slots = {makeSlot()},
        numAuras = 1,
    }
    auraList.slots = {makeSlot(), makeSlot()}
    auraList.numAuras = 2
    auraList:SetMaxCount(2)
    auraList:SetPartitionFilter("HARMFUL|PLAYER", partition)
    auraList:SetPartitionEnabled(true)

    local beforeRefreshCount = 0
    local updateArgs
    function auraList:OnBeforeAurasRefresh()
        beforeRefreshCount = beforeRefreshCount + 1
    end
    function auraList:OnAurasUpdated(...)
        updateArgs = {n = select("#", ...), ...}
    end

    auraList:SetUnit("player")
    assertEqual(auraList.registeredEvents.UNIT_AURA, nil,
        label .. " UNIT_AURA registration")
    assertEqual(auraList.numAuras, 0, label .. " main count")
    assertEqual(partition.numAuras, 0, label .. " partition count")
    assertEqual(auraList.slots[1].clearCount, 1,
        label .. " main clear")
    assertEqual(partition.slots[1].clearCount, 1,
        label .. " partition clear")
    assertEqual(beforeRefreshCount, 0, label .. " pre-refresh hook")
    assertEqual(updateArgs.n, 3, label .. " update argument count")
    assertEqual(updateArgs[1], 0, label .. " total update count")
    assertEqual(updateArgs[2], 0, label .. " main update count")
    assertEqual(updateArgs[3], 0, label .. " partition update count")

    auraList:RefreshAuras()
    auraList.scripts.OnEvent(auraList, "UNIT_AURA", {})

    auraList.unit = nil
    auraList.numAuras = 1
    updateArgs = nil
    auraList:RefreshAuras()
    assertEqual(auraList.numAuras, 0,
        label .. " missing-unit stale count")
    assertEqual(updateArgs[1], 0,
        label .. " missing-unit update count")

    local enumerationCalls, filterCalls = getCallCounts()
    assertEqual(enumerationCalls, 0, label .. " enumeration calls")
    assertEqual(filterCalls, 0, label .. " filter calls")
end

local function testRetail12_0_7Compatibility()
    local AF, getCallCounts = loadAuraHarness(120007)
    local auraList = AF.CreateSecretAuraList({}, "AFLegacyAuras", "HARMFUL")
    auraList.slots = {makeSlot()}
    auraList:SetMaxCount(1)

    auraList:SetUnit("player")
    assertEqual(auraList.registeredEvents.UNIT_AURA, "player",
        "12.0.7 UNIT_AURA registration")
    assertEqual(auraList.numAuras, 1, "12.0.7 aura count")
    assertEqual(auraList.slots[1].setCalls[1][1], "player",
        "12.0.7 aura unit")
    assertEqual(auraList.slots[1].setCalls[1][2], 101,
        "12.0.7 aura instance ID")

    local enumerationCalls, filterCalls = getCallCounts()
    assertEqual(enumerationCalls, 1, "12.0.7 enumeration calls")
    assertEqual(filterCalls, 0, "12.0.7 filter calls")
end

testRetail12_1FailsClosed(120100, "12.1")
testRetail12_1FailsClosed(120200, "future Retail")
testRetail12_1FailsClosed(nil, "unknown Retail")
testRetail12_0_7Compatibility()

print("legacy aura Retail 12.1 fail-closed tests passed")
