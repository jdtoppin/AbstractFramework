---@class AbstractFramework
local AF = select(2, ...)

local UnitCastingDuration = UnitCastingDuration
local UnitCastingInfo = UnitCastingInfo
local UnitChannelDuration = UnitChannelDuration
local UnitChannelInfo = UnitChannelInfo

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
end

function AF_SecretCastBarMixin:SetNameText(fontString)
    self.nameText = fontString
end

function AF_SecretCastBarMixin:SetIcon(texture)
    self.icon = texture
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

function AF_SecretCastBarMixin:ApplyCast(name, texture, duration, direction, castType, castBarID)
    -- Retail 12.0.7 (wow-ui-source 6e96727): UnitCastingDuration may
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

    self:Show()
    self:OnCastStart(castType, castBarID, isNewCast)
end

function AF_SecretCastBarMixin:UpdateCasting()
    local name, _, texture, _, _, _, _, _, _, castBarID = UnitCastingInfo(self.unit)
    self:ApplyCast(name, texture, UnitCastingDuration(self.unit), ElapsedTime, "cast", castBarID)
end

function AF_SecretCastBarMixin:UpdateChanneling(castType)
    local name, _, texture, _, _, _, _, _, isEmpowered, _, castBarID = UnitChannelInfo(self.unit)
    local direction = isEmpowered and ElapsedTime or RemainingTime
    self:ApplyCast(name, texture, UnitChannelDuration(self.unit), direction, castType, castBarID)
end

function AF_SecretCastBarMixin:UpdateCurrentCast()
    local castName, _, castTexture, _, _, _, _, _, _, castBarID = UnitCastingInfo(self.unit)
    if castBarID then
        self:ApplyCast(castName, castTexture, UnitCastingDuration(self.unit), ElapsedTime, "cast", castBarID)
        return
    end

    local channelName, _, channelTexture, _, _, _, _, _, isEmpowered, _, channelCastBarID = UnitChannelInfo(self.unit)
    if channelCastBarID then
        local castType = isEmpowered and "empower" or "channel"
        local direction = isEmpowered and ElapsedTime or RemainingTime
        self:ApplyCast(channelName, channelTexture, UnitChannelDuration(self.unit), direction, castType, channelCastBarID)
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
        self.nameText:SetText("")
    end
    if self.icon then
        self.icon:SetTexture(nil)
    end

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
    self:ApplyCast(name, texture, duration, direction, castType or "cast", -1)
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
        self:OnInterruptibilityChanged(true)
    elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
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
