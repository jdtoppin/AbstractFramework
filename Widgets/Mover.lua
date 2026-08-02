---@class AbstractFramework
local AF = select(2, ...)
local L = AF.L
local F = AF.funcs

local MOVER_PARENT_FRAME_LEVEL = 700
local MOVER_ON_TOP_FRAME_LEVEL = 777
local FINE_TUNING_FRAME_LEVEL = 800
local movers = {}

local moverParent, moverDialog, alignmentGrid, positionEditorFrame
local anchorLockedText
local CreatePositionEditorFrame, AnchorPositionEditorFrame, UpdateAndSave, UpdatePositionEditorFrame
local isAnchorLocked = false
local hidingMovers = false
local modified = {}

-- Retail 12.1.0.68914 (wow-ui-source d3915c78) marks frame points,
-- dimensions, centers, edges, and scale as secret-capable. GetPoint may also
-- return nothing. Mover interaction therefore validates every native result
-- before Lua work and uses AF's ordinary point ledger for initial snapshots.
local anchorPoints = {
    CENTER = true,
    LEFT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
    RIGHT = true,
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
}

local function IsOrdinaryNumber(value)
    return F.isValueNonSecret(value)
        and type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function IsOrdinaryFramePoint(value)
    return F.isValueNonSecret(value)
        and type(value) == "string"
        and anchorPoints[value] == true
end

local function GetOrdinaryPoint(owner)
    local point, relativeTo, relativePoint, x, y = owner:GetPoint()
    if not IsOrdinaryFramePoint(point)
        or not F.isValueNonSecret(relativeTo)
        or not IsOrdinaryFramePoint(relativePoint)
        or not IsOrdinaryNumber(x)
        or not IsOrdinaryNumber(y)
    then
        return
    end
    return point, relativeTo, relativePoint, x, y
end

local function GetOrdinaryScale(owner, effective)
    local scale
    if effective then
        scale = owner:GetEffectiveScale()
    else
        scale = owner:GetScale()
    end
    if not IsOrdinaryNumber(scale) or scale <= 0 then return end
    return scale
end

local function GetOrdinaryCenter(region)
    local x, y = region:GetCenter()
    if not IsOrdinaryNumber(x) or not IsOrdinaryNumber(y) then return end
    return x, y
end

local function GetOrdinarySize(region)
    local width, height = region:GetSize()
    if not IsOrdinaryNumber(width) or not IsOrdinaryNumber(height) then return end
    return width, height
end

local function GetOrdinaryPositionLedger(owner)
    local points = owner._points
    if not F.isValueNonSecret(points) or type(points) ~= "table" then return end

    local position
    for _, candidate in pairs(points) do
        if position then return end
        if not F.isValueNonSecret(candidate) or type(candidate) ~= "table" then return end
        position = candidate
    end
    if not position then return end

    local point = position[1]
    local relativeTo = position[2]
    local relativePoint = position[3]
    local x = position[4]
    local y = position[5]
    if not IsOrdinaryFramePoint(point)
        or not F.isValueNonSecret(relativeTo)
        or not IsOrdinaryFramePoint(relativePoint)
        or not IsOrdinaryNumber(x)
        or not IsOrdinaryNumber(y)
    then
        return
    end

    return point, x, y
end

local function ApplyOwnerPoint(owner, point, x, y)
    if not IsOrdinaryFramePoint(point)
        or not IsOrdinaryNumber(x)
        or not IsOrdinaryNumber(y)
    then
        return false
    end
    owner:ClearAllPoints()
    owner:SetPoint(point, x, y)
    return true
end

---------------------------------------------------------------------
-- base
---------------------------------------------------------------------
local lines = {}

local function CreateLine(key, color, alpha, x, y, w, h, subLevel)
    lines[key] = lines[key] or AF.CreateTexture(alignmentGrid, nil, AF.GetColorTable(color, alpha), "BACKGROUND", subLevel or 0, nil, nil, "NEAREST")
    AF.SetSize(lines[key], w, h)
    AF.ClearPoints(lines[key])
    AF.SetPoint(lines[key], "CENTER", x, y)
end

-- local function CreateLine2(color, alpha, x1, y1, x2, y2)
--     local l = alignmentGrid:CreateLine(nil, "BACKGROUND")
--     l:SetThickness(1)
--     l:SetColorTexture(AF.GetColorRGB(color, alpha))
--     l:SetStartPoint("BOTTOMLEFT", x1, y1)
--     l:SetEndPoint("BOTTOMLEFT", x2, y2)
--     return l
-- end

local function UpdateLines()
    -- local width, height = GetPhysicalScreenSize()

    local width, height = alignmentGrid:GetSize()
    local halfWidth, halfHeight = width / 2, height / 2

    -- v center
    CreateLine("c_v", "red", 0.75, 0, 0, 1, height, 1)

    -- h center
    CreateLine("c_h", "red", 0.75, 0, 0, width, 1, 1)

    -- vleft
    local n = 0
    local offset = 0
    repeat
        n = n + 1
        offset = offset - 25
        CreateLine("l_" .. n, "gray", 0.35, offset, 0, 1, height)
    until offset < -halfWidth

    -- vright
    n = 0
    offset = 0
    repeat
        n = n + 1
        offset = offset + 25
        CreateLine("r_" .. n, "gray", 0.35, offset, 0, 1, height)
    until offset > halfWidth

    -- hbottom
    n = 0
    offset = 0
    repeat
        n = n + 1
        offset = offset - 25
        CreateLine("b_" .. n, "gray", 0.35, 0, offset, width, 1)
    until offset < -halfHeight

    -- htop
    n = 0
    offset = 0
    repeat
        n = n + 1
        offset = offset + 25
        CreateLine("t_" .. n, "gray", 0.35, 0, offset, width, 1)
    until offset > halfHeight
end

local function CreateAlignmentGrid()
    alignmentGrid = CreateFrame("Frame", "AFAlignmentGrid", moverParent)
    alignmentGrid:SetFrameStrata("BACKGROUND")
    AF.ApplyDefaultBackdrop_NoBorder(alignmentGrid)
    alignmentGrid:SetBackdropColor(AF.GetColorRGB("gray", 0.2))
    alignmentGrid:SetAllPoints()

    -- DISPLAY_SIZE_CHANGED
    -- alignmentGrid:RegisterEvent("DISPLAY_SIZE_CHANGED")
    -- alignmentGrid:SetScript("OnEvent", UpdateLines)
    AF.RegisterCallback("AF_PIXEL_UPDATE", UpdateLines)

    UpdateLines()
end

local function CreateMoverDialog()
    moverDialog = AF.CreateHeaderedFrame(moverParent, "AFMoverDialog", "AF " .. L["Edit Mode"], 300, 180, "FULLSCREEN", nil, true)
    moverDialog:Hide()

    anchorLockedText = AF.CreateFontString(moverDialog, L["Anchor Locked"], "accent", "AF_FONT_OUTLINE")
    anchorLockedText:Hide()
    AF.CreateBlinkAnimation(anchorLockedText)

    -- desc
    local desc = AF.CreateFontString(moverDialog, L["Close this dialog to exit Edit Mode"])
    AF.SetPoint(desc, "TOPLEFT", 10, -10)

    -- tips
    local tips = AF.CreateFontString(moverDialog,
        AF.WrapTextInColor(L["Left Drag"] .. ": ", "accent") .. L["move frames"] .. "\n" ..
        AF.WrapTextInColor(L["Right Click"] .. ": ", "accent") .. L["toggle Position Adjustment dialog"] .. "\n" ..
        "    " .. L["Right Click the Anchor button to lock the anchor"] .. "\n" ..
        AF.WrapTextInColor(L["Mouse Wheel"] .. ": ", "accent") .. L["move frames vertically"] .. "\n" ..
        AF.WrapTextInColor("Shift " .. L["Mouse Wheel"] .. ": ", "accent") .. L["move frames horizontally"] .. "\n" ..
        AF.WrapTextInColor("Shift " .. L["Right Click"] .. ": ", "accent") .. L["hide mover"]
    )
    AF.SetPoint(tips, "TOPLEFT", 10, -35)
    tips:SetJustifyH("LEFT")
    tips:SetSpacing(5)

    -- undo
    local undo = AF.CreateButton(moverDialog, L["Undo"], "accent", 60, 20)
    moverDialog.undo = undo
    AF.SetPoint(undo, "BOTTOMRIGHT", -7, 7)
    undo:SetScript("OnClick", AF.UndoMovers)

    -- dropdown
    local moverGroups = AF.CreateDropdown(moverDialog, 20, 7)
    moverDialog.moverGroups = moverGroups
    AF.SetPoint(moverGroups, "BOTTOMLEFT", 7, 7)
    AF.SetPoint(moverGroups, "RIGHT", undo, "LEFT", -7, 0)
    local items = {}

    -- OnShow
    moverDialog:SetScript("OnShow", function()
        C_Timer.After(0, function()
            AF.SetWidth(moverDialog, AF.Round(max(desc:GetWidth(), tips:GetWidth()) + 40))
        end)
        AF.ClearPoints(moverDialog)
        AF.SetPoint(moverDialog, "BOTTOM", moverParent, "CENTER", 0, 100)

        undo:SetEnabled(false)
        wipe(modified)

        -- groups
        wipe(items)
        for group in pairs(movers) do
            tinsert(items, {
                ["text"] = group,
                ["value"] = group,
                ["onClick"] = function()
                    AF.ShowMovers(group)
                end
            })
        end

        sort(items, function(a, b)
            return a.value < b.value
        end)

        tinsert(items, 1, {
            ["text"] = _G.ALL,
            ["value"] = "all",
            ["onClick"] = function()
                AF.ShowMovers()
            end
        })

        moverGroups:SetItems(items)
        -- moverGroups:SetSelectedValue("all")

        -- update pixels
        AF.UpdatePixelsForRegionAndChildren(moverDialog)
        AF.UpdatePixelsForRegionAndChildren(positionEditorFrame)
    end)

    -- OnHide
    moverDialog:SetScript("OnHide", function()
        AF.HideMovers()
    end)
end

local function HideMoversImmediately()
    if hidingMovers or not moverParent then return false end
    hidingMovers = true

    -- A mover owner may be protected. Combat shutdown must only clear the
    -- addon-owned interaction state; never settle, restore, or save an owner.
    for _, group in pairs(movers) do
        for _, mover in pairs(group) do
            mover:SetScript("OnUpdate", nil)
            mover.isDragging = nil
            mover.moved = nil
            mover._movementOriginal = nil
            mover._original = nil
            mover:Hide()
        end
    end

    if positionEditorFrame then
        positionEditorFrame.owner = nil
        positionEditorFrame:Hide()
    end
    if moverDialog then moverDialog:Hide() end
    moverParent:Hide()

    hidingMovers = false
    return true
end

local function ShowCombatLockdownWarning()
    AF.Print(_G.ERR_AFFECTING_COMBAT)
end

function AF.InitMoverParent()
    if moverParent then return end

    moverParent = CreateFrame("Frame", "AFMoverParent", AF.UIParent)
    moverParent:SetFrameStrata("FULLSCREEN")
    moverParent:SetFrameLevel(MOVER_PARENT_FRAME_LEVEL)
    moverParent:SetAllPoints(AF.UIParent)
    moverParent:Hide()

    -- hide in combat
    moverParent:RegisterEvent("PLAYER_REGEN_DISABLED")
    moverParent:SetScript("OnEvent", function()
        HideMoversImmediately()
    end)

    moverParent:SetScript("OnShow", function()
        moverParent:SetScript("OnShow", nil)
        CreateMoverDialog()
        CreatePositionEditorFrame()
        CreateAlignmentGrid()
    end)
end

---------------------------------------------------------------------
-- calc best point
---------------------------------------------------------------------
---@param owner Frame
---@return string|nil point, number|nil x, number|nil y
function AF.CalcPoint(owner)
    local point, x, y

    if isAnchorLocked then
        point, _, _, x, y = GetOrdinaryPoint(owner)
        if not point then return end
    else
        local scale = GetOrdinaryScale(owner)
        if not scale then return end

        x, y = GetOrdinaryCenter(owner)
        if not x then return end

        local centerX, centerY = GetOrdinaryCenter(AF.UIParent)
        if not centerX then return end

        local width = AF.UIParent:GetRight()
        local parentTop = AF.UIParent:GetTop()
        local ownerTop = owner:GetTop()
        local ownerBottom = owner:GetBottom()
        local ownerRight = owner:GetRight()
        local ownerLeft = owner:GetLeft()
        if not IsOrdinaryNumber(width)
            or not IsOrdinaryNumber(parentTop)
            or not IsOrdinaryNumber(ownerTop)
            or not IsOrdinaryNumber(ownerBottom)
            or not IsOrdinaryNumber(ownerRight)
            or not IsOrdinaryNumber(ownerLeft)
        then
            return
        end

        centerX = centerX / scale
        centerY = centerY / scale
        width = width / scale

        -- local ownerScale = owner:GetEffectiveScale()
        -- local parentScale = AF.UIParent:GetEffectiveScale()
        -- local scaleFactor = parentScale / ownerScale

        if y >= centerY then
            point = "TOP"
            y = -(parentTop / scale - ownerTop)
        else
            point = "BOTTOM"
            y = ownerBottom
        end

        if x >= (width * 2 / 3) then
            point = point .. "RIGHT"
            x = ownerRight - width
        elseif x <= (width / 3) then
            point = point .. "LEFT"
            x = ownerLeft
        else
            x = x - centerX
        end
    end

    x = AF.RoundToDecimal(x, 1)
    y = AF.RoundToDecimal(y, 1)

    return point, x, y
end

local function RePoint(owner, newPoint)
    if not owner or not IsOrdinaryFramePoint(newPoint) then return false end

    local scale = GetOrdinaryScale(owner)
    if not scale then return false end

    local x, y = GetOrdinaryCenter(owner)
    if not x then return false end

    local centerX, centerY = GetOrdinaryCenter(AF.UIParent)
    if not centerX then return false end

    local width = AF.UIParent:GetRight()
    local parentTop = AF.UIParent:GetTop()
    local ownerTop = owner:GetTop()
    local ownerBottom = owner:GetBottom()
    local ownerLeft = owner:GetLeft()
    local ownerRight = owner:GetRight()
    if not IsOrdinaryNumber(width)
        or not IsOrdinaryNumber(parentTop)
        or not IsOrdinaryNumber(ownerTop)
        or not IsOrdinaryNumber(ownerBottom)
        or not IsOrdinaryNumber(ownerLeft)
        or not IsOrdinaryNumber(ownerRight)
    then
        return false
    end

    centerX = centerX / scale
    centerY = centerY / scale
    width = width / scale

    if strfind(newPoint, "^TOP") then
        y = -(parentTop / scale - ownerTop)
    elseif strfind(newPoint, "^BOTTOM") then
        y = ownerBottom
    else
        y = y - centerY
    end

    if strfind(newPoint, "LEFT$") then
        x = ownerLeft
    elseif strfind(newPoint, "RIGHT$") then
        x = ownerRight - width
    else
        x = x - centerX
    end

    if not UpdateAndSave(owner, newPoint, x, y) then return false end
    UpdatePositionEditorFrame(owner)
    return true
end

---------------------------------------------------------------------
-- position editor frame
---------------------------------------------------------------------
CreatePositionEditorFrame = function()
    positionEditorFrame = AF.CreateBorderedFrame(moverParent, "AFPositionEditorFrame", nil, nil, nil, "accent")
    positionEditorFrame:SetFrameLevel(FINE_TUNING_FRAME_LEVEL)
    positionEditorFrame:EnableMouse(true)
    positionEditorFrame:SetClampedToScreen(true)
    AF.SetSize(positionEditorFrame, 218, 91)
    positionEditorFrame:Hide()

    -- title
    positionEditorFrame.tp = AF.CreateTitledPane(positionEditorFrame, "")
    AF.SetPoint(positionEditorFrame.tp, "TOPLEFT", 7, -7)
    AF.SetPoint(positionEditorFrame.tp, "BOTTOMRIGHT", -7, 7)

    -- anchor
    positionEditorFrame.anchor = AF.CreateDropdown(positionEditorFrame.tp, 20, 9, "horizontal", 1)

    local items = {}
    local anchors = {"CENTER", "LEFT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT", "RIGHT", "TOPLEFT", "TOP", "TOPRIGHT"}
    for _, anchor in pairs(anchors) do
        tinsert(items, {
            ["text"] = "",
            ["value"] = anchor,
            ["texture"] = AF.GetIcon("Anchor_" .. anchor),
            ["onClick"] = function()
                if positionEditorFrame.owner then
                    RePoint(positionEditorFrame.owner, anchor)
                end
            end
        })
    end
    positionEditorFrame.anchor:SetItems(items)
    AF.SetPoint(positionEditorFrame.anchor, "TOPLEFT", 0, -30)

    -- lock anchor
    positionEditorFrame.anchor.lock = AF.CreateTexture(positionEditorFrame.anchor.button, AF.GetIcon("SmallLock"), "white", "OVERLAY")
    AF.SetSize(positionEditorFrame.anchor.lock, 20, 20)
    AF.SetPoint(positionEditorFrame.anchor.lock, "CENTER", 2, -2)
    positionEditorFrame.anchor.lock:Hide()
    positionEditorFrame.anchor.button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    positionEditorFrame.anchor.button:HookScript("OnClick", function(self, button)
        if button == "RightButton" then
            isAnchorLocked = not isAnchorLocked
            positionEditorFrame.anchor.lock:SetShown(isAnchorLocked)
            anchorLockedText:SetShown(isAnchorLocked)
        end
    end)

    -- x
    positionEditorFrame.x = AF.CreateEditBox(positionEditorFrame.tp, "", 69, 20)
    AF.SetPoint(positionEditorFrame.x, "LEFT", positionEditorFrame.anchor, "RIGHT", 20, 0)

    local x = AF.CreateFontString(positionEditorFrame.tp, "X", "accent")
    AF.SetPoint(x, "RIGHT", positionEditorFrame.x, "LEFT", -2, 0)

    -- y
    positionEditorFrame.y = AF.CreateEditBox(positionEditorFrame.tp, "", 69, 20)
    AF.SetPoint(positionEditorFrame.y, "BOTTOM", positionEditorFrame.x)
    AF.SetPoint(positionEditorFrame.y, "RIGHT")

    local y = AF.CreateFontString(positionEditorFrame.tp, "Y", "accent")
    AF.SetPoint(y, "RIGHT", positionEditorFrame.y, "LEFT", -2, 0)

    -- edit x
    positionEditorFrame.x:SetOnEditFocusGained(function()
        local value = positionEditorFrame.x:GetNumber()
        positionEditorFrame._x = IsOrdinaryNumber(value) and value or nil
    end)
    positionEditorFrame.x:SetOnEditFocusLost(function()
        if IsOrdinaryNumber(positionEditorFrame._x) then
            positionEditorFrame.x:SetText(positionEditorFrame._x)
        end
    end)
    positionEditorFrame.x:SetOnEnterPressed(function(text)
        if not F.isValueNonSecret(text) then return end
        local v = tonumber(text)
        if IsOrdinaryNumber(v) then
            positionEditorFrame._x = v

            local owner = positionEditorFrame.owner
            if not owner then return end

            local _p, _, _, _, _y = GetOrdinaryPoint(owner)
            local parentRight = AF.UIParent:GetRight()
            local scale = GetOrdinaryScale(owner)
            local ownerWidth = owner:GetWidth()
            if not _p
                or not IsOrdinaryNumber(parentRight)
                or not scale
                or not IsOrdinaryNumber(ownerWidth)
            then
                return
            end

            -- validate
            local mv = parentRight / scale - ownerWidth
            if strfind(_p, "LEFT$") then
                v = AF.Clamp(v, 0, mv)
            elseif strfind(_p, "RIGHT$") then
                v = AF.Clamp(v, -mv, 0)
            else
                v = AF.Clamp(v, -mv / 2, mv / 2)
            end

            if UpdateAndSave(owner, _p, v, _y) then
                AnchorPositionEditorFrame(owner)
            end
        end
    end)

    -- edit y
    positionEditorFrame.y:SetOnEditFocusGained(function()
        local value = positionEditorFrame.y:GetNumber()
        positionEditorFrame._y = IsOrdinaryNumber(value) and value or nil
    end)
    positionEditorFrame.y:SetOnEditFocusLost(function()
        if IsOrdinaryNumber(positionEditorFrame._y) then
            positionEditorFrame.y:SetText(positionEditorFrame._y)
        end
    end)
    positionEditorFrame.y:SetOnEnterPressed(function(text)
        if not F.isValueNonSecret(text) then return end
        local v = tonumber(text)
        if IsOrdinaryNumber(v) then
            positionEditorFrame._y = v

            local owner = positionEditorFrame.owner
            if not owner then return end

            local _p, _, _, _x = GetOrdinaryPoint(owner)
            local parentTop = AF.UIParent:GetTop()
            local scale = GetOrdinaryScale(owner)
            local ownerHeight = owner:GetHeight()
            if not _p
                or not IsOrdinaryNumber(parentTop)
                or not scale
                or not IsOrdinaryNumber(ownerHeight)
            then
                return
            end

            -- validate
            local mv = parentTop / scale - ownerHeight
            if strfind(_p, "^BOTTOM") then
                v = AF.Clamp(v, 0, mv)
            elseif strfind(_p, "^TOP") then
                v = AF.Clamp(v, -mv, 0)
            else
                v = AF.Clamp(v, -mv / 2, mv / 2)
            end

            if UpdateAndSave(owner, _p, _x, v) then
                AnchorPositionEditorFrame(owner)
            end
        end
    end)

    -- scale
    positionEditorFrame.scale = AF.CreateFontString(positionEditorFrame.tp, nil, "darkgray")
    AF.SetPoint(positionEditorFrame.scale, "BOTTOMRIGHT", positionEditorFrame.tp.line, "TOPRIGHT", 0, 2)

    -- undo previous
    positionEditorFrame.undo = AF.CreateButton(positionEditorFrame.tp, L["Undo"], "accent", 17, 17)
    positionEditorFrame.undo:SetEnabled(false)
    AF.SetPoint(positionEditorFrame.undo, "BOTTOMLEFT")
    AF.SetPoint(positionEditorFrame.undo, "BOTTOMRIGHT")
    positionEditorFrame.undo:SetScript("OnClick", function()
        positionEditorFrame.undo:SetEnabled(false)
        local owner = positionEditorFrame.owner
        local original = owner and owner.mover and owner.mover._original
        if original
            and UpdateAndSave(
                owner,
                original[1],
                original[2],
                original[3],
                true
            )
        then
            AnchorPositionEditorFrame(owner)
        end
    end)
end

UpdatePositionEditorFrame = function(owner)
    if not (positionEditorFrame and positionEditorFrame:IsShown()) then return end

    positionEditorFrame.tp:SetTitle(owner.mover.text:GetText())

    local p, _, _, x, y = GetOrdinaryPoint(owner)
    local scale = GetOrdinaryScale(owner)
    if not p or not scale then
        positionEditorFrame.owner = nil
        positionEditorFrame:Hide()
        return false
    end

    x = AF.RoundToDecimal(x, 1)
    y = AF.RoundToDecimal(y, 1)

    positionEditorFrame.x:ClearFocus()
    positionEditorFrame.y:ClearFocus()

    positionEditorFrame.anchor:SetSelectedValue(p)
    AF.CloseDropdown()
    positionEditorFrame.x:SetText(x)
    positionEditorFrame.y:SetText(y)

    positionEditorFrame.scale:SetFormattedText("x%.2f", scale)

    if owner.mover._original and (owner.mover._original[1] ~= p or owner.mover._original[2] ~= x or owner.mover._original[3] ~= y) then
        positionEditorFrame.undo:SetEnabled(true)
    else
        positionEditorFrame.undo:SetEnabled(false)
    end
    return true
end

AnchorPositionEditorFrame = function(owner)
    if not (positionEditorFrame and owner and owner.mover) then return false end

    -- NOTE: mover's parent is AFMoverParent, scale is always 1
    local centerX, centerY = GetOrdinaryCenter(AF.UIParent)
    local width = AF.UIParent:GetRight()
    local x, y = GetOrdinaryCenter(owner.mover)
    if not centerX or not IsOrdinaryNumber(width) or not x then
        positionEditorFrame.owner = nil
        positionEditorFrame:Hide()
        return false
    end

    positionEditorFrame.owner = owner

    local point, relativePoint

    if x >= (width * 2 / 3) then
        point, relativePoint = "RIGHT", "LEFT"
        x, y = -1, 0
    elseif x <= (width / 3) then
        point, relativePoint = "LEFT", "RIGHT"
        x, y = 1, 0
    else
        if y >= centerY then
            point, relativePoint = "TOP", "BOTTOM"
            x, y = 0, -1
        else
            point, relativePoint = "BOTTOM", "TOP"
            x, y = 0, 1
        end
    end

    AF.ClearPoints(positionEditorFrame)
    AF.SetPoint(positionEditorFrame, point, owner.mover, relativePoint, x, y)

    AF.ClearPoints(anchorLockedText)
    if point == "TOP" then
        AF.SetPoint(anchorLockedText, "BOTTOM", owner.mover, "TOP", 0, 1)
    else
        AF.SetPoint(anchorLockedText, "TOP", owner.mover, "BOTTOM", 0, -1)
    end

    if not UpdatePositionEditorFrame(owner) then return false end
    return true
end

local function TogglePositionAdjustmentFrame(owner)
    if positionEditorFrame:IsShown() then
        positionEditorFrame:Hide()
        positionEditorFrame.owner = nil
    else
        positionEditorFrame:Show()
        if not AnchorPositionEditorFrame(owner) then
            positionEditorFrame:Hide()
        end
    end
end

---------------------------------------------------------------------
-- save
---------------------------------------------------------------------
UpdateAndSave = function(owner, p, x, y, isUndo)
    if not owner
        or not owner.mover
        or not IsOrdinaryFramePoint(p)
        or not IsOrdinaryNumber(x)
        or not IsOrdinaryNumber(y)
    then
        return false
    end

    -- update ._points
    owner._useOriginalPoints = true
    owner._points = {}
    owner._points[p] = {p, AF.UIParent, p, x, y}
    AF.RePoint(owner)

    -- save position
    if type(owner.mover.save) == "function" then
        owner.mover.save(p, x, y)
    elseif type(owner.mover.save) == "table" then
        owner.mover.save[1] = p
        owner.mover.save[2] = x
        owner.mover.save[3] = y
    end

    -- update undo button status
    if isUndo then
        modified[owner] = nil
    else
        modified[owner] = true
    end
    if moverDialog and moverDialog.undo then
        if next(modified) then
            moverDialog.undo:SetEnabled(true)
        else
            moverDialog.undo:SetEnabled(false)
        end
    end
    return true
end

---------------------------------------------------------------------
-- stop moving
---------------------------------------------------------------------
local function RestoreMovement(owner)
    local mover = owner.mover
    local original = mover._movementOriginal
    mover._movementOriginal = nil
    if not original then return false end
    return ApplyOwnerPoint(owner, original[1], original[2], original[3])
end

local function StopMoving(owner)
    owner.mover:SetScript("OnUpdate", nil)
    if owner.mover.moved then
        owner.mover.moved = nil

        -- calc new point
        local p, x, y = AF.CalcPoint(owner)
        if p and UpdateAndSave(owner, p, x, y) then
            owner.mover._movementOriginal = nil
            return true
        end
        RestoreMovement(owner)
        return false
    end
    owner.mover._movementOriginal = nil
    return true
end

---------------------------------------------------------------------
-- min.max
---------------------------------------------------------------------
local function GetMinMaxOffsets(owner, point)
    if not point then
        point = GetOrdinaryPoint(owner)
    end
    if not IsOrdinaryFramePoint(point) then return end

    local scale = GetOrdinaryScale(owner)
    if not scale then return end

    local width, height = GetOrdinarySize(AF.UIParent)
    if not width then return end

    local ownerWidth, ownerHeight = GetOrdinarySize(owner)
    if not ownerWidth then return end

    width = width / scale
    height = height / scale

    local minX, maxX, minY, maxY

    if strfind(point, "^BOTTOM") then
        minY = 0
        maxY = height - ownerHeight
    elseif strfind(point, "^TOP") then
        minY = -(height - ownerHeight)
        maxY = 0
    else -- LEFT/RIGHT/CENTER
        minY = -((height - ownerHeight) / 2)
        maxY = (height - ownerHeight) / 2
    end

    if strfind(point, "LEFT$") then
        minX = 0
        maxX = width - ownerWidth
    elseif strfind(point, "RIGHT$") then
        minX = -(width - ownerWidth)
        maxX = 0
    else -- TOP/BOTTOM/CENTER
        minX = -((width - ownerWidth) / 2)
        maxX = (width - ownerWidth) / 2
    end

    return minX, maxX, minY, maxY
end

local function CaptureOriginal(mover)
    if mover._original then return true end
    local point, x, y = GetOrdinaryPositionLedger(mover.owner)
    if not point then return false end
    mover._original = {
        point,
        AF.RoundToDecimal(x, 1),
        AF.RoundToDecimal(y, 1),
    }
    return true
end

---------------------------------------------------------------------
-- create mover
---------------------------------------------------------------------
---@param save function|table
function AF.CreateMover(owner, group, text, save)
    -- assert(owner:GetNumPoints() == 1, "mover owner must have 1 anchor point")
    -- assert(owner:GetParent() == AF.UIParent, "owner must be the direct child of AF.UIParent")
    -- NOTE:
    -- owner must be the direct child of AF.UIParent
    -- or
    -- its parent must SetAllPoints(AF.UIParent)

    local mover = AF.CreateBorderedFrame(moverParent)
    mover:SetBackdropColor(AF.GetColorRGB("background", 0.8))
    mover.accentColor = AF.GetAddonAccentColorName()
    mover:SetBackdropBorderColor(AF.GetColorRGB(mover.accentColor))

    owner.mover = mover
    mover.owner = owner
    mover.save = save

    if not movers[group] then movers[group] = {} end
    tinsert(movers[group], mover)

    mover:SetAllPoints(owner)
    mover:SetFrameLevel(MOVER_PARENT_FRAME_LEVEL)
    mover:EnableMouse(true)
    mover:Hide()

    mover.text = AF.CreateFontString(mover, text, mover.accentColor, "AF_FONT_OUTLINE", "OVERLAY")
    mover.text:SetPoint("CENTER")
    mover.text:SetText(text)

    mover:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        if InCombatLockdown() then
            HideMoversImmediately()
            return
        end

        local mouseX, mouseY = GetCursorPosition()
        if not IsOrdinaryNumber(mouseX) or not IsOrdinaryNumber(mouseY) then return end

        local lastX, lastY = mouseX, mouseY

        local effectiveScale = GetOrdinaryScale(owner, true)
        local point, _, _, startX, startY = GetOrdinaryPoint(owner)
        if not effectiveScale or not point then return end

        local minX, maxX, minY, maxY = GetMinMaxOffsets(owner, point)
        if not minX then return end

        mover.isDragging = true
        mover._movementOriginal = {point, startX, startY}

        mover:SetScript("OnUpdate", function()
            if InCombatLockdown() then
                HideMoversImmediately()
                return
            end

            local newMouseX, newMouseY = GetCursorPosition()
            if not IsOrdinaryNumber(newMouseX)
                or not IsOrdinaryNumber(newMouseY)
            then
                mover:SetScript("OnUpdate", nil)
                mover.isDragging = nil
                if mover.moved then
                    mover.moved = nil
                    RestoreMovement(owner)
                else
                    mover._movementOriginal = nil
                end
                UpdatePositionEditorFrame(owner)
                return
            end
            if newMouseX == lastX and newMouseY == lastY then return end

            lastX = newMouseX
            lastY = newMouseY

            local newX = startX + (newMouseX - mouseX) / effectiveScale
            newX = AF.Clamp(newX, minX, maxX)

            local newY = startY + (newMouseY - mouseY) / effectiveScale
            newY = AF.Clamp(newY, minY, maxY)

            -- print(newX, newY)
            if not ApplyOwnerPoint(owner, point, newX, newY) then
                mover:SetScript("OnUpdate", nil)
                mover.isDragging = nil
                mover.moved = nil
                RestoreMovement(owner)
                return
            end
            mover.moved = true

            AnchorPositionEditorFrame(owner)
        end)
    end)

    mover:SetScript("OnMouseUp", function(self, button)
        if InCombatLockdown() then
            HideMoversImmediately()
            return
        end

        if button == "RightButton" then
            if IsShiftKeyDown() then -- hide mover
                if positionEditorFrame and positionEditorFrame.owner == owner and positionEditorFrame:IsShown() then
                    positionEditorFrame.owner = nil
                    positionEditorFrame:Hide()
                end
                mover:Hide()
                mover.text:SetColor("accent")
            else
                TogglePositionAdjustmentFrame(owner)
            end
        end

        if button ~= "LeftButton" then return end
        mover.isDragging = nil
        StopMoving(owner)

        -- update
        UpdatePositionEditorFrame(owner)
    end)

    mover:SetScript("OnMouseWheel", function(self, delta)
        if InCombatLockdown() then
            HideMoversImmediately()
            return
        end
        if mover.isDragging then return end
        if not IsOrdinaryNumber(delta) then return end

        local point, _, _, startX, startY = GetOrdinaryPoint(owner)
        if not point then return end

        startX = AF.RoundToDecimal(startX, 1)
        startY = AF.RoundToDecimal(startY, 1)

        local minX, maxX, minY, maxY = GetMinMaxOffsets(owner, point)
        if not minX then return end

        local newX, newY = startX, startY

        if delta == 1 then
            if IsShiftKeyDown() then
                -- move right
                newX = AF.Clamp(startX + 1, minX, maxX)
            else
                -- move up
                newY = AF.Clamp(startY + 1, minY, maxY)
            end
        else
            if IsShiftKeyDown() then
                -- move left
                newX = AF.Clamp(startX - 1, minX, maxX)
            else
                -- move down
                newY = AF.Clamp(startY - 1, minY, maxY)
            end
        end

        mover._movementOriginal = {point, startX, startY}
        if not ApplyOwnerPoint(owner, point, newX, newY) then
            mover._movementOriginal = nil
            return
        end
        mover.moved = true
        StopMoving(owner)

        -- update
        UpdatePositionEditorFrame(owner)
    end)

    mover:SetScript("OnEnter", function()
        for _, g in pairs(movers) do
            for _, m in pairs(g) do
                if m == mover then
                    m.text:SetColor("white")
                    m:SetFrameLevel(MOVER_ON_TOP_FRAME_LEVEL)
                    AF.FrameFadeIn(m, 0.25)
                elseif m:IsShown() then
                    m.text:SetColor(m.accentColor)
                    m:SetFrameLevel(MOVER_PARENT_FRAME_LEVEL)
                    AF.FrameFadeOut(m, 0.25, nil, 0.5)
                end
            end
        end

        AnchorPositionEditorFrame(owner)
    end)

    mover:SetScript("onLeave", function()
        for _, g in pairs(movers) do
            for _, m in pairs(g) do
                if m:IsShown() then
                    m.text:SetColor(m.accentColor)
                    m:SetFrameLevel(MOVER_PARENT_FRAME_LEVEL)
                    AF.FrameFadeIn(m, 0.25)
                end
            end
        end
    end)

end

---@param save function|table
function AF.UpdateMoverSave(owner, save)
    assert(owner.mover, string.format("no mover for %s", owner:GetName() or "owner"))
    owner.mover.save = save
end

---------------------------------------------------------------------
-- toggle movers
---------------------------------------------------------------------
function AF.ShowMovers(group)
    if InCombatLockdown() then
        HideMoversImmediately()
        ShowCombatLockdownWarning()
        return false
    end

    for g, gt in pairs(movers) do
        local show
        if not group then
            show = true
        else
            show = group == g
        end
        for _, m in pairs(gt) do
            if show
                and (type(m.owner.enabled) ~= "boolean" or m.owner.enabled)
                and CaptureOriginal(m)
            then
                m:Show()
            else
                m:Hide()
            end
        end
    end
    moverParent:Show()
    moverDialog:Show()
    moverDialog.moverGroups:SetSelectedValue(group or "all")
    if positionEditorFrame then positionEditorFrame:Hide() end
    return true
end

function AF.HideMovers()
    return HideMoversImmediately()
end

function AF.ToggleMovers()
    if InCombatLockdown() then
        HideMoversImmediately()
        ShowCombatLockdownWarning()
        return false
    end
    if not (moverParent and moverParent:IsShown()) then
        return AF.ShowMovers()
    end
    return AF.HideMovers()
end

function AF.UndoMovers()
    if InCombatLockdown() then return end
    if not moverParent:IsShown() then return end

    for _, g in pairs(movers) do
        for _, m in pairs(g) do
            if m._original then
                UpdateAndSave(
                    m.owner,
                    m._original[1],
                    m._original[2],
                    m._original[3],
                    true
                )
            end
        end
    end
    if positionEditorFrame then positionEditorFrame:Hide() end
end
