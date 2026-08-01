local function pack(...)
    return {n = select("#", ...), ...}
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local function assertCall(call, name, ...)
    assert(call, "missing call " .. name)
    assertEqual(call.name, name, "call name")

    local expected = pack(...)
    assertEqual(call.args.n, expected.n, name .. " argument count")
    for index = 1, expected.n do
        assertEqual(call.args[index], expected[index], name .. " argument " .. index)
    end
end

local function findCall(calls, name)
    for _, call in ipairs(calls) do
        if call.name == name then
            return call
        end
    end
end

local function copy(...)
    local result = {}
    for index = 1, select("#", ...) do
        local source = select(index, ...)
        for key, value in pairs(source) do
            result[key] = type(value) == "table" and copy(value) or value
        end
    end
    return result
end

local function record(calls, name, ...)
    calls[#calls + 1] = {
        name = name,
        args = pack(...),
    }
end

local function assertScalarSnapshot(snapshot, message)
    for field, value in pairs(snapshot) do
        local valueType = type(value)
        assert(
            valueType == "number" or valueType == "boolean" or valueType == "string",
            ("%s.%s is not scalar"):format(message, field)
        )
    end
end

local function assertSnapshotEqual(actual, expected, message)
    for field, value in pairs(expected) do
        assertEqual(actual[field], value, message .. "." .. field)
    end
    for field, value in pairs(actual) do
        assertEqual(value, expected[field], message .. "." .. field)
    end
end

local function expectedConstructionTotals(overrides)
    local expected = {
        containerCreateAttempts = 0,
        containerAllocations = 0,
        containerCreateCompletions = 0,
        trackedContainers = 0,
        externalContainersObserved = 0,
        groupAddAttempts = 0,
        groupsAdded = 0,
        slotAddAttempts = 0,
        slotsAdded = 0,
        itemEnchantmentAddAttempts = 0,
        itemEnchantmentsAdded = 0,
        initialFrameReservationsAttempted = 0,
        initialFrameReservationsCompleted = 0,
    }
    for field, value in pairs(overrides or {}) do
        expected[field] = value
    end
    return expected
end

local function expectedConstructionStats(createdByAbstractFramework, overrides)
    local expected = expectedConstructionTotals(overrides)
    expected.trackedContainers = nil
    expected.externalContainersObserved = nil
    expected.createdByAbstractFramework = createdByAbstractFramework
    return expected
end

local function makeRegion(button)
    local region = {
        calls = {},
    }

    local function style(name, ...)
        assert(
            button:CanBeAccessedInContext(),
            "styled a child of an access-restricted custom aura button while auras are secret"
        )
        button.sequence = button.sequence + 1
        button.lastRegionStyleSequence = button.sequence
        record(region.calls, name, ...)
    end

    function region:SetAllPoints(...)
        self.allPoints = pack(...)
        style("SetAllPoints", ...)
    end

    function region:SetColorTexture(...)
        self.colorTexture = pack(...)
        style("SetColorTexture", ...)
    end

    function region:SetTexCoord(...)
        style("SetTexCoord", ...)
    end

    function region:SetDesaturated(...)
        style("SetDesaturated", ...)
    end

    function region:SetTexture(...)
        self.texture = ...
        style("SetTexture", ...)
    end

    function region:SetShown(shown)
        self.shown = shown
        style("SetShown", shown)
    end

    function region:SetDrawBling(...)
        style("SetDrawBling", ...)
    end

    function region:SetDrawEdge(drawEdge)
        self.drawEdge = drawEdge
        style("SetDrawEdge", drawEdge)
    end

    function region:SetUseAuraDisplayTime(...)
        style("SetUseAuraDisplayTime", ...)
    end

    function region:SetTextColor(...)
        style("SetTextColor", ...)
    end

    function region:Hide()
        self.shown = false
        style("Hide")
    end

    function region:Show()
        self.shown = true
        style("Show")
    end

    function region:SetHideCountdownNumbers(hide)
        self.hideCountdownNumbers = hide
        style("SetHideCountdownNumbers", hide)
    end

    function region:SetOrientation(orientation)
        self.orientation = orientation
        style("SetOrientation", orientation)
    end

    function region:SetReverseFill(reverse)
        self.reverseFill = reverse
        style("SetReverseFill", reverse)
    end

    function region:SetStatusBarTexture(texture)
        self.statusBarTexture = texture
        style("SetStatusBarTexture", texture)
    end

    function region:SetStatusBarColor(...)
        self.statusBarColor = pack(...)
        style("SetStatusBarColor", ...)
    end

    function region:SetTimerDuration(...)
        self.timerDuration = pack(...)
        style("SetTimerDuration", ...)
    end

    function region:SetCooldownFromDurationObject(...)
        self.cooldownDuration = pack(...)
        style("SetCooldownFromDurationObject", ...)
    end

    function region:Clear()
        style("Clear")
    end

    function region:SetText(...)
        self.text = ...
        style("SetText", ...)
    end

    function region:SetFrameLevel(...)
        self.frameLevel = pack(...)
        style("SetFrameLevel", ...)
    end

    function region:CreateTexture()
        style("CreateTexture")
        local child = makeRegion(button)
        button.regions[#button.regions + 1] = child
        return child
    end

    function region:CreateFontString()
        style("CreateFontString")
        local child = makeRegion(button)
        button.regions[#button.regions + 1] = child
        return child
    end

    return region
end

local function makeButton(state)
    local button = {
        accessRestricted = false,
        bindings = {},
        sequence = 0,
        lastRegionStyleSequence = 0,
        frames = {},
        regions = {},
        scripts = {},
    }

    local function canAccess()
        return not button.accessRestricted or not state.aurasSecret
    end

    local function assertAccessible(action)
        assert(
            canAccess(),
            action .. " an access-restricted custom aura button while auras are secret"
        )
    end

    local function style()
        assertAccessible("styled")
        button.sequence = button.sequence + 1
        button.lastRegionStyleSequence = button.sequence
    end

    local function bind(name, ...)
        assertAccessible("bound")
        button.sequence = button.sequence + 1
        button.firstBindingSequence = button.firstBindingSequence or button.sequence
        button.bindings[name] = pack(...)
    end

    function button:CanBeAccessedInContext()
        return canAccess()
    end

    function button:SetSize()
        style()
    end

    function button:ClearAllPoints()
        style()
        button.point = nil
    end

    function button:SetPoint(...)
        style()
        button.point = pack(...)
    end

    function button:CreateTexture()
        style()
        local region = makeRegion(button)
        button.regions[#button.regions + 1] = region
        return region
    end

    function button:CreateFontString()
        style()
        local region = makeRegion(button)
        button.regions[#button.regions + 1] = region
        return region
    end

    function button:SetIcon(...)
        bind("SetIcon", ...)
    end

    function button:SetDurationCooldown(...)
        bind("SetDurationCooldown", ...)
    end

    function button:SetDurationBar(...)
        bind("SetDurationBar", ...)
    end

    function button:SetDurationText(...)
        bind("SetDurationText", ...)
    end

    function button:SetApplicationCount(...)
        bind("SetApplicationCount", ...)
    end

    function button:AddDispelTypeTexture(...)
        bind("AddDispelTypeTexture", ...)
    end

    function button:EnableMouse(...)
        bind("EnableMouse", ...)
    end

    function button:SetTooltipAnchorPoint(...)
        bind("SetTooltipAnchorPoint", ...)
    end

    function button:SetHideTooltipInCombat(...)
        bind("SetHideTooltipInCombat", ...)
    end

    function button:SetCancelAuraButtons(...)
        bind("SetCancelAuraButtons", ...)
    end

    function button:SetShown(shown)
        assertAccessible("changed visibility on")
        self.shown = shown
    end

    function button:Show()
        assertAccessible("showed")
        self.shown = true
    end

    function button:Hide()
        assertAccessible("hid")
        self.shown = false
    end

    function button:SetScript(script, callback)
        assertAccessible("set a script on")
        self.scripts[script] = callback
    end

    return button
end

local function makeContainer(state)
    local container = {
        buttons = {},
        calls = {},
        failNextCall = nil,
    }

    local function call(name, ...)
        record(container.calls, name, ...)
        if container.failNextCall == name then
            container.failNextCall = nil
            error("forced " .. name .. " failure", 2)
        end
    end

    local function initialize(options)
        local button = makeButton(state)
        state.activeButton = button
        options.initializeFrame(button)
        state.activeButton = nil
        button.accessRestricted = true
        container.buttons[#container.buttons + 1] = button
        return button
    end

    function container:SetSize(...)
        call("SetSize", ...)
        if state.failNextContainerSetSize then
            state.failNextContainerSetSize = nil
            error("forced SetSize construction failure", 2)
        end
    end

    function container:SetUnit(...)
        call("SetUnit", ...)
    end

    function container:SetEnabled(...)
        call("SetEnabled", ...)
    end

    function container:UpdateAllAuras(...)
        call("UpdateAllAuras", ...)
    end

    function container:SetAuraProcessingPolicy(...)
        call("SetAuraProcessingPolicy", ...)
    end

    function container:SetFlowLayoutAxis(...)
        call("SetFlowLayoutAxis", ...)
    end

    function container:SetFlowLayoutAnchorPoint(...)
        call("SetFlowLayoutAnchorPoint", ...)
    end

    function container:SetFlowLayoutGrowthDirection(...)
        call("SetFlowLayoutGrowthDirection", ...)
    end

    function container:SetFlowLayoutPadding(...)
        call("SetFlowLayoutPadding", ...)
    end

    function container:SetFlowLayoutMaximumLineSize(...)
        call("SetFlowLayoutMaximumLineSize", ...)
    end

    function container:ResetFlowLayoutOptions(...)
        call("ResetFlowLayoutOptions", ...)
    end

    function container:AddAuraGroup(key, filterString, options)
        call("AddAuraGroup", key, filterString, options)
        initialize(options)
    end

    function container:SetAuraGroupFilterString(...)
        call("SetAuraGroupFilterString", ...)
    end

    function container:SetAuraGroupMaxFrameCount(...)
        call("SetAuraGroupMaxFrameCount", ...)
    end

    function container:SetAuraGroupCandidateFilters(...)
        call("SetAuraGroupCandidateFilters", ...)
    end

    function container:SetAuraGroupSortMethod(...)
        call("SetAuraGroupSortMethod", ...)
    end

    function container:SetAuraGroupLayout(...)
        call("SetAuraGroupLayout", ...)
    end

    function container:AddAuraSlot(key, filterString, options)
        call("AddAuraSlot", key, filterString, options)
        return initialize(options)
    end

    function container:SetAuraSlotFilterString(...)
        call("SetAuraSlotFilterString", ...)
    end

    function container:SetAuraSlotCandidateFilters(...)
        call("SetAuraSlotCandidateFilters", ...)
    end

    function container:SetAuraSlotSortMethod(...)
        call("SetAuraSlotSortMethod", ...)
    end

    function container:AddItemEnchantment(slot, options)
        call("AddItemEnchantment", slot, options)
        return initialize(options)
    end

    function container:SetItemEnchantmentSortMethod(...)
        call("SetItemEnchantmentSortMethod", ...)
    end

    function container:SetItemEnchantmentLayout(...)
        call("SetItemEnchantmentLayout", ...)
    end

    function container:ResetItemEnchantmentLayout(...)
        call("ResetItemEnchantmentLayout", ...)
    end

    return container
end

local function loadAuraModule(currentSchema, forbidCreateFrame)
    local state = {
        bindings = {},
        containers = {},
        durations = {},
        durationFormatters = {},
        auraFilterCalls = {},
        auraInstanceIDs = {},
        filteredOut = {},
        aurasSecret = false,
        inCombat = false,
        allowLegacyAuraEnumeration = false,
        auraDataProviderSwitchCalls = 0,
        auraDataProviderResetCalls = 0,
        plainTexture = {},
        squareBorderTexture = {},
    }
    local environment = {}
    setmetatable(environment, {__index = _G})
    environment._G = environment

    local function forbiddenAuraEnumeration()
        error("12.1 adapter invoked manual C_UnitAuras enumeration", 2)
    end

    local function getUnitAuraInstanceIDs(...)
        if not state.allowLegacyAuraEnumeration then
            return forbiddenAuraEnumeration()
        end
        record(state.auraFilterCalls, "GetUnitAuraInstanceIDs", ...)
        return state.auraInstanceIDs
    end

    local function isAuraFilteredOut(unit, auraInstanceID, filterString)
        if not state.allowLegacyAuraEnumeration then
            return forbiddenAuraEnumeration()
        end
        record(
            state.auraFilterCalls,
            "IsAuraFilteredOutByInstanceID",
            unit,
            auraInstanceID,
            filterString
        )
        local byFilter = state.filteredOut[filterString]
        return byFilter and byFilter[auraInstanceID] == true or false
    end

    environment.C_UnitAuras = {
        GetAuraApplicationDisplayCount = forbiddenAuraEnumeration,
        GetAuraDataByAuraInstanceID = forbiddenAuraEnumeration,
        GetAuraDispelTypeColor = forbiddenAuraEnumeration,
        GetAuraDuration = forbiddenAuraEnumeration,
        GetUnitAuraInstanceIDs = getUnitAuraInstanceIDs,
        IsAuraFilteredOutByInstanceID = isAuraFilteredOut,
        SwitchAuraDataProvider = function()
            state.auraDataProviderSwitchCalls = state.auraDataProviderSwitchCalls + 1
            error("adapter must not own the native aura data provider", 2)
        end,
        ResetAuraDataProvider = function()
            state.auraDataProviderResetCalls = state.auraDataProviderResetCalls + 1
            error("adapter must not own the native aura data provider", 2)
        end,
    }
    environment.C_StringUtil = {
        CreateNumericRuleFormatter = function()
            error("aura durations must use the native seconds formatter", 2)
        end,
        CreateSecondsFormatter = function()
            local calls = {}
            local formatter = {calls = calls}
            state.durationFormatters[#state.durationFormatters + 1] = formatter

            function formatter:SetDefaultAbbreviation(...)
                record(calls, "SetDefaultAbbreviation", ...)
            end

            function formatter:SetMinInterval(...)
                record(calls, "SetMinInterval", ...)
            end

            function formatter:SetMaxInterval(...)
                record(calls, "SetMaxInterval", ...)
            end

            function formatter:SetDesiredUnitCount(...)
                record(calls, "SetDesiredUnitCount", ...)
            end

            function formatter:SetCanRoundUpLastUnit(...)
                record(calls, "SetCanRoundUpLastUnit", ...)
            end

            function formatter:SetCanRoundUpIntervals(...)
                record(calls, "SetCanRoundUpIntervals", ...)
            end

            function formatter:SetMillisecondsThreshold(...)
                record(calls, "SetMillisecondsThreshold", ...)
            end

            function formatter:SetStripIntervalWhitespace(...)
                record(calls, "SetStripIntervalWhitespace", ...)
            end

            return formatter
        end,
    }
    environment.C_DurationUtil = {
        CreateDurationTextBinding = function()
            local calls = {}
            local binding = {calls = calls}
            state.bindings[#state.bindings + 1] = binding

            function binding:SetFormatter(...)
                record(calls, "SetFormatter", ...)
            end

            function binding:SetExpiredText(...)
                record(calls, "SetExpiredText", ...)
            end

            function binding:SetZeroDurationText(...)
                record(calls, "SetZeroDurationText", ...)
            end

            function binding:SetUpdateInterval(...)
                record(calls, "SetUpdateInterval", ...)
            end

            function binding:SetFontString(...)
                record(calls, "SetFontString", ...)
            end

            function binding:SetDuration(...)
                record(calls, "SetDuration", ...)
            end

            function binding:Enable(...)
                record(calls, "Enable", ...)
            end

            function binding:Disable(...)
                record(calls, "Disable", ...)
            end

            return binding
        end,
        CreateDuration = function()
            local duration = {
                calls = {},
            }
            state.durations[#state.durations + 1] = duration
            function duration:SetTimeFromStart(...)
                record(self.calls, "SetTimeFromStart", ...)
            end
            return duration
        end,
    }
    environment.C_CurveUtil = {
        CreateColorCurve = function()
            return {
                SetType = function() end,
                AddPoint = function() end,
            }
        end,
    }
    environment.CreateColor = function(...)
        return pack(...)
    end
    environment.InCombatLockdown = function()
        return state.inCombat
    end
    environment.C_AuraContainerUtil = {
        ProcessCustomAuraButtonApplicationCountOptions = function() end,
        ProcessCustomAuraButtonDispelTypeTextureOptions = function() end,
        ProcessCustomAuraButtonDurationBarOptions = function() end,
        ProcessCustomAuraButtonDurationTextOptions = function() end,
    }
    environment.AuraContainerSortMethod = {Default = 0}
    environment.AuraContainerSortDirection = {Normal = 0, Reverse = 1}
    environment.AuraContainerInbound = {}
    environment.AuraContainerItemEnchantmentSlot = {MainHand = 0}
    environment.AuraContainerItemEnchantmentSortMethod = {Slot = 0, Duration = 1}
    environment.CustomAuraContainerAuraProcessingPolicy = {None = 0, ProcessAura = 1}
    environment.CustomAuraContainerItemEnchantmentPlacement = {
        BeforeAuraGroups = 0,
        AfterAuraGroups = 1,
    }
    environment.CustomAuraContainerSlotDefaultOptions = {}
    environment.CustomAuraContainerItemEnchantmentDefaultOptions = {}
    environment.CustomAuraContainerItemEnchantmentLayoutDefaultOptions = {}
    environment.CustomAuraContainerGroupDefaultOptions = {}
    environment.AnchorUtil = {
        FlowLayoutAxis = {Horizontal = 0, Vertical = 1},
        FlowDirection = {Left = -1, Right = 1, Up = 1, Down = -1},
    }
    environment.Enum = {
        LuaCurveType = {Step = 1},
        CustomAuraButtonDispelTypeTextureStyle = {PreserveAsset = 4},
        SecondsFormatterAbbreviation = {OneLetter = 1},
        SecondsFormatterInterval = {Seconds = 1, Days = 4},
        SecondsFormatterIntervalWhitespace = {Strip = 1},
        StatusBarInterpolation = {Immediate = 0},
        StatusBarTimerDirection = {ElapsedTime = 0, RemainingTime = 1},
        UnitAuraSortRule = {Default = 0},
        UnitAuraSortDirection = {Normal = 0, Reverse = 1},
    }
    environment.Mixin = function(target, mixin)
        for key, value in pairs(mixin) do
            target[key] = value
        end
        return target
    end

    if currentSchema then
        environment.CustomAuraContainerLayoutDefaults = {
            axis = 0,
            anchorPoint = "TOPLEFT",
            horizontalGrowthDirection = 1,
            verticalGrowthDirection = -1,
            paddingLeft = 0,
            paddingRight = 0,
            paddingTop = 0,
            paddingBottom = 0,
            maximumLineSize = math.huge,
        }
        environment.CustomAuraContainerGroupLayoutDefaultOptions = {
            elementSpacing = 0,
            lineSpacing = 0,
            groupSpacing = 0,
            groupLineSpacing = 0,
            forceNewLine = false,
            elementWidth = 1,
            elementHeight = 1,
            layoutIndex = 1,
        }
    else
        environment.CustomAuraContainerLayoutDefaults = {
            rowWidth = 100,
        }
        environment.CustomAuraContainerGroupLayoutDefaultOptions = {
            elementSpacingX = 0,
            elementSpacingY = 0,
            forceNewRow = false,
        }
    end

    if forbidCreateFrame then
        environment.CreateFrame = function()
            error("capability detection probed CreateFrame", 2)
        end
    else
        environment.CreateFrame = function(frameType, _name, parent)
            if frameType == "AuraContainer" then
                if state.failNextAuraContainerCreation then
                    state.failNextAuraContainerCreation = nil
                    error("forced AuraContainer allocation failure", 2)
                end
                local container = makeContainer(state)
                state.containers[#state.containers + 1] = container
                return container
            end
            assert(
                frameType == "Cooldown"
                    or frameType == "StatusBar"
                    or frameType == "Frame",
                "unexpected created frame type " .. tostring(frameType)
            )
            local button = state.activeButton or parent
            if not button or not button.frames then
                local frame = {
                    scripts = {},
                }
                function frame:SetScript(script, callback)
                    self.scripts[script] = callback
                end
                function frame:UnregisterAllEvents()
                    self.events = nil
                end
                function frame:RegisterUnitEvent(event, unit)
                    self.events = {event, unit}
                end
                return frame
            end
            local frame = makeRegion(button)
            frame.frameType = frameType
            button.frames[#button.frames + 1] = frame
            return frame
        end
    end

    local framework = {
        Copy = copy,
        GetColorRGB = function()
            return 0.1, 0.2, 0.3, 1
        end,
        GetAuraTypeColor = function()
            return 1, 1, 1
        end,
        GetPlainTexture = function()
            return state.plainTexture
        end,
        GetTexture = function(texture)
            assertEqual(texture, "Border", "requested framework texture")
            return state.squareBorderTexture
        end,
        ApplyDefaultBackdrop = function() end,
        SetFrameLevel = function(frame, level, relativeTo)
            frame:SetFrameLevel(level, relativeTo)
        end,
        SetInside = function(region)
            region:SetAllPoints()
        end,
        SetSize = function(frame, width, height)
            frame:SetSize(width, height)
        end,
        SetFont = function() end,
        LoadTextPosition = function() end,
        UnpackColor = function(color)
            return unpack(color)
        end,
    }

    local chunk = assert(loadfile("Widgets_UnitFrames/Aura.lua"))
    setfenv(chunk, environment)
    chunk("AbstractFramework", framework)

    return framework, state, environment
end

local function assertDurationFormatter(state, api, message)
    assertEqual(#state.durationFormatters, 1, message .. " formatter count")
    local formatter = state.durationFormatters[1]
    assertCall(
        formatter.calls[1],
        "SetDefaultAbbreviation",
        api.Enum.SecondsFormatterAbbreviation.OneLetter
    )
    assertCall(formatter.calls[2], "SetMinInterval", api.Enum.SecondsFormatterInterval.Seconds)
    assertCall(formatter.calls[3], "SetMaxInterval", api.Enum.SecondsFormatterInterval.Days)
    assertCall(formatter.calls[4], "SetDesiredUnitCount", 1)
    assertCall(formatter.calls[5], "SetCanRoundUpLastUnit", false)
    assertCall(formatter.calls[6], "SetCanRoundUpIntervals", false)
    assertCall(formatter.calls[7], "SetMillisecondsThreshold", 60)
    assertCall(
        formatter.calls[8],
        "SetStripIntervalWhitespace",
        api.Enum.SecondsFormatterIntervalWhitespace.Strip
    )
    assertEqual(#formatter.calls, 8, message .. " formatter configuration call count")
    return formatter
end

local legacyFramework, legacyState, legacyApi = loadAuraModule(false, true)
assertDurationFormatter(legacyState, legacyApi, "legacy schema")
assertEqual(legacyFramework.HasCustomAuraContainer(), false, "legacy schema capability")
assertSnapshotEqual(
    legacyFramework.GetCustomAuraContainerConstructionTotals(),
    expectedConstructionTotals(),
    "legacy construction totals"
)

local AF, state, api = loadAuraModule(true, false)
local durationFormatter = assertDurationFormatter(state, api, "current schema")
assertEqual(AF.HasCustomAuraContainer(), true, "current schema capability")
assertSnapshotEqual(
    AF.GetCustomAuraContainerConstructionTotals(),
    expectedConstructionTotals(),
    "initial construction totals"
)

local unknownContainer = {}
assertEqual(
    AF.GetCustomAuraContainerConstructionStats(unknownContainer),
    nil,
    "unknown container stats"
)
assertSnapshotEqual(
    AF.GetCustomAuraContainerConstructionTotals(),
    expectedConstructionTotals(),
    "unknown lookup must not register"
)

local parent = {}
local container = AF.CreateCustomAuraContainer(parent, "AFTestAuraContainer")
assertEqual(state.containers[1], container, "created container")
assertCall(container.calls[1], "SetSize", 1, 1)
assertSnapshotEqual(
    AF.GetCustomAuraContainerConstructionTotals(),
    expectedConstructionTotals({
        containerCreateAttempts = 1,
        containerAllocations = 1,
        containerCreateCompletions = 1,
        trackedContainers = 1,
    }),
    "created container totals"
)
assertSnapshotEqual(
    AF.GetCustomAuraContainerConstructionStats(container),
    expectedConstructionStats(true, {
        containerCreateAttempts = 1,
        containerAllocations = 1,
        containerCreateCompletions = 1,
    }),
    "created container stats"
)

local mutableTotals = AF.GetCustomAuraContainerConstructionTotals()
local mutableStats = AF.GetCustomAuraContainerConstructionStats(container)
assertScalarSnapshot(mutableTotals, "construction totals")
assertScalarSnapshot(mutableStats, "container construction stats")
mutableTotals.containerAllocations = 900
mutableTotals.injected = {}
mutableStats.groupsAdded = 900
mutableStats.injected = {}
assertEqual(
    AF.GetCustomAuraContainerConstructionTotals().containerAllocations,
    1,
    "global snapshot mutation"
)
assertEqual(
    AF.GetCustomAuraContainerConstructionStats(container).groupsAdded,
    0,
    "container snapshot mutation"
)

local beforeContainerTuning = AF.GetCustomAuraContainerConstructionTotals()
AF.SetCustomAuraContainerFlowLayout(container, {
    axis = 1,
    anchorPoint = "BOTTOMRIGHT",
    paddingLeft = 2,
    maximumLineSize = 128,
})
assertCall(findCall(container.calls, "SetFlowLayoutAxis"), "SetFlowLayoutAxis", 1)
assertCall(findCall(container.calls, "SetFlowLayoutAnchorPoint"), "SetFlowLayoutAnchorPoint", "BOTTOMRIGHT")
assertCall(findCall(container.calls, "SetFlowLayoutGrowthDirection"), "SetFlowLayoutGrowthDirection", 1, -1)
assertCall(findCall(container.calls, "SetFlowLayoutPadding"), "SetFlowLayoutPadding", 2, 0, 0, 0)
assertCall(findCall(container.calls, "SetFlowLayoutMaximumLineSize"), "SetFlowLayoutMaximumLineSize", 128)
AF.ResetCustomAuraContainerFlowLayout(container)
assertCall(findCall(container.calls, "ResetFlowLayoutOptions"), "ResetFlowLayoutOptions")

local processingOptions = {ignoreBuffs = true}
AF.SetCustomAuraContainerProcessingPolicy(
    container,
    api.CustomAuraContainerAuraProcessingPolicy.ProcessAura,
    processingOptions
)
assertCall(findCall(container.calls, "SetAuraProcessingPolicy"), "SetAuraProcessingPolicy",
    api.CustomAuraContainerAuraProcessingPolicy.ProcessAura, processingOptions)
assertSnapshotEqual(
    AF.GetCustomAuraContainerConstructionTotals(),
    beforeContainerTuning,
    "container tuning must not grow construction"
)

local groupOptions = {
    maxFrameCount = 4,
    candidateFilters = {
        includeSpellIDs = {[12345] = true},
    },
    layout = {
        elementSpacing = 2,
        forceNewLine = false,
    },
}
local configuredBlockColor = {0.2, 0.3, 0.4, 0.6}
local buttonStyle = {
    width = 20,
    height = 18,
    iconInset = 1,
    desaturated = false,
    cooldownStyle = "block_clock_with_leading_edge",
    blockColor = configuredBlockColor,
    durationText = {
        enabled = true,
        font = {"font", 10, ""},
        position = {"CENTER"},
        color = {normal = {1, 1, 1, 1}},
    },
    stackText = {
        enabled = true,
        font = {"font", 10, ""},
        position = {"BOTTOMRIGHT"},
        color = {1, 1, 1, 1},
    },
    dispelColor = true,
    tooltip = {
        enabled = true,
        anchorPoint = "ANCHOR_TOPRIGHT",
        offsetX = 3,
        offsetY = -2,
        hideInCombat = true,
    },
    cancelAuraButtons = "RightButtonUp",
}
AF.AddCustomAuraGroup(container, "helpful", "HELPFUL", groupOptions, buttonStyle)

local groupCall = findCall(container.calls, "AddAuraGroup")
local copiedGroupOptions = groupCall.args[3]
assert(copiedGroupOptions ~= groupOptions, "group options were not copied")
assert(copiedGroupOptions.candidateFilters ~= groupOptions.candidateFilters, "nested group options were not copied")
assertEqual(groupOptions.initializeFrame, nil, "caller group options mutated")
assertEqual(buttonStyle.dispelColorCurve, nil, "caller button style mutated")
assertEqual(buttonStyle.blockColor, configuredBlockColor,
    "caller block color table replaced")
assertCall({
    name = "SetColorTexture",
    args = pack(unpack(buttonStyle.blockColor)),
}, "SetColorTexture", 0.2, 0.3, 0.4, 0.6)
assertSnapshotEqual(
    AF.GetCustomAuraContainerConstructionTotals(),
    expectedConstructionTotals({
        containerCreateAttempts = 1,
        containerAllocations = 1,
        containerCreateCompletions = 1,
        trackedContainers = 1,
        groupAddAttempts = 1,
        groupsAdded = 1,
        initialFrameReservationsAttempted = 10,
        initialFrameReservationsCompleted = 10,
    }),
    "group construction totals"
)

local beforeDeferredInitializers = AF.GetCustomAuraContainerConstructionTotals()
for _index = 1, 2 do
    local deferredButton = makeButton(state)
    state.activeButton = deferredButton
    copiedGroupOptions.initializeFrame(deferredButton)
    state.activeButton = nil
    deferredButton.accessRestricted = true
end
assertSnapshotEqual(
    AF.GetCustomAuraContainerConstructionTotals(),
    beforeDeferredInitializers,
    "deferred initializer calls must not grow construction"
)

local firstButton = container.buttons[1]
assert(firstButton.firstBindingSequence > firstButton.lastRegionStyleSequence,
    "custom aura regions were not fully styled before native registration")
assertEqual(firstButton.accessRestricted, true,
    "custom aura button access restriction installation")
assertEqual(firstButton:CanBeAccessedInContext(), true,
    "non-secret custom aura button access")
local nonSecretAccess = pcall(firstButton.SetSize, firstButton, 22, 20)
assertEqual(nonSecretAccess, true,
    "non-secret custom aura button API access")
state.aurasSecret = true
assertEqual(firstButton:CanBeAccessedInContext(), false,
    "secret custom aura button access")
local secretAccess = pcall(firstButton.SetSize, firstButton, 24, 20)
assertEqual(secretAccess, false,
    "secret custom aura button API denial")
state.aurasSecret = false
assertEqual(firstButton:CanBeAccessedInContext(), true,
    "restored non-secret custom aura button access")
local restoredAccess = pcall(firstButton.SetSize, firstButton, 26, 20)
assertEqual(restoredAccess, true,
    "restored custom aura button API access")
local icon = firstButton.bindings.SetIcon[1]
local cooldown = firstButton.bindings.SetDurationCooldown[1]
local nativeDispelOverlay = firstButton.bindings.AddDispelTypeTexture[1]
local blockBackground = firstButton.regions[4]
assertEqual(nativeDispelOverlay.texture, state.squareBorderTexture,
    "native dispel square border texture")
assertEqual(findCall(nativeDispelOverlay.calls, "SetTexCoord"), nil,
    "native dispel border must use the complete square asset")
local durationBarArguments = firstButton.bindings.SetDurationBar
assertEqual(durationBarArguments.n, 2, "duration bar binding argument count")
local durationBar = durationBarArguments[1]
local durationBarOptions = durationBarArguments[2]
assertEqual(durationBar.frameType, "StatusBar", "duration bar object type")
assertEqual(
    durationBarOptions.interpolation,
    api.Enum.StatusBarInterpolation.Immediate,
    "duration bar interpolation"
)
assertEqual(
    durationBarOptions.direction,
    api.Enum.StatusBarTimerDirection.ElapsedTime,
    "duration bar timer direction"
)
assertEqual(cooldown.hideCountdownNumbers, true, "cooldown countdown suppression")
assertEqual(cooldown.noCooldownCount, true, "third-party countdown suppression")
assertEqual(cooldown.shown, true, "block clock cooldown sweep visibility")
assertEqual(cooldown.drawEdge, true,
    "block clock leading-edge visibility")
assertEqual(findCall(cooldown.calls, "SetSwipeColor"), nil,
    "block clock native swipe color ownership")
assertEqual(durationBar.shown, false, "block clock duration bar visibility")
assertEqual(durationBar.orientation, "VERTICAL", "duration bar orientation")
assertEqual(durationBar.reverseFill, true, "duration bar reverse fill")
assertEqual(durationBar.statusBarTexture, state.plainTexture, "duration bar texture")
assertCall({
    name = "SetStatusBarColor",
    args = durationBar.statusBarColor,
}, "SetStatusBarColor", 0, 0, 0, 0.75)
assertCall({
    name = "SetColorTexture",
    args = blockBackground.colorTexture,
}, "SetColorTexture", 0.2, 0.3, 0.4, 0.6)
assertEqual(blockBackground.shown, true, "block clock background visibility")
assertEqual(icon.shown, false, "block clock icon visibility")
assertCall({
    name = "SetFrameLevel",
    args = cooldown.frameLevel,
}, "SetFrameLevel", 1, firstButton)
assertCall({
    name = "SetFrameLevel",
    args = durationBar.frameLevel,
}, "SetFrameLevel", 1, firstButton)
assertCall({
    name = "SetFrameLevel",
    args = firstButton.frames[3].frameLevel,
}, "SetFrameLevel", 2, firstButton)
local durationArguments = firstButton.bindings.SetDurationText
assertEqual(durationArguments.n, 2, "duration binding argument count")
local durationOptions = durationArguments[2]
assert(durationOptions.binding, "duration binding missing")
assertEqual(durationOptions.formatter, nil, "legacy duration formatter option")
assertEqual(durationOptions.expiredText, nil, "legacy expired-text option")
assertEqual(durationOptions.zeroDurationText, nil, "legacy zero-duration option")
assertEqual(durationOptions.updateInterval, nil, "legacy update-interval option")
assertEqual(firstButton.bindings.SetApplicationCount.n, 1, "application-count formatter must be absent")
local dispelOptions = firstButton.bindings.AddDispelTypeTexture[2]
assertEqual(dispelOptions.style, 4, "dispel texture style")
assertEqual(dispelOptions.showWhenHarmful, true, "harmful dispel texture")
assertEqual(dispelOptions.showWhenHelpful, false, "helpful dispel texture")
assertEqual(dispelOptions.showWithoutDispelType, false, "untyped dispel texture")
assertCall({
    name = "EnableMouse",
    args = firstButton.bindings.EnableMouse,
}, "EnableMouse", true)
assertCall({
    name = "SetTooltipAnchorPoint",
    args = firstButton.bindings.SetTooltipAnchorPoint,
}, "SetTooltipAnchorPoint", "ANCHOR_TOPRIGHT", 3, -2)
assertCall({
    name = "SetHideTooltipInCombat",
    args = firstButton.bindings.SetHideTooltipInCombat,
}, "SetHideTooltipInCombat", true)
assertCall({
    name = "SetCancelAuraButtons",
    args = firstButton.bindings.SetCancelAuraButtons,
}, "SetCancelAuraButtons", "RightButtonUp")

local durationBinding = durationOptions.binding
assertCall(durationBinding.calls[1], "SetFormatter", durationFormatter)
assertCall(durationBinding.calls[2], "SetExpiredText", "0.0")
assertCall(durationBinding.calls[3], "SetZeroDurationText", "")
assertCall(durationBinding.calls[4], "SetUpdateInterval", 0.1)

local candidateFilters = {includeDispelTypes = {Magic = true}}
local groupLayout = {elementSpacing = 3, forceNewLine = true}
local beforeGroupTuning = AF.GetCustomAuraContainerConstructionTotals()
AF.SetCustomAuraGroupFilterString(container, "helpful", "HELPFUL|PLAYER")
AF.SetCustomAuraGroupMaxFrameCount(container, "helpful", 6)
AF.SetCustomAuraGroupCandidateFilters(container, "helpful", candidateFilters)
AF.SetCustomAuraGroupSortMethod(
    container,
    "helpful",
    api.AuraContainerSortMethod.Default,
    api.AuraContainerSortDirection.Reverse
)
AF.SetCustomAuraGroupLayout(container, "helpful", groupLayout)
assertCall(findCall(container.calls, "SetAuraGroupFilterString"),
    "SetAuraGroupFilterString", "helpful", "HELPFUL|PLAYER")
assertCall(findCall(container.calls, "SetAuraGroupMaxFrameCount"), "SetAuraGroupMaxFrameCount", "helpful", 6)
assertCall(findCall(container.calls, "SetAuraGroupCandidateFilters"),
    "SetAuraGroupCandidateFilters", "helpful", candidateFilters)
assertCall(findCall(container.calls, "SetAuraGroupSortMethod"), "SetAuraGroupSortMethod",
    "helpful", api.AuraContainerSortMethod.Default, api.AuraContainerSortDirection.Reverse)
assertCall(findCall(container.calls, "SetAuraGroupLayout"), "SetAuraGroupLayout", "helpful", groupLayout)
assertSnapshotEqual(
    AF.GetCustomAuraContainerConstructionTotals(),
    beforeGroupTuning,
    "group tuning must not grow construction"
)

local slotAnchorTarget = {}
local slotOptions = {
    candidateFilters = {isBossAura = true},
    anchor = {
        point = "BOTTOMRIGHT",
        relativeTo = slotAnchorTarget,
        relativePoint = "TOPLEFT",
        x = 7,
        y = -9,
    },
}
local clockButtonStyle = copy(buttonStyle)
clockButtonStyle.cooldownStyle = "clock_with_leading_edge"
local slotButton = AF.AddCustomAuraSlot(
    container,
    "boss",
    "HARMFUL",
    slotOptions,
    clockButtonStyle
)
assertEqual(slotButton, container.buttons[2], "slot return value")
assertEqual(slotButton.point[1], "BOTTOMRIGHT", "slot anchor point")
assertEqual(slotButton.point[2], slotAnchorTarget, "slot anchor target identity")
assertEqual(slotButton.point[3], "TOPLEFT", "slot relative point")
assertEqual(slotButton.point[4], 7, "slot anchor x")
assertEqual(slotButton.point[5], -9, "slot anchor y")
local slotCall = findCall(container.calls, "AddAuraSlot")
assertEqual(slotCall.args[3].anchor, nil, "AF-only slot anchor forwarded natively")
assertEqual(slotOptions.anchor.relativeTo, slotAnchorTarget, "caller slot anchor mutated")
local slotIcon = slotButton.bindings.SetIcon[1]
local slotCooldown = slotButton.bindings.SetDurationCooldown[1]
local slotDurationBar = slotButton.bindings.SetDurationBar[1]
local slotBlockBackground = slotButton.regions[4]
assertEqual(slotCooldown.hideCountdownNumbers, true,
    "clock cooldown countdown suppression")
assertEqual(slotCooldown.noCooldownCount, true,
    "clock third-party countdown suppression")
assertEqual(slotCooldown.shown, true, "clock cooldown sweep visibility")
assertEqual(slotCooldown.drawEdge, true, "clock cooldown edge visibility")
assertEqual(slotDurationBar.shown, false, "clock duration bar visibility")
assertEqual(slotBlockBackground.shown, false,
    "ordinary clock block background visibility")
assertEqual(slotIcon.shown, true, "clock icon visibility")
assertSnapshotEqual(
    AF.GetCustomAuraContainerConstructionTotals(),
    expectedConstructionTotals({
        containerCreateAttempts = 1,
        containerAllocations = 1,
        containerCreateCompletions = 1,
        trackedContainers = 1,
        groupAddAttempts = 1,
        groupsAdded = 1,
        slotAddAttempts = 1,
        slotsAdded = 1,
        initialFrameReservationsAttempted = 11,
        initialFrameReservationsCompleted = 11,
    }),
    "slot construction totals"
)
local beforeSlotTuning = AF.GetCustomAuraContainerConstructionTotals()
AF.SetCustomAuraSlotFilterString(container, "boss", "HARMFUL|RAID")
AF.SetCustomAuraSlotCandidateFilters(container, "boss", candidateFilters)
AF.SetCustomAuraSlotSortMethod(
    container,
    "boss",
    api.AuraContainerSortMethod.Default,
    api.AuraContainerSortDirection.Normal
)
assertCall(findCall(container.calls, "SetAuraSlotFilterString"),
    "SetAuraSlotFilterString", "boss", "HARMFUL|RAID")
assertCall(findCall(container.calls, "SetAuraSlotCandidateFilters"),
    "SetAuraSlotCandidateFilters", "boss", candidateFilters)
assertCall(findCall(container.calls, "SetAuraSlotSortMethod"), "SetAuraSlotSortMethod",
    "boss", api.AuraContainerSortMethod.Default, api.AuraContainerSortDirection.Normal)
assertSnapshotEqual(
    AF.GetCustomAuraContainerConstructionTotals(),
    beforeSlotTuning,
    "slot tuning must not grow construction"
)

local defaultBlockButtonStyle = copy(buttonStyle)
defaultBlockButtonStyle.cooldownStyle = "block_vertical"
defaultBlockButtonStyle.blockColor = nil
local enchantmentButton = AF.AddCustomItemEnchantment(
    container,
    api.AuraContainerItemEnchantmentSlot.MainHand,
    {hidePermanent = true},
    defaultBlockButtonStyle
)
assertEqual(enchantmentButton, container.buttons[3], "enchantment return value")
assertEqual(defaultBlockButtonStyle.blockColor, nil,
    "caller default block color mutated")
local enchantmentIcon = enchantmentButton.bindings.SetIcon[1]
local enchantmentCooldown = enchantmentButton.bindings.SetDurationCooldown[1]
local enchantmentDurationBar = enchantmentButton.bindings.SetDurationBar[1]
local enchantmentBlockBackground = enchantmentButton.regions[4]
assertEqual(enchantmentCooldown.shown, false,
    "native block vertical cooldown visibility")
assertEqual(enchantmentDurationBar.shown, true,
    "native block vertical duration bar visibility")
assertCall({
    name = "SetStatusBarColor",
    args = enchantmentDurationBar.statusBarColor,
}, "SetStatusBarColor", 0, 0, 0, 0.75)
assertCall({
    name = "SetColorTexture",
    args = enchantmentBlockBackground.colorTexture,
}, "SetColorTexture", 0.5, 0.5, 0.5, 1)
assertEqual(enchantmentBlockBackground.shown, true,
    "native block vertical background visibility")
assertEqual(enchantmentIcon.shown, false,
    "native block vertical icon visibility")
assert(state.bindings[1] ~= state.bindings[2], "duration bindings must be button-local")
assertSnapshotEqual(
    AF.GetCustomAuraContainerConstructionTotals(),
    expectedConstructionTotals({
        containerCreateAttempts = 1,
        containerAllocations = 1,
        containerCreateCompletions = 1,
        trackedContainers = 1,
        groupAddAttempts = 1,
        groupsAdded = 1,
        slotAddAttempts = 1,
        slotsAdded = 1,
        itemEnchantmentAddAttempts = 1,
        itemEnchantmentsAdded = 1,
        initialFrameReservationsAttempted = 12,
        initialFrameReservationsCompleted = 12,
    }),
    "item enchantment construction totals"
)
local beforeEnchantmentTuning = AF.GetCustomAuraContainerConstructionTotals()
AF.SetCustomItemEnchantmentSortMethod(
    container,
    api.AuraContainerItemEnchantmentSortMethod.Duration,
    api.AuraContainerSortDirection.Reverse
)
local enchantmentLayout = {
    placement = api.CustomAuraContainerItemEnchantmentPlacement.AfterAuraGroups,
    elementSpacing = 2,
}
AF.SetCustomItemEnchantmentLayout(container, enchantmentLayout)
AF.ResetCustomItemEnchantmentLayout(container)
assertCall(findCall(container.calls, "SetItemEnchantmentSortMethod"),
    "SetItemEnchantmentSortMethod",
    api.AuraContainerItemEnchantmentSortMethod.Duration,
    api.AuraContainerSortDirection.Reverse)
assertCall(findCall(container.calls, "SetItemEnchantmentLayout"),
    "SetItemEnchantmentLayout", enchantmentLayout)
assertCall(findCall(container.calls, "ResetItemEnchantmentLayout"), "ResetItemEnchantmentLayout")
assertSnapshotEqual(
    AF.GetCustomAuraContainerConstructionTotals(),
    beforeEnchantmentTuning,
    "item enchantment tuning must not grow construction"
)

local beforeLifecycleTuning = AF.GetCustomAuraContainerConstructionTotals()
AF.SetCustomAuraContainerUnit(container, "player")
AF.UpdateCustomAuraContainer(container)
AF.SetCustomAuraContainerEnabled(container, true)
assertCall(findCall(container.calls, "SetUnit"), "SetUnit", "player")
assertCall(findCall(container.calls, "UpdateAllAuras"), "UpdateAllAuras")
assertCall(findCall(container.calls, "SetEnabled"), "SetEnabled", true)
assertSnapshotEqual(
    AF.GetCustomAuraContainerConstructionTotals(),
    beforeLifecycleTuning,
    "container lifecycle tuning must not grow construction"
)

local legacyAura = AF.InitAura(makeButton(state), true)
local legacyIcon = legacyAura.icon
local legacyCooldown = legacyAura.cooldown
local legacyDurationBar = legacyAura.durationBar
local legacyBlockBackground = legacyAura.blockBackground
local legacyDurationTextBinding = legacyAura.durationTextBinding
assertEqual(legacyAura.dispelOverlay.texture, state.squareBorderTexture,
    "legacy dispel square border texture")
assertEqual(findCall(legacyAura.dispelOverlay.calls, "SetTexCoord"), nil,
    "legacy dispel border must use the complete square asset")
assertEqual(legacyCooldown.hideCountdownNumbers, true,
    "legacy cooldown countdown suppression")
assertEqual(legacyCooldown.noCooldownCount, true,
    "legacy third-party countdown suppression")
assertEqual(legacyDurationBar.orientation, "VERTICAL",
    "legacy duration bar orientation")
assertEqual(legacyDurationBar.reverseFill, true,
    "legacy duration bar reverse fill")
assertCall({
    name = "SetColorTexture",
    args = legacyBlockBackground.colorTexture,
}, "SetColorTexture", 0.5, 0.5, 0.5, 1)
assertEqual(legacyBlockBackground.shown, false,
    "legacy initial block background visibility")
assertCall(
    findCall(legacyDurationTextBinding.calls, "SetFormatter"),
    "SetFormatter",
    durationFormatter
)
assertCall(
    findCall(legacyDurationTextBinding.calls, "SetUpdateInterval"),
    "SetUpdateInterval",
    0.1
)

legacyAura:SetCooldownStyle("vertical")
assertEqual(legacyCooldown.shown, false, "legacy vertical cooldown visibility")
assertEqual(legacyDurationBar.shown, true,
    "legacy vertical duration bar visibility")
assertEqual(legacyBlockBackground.shown, false,
    "legacy vertical block background visibility")
assertEqual(legacyIcon.shown, true, "legacy vertical icon visibility")
assertCall({
    name = "SetStatusBarColor",
    args = legacyDurationBar.statusBarColor,
}, "SetStatusBarColor", 0, 0, 0, 0.75)

local previewIcon = {}
legacyAura:SetCooldown(100, 25, 2, previewIcon)
local previewDuration = state.durations[#state.durations]
assertCall(previewDuration.calls[1], "SetTimeFromStart", 100, 25)
assertCall({
    name = "SetCooldownFromDurationObject",
    args = legacyCooldown.cooldownDuration,
}, "SetCooldownFromDurationObject", previewDuration)
assertCall({
    name = "SetTimerDuration",
    args = legacyDurationBar.timerDuration,
}, "SetTimerDuration",
    previewDuration,
    api.Enum.StatusBarInterpolation.Immediate,
    api.Enum.StatusBarTimerDirection.ElapsedTime)

local legacyBlockColor = {0.15, 0.25, 0.35, 0.45}
legacyAura:SetCooldownStyle("block_vertical", legacyBlockColor)
assertCall({
    name = "caller block color",
    args = pack(unpack(legacyBlockColor)),
}, "caller block color", 0.15, 0.25, 0.35, 0.45)
assertEqual(legacyCooldown.shown, false,
    "legacy block vertical cooldown visibility")
assertEqual(legacyDurationBar.shown, true,
    "legacy block vertical duration bar visibility")
assertEqual(legacyBlockBackground.shown, true,
    "legacy block vertical background visibility")
assertEqual(legacyIcon.shown, false,
    "legacy block vertical icon visibility")
assertCall({
    name = "SetStatusBarColor",
    args = legacyDurationBar.statusBarColor,
}, "SetStatusBarColor", 0, 0, 0, 0.75)
assertCall({
    name = "SetColorTexture",
    args = legacyBlockBackground.colorTexture,
}, "SetColorTexture", 0.15, 0.25, 0.35, 0.45)

legacyBlockColor[1] = 0.95
legacyAura:SetCooldown(200, 30, 3, previewIcon)
assertCall({
    name = "SetStatusBarColor",
    args = legacyDurationBar.statusBarColor,
}, "SetStatusBarColor", 0, 0, 0, 0.75)
assertCall({
    name = "SetColorTexture",
    args = legacyBlockBackground.colorTexture,
}, "SetColorTexture", 0.15, 0.25, 0.35, 0.45)
assertEqual(legacyBlockBackground.shown, true,
    "legacy timer refresh block vertical background visibility")

legacyAura:SetCooldownStyle("clock_with_leading_edge")
assertEqual(legacyCooldown.shown, true, "legacy clock cooldown visibility")
assertEqual(legacyCooldown.drawEdge, true, "legacy clock leading edge")
assertEqual(legacyDurationBar.shown, false,
    "legacy clock duration bar visibility")
assertEqual(legacyBlockBackground.shown, false,
    "legacy clock block background visibility")
assertEqual(legacyIcon.shown, true, "legacy clock icon visibility")

legacyAura:SetCooldownStyle("block_clock", {0.6, 0.4, 0.2, 0.8})
assertEqual(legacyCooldown.shown, true,
    "legacy block clock cooldown visibility")
assertEqual(legacyCooldown.drawEdge, false,
    "legacy block clock leading edge")
assertEqual(legacyDurationBar.shown, false,
    "legacy block clock duration bar visibility")
assertCall({
    name = "SetColorTexture",
    args = legacyBlockBackground.colorTexture,
}, "SetColorTexture", 0.6, 0.4, 0.2, 0.8)
assertEqual(legacyBlockBackground.shown, true,
    "legacy block clock background visibility")
assertEqual(legacyIcon.shown, false,
    "legacy block clock icon visibility")

legacyAura:SetCooldownStyle("none")
assertEqual(legacyCooldown.shown, false, "legacy no-cooldown visibility")
assertEqual(legacyDurationBar.shown, false,
    "legacy no-duration-bar visibility")
assertEqual(legacyBlockBackground.shown, false,
    "legacy no-cooldown block background visibility")
assertEqual(legacyIcon.shown, true, "legacy no-cooldown icon visibility")

local function makeAuraListSlot()
    local slot = {
        setCalls = {},
        clearCount = 0,
    }
    function slot:SetAura(...)
        self.setCalls[#self.setCalls + 1] = pack(...)
    end
    function slot:ClearAura()
        self.clearCount = self.clearCount + 1
    end
    return slot
end

state.allowLegacyAuraEnumeration = true
state.auraInstanceIDs = {101, 102, 103}
state.filteredOut.PLAYER = {
    [102] = true,
    [103] = true,
}
local auraList = AF.CreateSecretAuraList({}, "AFMatchRuleList", "HELPFUL")
auraList.unit = "target"
auraList.maxCount = 3
auraList.slots = {
    makeAuraListSlot(),
    makeAuraListSlot(),
    makeAuraListSlot(),
}
auraList:SetMatchFilters({"PLAYER"})
auraList:RefreshAuras()
assertEqual(auraList.numAuras, 1, "string match-filter count")
assertCall({
    name = "SetAura",
    args = auraList.slots[1].setCalls[1],
}, "SetAura", "target", 101)
assertEqual(#auraList.slots[2].setCalls, 0, "string filtered slot")

state.auraFilterCalls = {}
for _, slot in ipairs(auraList.slots) do
    slot.setCalls = {}
    slot.clearCount = 0
end
auraList:SetMatchFilters({
    {
        filterString = "PLAYER",
        matchWhenFilteredOut = true,
    },
})
auraList:RefreshAuras()
assertEqual(auraList.numAuras, 2, "complement match-filter count")
assertCall({
    name = "SetAura",
    args = auraList.slots[1].setCalls[1],
}, "SetAura", "target", 102)
assertCall({
    name = "SetAura",
    args = auraList.slots[2].setCalls[1],
}, "SetAura", "target", 103)
for _, call in ipairs(state.auraFilterCalls) do
    if call.name == "IsAuraFilteredOutByInstanceID" then
        assertEqual(call.args[3], "PLAYER",
            "complement match-filter C-side token")
    end
end

-- Test-only pcall verifies trusted descriptor validation; no aura values are
-- passed through these deterministic configuration assertions.
local invalidMatchRules = {
    {42},
    {{matchWhenFilteredOut = true}},
    {{filterString = "", matchWhenFilteredOut = true}},
    {{filterString = "PLAYER", matchWhenFilteredOut = false}},
    {{
        filterString = "PLAYER",
        matchWhenFilteredOut = true,
        predicate = function() end,
    }},
}
for index, matchRules in ipairs(invalidMatchRules) do
    local accepted = pcall(auraList.SetMatchFilters, auraList, matchRules)
    assertEqual(accepted, false, "invalid match-rule descriptor " .. index)
end
-- Existing string rules retain their prior permissive shape.
auraList:SetMatchFilters({""})

-- Test-only pcall captures AF's expected non-secret reserved-option assertion.
local beforeInvalidSlot = AF.GetCustomAuraContainerConstructionTotals()
local ok = pcall(AF.AddCustomAuraSlot, container, "invalid", "HELPFUL", {
    initializeFrame = function() end,
})
assertEqual(ok, false, "reserved initializeFrame must be rejected")
local afterInvalidSlot = AF.GetCustomAuraContainerConstructionTotals()
assertEqual(
    afterInvalidSlot.slotAddAttempts,
    beforeInvalidSlot.slotAddAttempts,
    "rejected slot native attempt count"
)
assertEqual(
    afterInvalidSlot.slotsAdded,
    beforeInvalidSlot.slotsAdded,
    "failed slot completion count"
)
assertEqual(
    afterInvalidSlot.initialFrameReservationsAttempted,
    beforeInvalidSlot.initialFrameReservationsAttempted,
    "rejected slot reservation attempt"
)
assertEqual(
    afterInvalidSlot.initialFrameReservationsCompleted,
    beforeInvalidSlot.initialFrameReservationsCompleted,
    "failed slot reservation completion"
)

local failureAF, failureState, failureAPI = loadAuraModule(true, false)

-- Test-only pcall captures deterministic wrapper failures and verifies that
-- attempts remain visible without turning diagnostics into an error boundary.
failureState.failNextAuraContainerCreation = true
local createOK = pcall(failureAF.CreateCustomAuraContainer, {})
assertEqual(createOK, false, "forced allocation failure")
assertSnapshotEqual(
    failureAF.GetCustomAuraContainerConstructionTotals(),
    expectedConstructionTotals({
        containerCreateAttempts = 1,
    }),
    "failed allocation totals"
)

failureState.failNextContainerSetSize = true
createOK = pcall(failureAF.CreateCustomAuraContainer, {})
assertEqual(createOK, false, "forced construction failure")
local partialContainer = failureState.containers[1]
assertSnapshotEqual(
    failureAF.GetCustomAuraContainerConstructionTotals(),
    expectedConstructionTotals({
        containerCreateAttempts = 2,
        containerAllocations = 1,
        trackedContainers = 1,
    }),
    "partial construction totals"
)
assertSnapshotEqual(
    failureAF.GetCustomAuraContainerConstructionStats(partialContainer),
    expectedConstructionStats(true, {
        containerCreateAttempts = 1,
        containerAllocations = 1,
    }),
    "partial construction stats"
)

local externalContainer = makeContainer(failureState)
local beforeExternalLookup = failureAF.GetCustomAuraContainerConstructionTotals()
assertEqual(
    failureAF.GetCustomAuraContainerConstructionStats(externalContainer),
    nil,
    "external container unknown before mutation"
)
assertSnapshotEqual(
    failureAF.GetCustomAuraContainerConstructionTotals(),
    beforeExternalLookup,
    "external getter must not register"
)

failureAF.SetCustomAuraContainerEnabled(externalContainer, false)
assertSnapshotEqual(
    failureAF.GetCustomAuraContainerConstructionStats(externalContainer),
    expectedConstructionStats(false),
    "external container stats"
)
local afterExternalTracking = failureAF.GetCustomAuraContainerConstructionTotals()
assertEqual(afterExternalTracking.trackedContainers, 2, "tracked external container")
assertEqual(afterExternalTracking.externalContainersObserved, 1, "observed external container")
failureAF.SetCustomAuraContainerFlowLayout(externalContainer, {})
assertSnapshotEqual(
    failureAF.GetCustomAuraContainerConstructionTotals(),
    afterExternalTracking,
    "external tuning must not grow construction"
)

externalContainer.failNextCall = "AddAuraGroup"
local groupOK = pcall(
    failureAF.AddCustomAuraGroup,
    externalContainer,
    "failedGroup",
    "HELPFUL"
)
assertEqual(groupOK, false, "forced group failure")

externalContainer.failNextCall = "AddAuraSlot"
local slotOK = pcall(
    failureAF.AddCustomAuraSlot,
    externalContainer,
    "failedSlot",
    "HARMFUL",
    {
        sortMethod = failureAPI.AuraContainerSortMethod.Default,
        sortDirection = failureAPI.AuraContainerSortDirection.Normal,
    }
)
assertEqual(slotOK, false, "forced slot failure")

externalContainer.failNextCall = "AddItemEnchantment"
local enchantmentOK = pcall(
    failureAF.AddCustomItemEnchantment,
    externalContainer,
    failureAPI.AuraContainerItemEnchantmentSlot.MainHand
)
assertEqual(enchantmentOK, false, "forced item enchantment failure")
assertSnapshotEqual(
    failureAF.GetCustomAuraContainerConstructionTotals(),
    expectedConstructionTotals({
        containerCreateAttempts = 2,
        containerAllocations = 1,
        trackedContainers = 2,
        externalContainersObserved = 1,
        groupAddAttempts = 1,
        slotAddAttempts = 1,
        itemEnchantmentAddAttempts = 1,
        initialFrameReservationsAttempted = 12,
    }),
    "failed add totals"
)

assertEqual(
    failureAF.ResetCustomAuraContainerConstructionTotals,
    nil,
    "construction totals reset API"
)
assertEqual(
    failureAF.ResetCustomAuraContainerConstructionStats,
    nil,
    "container construction reset API"
)
assertEqual(state.auraDataProviderSwitchCalls, 0, "native provider switch ownership")
assertEqual(state.auraDataProviderResetCalls, 0, "native provider reset ownership")
assertEqual(failureState.auraDataProviderSwitchCalls, 0, "failure provider switch ownership")
assertEqual(failureState.auraDataProviderResetCalls, 0, "failure provider reset ownership")

local combatAF, combatState = loadAuraModule(true, false)
combatState.inCombat = true
combatState.aurasSecret = true
local combatContainer = combatAF.CreateCustomAuraContainer(
    {},
    "AFCombatAuraContainer",
    "player"
)
combatAF.AddCustomAuraGroup(
    combatContainer,
    "combatHelpful",
    "HELPFUL",
    {maxFrameCount = 1},
    {
        noBorder = true,
        width = 16,
        height = 16,
        cooldownStyle = "none",
    }
)
assertEqual(combatContainer.buttons[1].accessRestricted, true,
    "combat-created aura button access restriction installation")
assertEqual(combatContainer.buttons[1]:CanBeAccessedInContext(), false,
    "combat-created aura button secret access")
assertSnapshotEqual(
    combatAF.GetCustomAuraContainerConstructionTotals(),
    expectedConstructionTotals({
        containerCreateAttempts = 1,
        containerAllocations = 1,
        containerCreateCompletions = 1,
        trackedContainers = 1,
        groupAddAttempts = 1,
        groupsAdded = 1,
        initialFrameReservationsAttempted = 10,
        initialFrameReservationsCompleted = 10,
    }),
    "combat container construction totals"
)
combatState.aurasSecret = false
assertEqual(combatContainer.buttons[1]:CanBeAccessedInContext(), true,
    "combat-created aura button restored access")
local combatRestoredAccess = pcall(
    combatContainer.buttons[1].SetSize,
    combatContainer.buttons[1],
    18,
    18
)
assertEqual(combatRestoredAccess, true,
    "combat-created aura button restored API access")

print("aura_container_12_1_test: OK")
