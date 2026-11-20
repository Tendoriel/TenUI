local _, ns = ...

ns = ns or {}

local Resolver = {}
ns.Resources_Resolver = Resolver

local PT = Enum and Enum.PowerType or {}

local POWER_MANA       = PT.Mana       or 0
local POWER_RAGE       = PT.Rage       or 1
local POWER_FOCUS      = PT.Focus      or 2
local POWER_ENERGY     = PT.Energy     or 3
local POWER_COMBO      = PT.ComboPoints or 4
local POWER_RUNES      = PT.Runes      or 5
local POWER_RUNIC      = PT.RunicPower or 6
local POWER_SOUL_SHARDS = PT.SoulShards or 7
local POWER_LUNAR      = PT.LunarPower or 8
local POWER_HOLY       = PT.HolyPower  or 9
local POWER_MAELSTROM  = PT.Maelstrom  or 11
local POWER_CHI        = PT.Chi        or 12
local POWER_INSANITY   = PT.Insanity   or 13
local POWER_ARCANE     = PT.ArcaneCharges or 16
local POWER_FURY       = PT.Fury       or 17
local POWER_ESSENCE    = PT.Essence    or 19

local POWER_STAGGER        = "STAGGER"
local POWER_SOUL_FRAGMENTS = "SOUL_FRAGMENTS"
local POWER_VENGEANCE_FRAGMENTS = "VENGEANCE_FRAGMENTS"

local VOID_META_AURA_ID       = 1217607
local SOUL_FRAGMENTS_AURA_ID  = 1225789
local COLLAPSING_STAR_AURA_ID = 1227702
local SOUL_GLUTTON_SPELL_ID   = 1247534
local SURRENDER_TO_VOID       = 1261423

local SPEC = {
    BLOOD           = 250,
    FROST_DK        = 251,
    UNHOLY          = 252,
    HAVOC           = 577,
    VENGEANCE       = 581,
    DEVOURER        = 1480,
    BALANCE         = 102,
    FERAL           = 103,
    GUARDIAN        = 104,
    RESTORATION_D   = 105,
    DEVASTATION     = 1467,
    PRESERVATION    = 1468,
    AUGMENTATION    = 1473,
    BM              = 253,
    MARKSMAN        = 254,
    SURVIVAL        = 255,
    ARCANE          = 62,
    FIRE            = 63,
    FROST_M         = 64,
    BREWMASTER      = 268,
    MISTWEAVER      = 270,
    WINDWALKER      = 269,
    HOLY_PAL        = 65,
    PROTECTION_PAL  = 66,
    RETRIBUTION     = 70,
    DISCIPLINE      = 256,
    HOLY_PR         = 257,
    SHADOW          = 258,
    ASSASSINATION   = 259,
    OUTLAW          = 260,
    SUBTLETY        = 261,
    ELEMENTAL       = 262,
    ENHANCEMENT     = 263,
    RESTORATION_S   = 264,
    AFFLICTION      = 265,
    DEMONOLOGY      = 266,
    DESTRUCTION     = 267,
    ARMS            = 71,
    WARRIOR_FURY    = 72,
    PROTECTION_WAR  = 73,
}

local PRIMARY_BY_CLASS = {
    DEATHKNIGHT = POWER_RUNIC,
    WARLOCK     = POWER_MANA,
    DEMONHUNTER = POWER_FURY,
    HUNTER      = POWER_FOCUS,
    ROGUE       = POWER_ENERGY,
    WARRIOR     = POWER_RAGE,
    MAGE        = POWER_MANA,
    PRIEST      = POWER_MANA,
    PALADIN     = POWER_MANA,
    SHAMAN      = POWER_MANA,
    MONK        = POWER_MANA,
    EVOKER      = POWER_ESSENCE,
}

local PRIMARY_BY_SPEC = {
    [SPEC.BLOOD]            = POWER_RUNIC,
    [SPEC.FROST_DK]         = POWER_RUNIC,
    [SPEC.UNHOLY]           = POWER_RUNIC,
    [SPEC.AFFLICTION]       = POWER_MANA,
    [SPEC.DEMONOLOGY]       = POWER_MANA,
    [SPEC.DESTRUCTION]      = POWER_MANA,
    [SPEC.HAVOC]            = POWER_FURY,
    [SPEC.VENGEANCE]        = POWER_FURY,
    [SPEC.DEVOURER]         = POWER_FURY,
    [SPEC.BALANCE]          = POWER_MANA,
    [SPEC.FERAL]            = POWER_ENERGY,
    [SPEC.GUARDIAN]         = POWER_RAGE,
    [SPEC.RESTORATION_D]    = POWER_MANA,
    [SPEC.DEVASTATION]      = POWER_MANA,
    [SPEC.PRESERVATION]     = POWER_MANA,
    [SPEC.AUGMENTATION]     = POWER_MANA,
    [SPEC.BM]               = POWER_FOCUS,
    [SPEC.MARKSMAN]         = POWER_FOCUS,
    [SPEC.SURVIVAL]         = POWER_FOCUS,
    [SPEC.ARCANE]           = POWER_MANA,
    [SPEC.FIRE]             = POWER_MANA,
    [SPEC.FROST_M]          = POWER_MANA,
    [SPEC.WINDWALKER]       = POWER_ENERGY,
    [SPEC.BREWMASTER]       = POWER_ENERGY,
    [SPEC.MISTWEAVER]       = POWER_MANA,
    [SPEC.HOLY_PAL]         = POWER_MANA,
    [SPEC.PROTECTION_PAL]   = POWER_MANA,
    [SPEC.RETRIBUTION]      = POWER_MANA,
    [SPEC.DISCIPLINE]       = POWER_MANA,
    [SPEC.HOLY_PR]          = POWER_MANA,
    [SPEC.SHADOW]           = POWER_MANA,
    [SPEC.ASSASSINATION]    = POWER_ENERGY,
    [SPEC.OUTLAW]           = POWER_ENERGY,
    [SPEC.SUBTLETY]         = POWER_ENERGY,
    [SPEC.ELEMENTAL]        = POWER_MANA,
    [SPEC.ENHANCEMENT]      = POWER_MANA,
    [SPEC.RESTORATION_S]    = POWER_MANA,
    [SPEC.ARMS]             = POWER_RAGE,
    [SPEC.WARRIOR_FURY]     = POWER_RAGE,
    [SPEC.PROTECTION_WAR]   = POWER_RAGE,
}

local SECONDARY_BY_SPEC = {
    [SPEC.AFFLICTION]       = POWER_SOUL_SHARDS,
    [SPEC.DEMONOLOGY]       = POWER_SOUL_SHARDS,
    [SPEC.DESTRUCTION]      = POWER_SOUL_SHARDS,
    [SPEC.BLOOD]            = POWER_RUNES,
    [SPEC.FROST_DK]         = POWER_RUNES,
    [SPEC.UNHOLY]           = POWER_RUNES,
    [SPEC.ASSASSINATION]    = POWER_COMBO,
    [SPEC.OUTLAW]           = POWER_COMBO,
    [SPEC.SUBTLETY]         = POWER_COMBO,
    [SPEC.FERAL]            = POWER_COMBO,
    [SPEC.HOLY_PAL]         = POWER_HOLY,
    [SPEC.PROTECTION_PAL]   = POWER_HOLY,
    [SPEC.RETRIBUTION]      = POWER_HOLY,
    [SPEC.WINDWALKER]       = POWER_CHI,
    [SPEC.ARCANE]           = POWER_ARCANE,
    [SPEC.SHADOW]           = POWER_INSANITY,
    [SPEC.ELEMENTAL]        = POWER_MAELSTROM,
    [SPEC.DEVASTATION]      = POWER_ESSENCE,
    [SPEC.PRESERVATION]     = POWER_ESSENCE,
    [SPEC.AUGMENTATION]     = POWER_ESSENCE,
    [SPEC.BALANCE]          = POWER_LUNAR,
    [SPEC.BREWMASTER]       = POWER_STAGGER,
    [SPEC.DEVOURER]         = POWER_SOUL_FRAGMENTS,
    [SPEC.VENGEANCE]        = POWER_VENGEANCE_FRAGMENTS,
}

local AURA_RESOURCES = {
    MAELSTROM_WEAPON = { spellId = 344179, maxStacks = 5, talent = 384143, talentedMax = 10 },
    ICICLES          = { spellId = 205473, maxStacks = 5,  label = "Icicles" },
    TIP_OF_THE_SPEAR = { spellId = 260286, maxStacks = 3,  label = "TipOfTheSpear" },
    WHIRLWIND        = { spellId = 85739, altSpellId = 190411, maxStacks = 4 },
    SWEEPING_STRIKES = { spellId = 260708, maxStacks = 12, talent = 1261049, talentedMax = 18 },
}

local AURA_SECONDARY_BY_SPEC = {
    [SPEC.ENHANCEMENT]   = "MAELSTROM_WEAPON",
    [SPEC.FROST_M]       = "ICICLES",
    [SPEC.SURVIVAL]      = "TIP_OF_THE_SPEAR",
    [SPEC.WARRIOR_FURY]  = "WHIRLWIND",
    [SPEC.ARMS]          = "SWEEPING_STRIKES",
}

local POWER_TYPE_NAMES = {
    [POWER_MANA]        = "Mana",
    [POWER_RAGE]        = "Rage",
    [POWER_FOCUS]       = "Focus",
    [POWER_ENERGY]      = "Energy",
    [POWER_COMBO]       = "ComboPoints",
    [POWER_RUNES]       = "Runes",
    [POWER_RUNIC]       = "RunicPower",
    [POWER_SOUL_SHARDS] = "SoulShards",
    [POWER_LUNAR]       = "LunarPower",
    [POWER_HOLY]        = "HolyPower",
    [POWER_MAELSTROM]   = "Maelstrom",
    [POWER_CHI]         = "Chi",
    [POWER_INSANITY]    = "Insanity",
    [POWER_ARCANE]      = "ArcaneCharges",
    [POWER_FURY]        = "Fury",
    [POWER_ESSENCE]     = "Essence",
}

local POWER_TYPE_BY_NAME = {}
for enumValue, nameStr in pairs(POWER_TYPE_NAMES) do
    POWER_TYPE_BY_NAME[nameStr] = enumValue
end
Resolver.POWER_TYPE_BY_NAME = POWER_TYPE_BY_NAME
Resolver.POWER_TYPE_NAMES   = POWER_TYPE_NAMES

function Resolver:PowerTypeForName(name)
    if name == nil or name == "AUTO" then return nil end
    return POWER_TYPE_BY_NAME[name]
end

local DRUID_FORM_POWER = {
    [1]  = POWER_ENERGY,
    [5]  = POWER_RAGE,
    [31] = POWER_LUNAR,
}

local function getDruidPrimary(specId)
    local formId = GetShapeshiftFormID and GetShapeshiftFormID() or nil
    if formId == 1 then
        return POWER_ENERGY
    elseif formId == 5 then
        return POWER_RAGE
    end
    if (not formId) or formId == 0 or formId == 31 then
        return POWER_MANA
    end
    return PRIMARY_BY_SPEC[specId] or POWER_MANA
end

local playerClass, cachedIndex, cachedSpec, cachedName

function Resolver:GetPlayerInfo()
    if not playerClass then playerClass = select(2, UnitClass("player")) end
    local specIndex = (GetSpecialization and GetSpecialization()) or 0
    if specIndex ~= cachedIndex or not cachedSpec then
        cachedIndex = specIndex
        if specIndex > 0 and GetSpecializationInfo then
            cachedSpec, cachedName = GetSpecializationInfo(specIndex)
        else
            cachedSpec, cachedName = nil, nil
        end
    end
    return playerClass or "UNKNOWN", specIndex, cachedSpec or 0, cachedName
end

function Resolver:GetPrimaryResource(overrideName)
    local overridePT = self:PowerTypeForName(overrideName)
    if overridePT ~= nil then
        return overridePT
    end

    local playerClass, _, specId = self:GetPlayerInfo()

    if playerClass == "DRUID" then
        return getDruidPrimary(specId)
    end

    if specId > 0 and PRIMARY_BY_SPEC[specId] then
        return PRIMARY_BY_SPEC[specId]
    end

    return PRIMARY_BY_CLASS[playerClass]
end

function Resolver:GetSecondaryResource()
    local playerClass, _, specId = self:GetPlayerInfo()

    if playerClass == "DRUID" then
        local formId = GetShapeshiftFormID and GetShapeshiftFormID() or nil
        if formId == 1 then
            return POWER_COMBO
        end
        if formId == 5 then
            return nil
        end
        if specId == SPEC.BALANCE then
            return SECONDARY_BY_SPEC[SPEC.BALANCE]
        end
        return nil
    end

    if specId > 0 and SECONDARY_BY_SPEC[specId] then
        return SECONDARY_BY_SPEC[specId]
    end
    return nil
end

function Resolver:GetSecondaryMax()
    local secondary = self:GetSecondaryResource()
    if secondary == nil then
        local auraInfo, _, maximum = self:GetAuraResource()
        if auraInfo then
            return maximum or 0
        end
        return 0
    end
    if secondary == POWER_STAGGER then
        local ok, mh = pcall(UnitHealthMax, "player")
        if ok then return mh end
        return 0
    end
    if secondary == POWER_SOUL_FRAGMENTS then
        return self:GetSoulFragmentsMax()
    end
    if secondary == POWER_VENGEANCE_FRAGMENTS then return 6 end
    if not UnitPowerMax then
        return 0
    end
    local ok, maxV = pcall(UnitPowerMax, "player", secondary)
    if ok then
        return maxV
    end
    return 0
end

local function spellKnown(spellID)
    local getKnown = C_SpellBook and C_SpellBook.IsSpellKnown
    return getKnown and getKnown(spellID) == true
end

function Resolver:GetAuraResource()
    local _, _, specId = self:GetPlayerInfo()
    local key = specId > 0 and AURA_SECONDARY_BY_SPEC[specId] or nil
    local resource = key and AURA_RESOURCES[key]
    if resource then
        local maximum = resource.talent and spellKnown(resource.talent) and resource.talentedMax or resource.maxStacks
        return resource, key, maximum
    end
    return nil, nil
end

function Resolver:GetSoulFragmentsMax(inMeta)
    if inMeta == nil then inMeta = self:IsInVoidMeta() end
    if inMeta then
        return 40
    end
    local max = self:HasSoulGlutton() and 35 or 50
    if spellKnown(SURRENDER_TO_VOID) then max = max + 50 end
    return max
end

function Resolver:IsInVoidMeta()
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then
        return false
    end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, VOID_META_AURA_ID)
    if ok and ((issecretvalue and issecretvalue(aura)) or aura ~= nil) then return true end
    -- The transformation may be hidden while its Collapsing Star aura is still readable.
    local found, collapsingStar = pcall(C_UnitAuras.GetPlayerAuraBySpellID, COLLAPSING_STAR_AURA_ID)
    return found and ((issecretvalue and issecretvalue(collapsingStar)) or collapsingStar ~= nil) or false
end

function Resolver:HasSoulGlutton()
    if not (C_SpellBook and C_SpellBook.IsSpellKnown) then
        return false
    end
    local ok, known = pcall(C_SpellBook.IsSpellKnown, SOUL_GLUTTON_SPELL_ID)
    return ok and known == true
end

function Resolver:SoulFragmentsAuraID()
    if self:IsInVoidMeta() then
        return COLLAPSING_STAR_AURA_ID
    end
    return SOUL_FRAGMENTS_AURA_ID
end

function Resolver:GetPowerTypeName(powerType)
    if powerType == nil then return "none" end
    if powerType == POWER_STAGGER then return "Stagger" end
    if powerType == POWER_SOUL_FRAGMENTS then return "SoulFragments" end
    if powerType == POWER_VENGEANCE_FRAGMENTS then return "VengeanceFragments" end
    return POWER_TYPE_NAMES[powerType] or "Unknown"
end

Resolver.STAGGER_KEY            = POWER_STAGGER
Resolver.SOUL_FRAGMENTS_KEY     = POWER_SOUL_FRAGMENTS
Resolver.SOUL_FRAGMENTS_AURA_ID = SOUL_FRAGMENTS_AURA_ID
Resolver.COLLAPSING_STAR_AURA_ID = COLLAPSING_STAR_AURA_ID
Resolver.VOID_META_AURA_ID      = VOID_META_AURA_ID
Resolver.AURA_RESOURCES         = AURA_RESOURCES
ns.Resources_AURA_RESOURCES     = AURA_RESOURCES

return Resolver
