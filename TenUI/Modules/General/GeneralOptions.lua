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

    children[#children + 1] = C.CreateSection(sc, "Reminders")

    children[#children + 1] = C.CreateHelpText(sc,
        "Lightweight quality-of-life reminders. Everything is off by default.")

    local tabRow = CreateFrame("Frame", nil, sc)
    tabRow:SetHeight(28)
    children[#children + 1] = tabRow

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
            tb:SetPoint("LEFT", tabRow, "LEFT", 0, 0)
        end
        prevTab = tb
        tb:SetSelected(t.key == _selectedQoLTab)
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
        function(v) getCA().fontSize = v applyCA() end
    )

    children[#children + 1] = C.CreateSlider(sc, "Hold Duration (s)", 0.1, 5.0, 0.1,
        function() return getCA().holdDuration or 0.9 end,
        function(v) getCA().holdDuration = v applyCA() end
    )

    children[#children + 1] = C.CreateSlider(sc, "Fade In (s)", 0.0, 2.0, 0.05,
        function() return getCA().fadeInDuration or 0.25 end,
        function(v) getCA().fadeInDuration = v applyCA() end
    )

    children[#children + 1] = C.CreateSlider(sc, "Fade Out (s)", 0.0, 3.0, 0.05,
        function() return getCA().fadeOutDuration or 0.6 end,
        function(v) getCA().fadeOutDuration = v applyCA() end
    )

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

    elseif _selectedQoLTab == "stealth" then

    children[#children + 1] = C.CreateSubSection(sc, "Stealth Tracking")

    children[#children + 1] = C.CreateCheckBox(sc, "Enable Stealth Tracking",
        function() return getST().enabled == true end,
        function(v) getST().enabled = v applyST() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Rogue (Stealth)",
        function() return getST().rogue == true end,
        function(v) getST().rogue = v applyST() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Feral Druid (Prowl)",
        function() return getST().druidFeral == true end,
        function(v) getST().druidFeral = v applyST() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Balance Druid (Prowl in cat form)",
        function() return getST().druidBalance == true end,
        function(v) getST().druidBalance = v applyST() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Guardian Druid (Prowl in cat form)",
        function() return getST().druidGuardian == true end,
        function(v) getST().druidGuardian = v applyST() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Restoration Druid (Prowl in cat form)",
        function() return getST().druidResto == true end,
        function(v) getST().druidResto = v applyST() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Warlock: Burning Rush warning icon",
        function() return getST().warlockBurningRush == true end,
        function(v) getST().warlockBurningRush = v applyST() end
    )

    children[#children + 1] = C.CreateSlider(sc, "Icon Size", 16, 96, 1,
        function() return getST().iconSize or 36 end,
        function(v) getST().iconSize = v applyST() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Hide while mounted",
        function() return getST().hideWhileMounted == true end,
        function(v) getST().hideWhileMounted = v applyST() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Only show in instances",
        function() return getST().instanceOnly == true end,
        function(v) getST().instanceOnly = v applyST() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Unlock to move",
        function()
            local f = ns.StealthTracking and ns.StealthTracking.frame
            return f and f._locked == false or false
        end,
        function(v)
            if ns.StealthTracking and ns.StealthTracking.SetUnlocked then
                ns.StealthTracking:SetUnlocked(v)
            end
        end
    )

    children[#children + 1] = C.CreateButton(sc, "Test Stealth Icon",
        function()
            if ns.StealthTracking and ns.StealthTracking.Test then
                ns.StealthTracking:Test()
            end
        end
    )

    children[#children + 1] = C.CreateButton(sc, "Reset Position",
        function()
            if ns.StealthTracking and ns.StealthTracking.ResetPosition then
                ns.StealthTracking:ResetPosition()
            end
        end
    )

    children[#children + 1] = C.CreateButton(sc, "Center Horizontally",
        function()
            if ns.StealthTracking and ns.StealthTracking.CenterHorizontally then
                ns.StealthTracking:CenterHorizontally()
            end
        end
    )

    elseif _selectedQoLTab == "classReminders" then

    children[#children + 1] = C.CreateSubSection(sc, "Class Reminders")

    children[#children + 1] = C.CreateCheckBox(sc, "Enable Class Reminders",
        function() return getCR().enabled == true end,
        function(v) getCR().enabled = v applyCR() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Shaman: shield missing",
        function() return getCR().shamanShields == true end,
        function(v) getCR().shamanShields = v applyCR() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Holy Paladin: beacons missing",
        function() return getCR().paladinBeacons == true end,
        function(v) getCR().paladinBeacons = v applyCR() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Pets: missing pet (Hunter/Warlock/Unholy DK/Frost Mage)",
        function() return getCR().pets == true end,
        function(v) getCR().pets = v applyCR() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Pets: pet-on-passive warning",
        function() return getCR().petPassive == true end,
        function(v) getCR().petPassive = v applyCR() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Shadow Priest: not in Shadowform",
        function() return getCR().shadowform == true end,
        function(v) getCR().shadowform = v applyCR() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Rogue: poison upkeep (lethal + non-lethal)",
        function() return getCR().roguePoisons == true end,
        function(v) getCR().roguePoisons = v applyCR() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Raid buffs (only when a provider class is in group)",
        function() return getCR().raidBuffs == true end,
        function(v) getCR().raidBuffs = v applyCR() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Only show in instances",
        function() return getCR().instanceOnly == true end,
        function(v) getCR().instanceOnly = v applyCR() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Show in raid groups",
        function() return getCR().showInRaid == true end,
        function(v) getCR().showInRaid = v applyCR() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Hide in rested areas",
        function() return getCR().hideInRested == true end,
        function(v) getCR().hideInRested = v applyCR() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Hide while mounted",
        function() return getCR().hideWhileMounted == true end,
        function(v) getCR().hideWhileMounted = v applyCR() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Only out of combat",
        function() return getCR().onlyOutOfCombat == true end,
        function(v) getCR().onlyOutOfCombat = v applyCR() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Enable glow",
        function() return getCR().glow == true end,
        function(v) getCR().glow = v applyCR() end
    )

    children[#children + 1] = C.CreateSlider(sc, "Icon Size", 16, 96, 1,
        function() return getCR().iconSize or 36 end,
        function(v) getCR().iconSize = v applyCR() end
    )

    children[#children + 1] = C.CreateSlider(sc, "Label Font Size", 8, 24, 1,
        function() return getCR().fontSize or 11 end,
        function(v) getCR().fontSize = v applyCR() end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Unlock to move",
        function()
            local f = ns.ClassReminders and ns.ClassReminders.frame
            return f and f._locked == false or false
        end,
        function(v)
            if ns.ClassReminders and ns.ClassReminders.SetUnlocked then
                ns.ClassReminders:SetUnlocked(v)
            end
        end
    )

    children[#children + 1] = C.CreateButton(sc, "Test Class Reminders",
        function()
            if ns.ClassReminders and ns.ClassReminders.Test then
                ns.ClassReminders:Test()
            end
        end
    )

    children[#children + 1] = C.CreateButton(sc, "Reset Position",
        function()
            if ns.ClassReminders and ns.ClassReminders.ResetPosition then
                ns.ClassReminders:ResetPosition()
            end
        end
    )

    children[#children + 1] = C.CreateButton(sc, "Center Horizontally",
        function()
            if ns.ClassReminders and ns.ClassReminders.CenterHorizontally then
                ns.ClassReminders:CenterHorizontally()
            end
        end
    )

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
end

local function refreshQoLPage(sc)
    local kids = { sc:GetChildren() }
    for i = 1, #kids do
        if kids[i] and type(kids[i].Refresh) == "function" then
            pcall(kids[i].Refresh, kids[i])
        end
    end
end

if ns.Options and ns.Options.RegisterPage then
    ns.Options:RegisterPage({
        key     = "qolReminders",
        label   = "Reminders",
        build   = buildQoLPage,
        refresh = refreshQoLPage,
    })
end
