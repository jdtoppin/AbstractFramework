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

local function makeRegion(button)
    local region = {}

    local function style()
        assert(not button.denied, "styled a denied custom aura button")
        button.sequence = button.sequence + 1
        button.lastRegionStyleSequence = button.sequence
    end

    function region:SetAllPoints()
        style()
    end

    function region:SetColorTexture()
        style()
    end

    function region:SetTexCoord()
        style()
    end

    function region:SetDesaturated()
        style()
    end

    function region:SetTexture()
        style()
    end

    function region:SetShown()
        style()
    end

    function region:SetDrawBling()
        style()
    end

    function region:SetDrawEdge()
        style()
    end

    function region:SetUseAuraDisplayTime()
        style()
    end

    function region:SetTextColor()
        style()
    end

    function region:Hide()
        style()
    end

    return region
end

local function makeButton()
    local button = {
        bindings = {},
        denied = false,
        sequence = 0,
        lastRegionStyleSequence = 0,
    }

    local function style()
        assert(not button.denied, "styled a denied custom aura button")
        button.sequence = button.sequence + 1
        button.lastRegionStyleSequence = button.sequence
    end

    local function bind(name, ...)
        assert(not button.denied, "bound a denied custom aura button")
        button.sequence = button.sequence + 1
        button.firstBindingSequence = button.firstBindingSequence or button.sequence
        button.bindings[name] = pack(...)
    end

    function button:SetSize()
        style()
    end

    function button:CreateTexture()
        style()
        return makeRegion(button)
    end

    function button:CreateFontString()
        style()
        return makeRegion(button)
    end

    function button:SetIcon(...)
        bind("SetIcon", ...)
    end

    function button:SetDurationCooldown(...)
        bind("SetDurationCooldown", ...)
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

    return button
end

local function makeContainer(state)
    local container = {
        buttons = {},
        calls = {},
    }

    local function call(name, ...)
        record(container.calls, name, ...)
    end

    local function initialize(options)
        local button = makeButton()
        state.activeButton = button
        options.initializeFrame(button)
        state.activeButton = nil
        button.denied = true
        container.buttons[#container.buttons + 1] = button
        return button
    end

    function container:SetSize(...)
        call("SetSize", ...)
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
    }
    local environment = {}
    setmetatable(environment, {__index = _G})
    environment._G = environment

    local function forbiddenAuraEnumeration()
        error("12.1 adapter invoked manual C_UnitAuras enumeration", 2)
    end

    environment.C_UnitAuras = {
        GetAuraApplicationDisplayCount = forbiddenAuraEnumeration,
        GetAuraDataByAuraInstanceID = forbiddenAuraEnumeration,
        GetAuraDispelTypeColor = forbiddenAuraEnumeration,
        GetAuraDuration = forbiddenAuraEnumeration,
        GetUnitAuraInstanceIDs = forbiddenAuraEnumeration,
        IsAuraFilteredOutByInstanceID = forbiddenAuraEnumeration,
    }
    environment.C_StringUtil = {
        CreateNumericRuleFormatter = function()
            return {
                SetBreakpoints = function() end,
            }
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

            return binding
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
    environment.C_AuraContainerUtil = {
        ProcessCustomAuraButtonApplicationCountOptions = function() end,
        ProcessCustomAuraButtonDispelTypeTextureOptions = function() end,
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
    }

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
        environment.CreateFrame = function(frameType)
            if frameType == "AuraContainer" then
                local container = makeContainer(state)
                state.containers[#state.containers + 1] = container
                return container
            end
            assertEqual(frameType, "Cooldown", "created frame type")
            return makeRegion(state.activeButton)
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

local legacyFramework = loadAuraModule(false, true)
assertEqual(legacyFramework.HasCustomAuraContainer(), false, "legacy schema capability")

local AF, state, api = loadAuraModule(true, false)
assertEqual(AF.HasCustomAuraContainer(), true, "current schema capability")

local parent = {}
local container = AF.CreateCustomAuraContainer(parent, "AFTestAuraContainer")
assertEqual(state.containers[1], container, "created container")
assertCall(container.calls[1], "SetSize", 1, 1)

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
local buttonStyle = {
    width = 20,
    height = 18,
    iconInset = 1,
    desaturated = false,
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

local firstButton = container.buttons[1]
assert(firstButton.firstBindingSequence > firstButton.lastRegionStyleSequence,
    "custom aura regions were not fully styled before native registration")
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
assertCall(durationBinding.calls[1], "SetFormatter", findCall(durationBinding.calls, "SetFormatter").args[1])
assertCall(durationBinding.calls[2], "SetExpiredText", "0.0")
assertCall(durationBinding.calls[3], "SetZeroDurationText", "")
assertCall(durationBinding.calls[4], "SetUpdateInterval", 0)

local candidateFilters = {includeDispelTypes = {Magic = true}}
local groupLayout = {elementSpacing = 3, forceNewLine = true}
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

local slotOptions = {candidateFilters = {isBossAura = true}}
local slotButton = AF.AddCustomAuraSlot(container, "boss", "HARMFUL", slotOptions, buttonStyle)
assertEqual(slotButton, container.buttons[2], "slot return value")
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

local enchantmentButton = AF.AddCustomItemEnchantment(
    container,
    api.AuraContainerItemEnchantmentSlot.MainHand,
    {hidePermanent = true},
    buttonStyle
)
assertEqual(enchantmentButton, container.buttons[3], "enchantment return value")
assert(state.bindings[1] ~= state.bindings[2], "duration bindings must be button-local")
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

AF.SetCustomAuraContainerUnit(container, "player")
AF.UpdateCustomAuraContainer(container)
AF.SetCustomAuraContainerEnabled(container, true)
assertCall(findCall(container.calls, "SetUnit"), "SetUnit", "player")
assertCall(findCall(container.calls, "UpdateAllAuras"), "UpdateAllAuras")
assertCall(findCall(container.calls, "SetEnabled"), "SetEnabled", true)

-- Test-only pcall captures AF's expected non-secret reserved-option assertion.
local ok = pcall(AF.AddCustomAuraSlot, container, "invalid", "HELPFUL", {
    initializeFrame = function() end,
})
assertEqual(ok, false, "reserved initializeFrame must be rejected")

print("aura_container_12_1_test: OK")
