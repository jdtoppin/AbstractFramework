---@class AbstractFramework
local AF = select(2, ...)
local F = AF.funcs

local indicatorsByNativeUnitFrame = setmetatable({}, {__mode = "k"})
local scopedIndicators = setmetatable({}, {__mode = "k"})
local aggroHighlightHooked
local scopeEventFrame
local scopeEventsRegistered

local DEFAULT_BORDER_THICKNESS = 2
local DEFAULT_GLOW_THICKNESS = 4
local DEFAULT_GLOW_OUTSET = 3
local DEFAULT_BORDER_ALPHA = 1
local DEFAULT_GLOW_ALPHA = 0.55
local DEFAULT_BAR_ALPHA = 0.65
local DEFAULT_NAME_ALPHA = 1

local ShouldUnitThreatStateBeSecret =
    C_Secrets and C_Secrets.ShouldUnitThreatStateBeSecret
local UnitAffectingCombat = UnitAffectingCombat
local UnitExists = UnitExists
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitIsUnit = UnitIsUnit
local UnitThreatSituation = UnitThreatSituation

local THREAT_STATE_SAFE = "safe"
local THREAT_STATE_TRANSITION = "transition"
local THREAT_STATE_WARNING = "warning"
local THREAT_STATE_OFF_TANK = "offTank"

local offTankCandidates

local function ClampNumber(value, minimum, maximum, fallback)
    if type(value) ~= "number" then return fallback end
    return math.max(minimum, math.min(maximum, value))
end

local function ClearRegions(regions)
    for _, region in ipairs(regions) do
        -- Keep the last carrier color intact while hidden. Resetting the
        -- texture to white makes any delayed/native visibility update flash
        -- a white full-bar overlay before the next color refresh.
        region:SetAlphaFromBoolean(false, 1, 0)
    end
end

local function AnchorEdgeRegions(regions, owner, thickness, outset)
    local top, bottom, left, right = unpack(regions)

    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", owner, "TOPLEFT", -outset, outset)
    top:SetPoint("TOPRIGHT", owner, "TOPRIGHT", outset, outset)
    top:SetHeight(thickness)

    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", -outset, -outset)
    bottom:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", outset, -outset)
    bottom:SetHeight(thickness)

    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", owner, "TOPLEFT", -outset, outset)
    left:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", -outset, -outset)
    left:SetWidth(thickness)

    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", owner, "TOPRIGHT", outset, outset)
    right:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", outset, -outset)
    right:SetWidth(thickness)
end

local function CreateEdgeRegions(owner, blendMode, sublevel)
    local regions = {}
    for i = 1, 4 do
        local region = owner:CreateTexture(nil, "OVERLAY", nil, sublevel)
        region:SetColorTexture(1, 1, 1, 1)
        region:SetBlendMode(blendMode)
        region:SetAlpha(0)
        regions[i] = region
    end
    return regions
end

local function SetCarrierRegionColor(region, nativeHighlight, customColor)
    if customColor then
        region:SetVertexColor(AF.UnpackColor(customColor))
    else
        -- Forward the potentially secret components directly between the
        -- documented native source and sink. Do not capture, inspect,
        -- compare, transform, or expose them to consumer Lua.
        region:SetVertexColor(nativeHighlight:GetVertexColor())
    end
end

local function CopyNativeCarrier(
    regions,
    nativeHighlight,
    alpha,
    customColor
)
    for _, region in ipairs(regions) do
        SetCarrierRegionColor(region, nativeHighlight, customColor)
        region:SetAlphaFromBoolean(nativeHighlight:IsShown(), alpha, 0)
    end
end

local function CopyNativeNameCarrier(
    nameOverlay,
    nativeHighlight,
    alpha,
    customColor
)
    if customColor then
        nameOverlay:SetTextColor(AF.UnpackColor(customColor))
    else
        nameOverlay:SetTextColor(nativeHighlight:GetVertexColor())
    end
    nameOverlay:SetAlphaFromBoolean(nativeHighlight:IsShown(), alpha, 0)
end

local function SetSemanticCarrier(regions, color, alpha)
    for _, region in ipairs(regions) do
        region:SetVertexColor(AF.UnpackColor(color))
        region:SetAlphaFromBoolean(true, alpha, 0)
    end
end

local function SetSemanticNameCarrier(nameOverlay, color, alpha)
    nameOverlay:SetTextColor(AF.UnpackColor(color))
    nameOverlay:SetAlphaFromBoolean(true, alpha, 0)
end

local function TryGetThreatSituation(subjectUnit, mobUnit)
    -- Retail 12.0.7.68887 (wow-ui-source 4383ced) and 12.1.0.68824
    -- (wow-ui-source fa38386): UnitThreatSituation uses the
    -- SecretWhenUnitThreatStateRestricted predicate. Player/pet/ally to
    -- nameplate queries are generally public, but the predicate remains the
    -- authoritative per-query guard.
    if ShouldUnitThreatStateBeSecret
        and ShouldUnitThreatStateBeSecret(subjectUnit, mobUnit)
    then
        return nil, false
    end

    local status = UnitThreatSituation(subjectUnit, mobUnit)
    if not F.isValueNonSecret(status) then
        return nil, false
    end

    if status ~= nil
        and (
            type(status) ~= "number"
            or status < 0
            or status > 3
        )
    then
        return nil, false
    end

    return status, true
end

local function TryIsPlayerUnit(unit)
    local isPlayer = UnitIsUnit(unit, "player")
    if not F.isValueNonSecret(isPlayer) then
        return nil, false
    end
    return isPlayer == true, true
end

local function TryUnitExists(unit)
    local exists = UnitExists(unit)
    if not F.isValueNonSecret(exists) then
        return nil, false
    end
    return exists == true, true
end

local function TryUnitHasAggro(subjectUnit, mobUnit)
    local status, available =
        TryGetThreatSituation(subjectUnit, mobUnit)
    if not available then
        return nil, false
    end
    return status == 2 or status == 3, true
end

local function TryAddPetCandidate(candidates, petUnit)
    local petExists, existenceAvailable =
        TryUnitExists(petUnit)
    if not existenceAvailable then
        return false
    end
    if petExists then
        candidates[#candidates + 1] = petUnit
    end
    return true
end

local function TryBuildOffTankCandidates()
    local candidates = {}

    -- Include the player's own pet explicitly. Party tokens exclude the
    -- player, while the raid loop below deliberately skips the player's
    -- raidpet alias to avoid querying the same pet twice.
    if not TryAddPetCandidate(candidates, "pet") then
        return nil, false
    end

    local inRaid = IsInRaid()
    local count = inRaid
        and GetNumGroupMembers()
        or GetNumSubgroupMembers()
    local unitPrefix = inRaid and "raid" or "party"
    local petPrefix = inRaid and "raidpet" or "partypet"

    for index = 1, count do
        local groupUnit = unitPrefix .. index
        local isPlayer, identityAvailable =
            TryIsPlayerUnit(groupUnit)
        if not identityAvailable then
            return nil, false
        end

        if not isPlayer then
            local role = UnitGroupRolesAssigned(groupUnit)
            if not F.isValueNonSecret(role) then
                return nil, false
            end

            if role == "TANK" then
                candidates[#candidates + 1] = groupUnit
            end

            -- Match Platynator's useful pet-tank coverage without exposing
            -- raw threat values. Pet existence is cached until the next
            -- roster/role/pet/scope event.
            local petUnit = petPrefix .. index
            if not TryAddPetCandidate(candidates, petUnit) then
                return nil, false
            end
        end
    end

    return candidates, true
end

local function TryOtherTankHasAggro(mobUnit)
    if not offTankCandidates then
        local available
        offTankCandidates, available =
            TryBuildOffTankCandidates()
        if not available then
            offTankCandidates = nil
            return nil, false
        end
    end

    for _, candidateUnit in ipairs(offTankCandidates) do
        local hasAggro, available =
            TryUnitHasAggro(candidateUnit, mobUnit)
        if not available then
            return nil, false
        end
        if hasAggro then
            return true, true
        end
    end

    return false, true
end

local function ResolveSemanticThreatState(indicator)
    local unit = indicator.unit
    if not unit then
        return nil, false
    end

    local status, available =
        TryGetThreatSituation("player", unit)
    if not available then
        return nil, false
    end

    local unitInCombat = UnitAffectingCombat(unit)
    if not F.isValueNonSecret(unitInCombat) then
        return nil, false
    end

    -- A public nil outside combat means there is no active threat state, not
    -- that a tank has lost aggro on every nearby nameplate.
    if status == nil and not unitInCombat then
        return nil, true
    end

    local isTank = PlayerUtil.IsPlayerEffectivelyTank()
    if not F.isValueNonSecret(isTank) then
        return nil, false
    end

    -- Middle-ground classifier:
    -- Tank: 3 safe, 1/2 transition, 0/nil warning or off-tank.
    -- Other: 2/3 aggro warning, 1 transition, 0/nil safe.
    if isTank then
        if status == 3 then
            return THREAT_STATE_SAFE, true
        elseif status == 1 or status == 2 then
            return THREAT_STATE_TRANSITION, true
        end

        local otherTankHasAggro, offTankAvailable =
            TryOtherTankHasAggro(unit)
        if not offTankAvailable then
            return nil, false
        end
        if otherTankHasAggro then
            return THREAT_STATE_OFF_TANK, true
        end
        return THREAT_STATE_WARNING, true
    end

    if status == 3 or status == 2 then
        return THREAT_STATE_WARNING, true
    elseif status == 1 then
        return THREAT_STATE_TRANSITION, true
    end
    return THREAT_STATE_SAFE, true
end

local function GetSemanticStateColor(indicator, state)
    local config = indicator.stateColors
    local stateConfig = config and config[state]
    if stateConfig
        and stateConfig.enabled ~= false
        and type(stateConfig.rgb) == "table"
    then
        return stateConfig.rgb
    end
end

local function ShowSemanticState(indicator, state)
    local color = state and GetSemanticStateColor(indicator, state)
    if not color then
        indicator:ClearVisuals()
        return
    end

    if indicator.showBorder then
        SetSemanticCarrier(
            indicator.borderRegions,
            color,
            indicator.borderAlpha
        )
    else
        ClearRegions(indicator.borderRegions)
    end

    if indicator.showGlow then
        SetSemanticCarrier(
            indicator.glowRegions,
            color,
            indicator.glowAlpha
        )
    else
        ClearRegions(indicator.glowRegions)
    end

    if indicator.showBar then
        SetSemanticCarrier(
            indicator.barRegions,
            color,
            indicator.barAlpha
        )
    else
        ClearRegions(indicator.barRegions)
    end

    if indicator.showName and indicator.nameOverlay then
        SetSemanticNameCarrier(
            indicator.nameOverlay,
            color,
            indicator.nameAlpha
        )
    elseif indicator.nameOverlay then
        indicator.nameOverlay:SetAlphaFromBoolean(false, 1, 0)
    end
end

local function RefreshMappedIndicators(nativeUnitFrame)
    local indicators = indicatorsByNativeUnitFrame[nativeUnitFrame]
    if not indicators then return end

    for indicator in next, indicators do
        indicator:Refresh()
    end
end

local function RefreshScopedIndicators()
    offTankCandidates = nil
    for indicator in next, scopedIndicators do
        indicator:Refresh()
    end
end

local function UpdateScopeEvents()
    local hasScopedIndicator = next(scopedIndicators) ~= nil
    if hasScopedIndicator and not scopeEventsRegistered then
        offTankCandidates = nil
        if not scopeEventFrame then
            scopeEventFrame = CreateFrame("Frame")
            scopeEventFrame:SetScript(
                "OnEvent",
                RefreshScopedIndicators
            )
        end

        scopeEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        scopeEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        scopeEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        scopeEventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        scopeEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        scopeEventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
        scopeEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        scopeEventFrame:RegisterEvent("UNIT_PET")
        -- Blizzard's CompactUnitFrame handler already refreshes the affected
        -- nameplate for both threat events; the secure post-hook keeps
        -- that path per-plate instead of rescanning every visible plate.
        scopeEventsRegistered = true
    elseif not hasScopedIndicator and scopeEventsRegistered then
        offTankCandidates = nil
        scopeEventFrame:UnregisterAllEvents()
        scopeEventsRegistered = nil
    end
end

local function UpdateScopedIndicator(indicator)
    if indicator.enabled
        and indicator.nativeUnitFrame
        and (
            indicator.hasScopeGate
            or indicator.stateColors
        )
    then
        scopedIndicators[indicator] = true
    else
        scopedIndicators[indicator] = nil
    end
    UpdateScopeEvents()
end

local function EnsureAggroHighlightHook()
    if aggroHighlightHooked
        or type(CompactUnitFrame_UpdateAggroHighlight) ~= "function"
    then
        return
    end

    aggroHighlightHooked = true
    hooksecurefunc(
        "CompactUnitFrame_UpdateAggroHighlight",
        RefreshMappedIndicators
    )
end

local function RemoveNativeMapping(indicator)
    local nativeUnitFrame = indicator.nativeUnitFrame
    if not nativeUnitFrame then return end

    local indicators = indicatorsByNativeUnitFrame[nativeUnitFrame]
    if indicators then
        indicators[indicator] = nil
    end
end

local function AddNativeMapping(indicator, nativeUnitFrame)
    local indicators = indicatorsByNativeUnitFrame[nativeUnitFrame]
    if not indicators then
        indicators = setmetatable({}, {__mode = "k"})
        indicatorsByNativeUnitFrame[nativeUnitFrame] = indicators
    end
    indicators[indicator] = true
end

---@class AF_SecretNamePlateThreatIndicatorConfig
---@field enabled? boolean
---@field style? "border"|"glow"|"both" Legacy presentation fallback.
---@field border? boolean
---@field glow? boolean
---@field bar? boolean
---@field name? boolean Requires a dedicated overlay from SetNameOverlay.
---@field thickness? number
---@field glowThickness? number
---@field glowOutset? number
---@field alpha? number Legacy shared opacity fallback.
---@field borderAlpha? number
---@field glowAlpha? number
---@field barAlpha? number
---@field nameAlpha? number
---@field combatOnly? boolean
---@field instancesOnly? boolean
---@field tankOnly? boolean
---@field useCustomColor? boolean
---@field color? number[] Native/restricted fallback color.
---@field stateColors? table Role-aware colors for public qualitative states.

---@class AF_SecretNamePlateThreatIndicator:Frame
local AF_SecretNamePlateThreatIndicatorMixin = {}

function AF_SecretNamePlateThreatIndicatorMixin:ClearVisuals()
    ClearRegions(self.borderRegions)
    ClearRegions(self.glowRegions)
    ClearRegions(self.barRegions)
    if self.nameOverlay then
        self.nameOverlay:SetAlphaFromBoolean(false, 1, 0)
    end
end

function AF_SecretNamePlateThreatIndicatorMixin:IsInConfiguredScope()
    -- UnitAffectingCombat and IsInInstance remain ordinary static gates.
    -- PTR 7 makes UnitGroupRolesAssigned secret with unit identity, but the
    -- group-role scan below explicitly rejects secret results. Blizzard's
    -- PlayerUtil helper adds the current specialization fallback without
    -- consulting a threat result, so these gates do not create a second
    -- threat-classification path.
    if self.combatOnly and not UnitAffectingCombat("player") then
        return false
    end
    if self.instancesOnly and not IsInInstance() then
        return false
    end
    if self.tankOnly and not PlayerUtil.IsPlayerEffectivelyTank() then
        return false
    end
    return true
end

function AF_SecretNamePlateThreatIndicatorMixin:Refresh()
    local nativeUnitFrame = self.nativeUnitFrame
    local nativeHighlight =
        nativeUnitFrame and nativeUnitFrame.aggroHighlight

    if not self.enabled
        or not nativeHighlight
        or not self:IsInConfiguredScope()
    then
        self:ClearVisuals()
        return
    end

    if self.stateColors then
        local state, available =
            ResolveSemanticThreatState(self)
        if available then
            ShowSemanticState(self, state)
            return
        end
    end

    -- Retail 12.0.7.68887 (wow-ui-source 4383ced) and 12.1.0.68824
    -- (wow-ui-source fa38386): CompactUnitFrame_UpdateAggroHighlight drives
    -- the Blizzard nameplate's aggroHighlight carrier. IsShown and
    -- GetVertexColor may return secret values; SimpleRegion
    -- SetAlphaFromBoolean and SetVertexColor accept those tainted values.
    -- Mirroring the native carrier is the fallback whenever a qualitative
    -- query is restricted or otherwise unavailable.
    if self.showBorder then
        CopyNativeCarrier(
            self.borderRegions,
            nativeHighlight,
            self.borderAlpha,
            self.customColor
        )
    else
        ClearRegions(self.borderRegions)
    end

    if self.showGlow then
        CopyNativeCarrier(
            self.glowRegions,
            nativeHighlight,
            self.glowAlpha,
            self.customColor
        )
    else
        ClearRegions(self.glowRegions)
    end

    if self.showBar then
        CopyNativeCarrier(
            self.barRegions,
            nativeHighlight,
            self.barAlpha,
            self.customColor
        )
    else
        ClearRegions(self.barRegions)
    end

    if self.showName and self.nameOverlay then
        -- SimpleFontString.SetTextColor and SimpleRegion.SetAlphaFromBoolean
        -- explicitly accept tainted arguments in both pinned Retail builds.
        -- The normal name remains untouched beneath this dedicated overlay.
        CopyNativeNameCarrier(
            self.nameOverlay,
            nativeHighlight,
            self.nameAlpha,
            self.customColor
        )
    elseif self.nameOverlay then
        self.nameOverlay:SetAlphaFromBoolean(false, 1, 0)
    end
end

---@param config AF_SecretNamePlateThreatIndicatorConfig?
function AF_SecretNamePlateThreatIndicatorMixin:Configure(config)
    config = config or {}

    local style = config.style or "border"
    if style ~= "border" and style ~= "glow" and style ~= "both" then
        style = "border"
    end

    local sharedAlpha = ClampNumber(config.alpha, 0, 1, nil)
    self.enabled = config.enabled ~= false
    if config.border == nil then
        self.showBorder = style == "border" or style == "both"
    else
        self.showBorder = config.border == true
    end
    if config.glow == nil then
        self.showGlow = style == "glow" or style == "both"
    else
        self.showGlow = config.glow == true
    end
    self.showBar = config.bar == true and self.hasBarMask
    self.showName = config.name == true
    self.combatOnly = config.combatOnly == true
    self.instancesOnly = config.instancesOnly == true
    self.tankOnly = config.tankOnly == true
    self.hasScopeGate = self.combatOnly
        or self.instancesOnly
        or self.tankOnly
    self.customColor = config.useCustomColor == true
        and type(config.color) == "table"
        and config.color
        or nil
    self.stateColors = type(config.stateColors) == "table"
        and config.stateColors.enabled ~= false
        and config.stateColors
        or nil
    self.borderThickness = ClampNumber(
        config.thickness,
        1,
        32,
        DEFAULT_BORDER_THICKNESS
    )
    self.glowThickness = ClampNumber(
        config.glowThickness,
        1,
        32,
        DEFAULT_GLOW_THICKNESS
    )
    self.glowOutset = ClampNumber(
        config.glowOutset,
        0,
        64,
        DEFAULT_GLOW_OUTSET
    )
    self.borderAlpha = ClampNumber(
        config.borderAlpha,
        0,
        1,
        sharedAlpha or DEFAULT_BORDER_ALPHA
    )
    self.glowAlpha = ClampNumber(
        config.glowAlpha,
        0,
        1,
        sharedAlpha or DEFAULT_GLOW_ALPHA
    )
    self.barAlpha = ClampNumber(
        config.barAlpha,
        0,
        1,
        sharedAlpha or DEFAULT_BAR_ALPHA
    )
    self.nameAlpha = ClampNumber(
        config.nameAlpha,
        0,
        1,
        sharedAlpha or DEFAULT_NAME_ALPHA
    )

    AnchorEdgeRegions(
        self.borderRegions,
        self,
        self.borderThickness,
        self.borderThickness
    )
    AnchorEdgeRegions(
        self.glowRegions,
        self,
        self.glowThickness,
        self.glowOutset
    )
    UpdateScopedIndicator(self)
    self:Refresh()
end

---@param nameOverlay FontString?
function AF_SecretNamePlateThreatIndicatorMixin:SetNameOverlay(nameOverlay)
    if self.nameOverlay then
        self.nameOverlay:SetAlphaFromBoolean(false, 1, 0)
    end
    self.nameOverlay = nameOverlay
    self:Refresh()
end

---@param nativeUnitFrame Frame?
---@param unit UnitToken?
function AF_SecretNamePlateThreatIndicatorMixin:SetNativeUnitFrame(
    nativeUnitFrame,
    unit
)
    RemoveNativeMapping(self)
    self.nativeUnitFrame = nativeUnitFrame
    self.unit = nil
    if F.isValueNonSecret(unit)
        and type(unit) == "string"
        and unit:match("^nameplate%d+$")
    then
        self.unit = unit
    end
    UpdateScopedIndicator(self)
    self:ClearVisuals()

    if not nativeUnitFrame then return end

    AddNativeMapping(self, nativeUnitFrame)
    EnsureAggroHighlightHook()
    self:Refresh()
end

function AF_SecretNamePlateThreatIndicatorMixin:Clear()
    RemoveNativeMapping(self)
    self.nativeUnitFrame = nil
    self.unit = nil
    UpdateScopedIndicator(self)
    self:ClearVisuals()
end

---@param parent AF_SecretHealthBar|Frame
---@param name string?
---@return AF_SecretNamePlateThreatIndicator indicator
function AF.CreateSecretNamePlateThreatIndicator(parent, name)
    local indicator = CreateFrame("Frame", name, parent)
    Mixin(indicator, AF_SecretNamePlateThreatIndicatorMixin)

    indicator:SetAllPoints(parent)
    indicator:EnableMouse(false)
    indicator.borderRegions = CreateEdgeRegions(indicator, "BLEND", 6)
    indicator.glowRegions = CreateEdgeRegions(indicator, "ADD", 5)

    indicator.barRegions = {}
    if parent.fill and parent.fill.mask then
        -- AF_SecretHealthBar's mask follows the live status-bar texture, so
        -- the warning overlay covers current health rather than the unfilled
        -- background.
        local barRegion =
            parent:CreateTexture(nil, "ARTWORK", nil, 2)
        barRegion:SetColorTexture(1, 1, 1, 1)
        barRegion:SetAllPoints(parent)
        barRegion:SetAlpha(0)
        barRegion:AddMaskTexture(parent.fill.mask)
        indicator.barRegions[1] = barRegion
        indicator.hasBarMask = true
    end

    indicator:Configure()

    return indicator
end
