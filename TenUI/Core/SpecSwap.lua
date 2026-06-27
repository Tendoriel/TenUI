local addonName, ns = ...

local InCombatLockdown      = InCombatLockdown
local GetSpecialization     = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local C_Timer               = C_Timer

local lastKnownSpecID  = nil
local lastKnownCharKey = nil
local pendingSpecSwitch = false
local specRetryTimer    = nil

local function log(fmt, ...)
    if ns.Debug and ns.Debug.Log then
        ns.Debug:Log(fmt, ...)
    end
end

local function liveSpecID()
    local specIdx = GetSpecialization and GetSpecialization() or 0
    if type(specIdx) == "number" and specIdx > 0 then
        local sid = GetSpecializationInfo and GetSpecializationInfo(specIdx)
        if type(sid) == "number" and sid > 0 then return sid end
    end
    return nil
end

local function applySwitch(targetProfile, reason)
    if not targetProfile then return false end
    local current = ns:GetProfileKey()
    if current == targetProfile then
        log("[SpecSwap] %s: '%s' already active", tostring(reason), targetProfile)
        return true
    end
    local ok = ns:SetActiveProfile(targetProfile)
    if ok then
        log("[SpecSwap] %s: switched to '%s'", tostring(reason), targetProfile)
        if ns.Options and ns.Options._isOpen and ns.Options.Refresh then
            ns.Options:Refresh()
        end
    else
        log("[SpecSwap] %s: SetActiveProfile('%s') failed", tostring(reason), targetProfile)
    end
    return ok
end

local function findNonSpecFallback()
    if not ns.db then return "Default" end
    local specAssigned = {}
    if type(ns.db.specProfiles) == "table" then
        for _, pName in pairs(ns.db.specProfiles) do
            specAssigned[pName] = true
        end
    end
    for _, pName in ipairs(ns:ListProfiles()) do
        if not specAssigned[pName] then return pName end
    end
    return "Default"
end

local function currentIsSpecAssigned()
    if not ns.db or type(ns.db.specProfiles) ~= "table" then return false end
    local current = ns:GetProfileKey()
    for _, pName in pairs(ns.db.specProfiles) do
        if pName == current then return true end
    end
    return false
end

local function resolveAndSwitch(reason)
    if not ns.savedVarsReady or not ns.db then return end
    if InCombatLockdown() then
        pendingSpecSwitch = true
        log("[SpecSwap] %s: deferred (in combat)", tostring(reason))
        return
    end
    local targetProfile = ns:ResolveSpecProfile()
    if targetProfile then
        applySwitch(targetProfile, reason)
    end
end

local function startRetryTicker()
    if specRetryTimer then return end
    if not (C_Timer and C_Timer.NewTicker) then return end
    if lastKnownSpecID ~= nil then return end
    local attempts = 0
    specRetryTimer = C_Timer.NewTicker(1, function(ticker)
        attempts = attempts + 1
        local sid = liveSpecID()
        if sid then
            ticker:Cancel()
            specRetryTimer = nil
            lastKnownSpecID  = sid
            local ck = ns:GetCharKey()
            lastKnownCharKey = ck
            if ck and ns.db then
                ns.db.lastSpecByChar = ns.db.lastSpecByChar or {}
                ns.db.lastSpecByChar[ck] = sid
            end
            resolveAndSwitch("new-char-retry")
        elseif attempts >= 10 then
            ticker:Cancel()
            specRetryTimer = nil
        end
    end)
end

local function handleSpecEvent(event)
    if not ns.savedVarsReady or not ns.db then return end

    local specID = liveSpecID()
    if not specID then
        startRetryTicker()
        log("[SpecSwap] %s: no spec info yet, retry pending", tostring(event))
        return
    end

    if specRetryTimer then
        specRetryTimer:Cancel()
        specRetryTimer = nil
    end

    local charKey = ns:GetCharKey()
    local isFirstLogin = (lastKnownSpecID == nil)
    local charChanged  = (lastKnownCharKey ~= nil) and (lastKnownCharKey ~= charKey)

    if event == "PLAYER_ENTERING_WORLD" then
        if not isFirstLogin and not charChanged and specID == lastKnownSpecID then
            return
        end
    end

    lastKnownSpecID  = specID
    lastKnownCharKey = charKey
    if charKey then
        ns.db.lastSpecByChar = ns.db.lastSpecByChar or {}
        ns.db.lastSpecByChar[charKey] = specID
    end

    if InCombatLockdown() then
        pendingSpecSwitch = true
        log("[SpecSwap] %s: spec %s deferred (in combat)", tostring(event), tostring(specID))
        return
    end

    local targetProfile = ns:ResolveSpecProfile()
    if targetProfile then
        local doSwitch = function()
            applySwitch(targetProfile, isFirstLogin and "login" or tostring(event))
        end
        if isFirstLogin then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, doSwitch)
            else
                doSwitch()
            end
        else
            doSwitch()
        end
    elseif charChanged then
        if currentIsSpecAssigned() then
            local fallback = findNonSpecFallback()
            if fallback and fallback ~= ns:GetProfileKey() then
                applySwitch(fallback, "alt-swap-fallback")
            end
        end
    end
end

ns:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(event, unit)
    if unit and unit ~= "player" then return end
    handleSpecEvent("PLAYER_SPECIALIZATION_CHANGED")
end)

ns:RegisterEvent("PLAYER_ENTERING_WORLD", function(event, isInitialLogin, isReloadingUi)
    handleSpecEvent("PLAYER_ENTERING_WORLD")
end)

ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if not pendingSpecSwitch then return end
    pendingSpecSwitch = false
    if not ns.savedVarsReady or not ns.db then return end
    local sid = liveSpecID()
    if sid then
        lastKnownSpecID  = sid
        local ck = ns:GetCharKey()
        lastKnownCharKey = ck
        if ck then
            ns.db.lastSpecByChar = ns.db.lastSpecByChar or {}
            ns.db.lastSpecByChar[ck] = sid
        end
    end
    local targetProfile = ns:ResolveSpecProfile()
    if targetProfile then
        applySwitch(targetProfile, "post-combat")
    end
end)
