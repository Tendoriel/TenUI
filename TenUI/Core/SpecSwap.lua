local addonName, ns = ...

local InCombatLockdown   = InCombatLockdown
local GetSpecialization  = GetSpecialization
local UnitClass          = UnitClass
local tostring           = tostring

local _pendingSpecSwap = false
local _inSwap          = false

local function log(fmt, ...)
    if ns.Debug and ns.Debug.Log then
        ns.Debug:Log(fmt, ...)
    end
end

local function getCurrentSpecKey()
    local classToken = select(2, UnitClass("player"))
    local specIdx = GetSpecialization and GetSpecialization()
    if not classToken or not specIdx then return nil end
    return classToken .. "_" .. tostring(specIdx)
end

local function trySwap(reason)
    if _inSwap then return end
    if not ns.savedVarsReady or not ns.db then return end

    local p = ns:GetProfile()
    local cfg = p.modules and p.modules.Profiles and p.modules.Profiles.specSwap
    if not (cfg and cfg.enabled) then return end

    local specKey = getCurrentSpecKey()
    if not specKey then
        log("[SpecSwap] %s: no spec info yet, skipping", tostring(reason))
        return
    end

    local targetName = cfg.assignments and cfg.assignments[specKey]
    if not targetName then
        log("[SpecSwap] %s: no assignment for spec %s", tostring(reason), specKey)
        return
    end

    if ns:GetProfileKey() == targetName then
        log("[SpecSwap] %s: spec %s -> '%s' already active", tostring(reason), specKey, targetName)
        return
    end

    if not (ns.db.profiles and ns.db.profiles[targetName]) then
        log("[SpecSwap] %s: spec %s -> '%s' SKIPPED (profile no longer exists)", tostring(reason), specKey, targetName)
        return
    end

    if InCombatLockdown() then
        _pendingSpecSwap = true
        log("[SpecSwap] %s: spec %s -> '%s' deferred (in combat)", tostring(reason), specKey, targetName)
        return
    end

    _inSwap = true
    local ok = ns:SetActiveProfile(targetName)
    _inSwap = false

    if ok then
        log("[SpecSwap] spec %s -> profile '%s' (%s)", specKey, targetName, tostring(reason))
        if ns.Options and ns.Options._isOpen and ns.Options.Refresh then
            ns.Options:Refresh()
        end
    else
        log("[SpecSwap] spec %s -> '%s' FAILED in SetActiveProfile", specKey, targetName)
    end
end

ns:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(event, unit)
    if unit and unit ~= "player" then return end
    trySwap("spec-changed")
end)

ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if _pendingSpecSwap then
        _pendingSpecSwap = false
        trySwap("post-combat")
    end
end)

ns:RegisterEvent("PLAYER_ENTERING_WORLD", function(event, isInitialLogin, isReloadingUi)
    if isInitialLogin or isReloadingUi then
        trySwap("login")
    end
end)
