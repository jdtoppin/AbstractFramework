---@class AbstractFramework
local AF = select(2, ...)

local UnitClassBase = UnitClassBase
local UnitIsCharmed = UnitIsCharmed
local UnitName = UnitName
local UnitSelectionColor = UnitSelectionColor

---@class AF_SecretNameText:AF_FontString
local AF_SecretNameTextMixin = {}

function AF_SecretNameTextMixin:UpdateColor()
    if not self.color or not self.unit then return end

    local r, g, b
    if self.color.type == "selection_color" then
        r, g, b = UnitSelectionColor(self.unit, true)
        self:SetVertexColorFromBoolean(
            UnitIsCharmed(self.unit),
            CreateColor(AF.GetColorRGB("CHARMED")),
            CreateColor(r, g, b)
        )
        return
    elseif self.color.type == "class_color" then
        -- Retained for group-frame consumers. Nameplate consumers can use
        -- selection_color to avoid a class-identity lookup.
        if AF.UnitIsPlayer(self.unit) then
            r, g, b = AF.GetClassColor(UnitClassBase(self.unit))
        else
            r, g, b = AF.GetReactionColor(self.unit)
        end
    else
        r, g, b = AF.UnpackColor(self.color.rgb)
    end
    self:SetVertexColor(r, g, b)
end

function AF_SecretNameTextMixin:UpdateName()
    -- Retail 12.0.7 (wow-ui-source 6e96727): UnitName can return secret
    -- identity text and SimpleFontString.SetText accepts secret text.
    self:SetText((UnitName(self.unit)))
    self:UpdateColor()
end

function AF_SecretNameTextMixin:SetLength(length)
    self.length = length
    self:SetWordWrap(false)
    if length and length > 0 then
        self:SetWidth(self:GetParent():GetWidth() * length)
    else
        self:SetWidth(0)
    end
end

function AF_SecretNameTextMixin:SetUnit(unit)
    self.unit = unit
    self.eventFrame:UnregisterAllEvents()
    self.eventFrame:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
    self.eventFrame:RegisterUnitEvent("UNIT_FACTION", unit)
    self:UpdateName()
end

function AF_SecretNameTextMixin:ClearUnit()
    self.eventFrame:UnregisterAllEvents()
    self.unit = nil
    -- Retail 12.0.7 (wow-ui-source 4383ced) and 12.1
    -- (d3915c7): ClearText removes the Text secret aspect.
    self:ClearText()
end

local function OnEvent(self)
    self.owner:UpdateName()
end

---@return AF_SecretNameText text
function AF.CreateSecretNameText(parent, name)
    local text = AF.CreateFontString(parent)
    text._widgetName = name
    Mixin(text, AF_SecretNameTextMixin)

    text.eventFrame = CreateFrame("Frame", nil, parent)
    text.eventFrame.owner = text
    text.eventFrame:SetScript("OnEvent", OnEvent)

    return text
end
