local _, ns = ...

-- These identifiers denote the hostile aura itself. Linked aura IDs are
-- classified individually, since a single CDM entry can also own a player buff.
local targetDebuffIDs = {
    [164812] = true,    -- Moonfire
    [164815] = true,    -- Sunfire
    [155722] = true,    -- Rake
    [1079] = true,      -- Rip
    [703] = true,       -- Garrote
    [1943] = true,      -- Rupture
    [589] = true,       -- Shadow Word: Pain
    [34914] = true,     -- Vampiric Touch
    [980] = true,       -- Agony
    [146739] = true,    -- Corruption
    [157736] = true,    -- Immolate
    [445474] = true,    -- Wither
}

local function includesPlayer(entry, id)
    return entry.selfAura or not targetDebuffIDs[id]
end

function ns.InstallNativeAuraDisplay(Auras, runtime)
    local _auraCatalog = runtime._auraCatalog
    local _liveRenderCat = runtime._liveRenderCat
    local applyBarTextStyle = runtime.applyBarTextStyle
    local cdmCategoryFor = runtime.cdmCategoryFor
    local entryDisplayEnabled = runtime.entryDisplayEnabled
    local getTrackedBarsTextStyles = runtime.getTrackedBarsTextStyles
    local getTrackedBarsVisuals = runtime.getTrackedBarsVisuals
    local getTrackedIconCooldownTextStyle = runtime.getTrackedIconCooldownTextStyle
    local getTrackedIconTextStyle = runtime.getTrackedIconTextStyle
    local getTrackedIconVisuals = runtime.getTrackedIconVisuals
    local isSecret = runtime.isSecret
    local resolveTrackedBarsGeometry = runtime.resolveTrackedBarsGeometry
    local resolveTrackedIconSize = runtime.resolveTrackedIconSize

    function Auras:GetCooldownBuffFilter(key)
        for _, entries in pairs(_auraCatalog) do
            for _, entry in ipairs(entries) do
                if entry.stableEntryID == key then
                    local ids = {}
                    for _, id in ipairs(entry.matchSpellIDs) do ids[id] = true end
                    return next(ids) and ids or nil
                end
            end
        end
    end

    function Auras:GetCooldownBuffChoices()
        local choices, seen = {}, {}
        for _, kind in ipairs({ "TrackedIcon", "TrackedBars" }) do
            for _, entry in ipairs(self:GetConfiguredAuraList(kind)) do
                local key = entry.stableEntryID
                if key and (entry.cdmTracked or entry.displayEnabled) and not seen[key] then
                    seen[key] = true
                    choices[#choices + 1] = { key = key, label = entry.label or key }
                end
            end
        end
        table.sort(choices, function(a, b) return a.label < b.label end)
        return choices, seen
    end

    function Auras._NativeIncludeSets(kind, enabled)
        local units = { player = {}, target = {} }
        if not enabled then return units end
        for _, entry in ipairs(_auraCatalog[kind]) do
            if entryDisplayEnabled(entry) and not Auras._summonSpellForEntry(entry) then
                for _, id in ipairs(entry.matchSpellIDs) do
                    if includesPlayer(entry, id) then units.player[id] = true end
                    if not entry.selfAura then units.target[id] = true end
                end
            end
        end
        return units
    end

    function Auras:GetAuraGlowSettings(key, spellID, kind, baseSpellID)
        local profile = ns.savedVarsReady and ns:GetProfile()
        local auras = profile and profile.auras
        if type(auras) ~= "table" then return nil end
        local function settingsFor(id)
            local entry = auras[id]
            local glow = type(entry) == "table" and entry.glow
            local settings = type(glow) == "table" and glow[kind]
            if type(settings) == "table" then return settings end
        end
        local saved = settingsFor(key)
        if not saved or not (saved.mode or self:GetAuraGlowMode(saved, kind) ~= "inherit") then
            saved = settingsFor(spellID) or settingsFor(baseSpellID) or saved
        end
        if kind == "activeAura" and saved and saved.mode == "inherit" and not saved.useGroup
            and saved.style ~= "border" and ns.Glow and ns.Glow:GetStyleRenderer(saved.style) then
            -- Older choices left the mode inherited and could save full opacity as zero.
            local restored = {}
            for field, value in pairs(saved) do restored[field] = value end
            restored.mode = "on"
            local color = restored.color
            if type(color) == "table" and color[4] == 0 then
                restored.color = { color[1], color[2], color[3], 1 }
            end
            return restored
        end
        return saved
    end

    function Auras:GetAuraGlowMode(settings, kind)
        if not settings then return "inherit" end
        if settings.mode == "inherit" or settings.mode == "on" or settings.mode == "off" then
            return settings.mode
        end
        if settings.enabled == true and (settings.userSet == true or kind ~= "pandemic") then return "on" end
        if settings.enabled == false and (settings.userSet == true or kind == "pandemic") then return "off" end
        return "inherit"
    end

    function Auras:_NativeAuraStyle(entry, style)
        local override = {}
        local key, spellID, baseID = entry.stableEntryID, entry.overrideSpellID or entry.spellID, entry.spellID
        local timer = self:GetAuraGlowSettings(key, spellID, "lowTime", baseID)
        local timerMode = self:GetAuraGlowMode(timer, "lowTime")
        if timerMode == "off" then
            override.timerColors = false
        elseif timer and (timerMode == "on" or (style.timerColors and (timer.threshold or timer.color))) then
            local _, threshold, nr, ng, nb, na, lr, lg, lb, la = self:GetLowTimeTextConfig()
            override.timerColors = {
                threshold = math.max(1, math.min(60, tonumber(timer.threshold) or threshold)),
                normal = { nr, ng, nb, na },
                low = type(timer.color) == "table" and timer.color or { lr, lg, lb, la },
            }
        end
        if style.glowsEnabled == false then return next(override) and override or nil end

        local function customStyle(name)
            if ns.Glow and ns.Glow.GetStyleRenderer and ns.Glow:GetStyleRenderer(name) then return name end
        end
        local lowGlow = self:GetAuraGlowSettings(key, spellID, "lowTimeGlow", baseID)
        if self:GetAuraGlowMode(lowGlow, "lowTimeGlow") == "on" then
            override.lowTimeGlow = {
                threshold = math.max(1, math.min(60, tonumber(lowGlow.threshold) or 5)),
                color = type(lowGlow.color) == "table" and lowGlow.color or { 1, 0.45, 0.15, 1 },
                style = customStyle(lowGlow.style) or "solid",
            }
        end

        local gain = self:GetAuraGlowSettings(key, spellID, "gain", baseID)
        if self:GetAuraGlowMode(gain, "gain") == "on" then
            override.gainColor = type(gain.color) == "table" and gain.color or { 0.4, 0.8, 1, 0.8 }
            override.gainGlowStyle = customStyle(gain.style)
        end

        local pandemic = self:GetAuraGlowSettings(key, spellID, "pandemic", baseID)
        local pandemicMode = self:GetAuraGlowMode(pandemic, "pandemic")
        local filters = self:GetPandemicOpts()
        local cdID = entry.cooldownID
        if pandemicMode == "on" then
            override.pandemic = true
        elseif pandemicMode == "off" or (cdID and filters and (
            (type(filters.skip) == "table" and filters.skip[cdID])
            or (type(filters.only) == "table" and next(filters.only) and not filters.only[cdID]))) then
            override.pandemic = false
        end
        if pandemic and (pandemic.mode or pandemic.userSet) then
            if type(pandemic.color) == "table" then override.pandemicColor = pandemic.color end
            if pandemic.style == "pulse" then override.pandemicStyle = "pulse" end
            override.pandemicGlowStyle = customStyle(pandemic.style)
        end

        local active = self:GetAuraGlowSettings(key, spellID, "activeAura", baseID)
        local activeMode = self:GetAuraGlowMode(active, "activeAura")
        if activeMode == "off" then
            override.activeBorder = false
        elseif active and (activeMode == "on" or style.activeBorder) then
            if type(active.color) == "table" and (active.mode or activeMode == "on") then
                override.activeBorder = active.color
            elseif activeMode == "on" then
                override.activeBorder = { 0.4, 0.8, 1, 1 }
            end
            override.activeGlowStyle = customStyle(active.style)
        end
        return next(override) and override or nil
    end

    function Auras:GetTrackedBarSettings(key)
        local profile = ns.savedVarsReady and ns:GetProfile()
        local aura = profile and profile.auras and profile.auras[key]
        return type(aura) == "table" and aura.barDisplay or nil
    end

    function Auras:GetTrackedBarAppearance(key)
        local settings = self:GetTrackedBarSettings(key)
        return type(settings) == "table" and settings.appearance or nil
    end

    function Auras:_ShowInactiveTrackedBar(key)
        local settings = self:GetTrackedBarSettings(key)
        if settings and settings.visibility == "active" then return false end
        if settings and settings.visibility == "always" then return true end
        return self:GetBarShowInactive()
    end

    function Auras:_GetTrackedOrder(kind)
        local saved = self.profileRef and self.profileRef.trackedOrder
        local list = saved and saved[kind]
        if type(list) ~= "table" or #list == 0 then return nil, 0 end
        local ranks = {}
        for i, key in ipairs(list) do ranks[key] = i end
        return ranks, #list
    end

    function Auras:MoveTrackedEntry(kind, source, target, after)
        if not self.profileRef or InCombatLockdown() or not source or not target or source == target then return false end
        local list = self:GetConfiguredAuraList(kind)
        local order, foundSource, targetIndex = {}, false, nil
        for _, entry in ipairs(list) do
            local key = entry.stableEntryID
            if key == source then
                foundSource = true
            elseif key then
                order[#order + 1] = key
                if key == target then targetIndex = #order end
            end
        end
        if not (foundSource and targetIndex) then return false end
        table.insert(order, targetIndex + (after and 1 or 0), source)
        self.profileRef.trackedOrder = self.profileRef.trackedOrder or {}
        self.profileRef.trackedOrder[kind] = order
        self:RequestRefresh()
        return true
    end

    function Auras:_NativeDisplayOptions(kind, config, units)
        local overrides = { player = {}, target = {} }
        local order = { player = {}, target = {} }
        local ranks = (_liveRenderCat.rankByCategory or {})[cdmCategoryFor(kind)] or {}
        local custom, offset = self:_GetTrackedOrder(kind)
        local lastRank = 0
        for _, rank in pairs(ranks) do lastRank = math.max(lastRank, rank) end
        local catalog = _auraCatalog[kind]
        for index, entry in ipairs(catalog) do
            if entryDisplayEnabled(entry) then
                local style = self:_NativeAuraStyle(entry, config.style)
                local appearance = kind == "TrackedBars" and self:GetTrackedBarAppearance(entry.stableEntryID)
                if appearance then
                    style = style or {}
                    for field, value in pairs(appearance) do style[field] = value end
                end
                local rank = (custom and custom[entry.stableEntryID]) or offset + (ranks[entry.cooldownID] or lastRank + index)
                for _, id in ipairs(entry.matchSpellIDs) do
                    if includesPlayer(entry, id) and units.player[id] and (not order.player[id] or rank < order.player[id]) then
                        order.player[id], overrides.player[id] = rank, style
                    end
                    if not entry.selfAura and units.target[id] and (not order.target[id] or rank < order.target[id]) then
                        order.target[id], overrides.target[id] = rank, style
                    end
                end
            end
        end
        config.overrides, config.order = overrides, order
    end

    function Auras._NativeConfig(display, isBar)
        local anchor = ns:GetAnchor(display.anchorName)
        if not (anchor and anchor.frame) then return nil end
        local parent = anchor.frame
        local opts = display:Opts()
        local visuals = (isBar and getTrackedBarsVisuals() or getTrackedIconVisuals()) or {}
        local width, height, spacing
        local point, vertical
        local glowEnabled = not ns.Glow or not ns.Glow.IsGloballyEnabled or ns.Glow:IsGloballyEnabled()
        local style = { pandemic = glowEnabled and Auras:IsPandemicEnabled(), glowsEnabled = glowEnabled,
            tooltipMode = Auras.profileRef and Auras.profileRef.tooltipMode,
            timerDecimals = math.max(0, math.min(15, tonumber(Auras.profileRef and Auras.profileRef.timerDecimals) or 0)) }
        local colorTimers, threshold, nr, ng, nb, na, lr, lg, lb, la = Auras:GetLowTimeTextConfig()
        if colorTimers then
            style.timerColors = { threshold = threshold, normal = { nr, ng, nb, na }, low = { lr, lg, lb, la } }
        end
        if isBar then
            width, height, spacing = resolveTrackedBarsGeometry(opts.barHeight, opts.spacing)
            point, vertical = "BOTTOMLEFT", true
            style.name, style.timer = getTrackedBarsTextStyles()
            style.showName = opts.showName ~= false
            style.showTimer = opts.showTimer ~= false
            style.showIcon = opts.showIcon ~= false
            style.showCount = opts.showStackText ~= false
            style.count = { anchor = "LEFT", x = style.showIcon and height + 4 or 2, y = -4 }
            style.texture = ns.Widgets.resolveMedia("statusbar", visuals.texture, ns.Widgets.DEFAULT_STATUSBAR)
                or [[Interface\TargetingFrame\UI-StatusBar]]
            style.fill = visuals.fillColor or { 1, 1, 1, 1 }
            style.background = visuals.bgColor or { 0, 0, 0, 0.5 }
            style.showBackground = visuals.showBackground ~= false
        else
            width, height, spacing = resolveTrackedIconSize(parent:GetHeight(), opts.spacing)
            vertical = visuals.orientation == "V"
            point = opts.align == "LEFT" and "LEFT" or opts.align == "RIGHT" and "RIGHT" or "CENTER"
            if vertical then
                point = point == "LEFT" and "TOP" or point == "RIGHT" and "BOTTOM" or "CENTER"
            end
            style.showSwipe = opts.showDurationSwipe ~= false
            style.showTimer = true
            style.showCount = opts.showStackText ~= false
            style.timer = getTrackedIconCooldownTextStyle()
            style.count = getTrackedIconTextStyle()
        end
        if visuals.showBorder == true or (not isBar and visuals.showBorder ~= false) then
            style.border = visuals.borderColor or { 0, 0, 0, 1 }
        end
        local glow = opts.activeGlow
        if glowEnabled and glow and glow.enabled then
            style.activeBorder = glow.color or { glow.colorR or 1, glow.colorG or 0.85,
                glow.colorB or 0.3, glow.colorA or 0.85 }
        end
        return {
            parent = parent,
            width = width,
            height = height,
            spacing = spacing,
            point = point,
            vertical = vertical,
            isBar = isBar,
            style = style,
            styleText = applyBarTextStyle,
        }
    end

    function Auras:_SyncNativeDisplays(preview)
        local native = ns.TrackedAuras
        local showIcons = self.IconDisplay and self.IconDisplay:Enabled()
        local showBars = self.BarDisplay and self.BarDisplay:Enabled()
        local iconIDs = self._NativeIncludeSets("TrackedIcon", showIcons)
        local barIDs = self._NativeIncludeSets("TrackedBars", showBars)
        local preferIcon = self:GetCrossViewerPrefer() == "icon"
        for _, unit in ipairs({ "player", "target" }) do
            local keep, suppress = barIDs[unit], iconIDs[unit]
            if preferIcon then keep, suppress = suppress, keep end
            for id in pairs(keep) do suppress[id] = nil end
        end
        local iconConfig = showIcons and self._NativeConfig(self.IconDisplay, false)
        local barConfig = showBars and self._NativeConfig(self.BarDisplay, true)
        if iconConfig then self:_NativeDisplayOptions("TrackedIcon", iconConfig, iconIDs) end
        self._nativeIcons = native:SyncDisplay("icons", iconConfig, iconIDs)
        local fixedRows, independentRows
        if barConfig then
            local keepInactive = self:GetBarShowInactive()
            for _, entry in ipairs(_auraCatalog.TrackedBars) do
                local settings = self:GetTrackedBarSettings(entry.stableEntryID)
                if settings and settings.visibility == "always" and not settings.independent then
                    keepInactive = true
                    break
                end
            end
            if keepInactive then fixedRows = {} end
            independentRows = {}
            local ranks = (_liveRenderCat.rankByCategory or {})[cdmCategoryFor("TrackedBars")] or {}
            local order, offset = self:_GetTrackedOrder("TrackedBars")
            for _, entry in ipairs(_auraCatalog.TrackedBars) do
                local settings = self:GetTrackedBarSettings(entry.stableEntryID)
                local independent = settings and settings.independent == true
                if (fixedRows or independent) and entryDisplayEnabled(entry) then
                    local name = self._catalogDisplayName(entry) or entry.label
                    local icon = self._catalogDisplayTexture(entry)
                    local appearance = self:GetTrackedBarAppearance(entry.stableEntryID)
                    local style = self:_NativeAuraStyle(entry, barConfig.style)
                    if appearance then
                        style = style or {}
                        for field, value in pairs(appearance) do style[field] = value end
                    end
                    local row = {
                        key = entry.stableEntryID,
                        name = not isSecret(name) and name or nil,
                        icon = not isSecret(icon) and icon or nil,
                        rank = (order and order[entry.stableEntryID]) or offset + (ranks[entry.cooldownID] or math.huge),
                        appearance = appearance,
                        styleOverrides = style,
                        showInactive = self:_ShowInactiveTrackedBar(entry.stableEntryID),
                        player = {}, target = {},
                    }
                    for _, id in ipairs(entry.matchSpellIDs) do
                        if includesPlayer(entry, id) and barIDs.player[id] then row.player[id] = true end
                        if not entry.selfAura and barIDs.target[id] then row.target[id] = true end
                    end
                    if next(row.player) or next(row.target) or self._summonSpellForEntry(entry) then
                        if independent then
                            row.x, row.y = tonumber(settings.x) or 0, tonumber(settings.y) or 40
                            independentRows[#independentRows + 1] = row
                        else
                            fixedRows[#fixedRows + 1] = row
                        end
                    end
                end
            end
            if fixedRows then
                table.sort(fixedRows, function(a, b)
                    if a.rank ~= b.rank then return a.rank < b.rank end
                    return a.key < b.key
                end)
            end
            for _, row in ipairs(independentRows) do
                for _, unit in ipairs({ "player", "target" }) do
                    for id in pairs(row[unit]) do barIDs[unit][id] = nil end
                end
            end
            if not fixedRows then self:_NativeDisplayOptions("TrackedBars", barConfig, barIDs) end
        end
        self._nativeBars = native:SyncDisplay("bars", barConfig, barIDs, fixedRows)
        if self._nativeBars then
            self._nativeBars = native:SyncIndependentBars(barConfig, independentRows)
        end
        if not self._nativeBars then native:Hide("bars") end
        if preview then
            -- Prepare the native filters before combat can close Edit Mode.
            native:Hide()
            self._nativeIcons, self._nativeBars = false, false
        end
        return self._nativeIcons, self._nativeBars
    end

    function Auras:_BuildNativeSummonEntries(kind)
        local out = {}
        local totems = {}
        if GetNumTotemSlots and GetTotemInfo and GetTotemDuration then
            for slot = 1, GetNumTotemSlots() do
                local haveTotem, _, _, _, _, _, id = GetTotemInfo(slot)
                if not isSecret(haveTotem) and haveTotem and not isSecret(id) and type(id) == "number" then
                    totems[id] = slot
                end
            end
        end
        if not self._summonSpecGateOK and not next(totems) then return out end
        for _, entry in ipairs(_auraCatalog[kind]) do
            if entryDisplayEnabled(entry) then
                local duration
                for _, id in ipairs(entry.matchSpellIDs) do
                    if totems[id] then
                        duration = GetTotemDuration(totems[id])
                        break
                    end
                end
                if not duration and self._summonSpecGateOK and self._summonSpellForEntry(entry) then
                    local active, summonDuration = self._resolveSummonBarPresence(entry, true)
                    if active then duration = summonDuration end
                end
                if ns._auraPresentTruthy(duration) then
                    local item = self._makeSummonBarItem(entry, duration)
                    if kind == "TrackedBars" then
                        item._fixedBarKey = entry.stableEntryID
                        item._fixedBarIndex = ns.TrackedAuras:GetFixedBarIndex(entry.stableEntryID)
                    end
                    out[#out + 1] = item
                end
            end
        end
        return out
    end
end
