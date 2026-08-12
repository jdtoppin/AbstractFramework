local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local function assertColor(region, expected, message)
    for index = 1, 4 do
        assertEqual(region.vertexColor[index], expected[index], message .. " channel " .. index)
    end
end

local createdFrames = {}
local createdTextures = {}

local textureMethods = {}

function textureMethods:SetColorTexture(r, g, b, a)
    self.colorTexture = {r, g, b, a}
end

function textureMethods:SetVertexColor(r, g, b, a)
    self.vertexColor = {r, g, b, a}
end

function textureMethods:SetPoint(...)
    self.points[#self.points + 1] = {...}
end

function textureMethods:ClearAllPoints()
    self.points = {}
end

function textureMethods:SetWidth(width)
    self.width = width
end

function textureMethods:SetHeight(height)
    self.height = height
end

function textureMethods:GetParent()
    return self.parent
end

function textureMethods:GetEffectiveScale()
    return 1
end

function textureMethods:Show()
    self.shown = true
end

function textureMethods:Hide()
    self.shown = false
end

local frameMethods = {}

function frameMethods:CreateTexture(_, layer, _, subLevel)
    local texture = setmetatable({
        parent = self,
        layer = layer,
        subLevel = subLevel,
        points = {},
    }, {__index = textureMethods})
    self.textures[#self.textures + 1] = texture
    createdTextures[#createdTextures + 1] = texture
    return texture
end

function frameMethods:SetSize(width, height)
    self.width = width
    self.height = height
end

function frameMethods:GetSize()
    return self.width, self.height
end

function frameMethods:SetWidth(width)
    self.width = width
end

function frameMethods:SetHeight(height)
    self.height = height
end

function frameMethods:GetWidth()
    return self.width
end

function frameMethods:GetHeight()
    return self.height
end

function frameMethods:SetPoint(...)
    self.points[#self.points + 1] = {...}
end

function frameMethods:ClearAllPoints()
    self.points = {}
end

function frameMethods:SetFrameLevel(level)
    self.frameLevel = level
end

function frameMethods:Show()
    self.shown = true
end

function frameMethods:Hide()
    self.shown = false
end

function frameMethods:SetCooldown(start, duration)
    self.cooldown = {start, duration}
end

function frameMethods:SetCooldownDuration(duration)
    self.cooldownDuration = duration
end

function frameMethods:GetParent()
    return self.parent
end

function frameMethods:GetName()
    return self.name
end

function frameMethods:GetEffectiveScale()
    return 1
end

function frameMethods:SetScript(scriptType)
    self.scripts[scriptType] = true
end

function frameMethods:ClearBackdrop()
    self.clearBackdropCalls = self.clearBackdropCalls + 1
end

CreateFrame = function(frameType, name, parent, template)
    local frame = setmetatable({
        frameType = frameType,
        name = name,
        parent = parent,
        template = template,
        textures = {},
        points = {},
        scripts = {},
        clearBackdropCalls = 0,
    }, {__index = frameMethods})
    createdFrames[#createdFrames + 1] = frame
    return frame
end

Mixin = function(target, ...)
    for index = 1, select("#", ...) do
        local mixin = select(index, ...)
        for key, value in pairs(mixin) do
            target[key] = value
        end
    end
end

local colors = {
    background = {0.10, 0.11, 0.12, 0.85},
    border = {0.20, 0.21, 0.22, 1},
    customBackground = {0.30, 0.31, 0.32, 0.75},
    customBorder = {0.40, 0.41, 0.42, 0.65},
}

local rePointCalls = {}
local reSizeCalls = {}
local registeredPixelFrame

local AF = {
    funcs = {
        isValueNonSecret = function()
            return true
        end,
    },
    GetColorRGB = function(name)
        return unpack(colors[name])
    end,
    GetAddonAccentColorName = function()
        return "accent"
    end,
    SetSize = function(region, width, height)
        if width then region:SetWidth(width) end
        if height then region:SetHeight(height) end
    end,
    SetWidth = function(region, width)
        region._width = width
        region:SetWidth(width)
    end,
    SetHeight = function(region, height)
        region._height = height
        region:SetHeight(height)
    end,
    SetPoint = function(region, ...)
        region._points = region._points or {}
        local point = select(1, ...)
        region._points[point] = {...}
        region:SetPoint(...)
    end,
    ClearPoints = function(region)
        region:ClearAllPoints()
        region._points = {}
    end,
    SetInside = function(region, relativeTo, offset)
        region:ClearAllPoints()
        region._points = {
            TOPLEFT = {"TOPLEFT", relativeTo, "TOPLEFT", offset, -offset},
            BOTTOMRIGHT = {"BOTTOMRIGHT", relativeTo, "BOTTOMRIGHT", -offset, offset},
        }
        region:SetPoint(unpack(region._points.TOPLEFT))
        region:SetPoint(unpack(region._points.BOTTOMRIGHT))
    end,
    RePoint = function(region)
        rePointCalls[#rePointCalls + 1] = region
    end,
    ReSize = function(region)
        reSizeCalls[#reSizeCalls + 1] = region
    end,
    DefaultUpdatePixels = function(frame)
        frame.defaultPixelUpdates = (frame.defaultPixelUpdates or 0) + 1
    end,
    AddToPixelUpdater_OnShow = function(frame)
        registeredPixelFrame = frame
        frame._pixelUpdateType = "onshow"
    end,
    CreateBasicEventHandler = function() end,
}

local baseChunk = assert(loadfile("Widgets/Base.lua"))
baseChunk("AbstractFramework", AF)

local frameChunk = assert(loadfile("Widgets/Frame.lua"))
frameChunk("AbstractFramework", AF)

-- Ignore the scratch Frame, Cooldown, and Texture created while Base.lua
-- captures native methods.
createdFrames = {}
createdTextures = {}

local parent = CreateFrame("Frame", "Parent")
local frame = AF.CreateLightweightBorderedFrame(
    parent,
    "LightweightFrame",
    120,
    80,
    "customBackground",
    "customBorder"
)

assertEqual(frame.template, nil, "no BackdropTemplate")
assertEqual(frame.width, 120, "frame width")
assertEqual(frame.height, 80, "frame height")
assertEqual(#frame.textures, 5, "one fill plus four borders")
assertEqual(frame.clearBackdropCalls, 1, "native backdrop cleared once")
assertEqual(registeredPixelFrame, frame, "on-show pixel registration")
assertEqual(frame._pixelUpdateType, "onshow", "pixel updater type")
assertEqual(frame.scripts.OnUpdate, nil, "no OnUpdate")
assertEqual(frame.scripts.OnSizeChanged, nil, "no OnSizeChanged")

local backdrop = frame._afLightweightBackdrop
assertEqual(backdrop.background.layer, "BACKGROUND", "fill layer")
assertEqual(#backdrop.borders, 4, "border count")
for _, border in ipairs(backdrop.borders) do
    assertEqual(border.layer, "BORDER", "border layer")
end
assertColor(backdrop.background, colors.customBackground, "initial background")
for _, border in ipairs(backdrop.borders) do
    assertColor(border, colors.customBorder, "initial border")
end

frame:SetBackdropColor(0.5, 0.6, 0.7)
assertColor(backdrop.background, {0.5, 0.6, 0.7, 1}, "compatible background setter")
local r, g, b, a = frame:GetBackdropColor()
assertEqual(r, 0.5, "background getter red")
assertEqual(g, 0.6, "background getter green")
assertEqual(b, 0.7, "background getter blue")
assertEqual(a, 1, "background getter alpha")

frame:SetBackdropBorderColor(0.7, 0.6, 0.5, 0.4)
for _, border in ipairs(backdrop.borders) do
    assertColor(border, {0.7, 0.6, 0.5, 0.4}, "compatible border setter")
end

local textureCount = #frame.textures
local reapplied = AF.ApplyLightweightBackdrop(frame)
assertEqual(reapplied, backdrop, "idempotent backdrop identity")
assertEqual(#frame.textures, textureCount, "idempotent region count")
assertEqual(frame.clearBackdropCalls, 1, "idempotent native clear")

frame:UpdatePixels()
assertEqual(frame.defaultPixelUpdates, 1, "frame pixel resnap")
assertEqual(#rePointCalls, 5, "backdrop point resnaps")
assertEqual(#reSizeCalls, 5, "backdrop size resnaps")

frame:SetBackgroundColor("background")
frame:SetBorderColor("border")
assertColor(backdrop.background, colors.background, "bordered-frame background mixin")
for _, border in ipairs(backdrop.borders) do
    assertColor(border, colors.border, "bordered-frame border mixin")
end

print("lightweight backdrop tests passed")
