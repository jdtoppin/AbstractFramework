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

local function assertNotContains(source, needle, message)
    if source:find(needle, 1, true) then
        error(("%s: unexpected occurrence of %q"):format(message, needle), 2)
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
function textureMethods:SetAtlas(atlas)
    self.atlas = atlas
    -- mirrors Blizzard's real Texture:SetAtlas, which redefines the
    -- texture's coordinate rect from the atlas's own sub-region -- silently
    -- overwriting (without an explicit SetTexCoord call, so texCoordCalls
    -- is untouched) any texcoord a prior pooled-row render left behind,
    -- e.g. the 0.08-0.92 crop from a texture-icon row
    self.texCoord = nil
end
function textureMethods:SetDesaturated(desaturated) self.desaturated = desaturated end
function textureMethods:SetTexCoord(...)
    self.texCoord = {...}
    self.texCoordCalls = (self.texCoordCalls or 0) + 1
end
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
local backdropCalls = {}
local tooltipCalls = {}

local AF = {}

AF.Tooltip = {owner = nil}
function AF.Tooltip:GetOwner()
    return self.owner
end

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
AF.ShowTooltip = function(widget, anchor, x, y, lines)
    AF.Tooltip.owner = widget
    tooltipCalls[#tooltipCalls + 1] = {
        kind = "show",
        widget = widget,
        anchor = anchor,
        x = x,
        y = y,
        lines = lines,
    }
end
AF.HideTooltip = function()
    AF.Tooltip.owner = nil
    tooltipCalls[#tooltipCalls + 1] = {kind = "hide"}
end
AF.SetAdaptiveIcon = function(texture, icon)
    texture.adaptiveIcon = icon
    return true
end

-- mirrors Widgets/Texture.lua's AF.GetDefaultTexCoord/AF.ApplyDefaultTexCoord:
-- the standard Blizzard-icon crop that trims rounded stock corners
AF.GetDefaultTexCoord = function() return 0.08, 0.92, 0.08, 0.92 end
AF.ApplyDefaultTexCoord = function(tex) tex:SetTexCoord(AF.GetDefaultTexCoord()) end

-- mirrors Widgets/Base.lua's AF.ApplyLightweightBackdropWithColors: records
-- the (color, borderColor) it was invoked with so tests can observe both
-- "was a plate applied" and "was it applied exactly once per pooled row"
AF.ApplyLightweightBackdropWithColors = function(frame, color, borderColor, borderSize)
    frame.iconPlateBackdrop = {color = color, borderColor = borderColor, borderSize = borderSize}
    backdropCalls[#backdropCalls + 1] = frame
end

-- mirrors Widgets/Frame.lua's AF.CreateLightweightBorderedFrame: the
-- sanctioned constructor that applies the backdrop BEFORE the frame is
-- registered with the pixel updater, and whose mixin's UpdatePixels chains
-- AF.UpdateLightweightBackdropPixels -- unlike a bare AF.CreateFrame +
-- AF.ApplyLightweightBackdropWithColors call, which registers first and
-- never gets its backdrop pixels re-laid-out on a UI-scale change
AF.CreateLightweightBorderedFrame = function(parent, name, width, height, color, borderColor, borderSize)
    local frame = CreateFrame("Frame", name, parent)
    AF.SetSize(frame, width, height)
    AF.ApplyLightweightBackdropWithColors(frame, color, borderColor, borderSize)
    frame.isLightweightBorderedFrame = true
    function frame:UpdatePixels()
        self.updatePixelsCalled = (self.updatePixelsCalled or 0) + 1
    end
    return frame
end

-- mirrors Utils/PixelUtil.lua's AF.SetInside(region, relativeTo, offsetX, offsetY)
AF.SetInside = function(region, relativeTo, offsetX, offsetY)
    offsetX = offsetX or 0
    offsetY = offsetY or offsetX
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", relativeTo, "TOPLEFT", offsetX, -offsetY)
    region:SetPoint("BOTTOMRIGHT", relativeTo, "BOTTOMRIGHT", -offsetX, offsetY)
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
        {id = "equipment", label = "Equipment", icon = "Bag_IndividualBags", children = {
            {id = "weapons", label = "Weapons"},
            {id = "armor", label = "Armor"},
        }},
        {id = "equipment", label = "Duplicate"},
        {id = "consumables", label = "Consumables", icon = "Bag_Empty", expanded = true, children = {
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

local function isDescendantOf(frame, ancestor)
    local parent = frame:GetParent()
    while parent do
        if parent == ancestor then return true end
        parent = parent:GetParent()
    end
    return false
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
-- default sizing: 1440p legibility pass grows the icon plate (16->20) and
-- row height (26->28); headings are untouched (still 22)
---------------------------------------------------------------------
do
    local parent = CreateFrame("Frame", "Parent")
    local list = AF.CreateTreeList(parent, {})
    list.scrollFrame:SetHeight(300)
    list.scrollBar.frame:SetHeight(300)

    assertEqual(list.iconSize, 20, "default icon size is 20")
    assertEqual(list.rowHeight, 28, "default row height is 28")
    assertEqual(list.headingHeight, 22, "default heading height unchanged")

    list:SetModel(BuildModel())

    local dataRow = findActiveRow(list, "all")
    assertEqual(dataRow.iconPlate.width, 20, "data row icon plate is 20px wide")
    assertEqual(dataRow.iconPlate.height, 20, "data row icon plate is 20px tall")
    assertEqual(dataRow.height, 28, "data row frame height is 28px")

    local heading = list.activeRows[1]
    assertEqual(heading.kind, "heading", "first active row is the heading")
    assertEqual(heading.height, 22, "heading row frame height unchanged at 22px")
end

---------------------------------------------------------------------
-- icon shape dispatch (atlas / texture / string) + plate + crop
---------------------------------------------------------------------
do
    local function IconModel()
        return {
            {id = "atlasRow", label = "Atlas", icon = {atlas = "X"}},
            {id = "textureRow", label = "Texture", icon = {texture = 123}},
            {id = "stringRow", label = "String", icon = "Bag_Misc"},
        }
    end

    local parent = CreateFrame("Frame", "Parent")
    local list = AF.CreateTreeList(parent, {})
    list.scrollFrame:SetHeight(300)
    list.scrollBar.frame:SetHeight(300)

    local backdropCallsBefore = #backdropCalls
    list:SetModel(IconModel())

    local atlasRow = findActiveRow(list, "atlasRow")
    local textureRow = findActiveRow(list, "textureRow")
    local stringRow = findActiveRow(list, "stringRow")

    -- every row's icon sits on a plate: one lightweight backdrop per pooled
    -- row, created once (not per ApplyEntry)
    assertTrue(atlasRow.iconPlate, "atlas row has an icon plate")
    assertTrue(textureRow.iconPlate, "texture row has an icon plate")
    assertTrue(stringRow.iconPlate, "string row has an icon plate")
    assertEqual(atlasRow.icon.parent, atlasRow.iconPlate, "icon region parented inside the plate")
    assertEqual(#backdropCalls - backdropCallsBefore, 3, "one backdrop call per pooled row")

    -- plate built via AF's sanctioned lightweight-bordered-frame constructor
    -- (backdrop applied before pixel-updater registration, UpdatePixels
    -- chains AF.UpdateLightweightBackdropPixels) rather than a bare
    -- AF.CreateFrame + AF.ApplyLightweightBackdropWithColors pairing
    assertTrue(atlasRow.iconPlate.isLightweightBorderedFrame, "icon plate built via AF.CreateLightweightBorderedFrame")
    assertEqual(type(atlasRow.iconPlate.UpdatePixels), "function", "icon plate carries the lightweight-bordered-frame mixin's UpdatePixels")

    -- icons render at full alpha over the plate (icons must be full-color
    -- per spec, not composited toward the plate's near-black default fill)
    assertEqual(atlasRow.icon.vertexColor[4], 1, "row icon renders at full alpha")

    list:SetModel(IconModel())
    assertEqual(findActiveRow(list, "atlasRow"), atlasRow, "row object reused by index")
    assertEqual(#backdropCalls - backdropCallsBefore, 3, "plate created once per pooled row, not recreated on re-render")

    -- atlas: SetAtlas only, full color, never texcoord-cropped -- SetAtlas
    -- defines both the atlas page texture and its sub-region UVs, so
    -- cropping afterward would stretch the sprite sheet across the icon
    assertEqual(atlasRow.icon.atlas, "X", "atlas shape calls SetAtlas")
    assertEqual(atlasRow.icon.texCoordCalls, nil, "atlas shape gets no texcoord call")

    -- texture: SetTexture + the standard Blizzard icon crop (0.08-0.92) so
    -- the rounded stock corners vanish inside the square plate
    assertEqual(textureRow.icon.texture, 123, "texture shape calls SetTexture")
    assertEqual(textureRow.icon.texCoord[1], 0.08, "texture shape crops texcoord left")
    assertEqual(textureRow.icon.texCoord[2], 0.92, "texture shape crops texcoord right")
    assertEqual(textureRow.icon.texCoord[3], 0.08, "texture shape crops texcoord top")
    assertEqual(textureRow.icon.texCoord[4], 0.92, "texture shape crops texcoord bottom")

    -- string (glyph/adaptive icon): full color, uncropped, full texcoords
    assertEqual(stringRow.icon.adaptiveIcon, "Bag_Misc", "string shape uses adaptive icon path")
    assertEqual(stringRow.icon.texCoord[1], 0, "string shape uses full texcoord left")
    assertEqual(stringRow.icon.texCoord[2], 1, "string shape uses full texcoord right")
    assertEqual(stringRow.icon.texCoord[3], 0, "string shape uses full texcoord top")
    assertEqual(stringRow.icon.texCoord[4], 1, "string shape uses full texcoord bottom")

    -- pooled-row reuse: a row that showed an atlas icon (no texcoord call
    -- yet) must reset to full texcoords when reused for a string (glyph) row
    local reuseParent = CreateFrame("Frame", "Parent")
    local reuseList = AF.CreateTreeList(reuseParent, {})
    reuseList.scrollFrame:SetHeight(300)
    reuseList.scrollBar.frame:SetHeight(300)
    reuseList:SetModel({{id = "a", label = "A", icon = {atlas = "Foo"}}})

    local reusedRow = findActiveRow(reuseList, "a")
    assertEqual(reusedRow.icon.atlas, "Foo", "pooled row starts atlas")
    assertEqual(reusedRow.icon.texCoordCalls, nil, "pooled row starts atlas, no texcoord call yet")

    reuseList:SetModel({{id = "b", label = "B", icon = "Bag_Misc"}})
    local newRow = reuseList.activeRows[1]
    assertEqual(newRow, reusedRow, "row object reused by index (atlas->string)")
    assertEqual(newRow.icon.adaptiveIcon, "Bag_Misc", "reused row uses adaptive icon path")
    assertEqual(newRow.icon.texCoord[1], 0, "reused row (atlas->string) resets texcoord left")
    assertEqual(newRow.icon.texCoord[2], 1, "reused row (atlas->string) resets texcoord right")
    assertEqual(newRow.icon.texCoord[3], 0, "reused row (atlas->string) resets texcoord top")
    assertEqual(newRow.icon.texCoord[4], 1, "reused row (atlas->string) resets texcoord bottom")

    -- pooled-row reuse: a row that showed an atlas icon must also get
    -- cropped when reused for a plain texture-icon entry
    local reuseParent2 = CreateFrame("Frame", "Parent")
    local reuseList2 = AF.CreateTreeList(reuseParent2, {})
    reuseList2.scrollFrame:SetHeight(300)
    reuseList2.scrollBar.frame:SetHeight(300)
    reuseList2:SetModel({{id = "a", label = "A", icon = {atlas = "Foo"}}})

    local reusedRow2 = findActiveRow(reuseList2, "a")
    assertEqual(reusedRow2.icon.atlas, "Foo", "pooled row starts atlas")
    assertEqual(reusedRow2.icon.texCoordCalls, nil, "pooled row starts atlas, no texcoord call yet")

    reuseList2:SetModel({{id = "b", label = "B", icon = {texture = 42}}})
    local newRow2 = reuseList2.activeRows[1]
    assertEqual(newRow2, reusedRow2, "row object reused by index (atlas->texture)")
    assertEqual(newRow2.icon.texture, 42, "reused row (atlas->texture) sets texture")
    assertEqual(newRow2.icon.texCoord[1], 0.08, "reused row (atlas->texture) crops texcoord left")
    assertEqual(newRow2.icon.texCoord[2], 0.92, "reused row (atlas->texture) crops texcoord right")
    assertEqual(newRow2.icon.texCoord[3], 0.08, "reused row (atlas->texture) crops texcoord top")
    assertEqual(newRow2.icon.texCoord[4], 0.92, "reused row (atlas->texture) crops texcoord bottom")

    -- pooled-row reuse: a row that showed a CROPPED texture (0.08-0.92) must
    -- not keep that stale crop when reused for an atlas row. ApplyNodeIcon's
    -- atlas branch calls only SetAtlas -- no explicit texcoord reset -- so
    -- this depends entirely on SetAtlas overwriting the stale UVs itself;
    -- this exact seam is where the prior round's critical bug lived
    local reuseParent3 = CreateFrame("Frame", "Parent")
    local reuseList3 = AF.CreateTreeList(reuseParent3, {})
    reuseList3.scrollFrame:SetHeight(300)
    reuseList3.scrollBar.frame:SetHeight(300)
    reuseList3:SetModel({{id = "a", label = "A", icon = {texture = 7}}})

    local reusedRow3 = findActiveRow(reuseList3, "a")
    assertEqual(reusedRow3.icon.texture, 7, "pooled row starts as a cropped texture")
    assertEqual(reusedRow3.icon.texCoord[2], 0.92, "pooled row starts with the 0.08-0.92 crop")

    reuseList3:SetModel({{id = "b", label = "B", icon = {atlas = "Baz"}}})
    local newRow3 = reuseList3.activeRows[1]
    assertEqual(newRow3, reusedRow3, "row object reused by index (texture->atlas)")
    assertEqual(newRow3.icon.atlas, "Baz", "reused row (texture->atlas) calls SetAtlas")
    assertEqual(newRow3.icon.texCoordCalls, 1, "reused row (texture->atlas) gets no additional texcoord call")
    assertEqual(newRow3.icon.texCoord, nil, "reused row (texture->atlas) no longer carries the stale texture crop")
end

---------------------------------------------------------------------
-- compact fallbacks can use the same native texture-table shape as an
-- explicit model icon; consumers are not limited to AF adaptive glyphs
---------------------------------------------------------------------
do
    local parent = CreateFrame("Frame", "Parent")
    local nativeFallback = {texture = "Interface\\Icons\\INV_Misc_Gear_01"}
    local list = AF.CreateTreeList(parent, {fallbackIcon = nativeFallback})
    list.scrollFrame:SetHeight(300)
    list.scrollBar.frame:SetHeight(300)
    list:SetModel({{id = "fallback", label = "Fallback"}})
    list:SetCompact(true)

    local row = findActiveRow(list, "fallback")
    assertEqual(row.icon.texture, nativeFallback.texture,
        "compact fallback texture table uses the native texture path")
    assertEqual(row.icon.texCoord[1], 0.08,
        "native compact fallback uses the standard stock-icon crop")
end

---------------------------------------------------------------------
-- icon plate colors: default to AF's lightweight-backdrop defaults (nil
-- passed through, letting AF.ApplyLightweightBackdropWithColors apply its
-- own "background"/"border" defaults); explicit iconPlateColors passed
-- straight through to every pooled row's plate
---------------------------------------------------------------------
do
    local parent = CreateFrame("Frame", "Parent")
    local list = AF.CreateTreeList(parent, {})
    list.scrollFrame:SetHeight(300)
    list.scrollBar.frame:SetHeight(300)
    list:SetModel({{id = "a", label = "A", icon = "Bag_Misc"}})

    local row = findActiveRow(list, "a")
    assertEqual(row.iconPlate.iconPlateBackdrop.color, nil, "no iconPlateColors: fill left to AF's own default")
    assertEqual(row.iconPlate.iconPlateBackdrop.borderColor, nil, "no iconPlateColors: border left to AF's own default")

    local colors = {fill = {0.1, 0.2, 0.3, 1}, border = {0.4, 0.5, 0.6, 1}}
    local coloredParent = CreateFrame("Frame", "Parent")
    local coloredList = AF.CreateTreeList(coloredParent, {iconPlateColors = colors})
    coloredList.scrollFrame:SetHeight(300)
    coloredList.scrollBar.frame:SetHeight(300)
    coloredList:SetModel({{id = "a", label = "A", icon = "Bag_Misc"}})

    local coloredRow = findActiveRow(coloredList, "a")
    assertEqual(coloredRow.iconPlate.iconPlateBackdrop.color, colors.fill, "iconPlateColors.fill passed through to the plate")
    assertEqual(coloredRow.iconPlate.iconPlateBackdrop.borderColor, colors.border, "iconPlateColors.border passed through to the plate")
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
-- manual collapse: SetCollapsed / GetCollapsed / ToggleCollapsed
---------------------------------------------------------------------
do
    local parent = CreateFrame("Frame", "Parent")
    local rail = AF.CreateSidebarRail(parent, {fallbackIcon = "Bag_Misc"})
    local list = rail.treeList
    list.scrollFrame:SetHeight(300)
    list.scrollBar.frame:SetHeight(300)
    list:SetModel(BuildModel())

    assertEqual(rail:GetCollapsed(), false, "starts expanded")
    assertEqual(rail.width, 170, "starts at expanded width")

    local changedCalls = {}
    assertEqual(rail:SetOnCollapsedChanged(function(collapsed)
        changedCalls[#changedCalls + 1] = collapsed
    end), true, "callback registered")

    -- (a) collapse fires once, instantly (no animation ticker involved)
    assertEqual(rail:SetCollapsed(true), true, "collapse accepted, state changed")
    assertEqual(rail:GetCollapsed(), true, "GetCollapsed reports collapsed")
    assertEqual(rail.width, 58, "rail width reserves a compact scrollbar lane")
    assertEqual(list:IsCompact(), true, "tree list compact while collapsed")
    assertEqual(#changedCalls, 1, "callback fired once")
    assertEqual(changedCalls[1], true, "callback fired with true")

    -- (b) redundant collapse is a no-op: false return, no second callback
    assertEqual(rail:SetCollapsed(true), false, "no state change reported")
    assertEqual(#changedCalls, 1, "callback not fired again")

    -- (c) silent expand: no onCollapsedChanged, but presentation-width still
    -- fires with (expandedWidth, expandedWidth) -- both always the current width
    local presentationCalls = {}
    rail:SetOnPresentationWidthChanged(function(width, reservedWidth)
        presentationCalls[#presentationCalls + 1] = {width = width, reservedWidth = reservedWidth}
    end)
    -- registering the callback invokes it immediately; drop that call
    presentationCalls = {}

    assertEqual(rail:SetCollapsed(false, true), true, "silent expand accepted")
    assertEqual(rail:GetCollapsed(), false, "GetCollapsed reports expanded")
    assertEqual(rail.width, 170, "rail width is expandedWidth")
    assertEqual(list:IsCompact(), false, "tree list expanded")
    assertEqual(#changedCalls, 1, "silent expand does not fire onCollapsedChanged")
    assertEqual(#presentationCalls, 1, "presentation-width callback still fires")
    assertEqual(presentationCalls[1].width, 170, "presentation width is expandedWidth")
    assertEqual(presentationCalls[1].reservedWidth, 170, "reserved width equals current width")

    -- (d) ToggleCollapsed flips state, returns the new state, and always fires
    assertEqual(rail:ToggleCollapsed(), true, "toggle collapses")
    assertEqual(rail:GetCollapsed(), true, "GetCollapsed matches toggle result")
    assertEqual(#changedCalls, 2, "toggle fires callback")
    assertEqual(changedCalls[2], true, "toggle callback reports collapsed")

    assertEqual(rail:ToggleCollapsed(), false, "toggle expands")
    assertEqual(rail:GetCollapsed(), false, "GetCollapsed matches toggle result")
    assertEqual(#changedCalls, 3, "toggle fires callback again")
    assertEqual(changedCalls[3], false, "toggle callback reports expanded")
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

    assertEqual(rail:GetCollapsed(), false, "starts expanded")
    assertEqual(list:IsCompact(), false, "starts uncompact")

    -- expand a nest with a plain chevron toggle (no forced-expand special case:
    -- a second toggle right away must collapse, i.e. plain negation)
    assertEqual(list:ToggleExpanded("equipment"), true, "toggle expands")
    assertEqual(list.expandedById.equipment, true, "nest expanded")
    assertEqual(list:ToggleExpanded("equipment"), true, "toggle collapses (plain negation)")
    assertEqual(list.expandedById.equipment, false, "no forced-expand special case")
    list:ToggleExpanded("equipment")
    assertEqual(visibleIds(list), "heading,all,equipment,weapons,armor,consumables", "children visible after expand")

    -- rail collapse must not modify expandedById
    assertEqual(rail:SetCollapsed(true), true, "rail collapsed")
    assertEqual(rail.width, 58, "rail width reserves a compact scrollbar lane")
    assertEqual(list:IsCompact(), true, "compact after collapse")
    assertEqual(list.expandedById.equipment, true, "expandedById untouched by rail collapse")
    assertEqual(visibleIds(list), "heading,all,equipment,weapons,armor,consumables", "compact rail renders expanded children")

    -- compact rows are icon-only
    local weaponsRow = findActiveRow(list, "weapons")
    assertEqual(weaponsRow.label.shown, false, "compact row label hidden")
    assertEqual(weaponsRow.iconPlate.shown, true, "compact row icon plate shown")
    assertEqual(weaponsRow.icon.adaptiveIcon, "Bag_Misc", "fallback icon used for icon-less compact row")
    assertEqual(list.activeRows[1].label.shown, false, "compact heading label hidden")

    -- re-expanding restores previously expanded nests
    assertEqual(rail:SetCollapsed(false), true, "rail expanded")
    assertEqual(rail.width, 170, "rail width is expandedWidth")
    assertEqual(list:IsCompact(), false, "expanded presentation")
    assertEqual(list.expandedById.equipment, true, "expansion restored, not recomputed")
    assertEqual(visibleIds(list), "heading,all,equipment,weapons,armor,consumables", "children visible again")
    assertEqual(findActiveRow(list, "weapons").label.shown, true, "expanded row label shown")
end

---------------------------------------------------------------------
-- compact-mode chevrons: parent rows keep a clickable chevron beside the
-- icon; leaf rows stay icon-only; expanded-mode positioning is unchanged
---------------------------------------------------------------------
do
    local parent = CreateFrame("Frame", "Parent")
    local list = AF.CreateTreeList(parent, {fallbackIcon = "Bag_Misc"})
    list.scrollFrame:SetHeight(300)
    list.scrollBar.frame:SetHeight(300)
    list:SetModel(BuildModel())
    list:SetSelection("all")

    -- expanded mode: chevron anchored from the row's RIGHT edge (unchanged),
    -- full expanded size (TOGGLE_SIZE = 18)
    local equipmentRow = findActiveRow(list, "equipment")
    assertEqual(equipmentRow.toggle.shown, true, "expanded parent chevron shown")
    assertEqual(equipmentRow.toggle.width, 18, "expanded chevron is full-size (18px)")
    assertEqual(equipmentRow.toggle.height, 18, "expanded chevron is full-size (18px)")
    local expandedTogglePoint = equipmentRow.toggle.points[#equipmentRow.toggle.points]
    assertEqual(expandedTogglePoint[1], "RIGHT", "expanded chevron anchored from row RIGHT")
    assertEqual(expandedTogglePoint[2], -12, "expanded chevron inset unchanged (SCROLLBAR_WIDTH+2)")
    local expandedIconPoint = equipmentRow.iconPlate.points[#equipmentRow.iconPlate.points]
    assertEqual(expandedIconPoint[2], 12,
        "expanded icon leaves a clear gap after the 7px hover navigation strip")

    list:SetCompact(true)

    -- leaf row ("all", no children): chevron stays hidden in compact mode
    local allRow = findActiveRow(list, "all")
    assertEqual(allRow.toggle.shown, false, "compact leaf chevron hidden")

    -- Parent row ("equipment", collapsed, has children): chevron shown beside
    -- the icon in the 48px compact content lane. The remaining 10px (x=48..58)
    -- is dedicated to the transient scrollbar, even while it is faded out.
    equipmentRow = findActiveRow(list, "equipment")
    assertEqual(equipmentRow.toggle.shown, true, "compact parent chevron shown")
    assertEqual(equipmentRow.toggle.mouseEnabled, true, "compact parent chevron clickable")
    assertEqual(equipmentRow.toggle.width, 14, "compact chevron is reduced size (14px)")
    assertEqual(equipmentRow.toggle.height, 14, "compact chevron is reduced size (14px)")

    local iconPoint = equipmentRow.iconPlate.points[#equipmentRow.iconPlate.points]
    assertEqual(iconPoint[2], 12,
        "compact parent icon plate clears the 7px hover navigation strip")
    local togglePoint = equipmentRow.toggle.points[#equipmentRow.toggle.points]
    assertEqual(togglePoint[1], "LEFT", "compact parent chevron anchored from row LEFT")
    assertEqual(togglePoint[2], 32, "compact parent chevron follows the 20px icon plate")
    allRow = findActiveRow(list, "all")
    local leafIconPoint = allRow.iconPlate.points[#allRow.iconPlate.points]
    assertEqual(leafIconPoint[2], 12,
        "compact leaf icon also clears the 7px hover navigation strip")
    list.scrollContent:SetHeight(600)
    list.scrollBar:Update()
    assertTrue(list.scrollBar.frame.shown, "overflow reveals the compact scrollbar")
    local scrollBarLeft = list.collapsedWidth - list.scrollBar.frame.width
    assertEqual(scrollBarLeft, 48, "scrollbar starts after the 48px compact content lane")
    assertTrue(togglePoint[2] + equipmentRow.toggle.width <= scrollBarLeft - 2,
        "visible compact scrollbar leaves a gap after the chevron")

    -- clicking the chevron toggles expansion without touching selection
    assertEqual(list.expandedById.equipment, false, "starts collapsed")
    assertEqual(list.selectionId, "all", "selection before chevron click")
    equipmentRow.toggle.scripts.OnClick(equipmentRow.toggle)
    assertEqual(list.expandedById.equipment, true, "chevron click expands")
    assertEqual(list.selectionId, "all", "chevron click does not change selection")
    assertEqual(visibleIds(list), "heading,all,equipment,weapons,armor,consumables,potions", "children visible after chevron expand")

    equipmentRow = findActiveRow(list, "equipment")
    equipmentRow.toggle.scripts.OnClick(equipmentRow.toggle)
    assertEqual(list.expandedById.equipment, false, "chevron click collapses again")
    assertEqual(list.selectionId, "all", "selection still unchanged after collapse")

    -- returning to expanded mode restores the right-anchored, full-size chevron
    list:SetCompact(false)
    equipmentRow = findActiveRow(list, "equipment")
    local restoredTogglePoint = equipmentRow.toggle.points[#equipmentRow.toggle.points]
    assertEqual(restoredTogglePoint[1], "RIGHT", "chevron re-anchored from row RIGHT after leaving compact")
    assertEqual(restoredTogglePoint[2], -12, "chevron inset restored after leaving compact")
    assertEqual(equipmentRow.toggle.width, 18, "chevron size restored to full 18px after leaving compact")
    assertEqual(equipmentRow.toggle.height, 18, "chevron size restored to full 18px after leaving compact")
end

---------------------------------------------------------------------
-- row-title tooltips: visible labels and compact icon-only rows both use
-- the same pooled row tooltip, including the parent-row chevron hit target
---------------------------------------------------------------------
do
    local parent = CreateFrame("Frame", "Parent")
    local list = AF.CreateTreeList(parent, {fallbackIcon = "Bag_Misc"})
    list.scrollFrame:SetHeight(300)
    list.scrollBar.frame:SetHeight(300)
    list:SetModel(BuildModel())

    local equipmentRow = findActiveRow(list, "equipment")
    equipmentRow.mouseOver = true
    equipmentRow.scripts.OnEnter(equipmentRow)
    local tooltip = tooltipCalls[#tooltipCalls]
    assertEqual(tooltip.kind, "show", "expanded row hover shows a title tooltip")
    assertEqual(tooltip.widget, equipmentRow.tooltipAnchor,
        "expanded tooltip uses the row's visible-edge anchor")
    assertEqual(tooltip.widget.parent, list,
        "tooltip anchor belongs to the non-scrolling tree list")
    assertTrue(not isDescendantOf(tooltip.widget, list.scrollFrame),
        "tooltip anchor is outside the scroll frame so the owned GameTooltip is not clipped")
    assertEqual(tooltip.widget.points[1][2], equipmentRow,
        "non-scrolling tooltip anchor remains positioned from its row")
    assertEqual(tooltip.anchor, "RIGHT", "expanded tooltip opens beside the sidebar")
    assertEqual(tooltip.lines[1], "Equipment", "expanded tooltip uses the row title")
    assertEqual(equipmentRow.tooltipAnchor.accentColor, "accent",
        "tooltip inherits the list accent color")
    assertEqual(equipmentRow.tooltipAnchor.points[1][4], 170,
        "expanded tooltip anchor follows the full row width")

    -- Crossing from the row to its chevron must retain the same tooltip rather
    -- than allowing the row's deferred leave to hide it.
    equipmentRow.mouseOver = false
    equipmentRow.toggle.mouseOver = true
    equipmentRow.scripts.OnLeave(equipmentRow)
    equipmentRow.toggle.scripts.OnEnter(equipmentRow.toggle)
    drain()
    assertEqual(tooltipCalls[#tooltipCalls].kind, "show", "chevron hover keeps the tooltip visible")
    assertEqual(tooltipCalls[#tooltipCalls].widget, equipmentRow.tooltipAnchor,
        "chevron tooltip remains anchored to the parent row")

    equipmentRow.toggle.mouseOver = false
    equipmentRow.toggle.scripts.OnLeave(equipmentRow.toggle)
    drain()
    assertEqual(tooltipCalls[#tooltipCalls].kind, "hide", "leaving a row and chevron hides its tooltip")

    -- The deferred leave must not erase a tooltip a different AF widget
    -- showed after the pointer left this row.
    equipmentRow.mouseOver = true
    equipmentRow.scripts.OnEnter(equipmentRow)
    equipmentRow.mouseOver = false
    equipmentRow.scripts.OnLeave(equipmentRow)
    local otherTooltipOwner = CreateFrame("Frame", "OtherTooltipOwner")
    AF.ShowTooltip(otherTooltipOwner, "RIGHT", 0, 0, {"Other"})
    drain()
    assertEqual(AF.Tooltip:GetOwner(), otherTooltipOwner,
        "deferred row cleanup preserves another widget's newer tooltip")

    list:SetCompact(true)
    equipmentRow = findActiveRow(list, "equipment")
    equipmentRow.mouseOver = true
    equipmentRow.scripts.OnEnter(equipmentRow)
    tooltip = tooltipCalls[#tooltipCalls]
    assertEqual(tooltip.kind, "show", "compact icon row shows a title tooltip")
    assertEqual(tooltip.lines[1], "Equipment", "compact tooltip exposes the hidden row title")
    assertEqual(equipmentRow.label.shown, false, "compact fixture remains icon-only")
    assertEqual(equipmentRow.tooltipAnchor.points[1][2], equipmentRow.iconPlate,
        "compact parent tooltip follows its icon instead of the rail edge")
    assertEqual(equipmentRow.tooltipAnchor.points[1][3], "RIGHT",
        "compact parent tooltip opens immediately after its icon target")
    assertEqual(equipmentRow.tooltipAnchor.points[1][4], 0,
        "compact parent tooltip anchor adds no extra rail-width gap")

    equipmentRow.mouseOver = false
    equipmentRow.toggle.mouseOver = true
    equipmentRow.toggle.scripts.OnEnter(equipmentRow.toggle)
    assertEqual(equipmentRow.tooltipAnchor.points[1][2], equipmentRow.toggle,
        "compact chevron hover moves the tooltip next to the chevron target")
    equipmentRow.toggle.mouseOver = false

    local compactAllRow = findActiveRow(list, "all")
    compactAllRow.mouseOver = true
    compactAllRow.scripts.OnEnter(compactAllRow)
    tooltip = tooltipCalls[#tooltipCalls]
    assertEqual(tooltip.lines[1], "All", "compact leaf tooltip exposes its hidden row title")
    assertEqual(compactAllRow.tooltipAnchor.points[1][2], compactAllRow.iconPlate,
        "compact leaf tooltip follows the icon instead of the rail edge")
    assertEqual(compactAllRow.tooltipAnchor.points[1][3], "RIGHT",
        "compact leaf tooltip opens immediately after its icon target")
    assertEqual(compactAllRow.tooltipAnchor.points[1][4], 0,
        "compact leaf tooltip anchor adds no extra rail-width gap")

    -- A pooled row can be rebound or removed while its tooltip is visible.
    -- It must release its ownership so a former row title never survives a
    -- model rebuild or a hidden list.
    list:SetModel({{id = "all", label = "All", icon = "Bag_All"}})
    assertEqual(tooltipCalls[#tooltipCalls].kind, "hide", "model rebuild clears a stale pooled-row tooltip")

    local reboundAllRow = findActiveRow(list, "all")
    reboundAllRow.mouseOver = true
    reboundAllRow.scripts.OnEnter(reboundAllRow)
    list:Hide()
    assertEqual(tooltipCalls[#tooltipCalls].kind, "hide", "hiding the list clears its row tooltip")
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

    -- ten rows: content height 10*28 + 9*2 = 298, range 248
    local bigModel = {}
    for index = 1, 10 do
        bigModel[index] = {id = "row" .. index, label = "Row " .. index}
    end
    list:SetModel(bigModel)
    assertEqual(list.scrollContent.height, 298, "content height")
    assertEqual(bar.frame.shown, true, "bar revealed when overflow appears")
    assertEqual(bar.frame.mouseEnabled, true, "revealed bar accepts mouse")
    assertEqual(bar.frame.minMax[2], 248, "slider range")
    assertEqual(bar.thumb.height, 20, "thumb clamped to min height")

    -- fade after inactivity: mouse is elsewhere
    drain()
    assertEqual(bar.frame.shown, false, "bar fades after inactivity")
    assertEqual(bar.frame.mouseEnabled, false, "faded bar has mouse disabled")

    -- wheel scrolls and reveals: scrollStep = (rowHeight(28) + ROW_SPACING(2)) * 3 = 90
    list.scrollFrame.scripts.OnMouseWheel(list.scrollFrame, -1)
    assertEqual(list.scrollFrame:GetVerticalScroll(), 90, "wheel step applied")
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
    assertEqual(list.scrollFrame:GetVerticalScroll(), 248, "slider value clamped to range")
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
    assertEqual(list.scrollFrame:GetVerticalScroll(), 248, "offset clamped to range")

    -- one offset across compact/expanded presentation flips
    list:SetCompact(true)
    assertEqual(list.scrollFrame:GetVerticalScroll(), 248, "offset preserved entering compact")
    list:SetCompact(false)
    assertEqual(list.scrollFrame:GetVerticalScroll(), 248, "offset preserved leaving compact")

    -- shrinking content re-clamps the shared offset
    local smallModel = {}
    for index = 1, 5 do
        smallModel[index] = {id = "row" .. index, label = "Row " .. index}
    end
    list:SetModel(smallModel)
    -- content height 5*28 + 4*2 = 148, range 98
    assertEqual(list.scrollFrame:GetVerticalScroll(), 98, "offset re-clamped after shrink")
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

---------------------------------------------------------------------
-- tint removal: textureTint is fully deleted, and icon plates use AF's
-- lightweight one-fill/four-edge backdrop, never NineSlice/BackdropTemplate
---------------------------------------------------------------------
do
    local file = assert(io.open("Widgets/TreeList.lua", "r"))
    local source = file:read("*a")
    file:close()

    assertNotContains(source, "textureTint", "textureTint option fully deleted")
    assertNotContains(source, "SetDesaturated", "no desaturate treatment anywhere in the widget")
    assertNotContains(source, "NineSlice", "no NineSlice backdrop path")
    assertNotContains(source, "BackdropTemplate", "no BackdropTemplate backdrop path")
end

---------------------------------------------------------------------
-- rail hover auto-hide machinery is fully removed (manual collapse only)
---------------------------------------------------------------------
do
    local file = assert(io.open("Widgets/TreeList.lua", "r"))
    local source = file:read("*a")
    file:close()

    assertNotContains(source, "leaveGeneration", "leave-generation debouncing removed")
    assertNotContains(source, "hoverExpand", "hoverExpanded presentation state removed")
    assertNotContains(source, "RailPointerEnter", "rail pointer-enter wiring removed")
    assertNotContains(source, "RailPointerLeave", "rail pointer-leave wiring removed")
    assertNotContains(source, "ExpandRail", "ExpandRail helper removed")
    assertNotContains(source, "CollapseRail", "CollapseRail helper removed")
    assertNotContains(source, "AutoHide", "SetAutoHide/GetAutoHide/ToggleAutoHide/SetOnAutoHideChanged removed")

    -- the rail's own two AnimatedResize calls (hover expand/collapse width
    -- tweens) are gone; the tree list's own content-height animation and the
    -- row-collapse highlight animation are untouched, so exactly two
    -- AF.AnimatedResize call sites remain in the file
    local count, start = 0, 1
    while true do
        local from = source:find("AF.AnimatedResize(", start, true)
        if not from then break end
        count = count + 1
        start = from + 1
    end
    assertEqual(count, 2, "only the tree list's own AnimatedResize call sites remain")
end

print("tree list tests passed")
