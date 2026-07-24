---@class AbstractFramework
local AF = select(2, ...)

local GetAuraApplicationDisplayCount = C_UnitAuras.GetAuraApplicationDisplayCount
local GetAuraDataByAuraInstanceID = C_UnitAuras.GetAuraDataByAuraInstanceID
local GetAuraDispelTypeColor = C_UnitAuras.GetAuraDispelTypeColor
local GetAuraDuration = C_UnitAuras.GetAuraDuration
local GetUnitAuraInstanceIDs = C_UnitAuras.GetUnitAuraInstanceIDs
local IsAuraFilteredOutByInstanceID = C_UnitAuras.IsAuraFilteredOutByInstanceID

local durationFormatter = C_StringUtil.CreateNumericRuleFormatter()
durationFormatter:SetBreakpoints({
    {
        threshold = 0,
        format = "%.1f",
    },
})

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

local function SetupAuraCooldownStyle(icon, cooldown, style)
    cooldown:SetShown(style ~= "none")
    cooldown:SetDrawEdge(style:find("edge$") ~= nil)
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

function AF_SecretAuraMixin:SetAura(unit, auraInstanceID)
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
    self.cooldown:SetCooldownFromDurationObject(duration)
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
    self.cooldown:SetCooldownFromDurationObject(duration)
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
    self.cooldown:SetCooldownFromDurationObject(previewDuration)
    self.durationTextBinding:SetDuration(previewDuration)
    self.durationTextBinding:Enable()
    SetAuraShown(self, true)
end

function AF_SecretAuraMixin:SetVisibilityManagedExternally(managed)
    self.visibilityManagedExternally = managed
end

function AF_SecretAuraMixin:SetCooldownStyle(style)
    self.cooldownStyle = style
    SetupAuraCooldownStyle(self.icon, self.cooldown, style)
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

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown = cooldown
    cooldown:SetAllPoints()
    cooldown:SetDrawBling(false)
    cooldown:SetDrawEdge(false)
    cooldown:SetUseAuraDisplayTime(true)

    local dispelOverlay = button:CreateTexture(nil, "OVERLAY")
    button.dispelOverlay = dispelOverlay
    dispelOverlay:SetAllPoints()
    dispelOverlay:SetTexture([[Interface\Buttons\UI-Debuff-Overlays]])
    dispelOverlay:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    dispelOverlay:Hide()

    local durationText = button:CreateFontString(nil, "OVERLAY", "AF_FONT_NORMAL")
    button.durationText = durationText

    local stackText = button:CreateFontString(nil, "OVERLAY", "AF_FONT_NORMAL")
    button.stackText = stackText

    button.durationTextBinding = C_DurationUtil.CreateDurationTextBinding()
    button.durationTextBinding:SetFontString(durationText)
    button.durationTextBinding:SetFormatter(durationFormatter)
    button.durationTextBinding:SetExpiredText("0.0")
    button.durationTextBinding:SetZeroDurationText("")
    button.durationTextBinding:SetUpdateInterval(0)

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
-- Retail 12.1.0.68914 (wow-ui-source d3915c78) replaces Retail's
-- SecureAuraHeaderTemplate with externally-instantiable AuraContainer and
-- CustomAuraButton intrinsics. Check the current exported schema rather than
-- probing protected frame creation or accepting the incompatible 68824 API.
local customAuraContainerLayoutDefaults = _G.CustomAuraContainerLayoutDefaults
local customAuraGroupDefaults = _G.CustomAuraContainerGroupDefaultOptions
local customAuraGroupLayoutDefaults = _G.CustomAuraContainerGroupLayoutDefaultOptions
local customAuraSlotDefaults = _G.CustomAuraContainerSlotDefaultOptions
local customItemEnchantmentDefaults = _G.CustomAuraContainerItemEnchantmentDefaultOptions
local customItemEnchantmentLayoutDefaults = _G.CustomAuraContainerItemEnchantmentLayoutDefaultOptions
local customDispelTypeTextureStyle = _G.Enum and Enum.CustomAuraButtonDispelTypeTextureStyle

AF.hasCustomAuraContainer = _G.C_AuraContainerUtil ~= nil
    and C_AuraContainerUtil.ProcessCustomAuraButtonApplicationCountOptions ~= nil
    and C_AuraContainerUtil.ProcessCustomAuraButtonDispelTypeTextureOptions ~= nil
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
    and customDispelTypeTextureStyle ~= nil
    and customDispelTypeTextureStyle.PreserveAsset ~= nil

local function AssertCustomAuraContainer()
    assert(AF.hasCustomAuraContainer, "12.1 CustomAuraContainerTemplate is unavailable")
end

local function CreateCustomAuraDurationTextBinding()
    local binding = C_DurationUtil.CreateDurationTextBinding()
    binding:SetFormatter(durationFormatter)
    binding:SetExpiredText("0.0")
    binding:SetZeroDurationText("")
    binding:SetUpdateInterval(0)
    return binding
end

local function InitializeCustomAuraButton(button, style)
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
        AF.SetSize(button, style.width, style.height)
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

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints()
    cooldown:SetDrawBling(false)
    cooldown:SetDrawEdge(false)
    cooldown:SetUseAuraDisplayTime(true)
    if style.cooldownStyle then
        SetupAuraCooldownStyle(icon, cooldown, style.cooldownStyle)
    end

    local durationText
    if style.durationText then
        durationText = button:CreateFontString(nil, "OVERLAY", "AF_FONT_NORMAL")
        SetupAuraDurationText(durationText, style.durationText)
    end

    local stackText
    if style.stackText then
        stackText = button:CreateFontString(nil, "OVERLAY", "AF_FONT_NORMAL")
        SetupAuraStackText(stackText, style.stackText)
    end

    local dispelOverlay
    if style.dispelColor then
        dispelOverlay = button:CreateTexture(nil, "OVERLAY")
        dispelOverlay:SetAllPoints()
        dispelOverlay:SetTexture([[Interface\Buttons\UI-Debuff-Overlays]])
        dispelOverlay:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
        dispelOverlay:Hide()
    end

    -- Blizzard applies DenyTaintedAccessWhenAurasAreSecret immediately after
    -- this initializer. Fully configure regions before attaching them, then
    -- leave the live button opaque to addon code.
    button:SetIcon(icon)
    button:SetDurationCooldown(cooldown)
    if durationText then
        button:SetDurationText(durationText, {
            binding = CreateCustomAuraDurationTextBinding(),
        })
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

local function GetCustomAuraButtonOptions(buttonOptions, buttonStyle)
    local options = AF.Copy(buttonOptions or {})
    local style = AF.Copy(buttonStyle or {})
    assert(options.initializeFrame == nil, "initializeFrame is managed by AbstractFramework")
    assert(options.templateNames == nil, "templateNames are managed by AbstractFramework")
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
        InitializeCustomAuraButton(button, style)
    end
    return options
end

---@return boolean
function AF.HasCustomAuraContainer()
    return AF.hasCustomAuraContainer
end

---@return Frame container
function AF.CreateCustomAuraContainer(parent, name, unit)
    AssertCustomAuraContainer()

    local container = CreateFrame("AuraContainer", name, parent, "CustomAuraContainerTemplate")
    container:SetSize(1, 1)
    if unit ~= nil then
        container:SetUnit(unit)
    end
    return container
end

function AF.SetCustomAuraContainerFlowLayout(container, layoutOptions)
    AssertCustomAuraContainer()

    local layout = AF.Copy(customAuraContainerLayoutDefaults, layoutOptions or {})
    container:SetFlowLayoutAxis(layout.axis)
    container:SetFlowLayoutAnchorPoint(layout.anchorPoint)
    container:SetFlowLayoutGrowthDirection(layout.horizontalGrowthDirection, layout.verticalGrowthDirection)
    container:SetFlowLayoutPadding(layout.paddingLeft, layout.paddingRight, layout.paddingTop, layout.paddingBottom)
    container:SetFlowLayoutMaximumLineSize(layout.maximumLineSize)
end

function AF.ResetCustomAuraContainerFlowLayout(container)
    AssertCustomAuraContainer()
    container:ResetFlowLayoutOptions()
end

function AF.SetCustomAuraContainerUnit(container, unit)
    AssertCustomAuraContainer()
    container:SetUnit(unit)
end

function AF.SetCustomAuraContainerEnabled(container, enabled)
    AssertCustomAuraContainer()
    container:SetEnabled(enabled)
end

function AF.UpdateCustomAuraContainer(container)
    AssertCustomAuraContainer()
    container:UpdateAllAuras()
end

function AF.SetCustomAuraContainerProcessingPolicy(container, processingPolicy, options)
    AssertCustomAuraContainer()
    container:SetAuraProcessingPolicy(processingPolicy, options)
end

function AF.AddCustomAuraGroup(container, groupKey, filterString, groupOptions, buttonStyle)
    AssertCustomAuraContainer()

    local options = GetCustomAuraButtonOptions(groupOptions, buttonStyle)
    container:AddAuraGroup(groupKey, filterString, options)
end

function AF.SetCustomAuraGroupFilterString(container, groupKey, filterString)
    AssertCustomAuraContainer()
    container:SetAuraGroupFilterString(groupKey, filterString)
end

function AF.SetCustomAuraGroupMaxFrameCount(container, groupKey, maxFrameCount)
    AssertCustomAuraContainer()
    container:SetAuraGroupMaxFrameCount(groupKey, maxFrameCount)
end

function AF.SetCustomAuraGroupCandidateFilters(container, groupKey, candidateFilters)
    AssertCustomAuraContainer()
    container:SetAuraGroupCandidateFilters(groupKey, candidateFilters)
end

function AF.SetCustomAuraGroupSortMethod(container, groupKey, sortMethod, sortDirection)
    AssertCustomAuraContainer()
    container:SetAuraGroupSortMethod(groupKey, sortMethod, sortDirection)
end

function AF.SetCustomAuraGroupLayout(container, groupKey, layoutOptions)
    AssertCustomAuraContainer()
    container:SetAuraGroupLayout(groupKey, layoutOptions)
end

function AF.AddCustomAuraSlot(container, slotKey, filterString, slotOptions, buttonStyle)
    AssertCustomAuraContainer()

    local options = GetCustomAuraButtonOptions(slotOptions, buttonStyle)
    return container:AddAuraSlot(slotKey, filterString, options)
end

function AF.SetCustomAuraSlotFilterString(container, slotKey, filterString)
    AssertCustomAuraContainer()
    container:SetAuraSlotFilterString(slotKey, filterString)
end

function AF.SetCustomAuraSlotCandidateFilters(container, slotKey, candidateFilters)
    AssertCustomAuraContainer()
    container:SetAuraSlotCandidateFilters(slotKey, candidateFilters)
end

function AF.SetCustomAuraSlotSortMethod(container, slotKey, sortMethod, sortDirection)
    AssertCustomAuraContainer()
    container:SetAuraSlotSortMethod(slotKey, sortMethod, sortDirection)
end

function AF.AddCustomItemEnchantment(container, itemEnchantmentSlot, enchantmentOptions, buttonStyle)
    AssertCustomAuraContainer()

    local options = GetCustomAuraButtonOptions(enchantmentOptions, buttonStyle)
    return container:AddItemEnchantment(itemEnchantmentSlot, options)
end

function AF.SetCustomItemEnchantmentSortMethod(container, sortMethod, sortDirection)
    AssertCustomAuraContainer()
    container:SetItemEnchantmentSortMethod(sortMethod, sortDirection)
end

function AF.SetCustomItemEnchantmentLayout(container, layoutOptions)
    AssertCustomAuraContainer()
    container:SetItemEnchantmentLayout(layoutOptions)
end

function AF.ResetCustomItemEnchantmentLayout(container)
    AssertCustomAuraContainer()
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

function AF_SecretAuraListMixin:SetMatchFilters(matchFilters)
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
                if not IsAuraFilteredOutByInstanceID(self.unit, auraInstanceID, matchFilter) then
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
    if self.unit then
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
