---@class AbstractFramework
local AF = select(2, ...)

local suppressedNamePlates = setmetatable({}, {__mode = "k"})
local hookedCenterStatusUpdate

local function EnforceNativeNamePlateSuppression(unitFrame)
    if suppressedNamePlates[unitFrame] then
        unitFrame:SetAlpha(0)
    end
end

local function EnsureCenterStatusHook()
    if hookedCenterStatusUpdate or not CompactUnitFrame_UpdateCenterStatusIcon then
        return
    end

    hookedCenterStatusUpdate = true
    hooksecurefunc(
        "CompactUnitFrame_UpdateCenterStatusIcon",
        EnforceNativeNamePlateSuppression
    )
end

local function PreserveNativeOverlay(state, overlay)
    if not overlay then return end

    state.nativeOverlays = state.nativeOverlays or {}
    state.nativeOverlays[#state.nativeOverlays + 1] = {
        frame = overlay,
        ignoresParentAlpha = overlay:IsIgnoringParentAlpha(),
    }
    overlay:SetIgnoreParentAlpha(true)
end

---Suppresses only a native nameplate UnitFrame's presentation. The native
---controller stays shown, registered, parented, and clickable. Native overlays
---that custom nameplates cannot safely reproduce ignore the native frame's
---alpha so encounter/quest widgets, raid markers, soft-target icons, and the
---behind-camera indicator remain visible; selectionHighlight is made to
---inherit the suppressed alpha.
---
---Saved alpha values remain opaque: Retail 12.0.7 (wow-ui-source 4383ced) and
---12.1 (d3915c7) document GetAlpha as potentially secret and SetAlpha as
---accepting tainted secret arguments. No saved value is inspected or compared.
---@param unitFrame Frame
---@param suppressed boolean
function AF.SetNativeNamePlateVisualSuppressed(unitFrame, suppressed)
    if not unitFrame or unitFrame:IsForbidden() then return end

    if suppressed then
        if suppressedNamePlates[unitFrame] then
            EnforceNativeNamePlateSuppression(unitFrame)
            return
        end

        local widgetContainer = unitFrame.WidgetContainer
        local raidTargetFrame = unitFrame.RaidTargetFrame
        local softTargetFrame = unitFrame.SoftTargetFrame
        local behindCameraIcon = unitFrame.behindCameraIcon
        local selectionHighlight = unitFrame.selectionHighlight
        local state = {
            alpha = unitFrame:GetAlpha(),
            selectionHighlight = selectionHighlight,
        }

        PreserveNativeOverlay(state, widgetContainer)
        PreserveNativeOverlay(state, raidTargetFrame)
        PreserveNativeOverlay(state, softTargetFrame)
        PreserveNativeOverlay(state, behindCameraIcon)

        if selectionHighlight then
            state.selectionIgnoresParentAlpha =
                selectionHighlight:IsIgnoringParentAlpha()
            selectionHighlight:SetIgnoreParentAlpha(false)
        end

        suppressedNamePlates[unitFrame] = state
        EnsureCenterStatusHook()
        EnforceNativeNamePlateSuppression(unitFrame)
        return
    end

    local state = suppressedNamePlates[unitFrame]
    if not state then return end

    suppressedNamePlates[unitFrame] = nil
    unitFrame:SetAlpha(state.alpha)

    if state.nativeOverlays then
        for _, overlay in ipairs(state.nativeOverlays) do
            overlay.frame:SetIgnoreParentAlpha(
                overlay.ignoresParentAlpha
            )
        end
    end

    if state.selectionHighlight then
        state.selectionHighlight:SetIgnoreParentAlpha(
            state.selectionIgnoresParentAlpha
        )
    end
end

function AF.RestoreAllNativeNamePlateVisuals()
    for unitFrame in next, suppressedNamePlates do
        AF.SetNativeNamePlateVisualSuppressed(unitFrame, false)
    end
end
