local addonName, ns = ...

local Display = ns.Resources_Display

local Primary   = Display and Display.Primary   or {}
local Secondary = Display and Display.Secondary or {}

local function dlog(fmt, ...)
    if ns.Debug and ns.Debug.Log then
        ns.Debug:Log("[Resources] " .. fmt, ...)
    end
end

local function getSpecDescriptor()
    if Display and Display.getSpecDescriptor then
        return Display.getSpecDescriptor()
    end
    return nil, nil, nil
end

local function getManaColor()
    if Display and Display.getManaColor then
        return Display.getManaColor()
    end
    return { 0, 0.30, 1.00, 1 }
end

local function primary_Refresh()
    if Display and Display.primary_Refresh then Display.primary_Refresh() end
end

local function primary_Rebuild()
    if Display and Display.primary_Rebuild then return Display.primary_Rebuild() end
    return false
end

local function primary_ApplyFont()
    if Display and Display.primary_ApplyFont then Display.primary_ApplyFont() end
end

local function invalidateThresholdCurve()
    if Display and Display.invalidateThresholdCurve then Display.invalidateThresholdCurve() end
end

local function secondary_ApplyValueText()
    if Display and Display.secondary_ApplyValueText then Display.secondary_ApplyValueText() end
end

local function secondary_ApplyStyle()
    if Display and Display.secondary_ApplyStyle then Display.secondary_ApplyStyle() end
end

local function secondary_ApplyTexture()
    if Display and Display.secondary_ApplyTexture then Display.secondary_ApplyTexture() end
end

local function secondary_LayoutPips()
    if Display and Display.secondary_LayoutPips then Display.secondary_LayoutPips() end
end

local function resolvePrimaryColor(profile)
    if Display and Display.resolvePrimaryColor then
        return Display.resolvePrimaryColor(profile)
    end
    return nil
end

local function resolveSecondaryColor(profile)
    if Display and Display.resolveSecondaryColor then
        return Display.resolveSecondaryColor(profile)
    end
    return nil
end

local function resolvePrimaryEnabled(profile)
    if Display and Display.resolvePrimaryEnabled then
        return Display.resolvePrimaryEnabled(profile)
    end
    return true
end

local function resolveSecondaryEnabled(profile)
    if Display and Display.resolveSecondaryEnabled then
        return Display.resolveSecondaryEnabled(profile)
    end
    return true
end

local function resolveResourcesBlock(baseBlock)
    if ns.GetSpecBlock and ns.savedVarsReady then
        local function getBase() return baseBlock end
        local rp = ns:GetSpecBlock("resources", getBase, false, { "specColors", "_specColorsMigrated" })
        if type(rp) == "table" then return rp end
    end
    return baseBlock
end

local Resources = {
    profileRef = nil,
    _baseProfile = nil,
    _combatCB  = nil,
    _enterCB   = nil,
    _leaveCB   = nil,
    _specCB    = nil,
    _combatFrame = nil,
}

ns.Resources = Resources
Resources.Primary   = Primary
Resources.Secondary = Secondary

local DEFAULTS = {
    enabled         = true,
    hideOutOfCombat = false,
    specColors      = {},
    primary = {
        enabled   = true,
        showText  = true,
        texture   = "Interface\\TargetingFrame\\UI-StatusBar",
        font      = "default",
        fontSize  = 12,
        fontFlags = "OUTLINE",
        powerTypeOverride = "AUTO",
        fontAnchor = "RIGHT",
        fontX      = -4,
        fontY      = 0,
        color     = nil,
        threshold = {
            enabled   = false,
            pct       = 20,
            direction = "below",
            r         = 1,
            g         = 0.1,
            b         = 0.1,
        },
        thresholdLines = {
            enabled  = false,
            showCost = true,
        },
    },
    secondary = {
        enabled          = true,
        pipSpacing       = 2,
        color            = nil,
        texture          = "Interface\\TargetingFrame\\UI-StatusBar",
        text             = {},
        style            = {},
    },
}

local _lastCombatState = false
local function applyCombatVisibility(inCombat)
    _lastCombatState = inCombat and true or false
    local profile = Resources.profileRef
    if not profile then return end
    local alpha = 1
    if profile.hideOutOfCombat and not inCombat and not Resources._previewActive then
        alpha = 0
    end
    if Primary.bar and Primary.bar.frame then
        Primary.bar.frame:SetAlpha(alpha)
    end
    if Secondary.container then
        Secondary.container:SetAlpha(alpha)
    end
end

if Display and Display.SetReassert then
    Display.SetReassert(function()
        applyCombatVisibility(_lastCombatState)
    end)
end

Resources._reassertCombatVisibility = function()
    applyCombatVisibility(_lastCombatState)
end

function Resources:OnEnable(_, profile)
    self._baseProfile = profile
    profile = resolveResourcesBlock(profile)
    self.profileRef = profile

    local desc, class, specIdx = getSpecDescriptor()
    if not desc then
        dlog("no Resources support for class=%s specID=%s -- both anchors will be hidden",
             tostring(class), tostring(specIdx))
    else
        dlog("enabling for class=%s specID=%s (%s)",
             tostring(class), tostring(specIdx), desc.name or "?")
    end

    Primary:Enable(profile)
    Secondary:Enable(profile)

    self._enterCB = ns:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        if Resources._previewActive then
            Resources:SetPreview(false)
        end
        applyCombatVisibility(true)
    end)
    self._leaveCB = ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        applyCombatVisibility(false)
    end)

    self._specCB = ns:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(_, unit)
        if unit and unit ~= "player" then return end
        self:ApplyOptions()
    end)

    local InCombatLockdown = InCombatLockdown
    applyCombatVisibility(InCombatLockdown and InCombatLockdown() or false)

    if Display and Display.getActiveSpecColors then
        Display.getActiveSpecColors(profile)
    end

    self:ApplyOptions()
end

function Resources:OnDisable()
    Primary:Disable()
    Secondary:Disable()
    if self._enterCB then
        ns:UnregisterEvent("PLAYER_REGEN_DISABLED", self._enterCB)
        self._enterCB = nil
    end
    if self._leaveCB then
        ns:UnregisterEvent("PLAYER_REGEN_ENABLED", self._leaveCB)
        self._leaveCB = nil
    end
    if self._specCB then
        ns:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED", self._specCB)
        self._specCB = nil
    end
end

function Resources:ApplyOptions()
    local resolved = resolveResourcesBlock(self._baseProfile or self.profileRef)
    if resolved ~= self.profileRef then
        self.profileRef = resolved
        if Primary then
            Primary.profileRef = resolved
            Primary.selfProfile = resolved.primary or {}
        end
        if Secondary then
            Secondary.profileRef = resolved
            Secondary.selfProfile = resolved.secondary or {}
        end
    end
    local profile = self.profileRef
    if not profile then return end

    local sp = profile.primary or {}
    if Primary.bar then
        Primary.selfProfile = sp
        Primary.desc = nil
        primary_Rebuild()
        if sp.texture and Primary.bar.SetTexture then
            Primary.bar:SetTexture(sp.texture)
        end
        if Primary.bar.SetBackground
           and (sp.showBackground ~= nil or type(sp.bgColor) == "table") then
            local bgc = sp.bgColor
            if type(bgc) == "table" then
                Primary.bar:SetBackground(sp.showBackground ~= false,
                    bgc[1], bgc[2], bgc[3], bgc[4])
            else
                Primary.bar:SetBackground(sp.showBackground ~= false)
            end
        end
        if Primary.bar.SetBorder
           and (sp.showBorder ~= nil or type(sp.borderColor) == "table") then
            Primary.bar:SetBorder(sp.showBorder ~= false,
                (type(sp.borderColor) == "table") and sp.borderColor or nil)
        end
        invalidateThresholdCurve()
        local th = sp.threshold
        if th and th.enabled then
            primary_Refresh()
        else
            local c = resolvePrimaryColor(profile)
            if c then
                Primary.bar:SetColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
            else
                local dc = (Primary.desc and Primary.desc.color)
                if (not dc) and (Primary.desc and Primary.desc.powerName == "Mana") then
                    dc = getManaColor()
                end
                if dc then
                    Primary.bar:SetColor(dc[1] or 1, dc[2] or 1, dc[3] or 1, dc[4] or 1)
                end
            end
        end
        primary_ApplyFont()
        if Primary.bar.frame and Primary.bar.frame.rightText then
            Primary.bar.frame.rightText:SetShown(sp.showText ~= false)
        end
        if Primary.bar.frame then
            if resolvePrimaryEnabled(profile) == false then
                Primary.bar.frame:Hide()
            else
                Primary.bar.frame:Show()
            end
        end

        if Display and Display.thLines_SetEnabled then
            local tl = sp.thresholdLines or {}
            Display.thLines_SetEnabled(tl.enabled == true, tl.showCost ~= false)
        end
    end

    local ss = profile.secondary or {}
    if Secondary.container then
        if resolveSecondaryEnabled(profile) == false then
            Secondary.container:Hide()
        else
            Secondary.container:Show()
        end
    end
    if Secondary._kind == "bar" and Secondary.barWidget then
        local cb = resolveSecondaryColor(profile)
        if not cb then
            cb = Secondary.desc and Secondary.desc.color
        end
        if cb and Secondary.barWidget.SetColor then
            Secondary.barWidget:SetColor(cb[1] or 1, cb[2] or 1, cb[3] or 1, cb[4] or 1)
        end
    end
    if #Secondary.pips > 0 then
        local c = resolveSecondaryColor(profile)
        if not c then
            c = Secondary.desc and Secondary.desc.color
        end
        if c then
            if Secondary._kind == "runes" then
                Secondary._runeReadyColor = c
                Secondary._runeChargeColor = {
                    (c[1] or 1) * 0.65,
                    (c[2] or 1) * 0.65,
                    (c[3] or 1) * 0.65,
                    c[4] or 1,
                }
            end
            for i = 1, #Secondary.pips do
                local pip = Secondary.pips[i]
                if pip and pip.SetStatusBarColor then
                    pip:SetStatusBarColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
                end
            end
        end
    end

    Secondary.selfProfile = ss
    secondary_ApplyTexture()
    secondary_LayoutPips()
    secondary_ApplyStyle()
    secondary_ApplyValueText()

    local InCombatLockdown = InCombatLockdown
    applyCombatVisibility(InCombatLockdown and InCombatLockdown() or false)

    dlog("ApplyOptions: primary.enabled=%s primary.color(spec)=%s secondary.enabled=%s secondary.color(spec)=%s",
        tostring(sp.enabled), tostring(resolvePrimaryColor(profile) ~= nil),
        tostring(ss.enabled), tostring(resolveSecondaryColor(profile) ~= nil))
end

function Resources:SetPreview(flag)
    flag = flag and true or false
    if flag and InCombatLockdown and InCombatLockdown() then
        dlog("SetPreview: refused (in combat)")
        return false
    end
    if self._previewActive == flag then return true end
    self._previewActive = flag
    if Display and Display.SetPreviewActive then
        Display.SetPreviewActive(flag)
    end
    local inCombat = InCombatLockdown and InCombatLockdown() or false
    if flag then
        applyCombatVisibility(inCombat)
        if Display and Display.primary_Refresh then Display.primary_Refresh() end
        if Display and Display.secondary_Refresh then Display.secondary_Refresh() end
        dlog("SetPreview: ON")
    else
        self:ApplyOptions()
        if Display and Display.primary_Refresh then Display.primary_Refresh() end
        if Display and Display.secondary_Refresh then Display.secondary_Refresh() end
        dlog("SetPreview: OFF")
    end
    return true
end

function Resources:IsPreview()
    return self._previewActive == true
end

ns:RegisterModule("Resources", {
    defaults = DEFAULTS,
    OnEnable = function(mod, profile) Resources:OnEnable(mod, profile) end,
    OnDisable = function(mod) Resources:OnDisable() end,
})
