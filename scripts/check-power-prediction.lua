-- Run from the repository root with lua or luajit.
local Frame = {}
Frame.__index = Frame
local frames = {}
function CreateFrame(_, _, parent)
    local f = setmetatable({ children = {}, points = {}, width = 40, height = 12, shown = true }, Frame)
    local children = parent and parent.children or frames
    children[#children + 1] = f
    return f
end
for _, name in ipairs({"SetFrameLevel", "RegisterUnitEvent", "UnregisterAllEvents", "SetAlpha", "SetRotatesTexture"}) do
    Frame[name] = function() end
end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:IsShown() return self.shown end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetPoint(point, relative, edge, x, y) self.points[point] = {relative, edge, x, y} end
function Frame:SetScript(name, handler) self[name] = handler end
function Frame:GetFrameLevel() return 1 end
function Frame:GetTexture() return self.path end
function Frame:GetStatusBarTexture() return self end
function Frame:SetStatusBarTexture(path) self.path = path end
function Frame:SetClipsChildren(value) self.clips = value end
function Frame:GetReverseFill() return self.reverse or false end
function Frame:SetReverseFill(value) self.reverse = value end
function Frame:GetRotatesTexture() return false end
function Frame:GetOrientation() return self.orientation or "HORIZONTAL" end
function Frame:SetOrientation(value) self.orientation = value end
function Frame:SetHeight(value) self.height = value end
function Frame:GetHeight() return self.height end
function Frame:SetWidth(value) self.width = value end
function Frame:GetWidth() return self.width end
function Frame:SetStatusBarColor(r,g,b) self.color = {r,g,b} end
function Frame:SetMinMaxValues(_, maximum) self.max = maximum end
function Frame:SetValue(value) self.value = value end

Enum = {PowerType = {SoulShards=7, Mana=0, Focus=2, Fury=17, Maelstrom=11, LunarPower=8, Insanity=13, ArcaneCharges=16}}
local protected = {}
issecretvalue = function(value) return rawequal(value, protected) end
local raw, spec, talented = 34, 267, true
UnitCastingInfo = function() end
UnitPower = function(_, _, fragments) return fragments and raw or 3 end
UnitPowerMax = function(_, _, fragments) return fragments and 50 or 5 end
C_SpellBook = {IsSpellKnown = function() return talented end}
C_Spell = {GetSpellPowerCost = function(spell)
    if spell == 116858 then return {{type=0, cost=1}, {type=7, cost=2}} end
    if spell == 1 then return {{type=7, cost=protected}} end
    return {}
end}
local ns = {Resources_Resolver = {GetPlayerInfo = function() return nil, nil, spec end},
    Pixel = {Size = function() return 1 end}}
assert(loadfile("TenUI/Modules/Resources/PowerPrediction.lua"))("TenUI", ns)
local prediction = ns.PowerPrediction
local parent, pips = CreateFrame(), {}
for i = 1, 5 do
    pips[i] = CreateFrame(nil, nil, parent)
    pips[i].borderParts = {CreateFrame()}
end
prediction.Attach("secondary", parent, 7, pips, 3)
local driver = frames[#frames]
local primary = CreateFrame()
prediction.Attach("primary", primary, 0)
local function cast(event, spell, guid)
    driver:OnEvent("UNIT_SPELLCAST_" .. event, "player", guid or "current", spell)
end
cast("START", 116858)
local ruler = parent.children[6]
assert(ruler.value == 34 and ruler.max == 50 and ruler.width == 200)
for i, pip in ipairs(pips) do
    local clip = pip.children[1]
    assert(clip.clips and clip.points.TOPLEFT[1] == pip and clip.points.BOTTOMRIGHT[1] == pip)
    assert(clip.points.TOPLEFT[3] == 1 and clip.points.BOTTOMRIGHT[4] == 1)
    local segment = clip.children[1]
    assert(segment.points.TOPRIGHT[1] == ruler and segment.points.TOPRIGHT[3] == 3*(i-1))
    assert(segment.width == 200 and segment.value == 2 and segment.max == 5 and segment.reverse)
    assert(segment.color[1] > segment.color[2])
end
local mana = primary.children[1].children[1]
assert(mana.value == 1 and mana.color[1] > mana.color[2])
raw = 36
prediction.UpdatePips()
assert(ruler.value == 36)
cast("START", 29722)
local gain = pips[4].children[1].children[1]
assert(gain.value == 0.4 and gain.points.TOPLEFT[2] == "TOPRIGHT" and not gain.reverse)
assert(gain.color[2] > gain.color[1] and not primary.children[1].shown)
cast("FAILED", 29722, "another cast")
assert(pips[4].children[1].shown)
cast("INTERRUPTED", 29722)
for _, pip in ipairs(pips) do assert(not pip.children[1].shown) end
cast("START", 1)
assert(gain.value == protected)
prediction.Attach("secondary")
assert(not ruler.shown and not pips[1].children[1].shown)
spec, talented = 254, false
prediction.Attach("primary", primary, 2)
cast("START", 56641)
assert(mana.value == 20 and mana.color[2] > mana.color[1])
spec, talented = 1480, true
prediction.Attach("primary", primary, 17)
cast("START", 473662)
assert(mana.value == 10)
print("PASS prediction fill, gaps, borders, gains and costs, protected cost, interrupt and primary power")
