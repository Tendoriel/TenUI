local noop = function() end
local callbacks = {}
local ns = { Pixel = {SetFont=noop}, UI = {ResolveFontPath=noop},
    RegisterEvent = function(_, name, fn) callbacks[name] = fn end }
local macroItem = 54321
issecretvalue = function() return false end
InCombatLockdown = function() return false end
C_ActionBar = {GetSpell=function(slot) if slot == 1 then return 102 end end,
    GetActionText=function() return "trinket macro" end}
C_Spell = {GetBaseSpell=function() return 101 end, GetOverrideSpell=function() return 102 end}
GetActionInfo = function(slot)
    if slot == 1 then return "spell", 102 end
    if slot == 2 then return "macro", 3 end
    return "item", 777
end
GetMacroIndexByName = function() return 3 end
GetMacroItem = noop
GetMacroSpell = noop
GetMacroBody = function() return "#showtooltip\n/use 13" end
GetInventoryItemID = function(_, slot) if slot == 13 then return macroItem end end
for i=1,3 do
    _G["ActionButton"..i] = {action=i, GetName=function() return "ActionButton"..i end}
end
GetBindingKey = function(key)
    return ({ACTIONBUTTON1="SHIFT-Q", ACTIONBUTTON2="CTRL-MOUSEWHEELUP", ACTIONBUTTON3="ALT-BUTTON4"})[key]
end
local result
local label = { IsShown=function() return true end, Hide=function() result=nil end,
    SetText=function(_, value) result=value end, SetPoint=noop, ClearAllPoints=noop, Show=noop }
local icon = {frame={}, bindLabel=label}
assert(loadfile("TenUI/Modules/CooldownKeybinds.lua"))("TenUI",ns)
local function check(kind,id,expected)
    ns:UpdateCooldownKeybind(icon, {showKeybind=true}, {type=kind,id=id})
    assert(result==expected, tostring(result))
end
check("spell",101,"S-Q")
check("item",54321,"C-MWU")
check("item",777,"A-M4")
macroItem=24680
callbacks.PLAYER_EQUIPMENT_CHANGED()
check("item",54321,nil)
check("item",24680,"C-MWU")
print("PASS standard binding commands, override spell, direct item, equipment macro and cache refresh")
