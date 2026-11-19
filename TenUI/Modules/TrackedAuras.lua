local _, ns = ...

local TrackedAuras = {}
ns.TrackedAuras = TrackedAuras

local groups = {}
local fixedBars
local failures = {}
local groupKey = "tracked"
local unitFilters = { player = "HELPFUL", target = "HARMFUL|PLAYER" }

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
    regions.pandemic:SetAllPoints(button)
    regions.pandemic:SetAtlas(isBar and "UI-CooldownManager-PandemicBorderBar" or "UI-CooldownManager-PandemicBorder")
    regions.pandemic:Hide()
    return regions
end

local function applyStyle(button, regions, config)
    local styleText = config.styleText
    local style = config.style
    regions.border = applyBorder(button, regions.border, style.border)
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
    if style.pandemic ~= regions.pandemicRegistered then
        if style.pandemic then
            button:AddPandemicRegion(regions.pandemic)
        elseif regions.pandemicRegistered then
            button:RemovePandemicRegion(regions.pandemic)
            regions.pandemic:Hide()
        end
        regions.pandemicRegistered = style.pandemic
    end
end

local function createContainer(parent, unit)
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    local container = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    container:SetUnit(unit)
    return container
end

local function bindRegions(button, regions, bindName)
    button:SetIcon(regions.icon)
    button:SetApplicationCount(regions.count)
    button:SetDurationText(regions.timer)
    if regions.bar then
        if bindName then button:SetSpellName(regions.name) end
        button:SetDurationBar(regions.bar, { direction = Enum.StatusBarTimerDirection.RemainingTime })
    else
        button:SetDurationCooldown(regions.cooldown)
    end
end

local function createGroup(state, unit, config)
    local container = createContainer(config.parent, unit)
    state.frame = container
    container:Hide()
    container:SetSize(1, 1)
    container:AddAuraGroup(groupKey, unitFilters[unit], {
        maxFrameCount = 40,
        candidateFilters = { includeSpellIDs = config.ids },
        initializeFrame = function(button)
            local current = state.config
            -- Flow layout measures and positions group entries but leaves their size untouched.
            button:SetSize(current.width, current.height)
            local regions = makeRegions(button, config.isBar)
            state.buttons[button] = regions
            applyStyle(button, regions, current)
            bindRegions(button, regions, true)
        end,
    })
end

local function setLayout(frame, unit, config)
    local point = config.point
    local x, y = 0, 0
    if unit == "target" then
        if config.vertical then x = config.width + config.spacing
        else y = config.height + config.spacing end
    end
    frame:ClearAllPoints()
    frame:SetPoint(point, config.parent, point, x, y)
    local axes = AnchorUtil.FlowLayoutAxis
    local direction = AnchorUtil.FlowDirection
    frame:SetFlowLayoutAxis(config.vertical and axes.Vertical or axes.Horizontal)
    frame:SetFlowLayoutAnchorPoint(point)
    local growUp = point == "BOTTOM" or point == "BOTTOMLEFT"
    frame:SetFlowLayoutGrowthDirection(point == "RIGHT" and direction.Left or direction.Right,
        growUp and direction.Up or direction.Down)
    frame:SetAuraGroupLayout(groupKey, {
        elementWidth = config.width,
        elementHeight = config.height,
        elementSpacing = config.spacing,
    })
end

function TrackedAuras:IsRestricted()
    return InCombatLockdown() or (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret())
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
    if self:IsRestricted() then
        if state and state.ready then state.frame:Show() end
        return state and state.ready or false
    end
    if failures[key] and failures[key].signature == config.signature then return false end

    if not state or not state.ready then
        state = { buttons = {} }
        groups[key] = state
    end
    local previous = state.config
    state.config = config
    local ok, err = pcall(function()
        if not state.ready then createGroup(state, unit, config) end
        local frame = state.frame
        setLayout(frame, unit, config)
        if state.ready then
            if config.idSignature ~= previous.idSignature then
                frame:SetAuraGroupCandidateFilters(groupKey, { includeSpellIDs = config.ids })
            end
            if config.styleSignature ~= previous.styleSignature then
                for button, regions in pairs(state.buttons) do
                    button:SetSize(config.width, config.height)
                    applyStyle(button, regions, config)
                end
            end
        end
        frame:Show()
        frame:UpdateAllAuras()
    end)
    if not ok then
        if state.frame then pcall(state.frame.Hide, state.frame) end
        groups[key] = nil
        failures[key] = { signature = config.signature, reason = tostring(err) }
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
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", state.frame, "BOTTOMLEFT", 0, (index - 1) * (config.height + config.spacing))
    frame:SetSize(config.width, config.height)
    frame:Show()
    applyStyle(frame, regions, config)
    regions.bar:SetMinMaxValues(0, 1)
    regions.bar:SetValue(0)
    regions.icon:SetTexture(entry.icon)
    regions.icon:SetDesaturated(true)

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
                        bindRegions(button, visual, false)
                    end,
                })
            else
                container:SetAuraSlotCandidateFilters(key, { includeSpellIDs = ids })
                container:SetAuraSlotEnabled(key, true)
                applyStyle(slot.button, slot.regions, slotConfig)
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
    if self:IsRestricted() then
        if fixedBars and fixedBars.ready then fixedBars.frame:Show() end
        return fixedBars and fixedBars.ready or false
    end
    if failures.fixedBars and failures.fixedBars.signature == configSignature then return false end

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
        failures.fixedBars = { signature = configSignature, reason = tostring(err) }
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
    if not (fixedBars and fixedBars.ready) then return end
    for index = 1, fixedBars.count or 0 do
        fixedBars.rows[index].frame:SetShown(not overrides[index])
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
    local layoutSignature = table.concat({
        tostring(config.parent), config.point, config.width, config.height, config.spacing,
        tostring(config.vertical),
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
    local ready = true
    for _, unit in ipairs({ "player", "target" }) do
        local entry = {}
        for key, value in pairs(config) do entry[key] = value end
        entry.ids = units[unit]
        entry.idSignature = signature(entry.ids)
        entry.styleSignature = styleSignature
        entry.signature = layoutSignature .. "/" .. styleSignature .. "/" .. entry.idSignature
        if not self:Sync(kind, unit, entry) then ready = false end
    end
    if not ready then self:Hide(kind) end
    return ready
end
