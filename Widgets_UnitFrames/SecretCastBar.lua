---@class AbstractFramework
local AF = select(2, ...)

local UnitCastingDuration = UnitCastingDuration
local UnitCastingInfo = UnitCastingInfo
local UnitChannelDuration = UnitChannelDuration
local UnitChannelInfo = UnitChannelInfo
local PlayerIsSpellTarget = PlayerIsSpellTarget
local UnitSpellTargetName = UnitSpellTargetName

local EvaluateColorValueFromBoolean =
    C_CurveUtil.EvaluateColorValueFromBoolean
local IsSpellImportant = C_Spell.IsSpellImportant

local Immediate = Enum.StatusBarInterpolation.Immediate
local ElapsedTime = Enum.StatusBarTimerDirection.ElapsedTime
local RemainingTime = Enum.StatusBarTimerDirection.RemainingTime

local CAST_EVENTS = {
    UNIT_SPELLCAST_DELAYED = true,
    UNIT_SPELLCAST_START = true,
}

local CHANNEL_EVENTS = {
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_CHANNEL_UPDATE = true,
}

local EMPOWER_EVENTS = {
    UNIT_SPELLCAST_EMPOWER_START = true,
    UNIT_SPELLCAST_EMPOWER_UPDATE = true,
}

local STOP_EVENTS = {
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_STOP = true,
    UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_FAILED_QUIET = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_STOP = true,
}

local durationFormatter = C_StringUtil.CreateNumericRuleFormatter()
durationFormatter:SetBreakpoints({
    {
        threshold = 0,
        format = "%.1f",
    },
})

---@class AF_SecretCastBar:Frame
local AF_SecretCastBarMixin = {}

function AF_SecretCastBarMixin:SetStatusBar(statusBar)
    self.statusBar = statusBar
    self:ApplyNormalCastColor()
end

function AF_SecretCastBarMixin:SetNameText(fontString)
    self.nameText = fontString
end

function AF_SecretCastBarMixin:SetIcon(texture)
    self.icon = texture
end

function AF_SecretCastBarMixin:SetImportantCastRegion(region)
    if self.importantCastRegion then
        self.importantCastRegion:SetAlpha(0)
    end
    self.importantCastRegion = region
    if region then
        region:SetAlpha(0)
    end
end

function AF_SecretCastBarMixin:SetSpellTargetText(fontString)
    if self.spellTargetText then
        self.spellTargetText:ClearText()
    end
    self.spellTargetText = fontString
    if fontString then
        fontString:ClearText()
    end
end

function AF_SecretCastBarMixin:SetPlayerTargetRegion(region)
    if self.playerTargetRegion then
        self.playerTargetRegion:SetAlpha(0)
    end
    self.playerTargetRegion = region
    if region then
        region:SetAlpha(0)
    end
end

function AF_SecretCastBarMixin:SetUninterruptibleCastRegion(region)
    if self.uninterruptibleCastRegion then
        self.uninterruptibleCastRegion:SetAlpha(0)
    end
    self.uninterruptibleCastRegion = region
    if region then
        region:SetAlpha(0)
    end
end

function AF_SecretCastBarMixin:SetDurationText(fontString)
    self.durationText = fontString
    self.durationTextBinding:SetFontString(fontString)
    self.durationTextBinding:SetFormatter(durationFormatter)
    self.durationTextBinding:SetExpiredText("0.0")
    self.durationTextBinding:SetZeroDurationText("")
    self.durationTextBinding:SetUpdateInterval(0)
end

function AF_SecretCastBarMixin:OnCastStart()
end

function AF_SecretCastBarMixin:OnCastStop()
end

function AF_SecretCastBarMixin:OnInterruptibilityChanged()
end

local function CopyRGBA(color)
    return {
        color[1],
        color[2],
        color[3],
        color[4] == nil and 1 or color[4],
    }
end

---@param normalColor number[]
---@param interruptibleColor number[]
---@param uninterruptibleColor number[]
function AF_SecretCastBarMixin:SetInterruptibilityColors(
    normalColor,
    interruptibleColor,
    uninterruptibleColor
)
    -- These three colors are static consumer configuration, never values
    -- derived from a restricted unit.
    self.interruptibilityColors = {
        normal = CopyRGBA(normalColor),
        interruptible = CopyRGBA(interruptibleColor),
        uninterruptible = CopyRGBA(uninterruptibleColor),
    }
    self:ApplyNormalCastColor()
end

function AF_SecretCastBarMixin:ClearInterruptibilityColors()
    self:ApplyNormalCastColor()
    self.interruptibilityColors = nil
end

function AF_SecretCastBarMixin:ApplyNormalCastColor()
    local colors = self.interruptibilityColors
    if not self.statusBar or not colors then return end

    self.statusBar:SetStatusBarColor(unpack(colors.normal))
end

function AF_SecretCastBarMixin:ApplyInterruptibilityColor(notInterruptible)
    local colors = self.interruptibilityColors
    if not self.statusBar or not colors then return end

    local interruptible = colors.interruptible
    local uninterruptible = colors.uninterruptible

    -- Retail 12.0.7.68887 (wow-ui-source 4383ced) and 12.1.0.68824
    -- (wow-ui-source fa38386): UnitCastingInfo and UnitChannelInfo are
    -- SecretWhenUnitSpellCastRestricted. C_CurveUtil's component evaluator
    -- accepts tainted secret booleans, and SimpleStatusBar.SetStatusBarColor
    -- accepts the resulting tainted color components. Do not branch on or
    -- expose notInterruptible to a consumer callback.
    self.statusBar:SetStatusBarColor(
        EvaluateColorValueFromBoolean(
            notInterruptible,
            uninterruptible[1],
            interruptible[1]
        ),
        EvaluateColorValueFromBoolean(
            notInterruptible,
            uninterruptible[2],
            interruptible[2]
        ),
        EvaluateColorValueFromBoolean(
            notInterruptible,
            uninterruptible[3],
            interruptible[3]
        ),
        EvaluateColorValueFromBoolean(
            notInterruptible,
            uninterruptible[4],
            interruptible[4]
        )
    )
end

function AF_SecretCastBarMixin:ApplyInterruptibilityState(
    notInterruptible
)
    self:ApplyInterruptibilityColor(notInterruptible)
    -- Keep optional uninterruptible decoration in the same native boolean
    -- sink path so mid-cast attachment never needs to inspect the flag.
    if self.uninterruptibleCastRegion then
        self.uninterruptibleCastRegion:SetAlphaFromBoolean(
            notInterruptible,
            1,
            0
        )
    end
end

function AF_SecretCastBarMixin:UpdateLiveCastSinks(
    spellID,
    notInterruptible
)
    -- Retail 12.0.7.68887 (wow-ui-source 4383ced) and 12.1.0.68824
    -- (wow-ui-source fa38386): C_Spell.IsSpellImportant accepts tainted
    -- secret spell identifiers and SimpleRegion.SetAlphaFromBoolean accepts
    -- the resulting boolean without exposing it to Lua control flow.
    if self.importantCastRegion then
        self.importantCastRegion:SetAlphaFromBoolean(
            IsSpellImportant(spellID),
            1,
            0
        )
    end

    -- The same builds document UnitSpellTargetName and
    -- PlayerIsSpellTarget as SecretReturns. SimpleFontString.SetText and
    -- SimpleRegion.SetAlphaFromBoolean are their respective native sinks.
    if self.spellTargetText then
        self.spellTargetText:SetText(UnitSpellTargetName(self.unit))
    end
    if self.playerTargetRegion then
        self.playerTargetRegion:SetAlphaFromBoolean(
            PlayerIsSpellTarget(self.unit),
            1,
            0
        )
    end

    self:ApplyInterruptibilityState(notInterruptible)
end

function AF_SecretCastBarMixin:ClearCastSinks()
    if self.importantCastRegion then
        self.importantCastRegion:SetAlpha(0)
    end
    if self.spellTargetText then
        self.spellTargetText:ClearText()
    end
    if self.playerTargetRegion then
        self.playerTargetRegion:SetAlpha(0)
    end
    if self.uninterruptibleCastRegion then
        self.uninterruptibleCastRegion:SetAlpha(0)
    end
    self:ApplyNormalCastColor()
end

function AF_SecretCastBarMixin:ApplyCast(
    name,
    texture,
    duration,
    direction,
    castType,
    castBarID,
    spellID,
    notInterruptible,
    hasLiveCastData
)
    -- Retail 12.0.7.68887 (wow-ui-source 4383ced): UnitCastingDuration may
    -- return a secret LuaDurationObject. Copy() is explicitly
    -- ReturnsNeverSecret, providing an opaque handle whose internal values can
    -- be consumed by native duration-aware widgets without Lua inspecting
    -- start, end, elapsed, remaining, or total duration values.
    local durationCopy = duration:Copy()
    local isNewCast = not self:IsShown() or self.castBarID ~= castBarID or self.castType ~= castType

    self.castBarID = castBarID
    self.castType = castType
    self.duration = durationCopy

    if self.nameText then
        self.nameText:SetText(name)
    end
    if self.icon then
        self.icon:SetTexture(texture)
    end
    if self.statusBar then
        self.statusBar:SetTimerDuration(durationCopy, Immediate, direction)
    end
    if self.durationText then
        self.durationTextBinding:SetDuration(durationCopy)
        self.durationTextBinding:Enable()
    end

    self:ApplyNormalCastColor()
    if hasLiveCastData then
        -- hasLiveCastData is an ordinary call-site fact. spellID and
        -- notInterruptible are forwarded only to native secret-capable sinks.
        self:UpdateLiveCastSinks(spellID, notInterruptible)
    else
        self:ClearCastSinks()
    end

    self:Show()
    self:OnCastStart(castType, castBarID, isNewCast)
end

function AF_SecretCastBarMixin:UpdateCasting()
    self:UpdateCurrentCast()
end

function AF_SecretCastBarMixin:UpdateChanneling()
    self:UpdateCurrentCast()
end

function AF_SecretCastBarMixin:UpdateCurrentCast()
    local castName, _, castTexture, _, _, _, _, castNotInterruptible,
        castSpellID, castBarID = UnitCastingInfo(self.unit)
    if castBarID then
        self:ApplyCast(
            castName,
            castTexture,
            UnitCastingDuration(self.unit),
            ElapsedTime,
            "cast",
            castBarID,
            castSpellID,
            castNotInterruptible,
            true
        )
        return
    end

    local channelName, _, channelTexture, _, _, _, channelNotInterruptible,
        channelSpellID, isEmpowered, _, channelCastBarID =
        UnitChannelInfo(self.unit)
    if channelCastBarID then
        local castType = isEmpowered and "empower" or "channel"
        local direction = isEmpowered and ElapsedTime or RemainingTime
        self:ApplyCast(
            channelName,
            channelTexture,
            UnitChannelDuration(self.unit),
            direction,
            castType,
            channelCastBarID,
            channelSpellID,
            channelNotInterruptible,
            true
        )
        return
    end

    self:StopCast()
end

function AF_SecretCastBarMixin:StopCast(reason)
    self.castBarID = nil
    self.castType = nil
    self.duration = nil
    self.durationTextBinding:Disable()

    if self.nameText then
        self.nameText:ClearText()
    end
    if self.icon then
        self.icon:SetTexture(nil)
    end
    self:ClearCastSinks()

    self:Hide()
    self:OnCastStop(reason)
end

function AF_SecretCastBarMixin:RegisterUnitEvents()
    self:UnregisterAllEvents()
    if not self.unit then return end

    for event in pairs(CAST_EVENTS) do
        self:RegisterUnitEvent(event, self.unit)
    end
    for event in pairs(CHANNEL_EVENTS) do
        self:RegisterUnitEvent(event, self.unit)
    end
    for event in pairs(EMPOWER_EVENTS) do
        self:RegisterUnitEvent(event, self.unit)
    end
    for event in pairs(STOP_EVENTS) do
        self:RegisterUnitEvent(event, self.unit)
    end

    self:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", self.unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", self.unit)
end

function AF_SecretCastBarMixin:SetUnit(unit)
    self.unit = unit
    self:RegisterUnitEvents()
    self:UpdateCurrentCast()
end

function AF_SecretCastBarMixin:ClearUnit()
    self.unit = nil
    self:UnregisterAllEvents()
    self:StopCast()
end

function AF_SecretCastBarMixin:SetPreview(name, texture, seconds, castType)
    self:UnregisterAllEvents()

    local duration = C_DurationUtil.CreateDuration()
    duration:SetTimeFromStart(GetTime(), seconds)

    local direction = castType == "channel" and RemainingTime or ElapsedTime
    self:ApplyCast(
        name,
        texture,
        duration,
        direction,
        castType or "cast",
        -1,
        nil,
        nil,
        false
    )
end

local function OnEvent(self, event)
    -- Registered unit events already filter by self.unit. Their cast GUID and
    -- spell ID payloads may be secret, so this handler intentionally accepts
    -- and ignores them and only branches on the non-secret event name.
    if CAST_EVENTS[event] then
        self:UpdateCasting()
    elseif CHANNEL_EVENTS[event] then
        self:UpdateChanneling("channel")
    elseif EMPOWER_EVENTS[event] then
        self:UpdateChanneling("empower")
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        self:ApplyInterruptibilityState(false)
        self:OnInterruptibilityChanged(true)
    elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        self:ApplyInterruptibilityState(true)
        self:OnInterruptibilityChanged(false)
    else
        self:StopCast(event)
    end
end

---@return AF_SecretCastBar castBar
function AF.CreateSecretCastBar(parent, name)
    local frame = CreateFrame("Frame", name, parent)
    Mixin(frame, AF_SecretCastBarMixin)

    frame.durationTextBinding = C_DurationUtil.CreateDurationTextBinding()
    frame:SetScript("OnEvent", OnEvent)
    frame:Hide()

    return frame
end
