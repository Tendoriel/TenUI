local addonName, ns = ...

local CreateFrame      = CreateFrame
local UIParent         = UIParent
local PlaySoundFile    = PlaySoundFile
local InCombatLockdown = InCombatLockdown
local type             = type
local pcall            = pcall

local DEFAULTS = {
    enabled         = false,
    enterText       = "++ COMBAT",
    leaveText       = "-- COMBAT",
    enterColor      = { 1.0, 0.25, 0.2, 1 },
    leaveColor      = { 0.3, 1.0, 0.4, 1 },
    font            = "default",
    fontSize        = 32,
    holdDuration    = 0.9,
    fadeInDuration  = 0.25,
    fadeOutDuration = 0.6,
    soundEnabled    = false,
    soundFile       = "Sound\\Interface\\RaidWarning.ogg",
    point           = "CENTER",
    x               = 0,
    y               = 200,
}

local CombatAlerts = {
    profileRef = nil,
    frame      = nil,
    text       = nil,
    _enterCB   = nil,
    _leaveCB   = nil,
}
ns.CombatAlerts = CombatAlerts

local function dlog(fmt, ...)
    if ns.Debug and ns.Debug.Verbose then
        ns.Debug:Verbose("combatalerts", "[CombatAlerts] " .. tostring(fmt), ...)
    end
end

local function getOpts()
    local parent = CombatAlerts.profileRef
    if type(parent) ~= "table" then return nil end
    parent.combatAlerts = parent.combatAlerts or {}
    return parent.combatAlerts
end

local function resolveFontPath(key)
    if ns.Controls and ns.Controls.ResolveFontPath then
        local p = ns.Controls.ResolveFontPath(key)
        if p then return p end
    end
    local W = ns.Widgets
    if W and W.resolveMedia then
        return W.resolveMedia("font", key, W.DEFAULT_FONT)
    end
    return [[Fonts\FRIZQT__.TTF]]
end

local function buildFrame()
    if CombatAlerts.frame then return CombatAlerts.frame end

    local f = CreateFrame("Frame", "TenUICombatAlertFrame", UIParent)
    f:SetSize(320, 60)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:Hide()

    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER", f, "CENTER", 0, 0)
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    fs:SetWordWrap(false)
    f.text = fs

    ns.QoLDrag.Attach(f, getOpts, function(o)
        dlog("position saved -> %.0f, %.0f", o.x or 0, o.y or 0)
    end)

    local ag = f:CreateAnimationGroup()
    f._animGroup = ag

    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetOrder(1)
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    f._fadeIn = fadeIn

    local hold = ag:CreateAnimation("Alpha")
    hold:SetOrder(2)
    hold:SetFromAlpha(1)
    hold:SetToAlpha(1)
    f._hold = hold

    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetOrder(3)
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    f._fadeOut = fadeOut

    ag:SetScript("OnFinished", function()
        f:SetAlpha(0)
        f:Hide()
    end)
    ag:SetScript("OnStop", function()
    end)

    CombatAlerts.frame = f
    CombatAlerts.text  = fs
    return f
end

local function applyToFrame()
    local f = CombatAlerts.frame
    local o = getOpts()
    if not f or not o then return end

    f.text:SetFont(resolveFontPath(o.font), o.fontSize or DEFAULTS.fontSize, "OUTLINE")

    if f._fadeIn  then f._fadeIn:SetDuration(o.fadeInDuration  or DEFAULTS.fadeInDuration)  end
    if f._hold    then f._hold:SetDuration(o.holdDuration      or DEFAULTS.holdDuration)    end
    if f._fadeOut then f._fadeOut:SetDuration(o.fadeOutDuration or DEFAULTS.fadeOutDuration) end

    if not f._dragging then
        f:ClearAllPoints()
        f:SetPoint(o.point or "CENTER", UIParent, o.point or "CENTER", o.x or 0, o.y or 0)
    end
end

local function showAlert(text, color)
    local f = CombatAlerts.frame
    if not f then return end

    applyToFrame()

    f.text:SetText(text or "")
    local c = color or { 1, 1, 1, 1 }
    f.text:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)

    if f._animGroup then f._animGroup:Stop() end
    f:SetAlpha(0)
    f:Show()
    if f._animGroup then f._animGroup:Play() end
end

local function maybePlaySound(o)
    if not (o and o.soundEnabled and o.soundFile and o.soundFile ~= "") then return end
    pcall(PlaySoundFile, o.soundFile, "Master")
end

function CombatAlerts:Test()
    if not self.frame then buildFrame() end
    local o = getOpts()
    if not o then
        dlog("Test: no profile (savedvars not ready?)")
        return false
    end
    showAlert(o.enterText or DEFAULTS.enterText, o.enterColor or DEFAULTS.enterColor)
    maybePlaySound(o)
    return true
end

function CombatAlerts:ApplyOptions()
    if not self.frame then return end
    applyToFrame()
end

function CombatAlerts:IsEnabled()
    local o = getOpts()
    return o and o.enabled == true or false
end

local function onEnterCombat()
    local f = CombatAlerts.frame
    if f and f._locked == false then return end
    local o = getOpts()
    if not (o and o.enabled) then return end
    showAlert(o.enterText or DEFAULTS.enterText, o.enterColor or DEFAULTS.enterColor)
    maybePlaySound(o)
end

local function onLeaveCombat()
    local f = CombatAlerts.frame
    if f and f._locked == false then return end
    local o = getOpts()
    if not (o and o.enabled) then return end
    showAlert(o.leaveText or DEFAULTS.leaveText, o.leaveColor or DEFAULTS.leaveColor)
    maybePlaySound(o)
end

function CombatAlerts:OnEnable(_, profile)
    local p = ns:GetProfile()
    p.modules = p.modules or {}
    p.modules.General = p.modules.General or {}
    p.modules.General.combatAlerts = p.modules.General.combatAlerts or {}
    if ns._deepCopyMissing then
        ns._deepCopyMissing(p.modules.General.combatAlerts, DEFAULTS)
    end
    self.profileRef = p.modules.General

    buildFrame()
    applyToFrame()

    self._enterCB = ns:RegisterEvent("PLAYER_REGEN_DISABLED", onEnterCombat)
    self._leaveCB = ns:RegisterEvent("PLAYER_REGEN_ENABLED",  onLeaveCombat)

    dlog("enabled (alerts %s)", self:IsEnabled() and "ON" or "off")
end

function CombatAlerts:OnDisable()
    if self._enterCB then
        ns:UnregisterEvent("PLAYER_REGEN_DISABLED", self._enterCB)
        self._enterCB = nil
    end
    if self._leaveCB then
        ns:UnregisterEvent("PLAYER_REGEN_ENABLED", self._leaveCB)
        self._leaveCB = nil
    end
    if self.frame then
        if self.frame._animGroup then self.frame._animGroup:Stop() end
        self.frame:Hide()
    end
end

function CombatAlerts:SetUnlocked(unlocked)
    if not self.frame then buildFrame() end
    local f = self.frame
    f._locked = not unlocked
    f:EnableMouse(unlocked and true or false)
    if unlocked then
        local o = getOpts()
        applyToFrame()
        f.text:SetText((o and o.enterText) or DEFAULTS.enterText)
        local c = (o and o.enterColor) or DEFAULTS.enterColor
        f.text:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        if f._animGroup then f._animGroup:Stop() end
        f:SetAlpha(1)
        f:Show()
    else
        if f._animGroup then f._animGroup:Stop() end
        f:SetAlpha(0)
        f:Hide()
    end
end

function CombatAlerts:ResetPosition()
    local o = getOpts()
    if not o then return end
    o.point = DEFAULTS.point
    o.x     = DEFAULTS.x
    o.y     = DEFAULTS.y
    applyToFrame()
    dlog("position reset to default (%s %d, %d)", DEFAULTS.point, DEFAULTS.x, DEFAULTS.y)
end

function CombatAlerts:CenterHorizontally()
    local o = getOpts()
    if not o then return end
    o.point = "CENTER"
    o.x = 0
    applyToFrame()
    dlog("centered horizontally (x = 0, y = %.0f)", o.y or 0)
end

CombatAlerts.DEFAULTS = DEFAULTS

ns:RegisterModule("CombatAlerts", {
    OnEnable  = function(mod, profile) CombatAlerts:OnEnable(mod, profile) end,
    OnDisable = function(mod) CombatAlerts:OnDisable() end,
})
