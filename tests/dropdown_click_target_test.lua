local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local function assertTrue(value, message)
    assertEqual(not not value, true, message)
end

local function assertFalse(value, message)
    assertEqual(not not value, false, message)
end

tinsert = table.insert
tremove = table.remove
min = math.min

function wipe(target)
    for key in pairs(target) do
        target[key] = nil
    end
    return target
end

UISpecialFrames = {}
C_Timer = {NewTicker = function() end}

function Mixin(target, ...)
    for index = 1, select("#", ...) do
        for key, value in pairs(select(index, ...)) do
            target[key] = value
        end
    end
    return target
end

function hooksecurefunc(target, method, hook)
    local original = target[method]
    target[method] = function(self, ...)
        local results = {original(self, ...)}
        hook(self, ...)
        return unpack(results)
    end
end

local widgetMethods = {}

function widgetMethods:SetScript(script, callback)
    self.scripts[script] = callback
end

function widgetMethods:GetScript(script)
    return self.scripts[script]
end

function widgetMethods:HookScript(script, callback)
    local original = self.scripts[script]
    self.scripts[script] = function(...)
        if original then original(...) end
        callback(...)
    end
end

function widgetMethods:RunScript(script, ...)
    if script == "OnClick" and not self.enabled then return end
    local callback = self.scripts[script]
    if callback then return callback(self, ...) end
end

function widgetMethods:Show()
    if self.shown then return end
    self.shown = true
    self:RunScript("OnShow")
end

function widgetMethods:Hide()
    if not self.shown then return end
    self.shown = false
    self:RunScript("OnHide")
end

function widgetMethods:IsShown()
    return self.shown
end

function widgetMethods:SetEnabled(enabled)
    self.enabled = not not enabled
end

function widgetMethods:IsEnabled()
    return self.enabled
end

function widgetMethods:EnableMouse(enabled)
    self.mouseEnabled = not not enabled
end

function widgetMethods:IsMouseOver()
    return false
end

function widgetMethods:SetTexture(texture)
    self.texture = texture
end

function widgetMethods:SetText(text)
    self.value = text
end

function widgetMethods:SetColor(color)
    self.color = color
end

function widgetMethods:SetFont(font)
    self.font = font
end

function widgetMethods:SetColorTexture(...)
    self.colorTexture = {...}
end

function widgetMethods:SetVertexColor(...)
    self.vertexColor = {...}
end

function widgetMethods:SetDesaturated(desaturated)
    self.desaturated = desaturated
end

function widgetMethods:SetAlpha(alpha)
    self.alpha = alpha
end

function widgetMethods:SetJustifyH(justify)
    self.justify = justify
end

function widgetMethods:SetWordWrap(wordWrap)
    self.wordWrap = wordWrap
end

function widgetMethods:EnablePushEffect(enabled)
    self.pushEffect = enabled
end

function widgetMethods:SetTextJustifyH(justify)
    self.justify = justify
end

function widgetMethods:HideTexture()
    self.texture = nil
end

function widgetMethods:SetPoint(...)
    self.points[#self.points + 1] = {...}
end

function widgetMethods:ClearAllPoints()
    self.points = {}
end

function widgetMethods:SetAllPoints(relativeTo)
    self.allPoints = relativeTo or true
end

function widgetMethods:SetParent(parent)
    self.parent = parent
end

function widgetMethods:SetWidth(width)
    self.width = width
end

function widgetMethods:SetHeight(height)
    self.height = height
end

function widgetMethods:SetSize(width, height)
    self.width = width
    self.height = height
end

function widgetMethods:SetHitRectInsets(...)
    self.hitRectInsets = {...}
end

function widgetMethods:SetScale(scale)
    self.scale = scale
end

function widgetMethods:GetEffectiveScale()
    return 1
end

function widgetMethods:SetClampedToScreen() end
function widgetMethods:SetIgnoreParentScale() end
function widgetMethods:SetFrameStrata() end
function widgetMethods:RegisterEvent() end
function widgetMethods:UnregisterEvent() end
function widgetMethods:UpdatePixels() end
function widgetMethods:SetBackdropColor() end
function widgetMethods:SetBackdropBorderColor() end

local function newWidget(kind, parent)
    return setmetatable({
        kind = kind,
        parent = parent,
        scripts = {},
        points = {},
        shown = true,
        enabled = true,
    }, {__index = widgetMethods})
end

local verticalList

local AF = {
    UIParent = newWidget("uiParent"),
    L = setmetatable({}, {__index = function(_, key) return key end}),
}
AF.FrameSetWidth = widgetMethods.SetWidth
AF.FrameSetSize = widgetMethods.SetSize

function AF.CreateScrollList(parent)
    local list = newWidget("scrollList", parent)
    list.shown = false
    list.slotNum = 10
    list.scrollBar = newWidget("scrollBar", list)
    list.scrollThumb = newWidget("scrollThumb", list)
    list.slotFrame = newWidget("slotFrame", list)
    function list:Reset()
        for _, button in ipairs(self.buttons or {}) do
            button:Hide()
        end
    end
    function list:SetScroll(scroll) self.scroll = scroll end
    function list:SetSlotNum(slotNum) self.slotNum = slotNum end
    function list:SetWidgets(widgets) self.widgets = widgets end
    verticalList = list
    return list
end

function AF.CreateBorderedFrame(parent)
    return newWidget("borderedFrame", parent)
end

function AF.CreateButton(parent, text)
    local button = newWidget("button", parent)
    button.text = newWidget("buttonText", button)
    button.text.value = text
    return button
end

function AF.CreateFontString(parent, text)
    local fontString = newWidget("fontString", parent)
    fontString.value = text
    return fontString
end

function AF.CreateTexture(parent)
    return newWidget("texture", parent)
end

function AF.SetPoint(region, ...)
    region:SetPoint(...)
end

function AF.ClearPoints(region)
    region:ClearAllPoints()
end

function AF.SetSize(region, width, height)
    region:SetWidth(width)
    region:SetHeight(height)
end

function AF.SetWidth(region, width)
    region:SetWidth(width)
end

function AF.SetHeight(region, height)
    region:SetHeight(height)
end

function AF.SetAllPoints(region, relativeTo)
    region:SetAllPoints(relativeTo)
end

function AF.SetOnePixelInside(region, relativeTo)
    region:SetAllPoints(relativeTo)
end

function AF.SetListWidth() end
function AF.AddToFontSizeUpdater() end
function AF.SetTooltip() end
function AF.GetAddonAccentColorName() return "accent" end
function AF.GetColorRGB() return 1, 0.5, 0, 1 end
function AF.GetIcon(name) return name end
function AF.GetFontProps(name) return name end

local chunk = assert(loadfile("Widgets/Dropdown.lua"))
chunk("AbstractFramework", AF)

local dropdown = AF.CreateDropdown(AF.UIParent, 125)
dropdown:SetItems({
    {text = "Spell", value = "spell"},
    {text = "Target", value = "target"},
})

assertFalse(verticalList:IsShown(), "dropdown begins closed")
assertEqual(dropdown.button.hitRectInsets[1], -107,
    "standard dropdown arrow hit target reaches the field's left edge")
assertEqual(dropdown.button.hitRectInsets[2], 0,
    "standard dropdown hit target keeps its right edge")
assertEqual(dropdown:GetScript("OnMouseDown"), nil,
    "field clicking stays on the canonical dropdown button")

dropdown:SetWidth(60)
assertEqual(dropdown.button.hitRectInsets[1], -42,
    "direct width changes keep the hit target inside the dropdown")
dropdown:SetSize(80, 20)
assertEqual(dropdown.button.hitRectInsets[1], -62,
    "direct size changes also refresh the full-field hit target")
AF.SetWidth(dropdown, 70)
assertEqual(dropdown.button.hitRectInsets[1], -52,
    "pixel-helper width changes route through the dropdown wrapper")

dropdown.button:RunScript("OnClick", "LeftButton")
assertTrue(verticalList:IsShown(), "clicking the dropdown field opens the list")
assertEqual(dropdown.button.texture, "ArrowUp1", "field click updates the arrow")

dropdown.button:RunScript("OnClick", "LeftButton")
assertFalse(verticalList:IsShown(), "clicking the dropdown field again closes the list")
assertEqual(dropdown.button.texture, "ArrowDown1", "field toggle restores the arrow")

dropdown.button:RunScript("OnClick", "LeftButton")
assertTrue(verticalList:IsShown(), "clicking the arrow still opens the list")
assertEqual(dropdown.button.texture, "ArrowUp1", "arrow click keeps its open state")

dropdown:SetEnabled(false)
assertFalse(verticalList:IsShown(), "disabling an open dropdown closes its list")
dropdown.button:RunScript("OnClick", "LeftButton")
assertFalse(verticalList:IsShown(), "disabled dropdown field does not open the list")

dropdown:SetEnabled(true)
dropdown.button:RunScript("OnClick", "LeftButton")
assertTrue(verticalList:IsShown(), "re-enabled dropdown arrow opens the list")

local miniDropdown = AF.CreateDropdown(AF.UIParent, 100, 10, "vertical")
assertTrue(miniDropdown.button.allPoints,
    "mini dropdown keeps its existing full-field button")
assertEqual(miniDropdown.button.hitRectInsets, nil,
    "mini dropdown does not receive a redundant expanded hit target")

print("dropdown click target tests passed")
