issecretvalue = function() return false end
-- Exercise the registered event handlers and the normal HUD render path.
local dead, ghost, combat = false, false, false
InCombatLockdown = function() return combat end
UnitIsDeadOrGhost = function(unit)
    assert(unit == "player")
    return dead or ghost
end
GetTime = function() return 100 end
IsInRaid = function() return true end
IsInGroup = IsInRaid
GetNumGroupMembers = function() return 1 end
UnitClass = function() return "Priest", "PRIEST" end
UnitClassBase = function() return "PRIEST" end
UnitExists = function(unit) return unit == "player" end
C_UnitAuras = { GetPlayerAuraBySpellID = function() return nil end }
wipe = function(t) for k in pairs(t) do t[k] = nil end end

local function noop() end
local region = setmetatable({ GetStringWidth = function() return 36 end }, { __index = function() return noop end })
local frame = {
    _locked = true, slots = {}, ClearAllPoints = noop, SetPoint = noop, SetSize = noop, SetAlpha = noop,
    Show = function(self) self.visible = true end, Hide = function(self) self.visible = false end,
}
for i = 1, 8 do
    frame.slots[i] = setmetatable({ label = region, icon = region, glow = region, check = region, glowAnim = region }, { __index = region })
end
CreateFrame = function() return { SetScript = noop, UnregisterEvent = noop, RegisterUnitEvent = noop } end
local handlers = {}
local options = { enabled = true, raidBuffs = true, showInRaid = true }
local profile = { modules = { General = { classReminders = options } } }
local ns = { SyncHUDAction = noop, Pixel = { SetFont = noop }, RegisterModule = noop, GetProfile = function() return profile end,
    RegisterEvent = function(_, event, callback) handlers[event] = callback return callback end }
assert(loadfile("TenUI/Modules/General/ClassReminders.lua"))("TenUI", ns)
local reminders = ns.ClassReminders
reminders.frame = frame
reminders:OnEnable()
assert(frame.visible and frame.slots[1].entry.label == "Fortitude")
dead = true
handlers.PLAYER_DEAD("PLAYER_DEAD")
assert(not frame.visible)
reminders:ApplyOptions()
assert(not frame.visible)
dead, ghost = false, true
handlers.PLAYER_ALIVE("PLAYER_ALIVE")
assert(not frame.visible)
reminders:Test(1)
assert(not frame.visible)
reminders._testUntil = 0
ghost = false
handlers.PLAYER_UNGHOST("PLAYER_UNGHOST")
assert(frame.visible and frame.slots[1].entry.label == "Fortitude")
combat = true
handlers.PLAYER_REGEN_DISABLED("PLAYER_REGEN_DISABLED")
assert(not frame.visible)
frame._locked = false
reminders:Test(1)
assert(not frame.visible)
frame._locked, reminders._testUntil = true, 0
combat = false
handlers.PLAYER_REGEN_ENABLED("PLAYER_REGEN_ENABLED")
assert(frame.visible)
options.raidBuff21562 = false
reminders:ApplyOptions()
assert(not frame.visible)
options.raidBuff21562, options.raidBuffs = true, false
reminders:ApplyOptions()
assert(not frame.visible)
options.raidBuffs = true
options.showInRaid = false
reminders:ApplyOptions()
assert(not frame.visible)
print("PASS raid buff reminder, death, ghost, test preview, resurrection, combat, individual buffs and raid visibility")

options.showInRaid, options.raidBuffs = true, false
options.readyCheck, options.clickToApply = true, true
C_Timer = { After = function(delay, fn) if delay < 1 then fn() end end }
C_Item = { GetItemCount = function(id) return id == 241320 and 1 or 0 end }
C_UnitAuras.GetUnitAuras = function() return {{icon=136000}} end
GetWeaponEnchantInfo = function() return true end
GetInventoryItemID = function() return 42 end
GetInventoryItemDurability = function(slot) if slot == 1 then return 19,100 end end
ns.SyncHUDAction = function(slot, kind, id) slot.clickType, slot.clickID = kind, id end
handlers.READY_CHECK("READY_CHECK", "Leader", 30)
assert(frame.visible and frame.slots[1].entry.key == "flask")
assert(frame.slots[1].clickType == "item" and frame.slots[1].clickID == 241320)
assert(frame.slots[2].entry.key == "rune" and frame.slots[3].entry.key == "repair")
assert(rawget(frame.slots[4], "entry") == nil)
handlers.READY_CHECK_FINISHED("READY_CHECK_FINISHED")
assert(not frame.visible)
print("PASS ready check, equipped weapon, food, durability and owned flask click assignment")
