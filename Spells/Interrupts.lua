---@class AbstractFramework
local AF = select(2, ...)

local IsSpellKnownOrInSpellBook = AF.isRetail
    and C_SpellBook.IsSpellKnownOrInSpellBook
local GetSpellCooldownDuration = AF.isRetail
    and C_Spell.GetSpellCooldownDuration
local PlayerSpellBook = AF.isRetail
    and Enum.SpellBookSpellBank.Player
local PetSpellBook = AF.isRetail
    and Enum.SpellBookSpellBank.Pet
local IsKnownClassic =
    IsSpellKnownOrOverridesKnown or IsSpellKnown

local INTERRUPT_SPELLS = {
    WARRIOR = {6552},
    PALADIN = {96231, 31935},
    HUNTER = {147362, 187707},
    ROGUE = {1766},
    PRIEST = {15487},
    DEATHKNIGHT = {47528},
    SHAMAN = {57994},
    MAGE = {2139},
    WARLOCK = {89766, 119910, 132409},
    MONK = {116705},
    DRUID = {38675, 106839, 78675},
    DEMONHUNTER = {183752},
    EVOKER = {351338},
}

local knownSpells = {}

local function IsKnownInterrupt(spellID)
    if IsSpellKnownOrInSpellBook then
        return IsSpellKnownOrInSpellBook(spellID, PlayerSpellBook)
            or IsSpellKnownOrInSpellBook(spellID, PetSpellBook)
    end
    return IsKnownClassic and IsKnownClassic(spellID)
end

local function UpdateKnownInterrupts()
    wipe(knownSpells)

    local classSpells = INTERRUPT_SPELLS[AF.player.class]
    if not classSpells then return end

    for _, spellID in ipairs(classSpells) do
        if IsKnownInterrupt(spellID) then
            knownSpells[#knownSpells + 1] = spellID
        end
    end
end

local timer
local function DelayedUpdateKnownInterrupts()
    if timer then timer:Cancel() end
    timer = C_Timer.NewTimer(1, UpdateKnownInterrupts)
end

AF.CreateBasicEventHandler(
    DelayedUpdateKnownInterrupts,
    "PLAYER_LOGIN",
    "SPELLS_CHANGED"
)

function AF.GetKnownInterruptSpells()
    return knownSpells
end

function AF.GetPrimaryInterruptSpell()
    return knownSpells[1]
end

function AF.GetPrimaryInterruptCooldownDuration()
    local spellID = knownSpells[1]
    if not spellID then return end
    if not GetSpellCooldownDuration then return spellID end
    -- Retail 12.0.7.68887 and 12.1.0.68824 expose cooldown state through a
    -- LuaDurationObject. Consumers must forward its secret-capable accessors
    -- to native sinks rather than inspect the returned values in Lua.
    -- Interrupt readiness must not be suppressed by the global cooldown.
    return spellID, GetSpellCooldownDuration(spellID, true)
end

function AF.InterruptUsable()
    if AF.isRetail then
        for _, spellID in ipairs(knownSpells) do
            local duration =
                GetSpellCooldownDuration(spellID, true)
            if duration
                and not duration:HasSecretValues()
                and duration:IsZero()
            then
                return true
            end
        end
        return false
    end

    -- Classic clients do not load the Retail duration-object contract.
    for _, spellID in ipairs(knownSpells) do
        local cooldownDuration
        if C_Spell and C_Spell.GetSpellCooldown then
            local cooldownInfo = C_Spell.GetSpellCooldown(spellID)
            cooldownDuration = cooldownInfo
                and cooldownInfo.duration
        elseif GetSpellCooldown then
            local _, legacyDuration = GetSpellCooldown(spellID)
            cooldownDuration = legacyDuration
        end
        if cooldownDuration == 0 then return true end
    end
    return false
end
