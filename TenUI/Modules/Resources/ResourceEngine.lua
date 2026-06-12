local _, ns = ...

ns = ns or {}

local Engine = {}
ns.Resources_Engine = Engine

local pcall      = pcall
local tonumber   = tonumber
local math_max   = math.max
local ipairs     = ipairs
local type       = type
local C_Timer    = C_Timer
local C_UnitAuras = C_UnitAuras
local UnitStagger = UnitStagger
local UnitHealthMax = UnitHealthMax

local function isSecret(value)
    return issecretvalue and issecretvalue(value) == true
end
Engine.isSecret = isSecret

function Engine:IsSecret(value)
    return isSecret(value)
end

local function scrubNumber(value, fallback)
    if value == nil then
        return fallback
    end
    if isSecret(value) then
        return fallback
    end
    return tonumber(value) or fallback
end
Engine.scrubNumber = scrubNumber

function Engine:ScrubNumber(value, fallback)
    return scrubNumber(value, fallback)
end

local lastClean = {
    ratio   = nil,
    current = nil,
    max     = nil,
    hasClean = false,
}
Engine.lastClean = lastClean

local function acceptCleanPrimary(current, max)
    local cur = tonumber(current) or 0
    local mx  = math_max(1, tonumber(max) or 1)
    lastClean.current = cur
    lastClean.max     = mx
    lastClean.ratio   = cur / mx
    lastClean.hasClean = true
    return lastClean.ratio
end
Engine.acceptCleanPrimary = acceptCleanPrimary

function Engine:AcceptCleanPrimary(current, max)
    return acceptCleanPrimary(current, max)
end

function Engine:GetCleanRatio()
    return lastClean.ratio
end

function Engine:GetCleanCurMax()
    return lastClean.current, lastClean.max
end

function Engine:HasCleanPrimary()
    return lastClean.hasClean == true
end

local function isSuspiciousZero(explicitCurrentIsSecret, fallbackCurrent)
    if not explicitCurrentIsSecret then
        return false
    end
    if isSecret(fallbackCurrent) then
        return false
    end
    return (tonumber(fallbackCurrent) or 0) == 0
end
Engine.isSuspiciousZero = isSuspiciousZero

function Engine:IsSuspiciousZero(explicitCurrentIsSecret, fallbackCurrent)
    return isSuspiciousZero(explicitCurrentIsSecret, fallbackCurrent)
end

local function normalizePct(p)
    local n = tonumber(p)
    if not n then return nil end
    if n > 1.0 then n = n / 100 end
    return n
end

local function tryUnitPowerPercent(unit, powerType, diag)
    if not UnitPowerPercent then return nil end
    if powerType == nil then return nil end

    local ok, p = pcall(UnitPowerPercent, unit, powerType, false)
    if diag then
        diag[#diag + 1] = {
            form   = "3arg(false)",
            ok     = ok and true or false,
            secret = ok and isSecret(p) or false,
            value  = (ok and not isSecret(p)) and tostring(p) or nil,
        }
    end
    if ok and p ~= nil and not isSecret(p) then
        local n = normalizePct(p)
        if n then return n end
    end

    local CC = CurveConstants
    local scaleTo100 = CC and CC.ScaleTo100 or nil
    if scaleTo100 then
        local ok2, p2 = pcall(UnitPowerPercent, unit, powerType, false, scaleTo100)
        if diag then
            diag[#diag + 1] = {
                form   = "4arg(false,ScaleTo100)",
                ok     = ok2 and true or false,
                secret = ok2 and isSecret(p2) or false,
                value  = (ok2 and not isSecret(p2)) and tostring(p2) or nil,
            }
        end
        if ok2 and p2 ~= nil and not isSecret(p2) then
            local n = normalizePct(p2)
            if n then return n end
        end
    elseif diag then
        diag[#diag + 1] = { form = "4arg(skipped:noScaleTo100)", ok = false, secret = false }
    end

    return nil
end
Engine.tryUnitPowerPercent = tryUnitPowerPercent

function Engine:TryUnitPowerPercent(unit, powerType, diag)
    return tryUnitPowerPercent(unit, powerType, diag)
end

local FRESH_LOGIN_RETRY_DELAYS = { 0.3, 0.8, 2.0 }
Engine.FRESH_LOGIN_RETRY_DELAYS = FRESH_LOGIN_RETRY_DELAYS

local function freshLoginRetry(callback)
    if type(callback) ~= "function" then return false end
    if not (C_Timer and C_Timer.After) then return false end
    for _, delay in ipairs(FRESH_LOGIN_RETRY_DELAYS) do
        C_Timer.After(delay, function()
            pcall(callback, delay)
        end)
    end
    return true
end
Engine.freshLoginRetry = freshLoginRetry

function Engine:FreshLoginRetry(callback)
    return freshLoginRetry(callback)
end

local lastCleanPseudo = {}
Engine.lastCleanPseudo = lastCleanPseudo

local function pseudoCacheGet(key)
    local e = lastCleanPseudo[key]
    if e then return e.cur, e.max end
    return nil, nil
end

local function pseudoCacheSet(key, cur, max)
    local e = lastCleanPseudo[key]
    if not e then
        e = {}
        lastCleanPseudo[key] = e
    end
    e.cur = cur
    e.max = max
end

local function readStagger(key)
    local rawStagger = UnitStagger and UnitStagger("player") or nil
    local rawMax     = UnitHealthMax and UnitHealthMax("player") or nil
    local sSecret = isSecret(rawStagger)
    local mSecret = isSecret(rawMax)
    if (not sSecret) and (not mSecret)
       and type(rawStagger) == "number" and type(rawMax) == "number" then
        pseudoCacheSet(key, rawStagger, rawMax)
        return rawStagger, rawMax, true
    end
    local cCur, cMax = pseudoCacheGet(key)
    return (cCur or 0), (cMax or 0), false
end
Engine.readStagger = readStagger

function Engine:ReadStagger(key)
    return readStagger(key)
end

local function readAuraStacks(key, spellId)
    if not spellId then
        return 0, true
    end
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then
        local c = pseudoCacheGet(key)
        return (c or 0), false
    end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellId)
    if not ok then
        local c = pseudoCacheGet(key)
        return (c or 0), false
    end
    if aura == nil then
        pseudoCacheSet(key, 0, nil)
        return 0, true
    end
    local stacks = aura.applications
    if stacks == nil then
        pseudoCacheSet(key, 1, nil)
        return 1, true
    end
    if isSecret(stacks) then
        local c = pseudoCacheGet(key)
        return (c or 0), false
    end
    local n = tonumber(stacks) or 0
    pseudoCacheSet(key, n, nil)
    return n, true
end
Engine.readAuraStacks = readAuraStacks

function Engine:ReadAuraStacks(key, spellId)
    return readAuraStacks(key, spellId)
end

local staggerTicker
local auraTicker

local function cancelTicker(t)
    if t and t.Cancel then
        pcall(t.Cancel, t)
    end
end

function Engine:EnsureStaggerTicker(active, refreshFn)
    if not active then
        cancelTicker(staggerTicker)
        staggerTicker = nil
        return
    end
    if staggerTicker then return end
    if not (C_Timer and C_Timer.NewTicker) then return end
    staggerTicker = C_Timer.NewTicker(0.1, function()
        if type(refreshFn) == "function" then pcall(refreshFn) end
    end)
end

function Engine:EnsureAuraTicker(active, refreshFn)
    if not active then
        cancelTicker(auraTicker)
        auraTicker = nil
        return
    end
    if auraTicker then return end
    if not (C_Timer and C_Timer.NewTicker) then return end
    auraTicker = C_Timer.NewTicker(0.15, function()
        if type(refreshFn) == "function" then pcall(refreshFn) end
    end)
end

function Engine:StopAllTickers()
    cancelTicker(staggerTicker)
    staggerTicker = nil
    cancelTicker(auraTicker)
    auraTicker = nil
end

return Engine
