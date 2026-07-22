---@class AbstractFramework
local AF = select(2, ...)

local UnitClassBase = UnitClassBase
local UnitIsConnected = UnitIsConnected
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType

local function SetConfiguredColor(bar, texture, config)
    if not config then return end

    local colorType = config.type
    local factor = colorType and colorType:find("_dark$") and 0.2 or 1
    local unit = bar.unit
    local r, g, b

    if colorType and colorType:find("^power") then
        local powerToken = select(2, UnitPowerType(unit))
        r, g, b = AF.GetPowerColor(powerToken, unit, nil, factor)
    elseif colorType and colorType:find("^mana") then
        r, g, b = AF.GetPowerColor("MANA", unit, nil, factor)
    elseif colorType and colorType:find("^class") then
        if AF.UnitIsPlayer(unit) then
            r, g, b = AF.GetClassColor(UnitClassBase(unit), nil, factor)
        else
            r, g, b = AF.GetReactionColor(unit, nil, factor)
        end
    elseif config.gradient == "disabled" then
        r, g, b = AF.UnpackColor(config.rgb)
    else
        local firstColor = config.rgb[1]
        local secondColor = config.rgb[2] or firstColor
        texture:SetGradient(
            config.gradient:find("^vertical") and "VERTICAL" or "HORIZONTAL",
            CreateColor(AF.UnpackColor(firstColor, config.alpha and config.alpha[1])),
            CreateColor(AF.UnpackColor(secondColor, config.alpha and config.alpha[2]))
        )
        return
    end

    if not UnitIsConnected(unit) then
        r, g, b = AF.GetColorRGB("OFFLINE")
    end
    texture:SetVertexColor(r, g, b, config.alpha or 1)
end

---@class AF_SecretPowerBar:AF_SecretStatusBar
local AF_SecretPowerBarMixin = {}

function AF_SecretPowerBarMixin:UpdatePower()
    self:SetValue(UnitPower(self.unit))
end

function AF_SecretPowerBarMixin:UpdatePowerMax()
    self:SetMinMaxValues(0, UnitPowerMax(self.unit))
end

function AF_SecretPowerBarMixin:UpdateColor()
    SetConfiguredColor(self, self.fill, self.fillColor)
    SetConfiguredColor(self, self.unfill, self.unfillColor)
end

function AF_SecretPowerBarMixin:UpdateAll()
    self:UpdateColor()
    self:UpdatePowerMax()
    self:UpdatePower()
end

function AF_SecretPowerBarMixin:SetupFillColor(config)
    self.fillColor = config
    if self.unit then self:UpdateColor() end
end

function AF_SecretPowerBarMixin:SetupUnfillColor(config)
    self.unfillColor = config
    if self.unit then self:UpdateColor() end
end

function AF_SecretPowerBarMixin:EnableFrequentUpdates(enabled)
    self.frequentUpdates = enabled
    if self.unit then self:RegisterUnitEvents() end
end

function AF_SecretPowerBarMixin:RegisterUnitEvents()
    self.eventFrame:UnregisterAllEvents()
    self.eventFrame:RegisterUnitEvent(self.frequentUpdates and "UNIT_POWER_FREQUENT" or "UNIT_POWER_UPDATE", self.unit)
    self.eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", self.unit)
    self.eventFrame:RegisterUnitEvent("UNIT_DISPLAYPOWER", self.unit)
    self.eventFrame:RegisterUnitEvent("UNIT_FACTION", self.unit)
end

function AF_SecretPowerBarMixin:SetUnit(unit)
    self.unit = unit
    self:RegisterUnitEvents()
    self:UpdateAll()
end

function AF_SecretPowerBarMixin:ClearUnit()
    self.eventFrame:UnregisterAllEvents()
    self.unit = nil
    self:SetMinMaxValues(0, 1)
    self:SetValue(0)
end

local function OnEvent(self, event)
    local bar = self.owner
    if event == "UNIT_MAXPOWER" then
        bar:UpdatePowerMax()
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
        bar:UpdatePower()
    else
        bar:UpdateAll()
    end
end

---@return AF_SecretPowerBar bar
function AF.CreateSecretPowerBar(parent, name)
    local bar = AF.CreateSecretStatusBar(parent, name)
    Mixin(bar, AF_SecretPowerBarMixin)

    bar.eventFrame = CreateFrame("Frame", nil, bar)
    bar.eventFrame.owner = bar
    bar.eventFrame:SetScript("OnEvent", OnEvent)

    return bar
end
