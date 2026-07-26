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

local interruptReadinessBars = setmetatable({}, {__mode = "k"})
local interruptReadinessDriver = CreateFrame("Frame")
local interruptReadinessElapsed = 0
local INTERRUPT_READINESS_INTERVAL = 1 / 60

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

local function HasInterruptReadinessPresentation(castBar)
    return castBar.interruptReadinessColoring
        or castBar.interruptReadyCastMarker
        or castBar.interruptReadyChannelMarker
end

local function UpdateInterruptReadinessDriver()
    for castBar in pairs(interruptReadinessBars) do
        if castBar.hasLiveCastData
            and HasInterruptReadinessPresentation(castBar)
        then
            return interruptReadinessDriver:Show()
        end
        interruptReadinessBars[castBar] = nil
    end
    interruptReadinessDriver:Hide()
end

local function SetInterruptReadinessActive(castBar, active)
    if active and HasInterruptReadinessPresentation(castBar) then
        interruptReadinessBars[castBar] = true
    else
        interruptReadinessBars[castBar] = nil
    end
    UpdateInterruptReadinessDriver()
end

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

function AF_SecretCastBarMixin:SetInterruptibleCastRegion(region)
    if self.interruptibleCastRegion then
        self.interruptibleCastRegion:SetAlpha(0)
    end
    self.interruptibleCastRegion = region
    if region then
        region:SetAlpha(0)
    end
end

function AF_SecretCastBarMixin:SetInterruptReadinessColoring(enabled)
    self.interruptReadinessColoring = enabled == true
    if self.hasLiveCastData then
        self:UpdateInterruptReadiness()
    else
        self:ApplyNormalCastColor()
    end
    SetInterruptReadinessActive(self, self.hasLiveCastData)
end

function AF_SecretCastBarMixin:SetInterruptReadyMarkers(
    castMarker,
    channelMarker
)
    if self.interruptReadyCastMarker then
        self.interruptReadyCastMarker:SetAlpha(0)
    end
    if self.interruptReadyChannelMarker then
        self.interruptReadyChannelMarker:SetAlpha(0)
    end

    self.interruptReadyCastMarker = castMarker
    self.interruptReadyChannelMarker = channelMarker

    if castMarker then
        castMarker:SetAlpha(0)
    end
    if channelMarker then
        channelMarker:SetAlpha(0)
    end

    if self.hasLiveCastData then
        self:UpdateInterruptReadiness()
    end
    SetInterruptReadinessActive(self, self.hasLiveCastData)
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

function AF_SecretCastBarMixin:ApplyInterruptibilityColor(
    notInterruptible,
    cooldownDuration
)
    local colors = self.interruptibilityColors
    if not self.statusBar or not colors then return end

    local normal = colors.normal
    local interruptible = colors.interruptible
    local uninterruptible = colors.uninterruptible
    local ready = cooldownDuration and cooldownDuration:IsZero()

    local interruptibleR = interruptible[1]
    local interruptibleG = interruptible[2]
    local interruptibleB = interruptible[3]
    local interruptibleA = interruptible[4]

    if self.interruptReadinessColoring
        and self.hasLiveCastData
    then
        if cooldownDuration then
            interruptibleR = EvaluateColorValueFromBoolean(
                ready,
                interruptible[1],
                normal[1]
            )
            interruptibleG = EvaluateColorValueFromBoolean(
                ready,
                interruptible[2],
                normal[2]
            )
            interruptibleB = EvaluateColorValueFromBoolean(
                ready,
                interruptible[3],
                normal[3]
            )
            interruptibleA = EvaluateColorValueFromBoolean(
                ready,
                interruptible[4],
                normal[4]
            )
        else
            interruptibleR = normal[1]
            interruptibleG = normal[2]
            interruptibleB = normal[3]
            interruptibleA = normal[4]
        end
    end

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
            interruptibleR
        ),
        EvaluateColorValueFromBoolean(
            notInterruptible,
            uninterruptible[2],
            interruptibleG
        ),
        EvaluateColorValueFromBoolean(
            notInterruptible,
            uninterruptible[3],
            interruptibleB
        ),
        EvaluateColorValueFromBoolean(
            notInterruptible,
            uninterruptible[4],
            interruptibleA
        )
    )
end

function AF_SecretCastBarMixin:ApplyInterruptibilityState(
    notInterruptible
)
    self.castNotInterruptible = notInterruptible
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
    -- SimpleRegion.SetAlphaFromBoolean is AllowedWhenTainted in the same
    -- pinned Retail builds documented above. Inverting the native sink lets
    -- consumers present mutually exclusive decorations without inspecting
    -- the possibly secret interruptibility flag in Lua.
    if self.interruptibleCastRegion then
        self.interruptibleCastRegion:SetAlphaFromBoolean(
            notInterruptible,
            0,
            1
        )
    end
end

function AF_SecretCastBarMixin:UpdateInterruptReadiness(
    cooldownDuration,
    cooldownResolved
)
    if not self.hasLiveCastData or not self.duration then
        if self.interruptReadyCastMarker then
            self.interruptReadyCastMarker:SetAlpha(0)
        end
        if self.interruptReadyChannelMarker then
            self.interruptReadyChannelMarker:SetAlpha(0)
        end
        return
    end

    if not cooldownResolved then
        cooldownDuration = select(
            2,
            AF.GetPrimaryInterruptCooldownDuration()
        )
    end

    local castMarker = self.interruptReadyCastMarker
    local channelMarker = self.interruptReadyChannelMarker
    local activeMarker
    if self.castType == "channel" then
        activeMarker = channelMarker
        if castMarker then castMarker:SetAlpha(0) end
    else
        activeMarker = castMarker
        if channelMarker then channelMarker:SetAlpha(0) end
    end

    if not cooldownDuration then
        if activeMarker then activeMarker:SetAlpha(0) end
        self:ApplyInterruptibilityColor(
            self.castNotInterruptible
        )
        return
    end

    if activeMarker then
        -- Retail 12.0.7.68887 (wow-ui-source 4383ced) and
        -- 12.1.0.68824 (wow-ui-source fa38386): duration accessors may
        -- return secret timing values. SimpleStatusBar's range/value sinks
        -- and SimpleRegion:SetAlphaFromBoolean accept them. Keep the two
        -- marker bars pre-anchored; C-side fill geometry and clipping place
        -- the tick without Lua reading or calculating either duration.
        activeMarker:SetMinMaxValues(
            0,
            self.duration:GetRemainingDuration(),
            Immediate
        )
        activeMarker:SetValue(
            cooldownDuration:GetRemainingDuration(),
            Immediate
        )
        activeMarker:SetAlphaFromBoolean(
            cooldownDuration:IsZero(),
            0,
            EvaluateColorValueFromBoolean(
                self.castNotInterruptible,
                0,
                1
            )
        )
    end

    self:ApplyInterruptibilityColor(
        self.castNotInterruptible,
        cooldownDuration
    )
end

function AF_SecretCastBarMixin:UpdateLiveCastSinks(
    spellID,
    notInterruptible
)
    self.hasLiveCastData = true
    self.castNotInterruptible = notInterruptible

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
    self:UpdateInterruptReadiness()
    SetInterruptReadinessActive(self, true)
end

function AF_SecretCastBarMixin:ClearCastSinks()
    self.hasLiveCastData = false
    self.castNotInterruptible = nil
    SetInterruptReadinessActive(self, false)

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
    if self.interruptibleCastRegion then
        self.interruptibleCastRegion:SetAlpha(0)
    end
    if self.interruptReadyCastMarker then
        self.interruptReadyCastMarker:SetAlpha(0)
    end
    if self.interruptReadyChannelMarker then
        self.interruptReadyChannelMarker:SetAlpha(0)
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

interruptReadinessDriver:SetScript(
    "OnUpdate",
    function(_, elapsed)
        interruptReadinessElapsed =
            interruptReadinessElapsed + elapsed
        if interruptReadinessElapsed
            < INTERRUPT_READINESS_INTERVAL
        then
            return
        end
        interruptReadinessElapsed = 0

        if not next(interruptReadinessBars) then
            interruptReadinessDriver:Hide()
            return
        end

        local _, cooldownDuration =
            AF.GetPrimaryInterruptCooldownDuration()
        for castBar in pairs(interruptReadinessBars) do
            castBar:UpdateInterruptReadiness(
                cooldownDuration,
                true
            )
        end
    end
)
interruptReadinessDriver:Hide()

---@return AF_SecretCastBar castBar
function AF.CreateSecretCastBar(parent, name)
    local frame = CreateFrame("Frame", name, parent)
    Mixin(frame, AF_SecretCastBarMixin)

    frame.durationTextBinding = C_DurationUtil.CreateDurationTextBinding()
    frame:SetScript("OnEvent", OnEvent)
    frame:Hide()

    return frame
end
