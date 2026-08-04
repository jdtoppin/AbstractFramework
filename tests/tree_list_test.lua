-- Runtime tests for Widgets/TreeList.lua (transient scroll bar, tree list,
-- sidebar rail). Follows tests/lightweight_backdrop_test.lua's stub pattern.

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local function assertTrue(value, message)
    if not value then
        error(("%s: expected truthy, got %s"):format(message, tostring(value)), 2)
    end
end

---------------------------------------------------------------------
-- C_Timer stub with a drain() helper
---------------------------------------------------------------------
local timerQueue = {}

C_Timer = {
    After = function(delay, callback)
        timerQueue[#timerQueue + 1] = {kind = "after", delay = delay, callback = callback}
    end,
    NewTicker = function(interval, callback)
        local ticker = {cancelled = false}
        function ticker:Cancel()
            self.cancelled = true
        end
        timerQueue[#timerQueue + 1] = {kind = "ticker", delay = interval, callback = callback, ticker = ticker}
        return ticker
    end,
}

local function drain()
    local guard = 0
    while #timerQueue > 0 do
        guard = guard + 1
        assertTrue(guard < 500, "timer drain settles")
        local entry = table.remove(timerQueue, 1)
        if entry.kind == "after" then
            entry.callback()
        elseif not entry.ticker.cancelled then
            entry.callback()
        end
    end
end

---------------------------------------------------------------------
-- frame / texture / font string stubs
---------------------------------------------------------------------
local textureMethods = {}

function textureMethods:SetColorTexture(...) self.colorTexture = {...} end
function textureMethods:SetVertexColor(...) self.vertexColor = {...} end
function textureMethods:SetTexture(texture) self.texture = texture end
function textureMethods:SetTexCoord(...) self.texCoord = {...} end
function textureMethods:SetAllPoints() self.allPoints = true end
function textureMethods:SetPoint(...) self.points[#self.points + 1] = {...} end
function textureMethods:ClearAllPoints() self.points = {} end
function textureMethods:SetWidth(width) self.width = width end
function textureMethods:SetHeight(height) self.height = height end
function textureMethods:GetWidth() return self.width or 0 end
function textureMethods:GetHeight() return self.height or 0 end
function textureMethods:Show() self.shown = true end
function textureMethods:Hide() self.shown = false end
function textureMethods:IsShown() return self.shown end
function textureMethods:SetShown(shown) self.shown = shown end

local frameMethods = {}

function frameMethods:CreateTexture(_, layer)
    local texture = setmetatable({parent = self, layer = layer, points = {}, shown = true}, {__index = textureMethods})
    return texture
end

function frameMethods:SetPoint(...) self.points[#self.points + 1] = {...} end
function frameMethods:ClearAllPoints() self.points = {} end
function frameMethods:SetAllPoints() self.allPoints = true end
function frameMethods:SetWidth(width) self.width = width end
function frameMethods:SetHeight(height) self.height = height end
function frameMethods:GetWidth() return self.width or 0 end
function frameMethods:GetHeight() return self.height or 0 end
function frameMethods:SetAlpha(alpha) self.alpha = alpha end
function frameMethods:GetAlpha() return self.alpha or 1 end
function frameMethods:GetParent() return self.parent end

function frameMethods:Show()
    if not self.shown then
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
end

function frameMethods:Hide()
    if self.shown then
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
end

function frameMethods:IsShown() return self.shown end

function frameMethods:IsVisible()
    if not self.shown then return false end
    if self.parent then return self.parent:IsVisible() end
    return true
end

function frameMethods:IsMouseOver() return self.mouseOver == true end
function frameMethods:EnableMouse(enabled) self.mouseEnabled = enabled end
function frameMethods:EnableMouseWheel(enabled) self.mouseWheelEnabled = enabled end
function frameMethods:RegisterForClicks() end
function frameMethods:SetScript(scriptType, handler) self.scripts[scriptType] = handler end
function frameMethods:GetScript(scriptType) return self.scripts[scriptType] end

function frameMethods:SetVerticalScroll(offset) self.verticalScroll = offset end
function frameMethods:GetVerticalScroll() return self.verticalScroll or 0 end
function frameMethods:SetScrollChild(child) self.scrollChild = child end

-- slider
function frameMethods:SetOrientation(orientation) self.orientation = orientation end
function frameMethods:SetValueStep(step) self.valueStep = step end
function frameMethods:SetObeyStepOnDrag() end
function frameMethods:SetThumbTexture(texture) self.thumbTexture = texture end
function frameMethods:SetMinMaxValues(minValue, maxValue) self.minMax = {minValue, maxValue} end

function frameMethods:SetValue(value)
    self.value = value
    if self.scripts.OnValueChanged then
        self.scripts.OnValueChanged(self, value)
    end
end

CreateFrame = function(frameType, name, parent)
    local frame = setmetatable({
        frameType = frameType,
        name = name,
        parent = parent,
        points = {},
        scripts = {},
        shown = true,
        alpha = 1,
    }, {__index = frameMethods})
    return frame
end

Mixin = function(target, ...)
    for index = 1, select("#", ...) do
        for key, value in pairs((select(index, ...))) do
            target[key] = value
        end
    end
end

---------------------------------------------------------------------
-- AF stub
---------------------------------------------------------------------
local resizeCalls = {}

local AF = {}

AF.SetWidth = function(region, width) region:SetWidth(width) end
AF.SetHeight = function(region, height) region:SetHeight(height) end
AF.SetSize = function(region, width, height)
    region:SetWidth(width)
    region:SetHeight(height)
end
AF.SetPoint = function(region, ...) region:SetPoint(...) end
AF.SetFrameLevel = function() end
AF.GetColorTable = function(name, alpha) return {name = name, alpha = alpha} end
AF.GetColorRGB = function(name, alpha) return 1, 1, 1, alpha end
AF.GetAddonAccentColorName = function() return "accent" end
AF.GetIcon = function(name) return "Icons\\" .. name end
AF.SetAdaptiveIcon = function(texture, icon)
    texture.adaptiveIcon = icon
    return true
end

AF.CreateFrame = function(parent, name, width, height)
    local frame = CreateFrame("Frame", name, parent)
    if width then frame:SetWidth(width) end
    if height then frame:SetHeight(height) end
    return frame
end

AF.CreateFontString = function(parent, text)
    local fs = setmetatable({parent = parent, text = text, points = {}, shown = true}, {__index = textureMethods})
    function fs:SetText(value) self.text = value end
    function fs:SetJustifyH(justify) self.justifyH = justify end
    function fs:SetWordWrap() end
    function fs:SetFontObject(font) self.font = font end
    function fs:SetTextColor(...) self.textColor = {...} end
    function fs:SetColor(color) self.color = color end
    return fs
end

AF.CreateGradientTexture = function(parent, orientation, color1, color2)
    local texture = parent:CreateTexture(nil, "BORDER")
    texture.gradient = {orientation = orientation, color1 = color1, color2 = color2}
    return texture
end

-- recording FadeIn/FadeOut, synchronous alpha/visibility
AF.CreateFadeInOutAnimation = function(region, duration)
    region.fadeDuration = duration
    region.fadeCalls = {}
    region.fadeIn = {playing = false, IsPlaying = function(self) return self.playing end}
    region.fadeOut = {playing = false, IsPlaying = function(self) return self.playing end}
    function region:FadeIn()
        self.fadeCalls[#self.fadeCalls + 1] = "in"
        self:SetAlpha(1)
        self:Show()
    end
    function region:FadeOut()
        self.fadeCalls[#self.fadeCalls + 1] = "out"
        self:SetAlpha(0)
        self:Hide()
    end
    function region:ShowNow()
        self:SetAlpha(1)
        self:Show()
    end
    function region:HideNow()
        self:SetAlpha(0)
        self:Hide()
    end
end

-- completes synchronously via onFinish
AF.AnimatedResize = function(frame, targetWidth, targetHeight, _, _, onStart, onFinish, onChange)
    resizeCalls[#resizeCalls + 1] = {frame = frame, targetWidth = targetWidth, targetHeight = targetHeight}
    if onStart then onStart() end
    if targetWidth then frame:SetWidth(targetWidth) end
    if targetHeight then frame:SetHeight(targetHeight) end
    if onChange then onChange(frame:GetWidth(), frame:GetHeight()) end
    if onFinish then onFinish() end
end

local chunk = assert(loadfile("Widgets/TreeList.lua"))
chunk("AbstractFramework", AF)

---------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------
local function BuildModel()
    return {
        {kind = "heading", label = "CATEGORIES"},
        {id = "all", label = "All", icon = "Bag_All"},
        {id = "equipment", label = "Equipment", icon = "Bag_Equipment", children = {
            {id = "weapons", label = "Weapons"},
            {id = "armor", label = "Armor"},
        }},
        {id = "equipment", label = "Duplicate"},
        {id = "consumables", label = "Consumables", icon = "Bag_Consumables", expanded = true, children = {
            {id = "potions", label = "Potions"},
        }},
    }
end

local function visibleIds(list)
    local ids = {}
    for _, entry in ipairs(list.visibleEntries) do
        ids[#ids + 1] = entry.id or entry.kind
    end
    return table.concat(ids, ",")
end

local function findActiveRow(list, id)
    for _, row in ipairs(list.activeRows) do
        if row.id == id then return row end
    end
end

---------------------------------------------------------------------
-- model normalization
---------------------------------------------------------------------
do
    local parent = CreateFrame("Frame", "Parent")
    local list = AF.CreateTreeList(parent, {})
    list.scrollFrame:SetHeight(300)
    list.scrollBar.frame:SetHeight(300)

    assertEqual(list:SetModel("nope"), false, "non-table model rejected")
    assertEqual(list:SetModel(BuildModel()), true, "model accepted")

    assertEqual(#list.model, 4, "duplicate id deduped from top level")
    assertEqual(list.entriesById.equipment.label, "Equipment", "first occurrence wins")
    assertEqual(list.entriesById.equipment.hasChildren, true, "hasChildren computed")
    assertEqual(list.entriesById.weapons.depth, 1, "child depth")
    assertEqual(list.entriesById.weapons.parentId, "equipment", "child parentId")
    assertEqual(list.expandedById.equipment, false, "unexpanded parent seeded false")
    assertEqual(list.expandedById.consumables, true, "initial expanded honored")
    assertEqual(visibleIds(list), "heading,all,equipment,consumables,potions", "collapsed children hidden, expanded children visible")

    local heading = list.activeRows[1]
    assertEqual(heading.kind, "heading", "heading row applied")
    assertEqual(heading.mouseEnabled, false, "heading not clickable")
    assertEqual(heading.label.shown, true, "heading label shown when not compact")
end

---------------------------------------------------------------------
-- selection semantics
---------------------------------------------------------------------
do
    local parent = CreateFrame("Frame", "Parent")
    local list = AF.CreateTreeList(parent, {})
    list.scrollFrame:SetHeight(300)
    list.scrollBar.frame:SetHeight(300)
    list:SetModel(BuildModel())

    local selectedCalls = {}
    list:SetOnSelected(function(id, entry)
        selectedCalls[#selectedCalls + 1] = {id = id, entry = entry}
    end)

    -- silent programmatic selection with ancestor auto-expand
    assertEqual(list:SetSelection("weapons"), true, "selection accepted")
    assertEqual(#selectedCalls, 0, "programmatic selection is silent")
    assertEqual(list.expandedById.equipment, true, "ancestor auto-expanded")
    assertEqual(visibleIds(list), "heading,all,equipment,weapons,armor,consumables,potions", "selected branch visible")

    assertEqual(list:SetSelection("missing"), false, "unknown id rejected")
    assertEqual(list.selectionId, "weapons", "selection unchanged on reject")

    -- click selection fires onSelected
    local allRow = findActiveRow(list, "all")
    allRow.scripts.OnClick(allRow)
    assertEqual(#selectedCalls, 1, "click fires onSelected")
    assertEqual(selectedCalls[1].id, "all", "clicked id reported")

    -- stale-selection clearing on model swap
    list:SetSelection("weapons")
    assertEqual(list:SetModel({{id = "all", label = "All"}}), true, "swap model without selection")
    assertEqual(list.selectionId, nil, "stale selection cleared")

    -- expansion retained for temporarily absent parents
    assertEqual(list.expandedById.equipment, true, "expansion retained while parent absent")
    list:SetModel(BuildModel())
    assertEqual(visibleIds(list), "heading,all,equipment,weapons,armor,consumables,potions", "returning parent still expanded")
end

---------------------------------------------------------------------
-- the persistence cycle: expand nest -> rail collapse -> re-expand
---------------------------------------------------------------------
do
    local parent = CreateFrame("Frame", "Parent")
    local rail = AF.CreateSidebarRail(parent, {fallbackIcon = "Bag_Misc"})
    local list = rail.treeList
    list.scrollFrame:SetHeight(300)
    list.scrollBar.frame:SetHeight(300)
    list:SetModel(BuildModel())
    list:SetExpanded("consumables", false)

    assertEqual(rail:SetAutoHide(true), true, "auto-hide enabled")
    assertEqual(list:IsCompact(), true, "compact while auto-hidden and unhovered")
    assertEqual(rail:GetDesiredWidth(), 40, "reserved width is collapsed width")
    assertEqual(rail.width, 40, "rail collapsed")

    -- hover expand
    rail.mouseOver = true
    rail.scripts.OnEnter(rail)
    assertEqual(list:IsCompact(), false, "hover expands presentation")
    assertEqual(rail.width, 170, "rail expanded")

    -- expand a nest with a plain chevron toggle (no forced-expand special case:
    -- a second toggle right away must collapse, i.e. plain negation)
    assertEqual(list:ToggleExpanded("equipment"), true, "toggle expands")
    assertEqual(list.expandedById.equipment, true, "nest expanded")
    assertEqual(list:ToggleExpanded("equipment"), true, "toggle collapses (plain negation)")
    assertEqual(list.expandedById.equipment, false, "no forced-expand special case while auto-hidden")
    list:ToggleExpanded("equipment")
    assertEqual(visibleIds(list), "heading,all,equipment,weapons,armor,consumables", "children visible after expand")

    -- rail collapse (hover leave) must not modify expandedById
    rail.mouseOver = false
    rail.scripts.OnLeave(rail)
    drain()
    assertEqual(rail.width, 40, "rail collapsed after leave")
    assertEqual(list:IsCompact(), true, "compact after leave")
    assertEqual(list.expandedById.equipment, true, "expandedById untouched by rail collapse")
    assertEqual(visibleIds(list), "heading,all,equipment,weapons,armor,consumables", "compact rail renders expanded children")

    -- compact rows are icon-only
    local weaponsRow = findActiveRow(list, "weapons")
    assertEqual(weaponsRow.label.shown, false, "compact row label hidden")
    assertEqual(weaponsRow.icon.shown, true, "compact row icon shown")
    assertEqual(weaponsRow.icon.adaptiveIcon, "Bag_Misc", "fallback icon used for icon-less compact row")
    assertEqual(list.activeRows[1].label.shown, false, "compact heading label hidden")

    -- re-expanding restores previously expanded nests
    rail.mouseOver = true
    rail.scripts.OnEnter(rail)
    assertEqual(list:IsCompact(), false, "re-hover expands presentation")
    assertEqual(list.expandedById.equipment, true, "expansion restored, not recomputed")
    assertEqual(visibleIds(list), "heading,all,equipment,weapons,armor,consumables", "children visible again")
    assertEqual(findActiveRow(list, "weapons").label.shown, true, "expanded row label shown")
end

---------------------------------------------------------------------
-- transient scroll bar
---------------------------------------------------------------------
do
    local parent = CreateFrame("Frame", "Parent")
    local list = AF.CreateTreeList(parent, {})
    local bar = list.scrollBar
    list.scrollFrame:SetHeight(50)
    bar.frame:SetHeight(50)

    -- inactive while range <= 0
    list:SetModel({{id = "one", label = "One"}})
    assertEqual(bar.frame.shown, false, "bar hidden without overflow")
    list.scrollFrame.scripts.OnMouseWheel(list.scrollFrame, -1)
    assertEqual(bar.frame.shown, false, "wheel does not reveal without overflow")
    assertEqual(bar.frame.mouseEnabled, false, "bar mouse disabled without overflow")
    assertEqual(list.scrollFrame:GetVerticalScroll(), 0, "offset clamped to zero range")
    drain()

    -- ten rows: content height 10*26 + 9*2 = 278, range 228
    local bigModel = {}
    for index = 1, 10 do
        bigModel[index] = {id = "row" .. index, label = "Row " .. index}
    end
    list:SetModel(bigModel)
    assertEqual(list.scrollContent.height, 278, "content height")
    assertEqual(bar.frame.shown, true, "bar revealed when overflow appears")
    assertEqual(bar.frame.mouseEnabled, true, "revealed bar accepts mouse")
    assertEqual(bar.frame.minMax[2], 228, "slider range")
    assertEqual(bar.thumb.height, 20, "thumb clamped to min height")

    -- fade after inactivity: mouse is elsewhere
    drain()
    assertEqual(bar.frame.shown, false, "bar fades after inactivity")
    assertEqual(bar.frame.mouseEnabled, false, "faded bar has mouse disabled")

    -- wheel scrolls and reveals
    list.scrollFrame.scripts.OnMouseWheel(list.scrollFrame, -1)
    assertEqual(list.scrollFrame:GetVerticalScroll(), 84, "wheel step applied")
    assertEqual(bar.frame.shown, true, "wheel reveals bar")

    -- fade-generation invalidation: a later reveal makes the pending
    -- fade-out callback a no-op
    bar.frame.scripts.OnEnter(bar.frame)
    drain()
    assertEqual(bar.frame.shown, true, "stale fade generation ignored")
    assertEqual(bar.frame.mouseEnabled, true, "bar still interactive")

    -- drag holds the bar open through fade attempts
    bar.frame.scripts.OnMouseDown(bar.frame)
    assertEqual(bar:IsDragging(), true, "dragging tracked")
    bar:ScheduleFadeOut()
    drain()
    assertEqual(bar.frame.shown, true, "drag holds bar open")
    bar.frame.scripts.OnMouseUp(bar.frame)
    assertEqual(bar:IsDragging(), false, "drag released")
    drain()
    assertEqual(bar.frame.shown, false, "bar fades after drag ends")
    assertEqual(bar.frame.mouseEnabled, false, "faded bar mouse disabled after drag")

    -- dragging the slider writes clamped offsets
    bar.frame:SetValue(500)
    assertEqual(list.scrollFrame:GetVerticalScroll(), 228, "slider value clamped to range")
    drain()
end

---------------------------------------------------------------------
-- scroll clamping and the single shared offset
---------------------------------------------------------------------
do
    local parent = CreateFrame("Frame", "Parent")
    local list = AF.CreateTreeList(parent, {})
    list.scrollFrame:SetHeight(50)
    list.scrollBar.frame:SetHeight(50)

    local bigModel = {}
    for index = 1, 10 do
        bigModel[index] = {id = "row" .. index, label = "Row " .. index}
    end
    list:SetModel(bigModel)

    list.scrollBar:SetScroll(1000)
    assertEqual(list.scrollFrame:GetVerticalScroll(), 228, "offset clamped to range")

    -- one offset across compact/expanded presentation flips
    list:SetCompact(true)
    assertEqual(list.scrollFrame:GetVerticalScroll(), 228, "offset preserved entering compact")
    list:SetCompact(false)
    assertEqual(list.scrollFrame:GetVerticalScroll(), 228, "offset preserved leaving compact")

    -- shrinking content re-clamps the shared offset
    local smallModel = {}
    for index = 1, 5 do
        smallModel[index] = {id = "row" .. index, label = "Row " .. index}
    end
    list:SetModel(smallModel)
    -- content height 5*26 + 4*2 = 138, range 88
    assertEqual(list.scrollFrame:GetVerticalScroll(), 88, "offset re-clamped after shrink")
    drain()
end

---------------------------------------------------------------------
-- no OnUpdate anywhere in the widget source
---------------------------------------------------------------------
do
    local file = assert(io.open("Widgets/TreeList.lua", "r"))
    local source = file:read("*a")
    file:close()
    assertEqual(source:find('SetScript("OnUpdate"', 1, true), nil, "no OnUpdate handlers")
end

print("tree list tests passed")
