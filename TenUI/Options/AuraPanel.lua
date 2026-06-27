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

local function auraSupportsPandemic(cooldownID)
    if type(cooldownID) ~= "number" then return nil end
    if not (C_CooldownViewer and C_CooldownViewer.GetValidAlertTypes) then
        return nil
    end
    local pandemicType = Enum and Enum.CooldownViewerAlertEventType
        and Enum.CooldownViewerAlertEventType.PandemicTime
    if type(pandemicType) ~= "number" then return nil end
    local ok, types = pcall(C_CooldownViewer.GetValidAlertTypes, cooldownID)
    if not ok or type(types) ~= "table" then return nil end
    for _, t in ipairs(types) do
        if type(t) == "number" and t == pandemicType then return true end
    end
    return false
end

local function requestAurasRefresh()
    if ns.Auras and ns.Auras.RequestRefresh then
        pcall(ns.Auras.RequestRefresh, ns.Auras)
    end
end

local function getAuraProfile(spellID)
    if not ns.savedVarsReady or not spellID then return {} end
    local p = ns:GetProfile()
    p.auras = p.auras or {}
    if not p.auras[spellID] then
        p.auras[spellID] = {}
        if p.aurasDefaults and ns._deepCopyMissing then
            ns._deepCopyMissing(p.auras[spellID], p.aurasDefaults)
        end
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

local function getAuraDiagnostics()
    if ns.Auras and ns.Auras.GetTrackedAuraDiagnostics then
        local ok, lines = pcall(ns.Auras.GetTrackedAuraDiagnostics, ns.Auras, _selectedAuraContainer)
        if ok and type(lines) == "table" then return lines end
    end
    local lines = {}
    if not ns.Auras then
        lines[#lines + 1] = "ns.Auras: nil (module not loaded)"
        return lines
    end
    lines[#lines + 1] = "Auras module: " .. (ns.Auras._enabled and "enabled" or "disabled")
    lines[#lines + 1] = "BuffIconCooldownViewer: " .. (_G["BuffIconCooldownViewer"] and "found" or "nil")
    lines[#lines + 1] = "BuffBarCooldownViewer: "  .. (_G["BuffBarCooldownViewer"]  and "found" or "nil")
    return lines
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
        local diagLines = getAuraDiagnostics()
        local y = -8
        local ROW_D = 16
        for _, line in ipairs(diagLines) do
            local lbl = C.Text(_auraListFrame, C.Fonts.small, Theme.color.textDim, line)
            lbl:SetPoint("TOPLEFT", _auraListFrame, "TOPLEFT", 8, y)
            y = y - ROW_D
        end
        local note = C.Text(_auraListFrame, C.Fonts.small, Theme.color.textDim,
            "No tracked auras in this category. Add auras to Blizzard's Cooldown Manager, then click Refresh Aura List.")
        note:SetPoint("TOPLEFT", _auraListFrame, "TOPLEFT", 8, y - 4)
        _auraListFrame:SetHeight(math.abs(y) + 24)
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
            GameTooltip:AddLine(
                "This aura is enabled here but not tracked in Blizzard's",
                0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(
                "Cooldown Manager, so it only shows out of combat.",
                0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(
                "Move it into a Tracked list there to show it in combat.",
                0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        cdmBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

        local function refreshStateLabel()
            local displayOn = getEnabled()
            local liveOn = (aura.active == true)
            local liveTxt = liveOn and "active" or "idle"
            local oocOnly = displayOn and (aura.cdmTracked == false)
            if oocOnly then
                cdmMarker:SetText("|cffe6a23cOOC only|r")
                cdmMarker:Show()
                cdmBtn:Show()
                stateLabel:Hide()
            else
                cdmMarker:Hide()
                cdmBtn:Hide()
                stateLabel:Show()
                if displayOn then
                    stateLabel:SetText("|cff5fcf5fshown|r |cff6a6a78·|r |cff8a8a98"
                        .. liveTxt .. "|r")
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
        "Rows marked |cffe6a23cOOC only|r only show out of combat because Blizzard's Cooldown Manager does not track them. Click |cffe6a23cCDM|r on the row to fix that there.")
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
        "Force Blizzard Cooldown Manager populated (in-combat target debuffs)",
        function()
            if ns.Auras and ns.Auras.GetForceViewerPopulated then
                return ns.Auras:GetForceViewerPopulated()
            end
            return false
        end,
        function(v)
            if ns.Auras and ns.Auras.SetForceViewerPopulated then
                ns.Auras:SetForceViewerPopulated(v)
            end
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc,
        "Respect Blizzard CDM hidden/disabled cooldowns",
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
        "Show Inactive Tracked Bars (dimmed spell-name rows)",
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

    children[#children + 1] = C.CreateCheckBox(sc,
        "Color timer numbers + bar fill when low on time",
        function()
            if ns.Auras and ns.Auras.GetLowTimeTextEnabled then
                return ns.Auras:GetLowTimeTextEnabled()
            end
            return false
        end,
        function(v)
            if ns.Auras and ns.Auras.SetLowTimeTextEnabled then
                ns.Auras:SetLowTimeTextEnabled(v)
            end
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Low-Time Threshold (sec)", 1, 60, 1,
        function()
            if ns.Auras and ns.Auras.GetLowTimeTextConfig then
                local _, thr = ns.Auras:GetLowTimeTextConfig()
                return thr
            end
            return 5
        end,
        function(v)
            if ns.Auras and ns.Auras.SetLowTimeTextThreshold then
                ns.Auras:SetLowTimeTextThreshold(v)
            end
        end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Low-Time Color (timer numbers)",
        function()
            if ns.Auras and ns.Auras.GetLowTimeTextConfig then
                local _, _, _, _, _, _, lr, lg, lb = ns.Auras:GetLowTimeTextConfig()
                return lr, lg, lb, 1
            end
            return 1, 0.15, 0.10, 1
        end,
        function(r, g, b)
            if ns.Auras and ns.Auras.SetLowTimeTextLowRGB then
                ns.Auras:SetLowTimeTextLowRGB(r, g, b)
            end
        end
    )

    children[#children + 1] = C.CreateSubSection(sc, "Tracked Auras (check = show, right-click = settings)")

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
    local Theme = C.Theme
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

    local previewRow = CreateFrame("Frame", nil, sc)
    previewRow:SetHeight(60)
    C.SkinPanel(previewRow)
    children[#children + 1] = previewRow

    local previewHolder = CreateFrame("Frame", nil, previewRow)
    previewHolder:SetSize(40, 40)
    previewHolder:SetPoint("LEFT", previewRow, "LEFT", 10, 0)

    local previewTex
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, spellID)
        if ok then previewTex = t end
    end
    if ns.Widgets and ns.Widgets.Icon then
        pcall(ns.Widgets.Icon.New, ns.Widgets.Icon, previewHolder,
            { texture = previewTex, cooldown = false, stackText = false })
    end

    local previewDurText = previewHolder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    previewDurText:SetTextColor(1, 1, 1, 1)

    local previewStackText = previewHolder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    previewStackText:SetTextColor(1, 1, 1, 1)
    previewStackText:SetPoint("BOTTOMRIGHT", previewHolder, "BOTTOMRIGHT", -1, 1)
    previewStackText:SetJustifyH("RIGHT")

    local previewHint = C.Text(previewRow, C.Fonts.small, Theme.color.textDim,
        "Live sample: updates as you change settings.")
    previewHint:SetPoint("LEFT", previewHolder, "RIGHT", 12, 0)

    local function restylePreviewImpl()
        local ap = getAuraProfile(spellID)

        local dt = (ap.text and ap.text.duration) or {}
        local fontPath = (C.ResolveFontPath and C.ResolveFontPath(dt.font))
            or "Fonts\\FRIZQT__.TTF"
        local fontSize = tonumber(dt.size) or 12
        if fontSize < 6 then fontSize = 6 elseif fontSize > 64 then fontSize = 64 end
        pcall(previewDurText.SetFont, previewDurText, fontPath, fontSize, "OUTLINE")

        if dt.enabled == false then
            previewDurText:SetText("")
        else
            previewDurText:SetText("12")
        end
        local anchor = dt.anchor or "BOTTOM"
        local x = dt.x or 0
        local y = (dt.y ~= nil) and dt.y or -2
        previewDurText:ClearAllPoints()
        if anchor == "BELOW_ICON" then
            previewDurText:SetPoint("TOP", previewHolder, "BOTTOM", x, y)
        elseif anchor == "ABOVE_ICON" then
            previewDurText:SetPoint("BOTTOM", previewHolder, "TOP", x, y)
        else
            previewDurText:SetPoint(anchor, previewHolder, anchor, x, y)
        end

        local st = (ap.text and ap.text.stacks) or {}
        local stackSize = tonumber(st.size) or 11
        if stackSize < 6 then stackSize = 6 elseif stackSize > 64 then stackSize = 64 end
        pcall(previewStackText.SetFont, previewStackText,
            "Fonts\\FRIZQT__.TTF", stackSize, "OUTLINE")
        if st.enabled == false then
            previewStackText:SetText("")
        else
            previewStackText:SetText("x3")
        end

        if ns.Glow and ns.Glow.Set and ns.Glow.Clear then
            local function glowOpts(rec)
                local opts = {}
                if rec and type(rec.style) == "string" then opts.style = rec.style end
                local c = rec and rec.color
                if type(c) == "table" then
                    opts.colorR = tonumber(c[1])
                    opts.colorG = tonumber(c[2])
                    opts.colorB = tonumber(c[3])
                    opts.colorA = tonumber(c[4])
                end
                return opts
            end
            local g = ap.glow or {}
            if g.pandemic and g.pandemic.enabled == false then
                pcall(ns.Glow.Clear, ns.Glow, previewHolder, "pandemic")
            else
                pcall(ns.Glow.Set, ns.Glow, previewHolder, "pandemic", glowOpts(g.pandemic))
            end
            if g.activeAura and g.activeAura.enabled == true then
                pcall(ns.Glow.Set, ns.Glow, previewHolder, "activeAura", glowOpts(g.activeAura))
            else
                pcall(ns.Glow.Clear, ns.Glow, previewHolder, "activeAura")
            end
        end
    end

    local previewBroken = false
    local function restylePreview()
        if previewBroken then return end
        local ok, err = pcall(restylePreviewImpl)
        if not ok then
            previewBroken = true
            previewRow:Hide()
            if ns.Debug and ns.Debug.Log then
                ns.Debug:Log("[AuraPanel] sample preview failed (hidden): %s", tostring(err))
            end
        end
    end
    restylePreview()

    children[#children + 1] = C.CreateSubSection(sc, "Pandemic Glow")

    do
        local support = auraSupportsPandemic(_currentAuraCooldownID)
        local note
        if support == true then
            note = "This aura has a pandemic refresh window (auto-detected)."
        elseif support == false then
            note = "No pandemic window reported for this aura -- the glow may never trigger. Settings are kept anyway."
        else
            note = "Applies to refreshable damage-over-time effects (auto-detection unavailable here)."
        end
        children[#children + 1] = C.CreateHelpText(sc, note)
    end

    children[#children + 1] = C.CreateCheckBox(sc, "Pandemic Glow Enabled",
        function()
            local ap = getAuraProfile(spellID)
            return ap.glow and ap.glow.pandemic and ap.glow.pandemic.enabled ~= false
        end,
        function(v)
            local ap = getAuraProfile(spellID)
            ap.glow = ap.glow or {}
            ap.glow.pandemic = ap.glow.pandemic or {}
            ap.glow.pandemic.enabled = v
            ap.glow.pandemic.userSet = true
            if ns.Auras and ns.Auras.PrebuildPandemicCurves then
                pcall(ns.Auras.PrebuildPandemicCurves, ns.Auras)
            end
            requestAurasRefresh()
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Pandemic Threshold (%)", 5, 50, 1,
        function()
            local ap = getAuraProfile(spellID)
            local t = (ap.glow and ap.glow.pandemic and ap.glow.pandemic.threshold) or 0.30
            return math.floor(t * 100 + 0.5)
        end,
        function(v)
            local ap = getAuraProfile(spellID)
            ap.glow = ap.glow or {}
            ap.glow.pandemic = ap.glow.pandemic or {}
            ap.glow.pandemic.threshold = v / 100
            ap.glow.pandemic.userSet = true
            if ns.Auras and ns.Auras.PrebuildPandemicCurves then
                pcall(ns.Auras.PrebuildPandemicCurves, ns.Auras)
            end
            requestAurasRefresh()
        end
    )

    local pandemicStyleValues = {}
    do
        local names
        if ns.Glow and ns.Glow.GetRegisteredStyles then
            names = ns.Glow:GetRegisteredStyles()
        else
            names = { "blizzard", "border", "overlay", "pixel", "solid" }
        end
        for i = 1, #names do
            local k = names[i]
            local label = (ns.Glow and ns.Glow.GetStyleLabel) and ns.Glow:GetStyleLabel(k) or k
            if k == "pixel" then
                label = label .. " (default)"
            end
            pandemicStyleValues[#pandemicStyleValues + 1] = { key = k, label = label }
        end
    end

    children[#children + 1] = C.CreateDropdownLikeList(sc, "Pandemic Glow Style",
        pandemicStyleValues,
        function()
            local ap = getAuraProfile(spellID)
            return (ap.glow and ap.glow.pandemic and ap.glow.pandemic.style) or "pixel"
        end,
        function(v)
            local ap = getAuraProfile(spellID)
            ap.glow = ap.glow or {}
            ap.glow.pandemic = ap.glow.pandemic or {}
            ap.glow.pandemic.style = v
            ap.glow.pandemic.userSet = true
            requestAurasRefresh()
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateHelpText(sc,
        "FX styles (animated borders) play on the live tile when the aura is not " ..
        "secret. The edge styles (Border, Pixel, Solid) and the pandemic two-zone " ..
        "fade are always available.")

    children[#children + 1] = C.CreateColorSwatch(sc, "Pandemic Glow Color",
        function()
            local ap = getAuraProfile(spellID)
            local c = ap.glow and ap.glow.pandemic and ap.glow.pandemic.color
            if c then return c[1], c[2], c[3], c[4] end
            return 1, 0.35, 0.1, 1
        end,
        function(r, g, b, a)
            local ap = getAuraProfile(spellID)
            ap.glow = ap.glow or {}
            ap.glow.pandemic = ap.glow.pandemic or {}
            ap.glow.pandemic.color = { r, g, b, a }
            ap.glow.pandemic.userSet = true
            requestAurasRefresh()
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateSubSection(sc, "Active Aura Glow")

    children[#children + 1] = C.CreateCheckBox(sc, "Active Aura Glow Enabled",
        function()
            local ap = getAuraProfile(spellID)
            return ap.glow and ap.glow.activeAura and ap.glow.activeAura.enabled == true
        end,
        function(v)
            local ap = getAuraProfile(spellID)
            ap.glow = ap.glow or {}
            ap.glow.activeAura = ap.glow.activeAura or {}
            ap.glow.activeAura.enabled = v
            if ns.Auras and ns.Auras.PrebuildPandemicCurves then
                pcall(ns.Auras.PrebuildPandemicCurves, ns.Auras)
            end
            requestAurasRefresh()
            restylePreview()
        end
    )

    local activeStyleValues = {}
    do
        local names
        if ns.Glow and ns.Glow.GetRegisteredStyles then
            names = ns.Glow:GetRegisteredStyles()
        else
            names = { "blizzard", "border", "overlay", "pixel", "solid" }
        end
        for i = 1, #names do
            local k = names[i]
            local label = (ns.Glow and ns.Glow.GetStyleLabel) and ns.Glow:GetStyleLabel(k) or k
            if k == "border" then
                label = label .. " (default)"
            end
            activeStyleValues[#activeStyleValues + 1] = { key = k, label = label }
        end
    end

    children[#children + 1] = C.CreateDropdownLikeList(sc, "Active Aura Glow Style",
        activeStyleValues,
        function()
            local ap = getAuraProfile(spellID)
            return (ap.glow and ap.glow.activeAura and ap.glow.activeAura.style) or "border"
        end,
        function(v)
            local ap = getAuraProfile(spellID)
            ap.glow = ap.glow or {}
            ap.glow.activeAura = ap.glow.activeAura or {}
            ap.glow.activeAura.style = v
            requestAurasRefresh()
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Active Aura Glow Color",
        function()
            local ap = getAuraProfile(spellID)
            local c = ap.glow and ap.glow.activeAura and ap.glow.activeAura.color
            if c then return c[1], c[2], c[3], c[4] end
            return 0.4, 0.8, 1, 1
        end,
        function(r, g, b, a)
            local ap = getAuraProfile(spellID)
            ap.glow = ap.glow or {}
            ap.glow.activeAura = ap.glow.activeAura or {}
            ap.glow.activeAura.color = { r, g, b, a }
            if ns.Auras and ns.Auras.PrebuildPandemicCurves then
                pcall(ns.Auras.PrebuildPandemicCurves, ns.Auras)
            end
            requestAurasRefresh()
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateSubSection(sc, "Display")

    children[#children + 1] = C.CreateCheckBox(sc, "Display as Icon",
        function()
            local ap = getAuraProfile(spellID)
            return ap.display and ap.display.asIcon ~= false
        end,
        function(v)
            local ap = getAuraProfile(spellID)
            ap.display = ap.display or {}
            ap.display.asIcon = v
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Display as Bar",
        function()
            local ap = getAuraProfile(spellID)
            return ap.display and ap.display.asBar ~= false
        end,
        function(v)
            local ap = getAuraProfile(spellID)
            ap.display = ap.display or {}
            ap.display.asBar = v
        end
    )

    children[#children + 1] = C.CreateSubSection(sc, "Duration Text")

    children[#children + 1] = C.CreateCheckBox(sc, "Show Duration Text",
        function()
            local ap = getAuraProfile(spellID)
            return ap.text and ap.text.duration and ap.text.duration.enabled ~= false
        end,
        function(v)
            local ap = getAuraProfile(spellID)
            ap.text = ap.text or {}
            ap.text.duration = ap.text.duration or {}
            ap.text.duration.enabled = v
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateFontDropdown(sc, "Duration Font",
        function()
            local ap = getAuraProfile(spellID)
            return (ap.text and ap.text.duration and ap.text.duration.font) or "default"
        end,
        function(v)
            local ap = getAuraProfile(spellID)
            ap.text = ap.text or {}
            ap.text.duration = ap.text.duration or {}
            ap.text.duration.font = v
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Duration Font Size", 8, 28, 1,
        function()
            local ap = getAuraProfile(spellID)
            return (ap.text and ap.text.duration and ap.text.duration.size) or 12
        end,
        function(v)
            local ap = getAuraProfile(spellID)
            ap.text = ap.text or {}
            ap.text.duration = ap.text.duration or {}
            ap.text.duration.size = math.floor(v + 0.5)
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateTextAnchorDropdown(sc, "Duration Anchor",
        function()
            local ap = getAuraProfile(spellID)
            return (ap.text and ap.text.duration and ap.text.duration.anchor) or "BOTTOM"
        end,
        function(v)
            local ap = getAuraProfile(spellID)
            ap.text = ap.text or {}
            ap.text.duration = ap.text.duration or {}
            ap.text.duration.anchor = v
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Duration X Offset", -30, 30, 1,
        function()
            local ap = getAuraProfile(spellID)
            return (ap.text and ap.text.duration and ap.text.duration.x) or 0
        end,
        function(v)
            local ap = getAuraProfile(spellID)
            ap.text = ap.text or {}
            ap.text.duration = ap.text.duration or {}
            ap.text.duration.x = math.floor(v + 0.5)
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Duration Y Offset", -30, 30, 1,
        function()
            local ap = getAuraProfile(spellID)
            return (ap.text and ap.text.duration and ap.text.duration.y) or -2
        end,
        function(v)
            local ap = getAuraProfile(spellID)
            ap.text = ap.text or {}
            ap.text.duration = ap.text.duration or {}
            ap.text.duration.y = math.floor(v + 0.5)
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateSubSection(sc, "Stacks Text")

    children[#children + 1] = C.CreateCheckBox(sc, "Show Stack Count",
        function()
            local ap = getAuraProfile(spellID)
            return ap.text and ap.text.stacks and ap.text.stacks.enabled ~= false
        end,
        function(v)
            local ap = getAuraProfile(spellID)
            ap.text = ap.text or {}
            ap.text.stacks = ap.text.stacks or {}
            ap.text.stacks.enabled = v
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Stacks Font Size", 8, 22, 1,
        function()
            local ap = getAuraProfile(spellID)
            return (ap.text and ap.text.stacks and ap.text.stacks.size) or 11
        end,
        function(v)
            local ap = getAuraProfile(spellID)
            ap.text = ap.text or {}
            ap.text.stacks = ap.text.stacks or {}
            ap.text.stacks.size = math.floor(v + 0.5)
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateSubSection(sc, "Visibility Conditions")

    children[#children + 1] = C.CreateCheckBox(sc, "Show Own Auras Only",
        function()
            local ap = getAuraProfile(spellID)
            return ap.visibility and ap.visibility.ownOnly ~= false
        end,
        function(v)
            local ap = getAuraProfile(spellID)
            ap.visibility = ap.visibility or {}
            ap.visibility.ownOnly = v
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Combat Only",
        function()
            local ap = getAuraProfile(spellID)
            return ap.visibility and ap.visibility.combatOnly == true
        end,
        function(v)
            local ap = getAuraProfile(spellID)
            ap.visibility = ap.visibility or {}
            ap.visibility.combatOnly = v
        end
    )

    local totalH = C.LayoutVertical(sc, children, 4, -8)
    sc:SetHeight(math.max(totalH, 10))
end

function AuraPanel:OpenForAura(spellID, containerKey, cooldownID)
    _currentAuraSpellID = spellID
    _currentAuraContainer = containerKey
    _currentAuraCooldownID = tonumber(cooldownID)
    if ns.Options then
        ns.Options:SelectPage("aura_settings", true)
        ns.Options:Open()
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
