---@class AbstractFramework
local AF = select(2, ...)

-- Retail 12.0.7 (wow-ui-source 6e96727): SimpleStatusBar.SetValue and
-- SetMinMaxValues allow secret arguments, and their interpolation argument is
-- explicitly never secret. Keep all potentially secret bar values inside those
-- native methods; the Lua wrapper never reads or transforms them.
local Immediate = Enum.StatusBarInterpolation.Immediate
local ExponentialEaseOut = Enum.StatusBarInterpolation.ExponentialEaseOut

---@class AF_SecretStatusBar:AF_BaseStatusBar,Frame
local AF_SecretStatusBarMixin = {}

function AF_SecretStatusBarMixin:SetValue(value)
    self.innerBar:SetValue(value, self.interpolation)
end

AF_SecretStatusBarMixin.SetBarValue = AF_SecretStatusBarMixin.SetValue

function AF_SecretStatusBarMixin:SetMinMaxValues(minValue, maxValue)
    self.innerBar:SetMinMaxValues(minValue, maxValue, self.interpolation)
end

AF_SecretStatusBarMixin.SetBarMinMaxValues = AF_SecretStatusBarMixin.SetMinMaxValues

function AF_SecretStatusBarMixin:SetSmoothing(enabled)
    self.innerBar:SetToTargetValue()
    self.interpolation = enabled and ExponentialEaseOut or Immediate
end

function AF_SecretStatusBarMixin:ResetSmoothedValue()
    self.innerBar:SetToTargetValue()
end

function AF_SecretStatusBarMixin:GetValue()
    return self.innerBar:GetValue()
end

function AF_SecretStatusBarMixin:GetMinMaxValues()
    return self.innerBar:GetMinMaxValues()
end

---@return AF_SecretStatusBar bar
function AF.CreateSecretStatusBar(parent, name)
    local frame = CreateFrame("Frame", name, parent)
    Mixin(frame, AF_BaseWidgetMixin)
    Mixin(frame, AF_BaseStatusBarMixin)
    Mixin(frame, AF_SecretStatusBarMixin)

    local innerBar = CreateFrame("StatusBar", nil, frame)
    frame.innerBar = innerBar
    frame.bar = innerBar
    innerBar:SetStatusBarTexture(AF.GetEmptyTexture())
    AF.SetFrameLevel(innerBar, 0)

    local fill = frame:CreateTexture(nil, "ARTWORK", nil, -1)
    frame.fill = fill
    fill:SetAllPoints(innerBar)

    fill.mask = frame:CreateMaskTexture()
    fill.mask:SetTexture(AF.GetPlainTexture(), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
    fill.mask:SetAllPoints(innerBar:GetStatusBarTexture())
    fill:AddMaskTexture(fill.mask)

    local unfill = frame:CreateTexture(nil, "ARTWORK", nil, -1)
    frame.unfill = unfill
    unfill:SetAllPoints(innerBar)

    unfill.mask = frame:CreateMaskTexture()
    unfill.mask:SetTexture(AF.GetPlainTexture(), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
    unfill:AddMaskTexture(unfill.mask)

    local mod = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    frame.mod = mod
    mod:SetAllPoints(fill.mask)
    mod:SetColorTexture(0.6, 0.6, 0.6)
    mod:SetBlendMode("MOD")
    mod:Hide()

    frame.interpolation = Immediate
    frame:EnableBorder(true)
    frame:SetOrientation("left_to_right")
    frame:SetMinMaxValues(0, 1)
    frame:SetValue(0)

    AF.AddToPixelUpdater_Auto(frame, frame.DefaultUpdatePixels)

    return frame
end
