---@class AbstractFramework
local AF = select(2, ...)

local indicatorsByNativeUnitFrame = setmetatable({}, {__mode = "k"})
local aggroHighlightHooked

local DEFAULT_BORDER_THICKNESS = 2
local DEFAULT_GLOW_THICKNESS = 4
local DEFAULT_GLOW_OUTSET = 3
local DEFAULT_BORDER_ALPHA = 1
local DEFAULT_GLOW_ALPHA = 0.55

local function ClampNumber(value, minimum, maximum, fallback)
    if type(value) ~= "number" then return fallback end
    return math.max(minimum, math.min(maximum, value))
end

local function ClearRegions(regions)
    for _, region in ipairs(regions) do
        region:SetAlpha(0)
        region:SetVertexColor(1, 1, 1, 1)
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

local function CopyNativeCarrier(regions, nativeHighlight, alpha)
    for _, region in ipairs(regions) do
        -- Forward the potentially secret components directly between the
        -- documented native source and sink. Do not capture, inspect, compare,
        -- transform, or expose them to consumer Lua.
        region:SetVertexColor(nativeHighlight:GetVertexColor())
        region:SetAlphaFromBoolean(nativeHighlight:IsShown(), alpha, 0)
    end
end

local function RefreshMappedIndicators(nativeUnitFrame)
    local indicators = indicatorsByNativeUnitFrame[nativeUnitFrame]
    if not indicators then return end

    for indicator in next, indicators do
        indicator:Refresh()
    end
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

---@class AF_SecretNamePlateThreatIndicator:Frame
local AF_SecretNamePlateThreatIndicatorMixin = {}

function AF_SecretNamePlateThreatIndicatorMixin:ClearVisuals()
    ClearRegions(self.borderRegions)
    ClearRegions(self.glowRegions)
end

function AF_SecretNamePlateThreatIndicatorMixin:Refresh()
    local nativeUnitFrame = self.nativeUnitFrame
    local nativeHighlight =
        nativeUnitFrame and nativeUnitFrame.aggroHighlight

    if not self.enabled or not nativeHighlight then
        self:ClearVisuals()
        return
    end

    -- Retail 12.0.7.68887 (wow-ui-source 4383ced) and 12.1.0.68824
    -- (wow-ui-source fa38386): CompactUnitFrame_UpdateAggroHighlight drives
    -- the Blizzard nameplate's aggroHighlight carrier. IsShown and
    -- GetVertexColor may return secret values; SimpleRegion
    -- SetAlphaFromBoolean and SetVertexColor accept those tainted values.
    -- Mirroring the native carrier is the sole combat path, including when
    -- UnitThreat* results are restricted.
    if self.showBorder then
        CopyNativeCarrier(
            self.borderRegions,
            nativeHighlight,
            self.borderAlpha
        )
    else
        ClearRegions(self.borderRegions)
    end

    if self.showGlow then
        CopyNativeCarrier(
            self.glowRegions,
            nativeHighlight,
            self.glowAlpha
        )
    else
        ClearRegions(self.glowRegions)
    end
end

---@param config table?
function AF_SecretNamePlateThreatIndicatorMixin:Configure(config)
    config = config or {}

    local style = config.style or "border"
    if style ~= "border" and style ~= "glow" and style ~= "both" then
        style = "border"
    end

    local sharedAlpha = ClampNumber(config.alpha, 0, 1, nil)
    self.enabled = config.enabled ~= false
    self.showBorder = style == "border" or style == "both"
    self.showGlow = style == "glow" or style == "both"
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
    self:Refresh()
end

---@param nativeUnitFrame Frame?
function AF_SecretNamePlateThreatIndicatorMixin:SetNativeUnitFrame(
    nativeUnitFrame
)
    RemoveNativeMapping(self)
    self.nativeUnitFrame = nativeUnitFrame
    self:ClearVisuals()

    if not nativeUnitFrame then return end

    AddNativeMapping(self, nativeUnitFrame)
    EnsureAggroHighlightHook()
    self:Refresh()
end

function AF_SecretNamePlateThreatIndicatorMixin:Clear()
    RemoveNativeMapping(self)
    self.nativeUnitFrame = nil
    self:ClearVisuals()
end

---@param parent Frame
---@param name string?
---@return AF_SecretNamePlateThreatIndicator indicator
function AF.CreateSecretNamePlateThreatIndicator(parent, name)
    local indicator = CreateFrame("Frame", name, parent)
    Mixin(indicator, AF_SecretNamePlateThreatIndicatorMixin)

    indicator:SetAllPoints(parent)
    indicator:EnableMouse(false)
    indicator.borderRegions = CreateEdgeRegions(indicator, "BLEND", 6)
    indicator.glowRegions = CreateEdgeRegions(indicator, "ADD", 5)
    indicator:Configure()

    return indicator
end
