-- Run from the repository root: luajit scripts/check-warlock.lua
local ns = { RegisterEvent = function(_, _, handler) return handler end }
assert(loadfile("TenUI/Modules/TrackedAuras.lua"))("TenUI", ns)
local tracked = ns.TrackedAuras
assert(tracked:GetFixedBarIndex("cdm:760") == nil)
local state = {
    ready = true, shown = true, count = 2,
    rows = { { key = "cdm:760" }, { key = "cdm:84224" }, { key = "removed" } },
}
state.frame = { IsShown = function() return state.shown end }
local name = debug.getupvalue(tracked.GetFixedBarIndex, 1)
assert(name == "fixedBars")
debug.setupvalue(tracked.GetFixedBarIndex, 1, state)
assert(tracked:GetFixedBarIndex("cdm:760") == 1)
assert(tracked:GetFixedBarIndex("cdm:84224") == 2)
assert(tracked:GetFixedBarIndex("removed") == nil)
state.rows[1], state.rows[2] = state.rows[2], state.rows[1]
assert(tracked:GetFixedBarIndex("cdm:760") == 2)
state.shown = false
assert(tracked:GetFixedBarIndex("cdm:760") == nil)
state.shown, state.ready = true, false
assert(tracked:GetFixedBarIndex("cdm:760") == nil)

assert(loadfile("TenUI/Modules/AurasNative.lua"))("TenUI", ns)
local auras = { _summonSpecGateOK = true }
local entries = {
    { stableEntryID = "cdm:760", matchSpellIDs = {}, active = true },
    { stableEntryID = "cdm:84224", matchSpellIDs = {}, active = false },
}
state.ready = true
ns._auraPresentTruthy = function(value) return value ~= nil end
auras._summonSpellForEntry = function() return 104316 end
auras._resolveSummonBarPresence = function(entry) return entry.active, {} end
auras._makeSummonBarItem = function() return {} end
ns.InstallNativeAuraDisplay(auras, {
    _auraCatalog = { TrackedBars = entries }, entryDisplayEnabled = function() return true end,
})
local active = auras:_BuildNativeSummonEntries("TrackedBars")
assert(#active == 1 and active[1]._fixedBarKey == "cdm:760" and active[1]._fixedBarIndex == 2)
entries[2].active = true
active = auras:_BuildNativeSummonEntries("TrackedBars")
assert(#active == 2 and active[2]._fixedBarIndex == 1)

local combat, mounted, failContainer = false, false, false
local methods = {}
local function widget() return setmetatable({ shown = true }, { __index = methods }) end
for _, method in ipairs({ "SetSize", "SetFrameStrata", "EnableMouse", "SetMovable", "RegisterForDrag",
    "SetAllPoints", "SetTexCoord", "SetTexture", "ClearAllPoints", "SetPoint", "SetAlpha",
    "SetMouseClickEnabled", "SetMouseMotionEnabled", "SetIcon" }) do
    methods[method] = function() end
end
function methods:Hide() self.shown = false end
function methods:Show() self.shown = true end
function methods:SetShown(shown) self.shown = shown end
function methods:IsShown() return self.shown end
function methods:CreateTexture() return widget() end
function methods:SetUnit(unit) assert(unit == "player") end
function methods:AddAuraSlot(key, filter, config)
    assert(key == "burningRush" and filter == "HELPFUL")
    assert(config.candidateFilters.includeSpellIDs[111400] == true)
    assert(next(config.candidateFilters.includeSpellIDs, 111400) == nil)
    config.initializeFrame(widget())
end
CreateFrame = function(kind)
    if kind == "AuraContainer" and failContainer then error("native container unavailable") end
    return widget()
end
UIParent = widget()
UnitClass = function() return "Warlock", "WARLOCK" end
IsStealthed = function() return false end
IsMounted = function() return mounted end
IsInInstance = function() return false end
GetSpecialization = function() return 2 end
InCombatLockdown = function() return combat end
GetTime = function() return 1 end
C_AddOns = { IsAddOnLoaded = function() return true end }
C_UnitAuras = { GetPlayerAuraBySpellID = function() error("restricted lookup must not be used") end }
local opts = { enabled = true, warlockBurningRush = true, hideWhileMounted = true }
ns.GetProfile = function() return { modules = { General = { stealthTracking = opts } } } end
ns.QoLDrag = { Attach = function() end }
ns.RegisterModule = function() end
local function enableReminder()
    assert(loadfile("TenUI/Modules/General/StealthTracking.lua"))("TenUI", ns)
    ns.StealthTracking:OnEnable()
    return ns.StealthTracking
end
local reminder = enableReminder()
assert(reminder._rushContainer.shown and not reminder.frame.rushSlot.icon.shown)
reminder:SetUnlocked(true)
assert(not reminder._rushContainer.shown and reminder.frame.rushSlot.icon.shown)
reminder:SetUnlocked(false)
assert(reminder._rushContainer.shown and not reminder.frame.rushSlot.icon.shown)
mounted = true
reminder:ApplyOptions()
assert(not reminder.frame.shown)
mounted, opts.warlockBurningRush = false, false
reminder:ApplyOptions()
assert(not reminder.frame.shown)
opts.warlockBurningRush, combat = true, true
reminder = enableReminder()
assert(not reminder._rushContainer and not reminder.frame.rushSlot.icon.shown)
combat = false
reminder:ApplyOptions()
assert(reminder._rushContainer.shown)
failContainer = true
reminder = enableReminder()
assert(not reminder._rushContainer and not reminder.frame.rushSlot.icon.shown)
print("PASS: summon row mapping; native Burning Rush, preview, visibility, combat deferral and failure")
