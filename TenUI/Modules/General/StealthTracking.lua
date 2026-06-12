local addonName, ns = ...

local CreateFrame       = CreateFrame
local UIParent          = UIParent
local UnitClass         = UnitClass
local IsStealthed       = IsStealthed
local IsMounted         = IsMounted
local IsInInstance      = IsInInstance
local GetSpecialization = GetSpecialization
local InCombatLockdown  = InCombatLockdown
local issecretvalue     = issecretvalue
local pcall             = pcall
local type              = type

local SPELL_STEALTH      = 1784
local SPELL_PROWL        = 5215
local SPELL_BURNING_RUSH = 111400

local FALLBACK_STEALTH      = 132320
local FALLBACK_PROWL        = 132089
local FALLBACK_BURNING_RUSH = 538043

local DEFAULTS = {
    enabled          = false,
    rogue            = true,
    druidFeral       = true,
    druidBalance     = false,
    druidGuardian    = false,
    druidResto       = false,
    warlockBurningRush = true,
    iconSize         = 36,
    hideWhileMounted = true,
    instanceOnly     = false,
    point            = "CENTER",
    x                = 0,
    y                = -150,
}

local StealthTracking = {
    profileRef = nil,
    frame      = nil,
    _testUntil = 0,
    _handlers  = nil,
    _auraFrame = nil,
    _rushActive = false,
}
ns.StealthTracking = StealthTracking

local function dlog(fmt, ...)
    if ns.Debug and ns.Debug.Log then
        ns.Debug:Log("[StealthTracking] " .. tostring(fmt), ...)
    end
end

local function getOpts()
    local parent = StealthTracking.profileRef
    if type(parent) ~= "table" then return nil end
    parent.stealthTracking = parent.stealthTracking or {}
    return parent.stealthTracking
end

local function playerClass()
    local _, token = UnitClass("player")
    return token
end

local function spellIcon(spellID, fallback)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and tex ~= nil then
            return tex
        end
    end
    return fallback
end

local function isBurningRushActive()
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then
        return false
    end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, SPELL_BURNING_RUSH)
    if not ok then return false end
    if aura == nil then return false end
    return true
end

local function stealthRelevant(o)
    local class = playerClass()
    if class == "ROGUE" then
        return o.rogue == true
    end
    if class == "DRUID" then
        local spec = GetSpecialization()
        if spec == 2 then return o.druidFeral    == true end
        if spec == 1 then return o.druidBalance  == true end
        if spec == 3 then return o.druidGuardian == true end
        if spec == 4 then return o.druidResto    == true end
        return o.druidFeral == true
    end
    return false
end

local function stealthIconForClass()
    if playerClass() == "DRUID" then
        return spellIcon(SPELL_PROWL, FALLBACK_PROWL)
    end
    return spellIcon(SPELL_STEALTH, FALLBACK_STEALTH)
end

local function buildFrame()
    if StealthTracking.frame then return StealthTracking.frame end

    local f = CreateFrame("Frame", "TenUIStealthTrackingFrame", UIParent)
    f:SetSize(40, 40)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f._locked = true
    f:Hide()

    local function makeSlot()
        local slot = CreateFrame("Frame", nil, f)
        slot:EnableMouse(false)
        local tex = slot:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(slot)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        slot.icon = tex
        slot:Hide()
        return slot
    end
    f.stealthSlot = makeSlot()
    f.rushSlot    = makeSlot()

    ns.QoLDrag.Attach(f, getOpts, function(o)
        dlog("position saved -> %.0f, %.0f", o.x or 0, o.y or 0)
    end)

    StealthTracking.frame = f
    return f
end

local function layout(showStealth, showRush)
    local f = StealthTracking.frame
    local o = getOpts()
    if not (f and o) then return end

    local size    = o.iconSize or DEFAULTS.iconSize
    local spacing = 4
    local shown   = (showStealth and 1 or 0) + (showRush and 1 or 0)
    local width   = (shown > 0) and (shown * size + (shown - 1) * spacing) or size

    f:SetSize(width, size)
    if not f._dragging then
        f:ClearAllPoints()
        f:SetPoint(o.point or "CENTER", UIParent, o.point or "CENTER", o.x or 0, o.y or 0)
    end

    f.stealthSlot:SetSize(size, size)
    f.rushSlot:SetSize(size, size)
    f.stealthSlot:ClearAllPoints()
    f.rushSlot:ClearAllPoints()

    if showStealth and showRush then
        f.stealthSlot:SetPoint("LEFT", f, "LEFT", 0, 0)
        f.rushSlot:SetPoint("LEFT", f.stealthSlot, "RIGHT", spacing, 0)
    elseif showStealth then
        f.stealthSlot:SetPoint("CENTER", f, "CENTER", 0, 0)
    elseif showRush then
        f.rushSlot:SetPoint("CENTER", f, "CENTER", 0, 0)
    end

    f.stealthSlot:SetShown(showStealth and true or false)
    f.rushSlot:SetShown(showRush and true or false)
end

local function update()
    local f = StealthTracking.frame
    if not f then return end
    local o = getOpts()
    if not o then return end

    if f._locked == false then
        f.stealthSlot.icon:SetTexture(stealthIconForClass())
        f.rushSlot.icon:SetTexture(spellIcon(SPELL_BURNING_RUSH, FALLBACK_BURNING_RUSH))
        layout(true, true)
        f:Show()
        return
    end

    local now = GetTime and GetTime() or 0
    local testing = StealthTracking._testUntil > now

    if not o.enabled and not testing then
        f:Hide()
        return
    end

    if not testing then
        if o.hideWhileMounted and IsMounted() then
            f:Hide()
            return
        end
        if o.instanceOnly then
            local inInstance = IsInInstance()
            if not inInstance then
                f:Hide()
                return
            end
        end
    end

    local showStealth = false
    local showRush    = false

    if testing then
        showStealth = true
        showRush = (playerClass() == "WARLOCK")
    else
        if stealthRelevant(o) and IsStealthed() then
            showStealth = true
        end
        if playerClass() == "WARLOCK" and o.warlockBurningRush then
            showRush = StealthTracking._rushActive
        end
    end

    if not showStealth and not showRush then
        f:Hide()
        return
    end

    if showStealth then
        f.stealthSlot.icon:SetTexture(stealthIconForClass())
    end
    if showRush then
        f.rushSlot.icon:SetTexture(spellIcon(SPELL_BURNING_RUSH, FALLBACK_BURNING_RUSH))
    end

    layout(showStealth, showRush)
    f:SetAlpha(1)
    f:Show()
end

local function refreshRush()
    local o = getOpts()
    if o and playerClass() == "WARLOCK" and o.warlockBurningRush then
        StealthTracking._rushActive = isBurningRushActive()
    else
        StealthTracking._rushActive = false
    end
end

local function syncAuraRegistration()
    local o = getOpts()
    local want = o and o.enabled and o.warlockBurningRush
        and playerClass() == "WARLOCK" or false

    local af = StealthTracking._auraFrame
    if want then
        if not af then
            af = CreateFrame("Frame")
            af:SetScript("OnEvent", function()
                refreshRush()
                update()
            end)
            StealthTracking._auraFrame = af
        end
        if not af._registered then
            af:RegisterUnitEvent("UNIT_AURA", "player")
            af._registered = true
        end
    elseif af and af._registered then
        af:UnregisterEvent("UNIT_AURA")
        af._registered = false
        StealthTracking._rushActive = false
    end
end

function StealthTracking:Test(seconds)
    if not self.frame then buildFrame() end
    local o = getOpts()
    if not o then
        dlog("Test: no profile (savedvars not ready?)")
        return false
    end
    local dur = tonumber(seconds) or 5
    self._testUntil = (GetTime and GetTime() or 0) + dur
    update()
    if C_Timer and C_Timer.After then
        C_Timer.After(dur + 0.1, function()
            update()
        end)
    end
    dlog("test display forced for %ds", dur)
    return true
end

function StealthTracking:ApplyOptions()
    if not self.frame then return end
    syncAuraRegistration()
    refreshRush()
    update()
end

function StealthTracking:IsEnabled()
    local o = getOpts()
    return o and o.enabled == true or false
end

function StealthTracking:SetUnlocked(unlocked)
    if not self.frame then buildFrame() end
    local f = self.frame
    f._locked = not unlocked
    f:EnableMouse(unlocked and true or false)
    update()
end

function StealthTracking:ResetPosition()
    local o = getOpts()
    if not o then return end
    o.point = DEFAULTS.point
    o.x     = DEFAULTS.x
    o.y     = DEFAULTS.y
    update()
    dlog("position reset to default (%s %d, %d)", DEFAULTS.point, DEFAULTS.x, DEFAULTS.y)
end

function StealthTracking:CenterHorizontally()
    local o = getOpts()
    if not o then return end
    o.point = "CENTER"
    o.x = 0
    update()
    dlog("centered horizontally (x = 0, y = %.0f)", o.y or 0)
end

local LIFECYCLE_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "UPDATE_STEALTH",
    "UPDATE_SHAPESHIFT_FORM",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_MOUNT_DISPLAY_CHANGED",
    "PLAYER_UPDATE_RESTING",
    "PLAYER_SPECIALIZATION_CHANGED",
    "TRAIT_CONFIG_UPDATED",
}

local function onLifecycleEvent(event)
    if event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "TRAIT_CONFIG_UPDATED" then
        syncAuraRegistration()
        refreshRush()
    end
    update()
end

function StealthTracking:OnEnable()
    local p = ns:GetProfile()
    p.modules = p.modules or {}
    p.modules.General = p.modules.General or {}
    p.modules.General.stealthTracking = p.modules.General.stealthTracking or {}
    if ns._deepCopyMissing then
        ns._deepCopyMissing(p.modules.General.stealthTracking, DEFAULTS)
    end
    self.profileRef = p.modules.General

    buildFrame()

    self._handlers = {}
    for i = 1, #LIFECYCLE_EVENTS do
        local ev = LIFECYCLE_EVENTS[i]
        self._handlers[#self._handlers + 1] = {
            event = ev,
            fn    = ns:RegisterEvent(ev, onLifecycleEvent),
        }
    end

    syncAuraRegistration()
    refreshRush()
    update()

    dlog("enabled (indicator %s)", self:IsEnabled() and "ON" or "off")
end

function StealthTracking:OnDisable()
    if self._handlers then
        for i = 1, #self._handlers do
            local h = self._handlers[i]
            ns:UnregisterEvent(h.event, h.fn)
        end
        self._handlers = nil
    end
    if self._auraFrame and self._auraFrame._registered then
        self._auraFrame:UnregisterEvent("UNIT_AURA")
        self._auraFrame._registered = false
    end
    if self.frame then
        self.frame:Hide()
    end
end

StealthTracking.DEFAULTS = DEFAULTS

ns:RegisterModule("StealthTracking", {
    OnEnable  = function() StealthTracking:OnEnable() end,
    OnDisable = function() StealthTracking:OnDisable() end,
})
