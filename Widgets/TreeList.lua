---@class AbstractFramework
local AF = select(2, ...)

local max = math.max
local min = math.min
local type = type
local ipairs = ipairs
local pairs = pairs

---------------------------------------------------------------------
-- shared constants
---------------------------------------------------------------------
local DEFAULT_EXPANDED_WIDTH = 170
-- 48px is the compact content lane: 12px inset + 20px icon + 14px chevron
-- + 2px gap. The same 12px inset clears the 7px orange hover strip in both
-- presentations. Reserve a separate 10px lane for the transient scrollbar, so
-- parent chevrons remain fully visible and clickable while the list scrolls.
local DEFAULT_COLLAPSED_WIDTH = 58
local DEFAULT_ROW_HEIGHT = 28
local DEFAULT_HEADING_HEIGHT = 22
local DEFAULT_ICON_SIZE = 20
local DEFAULT_CONTENT_GAP = 8

local ROW_SPACING = 2
local HEADING_TOP_GAP = 4
local TOGGLE_SIZE = 18
-- The 7px hover navigation strip starts at the row's left edge. Keep the
-- expanded icon plate four pixels beyond it so the orange gradient never
-- visually runs into the plate's border.
local EXPANDED_ROW_LEFT_INSET = 12
-- Like EXPANDED_ROW_LEFT_INSET, keep compact plates past the 7px navigation
-- strip. This needs a 48px content lane once the compact parent chevron is
-- included (12 + 20 + 14 + 2).
local COMPACT_ICON_INSET = 12
-- Gap between a compact parent chevron and the dedicated scrollbar lane.
local COMPACT_TOGGLE_INSET = 2
-- Compact parent content: leftInset(12) + plate(20) + chevron(14) + gap(2)
-- = 48px, followed by the dedicated 10px scrollbar lane above. The chevron
-- shrinks from the expanded TOGGLE_SIZE (18) to 14 only while compact; the
-- same pooled row's toggle is resized back to TOGGLE_SIZE on expansion.
local COMPACT_TOGGLE_SIZE = 14
local ROW_ICON_ALPHA = 1
local INDENT_PER_DEPTH = 22
local SCROLLBAR_WIDTH = 10
local SCROLLBAR_THUMB_MIN_HEIGHT = 20
local SCROLLBAR_FADE_DELAY = 0.9
local SCROLLBAR_FADE_DURATION = 0.18

-- reserved space at the right edge of every row so content never sits under
-- the transient scroll bar
local ROW_RIGHT_INSET = SCROLLBAR_WIDTH + 4

local function GetMinimumCollapsedWidth(iconSize)
    return COMPACT_ICON_INSET + iconSize + COMPACT_TOGGLE_SIZE
        + COMPACT_TOGGLE_INSET + SCROLLBAR_WIDTH
end

-- AF.AnimatedResize tracks its ticker on the frame; cancel it so a pending
-- animation never keeps writing sizes after state has been reapplied
local function StopResize(region)
    if not region or not region._animatedResizeTimer then return end
    region._animatedResizeTimer:Cancel()
    region._animatedResizeTimer = nil
end

---------------------------------------------------------------------
-- transient scroll bar
---------------------------------------------------------------------
---@class AF_TransientScrollBar
---@field frame Slider the scroll bar frame
---@field thumb Texture the thumb texture
---@field track Texture the track texture

-- Attaches a template-free, fade-in/out vertical scroll bar to the right edge
-- of "host", driving "scrollFrame" (whose scroll child is "scrollContent").
-- The bar only participates when the scroll range is greater than zero, and
-- its mouse input is disabled whenever it is faded out so an invisible bar
-- never intercepts clicks.
---@param host Frame frame the bar anchors to (right edge)
---@param scrollFrame ScrollFrame
---@param scrollContent Frame scroll child of scrollFrame
---@param options? table
--- - width number (default 10)
--- - thumbMinHeight number (default 20)
--- - fadeDelay number seconds of inactivity before fading out (default 0.9)
--- - scrollStep number offset per wheel notch (default (28 + 2) * 3)
--- - accentColor string color name (default AF.GetAddonAccentColorName())
---@return AF_TransientScrollBar controller with SetScroll, Update, Reveal, ScheduleFadeOut, IsDragging, SetOnPointerEnter, SetOnPointerLeave
function AF.AttachTransientScrollBar(host, scrollFrame, scrollContent, options)
    options = options or {}
    local barWidth = options.width or SCROLLBAR_WIDTH
    local thumbMinHeight = options.thumbMinHeight or SCROLLBAR_THUMB_MIN_HEIGHT
    local fadeDelay = options.fadeDelay or SCROLLBAR_FADE_DELAY
    local scrollStep = options.scrollStep or (DEFAULT_ROW_HEIGHT + ROW_SPACING) * 3
    local accentColor = options.accentColor or AF.GetAddonAccentColorName()

    local controller = {}
    local needed = false
    local setting, dragging
    local fadeGeneration = 0
    local onPointerEnter, onPointerLeave

    local scrollBar = CreateFrame("Slider", nil, host)
    controller.frame = scrollBar
    scrollBar:SetPoint("TOPRIGHT", host, "TOPRIGHT")
    scrollBar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT")
    AF.SetWidth(scrollBar, barWidth)
    AF.SetFrameLevel(scrollBar, 10, scrollContent)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:EnableMouseWheel(true)
    scrollBar:SetValueStep(1)
    scrollBar:SetObeyStepOnDrag(false)
    scrollBar:SetMinMaxValues(0, 0)

    local track = scrollBar:CreateTexture(nil, "BACKGROUND")
    controller.track = track
    track:SetPoint("TOP", 0, -2)
    track:SetPoint("BOTTOM", 0, 2)
    AF.SetWidth(track, 2)
    track:SetColorTexture(AF.GetColorRGB("border", 0.45))

    local thumb = scrollBar:CreateTexture(nil, "ARTWORK")
    controller.thumb = thumb
    AF.SetSize(thumb, 5, thumbMinHeight)
    thumb:SetColorTexture(AF.GetColorRGB(accentColor, 0.9))
    scrollBar:SetThumbTexture(thumb)

    AF.CreateFadeInOutAnimation(scrollBar, SCROLLBAR_FADE_DURATION)
    scrollBar:SetAlpha(0)
    scrollBar:EnableMouse(false)
    scrollBar:Hide()

    local function GetRange()
        return max(0, scrollContent:GetHeight() - scrollFrame:GetHeight())
    end

    local function SyncValue(offset)
        if setting then return end
        setting = true
        scrollBar:SetValue(offset)
        setting = nil
    end

    local function SetScroll(offset)
        local range = GetRange()
        if offset < 0 then
            offset = 0
        elseif offset > range then
            offset = range
        end
        scrollFrame:SetVerticalScroll(offset)
        SyncValue(offset)
    end

    local function UpdateGeometry()
        local range = GetRange()
        scrollBar:SetMinMaxValues(0, range)

        local trackHeight = scrollBar:GetHeight()
        if range > 0 and trackHeight > 0 then
            local viewportHeight = scrollFrame:GetHeight()
            local thumbHeight = max(
                thumbMinHeight,
                trackHeight * (viewportHeight / (viewportHeight + range))
            )
            AF.SetHeight(thumb, min(trackHeight, thumbHeight))
        end
        return range
    end

    local function HideBar(immediate)
        fadeGeneration = fadeGeneration + 1
        scrollBar:EnableMouse(false)
        if immediate or not scrollBar:IsShown() then
            scrollBar:HideNow()
        else
            scrollBar:FadeOut()
        end
    end

    local function ScheduleFadeOut()
        if not needed then return end

        -- generation counter: any later Reveal/HideBar/ScheduleFadeOut
        -- invalidates callbacks already in flight
        fadeGeneration = fadeGeneration + 1
        local generation = fadeGeneration
        C_Timer.After(fadeDelay, function()
            if generation ~= fadeGeneration
                or not needed
                or dragging
                or scrollBar:IsMouseOver() then
                return
            end
            HideBar(false)
        end)
    end

    local function Reveal(scheduleFade)
        if not needed then return end

        fadeGeneration = fadeGeneration + 1
        scrollBar:EnableMouse(true)
        if not scrollBar:IsShown()
            or scrollBar:GetAlpha() < 1
            or scrollBar.fadeOut:IsPlaying() then
            scrollBar:FadeIn()
        end
        if scheduleFade ~= false then
            ScheduleFadeOut()
        end
    end

    local function Update()
        local range = UpdateGeometry()
        SetScroll(scrollFrame:GetVerticalScroll())

        local nowNeeded = range > 0
        local changed = nowNeeded ~= needed
        needed = nowNeeded
        if not needed then
            HideBar(false)
        elseif changed then
            Reveal()
        end
    end

    local function ScrollByWheel(delta)
        Reveal()
        SetScroll(scrollFrame:GetVerticalScroll() - (delta * scrollStep))
    end

    local function SetDragging(isDragging)
        if isDragging then
            dragging = true
            Reveal(false)
        elseif dragging then
            dragging = nil
            ScheduleFadeOut()
        end
    end

    scrollBar:SetScript("OnValueChanged", function(_, value)
        if not setting then
            Reveal(not dragging)
            SetScroll(value)
        end
    end)
    scrollBar:SetScript("OnMouseDown", function()
        SetDragging(true)
        if onPointerEnter then onPointerEnter() end
    end)
    scrollBar:SetScript("OnMouseUp", function()
        SetDragging(false)
        if onPointerLeave then onPointerLeave() end
    end)
    scrollBar:SetScript("OnEnter", function()
        Reveal(false)
        if onPointerEnter then onPointerEnter() end
    end)
    scrollBar:SetScript("OnLeave", function()
        if onPointerLeave then onPointerLeave() end
    end)
    scrollBar:SetScript("OnMouseWheel", function(_, delta)
        ScrollByWheel(delta)
    end)
    scrollBar:SetScript("OnHide", function()
        -- fires for host-driven hides too: reset so the bar comes back clean
        local wasDragging = dragging
        dragging = nil
        fadeGeneration = fadeGeneration + 1
        scrollBar:EnableMouse(false)
        scrollBar:SetAlpha(0)
        if wasDragging and onPointerLeave then
            onPointerLeave()
        end
    end)

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        ScrollByWheel(delta)
    end)

    ---@param offset number clamped to [0, range]
    function controller:SetScroll(offset)
        SetScroll(offset)
    end

    -- re-clamps the current offset, refreshes thumb geometry and neededness
    function controller:Update()
        Update()
    end

    ---@param scheduleFade? boolean pass false to keep the bar open
    function controller:Reveal(scheduleFade)
        Reveal(scheduleFade)
    end

    function controller:ScheduleFadeOut()
        ScheduleFadeOut()
    end

    ---@return boolean dragging
    function controller:IsDragging()
        return dragging == true
    end

    ---@param callback? function invoked when the pointer engages the bar
    function controller:SetOnPointerEnter(callback)
        onPointerEnter = callback
    end

    ---@param callback? function invoked when the pointer disengages the bar
    function controller:SetOnPointerLeave(callback)
        onPointerLeave = callback
    end

    return controller
end

---------------------------------------------------------------------
-- tree list
---------------------------------------------------------------------
-- Expansion-persistence contract (owner requirement -- do not regress):
-- * expandedById is the single authority for branch expansion in BOTH the
--   compact (icon-only) and expanded presentations. BuildVisibleEntries
--   always honors it; there is no presentation-level gate on nested entries.
-- * ToggleExpanded is a plain negation of expandedById[id]; there are no
--   presentation-dependent special cases.
-- * Switching presentations (SetCompact) never writes to expandedById:
--   collapsing a sidebar rail to its compact strip keeps every expanded nest
--   expanded (rendered icon-only), and re-expanding restores it visually.
-- * Because the visible entry list is identical in both presentations, one
--   scroll offset (the scroll frame's vertical scroll) is shared across
--   presentation flips; there is no per-presentation offset bookkeeping.
-- * expandedById persists across SetModel calls, so expansion is retained
--   for parents that are temporarily absent from the model.

---@class AF_TreeList:AF_Frame
local AF_TreeListMixin = {}

local function NotifyPointerEnter(list)
    if list.onPointerEnter then
        list.onPointerEnter()
    end
end

local function NotifyPointerLeave(list)
    if list.onPointerLeave then
        list.onPointerLeave()
    end
end

local function SetNavigationState(list, row, state, immediate)
    if row.navigationState == state then return end
    row.navigationState = state

    local highlight = row.highlight
    local targetWidth = state == "selected" and list.expandedWidth
        or state == "hover" and 7
        or 1
    local shouldShow = state ~= "idle"

    if immediate then
        StopResize(highlight)
        AF.SetWidth(highlight, targetWidth)
        highlight:SetShown(shouldShow)
        return
    end

    if not shouldShow and not highlight:IsShown() then
        AF.SetWidth(highlight, 1)
        return
    end

    AF.AnimatedResize(
        highlight,
        targetWidth,
        nil,
        nil,
        nil,
        shouldShow and function()
            highlight:Show()
        end or nil,
        not shouldShow and function()
            if row.navigationState == "idle" then
                highlight:Hide()
            end
        end or nil
    )
end

local function IsSelectedRow(list, row)
    if row.id == list.selectionId then return true end
    -- an expanded parent never claims the highlight on behalf of a selected
    -- descendant: the descendant row is visible and shows it itself
    if list.expandedById[row.id] then return false end

    local selected = list.entriesById[list.selectionId]
    while selected and selected.parentId do
        if selected.parentId == row.id then
            return true
        end
        selected = list.entriesById[selected.parentId]
    end
    return false
end

local function PaintRow(list, row, immediate)
    if row.kind == "heading" then
        row.label:SetTextColor(0.62, 0.62, 0.62, 1)
        SetNavigationState(list, row, "idle", true)
    else
        row.label:SetColor("white")
        local state = IsSelectedRow(list, row) and "selected"
            or row.hovered and "hover"
            or "idle"
        SetNavigationState(list, row, state, immediate)
    end
end

local function BuildVisibleEntries(list)
    local flattened = {}
    local expandedById = list.expandedById

    local function Append(entries)
        for _, entry in ipairs(entries) do
            flattened[#flattened + 1] = entry
            -- expandedById is authoritative in every presentation
            -- (see the expansion-persistence contract above)
            if entry.hasChildren and expandedById[entry.id] then
                Append(entry.children)
            end
        end
    end
    Append(list.model)

    list.visibleEntries = flattened
end

function AF_TreeListMixin:EnsureSelectedRowVisible()
    if self.selectionId == nil then return end

    local scrollFrame = self.scrollFrame
    local offset = scrollFrame:GetVerticalScroll()
    local bottom = offset + scrollFrame:GetHeight()
    for _, row in ipairs(self.activeRows) do
        if IsSelectedRow(self, row) then
            if row.layoutTop < offset then
                self.scrollBar:SetScroll(row.layoutTop)
            elseif row.layoutBottom > bottom then
                self.scrollBar:SetScroll(row.layoutBottom - scrollFrame:GetHeight())
            end
            return
        end
    end
end

local function SelectFromClick(row)
    local list = row.list
    if row.kind == "heading" or list.modelAnimation then return end

    local id = row.id
    local entry = row.entry
    local hasChildren = entry and entry.hasChildren
    if id ~= list.selectionId then
        list.selectionId = id
        for _, activeRow in ipairs(list.activeRows) do
            PaintRow(list, activeRow)
        end
        list:EnsureSelectedRowVisible()

        if list.onSelected then
            list.onSelected(id, entry)
        end
    end

    if hasChildren then
        list:ToggleExpanded(id)
    end
end

local function SetRowHovered(row, hovered)
    row.hovered = hovered or nil
    PaintRow(row.list, row)
end

local function HideRowTooltip(row)
    local list = row.list
    if list.tooltipOwner ~= row then return end

    list.tooltipOwner = nil
    -- The row's leave is deferred so moving onto its chevron does not flicker.
    -- Do not let that deferred cleanup hide a newer tooltip owned by another
    -- AF widget.
    if AF.Tooltip and AF.Tooltip:GetOwner() == row.tooltipAnchor then
        AF.HideTooltip()
    end
end

-- The tooltip owner must remain outside the scroll frame, otherwise the
-- GameTooltip it owns is clipped with the rows. In compact mode, however,
-- the owner should follow the visible control instead of the rail's far
-- edge. The row body follows its icon; the chevron gets its own target when
-- it is the current hover source. That keeps the title next to what the
-- pointer is actually over while preserving the non-clipping owner
-- relationship.
local function PositionRowTooltipAnchor(list, row, compact, hoverTarget)
    row.tooltipAnchor:ClearAllPoints()

    if compact then
        local target
        local hoverOnToggle = hoverTarget == row.toggle
            or hoverTarget == nil
                and row.toggle:IsShown()
                and row.toggle:IsMouseOver()
        if hoverOnToggle and row.toggle:IsShown() then
            target = row.toggle
        elseif row.iconPlate:IsShown() then
            target = row.iconPlate
        elseif row.toggle:IsShown() then
            target = row.toggle
        end
        if target then
            row.tooltipAnchor:SetPoint("LEFT", target, "RIGHT", 0, 0)
            return
        end
    end

    -- Headings and icon-less compact entries do not have a visible control to
    -- follow. They never normally show a row tooltip, but retain a stable
    -- visible-edge fallback for pooled-row safety.
    row.tooltipAnchor:SetPoint(
        "LEFT",
        row,
        "LEFT",
        compact and list.collapsedWidth or list.expandedWidth,
        0
    )
end

local function ShowRowTooltip(row, hoverTarget)
    local entry = row.entry
    if not entry or row.kind == "heading" then return end

    local list = row.list
    PositionRowTooltipAnchor(list, row, list.compact, hoverTarget)
    row.tooltipLines[1] = entry.label
    list.tooltipOwner = row
    AF.ShowTooltip(row.tooltipAnchor, "RIGHT", 4, 0, row.tooltipLines)
end

local function RefreshRowHover(row)
    C_Timer.After(0, function()
        if not row.entry then
            HideRowTooltip(row)
            return
        end
        local hovered = row:IsMouseOver()
            or row.toggle:IsShown() and row.toggle:IsMouseOver()
        SetRowHovered(row, hovered)
        if not hovered then
            HideRowTooltip(row)
        end
    end)
end

local function CreateRow(list)
    local row = CreateFrame("Button", nil, list.scrollContent)
    row.list = list
    row.tooltipLines = {}
    -- Rows retain expandedWidth even in the compact rail and are clipped by
    -- the scroll frame. The anchor itself must live on the tree list rather
    -- than the row: AF.Tooltip:SetOwner reparents the GameTooltip to its
    -- owner, and a row descendant would clip that tooltip inside scrollFrame.
    -- PositionRowTooltipAnchor keeps this non-scrolling owner aligned with
    -- the row's visible compact icon or chevron.
    row.tooltipAnchor = CreateFrame("Frame", nil, list)
    row.tooltipAnchor.accentColor = list.accentColor
    AF.SetSize(row.tooltipAnchor, 1, 1)
    row:RegisterForClicks("LeftButtonUp")

    row.highlight = AF.CreateGradientTexture(
        row,
        "HORIZONTAL",
        AF.GetColorTable(list.accentColor, 0.9),
        AF.GetColorTable(list.accentColor, 0),
        nil,
        "BORDER"
    )
    row.highlight:SetPoint("TOPLEFT")
    row.highlight:SetPoint("BOTTOMLEFT")
    AF.SetWidth(row.highlight, 1)
    row.highlight:Hide()

    -- one plate per pooled row, created once here and reused for every
    -- ApplyEntry call on this row -- never recreated per render. Uses AF's
    -- sanctioned lightweight-bordered-frame constructor (same one-fill/
    -- four-edge backdrop the bag icons use, deliberately avoiding the
    -- nine-region template-driven backdrop path) so the plate is registered
    -- with the pixel updater AFTER the backdrop exists and its UpdatePixels
    -- chains AF.UpdateLightweightBackdropPixels -- a plain AF.CreateFrame +
    -- AF.ApplyLightweightBackdropWithColors would register before the
    -- backdrop exists and never get its pixels re-laid-out on a UI-scale
    -- change.
    local plateColors = list.iconPlateColors
    row.iconPlate = AF.CreateLightweightBorderedFrame(
        row,
        nil,
        list.iconSize,
        list.iconSize,
        plateColors and plateColors.fill,
        plateColors and plateColors.border
    )

    row.icon = row.iconPlate:CreateTexture(nil, "ARTWORK")
    AF.SetInside(row.icon, row.iconPlate, 1)
    row.icon:SetVertexColor(1, 1, 1, ROW_ICON_ALPHA)

    row.label = AF.CreateFontString(row, nil, "white")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row.toggle = CreateFrame("Button", nil, row)
    row.toggle.row = row
    AF.SetSize(row.toggle, TOGGLE_SIZE, TOGGLE_SIZE)
    row.toggle:SetPoint("RIGHT", -(SCROLLBAR_WIDTH + 2), 0)
    row.toggle:RegisterForClicks("LeftButtonUp")

    row.toggle.icon = row.toggle:CreateTexture(nil, "ARTWORK")
    row.toggle.icon:SetAllPoints()
    row.toggle.icon:SetVertexColor(1, 1, 1, 0.62)

    row:SetScript("OnClick", SelectFromClick)
    row:SetScript("OnEnter", function(self)
        SetRowHovered(self, true)
        ShowRowTooltip(self, self)
        NotifyPointerEnter(list)
    end)
    row:SetScript("OnLeave", function(self)
        RefreshRowHover(self)
        NotifyPointerLeave(list)
    end)
    row.toggle:SetScript("OnClick", function(self)
        list:ToggleExpanded(self.row.id)
    end)
    row.toggle:SetScript("OnEnter", function(self)
        SetRowHovered(self.row, true)
        ShowRowTooltip(self.row, self)
        NotifyPointerEnter(list)
    end)
    row.toggle:SetScript("OnLeave", function(self)
        RefreshRowHover(self.row)
        NotifyPointerLeave(list)
    end)

    list.rows[#list.rows + 1] = row
    return row
end

-- rows live in an index-addressed cache instead of an unordered object pool:
-- the expand/collapse animation acquires extra rows past the active range and
-- the next ApplyModel reclaims them by index, which a Release/Acquire pool
-- cannot express without leaking actives
local function AcquireRow(list, index)
    return list.rows[index] or CreateRow(list)
end

local function ResetRowForEntry(row, entry)
    if row.id == entry.id and row.kind == entry.kind then return end
    StopResize(row.highlight)
    row.navigationState = nil
    AF.SetWidth(row.highlight, 1)
    row.highlight:Hide()
end

-- Dispatches a row's icon region (row.icon, seated on its row.iconPlate) to
-- one of three shapes:
--   string            -> AF.SetAdaptiveIcon (existing adaptive-icon lookup)
--   {atlas = name}     -> iconRegion:SetAtlas(name)
--   {texture = id}     -> iconRegion:SetTexture(id)
-- Every icon renders full-color on its plate -- no desaturate/tint
-- treatment. texture-shape icons get the standard Blizzard icon crop
-- (AF.ApplyDefaultTexCoord, 0.08-0.92) so their rounded stock corners are
-- clipped by the square plate; atlas-shape icons are never texcoord-cropped,
-- since SetAtlas already defines both the atlas page texture and the
-- sub-region UVs it needs -- cropping afterward would stretch the whole
-- sprite sheet across the icon. The string (glyph/adaptive) path always
-- resets to full texcoords (0, 1, 0, 1) so a pooled row previously showing
-- a cropped texture or an atlas sub-region comes back to a clean
-- full-texture UV rect when reused for a glyph row.
local function ApplyNodeIcon(list, iconRegion, icon)
    if type(icon) == "table" then
        if icon.atlas then
            iconRegion:SetAtlas(icon.atlas)
        else
            iconRegion:SetTexture(icon.texture)
            AF.ApplyDefaultTexCoord(iconRegion)
        end
    else
        AF.SetAdaptiveIcon(iconRegion, icon)
        iconRegion:SetTexCoord(0, 1, 0, 1)
    end
end

local function ApplyEntry(list, row, entry)
    HideRowTooltip(row)
    ResetRowForEntry(row, entry)
    row:SetAlpha(1)
    row.entry = entry
    row.id = entry.id
    row.kind = entry.kind
    row.hovered = nil
    row.label:SetText(entry.label)
    row.label:ClearAllPoints()
    row.label:Show()
    row.toggle:EnableMouse(true)
    if entry.kind == "heading" then
        row:EnableMouse(false)
        row.label:SetFontObject("AF_FONT_SMALL")
        row.label:SetPoint("LEFT", 8, 0)
        row.label:SetPoint("RIGHT", -ROW_RIGHT_INSET, 0)
        row.label:SetShown(not list.compact)
        row.iconPlate:Hide()
        row.toggle:Hide()
        PositionRowTooltipAnchor(list, row, list.compact)
        return
    end

    local compact = list.compact
    row:EnableMouse(true)
    row.label:SetFontObject("AF_FONT_NORMAL")
    row.label:SetShown(not compact)

    -- Compact parent rows (hasChildren) keep the shrunken chevron immediately
    -- beside the icon in the 48px content lane. The remaining 10px at the
    -- right is reserved exclusively for the transient scrollbar. Compact leaf
    -- rows stay icon-only, centered in their own content area.
    local leftInset
    if compact then
        leftInset = entry.hasChildren and COMPACT_ICON_INSET
            or ((list.compactIconAreaWidth - list.iconSize) / 2)
    else
        leftInset = EXPANDED_ROW_LEFT_INSET + ((entry.depth or 0) * INDENT_PER_DEPTH)
    end
    local icon = entry.icon or compact and list.fallbackIcon
    if icon then
        row.iconPlate:ClearAllPoints()
        row.iconPlate:SetPoint("LEFT", leftInset, 0)
        ApplyNodeIcon(list, row.icon, icon)
        row.iconPlate:Show()
        row.label:SetPoint("LEFT", row.iconPlate, "RIGHT", 7, 0)
    else
        row.iconPlate:Hide()
        row.label:SetPoint("LEFT", leftInset, 0)
    end

    if entry.hasChildren then
        row.toggle.icon:SetTexture(AF.GetIcon(
            list.expandedById[entry.id] and "ArrowDown1" or "ArrowRight1"
        ))
        row.toggle:ClearAllPoints()
        if compact then
            -- shrink to the compact chevron size (see COMPACT_TOGGLE_SIZE's
            -- arithmetic comment above) and anchor from the row's LEFT
            -- (which coincides with the viewport's left edge in both
            -- presentations) so it lands inside the visible collapsedWidth
            -- strip rather than off past the row's full (always-
            -- expandedWidth) frame
            AF.SetSize(row.toggle, COMPACT_TOGGLE_SIZE, COMPACT_TOGGLE_SIZE)
            row.toggle:SetPoint("LEFT", COMPACT_ICON_INSET + list.iconSize, 0)
        else
            -- restore the full expanded chevron size on this pooled row
            AF.SetSize(row.toggle, TOGGLE_SIZE, TOGGLE_SIZE)
            row.toggle:SetPoint("RIGHT", -(SCROLLBAR_WIDTH + 2), 0)
        end
        row.toggle:Show()
        if not compact then
            row.label:SetPoint("RIGHT", row.toggle, "LEFT", -3, 0)
        end
    else
        row.toggle:Hide()
        if not compact then
            row.label:SetPoint("RIGHT", -ROW_RIGHT_INSET, 0)
        end
    end

    PositionRowTooltipAnchor(list, row, compact)
end

local function ApplyModel(list)
    BuildVisibleEntries(list)

    local visibleEntries = list.visibleEntries
    local activeRows = list.activeRows
    local scrollContent = list.scrollContent
    local offset = 0
    for index, entry in ipairs(visibleEntries) do
        local row = AcquireRow(list, index)
        activeRows[index] = row
        ApplyEntry(list, row, entry)

        local height = entry.kind == "heading" and list.headingHeight or list.rowHeight
        if entry.kind == "heading" and index > 1 then
            offset = offset + HEADING_TOP_GAP
        end
        row.layoutTop = offset
        row.layoutBottom = offset + height
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, -offset)
        row:SetPoint("RIGHT", scrollContent, "RIGHT")
        AF.SetHeight(row, height)
        row:Show()
        row.hovered = row:IsMouseOver()
            or row.toggle:IsShown() and row.toggle:IsMouseOver()
        PaintRow(list, row)
        if row.hovered then
            ShowRowTooltip(row)
        end
        offset = row.layoutBottom + ROW_SPACING
    end

    for index = #visibleEntries + 1, #list.rows do
        local row = list.rows[index]
        activeRows[index] = nil
        row.entry = nil
        row.id = nil
        row.kind = nil
        row.hovered = nil
        HideRowTooltip(row)
        row:Hide()
    end

    AF.SetHeight(scrollContent, max(1, offset - ROW_SPACING))
    -- single shared scroll offset: re-clamp whatever the scroll frame holds
    -- (identical entries in compact/expanded keep it valid across flips)
    list.scrollBar:SetScroll(list.scrollFrame:GetVerticalScroll())
    list:EnsureSelectedRowVisible()
    list.scrollBar:Update()
end

local function BuildEntryLayout(list, entries)
    local layout = {}
    local offset = 0
    for index, entry in ipairs(entries) do
        local height = entry.kind == "heading" and list.headingHeight or list.rowHeight
        if entry.kind == "heading" and index > 1 then
            offset = offset + HEADING_TOP_GAP
        end

        local key = entry.id or entry
        layout[key] = {
            top = offset,
            bottom = offset + height,
            height = height,
        }
        offset = offset + height + ROW_SPACING
    end
    return layout, max(1, offset - ROW_SPACING)
end

local function PositionAnimatedRows(list, animation, progress)
    local scrollContent = list.scrollContent
    for _, state in ipairs(animation.rows) do
        local row = state.row
        local top = state.fromTop + ((state.toTop - state.fromTop) * progress)
        local alpha = state.fromAlpha + ((state.toAlpha - state.fromAlpha) * progress)
        row.layoutTop = top
        row.layoutBottom = top + state.height
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, -top)
        row:SetPoint("RIGHT", scrollContent, "RIGHT")
        AF.SetHeight(row, state.height)
        row:SetAlpha(alpha)
        row:Show()
    end
end

local function UpdateModelAnimation(list, animation, currentHeight)
    if list.modelAnimation ~= animation then return end

    local heightDelta = animation.targetHeight - animation.startHeight
    local progress = heightDelta == 0
        and 1
        or (currentHeight - animation.startHeight) / heightDelta
    progress = max(0, min(1, progress))
    PositionAnimatedRows(list, animation, progress)
    list.scrollBar:Update()
    list.scrollBar:SetScroll(
        animation.startOffset
            + ((animation.targetOffset - animation.startOffset) * progress)
    )
end

local function AnimateExpandedChange(list, id, expanded)
    if not list:IsVisible() then
        list.expandedById[id] = expanded
        ApplyModel(list)
        return
    end

    local oldRowsByKey = {}
    local oldLayout = {}
    for _, row in ipairs(list.activeRows) do
        if row.entry then
            local key = row.id or row.entry
            oldRowsByKey[key] = row
            oldLayout[key] = {
                top = row.layoutTop,
                bottom = row.layoutBottom,
                height = row.layoutBottom - row.layoutTop,
            }
        end
    end

    local scrollFrame = list.scrollFrame
    local scrollContent = list.scrollContent
    local startHeight = scrollContent:GetHeight()
    local startOffset = scrollFrame:GetVerticalScroll()
    list.expandedById[id] = expanded
    BuildVisibleEntries(list)

    local targetLayout, targetHeight = BuildEntryLayout(list, list.visibleEntries)
    local targetOffset = min(
        startOffset,
        max(0, targetHeight - scrollFrame:GetHeight())
    )
    if targetHeight == startHeight then
        ApplyModel(list)
        list.scrollBar:SetScroll(targetOffset)
        return
    end

    local parentLayout = targetLayout[id] or oldLayout[id]
    local branchTop = parentLayout and (parentLayout.bottom + ROW_SPACING) or 0
    local animation = {
        rows = {},
        startHeight = startHeight,
        targetHeight = targetHeight,
        startOffset = startOffset,
        targetOffset = targetOffset,
    }
    local usedRows = {}
    local nextPoolIndex = #list.activeRows + 1

    for _, entry in ipairs(list.visibleEntries) do
        local key = entry.id or entry
        local row = oldRowsByKey[key]
        local incoming = row == nil
        if incoming then
            row = AcquireRow(list, nextPoolIndex)
            nextPoolIndex = nextPoolIndex + 1
        end

        ApplyEntry(list, row, entry)
        PaintRow(list, row, true)
        row:EnableMouse(false)
        row.toggle:EnableMouse(false)
        usedRows[row] = true
        local target = targetLayout[key]
        local previous = oldLayout[key]
        local fromTop = previous and previous.top or branchTop
        if incoming and entry.parentId then
            local parent = oldLayout[entry.parentId]
                or targetLayout[entry.parentId]
            if parent then
                fromTop = parent.bottom + ROW_SPACING
            end
        end
        animation.rows[#animation.rows + 1] = {
            row = row,
            height = target.height,
            fromTop = fromTop,
            toTop = target.top,
            fromAlpha = incoming and 0 or 1,
            toAlpha = 1,
        }
    end

    for _, row in ipairs(list.activeRows) do
        if row.entry and not usedRows[row] then
            row:EnableMouse(false)
            row.toggle:EnableMouse(false)
            local parentId = row.entry.parentId
            local survivingParent
            while parentId do
                survivingParent = targetLayout[parentId]
                if survivingParent then break end
                local parent = list.entriesById[parentId]
                parentId = parent and parent.parentId
            end
            animation.rows[#animation.rows + 1] = {
                row = row,
                height = row.layoutBottom - row.layoutTop,
                fromTop = row.layoutTop,
                toTop = survivingParent
                    and (survivingParent.bottom + ROW_SPACING)
                    or branchTop,
                fromAlpha = 1,
                toAlpha = 0,
            }
        end
    end

    list.modelAnimation = animation
    PositionAnimatedRows(list, animation, 0)
    list.scrollBar:Update()
    list.scrollBar:Reveal()
    AF.AnimatedResize(
        scrollContent,
        nil,
        targetHeight,
        0.015,
        10,
        nil,
        function()
            if list.modelAnimation ~= animation then return end
            list.modelAnimation = nil
            ApplyModel(list)
            list.scrollBar:SetScroll(animation.targetOffset)
            list.scrollBar:ScheduleFadeOut()
        end,
        function(_, currentHeight)
            UpdateModelAnimation(list, animation, currentHeight)
        end
    )
end

-- completes any in-flight expand/collapse animation immediately
function AF_TreeListMixin:FinishModelAnimation()
    if not self.modelAnimation then return end

    StopResize(self.scrollContent)
    self.modelAnimation = nil
    ApplyModel(self)
    self.scrollBar:ScheduleFadeOut()
end

---@param model table[] hierarchical entries: {kind="heading", label=...} or {id=..., label=..., icon=..., expanded=..., children={...}}
---@return boolean accepted
function AF_TreeListMixin:SetModel(model)
    if type(model) ~= "table" then return false end
    self:FinishModelAnimation()

    local normalizedModel = {}
    local normalizedById = {}
    local expandedById = self.expandedById

    local function Normalize(entries, output, depth, parentId)
        for _, source in ipairs(entries) do
            if type(source) == "table" then
                if source.kind == "heading" then
                    output[#output + 1] = {
                        kind = "heading",
                        label = source.label or "",
                        depth = 0,
                    }
                elseif source.id ~= nil and not normalizedById[source.id] then
                    local entry = {}
                    for key, value in pairs(source) do
                        if key ~= "children" then
                            entry[key] = value
                        end
                    end
                    entry.kind = entry.kind or "row"
                    entry.label = entry.label or ""
                    entry.depth = depth
                    entry.parentId = parentId
                    entry.children = {}
                    normalizedById[entry.id] = entry
                    output[#output + 1] = entry

                    if type(source.children) == "table" then
                        Normalize(source.children, entry.children, depth + 1, entry.id)
                    end
                    entry.hasChildren = #entry.children > 0
                    -- expandedById persists across SetModel: only seed ids
                    -- never seen before, so expansion is retained for parents
                    -- that are temporarily absent from the model
                    if entry.hasChildren and expandedById[entry.id] == nil then
                        expandedById[entry.id] = source.expanded == true
                    end
                end
            end
        end
    end

    Normalize(model, normalizedModel, 0, nil)
    self.model = normalizedModel
    self.entriesById = normalizedById
    if self.selectionId ~= nil and not normalizedById[self.selectionId] then
        self.selectionId = nil
    end
    ApplyModel(self)
    return true
end

-- silent programmatic selection: expands ancestors so the selection is
-- visible, but never fires onSelected (only user clicks do)
---@param id any pass nil to clear the selection
---@return boolean selected
function AF_TreeListMixin:SetSelection(id)
    if id == nil then
        self:FinishModelAnimation()
        self.selectionId = nil
        ApplyModel(self)
        return false
    end
    local entry = self.entriesById[id]
    if not entry or entry.kind == "heading" then return false end

    self:FinishModelAnimation()
    self.selectionId = id
    local parentId = entry.parentId
    while parentId do
        self.expandedById[parentId] = true
        parentId = self.entriesById[parentId].parentId
    end
    ApplyModel(self)
    return true
end

---@param id any
---@param expanded boolean
---@return boolean accepted
function AF_TreeListMixin:SetExpanded(id, expanded)
    local entry = self.entriesById[id]
    if not entry or not entry.hasChildren or type(expanded) ~= "boolean" then
        return false
    end
    if self.modelAnimation then return false end
    if self.expandedById[id] == expanded then return true end

    AnimateExpandedChange(self, id, expanded)
    return true
end

---@param id any
---@return boolean accepted
function AF_TreeListMixin:ToggleExpanded(id)
    local entry = self.entriesById[id]
    if not entry or not entry.hasChildren then return false end
    if self.modelAnimation then return false end

    -- plain negation: no presentation-dependent special cases
    -- (see the expansion-persistence contract above)
    AnimateExpandedChange(self, id, not self.expandedById[id])
    return true
end

-- presentation only: icon-only rows, hidden headings/labels/chevrons.
-- expandedById is untouched, expanded children stay visible (icon-only),
-- and the shared scroll offset is preserved (re-clamped by ApplyModel)
---@param compact boolean
function AF_TreeListMixin:SetCompact(compact)
    compact = compact == true
    if self.compact == compact then return end

    self:FinishModelAnimation()
    self.compact = compact
    ApplyModel(self)
end

---@return boolean compact
function AF_TreeListMixin:IsCompact()
    return self.compact
end

---@param callback? fun(id:any, entry:table) fired on user click selection
---@return boolean accepted
function AF_TreeListMixin:SetOnSelected(callback)
    if callback ~= nil and type(callback) ~= "function" then return false end
    self.onSelected = callback
    return true
end

---@param callback? function invoked when the pointer engages the list (rows, chevrons, scroll bar)
function AF_TreeListMixin:SetOnPointerEnter(callback)
    self.onPointerEnter = callback
end

---@param callback? function invoked when the pointer disengages the list
function AF_TreeListMixin:SetOnPointerLeave(callback)
    self.onPointerLeave = callback
end

---@param parent Frame
---@param options? table
--- - expandedWidth number full presentation width (default 170)
--- - collapsedWidth number compact presentation width, clamped to retain a dedicated scrollbar lane (default 58)
--- - rowHeight number (default 28)
--- - headingHeight number (default 22)
--- - iconSize number (default 20)
--- - accentColor string color name for highlight/thumb (default AF.GetAddonAccentColorName())
--- - fallbackIcon string|{atlas?: string, texture?: string}|nil icon for icon-less rows in compact mode (default nil)
--- - iconPlateColors {border={r,g,b,a}, fill={r,g,b,a}}|nil colors for each row's
---   icon plate (AF's lightweight one-fill/four-edge backdrop); defaults to
---   AF.ApplyLightweightBackdropWithColors' own "background"/"border" defaults (default nil)
---@return AF_TreeList list
function AF.CreateTreeList(parent, options)
    options = options or {}

    local list = AF.CreateFrame(parent)
    Mixin(list, AF_TreeListMixin)

    list.expandedWidth = options.expandedWidth or DEFAULT_EXPANDED_WIDTH
    list.rowHeight = options.rowHeight or DEFAULT_ROW_HEIGHT
    list.headingHeight = options.headingHeight or DEFAULT_HEADING_HEIGHT
    list.iconSize = options.iconSize or DEFAULT_ICON_SIZE
    list.collapsedWidth = max(
        options.collapsedWidth or DEFAULT_COLLAPSED_WIDTH,
        GetMinimumCollapsedWidth(list.iconSize)
    )
    list.accentColor = options.accentColor or AF.GetAddonAccentColorName()
    list.fallbackIcon = options.fallbackIcon
    list.iconPlateColors = options.iconPlateColors
    list.compactIconAreaWidth = list.collapsedWidth - ROW_RIGHT_INSET

    list.compact = false
    list.model = {}
    list.entriesById = {}
    list.expandedById = {}
    list.visibleEntries = {}
    list.rows = {}
    list.activeRows = {}
    list.tooltipOwner = nil

    local scrollFrame = CreateFrame("ScrollFrame", nil, list)
    list.scrollFrame = scrollFrame
    scrollFrame:SetPoint("TOPLEFT")
    scrollFrame:SetPoint("BOTTOMRIGHT")
    scrollFrame:EnableMouse(true)

    local scrollContent = AF.CreateFrame(scrollFrame)
    list.scrollContent = scrollContent
    AF.SetWidth(scrollContent, list.expandedWidth)
    AF.SetHeight(scrollContent, 1)
    scrollFrame:SetScrollChild(scrollContent)

    list.scrollBar = AF.AttachTransientScrollBar(list, scrollFrame, scrollContent, {
        width = SCROLLBAR_WIDTH,
        thumbMinHeight = SCROLLBAR_THUMB_MIN_HEIGHT,
        fadeDelay = SCROLLBAR_FADE_DELAY,
        scrollStep = (list.rowHeight + ROW_SPACING) * 3,
        accentColor = list.accentColor,
    })
    list.scrollBar:SetOnPointerEnter(function()
        NotifyPointerEnter(list)
    end)
    list.scrollBar:SetOnPointerLeave(function()
        NotifyPointerLeave(list)
    end)

    scrollFrame:SetScript("OnEnter", function()
        NotifyPointerEnter(list)
    end)
    scrollFrame:SetScript("OnLeave", function()
        NotifyPointerLeave(list)
    end)
    scrollFrame:SetScript("OnSizeChanged", function()
        list.scrollBar:SetScroll(scrollFrame:GetVerticalScroll())
        list:EnsureSelectedRowVisible()
        list.scrollBar:Update()
    end)
    list:SetScript("OnHide", function()
        if list.tooltipOwner then
            HideRowTooltip(list.tooltipOwner)
        end
    end)

    return list
end

---------------------------------------------------------------------
-- sidebar rail
---------------------------------------------------------------------
-- Manual collapse only: the rail has exactly two presentation states,
-- expanded and collapsed, switched instantly by SetCollapsed/ToggleCollapsed
-- (no hover auto-hide, no width animation, no pointer-enter/leave wiring).
-- Collapsing is presentation-only -- expandedById is never written here, so
-- nests expanded before a collapse are still expanded after re-expanding
-- (see the tree list's expansion-persistence contract).
---@class AF_SidebarRail:AF_Frame
---@field treeList AF_TreeList embedded tree list (model/selection/expansion API)
local AF_SidebarRailMixin = {}

local function PublishPresentationWidth(rail, width)
    rail.presentationWidth = width
    if rail.onPresentationWidthChanged then
        rail.onPresentationWidthChanged(width, rail:GetDesiredWidth())
    end
end

local function SetRailWidth(rail, width)
    AF.SetWidth(rail, width)
    PublishPresentationWidth(rail, width)
end

local function ApplyDesiredState(rail)
    SetRailWidth(rail, rail.collapsed and rail.collapsedWidth or rail.expandedWidth)
    rail.treeList:SetCompact(rail.collapsed)
    if rail.shown then
        rail:Show()
    else
        rail:Hide()
    end
end

---@param shown boolean
---@return boolean accepted
function AF_SidebarRailMixin:SetShown(shown)
    if type(shown) ~= "boolean" then return false end
    if self.shown == shown then return true end
    self.shown = shown
    ApplyDesiredState(self)
    return true
end

---@param collapsed boolean
---@param silent? boolean suppress onCollapsedChanged (presentation-width callback still fires)
---@return boolean changed true if the collapsed state actually changed
function AF_SidebarRailMixin:SetCollapsed(collapsed, silent)
    if type(collapsed) ~= "boolean" then return false end
    if self.collapsed == collapsed then return false end

    self.collapsed = collapsed
    ApplyDesiredState(self)
    if not silent and self.onCollapsedChanged then
        self.onCollapsedChanged(collapsed)
    end
    return true
end

---@return boolean collapsed
function AF_SidebarRailMixin:GetCollapsed()
    return self.collapsed
end

---@return boolean collapsed the new state
function AF_SidebarRailMixin:ToggleCollapsed()
    local collapsed = not self.collapsed
    self:SetCollapsed(collapsed)
    return collapsed
end

---@param callback? fun(collapsed:boolean)
---@return boolean accepted
function AF_SidebarRailMixin:SetOnCollapsedChanged(callback)
    if callback ~= nil and type(callback) ~= "function" then return false end
    self.onCollapsedChanged = callback
    return true
end

---@param callback? fun(presentationWidth:number, reservedWidth:number)
---@return boolean accepted
function AF_SidebarRailMixin:SetOnPresentationWidthChanged(callback)
    if callback ~= nil and type(callback) ~= "function" then return false end
    self.onPresentationWidthChanged = callback
    if callback then
        callback(self.presentationWidth, self:GetDesiredWidth())
    end
    return true
end

---@return number width reserved width for the current collapse state
function AF_SidebarRailMixin:GetDesiredWidth()
    return self.collapsed and self.collapsedWidth or self.expandedWidth
end

---@param gap? number gap between the rail and adjacent content (default 8)
---@return number inset
function AF_SidebarRailMixin:GetContentInset(gap)
    return self:GetDesiredWidth() + (gap or DEFAULT_CONTENT_GAP)
end

---@param parent Frame
---@param options? table all AF.CreateTreeList options, plus:
--- - collapsedWidth number rail width while collapsed, clamped to retain a dedicated scrollbar lane (default 58)
---@return AF_SidebarRail rail
function AF.CreateSidebarRail(parent, options)
    options = options or {}

    local rail = AF.CreateFrame(parent)
    Mixin(rail, AF_SidebarRailMixin)
    AF.SetFrameLevel(rail, 30, parent)
    rail:EnableMouse(true)

    rail.expandedWidth = options.expandedWidth or DEFAULT_EXPANDED_WIDTH
    rail.collapsedWidth = max(
        options.collapsedWidth or DEFAULT_COLLAPSED_WIDTH,
        GetMinimumCollapsedWidth(options.iconSize or DEFAULT_ICON_SIZE)
    )
    rail.shown = true
    rail.collapsed = false
    rail.presentationWidth = rail.expandedWidth

    local background = rail:CreateTexture(nil, "BACKGROUND")
    rail.background = background
    background:SetAllPoints()
    background:SetColorTexture(AF.GetColorRGB("background", 0.96))

    local treeList = AF.CreateTreeList(rail, options)
    rail.treeList = treeList
    treeList:SetPoint("TOPLEFT")
    treeList:SetPoint("BOTTOMRIGHT")

    ApplyDesiredState(rail)
    return rail
end
