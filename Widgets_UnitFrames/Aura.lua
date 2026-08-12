---@class AbstractFramework
local AF = select(2, ...)
local F = AF.funcs

local GetAuraApplicationDisplayCount = C_UnitAuras.GetAuraApplicationDisplayCount
local GetAuraDataByAuraInstanceID = C_UnitAuras.GetAuraDataByAuraInstanceID
local GetAuraDispelTypeColor = C_UnitAuras.GetAuraDispelTypeColor
local GetAuraDuration = C_UnitAuras.GetAuraDuration
local GetUnitAuraInstanceIDs = C_UnitAuras.GetUnitAuraInstanceIDs
local IsAuraFilteredOutByInstanceID = C_UnitAuras.IsAuraFilteredOutByInstanceID
local STATUS_BAR_IMMEDIATE = Enum.StatusBarInterpolation.Immediate
local STATUS_BAR_ELAPSED_TIME = Enum.StatusBarTimerDirection.ElapsedTime
local DEFAULT_AURA_BLOCK_RED = 0.5
local DEFAULT_AURA_BLOCK_GREEN = 0.5
local DEFAULT_AURA_BLOCK_BLUE = 0.5
local DEFAULT_AURA_BLOCK_ALPHA = 1

-- Retail 12.1.0.69273 (wow-ui-source eb941aad) marks every general
-- unit-aura enumeration and instance-ID API RequiresUnitAuraAccess with
-- FailureMode=Error. This is a static client boundary, not a combat or
-- secrecy probe: live Retail 12.1 rows must use AuraContainers, and an
-- unavailable native backend must leave legacy widgets inert. Unknown future
-- Retail interfaces fail closed; pre-12.1 Retail keeps its compatibility path.
local RETAIL_12_1_INTERFACE_MIN = 120100
local function CanEnumerateLegacyUnitAuras()
    if not AF.isRetail then return true end

    local _, _, _, interfaceVersion = GetBuildInfo()
    interfaceVersion = tonumber(interfaceVersion)
    return interfaceVersion ~= nil
        and interfaceVersion < RETAIL_12_1_INTERFACE_MIN
end

local canEnumerateLegacyUnitAuras = CanEnumerateLegacyUnitAuras()

-- Retail 12.1.0.69273 (wow-ui-source eb941aad) exposes this formatter to
-- DurationTextBinding, so secret remaining-time values stay entirely native
-- while changing units at the ordinary minute/hour/day boundaries.
local durationFormatter = C_StringUtil.CreateSecondsFormatter()
durationFormatter:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
durationFormatter:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
durationFormatter:SetMaxInterval(Enum.SecondsFormatterInterval.Days)
durationFormatter:SetDesiredUnitCount(1)
durationFormatter:SetCanRoundUpLastUnit(false)
durationFormatter:SetCanRoundUpIntervals(false)
durationFormatter:SetMillisecondsThreshold(60)
durationFormatter:SetStripIntervalWhitespace(Enum.SecondsFormatterIntervalWhitespace.Strip)

local dispelTypes = {
    {0, "None"},
    {1, "Magic"},
    {2, "Curse"},
    {3, "Disease"},
    {4, "Poison"},
    {9, "Enrage"},
    {11, "Bleed"},
}

local defaultDispelColorCurve
function AF.GetAuraDispelColorCurve()
    if defaultDispelColorCurve then return defaultDispelColorCurve end

    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    for _, dispelType in ipairs(dispelTypes) do
        local r, g, b = AF.GetAuraTypeColor(dispelType[2])
        curve:AddPoint(dispelType[1], CreateColor(r, g, b, 1))
    end

    defaultDispelColorCurve = curve
    return curve
end

local function CreateAuraDurationBar(parent, anchor)
    local durationBar = CreateFrame("StatusBar", nil, parent)
    AF.SetFrameLevel(durationBar, 1, parent)
    durationBar:SetAllPoints(anchor)
    durationBar:SetOrientation("VERTICAL")
    durationBar:SetReverseFill(true)
    durationBar:SetStatusBarTexture(AF.GetPlainTexture())
    durationBar:SetStatusBarColor(0, 0, 0, 0.75)
    durationBar:Hide()

    return durationBar
end

local function CopyAuraBlockColor(color)
    if type(color) == "table"
        and type(color[1]) == "number"
        and type(color[2]) == "number"
        and type(color[3]) == "number"
        and type(color[4]) == "number"
    then
        return {color[1], color[2], color[3], color[4]}
    end

    return {
        DEFAULT_AURA_BLOCK_RED,
        DEFAULT_AURA_BLOCK_GREEN,
        DEFAULT_AURA_BLOCK_BLUE,
        DEFAULT_AURA_BLOCK_ALPHA,
    }
end

local function CreateAuraBlockBackground(parent, anchor, blockColor)
    local background = parent:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(anchor)
    background:SetColorTexture(unpack(blockColor))
    background:Hide()
    return background
end

local function UsesAuraDurationBar(style)
    return style == "vertical" or style == "block_vertical"
end

local function UsesAuraDurationCooldown(style)
    return style ~= "none" and not UsesAuraDurationBar(style)
end

local function SetupAuraCooldownStyle(
    icon,
    cooldown,
    durationBar,
    blockBackground,
    style,
    blockColor
)
    local isVertical = UsesAuraDurationBar(style)
    local isBlockVertical = style == "block_vertical"
    local isBlockClock = style:find("^block_clock") ~= nil
    local isBlock = isBlockVertical or isBlockClock
    if cooldown then
        cooldown:SetShown(UsesAuraDurationCooldown(style))
        cooldown:SetDrawEdge(style:find("edge$") ~= nil)
    end
    if durationBar then
        durationBar:SetShown(isVertical)
        durationBar:SetStatusBarColor(0, 0, 0, 0.75)
    end
    blockBackground:SetColorTexture(unpack(blockColor))
    blockBackground:SetShown(isBlock)
    icon:SetShown(style:find("^block") == nil)
end

local function SetupAuraDurationText(durationText, config)
    durationText:SetShown(config.enabled)
    AF.SetFont(durationText, unpack(config.font))
    AF.LoadTextPosition(durationText, config.position)
    durationText:SetTextColor(AF.UnpackColor(config.color.normal))
end

local function SetupAuraStackText(stackText, config)
    stackText:SetShown(config.enabled)
    AF.SetFont(stackText, unpack(config.font))
    AF.LoadTextPosition(stackText, config.position)
    stackText:SetTextColor(AF.UnpackColor(config.color))
end

---@class AF_SecretAura:Button
local AF_SecretAuraMixin = {}

local function SetAuraShown(aura, shown)
    if not aura.visibilityManagedExternally then
        aura:SetShown(shown)
    end
end

local function SetAuraTimer(aura, duration)
    aura.cooldown:SetCooldownFromDurationObject(duration)
    aura.durationBar:SetTimerDuration(
        duration,
        STATUS_BAR_IMMEDIATE,
        STATUS_BAR_ELAPSED_TIME
    )

    -- Native timer setters can refresh child presentation. Keep a configured
    -- cooldown style authoritative across live aura updates and previews.
    if aura.cooldownStyle then
        SetupAuraCooldownStyle(
            aura.icon,
            aura.cooldown,
            aura.durationBar,
            aura.blockBackground,
            aura.cooldownStyle,
            aura.blockColor
        )
    end
end

function AF_SecretAuraMixin:SetAura(unit, auraInstanceID)
    if not canEnumerateLegacyUnitAuras then
        self:ClearAura()
        return
    end

    self.unit = unit
    self.auraInstanceID = auraInstanceID
    self.inventorySlot = nil

    -- Retail 12.0.7 (wow-ui-source 6e96727): Copy() produces the
    -- never-secret opaque duration handle accepted by the native cooldown and
    -- duration-text binding.
    local duration = GetAuraDuration(unit, auraInstanceID):Copy()
    self.duration = duration

    -- The icon can be secret. Never inspect it; forward it directly to the
    -- documented secret-accepting native texture setter.
    local auraData = GetAuraDataByAuraInstanceID(unit, auraInstanceID)
    self.icon:SetTexture(auraData.icon)

    if self.dispelColorCurve then
        -- GetRGBA may contain secret components. SetVertexColor accepts them,
        -- so keep the entire value flow inside native APIs.
        self.dispelOverlay:SetVertexColor(GetAuraDispelTypeColor(unit, auraInstanceID, self.dispelColorCurve):GetRGBA())
        self.dispelOverlay:Show()
    else
        self.dispelOverlay:Hide()
    end

    self.stackText:SetText(GetAuraApplicationDisplayCount(unit, auraInstanceID))
    SetAuraTimer(self, duration)
    self.durationTextBinding:SetDuration(duration)
    self.durationTextBinding:Enable()
    SetAuraShown(self, true)
end

function AF_SecretAuraMixin:SetTemporaryEnchant(unit, inventorySlot, remainingTimeMs, applications)
    self.unit = unit
    self.auraInstanceID = nil
    self.inventorySlot = inventorySlot

    -- Retail 12.0.7's BuffFrame performs this same conversion on values from
    -- GetWeaponEnchantInfo. Keep the calculation here in the shared widget;
    -- the 12.1 backend uses CustomAuraContainer's native enchantment source.
    local duration = C_DurationUtil.CreateDuration()
    duration:SetTimeFromStart(GetTime(), remainingTimeMs / 1000)
    self.duration = duration

    self.icon:SetTexture(GetInventoryItemTexture(unit, inventorySlot))
    self.dispelOverlay:Hide()
    self.stackText:SetText(applications > 1 and applications or "")
    SetAuraTimer(self, duration)
    self.durationTextBinding:SetDuration(duration)
    self.durationTextBinding:Enable()
    SetAuraShown(self, true)
end

function AF_SecretAuraMixin:ClearAura()
    self.unit = nil
    self.auraInstanceID = nil
    self.inventorySlot = nil
    self.duration = nil
    self.durationTextBinding:Disable()
    self.cooldown:Clear()
    self.stackText:SetText("")
    self.icon:SetTexture(self.fallbackIcon)
    self.dispelOverlay:Hide()
    SetAuraShown(self, false)
end

function AF_SecretAuraMixin:SetFallbackIcon(texture)
    self.fallbackIcon = texture
    self.icon:SetTexture(texture)
end

function AF_SecretAuraMixin:EnableDispelColor(enabled, curve)
    self.dispelColorCurve = enabled and (curve or AF.GetAuraDispelColorCurve()) or nil
    if not enabled then
        self.dispelOverlay:Hide()
    end
end

function AF_SecretAuraMixin:SetCooldown(startTime, duration, applications, icon)
    -- Config-mode preview only. Combat aura data uses SetAura above.
    self.unit = nil
    self.auraInstanceID = nil
    self.inventorySlot = nil
    local previewDuration = C_DurationUtil.CreateDuration()
    previewDuration:SetTimeFromStart(startTime, duration)
    self.duration = previewDuration

    self.icon:SetTexture(icon)
    self.dispelOverlay:Hide()
    self.stackText:SetText(applications)
    SetAuraTimer(self, previewDuration)
    self.durationTextBinding:SetDuration(previewDuration)
    self.durationTextBinding:Enable()
    SetAuraShown(self, true)
end

function AF_SecretAuraMixin:SetVisibilityManagedExternally(managed)
    self.visibilityManagedExternally = managed
end

function AF_SecretAuraMixin:SetCooldownStyle(style, blockColor)
    self.cooldownStyle = style
    self.blockColor = CopyAuraBlockColor(blockColor)
    SetupAuraCooldownStyle(
        self.icon,
        self.cooldown,
        self.durationBar,
        self.blockBackground,
        style,
        self.blockColor
    )
end

function AF_SecretAuraMixin:SetupDurationText(config)
    SetupAuraDurationText(self.durationText, config)
end

function AF_SecretAuraMixin:SetupStackText(config)
    SetupAuraStackText(self.stackText, config)
end

function AF_SecretAuraMixin:EnableTooltip(config)
    self.tooltipConfig = config
    self:EnableMouse(config.enabled)
end

function AF_SecretAuraMixin:SetDesaturated(desaturated)
    self.icon:SetDesaturated(desaturated)
end

function AF_SecretAuraMixin:UpdatePixels()
    AF.DefaultUpdatePixels(self)
    AF.RePoint(self.durationText)
    AF.RePoint(self.stackText)
end

function AF_SecretAuraMixin:ShowTooltip()
    if not self.tooltipConfig or not self.tooltipConfig.enabled then return end
    if not self.auraInstanceID and not self.inventorySlot then return end

    local config = self.tooltipConfig
    if config.anchorTo == "self" and config.position then
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint(config.position[1], self, config.position[2], config.position[3], config.position[4])
    else
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
    end

    if self.auraInstanceID then
        GameTooltip:SetUnitAuraByAuraInstanceID(self.unit, self.auraInstanceID)
    else
        GameTooltip:SetInventoryItem(self.unit, self.inventorySlot)
    end
    GameTooltip:Show()
end

function AF_SecretAuraMixin:HideTooltip()
    GameTooltip:Hide()
end

local function Aura_OnEnter(self)
    self:ShowTooltip()
end

local function Aura_OnLeave(self)
    self:HideTooltip()
end

---@return AF_SecretAura aura
function AF.InitAura(button, noBorder, visibilityManagedExternally)
    Mixin(button, AF_SecretAuraMixin)
    button.visibilityManagedExternally = visibilityManagedExternally

    if not noBorder then
        AF.ApplyDefaultBackdrop(button)
    end

    local icon = button:CreateTexture(nil, "ARTWORK")
    button.icon = icon
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local blockColor = CopyAuraBlockColor()
    local blockBackground = CreateAuraBlockBackground(button, icon, blockColor)
    button.blockColor = blockColor
    button.blockBackground = blockBackground

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown = cooldown
    AF.SetFrameLevel(cooldown, 1, button)
    cooldown:SetAllPoints(icon)
    cooldown:SetDrawBling(false)
    cooldown:SetDrawEdge(false)
    -- AF's duration binding owns the numeric label. Keep the cooldown frame
    -- for its sweep and edge without native or third-party countdown text.
    cooldown:SetHideCountdownNumbers(true)
    cooldown.noCooldownCount = true
    cooldown:SetUseAuraDisplayTime(true)

    -- Retail 12.0.7.68887 and Retail 12.1.0.69273 (wow-ui-source eb941aad)
    -- SimpleStatusBar:SetTimerDuration accepts an opaque LuaDurationObject as
    -- a secret argument, keeping vertical timing native.
    local durationBar = CreateAuraDurationBar(button, icon)
    button.durationBar = durationBar

    local overlayFrame = CreateFrame("Frame", nil, button)
    AF.SetFrameLevel(overlayFrame, 2, button)
    overlayFrame:SetAllPoints()

    local dispelOverlay = overlayFrame:CreateTexture(nil, "OVERLAY")
    button.dispelOverlay = dispelOverlay
    dispelOverlay:SetAllPoints()
    dispelOverlay:SetTexture([[Interface\Buttons\UI-Debuff-Overlays]])
    dispelOverlay:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    dispelOverlay:Hide()

    local durationText = overlayFrame:CreateFontString(nil, "OVERLAY", "AF_FONT_NORMAL")
    button.durationText = durationText

    local stackText = overlayFrame:CreateFontString(nil, "OVERLAY", "AF_FONT_NORMAL")
    button.stackText = stackText

    button.durationTextBinding = C_DurationUtil.CreateDurationTextBinding()
    button.durationTextBinding:SetFontString(durationText)
    button.durationTextBinding:SetFormatter(durationFormatter)
    button.durationTextBinding:SetExpiredText("0.0")
    button.durationTextBinding:SetZeroDurationText("")
    button.durationTextBinding:SetUpdateInterval(0.1)

    button:SetFallbackIcon(134400)
    button:SetScript("OnEnter", Aura_OnEnter)
    button:SetScript("OnLeave", Aura_OnLeave)
    SetAuraShown(button, false)

    return button
end

---@return AF_SecretAura aura
function AF.CreateAura(parent, noBorder)
    return AF.InitAura(CreateFrame("Button", nil, parent), noBorder)
end

---------------------------------------------------------------------
-- Retail 12.1 custom aura containers
---------------------------------------------------------------------
-- Retail 12.1.0.69273 (wow-ui-source eb941aad) replaces Retail's
-- SecureAuraHeaderTemplate with externally-instantiable AuraContainer and
-- CustomAuraButton intrinsics. Its duration-text schema accepts a native
-- LuaColorCurveObject plus Enum.DurationTextBindingProperty. Check the current
-- exported schema rather than probing protected frame creation or accepting
-- the incompatible 68824 API.
local customAuraContainerLayoutDefaults = _G.CustomAuraContainerLayoutDefaults
local customAuraGroupDefaults = _G.CustomAuraContainerGroupDefaultOptions
local customAuraGroupLayoutDefaults = _G.CustomAuraContainerGroupLayoutDefaultOptions
local customAuraSlotDefaults = _G.CustomAuraContainerSlotDefaultOptions
local customItemEnchantmentDefaults = _G.CustomAuraContainerItemEnchantmentDefaultOptions
local customItemEnchantmentLayoutDefaults = _G.CustomAuraContainerItemEnchantmentLayoutDefaultOptions
local customDispelTypeTextureStyle = _G.Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
local durationTextBindingProperty = _G.Enum and Enum.DurationTextBindingProperty
local luaCurveType = _G.Enum and Enum.LuaCurveType

AF.hasCustomAuraContainer = _G.C_AuraContainerUtil ~= nil
    and C_AuraContainerUtil.ProcessCustomAuraButtonApplicationCountOptions ~= nil
    and C_AuraContainerUtil.ProcessCustomAuraButtonDispelTypeTextureOptions ~= nil
    and C_AuraContainerUtil.ProcessCustomAuraButtonDurationBarOptions ~= nil
    and C_AuraContainerUtil.ProcessCustomAuraButtonDurationTextOptions ~= nil
    and _G.AuraContainerSortMethod ~= nil
    and _G.AuraContainerSortDirection ~= nil
    and _G.AuraContainerInbound ~= nil
    and _G.AuraContainerItemEnchantmentSlot ~= nil
    and _G.AuraContainerItemEnchantmentSortMethod ~= nil
    and _G.CustomAuraContainerAuraProcessingPolicy ~= nil
    and _G.CustomAuraContainerItemEnchantmentPlacement ~= nil
    and customAuraContainerLayoutDefaults ~= nil
    and customAuraContainerLayoutDefaults.axis ~= nil
    and customAuraContainerLayoutDefaults.maximumLineSize ~= nil
    and customAuraGroupDefaults ~= nil
    and customAuraGroupLayoutDefaults ~= nil
    and customAuraGroupLayoutDefaults.elementSpacing ~= nil
    and customAuraGroupLayoutDefaults.forceNewLine ~= nil
    and customAuraSlotDefaults ~= nil
    and customItemEnchantmentDefaults ~= nil
    and customItemEnchantmentLayoutDefaults ~= nil
    and _G.AnchorUtil ~= nil
    and AnchorUtil.FlowLayoutAxis ~= nil
    and AnchorUtil.FlowDirection ~= nil
    and _G.C_CurveUtil ~= nil
    and C_CurveUtil.CreateColorCurve ~= nil
    and _G.CreateColor ~= nil
    and luaCurveType ~= nil
    and luaCurveType.Step ~= nil
    and durationTextBindingProperty ~= nil
    and durationTextBindingProperty.RemainingDuration ~= nil
    and durationTextBindingProperty.RemainingPercent ~= nil
    and customDispelTypeTextureStyle ~= nil
    and customDispelTypeTextureStyle.PreserveAsset ~= nil

local customAuraContainerConstructionTotals = {
    containerCreateAttempts = 0,
    containerAllocations = 0,
    containerCreateCompletions = 0,
    trackedContainers = 0,
    externalContainersObserved = 0,
    groupAddAttempts = 0,
    groupsAdded = 0,
    slotAddAttempts = 0,
    slotsAdded = 0,
    itemEnchantmentAddAttempts = 0,
    itemEnchantmentsAdded = 0,
    initialFrameReservationsAttempted = 0,
    initialFrameReservationsCompleted = 0,
}

local customAuraContainerConstructionCounterFields = {
    "containerCreateAttempts",
    "containerAllocations",
    "containerCreateCompletions",
    "groupAddAttempts",
    "groupsAdded",
    "slotAddAttempts",
    "slotsAdded",
    "itemEnchantmentAddAttempts",
    "itemEnchantmentsAdded",
    "initialFrameReservationsAttempted",
    "initialFrameReservationsCompleted",
}

-- Records must never keep a native container alive. Totals are intentionally
-- cumulative and have no reset path so callers can compare monotonic snapshots
-- around reload/build scenarios without changing the observed lifecycle.
local customAuraContainerConstructionRecords = setmetatable({}, {__mode = "k"})

-- Retail 12.1.0.69273 (wow-ui-source eb941aad) reserves ten frames in
-- AddAuraGroup's initial batch and one frame for each slot/enchantment.
-- Initializer callbacks for later lazy group batches are deliberately excluded.
local customAuraGroupInitialFrameReservation = 10
local customAuraSingleInitialFrameReservation = 1

local function CreateCustomAuraContainerConstructionRecord(createdByAbstractFramework)
    local record = {
        createdByAbstractFramework = createdByAbstractFramework,
    }
    for _, field in ipairs(customAuraContainerConstructionCounterFields) do
        record[field] = 0
    end
    return record
end

local function TrackCustomAuraContainerConstruction(container, createdByAbstractFramework)
    local record = customAuraContainerConstructionRecords[container]
    if record then
        return record
    end

    record = CreateCustomAuraContainerConstructionRecord(createdByAbstractFramework)
    customAuraContainerConstructionRecords[container] = record
    customAuraContainerConstructionTotals.trackedContainers =
        customAuraContainerConstructionTotals.trackedContainers + 1
    if not createdByAbstractFramework then
        customAuraContainerConstructionTotals.externalContainersObserved =
            customAuraContainerConstructionTotals.externalContainersObserved + 1
    end
    return record
end

local function IncrementCustomAuraContainerConstruction(record, field, amount)
    amount = amount or 1
    customAuraContainerConstructionTotals[field] =
        customAuraContainerConstructionTotals[field] + amount
    record[field] = record[field] + amount
end

local function CopyCustomAuraContainerConstructionCounters(source)
    local snapshot = {}
    for _, field in ipairs(customAuraContainerConstructionCounterFields) do
        snapshot[field] = source[field]
    end
    return snapshot
end

local function AssertCustomAuraContainer()
    assert(AF.hasCustomAuraContainer, "12.1 CustomAuraContainerTemplate is unavailable")
end

local function CreateCustomAuraDurationTextBinding()
    local binding = C_DurationUtil.CreateDurationTextBinding()
    binding:SetFormatter(durationFormatter)
    binding:SetExpiredText("0.0")
    binding:SetZeroDurationText("")
    binding:SetUpdateInterval(0.1)
    return binding
end

local function IsFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function IsNormalizedColor(color)
    if type(color) ~= "table" then return false end

    for index = 1, 3 do
        local component = color[index]
        if not IsFiniteNumber(component) or component < 0 or component > 1 then
            return false
        end
    end

    local alpha = color[4]
    return alpha == nil
        or IsFiniteNumber(alpha) and alpha >= 0 and alpha <= 1
end

-- Retail 12.1.0.69273 DurationTextBindingSharedDocumentation exposes one
-- sampled property for each native text-color curve. A valid descriptor colors
-- values below the threshold and returns to the configured normal color at the
-- threshold. Invalid descriptors deliberately keep the static normal color.
local function CreateCustomAuraDurationTextColorOptions(config)
    local color = type(config) == "table" and config.color
    local threshold = type(color) == "table" and color.threshold
    if threshold == nil then return nil end
    if type(threshold) ~= "table"
        or not IsNormalizedColor(color.normal)
        or not IsNormalizedColor(threshold.rgb)
        or not IsFiniteNumber(threshold.value)
        or threshold.value <= 0
    then
        return nil
    end

    local property
    if threshold.mode == "seconds" then
        property = durationTextBindingProperty.RemainingDuration
    elseif threshold.mode == "percent" and threshold.value <= 1 then
        property = durationTextBindingProperty.RemainingPercent
    else
        return nil
    end

    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(luaCurveType.Step)
    curve:AddPoint(0, CreateColor(AF.UnpackColor(threshold.rgb)))
    curve:AddPoint(threshold.value, CreateColor(AF.UnpackColor(color.normal)))

    return {
        curve = curve,
        property = property,
    }
end

local function InitializeCustomAuraButton(button, style, anchor)
    if not style.noBorder then
        -- BackdropTemplate has an OnSizeChanged Lua layout path. Custom aura
        -- geometry may be secret, so use scriptless child textures instead.
        local border = button:CreateTexture(nil, "BACKGROUND", nil, -8)
        border:SetAllPoints()
        border:SetColorTexture(unpack(style.backdropBorderColor))

        local background = button:CreateTexture(nil, "BACKGROUND", nil, -7)
        AF.SetInside(background, button, 1)
        background:SetColorTexture(unpack(style.backdropBackgroundColor))
    end

    if style.width and style.height then
        button:SetSize(style.width, style.height)
    end

    if anchor then
        button:ClearAllPoints()
        button:SetPoint(
            anchor.point,
            anchor.relativeTo,
            anchor.relativePoint,
            anchor.x,
            anchor.y
        )
    end

    local icon = button:CreateTexture(nil, "ARTWORK")
    if style.iconInset then
        AF.SetInside(icon, button, style.iconInset)
    else
        icon:SetAllPoints()
    end
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if style.desaturated ~= nil then
        icon:SetDesaturated(style.desaturated)
    end

    -- CustomAuraButton access restrictions are installed after this
    -- initializer and deny tainted access while aura data is secret. Keep the
    -- static, ordinary configured color in a scriptless texture and complete
    -- its styling before registering any aura-driven regions.
    local blockColor = CopyAuraBlockColor(style.blockColor)
    local blockBackground = CreateAuraBlockBackground(button, icon, blockColor)

    local cooldownStyle = style.cooldownStyle or "none"
    local cooldown
    if UsesAuraDurationCooldown(cooldownStyle) then
        cooldown = CreateFrame(
            "Cooldown",
            nil,
            button,
            "CooldownFrameTemplate"
        )
        AF.SetFrameLevel(cooldown, 1, button)
        cooldown:SetAllPoints(icon)
        cooldown:SetDrawBling(false)
        cooldown:SetDrawEdge(false)
        -- AF's duration binding owns the numeric label. Keep the cooldown
        -- frame for its sweep and edge without native or third-party text.
        cooldown:SetHideCountdownNumbers(true)
        cooldown.noCooldownCount = true
        cooldown:SetUseAuraDisplayTime(true)
    end

    local durationBar
    if UsesAuraDurationBar(cooldownStyle) then
        durationBar = CreateAuraDurationBar(button, icon)
    end
    SetupAuraCooldownStyle(
        icon,
        cooldown,
        durationBar,
        blockBackground,
        cooldownStyle,
        blockColor
    )

    local overlayFrame = CreateFrame("Frame", nil, button)
    AF.SetFrameLevel(overlayFrame, 2, button)
    overlayFrame:SetAllPoints()

    local durationText
    if style.durationText then
        durationText = overlayFrame:CreateFontString(nil, "OVERLAY", "AF_FONT_NORMAL")
        SetupAuraDurationText(durationText, style.durationText)
    end

    local stackText
    if style.stackText then
        stackText = overlayFrame:CreateFontString(nil, "OVERLAY", "AF_FONT_NORMAL")
        SetupAuraStackText(stackText, style.stackText)
    end

    local dispelOverlay
    if style.dispelColor then
        dispelOverlay = overlayFrame:CreateTexture(nil, "OVERLAY")
        dispelOverlay:SetAllPoints()
        dispelOverlay:SetTexture([[Interface\Buttons\UI-Debuff-Overlays]])
        dispelOverlay:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
        dispelOverlay:Hide()
    end

    -- Blizzard installs DenyTaintedAccessWhenAurasAreSecret after this
    -- initializer (or after the login bootstrap for early-created buttons).
    -- Fully configure regions before attaching them, then avoid relying on
    -- access to a live button while aura data is secret.
    button:SetIcon(icon)
    -- Retail 12.1 updates every registered duration display. Registering both
    -- carriers lets the native timer setter reactivate the nominally hidden
    -- one, drawing Blizzard's clock and AF's vertical bar together. Attach
    -- only the carrier selected by the construction-owned cooldown style.
    if durationBar then
        button:SetDurationBar(durationBar, {
            interpolation = STATUS_BAR_IMMEDIATE,
            direction = STATUS_BAR_ELAPSED_TIME,
        })
    elseif cooldown then
        button:SetDurationCooldown(cooldown)
    end
    if durationText then
        local options = {
            binding = CreateCustomAuraDurationTextBinding(),
        }
        options.textColor = CreateCustomAuraDurationTextColorOptions(
            style.durationText
        )
        button:SetDurationText(durationText, options)
    end
    if stackText then
        button:SetApplicationCount(stackText)
    end
    if dispelOverlay then
        button:AddDispelTypeTexture(dispelOverlay, {
            style = customDispelTypeTextureStyle.PreserveAsset,
            showWhenHarmful = true,
            showWhenHelpful = false,
            showWithoutDispelType = false,
            customDispelColorCurve = style.dispelColorCurve or AF.GetAuraDispelColorCurve(),
        })
    end
    if style.tooltip then
        button:EnableMouse(style.tooltip.enabled)
        if style.tooltip.anchorPoint then
            button:SetTooltipAnchorPoint(
                style.tooltip.anchorPoint,
                style.tooltip.offsetX,
                style.tooltip.offsetY
            )
        end
        if style.tooltip.hideInCombat ~= nil then
            button:SetHideTooltipInCombat(style.tooltip.hideInCombat)
        end
    end
    if style.cancelAuraButtons then
        button:SetCancelAuraButtons(style.cancelAuraButtons)
    end
end

local function CopyCustomAuraNativeOptions(buttonOptions, stripAnchor)
    local options
    if stripAnchor then
        local nativeOptions = {}
        for key, value in pairs(buttonOptions or {}) do
            if key ~= "anchor" then
                nativeOptions[key] = value
            end
        end
        options = AF.Copy(nativeOptions)
    else
        options = AF.Copy(buttonOptions or {})
    end
    assert(options.initializeFrame == nil, "initializeFrame is managed by AbstractFramework")
    assert(options.templateNames == nil, "templateNames are managed by AbstractFramework")
    return options
end

local function GetCustomAuraButtonOptions(buttonOptions, buttonStyle, anchor, stripAnchor)
    local options = CopyCustomAuraNativeOptions(buttonOptions, stripAnchor)
    local style = AF.Copy(buttonStyle or {})
    if style.tooltip then
        assert(type(style.tooltip.enabled) == "boolean", "tooltip.enabled must be a boolean")
        assert(style.tooltip.enabled or not style.cancelAuraButtons,
            "cancelAuraButtons requires mouse-enabled tooltips")
    end

    if not style.noBorder then
        style.backdropBorderColor = style.backdropBorderColor or {AF.GetColorRGB("border")}
        style.backdropBackgroundColor = style.backdropBackgroundColor or {AF.GetColorRGB("background")}
    end
    if style.dispelColor and not style.dispelColorCurve then
        style.dispelColorCurve = AF.GetAuraDispelColorCurve()
    end

    options.initializeFrame = function(button)
        InitializeCustomAuraButton(button, style, anchor)
    end
    return options
end

local function GetCustomAuraSlotAnchor(container, slotOptions)
    local anchor = slotOptions and slotOptions.anchor
    if anchor == nil then
        return nil
    end

    assert(type(anchor) == "table", "anchor must be a table")
    assert(type(anchor.point) == "string" and anchor.point ~= "",
        "anchor.point must be a non-empty string")

    local relativePoint = anchor.relativePoint
    local relativeTo = anchor.relativeTo
    local x = anchor.x
    local y = anchor.y
    if relativePoint == nil then
        relativePoint = anchor.point
    end
    if relativeTo == nil then
        relativeTo = container
    end
    if x == nil then
        x = 0
    end
    if y == nil then
        y = 0
    end
    assert(type(relativePoint) == "string" and relativePoint ~= "",
        "anchor.relativePoint must be a non-empty string")
    assert(type(x) == "number", "anchor.x must be a number")
    assert(type(y) == "number", "anchor.y must be a number")

    -- Keep the trusted frame reference by identity. Deep-copy only the scalar
    -- point data, and default to a container-relative anchor for simple slots.
    return {
        point = anchor.point,
        relativeTo = relativeTo,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

local customAuraDispelOverlayStyleKeys = {
    alpha = true,
    atlas = true,
    blendMode = true,
    dispelTypeTextureOptions = true,
    drawLayer = true,
    frameLevelOffset = true,
    height = true,
    inset = true,
    solidColor = true,
    subLevel = true,
    texture = true,
    width = true,
}

local customAuraDispelTextureOptionKeys = {
    customDispelAssetMap = true,
    customDispelColorCurve = true,
    customDispelColorMap = true,
    showWhenHarmful = true,
    showWhenHelpful = true,
    showWithoutDispelType = true,
    style = true,
}

local customAuraOverlayDrawLayers = {
    BACKGROUND = true,
    BORDER = true,
    ARTWORK = true,
    OVERLAY = true,
    HIGHLIGHT = true,
}

local customAuraOverlayBlendModes = {
    DISABLE = true,
    BLEND = true,
    ALPHAKEY = true,
    ADD = true,
    MOD = true,
}

local function IsCustomDispelTextureStyle(value)
    if type(value) ~= "number" then return false end

    for _, enumValue in pairs(customDispelTypeTextureStyle) do
        if value == enumValue then
            return true
        end
    end
    return false
end

local function CopyCustomAuraDispelTextureOptions(source)
    assert(source == nil or type(source) == "table",
        "dispelTypeTextureOptions must be a table")

    source = source or {}
    for key in pairs(source) do
        assert(customAuraDispelTextureOptionKeys[key],
            "unsupported dispelTypeTextureOptions field: " .. tostring(key))
    end

    for _, key in ipairs({
        "showWhenHarmful",
        "showWhenHelpful",
        "showWithoutDispelType",
    }) do
        assert(source[key] == nil or type(source[key]) == "boolean",
            "dispelTypeTextureOptions." .. key .. " must be a boolean")
    end
    assert(source.style == nil or IsCustomDispelTextureStyle(source.style),
        "dispelTypeTextureOptions.style must be an enum value")
    assert(source.customDispelAssetMap == nil
            or type(source.customDispelAssetMap) == "table",
        "dispelTypeTextureOptions.customDispelAssetMap must be a table")
    assert(source.customDispelColorMap == nil
            or type(source.customDispelColorMap) == "table",
        "dispelTypeTextureOptions.customDispelColorMap must be a table")

    local copySource = {}
    for key, value in pairs(source) do
        if key ~= "customDispelColorCurve" then
            copySource[key] = value
        end
    end
    local options = AF.Copy(copySource)
    -- A LuaColorCurveObject is an opaque native object. Preserve it by
    -- identity instead of treating table-backed test doubles as configuration.
    options.customDispelColorCurve = source.customDispelColorCurve
    if options.showWhenHarmful == nil then
        options.showWhenHarmful = true
    end
    if options.showWhenHelpful == nil then
        options.showWhenHelpful = false
    end
    if options.showWithoutDispelType == nil then
        options.showWithoutDispelType = false
    end
    if options.style == nil then
        options.style = customDispelTypeTextureStyle.PreserveAsset
    end
    if options.customDispelColorCurve == nil
        and options.customDispelColorMap == nil
    then
        options.customDispelColorCurve = AF.GetAuraDispelColorCurve()
    end
    return options
end

local function CopyCustomAuraDispelOverlayStyle(overlayStyle)
    assert(overlayStyle == nil or type(overlayStyle) == "table",
        "overlayStyle must be a table")

    overlayStyle = overlayStyle or {}
    for key in pairs(overlayStyle) do
        assert(customAuraDispelOverlayStyleKeys[key],
            "unsupported overlayStyle field: " .. tostring(key))
    end

    local hasWidth = overlayStyle.width ~= nil
    local hasHeight = overlayStyle.height ~= nil
    assert(hasWidth == hasHeight,
        "overlayStyle.width and overlayStyle.height must be supplied together")
    if hasWidth then
        assert(IsFiniteNumber(overlayStyle.width) and overlayStyle.width > 0,
            "overlayStyle.width must be a positive finite number")
        assert(IsFiniteNumber(overlayStyle.height) and overlayStyle.height > 0,
            "overlayStyle.height must be a positive finite number")
    end
    assert(overlayStyle.alpha == nil
            or IsFiniteNumber(overlayStyle.alpha)
                and overlayStyle.alpha >= 0
                and overlayStyle.alpha <= 1,
        "overlayStyle.alpha must be between zero and one")
    assert(overlayStyle.blendMode == nil
            or customAuraOverlayBlendModes[overlayStyle.blendMode],
        "overlayStyle.blendMode must be a valid blend mode")
    assert(overlayStyle.inset == nil
            or IsFiniteNumber(overlayStyle.inset) and overlayStyle.inset >= 0,
        "overlayStyle.inset must be a non-negative finite number")
    assert(overlayStyle.frameLevelOffset == nil
            or IsFiniteNumber(overlayStyle.frameLevelOffset),
        "overlayStyle.frameLevelOffset must be a finite number")
    assert(overlayStyle.subLevel == nil
            or IsFiniteNumber(overlayStyle.subLevel),
        "overlayStyle.subLevel must be a finite number")

    local drawLayer = overlayStyle.drawLayer or "ARTWORK"
    assert(customAuraOverlayDrawLayers[drawLayer],
        "overlayStyle.drawLayer must be a valid draw layer")
    assert(overlayStyle.texture == nil
            or type(overlayStyle.texture) == "string"
                and overlayStyle.texture ~= ""
            or IsFiniteNumber(overlayStyle.texture)
                and overlayStyle.texture > 0,
        "overlayStyle.texture must be a texture path or file ID")
    assert(overlayStyle.atlas == nil
            or type(overlayStyle.atlas) == "string"
                and overlayStyle.atlas ~= "",
        "overlayStyle.atlas must be a non-empty string")
    assert(overlayStyle.solidColor == nil
            or IsNormalizedColor(overlayStyle.solidColor),
        "overlayStyle.solidColor must be a normalized RGB or RGBA table")

    local textureSourceCount = 0
    for _, key in ipairs({"texture", "atlas", "solidColor"}) do
        if overlayStyle[key] ~= nil then
            textureSourceCount = textureSourceCount + 1
        end
    end
    assert(textureSourceCount <= 1,
        "overlayStyle accepts only one of texture, atlas, or solidColor")

    local copySource = {}
    for key, value in pairs(overlayStyle) do
        if key ~= "dispelTypeTextureOptions" then
            copySource[key] = value
        end
    end
    local style = AF.Copy(copySource)
    style.alpha = style.alpha or 1
    style.blendMode = style.blendMode or "BLEND"
    style.drawLayer = drawLayer
    style.frameLevelOffset = style.frameLevelOffset or 0
    style.subLevel = style.subLevel or 0
    style.dispelTypeTextureOptions =
        CopyCustomAuraDispelTextureOptions(
            overlayStyle.dispelTypeTextureOptions
        )
    return style
end

local function GetCustomAuraDispelOverlayAnchor(container, slotOptions)
    local anchor = slotOptions and slotOptions.anchor
    assert(type(anchor) == "table",
        "dispel overlay slots require an anchor table")
    assert(anchor.matchAnchorBounds == nil
            or type(anchor.matchAnchorBounds) == "boolean",
        "anchor.matchAnchorBounds must be a boolean")

    if anchor.matchAnchorBounds then
        assert(anchor.relativeTo ~= nil,
            "a bounds-matching anchor requires anchor.relativeTo")
        return {
            matchAnchorBounds = true,
            relativeTo = anchor.relativeTo,
        }
    end

    return GetCustomAuraSlotAnchor(container, slotOptions)
end

local function InitializeCustomAuraDispelOverlayButton(button, style, anchor)
    if style.width and style.height then
        button:SetSize(style.width, style.height)
    else
        assert(anchor.matchAnchorBounds,
            "a point-anchored dispel overlay requires width and height")
    end

    button:ClearAllPoints()
    if anchor.matchAnchorBounds then
        button:SetAllPoints(anchor.relativeTo)
    else
        button:SetPoint(
            anchor.point,
            anchor.relativeTo,
            anchor.relativePoint,
            anchor.x,
            anchor.y
        )
    end

    local relativeFrameLevel = anchor.relativeTo:GetFrameLevel()
    if F.isValueNonSecret(relativeFrameLevel) then
        button:SetFrameLevel(math.max(
            0,
            math.min(10000, relativeFrameLevel + style.frameLevelOffset)
        ))
    end

    local overlay = button:CreateTexture(
        nil,
        style.drawLayer,
        nil,
        style.subLevel
    )
    if style.inset and style.inset ~= 0 then
        overlay:SetPoint(
            "TOPLEFT",
            button,
            "TOPLEFT",
            style.inset,
            -style.inset
        )
        overlay:SetPoint(
            "BOTTOMRIGHT",
            button,
            "BOTTOMRIGHT",
            -style.inset,
            style.inset
        )
    else
        overlay:SetAllPoints(button)
    end
    if style.texture ~= nil then
        overlay:SetTexture(style.texture)
    elseif style.atlas ~= nil then
        overlay:SetAtlas(style.atlas, false)
    else
        overlay:SetColorTexture(unpack(style.solidColor or {1, 1, 1, 1}))
    end
    overlay:SetAlpha(style.alpha)
    overlay:SetBlendMode(style.blendMode)
    overlay:Hide()

    -- Retail 12.1.0.69273 (wow-ui-source eb941aad) lets addons configure a
    -- descendant texture before AddDispelTypeTexture transfers visibility and
    -- vertex-color ownership to Blizzard. The button carries no scripts,
    -- tooltip, icon, cooldown, or text and must never intercept unit clicks.
    button:EnableMouse(false)
    button:AddDispelTypeTexture(
        overlay,
        style.dispelTypeTextureOptions
    )
end

local function GetCustomAuraDispelOverlayOptions(
    slotOptions,
    overlayStyle,
    anchor
)
    local options = CopyCustomAuraNativeOptions(slotOptions, true)
    local style = CopyCustomAuraDispelOverlayStyle(overlayStyle)
    assert(style.width ~= nil or anchor.matchAnchorBounds,
        "a point-anchored dispel overlay requires width and height")
    options.initializeFrame = function(button)
        InitializeCustomAuraDispelOverlayButton(button, style, anchor)
    end
    return options
end

---@return boolean
function AF.HasCustomAuraContainer()
    return AF.hasCustomAuraContainer
end

---@return table totals
function AF.GetCustomAuraContainerConstructionTotals()
    local snapshot =
        CopyCustomAuraContainerConstructionCounters(customAuraContainerConstructionTotals)
    snapshot.trackedContainers = customAuraContainerConstructionTotals.trackedContainers
    snapshot.externalContainersObserved =
        customAuraContainerConstructionTotals.externalContainersObserved
    return snapshot
end

---@param container Frame
---@return table|nil stats
function AF.GetCustomAuraContainerConstructionStats(container)
    local record = customAuraContainerConstructionRecords[container]
    if not record then
        return nil
    end

    local snapshot = CopyCustomAuraContainerConstructionCounters(record)
    snapshot.createdByAbstractFramework = record.createdByAbstractFramework
    return snapshot
end

---@return Frame container
function AF.CreateCustomAuraContainer(parent, name, unit)
    AssertCustomAuraContainer()

    customAuraContainerConstructionTotals.containerCreateAttempts =
        customAuraContainerConstructionTotals.containerCreateAttempts + 1
    local container = CreateFrame("AuraContainer", name, parent, "CustomAuraContainerTemplate")
    customAuraContainerConstructionTotals.containerAllocations =
        customAuraContainerConstructionTotals.containerAllocations + 1
    local construction =
        TrackCustomAuraContainerConstruction(container, true)
    construction.containerCreateAttempts = construction.containerCreateAttempts + 1
    construction.containerAllocations = construction.containerAllocations + 1

    container:SetSize(1, 1)
    if unit ~= nil then
        container:SetUnit(unit)
    end

    IncrementCustomAuraContainerConstruction(
        construction,
        "containerCreateCompletions"
    )
    return container
end

function AF.SetCustomAuraContainerFlowLayout(container, layoutOptions)
    AssertCustomAuraContainer()
    TrackCustomAuraContainerConstruction(container, false)

    local layout = AF.Copy(customAuraContainerLayoutDefaults, layoutOptions or {})
    container:SetFlowLayoutAxis(layout.axis)
    container:SetFlowLayoutAnchorPoint(layout.anchorPoint)
    container:SetFlowLayoutGrowthDirection(layout.horizontalGrowthDirection, layout.verticalGrowthDirection)
    container:SetFlowLayoutPadding(layout.paddingLeft, layout.paddingRight, layout.paddingTop, layout.paddingBottom)
    container:SetFlowLayoutMaximumLineSize(layout.maximumLineSize)
end

function AF.ResetCustomAuraContainerFlowLayout(container)
    AssertCustomAuraContainer()
    TrackCustomAuraContainerConstruction(container, false)
    container:ResetFlowLayoutOptions()
end

function AF.SetCustomAuraContainerUnit(container, unit)
    AssertCustomAuraContainer()
    TrackCustomAuraContainerConstruction(container, false)
    container:SetUnit(unit)
end

function AF.SetCustomAuraContainerEnabled(container, enabled)
    AssertCustomAuraContainer()
    TrackCustomAuraContainerConstruction(container, false)
    container:SetEnabled(enabled)
end

function AF.UpdateCustomAuraContainer(container)
    AssertCustomAuraContainer()
    TrackCustomAuraContainerConstruction(container, false)
    container:UpdateAllAuras()
end

function AF.SetCustomAuraContainerProcessingPolicy(container, processingPolicy, options)
    AssertCustomAuraContainer()
    TrackCustomAuraContainerConstruction(container, false)
    container:SetAuraProcessingPolicy(processingPolicy, options)
end

function AF.AddCustomAuraGroup(container, groupKey, filterString, groupOptions, buttonStyle)
    AssertCustomAuraContainer()

    local options = GetCustomAuraButtonOptions(groupOptions, buttonStyle)
    local construction = TrackCustomAuraContainerConstruction(container, false)
    IncrementCustomAuraContainerConstruction(construction, "groupAddAttempts")
    IncrementCustomAuraContainerConstruction(
        construction,
        "initialFrameReservationsAttempted",
        customAuraGroupInitialFrameReservation
    )
    container:AddAuraGroup(groupKey, filterString, options)
    IncrementCustomAuraContainerConstruction(construction, "groupsAdded")
    IncrementCustomAuraContainerConstruction(
        construction,
        "initialFrameReservationsCompleted",
        customAuraGroupInitialFrameReservation
    )
end

function AF.SetCustomAuraGroupFilterString(container, groupKey, filterString)
    AssertCustomAuraContainer()
    TrackCustomAuraContainerConstruction(container, false)
    container:SetAuraGroupFilterString(groupKey, filterString)
end

function AF.SetCustomAuraGroupMaxFrameCount(container, groupKey, maxFrameCount)
    AssertCustomAuraContainer()
    TrackCustomAuraContainerConstruction(container, false)
    container:SetAuraGroupMaxFrameCount(groupKey, maxFrameCount)
end

function AF.SetCustomAuraGroupCandidateFilters(container, groupKey, candidateFilters)
    AssertCustomAuraContainer()
    TrackCustomAuraContainerConstruction(container, false)
    container:SetAuraGroupCandidateFilters(groupKey, candidateFilters)
end

function AF.SetCustomAuraGroupSortMethod(container, groupKey, sortMethod, sortDirection)
    AssertCustomAuraContainer()
    TrackCustomAuraContainerConstruction(container, false)
    container:SetAuraGroupSortMethod(groupKey, sortMethod, sortDirection)
end

function AF.SetCustomAuraGroupLayout(container, groupKey, layoutOptions)
    AssertCustomAuraContainer()
    TrackCustomAuraContainerConstruction(container, false)
    container:SetAuraGroupLayout(groupKey, layoutOptions)
end

local function AddPreparedCustomAuraSlot(container, slotKey, filterString, options)
    local construction = TrackCustomAuraContainerConstruction(container, false)
    IncrementCustomAuraContainerConstruction(construction, "slotAddAttempts")
    IncrementCustomAuraContainerConstruction(
        construction,
        "initialFrameReservationsAttempted",
        customAuraSingleInitialFrameReservation
    )
    local button = container:AddAuraSlot(slotKey, filterString, options)
    IncrementCustomAuraContainerConstruction(construction, "slotsAdded")
    IncrementCustomAuraContainerConstruction(
        construction,
        "initialFrameReservationsCompleted",
        customAuraSingleInitialFrameReservation
    )
    return button
end

function AF.AddCustomAuraSlot(container, slotKey, filterString, slotOptions, buttonStyle)
    AssertCustomAuraContainer()

    local anchor = GetCustomAuraSlotAnchor(container, slotOptions)
    local options = GetCustomAuraButtonOptions(slotOptions, buttonStyle, anchor, true)
    return AddPreparedCustomAuraSlot(container, slotKey, filterString, options)
end

---@param container Frame
---@param slotKey string
---@param filterString string
---@param slotOptions table Native slot options plus an AF-only anchor table.
---@param overlayStyle? table Construction-owned overlay presentation.
---@return Button button
function AF.AddCustomAuraDispelOverlaySlot(
    container,
    slotKey,
    filterString,
    slotOptions,
    overlayStyle
)
    AssertCustomAuraContainer()

    local anchor = GetCustomAuraDispelOverlayAnchor(container, slotOptions)
    local options = GetCustomAuraDispelOverlayOptions(
        slotOptions,
        overlayStyle,
        anchor
    )
    return AddPreparedCustomAuraSlot(container, slotKey, filterString, options)
end

function AF.SetCustomAuraSlotFilterString(container, slotKey, filterString)
    AssertCustomAuraContainer()
    TrackCustomAuraContainerConstruction(container, false)
    container:SetAuraSlotFilterString(slotKey, filterString)
end

function AF.SetCustomAuraSlotCandidateFilters(container, slotKey, candidateFilters)
    AssertCustomAuraContainer()
    TrackCustomAuraContainerConstruction(container, false)
    container:SetAuraSlotCandidateFilters(slotKey, candidateFilters)
end

function AF.SetCustomAuraSlotSortMethod(container, slotKey, sortMethod, sortDirection)
    AssertCustomAuraContainer()
    TrackCustomAuraContainerConstruction(container, false)
    container:SetAuraSlotSortMethod(slotKey, sortMethod, sortDirection)
end

function AF.AddCustomItemEnchantment(container, itemEnchantmentSlot, enchantmentOptions, buttonStyle)
    AssertCustomAuraContainer()

    local options = GetCustomAuraButtonOptions(enchantmentOptions, buttonStyle)
    local construction = TrackCustomAuraContainerConstruction(container, false)
    IncrementCustomAuraContainerConstruction(
        construction,
        "itemEnchantmentAddAttempts"
    )
    IncrementCustomAuraContainerConstruction(
        construction,
        "initialFrameReservationsAttempted",
        customAuraSingleInitialFrameReservation
    )
    local button = container:AddItemEnchantment(itemEnchantmentSlot, options)
    IncrementCustomAuraContainerConstruction(
        construction,
        "itemEnchantmentsAdded"
    )
    IncrementCustomAuraContainerConstruction(
        construction,
        "initialFrameReservationsCompleted",
        customAuraSingleInitialFrameReservation
    )
    return button
end

function AF.SetCustomItemEnchantmentSortMethod(container, sortMethod, sortDirection)
    AssertCustomAuraContainer()
    TrackCustomAuraContainerConstruction(container, false)
    container:SetItemEnchantmentSortMethod(sortMethod, sortDirection)
end

function AF.SetCustomItemEnchantmentLayout(container, layoutOptions)
    AssertCustomAuraContainer()
    TrackCustomAuraContainerConstruction(container, false)
    container:SetItemEnchantmentLayout(layoutOptions)
end

function AF.ResetCustomItemEnchantmentLayout(container)
    AssertCustomAuraContainer()
    TrackCustomAuraContainerConstruction(container, false)
    container:ResetItemEnchantmentLayout()
end

---@class AF_SecretAuraList:Frame
local AF_SecretAuraListMixin = {}

local function ClearAuraList(auraList)
    if not auraList then return end

    for _, aura in ipairs(auraList.slots) do
        aura:ClearAura()
    end
    auraList.numAuras = 0
end

function AF_SecretAuraListMixin:SetFilter(filter)
    self.filter = filter
end

local function AssertAuraMatchFilter(matchFilter)
    if type(matchFilter) == "string" then
        return
    end

    assert(type(matchFilter) == "table",
        "aura match filter must be a string or descriptor")
    assert(
        type(matchFilter.filterString) == "string"
            and matchFilter.filterString ~= "",
        "aura match filter descriptor requires a non-empty filterString"
    )
    assert(matchFilter.matchWhenFilteredOut == true,
        "aura match filter descriptor requires matchWhenFilteredOut=true")
    for key in pairs(matchFilter) do
        assert(
            key == "filterString" or key == "matchWhenFilteredOut",
            "aura match filter descriptor contains an unsupported field"
        )
    end
end

function AF_SecretAuraListMixin:SetMatchFilters(matchFilters)
    assert(matchFilters == nil or type(matchFilters) == "table",
        "aura match filters must be a table or nil")
    for _, matchFilter in ipairs(matchFilters or {}) do
        AssertAuraMatchFilter(matchFilter)
    end
    self.matchFilters = matchFilters
end

function AF_SecretAuraListMixin:SetPartitionFilter(partitionFilter, partitionList)
    if self.partitionList and self.partitionList ~= partitionList then
        ClearAuraList(self.partitionList)
    end

    self.partitionFilter = partitionFilter
    self.partitionList = partitionList
    self.partitionEnabled = partitionFilter ~= nil and partitionList ~= nil
end

function AF_SecretAuraListMixin:SetPartitionEnabled(enabled)
    self.partitionEnabled = enabled and self.partitionFilter ~= nil and self.partitionList ~= nil
end

function AF_SecretAuraListMixin:SetSortRule(sortRule, sortDirection)
    self.sortRule = sortRule
    self.sortDirection = sortDirection or Enum.UnitAuraSortDirection.Normal
end

function AF_SecretAuraListMixin:SetMaxCount(maxCount)
    self.maxCount = maxCount
end

function AF_SecretAuraListMixin:RefreshAuras()
    if not canEnumerateLegacyUnitAuras then
        ClearAuraList(self)
        ClearAuraList(self.partitionList)
        self:OnAurasUpdated(0, 0, 0)
        return
    end

    if not self.unit or not self.filter or not self.maxCount then return end

    self:OnBeforeAurasRefresh()

    local auraInstanceIDs = GetUnitAuraInstanceIDs(
        self.unit,
        self.filter,
        nil,
        self.sortRule,
        self.sortDirection
    )

    local count = 0
    local mainCount = 0
    local partitionCount = 0
    for _, auraInstanceID in ipairs(auraInstanceIDs) do
        local include = self.matchFilters == nil
        if self.matchFilters then
            -- IsAuraFilteredOutByInstanceID returns an ordinary boolean. These
            -- checks classify the ID in C without reading restricted AuraData.
            for _, matchFilter in ipairs(self.matchFilters) do
                local match
                if type(matchFilter) == "string" then
                    match = not IsAuraFilteredOutByInstanceID(
                        self.unit,
                        auraInstanceID,
                        matchFilter
                    )
                else
                    -- Retail 12.0.7.68887 generated UnitAura documentation
                    -- exposes this secret-argument C query as an ordinary bool.
                    -- The descriptor selects its complement without reading
                    -- AuraData or potentially secret source fields.
                    match = IsAuraFilteredOutByInstanceID(
                        self.unit,
                        auraInstanceID,
                        matchFilter.filterString
                    )
                end
                if match then
                    include = true
                    break
                end
            end
        end

        if include then
            local auraList = self
            local auraIndex
            if self.partitionEnabled
                -- PLAYER and the other AuraFilters are evaluated in C. The
                -- ordinary boolean result can safely select the complementary
                -- list without reading restricted AuraData fields.
                and IsAuraFilteredOutByInstanceID(self.unit, auraInstanceID, self.partitionFilter)
            then
                auraList = self.partitionList
                partitionCount = partitionCount + 1
                auraIndex = partitionCount
            else
                mainCount = mainCount + 1
                auraIndex = mainCount
            end

            count = count + 1
            auraList.slots[auraIndex]:SetAura(self.unit, auraInstanceID)
            if count == self.maxCount then break end
        end
    end

    for index = mainCount + 1, #self.slots do
        self.slots[index]:ClearAura()
    end
    if self.partitionList then
        for index = partitionCount + 1, #self.partitionList.slots do
            self.partitionList.slots[index]:ClearAura()
        end
        self.partitionList.numAuras = partitionCount
    end

    self.numAuras = count
    self:OnAurasUpdated(count, mainCount, partitionCount)
end

function AF_SecretAuraListMixin:OnBeforeAurasRefresh()
end

function AF_SecretAuraListMixin:OnAurasUpdated()
end

function AF_SecretAuraListMixin:RegisterUnitEvents()
    self:UnregisterAllEvents()
    if canEnumerateLegacyUnitAuras and self.unit then
        self:RegisterUnitEvent("UNIT_AURA", self.unit)
    end
end

function AF_SecretAuraListMixin:SetUnit(unit)
    self.unit = unit
    self:RegisterUnitEvents()
    self:RefreshAuras()
end

function AF_SecretAuraListMixin:ClearUnit()
    self.unit = nil
    self:UnregisterAllEvents()
    ClearAuraList(self)
    ClearAuraList(self.partitionList)
    self:OnAurasUpdated(0)
end

local function AuraList_OnEvent(self)
    -- UNIT_AURA's updateInfo may contain secret AuraData. Unit-event
    -- registration already filters the unit, so always request a fresh C-side
    -- filtered and sorted list and never inspect the payload.
    self:RefreshAuras()
end

---@return AF_SecretAuraList auraList
function AF.CreateSecretAuraList(parent, name, filter)
    local frame = CreateFrame("Frame", name, parent)
    Mixin(frame, AF_SecretAuraListMixin)

    frame.filter = filter
    frame.sortRule = Enum.UnitAuraSortRule.Default
    frame.sortDirection = Enum.UnitAuraSortDirection.Normal
    frame.slots = {}
    frame.numAuras = 0
    frame:SetScript("OnEvent", AuraList_OnEvent)

    return frame
end
