local _, ns = ...

local pending = false
local retry
local appliedSpecID

local function applyCurrentProfile()
    if not ns.savedVarsReady then return end
    if InCombatLockdown() then
        pending = true
        return
    end

    local name, specID = ns:ResolveActiveProfile()
    if not specID then
        pending = true
        return
    end
    pending = false
    local previous = ns:GetProfileKey()
    local specChanged = specID ~= appliedSpecID
    if not ns:SetActiveProfile(name, true) then return end
    appliedSpecID = specID
    if specChanged and name == previous then
        ns:Fire("PROFILE_CHANGED", name)
    end
    if (specChanged or name ~= previous) and ns.Options and ns.Options._isOpen and ns.Options.Refresh then
        ns.Options:Refresh()
    end
end

local function checkTransition()
    applyCurrentProfile()
    -- Role-based matchmaking can finish the automatic spec change after entering the world.
    if retry then retry:Cancel() end
    local attempts = 0
    retry = C_Timer.NewTicker(0.75, function()
        applyCurrentProfile()
        attempts = attempts + 1
        if attempts == 8 then retry = nil end
    end, 8)
end

ns:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(_, unit)
    if unit == nil or unit == "player" then checkTransition() end
end)

ns:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", checkTransition)
ns:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", checkTransition)
ns:RegisterEvent("PLAYER_ENTERING_WORLD", checkTransition)
ns:RegisterEvent("PLAYER_ROLES_ASSIGNED", checkTransition)

ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if pending then applyCurrentProfile() end
end)

ns:RegisterMessage("SPEC_PROFILE_ASSIGNMENT_CHANGED", function(_, specID)
    if specID == ns:GetLiveSpecID() then applyCurrentProfile() end
end)
