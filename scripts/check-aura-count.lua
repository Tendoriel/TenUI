-- WoW may create a native slot's button well after AddAuraSlot returns.
local function noop() end
local deferred, initialize, bound, lastAnchor
local ns = { RegisterEvent = noop }
local text = {
    SetFont = function(_, path, size) assert(path == "font" and size == 14) end,
    SetJustifyH = noop, ClearAllPoints = noop,
    SetPoint = function(_, point) lastAnchor = point end,
}
local button = {
    SetAllPoints = noop, SetMouseClickEnabled = noop, SetMouseMotionEnabled = noop,
    CreateFontString = function() return text end,
    SetApplicationCount = function(_, region, options) assert(options.formatter) bound = region end,
}
InCombatLockdown = function() return false end
C_AddOns = { IsAddOnLoaded = function() return true end }
C_StringUtil = { CreateNumericRuleFormatter = function() return { SetBreakpoints = noop } end }
CreateFrame = function()
    return {
        SetUnit = noop, SetAllPoints = noop, SetFrameLevel = noop, Hide = noop,
        AddAuraSlot = function(_, _, filter, config)
            assert(filter == "HELPFUL" and config.candidateFilters.includeSpellIDs[42])
            initialize = config.initializeFrame
            if not deferred then initialize(button) end
        end,
    }
end
assert(loadfile("TenUI/Modules/TrackedAuras.lua"))("TenUI", ns)
for _, lazy in ipairs({ false, true }) do
    deferred, bound, lastAnchor = lazy, nil, nil
    local anchor = "TOPRIGHT"
    local frame = {
        cooldown = { GetFrameLevel = function() return 4 end },
        stack = { GetPoint = function() return anchor end, GetFont = function() return "font", 14 end },
    }
    local icon = { frame = frame }
    ns.TrackedAuras:SetupPlayerAuraCount(icon, 42)
    assert(icon._playerAuraCount and icon._playerAuraCountFailed == nil)
    if lazy then assert(not bound) initialize(button) end
    assert(bound == text and lastAnchor == anchor)
    anchor = "BOTTOMRIGHT"
    ns.TrackedAuras:SetupPlayerAuraCount(icon, 42)
    assert(lastAnchor == anchor)
end
print("PASS immediate and delayed native aura stack bindings and style changes")
