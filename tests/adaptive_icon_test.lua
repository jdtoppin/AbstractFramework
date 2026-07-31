local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(message, tostring(expected), tostring(actual)), 2)
    end
end

-- Retail 12.1 exposes VectorGraphics and also lets ordinary Texture regions
-- load SVG files. Use the new method as the client capability marker.
UIParent = {
    CreateVectorGraphics = function() end,
}

local AF = {
    IsBlank = function(value)
        return value == nil or value == ""
    end,
}

local mediaChunk = assert(loadfile("Media/Media.lua"))
mediaChunk("AbstractFramework", AF)

assertEqual(AF.hasVectorGraphics, true, "12.1 VectorGraphics capability")
assertEqual(AF.hasSVGIcons, true, "Texture SVG capability")
assertEqual(
    AF.GetAdaptiveIcon("Housing_All"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Housing_All.svg",
    "12.1 adaptive Texture path"
)

local loadedPath
local texture = {
    SetTexture = function(_, path)
        loadedPath = path
        return true
    end,
}

assertEqual(AF.SetHousingIcon(texture, "Housing_All"), true, "Housing Texture load")
assertEqual(
    loadedPath,
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Housing_All.svg",
    "12.1 Housing Texture path"
)

local loadedPaths = {}
local fallbackTexture = {
    SetTexture = function(_, path)
        loadedPaths[#loadedPaths + 1] = path
        return path:sub(-4) == ".tga"
    end,
}

assertEqual(AF.SetAdaptiveIcon(fallbackTexture, "View_ZoomIn"), true, "raster fallback load")
assertEqual(
    loadedPaths[1],
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\View_ZoomIn.svg",
    "raster fallback SVG attempt"
)
assertEqual(
    loadedPaths[2],
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\View_ZoomIn.tga",
    "raster fallback path"
)

UIParent = {}

local rasterAF = {
    IsBlank = AF.IsBlank,
}

mediaChunk("AbstractFramework", rasterAF)

assertEqual(rasterAF.hasVectorGraphics, false, "12.0 VectorGraphics capability")
assertEqual(rasterAF.hasSVGIcons, false, "12.0 Texture SVG capability")
assertEqual(
    rasterAF.GetAdaptiveIcon("Housing_All"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Housing_All.tga",
    "12.0 adaptive Texture path"
)

print("adaptive icon tests passed")
