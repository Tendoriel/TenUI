-- A dirty Blizzard data provider must be strictly read-only, including on spec swaps.
local combat, secretAuras, spec, tag = false, false, 266, 92
function UnitClass() return "Warlock", "WARLOCK" end
function InCombatLockdown() return combat end
C_Secrets = { ShouldAurasBeSecret = function() return secretAuras end }
CooldownViewerUtil = { GetCurrentClassAndSpecTag = function() return tag end }
Enum = { CooldownViewerCategory = {Essential=0, Utility=1, TrackedBuff=2, TrackedBar=3, HiddenActive=-1, HiddenPassive=-2},
    CooldownSetSpellFlags = {HideByDefault=1} }
FlagsUtil = {IsSet=function(flags, bit) return flags == bit end}
C_CooldownViewer = {
    GetCooldownViewerCategorySet=function(category) return ({[0]={11,12}, [2]={13}})[category] or {} end,
    GetCooldownViewerCooldownInfo=function(id) return {category=id == 13 and 2 or 0, isKnown=true, flags=id == 12 and 1 or 0} end,
}
local layout = {classAndSpecTag=tag, orderedCooldownIDs={13,11}, cooldownInfo={[13]={category=3}}}
local calls = 0
local function forbiddenCall() calls=calls+1 error("unexpected Blizzard layout callback") end
CooldownViewerSettings = {GetDataProvider=forbiddenCall, dataProvider={
    GetDisplayData=forbiddenCall, IsDirty=forbiddenCall, displayDataDirty=true,
    layoutManager={GetActiveLayout=forbiddenCall, activeLayoutID=4, layouts={[4]=layout}}}}
local ns = {GetLiveSpecID=function() return spec end}
assert(loadfile("TenUI/Core/CDMLayout.lua"))("TenUI", ns)
local result, fresh = ns:ReadCooldownLayout()
assert(fresh and result.configured[0][1]==11 and result.configured[3][1]==13 and result.byID[12].category==-1)
combat=true
assert(ns:ReadCooldownLayout()==result)
spec,tag=267,93
assert(ns:ReadCooldownLayout()==nil)
combat,secretAuras=false,true
assert(ns:ReadCooldownLayout()==nil)
secretAuras=false
result,fresh=ns:ReadCooldownLayout()
assert(fresh and result.configured[2][1]==13 and not result.configured[3] and calls==0)
local function child(index, blocked) return {layoutIndex=index, IsForbidden=function() return blocked end} end
local first, second, decoration, restricted = child(1), child(2), child(nil), child(3,true)
local frames=ns.GetCooldownViewerFrames({GetChildren=function() return second,decoration,first,restricted end})
assert(#frames==2 and frames[1]==first and frames[2]==second)
print("PASS read-only CDM layouts, restrictions, spec change, hidden entries and unassigned viewer slots")
