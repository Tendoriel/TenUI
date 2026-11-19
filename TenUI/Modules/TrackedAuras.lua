local _, ns = ...

local TrackedAuras = {}
ns.TrackedAuras = TrackedAuras

local groups = {}
local fixedBars
local failures = {}
local groupKey = "tracked"
local maxTrackedIcons = 40
local unitFilters = { player = "HELPFUL", target = "HARMFUL|PLAYER" }
local cooldownDebuffs = setmetatable({}, { __mode = "k" })
local cooldownDebuffFailures = setmetatable({}, { __mode = "k" })
local iconAlignment
local iconTimerOptions
local auraCountFormatter
local timerCurves = setmetatable({}, { __mode = "v" })

local function signature(value)
    if type(value) ~= "table" then return tostring(value) end
    local parts = {}
    for key, field in pairs(value) do
        parts[#parts + 1] = tostring(key) .. "=" .. signature(field)
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
end

local function applyBorder(button, regions, color)
    if not regions then
        regions = {}
        for i, point in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local edge = button:CreateTexture(nil, "OVERLAY")
            if i <= 2 then
                edge:SetPoint(point .. "LEFT")
                edge:SetPoint(point .. "RIGHT")
                edge:SetHeight(1)
            else
                edge:SetPoint("TOP" .. point)
                edge:SetPoint("BOTTOM" .. point)
                edge:SetWidth(1)
            end
            regions[i] = edge
        end
    end
    for i = 1, #regions do
        local edge = regions[i]
        if color then edge:SetColorTexture(unpack(color)) end
        edge:SetShown(color ~= nil)
    end
    return regions
end

local function makeRegions(button, isBar)
    local regions = {}
    local textParent = button
    regions.icon = button:CreateTexture(nil, "ARTWORK")
    regions.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if isBar then
        local bar = CreateFrame("StatusBar", nil, button)
        regions.bar = bar
        regions.bg = bar:CreateTexture(nil, "BACKGROUND")
        regions.bg:SetAllPoints(bar)
        regions.name = bar:CreateFontString(nil, "OVERLAY")
        regions.name:SetJustifyH("LEFT")
        regions.timer = bar:CreateFontString(nil, "OVERLAY")
    else
        regions.icon:SetAllPoints(button)
        local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cooldown:SetAllPoints(button)
        cooldown:SetReverse(true)
        cooldown:SetDrawBling(false)
        cooldown:SetHideCountdownNumbers(true)
        cooldown:EnableMouse(false)
        regions.cooldown = cooldown
        textParent = CreateFrame("Frame", nil, button)
        textParent:SetAllPoints(button)
        textParent:SetFrameLevel(cooldown:GetFrameLevel() + 1)
        regions.timer = textParent:CreateFontString(nil, "OVERLAY")
    end
    regions.count = textParent:CreateFontString(nil, "OVERLAY")
    regions.pandemic = button:CreateTexture(nil, "OVERLAY")
    if isBar then
        regions.pandemic:SetAllPoints(button)
    else
        regions.pandemic:SetPoint("TOPLEFT", button, "TOPLEFT", -5, 5)
        regions.pandemic:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 5, -5)
    end
    regions.pandemic:SetAtlas(isBar and "UI-CooldownManager-PandemicBorderBar" or "UI-CooldownManager-PandemicBorder")
    regions.pandemic:Hide()
    return regions
end

local function applyCustomGlow(button, regions, config, intent, name, color)
    local renderer = name and ns.Glow:GetStyleRenderer(name)
    local state = regions.glows and regions.glows[intent]
    if not state then
        if not renderer then return nil end
        local host = CreateFrame("Frame", nil, button)
        host:SetPoint("CENTER", button)
        host:SetFrameLevel(button:GetFrameLevel() + 2)
        host:EnableMouse(false)
        state = { host = host }
        regions.glows = regions.glows or {}
        regions.glows[intent] = state
    end
    local host = state.host
    if state.renderer and state.renderer ~= renderer then
        pcall(state.renderer.clear, host)
        state.renderer, state.signature = nil, nil
    end
    if not renderer then return nil end

    local key = signature(color) .. "/" .. config.width .. "/" .. config.height
    if state.signature ~= key then
        host:SetSize(config.width, config.height)
        color = color or { 1, 1, 1, 1 }
        local ok, err = pcall(renderer.apply, host, intent, {
            colorR = color[1], colorG = color[2], colorB = color[3], colorA = color[4],
        })
        if not ok then
            pcall(renderer.clear, host)
            if ns.Debug and ns.Debug.Warn then ns.Debug:Warn("[TrackedAuras] %s glow: %s", name, tostring(err)) end
            return nil
        end
        state.renderer, state.signature = renderer, key
    end
    return host
end

local function applyPandemicStyle(button, regions, config)
    local style = config.style
    local texture = regions.pandemic
    local enabled = style.pandemic == true
    local custom = applyCustomGlow(button, regions, config, "pandemic",
        enabled and style.pandemicGlowStyle, style.pandemicColor)
    local region = enabled and (custom or texture) or nil
    if region == texture then
        local color = style.pandemicColor
        if color then
            texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
        else
            texture:SetVertexColor(1, 1, 1, 1)
        end
    end
    if region ~= regions.pandemicRegion then
        if regions.pandemicRegion then
            button:RemovePandemicRegion(regions.pandemicRegion)
            regions.pandemicRegion:Hide()
        end
        if region then button:AddPandemicRegion(region) end
        regions.pandemicRegion = region
    end

    local pulse = region == texture and style.pandemicStyle == "pulse"
    local animation = regions.pandemicPulse
    if pulse and not animation and texture.CreateAnimationGroup and button.AddPandemicActiveAnimation then
        animation = texture:CreateAnimationGroup()
        animation:SetLooping("BOUNCE")
        local alpha = animation:CreateAnimation("Alpha")
        alpha:SetFromAlpha(1)
        alpha:SetToAlpha(0.3)
        alpha:SetDuration(0.5)
        button:AddPandemicActiveAnimation(animation)
        regions.pandemicPulse = animation
    elseif not pulse and animation then
        button:RemovePandemicActiveAnimation(animation)
        animation:Stop()
        regions.pandemicPulse = nil
        texture:SetAlpha(1)
    end
end

local function applyGainFlash(button, regions, config)
    if not button.AddAuraShownAnimation then return end
    local style = config.style
    local color = style.gainColor
    local target = applyCustomGlow(button, regions, config, "proc", color and style.gainGlowStyle, color)
    if color and not target then
        if not regions.gainFlash then
            local flash = button:CreateTexture(nil, "OVERLAY", nil, 2)
            flash:SetAllPoints(button)
            flash:SetColorTexture(1, 1, 1, 1)
            flash:SetBlendMode("ADD")
            regions.gainFlash = flash
        end
        target = regions.gainFlash
        target:SetVertexColor(color[1], color[2], color[3], color[4] or 0.8)
    end
    if target == regions.gainTarget then return end
    if regions.gainTarget then
        local previous = regions.gainAnimations[regions.gainTarget]
        button:RemoveAuraShownAnimation(previous)
        previous:Stop()
        regions.gainTarget:SetAlpha(0)
    end
    regions.gainTarget = target
    if not target then return end

    target:SetAlpha(0)
    regions.gainAnimations = regions.gainAnimations or {}
    local animation = regions.gainAnimations[target]
    if not animation then
        animation = target:CreateAnimationGroup()
        local fadeIn = animation:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.12)
        fadeIn:SetOrder(1)
        local fadeOut = animation:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0)
        fadeOut:SetDuration(0.65)
        fadeOut:SetOrder(2)
        regions.gainAnimations[target] = animation
    end
    button:AddAuraShownAnimation(animation)
end

local function applyStyle(button, regions, config)
    local styleText = config.styleText
    local style = config.style
    local custom = applyCustomGlow(button, regions, config, "activeAura",
        style.activeBorder and style.activeGlowStyle, style.activeBorder)
    regions.border = applyBorder(button, regions.border, (not custom and style.activeBorder) or style.border)
    local bar = regions.bar
    if bar then
        regions.icon:ClearAllPoints()
        regions.icon:SetPoint("LEFT", button)
        regions.icon:SetSize(config.height, config.height)
        regions.icon:SetShown(style.showIcon)
        bar:ClearAllPoints()
        if style.showIcon then
            bar:SetPoint("TOPLEFT", regions.icon, "TOPRIGHT", 2, 0)
        else
            bar:SetPoint("TOPLEFT", button)
        end
        bar:SetPoint("BOTTOMRIGHT", button)
        bar:SetStatusBarTexture(style.texture)
        bar:SetStatusBarColor(unpack(style.fill))
        regions.bg:SetColorTexture(unpack(style.background))
        regions.bg:SetShown(style.showBackground)
        styleText(regions.name, bar, style.name, "LEFT")
        regions.name:SetShown(style.showName)
    else
        regions.cooldown:SetDrawSwipe(style.showSwipe)
        regions.cooldown:SetDrawEdge(style.showSwipe)
    end
    styleText(regions.timer, bar or button, style.timer, bar and "RIGHT" or "CENTER")
    styleText(regions.count, button, style.count, "BOTTOMRIGHT")
    regions.timer:SetShown(style.showTimer)
    regions.count:SetShown(style.showCount)
    applyPandemicStyle(button, regions, config)
    applyGainFlash(button, regions, config)
end

local function createContainer(parent, unit)
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    local container = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    container:SetUnit(unit)
    return container
end

local function getIconTimerOptions()
    if not iconTimerOptions and C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
       and Enum.NumericRuleFormatRounding then
        local formatter = C_StringUtil.CreateNumericRuleFormatter()
        local up = Enum.NumericRuleFormatRounding.Up
        formatter:SetBreakpoints({
            { threshold = 0, format = "%d", step = 1, rounding = up },
            { threshold = 90, format = "%dm", step = 60, rounding = up, components = { { div = 60 } } },
            { threshold = 5401, format = "%dh", step = 3600, rounding = up, components = { { div = 3600 } } },
            { threshold = 129601, format = "%dd", step = 86400, rounding = up, components = { { div = 86400 } } },
        })
        iconTimerOptions = { textFormatter = formatter }
    end
    return iconTimerOptions
end

local function bindDurationText(button, regions, style)
    local colors = style and style.timerColors
    local key = colors and signature(colors) or false
    if regions.timerColorKey == key then return end
    local options = not regions.bar and getIconTimerOptions() or nil
    if colors and CreateColor and C_CurveUtil and C_CurveUtil.CreateColorCurve
       and Enum.DurationTextBindingProperty then
        local curve = timerCurves[key]
        if not curve then
            curve = C_CurveUtil.CreateColorCurve()
            curve:SetType(Enum.LuaCurveType.Step)
            curve:AddPoint(0, CreateColor(unpack(colors.low)))
            curve:AddPoint(colors.threshold, CreateColor(unpack(colors.normal)))
            timerCurves[key] = curve
        end
        options = {
            textFormatter = options and options.textFormatter,
            textColor = { curve = curve, property = Enum.DurationTextBindingProperty.RemainingDuration },
        }
    end
    button:SetDurationText(regions.timer, options)
    regions.timerColorKey = key
end

local function bindRegions(button, regions, bindName, style)
    button:SetIcon(regions.icon)
    button:SetApplicationCount(regions.count)
    bindDurationText(button, regions, style)
    if regions.bar then
        if bindName then button:SetSpellName(regions.name) end
        button:SetDurationBar(regions.bar, { direction = Enum.StatusBarTimerDirection.RemainingTime })
    else
        button:SetDurationCooldown(regions.cooldown)
    end
end

local function groupLayout(config)
    return {
        elementWidth = config.width,
        elementHeight = config.height,
        elementSpacing = config.spacing,
    }
end

local function withStyle(config, overrides)
    if not overrides then return config end
    local styled = {}
    for key, value in pairs(config) do styled[key] = value end
    styled.style = {}
    for key, value in pairs(config.style) do styled.style[key] = value end
    for key, value in pairs(overrides) do styled.style[key] = value end
    return styled
end

local function createGroup(frame, key, unit, group)
    local config = group.config
    frame:AddAuraGroup(key, unitFilters[unit], {
        maxFrameCount = maxTrackedIcons,
        candidateFilters = { includeSpellIDs = group.ids },
        layout = groupLayout(config),
        initializeFrame = function(button)
            local current = group.config
            -- Flow layout measures and positions group entries but leaves their size untouched.
            button:SetSize(current.width, current.height)
            local regions = makeRegions(button, config.isBar)
            group.buttons[button] = regions
            applyStyle(button, regions, current)
            bindRegions(button, regions, true, current.style)
        end,
    })
end

local function syncGroups(state, unit, config)
    local definitions = { { ids = config.ids } }
    if config.overrides and next(config.overrides) then
        local base = { ids = {} }
        local byStyle, keys = {}, {}
        for id in pairs(config.ids) do
            local override = config.overrides[id]
            local definition = base
            if override then
                local key = signature(override)
                definition = byStyle[key]
                if not definition then
                    definition = { ids = {}, override = override }
                    byStyle[key] = definition
                    keys[#keys + 1] = key
                end
            end
            definition.ids[id] = true
        end
        if next(keys) then
            definitions = next(base.ids) and { base } or {}
            table.sort(keys)
            for _, key in ipairs(keys) do definitions[#definitions + 1] = byStyle[key] end
        end
    end

    local frame = state.frame
    for index, definition in ipairs(definitions) do
        local key = index == 1 and groupKey or groupKey .. index
        local styled = withStyle(config, definition.override)
        local group = state.auraGroups[index]
        local styleKey = config.styleSignature .. signature(definition.override)
        local idKey = signature(definition.ids)
        if not group then
            group = { key = key, config = styled, ids = definition.ids, buttons = {}, enabled = true }
            state.auraGroups[index] = group
            createGroup(frame, key, unit, group)
        else
            group.config, group.ids = styled, definition.ids
            if group.idKey ~= idKey then
                frame:SetAuraGroupCandidateFilters(key, { includeSpellIDs = group.ids })
            end
            if group.styleKey ~= styleKey then
                frame:SetAuraGroupLayout(key, groupLayout(styled))
                for button, regions in pairs(group.buttons) do
                    button:SetSize(config.width, config.height)
                    applyStyle(button, regions, styled)
                    bindDurationText(button, regions, styled.style)
                end
            end
            if not group.enabled then
                frame:SetAuraGroupEnabled(key, true)
                group.enabled = true
            end
        end
        group.styleKey, group.idKey = styleKey, idKey
    end
    for index = #definitions + 1, #state.auraGroups do
        local group = state.auraGroups[index]
        if group.enabled then
            frame:SetAuraGroupEnabled(group.key, false)
            group.enabled = false
        end
    end
end

local function splitGroupPoint(unit, vertical)
    if vertical then return unit == "player" and "BOTTOM" or "TOP" end
    return unit == "player" and "RIGHT" or "LEFT"
end

local function positionGroup(frame, unit, config)
    local point, x, y = config.point, 0, 0
    local relative, relativePoint = config.parent, point
    if config.splitIcons then
        point = splitGroupPoint(unit, config.vertical)
        local gap = config.spacing * 0.5
        local displacement = unit == "player" and -gap or gap
        if config.alignment then
            relative = config.alignment
            if relativePoint == "LEFT" or relativePoint == "TOP" then
                relativePoint = config.vertical and "BOTTOM" or "RIGHT"
                displacement = displacement - gap - 1
            elseif relativePoint == "RIGHT" or relativePoint == "BOTTOM" then
                relativePoint = config.vertical and "TOP" or "LEFT"
                displacement = displacement + gap + 1
            end
        end
        if config.vertical then y = -displacement else x = displacement end
    elseif config.playerBars then
        relative, relativePoint = config.playerBars, "TOPLEFT"
        y = config.spacing
    end
    frame:ClearAllPoints()
    frame:SetPoint(point, relative, relativePoint, x, y)
end

local function setLayout(frame, unit, config)
    positionGroup(frame, unit, config)
    local point = config.point
    if config.splitIcons then
        point = splitGroupPoint(unit, config.vertical)
    elseif point == "CENTER" then
        -- The native container resizes around its external center anchor.
        point = config.vertical and "TOP" or "LEFT"
    end
    local axes = AnchorUtil.FlowLayoutAxis
    local direction = AnchorUtil.FlowDirection
    frame:SetFlowLayoutAxis(config.vertical and axes.Vertical or axes.Horizontal)
    frame:SetFlowLayoutAnchorPoint(point)
    local growUp = point == "BOTTOM" or point == "BOTTOMLEFT"
    frame:SetFlowLayoutGrowthDirection(point == "RIGHT" and direction.Left or direction.Right,
        growUp and direction.Up or direction.Down)
end

local function hideIconAlignment()
    if iconAlignment then
        for _, frame in pairs(iconAlignment.measures) do frame:Hide() end
    end
end

local function syncIconAlignment(config, units, key)
    local state = iconAlignment
    if state and state.key == key then
        for _, frame in pairs(state.measures) do frame:Show() end
        return state.anchor
    end
    local restricted = TrackedAuras:IsRestricted()
    local failure = failures.alignment
    if failure and failure.signature == key and (not failure.restricted or restricted) then return nil end
    if restricted and state then
        if state and state.key then
            for _, frame in pairs(state.measures) do frame:Show() end
            return state.anchor
        end
        return nil
    end

    -- Measure each group in the opposite direction to its visible row. The
    -- midpoint between the two far edges places the junction of the visible
    -- groups. Blizzard resolves those anchors without exposing aura counts.
    local ok, err = pcall(function()
        if not state then
            state = {
                anchor = CreateFrame("Frame", nil, config.parent, "DisableUntrustedLayoutScriptsTemplate"),
                measures = {},
            }
            iconAlignment = state
        end
        local vertical = config.vertical
        local axis, direction = AnchorUtil.FlowLayoutAxis, AnchorUtil.FlowDirection
        for _, unit in ipairs({ "player", "target" }) do
            local measure = state.measures[unit]
            local filters = { includeSpellIDs = units[unit] }
            local layout = {
                elementWidth = vertical and 1 or config.width + config.spacing,
                elementHeight = vertical and config.height + config.spacing or 1,
                elementSpacing = 0,
            }
            if not measure then
                measure = createContainer(config.parent, unit)
                state.measures[unit] = measure
                measure:SetAlpha(0)
                measure:SetSize(1, 1)
                measure:AddAuraGroup(groupKey, unitFilters[unit], {
                    candidateFilters = filters,
                    maxFrameCount = maxTrackedIcons,
                    layout = layout,
                    initializeFrame = function(button)
                        button:SetMouseClickEnabled(false)
                        button:SetMouseMotionEnabled(false)
                    end,
                })
            else
                measure:SetAuraGroupCandidateFilters(groupKey, filters)
                measure:SetAuraGroupLayout(groupKey, layout)
            end
            local player = unit == "player"
            local point = splitGroupPoint(player and "target" or "player", vertical)
            measure:ClearAllPoints()
            measure:SetPoint(point, config.parent, config.point)
            measure:SetFlowLayoutAxis(vertical and axis.Vertical or axis.Horizontal)
            measure:SetFlowLayoutAnchorPoint(point)
            measure:SetFlowLayoutGrowthDirection(player and direction.Right or direction.Left,
                player and direction.Down or direction.Up)
            -- One unit of outer padding gives empty groups the same baseline.
            if vertical then
                measure:SetFlowLayoutPadding(0, 0, player and 0 or 1, player and 1 or 0)
            else
                measure:SetFlowLayoutPadding(player and 0 or 1, player and 1 or 0, 0, 0)
            end
            measure:Show()
            measure:UpdateAllAuras()
        end
        local anchor = state.anchor
        anchor:ClearAllPoints()
        anchor:SetSize(1, 1)
        local start = vertical and "TOP" or "LEFT"
        local finish = vertical and "BOTTOM" or "RIGHT"
        anchor:SetPoint(start, state.measures.target, start)
        anchor:SetPoint(finish, state.measures.player, finish)
    end)
    if not ok then
        hideIconAlignment()
        iconAlignment = nil
        failures.alignment = { signature = key, restricted = restricted }
        if ns.Debug and ns.Debug.Warn then ns.Debug:Warn("[TrackedAuras] icon alignment: %s", tostring(err)) end
        return nil
    end
    state.key = key
    failures.alignment = nil
    return state.anchor
end

function TrackedAuras:SyncCooldownDebuff(icon, ids, showText, showSwipe, textStyle, activeSpellID)
    local frame = icon.frame
    local state = cooldownDebuffs[frame]
    if not ids then
        if state then state.container:Hide() end
        return
    end
    local restricted = self:IsRestricted()
    local idSignature = signature(ids)
    if restricted and state then
        if state then
            local sameSpell = activeSpellID ~= nil and state.activeSpellID == activeSpellID
            state.container:SetShown(sameSpell or state.ids == idSignature)
        end
        return
    end
    local styleSignature = signature(textStyle) .. tostring(showText) .. tostring(showSwipe)
    local key = idSignature .. "/" .. styleSignature
    local failure = cooldownDebuffFailures[frame]
    if failure and failure.signature == key and (not failure.restricted or restricted) then return end
    if state and state.ids == idSignature and state.style == styleSignature then
        state.activeSpellID = activeSpellID
        state.container:Show()
        return
    end
    local function style(visual)
        local fs = visual.timer
        local styleOptions = textStyle or {}
        local font, size, flags = GameFontNormal:GetFont()
        if ns.Controls and ns.Controls.ResolveFontPath then
            font = ns.Controls.ResolveFontPath(styleOptions.font) or font
        end
        fs:SetFont(font, styleOptions.size or size, styleOptions.flags or flags)
        local point = styleOptions.anchor or "CENTER"
        if point == "ABOVE_ICON" then point = "TOP" elseif point == "BELOW_ICON" then point = "BOTTOM" end
        fs:ClearAllPoints()
        fs:SetPoint(point, visual.cooldown, point, styleOptions.x or 0, styleOptions.y or 0)
        fs:SetShown(showText)
        visual.cooldown:SetDrawSwipe(showSwipe)
        visual.cooldown:SetDrawEdge(showSwipe)
    end
    local ok, err = pcall(function()
        if not state then
            local container = createContainer(frame, "target")
            state = { container = container }
            cooldownDebuffs[frame] = state
            container:SetAllPoints(frame)
            local cooldown = frame.cooldown or frame
            container:SetFrameLevel(cooldown:GetFrameLevel() + 5)
            container:AddAuraSlot("debuff", unitFilters.target, {
                candidateFilters = { includeSpellIDs = ids },
                initializeFrame = function(button)
                    button:SetAllPoints(container)
                    if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
                    if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
                    local bg = button:CreateTexture(nil, "BACKGROUND")
                    bg:SetAllPoints(button)
                    bg:SetColorTexture(0.05, 0.05, 0.05, 1)
                    local visual = makeRegions(button, false)
                    state.visual = visual
                    style(visual)
                    button:SetIcon(visual.icon)
                    bindDurationText(button, visual)
                    button:SetDurationCooldown(visual.cooldown)
                end,
            })
        else
            if state.ids ~= idSignature then
                state.container:SetAuraSlotCandidateFilters("debuff", { includeSpellIDs = ids })
            end
            style(state.visual)
        end
        state.ids, state.style, state.activeSpellID = idSignature, styleSignature, activeSpellID
        state.container:Show()
    end)
    if not ok then
        if state then pcall(state.container.Hide, state.container) end
        cooldownDebuffs[frame] = nil
        cooldownDebuffFailures[frame] = { signature = key, restricted = restricted }
        if ns.Debug and ns.Debug.Warn then ns.Debug:Warn("[TrackedAuras] cooldown debuff: %s", tostring(err)) end
    else
        cooldownDebuffFailures[frame] = nil
    end
end

function TrackedAuras:ReleaseCooldownDebuff(icon)
    local frame = icon.frame
    local state = cooldownDebuffs[frame]
    cooldownDebuffs[frame], cooldownDebuffFailures[frame] = nil, nil
    if state then pcall(state.container.Hide, state.container) end
end

function TrackedAuras:SetupPlayerAuraCount(icon, auraSpellID)
    local frame = icon.frame
    if not frame.stack then return end
    local state = icon._playerAuraCount
    local restricted = self:IsRestricted()
    if restricted and state then return end
    if icon._playerAuraCountFailed == restricted then return end
    local ok, err = pcall(function()
        if not state then
            local container = createContainer(frame, "player")
            container:SetAllPoints(frame)
            container:SetFrameLevel(frame.cooldown:GetFrameLevel() + 6)
            state = { container = container }
            if not auraCountFormatter then
                local formatter = C_StringUtil.CreateNumericRuleFormatter()
                formatter:SetBreakpoints({ { threshold = 0, format = "%d", step = 1 } })
                auraCountFormatter = formatter
            end
            container:AddAuraSlot("count", unitFilters.player, {
                candidateFilters = { includeSpellIDs = { [auraSpellID] = true } },
                initializeFrame = function(button)
                    button:SetAllPoints(container)
                    local text = button:CreateFontString(nil, "OVERLAY")
                    text:SetFont(frame.stack:GetFont())
                    button:SetApplicationCount(text, { formatter = auraCountFormatter })
                    state.text = text
                end,
            })
        end
        local text = state.text
        local point, _, relativePoint, x, y = frame.stack:GetPoint(1)
        point = point or "BOTTOMRIGHT"
        text:SetFont(frame.stack:GetFont())
        text:SetJustifyH("RIGHT")
        text:ClearAllPoints()
        text:SetPoint(point, state.container, relativePoint or point, x or -1, y or 1)
    end)
    if ok then
        icon._playerAuraCount = state
        icon._playerAuraCountFailed = nil
    else
        if state then pcall(state.container.Hide, state.container) end
        icon._playerAuraCount = nil
        icon._playerAuraCountFailed = restricted
        if ns.Debug and ns.Debug.Warn then ns.Debug:Warn("[TrackedAuras] player aura count: %s", tostring(err)) end
    end
end

ns:RegisterEvent("PLAYER_TARGET_CHANGED", function()
    for _, key in ipairs({ "iconstarget", "barstarget" }) do
        local state = groups[key]
        if state and state.ready then state.frame:UpdateAllAuras() end
    end
    local target = fixedBars and fixedBars.containers.target
    if target then target:UpdateAllAuras() end
    for _, state in pairs(cooldownDebuffs) do
        if state.container:IsShown() then state.container:UpdateAllAuras() end
    end
    local measure = iconAlignment and iconAlignment.measures.target
    if measure and measure:IsShown() then measure:UpdateAllAuras() end
end)

function TrackedAuras:IsRestricted()
    return InCombatLockdown()
        or (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()) == true
end

function TrackedAuras:Sync(kind, unit, config)
    local key = kind .. unit
    local state = groups[key]
    local show = config and next(config.ids) ~= nil
    if not show then
        if state then state.frame:Hide() end
        return true
    end
    if state and state.ready and state.signature == config.signature then
        state.frame:Show()
        return true
    end
    local restricted = self:IsRestricted()
    if restricted and state and state.ready then
        if state and state.ready then state.frame:Show() end
        return state and state.ready or false
    end
    local failure = failures[key]
    if failure and failure.signature == config.signature and (not failure.restricted or restricted) then
        return false
    end

    if not state or not state.ready then
        state = { auraGroups = {} }
        groups[key] = state
    end
    state.config = config
    local ok, err = pcall(function()
        if not state.ready then
            state.frame = createContainer(config.parent, unit)
            state.frame:Hide()
            state.frame:SetSize(1, 1)
        end
        local frame = state.frame
        syncGroups(state, unit, config)
        setLayout(frame, unit, config)
        frame:Show()
        frame:UpdateAllAuras()
    end)
    if not ok then
        if state.frame then pcall(state.frame.Hide, state.frame) end
        groups[key] = nil
        failures[key] = { signature = config.signature, reason = tostring(err), restricted = restricted }
        if ns.Debug and ns.Debug.Warn then
            ns.Debug:Warn("[TrackedAuras] %s/%s: %s", kind, unit, tostring(err))
        end
        return false
    end
    state.ready = true
    state.signature = config.signature
    failures[key] = nil
    return true
end

local function hideGroups(kind)
    for key, state in pairs(groups) do
        if state.frame and (not kind or key:sub(1, #kind) == kind) then
            state.frame:Hide()
        end
    end
end

function TrackedAuras:Hide(kind)
    hideGroups(kind)
    if not kind or kind == "icons" then hideIconAlignment() end
    if fixedBars and (not kind or kind == "bars") then fixedBars.frame:Hide() end
end

local function updateFixedBar(state, index, entry, baseConfig, slotConfig)
    local config = baseConfig
    local row = state.rows[index]
    if not row then
        local frame = CreateFrame("Frame", nil, state.frame)
        row = { frame = frame, regions = makeRegions(frame, true), slots = {} }
        state.rows[index] = row
    end
    local frame, regions = row.frame, row.regions
    row.key = entry.key
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", state.frame, "BOTTOMLEFT", 0, (index - 1) * (config.height + config.spacing))
    frame:SetSize(config.width, config.height)
    frame:Show()
    applyStyle(frame, regions, config)
    regions.bar:SetMinMaxValues(0, 1)
    regions.bar:SetValue(0)
    regions.icon:SetTexture(entry.icon)
    regions.icon:SetDesaturated(true)
    slotConfig = withStyle(slotConfig, entry.styleOverrides)

    for _, unit in ipairs({ "target", "player" }) do
        local ids = entry[unit]
        local container = state.containers[unit]
        local key = tostring(index)
        local slot = row.slots[unit]
        if next(ids) then
            if not slot then
                container:AddAuraSlot(key, unitFilters[unit], {
                    candidateFilters = { includeSpellIDs = ids },
                    initializeFrame = function(button)
                        local visual = makeRegions(button, true)
                        row.slots[unit] = { button = button, regions = visual }
                        button:SetAllPoints(frame)
                        applyStyle(button, visual, slotConfig)
                        bindRegions(button, visual, false, slotConfig.style)
                    end,
                })
            else
                container:SetAuraSlotCandidateFilters(key, { includeSpellIDs = ids })
                container:SetAuraSlotEnabled(key, true)
                applyStyle(slot.button, slot.regions, slotConfig)
                bindDurationText(slot.button, slot.regions, slotConfig.style)
            end
        elseif slot then
            container:SetAuraSlotEnabled(key, false)
        end
    end
    -- The row supplies its label whether or not a native slot has an aura.
    local labelLayer = row.labelLayer
    if not labelLayer then
        labelLayer = CreateFrame("Frame", nil, frame)
        labelLayer:SetAllPoints(frame)
        labelLayer:SetFrameLevel(state.containers.player:GetFrameLevel() + 10)
        row.labelLayer = labelLayer
        row.label = labelLayer:CreateFontString(nil, "OVERLAY")
    end
    config.styleText(row.label, regions.bar, config.style.name, "LEFT")
    row.label:SetText(entry.name)
    row.label:SetAlpha(0.7)
    row.label:SetShown(slotConfig.showLabel)
end

function TrackedAuras:SyncFixedBars(config, rows, configSignature)
    if fixedBars and fixedBars.signature == configSignature then
        if not fixedBars.frame:IsShown() then
            fixedBars.frame:Show()
            if not self:IsRestricted() then
                for _, container in pairs(fixedBars.containers) do container:UpdateAllAuras() end
            end
        end
        hideGroups("bars")
        return true
    end
    local restricted = self:IsRestricted()
    if restricted and fixedBars then
        if not fixedBars.ready then return false end
        fixedBars.frame:Show()
        hideGroups("bars")
        return true
    end
    local failure = failures.fixedBars
    if failure and failure.signature == configSignature and (not failure.restricted or restricted) then
        return false
    end

    local ok, err = pcall(function()
        if not fixedBars then
            local frame = CreateFrame("Frame", nil, config.parent)
            frame:SetAllPoints(config.parent)
            fixedBars = { frame = frame, rows = {}, containers = {} }
            for i, unit in ipairs({ "target", "player" }) do
                local container = createContainer(frame, unit)
                container:SetAllPoints(frame)
                container:SetFrameLevel(frame:GetFrameLevel() + i * 3)
                fixedBars.containers[unit] = container
            end
        end
        local baseConfig, slotConfig = {}, {}
        for key, value in pairs(config) do baseConfig[key], slotConfig[key] = value, value end
        baseConfig.style, slotConfig.style = {}, {}
        for key, value in pairs(config.style) do baseConfig.style[key], slotConfig.style[key] = value, value end
        baseConfig.style.pandemic, baseConfig.style.showName, baseConfig.style.showTimer = false, false, false
        baseConfig.style.activeBorder = nil
        baseConfig.style.gainColor = nil
        slotConfig.style.showBackground, slotConfig.style.showName, slotConfig.style.border = false, false, nil
        slotConfig.showLabel = config.style.showName
        for index, entry in ipairs(rows) do updateFixedBar(fixedBars, index, entry, baseConfig, slotConfig) end
        for index = #rows + 1, #fixedBars.rows do
            local row = fixedBars.rows[index]
            row.frame:Hide()
            for unit in pairs(row.slots) do
                fixedBars.containers[unit]:SetAuraSlotEnabled(tostring(index), false)
            end
        end
        fixedBars.frame:Show()
        fixedBars.count = #rows
        for _, container in pairs(fixedBars.containers) do container:UpdateAllAuras() end
    end)
    if not ok then
        if fixedBars then fixedBars.frame:Hide() end
        fixedBars = nil
        failures.fixedBars = { signature = configSignature, reason = tostring(err), restricted = restricted }
        if ns.Debug and ns.Debug.Warn then ns.Debug:Warn("[TrackedAuras] fixed bars: %s", tostring(err)) end
        return false
    end
    fixedBars.signature = configSignature
    fixedBars.ready = true
    failures.fixedBars = nil
    hideGroups("bars")
    return true
end

function TrackedAuras:SetFixedBarOverrides(overrides)
    if not (fixedBars and fixedBars.ready and fixedBars.frame:IsShown()) then return end
    for index = 1, fixedBars.count or 0 do
        local row = fixedBars.rows[index]
        row.frame:SetShown(not overrides[row.key])
    end
end

function TrackedAuras:GetSourceStatus()
    local status = {}
    if failures.fixedBars then
        status[#status + 1] = "bars/fixed: " .. failures.fixedBars.reason
    elseif fixedBars and fixedBars.frame:IsShown() then
        status[#status + 1] = ("bars/fixed: %d rows installed"):format(fixedBars.count)
    end
    for _, kind in ipairs({ "icons", "bars" }) do
        for _, unit in ipairs({ "player", "target" }) do
            local key = kind .. unit
            local failure = failures[key]
            local state = groups[key]
            if failure then
                status[#status + 1] = kind .. "/" .. unit .. " " .. failure.reason
            elseif state and state.ready then
                local ids = {}
                for id in pairs(state.config.ids) do ids[#ids + 1] = id end
                table.sort(ids)
                status[#status + 1] = ("%s/%s: %d registered [%s]"):format(kind, unit, #ids,
                    table.concat(ids, ", ", 1, math.min(#ids, 12)))
            else
                status[#status + 1] = kind .. "/" .. unit .. ": no filter installed"
            end
        end
    end
    return status
end

function TrackedAuras:SyncDisplay(kind, config, units, rows)
    if not config then
        self:Hide(kind)
        return not (next(units.player) or next(units.target))
    end
    local styleSignature = signature(config.style) .. "/" .. config.width .. "/" .. config.height
    local splitIcons = kind == "icons" and next(units.player) ~= nil and next(units.target) ~= nil
    local layoutSignature = table.concat({
        tostring(config.parent), config.point, config.width, config.height, config.spacing,
        tostring(config.vertical), tostring(splitIcons),
    }, "/")
    if rows then
        if #rows == 0 then
            self:Hide("bars")
            if fixedBars then fixedBars.signature = nil end
            return true
        end
        return self:SyncFixedBars(config, rows, layoutSignature .. "/" .. styleSignature .. "/" .. signature(rows))
    end
    if kind == "bars" and fixedBars then fixedBars.frame:Hide() end
    local alignment
    if splitIcons then
        alignment = syncIconAlignment(config, units, layoutSignature .. "/" .. signature(units))
    elseif kind == "icons" then
        hideIconAlignment()
    end
    local ready = true
    for _, unit in ipairs({ "player", "target" }) do
        local entry = {}
        for key, value in pairs(config) do entry[key] = value end
        entry.splitIcons = splitIcons
        entry.alignment = alignment
        entry.ids = units[unit]
        entry.overrides = config.overrides and config.overrides[unit]
        entry.idSignature = signature(entry.ids)
        entry.styleSignature = styleSignature
        entry.signature = layoutSignature .. "/" .. styleSignature .. "/" .. entry.idSignature
            .. "/" .. signature(entry.overrides) .. "/" .. tostring(alignment)
        if kind == "bars" and config.vertical and unit == "target" and next(units.player) then
            local player = groups.barsplayer
            entry.playerBars = player and player.ready and player.frame or nil
            entry.signature = entry.signature .. "/" .. tostring(entry.playerBars)
        end
        if not self:Sync(kind, unit, entry) then ready = false end
    end
    if not ready then self:Hide(kind) end
    return ready
end
