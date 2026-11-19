local _, ns = ...

local pending = false
local retry

local function applyCurrentProfile()
    if not ns.savedVarsReady then return end
    if InCombatLockdown() then
        pending = true
        return
    end

    pending = false
    local name, specID = ns:ResolveActiveProfile()
    local previous = ns:GetProfileKey()
    if ns:SetActiveProfile(name, true) and name ~= previous
        and ns.Options and ns.Options._isOpen and ns.Options.Refresh then
        ns.Options:Refresh()
    end
    if specID and retry then
        retry:Cancel()
        retry = nil
    elseif not specID and not retry then
        local attempts = 0
        retry = C_Timer.NewTicker(1, function(ticker)
            attempts = attempts + 1
            applyCurrentProfile()
            if ticker == retry and attempts >= 10 then
                ticker:Cancel()
                retry = nil
            end
        end, 10)
    end
end

ns:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(_, unit)
    if unit == nil or unit == "player" then applyCurrentProfile() end
end)

ns:RegisterEvent("PLAYER_ENTERING_WORLD", applyCurrentProfile)

ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if pending then applyCurrentProfile() end
end)

ns:RegisterMessage("SPEC_PROFILE_ASSIGNMENT_CHANGED", function(_, specID)
    if specID == ns:GetLiveSpecID() then applyCurrentProfile() end
end)
