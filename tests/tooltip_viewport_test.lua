local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function newFrame(kind, name, parent, template)
    local frame = {
        kind = kind,
        lines = {},
        name = name,
        parent = parent,
        template = template,
    }

    function frame:AddDoubleLine(left, right)
        self.lines[#self.lines + 1] = {left, right}
    end

    function frame:AddLine(text)
        self.lines[#self.lines + 1] = text
    end

    function frame:ClearAllPoints()
        self.points = {}
    end

    function frame:ClearLines()
        self.lines = {}
    end

    function frame:GetParent()
        return self.parent
    end

    function frame:Hide()
        self.shown = false
    end

    function frame:RegisterEvent()
    end

    function frame:SetBackdropBorderColor()
    end

    function frame:SetBackdropColor()
    end

    function frame:SetCustomWordWrapMinWidth(width)
        self.wordWrapMinWidth = width
    end

    function frame:SetFrameStrata(strata)
        self.frameStrata = strata
    end

    function frame:SetOnHide(callback)
        self.onHide = callback
    end

    function frame:SetOnShow(callback)
        self.onShow = callback
    end

    function frame:SetOwner(owner, ...)
        self.nativeOwner = owner
        self.nativeOwnerArgs = {...}
    end

    function frame:SetPadding()
    end

    function frame:SetParent(nextParent)
        self.parent = nextParent
        self.parentSetCount = (self.parentSetCount or 0) + 1
    end

    function frame:SetPoint(...)
        self.points = {...}
    end

    function frame:Show()
        self.shown = true
    end

    function frame:UnregisterEvent()
    end

    return frame
end

local callbacks = {}
local AF = {
    UIParent = newFrame("Frame", "AFParent"),
    AddEventHandler = function()
    end,
    AddToPixelUpdater_OnShow = function()
    end,
    ApplyDefaultBackdrop = function()
    end,
    ClearPoints = function(frame)
        frame:ClearAllPoints()
    end,
    ConvertPixelsForRegion = function(value)
        return value
    end,
    GetColorRGB = function()
        return 1, 1, 1
    end,
    IsBlank = function(value)
        return value == nil or value == ""
    end,
    ReBorder = function()
    end,
    RegisterCallback = function(event, callback)
        callbacks[event] = callback
    end,
}

local environment = {
    AF_BaseWidgetMixin = {},
    AbstractFramework = AF,
    C_Item = {
        GetItemIconByID = function()
        end,
        GetItemQualityByID = function()
        end,
    },
    C_Spell = {
        GetSpellTexture = function()
        end,
    },
    CreateFrame = newFrame,
    EmbeddedItemTooltip_Hide = function()
    end,
    GameTooltip_ClearMoney = function()
    end,
    GameTooltip_ClearProgressBars = function()
    end,
    GameTooltip_ClearStatusBars = function()
    end,
    GameTooltip_ClearWidgetSet = function()
    end,
    GameTooltip_HideBattlePetTooltip = function()
    end,
    IsAltKeyDown = function()
        return false
    end,
    IsControlKeyDown = function()
        return false
    end,
    IsShiftKeyDown = function()
        return false
    end,
    Mixin = function(target, mixin)
        for key, value in pairs(mixin) do
            target[key] = value
        end
    end,
    TooltipComparisonManager = {
        Clear = function()
        end,
    },
    GameTooltip_ClearStatusBarWatch = function()
    end,
    strupper = string.upper,
    tinsert = table.insert,
}
setmetatable(environment, {__index = _G})
environment._G = environment

local chunk, loadError = loadfile("Widgets/Tooltip.lua")
assertEqual(type(chunk), "function", loadError or "tooltip module load")
setfenv(chunk, environment)
chunk("AbstractFramework", AF)

assertEqual(type(callbacks.AF_LOADED), "function",
    "tooltip creation callback is registered")
callbacks.AF_LOADED()

local scrollViewport = newFrame("ScrollFrame", "Viewport", AF.UIParent)
local scrollContent = newFrame("Frame", "ScrollContent", scrollViewport)
local optionControl = newFrame("CheckButton", "OptionControl", scrollContent)

AF.ShowTooltip(optionControl, "TOPLEFT", 0, 2, {"Title", "Body"})

assertEqual(AF.Tooltip:GetParent(), AF.UIParent,
    "tooltip stays outside the scroll viewport")
assertEqual(AF.Tooltip.parentSetCount, nil,
    "showing a tooltip does not reparent it into the hovered control")
assertEqual(AF.Tooltip.nativeOwner, optionControl,
    "native tooltip ownership still follows the hovered control")
assertEqual(AF.Tooltip.frameStrata, "TOOLTIP",
    "tooltip retains its overlay strata")
assertEqual(AF.Tooltip.points[1], "BOTTOMLEFT",
    "tooltip keeps the requested inverse anchor")
assertEqual(AF.Tooltip.points[2], optionControl,
    "tooltip remains anchored to the hovered control")
assertEqual(AF.Tooltip.lines[1], "Title",
    "tooltip retains its title")
assertEqual(AF.Tooltip.lines[2], "Body",
    "tooltip retains its wrapped body")

AF.Tooltip2:SetOwner(optionControl, "ANCHOR_NONE")
assertEqual(AF.Tooltip2:GetParent(), AF.UIParent,
    "secondary tooltip also stays outside the scroll viewport")
assertEqual(AF.Tooltip2.nativeOwner, optionControl,
    "secondary tooltip keeps native ownership")

print("tooltip viewport tests passed")
