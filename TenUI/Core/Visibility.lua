local addonName, ns = ...

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local IsInInstance = IsInInstance
local IsMounted = IsMounted
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local C_Housing = C_Housing
local pcall = pcall
local pairs = pairs
local type = type

local Visibility = {}
ns.Visibility = Visibility

Visibility._inCombat = false

local INSTANCE_TYPES = {
    party    = true,
    raid     = true,
    scenario = true,
    arena    = true,
    pvp      = true,
}

local STATE_LABELS = {
    { key = "always",        label = "Always" },
    { key = "never",         label = "Never" },
    { key = "in_combat",     label = "In Combat" },
    { key = "out_of_combat", label = "Out of Combat" },
    { key = "in_raid",       label = "In Raid" },
    { key = "in_party",      label = "In Party" },
    { key = "solo",          label = "Solo" },
}

Visibility.STATE_LABELS = STATE_LABELS

local VALID_STATES = {}
for i = 1, #STATE_LABELS do
    VALID_STATES[STATE_LABELS[i].key] = true
end

Visibility.VALID_STATES = VALID_STATES

function Visibility:IsInCombat()
    return self._inCombat
end

function Visibility:NormalizeState(state)
    if type(state) == "string" and VALID_STATES[state] then
        return state
    end
    return "always"
end

local function isInTrackedInstance()
    local inInstance, instanceType = IsInInstance()
    if not inInstance then return false end
    return INSTANCE_TYPES[instanceType] == true
end

function Visibility:OptionsHide(opt)
    if type(opt) ~= "table" then return false end
    if opt.onlyInstances then
        if not isInTrackedInstance() then
            return true
        end
    end
    if opt.hideHousing then
        if C_Housing and C_Housing.IsInsideHouseOrPlot and C_Housing.IsInsideHouseOrPlot() then
            return true
        end
    end
    if opt.hideMounted then
        if IsMounted and IsMounted() then
            return true
        end
    end
    return false
end

function Visibility:StateShow(state)
    state = self:NormalizeState(state)
    if state == "always" then return true end
    if state == "never" then return false end
    if state == "in_combat" then return self._inCombat end
    if state == "out_of_combat" then return not self._inCombat end
    if state == "in_raid" then return IsInRaid() end
    if state == "in_party" then return IsInGroup() and not IsInRaid() end
    if state == "solo" then return not IsInGroup() end
    return true
end

function Visibility:ShouldShow(cfg)
    if type(cfg) ~= "table" then return true end
    if self:OptionsHide(cfg.options) then return false end
    return self:StateShow(cfg.state)
end

local function defaultCfg()
    return {
        state = "always",
        options = { onlyInstances = false, hideHousing = false, hideMounted = false },
    }
end

Visibility.defaultCfg = defaultCfg

local entries = {}

function Visibility:RegisterEntry(name, getCfg)
    if type(name) ~= "string" or name == "" then return end
    if type(getCfg) ~= "function" then return end
    entries[name] = { name = name, getCfg = getCfg }
end

function Visibility:UnregisterEntry(name)
    entries[name] = nil
end

function Visibility:HasEntry(name)
    return entries[name] ~= nil
end

local function isEditModeActive()
    return ns.EditMode and ns.EditMode.IsActive and ns.EditMode:IsActive() == true
end

local function updateEntry(entry)
    local cfg = entry.getCfg()
    local show = Visibility:ShouldShow(cfg)
    if ns.Anchors and ns.Anchors.SetAnchorVisible then
        ns.Anchors:SetAnchorVisible(entry.name, show)
    end
end

function Visibility:RequestUpdate()
    if not ns.savedVarsReady then return end
    if isEditModeActive() then
        if ns.Anchors and ns.Anchors.SetAnchorVisible then
            for name in pairs(entries) do
                ns.Anchors:SetAnchorVisible(name, true)
            end
        end
        return
    end
    for _, entry in pairs(entries) do
        local ok, err = pcall(updateEntry, entry)
        if not ok and ns.Debug and ns.Debug.Log then
            ns.Debug:Log("Visibility update error for %s: %s", tostring(entry.name), tostring(err))
        end
    end
end

function Visibility:UpdateOne(name)
    if not ns.savedVarsReady then return end
    local entry = entries[name]
    if not entry then return end
    if isEditModeActive() then
        if ns.Anchors and ns.Anchors.SetAnchorVisible then
            ns.Anchors:SetAnchorVisible(name, true)
        end
        return
    end
    local ok, err = pcall(updateEntry, entry)
    if not ok and ns.Debug and ns.Debug.Log then
        ns.Debug:Log("Visibility update error for %s: %s", tostring(name), tostring(err))
    end
end

local _pending = false
local function deferredRequest()
    _pending = false
    Visibility:RequestUpdate()
end

function Visibility:ScheduleUpdate()
    if _pending then return end
    _pending = true
    C_Timer.After(0, deferredRequest)
end

local visFrame = CreateFrame("Frame", "TenUIVisibilityFrame")
visFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
visFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
visFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
visFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
visFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
visFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
visFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
visFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")

visFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        Visibility._inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        Visibility._inCombat = false
    end
    Visibility:ScheduleUpdate()
end)

ns:RegisterMessage("SAVEDVARS_READY", function()
    Visibility:ScheduleUpdate()
end)

ns:RegisterMessage("PROFILE_CHANGED", function()
    Visibility:ScheduleUpdate()
end)

ns:RegisterMessage("EDIT_MODE_CHANGED", function()
    Visibility:ScheduleUpdate()
end)

ns:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(_, unit)
    if unit and unit ~= "player" then return end
    Visibility:ScheduleUpdate()
end)
