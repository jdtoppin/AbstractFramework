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

---@class AF_SecretAura:Button
local AF_SecretAuraMixin = {}

function AF_SecretAuraMixin:SetAura(unit, auraInstanceID)
    self.unit = unit
    self.auraInstanceID = auraInstanceID

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
    self:Show()
end

function AF_SecretAuraMixin:ClearAura()
    self.unit = nil
    self.auraInstanceID = nil
    self.duration = nil
    self.durationTextBinding:Disable()
    self.stackText:SetText("")
    self.icon:SetTexture(self.fallbackIcon)
    self.dispelOverlay:Hide()
    self:Hide()
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
    local previewDuration = C_DurationUtil.CreateDuration()
    previewDuration:SetTimeFromStart(startTime, duration)
    self.duration = previewDuration

    self.icon:SetTexture(icon)
    self.dispelOverlay:Hide()
    self.stackText:SetText(applications)
    self.cooldown:SetCooldownFromDurationObject(previewDuration)
    self.durationTextBinding:SetDuration(previewDuration)
    self.durationTextBinding:Enable()
    self:Show()
end

function AF_SecretAuraMixin:SetCooldownStyle(style)
    self.cooldownStyle = style
    self.cooldown:SetShown(style ~= "none")
    self.cooldown:SetDrawEdge(style:find("edge$") ~= nil)
    self.icon:SetShown(style:find("^block") == nil)
end

function AF_SecretAuraMixin:SetupDurationText(config)
    self.durationText:SetShown(config.enabled)
    AF.SetFont(self.durationText, unpack(config.font))
    AF.LoadTextPosition(self.durationText, config.position)
    self.durationText:SetTextColor(AF.UnpackColor(config.color.normal))
end

function AF_SecretAuraMixin:SetupStackText(config)
    self.stackText:SetShown(config.enabled)
    AF.SetFont(self.stackText, unpack(config.font))
    AF.LoadTextPosition(self.stackText, config.position)
    self.stackText:SetTextColor(AF.UnpackColor(config.color))
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
    if not self.tooltipConfig or not self.tooltipConfig.enabled or not self.auraInstanceID then return end

    local config = self.tooltipConfig
    if config.anchorTo == "self" and config.position then
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint(config.position[1], self, config.position[2], config.position[3], config.position[4])
    else
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
    end

    GameTooltip:SetUnitAuraByAuraInstanceID(self.unit, self.auraInstanceID)
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
function AF.InitAura(button, noBorder)
    Mixin(button, AF_SecretAuraMixin)

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
    button:Hide()

    return button
end

---@return AF_SecretAura aura
function AF.CreateAura(parent, noBorder)
    return AF.InitAura(CreateFrame("Button", nil, parent), noBorder)
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
