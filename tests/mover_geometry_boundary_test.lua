local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertTrue(value, message)
    assertEqual(value, true, message)
end

local function assertFalse(value, message)
    assertEqual(value, false, message)
end

local secret = setmetatable({}, {
    __add = function() error("secret arithmetic") end,
    __sub = function() error("secret arithmetic") end,
    __mul = function() error("secret arithmetic") end,
    __div = function() error("secret arithmetic") end,
    __lt = function() error("secret comparison") end,
    __le = function() error("secret comparison") end,
    __concat = function() error("secret concatenation") end,
    __tostring = function() return "<secret>" end,
})

local cursorX, cursorY = 100, 100
local shiftDown = false
local frames = {}
local editBoxes = {}
local dropdowns = {}

local Frame = {}
Frame.__index = Frame

local function NewFrame(name, parent)
    local frame = setmetatable({
        name = name,
        parent = parent,
        shown = true,
        scripts = {},
        width = 100,
        height = 40,
        centerX = 500,
        centerY = 400,
        left = 450,
        right = 550,
        top = 420,
        bottom = 380,
        scale = 1,
        effectiveScale = 1,
        clearCalls = 0,
        setPointCalls = 0,
    }, Frame)
    frames[#frames + 1] = frame
    return frame
end

function Frame:GetName()
    return self.name
end

function Frame:GetParent()
    return self.parent
end

function Frame:SetScript(script, callback)
    self.scripts[script] = callback
end

function Frame:GetScript(script)
    return self.scripts[script]
end

function Frame:HookScript(script, callback)
    local previous = self.scripts[script]
    self.scripts[script] = function(...)
        if previous then previous(...) end
        callback(...)
    end
end

function Frame:RunScript(script, ...)
    local callback = self.scripts[script]
    if callback then return callback(self, ...) end
end

function Frame:Show()
    local changed = not self.shown
    self.shown = true
    if changed then self:RunScript("OnShow") end
end

function Frame:Hide()
    local changed = self.shown
    self.shown = false
    if changed then self:RunScript("OnHide") end
end

function Frame:SetShown(shown)
    if shown then self:Show() else self:Hide() end
end

function Frame:IsShown()
    return self.shown
end

function Frame:SetPoint(point, relativeTo, relativePoint, x, y)
    if type(relativeTo) == "number" then
        x, y = relativeTo, relativePoint
        relativeTo = self.parent
        relativePoint = point
    elseif relativeTo == nil then
        relativeTo = self.parent
        relativePoint = point
        x, y = 0, 0
    elseif type(relativePoint) == "number" then
        x, y = relativePoint, x
        relativePoint = point
    end
    self.nativePoint = {
        point,
        relativeTo,
        relativePoint or point,
        x or 0,
        y or 0,
    }
    self.setPointCalls = self.setPointCalls + 1
end

function Frame:GetPoint()
    if self.pointOverride then
        return unpack(self.pointOverride)
    end
    if self.failGetPoint then error("unexpected native GetPoint") end
    if not self.nativePoint then return end
    return unpack(self.nativePoint)
end

function Frame:ClearAllPoints()
    self.clearCalls = self.clearCalls + 1
    self.nativePoint = nil
end

function Frame:SetAllPoints(relativeTo)
    self.allPointsTo = relativeTo or self.parent
end

function Frame:GetCenter()
    if self.allPointsTo then return self.allPointsTo:GetCenter() end
    return self.centerX, self.centerY
end

function Frame:GetSize()
    return self.width, self.height
end

function Frame:GetWidth()
    return self.width
end

function Frame:GetHeight()
    return self.height
end

function Frame:GetLeft()
    return self.left
end

function Frame:GetRight()
    return self.right
end

function Frame:GetTop()
    return self.top
end

function Frame:GetBottom()
    return self.bottom
end

function Frame:GetScale()
    return self.scale
end

function Frame:GetEffectiveScale()
    return self.effectiveScale
end

function Frame:SetText(text)
    self.text = text
end

function Frame:GetText()
    return self.text
end

function Frame:GetNumber()
    return tonumber(self.text) or 0
end

function Frame:SetFormattedText(format, ...)
    self.text = format:format(...)
end

function Frame:SetItems(items)
    self.items = items
end

function Frame:SetSelectedValue(value)
    self.selectedValue = value
end

function Frame:SetEnabled(enabled)
    self.enabledState = enabled
end

function Frame:GetWidthForText()
    return 100
end

function Frame:GetStringWidth()
    return 100
end

function Frame:GetStringHeight()
    return 20
end

function Frame:GetObjectType()
    return "Frame"
end

local noopMethods = {
    "SetBackdropColor",
    "SetBackdropBorderColor",
    "SetFrameLevel",
    "SetFrameStrata",
    "EnableMouse",
    "RegisterEvent",
    "UnregisterEvent",
    "SetClampedToScreen",
    "SetJustifyH",
    "SetSpacing",
    "RegisterForClicks",
    "ClearFocus",
    "SetColor",
    "SetTexture",
}
for _, method in ipairs(noopMethods) do
    Frame[method] = function() end
end

function Frame:SetOnEditFocusGained(callback)
    self.onEditFocusGained = callback
end

function Frame:SetOnEditFocusLost(callback)
    self.onEditFocusLost = callback
end

function Frame:SetOnEnterPressed(callback)
    self.onEnterPressed = callback
end

local uiParent = NewFrame("AFParent")
uiParent.width = 1000
uiParent.height = 800
uiParent.left = 0
uiParent.right = 1000
uiParent.top = 800
uiParent.bottom = 0
uiParent.centerX = 500
uiParent.centerY = 400

local AF = {
    L = setmetatable({}, {__index = function(_, key) return key end}),
    UIParent = uiParent,
    funcs = {
        isValueNonSecret = function(value)
            return value ~= secret
        end,
    },
}

function AF.CreateBorderedFrame(parent, name)
    return NewFrame(name, parent)
end

function AF.CreateHeaderedFrame(parent, name)
    return NewFrame(name, parent)
end

function AF.CreateFontString(parent, text)
    local fontString = NewFrame(nil, parent)
    fontString.text = text
    return fontString
end

function AF.CreateTexture(parent)
    return NewFrame(nil, parent)
end

function AF.CreateButton(parent, text)
    local button = NewFrame(nil, parent)
    button.text = text
    return button
end

function AF.CreateDropdown(parent)
    local dropdown = NewFrame(nil, parent)
    dropdown.button = NewFrame(nil, dropdown)
    dropdowns[#dropdowns + 1] = dropdown
    return dropdown
end

function AF.CreateEditBox(parent, text)
    local editBox = NewFrame(nil, parent)
    editBox.text = text
    editBoxes[#editBoxes + 1] = editBox
    return editBox
end

function AF.CreateTitledPane(parent)
    local pane = NewFrame(nil, parent)
    pane.line = NewFrame(nil, pane)
    function pane:SetTitle(title) self.title = title end
    return pane
end

function AF.GetColorRGB()
    return 1, 1, 1, 1
end

function AF.GetColorTable()
    return {1, 1, 1, 1}
end

function AF.GetAddonAccentColorName()
    return "accent"
end

function AF.GetIcon(icon)
    return icon
end

function AF.WrapTextInColor(text)
    return text
end

function AF.Round(value)
    return math.floor(value + 0.5)
end

function AF.RoundToDecimal(value, places)
    local multiplier = 10 ^ places
    return math.floor(value * multiplier + 0.5) / multiplier
end

function AF.Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function AF.SetSize(frame, width, height)
    if width then frame.width = width end
    if height then frame.height = height end
end

function AF.SetWidth(frame, width)
    frame.width = width
end

function AF.SetPoint(frame, ...)
    frame:SetPoint(...)
end

function AF.ClearPoints(frame)
    frame:ClearAllPoints()
end

function AF.RePoint(frame)
    local _, position = next(frame._points or {})
    if not position then return end
    frame:ClearAllPoints()
    frame:SetPoint(unpack(position))
end

function AF.ApplyDefaultBackdrop_NoBorder() end
function AF.RegisterCallback() end
function AF.CreateBlinkAnimation() end
function AF.UpdatePixelsForRegionAndChildren() end
function AF.CloseDropdown() end
function AF.FrameFadeIn() end
function AF.FrameFadeOut() end

local environment = {
    _G = false,
    AbstractFramework = AF,
    ALL = "All",
    CreateFrame = function(_, name, parent)
        return NewFrame(name, parent)
    end,
    C_Timer = {
        After = function(_, callback) callback() end,
    },
    InCombatLockdown = function() return false end,
    GetCursorPosition = function() return cursorX, cursorY end,
    IsShiftKeyDown = function() return shiftDown end,
    strfind = string.find,
    tinsert = table.insert,
    sort = table.sort,
    max = math.max,
    wipe = function(t)
        for key in pairs(t) do t[key] = nil end
    end,
}
setmetatable(environment, {__index = _G})
environment._G = environment

local chunk, loadError = loadfile("Widgets/Mover.lua")
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("AbstractFramework", AF)

AF.InitMoverParent()

local function NewOwner(name, point, x, y)
    local owner = NewFrame(name, AF.UIParent)
    owner:SetPoint(point, AF.UIParent, point, x, y)
    owner._points = {
        [point] = {point, AF.UIParent, point, x, y},
    }
    owner.clearCalls = 0
    owner.setPointCalls = 0
    return owner
end

local saves = 0
local validOwner = NewOwner("ValidOwner", "CENTER", 10.04, 20.06)
AF.CreateMover(validOwner, "Test", "Valid", function()
    saves = saves + 1
end)

local unanchoredOwner = NewFrame("UnanchoredOwner", AF.UIParent)
AF.CreateMover(unanchoredOwner, "Test", "Unanchored")

local malformedOwner = NewOwner("MalformedOwner", "CENTER", 1, 2)
malformedOwner._points.CENTER[3] = 17
AF.CreateMover(malformedOwner, "Test", "Malformed")

local secretOwner = NewOwner("SecretOwner", "CENTER", 1, 2)
secretOwner._points.CENTER[4] = secret
AF.CreateMover(secretOwner, "Test", "Secret")

validOwner.failGetPoint = true
AF.ShowMovers()
assertTrue(validOwner.mover:IsShown(), "ordinary ledger mover shown")
assertFalse(unanchoredOwner.mover:IsShown(), "unanchored mover skipped")
assertFalse(malformedOwner.mover:IsShown(), "malformed ledger mover skipped")
assertFalse(secretOwner.mover:IsShown(), "secret ledger mover skipped")
assertEqual(validOwner.mover._original[1], "CENTER", "captured point")
assertEqual(validOwner.mover._original[2], 10, "captured rounded x")
assertEqual(validOwner.mover._original[3], 20.1, "captured rounded y")
assertEqual(unanchoredOwner.mover._original, nil, "unavailable owner has no undo")
validOwner.failGetPoint = nil

local baselineClear = validOwner.clearCalls
local baselineSet = validOwner.setPointCalls
validOwner.effectiveScale = secret
validOwner.mover:RunScript("OnMouseDown", "LeftButton")
assertEqual(validOwner.mover.isDragging, nil, "secret effective scale blocks drag")
assertEqual(validOwner.clearCalls, baselineClear, "blocked drag does not clear points")
assertEqual(validOwner.setPointCalls, baselineSet, "blocked drag does not set points")
assertEqual(saves, 0, "blocked drag does not save")
validOwner.effectiveScale = 1

validOwner.pointOverride = {secret, secret, secret, secret, secret}
validOwner.mover:RunScript("OnMouseWheel", 1)
assertEqual(validOwner.clearCalls, baselineClear, "secret point blocks wheel mutation")
assertEqual(saves, 0, "secret point blocks wheel save")
validOwner.pointOverride = nil

validOwner.width = secret
validOwner.mover:RunScript("OnMouseWheel", 1)
assertEqual(validOwner.clearCalls, baselineClear, "secret size blocks wheel mutation")
assertEqual(saves, 0, "secret size blocks wheel save")
validOwner.width = 100

validOwner.width = math.huge
validOwner.mover:RunScript("OnMouseWheel", 1)
assertEqual(validOwner.clearCalls, baselineClear, "non-finite size blocks wheel mutation")
assertEqual(saves, 0, "non-finite size blocks wheel save")
validOwner.width = 100

validOwner.left = secret
local point = AF.CalcPoint(validOwner)
assertEqual(point, nil, "secret edge blocks point calculation")
assertEqual(saves, 0, "secret point calculation does not save")
validOwner.left = 450

validOwner.mover:RunScript("OnMouseUp", "RightButton")
assertEqual(#editBoxes, 2, "position editor edit boxes created")
assertEqual(#dropdowns, 2, "mover and anchor dropdowns created")

validOwner.scale = secret
editBoxes[1].onEnterPressed("25")
assertEqual(validOwner.clearCalls, baselineClear, "secret editor scale blocks mutation")
assertEqual(saves, 0, "secret editor scale blocks save")

for _, item in ipairs(dropdowns[2].items) do
    if item.value == "TOP" then item.onClick() end
end
assertEqual(validOwner.clearCalls, baselineClear, "secret repoint scale blocks mutation")
assertEqual(saves, 0, "secret repoint scale blocks save")
validOwner.scale = 1

cursorX, cursorY = 100, 100
validOwner.mover:RunScript("OnMouseDown", "LeftButton")
assertTrue(validOwner.mover.isDragging, "ordinary geometry begins drag")
cursorX, cursorY = 120, 110
validOwner.mover:RunScript("OnUpdate")
assertTrue(validOwner.mover.moved, "ordinary cursor update moves owner")

local savesBeforeFailedStop = saves
validOwner.scale = secret
validOwner.mover:RunScript("OnMouseUp", "LeftButton")
assertEqual(saves, savesBeforeFailedStop, "unavailable stop geometry does not save")
local restoredPoint, _, _, restoredX, restoredY = validOwner:GetPoint()
assertEqual(restoredPoint, "CENTER", "failed stop restores point")
assertEqual(restoredX, 10.04, "failed stop restores x")
assertEqual(restoredY, 20.06, "failed stop restores y")
validOwner.scale = 1

local clearBeforeCursorFailure = validOwner.clearCalls
validOwner.mover:RunScript("OnMouseDown", "LeftButton")
cursorX, cursorY = secret, secret
validOwner.mover:RunScript("OnUpdate")
assertEqual(validOwner.clearCalls, clearBeforeCursorFailure,
    "unavailable cursor before movement does not mutate")
assertEqual(validOwner.mover.isDragging, nil, "unavailable cursor cancels drag")
cursorX, cursorY = 100, 100

local savesBeforeUndo = saves
AF.UndoMovers()
assertEqual(saves, savesBeforeUndo + 1, "valid original remains undoable")
assertEqual(unanchoredOwner.clearCalls, 0, "unavailable mover ignored by undo")

print("mover_geometry_boundary_test.lua: ok")
