local addonName, ns = ...

local CreateFrame        = CreateFrame
local C_Timer            = C_Timer
local C_PlayerInfo       = C_PlayerInfo
local C_Spell            = C_Spell
local C_ChallengeMode    = C_ChallengeMode
local C_UnitAuras        = C_UnitAuras
local IsMounted          = IsMounted
local IsInInstance       = IsInInstance
local InCombatLockdown   = InCombatLockdown
local UnitAffectingCombat = UnitAffectingCombat
local GetTime            = GetTime
local UnitClass          = UnitClass
local pcall              = pcall
local type               = type
local ipairs             = ipairs
local issecretvalue      = issecretvalue
local floor              = math.floor
local min               = math.min
local max               = math.max
local abs               = math.abs
local format            = string.format

local SPELL_SKYWARD_ASCENT = 372610
local SPELL_SECOND_WIND    = 425782
local SPELL_WHIRLING_SURGE = 361584
local SKYRIDING_PIPS  = 6
local SECONDWIND_PIPS = 3
local BASE_RUN_SPEED  = 7.0
local UPDATE_THROTTLE = 1 / 30
local SPEED_EMA_ALPHA = 0.25
local WHITE_TEX       = "Interface\\Buttons\\WHITE8x8"
local DEFAULT_WS_ICON = 135860

local DRUID_MOUNT_FORM_SPELLS = { 783, 33943, 40120, 165962, 210053 }

local DEFAULTS = {
    enabled      = true,
    hideInCombat = false,
    showInstances = false,

    width            = 240,
    speedHeight      = 14,
    skyridingHeight  = 10,
    secondWindHeight = 6,
    gap              = 2,
    stackSpacing     = 2,

    borderThickness = 1,
    borderColor     = { r = 0.0, g = 0.0, b = 0.0, a = 1.0 },

    barTexture = "Blizzard",

    maxSpeed          = 1300,
    thrillThreshold   = 789,
    thrillColorToggle = true,
    normalColor       = { r = 0.055, g = 0.667, b = 0.761, a = 1.0 },
    thrillColor       = { r = 0.902, g = 0.494, b = 0.133, a = 1.0 },
    speedBarBg        = { r = 0.10, g = 0.10, b = 0.10, a = 0.80 },
    tickColor         = { r = 1.00, g = 1.00, b = 1.00, a = 0.50 },

    speedText = {
        enabled = true,
        justify = "CENTER",
        size    = 12,
        offsetX = 0,
        offsetY = 0,
    },

    skyridingFilled  = { r = 0.047, g = 0.824, b = 0.624, a = 1.0 },
    skyridingBg      = { r = 0.10, g = 0.10, b = 0.10, a = 0.80 },

    secondWindFilled = { r = 0.902, g = 0.706, b = 0.133, a = 1.0 },
    secondWindBg     = { r = 0.10, g = 0.10, b = 0.10, a = 0.80 },

    whirlingSurgeText = {
        enabled = true,
        justify = "CENTER",
        size    = 12,
        offsetX = 0,
        offsetY = 0,
    },
}

local DragonRiding = {
    profileRef = nil,
    anchor     = nil,
    content    = nil,
    speedBar   = nil,
    skyFrame   = nil,
    swFrame    = nil,
    wsIcon     = nil,
    evtFrame   = nil,
    _enabled   = false,
    _built     = false,
    _spellEventsRegistered = false,
    _elapsed       = 0,
    _smoothedSpeed = 0,
    _skyridingDirty  = true,
    _secondWindDirty = true,
    _whirlingDirty   = true,
    _lastSpeedApplied = -1,
    _lastSkyCur = -1, _lastSkyProgress = -1,
    _lastSwCur  = -1, _lastSwProgress  = -1,
    _lastCdStart = -1, _lastCdDur = -1,
    _playerClass = nil,
}
ns.DragonRiding = DragonRiding

local function dlog(...)
    if ns.Debug and ns.Debug.Log then
        ns.Debug:Log("[DragonRiding] " .. format(...))
    end
end

local function isSecret(v)
    return type(issecretvalue) == "function" and issecretvalue(v)
end

local function resolveTexture(key)
    if ns.Widgets and ns.Widgets.resolveMedia then
        local ok, path = pcall(ns.Widgets.resolveMedia, "statusbar", key, WHITE_TEX)
        if ok and type(path) == "string" and path ~= "" then
            return path
        end
    end
    return WHITE_TEX
end

local function resolveFontPath(key, size)
    local path
    if ns.UI and ns.UI.ResolveFontPath then
        local ok, p = pcall(ns.UI.ResolveFontPath, key)
        if ok then path = p end
    end
    if type(path) ~= "string" or path == "" then path = "Fonts\\FRIZQT__.TTF" end
    return path, size or 12
end

function DragonRiding:GetProfile()
    if not ns.savedVarsReady then return nil end
    local p = ns:GetProfile()
    p.modules = p.modules or {}
    p.modules.DragonRiding = p.modules.DragonRiding or {}
    if ns._deepCopyMissing then
        ns._deepCopyMissing(p.modules.DragonRiding, DEFAULTS)
    end
    return p.modules.DragonRiding
end

function DragonRiding:IsInLockedContent()
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive then
        local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
        if ok and active then return true end
    end
    local _, instanceType = IsInInstance()
    if instanceType == "raid" or instanceType == "party" then
        return true
    end
    return false
end

function DragonRiding:IsPlayerMountedLike()
    if IsMounted and IsMounted() then return true end
    if self._playerClass ~= "DRUID" then return false end
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for i = 1, #DRUID_MOUNT_FORM_SPELLS do
            local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, DRUID_MOUNT_FORM_SPELLS[i])
            if ok and aura then return true end
        end
    end
    return false
end

function DragonRiding:IsOnSkyridingMount()
    if not self:IsPlayerMountedLike() then return false end
    if not (C_PlayerInfo and C_PlayerInfo.GetGlidingInfo) then return false end
    local ok, _, canGlide = pcall(C_PlayerInfo.GetGlidingInfo)
    return ok and canGlide == true
end

function DragonRiding:GetSkyridingSpeed()
    if not (C_PlayerInfo and C_PlayerInfo.GetGlidingInfo) then
        self._smoothedSpeed = self._smoothedSpeed * (1 - SPEED_EMA_ALPHA)
        return false, self._smoothedSpeed
    end
    local ok, isGliding, _, forwardSpeed = pcall(C_PlayerInfo.GetGlidingInfo)
    if not ok or not isGliding or isSecret(forwardSpeed) then
        self._smoothedSpeed = self._smoothedSpeed * (1 - SPEED_EMA_ALPHA)
        return false, self._smoothedSpeed
    end
    self._smoothedSpeed = self._smoothedSpeed + SPEED_EMA_ALPHA * ((forwardSpeed or 0) - self._smoothedSpeed)
    return true, self._smoothedSpeed
end

local function createSolidTexture(parent, layer, sublevel, r, g, b, a)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    tex:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
    return tex
end

local function ensureBorder(frame)
    if not frame or frame._drBorder then return end
    local b = {}
    b.top    = createSolidTexture(frame, "OVERLAY", 7)
    b.bottom = createSolidTexture(frame, "OVERLAY", 7)
    b.left   = createSolidTexture(frame, "OVERLAY", 7)
    b.right  = createSolidTexture(frame, "OVERLAY", 7)
    frame._drBorder = b
end

local function applyBorder(frame, thick, c)
    local b = frame and frame._drBorder
    if not b then return end
    if not thick or thick <= 0 then
        b.top:Hide() b.bottom:Hide() b.left:Hide() b.right:Hide()
        return
    end
    local r, g, bl, a = c.r, c.g, c.b, c.a
    b.top:SetColorTexture(r, g, bl, a)
    b.bottom:SetColorTexture(r, g, bl, a)
    b.left:SetColorTexture(r, g, bl, a)
    b.right:SetColorTexture(r, g, bl, a)
    b.top:ClearAllPoints()
    b.top:SetPoint("TOPLEFT", frame, "TOPLEFT", -thick, thick)
    b.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", thick, thick)
    b.top:SetHeight(thick)
    b.bottom:ClearAllPoints()
    b.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -thick, -thick)
    b.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", thick, -thick)
    b.bottom:SetHeight(thick)
    b.left:ClearAllPoints()
    b.left:SetPoint("TOPLEFT", frame, "TOPLEFT", -thick, thick)
    b.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -thick, -thick)
    b.left:SetWidth(thick)
    b.right:ClearAllPoints()
    b.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", thick, thick)
    b.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", thick, -thick)
    b.right:SetWidth(thick)
    b.top:Show() b.bottom:Show() b.left:Show() b.right:Show()
end

local function createSpeedBar(parent)
    local f = CreateFrame("StatusBar", nil, parent)
    f:EnableMouse(false)
    f:SetMinMaxValues(0, 1)
    f:SetValue(0)
    f:SetStatusBarTexture(WHITE_TEX)
    f.bg = createSolidTexture(f, "BACKGROUND", 0)
    f.bg:SetAllPoints(f)
    f.tick = createSolidTexture(f, "OVERLAY", 5)
    f.text = f:CreateFontString(nil, "OVERLAY")
    ensureBorder(f)
    return f
end

local function createStackFrame(parent, pipCount)
    local f = CreateFrame("Frame", nil, parent)
    f:EnableMouse(false)
    f.pips = {}
    for i = 1, pipCount do
        local pip = CreateFrame("StatusBar", nil, f)
        pip:EnableMouse(false)
        pip:SetMinMaxValues(0, 1)
        pip:SetValue(0)
        pip:SetStatusBarTexture(WHITE_TEX)
        pip.bg = createSolidTexture(pip, "BACKGROUND", 0)
        pip.bg:SetAllPoints(pip)
        ensureBorder(pip)
        f.pips[i] = pip
    end
    return f
end

local function createWhirlingSurgeIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:EnableMouse(false)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints(f)
    local iconFile = DEFAULT_WS_ICON
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, SPELL_WHIRLING_SURGE)
        if ok and info and info.iconID then iconFile = info.iconID end
    end
    f.tex:SetTexture(iconFile)
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f)
    f.cd:EnableMouse(false)
    f.cd:SetDrawEdge(false)
    f.cd:SetHideCountdownNumbers(true)
    f.textFrame = CreateFrame("Frame", nil, f)
    f.textFrame:SetAllPoints(f)
    f.textFrame:EnableMouse(false)
    f.textFrame:SetFrameLevel(f.cd:GetFrameLevel() + 1)
    f.text = f.textFrame:CreateFontString(nil, "OVERLAY")
    ensureBorder(f)
    return f
end

local function layoutPips(frame, pipCount, width, height, spacing)
    local widthAvail = max(0, width - (pipCount - 1) * spacing)
    local pipW = floor(widthAvail / pipCount)
    local rem  = widthAvail - pipW * pipCount
    local x = 0
    for i = 1, pipCount do
        local thisW = pipW + (i <= rem and 1 or 0)
        local pip = frame.pips[i]
        pip:ClearAllPoints()
        pip:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
        pip:SetSize(thisW, height)
        x = x + thisW + spacing
    end
end

function DragonRiding:Build()
    if self._built then return true end
    local anchor = ns:GetAnchor("DragonRiding")
    if not (anchor and anchor.frame) then
        dlog("Build: DragonRiding anchor not registered yet -- aborting")
        return false
    end
    self.anchor = anchor

    local content = CreateFrame("Frame", "TenUIDragonRidingContent", anchor.frame)
    content:EnableMouse(false)
    content:SetAllPoints(anchor.frame)
    content:Hide()
    self.content = content

    self.speedBar = createSpeedBar(content)
    self.skyFrame = createStackFrame(content, SKYRIDING_PIPS)
    self.swFrame  = createStackFrame(content, SECONDWIND_PIPS)
    self.wsIcon   = createWhirlingSurgeIcon(content)

    self._built = true
    self:Layout()
    self:Redraw()
    return true
end

function DragonRiding:Layout()
    if not self._built then return end
    local p = self.profileRef
    if not p then return end
    local content = self.content

    local totalH   = p.secondWindHeight + p.gap + p.skyridingHeight + p.gap + p.speedHeight
    local iconSize = totalH
    local totalW   = p.width + p.gap + iconSize

    content:ClearAllPoints()
    content:SetPoint("CENTER", self.anchor.frame, "CENTER", 0, 0)
    content:SetSize(totalW, totalH)

    self.speedBar:ClearAllPoints()
    self.speedBar:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
    self.speedBar:SetSize(p.width, p.speedHeight)

    self.skyFrame:ClearAllPoints()
    self.skyFrame:SetPoint("BOTTOMLEFT", self.speedBar, "TOPLEFT", 0, p.gap)
    self.skyFrame:SetSize(p.width, p.skyridingHeight)
    layoutPips(self.skyFrame, SKYRIDING_PIPS, p.width, p.skyridingHeight, p.stackSpacing)

    self.swFrame:ClearAllPoints()
    self.swFrame:SetPoint("BOTTOM", self.skyFrame, "TOP", 0, p.gap)
    self.swFrame:SetSize(p.width, p.secondWindHeight)
    layoutPips(self.swFrame, SECONDWIND_PIPS, p.width, p.secondWindHeight, p.stackSpacing)

    self.wsIcon:ClearAllPoints()
    self.wsIcon:SetPoint("BOTTOMLEFT", self.speedBar, "BOTTOMRIGHT", p.gap, 0)
    self.wsIcon:SetSize(iconSize, iconSize)

    if ns.savedVarsReady and not InCombatLockdown() then
        ns:AutoFitAnchor("DragonRiding", totalW, totalH)
    end
end

function DragonRiding:Redraw()
    if not self._built then return end
    local p = self.profileRef
    if not p then return end

    local texPath = resolveTexture(p.barTexture or "Blizzard")
    self.speedBar:SetStatusBarTexture(texPath)
    for i = 1, SKYRIDING_PIPS do self.skyFrame.pips[i]:SetStatusBarTexture(texPath) end
    for i = 1, SECONDWIND_PIPS do self.swFrame.pips[i]:SetStatusBarTexture(texPath) end

    local c = p.normalColor
    self.speedBar:SetStatusBarColor(c.r, c.g, c.b, c.a)
    self.speedBar.bg:SetColorTexture(p.speedBarBg.r, p.speedBarBg.g, p.speedBarBg.b, p.speedBarBg.a)

    local tickFrac = (p.thrillThreshold or 0) / (p.maxSpeed > 0 and p.maxSpeed or 1)
    tickFrac = max(0, min(1, tickFrac))
    self.speedBar.tick:ClearAllPoints()
    self.speedBar.tick:SetPoint("TOP",    self.speedBar, "TOPLEFT",    p.width * tickFrac, 0)
    self.speedBar.tick:SetPoint("BOTTOM", self.speedBar, "BOTTOMLEFT", p.width * tickFrac, 0)
    self.speedBar.tick:SetWidth(2)
    self.speedBar.tick:SetColorTexture(p.tickColor.r, p.tickColor.g, p.tickColor.b, p.tickColor.a)

    local stFont, stSize = resolveFontPath("default", p.speedText.size)
    self.speedBar.text:SetFont(stFont, stSize, "OUTLINE")
    self.speedBar.text:ClearAllPoints()
    self.speedBar.text:SetPoint(p.speedText.justify or "CENTER", self.speedBar,
        p.speedText.justify or "CENTER", p.speedText.offsetX or 0, p.speedText.offsetY or 0)
    self.speedBar.text:SetJustifyH(p.speedText.justify or "CENTER")
    self.speedBar.text:SetShown(p.speedText.enabled ~= false)

    for i = 1, SKYRIDING_PIPS do
        local pip = self.skyFrame.pips[i]
        pip:SetStatusBarColor(p.skyridingFilled.r, p.skyridingFilled.g, p.skyridingFilled.b, 1)
        pip.bg:SetColorTexture(p.skyridingBg.r, p.skyridingBg.g, p.skyridingBg.b, p.skyridingBg.a)
    end
    for i = 1, SECONDWIND_PIPS do
        local pip = self.swFrame.pips[i]
        pip:SetStatusBarColor(p.secondWindFilled.r, p.secondWindFilled.g, p.secondWindFilled.b, 1)
        pip.bg:SetColorTexture(p.secondWindBg.r, p.secondWindBg.g, p.secondWindBg.b, p.secondWindBg.a)
    end

    local wsFont, wsSize = resolveFontPath("default", p.whirlingSurgeText.size)
    self.wsIcon.text:SetFont(wsFont, wsSize, "OUTLINE")
    self.wsIcon.text:ClearAllPoints()
    self.wsIcon.text:SetPoint(p.whirlingSurgeText.justify or "CENTER", self.wsIcon,
        p.whirlingSurgeText.justify or "CENTER", p.whirlingSurgeText.offsetX or 0, p.whirlingSurgeText.offsetY or 0)
    self.wsIcon.text:SetJustifyH(p.whirlingSurgeText.justify or "CENTER")
    self.wsIcon.text:SetShown(p.whirlingSurgeText.enabled ~= false)

    local thick = p.borderThickness or 0
    applyBorder(self.speedBar, thick, p.borderColor)
    for i = 1, SKYRIDING_PIPS do applyBorder(self.skyFrame.pips[i], thick, p.borderColor) end
    for i = 1, SECONDWIND_PIPS do applyBorder(self.swFrame.pips[i], thick, p.borderColor) end
    applyBorder(self.wsIcon, thick, p.borderColor)

    self._skyridingDirty  = true
    self._secondWindDirty = true
    self._whirlingDirty   = true
    self._lastSpeedApplied = -1
    self._lastSkyCur, self._lastSkyProgress = -1, -1
    self._lastSwCur,  self._lastSwProgress  = -1, -1
    self._lastCdStart, self._lastCdDur      = -1, -1
end

local function applyPipRow(pips, pipCount, cur, maxC, progress, lastCur, lastProgress, filled, bgAlpha)
    if cur ~= lastCur then
        for i = 1, pipCount do
            local pip = pips[i]
            if i <= cur then
                pip:SetValue(1)
                pip:SetStatusBarColor(filled.r, filled.g, filled.b, 1)
            elseif i == cur + 1 and cur < maxC then
                pip:SetValue(progress)
                pip:SetStatusBarColor(filled.r, filled.g, filled.b, bgAlpha)
            else
                pip:SetValue(0)
                pip:SetStatusBarColor(filled.r, filled.g, filled.b, 1)
            end
        end
        return cur, progress
    elseif cur < maxC and abs(progress - lastProgress) > 0.005 then
        local pip = pips[cur + 1]
        if pip then pip:SetValue(progress) end
        return cur, progress
    end
    return lastCur, lastProgress
end

local function updateChargeRow(self, spellID, pips, pipCount, lastCur, lastProgress, filled)
    if not (C_Spell and C_Spell.GetSpellCharges) then return lastCur, lastProgress, false end
    local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
    if not ok or type(info) ~= "table" then return lastCur, lastProgress, false end
    local cur  = info.currentCharges
    local maxC = info.maxCharges or pipCount
    if isSecret(cur) or isSecret(maxC) then
        return lastCur, lastProgress, true
    end
    cur  = cur or 0
    local progress = 0
    local cdStart = info.cooldownStartTime
    local cdDur   = info.cooldownDuration
    if not isSecret(cdStart) and not isSecret(cdDur) and cdDur and cdDur > 0 then
        local e = GetTime() - (cdStart or 0)
        progress = max(0, min(1, e / cdDur))
    end
    local newCur, newProg = applyPipRow(pips, pipCount, cur, maxC, progress, lastCur, lastProgress, filled, 0.4)
    return newCur, newProg, (cur < maxC)
end

function DragonRiding:OnUpdate(dt)
    self._elapsed = self._elapsed + dt
    if self._elapsed < UPDATE_THROTTLE then return end
    self._elapsed = 0

    local p = self.profileRef
    if not p then return end

    local _, curSpeed = self:GetSkyridingSpeed()
    local speedPct = curSpeed / BASE_RUN_SPEED * 100
    local frac = (p.maxSpeed > 0) and (speedPct / p.maxSpeed) or 0
    frac = max(0, min(1, frac))
    if frac ~= self._lastSpeedApplied then
        self.speedBar:SetValue(frac)
        if p.speedText.enabled ~= false then
            self.speedBar.text:SetText(format("%d%%", floor(speedPct + 0.5)))
        end
        local aboveThrill = (speedPct >= (p.thrillThreshold or 0))
        local col = (p.thrillColorToggle and aboveThrill) and p.thrillColor or p.normalColor
        self.speedBar:SetStatusBarColor(col.r, col.g, col.b, col.a)
        self._lastSpeedApplied = frac
    end

    if self._skyridingDirty then
        self._lastSkyCur, self._lastSkyProgress, self._skyridingDirty = updateChargeRow(
            self, SPELL_SKYWARD_ASCENT, self.skyFrame.pips, SKYRIDING_PIPS,
            self._lastSkyCur, self._lastSkyProgress, p.skyridingFilled)
    end

    if self._secondWindDirty then
        self._lastSwCur, self._lastSwProgress, self._secondWindDirty = updateChargeRow(
            self, SPELL_SECOND_WIND, self.swFrame.pips, SECONDWIND_PIPS,
            self._lastSwCur, self._lastSwProgress, p.secondWindFilled)
    end

    if self._whirlingDirty then
        self:UpdateWhirling()
    end
end

function DragonRiding:UpdateWhirling()
    local p = self.profileRef
    if not p then return end
    local wsIcon = self.wsIcon

    if C_Spell and C_Spell.GetSpellCooldownDuration then
        local ok, durObj = pcall(C_Spell.GetSpellCooldownDuration, SPELL_WHIRLING_SURGE, false)
        if ok and durObj then
            local applied = pcall(wsIcon.cd.SetCooldownFromDurationObject, wsIcon.cd, durObj)
            if applied then
                local shown = wsIcon.cd:IsShown()
                if not shown then
                    wsIcon.text:SetText("")
                    self._whirlingDirty = false
                else
                    self._whirlingDirty = true
                end
                if p.whirlingSurgeText.enabled ~= false and shown then
                    self:UpdateWhirlingText()
                elseif not shown then
                    wsIcon.text:SetText("")
                end
                return
            end
        end
    end

    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, SPELL_WHIRLING_SURGE)
        if ok and type(info) == "table" then
            local start = info.startTime
            local dur   = info.duration
            if isSecret(start) or isSecret(dur) then
                self._whirlingDirty = true
                return
            end
            start = start or 0
            dur   = dur or 0
            if dur > 1.5 then
                if start ~= self._lastCdStart or dur ~= self._lastCdDur then
                    wsIcon.cd:SetCooldown(start, dur)
                    self._lastCdStart, self._lastCdDur = start, dur
                end
                local remaining = start + dur - GetTime()
                if remaining > 0 then
                    if p.whirlingSurgeText.enabled ~= false then
                        wsIcon.text:SetText(self:FormatCooldownText(remaining))
                    end
                    self._whirlingDirty = true
                else
                    wsIcon.text:SetText("")
                    self._whirlingDirty = false
                end
            else
                if self._lastCdDur ~= 0 then
                    wsIcon.cd:Clear()
                    wsIcon.text:SetText("")
                    self._lastCdStart, self._lastCdDur = 0, 0
                end
                self._whirlingDirty = false
            end
        end
    end
end

function DragonRiding:UpdateWhirlingText()
    if not (C_Spell and C_Spell.GetSpellCooldown) then return end
    local ok, info = pcall(C_Spell.GetSpellCooldown, SPELL_WHIRLING_SURGE)
    if not ok or type(info) ~= "table" then return end
    local start = info.startTime
    local dur   = info.duration
    if isSecret(start) or isSecret(dur) then return end
    start = start or 0
    dur   = dur or 0
    if dur <= 0 then self.wsIcon.text:SetText("") return end
    local remaining = start + dur - GetTime()
    if remaining > 0 then
        self.wsIcon.text:SetText(self:FormatCooldownText(remaining))
    else
        self.wsIcon.text:SetText("")
    end
end

function DragonRiding:FormatCooldownText(remaining)
    if remaining >= 10 then return format("%d", floor(remaining + 0.5))
    elseif remaining >= 1 then return format("%d", floor(remaining))
    else return format("%.1f", remaining) end
end

local function dragonRiding_OnUpdate(_, dt)
    DragonRiding:OnUpdate(dt)
end

function DragonRiding:RegisterSpellEvents()
    if self._spellEventsRegistered or not self.evtFrame then return end
    self.evtFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
    self.evtFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    self._spellEventsRegistered = true
end

function DragonRiding:UnregisterSpellEvents()
    if not self._spellEventsRegistered or not self.evtFrame then return end
    self.evtFrame:UnregisterEvent("SPELL_UPDATE_CHARGES")
    self.evtFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    self._spellEventsRegistered = false
end

function DragonRiding:IsEditMode()
    return ns.EditMode and ns.EditMode.IsActive and ns.EditMode:IsActive() == true
end

function DragonRiding:UpdateVisibility()
    if not self._built or not self.content then return end
    local p = self.profileRef

    if not p or p.enabled == false then
        self.content:Hide()
        self.content:SetScript("OnUpdate", nil)
        self:UnregisterSpellEvents()
        return
    end

    if self:IsEditMode() then
        self.content:Show()
        self.content:SetScript("OnUpdate", dragonRiding_OnUpdate)
        self:RegisterSpellEvents()
        return
    end

    local lockedOut = self:IsInLockedContent() and p.showInstances ~= true
    if lockedOut then
        self.content:Hide()
        self.content:SetScript("OnUpdate", nil)
        self:UnregisterSpellEvents()
        return
    end

    local onSky = self:IsOnSkyridingMount()
    local hideCombat = p.hideInCombat and UnitAffectingCombat("player")
    local visible = onSky and not hideCombat

    self.content:SetShown(visible)
    if visible then
        self.content:SetScript("OnUpdate", dragonRiding_OnUpdate)
        self:RegisterSpellEvents()
    else
        self.content:SetScript("OnUpdate", nil)
        self:UnregisterSpellEvents()
    end
end

function DragonRiding:DeferVisibility()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() self:UpdateVisibility() end)
    else
        self:UpdateVisibility()
    end
end

local function dragonRiding_OnEvent(_, event)
    if event == "SPELL_UPDATE_CHARGES" then
        DragonRiding._skyridingDirty = true
        DragonRiding._secondWindDirty = true
        return
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        DragonRiding._whirlingDirty = true
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        DragonRiding._skyridingDirty = true
        DragonRiding._secondWindDirty = true
        DragonRiding._whirlingDirty = true
    end
    DragonRiding:DeferVisibility()
end

function DragonRiding:EnsureEventFrame()
    if self.evtFrame then return end
    local ef = CreateFrame("Frame", "TenUIDragonRidingEventFrame")
    ef:RegisterEvent("PLAYER_ENTERING_WORLD")
    ef:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    ef:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")
    ef:RegisterEvent("PLAYER_REGEN_DISABLED")
    ef:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    ef:SetScript("OnEvent", dragonRiding_OnEvent)
    self.evtFrame = ef
end

function DragonRiding:OnEnable(_, profile)
    local _, class = UnitClass("player")
    self._playerClass = class
    self.profileRef = self:GetProfile() or profile
    self._enabled = true

    if not self:Build() then return end
    self:EnsureEventFrame()
    self:UpdateVisibility()
end

function DragonRiding:OnDisable()
    self._enabled = false
    if self.content then
        self.content:Hide()
        self.content:SetScript("OnUpdate", nil)
    end
    self:UnregisterSpellEvents()
end

function DragonRiding:Rebuild()
    self.profileRef = self:GetProfile()
    if not self.profileRef then return end
    if not self._built then
        if not self:Build() then return end
        self:EnsureEventFrame()
    end
    self:Layout()
    self:Redraw()
    self:UpdateVisibility()
end

function DragonRiding:RedrawOptions()
    self.profileRef = self:GetProfile()
    if not self._built then return self:Rebuild() end
    self:Redraw()
    self:UpdateVisibility()
end

ns.dragonRidingRebuild = function() DragonRiding:Rebuild() end
ns.dragonRidingRedraw  = function() DragonRiding:RedrawOptions() end

ns:RegisterModule("DragonRiding", {
    defaults  = DEFAULTS,
    OnEnable  = function(mod, profile) DragonRiding:OnEnable(mod, profile) end,
    OnDisable = function(mod) DragonRiding:OnDisable() end,
})

DragonRiding.DEFAULTS = DEFAULTS

ns:RegisterMessage("PROFILE_CHANGED", function()
    if not DragonRiding._enabled then return end
    DragonRiding:Rebuild()
end)

ns:RegisterMessage("EDIT_MODE_CHANGED", function()
    if not DragonRiding._enabled then return end
    DragonRiding:UpdateVisibility()
end)

ns:RegisterMessage("LOCK_STATE_CHANGED", function()
    if not DragonRiding._enabled then return end
    DragonRiding:UpdateVisibility()
end)

ns:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(_, unit)
    if unit and unit ~= "player" then return end
    if not DragonRiding._enabled then return end
    DragonRiding:Rebuild()
end)
