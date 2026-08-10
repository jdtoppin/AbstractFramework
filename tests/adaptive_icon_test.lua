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
assertEqual(AF.hasSVGIcons, true, "12.1 SVG asset capability")
assertEqual(AF.hasTextureSVGIcons, false, "12.1 Texture SVG safety gate")
assertEqual(AF.hasLockIcons, true, "shared lock icon capability")
assertEqual(AF.hasBagIcons, true, "shared bag icon capability")
assertEqual(
    AF.GetAdaptiveIcon("Housing_All"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Housing_All.tga",
    "12.1 adaptive Texture path"
)
assertEqual(
    AF.GetAdaptiveIcon("Lock"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Lock.tga",
    "12.1 lock Texture raster path"
)
assertEqual(
    AF.GetAdaptiveIcon("Unlock"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Unlock.tga",
    "12.1 unlock Texture raster path"
)
assertEqual(
    AF.GetAdaptiveIcon("Bag_Misc"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Bag_Misc.tga",
    "12.1 bag Texture raster path"
)
assertEqual(
    AF.GetAdaptiveIcon("Bag_All"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Bag_All.tga",
    "12.1 bag Texture raster path"
)
assertEqual(
    AF.GetAdaptiveIcon("Bag_Empty"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Bag_Empty.tga",
    "12.1 bag Texture raster path"
)
assertEqual(
    AF.GetAdaptiveIcon("Bag_IndividualBags"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Bag_IndividualBags.tga",
    "12.1 bag Texture raster path"
)
assertEqual(
    AF.GetAdaptiveIcon("Bag_Bag"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Bag_Bag.tga",
    "12.1 equipment-bag Texture raster path"
)
assertEqual(
    AF.GetAdaptiveIcon("Bag_ProfessionTool"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Bag_ProfessionTool.tga",
    "12.1 profession-tool Texture raster path"
)
assertEqual(
    AF.GetAdaptiveIcon("Bag_ProfessionEquipment"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Bag_ProfessionEquipment.tga",
    "12.1 profession-equipment Texture raster path"
)
assertEqual(
    AF.GetAdaptiveIcon("Bag_Miscellaneous"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Bag_Miscellaneous.tga",
    "12.1 miscellaneous Texture raster path"
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
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Housing_All.tga",
    "12.1 Housing Texture path"
)

local loadedPaths = {}
local viewTexture = {
    SetTexture = function(_, path)
        loadedPaths[#loadedPaths + 1] = path
        return true
    end,
}

assertEqual(AF.SetAdaptiveIcon(viewTexture, "View_ZoomIn"), true, "view Texture load")
assertEqual(
    loadedPaths[1],
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\View_ZoomIn.tga",
    "view Texture raster path"
)
assertEqual(#loadedPaths, 1, "single Texture load attempt")

UIParent = {}

local rasterAF = {
    IsBlank = AF.IsBlank,
}

mediaChunk("AbstractFramework", rasterAF)

assertEqual(rasterAF.hasVectorGraphics, false, "12.0 VectorGraphics capability")
assertEqual(rasterAF.hasSVGIcons, false, "12.0 SVG asset capability")
assertEqual(rasterAF.hasTextureSVGIcons, false, "12.0 Texture SVG safety gate")
assertEqual(rasterAF.hasLockIcons, true, "12.0 shared lock icon capability")
assertEqual(rasterAF.hasBagIcons, true, "12.0 shared bag icon capability")
assertEqual(
    rasterAF.GetAdaptiveIcon("Housing_All"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Housing_All.tga",
    "12.0 adaptive Texture path"
)
assertEqual(
    rasterAF.GetAdaptiveIcon("Lock"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Lock.tga",
    "12.0 lock Texture raster path"
)
assertEqual(
    rasterAF.GetAdaptiveIcon("Unlock"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Unlock.tga",
    "12.0 unlock Texture raster path"
)
assertEqual(
    rasterAF.GetAdaptiveIcon("Bag_Misc"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Bag_Misc.tga",
    "12.0 bag Texture raster path"
)
assertEqual(
    rasterAF.GetAdaptiveIcon("Bag_All"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Bag_All.tga",
    "12.0 bag Texture raster path"
)
assertEqual(
    rasterAF.GetAdaptiveIcon("Bag_Empty"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Bag_Empty.tga",
    "12.0 bag Texture raster path"
)
assertEqual(
    rasterAF.GetAdaptiveIcon("Bag_IndividualBags"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Bag_IndividualBags.tga",
    "12.0 bag Texture raster path"
)
assertEqual(
    rasterAF.GetAdaptiveIcon("Bag_Bag"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Bag_Bag.tga",
    "12.0 equipment-bag Texture raster path"
)
assertEqual(
    rasterAF.GetAdaptiveIcon("Bag_ProfessionTool"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Bag_ProfessionTool.tga",
    "12.0 profession-tool Texture raster path"
)
assertEqual(
    rasterAF.GetAdaptiveIcon("Bag_ProfessionEquipment"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Bag_ProfessionEquipment.tga",
    "12.0 profession-equipment Texture raster path"
)
assertEqual(
    rasterAF.GetAdaptiveIcon("Bag_Miscellaneous"),
    "Interface\\AddOns\\AbstractFramework\\Media\\Icons\\Bag_Miscellaneous.tga",
    "12.0 miscellaneous Texture raster path"
)

print("adaptive icon tests passed")
