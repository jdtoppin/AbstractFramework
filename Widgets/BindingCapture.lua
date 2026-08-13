---@class AbstractFramework
local AF = select(2, ...)

local type = type
local tonumber = tonumber
local strupper = string.upper
local strmatch = string.match
local strfind = string.find
local strformat = string.format
local tconcat = table.concat

local IsAltKeyDown = IsAltKeyDown or AF.noop_false
local IsControlKeyDown = IsControlKeyDown or AF.noop_false
local IsShiftKeyDown = IsShiftKeyDown or AF.noop_false
local InCombatLockdown = InCombatLockdown or AF.noop_false
local GetBindingText = GetBindingText

local DEFAULT_PLACEHOLDER = _G.NOT_BOUND or "Not Bound"
local DEFAULT_CAPTURE_TEXT = AF.L and AF.L["Press a key or mouse button"] or "Press a key or mouse button"

local mouseAliases = {
    LEFTBUTTON = "BUTTON1",
    RIGHTBUTTON = "BUTTON2",
    MIDDLEBUTTON = "BUTTON3",
}

local modifierKeys = {
    ALT = true,
    LALT = true,
    RALT = true,
    CTRL = true,
    CONTROL = true,
    LCTRL = true,
    RCTRL = true,
    SHIFT = true,
    LSHIFT = true,
    RSHIFT = true,
    META = true,
    LMETA = true,
    RMETA = true,
}

-- Retail input contract verified against client 12.1.0.68914 and
-- jdtoppin/wow-ui-source commit d3915c78aba77a7a9be76acbfa35c674bbb6abe9:
-- SimpleFrame exposes EnableKeyboard/SetPropagateKeyboardInput, while
-- SimpleScriptRegion exposes EnableMouseWheel; UI.xsd declares OnKeyDown,
-- OnKeyUp, OnMouseDown, and OnMouseWheel scripts. Consumers should still use
-- this settings widget behind their normal combat-protection boundary.

---@class AF_Binding
---@field key string Canonical BUTTON1..BUTTON31, MOUSEWHEELUP/DOWN, or uppercase keyboard token.
---@field alt? boolean
---@field ctrl? boolean
---@field shift? boolean

local function Trim(value)
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function NormalizeKey(key)
    if type(key) ~= "string" then return end

    key = strupper(Trim(key))
    if key == "" or strfind(key, "%s") or modifierKeys[key] then return end

    key = mouseAliases[key] or key

    local buttonNumber = strmatch(key, "^BUTTON(%d+)$")
    if buttonNumber then
        buttonNumber = tonumber(buttonNumber)
        if buttonNumber < 1 or buttonNumber > 31 then return end
        return "BUTTON" .. buttonNumber
    elseif strfind(key, "^BUTTON") then
        return
    end

    if key == "MOUSEWHEELUP" or key == "MOUSEWHEELDOWN" then
        return key
    elseif strfind(key, "^MOUSEWHEEL") then
        return
    end

    return key
end

local function CopyBinding(binding)
    if not binding then return end

    local copy = {key = binding.key}
    if binding.alt then copy.alt = true end
    if binding.ctrl then copy.ctrl = true end
    if binding.shift then copy.shift = true end
    return copy
end

local function ToBoolean(value)
    return not not value
end

---Normalize a structured input binding without retaining the caller's table.
---Mouse keys use BUTTON1 (left), BUTTON2 (right), BUTTON3 (middle), and
---BUTTON4..BUTTON31. Wheel keys are MOUSEWHEELUP/DOWN. Keyboard keys use the
---uppercase token delivered by OnKeyDown. Alt, Ctrl, and Shift are separate
---booleans and are emitted in that display order.
---@param binding AF_Binding|nil
---@return AF_Binding|nil normalizedBinding
function AF.NormalizeBinding(binding)
    if type(binding) ~= "table" then return end

    if binding.alt ~= nil and type(binding.alt) ~= "boolean" then return end
    if binding.ctrl ~= nil and type(binding.ctrl) ~= "boolean" then return end
    if binding.shift ~= nil and type(binding.shift) ~= "boolean" then return end

    local key = NormalizeKey(binding.key)
    if not key then return end

    local normalized = {key = key}
    if binding.alt then normalized.alt = true end
    if binding.ctrl then normalized.ctrl = true end
    if binding.shift then normalized.shift = true end
    return normalized
end

---@param first AF_Binding|nil
---@param second AF_Binding|nil
---@return boolean equal
function AF.BindingEquals(first, second)
    if first == second then return true end
    if not first or not second then return false end

    return first.key == second.key
        and ToBoolean(first.alt) == ToBoolean(second.alt)
        and ToBoolean(first.ctrl) == ToBoolean(second.ctrl)
        and ToBoolean(first.shift) == ToBoolean(second.shift)
end

local function GetKeyText(key)
    if GetBindingText then
        local text = GetBindingText(key, "KEY_")
        if text and text ~= "" then return text end
    end

    local text = _G["KEY_" .. key]
    if text and text ~= "" then return text end

    if key == "BUTTON1" then
        return "Left Button"
    elseif key == "BUTTON2" then
        return "Right Button"
    elseif key == "BUTTON3" then
        return "Middle Button"
    elseif key == "MOUSEWHEELUP" then
        return "Mouse Wheel Up"
    elseif key == "MOUSEWHEELDOWN" then
        return "Mouse Wheel Down"
    end

    local buttonNumber = strmatch(key, "^BUTTON(%d+)$")
    if buttonNumber then
        return strformat("Button %s", buttonNumber)
    end

    return key
end

local function AddModifierText(parts, binding)
    if binding.alt then
        parts[#parts + 1] = _G.ALT_KEY_TEXT or "Alt"
    end
    if binding.ctrl then
        parts[#parts + 1] = _G.CTRL_KEY_TEXT or "Ctrl"
    end
    if binding.shift then
        parts[#parts + 1] = _G.SHIFT_KEY_TEXT or "Shift"
    end
end

---@param binding AF_Binding|nil
---@param emptyText? string
---@return string displayText
function AF.FormatBinding(binding, emptyText)
    binding = AF.NormalizeBinding(binding)
    if not binding then return emptyText or DEFAULT_PLACEHOLDER end

    local parts = {}
    AddModifierText(parts, binding)
    parts[#parts + 1] = GetKeyText(binding.key)
    return tconcat(parts, " + ")
end

local activeCapture
local pendingInputCleanup = {}

local function DisableCaptureInput(self)
    self:EnableKeyboard(false)
    self:EnableMouseWheel(false)
    self._inputCleanupPending = nil
    pendingInputCleanup[self] = nil
end

AF.CreateBasicEventHandler(function()
    for capture in pairs(pendingInputCleanup) do
        DisableCaptureInput(capture)
    end
end, "PLAYER_REGEN_ENABLED")

local function BuildBinding(key)
    local binding = {key = key}
    if IsAltKeyDown() then binding.alt = true end
    if IsControlKeyDown() then binding.ctrl = true end
    if IsShiftKeyDown() then binding.shift = true end
    return AF.NormalizeBinding(binding)
end

---@class AF_BindingCapture:AF_Button
local AF_BindingCaptureMixin = {}

local function UpdateBindingText(self)
    self:SetText(AF.FormatBinding(self.binding, self.placeholder))
end

local function UpdateCaptureText(self)
    local parts = {}
    AddModifierText(parts, {
        alt = IsAltKeyDown(),
        ctrl = IsControlKeyDown(),
        shift = IsShiftKeyDown(),
    })
    parts[#parts + 1] = self.captureText
    self:SetText(tconcat(parts, " + "))
end

local function StopCapture(self, cancelled)
    if not self._isCapturing then return false end

    self._isCapturing = nil
    if activeCapture == self then activeCapture = nil end
    if InCombatLockdown() then
        self._inputCleanupPending = true
        pendingInputCleanup[self] = true
        self:SetPropagateKeyboardInput(true)
    else
        DisableCaptureInput(self)
    end
    self:UnlockHighlight()
    UpdateBindingText(self)

    if self.onCaptureChanged then
        self.onCaptureChanged(false, self, cancelled)
    end
    return true
end

local function CommitBinding(self, binding)
    local oldBinding = CopyBinding(self.binding)
    self.binding = CopyBinding(binding)
    StopCapture(self, false)

    if not AF.BindingEquals(oldBinding, self.binding) and self.onBindingChanged then
        self.onBindingChanged(CopyBinding(self.binding), self, oldBinding)
    end
end

---@param binding AF_Binding|nil
---@return boolean accepted
function AF_BindingCaptureMixin:SetBinding(binding)
    local normalized = AF.NormalizeBinding(binding)
    if binding ~= nil and not normalized then return false end

    self:CancelCapture()
    self.binding = normalized
    UpdateBindingText(self)
    return true
end

---@return AF_Binding|nil binding
function AF_BindingCaptureMixin:GetBinding()
    return CopyBinding(self.binding)
end

function AF_BindingCaptureMixin:ClearBinding()
    return self:SetBinding(nil)
end

---@param callback? fun(binding:AF_Binding|nil, self:AF_BindingCapture, oldBinding:AF_Binding|nil)
function AF_BindingCaptureMixin:SetOnBindingChanged(callback)
    self.onBindingChanged = callback
end

---@param callback? fun(capturing:boolean, self:AF_BindingCapture, cancelled:boolean|nil)
function AF_BindingCaptureMixin:SetOnCaptureChanged(callback)
    self.onCaptureChanged = callback
end

---@param text? string
function AF_BindingCaptureMixin:SetPlaceholder(text)
    self.placeholder = text or DEFAULT_PLACEHOLDER
    if not self._isCapturing then UpdateBindingText(self) end
end

---@param text? string
function AF_BindingCaptureMixin:SetCaptureText(text)
    self.captureText = text or DEFAULT_CAPTURE_TEXT
    if self._isCapturing then UpdateCaptureText(self) end
end

---@return boolean started
function AF_BindingCaptureMixin:StartCapture()
    if self._isCapturing then return true end
    if InCombatLockdown() or not self:IsEnabled() then return false end

    if self._inputCleanupPending then DisableCaptureInput(self) end

    if activeCapture and activeCapture ~= self then
        activeCapture:CancelCapture()
    end

    activeCapture = self
    self._isCapturing = true
    self:EnableKeyboard(true)
    self:EnableMouseWheel(true)
    self:LockHighlight()
    UpdateCaptureText(self)

    if self.onCaptureChanged then
        self.onCaptureChanged(true, self)
    end
    return true
end

---@return boolean cancelled
function AF_BindingCaptureMixin:CancelCapture()
    return StopCapture(self, true)
end

---@return boolean capturing
function AF_BindingCaptureMixin:IsCapturing()
    return ToBoolean(self._isCapturing)
end

local function BindingCapture_OnClick(self, button)
    if button == "LeftButton" and self._ignoreNextLeftClick then
        self._ignoreNextLeftClick = nil
        return
    end
    self:StartCapture()
end

local function BindingCapture_OnMouseDown(self, button)
    if not self._isCapturing then return end
    if InCombatLockdown() then
        self:CancelCapture()
        return
    end

    local key = NormalizeKey(button)
    if not key or not strmatch(key, "^BUTTON%d+$") then return end

    if button == "LeftButton" then
        -- The same physical click invokes OnClick after OnMouseDown. Suppress
        -- that one OnClick so capturing BUTTON1 does not immediately restart.
        self._ignoreNextLeftClick = true
    end
    CommitBinding(self, BuildBinding(key))
end

local function BindingCapture_OnMouseWheel(self, delta)
    if not self._isCapturing or delta == 0 then return end
    if InCombatLockdown() then
        self:CancelCapture()
        return
    end
    local key = delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
    CommitBinding(self, BuildBinding(key))
end

local function BindingCapture_OnKeyDown(self, key)
    if not self._isCapturing then return end
    if InCombatLockdown() then
        self:CancelCapture()
        return
    end
    self:SetPropagateKeyboardInput(false)

    key = NormalizeKey(key)
    if not key then
        UpdateCaptureText(self)
        return
    end

    if key == "ESCAPE" then
        self:CancelCapture()
    elseif key == "DELETE" or key == "BACKSPACE" then
        CommitBinding(self, nil)
    else
        CommitBinding(self, BuildBinding(key))
    end
end

local function BindingCapture_OnKeyUp(self)
    if not self._isCapturing then return end
    self:SetPropagateKeyboardInput(false)
    UpdateCaptureText(self)
end

local function BindingCapture_Cancel(self)
    self:CancelCapture()
end

---Create a reusable input-capture button. User capture emits a structured
---binding through SetOnBindingChanged; programmatic SetBinding is silent.
---@param parent Frame
---@param width? number
---@param height? number
---@param placeholder? string
---@param captureText? string
---@return AF_BindingCapture capture
function AF.CreateBindingCapture(parent, width, height, placeholder, captureText)
    local capture = AF.CreateButton(parent, nil, "accent_hover", width or 150, height or 20)
    Mixin(capture, AF_BindingCaptureMixin)

    capture.placeholder = placeholder or DEFAULT_PLACEHOLDER
    capture.captureText = captureText or DEFAULT_CAPTURE_TEXT
    capture:SetTextJustifyH("CENTER")
    if not InCombatLockdown() then DisableCaptureInput(capture) end

    capture:SetScript("OnClick", BindingCapture_OnClick)
    capture:HookScript("OnMouseDown", BindingCapture_OnMouseDown)
    capture:SetScript("OnMouseWheel", BindingCapture_OnMouseWheel)
    capture:SetScript("OnKeyDown", BindingCapture_OnKeyDown)
    capture:SetScript("OnKeyUp", BindingCapture_OnKeyUp)
    capture:HookScript("OnDisable", BindingCapture_Cancel)
    capture:HookScript("OnHide", BindingCapture_Cancel)

    UpdateBindingText(capture)
    return capture
end
