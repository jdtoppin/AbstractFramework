local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local function assertBinding(binding, key, alt, ctrl, shift, message)
    assert(binding, message .. ": binding missing")
    assertEqual(binding.key, key, message .. ": key")
    assertEqual(not not binding.alt, not not alt, message .. ": alt")
    assertEqual(not not binding.ctrl, not not ctrl, message .. ": ctrl")
    assertEqual(not not binding.shift, not not shift, message .. ": shift")
end

local modifiers = {
    alt = false,
    ctrl = false,
    shift = false,
}
local inCombat
local regenEnabled

function InCombatLockdown()
    return inCombat
end

function IsAltKeyDown()
    return modifiers.alt
end

function IsControlKeyDown()
    return modifiers.ctrl
end

function IsShiftKeyDown()
    return modifiers.shift
end

ALT_KEY_TEXT = "Alt"
CTRL_KEY_TEXT = "Ctrl"
SHIFT_KEY_TEXT = "Shift"
NOT_BOUND = "Not Bound"

local keyText = {
    A = "A",
    K = "K",
    BUTTON1 = "Left Mouse Button",
    BUTTON2 = "Right Mouse Button",
    BUTTON3 = "Middle Mouse Button",
    BUTTON31 = "Mouse Button 31",
    MOUSEWHEELUP = "Mouse Wheel Up",
    MOUSEWHEELDOWN = "Mouse Wheel Down",
}

function GetBindingText(key)
    return keyText[key] or ""
end

function Mixin(object, mixin)
    for key, value in pairs(mixin) do
        object[key] = value
    end
    return object
end

local function NewFakeButton(parent, text, color, width, height)
    local button = {
        parent = parent,
        color = color,
        width = width,
        height = height,
        enabled = true,
        scripts = {},
        text = text,
    }

    function button:SetScript(script, callback)
        self.scripts[script] = callback
    end

    function button:HookScript(script, callback)
        local previous = self.scripts[script]
        self.scripts[script] = function(...)
            if previous then previous(...) end
            callback(...)
        end
    end

    function button:RunScript(script, ...)
        local callback = self.scripts[script]
        if callback then return callback(self, ...) end
    end

    function button:SetText(value)
        self.text = value
    end

    function button:GetText()
        return self.text
    end

    function button:SetTextJustifyH(justify)
        self.justifyH = justify
    end

    function button:EnableKeyboard(enabled)
        self.keyboardEnabled = enabled
    end

    function button:EnableMouseWheel(enabled)
        self.mouseWheelEnabled = enabled
    end

    function button:SetPropagateKeyboardInput(propagate)
        self.propagateKeyboardInput = propagate
    end

    function button:IsEnabled()
        return self.enabled
    end

    function button:LockHighlight()
        self.highlightLocked = true
    end

    function button:UnlockHighlight()
        self.highlightLocked = false
    end

    return button
end

local AF = {
    noop_false = function() return false end,
    CreateButton = NewFakeButton,
}
function AF.CreateBasicEventHandler(callback, event)
    assertEqual(event, "PLAYER_REGEN_ENABLED", "capture cleanup event")
    regenEnabled = callback
    return {}
end

local chunk = assert(loadfile("Widgets/BindingCapture.lua"))
chunk("AbstractFramework", AF)

-- Canonical structured values are copied, normalized, and strictly bounded.
local source = {key = " LeftButton ", alt = true, ctrl = false, shift = true, ignored = true}
local normalized = AF.NormalizeBinding(source)
assertBinding(normalized, "BUTTON1", true, false, true, "left-button normalization")
assert(normalized ~= source, "NormalizeBinding must not retain the caller table")
assertEqual(normalized.ignored, nil, "unknown binding fields")
assertBinding(AF.NormalizeBinding({key = "RightButton"}), "BUTTON2", false, false, false,
    "right-button normalization")
assertBinding(AF.NormalizeBinding({key = "MiddleButton"}), "BUTTON3", false, false, false,
    "middle-button normalization")
assertBinding(AF.NormalizeBinding({key = "Button04"}), "BUTTON4", false, false, false,
    "button number canonicalization")
for buttonNumber = 4, 31 do
    assertBinding(
        AF.NormalizeBinding({key = "Button" .. buttonNumber}),
        "BUTTON" .. buttonNumber,
        false,
        false,
        false,
        "extended button " .. buttonNumber
    )
end
assertBinding(AF.NormalizeBinding({key = "mousewheelup"}), "MOUSEWHEELUP", false, false, false,
    "wheel normalization")
assertBinding(AF.NormalizeBinding({key = "pagedown", ctrl = true}), "PAGEDOWN", false, true, false,
    "keyboard normalization")

for _, invalid in ipairs({
    nil,
    {},
    {key = ""},
    {key = "two words"},
    {key = "LALT"},
    {key = "BUTTON0"},
    {key = "BUTTON32"},
    {key = "BUTTONX"},
    {key = "MOUSEWHEELLEFT"},
    {key = "A", alt = 1},
}) do
    assertEqual(AF.NormalizeBinding(invalid), nil, "invalid binding rejection")
end

assert(AF.BindingEquals({key = "A", alt = true}, {key = "A", alt = true}),
    "equal bindings")
assert(not AF.BindingEquals({key = "A", alt = true}, {key = "A"}),
    "modifier inequality")
assert(AF.BindingEquals(nil, nil), "nil bindings")
assertEqual(AF.FormatBinding(nil), "Not Bound", "default empty display")
assertEqual(AF.FormatBinding(nil, "Unassigned"), "Unassigned", "custom empty display")
assertEqual(
    AF.FormatBinding({key = "Button1", alt = true, ctrl = true, shift = true}),
    "Alt + Ctrl + Shift + Left Mouse Button",
    "localized binding display order"
)

local capture = AF.CreateBindingCapture({}, 180, 24, "Unassigned", "Listening")
assertEqual(capture.width, 180, "capture width")
assertEqual(capture.height, 24, "capture height")
assertEqual(capture.justifyH, "CENTER", "capture text alignment")
assertEqual(capture:GetText(), "Unassigned", "initial placeholder")
assertEqual(capture.keyboardEnabled, false, "initial keyboard state")
assertEqual(capture.mouseWheelEnabled, false, "initial wheel state")

local changes = {}
local captureStates = {}
capture:SetOnBindingChanged(function(binding, self, oldBinding)
    changes[#changes + 1] = {
        binding = binding,
        self = self,
        oldBinding = oldBinding,
    }
end)
capture:SetOnCaptureChanged(function(capturing, self, cancelled)
    captureStates[#captureStates + 1] = {
        capturing = capturing,
        self = self,
        cancelled = cancelled,
    }
end)

capture:RunScript("OnClick", "LeftButton")
assert(capture:IsCapturing(), "click must start capture")
assertEqual(capture.keyboardEnabled, true, "capturing keyboard state")
assertEqual(capture.mouseWheelEnabled, true, "capturing wheel state")
assertEqual(capture.highlightLocked, true, "capturing highlight")
assertEqual(capture:GetText(), "Listening", "capture prompt")

modifiers.alt = true
capture:RunScript("OnKeyDown", "LALT")
assert(capture:IsCapturing(), "modifier-only key must not commit")
assertEqual(capture:GetText(), "Alt + Listening", "modifier preview")
capture:RunScript("OnKeyDown", "k")
assert(not capture:IsCapturing(), "keyboard commit must stop capture")
assertBinding(capture:GetBinding(), "K", true, false, false, "keyboard capture")
assertEqual(capture:GetText(), "Alt + K", "keyboard capture display")
assertEqual(capture.propagateKeyboardInput, false, "captured keyboard input propagation")
assertEqual(#changes, 1, "keyboard change callback count")
assertBinding(changes[1].binding, "K", true, false, false, "keyboard callback binding")
assertEqual(changes[1].self, capture, "keyboard callback widget")
assertEqual(changes[1].oldBinding, nil, "keyboard callback old binding")
changes[1].binding.key = "MUTATED"
assertBinding(capture:GetBinding(), "K", true, false, false, "callback copy isolation")

modifiers.alt = false
local returned = capture:GetBinding()
returned.key = "MUTATED_AGAIN"
assertBinding(capture:GetBinding(), "K", true, false, false, "getter copy isolation")

-- Programmatic updates are silent and invalid values do not disturb capture.
assert(capture:SetBinding({key = "a", ctrl = true}), "programmatic SetBinding")
assertBinding(capture:GetBinding(), "A", false, true, false, "programmatic binding")
assertEqual(#changes, 1, "programmatic SetBinding callback count")
capture:StartCapture()
assertEqual(capture:SetBinding({key = "Button32"}), false, "invalid SetBinding result")
assert(capture:IsCapturing(), "invalid SetBinding must preserve capture")
capture:RunScript("OnKeyDown", "ESCAPE")
assert(not capture:IsCapturing(), "Escape must cancel")
assertBinding(capture:GetBinding(), "A", false, true, false, "Escape preserves binding")
assertEqual(#changes, 1, "Escape callback count")
assertEqual(captureStates[#captureStates].cancelled, true, "Escape cancellation state")

-- Delete and Backspace clear, while user changes report the previous value.
capture:StartCapture()
capture:RunScript("OnKeyDown", "DELETE")
assertEqual(capture:GetBinding(), nil, "Delete clear")
assertEqual(capture:GetText(), "Unassigned", "Delete placeholder")
assertEqual(#changes, 2, "Delete callback count")
assertBinding(changes[2].oldBinding, "A", false, true, false, "Delete old binding")

capture:SetBinding({key = "A"})
capture:StartCapture()
capture:RunScript("OnKeyDown", "BACKSPACE")
assertEqual(capture:GetBinding(), nil, "Backspace clear")
assertEqual(#changes, 3, "Backspace callback count")

-- Mouse capture covers primary, extended, and wheel tokens with modifiers.
modifiers.shift = true
capture:StartCapture()
capture:RunScript("OnMouseDown", "LeftButton")
assertBinding(capture:GetBinding(), "BUTTON1", false, false, true, "left mouse capture")
capture:RunScript("OnClick", "LeftButton")
assert(not capture:IsCapturing(), "BUTTON1 OnClick suppression")

modifiers.shift = false
modifiers.ctrl = true
capture:StartCapture()
capture:RunScript("OnMouseDown", "RightButton")
assertBinding(capture:GetBinding(), "BUTTON2", false, true, false, "right mouse capture")

capture:StartCapture()
capture:RunScript("OnMouseDown", "MiddleButton")
assertBinding(capture:GetBinding(), "BUTTON3", false, true, false, "middle mouse capture")

capture:StartCapture()
capture:RunScript("OnMouseDown", "Button31")
assertBinding(capture:GetBinding(), "BUTTON31", false, true, false, "extended mouse capture")

capture:StartCapture()
capture:RunScript("OnMouseDown", "Button32")
assert(capture:IsCapturing(), "out-of-range mouse button must be ignored")
capture:RunScript("OnKeyDown", "ESCAPE")

capture:StartCapture()
capture:RunScript("OnMouseWheel", 1)
assertBinding(capture:GetBinding(), "MOUSEWHEELUP", false, true, false, "wheel-up capture")

capture:StartCapture()
capture:RunScript("OnMouseWheel", -1)
assertBinding(capture:GetBinding(), "MOUSEWHEELDOWN", false, true, false, "wheel-down capture")

-- Protected input toggles are deferred if combat begins during capture.
capture:StartCapture()
inCombat = true
assert(capture:CancelCapture(), "combat cancellation remains logical")
assertEqual(capture.keyboardEnabled, true,
    "combat cancellation defers protected keyboard teardown")
assertEqual(capture.mouseWheelEnabled, true,
    "combat cancellation defers protected wheel teardown")
assertEqual(capture.propagateKeyboardInput, true,
    "combat cancellation immediately restores key propagation")
assertEqual(capture:StartCapture(), false,
    "capture cannot begin during combat")
inCombat = false
regenEnabled()
assertEqual(capture.keyboardEnabled, false,
    "post-combat cleanup disables keyboard input")
assertEqual(capture.mouseWheelEnabled, false,
    "post-combat cleanup disables wheel input")

capture:StartCapture()
capture:RunScript("OnMouseWheel", 0)
assert(capture:IsCapturing(), "zero wheel delta must be ignored")
capture:CancelCapture()

-- Only one widget may capture globally; hiding or disabling cancels safely.
local second = AF.CreateBindingCapture({})
capture:StartCapture()
second:StartCapture()
assert(not capture:IsCapturing(), "starting another widget cancels the first")
assert(second:IsCapturing(), "second widget capture")
second:RunScript("OnHide")
assert(not second:IsCapturing(), "hide cancellation")

capture.enabled = false
assertEqual(capture:StartCapture(), false, "disabled capture start")
capture.enabled = true
capture:StartCapture()
capture.enabled = false
capture:RunScript("OnDisable")
assert(not capture:IsCapturing(), "disable cancellation")

print("binding capture tests passed")
