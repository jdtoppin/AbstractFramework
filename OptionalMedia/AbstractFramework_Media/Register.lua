local addonName = ...
local AF = _G.AbstractFramework
local LSM = AF.Libs.LSM

-- Keep the existing names so saved selections restore when this pack loads.
LSM:Register("font", "Noto_AP", AF.GetFont("NotoSansCJKsc_AP", addonName), 255)
LSM:Register("font", "Noto_Dolphin", AF.GetFont("NotoSansCJKsc_Dolphin", addonName), 255)
LSM:Register("font", "Unifont", AF.GetFont("Unifont.otf", addonName), 255)
