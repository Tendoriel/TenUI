local addonName, ns = ...

ns.AuraPanel = ns.AuraPanel or {}
local AuraPanel = ns.AuraPanel

local type     = type
local tostring = tostring
local tonumber = tonumber
local pcall    = pcall
local ipairs   = ipairs

local AURA_CONTAINERS = {
    { key = "TrackedIcon", label = "Tracked Icons" },
    { key = "TrackedBars", label = "Tracked Bars"  },
}

local _selectedAuraContainer = "TrackedBars"
local _currentAuraSpellID    = nil
local _currentAuraContainer  = nil
local _currentAuraCooldownID = nil

local function getAuraProfile(spellID)
    if not ns.savedVarsReady or not spellID then return {} end
    local p = ns:GetProfile()
    p.auras = p.auras or {}
    if not p.auras[spellID] then
        p.auras[spellID] = {}
    end
    return p.auras[spellID]
end

local function getActiveAuras(containerKey)
    local displayType = containerKey
    local list
    if ns.Auras and ns.Auras.GetConfiguredAuraList then
        local ok, configured = pcall(ns.Auras.GetConfiguredAuraList, ns.Auras, displayType)
        if ok and type(configured) == "table" then
            list = configured
        end
    end
    if list == nil and ns.Auras and ns.Auras.GetTrackedAuraList then
        local ok, fallback = pcall(ns.Auras.GetTrackedAuraList, ns.Auras, displayType)
        if ok and type(fallback) == "table" then
            list = fallback
        end
    end
    if type(list) ~= "table" then return {} end

    local result = {}
    for _, entry in ipairs(list) do
        result[#result + 1] = {
            cooldownID    = entry.cooldownID,
            spellID       = entry.spellID,
            stableEntryID = entry.stableEntryID,
            label         = entry.label or entry.displayName or ("aura:?"),
            source        = entry.source,
            icon          = entry.displayIcon or entry.icon,
            active        = entry.active,
            isKnown       = entry.isKnown,
            cdmTracked    = entry.cdmTracked,
        }
    end
    return result
end

local _auraListFrame = nil
local _relayoutAuraPage = nil

local function makeRowCheck(C, row, initial, onToggle)
    local Theme = C.Theme
    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(16, 16)
    local bg = C.Rect(btn, "BACKGROUND", Theme.color.input)
    bg:SetAllPoints(btn)
    local border = C.Border(btn, Theme.color.lineSoft)
    local mark = btn:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", btn, "TOPLEFT", 4, -4)
    mark:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -4, 4)
    mark:SetColorTexture(unpack(Theme.color.violet))
    local checked = initial and true or false
    mark:SetShown(checked)
    function btn.GetChecked(self) return checked end
    function btn.SetChecked(self, v)
        checked = v and true or false
        mark:SetShown(checked)
    end
    btn:SetScript("OnClick", function(self)
        checked = not checked
        mark:SetShown(checked)
        local fn = self._onToggle or onToggle
        if type(fn) == "function" then pcall(fn, self) end
    end)
    btn:SetScript("OnEnter", function() border.SetColor(unpack(Theme.color.line)) end)
    btn:SetScript("OnLeave", function() border.SetColor(unpack(Theme.color.lineSoft)) end)
    return btn
end

local function rebuildAuraList()
    if not (_auraListFrame and ns.UI) then return end
    local C = ns.UI
    local Theme = C.Theme
    C.ClearChildren(_auraListFrame)

    local auras = getActiveAuras(_selectedAuraContainer)
    if #auras == 0 then
        local note = C.Text(_auraListFrame, C.Fonts.small, Theme.color.textDim,
            "No auras in this category. Check the tracked lists in Blizzard Cooldown Manager.")
        note:SetPoint("TOPLEFT", _auraListFrame, "TOPLEFT", 8, -8)
        _auraListFrame:SetHeight(32)
        return
    end

    local ROW_H  = 24
    local ICON_W = 20
    local totalH = 0
    for idx, aura in ipairs(auras) do
        local row = CreateFrame("Frame", nil, _auraListFrame)
        row:SetPoint("TOPLEFT",  _auraListFrame, "TOPLEFT",  0, -totalH)
        row:SetPoint("TOPRIGHT", _auraListFrame, "TOPRIGHT", -4, -totalH)
        row:SetHeight(ROW_H)
        local baseAlpha = (idx % 2 == 0) and 0.05 or 0.02
        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetAllPoints(row)
        rowBg:SetColorTexture(1, 1, 1, baseAlpha)

        local capturedSpellID = aura.spellID
        local capturedKey     = aura.stableEntryID or aura.spellID
        local function getEnabled()
            if not (ns.savedVarsReady and capturedKey) then return true end
            local p = ns:GetProfile()
            p.auras = p.auras or {}
            local rec = p.auras[capturedKey]
            if type(rec) == "table" and rec.enabled ~= nil then
                return rec.enabled ~= false
            end
            if capturedSpellID and capturedSpellID ~= capturedKey then
                local legacy = p.auras[capturedSpellID]
                if type(legacy) == "table" and legacy.enabled ~= nil then
                    return legacy.enabled ~= false
                end
            end
            return true
        end
        local cbFrame = makeRowCheck(C, row, getEnabled())
        cbFrame:SetPoint("LEFT", row, "LEFT", 2, 0)

        local iconTex = row:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(ICON_W, ICON_W)
        iconTex:SetPoint("LEFT", cbFrame, "RIGHT", 4, 0)
        if aura.icon then
            iconTex:SetTexture(aura.icon)
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            iconTex:SetColorTexture(0.18, 0.20, 0.28, 1)
        end

        local nameLabel = C.Text(row, C.Fonts.value, Theme.color.text, tostring(aura.label))
        nameLabel:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
        nameLabel:SetPoint("RIGHT", row, "RIGHT", -80, 0)
        nameLabel:SetJustifyH("LEFT")

        local stateLabel = C.Text(row, C.Fonts.small, Theme.color.textDim)
        stateLabel:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        stateLabel:SetJustifyH("RIGHT")

        local cdmMarker = C.Text(row, C.Fonts.small, Theme.color.textDim)
        cdmMarker:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        cdmMarker:SetJustifyH("RIGHT")
        cdmMarker:Hide()

        local cdmBtn = C.CreateCompactButton(row, "CDM", function()
            if ns.Auras and ns.Auras.OpenBlizzardCDMSettings then
                local ok, reason = ns.Auras:OpenBlizzardCDMSettings()
                if not ok and reason == "combat" then
                    UIErrorsFrame:AddMessage(
                        "TenUI: can't open Cooldown Manager in combat.",
                        1, 0.4, 0.4)
                elseif not ok then
                    UIErrorsFrame:AddMessage(
                        "TenUI: Cooldown Manager unavailable.",
                        1, 0.4, 0.4)
                end
            end
        end, 40)
        cdmBtn:SetHeight(18)
        cdmBtn:SetPoint("RIGHT", cdmMarker, "LEFT", -4, 0)
        cdmBtn:Hide()
        cdmBtn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Open Blizzard Cooldown Manager")
            GameTooltip:AddLine("Configure this aura in Blizzard's tracked lists.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        cdmBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

        local function refreshStateLabel()
            local displayOn = getEnabled()
            local notPinned = displayOn and (aura.cdmTracked == false)
            if notPinned then
                cdmMarker:SetText("|cffe6a23cNot pinned|r")
                cdmMarker:Show()
                cdmBtn:Show()
                stateLabel:Hide()
            else
                cdmMarker:Hide()
                cdmBtn:Hide()
                stateLabel:Show()
                if displayOn then
                    stateLabel:SetText("|cff5fcf5fenabled|r")
                else
                    stateLabel:SetText("|cffb05555hidden|r")
                end
            end
        end
        refreshStateLabel()

        cbFrame._onToggle = function(self)
            if not (ns.savedVarsReady and capturedKey) then
                self:SetChecked(true)
                return
            end
            local ap = getAuraProfile(capturedKey)
            ap.enabled = self:GetChecked() and true or false
            refreshStateLabel()
            if ns.Auras and ns.Auras.OnAuraEnabledChanged then
                pcall(ns.Auras.OnAuraEnabledChanged, ns.Auras, capturedKey, ap.enabled)
            end
        end

        local hintLabel = C.Text(row, C.Fonts.small, Theme.color.textFaint, "right-click settings")
        hintLabel:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        hintLabel:Hide()

        row:EnableMouse(true)
        row:SetScript("OnMouseDown", function(self, btn)
            if btn == "RightButton" then
                AuraPanel:OpenForAura(capturedSpellID, _selectedAuraContainer,
                    aura.cooldownID)
            end
        end)
        row:SetScript("OnEnter", function()
            rowBg:SetColorTexture(unpack(Theme.color.selected))
            stateLabel:Hide()
            cdmMarker:Hide()
            hintLabel:Show()
        end)
        row:SetScript("OnLeave", function()
            rowBg:SetColorTexture(1, 1, 1, baseAlpha)
            hintLabel:Hide()
            refreshStateLabel()
        end)

        totalH = totalH + ROW_H + 2
    end
    _auraListFrame:SetHeight(math.max(totalH, 30))
    if _relayoutAuraPage then _relayoutAuraPage() end
end

ns:RegisterMessage("AURA_LIST_UPDATED", function()
    if _auraListFrame and _auraListFrame.IsVisible and _auraListFrame:IsVisible() then
        rebuildAuraList()
    end
end)

local function buildAuraPage(sc)
    local C = ns.UI
    if not C then return end
    local Theme = C.Theme
    local children = {}

    if ns.Auras and ns.Auras._invalidateLiveRenderCategoryMap then
        pcall(ns.Auras._invalidateLiveRenderCategoryMap, ns.Auras)
    end

    do
        local ui = ns.GetUIState and ns:GetUIState()
        local savedContainer = ui and ui.lastOptionsSub.auras
        if not savedContainer and ns.savedVarsReady then
            local p = ns:GetProfile()
            if p.modules and p.modules.Options then
                savedContainer = p.modules.Options.selectedAuraContainer
            end
        end
        if savedContainer then
            for _, cont in ipairs(AURA_CONTAINERS) do
                if cont.key == savedContainer then
                    _selectedAuraContainer = savedContainer
                    break
                end
            end
        end
    end

    children[#children + 1] = C.CreateSection(sc, "Blizzard CDM Tracked Auras")

    local depNote = C.CreateHelpText and C.CreateHelpText(sc,
        "TenUI uses Blizzard aura containers to display enabled buffs and your target debuffs.")
    if depNote then children[#children + 1] = depNote end

    local tabRow = CreateFrame("Frame", nil, sc)
    tabRow:SetHeight(28)
    children[#children + 1] = tabRow

    local tabBtns = {}
    local prevTab
    for i, cont in ipairs(AURA_CONTAINERS) do
        local capturedKey = cont.key
        local tb
        tb = C.CreateTabButton(tabRow, cont.label, function()
            for _, b in pairs(tabBtns) do
                b:SetSelected(false)
            end
            tb:SetSelected(true)
            _selectedAuraContainer = capturedKey
            rebuildAuraList()
            if ns.savedVarsReady then
                local p = ns:GetProfile()
                p.modules = p.modules or {}
                p.modules.Options = p.modules.Options or {}
                p.modules.Options.selectedAuraContainer = capturedKey
            end
            local ui = ns.GetUIState and ns:GetUIState()
            if ui then
                ui.lastOptionsSub.auras = capturedKey
            end
        end)
        if prevTab then
            tb:SetPoint("LEFT", prevTab, "RIGHT", 4, 0)
        else
            tb:SetPoint("LEFT", tabRow, "LEFT", 0, 0)
        end
        prevTab = tb
        tb:SetSelected(cont.key == _selectedAuraContainer)
        tabBtns[cont.key] = tb
    end

    children[#children + 1] = C.CreateButton(sc, "Refresh Aura List", function()
        if ns.Auras and ns.Auras.RefreshTrackedAuraCatalog then
            pcall(ns.Auras.RefreshTrackedAuraCatalog, ns.Auras)
        elseif ns.Auras and ns.Auras.ScanBlizzardCDMAuras then
            pcall(ns.Auras.ScanBlizzardCDMAuras, ns.Auras)
        end
        rebuildAuraList()
    end)

    children[#children + 1] = C.CreateHelpText(sc,
        "If the same aura is in both Tracked Icons and Tracked Bars, only one shows it. Choose which.")

    children[#children + 1] = C.CreateDropdownLikeList(sc, "Duplicate aura shown in",
        {
            { key = "bar",  label = "Bars only (default)" },
            { key = "icon", label = "Icons only" },
        },
        function()
            if ns.Auras and ns.Auras.GetCrossViewerPrefer then
                return ns.Auras:GetCrossViewerPrefer()
            end
            return "bar"
        end,
        function(v)
            if ns.Auras and ns.Auras.SetCrossViewerPrefer then
                ns.Auras:SetCrossViewerPrefer(v)
            end
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc,
        "Hide auras disabled in Blizzard Cooldown Manager",
        function()
            if ns.Auras and ns.Auras.GetRespectCDMHidden then
                return ns.Auras:GetRespectCDMHidden()
            end
            return false
        end,
        function(v)
            if ns.Auras and ns.Auras.SetRespectCDMHidden then
                ns.Auras:SetRespectCDMHidden(v)
            end
            rebuildAuraList()
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc,
        "Show Duration Swipe (Tracked Icons)",
        function()
            if ns.Auras and ns.Auras.GetIconDurationSwipe then
                return ns.Auras:GetIconDurationSwipe()
            end
            return true
        end,
        function(v)
            if ns.Auras and ns.Auras.SetIconDurationSwipe then
                ns.Auras:SetIconDurationSwipe(v)
            end
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc,
        "Show Icon on Tracked Bars",
        function()
            if ns.Auras and ns.Auras.GetBarShowIcon then
                return ns.Auras:GetBarShowIcon()
            end
            return true
        end,
        function(v)
            if ns.Auras and ns.Auras.SetBarShowIcon then
                ns.Auras:SetBarShowIcon(v)
            end
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc,
        "Keep inactive bars visible",
        function()
            if ns.Auras and ns.Auras.GetBarShowInactive then
                return ns.Auras:GetBarShowInactive()
            end
            return false
        end,
        function(v)
            if ns.Auras and ns.Auras.SetBarShowInactive then
                ns.Auras:SetBarShowInactive(v)
            end
        end
    )

    children[#children + 1] = C.CreateDropdownLikeList(sc, "Tracked aura tooltips", {
        { key = "always", label = "Always" },
        { key = "outOfCombat", label = "Out of combat" },
        { key = "off", label = "Off" },
    }, function()
        local profile = ns.Auras and ns.Auras.profileRef
        return profile and profile.tooltipMode or "always"
    end, function(value)
        local auras = ns.Auras
        if auras and auras.profileRef then
            auras.profileRef.tooltipMode = value ~= "always" and value or nil
            auras:RequestRefresh()
        end
    end)

    children[#children + 1] = C.CreateCheckBox(sc, "Show Blizzard's Pandemic warning",
        function() return ns.Auras and ns.Auras:IsPandemicEnabled() or false end,
        function(v) if ns.Auras then ns.Auras:SetPandemicEnabled(v) end end
    )

    for _, display in ipairs({ { key = "icon", label = "Tracked Icons" }, { key = "bar", label = "Tracked Bars" } }) do
        local kind = display.key
        children[#children + 1] = C.CreateCheckBox(sc, "Show stacks (" .. display.label .. ")",
            function()
                local profile = ns.Auras and ns.Auras.profileRef
                local options = profile and profile[kind .. "s"]
                return not (options and options.showStackText == false)
            end,
            function(v)
                local auras = ns.Auras
                if auras and auras.profileRef then
                    auras.profileRef[kind .. "s"].showStackText = v
                    auras:RequestRefresh()
                end
            end
        )
        children[#children + 1] = C.CreateCheckBox(sc, "Active aura highlight (" .. display.label .. ")",
            function() return ns.Auras and ns.Auras:IsActiveGlowEnabled(kind) end,
            function(v) if ns.Auras then ns.Auras:SetActiveGlowEnabled(v, kind) end end
        )
    end

    children[#children + 1] = C.CreateSubSection(sc, "Timer Colors")
    children[#children + 1] = C.CreateCheckBox(sc, "Color expiring aura timers",
        function() return ns.Auras and ns.Auras:GetLowTimeTextEnabled() end,
        function(v) if ns.Auras then ns.Auras:SetLowTimeTextEnabled(v) end end
    )
    children[#children + 1] = C.CreateSlider(sc, "Low time (seconds)", 1, 60, 1,
        function()
            if not ns.Auras then return 5 end
            local _, threshold = ns.Auras:GetLowTimeTextConfig()
            return threshold
        end,
        function(v) if ns.Auras then ns.Auras:SetLowTimeTextThreshold(v) end end
    )
    children[#children + 1] = C.CreateColorSwatch(sc, "Low-time color",
        function()
            if not ns.Auras then return 1, 0.15, 0.1, 1 end
            return select(7, ns.Auras:GetLowTimeTextConfig())
        end,
        function(r, g, b)
            if ns.Auras then ns.Auras:SetLowTimeTextLowRGB(r, g, b) end
        end
    )

    children[#children + 1] = C.CreateSubSection(sc, "Tracked Auras")

    local auraContainer = CreateFrame("Frame", nil, sc)
    auraContainer:SetHeight(80)
    _auraListFrame = auraContainer
    children[#children + 1] = auraContainer

    _relayoutAuraPage = function()
        local h = C.LayoutVertical(sc, children, 4, -8)
        sc:SetHeight(math.max(h, 10))
    end

    _relayoutAuraPage()

    rebuildAuraList()
end

local function buildAuraSettingsPage(sc)
    local C = ns.UI
    if not C then return end
    local children = {}

    local spellID   = _currentAuraSpellID
    local spellName = "No aura selected"
    if spellID and C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, spellID)
        if ok and n then spellName = n .. " (" .. tostring(spellID) .. ")" end
    end

    children[#children + 1] = C.CreateSection(sc, "Aura Settings: " .. spellName)

    if not spellID then
        children[#children + 1] = C.CreateHelpText(sc,
            "Right-click an aura in the Auras page to open its settings.")
        C.LayoutVertical(sc, children, 4, -8)
        sc:SetHeight(60)
        return
    end

    local key = _currentAuraCooldownID and ("cdm:" .. _currentAuraCooldownID) or spellID
    local category = _currentAuraContainer == "TrackedBars" and "Tracked Bars" or "Tracked Icons"
    children[#children + 1] = C.CreateCheckBox(sc, "Show in " .. category,
        function()
            local profile = ns.savedVarsReady and ns:GetProfile()
            local auras = profile and profile.auras
            local aura = auras and (auras[key] or auras[spellID])
            return not (aura and aura.enabled == false)
        end,
        function(v)
            getAuraProfile(key).enabled = v
            if ns.Auras then ns.Auras:OnAuraEnabledChanged(key, v) end
        end
    )
    children[#children + 1] = C.CreateHelpText(sc,
        "Move the aura between Tracked Icons and Tracked Bars in Blizzard Cooldown Manager. Adjust the selected group's appearance in Layout.")
    children[#children + 1] = C.CreateButton(sc, "Open Blizzard Cooldown Manager", function()
        if ns.Auras then ns.Auras:OpenBlizzardCDMSettings() end
    end)

    local function getGlow(kind)
        return ns.Auras and ns.Auras:GetAuraGlowSettings(key, spellID, kind)
    end

    local gainToggle
    local activeModeControl
    local function setGlow(kind, setting, value)
        if not ns.Auras then return end
        local existing = getGlow(kind)
        local aura = getAuraProfile(key)
        local allGlows, glow = {}, {}
        if type(aura.glow) == "table" then ns._deepCopyMissing(allGlows, aura.glow) end
        if existing then ns._deepCopyMissing(glow, existing) end
        glow.mode = ns.Auras:GetAuraGlowMode(glow, kind)
        if setting == "style" and glow.mode == "inherit"
            and (kind == "gain" or (kind == "activeAura" and ns.Glow:GetStyleRenderer(value))) then
            glow.mode = "on"
        end
        glow[setting] = value
        if kind == "activeAura" then glow.useGroup = glow.mode == "inherit" or nil end
        allGlows[kind] = glow
        aura.glow = allGlows
        ns.Auras:RequestRefresh()
        if gainToggle and kind == "gain" then gainToggle.Refresh() end
        if activeModeControl and kind == "activeAura" then activeModeControl.Refresh() end
    end

    local glowModes = {
        { key = "inherit", label = "Use Auras setting" },
        { key = "on", label = "Always enabled" },
        { key = "off", label = "Off" },
    }
    local function addGlowMode(label, kind)
        local control = C.CreateDropdownLikeList(sc, label, glowModes,
            function() return ns.Auras and ns.Auras:GetAuraGlowMode(getGlow(kind), kind) or "inherit" end,
            function(v) setGlow(kind, "mode", v) end
        )
        children[#children + 1] = control
        return control
    end
    local function addGlowStyle(label, kind, choices)
        local default = choices[1].key
        for _, choice in ipairs(ns.Glow:GetStyleChoices(nil, kind ~= "gain")) do
            choices[#choices + 1] = choice
        end
        children[#children + 1] = C.CreateDropdownLikeList(sc, label, choices,
            function()
                local glow = getGlow(kind)
                local style = glow and glow.style
                for _, choice in ipairs(choices) do
                    if choice.key == style then return style end
                end
                return default
            end,
            function(v) setGlow(kind, "style", v) end
        )
    end
    local glowColors = {}
    local function addGlowColor(label, kind, default)
        glowColors[kind] = function()
            local glow = getGlow(kind)
            local color = glow and type(glow.color) == "table" and glow.color
                or (type(default) == "function" and default() or default)
            return unpack(color)
        end
        children[#children + 1] = C.CreateColorSwatch(sc, label, glowColors[kind],
            function(r, g, b, a) setGlow(kind, "color", { r, g, b, a }) end
        )
    end

    children[#children + 1] = C.CreateSection(sc, "Glow Effects")
    children[#children + 1] = C.CreateSubSection(sc, "Pandemic")
    addGlowMode("Pandemic warning", "pandemic")
    addGlowStyle("Pandemic glow style", "pandemic", {
        { key = "static", label = "Blizzard (static)" }, { key = "pulse", label = "Blizzard (pulse)" },
    })
    addGlowColor("Pandemic color", "pandemic", { 1, 1, 1, 1 })
    children[#children + 1] = C.CreateHelpText(sc,
        "The warning follows Blizzard's refresh window for this aura.")

    children[#children + 1] = C.CreateSubSection(sc, "Active Aura")
    activeModeControl = addGlowMode("Active aura highlight", "activeAura")
    addGlowStyle("Active aura glow style", "activeAura", { { key = "default", label = "Default outline" } })
    addGlowColor("Active aura highlight color", "activeAura", { 0.4, 0.8, 1, 1 })
    children[#children + 1] = C.CreateSubSection(sc, "Aura Proc")
    gainToggle = C.CreateCheckBox(sc, "Glow when aura appears",
        function() return ns.Auras and ns.Auras:GetAuraGlowMode(getGlow("gain"), "gain") == "on" end,
        function(v) setGlow("gain", "mode", v and "on" or "off") end
    )
    children[#children + 1] = gainToggle
    addGlowStyle("Proc glow style", "gain", { { key = "flash", label = "Flash (default)" } })
    addGlowColor("Proc glow color", "gain", { 0.4, 0.8, 1, 0.8 })

    local preview = CreateFrame("Frame", nil, sc)
    preview:SetHeight(54)
    C.SkinPanel(preview)
    children[#children + 1] = preview

    local icon = CreateFrame("Frame", nil, preview)
    icon:SetSize(30, 30)
    icon:SetPoint("LEFT", preview, "LEFT", 10, 0)
    local texture = icon:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(icon)
    texture:SetTexture(C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID) or 134400)
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    preview:HookScript("OnHide", function() ns.Glow:ClearAll(icon) end)

    local message = C.Text(preview, C.Fonts.small, C.Theme.color.textDim, "Preview the selected custom glow")
    message:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, 3)
    local previous
    for _, effect in ipairs({
        { kind = "pandemic", label = "Pandemic" },
        { kind = "activeAura", label = "Active" },
        { kind = "gain", label = "Proc" },
    }) do
        local button = C.CreateCompactButton(preview, effect.label, function()
            local glow = ns.Glow
            glow:ClearAll(icon)
            local settings = getGlow(effect.kind)
            local style = settings and settings.style
            if not glow:GetStyleRenderer(style) then
                message:SetText("Select a custom glow style to preview it")
                return
            end
            if not glow:IsGloballyEnabled() then
                message:SetText("Enable Glow Effects to preview this style")
                return
            end
            local r, g, b, a = glowColors[effect.kind]()
            local intent = effect.kind == "gain" and "proc" or effect.kind
            message:SetText(glow:GetStyleLabel(style))
            glow:Preview(icon, intent, {
                style = style, colorR = r, colorG = g, colorB = b, colorA = a,
                previewAura = true,
            }, intent == "proc" and 0.77 or 2)
        end, 68)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("TOPLEFT", message, "BOTTOMLEFT", 0, -2)
        end
        previous = button
    end

    children[#children + 1] = C.CreateSubSection(sc, "Low Time")
    addGlowMode("Color expiring aura timer", "lowTime")
    children[#children + 1] = C.CreateSlider(sc, "Timer color threshold (seconds)", 1, 60, 1,
        function()
            local glow = getGlow("lowTime")
            local _, threshold = ns.Auras:GetLowTimeTextConfig()
            return glow and tonumber(glow.threshold) or threshold
        end,
        function(v) setGlow("lowTime", "threshold", v) end
    )
    addGlowColor("Low-time color", "lowTime", function()
        return { select(7, ns.Auras:GetLowTimeTextConfig()) }
    end)

    local totalH = C.LayoutVertical(sc, children, 4, -8)
    sc:SetHeight(math.max(totalH, 10))
end

function AuraPanel:OpenForAura(spellID, containerKey, cooldownID)
    _currentAuraSpellID = spellID
    _currentAuraContainer = containerKey
    _currentAuraCooldownID = tonumber(cooldownID)
    if ns.Options then
        ns.Options:Open()
        ns.Options:SelectPage("aura_settings", true)
    end
end

ns.Options:RegisterPage({
    key   = "auras",
    label = "Auras",
    build = buildAuraPage,
})

ns.Options:RegisterPage({
    key   = "aura_settings",
    label = "Aura Settings",
    build = buildAuraSettingsPage,
})
