local addonName, ns = ...

local CreateFrame    = CreateFrame
local C_Timer        = C_Timer
local UnitCastingInfo       = UnitCastingInfo
local UnitChannelInfo       = UnitChannelInfo
local UnitCastingDuration   = UnitCastingDuration
local UnitChannelDuration   = UnitChannelDuration
local UnitEmpoweredChannelDuration = UnitEmpoweredChannelDuration
local GetUnitEmpowerStageDuration  = GetUnitEmpowerStageDuration
local GetUnitEmpowerHoldAtMaxTime  = GetUnitEmpowerHoldAtMaxTime
local UnitEmpoweredStagePercentages = UnitEmpoweredStagePercentages
local pcall          = pcall
local select         = select
local unpack         = unpack
local tostring       = tostring
local type           = type
local pairs          = pairs

local function isSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function hasCastInfo(value)
    return isSecret(value) or value ~= nil
end

local function castDisplayName(displayName, name)
    if hasCastInfo(displayName) then return displayName end
    return name
end

local INTERP_IMMEDIATE = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
local DIR_ELAPSED      = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime or 0
local DIR_REMAINING    = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1

local CastBar = {
    bar              = nil,
    icon             = nil,
    anchor           = nil,
    eventFrame       = nil,
    profileRef       = nil,
    _baseProfile     = nil,
    _enabled         = false,
    _state           = "idle",
    _activeCastID    = nil,
    _hideTimer       = nil,
    _pendingNaturalStop = false,
    _testCycleIndex  = 0,
    _resizedCallback = nil,
    _tickFrame       = nil,
    _activeDuration  = nil,
    _lastDisplayedTenths = nil,
    _stagePips       = nil,
    _stageFracs      = nil,
    _stageBoundsSec  = nil,
    _stageStartSec   = nil,
    _stageCurrent    = nil,
    _stageNotInterruptible = nil,
    _stageDebugLogged = false,
}

local DEFAULTS = {
    enabled       = true,
    showQueueWindow = false,
    colorEmpowerStages = false,
    showIcon      = true,
    iconSide      = "LEFT",
    iconSize      = "auto",
    iconGap       = 2,
    showSpellName = true,
    showTime      = true,
    timeFormat    = "%.1f",
    colors = {
        cast            = { 1.0, 0.7, 0.0, 1 },
        channel         = { 0.3, 0.7, 1.0, 1 },
        empower         = { 0.8, 0.3, 1.0, 1 },
        uninterruptible = { 0.5, 0.5, 0.5, 1 },
        interrupted     = { 1.0, 0.1, 0.1, 1 },
        failed          = { 0.6, 0.6, 0.6, 1 },
        success         = { 0.2, 1.0, 0.2, 1 },
    },
    holdTime      = 0.4,
    texture       = nil,
    font          = nil,
    fontSize      = 12,
    fontFlags     = "OUTLINE",
    grace = {
        enabled = true,
    },
    instant = {
        enabled = true,
    },
}

ns.CastBar = CastBar

local GRACE_WINDOW_SEC = 0.5

local lastCast = {
    name             = nil,
    startTime        = nil,
    endTime          = nil,
    spellID          = nil,
    isChannel        = false,
    notInterruptible = false,
    seenAt           = 0,
}

local function graceEnabled()
    local p = CastBar.profileRef
    if not p then return true end
    local g = p.grace
    if type(g) ~= "table" then return true end
    return g.enabled ~= false
end

local function stampLastCast(name, startMs, endMs, spellID, notInterruptible, isChannel)
    lastCast.name             = name
    lastCast.startTime        = startMs
    lastCast.endTime          = endMs
    lastCast.spellID          = spellID
    lastCast.notInterruptible = notInterruptible
    lastCast.isChannel        = isChannel and true or false
    lastCast.seenAt           = GetTime()
end

local function clearLastCast()
    lastCast.name             = nil
    lastCast.startTime        = nil
    lastCast.endTime          = nil
    lastCast.spellID          = nil
    lastCast.notInterruptible = false
    lastCast.isChannel        = false
    lastCast.seenAt           = 0
end

local function withinGraceWindow()
    if not graceEnabled() then return false end
    if not hasCastInfo(lastCast.name) then return false end
    local now = GetTime()
    if now - (lastCast.seenAt or 0) > GRACE_WINDOW_SEC then return false end
    local endMs = lastCast.endTime
    if type(endMs) ~= "number" then return false end
    if type(issecretvalue) == "function" and issecretvalue(endMs) then
        return false
    end
    if (endMs / 1000) + 0.2 < now then return false end
    return true
end

local INSTANT_OVERLAY_DURATION_SEC = 0.3
local INSTANT_OVERLAY_HEIGHT       = 12

local function instantEnabled()
    local p = CastBar.profileRef
    if not p then return true end
    local i = p.instant
    if type(i) ~= "table" then return true end
    return i.enabled ~= false
end

local function dlog(fmt, ...)
    if ns.Debug and ns.Debug.Verbose then
        ns.Debug:Verbose("castbar", "[CastBar] " .. fmt, ...)
    end
end

local function getProfile()
    return CastBar.profileRef
end

local function resolveCastBarBlock(baseBlock)
    if ns.GetSpecBlock and ns.savedVarsReady then
        local function getBase() return baseBlock end
        local cb = ns:GetSpecBlock("castbar", getBase, false)
        if type(cb) == "table" then return cb end
    end
    return baseBlock
end

function CastBar:FormatTimerText(profile, remaining, total)
    if not (profile and profile.showTime) or isSecret(remaining) or type(remaining) ~= "number" then
        return ""
    end
    local fmt = profile.timeFormat or "%.1f"
    if profile.showTotalDuration and not isSecret(total) and type(total) == "number" and total > 0 then
        local elapsed = math.max(0, math.min(total, total - remaining))
        local ok, text = pcall(string.format, fmt .. " / " .. fmt, elapsed, total)
        if ok then return text end
    end
    local ok, text = pcall(string.format, fmt, remaining)
    if ok then return text .. "s" end
    return ""
end

local function computeRemainingSec(startMs, endMs)
    if type(startMs) ~= "number" or type(endMs) ~= "number" then return nil end
    if type(issecretvalue) == "function" then
        if issecretvalue(startMs) or issecretvalue(endMs) then return nil end
    end
    local total = (endMs - startMs) / 1000
    if total <= 0 then return nil end
    return total
end

local function applyColor(bar, colorTbl)
    if not bar or not colorTbl then return end
    bar:SetColor(colorTbl[1] or 1, colorTbl[2] or 1, colorTbl[3] or 1, colorTbl[4] or 1)
end

function CastBar:ApplyCastVisual(castType, spellName, iconTexture, notInterruptible)
    if not self.bar then return end
    local profile = getProfile()
    if not profile then return end
    if profile.enabled == false then return end

    self._visualCastType = castType
    local colorKey = castType
    if not isSecret(notInterruptible) and notInterruptible
       and (castType == "cast" or castType == "channel" or castType == "empower") then
        colorKey = "uninterruptible"
    end
    applyColor(self.bar, profile.colors and profile.colors[colorKey])

    if profile.showSpellName then
        self.bar:SetLeftText(spellName)
    else
        self.bar:SetLeftText("")
    end

    if self.icon then
        if profile.showIcon and hasCastInfo(iconTexture) then
            self.icon:SetTexture(iconTexture)
            self.icon:Show()
        else
            self.icon:Hide()
        end
    end

    self.bar:Show()
end

-- Both the settings preview and the HUD use the same duration and fill geometry.
function CastBar:LayoutQueueWindow(bar, enabled, seconds, drain)
    local frame = bar.frame
    local queue = enabled and C_Spell.GetSpellQueueWindow and C_Spell.GetSpellQueueWindow()
    if type(queue) ~= "number" or queue <= 0 or isSecret(seconds) or type(seconds) ~= "number" or seconds <= 0 then
        if bar.queueZone then bar.queueZone:Hide() end
        return
    end
    local zone = bar.queueZone
    if not zone then
        zone = frame:CreateTexture(nil, "OVERLAY", nil, 1)
        zone:SetColorTexture(1, 1, 1, 0.32)
        bar.queueZone = zone
    end
    local edge = drain and "LEFT" or "RIGHT"
    zone:ClearAllPoints()
    local inset = frame.border and ns.Pixel.Size(frame, 1) or 0
    local x = drain and inset or -inset
    zone:SetPoint("TOP" .. edge, frame, "TOP" .. edge, x, -inset)
    zone:SetPoint("BOTTOM" .. edge, frame, "BOTTOM" .. edge, x, inset)
    zone:SetWidth(math.max(0.01, (frame:GetWidth() - 2 * inset) * math.min(1, queue / (1000 * seconds))))
    zone:Show()
end

function CastBar:LayoutEmpowerColors(bar, fractions, color)
    local clip = bar.stageClip
    if not fractions or not color then
        if clip then clip:Hide() end
        return
    end
    local frame = bar.frame
    if not clip then
        clip = CreateFrame("Frame", nil, frame)
        clip:SetClipsChildren(true)
        local holder = CreateFrame("Frame", nil, clip)
        holder:SetFrameLevel(clip:GetFrameLevel())
        holder:SetAllPoints(frame)
        clip.holder, clip.bands = holder, {}
        bar.stageClip = clip
    end
    clip:SetAllPoints(frame:GetStatusBarTexture())
    local inset = frame.border and ns.Pixel.Size(frame, 1) or 0
    local width, left = frame:GetWidth(), 0
    for i = 1, #fractions + 1 do
        local right = fractions[i] or 1
        local band = clip.bands[i]
        if not band then
            band = clip.holder:CreateTexture(nil, "ARTWORK")
            clip.bands[i] = band
        end
        local tint = (i - 1) / math.max(1, #fractions) * 0.75
        band:SetColorTexture(color[1] + (1 - color[1]) * tint,
            color[2] + (1 - color[2]) * tint, color[3] + (1 - color[3]) * tint, 0.8)
        band:ClearAllPoints()
        band:SetPoint("TOPLEFT", frame, "TOPLEFT", math.max(inset, left * width), -inset)
        band:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", math.min(width - inset, right * width), inset)
        band:SetShown(right > left)
        left = right
    end
    for i = #fractions + 2, #clip.bands do clip.bands[i]:Hide() end
    clip:Show()
end

function CastBar:RefreshTimerLayout()
    if not self._activeDuration then return end
    local p = getProfile()
    local enabled = p and p.showQueueWindow and self._visualCastType ~= "empower"
    self:LayoutQueueWindow(self.bar, enabled, self._queueSeconds, self._visualCastType == "channel")
    self:LayoutStagePips()
end

function CastBar:ArmTimer(durationObject, drain, startMs, endMs)
    if not self.bar or not durationObject then return end
    local direction = drain and DIR_REMAINING or DIR_ELAPSED
    local profile = getProfile()
    local queue = profile and profile.showQueueWindow and self._visualCastType ~= "empower"
    self._queueSeconds = computeRemainingSec(startMs, endMs)
    if not self._queueSeconds then self._queueSeconds = durationObject:GetTotalDuration() end
    self:LayoutQueueWindow(self.bar, queue, self._queueSeconds, drain)
    local ok = self.bar:SetTimerDuration(durationObject, INTERP_IMMEDIATE, direction)
    if not ok then
        dlog("ArmTimer: SetTimerDuration failed (durationObject malformed?)")
    end
end

function CastBar:SetStartTimeText(totalSeconds)
    if not self.bar then return end
    self.bar:SetRightText(self:FormatTimerText(getProfile(), totalSeconds, totalSeconds))
end

function CastBar:ClearTimeText()
    if self.bar then self.bar:SetRightText("") end
end

local function tick_OnUpdate(_self, _elapsed)
    local duration = CastBar._activeDuration
    if not duration then
        if CastBar._tickFrame then
            CastBar._tickFrame:SetScript("OnUpdate", nil)
        end
        CastBar._lastDisplayedTenths = nil
        return
    end

    if CastBar._stageBoundsSec then
        CastBar:UpdateEmpowerStageTint()
    end

    local ok, remaining = pcall(duration.GetRemainingDuration, duration)
    if not ok or isSecret(remaining) or type(remaining) ~= "number" then
        if CastBar._lastDisplayedTenths ~= false and CastBar.bar then CastBar.bar:SetRightText("") end
        CastBar._lastDisplayedTenths = false
        return
    end

    if remaining < 0 then remaining = 0 end

    local tenths = math.floor(remaining * 10)
    if tenths == CastBar._lastDisplayedTenths then return end
    CastBar._lastDisplayedTenths = tenths

    local profile = CastBar.profileRef
    local total
    if profile and profile.showTime and profile.showTotalDuration then
        local okTotal, seconds = pcall(duration.GetTotalDuration, duration)
        if okTotal then total = seconds end
    end
    if CastBar.bar then CastBar.bar:SetRightText(CastBar:FormatTimerText(profile, remaining, total)) end
end

function CastBar:_EnsureTickFrame()
    if self._tickFrame then return self._tickFrame end
    self._tickFrame = CreateFrame("Frame", "TenUICastBarTickFrame", UIParent)
    self._tickFrame:Show()
    self._tickFrame:SetScript("OnUpdate", nil)
    return self._tickFrame
end

function CastBar:StartLiveTimer(durationObject)
    if not durationObject then return end
    self._activeDuration = durationObject
    self._lastDisplayedTenths = nil
    local tf = self:_EnsureTickFrame()
    tf:SetScript("OnUpdate", tick_OnUpdate)
end

function CastBar:StopLiveTimer()
    if self.bar and self.bar.queueZone then self.bar.queueZone:Hide() end
    self._activeDuration = nil
    self._lastDisplayedTenths = nil
    if self._tickFrame then
        self._tickFrame:SetScript("OnUpdate", nil)
    end
end

local STAGE_PIP_COLOR = { 1, 1, 1, 0.75 }

local CHANNEL_INTERVALS = {
    [15407] = 6, [48045] = 6, [64843] = 4, [205065] = 5,
    [740] = 4, [12051] = 6, [205021] = 5,
    [198590] = 5, [755] = 5, [234153] = 5, [206931] = 3,
    [113656] = 4, [115175] = 12, [443028] = 4, [291944] = 6,
    [212084] = 10, [356995] = 3, [5143] = 4, [257044] = 6,
}

local CHANNEL_EXTRA_INTERVALS = {
    [356995] = { [1219723] = 1 }, -- Azure Celerity
    [5143] = { [236628] = 2, [1296581] = 1 }, -- Amplification and tier bonus
    [257044] = { [459794] = 3 }, -- Quick Draw
}

local function plainNumber(v)
    if type(v) ~= "number" or isSecret(v) then return nil end
    return v
end

function CastBar:GetChannelTickFractions(spellID, totalSeconds)
    if not plainNumber(spellID) then return nil end
    local count = CHANNEL_INTERVALS[spellID]
    if spellID == 47540 or spellID == 47757 or spellID == 47758 or spellID == 373129 or spellID == 400171 then
        count = IsPlayerSpell and IsPlayerSpell(193134) and 3 or 2
    end
    local extra = CHANNEL_EXTRA_INTERVALS[spellID]
    if extra and IsPlayerSpell then
        for talent, intervals in pairs(extra) do
            if IsPlayerSpell(talent) then count = count + intervals end
        end
    end
    local marks = {}
    if count then
        for i = 1, count - 1 do marks[i] = 1 - i / count end
    elseif (spellID == 198013 or spellID == 473728) and plainNumber(totalSeconds) and totalSeconds > 0 then
        for elapsed = 0.2, totalSeconds - 0.001, 0.2 do
            marks[#marks + 1] = 1 - elapsed / totalSeconds
        end
    end
    return #marks > 0 and marks or nil
end

local STAGE_TINT_STEP = 0.18
local STAGE_TINT_CAP  = 0.66

local function computeStageData(numStages)
    if GetUnitEmpowerStageDuration and GetUnitEmpowerHoldAtMaxTime then
        local durs = {}
        local total = 0
        local usable = true
        for i = 1, numStages do
            local okCall, d = pcall(GetUnitEmpowerStageDuration, "player", i - 1)
            d = okCall and plainNumber(d) or nil
            if not d or d <= 0 then
                usable = false
                break
            end
            durs[i] = d
            total = total + d
        end
        if usable then
            local okHold, hold = pcall(GetUnitEmpowerHoldAtMaxTime, "player")
            hold = (okHold and plainNumber(hold)) or 0
            if hold < 0 then hold = 0 end
            total = total + hold
            if total > 0 then
                local fracs, boundsSec = {}, {}
                local cum = 0
                for i = 1, numStages do
                    cum = cum + durs[i]
                    fracs[i] = cum / total
                    boundsSec[i] = cum / 1000
                end
                return fracs, boundsSec
            end
        end
    end
    if UnitEmpoweredStagePercentages then
        local okCall, pcts = pcall(UnitEmpoweredStagePercentages, "player", true)
        if okCall and type(pcts) == "table" then
            local okNorm, fracs = pcall(function()
                local sum = 0
                local vals = {}
                for i = 1, #pcts do
                    local p = plainNumber(pcts[i])
                    if not p or p < 0 then return nil end
                    vals[i] = p
                    sum = sum + p
                end
                if sum <= 0 or #vals < numStages then return nil end
                local out = {}
                local cum = 0
                for i = 1, numStages do
                    cum = cum + vals[i]
                    out[i] = cum / sum
                end
                return out
            end)
            if okNorm and type(fracs) == "table" then
                return fracs, nil
            end
        end
    end
    return nil, nil
end

function CastBar:ClearStagePips()
    if self.bar and self.bar.stageClip then self.bar.stageClip:Hide() end
    local pips = self._stagePips
    if pips then
        for i = 1, #pips do pips[i]:Hide() end
    end
    self._stageFracs = nil
    self._stageBoundsSec = nil
    self._stageStartSec = nil
    self._stageCurrent = nil
    self._stageNotInterruptible = nil
    self._channelTicks = nil
end

function CastBar:LayoutStagePips()
    local fracs = self._stageFracs
    local profile = getProfile()
    if not fracs and profile and profile.showChannelTicks then fracs = self._channelTicks end
    local barFrame = self.bar and self.bar.frame
    if not barFrame then return end
    self:LayoutEmpowerColors(self.bar, profile and profile.colorEmpowerStages and not self._stageNotInterruptible and self._stageFracs,
        profile and profile.colors and profile.colors.empower)
    local w = barFrame:GetWidth()
    if not w or w <= 0 then return end
    self._stagePips = self._stagePips or {}
    local pips = self._stagePips
    local used = 0
    for i = 1, #(fracs or {}) do
        local frac = fracs[i]
        if type(frac) == "number" and frac > 0.01 and frac < 0.995 then
            used = used + 1
            local tex = pips[used]
            if not tex then
                tex = (self.bar.textLayer or barFrame):CreateTexture(nil, "ARTWORK")
                tex:SetColorTexture(STAGE_PIP_COLOR[1], STAGE_PIP_COLOR[2],
                    STAGE_PIP_COLOR[3], STAGE_PIP_COLOR[4])
                ns.Pixel.Edge(tex, barFrame, false)
                pips[used] = tex
            end
            tex:ClearAllPoints()
            local x = ns.Pixel.Snap(barFrame, w * frac)
            local px = ns.Pixel.Size(barFrame, 1)
            tex:SetPoint("TOP", barFrame, "TOPLEFT", x, -px)
            tex:SetPoint("BOTTOM", barFrame, "BOTTOMLEFT", x, px)
            tex:Show()
        end
    end
    for i = used + 1, #pips do pips[i]:Hide() end
end

function CastBar:SetupStagePips(numStages, startMs, notInterruptible)
    self:ClearStagePips()
    self._stageNotInterruptible = not isSecret(notInterruptible) and notInterruptible == true
    numStages = plainNumber(numStages)
    if not numStages or numStages < 1 then
        dlog("SetupStagePips: numStages unusable (nil/secret) -- no markers")
        return
    end
    local fracs, boundsSec = computeStageData(numStages)
    if not fracs then
        dlog("SetupStagePips: stage data unavailable (durations+percentages both unusable) -- no markers")
        return
    end
    self._stageFracs = fracs
    self._stageBoundsSec = boundsSec
    local sMs = plainNumber(startMs)
    self._stageStartSec = (sMs and sMs / 1000) or GetTime()
    self._stageCurrent = 0
    self:LayoutStagePips()
    if not self._stageDebugLogged then
        self._stageDebugLogged = true
        local fparts = {}
        for i = 1, #fracs do fparts[#fparts + 1] = string.format("%.3f", fracs[i]) end
        local bparts = {}
        if boundsSec then
            for i = 1, #boundsSec do bparts[#bparts + 1] = string.format("%.2f", boundsSec[i]) end
        end
        dlog("empower stages: numStages=%d fracs=[%s] boundsSec=[%s] (please report if markers look wrong)",
            numStages, table.concat(fparts, ","),
            boundsSec and table.concat(bparts, ",") or "none(percent fallback)")
    end
end

function CastBar:UpdateEmpowerStageTint()
    local bounds = self._stageBoundsSec
    if not bounds or not self._stageStartSec then return end
    if self._state ~= "empowering" and self._state ~= "test" then return end
    if self._stageNotInterruptible or (self.profileRef and self.profileRef.colorEmpowerStages) then return end
    local elapsed = GetTime() - self._stageStartSec
    local stage = 0
    for i = 1, #bounds do
        if elapsed >= bounds[i] then stage = i else break end
    end
    if stage == self._stageCurrent then return end
    self._stageCurrent = stage
    local profile = getProfile()
    local base = (profile and profile.colors and profile.colors.empower)
                 or DEFAULTS.colors.empower
    if not self.bar then return end
    if stage <= 0 then
        applyColor(self.bar, base)
        return
    end
    local f = stage * STAGE_TINT_STEP
    if f > STAGE_TINT_CAP then f = STAGE_TINT_CAP end
    local r = (base[1] or 1) + (1 - (base[1] or 1)) * f
    local g = (base[2] or 1) + (1 - (base[2] or 1)) * f
    local b = (base[3] or 1) + (1 - (base[3] or 1)) * f
    self.bar:SetColor(r, g, b, base[4] or 1)
end

function CastBar:_EnsureInstantOverlay()
    if self._instantOverlay then return self._instantOverlay end
    local anchor = self.anchor or ns:GetAnchor("CastBar")
    if not (anchor and anchor.frame) then return nil end

    local f = CreateFrame("Frame", "TenUICastBarInstantOverlay", anchor.frame)
    f:SetHeight(INSTANT_OVERLAY_HEIGHT)
    f:SetPoint("TOPLEFT",  anchor.frame, "BOTTOMLEFT",  0, -2)
    f:SetPoint("TOPRIGHT", anchor.frame, "BOTTOMRIGHT", 0, -2)
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0, 0, 0, 0.6)

    local fg = f:CreateTexture(nil, "ARTWORK")
    fg:SetAllPoints(f)
    fg:SetColorTexture(0.2, 1.0, 0.2, 0.8)
    f.fg = fg

    local iconTex = f:CreateTexture(nil, "OVERLAY")
    iconTex:SetPoint("LEFT", f, "LEFT", 0, 0)
    iconTex:SetSize(INSTANT_OVERLAY_HEIGHT, INSTANT_OVERLAY_HEIGHT)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon = iconTex

    local nameFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFS:SetPoint("LEFT", iconTex, "RIGHT", 3, 0)
    nameFS:SetPoint("RIGHT", f, "RIGHT", -3, 0)
    nameFS:SetJustifyH("LEFT")
    f.nameFS = nameFS

    self._instantOverlay = f
    return f
end

function CastBar:ShowInstantOverlay(spellName, iconTexture)
    if not instantEnabled() then return end
    if self._state == "casting" or self._state == "channeling"
       or self._state == "empowering" then
        return
    end
    local f = self:_EnsureInstantOverlay()
    if not f then return end
    if f.icon then
        if iconTexture then
            f.icon:SetTexture(iconTexture)
            f.icon:Show()
        else
            f.icon:Hide()
        end
    end
    if f.nameFS then
        f.nameFS:SetText(spellName or "")
    end
    f:SetAlpha(1)
    f:Show()
    self._instantHideToken = (self._instantHideToken or 0) + 1
    local myToken = self._instantHideToken
    if C_Timer and C_Timer.After then
        C_Timer.After(INSTANT_OVERLAY_DURATION_SEC, function()
            if CastBar._instantHideToken ~= myToken then return end
            if CastBar._instantOverlay then
                CastBar._instantOverlay:Hide()
            end
        end)
    end
end

function CastBar:HideInstantOverlay()
    if self._instantOverlay then
        self._instantOverlay:Hide()
    end
    self._instantHideToken = (self._instantHideToken or 0) + 1
end

function CastBar:CancelHideTimer()
    if self._hideTimer then
        if self._hideTimer.Cancel then
            self._hideTimer:Cancel()
        end
        self._hideTimer = nil
    end
end

function CastBar:HideAfterDelay(delay)
    self:CancelHideTimer()
    delay = delay or 0.4
    self._hideTimer = C_Timer.NewTimer(delay, function()
        CastBar._hideTimer = nil
        if CastBar.bar then CastBar.bar:Hide() end
        if CastBar.icon then CastBar.icon:Hide() end
        CastBar:ClearTimeText()
        CastBar:ClearStagePips()
        CastBar._state = "idle"
    end)
end

function CastBar:HideNow()
    self:CancelHideTimer()
    self:StopLiveTimer()
    self:ClearStagePips()
    self._pendingNaturalStop = false
    if self.bar then self.bar:Hide() end
    if self.icon then self.icon:Hide() end
    self:ClearTimeText()
    self._state = "idle"
    self._activeCastID = nil
    self._activeCastBarID = nil
end

local finishedDuration
local function freezeCompletedBar(bar)
    if not finishedDuration then
        finishedDuration = C_DurationUtil.CreateDuration()
        finishedDuration:SetTimeFromStart(0, 1)
    end
    bar:SetTimerDuration(finishedDuration, INTERP_IMMEDIATE, DIR_ELAPSED)
end

function CastBar:PlayInterruptedVisual()
    if not self.bar then return end
    local profile = getProfile()
    if not profile then return end
    self:StopLiveTimer()
    self:ClearStagePips()
    freezeCompletedBar(self.bar)
    applyColor(self.bar, profile.colors and profile.colors.interrupted)
    self.bar:SetLeftText(INTERRUPTED or "Interrupted")
    self:ClearTimeText()
    self._state = "interrupted"
    self:HideAfterDelay(profile.holdTime or 0.4)
end

function CastBar:PlayFailedVisual()
    if not self.bar then return end
    local profile = getProfile()
    if not profile then return end
    self:StopLiveTimer()
    self:ClearStagePips()
    freezeCompletedBar(self.bar)
    applyColor(self.bar, profile.colors and profile.colors.failed)
    self.bar:SetLeftText(FAILED or "Failed")
    self:ClearTimeText()
    self._state = "failed"
    self:HideAfterDelay(profile.holdTime or 0.4)
end

function CastBar:PlaySuccessVisual()
    if not self.bar then return end
    local profile = getProfile()
    if not profile then return end
    self:StopLiveTimer()
    self:ClearStagePips()
    applyColor(self.bar, profile.colors and profile.colors.success)
    self:ClearTimeText()
    self._state = "succeeded"
    self:HideAfterDelay(profile.holdTime or 0.4)
end

local function readCastGUID(value)
    if not (issecretvalue and issecretvalue(value)) then return value end
end

local function castMatches(castGUID, castBarID)
    if castBarID and CastBar._activeCastBarID then return castBarID == CastBar._activeCastBarID end
    local readable = readCastGUID(castGUID)
    if readable ~= nil and CastBar._activeCastID ~= nil then
        return readable == CastBar._activeCastID
    end
end

local function playerHasLiveCast()
    return (UnitCastingInfo and hasCastInfo(UnitCastingInfo("player")))
        or (UnitChannelInfo and hasCastInfo(UnitChannelInfo("player")))
end

function CastBar:OnSpellcastStart(castGUID, castBarID)
    if self._state == "channeling" or self._state == "empowering" then
        local castingName = UnitCastingInfo and UnitCastingInfo("player")
        if hasCastInfo(castingName) then
            dlog("CastBar: hardcast preempted " .. self._state)
        else
            dlog("CastBar GUARD: OnSpellcastStart rejected -- state="
                .. tostring(self._state) .. " (instant during channel/empower)")
            return
        end
    end
    if UnitChannelInfo and hasCastInfo(UnitChannelInfo("player"))
       and not (UnitCastingInfo and hasCastInfo(UnitCastingInfo("player"))) then
        dlog("CastBar GUARD: OnSpellcastStart rejected -- UnitChannelInfo active (no engine cast)")
        return
    end

    if self._state ~= "idle" then
        dlog("CastBar: preempting previous cast (state="
            .. tostring(self._state) .. ") for new START")
    end
    self:CancelHideTimer()
    self._pendingNaturalStop = false
    self._succeededFlag = false
    self._failedFlag    = false
    self:StopLiveTimer()
    self:ClearStagePips()

    local name, displayName, texture, startMs, endMs, isTradeSkill, castID, notInterruptible, spellID, nativeCastBarID =
        UnitCastingInfo("player")
    if not hasCastInfo(name) then
        dlog("OnSpellcastStart: no UnitCastingInfo (likely race) -- ignoring")
        return
    end

    stampLastCast(name, startMs, endMs, spellID, notInterruptible, false)

    self._activeCastID = readCastGUID(castID) or readCastGUID(castGUID)
    self._activeCastBarID = castBarID or nativeCastBarID
    self._succeededFlag = false
    self._failedFlag    = false
    self._state = "casting"

    self:ApplyCastVisual("cast", castDisplayName(displayName, name), texture, notInterruptible)

    local duration = UnitCastingDuration("player")
    if duration then
        self:ArmTimer(duration, false, startMs, endMs)
        self:StartLiveTimer(duration)
    else
        dlog("OnSpellcastStart: UnitCastingDuration returned nil -- bar will not animate")
    end

    local totalSec = computeRemainingSec(startMs, endMs)
    self:SetStartTimeText(totalSec)
end

function CastBar:OnSpellcastDelayed(castGUID, castBarID)
    if not castMatches(castGUID, castBarID) then return end
    if self._state ~= "casting" then return end
    local name, _, _, startMs, endMs = UnitCastingInfo("player")
    if not hasCastInfo(name) then return end
    local duration = UnitCastingDuration("player")
    if duration then
        self:ArmTimer(duration, false, startMs, endMs)
        self:StartLiveTimer(duration)
    end
end

function CastBar:OnChannelStart(castGUID, castBarID, eventSpellID)
    if self._state ~= "idle" then
        dlog("CastBar: preempting previous cast (state="
            .. tostring(self._state) .. ") for new CHANNEL_START")
    end

    self:CancelHideTimer()
    self._pendingNaturalStop = false
    self._succeededFlag = false
    self._failedFlag    = false
    self:StopLiveTimer()
    self:ClearStagePips()

    local name, displayName, texture, startMs, endMs, isTradeSkill, notInterruptible, spellID,
        _isEmpowered, _numStages, nativeCastBarID =
        UnitChannelInfo("player")
    if not hasCastInfo(name) then
        dlog("OnChannelStart: no UnitChannelInfo -- ignoring")
        return
    end

    stampLastCast(name, startMs, endMs, spellID, notInterruptible, true)

    self._state = "channeling"
    self._activeCastID = readCastGUID(castGUID)
    self._activeCastBarID = castBarID or nativeCastBarID
    self._succeededFlag = false
    self._failedFlag    = false

    self:ApplyCastVisual("channel", castDisplayName(displayName, name), texture, notInterruptible)
    local channelStart, channelEnd = plainNumber(startMs), plainNumber(endMs)
    local channelLength = channelStart and channelEnd and (channelEnd - channelStart) / 1000
    self._channelTicks = self:GetChannelTickFractions(spellID, channelLength)
        or self:GetChannelTickFractions(eventSpellID, channelLength)
    self:LayoutStagePips()

    local duration = UnitChannelDuration("player")
    if duration then
        self:ArmTimer(duration, true, startMs, endMs)
        self:StartLiveTimer(duration)
    else
        dlog("OnChannelStart: UnitChannelDuration returned nil")
    end

    local totalSec = computeRemainingSec(startMs, endMs)
    self:SetStartTimeText(totalSec)
end

function CastBar:OnChannelUpdate(castGUID, castBarID)
    if self._state ~= "channeling" then return end
    local matches = castMatches(castGUID, castBarID)
    if matches == false then return end
    local name, _, _, startMs, endMs, _, _, _, empowered = UnitChannelInfo("player")
    if matches == nil then
        if not hasCastInfo(name) or (not isSecret(empowered) and empowered) then return end
    end
    local duration = UnitChannelDuration("player")
    if duration then
        self:ArmTimer(duration, true, startMs, endMs)
        self:StartLiveTimer(duration)
    end
end

function CastBar:OnEmpowerStart(castGUID, castBarID)
    if self._state ~= "idle" then
        dlog("CastBar: preempting previous cast (state="
            .. tostring(self._state) .. ") for new EMPOWER_START")
    end

    self:CancelHideTimer()
    self._pendingNaturalStop = false
    self._succeededFlag = false
    self._failedFlag    = false
    self:StopLiveTimer()

    local name, displayName, texture, startMs, endMs, isTradeSkill, notInterruptible, spellID, isEmpowered, numStages, nativeCastBarID =
        UnitChannelInfo("player")
    if not hasCastInfo(name) then
        dlog("OnEmpowerStart: no UnitChannelInfo -- ignoring")
        return
    end

    stampLastCast(name, startMs, endMs, spellID, notInterruptible, true)

    self._state = "empowering"
    self._activeCastID = readCastGUID(castGUID)
    self._activeCastBarID = castBarID or nativeCastBarID
    self._succeededFlag = false
    self._failedFlag    = false
    self:ApplyCastVisual("empower", castDisplayName(displayName, name), texture, notInterruptible)

    local duration = nil
    if UnitEmpoweredChannelDuration then
        duration = UnitEmpoweredChannelDuration("player")
    end
    if not duration then
        duration = UnitChannelDuration("player")
    end
    if duration then
        self:ArmTimer(duration, false)
        self:StartLiveTimer(duration)
    end

    self:SetupStagePips(numStages, startMs, notInterruptible)

    local totalSec = computeRemainingSec(startMs, endMs)
    self:SetStartTimeText(totalSec)
end

function CastBar:OnEmpowerUpdate(castGUID, castBarID)
    if self._state ~= "empowering" then return end
    local matches = castMatches(castGUID, castBarID)
    if matches == false then return end
    local _n, _dn, _tex, startMs, _endMs, _ts, _ni, _sid, empowered, numStages =
        UnitChannelInfo("player")
    if matches == nil and (not hasCastInfo(_n) or (not isSecret(empowered) and not empowered)) then return end
    local duration = (UnitEmpoweredChannelDuration and UnitEmpoweredChannelDuration("player"))
                     or UnitChannelDuration("player")
    if duration then
        self:ArmTimer(duration, false)
        self:StartLiveTimer(duration)
    end
    self:SetupStagePips(numStages, startMs, _ni)
end

function CastBar:OnSpellcastStop(castGUID, castBarID, interrupted)
    if self._state ~= "casting" then return end
    local matches = castMatches(castGUID, castBarID)
    if matches == false then return end

    local previous = self._pendingNaturalStop
    local pending = { interrupted = interrupted or (previous and previous.interrupted) }
    self._pendingNaturalStop = pending
    C_Timer.After(0, function()
        if CastBar._pendingNaturalStop ~= pending then
            return
        end
        CastBar._pendingNaturalStop = false

        if matches == nil and playerHasLiveCast() then return end
        if pending.interrupted then
            CastBar:FinishInterruptedCast()
            return
        end

        if CastBar._succeededFlag then
            CastBar._succeededFlag = false
            CastBar:PlaySuccessVisual()
            CastBar._activeCastID = nil
            CastBar._activeCastBarID = nil
            clearLastCast()
            return
        end
        if CastBar._failedFlag then
            CastBar._failedFlag = false
            CastBar:PlayFailedVisual()
            CastBar._activeCastID = nil
            CastBar._activeCastBarID = nil
            clearLastCast()
            return
        end

        if withinGraceWindow() then
            if not playerHasLiveCast() then
                local delay = GRACE_WINDOW_SEC - (GetTime() - (lastCast.seenAt or 0))
                if delay < 0.05 then delay = 0.05 end
                CastBar:CancelHideTimer()
                CastBar._state = "finishing"
                CastBar._hideTimer = C_Timer.NewTimer(delay, function()
                    CastBar._hideTimer = nil
                    if CastBar._state == "casting" or CastBar._state == "channeling"
                       or CastBar._state == "empowering" then
                        return
                    end
                    CastBar:StopLiveTimer()
                    CastBar:ClearTimeText()
                    if CastBar.bar then CastBar.bar:Hide() end
                    if CastBar.icon then CastBar.icon:Hide() end
                    CastBar._state = "idle"
                    clearLastCast()
                end)
                CastBar._activeCastID = nil
                CastBar._activeCastBarID = nil
                return
            end
        end

        CastBar:StopLiveTimer()
        CastBar:ClearTimeText()
        local profile = getProfile()
        CastBar:HideAfterDelay((profile and profile.holdTime) or 0.4)
        CastBar._activeCastID = nil
        CastBar._activeCastBarID = nil
        clearLastCast()
    end)
end

function CastBar:OnChannelStop(castGUID, complete, castBarID)
    if self._state ~= "channeling" and self._state ~= "empowering" then return end
    local matches = castMatches(castGUID, castBarID)
    if matches == false then return end

    if matches and complete == false then
        self:OnSpellcastInterrupted(castGUID, castBarID)
        return
    end

    local previous = self._pendingNaturalStop
    if previous and previous.channelStop and previous.complete == false and complete == nil then
        complete = false
    end
    local pending = { channelStop = true, complete = complete }
    self._pendingNaturalStop = pending
    C_Timer.After(0, function()
        if CastBar._pendingNaturalStop ~= pending then return end
        CastBar._pendingNaturalStop = false

        -- With neither a readable GUID nor a castBarID, a delayed STOP may
        -- belong to a previous channel. Leave any current cast alone.
        if not matches and playerHasLiveCast() then return end
        if complete == false then
            CastBar:FinishInterruptedCast()
            return
        end

        if CastBar._failedFlag then
            CastBar._failedFlag = false
            CastBar:PlayFailedVisual()
            CastBar._activeCastID = nil
            CastBar._activeCastBarID = nil
            clearLastCast()
            return
        end

        if withinGraceWindow() then
            if not playerHasLiveCast() then
                local delay = GRACE_WINDOW_SEC - (GetTime() - (lastCast.seenAt or 0))
                if delay < 0.05 then delay = 0.05 end
                CastBar:CancelHideTimer()
                CastBar._state = "finishing"
                CastBar._hideTimer = C_Timer.NewTimer(delay, function()
                    CastBar._hideTimer = nil
                    if CastBar._state == "casting" or CastBar._state == "channeling"
                       or CastBar._state == "empowering" then
                        return
                    end
                    CastBar:StopLiveTimer()
                    CastBar:ClearTimeText()
                    if CastBar.bar then CastBar.bar:Hide() end
                    if CastBar.icon then CastBar.icon:Hide() end
                    CastBar._state = "idle"
                    clearLastCast()
                end)
                CastBar._activeCastID = nil
                CastBar._activeCastBarID = nil
                return
            end
        end

        CastBar:StopLiveTimer()
        CastBar:ClearTimeText()
        CastBar._state = "finishing"
        local profile = getProfile()
        CastBar:HideAfterDelay((profile and profile.holdTime) or 0.4)
        CastBar._activeCastID = nil
        CastBar._activeCastBarID = nil
        clearLastCast()
    end)
end

function CastBar:FinishInterruptedCast()
    self._pendingNaturalStop = false
    self._succeededFlag = false
    self._failedFlag    = false
    self:PlayInterruptedVisual()
    self._activeCastID = nil
    self._activeCastBarID = nil
    clearLastCast()
end

function CastBar:OnSpellcastInterrupted(castGUID, castBarID)
    local matches = castMatches(castGUID, castBarID)
    if matches then
        self:FinishInterruptedCast()
    elseif matches == nil then
        if self._state == "casting" then
            self:OnSpellcastStop(castGUID, castBarID, true)
        else
            self:OnChannelStop(castGUID, false, castBarID)
        end
    end
end

function CastBar:OnSpellcastFailed(castGUID, castBarID)
    if self._state == "channeling" or self._state == "empowering" then return end
    if not castMatches(castGUID, castBarID) then return end

    local failure = {}
    self._failedFlag = failure
    C_Timer.After(0, function()
        if CastBar._failedFlag ~= failure then return end
        if playerHasLiveCast() then
            CastBar._failedFlag = false
        elseif not CastBar._pendingNaturalStop then
            CastBar._failedFlag = false
            CastBar:PlayFailedVisual()
            CastBar._activeCastID = nil
            CastBar._activeCastBarID = nil
            clearLastCast()
        end
    end)
end

function CastBar:OnSpellcastFailedQuiet(castGUID, castBarID)
    if not castMatches(castGUID, castBarID) then return end
    self._failedFlag = false
end

function CastBar:OnSpellcastSucceeded(castGUID, castBarID)
    if instantEnabled()
       and self._state ~= "casting"
       and self._state ~= "channeling"
       and self._state ~= "empowering" then
        if not playerHasLiveCast() then
            local sname, stex = nil, nil
            local sid = self._instantPendingSpellID
            self._instantPendingSpellID = nil
            if sid and C_Spell then
                if C_Spell.GetSpellName then
                    local ok, nm = pcall(C_Spell.GetSpellName, sid)
                    if ok then sname = nm end
                end
                if C_Spell.GetSpellTexture then
                    local ok, tx = pcall(C_Spell.GetSpellTexture, sid)
                    if ok then stex = tx end
                end
            end
            self:ShowInstantOverlay(sname or "", stex)
        end
    end

    if not castMatches(castGUID, castBarID) then return end
    if self._state == "casting" then
        self._succeededFlag = true
    end
end

function CastBar:OnInterruptibleChanged(notInterruptible)
    if isSecret(notInterruptible) then return end
    if self._state ~= "casting" and self._state ~= "channeling" and self._state ~= "empowering" then
        return
    end
    if not playerHasLiveCast() then return end

    local profile = getProfile()
    if not (profile and profile.colors) then return end
    local key = self._state == "casting" and "cast"
             or (self._state == "channeling" and "channel" or "empower")
    local color = notInterruptible and profile.colors.uninterruptible or profile.colors[key]
    applyColor(self.bar, color)
    if self._state == "empowering" then
        self._stageNotInterruptible = notInterruptible and true or false
        self._stageCurrent = nil
        self:LayoutStagePips()
    end
end

function CastBar:OnPlayerEnteringWorld()
    self:HideNow()
    self._succeededFlag = false
    self._failedFlag    = false
    self._activeCastID  = nil
    clearLastCast()
    self:HideInstantOverlay()
end

function CastBar:Relayout(width, height)
    local anchor = self.anchor
    if not (anchor and anchor.frame) then return end
    width  = width  or anchor.frame:GetWidth()
    height = height or anchor.frame:GetHeight()
    if not (width and height) then return end

    local profile = getProfile()
    if not profile then return end

    local showIcon = profile.showIcon and self.icon
    if not showIcon then
        if self.bar and self.bar.frame then
            self.bar.frame:ClearAllPoints()
            self.bar.frame:SetAllPoints(anchor.frame)
        end
        if self.icon then self.icon:Hide() end
        self:RefreshTimerLayout()
        return
    end

    local iconSize = profile.iconSize
    if iconSize == "auto" or type(iconSize) ~= "number" or iconSize <= 0 then
        iconSize = height
    else
        local maxIcon = height * 3
        if iconSize < 8 then iconSize = 8 elseif iconSize > maxIcon then iconSize = maxIcon end
    end
    local gap = profile.iconGap or 0
    if type(gap) ~= "number" or gap < 0 then gap = 0 end

    if self.icon and self.icon.frame then
        local f = self.icon.frame
        f:ClearAllPoints()
        f:SetSize(iconSize, iconSize)
        if profile.iconSide == "RIGHT" then
            f:SetPoint("RIGHT", anchor.frame, "RIGHT", 0, 0)
        else
            f:SetPoint("LEFT", anchor.frame, "LEFT", 0, 0)
        end
        if self._state ~= "idle" then
            self.icon:Show()
        else
            self.icon:Hide()
        end
    end

    if self.bar and self.bar.frame then
        local bf = self.bar.frame
        bf:ClearAllPoints()
        if profile.iconSide == "RIGHT" then
            bf:SetPoint("TOPLEFT",     anchor.frame, "TOPLEFT",     0, 0)
            bf:SetPoint("BOTTOMRIGHT", self.icon.frame, "BOTTOMLEFT", -gap, 0)
        else
            bf:SetPoint("TOPLEFT",     self.icon.frame, "TOPRIGHT", gap, 0)
            bf:SetPoint("BOTTOMRIGHT", anchor.frame, "BOTTOMRIGHT", 0, 0)
        end
    end

    self:RefreshTimerLayout()
end

local TEST_CYCLE = {
    function()
        local tex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(133))
                    or [[Interface\Icons\Spell_Fire_Fireball02]]
        CastBar:ApplyCastVisual("cast", "Test Cast", tex, false)
        CastBar:SetStartTimeText(4.0)
        if C_DurationUtil and C_DurationUtil.CreateDuration and GetTime then
            local d = C_DurationUtil.CreateDuration()
            if d and d.SetTimeFromStart then
                d:SetTimeFromStart(GetTime(), 4.0, 1)
                CastBar:ArmTimer(d, false)
            end
        end
        return "test cast (4s)"
    end,
    function()
        local tex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(15407))
                    or [[Interface\Icons\Spell_Shadow_Twilight]]
        CastBar:ApplyCastVisual("channel", "Test Channel", tex, false)
        CastBar:SetStartTimeText(4.0)
        if C_DurationUtil and C_DurationUtil.CreateDuration and GetTime then
            local d = C_DurationUtil.CreateDuration()
            if d and d.SetTimeFromStart then
                d:SetTimeFromStart(GetTime(), 4.0, 1)
                CastBar:ArmTimer(d, true)
            end
        end
        return "test channel (4s, drain)"
    end,
    function()
        local tex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(382266))
                    or [[Interface\Icons\Ability_Evoker_Firebreath]]
        CastBar:ApplyCastVisual("empower", "Test Empower", tex, false)
        CastBar:SetStartTimeText(4.0)
        if C_DurationUtil and C_DurationUtil.CreateDuration and GetTime then
            local d = C_DurationUtil.CreateDuration()
            if d and d.SetTimeFromStart then
                d:SetTimeFromStart(GetTime(), 4.0, 1)
                CastBar:ArmTimer(d, false)
                CastBar:StartLiveTimer(d)
            end
        end
        CastBar:ClearStagePips()
        CastBar._stageFracs = { 0.22, 0.47, 0.72 }
        CastBar._stageBoundsSec = { 0.88, 1.88, 2.88 }
        CastBar._stageStartSec = GetTime()
        CastBar._stageCurrent = 0
        CastBar._stageNotInterruptible = false
        CastBar:LayoutStagePips()
        return "test empower (4s, 3 stage markers + tint)"
    end,
    function()
        CastBar:HideNow()
        return "test mode off"
    end,
}

function CastBar:RunTest()
    self._testCycleIndex = (self._testCycleIndex % #TEST_CYCLE) + 1
    self._state = "test"
    self:CancelHideTimer()
    self._pendingNaturalStop = false
    self:ClearStagePips()
    self:StopLiveTimer()
    return TEST_CYCLE[self._testCycleIndex]()
end

local EVENT_DISPATCH = {
    UNIT_SPELLCAST_START               = function(_unit, castGUID, _spellID, castBarID) CastBar:OnSpellcastStart(castGUID, castBarID) end,
    UNIT_SPELLCAST_STOP                = function(_unit, castGUID, _spellID, castBarID) CastBar:OnSpellcastStop(castGUID, castBarID) end,
    UNIT_SPELLCAST_DELAYED             = function(_unit, castGUID, _spellID, castBarID) CastBar:OnSpellcastDelayed(castGUID, castBarID) end,
    UNIT_SPELLCAST_FAILED              = function(_unit, castGUID, _spellID, castBarID) CastBar:OnSpellcastFailed(castGUID, castBarID) end,
    UNIT_SPELLCAST_FAILED_QUIET        = function(_unit, castGUID, _spellID, castBarID) CastBar:OnSpellcastFailedQuiet(castGUID, castBarID) end,
    UNIT_SPELLCAST_SUCCEEDED           = function(_unit, castGUID, spellID, castBarID)
        CastBar._instantPendingSpellID = readCastGUID(spellID)
        CastBar:OnSpellcastSucceeded(castGUID, castBarID)
    end,
    UNIT_SPELLCAST_INTERRUPTED         = function(_unit, castGUID, _spellID, _interruptedBy, castBarID) CastBar:OnSpellcastInterrupted(castGUID, castBarID) end,
    UNIT_SPELLCAST_INTERRUPTIBLE       = function() CastBar:OnInterruptibleChanged(false) end,
    UNIT_SPELLCAST_NOT_INTERRUPTIBLE   = function() CastBar:OnInterruptibleChanged(true) end,
    UNIT_SPELLCAST_CHANNEL_START       = function(_unit, castGUID, spellID, castBarID) CastBar:OnChannelStart(castGUID, castBarID, spellID) end,
    UNIT_SPELLCAST_CHANNEL_STOP        = function(_unit, castGUID, _spellID, interruptedBy, castBarID)
        local complete
        if not isSecret(interruptedBy) then complete = interruptedBy == nil end
        CastBar:OnChannelStop(castGUID, complete, castBarID)
    end,
    UNIT_SPELLCAST_CHANNEL_UPDATE      = function(_unit, castGUID, _spellID, castBarID) CastBar:OnChannelUpdate(castGUID, castBarID) end,
    UNIT_SPELLCAST_EMPOWER_START       = function(_unit, castGUID, _spellID, castBarID) CastBar:OnEmpowerStart(castGUID, castBarID) end,
    UNIT_SPELLCAST_EMPOWER_STOP        = function(_unit, castGUID, _spellID, complete, _interruptedBy, castBarID)
        if isSecret(complete) then complete = nil end
        CastBar:OnChannelStop(castGUID, complete, castBarID)
    end,
    UNIT_SPELLCAST_EMPOWER_UPDATE      = function(_unit, castGUID, _spellID, castBarID) CastBar:OnEmpowerUpdate(castGUID, castBarID) end,
    PLAYER_ENTERING_WORLD              = function() CastBar:OnPlayerEnteringWorld() end,
}

local function castbar_OnEvent(self, event, ...)
    local handler = EVENT_DISPATCH[event]
    if handler then
        local ok, err = pcall(handler, ...)
        if not ok then dlog("event %s failed: %s", event, tostring(err)) end
    end
end

local _blizzSuppressed = false
local _blizzHookInstalled = false

local function ensureBlizzHook()
    if _blizzHookInstalled then return end
    local cb = _G and _G.PlayerCastingBarFrame
    if not cb then return end
    _blizzHookInstalled = true
    cb:HookScript("OnShow", function(self)
        if _blizzSuppressed then
            self:Hide()
        end
    end)
end

local function suppressBlizzardCastBar()
    local cb = _G and _G.PlayerCastingBarFrame
    if not cb then
        dlog("suppressBlizzardCastBar: PlayerCastingBarFrame missing -- nothing to do")
        return
    end
    _blizzSuppressed = true
    ensureBlizzHook()
    pcall(cb.UnregisterAllEvents, cb)
    pcall(cb.Hide, cb)
    dlog("Blizzard PlayerCastingBarFrame suppressed")
end

local function restoreBlizzardCastBar()
    local cb = _G and _G.PlayerCastingBarFrame
    if not cb then return end
    _blizzSuppressed = false
    if cb.SetUnit then
        if type(securecallfunction) == "function" then
            securecallfunction(function() cb:SetUnit("player", true, false) end)
        else
            pcall(cb.SetUnit, cb, "player", true, false)
        end
    end
    dlog("Blizzard PlayerCastingBarFrame restored")
end

local function buildWidgets(profile)
    local anchor = ns:GetAnchor("CastBar")
    if not (anchor and anchor.frame) then
        dlog("OnEnable: CastBar anchor not registered yet -- aborting")
        return false
    end
    CastBar.anchor = anchor

    CastBar.bar = ns.Widgets.Bar:New(anchor.frame, {
        orientation = "HORIZONTAL",
        fgColor     = profile.colors and profile.colors.cast or { 1, 0.7, 0, 1 },
        bgColor     = { 0, 0, 0, 0.7 },
        border      = true,
        leftText    = profile.showSpellName,
        rightText   = profile.showTime,
        font        = profile.font,
        fontSize    = profile.fontSize,
        fontFlags   = profile.fontFlags,
        texture     = profile.texture,
    })
    if CastBar.bar and CastBar.bar.frame then
        CastBar.bar:SetMinMaxValues(0, 1)
        local bar = CastBar.bar
        if bar.SetBackground
           and (profile.showBackground ~= nil or type(profile.bgColor) == "table") then
            local bgc = profile.bgColor
            if type(bgc) == "table" then
                bar:SetBackground(profile.showBackground ~= false,
                    bgc[1], bgc[2], bgc[3], bgc[4])
            else
                bar:SetBackground(profile.showBackground ~= false)
            end
        end
        if bar.SetBorder
           and (profile.showBorder ~= nil or type(profile.borderColor) == "table") then
            bar:SetBorder(profile.showBorder ~= false,
                (type(profile.borderColor) == "table") and profile.borderColor or nil)
        end
    end

    CastBar.icon = ns.Widgets.Icon:New(anchor.frame, {
        texture   = nil,
        border    = true,
        cooldown  = false,
        countdown = false,
        stackText = false,
        zoomIcon  = true,
    })

    CastBar.bar:Hide()
    CastBar.icon:Hide()

    CastBar:Relayout(anchor.frame:GetWidth(), anchor.frame:GetHeight())
    return true
end

function CastBar:OnEnable(_, profile)
    self._baseProfile = profile
    profile = resolveCastBarBlock(profile)
    self.profileRef = profile
    self._enabled = true

    local ok = buildWidgets(profile)
    if not ok then return end

    if not self.eventFrame then
        self.eventFrame = CreateFrame("Frame", "TenUICastBarEventFrame")
    end
    local ef = self.eventFrame
    ef:SetScript("OnEvent", castbar_OnEvent)

    local function regUnit(event)
        local ok2, err = pcall(ef.RegisterUnitEvent, ef, event, "player")
        if not ok2 then dlog("RegisterUnitEvent(%s) failed: %s", event, tostring(err)) end
    end

    regUnit("UNIT_SPELLCAST_START")
    regUnit("UNIT_SPELLCAST_STOP")
    regUnit("UNIT_SPELLCAST_FAILED")
    regUnit("UNIT_SPELLCAST_FAILED_QUIET")
    regUnit("UNIT_SPELLCAST_SUCCEEDED")
    regUnit("UNIT_SPELLCAST_INTERRUPTED")
    regUnit("UNIT_SPELLCAST_DELAYED")
    regUnit("UNIT_SPELLCAST_INTERRUPTIBLE")
    regUnit("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
    regUnit("UNIT_SPELLCAST_CHANNEL_START")
    regUnit("UNIT_SPELLCAST_CHANNEL_STOP")
    regUnit("UNIT_SPELLCAST_CHANNEL_UPDATE")
    regUnit("UNIT_SPELLCAST_EMPOWER_START")
    regUnit("UNIT_SPELLCAST_EMPOWER_STOP")
    regUnit("UNIT_SPELLCAST_EMPOWER_UPDATE")
    ef:RegisterEvent("PLAYER_ENTERING_WORLD")

    self._resizedCallback = ns:RegisterMessage("ANCHOR_RESIZED", function(_, name, w, h)
        if name == "CastBar" then
            CastBar:Relayout(w, h)
        end
    end)

    self._specCB = ns:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(_, unit)
        if unit and unit ~= "player" then return end
        CastBar:ApplyOptions()
    end)

    self:ApplyBlizzardSuppression()

    dlog("enabled")
end

function CastBar:ApplyBlizzardSuppression()
    local profile = self.profileRef
    local ourEnabled = not (profile and profile.enabled == false)
    if ourEnabled then
        suppressBlizzardCastBar()
    else
        restoreBlizzardCastBar()
    end
end

function CastBar:OnDisable()
    self._enabled = false

    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
        self.eventFrame:SetScript("OnEvent", nil)
    end

    if self._resizedCallback then
        ns:UnregisterMessage("ANCHOR_RESIZED", self._resizedCallback)
        self._resizedCallback = nil
    end

    if self._specCB then
        ns:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED", self._specCB)
        self._specCB = nil
    end

    self:CancelHideTimer()
    self:StopLiveTimer()
    self:ClearStagePips()
    self._pendingNaturalStop = false
    self._succeededFlag = false
    self._failedFlag = false
    self._activeCastID = nil
    self._activeCastBarID = nil
    self._state = "idle"

    if self.bar then self.bar:Hide() end
    if self.icon then self.icon:Hide() end

    clearLastCast()
    self:HideInstantOverlay()

    restoreBlizzardCastBar()

    dlog("disabled")
end

function CastBar:SetGraceEnabled(flag)
    local p = self.profileRef
    if not p then return false, "profile not ready" end
    p.grace = p.grace or {}
    p.grace.enabled = flag and true or false
    return true
end

function CastBar:IsGraceEnabled()
    local p = self.profileRef
    if not p then return true end
    return not (p.grace and p.grace.enabled == false)
end

function CastBar:SetInstantEnabled(flag)
    local p = self.profileRef
    if not p then return false, "profile not ready" end
    p.instant = p.instant or {}
    p.instant.enabled = flag and true or false
    if not p.instant.enabled then
        self:HideInstantOverlay()
    end
    return true
end

function CastBar:IsInstantEnabled()
    local p = self.profileRef
    if not p then return true end
    return not (p.instant and p.instant.enabled == false)
end

function CastBar:ApplyOptions()
    local resolved = resolveCastBarBlock(self._baseProfile or self.profileRef)
    self.profileRef = resolved
    local profile = self.profileRef
    if not profile then return end
    if not self.bar then return end
    self._lastDisplayedTenths = nil

    self:ApplyBlizzardSuppression()
    if profile.enabled == false then
        self:HideNow()
        self:HideInstantOverlay()
        dlog("ApplyOptions: our cast bar disabled -- hidden, Blizzard restored")
        return
    end

    if self._state == "casting" or self._state == "channeling" or self._state == "empowering" then
        local key = self._state == "casting" and "cast"
                 or (self._state == "channeling" and "channel" or "empower")
        local notInterruptible = false
        if self._state == "casting" then
            local _n, _d, _t, _s, _e, _ts, _cid, ni = UnitCastingInfo("player")
            notInterruptible = not isSecret(ni) and ni == true
        elseif UnitChannelInfo then
            local _n, _d, _t, _s, _e, _ts, ni = UnitChannelInfo("player")
            notInterruptible = not isSecret(ni) and ni == true
        end
        local colorKey = (notInterruptible and "uninterruptible") or key
        if profile.colors then
            applyColor(self.bar, profile.colors[colorKey])
        end
    end

    if not profile.showSpellName then
        self.bar:SetLeftText("")
    end

    if not profile.showTime then
        self.bar:SetRightText("")
    end

    if self.bar.SetFont then
        local fontSize  = profile.fontSize  or 12
        local fontFlags = profile.fontFlags or "OUTLINE"
        pcall(self.bar.SetFont, self.bar, profile.font, fontSize, fontFlags)
    end

    if profile.texture and self.bar.SetTexture then
        pcall(self.bar.SetTexture, self.bar, profile.texture)
    end

    if self.bar.SetBackground
       and (profile.showBackground ~= nil or type(profile.bgColor) == "table") then
        local bgc = profile.bgColor
        if type(bgc) == "table" then
            self.bar:SetBackground(profile.showBackground ~= false,
                bgc[1], bgc[2], bgc[3], bgc[4])
        else
            self.bar:SetBackground(profile.showBackground ~= false)
        end
    end
    if self.bar.SetBorder
       and (profile.showBorder ~= nil or type(profile.borderColor) == "table") then
        self.bar:SetBorder(profile.showBorder ~= false,
            (type(profile.borderColor) == "table") and profile.borderColor or nil)
    end

    if self.icon then
        if profile.showIcon and self._state ~= "idle" then
            self.icon:Show()
        elseif not profile.showIcon then
            self.icon:Hide()
        end
    end

    if not instantEnabled() then
        self:HideInstantOverlay()
    end

    self:Relayout()

    dlog("ApplyOptions applied")
end

ns:RegisterModule("CastBar", {
    defaults = DEFAULTS,
    OnEnable = function(mod, profile) CastBar:OnEnable(mod, profile) end,
    OnDisable = function(mod) CastBar:OnDisable() end,
})

ns:RegisterMessage("PROFILE_CHANGED", function()
    if not CastBar._enabled then return end
    CastBar._baseProfile = ns:GetProfile().modules.CastBar
    CastBar:ApplyOptions()
end)
