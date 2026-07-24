---@class AbstractFramework
---@field ItemLevel AF_ItemLevel
local AF = select(2, ...)
local F = AF.funcs

AF.ItemLevel = {}

---@class AF_ItemLevel
local IL = AF.ItemLevel

---------------------------------------------------------------------
-- retail
---------------------------------------------------------------------
if AF.isRetail then
    local CanInspect = _G.CanInspect
    local GetAverageItemLevel = _G.GetAverageItemLevel
    local GetTime = _G.GetTime
    local NotifyInspect = _G.NotifyInspect
    local UnitGUID = _G.UnitGUID
    local After = C_Timer.After
    local GetInspectItemLevel = C_PaperDollInfo.GetInspectItemLevel

    local INSPECT_REQUEST_INTERVAL = 2

    local cache = {}
    local pendingUnit
    local pendingGUID
    local queuedUnit
    local retryScheduled
    local lastRequest

    -- Retail 12.0.7 and 12.1 expose the inspected equipped item level
    -- directly. Keep identity matching inside C by accepting only a
    -- caller-owned, non-secret unit token such as "mouseover".
    --
    -- 12.0.7:
    -- Gethe/wow-ui-source@4383ced
    -- Blizzard_APIDocumentationGenerated/PaperDollInfoDocumentation.lua
    -- 12.1:
    -- Gethe/wow-ui-source@d3915c7
    -- Blizzard_APIDocumentationGenerated/PaperDollInfoDocumentation.lua
    local function IsNonSecretString(value)
        return F.isValueNonSecret(value) and type(value) == "string"
    end

    local function GetItemLevel(unit)
        if not IsNonSecretString(unit) then return end

        local itemLevel = GetInspectItemLevel(unit)
        if itemLevel > 0 then
            return itemLevel
        end
    end

    local function GetSelfItemLevel()
        local _, equippedItemLevel = GetAverageItemLevel()
        if F.isValueNonSecret(equippedItemLevel)
            and type(equippedItemLevel) == "number"
            and equippedItemLevel > 0
        then
            return equippedItemLevel
        end
    end

    local function GetNonSecretGUID(unit)
        local guid = UnitGUID(unit)
        if IsNonSecretString(guid) then
            return guid
        end
    end

    ---Returns the equipped item level currently available for a non-secret
    ---unit token. This function does not initiate an inspect request.
    ---@param unit string
    ---@return number? itemLevel
    function IL.Get(unit)
        return GetItemLevel(unit)
    end

    local function IsInspectChannelBusy()
        local inspectFrame = _G.InspectFrame
        if inspectFrame and inspectFrame:IsShown() then
            return true
        end

        local playerSpellsFrame = _G.PlayerSpellsFrame
        return playerSpellsFrame and playerSpellsFrame:IsInspecting()
    end

    local function StoreCache(unit, guid, itemLevel)
        if not IsNonSecretString(guid) then return end

        cache[guid] = {
            lastUpdate = GetTime(),
            itemLevel = itemLevel,
        }
        AF.Fire("AF_UNIT_ITEM_LEVEL_UPDATE", unit, guid)
    end

    local Request
    local function QueueRetry(unit, delay)
        queuedUnit = unit
        if retryScheduled then return end

        retryScheduled = true
        After(delay, function()
            retryScheduled = nil

            local retryUnit = queuedUnit
            queuedUnit = nil
            if not retryUnit then return end

            local itemLevel = Request(retryUnit)
            if itemLevel then
                AF.Fire("AF_UNIT_ITEM_LEVEL_READY", retryUnit, itemLevel)
            end
        end)
    end

    ---Returns the equipped item level when it is already available, otherwise
    ---requests it through Blizzard's serialized inspect channel. Repeated
    ---calls replace the one queued retry with the latest non-secret unit token.
    ---@param unit string
    ---@return number? itemLevel
    function Request(unit)
        local itemLevel = GetItemLevel(unit)
        if itemLevel then
            if pendingUnit == unit then
                pendingUnit = nil
                pendingGUID = nil
            end
            if queuedUnit == unit then
                queuedUnit = nil
            end
            return itemLevel
        end
        if not IsNonSecretString(unit) or IsInspectChannelBusy() or not CanInspect(unit) then return end

        local now = GetTime()
        if lastRequest and now - lastRequest < INSPECT_REQUEST_INTERVAL then
            QueueRetry(unit, INSPECT_REQUEST_INTERVAL - (now - lastRequest))
            return
        end

        queuedUnit = nil
        pendingUnit = unit
        pendingGUID = GetNonSecretGUID(unit)
        lastRequest = now
        NotifyInspect(unit)
    end

    function IL.Request(unit)
        return Request(unit)
    end

    local function INSPECT_READY(_, _, guid)
        local unit = pendingUnit
        if not unit then return end
        local requestGUID = pendingGUID

        local itemLevel = GetItemLevel(unit)
        if not itemLevel then return end

        pendingUnit = nil
        pendingGUID = nil
        if queuedUnit == unit then
            queuedUnit = nil
        end

        if requestGUID and IsNonSecretString(guid) then
            local currentGUID = GetNonSecretGUID(unit)
            if currentGUID and requestGUID == guid and currentGUID == guid then
                StoreCache(unit, guid, itemLevel)
            end
        end
        AF.Fire("AF_UNIT_ITEM_LEVEL_READY", unit, itemLevel)
    end
    AF:RegisterEvent("INSPECT_READY", INSPECT_READY)

    -- Compatibility entry points for existing consumers. New Retail consumers
    -- can avoid GUID handling by using Request and AF_UNIT_ITEM_LEVEL_READY.
    function IL.UpdateCache(unit)
        if IsNonSecretString(unit) and unit == "player" then
            local itemLevel = GetSelfItemLevel()
            if itemLevel then
                StoreCache(unit, AF.player and AF.player.guid, itemLevel)
            end
            return itemLevel
        end

        local itemLevel = IL.Request(unit)
        if itemLevel then
            local guid = GetNonSecretGUID(unit)
            if guid then
                StoreCache(unit, guid, itemLevel)
            end
        end
        return itemLevel
    end

    ---@param guid string
    ---@return number? itemLevel
    ---@return number? timeSinceLastUpdate
    function IL.GetCache(guid)
        if not IsNonSecretString(guid) then return end

        local playerGUID = AF.player and AF.player.guid
        if IsNonSecretString(playerGUID) and guid == playerGUID then
            local itemLevel = GetSelfItemLevel()
            if itemLevel then
                cache[guid] = {
                    lastUpdate = GetTime(),
                    itemLevel = itemLevel,
                }
                return itemLevel, 0
            end
        end

        local cached = cache[guid]
        if cached then
            return cached.itemLevel, GetTime() - cached.lastUpdate
        end
    end

    return
end

---------------------------------------------------------------------
-- classic
---------------------------------------------------------------------
local cache = {}

local CalcItemLevel
local UnitGUID = UnitGUID
local UnitExists = UnitExists
local GetTime = GetTime
local CanInspect = CanInspect
local GetAverageItemLevel = GetAverageItemLevel
local GetInventoryItemLink = GetInventoryItemLink
local GetItemInfo = C_Item.GetItemInfo
local GetTooltipData = C_TooltipInfo and C_TooltipInfo.GetInventoryItem

---------------------------------------------------------------------
-- update
---------------------------------------------------------------------
if GetTooltipData then
    local SLOTS = {
        INVSLOT_HEAD,
        INVSLOT_NECK,
        INVSLOT_SHOULDER,
        INVSLOT_CHEST,
        INVSLOT_WAIST,
        INVSLOT_LEGS,
        INVSLOT_FEET,
        INVSLOT_WRIST,
        INVSLOT_HAND,
        INVSLOT_FINGER1,
        INVSLOT_FINGER2,
        INVSLOT_TRINKET1,
        INVSLOT_TRINKET2,
        INVSLOT_BACK,
        INVSLOT_MAINHAND,
        INVSLOT_OFFHAND,
    }

    local NUM_SLOTS = 16

    local TWO_HANDED = {
        INVTYPE_2HWEAPON = true,
        INVTYPE_RANGED = true,
        INVTYPE_RANGEDRIGHT = true,
    }

    local ITEM_LEVEL_PATTERN = ITEM_LEVEL:gsub("%%d", "(%%d+)")
    local ITEM_LEVEL_ALT_PATTERN = ITEM_LEVEL_ALT:gsub("%%d %(%%d%)", "%%d+ %%((%%d+)%%)")


    local function GetSlotInfo(unit, slot)
        local item = GetInventoryItemLink(unit, slot)
        if item then
            local _, _, quality, _, _, _, _, _, equipLoc, _, _, classId, subClassId = C_Item.GetItemInfo(item)
            return quality, equipLoc, classId, subClassId
        end
    end

    local function GetSlotLevel(data)
        if not data then
            return 0
        end

        local line = data.lines[1]
        local text = line and line.leftText
        if not text or text == RETRIEVING_ITEM_INFO then
            return nil
        end

        for i = 2, #data.lines do
            local tooltipLine = data.lines[i]
            local tooltipText = tooltipLine.leftText
            if tooltipText and tooltipText ~= "" then
                tooltipText = tooltipText:match(ITEM_LEVEL_PATTERN) or tooltipText:match(ITEM_LEVEL_ALT_PATTERN)
                if tooltipText then
                    return tonumber(tooltipText)
                end
            end
        end
    end

    local slotData = {}

    CalcItemLevel = function(unit, guid)
        if slotData[guid] then return end
        slotData[guid] = {}

        -- print("Calculating item level for", unit, guid)

        local spec = GetInspectSpecialization(unit)

        for _, slot in pairs(SLOTS) do
            slotData[guid][slot] = GetTooltipData(unit, slot)
        end

        local mainLevel = GetSlotLevel(slotData[guid][INVSLOT_MAINHAND])
        local offLevel = GetSlotLevel(slotData[guid][INVSLOT_OFFHAND])
        slotData[guid][INVSLOT_MAINHAND] = nil
        slotData[guid][INVSLOT_OFFHAND] = nil

        -- print(mainLevel, offLevel)
        if mainLevel and offLevel then
            local total = 0
            local mainQuality, mainEquipLoc, mainClassId, mainSubClassId = GetSlotInfo(unit, INVSLOT_MAINHAND)
            if spec ~= 72 and mainEquipLoc and (mainQuality == Enum.ItemQuality.Artifact or TWO_HANDED[mainEquipLoc])
                and not (mainClassId == 2 and mainSubClassId == 19) then -- 2:武器 19:魔杖
                total = total + max(mainLevel, offLevel) * 2
            else
                total = total + mainLevel + offLevel
            end

            for _, data in pairs(slotData[guid]) do
                local slot = GetSlotLevel(data)
                -- print(data.hyperlink, slot)
                if slot then
                    total = total + slot
                else
                    total = nil
                    break
                end
            end

            if total and total ~= 0 then
                cache[guid] = {
                    lastUpdate = GetTime(),
                    itemLevel = AF.RoundToDecimal(total / NUM_SLOTS, 1)
                }
                AF.Fire("AF_UNIT_ITEM_LEVEL_UPDATE", unit, guid)
            end
        end

        slotData[guid] = nil

        if not cache[guid] and UnitExists(unit) and UnitGUID(unit) == guid then
            -- print("RETRY", unit, guid)
            AF.DelayedInvoke(0.2, CalcItemLevel, unit, guid)
        end
    end

else
    local GetDetailedItemLevelInfo = GetDetailedItemLevelInfo or C_Item.GetDetailedItemLevelInfo

    local SLOTS = {
        INVSLOT_HEAD,
        INVSLOT_NECK,
        INVSLOT_SHOULDER,
        INVSLOT_CHEST,
        INVSLOT_WAIST,
        INVSLOT_LEGS,
        INVSLOT_FEET,
        INVSLOT_WRIST,
        INVSLOT_HAND,
        INVSLOT_FINGER1,
        INVSLOT_FINGER2,
        INVSLOT_TRINKET1,
        INVSLOT_TRINKET2,
        INVSLOT_BACK,
        INVSLOT_RANGED,
    }

    local NUM_SLOTS

    if AF.isMists then
        NUM_SLOTS = 16
    else
        tinsert(SLOTS, INVSLOT_RANGED)
        NUM_SLOTS = 17
    end

    local function GetSlotLevel(unit, slot)
        local link = GetInventoryItemLink(unit, slot)
        local level = 0
        if link then
            level = GetDetailedItemLevelInfo(link)
        end
        return level
    end

    -- REVIEW:
    CalcItemLevel = function(unit, guid)
        C_Timer.After(0.1, function()
            local mainLevel, offLevel = 0, 0
            local mainEquipLoc

            local mainLink = GetInventoryItemLink(unit, INVSLOT_MAINHAND)
            if mainLink then
                mainLevel = GetDetailedItemLevelInfo(mainLink)
                mainEquipLoc = select(9, GetItemInfo(mainLink))
            end

            local offLink = GetInventoryItemLink(unit, INVSLOT_OFFHAND)
            if offLink then
                offLevel = GetDetailedItemLevelInfo(offLink)
            end

            if mainLevel and offLevel then
                local total = 0
                if mainEquipLoc and mainEquipLoc == INVTYPE_2HWEAPON then
                    total = total + mainLevel * 2
                else
                    total = total + mainLevel + offLevel
                end

                for _, slot in pairs(SLOTS) do
                    slot = GetSlotLevel(unit, slot)
                    total = total + slot
                end

                if total and total ~= 0 then
                    cache[guid] = {
                        lastUpdate = GetTime(),
                        itemLevel = AF.RoundToDecimal(total / NUM_SLOTS, 1)
                    }
                    AF.Fire("AF_UNIT_ITEM_LEVEL_UPDATE", unit, guid)
                end
            end
        end)
    end
end

---------------------------------------------------------------------
-- inspect
---------------------------------------------------------------------
local queue = {}

local function INSPECT_READY(_, _, guid)
    local unit = queue[guid] and queue[guid].unit
    if not unit then return end

    -- print("Inspect ready for", unit, guid)

    local correct_guid = UnitGUID(unit)
    if correct_guid == guid then
        CalcItemLevel(unit, guid)
    end

    queue[guid] = nil
end
AF:RegisterEvent("INSPECT_READY", INSPECT_READY)

-- will fire "AF_UNIT_ITEM_LEVEL_UPDATE(unit, guid)" when item level is updated
---@param unit string
function IL.UpdateCache(unit)
    if not UnitIsPlayer(unit) then return end

    if UnitIsUnit(unit, "player") then
        cache[AF.player.guid] = {
            lastUpdate = GetTime(),
            itemLevel = AF.RoundToDecimal(select(2, GetAverageItemLevel()), 1)
        }
        AF.Fire("AF_UNIT_ITEM_LEVEL_UPDATE", unit, AF.player.guid)
        return
    end

    local guid = UnitGUID(unit)
    if not guid then return end

    if CanInspect(unit) and not (queue[guid] and GetTime() - queue[guid].requested < 2) then
        queue[guid] = {
            unit = unit,
            requested = GetTime(),
        }
        -- print("Requesting inspect for", unit, guid)
        NotifyInspect(unit)
    end
end

---@param guid string
---@return number? itemLevel
---@return number? timeSinceLastUpdate
function IL.GetCache(guid)
    if not guid then return end

    if guid == AF.player.guid then
        cache[AF.player.guid] = {
            lastUpdate = GetTime(),
            itemLevel = AF.RoundToDecimal(select(2, GetAverageItemLevel()), 1)
        }
        return cache[AF.player.guid].itemLevel, 0
    end

    if cache[guid] then
        return cache[guid].itemLevel, GetTime() - cache[guid].lastUpdate
    end
end

-- function IL.ClearCache()
--     wipe(cache)
--     wipe(queue)
-- end
