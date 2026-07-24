---@class AbstractFramework
local AF = select(2, ...)
local F = AF.funcs

local UnitClassBase = UnitClassBase
local UnitClassification = UnitClassification
local UnitEffectiveLevel = UnitEffectiveLevel
local UnitGetDetailedHealPrediction = UnitGetDetailedHealPrediction
local UnitHasVehicleUI = UnitHasVehicleUI
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitIsCharmed = UnitIsCharmed
local UnitIsConnected = UnitIsConnected
local UnitIsBossMob = UnitIsBossMob
local UnitIsLieutenant = UnitIsLieutenant
local UnitIsTapDenied = UnitIsTapDenied
local UnitPowerType = UnitPowerType
local UnitPlayerControlled = UnitPlayerControlled
local UnitSelectionColor = UnitSelectionColor

local Mana = Enum.PowerType.Mana

---@class AF_NameplateSemanticColor
---@field enabled? boolean Defaults to true.
---@field rgb number[]

---@class AF_NameplateSemanticColorConfig
---@field type "nameplate_semantic"
---@field alpha? number Shared alpha for every semantic color.
---@field boss? AF_NameplateSemanticColor
---@field lieutenant? AF_NameplateSemanticColor
---@field caster? AF_NameplateSemanticColor
---@field default? AF_NameplateSemanticColor

local function SetVertexColorWithCharm(texture, unit, r, g, b, a)
    local charmedR, charmedG, charmedB = AF.GetColorRGB("CHARMED")
    texture:SetVertexColorFromBoolean(
        UnitIsCharmed(unit),
        CreateColor(charmedR, charmedG, charmedB, a),
        CreateColor(r, g, b, a)
    )
end

local function GetEnabledSemanticColor(config, key)
    local color = config[key]
    if color and color.enabled ~= false and color.rgb then
        return color.rgb
    end
end

local function IsSemanticBoss(unit)
    local isBoss = UnitIsBossMob(unit)
    if F.isValueNonSecret(isBoss) and isBoss then
        return true
    end

    local classification = UnitClassification(unit)
    if F.isValueNonSecret(classification) and classification == "worldboss" then
        return true
    end

    local unitLevel = UnitEffectiveLevel(unit)
    if not F.isValueNonSecret(unitLevel) then return false end
    if unitLevel == -1 then return true end

    local playerLevel = UnitEffectiveLevel("player")
    return F.isValueNonSecret(playerLevel) and unitLevel >= playerLevel + 2
end

local function IsSemanticLieutenant(unit)
    local isLieutenant = UnitIsLieutenant(unit)
    if F.isValueNonSecret(isLieutenant) and isLieutenant then
        return true
    end

    local unitLevel = UnitEffectiveLevel(unit)
    local playerLevel = UnitEffectiveLevel("player")
    return F.isValueNonSecret(unitLevel)
        and F.isValueNonSecret(playerLevel)
        and unitLevel == playerLevel + 1
end

local function IsSemanticCaster(unit)
    local class = UnitClassBase(unit)
    if F.isValueNonSecret(class) and class == "PALADIN" then
        return true
    end

    local powerType = UnitPowerType(unit)
    return F.isValueNonSecret(powerType) and powerType == Mana
end

local function GetSemanticColor(config, unit)
    -- Retail 12.0.7.68887 (wow-ui-source 4383ced) and 12.1.0.68824
    -- (wow-ui-source fa38386):
    -- UnitClassification, UnitEffectiveLevel, UnitIsBossMob,
    -- UnitIsLieutenant, UnitPowerType, and UnitClassBase are not documented
    -- with secret-return aspects in either pinned build. Guard every inspected
    -- result anyway so a future restricted value simply falls through to the
    -- next static category without entering a separate combat path.
    local rgb = GetEnabledSemanticColor(config, "boss")
    if rgb and IsSemanticBoss(unit) then
        return AF.UnpackColor(rgb)
    end

    rgb = GetEnabledSemanticColor(config, "lieutenant")
    if rgb and IsSemanticLieutenant(unit) then
        return AF.UnpackColor(rgb)
    end

    rgb = GetEnabledSemanticColor(config, "caster")
    if rgb and IsSemanticCaster(unit) then
        return AF.UnpackColor(rgb)
    end

    rgb = GetEnabledSemanticColor(config, "default")
    if rgb then
        return AF.UnpackColor(rgb)
    end
end

local function SetConfiguredColor(bar, texture, config, skipTapDeniedCheck)
    if not config then return end

    local unit = bar.unit
    local colorType = config.type
    local factor = colorType and colorType:find("_dark$") and 0.2 or 1
    local alpha = type(config.alpha) == "number" and config.alpha or 1
    local r, g, b

    if colorType and colorType:find("^selection") then
        r, g, b = UnitSelectionColor(unit, true)
        if factor ~= 1 then
            r, g, b = AF.ScaleColor(r, g, b, factor)
        end
        SetVertexColorWithCharm(texture, unit, r, g, b, alpha)
        return r, g, b
    elseif colorType == "nameplate_semantic" then
        if not skipTapDeniedCheck and not UnitPlayerControlled(unit) and UnitIsTapDenied(unit) then
            r, g, b = AF.GetColorRGB("TAP_DENIED")
        else
            r, g, b = GetSemanticColor(config, unit)
            if not r then
                r, g, b = UnitSelectionColor(unit, true)
            end
        end
    elseif AF.UnitIsPlayer(unit) then
        if not UnitIsConnected(unit) then
            r, g, b = AF.GetColorRGB("OFFLINE")
        elseif colorType and colorType:find("^class") then
            if UnitHasVehicleUI(unit) then
                r, g, b = AF.GetColorRGB("FRIENDLY", nil, factor)
            else
                r, g, b = AF.GetClassColor(UnitClassBase(unit), nil, factor)
            end
        end
    elseif not skipTapDeniedCheck and not UnitPlayerControlled(unit) and UnitIsTapDenied(unit) then
        r, g, b = AF.GetColorRGB("TAP_DENIED")
    elseif colorType and colorType:find("^class") then
        r, g, b = AF.GetReactionColor(unit, nil, factor)
    end

    if not r then
        if config.gradient == "disabled" then
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
    end

    -- Feed UnitIsCharmed directly into a secret-capable region sink so a
    -- restricted result is never branched on in Lua.
    SetVertexColorWithCharm(texture, unit, r, g, b, alpha)
    return r, g, b
end

local function CreatePredictionBar(parent, layer)
    local bar = CreateFrame("StatusBar", nil, parent)
    AF.SetFrameLevel(bar, layer)
    bar:SetStatusBarTexture(AF.GetPlainTexture())
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    return bar
end

---@class AF_SecretHealthBar:AF_SecretStatusBar
local AF_SecretHealthBarMixin = {}

function AF_SecretHealthBarMixin:UpdateHealth()
    -- Retail 12.0.7.68887 (wow-ui-source 4383ced): UnitHealth and
    -- UnitHealthMax may return secrets; native status bars accept them.
    self:SetMinMaxValues(0, UnitHealthMax(self.unit))
    self:SetValue(UnitHealth(self.unit))
end

function AF_SecretHealthBarMixin:UpdateColor()
    local r, g, b = SetConfiguredColor(self, self.fill, self.fillColor)
    SetConfiguredColor(self, self.unfill, self.unfillColor, true)
    if not self.healPredictionUseCustomColor and r then
        self.healPrediction:SetStatusBarColor(r, g, b, 0.4)
    end
end

function AF_SecretHealthBarMixin:UpdatePredictions()
    UnitGetDetailedHealPrediction(self.unit, nil, self.healPredictionCalculator)

    local incomingHeals = self.healPredictionCalculator:GetIncomingHeals()
    self.healPrediction:SetMinMaxValues(0, self.healPredictionCalculator:GetMissingHealth())
    self.healPrediction:SetValue(incomingHeals)

    local damageAbsorbs = self.healPredictionCalculator:GetDamageAbsorbs()
    self.damageAbsorb:SetMinMaxValues(0, self.healPredictionCalculator:GetMaximumDamageAbsorbs())
    self.damageAbsorb:SetValue(damageAbsorbs)

    local healAbsorbs = self.healPredictionCalculator:GetHealAbsorbs()
    self.healAbsorb:SetMinMaxValues(0, self.healPredictionCalculator:GetCurrentHealth())
    self.healAbsorb:SetValue(healAbsorbs)
end

function AF_SecretHealthBarMixin:UpdateHealPrediction()
    self:UpdatePredictions()
end

function AF_SecretHealthBarMixin:UpdateDamageAbsorb()
    self:UpdatePredictions()
end

function AF_SecretHealthBarMixin:UpdateHealAbsorb()
    self:UpdatePredictions()
end

function AF_SecretHealthBarMixin:UpdateDispelHighlight()
    -- Aura-instance plumbing is intentionally handled by the shared aura
    -- widget. Do not inspect a potentially secret AuraData table here.
    self.dispelHighlight:Hide()
end

function AF_SecretHealthBarMixin:UpdateAll()
    self:UpdateColor()
    self:UpdateHealth()
    self:UpdatePredictions()
    self:UpdateDispelHighlight()
end

function AF_SecretHealthBarMixin:SetupFillColor(config)
    self.fillColor = config
    if self.unit then
        self:RegisterUnitEvents()
        self:UpdateColor()
    end
end

function AF_SecretHealthBarMixin:SetupUnfillColor(config)
    self.unfillColor = config
    if self.unit then
        self:RegisterUnitEvents()
        self:UpdateColor()
    end
end

function AF_SecretHealthBarMixin:EnableHealPrediction(enabled)
    self.healPredictionEnabled = enabled
    self.healPrediction:SetShown(enabled)
end

function AF_SecretHealthBarMixin:SetHealPredictionColor(r, g, b, a)
    self.healPredictionUseCustomColor = true
    self.healPrediction:SetStatusBarColor(r, g, b, a)
end

function AF_SecretHealthBarMixin:ClearHealPredictionColor()
    self.healPredictionUseCustomColor = false
    if self.unit then self:UpdateColor() end
end

function AF_SecretHealthBarMixin:LSM_SetHealPredictionTexture(texture)
    self.healPrediction:SetStatusBarTexture(AF.LSM_GetBarTexture(texture))
end

function AF_SecretHealthBarMixin:EnableDamageAbsorb(enabled)
    self.damageAbsorbEnabled = enabled
    self.damageAbsorb:SetShown(enabled)
end

function AF_SecretHealthBarMixin:SetDamageAbsorbColor(r, g, b, a)
    self.damageAbsorb:SetStatusBarColor(r, g, b, a)
end

function AF_SecretHealthBarMixin:SetDamageAbsorbExcessGlowColor(r, g, b, a)
    self.damageAbsorbExcessGlow:SetVertexColor(r, g, b, a)
end

function AF_SecretHealthBarMixin:LSM_SetDamageAbsorbTexture(texture)
    self.damageAbsorb:SetStatusBarTexture(AF.LSM_GetBarTexture(texture))
end

function AF_SecretHealthBarMixin:SetupDamageAbsorb_NormalStyle(reverseFill, excessGlow)
    self.damageAbsorb:SetReverseFill(reverseFill)
    self.damageAbsorbExcessGlowEnabled = excessGlow
    -- The calculator's clamped flag may be secret, while SetShown does not
    -- accept secret arguments from tainted code. Never branch on that flag.
    self.damageAbsorbExcessGlow:Hide()
end

function AF_SecretHealthBarMixin:SetupDamageAbsorb_OverlayStyle(excessGlow)
    self.damageAbsorb:SetReverseFill(false)
    self.damageAbsorbExcessGlowEnabled = excessGlow
    self.damageAbsorbExcessGlow:Hide()
end

function AF_SecretHealthBarMixin:SetupDamageAbsorb_BorderStyle(thickness)
    self.damageAbsorbBorderThickness = thickness
    self.damageAbsorb:SetReverseFill(false)
end

function AF_SecretHealthBarMixin:EnableHealAbsorb(enabled)
    self.healAbsorbEnabled = enabled
    self.healAbsorb:SetShown(enabled)
end

function AF_SecretHealthBarMixin:SetHealAbsorbColor(r, g, b, a)
    self.healAbsorb:SetStatusBarColor(r, g, b, a)
end

function AF_SecretHealthBarMixin:SetHealAbsorbExcessGlowColor(r, g, b, a)
    self.healAbsorbExcessGlow:SetVertexColor(r, g, b, a)
end

function AF_SecretHealthBarMixin:LSM_SetHealAbsorbTexture(texture)
    self.healAbsorb:SetStatusBarTexture(AF.LSM_GetBarTexture(texture))
end

function AF_SecretHealthBarMixin:SetupHealAbsorb_NormalStyle(excessGlow)
    self.healAbsorb:SetReverseFill(true)
    self.healAbsorbExcessGlowEnabled = excessGlow
    self.healAbsorbExcessGlow:Hide()
end

function AF_SecretHealthBarMixin:SetupHealAbsorb_OverlayStyle(excessGlow)
    self.healAbsorb:SetReverseFill(true)
    self.healAbsorbExcessGlowEnabled = excessGlow
    self.healAbsorbExcessGlow:Hide()
end

function AF_SecretHealthBarMixin:EnableDispelHighlight(enabled, onlyDispellable)
    self.dispelHighlightEnabled = enabled
    self.dispelHighlightOnlyDispellable = onlyDispellable
    if not enabled then self.dispelHighlight:Hide() end
end

function AF_SecretHealthBarMixin:SetDispelHighlightBlendMode(blendMode)
    self.dispelHighlight:SetBlendMode(blendMode)
end

function AF_SecretHealthBarMixin:SetDispelHighlightAlpha(alpha)
    self.dispelHighlight:SetAlpha(alpha)
end

function AF_SecretHealthBarMixin:EnableMouseoverHighlight(enabled)
    self.mouseoverHighlightEnabled = enabled
    if not enabled then self.mouseoverHighlight:Hide() end
end

function AF_SecretHealthBarMixin:SetMouseoverHighlightColor(r, g, b, a)
    self.mouseoverHighlight:SetVertexColor(r, g, b, a)
end

function AF_SecretHealthBarMixin:RegisterUnitEvents()
    self.eventFrame:UnregisterAllEvents()
    self.eventFrame:RegisterUnitEvent("UNIT_HEALTH", self.unit)
    self.eventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", self.unit)
    self.eventFrame:RegisterUnitEvent("UNIT_FACTION", self.unit)
    self.eventFrame:RegisterUnitEvent("UNIT_HEAL_PREDICTION", self.unit)
    self.eventFrame:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", self.unit)
    self.eventFrame:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", self.unit)
    self.eventFrame:RegisterUnitEvent("UNIT_AURA", self.unit)

    local fillIsSemantic = self.fillColor and self.fillColor.type == "nameplate_semantic"
    local unfillIsSemantic = self.unfillColor and self.unfillColor.type == "nameplate_semantic"
    if fillIsSemantic or unfillIsSemantic then
        self.eventFrame:RegisterUnitEvent("UNIT_CLASSIFICATION_CHANGED", self.unit)
        self.eventFrame:RegisterUnitEvent("UNIT_LEVEL", self.unit)
        self.eventFrame:RegisterUnitEvent("UNIT_NAME_UPDATE", self.unit)
        self.eventFrame:RegisterUnitEvent("UNIT_DISPLAYPOWER", self.unit)
        self.eventFrame:RegisterUnitEvent("UNIT_POWER_BAR_SHOW", self.unit)
        self.eventFrame:RegisterUnitEvent("UNIT_POWER_BAR_HIDE", self.unit)
        self.eventFrame:RegisterEvent("PLAYER_LEVEL_CHANGED")
    end
end

function AF_SecretHealthBarMixin:SetUnit(unit)
    self.unit = unit
    self:RegisterUnitEvents()
    self:UpdateAll()
end

function AF_SecretHealthBarMixin:ClearUnit()
    self.eventFrame:UnregisterAllEvents()
    self.unit = nil
    self.healPredictionCalculator:Reset()
    self:SetMinMaxValues(0, 1)
    self:SetValue(0)
    self.healPrediction:SetMinMaxValues(0, 1)
    self.healPrediction:SetValue(0)
    self.damageAbsorb:SetMinMaxValues(0, 1)
    self.damageAbsorb:SetValue(0)
    self.healAbsorb:SetMinMaxValues(0, 1)
    self.healAbsorb:SetValue(0)
    self.dispelHighlight:Hide()
end

local function OnEvent(self, event)
    local bar = self.owner
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        bar:UpdateHealth()
        bar:UpdatePredictions()
    elseif event == "UNIT_FACTION"
        or event == "UNIT_CLASSIFICATION_CHANGED"
        or event == "UNIT_LEVEL"
        or event == "UNIT_NAME_UPDATE"
        or event == "UNIT_DISPLAYPOWER"
        or event == "UNIT_POWER_BAR_SHOW"
        or event == "UNIT_POWER_BAR_HIDE"
        or event == "PLAYER_LEVEL_CHANGED"
    then
        bar:UpdateColor()
    elseif event == "UNIT_AURA" then
        bar:UpdateDispelHighlight()
    else
        bar:UpdatePredictions()
    end
end

---@return AF_SecretHealthBar bar
function AF.CreateSecretHealthBar(parent, name)
    local bar = AF.CreateSecretStatusBar(parent, name)
    Mixin(bar, AF_SecretHealthBarMixin)

    bar.eventFrame = CreateFrame("Frame", nil, bar)
    bar.eventFrame.owner = bar
    bar.eventFrame:SetScript("OnEvent", OnEvent)

    local currentHealthTexture = bar.innerBar:GetStatusBarTexture()

    bar.healPrediction = CreatePredictionBar(bar, 1)
    bar.healPrediction:SetPoint("TOPLEFT", currentHealthTexture, "TOPRIGHT")
    bar.healPrediction:SetPoint("BOTTOMRIGHT", bar.innerBar)

    bar.damageAbsorb = CreatePredictionBar(bar, 2)
    bar.damageAbsorb:SetPoint("TOPLEFT", bar.healPrediction:GetStatusBarTexture(), "TOPRIGHT")
    bar.damageAbsorb:SetPoint("BOTTOMRIGHT", bar.innerBar)

    bar.healAbsorb = CreatePredictionBar(bar, 3)
    bar.healAbsorb:SetAllPoints(currentHealthTexture)
    bar.healAbsorb:SetReverseFill(true)

    bar.damageAbsorbExcessGlow = bar:CreateTexture(nil, "OVERLAY")
    bar.damageAbsorbExcessGlow:SetPoint("TOPRIGHT")
    bar.damageAbsorbExcessGlow:SetPoint("BOTTOMRIGHT")
    bar.damageAbsorbExcessGlow:SetWidth(2)
    bar.damageAbsorbExcessGlow:SetTexture(AF.GetPlainTexture())
    bar.damageAbsorbExcessGlow:Hide()

    bar.healAbsorbExcessGlow = bar:CreateTexture(nil, "OVERLAY")
    bar.healAbsorbExcessGlow:SetPoint("TOPLEFT")
    bar.healAbsorbExcessGlow:SetPoint("BOTTOMLEFT")
    bar.healAbsorbExcessGlow:SetWidth(2)
    bar.healAbsorbExcessGlow:SetTexture(AF.GetPlainTexture())
    bar.healAbsorbExcessGlow:Hide()

    bar.dispelHighlight = bar:CreateTexture(nil, "OVERLAY")
    bar.dispelHighlight:SetAllPoints()
    bar.dispelHighlight:SetTexture(AF.GetPlainTexture())
    bar.dispelHighlight:Hide()

    bar.mouseoverHighlight = bar:CreateTexture(nil, "OVERLAY")
    bar.mouseoverHighlight:SetAllPoints()
    bar.mouseoverHighlight:SetTexture(AF.GetPlainTexture())
    bar.mouseoverHighlight:Hide()

    parent:HookScript("OnEnter", function()
        if bar.mouseoverHighlightEnabled then bar.mouseoverHighlight:Show() end
    end)
    parent:HookScript("OnLeave", function()
        bar.mouseoverHighlight:Hide()
    end)

    bar.healPredictionCalculator = CreateUnitHealPredictionCalculator()
    bar.healPredictionCalculator:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
    bar.healPredictionCalculator:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth)
    bar.healPredictionCalculator:SetIncomingHealOverflowPercent(0)
    bar.healPredictionCalculator:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealth)
    bar.healPredictionCalculator:SetHealAbsorbClampMode(Enum.UnitHealAbsorbClampMode.CurrentHealth)
    bar.healPredictionCalculator:SetHealAbsorbMode(Enum.UnitHealAbsorbMode.ReducedByIncomingHeals)

    bar:EnableHealPrediction(false)
    bar:EnableDamageAbsorb(false)
    bar:EnableHealAbsorb(false)

    return bar
end
