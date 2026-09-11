local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local corePrefix = "Interface\\AddOns\\AbstractFramework\\Media\\Fonts\\"
local packPrefix = "Interface\\AddOns\\AbstractFramework_Media\\Media\\Fonts\\"
local optionalFonts = {
    {name = "Noto_AP", file = "NotoSansCJKsc_AP.ttf", latinFile = "NotoSansCJKsc_AP_Latin.ttf"},
    {name = "Noto_Dolphin", file = "NotoSansCJKsc_Dolphin.ttf"},
    {name = "Unifont", file = "Unifont.otf"},
}

-- The media pack should need neither frames nor delayed registration.
CreateFrame = function()
    error("font media must not create an event or polling frame")
end

local function createFontObject(name)
    local font = {
        SetTextColor = function() end,
        SetShadowColor = function() end,
        SetShadowOffset = function() end,
        SetJustifyH = function() end,
        SetJustifyV = function() end,
        SetText = function() end,
    }
    function font:SetFont(file, size, flags)
        self.file, self.size, self.flags = file, size, flags
    end
    function font:GetFont()
        return self.file, self.size, self.flags
    end
    function font:SetFontObject(object)
        self.fontObject = object
    end
    if name then _G[name] = font end
    return font
end

local function loadCore(clientFont, isEnglish)
    local media = {font = {}, statusbar = {}}
    local LSM = {}

    function LSM:Register(kind, name, file)
        assertEqual(media[kind][name], nil, "one registration per media name")
        media[kind][name] = file
    end

    function LSM:IsValid(kind, name)
        return media[kind][name] ~= nil
    end

    function LSM:Fetch(kind, name)
        assert(media[kind][name], "missing media must be checked before Fetch")
        return media[kind][name]
    end

    function LSM:List(kind)
        local names = {}
        for name in pairs(media[kind]) do
            names[#names + 1] = name
        end
        table.sort(names)
        return names
    end

    function LSM:HashTable(kind)
        return media[kind]
    end

    LOCALE_enUS = isEnglish
    GameFontNormal = {
        GetFont = function() return clientFont, 13, "" end,
    }
    ChatFontNormal = {
        GetFont = function() return "Fonts\\CLIENT_CHAT.TTF", 13, "" end,
    }
    GameTooltipText = {
        GetFont = function() return "Fonts\\CLIENT_TOOLTIP.TTF", 13, "" end,
    }
    UNIT_NAME_FONT_CHINESE = "Fonts\\CLIENT_CHINESE.TTF"
    CreateFont = createFontObject
    CreateObjectPool = function() return {} end
    Mixin = function(target, mixin)
        for key, value in pairs(mixin) do target[key] = value end
    end

    local AF = {
        Libs = {LSM = LSM},
        L = setmetatable({}, {__index = function(_, key) return key end}),
        IsBlank = function(value) return value == nil or value == "" end,
        GetColorRGB = function() return 1, 1, 1 end,
        CreateObjectPool = function() return {} end,
        ColorFontString = function() end,
        AddToPixelUpdater_OnShow = function() end,
    }
    _G.AbstractFramework = AF
    assert(loadfile("Media/Media.lua"))("AbstractFramework", AF)
    assert(loadfile("Media/SharedMedia.lua"))("AbstractFramework", AF)
    assert(loadfile("Widgets/Font.lua"))("AbstractFramework", AF)
    assert(loadfile("Widgets/FontString.lua"))("AbstractFramework", AF)

    -- A consumer may replace the global font after framework startup. Missing
    -- media must still resolve to the original, locale-appropriate client font.
    GameFontNormal.GetFont = function() return "unavailable-replacement.ttf" end
    return AF, LSM
end

local function assertSavedSelections(AF, expectedPrefix, clientFont, isEnglish)
    local renderedFont
    local fs = {
        SetFont = function(_, font) renderedFont = font end,
        SetShadowOffset = function() end,
        SetShadowColor = function() end,
    }
    local parent = {CreateFontString = function() return createFontObject() end}

    for _, font in ipairs(optionalFonts) do
        local expected = expectedPrefix and expectedPrefix .. font.file
            or isEnglish and font.latinFile and corePrefix .. font.latinFile
            or clientFont
        local savedSelections = {
            font.name,
            corePrefix .. font.file,
            packPrefix .. font.file,
            ((corePrefix .. font.file):upper():gsub("\\", "/")),
        }
        for _, saved in ipairs(savedSelections) do
            assertEqual(AF.LSM_GetFont(saved), expected, "saved font resolves: " .. saved)
            local profileFont = {saved, 16, "outline", true}
            AF.SetFont(fs, profileFont)
            assertEqual(renderedFont, expected, "SetFont uses resolved media")
            assertEqual(profileFont[1], saved, "saved choice is preserved")

            local created = AF.CreateFont(nil, "TestOptionalFont", saved, 16, "OUTLINE")
            assertEqual(created:GetFont(), expected, "CreateFont resolves saved font")
            assertEqual(created.size, 16, "CreateFont retains explicit size")
            assertEqual(created.flags, "OUTLINE", "CreateFont retains explicit flags")
            assertEqual(AF.GetFontProps(saved), expected, "GetFontProps resolves saved font")
            local fontString = AF.CreateFontString(parent, "Example", nil, saved)
            assertEqual(fontString:GetFont(), expected, "CreateFontString resolves optional name/path")

            AF.UpdateBaseFont(saved)
            assertEqual(AF.GetFontProps("normal"), expected, "UpdateBaseFont resolves saved font")
            assertEqual(AF.GetFontProps("chat"), expected, "explicit base font applies to chat")
            assertEqual(AF_FONT_TOOLTIP:GetFont(), expected, "explicit base font applies to tooltips")
            assertEqual(AF.CreateFont(nil, "TestInheritedFont"):GetFont(), expected, "nil CreateFont inherits configured base")
        end
        assertEqual(AF.GetFont(font.file), expected, "legacy helper filename")
        assertEqual(AF.GetFont(font.file, "AbstractFramework"), expected, "explicit core helper filename")
        assertEqual(
            AF.GetFont(font.file, "AnotherAddon"),
            "Interface\\AddOns\\AnotherAddon\\Media\\Fonts\\" .. font.file,
            "other addons retain ownership of same-named files"
        )
    end

    assertEqual(AF.LSM_GetFont(nil), clientFont, "nil font fallback")
    assertEqual(AF.LSM_GetFont("MissingFont"), clientFont, "unknown name fallback")
    assertEqual(AF.LSM_GetFont("Fonts\\Custom.ttf"), "Fonts\\Custom.ttf", "custom TrueType path")
    assertEqual(AF.LSM_GetFont("Fonts\\Custom.otf"), "Fonts\\Custom.otf", "custom OpenType path")
    assertEqual(AF.LSM_GetFont("Fonts\\CustomXttf"), clientFont, "extension needs a dot")

    AF.UpdateBaseFont("Fonts\\Custom.ttf")
    assertEqual(AF.CreateFont(nil, "TestCustomBaseFont"):GetFont(), "Fonts\\Custom.ttf", "nil CreateFont retains custom base")
    local latinFont = AF.CreateFont(nil, "TestLatinFont", "Dolphin")
    assertEqual(latinFont:GetFont(), corePrefix .. "Dolphin.ttf", "CreateFont retains installed Latin font")
    AF.UpdateBaseFont(nil)
    assertEqual(AF.GetFontProps("normal"), "unavailable-replacement.ttf", "nil UpdateBaseFont retains current normal-font semantics")
    assertEqual(AF.GetFontProps("chat"), "Fonts\\CLIENT_CHAT.TTF", "nil UpdateBaseFont restores separate chat font")
    assertEqual(AF_FONT_TOOLTIP:GetFont(), "Fonts\\CLIENT_TOOLTIP.TTF", "nil UpdateBaseFont restores separate tooltip font")
    assertEqual(AF.CreateFontString(parent, "Default").fontObject, "AF_FONT_NORMAL", "nil font string keeps default object")
    assertEqual(AF.CreateFontString(parent, "Named", nil, "GameFontNormal").fontObject, "GameFontNormal", "named font object is preserved")
    local customObject = createFontObject()
    assertEqual(AF.CreateFontString(parent, "Object", nil, customObject).fontObject, customObject, "font object value is preserved")
end

-- These are test fixtures for differing client-localized UI fonts, not a
-- claim that every game installation exposes the same font filenames.
for _, client in ipairs({
    {font = "Fonts\\FRIZQT__.TTF", isEnglish = true},
    {font = "Fonts\\ARKai_T.ttf", isEnglish = false},
    {font = "Fonts\\2002.TTF", isEnglish = false},
    {font = "Fonts\\FRIZQT___CYR.TTF", isEnglish = false},
}) do
    local clientFont, isEnglish = client.font, client.isEnglish
    local AF, LSM = loadCore(clientFont, isEnglish)
    for _, font in ipairs(optionalFonts) do
        assertEqual(LSM:IsValid("font", font.name), false, "core omits optional font registrations")
    end
    assertEqual(LSM:IsValid("font", "Dolphin"), true, "small Latin Dolphin remains")
    assertEqual(LSM:IsValid("font", "Accidental Presidency"), true, "small Latin AP remains")
    assertEqual(AF.LSM_GetFont("Noto_AP_Latin"), corePrefix .. "NotoSansCJKsc_AP_Latin.ttf", "slim Noto_AP is registered in core")
    local latinFile = assert(io.open("Media/Fonts/NotoSansCJKsc_AP_Latin.ttf", "rb"))
    latinFile:close()
    assertEqual(#AF.LSM_GetFontDropdownItems(), 7, "core dropdown contains only installed fonts")
    assertSavedSelections(AF, nil, clientFont, isEnglish)

    assert(loadfile("OptionalMedia/AbstractFramework_Media/Register.lua"))("AbstractFramework_Media", {})
    assertEqual(#AF.LSM_GetFontDropdownItems(), 10, "installed pack exposes all three optional fonts")
    assertSavedSelections(AF, packPrefix, clientFont, isEnglish)

    for _, font in ipairs(optionalFonts) do
        assertEqual(LSM:Fetch("font", font.name), packPrefix .. font.file, "pack uses its own media path")
        local file = assert(io.open("OptionalMedia/AbstractFramework_Media/Media/Fonts/" .. font.file, "rb"))
        file:close()
        assertEqual(io.open("Media/Fonts/" .. font.file, "rb"), nil, "core no longer carries optional binary")
    end

    -- A UI reload with the pack disabled creates a fresh registry. Reinstalling
    -- on the next load resolves the same saved selections to the pack again.
    AF = loadCore(clientFont, isEnglish)
    assertSavedSelections(AF, nil, clientFont, isEnglish)
    AF = loadCore(clientFont, isEnglish)
    assert(loadfile("OptionalMedia/AbstractFramework_Media/Register.lua"))("AbstractFramework_Media", {})
    assertSavedSelections(AF, packPrefix, clientFont, isEnglish)
end

print("optional media font tests passed")
