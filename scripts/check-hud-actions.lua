-- Exercise a protected button's lifetime without consuming a real character item.
local combat, queued = false, {}
local events, messages = {}, {}
local ns = {db={locked=true}}
function ns:RegisterEvent(k, fn) events[k]=fn end
function ns:RegisterMessage(k, fn) messages[k]=fn end
function InCombatLockdown() return combat end
C_Timer={After=function(_, fn) queued[#queued+1]=fn end}
local function flush()
    local todo=queued
    queued={}
    for _, fn in ipairs(todo) do fn() end
end
local Frame = {}
Frame.__index = Frame
function CreateFrame(_, _, parent)
    return setmetatable({parent=parent, shown=true, attrs={}, scripts={}, x=20, y=30},Frame)
end
function Frame:SetAttribute(k,v) assert(not combat) self.attrs[k]=v end
function Frame:SetAllPoints() end
function Frame:ClearAllPoints() assert(not combat) end
function Frame:SetPoint(_,_,_,x,y) assert(not combat) self.x,self.y=x,y end
function Frame:SetSize(w,h) self.width,self.height=w,h end
function Frame:GetWidth() return self.width or 24 end
function Frame:GetHeight() return self.height or 24 end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetFrameLevel() return 4 end
function Frame:GetFrameStrata() return "MEDIUM" end
function Frame:SetFrameStrata() end
function Frame:SetFrameLevel() end
function Frame:GetEffectiveAlpha() return 1 end
function Frame:GetCenter() return self.x,self.y end
function Frame:GetParent() return self.parent end
function Frame:IsVisible() return self.shown end
function Frame:Show() assert(not combat) self.shown=true end
function Frame:Hide() assert(not combat) self.shown=false end
function Frame:SetScript(k,v) self.scripts[k]=v end
Frame.HookScript=Frame.SetScript
function Frame:GetScript(k) return self.scripts[k] end
function Frame:SetPassThroughButtons(...) self.passthrough={...} end
function Frame:RegisterForClicks(...) self.clicks={...} end
function RegisterStateDriver(frame,_,cond) assert(cond:find("combat")) end
UIParent=CreateFrame()
assert(loadfile("TenUI/Widgets/HUDActions.lua"))("TenUI",ns)
local icon=CreateFrame(nil,nil,UIParent)
ns.SyncHUDAction(icon,"item",123,16)
local button=assert(icon._actionButton)
assert(button.attrs["target-slot1"]==16 and not button.attrs.unit1 and button.clicks[1]=="LeftButtonDown")
assert(button.passthrough[1]=="RightButton")
local hovered
icon:SetScript("OnEnter",function(owner) hovered=owner end)
button.scripts.OnEnter(button)
assert(hovered==icon)
ns.db.locked=false
messages.LOCK_STATE_CHANGED()
flush()
assert(not button.shown)
ns.db.locked=true
icon.x=200
messages.ANCHOR_MOVED()
flush()
assert(button.shown and button.x==200)
combat=true
ns.ReleaseHUDAction(icon)
icon.parent=nil
local nextIcon=CreateFrame(nil,nil,UIParent)
ns.SyncHUDAction(nextIcon,"spell",456)
assert(not icon._actionButton and not nextIcon._actionButton)
combat=false
events.PLAYER_REGEN_ENABLED()
flush()
assert(nextIcon._actionButton==button and button.attrs.spell1==456)
assert(not button.attrs.item1 and not button.attrs["target-slot1"] and button.attrs.unit1=="player")
ns.ReleaseHUDAction(nextIcon)
assert(not button.shown)
print("PASS HUD click lifetime, editing, reposition, tooltip forwarding, weapon slot and combat recycling")
