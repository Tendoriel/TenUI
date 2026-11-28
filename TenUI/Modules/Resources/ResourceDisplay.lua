local addonName, ns = ...

local CreateFrame      = CreateFrame
local UnitClass        = UnitClass
local UnitPower        = UnitPower
local UnitPowerMax     = UnitPowerMax
local UnitPowerPercent = UnitPowerPercent
local UnitPowerDisplayMod = UnitPowerDisplayMod
local GetSpecialization   = GetSpecialization
local GetRuneCooldown     = GetRuneCooldown
local C_DurationUtil      = C_DurationUtil
local GetTime          = GetTime
local InCombatLockdown = InCombatLockdown
local C_Timer          = C_Timer
local AbbreviateNumbers = AbbreviateNumbers
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local pcall            = pcall
local type             = type
local math_floor       = math.floor
local math_max         = math.max
local math_min         = math.min
local tostring         = tostring
local tonumber         = tonumber
local pairs            = pairs

local Resolver = ns.Resources_Resolver
local Engine   = ns.Resources_Engine

local function powerEnum(name)
    return (Enum and Enum.PowerType and Enum.PowerType[name]) or nil
end

local POWER_TYPE_ENUM = {
    Mana          = powerEnum("Mana")          or 0,
    Rage          = powerEnum("Rage")          or 1,
    Focus         = powerEnum("Focus")         or 2,
    Energy        = powerEnum("Energy")        or 3,
    ComboPoints   = powerEnum("ComboPoints")   or 4,
    Runes         = powerEnum("Runes")         or 5,
    RunicPower    = powerEnum("RunicPower")    or 6,
    SoulShards    = powerEnum("SoulShards")    or 7,
    LunarPower    = powerEnum("LunarPower")    or 8,
    HolyPower     = powerEnum("HolyPower")     or 9,
    Maelstrom     = powerEnum("Maelstrom")     or 11,
    Chi           = powerEnum("Chi")           or 12,
    Insanity      = powerEnum("Insanity")      or 13,
    ArcaneCharges = powerEnum("ArcaneCharges") or 16,
    Fury          = powerEnum("Fury")          or 17,
    Pain          = powerEnum("Pain")          or 18,
    Essence       = powerEnum("Essence")       or 19,
}

local POWER_NAME_BY_ENUM = {}
for name, value in pairs(POWER_TYPE_ENUM) do
    POWER_NAME_BY_ENUM[value] = name
end

local POWER_TYPE_EVENT_STRING = {
    Mana          = "MANA",
    Rage          = "RAGE",
    Focus         = "FOCUS",
    Energy        = "ENERGY",
    ComboPoints   = "COMBO_POINTS",
    Runes         = "RUNES",
    RunicPower    = "RUNIC_POWER",
    SoulShards    = "SOUL_SHARDS",
    LunarPower    = "LUNAR_POWER",
    HolyPower     = "HOLY_POWER",
    Maelstrom     = "MAELSTROM",
    Chi           = "CHI",
    Insanity      = "INSANITY",
    ArcaneCharges = "ARCANE_CHARGES",
    Fury          = "FURY",
    Pain          = "PAIN",
    Essence       = "ESSENCE",
}

local function getScaleTo100()
    if CurveConstants and CurveConstants.ScaleTo100 ~= nil then
        return CurveConstants.ScaleTo100
    end
    return nil
end

local function dlog(fmt, ...)
    if ns.Debug and ns.Debug.Verbose then
        ns.Debug:Verbose("resources", "[Resources] " .. fmt, ...)
    end
end

local reassertCombatVisibility = function() end

local RESOURCES_VERBOSE = false

local function verboseOn()
    if RESOURCES_VERBOSE then return true end
    if ns.db and ns.db.debug and ns.db.debug.verbose
       and ns.db.debug.verbose.resources then
        return true
    end
    return false
end

local function vlog(fmt, ...)
    if not verboseOn() then return end
    if ns.Debug and ns.Debug.Log then
        ns.Debug:Log("[Resources] " .. fmt, ...)
    end
end

local function isSecret(v)
    if Engine and Engine.isSecret then
        return Engine.isSecret(v)
    end
    return type(issecretvalue) == "function" and issecretvalue(v)
end

local _previewActive = false

local function resolveFontKey(key)
    if ns.Controls and ns.Controls.ResolveFontPath then
        return ns.Controls.ResolveFontPath(key)
    end
    return "Fonts\\FRIZQT__.TTF"
end

local VALID_FONT_ANCHORS = {
    CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

local SHARD_COLOR = { 0.74, 0.41, 0.93, 1 }
local RUNIC_COLOR = { 0.00, 0.82, 1.00, 1 }
local RUNE_COLOR  = { 0.77, 0.12, 0.23, 1 }
local MANA_COLOR  = { 0.00, 0.30, 1.00, 1 }

local function getManaColor()
    local _, class = UnitClass("player")
    if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        return {
            (c.r + MANA_COLOR[1]) * 0.5,
            (c.g + MANA_COLOR[2]) * 0.5,
            (c.b + MANA_COLOR[3]) * 0.5,
            1,
        }
    end
    return MANA_COLOR
end

local function getResourceSpecKey()
    local class
    if UnitClass then
        local ok, _n, c = pcall(UnitClass, "player")
        if ok then class = c end
    end
    if type(class) ~= "string" or class == "" then class = "UNKNOWN" end
    local specIdx
    if GetSpecialization then
        local ok, s = pcall(GetSpecialization)
        if ok then specIdx = s end
    end
    if type(specIdx) == "number" and specIdx > 0 then
        return class .. "_" .. tostring(specIdx)
    end
    return class .. "_NIL"
end

local function getActiveSpecColors(profile)
    if not profile then return nil end
    if ns.savedVarsReady and ns.GetProfile then
        local ok, p = pcall(ns.GetProfile, ns)
        if ok and type(p) == "table" and type(p.modules) == "table"
           and type(p.modules.Resources) == "table" then
            profile = p.modules.Resources
        end
    end
    profile.specColors = profile.specColors or {}
    local key = getResourceSpecKey()
    local entry = profile.specColors[key]
    if not entry then
        entry = {}
        profile.specColors[key] = entry
        if not profile._specColorsMigrated then
            profile._specColorsMigrated = true
            local lp = profile.primary
            local ls = profile.secondary
            if lp and lp.color and entry.primary == nil then
                local c = lp.color
                entry.primary = { c[1], c[2], c[3], c[4] or 1 }
            end
            if ls and ls.color and entry.secondary == nil then
                local c = ls.color
                entry.secondary = { c[1], c[2], c[3], c[4] or 1 }
            end
            if lp and type(lp.enabled) == "boolean" and entry.primaryEnabled == nil then
                entry.primaryEnabled = lp.enabled
            end
            if ls and type(ls.enabled) == "boolean" and entry.secondaryEnabled == nil then
                entry.secondaryEnabled = ls.enabled
            end
            if lp and lp.threshold and type(lp.threshold.enabled) == "boolean"
               and entry.thresholdEnabled == nil then
                entry.thresholdEnabled = lp.threshold.enabled
            end
        end
    end
    return entry, key
end

local function resolvePrimaryEnabled(profile)
    local entry = getActiveSpecColors(profile)
    if entry and type(entry.primaryEnabled) == "boolean" then
        return entry.primaryEnabled
    end
    return true
end

local function resolveSecondaryEnabled(profile)
    local entry = getActiveSpecColors(profile)
    if entry and type(entry.secondaryEnabled) == "boolean" then
        return entry.secondaryEnabled
    end
    return true
end

local function resolveThresholdEnabled(profile)
    local entry = getActiveSpecColors(profile)
    if entry and type(entry.thresholdEnabled) == "boolean" then
        return entry.thresholdEnabled
    end
    return false
end

local function resolvePrimaryColor(profile)
    local entry = getActiveSpecColors(profile)
    if entry and entry.primary then return entry.primary end
    return nil
end

local function resolveSecondaryColor(profile)
    local entry = getActiveSpecColors(profile)
    if entry and entry.secondary then return entry.secondary end
    return nil
end

local PRIMARY_SEED_BY_NAME = {
    Mana          = { color = nil,                          maxFallback = 100000 },
    Rage          = { color = { 1.00, 0.00, 0.00, 1 },      maxFallback = 100 },
    Focus         = { color = { 1.00, 0.50, 0.25, 1 },      maxFallback = 100 },
    Energy        = { color = { 1.00, 1.00, 0.00, 1 },      maxFallback = 100 },
    RunicPower    = { color = RUNIC_COLOR,                  maxFallback = 100 },
    LunarPower    = { color = { 0.30, 0.52, 0.90, 1 },      maxFallback = 100 },
    Maelstrom     = { color = { 0.00, 0.50, 1.00, 1 },      maxFallback = 100 },
    Insanity      = { color = { 0.40, 0.00, 0.80, 1 },      maxFallback = 100 },
    Fury          = { color = { 0.79, 0.26, 0.99, 1 },      maxFallback = 100 },
    Essence       = { color = { 0.42, 0.80, 0.47, 1 },      maxFallback = 6 },
    HolyPower     = { color = { 0.95, 0.90, 0.60, 1 },      maxFallback = 5 },
    Chi           = { color = { 0.71, 1.00, 0.92, 1 },      maxFallback = 6 },
    ComboPoints   = { color = { 1.00, 0.96, 0.41, 1 },      maxFallback = 5 },
    ArcaneCharges = { color = { 0.10, 0.10, 0.98, 1 },      maxFallback = 4 },
    SoulShards    = { color = SHARD_COLOR,                  maxFallback = 5 },
}

local SECONDARY_SEED_BY_NAME = {
    SoulShards    = { kind = "shards", powerName = "SoulShards",    pipCount = 5, color = SHARD_COLOR },
    Runes         = { kind = "runes",                              runeCount = 6, color = RUNE_COLOR },
    ComboPoints   = { kind = "shards", powerName = "ComboPoints",   pipCount = 5, color = { 1.00, 0.96, 0.41, 1 } },
    HolyPower     = { kind = "shards", powerName = "HolyPower",     pipCount = 5, color = { 0.95, 0.90, 0.60, 1 } },
    Chi           = { kind = "shards", powerName = "Chi",           pipCount = 5, color = { 0.71, 1.00, 0.92, 1 } },
    ArcaneCharges = { kind = "shards", powerName = "ArcaneCharges", pipCount = 4, color = { 0.10, 0.10, 0.98, 1 } },
    Insanity      = { kind = "bar", powerName = "Insanity",   maxFallback = 100, color = { 0.40, 0.00, 0.80, 1 } },
    LunarPower    = { kind = "bar", powerName = "LunarPower",  maxFallback = 100, color = { 0.30, 0.52, 0.90, 1 } },
    Maelstrom     = { kind = "bar", powerName = "Maelstrom",   maxFallback = 100, color = { 0.00, 0.50, 1.00, 1 } },
    Essence       = { kind = "shards", powerName = "Essence",  pipCount = 6, color = { 0.42, 0.80, 0.47, 1 } },
    Stagger       = { kind = "bar", valueSource = "stagger",       maxFallback = 1, color = { 0.85, 0.55, 0.10, 1 } },
    SoulFragments = { kind = "bar", valueSource = "soulfragments", maxFallback = 50, color = { 0.62, 0.20, 0.78, 1 } },
    VengeanceFragments = { kind = "shards", valueSource = "vengeance", pipCount = 6, color = { 0.62, 0.20, 0.78, 1 } },
}

local AURA_SECONDARY_SEED_BY_KEY = {
    MAELSTROM_WEAPON = { kind = "shards", valueSource = "aura", color = { 0.00, 0.55, 1.00, 1 } },
    ICICLES          = { kind = "shards", valueSource = "aura", color = { 0.55, 0.85, 1.00, 1 } },
    TIP_OF_THE_SPEAR = { kind = "shards", valueSource = "aura", color = { 0.85, 0.45, 0.20, 1 } },
    WHIRLWIND        = { color = { 0.75, 0.25, 0.18, 1 } },
    SWEEPING_STRIKES = { color = { 0.85, 0.50, 0.18, 1 } },
}

local Primary
local function getSpecDescriptor()
    local class, specIdx, specID, name
    if Resolver and Resolver.GetPlayerInfo then
        class, specIdx, specID, name = Resolver:GetPlayerInfo()
    else
        local _, c = UnitClass("player")
        class = c
        specIdx = GetSpecialization and GetSpecialization() or nil
    end

    if not (Resolver and Resolver.GetPrimaryResource) then
        return nil, class, specIdx
    end

    local overrideName
    local sp = Primary and Primary.selfProfile
    if sp then overrideName = sp.powerTypeOverride end
    local primPT = Resolver:GetPrimaryResource(overrideName)
    local primName = primPT and POWER_NAME_BY_ENUM[primPT]
    if not primName then
        return nil, class, specIdx
    end
    local primSeed = PRIMARY_SEED_BY_NAME[primName] or {}

    local primary = {
        kind        = "bar",
        powerName   = primName,
        color       = primSeed.color,
        maxFallback = primSeed.maxFallback,
    }

    local secondary
    local opts = Primary and Primary.profileRef and Primary.profileRef.secondary or {}
    if class == "DRUID" and opts.showManaInForms and overrideName ~= "Mana" then
        local form = GetShapeshiftFormID and GetShapeshiftFormID()
        if (form == 1 or form == 5) and primName ~= "Mana" then
            secondary = { kind = "bar", powerName = "Mana", color = { 0.24, 0.55, 1, 1 } }
        end
    end
    if not secondary and Resolver.GetSecondaryResource then
        local secPT = Resolver:GetSecondaryResource()
        local secName = secPT and POWER_NAME_BY_ENUM[secPT]
        if (not secName) and type(secPT) == "string" and Resolver.GetPowerTypeName then
            secName = Resolver:GetPowerTypeName(secPT)
        end
        local secSeed = secName and SECONDARY_SEED_BY_NAME[secName]
        if secSeed then
            if secSeed.kind == "shards" then
                secondary = {
                    kind      = "shards",
                    powerName = secSeed.powerName,
                    valueSource = secSeed.valueSource,
                    pipCount  = secSeed.pipCount,
                    color     = secSeed.color,
                }
            elseif secSeed.kind == "bar" then
                secondary = {
                    kind        = "bar",
                    powerName   = secSeed.powerName,
                    valueSource = secSeed.valueSource,
                    maxFallback = secSeed.maxFallback,
                    color       = secSeed.color,
                }
            else
                secondary = {
                    kind      = "runes",
                    runeCount = secSeed.runeCount,
                    color     = secSeed.color,
                }
            end
        end
    end

    if (not secondary) and Resolver.GetAuraResource then
        local auraInfo, auraKey, maximum = Resolver:GetAuraResource()
        if auraInfo and auraKey then
            local seed = AURA_SECONDARY_SEED_BY_KEY[auraKey] or {}
            secondary = {
                kind        = "shards",
                valueSource = "aura",
                auraSpellId = auraInfo.spellId,
                altAuraSpellId = auraInfo.altSpellId,
                auraKey     = auraKey,
                pipCount    = maximum,
                color       = seed.color,
            }
        end
    end

    if not name then
        name = tostring(class)
    end

    return { name = name, primary = primary, secondary = secondary }, class, specIdx
end

Primary = {
    eventFrame   = nil,
    bar          = nil,
    anchor       = nil,
    profileRef   = nil,
    selfProfile  = nil,
    desc         = nil,
    _resizeCB    = nil,
    _enabled     = false,
    _thColorCurve     = nil,
    _thColorCurveHash = nil,
    _thCurveFailed    = false,
}

local primary_ApplyFont

local thLines_Rebuild
local thLines_Reposition
local thLines_Recolor
local thLines_HideAll
local thLines_SetEnabled
local thLines_SecondaryBar = function() return nil end

local function primary_BuildWidget()
    if Primary.bar then return Primary.bar end
    local anchor = ns:GetAnchor("Resources")
    if not (anchor and anchor.frame) then
        dlog("Primary: Resources anchor missing -- abort")
        return nil
    end
    Primary.anchor = anchor
    local sp = Primary.selfProfile or {}
    local seedColor = resolvePrimaryColor(Primary.profileRef) or { 0.5, 0.5, 0.5, 1 }
    local bar = ns.Widgets.Bar:New(anchor.frame, {
        orientation = "HORIZONTAL",
        fgColor     = seedColor,
        bgColor     = { 0, 0, 0, 0.7 },
        border      = true,
        leftText    = false,
        rightText   = sp.showText ~= false,
        texture     = sp.texture,
        font        = resolveFontKey(sp.font),
        fontSize    = sp.fontSize or 12,
        fontFlags   = sp.fontFlags or "OUTLINE",
    })
    Primary.bar = bar
    primary_ApplyFont()
    if bar.SetBackground and (sp.showBackground ~= nil or type(sp.bgColor) == "table") then
        local bgc = sp.bgColor
        if type(bgc) == "table" then
            bar:SetBackground(sp.showBackground ~= false, bgc[1], bgc[2], bgc[3], bgc[4])
        else
            bar:SetBackground(sp.showBackground ~= false)
        end
    end
    if bar.SetBorder and (sp.showBorder ~= nil or type(sp.borderColor) == "table") then
        bar:SetBorder(sp.showBorder ~= false,
            (type(sp.borderColor) == "table") and sp.borderColor or nil)
    end
    return bar
end

primary_ApplyFont = function()
    local bar = Primary.bar
    if not (bar and bar.frame) then return end
    local sp = Primary.selfProfile or {}

    local fontPath = resolveFontKey(sp.font)
    local size  = sp.fontSize  or 12
    local flags = sp.fontFlags or "OUTLINE"

    if bar.SetFont then
        pcall(bar.SetFont, bar, fontPath, size, flags)
    end

    local fs = bar.frame.rightText
    if fs then
        local anchor = sp.fontAnchor
        if not (anchor and VALID_FONT_ANCHORS[anchor]) then anchor = "RIGHT" end
        local ox = tonumber(sp.fontX)
        local oy = tonumber(sp.fontY)
        if ox == nil then ox = (anchor == "RIGHT") and -4 or 0 end
        if oy == nil then oy = 0 end
        fs:ClearAllPoints()
        fs:SetPoint(anchor, bar.frame, anchor, ox, oy)
        if anchor:find("LEFT") then
            fs:SetJustifyH("LEFT")
        elseif anchor:find("RIGHT") then
            fs:SetJustifyH("RIGHT")
        else
            fs:SetJustifyH("CENTER")
        end
    end
end

local function primary_Layout()
    if not (Primary.bar and Primary.bar.frame and Primary.anchor and Primary.anchor.frame) then
        return
    end
    local bar, anchor = Primary.bar.frame, Primary.anchor.frame
    bar:ClearAllPoints()
    bar:SetAllPoints(anchor)
    local profile, opts = Primary.profileRef, Primary.selfProfile
    if opts and opts.expandIfNoSecondary and not _previewActive and ns:AreAnchorsLocked()
       and (not ns.EditMode or not ns.EditMode:IsActive()) then
        local desc = getSpecDescriptor()
        local secondaryOpts = profile and profile.secondary or {}
        local secondary = ns:GetAnchor("ResourceSecondary")
        local other = secondary and secondary.frame
        if desc and other and (not desc.secondary or secondaryOpts.enabled == false
            or not resolveSecondaryEnabled(profile)) then
            local pScale, sScale = anchor:GetEffectiveScale(), other:GetEffectiveScale()
            local px, py, pw, ph = anchor:GetRect()
            local sx, sy, sw, sh = other:GetRect()
            if px and sx then
                local pLeft, pRight = px * pScale, (px + pw) * pScale
                local sLeft, sRight = sx * sScale, (sx + sw) * sScale
                local pBottom, pTop = py * pScale, (py + ph) * pScale
                local sBottom, sTop = sy * sScale, (sy + sh) * sScale
                if math.abs(pLeft - sLeft) <= 6 and math.abs(pRight - sRight) <= 6 then
                    if sBottom >= pTop - 1 and sBottom <= pTop + 16 * pScale then
                        bar:ClearAllPoints()
                        bar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT")
                        bar:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, (sTop - pTop) / pScale)
                    elseif sTop <= pBottom + 1 and sTop >= pBottom - 16 * pScale then
                        bar:ClearAllPoints()
                        bar:SetPoint("TOPRIGHT", anchor, "TOPRIGHT")
                        bar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, (sBottom - pBottom) / pScale)
                    end
                end
            end
        end
    end
    if thLines_Reposition then thLines_Reposition() end
    local predict = not _previewActive and opts and opts.showManaCost
        and Primary.desc and resolvePrimaryEnabled(profile) ~= false
    local power = Primary.desc and POWER_TYPE_ENUM[Primary.desc.powerName]
    ns.PowerPrediction.Attach("primary", predict and bar or nil, power)
end

ns:RegisterMessage("ANCHOR_MOVED", function(_, name)
    if name == "Resources" or name == "ResourceSecondary" then primary_Layout() end
end)
ns:RegisterMessage("ANCHOR_RESIZED", function(_, name)
    if name == "ResourceSecondary" then primary_Layout() end
end)
ns:RegisterMessage("LOCK_STATE_CHANGED", function() primary_Layout() end)

local function formatNumber(n)
    if type(n) ~= "number" then return "" end
    if n >= 10000 and AbbreviateNumbers then
        local ok, text = pcall(AbbreviateNumbers, n)
        if ok and text then return text end
    end
    local ok, text = pcall(string.format, "%d", n)
    if ok then return text end
    return ""
end

local function customPowerText(bar, mode, power, current, unmodified)
    if not mode or mode == "auto" then return false end
    local precision = "%d"
    if unmodified then
        local divisor = UnitPowerDisplayMod and UnitPowerDisplayMod(power)
        if isSecret(current) then
            current = UnitPower("player", power)
        elseif type(divisor) == "number" and divisor > 1 then
            current = current / divisor
            precision = "%.1f"
        end
    end
    if mode == "percent" or mode == "both" then
        local ok, percent = pcall(UnitPowerPercent, "player", power, false, getScaleTo100())
        local fs = bar.frame.rightText
        if ok and fs and (isSecret(percent) or type(percent) == "number") then
            if mode == "both" then ok = pcall(fs.SetFormattedText, fs, precision .. " · %.0f%%", current, percent)
            else ok = pcall(fs.SetFormattedText, fs, "%.0f%%", percent) end
            if ok then return true end
        end
    elseif mode == "short" and precision == "%d" then
        local ok, value = pcall(AbbreviateNumbers, current)
        if ok then bar:SetRightText(value) return true end
    end
    if precision == "%.1f" then bar:SetRightText(string.format(precision, current))
    else bar:SetRightText(current) end
    return true
end

local function setBarCurrentValueText(bar, pt, cur, maxV)
    if not (bar and bar.SetRightText) then return end
    local curSecret = isSecret(cur)
    local maxSecret = isSecret(maxV)

    if curSecret or maxSecret then
        local renderedPct = false
        local scaleTo100 = getScaleTo100()
        if UnitPowerPercent and scaleTo100 then
            local ok, pct = pcall(UnitPowerPercent, "player", pt, false, scaleTo100)
            if ok and not isSecret(pct) and type(pct) == "number" then
                local ok2, text = pcall(string.format, "%.0f", pct)
                if ok2 and not isSecret(text) then
                    bar:SetRightText(text)
                    renderedPct = true
                end
            end
        end
        if not renderedPct then
            local rendered = false
            if cur ~= nil and AbbreviateNumbers then
                local ok, text = pcall(AbbreviateNumbers, cur)
                if ok and type(text) == "string" and not isSecret(text) then
                    bar:SetRightText(text)
                    rendered = true
                end
            end
            if not rendered then
                if cur ~= nil then
                    bar:SetRightText(cur)
                else
                    bar:SetRightText("")
                end
            end
        end
    else
        local text = formatNumber(cur)
        bar:SetRightText(text)
    end
end

local function secretSafeStr(v)
    if isSecret(v) then return "<secret>" end
    return tostring(v)
end

local function buildThresholdColorCurve(pct, direction, threshR, threshG, threshB,
                                        baseR, baseG, baseB)
    if Primary._thCurveFailed then return nil end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then
        Primary._thCurveFailed = true
        vlog("threshold curve: C_CurveUtil.CreateColorCurve unavailable")
        return nil
    end
    if not (Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step ~= nil) then
        Primary._thCurveFailed = true
        vlog("threshold curve: Enum.LuaCurveType.Step unavailable")
        return nil
    end

    local p = tonumber(pct) or 20
    if p < 1 then p = 1 elseif p > 99 then p = 99 end
    local dir = (direction == "above") and "above" or "below"
    local t = p / 100
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local EPS = 0.0001

    local hash = string.format("%s|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f",
        dir, t, threshR, threshG, threshB, baseR, baseG, baseB)
    if Primary._thColorCurveHash == hash and Primary._thColorCurve then
        return Primary._thColorCurve
    end

    local okC, curve = pcall(C_CurveUtil.CreateColorCurve)
    if not okC or not curve then
        vlog("threshold curve: CreateColorCurve failed err=%s", tostring(curve))
        return nil
    end

    local okT = pcall(curve.SetType, curve, Enum.LuaCurveType.Step)
    local ok2, ok3, ok4 = true, true, true
    if dir == "below" then
        ok2 = pcall(curve.AddPoint, curve, 0, CreateColor(threshR, threshG, threshB, 1))
        if t < 1 then
            ok3 = pcall(curve.AddPoint, curve, math.min(1, t + EPS),
                CreateColor(baseR, baseG, baseB, 1))
        end
    else
        ok2 = pcall(curve.AddPoint, curve, 0, CreateColor(baseR, baseG, baseB, 1))
        ok3 = pcall(curve.AddPoint, curve, t, CreateColor(threshR, threshG, threshB, 1))
    end
    if not (okT and ok2 and ok3 and ok4) then
        vlog("threshold curve: curve setup failed")
        return nil
    end

    Primary._thColorCurve = curve
    Primary._thColorCurveHash = hash
    return curve
end

local function invalidateThresholdCurve()
    Primary._thColorCurve = nil
    Primary._thColorCurveHash = nil
end

local function primary_Refresh()
    local bar = Primary.bar
    local desc = Primary.desc
    if not (bar and desc) then
        vlog("Primary.Refresh: early-return bar=%s desc=%s",
             tostring(bar), tostring(desc))
        return
    end

    if not _previewActive and resolvePrimaryEnabled(Primary.profileRef) == false then
        bar:Hide()
        return
    end

    if _previewActive then
        local pc = resolvePrimaryColor(Primary.profileRef) or desc.color
        if (not pc) and desc.powerName == "Mana" then
            pc = getManaColor()
        end
        local th = Primary.selfProfile and Primary.selfProfile.threshold
        if th and resolveThresholdEnabled(Primary.profileRef) then
            local pct = tonumber(th.pct) or 20
            local dir = th.direction or "below"
            local hit
            if dir == "above" then
                hit = 65 >= pct
            else
                hit = 65 <= pct
            end
            if hit then
                local tr = th.r if tr == nil then tr = 1 end
                local tg = th.g if tg == nil then tg = 0.1 end
                local tb = th.b if tb == nil then tb = 0.1 end
                pc = { tr, tg, tb, 1 }
            end
        end
        if pc then
            bar:SetColor(pc[1] or 1, pc[2] or 1, pc[3] or 1, pc[4] or 1)
        end
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(65)
        if Primary.selfProfile and Primary.selfProfile.showText ~= false then
            bar:SetRightText("65 / 100")
        else
            bar:SetRightText("")
        end
        bar:Show()
        if thLines_Reposition then thLines_Reposition() end
        if thLines_Recolor then thLines_Recolor() end
        return
    end

    local powerName = desc.powerName
    if not powerName then return end
    local pt = POWER_TYPE_ENUM[powerName]
    if not pt then return end

    local useUnmodified = (powerName == "SoulShards")

    local cur, maxV
    if useUnmodified then
        cur  = UnitPower("player", pt, true)
        maxV = UnitPowerMax("player", pt, true)
    else
        cur  = UnitPower("player", pt)
        maxV = UnitPowerMax("player", pt)
    end

    local curSecret = isSecret(cur)
    local maxSecret = isSecret(maxV)

    if Engine and (not curSecret) and (not maxSecret)
       and type(cur) == "number" and type(maxV) == "number" and maxV > 0 then
        Engine:AcceptCleanPrimary(cur, maxV)
    end

    vlog("Primary.Refresh: power=%s enum=%s cur=%s max=%s curSecret=%s maxSecret=%s",
         tostring(powerName), tostring(pt),
         secretSafeStr(cur), secretSafeStr(maxV),
         tostring(curSecret), tostring(maxSecret))

    local c = resolvePrimaryColor(Primary.profileRef) or desc.color
    if (not c) and powerName == "Mana" then
        c = getManaColor()
    end

    local th = Primary.selfProfile and Primary.selfProfile.threshold
    local thEnabled = resolveThresholdEnabled(Primary.profileRef)
    local applied = false
    if th and thEnabled and UnitPowerPercent then
        local baseR = (c and c[1]) or 1
        local baseG = (c and c[2]) or 1
        local baseB = (c and c[3]) or 1
        local tR = th.r if tR == nil then tR = 1 end
        local tG = th.g if tG == nil then tG = 0.1 end
        local tB = th.b if tB == nil then tB = 0.1 end
        local curve = buildThresholdColorCurve(th.pct, th.direction,
            tR, tG, tB, baseR, baseG, baseB)
        if curve then
            local ok, colorResult = pcall(UnitPowerPercent, "player", pt, false, curve)
            if ok and colorResult and colorResult.GetRGBA then
                local okSet = pcall(function()
                    bar.frame:SetStatusBarColor(colorResult:GetRGBA())
                end)
                if okSet then applied = true end
            end
        end
    end

    if (not applied) and c then
        bar:SetColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    end

    if not maxSecret then
        if type(maxV) ~= "number" or maxV <= 0 then
            local fb = desc.maxFallback
            if type(fb) == "number" and fb > 0 then
                bar:SetMinMaxValues(0, fb)
            else
                bar:SetMinMaxValues(0, 1)
            end
        else
            bar:SetMinMaxValues(0, maxV)
        end
    else
        bar:SetMinMaxValues(0, maxV)
    end

    if not curSecret and type(cur) ~= "number" then cur = 0 end
    bar:SetValue(cur, Primary.selfProfile and Primary.selfProfile.smooth)
    if bar.frame then
        vlog("Primary.Refresh: applied cur=%s max=%s alpha=%s shown=%s w=%s h=%s",
             secretSafeStr(cur), secretSafeStr(maxV),
             tostring(bar.frame:GetAlpha()),
             tostring(bar.frame:IsShown()),
             tostring(bar.frame:GetWidth()),
             tostring(bar.frame:GetHeight()))
    end

    if Primary.selfProfile and Primary.selfProfile.showText ~= false then
        if customPowerText(bar, Primary.selfProfile.valueFormat, pt, cur, useUnmodified) then
            -- The selected format has already written the label.
        elseif curSecret or maxSecret then
            local renderedPct = false
            local scaleTo100 = getScaleTo100()
            if UnitPowerPercent and scaleTo100 then
                local ok, pct = pcall(UnitPowerPercent, "player", pt, false, scaleTo100)
                if ok and not isSecret(pct) and type(pct) == "number" then
                    local ok2, text = pcall(string.format, "%.0f%%", pct)
                    if ok2 and not isSecret(text) then
                        bar:SetRightText(text)
                        renderedPct = true
                    end
                end
            end
            if not renderedPct then
                local rendered = false
                if cur ~= nil and AbbreviateNumbers then
                    local ok, text = pcall(AbbreviateNumbers, cur)
                    if ok and type(text) == "string" and not isSecret(text) then
                        bar:SetRightText(text)
                        rendered = true
                    end
                end
                if not rendered then
                    if cur ~= nil then
                        bar:SetRightText(cur)
                    else
                        bar:SetRightText("")
                    end
                end
            end
        elseif useUnmodified then
            local mod = (UnitPowerDisplayMod and UnitPowerDisplayMod(pt)) or 1
            if type(mod) ~= "number" or mod <= 0 then mod = 1 end
            local shards = cur / mod
            local maxShards = maxV / mod
            local fmt = (mod > 1) and "%.1f / %d" or "%d / %d"
            local ok, text = pcall(string.format, fmt, shards, maxShards)
            if ok then bar:SetRightText(text) else bar:SetRightText("") end
        else
            local curText = formatNumber(cur)
            local maxText = formatNumber(maxV)
            if curText ~= "" and maxText ~= "" then
                bar:SetRightText(curText .. " / " .. maxText)
            else
                bar:SetRightText("")
            end
        end
    else
        bar:SetRightText("")
    end

    bar:Show()
    reassertCombatVisibility()

    if thLines_Reposition then thLines_Reposition() end
    if thLines_Recolor then thLines_Recolor() end
end

local function primary_HideAll()
    ns.PowerPrediction.Attach("primary")
    if Primary.bar then
        Primary.bar:Hide()
    end
    if thLines_HideAll then thLines_HideAll() end
end

local TH_SPENDERS_BY_SPEC = {
    [259] = { 1329, 32645, 196819 },
    [260] = { 193315, 315341, 2098 },
    [261] = { 8676, 53, 196819 },
    [250] = { 206930, 195182, 61999 },
    [251] = { 49143, 207230 },
    [252] = { 47541, 207317, 85948 },
    [71]  = { 12294, 1464, 1715 },
    [72]  = { 85288, 184367, 5308 },
    [73]  = { 23922, 6572, 2565 },
    [253] = { 217200, 34026, 19574 },
    [254] = { 19434, 257044, 257620 },
    [255] = { 259489, 186270, 320976 },
    [269] = { 100780, 107428, 113656 },
    [103] = { 5221, 1822, 106785 },
    [577] = { 162794, 198013, 188499 },
    [581] = { 228477, 247454, 212084 },
    [1480] = { { id = 473728, fixedCost = 100 }, 473662, 1217610 },
    [102] = { 78674, 191034, 205636 },
    [104] = { 192081, 6807, 400254 },

    [258] = { 8092, 228260, 335467, 263165 },
    [262] = { 8042, 61882, 117014, 188196 },
}

Primary._thl    = { overlay = nil, pool = {}, active = 0, maxFallback = nil }
Primary._thlSec = { overlay = nil, pool = {}, active = 0, maxFallback = nil }
Primary._thlEnabled = false
Primary._thlShowNum = true

local THL_COLOR_USABLE   = { 0.20, 0.95, 0.30, 1 }
local THL_COLOR_NOPOWER  = { 0.95, 0.30, 0.20, 1 }
local THL_COLOR_UNUSABLE = { 0.55, 0.55, 0.55, 0.85 }
local THL_LINE_WIDTH     = 2

local DEVOURER_SPEC_ID       = 1480
local COLLAPSING_STAR_SPELLID = 1221150
local CS_FALLBACK_COST        = 30
local function thLines_CollapsingStarCost()
    if type(GetCollapsingStarCost) == "function" then
        local ok, c = pcall(GetCollapsingStarCost)
        if ok and type(c) == "number" and c > 0 then return c end
    end
    return CS_FALLBACK_COST
end

local function thLines_SpenderList()
    local _, specIdx = nil, nil
    if Resolver and Resolver.GetPlayerInfo then
        _, specIdx = Resolver:GetPlayerInfo()
    end
    if not (specIdx and specIdx > 0 and GetSpecializationInfo) then return nil end
    local ok, specId = pcall(GetSpecializationInfo, specIdx)
    if not (ok and specId) then return nil end

    if specId == 103 then
        local formId = GetShapeshiftFormID and GetShapeshiftFormID() or nil
        if formId ~= 1 then return nil end
    elseif specId == 104 then
        local formId = GetShapeshiftFormID and GetShapeshiftFormID() or nil
        if formId ~= 5 then return nil end
    elseif specId == 102 then
        local formId = GetShapeshiftFormID and GetShapeshiftFormID() or nil
        if formId == 1 or formId == 5 then return nil end
    end
    return TH_SPENDERS_BY_SPEC[specId]
end

local function thLines_SpellCostFor(spellId, wantEnum)
    if not wantEnum then return nil end
    if not (C_Spell and C_Spell.GetSpellPowerCost) then return nil end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellId)
    if not (ok and type(costs) == "table") then return nil end
    for i = 1, #costs do
        local entry = costs[i]
        if entry and entry.type == wantEnum then
            local c = entry.cost
            if type(c) == "number" and c > 0 then
                return c
            end
            local mc = entry.minCost
            if type(mc) == "number" and mc > 0 then
                return mc
            end
        end
    end
    return nil
end

local function thLines_IsKnown(spellId)
    local anyCheck = false
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        anyCheck = true
        local ok, k = pcall(C_SpellBook.IsSpellKnown, spellId)
        if ok and k == true then return true, "IsSpellKnown" end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
        anyCheck = true
        local ok, k = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, spellId)
        if ok and k == true then return true, "InSpellBook+overrides" end
    end
    if IsPlayerSpell then
        anyCheck = true
        local ok, k = pcall(IsPlayerSpell, spellId)
        if ok and k == true then return true, "IsPlayerSpell" end
    end
    if not anyCheck then
        return true, "no-check-available"
    end
    return false, "none"
end

local function thLines_AcquireFor(target, i)
    target.pool = target.pool or {}
    local entry = target.pool[i]
    if entry then return entry end
    local overlay = target.overlay
    if not overlay then return nil end

    local f = CreateFrame("Frame", nil, overlay)
    f:SetSize(THL_LINE_WIDTH, overlay:GetHeight() or 16)
    f:EnableMouse(false)
    local tex = f:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(f)
    tex:SetColorTexture(1, 1, 1, 1)

    local label = f:CreateFontString(nil, "OVERLAY")
    ns.Pixel.SetFont(label, resolveFontKey("default"), 9, "OUTLINE")
    label:SetPoint("BOTTOM", f, "TOP", 0, 1)
    label:SetJustifyH("CENTER")
    label:SetTextColor(1, 1, 1, 1)

    entry = { frame = f, tex = tex, label = label, spellId = nil }
    target.pool[i] = entry
    return entry
end

local function thLines_HideTarget(target)
    if not target then return end
    local pool = target.pool
    if pool then
        for i = 1, #pool do
            local e = pool[i]
            if e and e.frame then e.frame:Hide() end
        end
    end
    target.active = 0
end

thLines_HideAll = function()
    thLines_HideTarget(Primary._thl)
    thLines_HideTarget(Primary._thlSec)
end

local function thLines_RepositionTarget(target, bar, powerName, maxFallback)
    if not Primary._thlEnabled then return end
    if not target then return end
    local pool = target.pool
    if not (pool and target.active > 0) then return end
    local overlay = target.overlay
    if not (overlay and bar and bar.frame) then return end

    local width = bar.frame:GetWidth() or 0
    if width <= 0 then return end
    local height = bar.frame:GetHeight() or 16
    overlay:SetHeight(height)

    local minR, maxR
    if type(bar._thlLastMax) == "number" and bar._thlLastMax > 0 then
        minR = (type(bar._thlLastMin) == "number") and bar._thlLastMin or 0
        maxR = bar._thlLastMax
        target.maxFallback = maxR
    end
    if not maxR and powerName then
        local pt = POWER_TYPE_ENUM[powerName]
        if pt and UnitPowerMax then
            local ok, m = pcall(UnitPowerMax, "player", pt)
            if ok and not isSecret(m) and type(m) == "number" and m > 0 then
                minR = 0
                maxR = m
                target.maxFallback = m
            end
        end
    end
    if not maxR then
        minR = 0
        maxR = target.maxFallback or maxFallback or 100
    end
    if type(minR) ~= "number" then minR = 0 end
    if maxR <= minR then maxR = minR + 100 end

    local span = maxR - minR
    if span <= 0 then span = 100 end
    local factor = width / span
    for i = 1, target.active do
        local e = pool[i]
        if e and e.frame and e.cost then
            local x = math_floor((e.cost - minR) * factor + 0.5)
            if x < 0 then x = 0 end
            if x > width then x = width end
            e.frame:SetHeight(height)
            e.frame:ClearAllPoints()
            e.frame:SetPoint("LEFT", bar.frame, "LEFT", x, 0)
            e.frame:Show()
        end
    end
end

thLines_Reposition = function()
    if not Primary._thlEnabled then return end
    local pdesc = Primary.desc
    thLines_RepositionTarget(Primary._thl, Primary.bar,
        pdesc and pdesc.powerName, pdesc and pdesc.maxFallback)
    local secBar = thLines_SecondaryBar()
    if secBar then
        local sd = Primary._thlSecDesc
        thLines_RepositionTarget(Primary._thlSec, secBar,
            sd and sd.powerName, sd and sd.maxFallback)
    end
end

local function thLines_SoulFragmentCount()
    local spellId
    if Resolver and Resolver.SoulFragmentsAuraID then
        local ok, id = pcall(Resolver.SoulFragmentsAuraID, Resolver)
        if ok then spellId = id end
    end
    spellId = spellId or (Resolver and Resolver.SOUL_FRAGMENTS_AURA_ID)
    if Engine and Engine.readAuraStacks and spellId then
        local c = Engine.readAuraStacks("SOUL_FRAGMENTS", spellId)
        if type(c) == "number" and c >= 0 then return c end
    end
    return 0
end

local function thLines_RecolorTarget(target)
    if not target then return end
    local pool = target.pool
    if not (pool and target.active > 0) then return end
    for i = 1, target.active do
        local e = pool[i]
        if e and e.tex and e.spellId then
            local col = THL_COLOR_UNUSABLE
            if e.spellId == COLLAPSING_STAR_SPELLID then
                local cost = (type(e.cost) == "number" and e.cost > 0)
                    and e.cost or thLines_CollapsingStarCost()
                if thLines_SoulFragmentCount() >= cost then
                    col = THL_COLOR_USABLE
                else
                    col = THL_COLOR_NOPOWER
                end
            elseif C_Spell and C_Spell.IsSpellUsable then
                local ok, usable, insufficient = pcall(C_Spell.IsSpellUsable, e.spellId)
                if ok then
                    if usable == true then
                        col = THL_COLOR_USABLE
                    elseif insufficient == true then
                        col = THL_COLOR_NOPOWER
                    else
                        col = THL_COLOR_UNUSABLE
                    end
                end
            end
            e.tex:SetColorTexture(col[1], col[2], col[3], col[4] or 1)
        end
    end
end

thLines_Recolor = function()
    if not Primary._thlEnabled then return end
    thLines_RecolorTarget(Primary._thl)
    thLines_RecolorTarget(Primary._thlSec)
end

local function thLines_EnsureOverlay(target, bar)
    if not (bar and bar.frame) then return nil end
    if not target.overlay then
        local ov = CreateFrame("Frame", nil, bar.frame)
        ov:SetAllPoints(bar.frame)
        ov:EnableMouse(false)
        ov:SetFrameLevel((bar.frame:GetFrameLevel() or 1) + 2)
        target.overlay = ov
    else
        target.overlay:SetParent(bar.frame)
        target.overlay:ClearAllPoints()
        target.overlay:SetAllPoints(bar.frame)
    end
    return target.overlay
end

local function thLines_AddLine(target, n, spellId, cost)
    n = n + 1
    local e = thLines_AcquireFor(target, n)
    if e then
        e.spellId = spellId
        e.cost    = cost
        if Primary._thlShowNum then
            local ok2, txt = pcall(string.format, "%d", cost)
            e.label:SetText(ok2 and txt or "")
            e.label:Show()
        else
            e.label:Hide()
        end
    end
    return n
end

thLines_Rebuild = function()
    if not Primary._thlEnabled then
        if thLines_HideAll then thLines_HideAll() end
        return
    end

    local pbar  = Primary.bar
    local pdesc = Primary.desc
    if not (pbar and pbar.frame and pdesc and pdesc.powerName) then
        if thLines_HideAll then thLines_HideAll() end
        return
    end

    local primaryEnum = POWER_TYPE_ENUM[pdesc.powerName]
    if not primaryEnum then
        if thLines_HideAll then thLines_HideAll() end
        return
    end

    local secBar  = thLines_SecondaryBar()
    local secDesc = Primary._thlSecDesc
    local secEnum = nil
    if secBar and secDesc and secDesc.powerName then
        secEnum = POWER_TYPE_ENUM[secDesc.powerName]
    end

    local primaryIsMana = (pdesc.powerName == "Mana")
    local suppressPrimary = primaryIsMana and (secBar ~= nil) and (secEnum ~= nil)

    if not suppressPrimary then
        thLines_EnsureOverlay(Primary._thl, pbar)
    end
    if secBar and secEnum then
        thLines_EnsureOverlay(Primary._thlSec, secBar)
    end

    local list = thLines_SpenderList()
    if not list then
        if thLines_HideAll then thLines_HideAll() end
        return
    end

    local np, ns_ = 0, 0
    for li = 1, #list do
        local item = list[li]
        local spellId, fixedCost
        if type(item) == "table" then
            spellId   = item.id
            fixedCost = item.fixedCost
        else
            spellId = item
        end
        local known = spellId and thLines_IsKnown(spellId) or false
        if spellId and (known or fixedCost) then
            if not suppressPrimary then
                local costP = thLines_SpellCostFor(spellId, primaryEnum)
                if (not costP) and fixedCost and type(fixedCost) == "number" then
                    costP = fixedCost
                end
                if costP and costP > 0 then
                    np = thLines_AddLine(Primary._thl, np, spellId, costP)
                end
            end
            if secEnum and secEnum ~= primaryEnum then
                local costS = thLines_SpellCostFor(spellId, secEnum)
                if costS and costS > 0 then
                    ns_ = thLines_AddLine(Primary._thlSec, ns_, spellId, costS)
                end
            end
        end
    end

    if secBar and secDesc and secDesc.valueSource == "soulfragments" then
        local _, sIdx = nil, nil
        if Resolver and Resolver.GetPlayerInfo then
            _, sIdx = Resolver:GetPlayerInfo()
        end
        local sId = 0
        if sIdx and sIdx > 0 and GetSpecializationInfo then
            local okS, id = pcall(GetSpecializationInfo, sIdx)
            if okS and id then sId = id end
        end
        local inMeta = Resolver and Resolver.IsInVoidMeta and Resolver:IsInVoidMeta()
        if sId == DEVOURER_SPEC_ID and inMeta then
            thLines_EnsureOverlay(Primary._thlSec, secBar)
            ns_ = thLines_AddLine(Primary._thlSec, ns_,
                COLLAPSING_STAR_SPELLID, thLines_CollapsingStarCost())
        end
    end

    local ppool = Primary._thl.pool or {}
    for i = np + 1, #ppool do
        local e = ppool[i]
        if e and e.frame then e.frame:Hide() end
    end
    Primary._thl.active = np

    local spool = Primary._thlSec.pool or {}
    for i = ns_ + 1, #spool do
        local e = spool[i]
        if e and e.frame then e.frame:Hide() end
    end
    Primary._thlSec.active = ns_

    thLines_Reposition()
    thLines_Recolor()
end

local function thLines_DiagDump()
    if not (ns.Debug and ns.Debug.Log) then return false end
    local function L(fmt, ...) ns.Debug:Log("[ThL] " .. fmt, ...) end

    L("=== thldump (threshold-line diagnostics) ===")
    local pdesc = Primary.desc
    local primaryEnum = (pdesc and pdesc.powerName)
        and POWER_TYPE_ENUM[pdesc.powerName] or nil
    local secBar  = thLines_SecondaryBar()
    local secDesc = Primary._thlSecDesc
    local secEnum = (secBar and secDesc and secDesc.powerName)
        and POWER_TYPE_ENUM[secDesc.powerName] or nil
    local suppressPrimary = (pdesc and pdesc.powerName == "Mana")
        and (secBar ~= nil) and (secEnum ~= nil)
    L("enabled=%s showNum=%s primary=%s(enum=%s) secondary=%s(enum=%s) suppressPrimary=%s",
        tostring(Primary._thlEnabled), tostring(Primary._thlShowNum),
        tostring(pdesc and pdesc.powerName), tostring(primaryEnum),
        tostring(secDesc and (secDesc.powerName or secDesc.valueSource)),
        tostring(secEnum), tostring(suppressPrimary))

    local list = thLines_SpenderList()
    if not list then
        L("spender list: nil (no curated list for this spec/form)")
    end
    for li = 1, (list and #list or 0) do
        local item = list[li]
        local spellId, fixedCost
        if type(item) == "table" then
            spellId   = item.id
            fixedCost = item.fixedCost
        else
            spellId = item
        end
        local known, via = false, "nil-id"
        if spellId then known, via = thLines_IsKnown(spellId) end
        local name = ""
        if spellId and C_Spell and C_Spell.GetSpellName then
            local okN, nm = pcall(C_Spell.GetSpellName, spellId)
            if okN and type(nm) == "string" then name = nm end
        end
        L("spell %s (%s): known=%s (via %s) fixedCost=%s",
            tostring(spellId), name, tostring(known), via, tostring(fixedCost))
        if spellId and C_Spell and C_Spell.GetSpellPowerCost then
            local okC, costs = pcall(C_Spell.GetSpellPowerCost, spellId)
            if okC and type(costs) == "table" then
                if #costs == 0 then L("  cost table EMPTY") end
                for ci = 1, #costs do
                    local c = costs[ci]
                    if c then
                        L("  cost[%d]: type=%s cost=%s minCost=%s costPerSec=%s reqAura=%s hasReqAura=%s",
                            ci, tostring(c.type), tostring(c.cost),
                            tostring(c.minCost), tostring(c.costPerSec),
                            tostring(c.requiredAuraID), tostring(c.hasRequiredAura))
                    end
                end
            else
                L("  GetSpellPowerCost: %s",
                    okC and "nil / non-table" or "pcall FAILED")
            end
        end
        local costP = spellId and thLines_SpellCostFor(spellId, primaryEnum) or nil
        local costS = (spellId and secEnum)
            and thLines_SpellCostFor(spellId, secEnum) or nil
        local matched = ""
        if spellId and (known or fixedCost) then
            if not suppressPrimary then
                local cp = costP
                if (not cp) and type(fixedCost) == "number" then cp = fixedCost end
                if cp and cp > 0 then
                    matched = "PRIMARY@" .. tostring(cp)
                end
            end
            if secEnum and secEnum ~= primaryEnum and costS and costS > 0 then
                matched = (matched ~= "" and (matched .. " + ") or "")
                    .. "SECONDARY@" .. tostring(costS)
            end
        end
        if matched == "" then matched = "NONE" end
        L("  -> matched=%s (costPrimary=%s costSecondary=%s)",
            matched, tostring(costP), tostring(costS))
    end

    if secDesc and secDesc.valueSource == "soulfragments" then
        local inMeta = (Resolver and Resolver.IsInVoidMeta
            and Resolver:IsInVoidMeta()) and true or false
        local csCost = thLines_CollapsingStarCost()
        local frag = thLines_SoulFragmentCount()
        local state
        if not inMeta then
            state = "hidden (not in Void Meta)"
        elseif frag >= csCost then
            state = "shown GREEN (count >= cost)"
        else
            state = "shown RED (count < cost)"
        end
        L("CS synthetic line: inMeta=%s csCost=%s fragments(scrubbed)=%s -> %s",
            tostring(inMeta), tostring(csCost), tostring(frag), state)
    end
    L("active lines: primary=%d secondary=%d",
        Primary._thl.active or 0, Primary._thlSec.active or 0)
    L("=== end thldump ===")
    return true
end

local function thLines_SetSecondaryTarget(secDesc)
    Primary._thlSecDesc = secDesc
    if Primary._thlEnabled then
        if thLines_Rebuild then thLines_Rebuild() end
    end
end

thLines_SetEnabled = function(show, showNum)
    Primary._thlEnabled = show and true or false
    Primary._thlShowNum = (showNum ~= false)
    if Primary._thlEnabled then
        thLines_Rebuild()
    else
        if thLines_HideAll then thLines_HideAll() end
    end
end

local function primary_Rebuild()
    local desc = getSpecDescriptor()
    if not desc or not desc.primary then
        dlog("Primary.Rebuild: no descriptor for current spec -- hiding")
        ns.PowerPrediction.Attach("primary")
        Primary.desc = nil
        primary_HideAll()
        return false
    end
    Primary.desc = desc.primary
    local built = primary_BuildWidget()
    dlog("Primary.Rebuild: desc.powerName=%s bar=%s anchor=%s",
         tostring(Primary.desc.powerName), tostring(built),
         tostring(Primary.anchor and Primary.anchor.frame))
    primary_Layout()
    primary_Refresh()
    if thLines_Rebuild then thLines_Rebuild() end
    return true
end

local PRIMARY_EVENTS = {
    UNIT_POWER_UPDATE             = true,
    UNIT_POWER_FREQUENT           = true,
    UNIT_MAXPOWER                 = true,
    UNIT_DISPLAYPOWER             = true,
    PLAYER_ENTERING_WORLD         = true,
    PLAYER_SPECIALIZATION_CHANGED = true,
    UPDATE_SHAPESHIFT_FORM        = true,
}

local function primary_ExpectedPowerString()
    local desc = Primary.desc
    if not desc then return nil end
    local pn = desc.powerName
    if not pn then return nil end
    return POWER_TYPE_EVENT_STRING[pn]
end

local function primary_OnEvent(_self, event, unit, arg2)
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED"
       or event == "UNIT_DISPLAYPOWER" or event == "UPDATE_SHAPESHIFT_FORM" then
        primary_Rebuild()
        primary_Refresh()
        return
    end
    if event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
       or event == "UNIT_MAXPOWER" then
        if unit ~= "player" then return end
        local expected = primary_ExpectedPowerString()
        if expected and arg2 and arg2 ~= expected then
            return
        end
        primary_Refresh()
        return
    end
    if event == "SPELL_UPDATE_USABLE" or event == "SPELL_UPDATE_COOLDOWN" then
        if thLines_Recolor then thLines_Recolor() end
        return
    end
    if event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_TALENT_UPDATE"
       or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
        if thLines_Rebuild then thLines_Rebuild() end
        return
    end
end

function Primary:Enable(parentProfile)
    if self._enabled then return end
    self.profileRef = parentProfile
    self.selfProfile = parentProfile and parentProfile.primary or {}
    if self.selfProfile.enabled == false then
        dlog("Primary: disabled via profile.primary.enabled=false")
        return
    end

    if not self.eventFrame then
        self.eventFrame = CreateFrame("Frame", "TenUIResourcePrimaryEventFrame")
    end
    local ef = self.eventFrame
    ef:SetScript("OnEvent", primary_OnEvent)

    local function regUnit(event)
        local ok, err = pcall(ef.RegisterUnitEvent, ef, event, "player")
        if not ok then dlog("Primary regUnit(%s) failed: %s", event, tostring(err)) end
    end
    regUnit("UNIT_POWER_UPDATE")
    regUnit("UNIT_POWER_FREQUENT")
    regUnit("UNIT_MAXPOWER")
    regUnit("UNIT_DISPLAYPOWER")
    ef:RegisterEvent("PLAYER_ENTERING_WORLD")
    ef:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    pcall(ef.RegisterEvent, ef, "UPDATE_SHAPESHIFT_FORM")
    pcall(ef.RegisterEvent, ef, "SPELL_UPDATE_USABLE")
    pcall(ef.RegisterEvent, ef, "SPELL_UPDATE_COOLDOWN")
    pcall(ef.RegisterEvent, ef, "TRAIT_CONFIG_UPDATED")
    pcall(ef.RegisterEvent, ef, "PLAYER_TALENT_UPDATE")

    self._resizeCB = ns:RegisterMessage("ANCHOR_RESIZED", function(_, name)
        if name == "Resources" then primary_Layout() end
    end)

    self._enabled = true
    primary_Rebuild()
    primary_Refresh()
end

function Primary:Disable()
    if not self._enabled then return end
    ns.PowerPrediction.Attach("primary")
    self._enabled = false
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
        self.eventFrame:SetScript("OnEvent", nil)
    end
    if self._resizeCB then
        ns:UnregisterMessage("ANCHOR_RESIZED", self._resizeCB)
        self._resizeCB = nil
    end
    primary_HideAll()
    self.desc = nil
end

local Secondary = {
    eventFrame   = nil,
    container    = nil,
    pips         = {},
    anchor       = nil,
    profileRef   = nil,
    selfProfile  = nil,
    desc         = nil,
    _resizeCB    = nil,
    _enabled     = false,
    _kind        = nil,
    _valueSource = nil,
    _unitAuraRegistered = false,
    barWidget    = nil,
    countOverlay = nil,
    countText    = nil,
    _runeDurations = {},
    _runeReadyColor  = nil,
    _runeChargeColor = nil,
    shardPool    = {},
    runePool     = {},
    lastSecondaryMax  = -1,
    lastSecondaryType = nil,
}

local SECONDARY_COUNT_MIN = 1
local SECONDARY_COUNT_MAX = 10
local NativeBar = ns.NativeResourceBar

local function secondary_AttachPrediction(frame, pips, spacing)
    local power = Secondary.desc and POWER_TYPE_ENUM[Secondary.desc.powerName]
    local mana = power == POWER_TYPE_ENUM.Mana
    local primary, secondary = Primary.selfProfile or {}, Secondary.selfProfile or {}
    local enabled = (mana and primary.showManaCost) or secondary.showPrediction
    if _previewActive or not enabled or resolveSecondaryEnabled(Secondary.profileRef) == false then
        frame = nil
    end
    ns.PowerPrediction.Attach("secondary", frame, power, pips, spacing)
end

local buildShardPip
local buildRune
local secondary_EnsureContainer
local secondary_ApplyPipStyle
local _runeLastSec = {}

local function secondary_PoolForKind(kind)
    if kind == "shards" then
        return Secondary.shardPool
    elseif kind == "runes" then
        return Secondary.runePool
    end
    return nil
end

local function secondary_AcquirePip(kind, i, color)
    local pool = secondary_PoolForKind(kind)
    if not pool then return nil end
    local w = pool[i]
    if w then
        if kind == "shards" and color and w.SetStatusBarColor then
            w:SetStatusBarColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        end
        if secondary_ApplyPipStyle then secondary_ApplyPipStyle(w, kind) end
        return w
    end
    local container = secondary_EnsureContainer()
    if not container then return nil end
    if kind == "shards" then
        w = buildShardPip(container, color)
    else
        w = buildRune(container, color)
        w.runeIndex = i
    end
    if secondary_ApplyPipStyle then secondary_ApplyPipStyle(w, kind) end
    pool[i] = w
    return w
end

local function secondary_ReleaseExtras(kind, n)
    local pool = secondary_PoolForKind(kind)
    if not pool then return end
    for i = n + 1, #pool do
        local w = pool[i]
        if w then
            if w.text and w.text.SetText then
                w.text:SetText("")
            end
            _runeLastSec[i] = nil
            w:Hide()
        end
    end
end

local function secondary_HideAllPooled()
    ns.PowerPrediction.Attach("secondary")
    if Secondary.nativeAura then Secondary.nativeAura.frame:Hide() end
    NativeBar.Hide(Secondary.barWidget)
    for i = 1, #Secondary.shardPool do
        local w = Secondary.shardPool[i]
        if w then w:Hide() end
    end
    for i = 1, #Secondary.runePool do
        local w = Secondary.runePool[i]
        if w then
            if w.text and w.text.SetText then w.text:SetText("") end
            w:Hide()
        end
    end
    for i = 1, #Secondary.pips do
        Secondary.pips[i] = nil
    end
    if Secondary.barWidget then
        Secondary.barWidget:Hide()
    end
    if Secondary.countOverlay then
        Secondary.countText:SetText("")
        Secondary.countOverlay:Hide()
    end
    Secondary._kind = nil
    Secondary._valueSource = nil
end

secondary_EnsureContainer = function()
    if Secondary.container then return Secondary.container end
    local anchor = ns:GetAnchor("ResourceSecondary")
    if not (anchor and anchor.frame) then return nil end
    Secondary.anchor = anchor
    local c = CreateFrame("Frame", "TenUIResourceSecondaryContainer", anchor.frame)
    c:SetAllPoints(anchor.frame)
    Secondary.container = c
    return c
end

local function secondary_ResolveTexture()
    local sp = Secondary.selfProfile or {}
    local key = sp.texture
    if ns.Widgets and ns.Widgets.resolveMedia then
        return ns.Widgets.resolveMedia("statusbar", key, ns.Widgets.DEFAULT_STATUSBAR)
    end
    if type(key) == "string" and key ~= "" then return key end
    return ns.Widgets.DEFAULT_STATUSBAR
end

local function secondary_TextConf()
    local ss = Secondary.selfProfile or {}
    if type(ss.text) == "table" then return ss.text end
    return nil
end

local function secondary_TextEnabledForBar()
    local t = secondary_TextConf()
    if t and type(t.enabled) == "boolean" then return t.enabled end
    local sp = Primary.selfProfile or {}
    return sp.showText ~= false
end

local function secondary_CountEnabled()
    local t = secondary_TextConf()
    return (t and t.enabled) == true
end

local function secondary_EnsureCountText()
    if Secondary.countText then return Secondary.countText end
    local container = secondary_EnsureContainer()
    if not container then return nil end
    local overlay = CreateFrame("Frame", nil, container)
    overlay:SetAllPoints(container)
    overlay:EnableMouse(false)
    overlay:SetFrameLevel(container:GetFrameLevel() + 10)
    local fs = overlay:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    ns.Pixel.SetFont(fs, "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    fs:SetTextColor(1, 1, 1, 1)
    fs:SetText("")
    Secondary.countOverlay = overlay
    Secondary.countText = fs
    return fs
end

local function secondary_ApplyCountFont(fs, overlay)
    fs = fs or Secondary.countText
    overlay = overlay or Secondary.countOverlay
    if not (fs and overlay) then return end
    local sp = Primary.selfProfile or {}
    local t = secondary_TextConf() or {}
    local fontPath = resolveFontKey(t.font or sp.font)
    local size  = tonumber(t.fontSize) or sp.fontSize or 12
    local flags = t.fontFlags or sp.fontFlags or "OUTLINE"
    ns.Pixel.SetFont(fs, fontPath, size, flags)
    local anchor = t.anchor
    if not (anchor and VALID_FONT_ANCHORS[anchor]) then anchor = "CENTER" end
    local ox = tonumber(t.x) or 0
    local oy = tonumber(t.y) or 0
    fs:ClearAllPoints()
    fs:SetPoint(anchor, overlay, anchor, ox, oy)
    if anchor:find("LEFT") then
        fs:SetJustifyH("LEFT")
    elseif anchor:find("RIGHT") then
        fs:SetJustifyH("RIGHT")
    else
        fs:SetJustifyH("CENTER")
    end
end

local function secondary_UpdateCountVisibility()
    local wantShow = secondary_CountEnabled()
        and (Secondary._kind == "shards" or Secondary._kind == "runes")
    if not wantShow then
        if Secondary.countOverlay then
            Secondary.countText:SetText("")
            Secondary.countOverlay:Hide()
        end
        return false
    end
    local fs = secondary_EnsureCountText()
    if not fs then return false end
    Secondary.countOverlay:Show()
    return true
end

local function secondary_CountActive()
    return secondary_CountEnabled()
        and Secondary.countText ~= nil
        and Secondary.countOverlay ~= nil
        and Secondary.countOverlay:IsShown()
end

local function secondary_SetCountValue(value)
    local fs = Secondary.countText
    if not fs then return end
    if isSecret(value) then
        pcall(fs.SetText, fs, value)
    elseif type(value) == "number" then
        fs:SetText(tostring(math_floor(value + 0.5)))
    else
        fs:SetText("")
    end
end

local function secondary_RefreshVengeance()
    local getCount = C_Spell and C_Spell.GetSpellCastCount
    local ok, count = pcall(getCount, 228477)
    if not ok or type(count) ~= "number" then count = 0 end
    for index, pip in ipairs(Secondary.pips) do
        pip:SetMinMaxValues(index - 1, index)
        pip:SetValue(count)
    end
    if secondary_CountActive() then secondary_SetCountValue(count) end
end

local function secondary_UpdateCountFromPower(pt)
    if not secondary_CountActive() then return end
    local cur = UnitPower("player", pt)
    secondary_SetCountValue(cur)
end

local PIP_BG_SHARDS = { 0, 0, 0, 0.6 }
local PIP_BG_RUNES  = { 0.2, 0.2, 0.2, 0.6 }

local function secondary_StyleConf()
    local ss = Secondary.selfProfile or {}
    if type(ss.style) == "table" then return ss.style end
    return nil
end

secondary_ApplyPipStyle = function(f, kind)
    if not f then return end
    local st = secondary_StyleConf() or {}

    local showBorder = true
    if type(st.showBorder) == "boolean" then showBorder = st.showBorder end
    local bc = (type(st.borderColor) == "table") and st.borderColor or nil
    if f.borderParts then
        for i = 1, #f.borderParts do
            local t = f.borderParts[i]
            if bc then
                t:SetColorTexture(bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 1)
            else
                t:SetColorTexture(0, 0, 0, 1)
            end
            t:SetShown(showBorder)
        end
    end

    local showBg = true
    if type(st.showBackground) == "boolean" then showBg = st.showBackground end
    local bgc = (type(st.backgroundColor) == "table") and st.backgroundColor
        or ((kind == "runes") and PIP_BG_RUNES or PIP_BG_SHARDS)
    if f.bg then
        if kind == "runes" then
            f.bg:SetColorTexture(bgc[1] or 0, bgc[2] or 0, bgc[3] or 0, bgc[4] or 1)
        else
            f.bg:SetVertexColor(bgc[1] or 0, bgc[2] or 0, bgc[3] or 0, bgc[4] or 1)
        end
        f.bg:SetShown(showBg)
    end
end

local function secondary_ApplyBarStyle()
    local bar = Secondary.barWidget
    if not bar then return end
    local st = secondary_StyleConf() or {}
    local pp = Primary.selfProfile or {}

    if bar.SetBackground
       and (st.showBackground ~= nil or type(st.backgroundColor) == "table"
            or pp.showBackground ~= nil or type(pp.bgColor) == "table") then
        local show
        if type(st.showBackground) == "boolean" then
            show = st.showBackground
        else
            show = pp.showBackground ~= false
        end
        local c = (type(st.backgroundColor) == "table") and st.backgroundColor
            or ((type(pp.bgColor) == "table") and pp.bgColor or nil)
        if c then
            bar:SetBackground(show, c[1], c[2], c[3], c[4])
        else
            bar:SetBackground(show)
        end
    end

    if bar.SetBorder
       and (st.showBorder ~= nil or type(st.borderColor) == "table"
            or pp.showBorder ~= nil or type(pp.borderColor) == "table") then
        local show
        if type(st.showBorder) == "boolean" then
            show = st.showBorder
        else
            show = pp.showBorder ~= false
        end
        bar:SetBorder(show,
            (type(st.borderColor) == "table") and st.borderColor
            or ((type(pp.borderColor) == "table") and pp.borderColor or nil))
    end
end

local function secondary_ApplyStyle()
    if Secondary.barWidget then
        secondary_ApplyBarStyle()
    end
    local kind = Secondary._kind
    if kind == "shards" or kind == "runes" then
        for i = 1, #Secondary.pips do
            secondary_ApplyPipStyle(Secondary.pips[i], kind)
        end
    end
end

buildShardPip = function(parent, color)
    local f = CreateFrame("StatusBar", nil, parent, "BackdropTemplate")
    f:SetMinMaxValues(0, 1)
    f:SetValue(0)
    f:SetStatusBarTexture(secondary_ResolveTexture())
    f:SetStatusBarColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetTexture(secondary_ResolveTexture())
    bg:SetVertexColor(0, 0, 0, 0.6)
    f.bg = bg
    local function side()
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0, 0, 0, 1)
        return t
    end
    local top, bottom, left, right = side(), side(), side(), side()
    top:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    ns.Pixel.Edge(top, f, true)
    bottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    ns.Pixel.Edge(bottom, f, true)
    left:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    ns.Pixel.Edge(left, f, false)
    right:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    ns.Pixel.Edge(right, f, false)
    f.borderParts = { top, bottom, left, right }
    return f
end

local RUNE_READY_COLOR  = { 0.77, 0.12, 0.23, 1 }
local RUNE_CHARGE_COLOR = { 0.50, 0.10, 0.15, 1 }

buildRune = function(parent, _color)
    local f = CreateFrame("StatusBar", nil, parent, "BackdropTemplate")
    f:SetStatusBarTexture(secondary_ResolveTexture())
    f:SetMinMaxValues(0, 1)
    f:SetValue(1)
    f:SetStatusBarColor(RUNE_READY_COLOR[1], RUNE_READY_COLOR[2], RUNE_READY_COLOR[3], RUNE_READY_COLOR[4])

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0.2, 0.2, 0.2, 0.6)
    f.bg = bg

    local function side()
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0, 0, 0, 1)
        return t
    end
    local top, bottom, left, right = side(), side(), side(), side()
    top:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    ns.Pixel.Edge(top, f, true)
    bottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    ns.Pixel.Edge(bottom, f, true)
    left:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    ns.Pixel.Edge(left, f, false)
    right:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    ns.Pixel.Edge(right, f, false)
    f.borderParts = { top, bottom, left, right }

    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", f, "CENTER", 0, 0)
    ns.Pixel.SetFont(text, "Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    text:SetTextColor(1, 1, 1, 1)
    text:SetText("")
    f.text = text

    return f
end

local function secondary_PopulateActive(kind, count, color)
    local container = secondary_EnsureContainer()
    if not container then return end
    local otherKind = (kind == "shards") and "runes" or "shards"
    secondary_ReleaseExtras(otherKind, 0)
    if Secondary.barWidget then
        ns.PowerPrediction.Attach("secondary")
        Secondary.barWidget:Hide()
    end
    Secondary._kind = kind
    for i = 1, count do
        local w = secondary_AcquirePip(kind, i, color)
        w.baseColor = color
        Secondary.pips[i] = w
    end
    for i = count + 1, #Secondary.pips do
        Secondary.pips[i] = nil
    end
    secondary_ReleaseExtras(kind, count)
end

local function secondary_LayoutPips()
    local container = Secondary.container
    if not container then return end
    local count = #Secondary.pips
    if count == 0 then return end
    local sp = Secondary.selfProfile or {}
    local spacing = sp.pipSpacing or 2
    if type(spacing) ~= "number" or spacing < 0 then spacing = 0 end
    local total_w = container:GetWidth() or 0
    local h = container:GetHeight() or 0
    if total_w <= 0 or h <= 0 then return end
    local each_w = (total_w - spacing * (count - 1)) / count
    if each_w < 1 then each_w = 1 end
    for i = 1, count do
        local p = Secondary.pips[i]
        if p then
            p:ClearAllPoints()
            p:SetSize(each_w, h)
            local x = (i - 1) * (each_w + spacing)
            p:SetPoint("LEFT", container, "LEFT", x, 0)
            p:Show()
        end
    end
    local predictsPower = Secondary._kind == "shards" and not Secondary._valueSource
    secondary_AttachPrediction(predictsPower and container or nil, Secondary.pips, spacing)
end

local SPEC_WARLOCK_DESTRUCTION = 267

local function secondary_ShardsIsDestruction()
    if not (GetSpecialization and GetSpecializationInfo) then return false end
    local okIdx, specIdx = pcall(GetSpecialization)
    if not (okIdx and specIdx and specIdx > 0) then return false end
    local okId, specId = pcall(GetSpecializationInfo, specIdx)
    return okId and specId == SPEC_WARLOCK_DESTRUCTION
end

local shardFillCurves = {}

local function secondary_RefreshShards()
    local desc = Secondary.desc
    if not desc then return end
    local powerName = desc.powerName
    if not powerName then return end
    local pt = POWER_TYPE_ENUM[powerName]
    if not pt then return end

    ns.PowerPrediction.UpdatePips()
    secondary_UpdateCountFromPower(pt)

    if powerName == "ComboPoints" then
        local options = Secondary.selfProfile or {}
        local charged = GetUnitChargedPowerPoints and GetUnitChargedPowerPoints("player")
        for index, pip in ipairs(Secondary.pips) do
            local c = index == #Secondary.pips and options.lastPointColor or pip.baseColor
            if options.chargedPointColor and not isSecret(charged) and type(charged) == "table" then
                for _, point in ipairs(charged) do
                    if not isSecret(point) and point == index then c = options.chargedPointColor break end
                end
            end
            if c then pip:SetStatusBarColor(unpack(c)) end
        end
    end
    local modCur = UnitPower("player", pt)
    if isSecret(modCur) then
        if not (UnitPowerPercent and C_CurveUtil and C_CurveUtil.CreateCurve) then return end
        local count = #Secondary.pips
        local curves = shardFillCurves[count]
        if not curves then
            curves = {}
            for i = 1, count do
                local curve = C_CurveUtil.CreateCurve()
                curve:SetType(Enum.LuaCurveType.Linear)
                curve:AddPoint((i - 1) / count, 0)
                curve:AddPoint(i / count, 1)
                curves[i] = curve
            end
            shardFillCurves[count] = curves
        end
        local raw = powerName == "SoulShards" and secondary_ShardsIsDestruction()
        for i, pip in ipairs(Secondary.pips) do
            local ok, fill = pcall(UnitPowerPercent, "player", pt, raw, curves[i])
            if ok then pip:SetValue(fill) end
        end
        return
    end

    if type(modCur) ~= "number" then
        for i = 1, #Secondary.pips do
            local p = Secondary.pips[i]
            if p then p:SetValue(0) end
        end
        return
    end

    local whole = math_floor(modCur + 0.5)

    local partialFrac = 0
    local partialIndex = nil
    if powerName == "SoulShards" and secondary_ShardsIsDestruction() then
        local mod = (UnitPowerDisplayMod and UnitPowerDisplayMod(pt)) or 1
        if type(mod) ~= "number" or mod <= 0 then mod = 1 end
        local total = UnitPower("player", pt, true)
        if type(total) == "number" and not isSecret(total) then
            local exact = total / mod
            local eps = (MathUtil and MathUtil.Epsilon) or 0.000001
            whole = math_floor(exact + eps)
            local rem = exact - whole
            if rem > eps then
                partialFrac = math_min(1, math_max(0, rem))
                partialIndex = whole + 1
            end
        end
    end

    for i = 1, #Secondary.pips do
        local p = Secondary.pips[i]
        if p then
            if i <= whole then
                p:SetValue(1)
            elseif partialIndex and i == partialIndex then
                p:SetValue(partialFrac)
            else
                p:SetValue(0)
            end
        end
    end
end

local function secondary_GetRuneDuration(index)
    local d = Secondary._runeDurations[index]
    if d then return d end
    if not (C_DurationUtil and C_DurationUtil.CreateDuration) then return nil end
    d = C_DurationUtil.CreateDuration()
    Secondary._runeDurations[index] = d
    return d
end

local function updateRuneTexts(container)
    if not GetRuneCooldown then
        container:SetScript("OnUpdate", nil)
        return
    end
    local anyActive = false
    local now = GetTime()
    for i = 1, #Secondary.pips do
        local rune = Secondary.pips[i]
        if rune and rune.text then
            local ok, start, duration, ready = pcall(GetRuneCooldown, i)
            if ok and not ready and type(start) == "number"
               and type(duration) == "number" and duration > 0 then
                local okArith, remaining = pcall(function()
                    return duration - (now - start)
                end)
                if okArith and type(remaining) == "number" and remaining > 0 then
                    local secInt
                    if remaining >= 0 then
                        secInt = math.ceil(remaining)
                    else
                        secInt = 0
                    end
                    if _runeLastSec[i] ~= secInt then
                        _runeLastSec[i] = secInt
                        if secInt > 0 then
                            rune.text:SetText(tostring(secInt))
                        else
                            rune.text:SetText("")
                        end
                    end
                    anyActive = true
                else
                    rune.text:SetText("")
                    _runeLastSec[i] = nil
                end
            else
                rune.text:SetText("")
                _runeLastSec[i] = nil
            end
        end
    end
    if not anyActive then
        container:SetScript("OnUpdate", nil)
    end
end

local function secondary_RefreshRunes()
    if not GetRuneCooldown then return end
    local container = Secondary.container
    local anyRecharging = false
    local readyCount = 0

    local readyC  = Secondary._runeReadyColor  or RUNE_READY_COLOR
    local chargeC = Secondary._runeChargeColor or RUNE_CHARGE_COLOR

    for i = 1, #Secondary.pips do
        local rune = Secondary.pips[i]
        if rune then
            local ok, start, duration, ready = pcall(GetRuneCooldown, i)
            if not ok then
                rune:SetMinMaxValues(0, 1)
                rune:SetValue(1)
                rune:SetStatusBarColor(readyC[1], readyC[2], readyC[3], readyC[4])
                if rune.text then rune.text:SetText("") end
                _runeLastSec[i] = nil
                readyCount = readyCount + 1
            elseif ready then
                rune:SetMinMaxValues(0, 1)
                rune:SetValue(1)
                rune:SetStatusBarColor(readyC[1], readyC[2], readyC[3], readyC[4])
                if rune.text then rune.text:SetText("") end
                _runeLastSec[i] = nil
                readyCount = readyCount + 1
            else
                if type(start) == "number" and type(duration) == "number" and duration > 0 then
                    rune:SetStatusBarColor(chargeC[1], chargeC[2], chargeC[3], chargeC[4])
                    local dur = secondary_GetRuneDuration(i)
                    if dur and dur.SetTimeFromStart and rune.SetTimerDuration then
                        local okSet = pcall(dur.SetTimeFromStart, dur, start, duration, 1)
                        if okSet then
                            local interp = (Enum and Enum.StatusBarInterpolation
                                            and Enum.StatusBarInterpolation.Immediate) or 0
                            local direction = (Enum and Enum.StatusBarTimerDirection
                                               and Enum.StatusBarTimerDirection.ElapsedTime) or 0
                            local okTimer = pcall(rune.SetTimerDuration, rune, dur, interp, direction)
                            if not okTimer then
                                rune:SetMinMaxValues(0, 1)
                                rune:SetValue(0)
                            end
                        else
                            rune:SetMinMaxValues(0, 1)
                            rune:SetValue(0)
                        end
                    else
                        rune:SetMinMaxValues(0, 1)
                        rune:SetValue(0)
                    end
                    anyRecharging = true
                else
                    rune:SetMinMaxValues(0, 1)
                    rune:SetValue(0)
                    rune:SetStatusBarColor(chargeC[1], chargeC[2], chargeC[3], chargeC[4])
                end
            end
        end
    end

    if secondary_CountActive() then
        secondary_SetCountValue(readyCount)
    end

    if container and anyRecharging then
        container:SetScript("OnUpdate", updateRuneTexts)
        updateRuneTexts(container)
    elseif container and not anyRecharging then
        container:SetScript("OnUpdate", nil)
    end
end

local function secondary_ApplyBarFont()
    local bar = Secondary.barWidget
    if not (bar and bar.frame) then return end
    local sp = Primary.selfProfile or {}
    local t = secondary_TextConf() or {}

    local fontPath = resolveFontKey(t.font or sp.font)
    local size  = tonumber(t.fontSize) or sp.fontSize or 12
    local flags = t.fontFlags or sp.fontFlags or "OUTLINE"
    if bar.SetFont then
        pcall(bar.SetFont, bar, fontPath, size, flags)
    end

    local fs = bar.frame.rightText
    if fs then
        local anchor = t.anchor
        if not (anchor and VALID_FONT_ANCHORS[anchor]) then anchor = sp.fontAnchor end
        if not (anchor and VALID_FONT_ANCHORS[anchor]) then anchor = "RIGHT" end
        local ox = tonumber(t.x)
        if ox == nil then ox = tonumber(sp.fontX) end
        local oy = tonumber(t.y)
        if oy == nil then oy = tonumber(sp.fontY) end
        if ox == nil then ox = (anchor == "RIGHT") and -4 or 0 end
        if oy == nil then oy = 0 end
        fs:ClearAllPoints()
        fs:SetPoint(anchor, bar.frame, anchor, ox, oy)
        local justify = anchor:find("LEFT") and "LEFT" or anchor:find("RIGHT") and "RIGHT" or "CENTER"
        fs:SetJustifyH(justify)
        Secondary.nativeBarFont = { fontPath, size, flags, anchor, ox, oy, justify }
    end
end

local function secondary_BuildBar()
    if Secondary.barWidget then return Secondary.barWidget end
    local container = secondary_EnsureContainer()
    if not container then return nil end
    local seedColor = resolveSecondaryColor(Secondary.profileRef)
        or (Secondary.desc and Secondary.desc.color) or { 0.5, 0.5, 0.5, 1 }
    local psp = Primary.selfProfile or {}
    local tconf = secondary_TextConf() or {}
    local bar = ns.Widgets.Bar:New(container, {
        orientation = "HORIZONTAL",
        fgColor     = seedColor,
        bgColor     = { 0, 0, 0, 0.7 },
        border      = true,
        leftText    = false,
        rightText   = true,
        texture     = secondary_ResolveTexture(),
        font        = resolveFontKey(tconf.font or psp.font),
        fontSize    = tonumber(tconf.fontSize) or psp.fontSize or 12,
        fontFlags   = tconf.fontFlags or psp.fontFlags or "OUTLINE",
    })
    Secondary.barWidget = bar
    secondary_ApplyBarFont()
    secondary_ApplyBarStyle()
    return bar
end

local function secondary_LayoutBar()
    local bar = Secondary.barWidget
    local container = Secondary.container
    if not (bar and bar.frame and container) then return end
    bar.frame:ClearAllPoints()
    bar.frame:SetAllPoints(container)
    bar:Show()
    secondary_AttachPrediction(bar.frame)
    if thLines_Reposition then thLines_Reposition() end
end

thLines_SecondaryBar = function()
    if Secondary._kind == "bar" and Secondary.barWidget and Secondary.barWidget.frame then
        return Secondary.barWidget
    end
    return nil
end

local function secondary_RefreshBar()
    local bar = Secondary.barWidget
    local desc = Secondary.desc
    if not (bar and desc) then return end
    local powerName = desc.powerName
    if not powerName then return end
    local pt = POWER_TYPE_ENUM[powerName]
    if not pt then return end

    local c = resolveSecondaryColor(Secondary.profileRef) or desc.color
    if c then
        bar:SetColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    end

    local cur  = UnitPower("player", pt)
    local maxV = UnitPowerMax("player", pt)
    local maxSecret = isSecret(maxV)

    if not maxSecret then
        if type(maxV) ~= "number" or maxV <= 0 then
            local fb = desc.maxFallback
            if type(fb) == "number" and fb > 0 then
                bar:SetMinMaxValues(0, fb)
            else
                bar:SetMinMaxValues(0, 1)
            end
        else
            bar:SetMinMaxValues(0, maxV)
        end
    else
        bar:SetMinMaxValues(0, maxV)
    end

    if not isSecret(cur) and type(cur) ~= "number" then cur = 0 end
    local options = Secondary.selfProfile or {}
    bar:SetValue(cur, options.smooth)
    if secondary_TextEnabledForBar() then
        if not customPowerText(bar, options.valueFormat, pt, cur) then setBarCurrentValueText(bar, pt, cur, maxV) end
    else
        bar:SetRightText("")
    end

    bar:Show()
    if thLines_Reposition then thLines_Reposition() end
    if thLines_Recolor then thLines_Recolor() end
end

local function secondary_SetPseudoBar(cur, max, showPercent)
    local bar = Secondary.barWidget
    if not (bar and bar.frame) then return end
    local mx = (type(max) == "number" and max > 0) and max or 1
    local cv = (type(cur) == "number" and cur >= 0) and cur or 0
    if cv > mx then cv = mx end
    bar:SetMinMaxValues(0, mx)
    bar:SetValue(cv)
    if secondary_TextEnabledForBar() then
        if showPercent then
            local pct = (mx > 0) and math_floor((cv / mx) * 100 + 0.5) or 0
            local ok, text = pcall(string.format, "%d%%", pct)
            bar:SetRightText(ok and text or "")
        else
            local ok, text = pcall(string.format, "%d / %d",
                math_floor(cv + 0.5), math_floor(mx + 0.5))
            bar:SetRightText(ok and text or "")
        end
    else
        bar:SetRightText("")
    end
    bar:Show()
end

local function secondary_RefreshStaggerBar()
    local bar = Secondary.barWidget
    local desc = Secondary.desc
    if not (bar and desc) then return end
    local c = resolveSecondaryColor(Secondary.profileRef) or desc.color
    if c then bar:SetColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
    local cur, max, readable, rawStagger, rawMax = 0, 0
    if Engine and Engine.readStagger then
        cur, max, readable, rawStagger, rawMax = Engine.readStagger("STAGGER")
    end
    if not readable and type(rawStagger) == "number" and type(rawMax) == "number" then
        local rangeSet = pcall(bar.SetMinMaxValues, bar, 0, rawMax)
        if rangeSet and pcall(bar.SetValue, bar, rawStagger) then
            bar:SetRightText("")
            bar:Show()
            return
        end
    end
    secondary_SetPseudoBar(cur, max, true)
end

local function secondary_RefreshFragmentsBar()
    local bar = Secondary.barWidget
    local desc = Secondary.desc
    if not (bar and desc) then return end
    local c = resolveSecondaryColor(Secondary.profileRef) or desc.color
    if c then bar:SetColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
    local spellId
    if Resolver and Resolver.SoulFragmentsAuraID then
        local ok, id = pcall(Resolver.SoulFragmentsAuraID, Resolver)
        if ok then spellId = id end
    end
    spellId = spellId or (Resolver and Resolver.SOUL_FRAGMENTS_AURA_ID)
    local cur, known, raw
    if Engine and Engine.readAuraStacks and spellId then
        cur, known, raw = Engine.readAuraStacks("SOUL_FRAGMENTS", spellId)
    end
    local max = desc.maxFallback or 50
    if Resolver and Resolver.GetSoulFragmentsMax then
        local ok, m = pcall(Resolver.GetSoulFragmentsMax, Resolver)
        if ok and type(m) == "number" and m > 0 then max = m end
    end
    if not known and not isSecret(raw) then
        local powerType = Enum.PowerType.SoulFragments
        if powerType then
            local powerMax = UnitPowerMax("player", powerType)
            if isSecret(powerMax) or (type(powerMax) == "number" and powerMax > 0) then
                raw, max = UnitPower("player", powerType), powerMax
            end
        end
    end
    if isSecret(raw) or isSecret(max) or type(raw) == "number" then
        NativeBar.Hide(bar)
        bar:SetMinMaxValues(0, max)
        bar:SetValue(raw)
        bar:SetRightText("")
        if secondary_TextEnabledForBar() then bar:SetRightText(raw) end
        bar:Show()
    elseif known then
        NativeBar.Hide(bar)
        secondary_SetPseudoBar(cur, max, false)
    else
        bar:SetMinMaxValues(0, max)
        bar:SetValue(0)
        bar:SetRightText("")
        bar:Show()
        if spellId then
            NativeBar.Show(bar, spellId, max, secondary_ResolveTexture(), c,
                secondary_TextEnabledForBar() and Secondary.nativeBarFont or nil)
        end
    end

    if Primary._thlEnabled then
        local inMeta = (Resolver and Resolver.IsInVoidMeta and Resolver:IsInVoidMeta()) and true or false
        if Secondary._csLastInMeta ~= inMeta then
            Secondary._csLastInMeta = inMeta
            if thLines_Rebuild then thLines_Rebuild() end
        end
        if thLines_Recolor then thLines_Recolor() end
    end
end

local function secondary_SyncNativeAuraPips()
    local count, spellID = #Secondary.pips, Secondary.desc.auraSpellId
    if count == 0 or not spellID then return false end
    local current = Secondary.nativeAura
    local restricted = InCombatLockdown()
        or (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret())
    local texture = secondary_ResolveTexture()
    local color = resolveSecondaryColor(Secondary.profileRef) or Secondary.desc.color or { 1, 1, 1, 1 }
    local style = secondary_StyleConf() or {}
    local border = style.showBorder
    if type(border) ~= "boolean" then border = (Primary.selfProfile or {}).showBorder ~= false end
    local textEnabled = secondary_CountEnabled()
    local function setFill(fill, pip)
        local inset = border and ns.Pixel.Size(pip, 1) or 0
        fill:ClearAllPoints()
        fill:SetPoint("TOPLEFT", pip, "TOPLEFT", inset, -inset)
        fill:SetPoint("BOTTOMRIGHT", pip, "BOTTOMRIGHT", -inset, inset)
        fill:SetStatusBarTexture(texture)
        fill:SetStatusBarColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
    if current and current.spellID == spellID and current.count == count then
        if not restricted then
            for index, fill in ipairs(current.fills) do setFill(fill, Secondary.pips[index]) end
            secondary_ApplyCountFont(current.text, current.textHost)
            current.textHost:SetShown(textEnabled)
        end
        current.frame:Show()
        return true
    end
    if current then current.frame:Hide() end
    if Secondary.nativeAuraRetry and Secondary.nativeAuraRetry > GetTime() then return false end

    local frame
    local candidate = { spellID = spellID, count = count, fills = {} }
    local ok, err = pcall(function()
        frame = CreateFrame("AuraContainer", nil, Secondary.container, "CustomAuraContainerTemplate")
        frame:SetAllPoints(Secondary.container)
        frame:EnableMouse(false)
        frame:SetUnit("player")
        local filters = { includeSpellIDs = { [spellID] = true } }
        if Secondary.desc.altAuraSpellId then
            filters.includeSpellIDs[Secondary.desc.altAuraSpellId] = true
        end
        local formatter = C_StringUtil.CreateNumericRuleFormatter()
        formatter:SetBreakpoints({ { threshold = 0, format = "%d" } })
        for index, pip in ipairs(Secondary.pips) do
            frame:AddAuraSlot(tostring(index), "HELPFUL", {
                candidateFilters = filters,
                initializeFrame = function(button)
                    button:SetAllPoints(frame)
                    button:SetMouseClickEnabled(false)
                    button:SetMouseMotionEnabled(false)
                    local fill = CreateFrame("StatusBar", nil, button)
                    fill:SetFrameLevel(pip:GetFrameLevel() + 1)
                    setFill(fill, pip)
                    button:SetApplicationBar(fill, { minApplications = index - 1, maxApplications = index })
                    candidate.fills[index] = fill
                    if index == 1 then
                        local host = CreateFrame("Frame", nil, button)
                        host:SetAllPoints(frame)
                        host:SetFrameLevel(pip:GetFrameLevel() + 10)
                        local text = host:CreateFontString(nil, "OVERLAY")
                        text:SetTextColor(1, 1, 1, 1)
                        secondary_ApplyCountFont(text, host)
                        host:SetShown(textEnabled)
                        button:SetApplicationCount(text, { formatter = formatter })
                        candidate.text, candidate.textHost = text, host
                    end
                end,
            })
        end
        frame:SetEnabled(true)
    end)
    if not ok then
        if frame then frame:Hide() end
        Secondary.nativeAuraRetry = GetTime() + 2
        dlog("Secondary aura pips: %s", tostring(err))
        return false
    end
    candidate.frame = frame
    Secondary.nativeAura, Secondary.nativeAuraRetry = candidate, nil
    return true
end

local function secondary_RefreshAuraPips()
    local desc = Secondary.desc
    if not desc then return end
    local spellId = desc.auraSpellId
    local native = secondary_SyncNativeAuraPips()
    local count, known
    if not native and Engine and Engine.readAuraStacks and spellId then
        count, known = Engine.readAuraStacks(desc.auraKey or "AURA", spellId)
        if count == 0 and desc.altAuraSpellId then
            count, known = Engine.readAuraStacks(desc.auraKey, desc.altAuraSpellId)
        end
    end
    if type(count) ~= "number" or count < 0 then count = 0 end
    for i = 1, #Secondary.pips do
        local p = Secondary.pips[i]
        if p then
            p:SetValue(i <= count and 1 or 0)
        end
    end
    if secondary_CountActive() then
        secondary_SetCountValue(known and count or nil)
    end
end

local function secondary_PreviewRender()
    local kind = Secondary._kind
    if kind == "shards" then
        for i = 1, #Secondary.pips do
            local p = Secondary.pips[i]
            if p then
                p:SetMinMaxValues(0, 1)
                p:SetValue(i <= 3 and 1 or 0)
                p:Show()
            end
        end
        if secondary_CountActive() then
            secondary_SetCountValue(3)
        end
    elseif kind == "runes" then
        local n = #Secondary.pips
        local readyC  = Secondary._runeReadyColor  or RUNE_READY_COLOR
        local chargeC = Secondary._runeChargeColor or RUNE_CHARGE_COLOR
        if Secondary.container then
            Secondary.container:SetScript("OnUpdate", nil)
        end
        for i = 1, n do
            local rune = Secondary.pips[i]
            if rune then
                rune:SetMinMaxValues(0, 1)
                if i > n - 2 then
                    rune:SetValue(0.5)
                    rune:SetStatusBarColor(chargeC[1], chargeC[2], chargeC[3], chargeC[4])
                    if rune.text then rune.text:SetText("5") end
                else
                    rune:SetValue(1)
                    rune:SetStatusBarColor(readyC[1], readyC[2], readyC[3], readyC[4])
                    if rune.text then rune.text:SetText("") end
                end
                _runeLastSec[i] = nil
                rune:Show()
            end
        end
        if secondary_CountActive() then
            secondary_SetCountValue(math_max(0, n - 2))
        end
    elseif kind == "bar" then
        local bar = Secondary.barWidget
        if bar then
            local c = resolveSecondaryColor(Secondary.profileRef)
                or (Secondary.desc and Secondary.desc.color)
            if c then
                bar:SetColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
            end
            bar:SetMinMaxValues(0, 100)
            bar:SetValue(50)
            if secondary_TextEnabledForBar() then
                bar:SetRightText("50")
            else
                bar:SetRightText("")
            end
            bar:Show()
            if thLines_Reposition then thLines_Reposition() end
            if thLines_Recolor then thLines_Recolor() end
        end
    end
end

local function secondary_Refresh()
    if Secondary.nativeAura and (_previewActive or Secondary._valueSource ~= "aura") then
        Secondary.nativeAura.frame:Hide()
    end
    if _previewActive then
        NativeBar.Hide(Secondary.barWidget)
        secondary_PreviewRender()
        return
    end
    local vs = Secondary._valueSource
    if vs ~= "soulfragments" then NativeBar.Hide(Secondary.barWidget) end
    if Secondary._kind == "shards" then
        if vs == "aura" then
            secondary_RefreshAuraPips()
        elseif vs == "vengeance" then
            secondary_RefreshVengeance()
        else
            secondary_RefreshShards()
        end
    elseif Secondary._kind == "runes" then
        secondary_RefreshRunes()
    elseif Secondary._kind == "bar" then
        if vs == "stagger" then
            secondary_RefreshStaggerBar()
        elseif vs == "soulfragments" then
            secondary_RefreshFragmentsBar()
        else
            secondary_RefreshBar()
        end
    end
    reassertCombatVisibility()
end

local function secondary_ApplyValueText()
    if Secondary.barWidget and Secondary.barWidget.frame then
        secondary_ApplyBarFont()
        local fs = Secondary.barWidget.frame.rightText
        if fs then
            fs:SetShown(secondary_TextEnabledForBar())
        end
    end
    if secondary_UpdateCountVisibility() then
        secondary_ApplyCountFont()
    end
    local source = Secondary._valueSource
    if source == "aura" or source == "soulfragments" or secondary_CountActive() then
        secondary_Refresh()
    end
end

local function secondary_ApplyTexture()
    local path = secondary_ResolveTexture()
    if Secondary.barWidget and Secondary.barWidget.SetTexture then
        Secondary.barWidget:SetTexture(path)
    end
    for i = 1, #Secondary.pips do
        local p = Secondary.pips[i]
        if p and p.SetStatusBarTexture then
            p:SetStatusBarTexture(path)
            if Secondary._kind == "shards" and p.bg and p.bg.SetTexture then
                p.bg:SetTexture(path)
                local st = secondary_StyleConf() or {}
                local bgc = (type(st.backgroundColor) == "table")
                    and st.backgroundColor or PIP_BG_SHARDS
                p.bg:SetVertexColor(bgc[1] or 0, bgc[2] or 0, bgc[3] or 0, bgc[4] or 1)
            end
        end
    end
end

local function secondary_ResolveCount(kind)
    local fallback = (kind == "runes") and 6 or 5
    local rawMax = 0
    if Resolver and Resolver.GetSecondaryMax then
        rawMax = Resolver:GetSecondaryMax()
    end
    local count = Engine and Engine.scrubNumber(rawMax, fallback) or fallback
    if type(count) ~= "number" then count = fallback end
    count = math_floor(count + 0.5)
    if count <= 0 then count = fallback end
    if count < SECONDARY_COUNT_MIN then count = SECONDARY_COUNT_MIN end
    if count > SECONDARY_COUNT_MAX then count = SECONDARY_COUNT_MAX end
    return count
end

local function secondary_UpdatePseudoLifecycle(vs)
    local ef = Secondary.eventFrame
    local needsAura = (vs == "aura" or vs == "soulfragments" or vs == "vengeance")

    if vs ~= "soulfragments" then
        Secondary._csLastInMeta = nil
    end

    if ef and needsAura ~= Secondary._unitAuraRegistered then
        if needsAura then
            ef:RegisterUnitEvent("UNIT_AURA", "player")
        else
            ef:UnregisterEvent("UNIT_AURA")
        end
        Secondary._unitAuraRegistered = needsAura
    end

    if Engine then
        if Engine.EnsureStaggerTicker then
            Engine:EnsureStaggerTicker(vs == "stagger", secondary_Refresh)
        end
    end
end

local function secondary_Rebuild()
    local desc = getSpecDescriptor()
    if not (desc and desc.secondary) then
        ns.PowerPrediction.Attach("secondary")
        secondary_HideAllPooled()
        Secondary.desc = nil
        Secondary._valueSource = nil
        Secondary.lastSecondaryType = nil
        Secondary.lastSecondaryMax  = -1
        secondary_UpdatePseudoLifecycle(nil)
        if thLines_SetSecondaryTarget then thLines_SetSecondaryTarget(nil) end
        return false
    end
    Secondary.desc = desc.secondary
    local kind = desc.secondary.kind
    Secondary._valueSource = desc.secondary.valueSource
    secondary_UpdatePseudoLifecycle(Secondary._valueSource)
    if kind ~= "shards" and kind ~= "runes" and kind ~= "bar" then
        ns.PowerPrediction.Attach("secondary")
        secondary_HideAllPooled()
        Secondary._valueSource = nil
        Secondary.lastSecondaryType = nil
        Secondary.lastSecondaryMax  = -1
        secondary_UpdatePseudoLifecycle(nil)
        if thLines_SetSecondaryTarget then thLines_SetSecondaryTarget(nil) end
        return false
    end

    local color = resolveSecondaryColor(Secondary.profileRef)
        or desc.secondary.color or { 1, 1, 1, 1 }

    if kind == "bar" then
        secondary_ReleaseExtras("shards", 0)
        secondary_ReleaseExtras("runes", 0)
        for i = 1, #Secondary.pips do
            Secondary.pips[i] = nil
        end
        Secondary._runeReadyColor  = nil
        Secondary._runeChargeColor = nil
        Secondary._kind = "bar"
        secondary_BuildBar()
        secondary_LayoutBar()
        if Secondary._valueSource == "soulfragments" and Secondary.barWidget then
            local texture = secondary_ResolveTexture()
            local font = secondary_TextEnabledForBar() and Secondary.nativeBarFont or nil
            NativeBar.Prepare(Secondary.barWidget, Resolver.SOUL_FRAGMENTS_AURA_ID, Resolver:GetSoulFragmentsMax(false), texture, color, font)
            NativeBar.Prepare(Secondary.barWidget, Resolver.COLLAPSING_STAR_AURA_ID, Resolver:GetSoulFragmentsMax(true), texture, color, font)
        end
        secondary_UpdateCountVisibility()
        Secondary.lastSecondaryType = "bar"
        Secondary.lastSecondaryMax  = -1
        if thLines_SetSecondaryTarget then
            thLines_SetSecondaryTarget(desc.secondary)
        end
        secondary_Refresh()
        return true
    end
    if thLines_SetSecondaryTarget then
        thLines_SetSecondaryTarget(nil)
    end
    if kind == "runes" then
        Secondary._runeReadyColor  = color
        Secondary._runeChargeColor = {
            (color[1] or 1) * 0.65,
            (color[2] or 1) * 0.65,
            (color[3] or 1) * 0.65,
            color[4] or 1,
        }
    else
        Secondary._runeReadyColor  = nil
        Secondary._runeChargeColor = nil
    end

    local count
    if Secondary._valueSource == "aura" then
        count = desc.secondary.pipCount or 5
        if type(count) ~= "number" then count = 5 end
        count = math_floor(count + 0.5)
        if count < SECONDARY_COUNT_MIN then count = SECONDARY_COUNT_MIN end
    elseif Secondary._valueSource == "vengeance" then
        count = desc.secondary.pipCount
    else
        count = secondary_ResolveCount(kind)
    end

    local typeChanged  = (Secondary.lastSecondaryType ~= kind)
    local countChanged = (Secondary.lastSecondaryMax  ~= count)
    local needPopulate = typeChanged or countChanged or (#Secondary.pips == 0)

    if needPopulate then
        secondary_PopulateActive(kind, count, color)
        secondary_LayoutPips()
        Secondary.lastSecondaryType = kind
        Secondary.lastSecondaryMax  = count
    end

    if secondary_UpdateCountVisibility() then
        secondary_ApplyCountFont()
    end

    secondary_Refresh()
    return true
end

local function secondary_ExpectedPowerString()
    local desc = Secondary.desc
    if not desc then return nil end
    local pn = desc.powerName
    if not pn then return nil end
    return POWER_TYPE_EVENT_STRING[pn]
end

local SECONDARY_RELAYOUT_EVENTS = {
    PLAYER_TALENT_UPDATE        = true,
    TRAIT_CONFIG_UPDATED        = true,
    ACTIVE_TALENT_GROUP_CHANGED = true,
    UPDATE_SHAPESHIFT_FORM      = true,
}

local function secondary_DeferredRelayout()
    if InCombatLockdown and InCombatLockdown() and C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            secondary_Rebuild()
        end)
    else
        secondary_Rebuild()
    end
end

local function secondary_OnEvent(_self, event, unit, arg2)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" or event == "PLAYER_REGEN_ENABLED" then
        if Secondary._valueSource then secondary_Refresh() end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        secondary_Rebuild()
        secondary_Refresh()
        return
    end
    if SECONDARY_RELAYOUT_EVENTS[event] then
        secondary_DeferredRelayout()
        return
    end
    if event == "UNIT_AURA" then
        if unit ~= "player" then return end
        local vs = Secondary._valueSource
        if vs == "aura" or vs == "soulfragments" or vs == "vengeance" then
            secondary_Refresh()
        end
        return
    end
    if event == "SPELL_UPDATE_CHARGES" then
        if Secondary._valueSource == "vengeance" then secondary_Refresh() end
        return
    end
    if event == "UNIT_MAXPOWER" then
        if unit ~= "player" then return end
        if Secondary._valueSource then return end
        if Secondary._kind == "shards" or Secondary._kind == "runes" then
            local expected = secondary_ExpectedPowerString()
            if expected and arg2 and arg2 ~= expected then
                return
            end
            secondary_DeferredRelayout()
        elseif Secondary._kind == "bar" then
            local expected = secondary_ExpectedPowerString()
            if expected and arg2 and arg2 ~= expected then
                return
            end
            secondary_Refresh()
        end
        return
    end
    if event == "UNIT_POWER_POINT_CHARGE" then secondary_RefreshShards() return end
    if event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
        if unit ~= "player" then return end
        if Secondary._valueSource then return end
        if Secondary._kind == "shards" or Secondary._kind == "bar" then
            local expected = secondary_ExpectedPowerString()
            if expected and arg2 and arg2 ~= expected then
                return
            end
            secondary_Refresh()
        end
        return
    end
    if event == "RUNE_POWER_UPDATE" or event == "RUNE_TYPE_UPDATE" then
        if Secondary._kind == "runes" then
            secondary_Refresh()
        end
        return
    end
end

function Secondary:Enable(parentProfile)
    if self._enabled then return end
    self.profileRef = parentProfile
    self.selfProfile = parentProfile and parentProfile.secondary or {}
    if self.selfProfile.enabled == false then
        dlog("Secondary: disabled via profile.secondary.enabled=false")
        return
    end

    if not self.eventFrame then
        self.eventFrame = CreateFrame("Frame", "TenUIResourceSecondaryEventFrame")
    end
    local ef = self.eventFrame
    ef:SetScript("OnEvent", secondary_OnEvent)

    local function regUnit(event)
        local ok, err = pcall(ef.RegisterUnitEvent, ef, event, "player")
        if not ok then dlog("Secondary regUnit(%s) failed: %s", event, tostring(err)) end
    end
    regUnit("UNIT_POWER_POINT_CHARGE")
    regUnit("UNIT_POWER_UPDATE")
    regUnit("UNIT_POWER_FREQUENT")
    regUnit("UNIT_MAXPOWER")
    ef:RegisterEvent("PLAYER_ENTERING_WORLD")
    ef:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")
    ef:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    ef:RegisterEvent("SPELL_UPDATE_CHARGES")
    pcall(ef.RegisterEvent, ef, "RUNE_POWER_UPDATE")
    pcall(ef.RegisterEvent, ef, "RUNE_TYPE_UPDATE")
    pcall(ef.RegisterEvent, ef, "PLAYER_TALENT_UPDATE")
    pcall(ef.RegisterEvent, ef, "TRAIT_CONFIG_UPDATED")
    pcall(ef.RegisterEvent, ef, "ACTIVE_TALENT_GROUP_CHANGED")
    pcall(ef.RegisterEvent, ef, "UPDATE_SHAPESHIFT_FORM")

    self._resizeCB = ns:RegisterMessage("ANCHOR_RESIZED", function(_, name)
        if name == "ResourceSecondary" then
            if Secondary._kind == "bar" then
                secondary_LayoutBar()
            else
                secondary_LayoutPips()
            end
        end
    end)

    self._enabled = true
    secondary_Rebuild()
    secondary_Refresh()
end

function Secondary:Disable()
    if not self._enabled then return end
    ns.PowerPrediction.Attach("secondary")
    self._enabled = false
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
        self.eventFrame:SetScript("OnEvent", nil)
    end
    if self._resizeCB then
        ns:UnregisterMessage("ANCHOR_RESIZED", self._resizeCB)
        self._resizeCB = nil
    end
    if Secondary.container then
        Secondary.container:SetScript("OnUpdate", nil)
    end
    Secondary._unitAuraRegistered = false
    Secondary._valueSource = nil
    if Engine and Engine.StopAllTickers then
        Engine:StopAllTickers()
    end
    secondary_HideAllPooled()
    Secondary.lastSecondaryType = nil
    Secondary.lastSecondaryMax  = -1
    self.desc = nil
end

local Display = {
    Primary   = Primary,
    Secondary = Secondary,
    getSpecDescriptor      = getSpecDescriptor,
    getManaColor           = getManaColor,
    primary_Refresh        = primary_Refresh,
    primary_Rebuild        = primary_Rebuild,
    primary_ApplyFont      = primary_ApplyFont,
    secondary_ApplyBarFont = secondary_ApplyBarFont,
    secondary_ApplyValueText = secondary_ApplyValueText,
    secondary_ApplyStyle   = secondary_ApplyStyle,
    invalidateThresholdCurve = invalidateThresholdCurve,
    secondary_ApplyTexture = secondary_ApplyTexture,
    secondary_LayoutPips   = secondary_LayoutPips,
    getResourceSpecKey     = getResourceSpecKey,
    getActiveSpecColors    = getActiveSpecColors,
    resolvePrimaryColor    = resolvePrimaryColor,
    resolveSecondaryColor  = resolveSecondaryColor,
    resolvePrimaryEnabled    = resolvePrimaryEnabled,
    resolveSecondaryEnabled  = resolveSecondaryEnabled,
    resolveThresholdEnabled  = resolveThresholdEnabled,
    thLines_SetEnabled       = thLines_SetEnabled,
    thLines_Rebuild          = thLines_Rebuild,
    thLines_DiagDump         = thLines_DiagDump,
    secondary_Refresh        = secondary_Refresh,
    secondary_Rebuild        = secondary_Rebuild,
    RefreshPowerPrediction  = function()
        primary_Layout()
        if Secondary._kind == "bar" then
            secondary_LayoutBar()
        else
            secondary_LayoutPips()
        end
    end,
    SetPreviewActive         = function(flag)
        _previewActive = flag and true or false
        if _previewActive then
            ns.PowerPrediction.Attach("primary")
            ns.PowerPrediction.Attach("secondary")
        end
    end,
    IsPreviewActive          = function() return _previewActive end,
}

function Display.SetReassert(fn)
    if type(fn) == "function" then
        reassertCombatVisibility = fn
    else
        reassertCombatVisibility = function() end
    end
end

ns.Resources_Display = Display

return Display
