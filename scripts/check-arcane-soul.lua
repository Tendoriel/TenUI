-- Verify how the helper configures the two native aura slots, including spec changes.
unpack = unpack or table.unpack
local function noop() end
local spec, tree, haste, combat = 62, 39, 0, false
local frames, slots = {}, {}
local function frame(parent)
    local f = { parent = parent, visible = true }
    f.SetTextColor = noop
    f.SetAllPoints, f.SetPoint = noop, noop
    f.SetMouseClickEnabled, f.SetMouseMotionEnabled = noop, noop
    function f:GetParent() return self.parent end
    function f:SetParent(p) self.parent = p end
    function f:SetAlpha(a) self.alpha = a end
    function f:SetShown(shown) self.visible = shown end
    function f:Show() self.visible = true end
    function f:Hide() self.visible = false end
    function f:CreateFontString() return frame(self) end
    function f:SetText(s) self.text = s end
    function f:SetDurationText(text, binding) self.binding = binding end
    return f
end
CreateFrame = function(kind, _, parent)
    local f = frame(parent)
    frames[#frames + 1] = f
    if kind == "AuraContainer" then
        function f:SetUnit(unit) assert(unit == "player") end
        function f:AddAuraSlot(_, filter, options)
            assert(filter == "HELPFUL")
            local id = next(options.candidateFilters.includeSpellIDs)
            local button = frame(self)
            slots[id] = button
            options.initializeFrame(button)
        end
        f.SetEnabled = noop
    end
    return f
end
InCombatLockdown = function() return combat end
GetTime = function() return 10 end
UnitSpellHaste = function() return haste end
issecretvalue = function() return false end
C_ClassTalents = { GetActiveHeroTalentSpec = function() return tree end }
C_AddOns = { IsAddOnLoaded = function() return true end }
C_Secrets = { ShouldAurasBeSecret = function() return false end }
C_StringUtil = { CreateNumericRuleFormatter = function()
    return { SetBreakpoints = function(self, points) self.points = points end }
end }
C_CurveUtil = { CreateColorCurve = function() return { SetType = noop, AddPoint = noop } end }
CreateColor = function(...) return {...} end
Enum = { LuaCurveType = { Step = 1 }, DurationTextBindingProperty = { RemainingDuration = 1 } }
local anchor
local ns = { Widgets = { resolveMedia = function() return "font" end }, Pixel = { SetFont = noop }, EditMode = { IsActive = function() return false end },
    Debug = { Warn = function(_, _, reason) error(reason) end },
    Resources_Resolver = { GetPlayerInfo = function() return "MAGE", 1, spec end },
    GetAnchor = function() return anchor end,
    RegisterAnchor = function() anchor = { frame = frame() } return anchor end,
    UnregisterAnchor = function() anchor = nil end,
}
assert(loadfile("TenUI/Modules/Resources/ArcaneSoul.lua"))("TenUI", ns)
local opts = { arcaneSoulEnabled = true }
ns.ArcaneSoul.Update(opts, false, 1)
local surge, soul = slots[365362], slots[451038]
assert(surge.binding.textFormatter.points[7].format == " ")
assert(soul.binding.textFormatter.points[1].format == "Barrage 1")
assert(surge.binding.textFormatter.points[7].threshold == 9)
haste = 100
ns.ArcaneSoul.Update(opts, true, 1)
assert(surge.binding.textFormatter.points[7].threshold == 4.5)
assert(not surge.parent.visible and not soul.parent.visible)
combat = true
ns.ArcaneSoul.Update(opts, false, 1)
assert(surge.parent.visible and soul.parent.visible and #frames == 3)
combat, tree = false, 0
ns.ArcaneSoul.Update(opts, false, 1)
assert(not anchor and not frames[1].visible)
print("PASS Arcane Soul native slot configuration, haste, preview, combat and talent switch")
