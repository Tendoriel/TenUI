local addonName, ns = ...

local type  = type
local pcall = pcall
local math_max = math.max

local function copyDefaults(src)
    local copy = {}
    for kk, vv in pairs(src) do
        if type(vv) == "table" then
            local inner = {}
            for i, x in pairs(vv) do inner[i] = x end
            copy[kk] = inner
        else
            copy[kk] = vv
        end
    end
    return copy
end

local function buildGeneralDefaults()
    local defaults = {}
    local caDefaults = ns.CombatAlerts and ns.CombatAlerts.DEFAULTS
    defaults.combatAlerts = type(caDefaults) == "table"
        and copyDefaults(caDefaults) or { enabled = false }
    local stDefaults = ns.StealthTracking and ns.StealthTracking.DEFAULTS
    defaults.stealthTracking = type(stDefaults) == "table"
        and copyDefaults(stDefaults) or { enabled = false }
    local ttDefaults = ns.TooltipControl and ns.TooltipControl.DEFAULTS
    defaults.tooltipControl = type(ttDefaults) == "table"
        and copyDefaults(ttDefaults) or { enabled = false }
    local crDefaults = ns.ClassReminders and ns.ClassReminders.DEFAULTS
    defaults.classReminders = type(crDefaults) == "table"
        and copyDefaults(crDefaults) or { enabled = false }
    local trDefaults = ns.TalentReminder and ns.TalentReminder.DEFAULTS
    defaults.talentReminder = type(trDefaults) == "table"
        and copyDefaults(trDefaults) or { enabled = true }
    return defaults
end

local function ensureGeneralBranch()
    if not ns.savedVarsReady then return nil end
    local p = ns:GetProfile()
    p.modules = p.modules or {}
    p.modules.General = p.modules.General or {}
    if ns._deepCopyMissing then
        ns._deepCopyMissing(p.modules.General, buildGeneralDefaults())
    end
    return p.modules.General
end

ns:RegisterMessage("SAVEDVARS_READY", function()
    ensureGeneralBranch()
end)

ns:RegisterMessage("PROFILE_CHANGED", function()
    local general = ensureGeneralBranch()
    for _, name in ipairs({ "CombatAlerts", "StealthTracking", "TooltipControl", "ClassReminders", "TalentReminder" }) do
        local module = ns[name]
        local registered = ns:GetModule(name)
        if module and registered and registered.enabled then
            module.profileRef = general
            if module.ApplyOptions then module:ApplyOptions() end
        end
    end
end)

local function getCA()
    local g = ensureGeneralBranch()
    if not g then return {} end
    g.combatAlerts = g.combatAlerts or {}
    return g.combatAlerts
end

local function applyCA()
    if ns.CombatAlerts and ns.CombatAlerts.ApplyOptions then
        pcall(ns.CombatAlerts.ApplyOptions, ns.CombatAlerts)
    end
end

local function getST()
    local g = ensureGeneralBranch()
    if not g then return {} end
    g.stealthTracking = g.stealthTracking or {}
    return g.stealthTracking
end

local function applyST()
    if ns.StealthTracking and ns.StealthTracking.ApplyOptions then
        pcall(ns.StealthTracking.ApplyOptions, ns.StealthTracking)
    end
end

local function getCR()
    local g = ensureGeneralBranch()
    if not g then return {} end
    g.classReminders = g.classReminders or {}
    return g.classReminders
end

local function applyCR()
    if ns.ClassReminders and ns.ClassReminders.ApplyOptions then
        pcall(ns.ClassReminders.ApplyOptions, ns.ClassReminders)
    end
end

local function getTR()
    local g = ensureGeneralBranch()
    if not g then return {} end
    g.talentReminder = g.talentReminder or {}
    return g.talentReminder
end

local QOL_TABS = {
    { key = "combatAlerts",   label = "Combat Alerts" },
    { key = "stealth",        label = "Stealth" },
    { key = "classReminders", label = "Class Reminders" },
    { key = "talentReminder", label = "Talent Reminder" },
}

local _selectedQoLTab = "combatAlerts"

local function buildReminderPreview(sc, header, rows, isClass)
    local C = ns.UI
    local panel = CreateFrame("Frame", nil, header)
    panel:SetPoint("TOPLEFT", header, "TOPLEFT", 8, -30)
    panel:SetPoint("TOPRIGHT", header, "TOPRIGHT", -8, -30)
    C.SkinPanel(panel)

    local title = C.Text(panel, C.Fonts.small, C.Theme.color.textDim,
        isClass and "Preview for your class and spec" or "Stealth and Burning Rush preview")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -9)
    local empty = C.Text(panel, C.Fonts.small, C.Theme.color.textDim, "No enabled reminders for this class and spec.")
    empty:SetPoint("CENTER", panel, "CENTER", 0, -7)

    local function openSetting(key)
        local row = rows[key]
        local top, rowTop = sc:GetTop(), row and row:GetTop()
        if top and rowTop then
            local scroll = sc:GetParent()
            scroll:SetVerticalScroll(math.max(0, math.min(top - rowTop - 8, scroll:GetVerticalScrollRange())))
        end
    end

    local module = isClass and ns.ClassReminders or ns.StealthTracking
    local test = C.CreateCompactButton(panel, "Test on HUD", function() module:Test() end, 96)
    test:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -4)

    local render
    if isClass then
        render = module:CreateOptionsPreview(panel, openSetting)
    else
        local buttons = {}
        render = function(o)
            local entries = module:GetOptionsPreview(o)
            local size = o.iconSize or module.DEFAULTS.iconSize
            for i, entry in ipairs(entries) do
                local button = buttons[i]
                if not button then
                    local function selectEntry() openSetting(button.previewEntry.key) end
                    button = C.CreateIconButton(panel, { texture = entry.texture, isKnown = true }, {
                        onClick = selectEntry,
                        onRightClick = selectEntry,
                        onEnter = function(self)
                            local data = self.previewEntry
                            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                            GameTooltip:SetText(data.label)
                            GameTooltip:AddLine("Click to find this setting", 0.6, 0.8, 1)
                            GameTooltip:Show()
                        end,
                    })
                    button.name = C.Text(button, C.Fonts.small, C.Theme.color.text, entry.label)
                    button.name:SetPoint("TOP", button, "BOTTOM", 0, -2)
                    buttons[i] = button
                end
                button.previewEntry = entry
                button.iconTex:SetTexture(entry.texture)
                button.iconTex:SetDesaturated(not entry.enabled)
                button.iconTex:SetAlpha(entry.enabled and 1 or 0.45)
                button.name:SetAlpha(entry.enabled and 1 or 0.65)
                button:SetSize(size, size)
                button:ClearAllPoints()
                button:SetPoint("CENTER", panel, "CENTER", (i - 2) * (math.max(size, 80) + 8), 0)
            end
            return size + 15
        end
    end

    local getOptions = isClass and getCR or getST
    local function refresh()
        local height = render(getOptions())
        empty:SetShown(height == 0)
        panel:SetHeight(math.max(32, height) + 32)
        ns.Options:GetPinnedHeader("qolReminders", 32 + panel:GetHeight())
    end
    panel:SetScript("OnShow", function()
        refresh()
        if isClass then panel:RegisterEvent("SPELLS_CHANGED") end
    end)
    panel:SetScript("OnHide", function() panel:UnregisterAllEvents() end)
    panel:SetScript("OnEvent", refresh)
    return refresh
end

local function buildQoLPage(sc)
    local C = ns.UI
    if not C then return end
    local Theme = C.Theme
    local children = {}

    do
        local ui = ns.GetUIState and ns:GetUIState()
        local saved = ui and ui.lastOptionsSub and ui.lastOptionsSub.qolReminders
        if saved then
            for _, t in ipairs(QOL_TABS) do
                if t.key == saved then
                    _selectedQoLTab = saved
                    break
                end
            end
        end
    end

    sc.searchTab = _selectedQoLTab
    ns.Options:ClearPinnedHeader("qolReminders")
    local tabRow = ns.Options:GetPinnedHeader("qolReminders", 28)

    local prevTab
    for i, t in ipairs(QOL_TABS) do
        local capturedKey = t.key
        local tb = C.CreateTabButton(tabRow, t.label, function()
            if _selectedQoLTab == capturedKey then return end
            _selectedQoLTab = capturedKey
            local ui = ns.GetUIState and ns:GetUIState()
            if ui and ui.lastOptionsSub then
                ui.lastOptionsSub.qolReminders = capturedKey
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if ns.Options and ns.Options.RebuildPage then
                        ns.Options:RebuildPage("qolReminders")
                    end
                end)
            elseif ns.Options and ns.Options.RebuildPage then
                ns.Options:RebuildPage("qolReminders")
            end
        end)
        if prevTab then
            tb:SetPoint("LEFT", prevTab, "RIGHT", 4, 0)
        else
            tb:SetPoint("TOPLEFT", tabRow, "TOPLEFT", 8, 0)
        end
        prevTab = tb
        tb:SetSelected(t.key == _selectedQoLTab)
    end

    local isClass, isStealth = _selectedQoLTab == "classReminders", _selectedQoLTab == "stealth"
    local settingRows = {}
    local refreshPreview
    if isClass or isStealth then
        refreshPreview = buildReminderPreview(sc, tabRow, settingRows, isClass)
    end
    sc.refreshReminderPreview = refreshPreview
    local getReminderOptions = isClass and getCR or getST
    local applyReminderOptions = isClass and applyCR or applyST
    local function addReminderToggle(key, label, icons)
        local row = C.CreateCheckBox(sc, label,
            function() return getReminderOptions()[key] == true end,
            function(value)
                getReminderOptions()[key] = value
                if key == "raidBuffs" then
                    for _, buff in ipairs(ns.ClassReminders.raidBuffs) do
                        local child = settingRows[buff.option]
                        if child then child:SetAlpha(value and 1 or 0.45) child:EnableMouse(value) end
                    end
                end
                applyReminderOptions()
                refreshPreview()
            end)
        if icons then
            local previous
            for _, id in ipairs(icons) do
                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetSize(20, 20)
                icon:SetTexture(id)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                if previous then icon:SetPoint("LEFT", previous, "RIGHT", 2, 0)
                else icon:SetPoint("LEFT", row, "LEFT") end
                previous = icon
            end
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        end
        if key:match("^raidBuff%d") and not getReminderOptions().raidBuffs then
            row:SetAlpha(0.45)
            row:EnableMouse(false)
        end
        settingRows[key] = row
        children[#children + 1] = row
    end

    if _selectedQoLTab == "combatAlerts" then

    children[#children + 1] = C.CreateSubSection(sc, "Combat Alerts")

    children[#children + 1] = C.CreateCheckBox(sc, "Enable Combat Alerts",
        function() return getCA().enabled == true end,
        function(v) getCA().enabled = v applyCA() end
    )

    children[#children + 1] = C.CreateEditBox(sc, "Enter Combat Text",
        function() return getCA().enterText end,
        function(v) getCA().enterText = v applyCA() end
    )

    children[#children + 1] = C.CreateEditBox(sc, "Leave Combat Text",
        function() return getCA().leaveText end,
        function(v) getCA().leaveText = v applyCA() end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Enter Color",
        function()
            local c = getCA().enterColor or { 1, 1, 1, 1 }
            return c[1], c[2], c[3], c[4]
        end,
        function(r, g, b, a)
            getCA().enterColor = { r, g, b, a }
            applyCA()
        end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Leave Color",
        function()
            local c = getCA().leaveColor or { 1, 1, 1, 1 }
            return c[1], c[2], c[3], c[4]
        end,
        function(r, g, b, a)
            getCA().leaveColor = { r, g, b, a }
            applyCA()
        end
    )

    children[#children + 1] = C.CreateFontDropdown(sc, "Font",
        function() return getCA().font or "default" end,
        function(v) getCA().font = v applyCA() end
    )

    children[#children + 1] = C.CreateSlider(sc, "Font Size", 10, 72, 1,
        function() return getCA().fontSize or 32 end,
        function(v) getCA().fontSize = v applyCA() end, 32)

    children[#children + 1] = C.CreateSlider(sc, "Hold Duration (s)", 0.1, 5.0, 0.1,
        function() return getCA().holdDuration or 0.9 end,
        function(v) getCA().holdDuration = v applyCA() end, 0.9)

    children[#children + 1] = C.CreateSlider(sc, "Fade In (s)", 0.0, 2.0, 0.05,
        function() return getCA().fadeInDuration or 0.25 end,
        function(v) getCA().fadeInDuration = v applyCA() end, 0.25)

    children[#children + 1] = C.CreateSlider(sc, "Fade Out (s)", 0.0, 3.0, 0.05,
        function() return getCA().fadeOutDuration or 0.6 end,
        function(v) getCA().fadeOutDuration = v applyCA() end, 0.6)

    children[#children + 1] = C.CreateCheckBox(sc, "Play Sound on Alert",
        function() return getCA().soundEnabled == true end,
        function(v) getCA().soundEnabled = v end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Unlock to move",
        function()
            local f = ns.CombatAlerts and ns.CombatAlerts.frame
            return f and f._locked == false or false
        end,
        function(v)
            if ns.CombatAlerts and ns.CombatAlerts.SetUnlocked then
                ns.CombatAlerts:SetUnlocked(v)
            end
        end
    )

    children[#children + 1] = C.CreateButton(sc, "Test Combat Alert",
        function()
            if ns.CombatAlerts and ns.CombatAlerts.Test then
                ns.CombatAlerts:Test()
            end
        end
    )

    children[#children + 1] = C.CreateButton(sc, "Reset Position",
        function()
            if ns.CombatAlerts and ns.CombatAlerts.ResetPosition then
                ns.CombatAlerts:ResetPosition()
            end
        end
    )

    children[#children + 1] = C.CreateButton(sc, "Center Horizontally",
        function()
            if ns.CombatAlerts and ns.CombatAlerts.CenterHorizontally then
                ns.CombatAlerts:CenterHorizontally()
            end
        end
    )

    elseif isClass or isStealth then

    children[#children + 1] = C.CreateSection(sc, isClass and "Class Reminders" or "Stealth Tracking")
    addReminderToggle("enabled", isClass and "Enable Class Reminders" or "Enable Stealth Tracking")

    if isClass then
        addReminderToggle("clickToApply", "Click missing buffs or summons outside combat")
        addReminderToggle("readyCheck", "Check consumables and repairs during ready checks")
        local function texture(spell, fallback)
            return C_Spell.GetSpellTexture(spell) or fallback
        end
        children[#children + 1] = C.CreateSubSection(sc, "Raid Buffs")
        addReminderToggle("raidBuffs", "Track buffs provided by players in your group")
        for _, buff in ipairs(ns.ClassReminders.raidBuffs) do
            addReminderToggle(buff.option, C_Spell.GetSpellName(buff.iconSpell) or buff.label,
                { texture(buff.iconSpell, buff.fallback) })
        end

        children[#children + 1] = C.CreateSubSection(sc, "Self Buffs and Forms")
        addReminderToggle("shamanShields", "Shaman shields", { texture(974, 136089), texture(192106, 136051), texture(52127, 132315) })
        addReminderToggle("shadowform", "Shadowform", { texture(232698, 136200) })
        addReminderToggle("moonkinForm", "Moonkin Form", { texture(24858, 136036) })
        addReminderToggle("roguePoisons", "Lethal and non-lethal poisons", { texture(8679, 132273), texture(3408, 132274) })

        children[#children + 1] = C.CreateSubSection(sc, "Targeted Buffs")
        addReminderToggle("paladinBeacons", "Beacon of Light and Beacon of Faith", { texture(53563, 1030094), texture(156910, 1030095) })

        children[#children + 1] = C.CreateSubSection(sc, "Pet Reminders")
        addReminderToggle("pets", "Missing or incorrect pet", { 132599 })
        addReminderToggle("petPassive", "Pet on passive", { 132311 })
    else
        children[#children + 1] = C.CreateSubSection(sc, "Stealth Indicators")
        addReminderToggle("rogue", "Rogue (Stealth)")
        addReminderToggle("druidFeral", "Feral Druid (Prowl)")
        addReminderToggle("druidBalance", "Balance Druid (Prowl in cat form)")
        addReminderToggle("druidGuardian", "Guardian Druid (Prowl in cat form)")
        addReminderToggle("druidResto", "Restoration Druid (Prowl in cat form)")

        children[#children + 1] = C.CreateSubSection(sc, "Burning Rush")
        addReminderToggle("warlockBurningRush", "Warlock: show while Burning Rush is active")
    end

    children[#children + 1] = C.CreateSection(sc, "Appearance")
    if isClass then
        addReminderToggle("showActive", "Show active buffs, forms and pets with a check mark")
        addReminderToggle("glow", "Glow when a reminder needs attention")
        children[#children + 1] = C.CreateSlider(sc, "Label Font Size", 8, 24, 1,
            function() return getCR().fontSize or 11 end,
            function(value)
                getCR().fontSize = value
                applyCR()
                refreshPreview()
            end, 11)
    end
    children[#children + 1] = C.CreateSlider(sc, "Icon Size", 16, 96, 1,
        function() return getReminderOptions().iconSize or 36 end,
        function(value)
            getReminderOptions().iconSize = value
            applyReminderOptions()
            refreshPreview()
        end, 36)

    children[#children + 1] = C.CreateSection(sc, "Visibility")
    addReminderToggle("hideWhileMounted", "Hide while mounted")
    addReminderToggle("instanceOnly", "Only show in instances")
    if isClass then
        addReminderToggle("showInRaid", "Show in raid groups")
        addReminderToggle("hideInRested", "Hide in rested areas")
        children[#children + 1] = C.CreateHelpText(sc, "Class reminders are hidden in combat, while dead and in spirit form.")
    end

    children[#children + 1] = C.CreateSection(sc, "Position")
    local module = isClass and ns.ClassReminders or ns.StealthTracking
    children[#children + 1] = C.CreateCheckBox(sc, "Unlock to move",
        function() return module.frame and module.frame._locked == false end,
        function(value) module:SetUnlocked(value) end)
    children[#children + 1] = C.CreateButton(sc, "Reset Position", function() module:ResetPosition() end)
    children[#children + 1] = C.CreateButton(sc, "Center Horizontally", function() module:CenterHorizontally() end)

    elseif _selectedQoLTab == "talentReminder" then

    children[#children + 1] = C.CreateSubSection(sc, "Talent Reminder")

    children[#children + 1] = C.CreateCheckBox(sc, "Enable Talent Reminder",
        function() return getTR().enabled == true end,
        function(v) getTR().enabled = v end
    )

    do
        local label = CreateFrame("Frame", nil, sc)
        label:SetHeight(16)
        local fs = C.Text(label, C.Fonts.value, Theme.color.accent)
        fs:SetPoint("TOPLEFT", label, "TOPLEFT", 0, 0)
        fs:SetPoint("TOPRIGHT", label, "TOPRIGHT", 0, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        function label:Refresh()
            local name = ns.TalentReminder and ns.TalentReminder.GetCurrentBuildName
                and ns.TalentReminder:GetCurrentBuildName() or "Unknown"
            fs:SetText("Current build: " .. tostring(name))
        end
        label:Refresh()
        children[#children + 1] = label
    end

    children[#children + 1] = C.CreateCheckBox(sc, "Show build name on Ready Check",
        function() return getTR().showOnReadyCheck == true end,
        function(v) getTR().showOnReadyCheck = v end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Check expected build on Ready Check",
        function() return getTR().checkOnReadyCheck == true end,
        function(v) getTR().checkOnReadyCheck = v end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Check expected build on dungeon/raid entry",
        function() return getTR().checkOnEntry == true end,
        function(v) getTR().checkOnEntry = v end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Show mismatch warning popup",
        function() return getTR().showPopup == true end,
        function(v) getTR().showPopup = v end
    )

    children[#children + 1] = C.CreateButton(sc, "Save current build for current zone",
        function()
            if ns.TalentReminder and ns.TalentReminder.SaveCurrentBuild then
                ns.TalentReminder:SaveCurrentBuild()
            end
        end
    )

    children[#children + 1] = C.CreateButton(sc, "Clear saved build for current zone",
        function()
            if ns.TalentReminder and ns.TalentReminder.ClearCurrentBuild then
                ns.TalentReminder:ClearCurrentBuild()
            end
        end
    )

    children[#children + 1] = C.CreateButton(sc, "Clear all saved builds",
        function()
            if ns.TalentReminder and ns.TalentReminder.ClearAllBuilds then
                ns.TalentReminder:ClearAllBuilds()
            end
        end
    )

    children[#children + 1] = C.CreateButton(sc, "Print Current Talent Build",
        function()
            if ns.TalentReminder and ns.TalentReminder.PrintCurrentBuild then
                ns.TalentReminder:PrintCurrentBuild()
            end
        end
    )

    end

    local totalH = C.LayoutVertical(sc, children, 4, -8)
    sc:SetHeight(math_max(totalH, 10))
    if refreshPreview then refreshPreview() end
end

local function refreshQoLPage(sc)
    local kids = { sc:GetChildren() }
    for i = 1, #kids do
        if kids[i] and type(kids[i].Refresh) == "function" then
            pcall(kids[i].Refresh, kids[i])
        end
    end
    if sc.refreshReminderPreview then sc.refreshReminderPreview() end
end

if ns.Options and ns.Options.RegisterPage then
    ns.Options:RegisterPage({
        key     = "qolReminders",
        label   = "Reminders",
        build   = buildQoLPage,
        refresh = refreshQoLPage,
    })
end
