local addonName, ns = ...

local function out(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7TenUI|r: " .. tostring(msg))
end

local function showHelp()
    out("v" .. tostring(ns.version) .. " commands:")
    out("  |cffffd200/tenui|r                       -- show version and commands")
    out("  |cffffd200/tenui help|r                  -- this list")
    out("  |cffffd200/tenui debug|r                 -- toggle debug window")
    out("  |cffffd200/tenui debug clear|r           -- clear debug log")
    out("  |cffffd200/tenui debug pause|r           -- stop appending new lines + freeze display")
    out("  |cffffd200/tenui debug resume|r          -- resume appending + display updates")
    out("  |cffffd200/tenui debug verbose <module> [off]|r -- toggle verbose detail for a module (e.g. auras)")
    out("  |cffffd200/tenui debug trace <module> [off]|r   -- toggle per-tick trace for a module (e.g. auras)")
    out("  |cffffd200/tenui debug chat on|off|r     -- mirror debug lines to the chat frame (default off)")
    out("  |cffffd200/tenui debug status|r          -- show enabled/pause/maxLines + which modules have verbose/trace on")
    out("  |cffffd200/tenui lock|r                  -- lock anchors")
    out("  |cffffd200/tenui unlock|r                -- unlock anchors (out of combat)")
    out("  |cffffd200/tenui reset anchors|r         -- reset all anchors to defaults")
    out("  |cffffd200/tenui reset anchor <name>|r   -- reset one anchor to its default")
    out("  |cffffd200/tenui anchor reset|r          -- emergency: force-reset TrackedIcon + TrackedBars")
    out("  |cffffd200/tenui anchor reset <name>|r   -- emergency: force-reset one anchor (any name)")
    out("  |cffffd200/tenui anchor list|r           -- print live + saved width/height of every anchor (+ per-anchor save/load sentinels)")
    out("  |cffffd200/tenui anchor set <name> <x> <y>|r -- write saved x/y directly (debug escape hatch)")
    out("  |cffffd200/tenui anchor history|r [name]  -- dump persistent SAVE/LOAD/APPLY ring (per anchor if name given)")
    out("  |cffffd200/tenui reset|r                 -- prompt to wipe SavedVariables")
    out("  |cffffd200/tenui reset confirm|r         -- wipe SavedVariables and reload")
    out("  |cffffd200/tenui version|r               -- print version")
    out("  |cffffd200/tenui options|r               -- open options window")
    out("  |cffffd200/tenui demo widgets|r          -- toggle Bar/Icon/Text demo widgets")
    out("  |cffffd200/tenui castbar test|r          -- cycle CastBar visuals (cast/channel/empower/off)")
    out("  |cffffd200/tenui castbar reset|r         -- restore CastBar module defaults")
    out("  |cffffd200/tenui castbar grace on|off|r  -- toggle grace-window anti-flicker (Phase B)")
    out("  |cffffd200/tenui castbar instant on|off|r -- toggle GCD instant-cast overlay (Phase B)")
    out("  |cffffd200/tenui resources reset|r       -- restore Resources module defaults")
    out("  |cffffd200/tenui resources thldump|r      -- dump threshold-line per-spell diagnostics (known/cost/routing) to the debug window")
    out("  |cffffd200/tenui combatalert test|r       -- fire the QoL Combat Alert test")
    out("  |cffffd200/tenui combatalert reset|r      -- reset Combat Alert frame position")
    out("  |cffffd200/tenui general debug|r           -- show which QoL modules are enabled")
    out("  |cffffd200/tenui stealth test|r            -- force the Stealth Tracking icon visible for a few seconds")
    out("  |cffffd200/tenui stealth reset|r           -- reset Stealth Tracking frame position")
    out("  |cffffd200/tenui tooltipdump|r             -- dump last-seen tooltip item/spell/icon ids to the debug window")
    out("  |cffffd200/tenui classreminder test|r       -- force-show test Class Reminders for a few seconds")
    out("  |cffffd200/tenui classreminder reset|r      -- reset Class Reminders frame position")
    out("  |cffffd200/tenui talent|r                   -- print current talent build, zone key, and saved expected build")
    out("  |cffffd200/tenui talent save|r              -- save current build as expected for the current zone")
    out("  |cffffd200/tenui talent clear|r             -- clear the saved expected build for the current zone")
    out("  |cffffd200/tenui bars|r                   -- list rows + displayed/candidate counts")
    out("  |cffffd200/tenui bars list <row>|r        -- list displayed and candidates for a row")
    out("  |cffffd200/tenui bars add <row> spell:<id>|r    -- append a spell to a row")
    out("  |cffffd200/tenui bars add <row> spell:<id> summon:<sec>|r -- spell with active-summon timer")
    out("  |cffffd200/tenui bars add <row> item:<id>|r     -- append an item to a row")
    out("  |cffffd200/tenui bars remove <row> spell:<id>|r -- remove a spell from a row")
    out("  |cffffd200/tenui bars remove <row> item:<id>|r  -- remove an item from a row")
    out("  |cffffd200/tenui bars scan|r              -- run CDM scan for all rows")
    out("  |cffffd200/tenui bars scan <row>|r        -- run CDM scan for one row")
    out("  |cffffd200/tenui bars trinkets autoadd|r  -- (legacy) re-sync Trinkets row to equipped on-use trinkets")
    out("  |cffffd200/tenui trinkets|r               -- print currently-tracked on-use trinkets (slot/itemID/spellID/cooldown)")
    out("  |cffffd200/tenui trinkets rescan|r        -- force re-scan equipped trinket slots (slot 13 + 14)")
    out("  |cffffd200/tenui bars clear <row>|r       -- clear displayed entries for one row")
    out("  |cffffd200/tenui bars reset|r             -- restore Bars module defaults")
    out("  |cffffd200/tenui bars scope|r             -- print current class+spec scope key")
    out("  |cffffd200/tenui bars scopes|r            -- list all saved class+spec scopes")
    out("  |cffffd200/tenui bars procdump|r          -- COMBAT-CAPABLE: per-icon base/override spellID, IsSpellUsable, proc-glow-seen (to debug window)")
    out("  |cffffd200/tenui auras|r                  -- overview (icon/bar displays, active counts, scope)")
    out("  |cffffd200/tenui auras icons on|off|r     -- toggle the tracked-buff ICON display")
    out("  |cffffd200/tenui auras bars on|off|r      -- toggle the tracked-bar BAR display")
    out("  |cffffd200/tenui auras rescan|r           -- re-read both CDM aura categories (mirror)")
    out("  |cffffd200/tenui auras reset|r            -- restore Auras module defaults")
    out("  |cffffd200/tenui auras unsuppress|r       -- restore alpha on native CDM aura viewers (recovery)")
    out("  |cffffd200/tenui auras suppress|r         -- re-hide native CDM aura viewers")
    out("  |cffffd200/tenui auras pandemic on|off|r  -- toggle pandemic glow on BuffBar items")
    out("  |cffffd200/tenui auras pandemic threshold <0..100>|r -- set pandemic window percent (default 30)")
    out("  |cffffd200/tenui auras pandemic dump|r    -- print per-cdID pandemic state (diagnostic)")
    out("  |cffffd200/tenui auras pandemic probe <cdID>|r -- dump full field structure of one item (diagnostic)")
    out("  |cffffd200/tenui auras pandemic skip|unskip <cdID>|r -- blacklist a cdID from glow")
    out("  |cffffd200/tenui auras pandemic only|unonly <cdID>|r -- whitelist mode: glow ONLY these cdIDs")
    out("  |cffffd200/tenui auras pandemic listfilters|r       -- show skip/only sets")
    out("  |cffffd200/tenui auras activeglow on|off|r           -- toggle active-aura glow (icons + bars) -- lights EVERY live aura; use sparingly")
    out("  |cffffd200/tenui aura lowtime on|off|toggle|r         -- recolor timer NUMBER (icons + bars) AND the bar FILL when low on time (default off; applied live)")
    out("  |cffffd200/tenui aura lowtime threshold <1..60>|r     -- displayed seconds at/below which the timer NUMBER + bar FILL take the low color (default 5s)")
    out("  |cffffd200/tenui aura lowtime color <r> <g> <b>|r     -- low-time color for both timer NUMBER + bar FILL, each channel 0..1 (default 1 0.15 0.10)")
    out("  |cffffd200/tenui aura lowtime|r                       -- (bare) diagnostic for the timer-number layer (enabled/threshold/colors + first active bar/icon)")
    out("  |cffffd200/tenui aura lowtimedebug|r                  -- COMBAT-CAPABLE engine diagnostic: durObj path, curve eval ok/err, result-secret, curveApplied, failed-latch (run OOC + in combat)")
    out("  |cffffd200/tenui auras barpreview on|off|r [count]    -- spawn deterministic DRAINING demo bars (test Bar Width w/o a live aura)")
    out("  |cffffd200/tenui auras glow dump|r [N]                -- diagnostic: per-slot glow state (default N=12)")
    out("  |cffffd200/tenui auras prefer icon|bar|r            -- cross-viewer dedup precedence (default: bar)")
    out("  |cffffd200/tenui aura forceviewer on|off|toggle|r   -- keep Blizzard CDM viewer populated+invisible for in-combat target debuffs (default: off)")
    out("  |cffffd200/tenui aura dump|r                         -- CDM identity/runtime/display/matching dump (to debug window)")
    out("  |cffffd200/tenui aura pipeline|r                     -- prove WHERE the aura display chain breaks (to debug window)")
    out("  |cffffd200/tenui aura rawset|r                       -- dump RAW Blizzard CDM category sets (unfiltered) -- no-cooldownID vs HideByDefault (to debug window)")
    out("  |cffffd200/tenui aura verifydk|r                     -- DK Virulent/Dread Plague + Lesser Ghoul icon self-test")
    out("  |cffffd200/tenui auras lookup <spellID>|r            -- viewer-aura map + active + probe diagnostic")
    out("  |cffffd200/tenui auras dedup dump|r                  -- list cross-viewer overlaps (spellIDs in both viewers)")
    out("  |cffffd200/tenui glow dump|r                          -- ns.Glow core diagnostic: style registry, priorities/channels, live intents (G0)")
    out("  |cffffd200/tenui swipe dump|r                         -- per-icon duration-swipe diagnostic: widget flag, live GetDrawSwipe/GetDrawEdge, hook, last arm path")
end

local function safeCreate(list, label, fn)
    local ok, result = pcall(fn)
    if not ok then
        if ns.Debug and ns.Debug.Log then
            ns.Debug:Log("Slash demo: " .. label .. " creation failed: " .. tostring(result))
        end
        return
    end
    if result then
        list[#list + 1] = result
    end
end

local function demoWidgetsToggle()
    ns._demoWidgets = ns._demoWidgets or {}

    if ns._demoShown then
        for i = 1, #ns._demoWidgets do
            local w = ns._demoWidgets[i]
            if w and w.Destroy then
                pcall(w.Destroy, w)
            end
        end
        ns._demoWidgets = {}
        ns._demoShown = false
        out("demo widgets removed")
        return
    end

    local Widgets = ns.Widgets
    if not (Widgets and Widgets.Bar and Widgets.Icon and Widgets.Text) then
        out("widget system not ready")
        return
    end

    safeCreate(ns._demoWidgets, "Icon", function()
        local essential = ns:GetAnchor("EssentialCooldowns")
        if not (essential and essential.frame) then return nil end
        local tex = nil
        if C_Spell and C_Spell.GetSpellTexture then
            tex = C_Spell.GetSpellTexture(61304)
        end
        if not tex then tex = [[Interface\Icons\Spell_Holy_PowerWordShield]] end
        local icon = Widgets.Icon:New(essential.frame, {
            texture   = tex,
            border    = true,
            cooldown  = true,
            countdown = true,
            stackText = true,
            fontSize  = 12,
            fontFlags = "OUTLINE",
            zoomIcon  = true,
        })
        icon:SetStackText(3)
        icon:Show()
        return icon
    end)

    safeCreate(ns._demoWidgets, "Bar", function()
        local resources = ns:GetAnchor("Resources")
        if not (resources and resources.frame) then return nil end
        local bar = Widgets.Bar:New(resources.frame, {
            orientation = "HORIZONTAL",
            fgColor     = { 0.2, 0.5, 1.0, 1 },
            bgColor     = { 0, 0, 0, 0.7 },
            border      = true,
            leftText    = true,
            rightText   = true,
            fontSize    = 12,
            fontFlags   = "OUTLINE",
        })
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(65)
        bar:SetLeftText("Demo Resource")
        bar:SetRightText("65 / 100")
        bar:Show()
        return bar
    end)

    safeCreate(ns._demoWidgets, "Text", function()
        local castbar = ns:GetAnchor("CastBar")
        if not (castbar and castbar.frame) then return nil end
        local txt = Widgets.Text:New(castbar.frame, {
            text      = "Demo cast text",
            fontSize  = 14,
            fontFlags = "OUTLINE",
            justifyH  = "CENTER",
            justifyV  = "MIDDLE",
            color     = { 1, 1, 1, 1 },
            shadow    = true,
        })
        txt:Show()
        return txt
    end)

    ns._demoShown = true
    out("demo widgets shown (" .. #ns._demoWidgets .. " created)")
end

local function handleDemo(rest)
    local sub = (rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if sub == "widgets" then
        demoWidgetsToggle()
        return
    end
    out("usage: |cffffd200/tenui demo widgets|r")
end

local function handleCastBar(rest)
    local raw = rest or ""
    local sub = raw:gsub("^%s+", ""):gsub("%s+$", ""):lower()
    local head, tail = sub:match("^(%S+)%s*(.*)$")
    head = head or sub
    if sub == "test" then
        if not (ns.CastBar and ns.CastBar.RunTest) then
            out("castbar module not loaded")
            return
        end
        local label = ns.CastBar:RunTest()
        if label then out("castbar: " .. label) end
        return
    end
    if sub == "reset" then
        local mod = ns:GetModule("CastBar")
        if not mod then
            out("castbar module not registered")
            return
        end
        local profile = ns:GetProfile()
        profile.modules = profile.modules or {}
        profile.modules.CastBar = nil
        ns:DisableModule("CastBar")
        ns:EnableModule("CastBar")
        out("castbar module reset to defaults")
        return
    end

    if head == "grace" then
        if not (ns.CastBar and ns.CastBar.SetGraceEnabled) then
            out("castbar grace helpers not loaded")
            return
        end
        local arg = (tail or ""):lower()
        if arg == "on" or arg == "off" then
            local want = (arg == "on")
            local ok, err = ns.CastBar:SetGraceEnabled(want)
            if ok then
                out(("castbar grace -> |cffffd200%s|r"):format(want and "on" or "off"))
            else
                out("could not toggle grace: " .. tostring(err))
            end
        else
            local enabled = ns.CastBar:IsGraceEnabled()
            out(("castbar grace: |cffffd200%s|r"):format(enabled and "on" or "off"))
            out("usage: |cffffd200/tenui castbar grace on|off|r")
        end
        return
    end

    if head == "instant" then
        if not (ns.CastBar and ns.CastBar.SetInstantEnabled) then
            out("castbar instant helpers not loaded")
            return
        end
        local arg = (tail or ""):lower()
        if arg == "on" or arg == "off" then
            local want = (arg == "on")
            local ok, err = ns.CastBar:SetInstantEnabled(want)
            if ok then
                out(("castbar instant -> |cffffd200%s|r"):format(want and "on" or "off"))
            else
                out("could not toggle instant: " .. tostring(err))
            end
        else
            local enabled = ns.CastBar:IsInstantEnabled()
            out(("castbar instant: |cffffd200%s|r"):format(enabled and "on" or "off"))
            out("usage: |cffffd200/tenui castbar instant on|off|r")
        end
        return
    end

    if sub == "" then
        local g = ns.CastBar and ns.CastBar.IsGraceEnabled and ns.CastBar:IsGraceEnabled()
        local i = ns.CastBar and ns.CastBar.IsInstantEnabled and ns.CastBar:IsInstantEnabled()
        out("castbar status:")
        out(("  grace (anti-flicker)        : |cffffd200%s|r"):format(g and "on" or "off"))
        out(("  instant overlay (GCD flash) : |cffffd200%s|r"):format(i and "on" or "off"))
        out("  |cffffd200/tenui castbar test|r | |cffffd200reset|r | |cffffd200grace on|off|r | |cffffd200instant on|off|r")
        return
    end

    out("usage: |cffffd200/tenui castbar test|r | |cffffd200reset|r | |cffffd200grace on|off|r | |cffffd200instant on|off|r")
end

local function handleResources(rest)
    local sub = (rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if sub == "reset" then
        local mod = ns:GetModule("Resources")
        if not mod then
            out("resources module not registered")
            return
        end
        local profile = ns:GetProfile()
        profile.modules = profile.modules or {}
        profile.modules.Resources = nil
        ns:DisableModule("Resources")
        ns:EnableModule("Resources")
        out("resources module reset to defaults")
        return
    end
    if sub == "thldump" then
        local D = ns.Resources_Display
        if D and D.thLines_DiagDump and D.thLines_DiagDump() then
            if ns.Debug and ns.Debug.Show then ns.Debug:Show() end
            out("thldump sent to the debug window -- |cffffd200/tenui debug|r to view/copy")
        else
            out("thldump unavailable (Resources display or debug window not loaded)")
        end
        return
    end
    out("usage: |cffffd200/tenui resources reset|r | |cffffd200thldump|r (threshold-line diagnostic)")
end

local function handleCombatAlert(rest)
    local sub = (rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if sub == "test" then
        if not (ns.CombatAlerts and ns.CombatAlerts.Test) then
            out("combat alerts module not loaded")
            return
        end
        local ok = ns.CombatAlerts:Test()
        out(ok and "combat alert test fired" or "combat alert test could not fire (savedvars not ready?)")
        return
    end
    if sub == "reset" then
        if ns.CombatAlerts and ns.CombatAlerts.ResetPosition then
            ns.CombatAlerts:ResetPosition()
            out("combat alert position reset to default")
        else
            out("combat alerts module not loaded")
        end
        return
    end
    out("usage: |cffffd200/tenui combatalert test|r | |cffffd200reset|r")
end

local function handleStealth(rest)
    local sub = (rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if sub == "test" then
        if not (ns.StealthTracking and ns.StealthTracking.Test) then
            out("stealth tracking module not loaded")
            return
        end
        local ok = ns.StealthTracking:Test()
        out(ok and "stealth icon test forced for 5 seconds"
            or "stealth test could not fire (savedvars not ready?)")
        return
    end
    if sub == "reset" then
        if ns.StealthTracking and ns.StealthTracking.ResetPosition then
            ns.StealthTracking:ResetPosition()
            out("stealth tracking position reset to default")
        else
            out("stealth tracking module not loaded")
        end
        return
    end
    out("usage: |cffffd200/tenui stealth test|r | |cffffd200reset|r")
end

local function handleClassReminder(rest)
    local sub = (rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if sub == "test" then
        if not (ns.ClassReminders and ns.ClassReminders.Test) then
            out("class reminders module not loaded")
            return
        end
        local ok = ns.ClassReminders:Test()
        out(ok and "class reminders test forced for 5 seconds"
            or "class reminders test could not fire (savedvars not ready?)")
        return
    end
    if sub == "reset" then
        if ns.ClassReminders and ns.ClassReminders.ResetPosition then
            ns.ClassReminders:ResetPosition()
            out("class reminders position reset to default")
        else
            out("class reminders module not loaded")
        end
        return
    end
    out("usage: |cffffd200/tenui classreminder test|r | |cffffd200reset|r")
end

local function handleTalent(rest)
    local TR = ns.TalentReminder
    if not TR then
        out("talent reminder module not loaded")
        return
    end
    local sub = (rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()

    if sub == "save" then
        local ok, keyOrErr, name = TR:SaveCurrentBuild()
        if ok then
            out(("expected build saved -- key=|cffffd200%s|r build=|cffffd200%s|r")
                :format(tostring(keyOrErr), tostring(name)))
        else
            out("could not save: " .. tostring(keyOrErr))
        end
        return
    end

    if sub == "clear" then
        local ok, keyOrErr = TR:ClearCurrentBuild()
        if ok then
            out(("expected build cleared for key=|cffffd200%s|r"):format(tostring(keyOrErr)))
        else
            out("could not clear: " .. tostring(keyOrErr))
        end
        return
    end

    if sub == "clearall" then
        TR:ClearAllBuilds()
        out("all expected builds cleared")
        return
    end

    if sub ~= "" then
        out("usage: |cffffd200/tenui talent|r | |cffffd200save|r | |cffffd200clear|r | |cffffd200clearall|r")
        return
    end

    local name = TR.GetCurrentBuildName and TR:GetCurrentBuildName() or "Unknown"
    local key = TR.GetCurrentKey and TR:GetCurrentKey()
    local exp = TR.GetExpectedForCurrentKey and TR:GetExpectedForCurrentKey()
    out(("talent build: |cffffd200%s|r  zone key: |cffffd200%s|r  expected: |cffffd200%s|r")
        :format(tostring(name), tostring(key or "none (open world)"),
            exp and tostring(exp.name) or "none saved"))
end

local function handleTooltipDump()
    if not (ns.TooltipControl and ns.TooltipControl.DumpLastSeen) then
        out("tooltip control module not loaded")
        return
    end
    if ns.TooltipControl:DumpLastSeen() then
        out("tooltip ids sent to the debug window -- |cffffd200/tenui debug|r to view/copy")
    else
        out("debug window unavailable")
    end
end

local function handleGeneral(rest)
    local sub = (rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if sub ~= "debug" then
        out("usage: |cffffd200/tenui general debug|r")
        return
    end

    if not ns.savedVarsReady then
        out("saved variables not ready")
        return
    end

    local p = ns:GetProfile()
    local g = p and p.modules and p.modules.General
    local function flag(t) return (t and t.enabled == true) and "ON" or "off" end

    local lines = {}
    lines[#lines + 1] = "[General/QoL] enabled-state summary:"
    if not g then
        lines[#lines + 1] = "  (General branch not seeded yet)"
    else
        lines[#lines + 1] = ("  combatAlerts    : %s"):format(flag(g.combatAlerts))
        lines[#lines + 1] = ("  stealthTracking : %s"):format(flag(g.stealthTracking))
        lines[#lines + 1] = ("  tooltipControl  : %s"):format(flag(g.tooltipControl))
        lines[#lines + 1] = ("  classReminders  : %s"):format(flag(g.classReminders))
        lines[#lines + 1] = ("  talentReminder  : %s"):format(flag(g.talentReminder))
    end

    if ns.Debug and ns.Debug.Log then
        for i = 1, #lines do ns.Debug:Log("%s", lines[i]) end
        if ns.Debug.Show then ns.Debug:Show() end
        out("general/QoL summary sent to the debug window -- |cffffd200/tenui debug|r to view/copy")
    else
        for i = 1, #lines do out(lines[i]) end
    end
end

local function parseOnOff(s)
    s = (s or ""):lower():gsub("%s+", "")
    if s == "on" or s == "enable" or s == "enabled" or s == "1" or s == "true" then
        return true
    elseif s == "off" or s == "disable" or s == "disabled" or s == "0" or s == "false" then
        return false
    end
    return nil
end

local function handleAuras(rest)
    local Auras = ns.Auras
    local sub, subRest = (rest or ""):match("^(%S*)%s*(.-)$")
    sub = (sub or ""):lower()

    if sub == "" then
        if not Auras then out("auras module not registered") return end
        local scope = Auras.GetCurrentScopeKey and Auras:GetCurrentScopeKey() or "?"
        local iconsOn  = Auras.IsDisplayEnabled and Auras:IsDisplayEnabled("icons")
        local barsOn   = Auras.IsDisplayEnabled and Auras:IsDisplayEnabled("bars")
        local iconCnt  = Auras.GetActiveCount and Auras:GetActiveCount("icons") or 0
        local barCnt   = Auras.GetActiveCount and Auras:GetActiveCount("bars") or 0
        out(("auras  scope=|cffffd200%s|r"):format(tostring(scope)))
        out(("  icons: |cffffd200%s|r  active=|cffffd200%d|r  (TrackedIcon anchor)")
            :format(iconsOn and "on" or "off", iconCnt))
        out(("  bars : |cffffd200%s|r  active=|cffffd200%d|r  (TrackedBars anchor)")
            :format(barsOn and "on" or "off", barCnt))
        local pOn = Auras.IsPandemicEnabled and Auras:IsPandemicEnabled()
        local pThr = Auras.GetPandemicThreshold and Auras:GetPandemicThreshold() or 0.30
        out(("  pandemic glow: |cffffd200%s|r  threshold=|cffffd200%d%%|r"):format(
            pOn and "on" or "off", math.floor(pThr * 100 + 0.5)))
        local fvp = Auras.GetForceViewerPopulated and Auras:GetForceViewerPopulated()
        out(("  forceViewerPopulated: |cffffd200%s|r  (in-combat target-debuff first-detect; default off)")
            :format(fvp and "on" or "off"))
        local rch = Auras.GetRespectCDMHidden and Auras:GetRespectCDMHidden()
        out(("  respectCDMHidden: |cffffd200%s|r  (hide CDM HideByDefault/disabled cooldowns; default off)")
            :format(rch and "on" or "off"))
        if Auras.GetLowTimeTextConfig then
            local ltEn, ltThr = Auras:GetLowTimeTextConfig()
            out(("  lowTimeText (timer numbers): |cffffd200%s|r  threshold=|cffffd200%gs|r  (icons + bars; default off)")
                :format(ltEn and "on" or "off", ltThr))
        end
        out("  the mirror is automatic -- it shows whatever the Blizzard CDM aura viewers track.")
        out("  |cffffd200/tenui auras icons on|off|r  |cffffd200/tenui auras bars on|off|r  |cffffd200/tenui auras rescan|r  |cffffd200/tenui auras reset|r  |cffffd200/tenui auras pandemic ...|r")
        out("  |cffffd200/tenui auras active|r  -- dump per-entry active-detection breakdown to the debug window")
        return
    end

    if sub == "icons" or sub == "bars" then
        if not Auras then out("auras module not registered") return end
        local want = parseOnOff(subRest)
        if want == nil then
            out(("usage: |cffffd200/tenui auras %s on|r or |cffffd200/tenui auras %s off|r")
                :format(sub, sub))
            return
        end
        local ok, err = Auras:SetDisplayEnabled(sub, want)
        if ok then
            out(("auras %s display -> |cffffd200%s|r"):format(sub, want and "on" or "off"))
        else
            out("could not toggle " .. sub .. " display: " .. tostring(err))
        end
        return
    end

    if sub == "rescan" then
        if not Auras then out("auras module not registered") return end
        if Auras.Rescan then Auras:Rescan() end
        local iconCnt = Auras.GetActiveCount and Auras:GetActiveCount("icons") or 0
        local barCnt  = Auras.GetActiveCount and Auras:GetActiveCount("bars") or 0
        out(("auras rescanned -- icons=%d bars=%d active mirrored"):format(iconCnt, barCnt))
        return
    end

    if sub == "map" then
        if not Auras then out("auras module not registered") return end
        if not Auras.GetViewerAuraMapStats then
            out("viewer-aura map helpers not loaded (Auras.lua out of date)")
            return
        end
        local single, multi, mapSingle, mapMulti = Auras:GetViewerAuraMapStats()
        out(("auras map: |cffffd200%d|r keys, |cffffd200%d|r multi-keys"):format(single, multi))
        local sids = {}
        for sid in pairs(mapSingle) do sids[#sids + 1] = sid end
        table.sort(sids)
        local sampleN = math.min(5, #sids)
        for i = 1, sampleN do
            local sid = sids[i]
            local child = mapSingle[sid]
            local cdInfo = type(child) == "table" and child.cooldownInfo or nil
            local parent = type(child) == "table" and child.GetParent and child:GetParent()
            local parentName = parent and parent.GetName and parent:GetName() or "?"
            local base = cdInfo and cdInfo.spellID or "?"
            out(("  [%d] spellID=%s base=%s parent=%s"):format(i, tostring(sid), tostring(base), tostring(parentName)))
        end
        if #sids == 0 then
            out("  (no entries -- is the Blizzard CDM addon loaded? try after PLAYER_ENTERING_WORLD)")
        end
        return
    end

    if sub == "reset" then
        local mod = ns:GetModule("Auras")
        if not mod then out("auras module not registered") return end
        local profile = ns:GetProfile()
        profile.modules = profile.modules or {}
        profile.modules.Auras = nil
        ns:DisableModule("Auras")
        ns:EnableModule("Auras")
        out("auras module reset to defaults")
        return
    end

    if sub == "unsuppress" then
        if not Auras then out("auras module not registered") return end
        if Auras.UnsuppressNativeViewers then
            Auras:UnsuppressNativeViewers()
            out("native CDM aura viewers restored (alpha=1)")
        else
            out("auras suppression helpers not loaded")
        end
        return
    end

    if sub == "suppress" then
        if not Auras then out("auras module not registered") return end
        if Auras.SuppressNativeViewers then
            Auras:SuppressNativeViewers()
            out("native CDM aura viewers hidden (alpha=0)")
        else
            out("auras suppression helpers not loaded")
        end
        return
    end

    if sub == "pandemic" then
        if not Auras then out("auras module not registered") return end
        local pSub, pRest = (subRest or ""):match("^(%S*)%s*(.-)$")
        pSub = (pSub or ""):lower()

        if pSub == "" then
            local enabled = Auras.IsPandemicEnabled and Auras:IsPandemicEnabled()
            local thr = Auras.GetPandemicThreshold and Auras:GetPandemicThreshold() or 0.30
            out(("auras pandemic: |cffffd200%s|r  threshold=|cffffd200%d%%|r"):format(
                enabled and "on" or "off", math.floor(thr * 100 + 0.5)))
            out("  |cffffd200/tenui auras pandemic on|off|r  |cffffd200/tenui auras pandemic threshold <0..100>|r  |cffffd200/tenui auras pandemic dump|r")
            return
        end

        local want = parseOnOff(pSub)
        if want ~= nil then
            if not Auras.SetPandemicEnabled then
                out("pandemic helpers not loaded (Auras.lua out of date)")
                return
            end
            local ok, err = Auras:SetPandemicEnabled(want)
            if ok then
                out(("auras pandemic glow -> |cffffd200%s|r"):format(want and "on" or "off"))
            else
                out("could not toggle pandemic: " .. tostring(err))
            end
            return
        end

        if pSub == "threshold" then
            if not Auras.SetPandemicThreshold then
                out("pandemic helpers not loaded (Auras.lua out of date)")
                return
            end
            local n = tonumber((pRest or ""):match("(%-?%d+%.?%d*)"))
            if not n then
                out("usage: |cffffd200/tenui auras pandemic threshold <0..100>|r (percent) or 0..1 fraction")
                return
            end
            local ok, applied = Auras:SetPandemicThreshold(n)
            if ok then
                out(("auras pandemic threshold -> |cffffd200%d%%|r"):format(
                    math.floor((applied or 0) * 100 + 0.5)))
            else
                out("could not set threshold: " .. tostring(applied))
            end
            return
        end

        if pSub == "dump" then
            if not Auras.DumpPandemicState then
                out("pandemic helpers not loaded (Auras.lua out of date)")
                return
            end
            local rows = Auras:DumpPandemicState() or {}
            local pandemicEnabled = Auras.IsPandemicEnabled and Auras:IsPandemicEnabled()
            local disabledNote = pandemicEnabled and "" or " |cffaaaaaa(disabled -- see Phase 9 plan)|r"
            if #rows == 0 then
                out("auras pandemic dump: |cffffd200no state|r (no live BuffBar auras tracked)"
                    .. disabledNote)
                return
            end
            out(("auras pandemic dump: |cffffd200%d|r entries (icon + bar)%s"):format(
                #rows, disabledNote))
            for i = 1, #rows do
                local r = rows[i]
                local pctStr = (r.pct and ("%.1f%%"):format(r.pct * 100)) or "?"
                local cls = r.classification
                local tag
                if cls == "only" then tag = "|cff66ccff[only]|r"
                elseif cls == "skip" then tag = "|cffcc6666[skip]|r"
                elseif cls == "default-reject" then tag = "|cffaaaaaa[default-filter:reject]|r"
                elseif cls == "default-pass" then tag = "|cff66ff66[ok]|r"
                else tag = "[?]" end
                local bizStr = (r.bizPandemic and "|cff66ff66YES|r")
                    or (r.bizPandemic == false and "no") or "?"
                local srcStr = r.source or "?"
                local srcColored
                if srcStr == "blizzard-icon" then
                    srcColored = "|cff66ff66blizzard-icon|r"
                elseif srcStr == "duration-percent" then
                    srcColored = "|cff66ccffduration-percent|r"
                elseif srcStr == "secret-visual" then
                    srcColored = "|cffffd200secret-visual|r"
                else
                    srcColored = "|cffaaaaaa" .. srcStr .. "|r"
                end
                local secretStr = (r.durHasSecret == true and "|cffffd200yes|r")
                    or (r.durHasSecret == false and "no") or "?"
                out(("  %s [%s] cdID=%s spellID=%s pct=%s inWindow=%s biz=%s source=%s durSecret=%s supDelta=%.2fs"):format(
                    tag, tostring(r.kind or "?"),
                    tostring(r.cdID), tostring(r.spellID), pctStr,
                    tostring(r.inWindow), bizStr, srcColored, secretStr,
                    r.suppressedDelta or 0))
            end
            return
        end

        if pSub == "probe" then
            if not Auras.PandemicProbe then
                out("pandemic probe not loaded (Auras.lua out of date)")
                return
            end
            local n = tonumber((pRest or ""):match("(%d+)"))
            if not n then
                out("usage: |cffffd200/tenui auras pandemic probe <cdID>|r")
                out("hint: run |cffffd200/tenui auras pandemic dump|r to list cdIDs")
                return
            end
            local lines, err = Auras:PandemicProbe(n)
            if not lines then
                out("probe failed: " .. tostring(err))
                return
            end
            for i = 1, #lines do out(lines[i]) end
            return
        end

        if pSub == "skip" then
            if not Auras.AddPandemicSkip then
                out("pandemic helpers not loaded (Auras.lua out of date)")
                return
            end
            local n = tonumber((pRest or ""):match("(%d+)"))
            if not n then
                out("usage: |cffffd200/tenui auras pandemic skip <cdID>|r")
                return
            end
            local ok, err = Auras:AddPandemicSkip(n)
            if ok then
                out(("auras pandemic skip + cdID=|cffffd200%d|r (will never glow)"):format(n))
            else
                out("could not add to skip: " .. tostring(err))
            end
            return
        end

        if pSub == "unskip" then
            if not Auras.RemovePandemicSkip then
                out("pandemic helpers not loaded (Auras.lua out of date)")
                return
            end
            local n = tonumber((pRest or ""):match("(%d+)"))
            if not n then
                out("usage: |cffffd200/tenui auras pandemic unskip <cdID>|r")
                return
            end
            local ok, err = Auras:RemovePandemicSkip(n)
            if ok then
                out(("auras pandemic skip - cdID=|cffffd200%d|r"):format(n))
            else
                out("could not remove from skip: " .. tostring(err))
            end
            return
        end

        if pSub == "only" then
            if not Auras.AddPandemicOnly then
                out("pandemic helpers not loaded (Auras.lua out of date)")
                return
            end
            local n = tonumber((pRest or ""):match("(%d+)"))
            if not n then
                out("usage: |cffffd200/tenui auras pandemic only <cdID>|r")
                return
            end
            local ok, err = Auras:AddPandemicOnly(n)
            if ok then
                out(("auras pandemic only + cdID=|cffffd200%d|r (whitelist mode active)"):format(n))
            else
                out("could not add to only: " .. tostring(err))
            end
            return
        end

        if pSub == "unonly" then
            if not Auras.RemovePandemicOnly then
                out("pandemic helpers not loaded (Auras.lua out of date)")
                return
            end
            local n = tonumber((pRest or ""):match("(%d+)"))
            if not n then
                out("usage: |cffffd200/tenui auras pandemic unonly <cdID>|r")
                return
            end
            local ok, err = Auras:RemovePandemicOnly(n)
            if ok then
                out(("auras pandemic only - cdID=|cffffd200%d|r"):format(n))
            else
                out("could not remove from only: " .. tostring(err))
            end
            return
        end

        if pSub == "listfilters" then
            if not Auras.GetPandemicFilters then
                out("pandemic helpers not loaded (Auras.lua out of date)")
                return
            end
            local skipList, onlyList = Auras:GetPandemicFilters()
            out(("auras pandemic filters: skip=|cffffd200%d|r  only=|cffffd200%d|r"):format(
                #skipList, #onlyList))
            if #onlyList > 0 then
                out("  |cff66ccffonly|r (whitelist mode active -- ONLY these glow):")
                for i = 1, #onlyList do out(("    cdID=%d"):format(onlyList[i])) end
            end
            if #skipList > 0 then
                out("  |cffcc6666skip|r (never glow):")
                for i = 1, #skipList do out(("    cdID=%d"):format(skipList[i])) end
            end
            if #skipList == 0 and #onlyList == 0 then
                out("  (default filter active: glow ONLY target HARMFUL auras)")
            end
            return
        end

        out("usage: |cffffd200/tenui auras pandemic|r [|cffffd200on|off|r | |cffffd200threshold <0..100>|r | |cffffd200dump|r | |cffffd200skip <cdID>|r | |cffffd200unskip <cdID>|r | |cffffd200only <cdID>|r | |cffffd200unonly <cdID>|r | |cffffd200listfilters|r]")
        return
    end

    if sub == "prefer" then
        if not Auras then out("auras module not registered") return end
        if not Auras.SetCrossViewerPrefer then
            out("cross-viewer dedup helpers not loaded (Auras.lua out of date)")
            return
        end
        local arg = (subRest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
        if arg == "" then
            local cur = Auras.GetCrossViewerPrefer and Auras:GetCrossViewerPrefer() or "?"
            out(("auras crossViewerPrefer: |cffffd200%s|r"):format(cur))
            out("  |cffffd200/tenui auras prefer bar|r   -- bar wins on conflict (default)")
            out("  |cffffd200/tenui auras prefer icon|r  -- icon wins on conflict")
            return
        end
        if arg ~= "bar" and arg ~= "icon" then
            out("usage: |cffffd200/tenui auras prefer bar|icon|r")
            return
        end
        local ok, err = Auras:SetCrossViewerPrefer(arg)
        if ok then
            out(("auras crossViewerPrefer -> |cffffd200%s|r"):format(arg))
        else
            out("could not set prefer: " .. tostring(err))
        end
        return
    end

    if sub == "forceviewer" then
        if not Auras then out("auras module not registered") return end
        if not Auras.SetForceViewerPopulated then
            out("forceviewer helpers not loaded (Auras.lua out of date)")
            return
        end
        local arg = (subRest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
        if arg == "" then
            local cur = Auras.GetForceViewerPopulated and Auras:GetForceViewerPopulated()
            out(("auras forceViewerPopulated: |cffffd200%s|r"):format(cur and "on" or "off"))
            out("  on  -- keep Blizzard CDM viewer populated (invisible) so in-combat")
            out("         TARGET debuffs first-detect via the viewer engine")
            out("  off -- default; engine spellID-family ticker query is the source of truth")
            out("  |cffffd200/tenui aura forceviewer on|off|toggle|r")
            return
        end
        local want
        if arg == "toggle" then
            local cur = Auras.GetForceViewerPopulated and Auras:GetForceViewerPopulated()
            want = not cur
        else
            want = parseOnOff(arg)
        end
        if want == nil then
            out("usage: |cffffd200/tenui aura forceviewer on|off|toggle|r")
            return
        end
        local ok, changed = Auras:SetForceViewerPopulated(want)
        if ok then
            out(("auras forceViewerPopulated -> |cffffd200%s|r%s"):format(
                want and "on" or "off",
                changed == false and " (no change)" or ""))
            out("  applied live -- no /reload required. The engine query remains the")
            out("  default source; ON only ADDS viewer-detected target debuffs.")
        else
            out("could not set forceviewer: " .. tostring(changed))
        end
        return
    end

    if sub == "respectcdmhidden" then
        if not Auras then out("auras module not registered") return end
        if not Auras.SetRespectCDMHidden then
            out("respectcdmhidden helpers not loaded (Auras.lua out of date)")
            return
        end
        local arg = (subRest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
        if arg == "" then
            local cur = Auras.GetRespectCDMHidden and Auras:GetRespectCDMHidden()
            out(("auras respectCDMHidden: |cffffd200%s|r"):format(cur and "on" or "off"))
            out("  on  -- hide cooldowns Blizzard CDM flags HideByDefault/disabled")
            out("         (match the live Cooldown Manager's rendered subset)")
            out("  off -- default; show the full CDM set including hidden entries")
            out("  |cffffd200/tenui aura respectcdmhidden on|off|toggle|r")
            return
        end
        local want
        if arg == "toggle" then
            local cur = Auras.GetRespectCDMHidden and Auras:GetRespectCDMHidden()
            want = not cur
        else
            want = parseOnOff(arg)
        end
        if want == nil then
            out("usage: |cffffd200/tenui aura respectcdmhidden on|off|toggle|r")
            return
        end
        local ok, changed = Auras:SetRespectCDMHidden(want)
        if ok then
            out(("auras respectCDMHidden -> |cffffd200%s|r%s"):format(
                want and "on" or "off",
                changed == false and " (no change)" or ""))
            out("  applied live -- no /reload required. Catalog rebuilt; display")
            out("  and Options list now reflect the filter.")
        else
            out("could not set respectcdmhidden: " .. tostring(changed))
        end
        return
    end

    if sub == "lowtimedebug" or sub == "lowtimedbg" then
        if not Auras then out("auras module not registered") return end
        if not Auras.GetLowTimeEngineDebug then
            out("lowtime engine debug not loaded (Auras.lua out of date)")
            return
        end
        local d = Auras:GetLowTimeEngineDebug()
        local o = d and d.opts
        out(("auras lowtime ENGINE debug  inCombat=|cffffd200%s|r")
            :format(tostring(d.inCombat)))
        if o then
            out(("  enabled=|cffffd200%s|r  threshold=|cffffd200%g|rs  low=%.2f %.2f %.2f  normal=%.2f %.2f %.2f")
                :format(tostring(o.enabled), o.threshold,
                    o.lowR, o.lowG, o.lowB, o.normalR, o.normalG, o.normalB))
        end
        out(("  _lowTimeCurveFailed (capability latch)=|cffffd200%s|r  _lowTimeCurveGen=|cffffd200%s|r")
            :format(tostring(d.curveFailedLatch), tostring(d.curveGen)))
        local function dumpSlot(label, s)
            if not s then
                out(("  %s: (no active %s recorded this tick)"):format(label, label))
                return
            end
            out(("  %s: enabled=%s thr=%gs inCombat=%s")
                :format(label, tostring(s.enabled), tonumber(s.threshold) or -1, tostring(s.inCombat)))
            out(("    durSrc=|cffffd200%s|r  durPath=|cffffd200%s|r  durErr=%s  fs=%s")
                :format(tostring(s.durSrc), tostring(s.durPath), tostring(s.durErr), tostring(s.fs)))
            out(("    stashType=|cffffd200%s|r  stashSecret=|cffffd200%s|r  evalType=|cffffd200%s|r  evalSecret=|cffffd200%s|r  evalHasMethod=%s")
                :format(tostring(s.stashType), tostring(s.stashSecret),
                    tostring(s.evalType), tostring(s.evalSecret), tostring(s.evalHasMethod)))
            out(("    evalOk=|cffffd200%s|r  evalErr=%s  resultIsTable=%s")
                :format(tostring(s.evalOk), tostring(s.evalErr), tostring(s.resultIsTable)))
            out(("    result.r secret=|cffffd200%s|r  result.a secret=|cffffd200%s|r")
                :format(tostring(s.resultRSecret), tostring(s.resultASecret)))
            out(("    sinkOk=%s textSinkOk=%s fillSinkOk=%s  curveApplied=|cffffd200%s|r")
                :format(tostring(s.sinkOk), tostring(s.textSinkOk),
                    tostring(s.fillSinkOk), tostring(s.curveApplied)))
        end
        dumpSlot("bar", d.bar)
        dumpSlot("icon", d.icon)
        out("  curveApplied=true means the C-side curve color was genuinely written this tick.")
        out("  curveApplied=false -> the OOC text-parse fallback ran (colors only OOC; secret text in combat).")
        out("  Run this OOC AND in combat to compare durPath / evalOk / curveApplied.")
        return
    end

    if sub == "lowtime" then
        if not Auras then out("auras module not registered") return end
        if not Auras.GetLowTimeTextDiagnostic then
            out("lowtime diagnostic not loaded (Auras.lua out of date)")
            return
        end
        local ltArg, ltRest = (subRest or ""):match("^(%S*)%s*(.-)$")
        ltArg = (ltArg or ""):lower()
        if ltArg == "threshold" or ltArg == "thresh" or ltArg == "sec" then
            if not Auras.SetLowTimeTextThreshold then
                out("lowtime config not loaded (Auras.lua out of date)")
                return
            end
            local n = tonumber((ltRest or ""):match("([%d%.]+)"))
            if not n then
                out("usage: |cffffd200/tenui aura lowtime threshold <1..60>|r (seconds)")
                return
            end
            local ok, applied = Auras:SetLowTimeTextThreshold(n)
            if ok then
                out(("auras lowtime threshold -> |cffffd200%gs|r (timer NUMBER + bar FILL; applied live)"):format(applied))
            else
                out("could not set lowtime threshold: " .. tostring(applied))
            end
            return
        end
        if ltArg == "color" then
            if not Auras.SetLowTimeTextLowRGB then
                out("lowtime config not loaded (Auras.lua out of date)")
                return
            end
            local r, g, b = (ltRest or ""):match("([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)")
            if not (r and g and b) then
                out("usage: |cffffd200/tenui aura lowtime color <r> <g> <b>|r (each 0..1)")
                return
            end
            local ok, rr, gg, bb = Auras:SetLowTimeTextLowRGB(r, g, b)
            if ok then
                out(("auras lowtime color -> |cffffd200%.2f %.2f %.2f|r (timer NUMBER + bar FILL; applied live)")
                    :format(rr, gg, bb))
            else
                out("could not set lowtime color: " .. tostring(rr))
            end
            return
        end
        if ltArg ~= "" then
            local want
            if ltArg == "toggle" then
                want = not Auras:GetLowTimeTextEnabled()
            else
                want = parseOnOff(ltArg)
            end
            if want == nil then
                out("usage: |cffffd200/tenui aura lowtime on|off|toggle|r | |cffffd200threshold <N>|r | |cffffd200color <r> <g> <b>|r | (bare = diagnostic)")
                return
            end
            local ok, changed = Auras:SetLowTimeTextEnabled(want)
            if ok then
                out(("auras lowtime -> |cffffd200%s|r%s (timer NUMBER + bar FILL color; applied live)"):format(
                    want and "on" or "off",
                    changed == false and " (no change)" or ""))
            else
                out("could not set lowtime: " .. tostring(changed))
            end
            return
        end
        local d = Auras:GetLowTimeTextDiagnostic()
        local o = d and d.opts
        if not o then out("auras lowtime: no options") return end
        out(("auras lowtime (timer NUMBER + bar FILL color): |cffffd200%s|r  threshold=|cffffd200%g|rs")
            :format(o.enabled and "on" or "off", o.threshold))
        out(("  normal color: |cffffd200%.2f %.2f %.2f %.2f|r")
            :format(o.normalR, o.normalG, o.normalB, o.normalA))
        out(("  low color   : |cffffd200%.2f %.2f %.2f %.2f|r")
            :format(o.lowR, o.lowG, o.lowB, o.lowA))
        if d.bar then
            out(("  first BAR : text=|cffffd200%s|r  parsedSeconds=|cffffd200%s|r  chosen=|cffffd200%s|r")
                :format(tostring(d.bar.text), tostring(d.bar.seconds), tostring(d.bar.color)))
        else
            out("  first BAR : (none active)")
        end
        if d.icon then
            if d.icon.hasFS == false then
                out("  first ICON: (no cooldown FontString reachable on icon widget)")
            else
                out(("  first ICON: text=|cffffd200%s|r  parsedSeconds=|cffffd200%s|r  chosen=|cffffd200%s|r")
                    :format(tostring(d.icon.text), tostring(d.icon.seconds), tostring(d.icon.color)))
            end
        else
            out("  first ICON: (none active)")
        end
        out("  NOTE: this colors the TIMER NUMBER (FontString) on icons AND bars.")
        out("  |cffffd200/tenui aura lowtime on|off|toggle|r")
        out("  |cffffd200/tenui aura lowtime threshold <1..60>|r  -- displayed seconds")
        out("  |cffffd200/tenui aura lowtime color <r> <g> <b>|r  -- low-time NUMBER color (0..1 each)")
        return
    end

    if sub == "barpreview" or sub == "preview" then
        if not Auras then out("auras module not registered") return end
        if not Auras.SetBarPreviewManual then
            out("barpreview not loaded (Auras.lua out of date)")
            return
        end
        local arg, bpRest = (subRest or ""):match("^(%S*)%s*(.-)$")
        arg = (arg or ""):lower()
        if arg == "" then
            local en, count, pcts = Auras:GetBarPreviewStats()
            out(("auras barpreview: |cffffd200%s|r  count=|cffffd200%d|r  lastRemainingFrac=[%s]")
                :format(en and "on" or "off", count, pcts))
            out("  |cffffd200/tenui auras barpreview on|off|r [count 1..3]")
            out("  spawns synthetic DRAINING bars (only when 0 real bars active) through the real render path")
            return
        end
        local want = parseOnOff(arg)
        if want == nil then
            out("usage: |cffffd200/tenui auras barpreview on|off|r [count 1..3]")
            return
        end
        local count = tonumber((bpRest or ""):match("([%d]+)"))
        local ok, msg = Auras:SetBarPreviewManual(want, count)
        if ok then
            out("auras barpreview: |cff00ff00" .. tostring(msg) .. "|r")
        else
            out("auras barpreview: |cffff4040" .. tostring(msg) .. "|r")
        end
        return
    end

    if sub == "lookup" then
        if not Auras then out("auras module not registered") return end
        if not Auras.LookupSpellID then
            out("lookup helper not loaded (Auras.lua out of date)")
            return
        end
        local n = tonumber((subRest or ""):match("(%d+)"))
        if not n then
            out("usage: |cffffd200/tenui auras lookup <spellID>|r")
            return
        end
        local lines, err = Auras:LookupSpellID(n)
        if not lines then
            out("lookup failed: " .. tostring(err))
            return
        end
        for i = 1, #lines do out(lines[i]) end
        return
    end

    if sub == "activeglow" then
        if not Auras then out("auras module not registered") return end
        if not Auras.SetActiveGlowEnabled then
            out("active-glow helpers not loaded (Auras.lua out of date)")
            return
        end
        local want = parseOnOff(subRest)
        if want == nil then
            local iconOn = Auras.IsActiveGlowEnabled and Auras:IsActiveGlowEnabled("icon")
            local barOn  = Auras.IsActiveGlowEnabled and Auras:IsActiveGlowEnabled("bar")
            out(("auras activeglow:  icons=|cffffd200%s|r  bars=|cffffd200%s|r"):format(
                iconOn and "on" or "off", barOn and "on" or "off"))
            out("  |cffffd200/tenui auras activeglow on|off|r")
            return
        end
        local ok, err = Auras:SetActiveGlowEnabled(want, nil)
        if ok then
            out(("auras activeglow -> |cffffd200%s|r (icons + bars)"):format(want and "on" or "off"))
            local iconOn = Auras.IsActiveGlowEnabled and Auras:IsActiveGlowEnabled("icon")
            local barOn  = Auras.IsActiveGlowEnabled and Auras:IsActiveGlowEnabled("bar")
            out(("  read-back: icon=|cffffd200%s|r bar=|cffffd200%s|r"):format(
                iconOn and "on" or "off", barOn and "on" or "off"))
        else
            out("could not toggle activeglow: " .. tostring(err))
        end
        return
    end

    if sub == "glow" then
        if not Auras then out("auras module not registered") return end
        local pSub, pRest = (subRest or ""):match("^(%S*)%s*(.-)$")
        pSub = (pSub or ""):lower()
        if pSub == "dump" then
            if not Auras.DumpGlowDiagnostic then
                out("glow-dump helper not loaded (Auras.lua out of date)")
                return
            end
            local n = tonumber((pRest or ""):match("(%d+)"))
            local lines = Auras:DumpGlowDiagnostic(n)
            for i = 1, #lines do out(lines[i]) end
            return
        end
        out("usage: |cffffd200/tenui auras glow dump|r [N]")
        return
    end

    if sub == "active" then
        if not Auras then out("auras module not registered") return end
        if not Auras.DumpActiveDiagnostic then
            out("active-dump helper not loaded (Auras.lua out of date)")
            return
        end
        local lines = Auras:DumpActiveDiagnostic() or {}
        if ns.Debug and ns.Debug.Log then
            for i = 1, #lines do ns.Debug:Log("%s", lines[i]) end
            if ns.Debug.Show then ns.Debug:Show() end
            out(("active-detection dump (%d lines) sent to the debug window -- |cffffd200/tenui debug|r to view/copy"):format(#lines))
        else
            for i = 1, #lines do out(lines[i]) end
        end
        return
    end

    if sub == "dump" then
        if not Auras then out("auras module not registered") return end
        if not Auras.DumpAuraIdentity then
            out("aura dump helper not loaded (Auras.lua out of date)")
            return
        end
        local lines = Auras:DumpAuraIdentity() or {}
        if ns.Debug and ns.Debug.Log then
            for i = 1, #lines do ns.Debug:Log("%s", lines[i]) end
            if ns.Debug.Show then ns.Debug:Show() end
            out(("aura identity dump (%d lines) sent to the debug window -- |cffffd200/tenui debug|r to view/copy"):format(#lines))
        else
            for i = 1, #lines do out(lines[i]) end
        end
        return
    end

    if sub == "pipeline" then
        if not Auras then out("auras module not registered") return end
        if not Auras.DumpPipeline then
            out("aura pipeline helper not loaded (Auras.lua out of date)")
            return
        end
        local lines = Auras:DumpPipeline() or {}
        if ns.Debug and ns.Debug.Log then
            for i = 1, #lines do ns.Debug:Log("%s", lines[i]) end
            if ns.Debug.Show then ns.Debug:Show() end
            out(("aura pipeline diagnostic (%d lines) sent to the debug window -- |cffffd200/tenui debug|r to view/copy"):format(#lines))
        else
            for i = 1, #lines do out(lines[i]) end
        end
        return
    end

    if sub == "rawset" then
        if not Auras then out("auras module not registered") return end
        if not Auras.DumpRawCategorySet then
            out("rawset helper not loaded (Auras.lua out of date)")
            return
        end
        local lines = Auras:DumpRawCategorySet() or {}
        if ns.Debug and ns.Debug.Log then
            for i = 1, #lines do ns.Debug:Log("%s", lines[i]) end
            if ns.Debug.Show then ns.Debug:Show() end
            out(("raw category-set dump (%d lines) sent to the debug window -- |cffffd200/tenui debug|r to view/copy"):format(#lines))
        else
            for i = 1, #lines do out(lines[i]) end
        end
        return
    end

    if sub == "verifydk" then
        if not Auras then out("auras module not registered") return end
        if not Auras.VerifyDK then
            out("verifydk helper not loaded (Auras.lua out of date)")
            return
        end
        local lines = Auras:VerifyDK() or {}
        if ns.Debug and ns.Debug.Log then
            for i = 1, #lines do ns.Debug:Log("%s", lines[i]) end
            if ns.Debug.Show then ns.Debug:Show() end
            out(("aura verifydk (%d lines) sent to the debug window -- |cffffd200/tenui debug|r to view/copy"):format(#lines))
        else
            for i = 1, #lines do out(lines[i]) end
        end
        return
    end

    if sub == "dedup" then
        if not Auras then out("auras module not registered") return end
        local pSub = (subRest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
        if pSub == "dump" then
            if not Auras.DumpCrossViewerDedup then
                out("dedup-dump helper not loaded (Auras.lua out of date)")
                return
            end
            local lines = Auras:DumpCrossViewerDedup() or {}
            for i = 1, #lines do out(lines[i]) end
            return
        end
        out("usage: |cffffd200/tenui auras dedup dump|r")
        return
    end

    out("usage: |cffffd200/tenui auras|r [|cffffd200icons on|off|r | |cffffd200bars on|off|r | |cffffd200rescan|r | |cffffd200reset|r | |cffffd200unsuppress|r | |cffffd200suppress|r | |cffffd200map|r | |cffffd200active|r | |cffffd200dump|r | |cffffd200pipeline|r | |cffffd200rawset|r | |cffffd200verifydk|r | |cffffd200pandemic ...|r | |cffffd200prefer bar|icon|r | |cffffd200probe on|off|r | |cffffd200lookup <spellID>|r | |cffffd200dedup dump|r | |cffffd200activeglow on|off|r | |cffffd200lowtime on|off|threshold <N>|color <r> <g> <b>|r | |cffffd200barpreview on|off|r [count] | |cffffd200glow dump|r [N]]")
end

local function trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end

local function parseEntryArg(arg)
    arg = trim(arg or "")
    if arg == "" then return nil, "missing entry argument" end

    local tokens = {}
    for tok in arg:gmatch("%S+") do tokens[#tokens + 1] = tok end
    if #tokens == 0 then
        return nil, "missing entry argument"
    end

    local headKind, headIdStr = tokens[1]:match("^([%a]+)%s*:%s*(%d+)$")
    if not headKind or not headIdStr then
        return nil, "bad format (expected spell:<id> or item:<id>)"
    end
    headKind = headKind:lower()
    if headKind ~= "spell" and headKind ~= "item" then
        return nil, "unknown entry type '" .. tostring(headKind) .. "'"
    end
    local headId = tonumber(headIdStr)
    if not headId or headId <= 0 then
        return nil, "bad id '" .. tostring(headIdStr) .. "'"
    end

    local entry = { type = headKind, id = headId }

    for i = 2, #tokens do
        local key, valStr = tokens[i]:match("^([%a]+)%s*:%s*(%w+)$")
        if not key then
            return nil, "bad modifier token '" .. tostring(tokens[i]) .. "'"
        end
        key = key:lower()
        if key == "summon" then
            if headKind ~= "spell" then
                return nil, "summon:<N> only valid for spell entries"
            end
            local n = tonumber(valStr)
            if not n or n <= 0 then
                return nil, "bad summon duration '" .. tostring(valStr) .. "'"
            end
            entry.summonDuration = n
        else
            return nil, "unknown modifier '" .. tostring(key) .. "'"
        end
    end

    return entry
end

local function describeEntry(entry)
    if not entry then return "?" end
    if entry.type == "spell" then
        local name
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, entry.id)
            if ok and type(info) == "table" then name = info.name end
        end
        local suffix = name and (" (" .. name .. ")") or ""
        local sd = tonumber(entry.summonDuration)
        if sd and sd > 0 then
            suffix = suffix .. " [summon:" .. tostring(sd) .. "s]"
        end
        return "spell:" .. tostring(entry.id) .. suffix
    elseif entry.type == "item" then
        local name
        if C_Item and C_Item.GetItemInfo then
            local ok, n = pcall(C_Item.GetItemInfo, entry.id)
            if ok and type(n) == "string" then name = n end
        end
        return "item:" .. tostring(entry.id) .. (name and (" (" .. name .. ")") or "")
    end
    return tostring(entry.type) .. ":" .. tostring(entry.id)
end

local function listValidRows()
    local Bars = ns.Bars
    if not (Bars and Bars.GetRowNames) then return "(Bars module not loaded)" end
    return table.concat(Bars:GetRowNames(), ", ")
end

local function resolveRow(input)
    local Bars = ns.Bars
    if not (Bars and Bars.ResolveRowName) then return nil, "Bars module not loaded" end
    local name = Bars:ResolveRowName(input)
    if not name then
        return nil, "unknown row '" .. tostring(input) .. "'. Valid: " .. listValidRows()
    end
    return name
end

local function currentScopeKey()
    if ns.Bars and ns.Bars.GetCurrentScopeKey then
        return ns.Bars:GetCurrentScopeKey()
    end
    return "?"
end

local function getRowProfileSafe(name)
    if not (ns.Bars and ns.Bars.GetCurrentRows) then
        return { displayed = {}, candidates = {} }
    end
    local rows = ns.Bars:GetCurrentRows() or {}
    rows[name] = rows[name] or { displayed = {}, candidates = {} }
    rows[name].displayed  = rows[name].displayed  or {}
    rows[name].candidates = rows[name].candidates or {}
    return rows[name]
end

local function handleBarsList(rowInput)
    local name, err = resolveRow(rowInput)
    if not name then out(err) return end
    local rp = getRowProfileSafe(name)
    out("Row: |cffffd200" .. name .. "|r (scope=" .. currentScopeKey() .. ")")
    out("  displayed (" .. #rp.displayed .. "):")
    if #rp.displayed == 0 then
        out("    (empty)")
    else
        for i = 1, #rp.displayed do
            out("    " .. i .. ". " .. describeEntry(rp.displayed[i]))
        end
    end
    out("  candidates (" .. #rp.candidates .. "):")
    if #rp.candidates == 0 then
        out("    (empty -- try /tenui bars scan)")
    else
        for i = 1, #rp.candidates do
            out("    " .. i .. ". " .. describeEntry(rp.candidates[i]))
        end
    end
end

local function handleBarsAdd(rowInput, entryArg)
    local name, err = resolveRow(rowInput)
    if not name then out(err) return end
    local entry, perr = parseEntryArg(entryArg)
    if not entry then out("usage: /tenui bars add <row> spell:<id> [summon:<sec>] | item:<id> -- " .. tostring(perr)) return end
    local Bars = ns.Bars
    local ok, why = Bars:AddEntry(name, entry)
    if ok then
        out("added " .. describeEntry(entry) .. " to " .. name)
    else
        out("could not add: " .. tostring(why))
    end
end

local function handleBarsRemove(rowInput, entryArg)
    local name, err = resolveRow(rowInput)
    if not name then out(err) return end
    local entry, perr = parseEntryArg(entryArg)
    if not entry then out("usage: /tenui bars remove <row> spell:<id> | item:<id> -- " .. tostring(perr)) return end
    local Bars = ns.Bars
    local ok, why = Bars:RemoveEntry(name, entry)
    if ok then
        out("removed " .. describeEntry(entry) .. " from " .. name)
    else
        out("could not remove: " .. tostring(why))
    end
end

local function handleBarsScan(rowInput)
    local Bars = ns.Bars
    if not (Bars and Bars.Scanner and Bars.Scanner.CDM) then
        out("Bars module / CDM scanner not loaded")
        return
    end
    if rowInput and rowInput ~= "" then
        local name, err = resolveRow(rowInput)
        if not name then out(err) return end
        local ok, info = Bars.Scanner.CDM:ScanRow(name)
        if ok then
            out("scan " .. name .. ": " .. tostring(info) .. " candidates")
        else
            out("scan " .. name .. " failed: " .. tostring(info))
        end
    else
        local ok, total = Bars.Scanner.CDM:ScanAll()
        if ok then
            out("scan complete: " .. tostring(total) .. " total candidates across rows")
        else
            out("scan failed: " .. tostring(total))
        end
    end
end

local function handleBarsTrinkets(rest)
    local Bars = ns.Bars
    if not (Bars and Bars.Scanner and Bars.Scanner.Trinkets) then
        out("Bars module / Trinkets scanner not loaded")
        return
    end
    local sub = trim((rest or "")):lower()
    if sub == "autoadd" then
        local ok, added = Bars.Scanner.Trinkets:AutoAdd()
        if ok then
            out("trinkets autoadd: added " .. tostring(added) .. " (Trinkets row now has "
                .. #(getRowProfileSafe("Trinkets").displayed) .. " items)")
            local row = Bars:GetRow("Trinkets")
            if row then row:Rebuild() end
        else
            out("trinkets autoadd failed: " .. tostring(added))
        end
        return
    end
    out("usage: /tenui bars trinkets autoadd")
end

local function handleBarsClear(rowInput)
    local name, err = resolveRow(rowInput)
    if not name then out(err) return end
    local Bars = ns.Bars
    local ok, why = Bars:ClearDisplayed(name)
    if ok then
        out("cleared displayed entries for " .. name)
    else
        out("could not clear: " .. tostring(why))
    end
end

local function handleBarsReset()
    local mod = ns:GetModule("Bars")
    if not mod then
        out("bars module not registered")
        return
    end
    local profile = ns:GetProfile()
    profile.modules = profile.modules or {}
    profile.modules.Bars = nil
    ns:DisableModule("Bars")
    ns:EnableModule("Bars")
    out("bars module reset to defaults")
end

local function handleBarsOverview()
    local Bars = ns.Bars
    if not Bars then out("Bars module not loaded") return end
    out("Bars rows (scope=" .. currentScopeKey() .. "):")
    for _, name in ipairs(Bars:GetRowNames()) do
        local rp = getRowProfileSafe(name)
        out(("  %-20s displayed=%d  candidates=%d"):format(name, #rp.displayed, #rp.candidates))
    end
    out("Use |cffffd200/tenui bars list <row>|r to inspect entries.")
end

local function handleBarsScope()
    out("current Bars scope: |cffffd200" .. currentScopeKey() .. "|r")
end

local function handleBarsScopes()
    local Bars = ns.Bars
    if not (Bars and Bars.GetScopes) then
        out("Bars module not loaded")
        return
    end
    local scopes = Bars:GetScopes()
    local current = currentScopeKey()
    if #scopes == 0 then
        out("no saved Bars scopes yet (current scope: " .. current .. ")")
        return
    end
    out("saved Bars scopes (" .. #scopes .. "):")
    for _, key in ipairs(scopes) do
        local marker = (key == current) and "  |cffffd200*|r " or "    "
        out(marker .. key)
    end
    out("(|cffffd200*|r = current scope)")
end

local function handleBars(rest)
    rest = trim(rest or "")
    if rest == "" then
        handleBarsOverview()
        return
    end
    local sub, subRest = rest:match("^(%S+)%s*(.-)$")
    sub = (sub or ""):lower()
    subRest = subRest or ""

    if sub == "list" then
        handleBarsList(trim(subRest))
        return
    end
    if sub == "add" then
        local rowName, entryArg = subRest:match("^(%S+)%s+(.+)$")
        if not rowName then
            out("usage: /tenui bars add <row> spell:<id> | item:<id>")
            return
        end
        handleBarsAdd(rowName, entryArg)
        return
    end
    if sub == "remove" or sub == "rm" then
        local rowName, entryArg = subRest:match("^(%S+)%s+(.+)$")
        if not rowName then
            out("usage: /tenui bars remove <row> spell:<id> | item:<id>")
            return
        end
        handleBarsRemove(rowName, entryArg)
        return
    end
    if sub == "scan" then
        handleBarsScan(trim(subRest))
        return
    end
    if sub == "trinkets" then
        handleBarsTrinkets(subRest)
        return
    end
    if sub == "clear" then
        handleBarsClear(trim(subRest))
        return
    end
    if sub == "reset" then
        handleBarsReset()
        return
    end
    if sub == "scope" then
        handleBarsScope()
        return
    end
    if sub == "scopes" then
        handleBarsScopes()
        return
    end
    if sub == "procdump" then
        local Bars = ns.Bars
        if not (Bars and Bars.ProcDiagnostic) then
            out("Bars module not loaded")
            return
        end
        local n = Bars:ProcDiagnostic()
        out(("procdump: %d icon(s) reported to the debug window -- |cffffd200/tenui debug|r to view"):format(n or 0))
        return
    end
    out("unknown bars subcommand: |cffff7070" .. sub .. "|r. See |cffffd200/tenui help|r.")
end

local function handleTrinkets(rest)
    local Bars = ns.Bars
    if not (Bars and Bars.Scanner and Bars.Scanner.Trinkets) then
        out("Trinkets scanner not loaded (Bars module disabled?)")
        return
    end
    local scanner = Bars.Scanner.Trinkets
    local sub = trim(rest or ""):lower()

    if sub == "rescan" or sub == "scan" or sub == "sync" then
        if not scanner.Sync then
            out("Trinkets scanner does not expose Sync (loaded an older module?)")
            return
        end
        local ok, info = scanner:Sync()
        if ok then
            out(("trinkets rescan: %s"):format(tostring(info)))
        else
            out("trinkets rescan failed: " .. tostring(info))
        end
    elseif sub ~= "" then
        out("usage: |cffffd200/tenui trinkets|r [|cffffd200rescan|r]")
        return
    end

    if not scanner.GetStatus then
        out("Trinkets scanner does not expose GetStatus (loaded an older module?)")
        return
    end
    local status = scanner:GetStatus()
    local profile = ns:GetProfile()
    local autoMode = true
    if profile and profile.modules and profile.modules.Bars then
        autoMode = profile.modules.Bars.autoTrinkets ~= false
    end
    out(("Trinkets (auto-sync=%s):"):format(autoMode and "|cff80ff80on|r" or "|cffff8080off|r"))
    if #status == 0 then
        out("  no on-use trinkets equipped (slot 13/14 empty or both passive)")
        return
    end
    for i = 1, #status do
        local e = status[i]
        local cdStr
        if e.ready == true then
            cdStr = "|cff80ff80ready|r"
        elseif type(e.remaining) == "number" and e.remaining > 0 then
            cdStr = ("|cffffd200%.1fs|r"):format(e.remaining)
        elseif e.cdStart ~= nil and e.cdDuration ~= nil then
            cdStr = "|cffa0a0a0(opaque/secret)|r"
        else
            cdStr = "|cffa0a0a0n/a|r"
        end
        out(("  slot=%d itemID=%d spellID=%d cd=%s"):format(
            tonumber(e.slot) or 0,
            tonumber(e.itemID) or 0,
            tonumber(e.spellID) or 0,
            cdStr))
    end
end

local function listAnchorNames()
    local names = {}
    if ns.anchors then
        for k in pairs(ns.anchors) do
            names[#names + 1] = k
        end
    end
    table.sort(names)
    return names
end

local function handleResetAnchor(rest)
    local name = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        out("usage: |cffffd200/tenui reset anchor <name>|r")
        out("valid names: " .. table.concat(listAnchorNames(), ", "))
        return
    end
    local match
    for k in pairs(ns.anchors or {}) do
        if k:lower() == name:lower() then
            match = k
            break
        end
    end
    if not match then
        out("unknown anchor: |cffff7070" .. name .. "|r")
        out("valid names: " .. table.concat(listAnchorNames(), ", "))
        return
    end
    local ok = ns:ResetAnchor(match)
    if ok then
        out("anchor '" .. match .. "' reset to default")
    else
        out("could not reset anchor '" .. match .. "' (saved vars not ready?)")
    end
end

local function handleAnchorReset(rest)
    if not ns.savedVarsReady then
        out("saved variables not ready")
        return
    end
    local name = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        if not (ns.Anchors and ns.Anchors.ForceResetTracked) then
            out("anchor system not ready")
            return
        end
        local ok = ns.Anchors:ForceResetTracked(nil)
        if ok then
            out("TrackedIcon -> 320x40 and TrackedBars -> 320x24 force-reset")
            out("If icons still look wrong, type |cffffd200/tenui anchor list|r to verify.")
        else
            out("could not force-reset (saved vars not ready?)")
        end
        return
    end
    local match
    for k in pairs(ns.anchors or {}) do
        if k:lower() == name:lower() then
            match = k
            break
        end
    end
    if not match then
        out("unknown anchor: |cffff7070" .. name .. "|r")
        out("valid names: " .. table.concat(listAnchorNames(), ", "))
        return
    end
    if not (ns.Anchors and ns.Anchors.ForceResetTracked) then
        out("anchor system not ready")
        return
    end
    local ok = ns.Anchors:ForceResetTracked(match)
    if ok then
        out(("anchor '%s' force-reset to its default geometry"):format(match))
    else
        out(("could not force-reset '%s'"):format(match))
    end
end

local function handleAnchorList()
    if not (ns.Anchors and ns.Anchors.Inspect) then
        out("anchor system not ready")
        return
    end
    local rows = ns.Anchors:Inspect()
    if #rows == 0 then
        out("no anchors registered")
        return
    end
    out(("anchors (%d):"):format(#rows))
    local saveMap = (ns.db and ns.db.debug and type(ns.db.debug._last_drag_save) == "table")
        and ns.db.debug._last_drag_save or nil
    local loadMap = (ns.db and ns.db.debug and type(ns.db.debug._last_load) == "table")
        and ns.db.debug._last_load or nil
    for i = 1, #rows do
        local r = rows[i]
        out(("  |cffffd200%s|r  saved=%sx%s @ (%s,%s)  live=%sx%s"):format(
            r.name,
            tostring(r.savedW), tostring(r.savedH),
            tostring(r.x), tostring(r.y),
            r.liveW and string.format("%.1f", r.liveW) or "nil",
            r.liveH and string.format("%.1f", r.liveH) or "nil"))
        if saveMap and saveMap[r.name] then
            out("    last save: " .. tostring(saveMap[r.name]))
        end
        if loadMap and loadMap[r.name] then
            out("    last load: " .. tostring(loadMap[r.name]))
        end
    end
    if ns.db and ns.db.debug then
        if type(ns.db.debug._last_drag_save) == "string" then
            out("last drag-save (legacy): " .. tostring(ns.db.debug._last_drag_save))
        end
        if ns.db.debug._last_slash_setpos then
            out("last slash-set: " .. tostring(ns.db.debug._last_slash_setpos))
        end
        if ns.db.debug._last_force_reset then
            out("last force-reset: " .. tostring(ns.db.debug._last_force_reset))
        end
        if ns.db.debug._last_slash_reset then
            out("last slash-reset: " .. tostring(ns.db.debug._last_slash_reset))
        end
        if ns.db.debug._migration_trace then
            out("migration trace: " .. tostring(ns.db.debug._migration_trace))
        end
    end
end

local function handleAnchorHistory(rest)
    if not (ns.db and ns.db.debug) then
        out("saved variables not ready")
        return
    end
    local hist = ns.db.debug._anchor_history
    if type(hist) ~= "table" or #hist == 0 then
        out("no anchor history recorded yet (drag an anchor or /reload to populate)")
        return
    end
    local filter = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local matchName
    if filter ~= "" then
        for k in pairs(ns.anchors or {}) do
            if k:lower() == filter:lower() then
                matchName = k
                break
            end
        end
        if not matchName then
            out("unknown anchor: |cffff7070" .. filter .. "|r")
            return
        end
    end
    local total = #hist
    out(("anchor history (%d entries%s):"):format(total,
        matchName and (" filtered to " .. matchName) or ""))
    local shown = 0
    local CAP = 40
    local startIdx = math.max(1, total - CAP + 1)
    for i = startIdx, total do
        local e = hist[i]
        if type(e) == "table" then
            if not matchName or e.name == matchName then
                local extras = {}
                if e.point ~= nil then extras[#extras + 1] = "p=" .. tostring(e.point) end
                if e.x     ~= nil then extras[#extras + 1] = "x=" .. tostring(e.x) end
                if e.y     ~= nil then extras[#extras + 1] = "y=" .. tostring(e.y) end
                if e.w     ~= nil then extras[#extras + 1] = "w=" .. tostring(e.w) end
                if e.h     ~= nil then extras[#extras + 1] = "h=" .. tostring(e.h) end
                if e.corrupt then extras[#extras + 1] = "CORRUPT" end
                if e.note  ~= nil then extras[#extras + 1] = "note=" .. tostring(e.note) end
                out(("  %s  |cffffd200%-9s|r %-20s  %s"):format(
                    tostring(e.at or "?"),
                    tostring(e.event or "?"),
                    tostring(e.name or "?"),
                    table.concat(extras, " ")))
                shown = shown + 1
            end
        end
    end
    if shown == 0 then
        out("(no matching entries in last " .. tostring(CAP) .. ")")
    end
    out("(/dump TenUIDB.debug._anchor_history dumps full ring)")
end

local function handleAnchorSet(rest)
    if not ns.savedVarsReady then
        out("saved variables not ready")
        return
    end
    local name, xs, ys = rest:match("^(%S+)%s+(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)%s*$")
    if not (name and xs and ys) then
        out("usage: |cffffd200/tenui anchor set <name> <x> <y>|r")
        out("example: |cffffd200/tenui anchor set TrackedIcon 0 240|r")
        return
    end
    local x = tonumber(xs)
    local y = tonumber(ys)
    if not (x and y) then
        out("invalid x/y -- must be numbers")
        return
    end
    local match
    for k in pairs(ns.anchors or {}) do
        if k:lower() == name:lower() then
            match = k
            break
        end
    end
    if not match then
        out("unknown anchor: |cffff7070" .. name .. "|r")
        out("valid names: " .. table.concat(listAnchorNames(), ", "))
        return
    end
    if not (ns.Anchors and ns.Anchors.SetPositionDirect) then
        out("anchor system not ready")
        return
    end
    local ok, err = ns.Anchors:SetPositionDirect(match, x, y)
    if ok then
        out(("anchor '%s' position set to (%d, %d)"):format(match,
            math.floor(x + 0.5), math.floor(y + 0.5)))
        out("Run |cffffd200/reload|r then |cffffd200/tenui anchor list|r to verify it survived.")
    else
        out("could not set position: " .. tostring(err))
    end
end

local function handleAnchor(rest)
    local sub, subRest = rest:match("^(%S*)%s*(.-)$")
    sub = (sub or ""):lower()
    subRest = subRest or ""
    if sub == "" or sub == "help" then
        out("usage: |cffffd200/tenui anchor reset|r [name]   -- emergency force-reset")
        out("       |cffffd200/tenui anchor list|r           -- show live+saved sizes (+ per-anchor save/load sentinels)")
        out("       |cffffd200/tenui anchor set <name> <x> <y>|r -- write saved x/y directly")
        out("       |cffffd200/tenui anchor history|r [name] -- dump persistent SAVE/LOAD/APPLY history ring")
        return
    end
    if sub == "reset" then
        handleAnchorReset(subRest)
        return
    end
    if sub == "list" then
        handleAnchorList()
        return
    end
    if sub == "set" then
        handleAnchorSet(subRest)
        return
    end
    if sub == "history" then
        handleAnchorHistory(subRest)
        return
    end
    out("unknown anchor subcommand: |cffff7070" .. sub .. "|r. See |cffffd200/tenui help|r.")
end

local function handler(msg)
    msg = tostring(msg or "")
    msg = msg:gsub("^%s+", ""):gsub("%s+$", "")

    if msg == "" then
        out("v" .. tostring(ns.version) .. " loaded. Type |cffffd200/tenui help|r.")
        return
    end

    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = (cmd or ""):lower()
    rest = rest or ""

    if cmd == "help" or cmd == "?" then
        showHelp()
        return
    end

    if cmd == "version" then
        out("v" .. tostring(ns.version))
        return
    end

    if cmd == "debug" then
        local subTok, subRest = rest:match("^(%S*)%s*(.-)$")
        local sub = (subTok or ""):lower()
        subRest = subRest or ""

        if sub == "clear" then
            if ns.Debug and ns.Debug.Clear then
                ns.Debug:Clear()
                out("debug log cleared")
            else
                out("debug system not ready")
            end
            return
        end

        if sub == "pause" then
            if ns.Debug and ns.Debug.Pause then
                ns.Debug:Pause()
                out("Debug paused (new lines no longer appended). Use |cffffd200/tenui debug resume|r to continue.")
            else
                out("debug system not ready")
            end
            return
        end

        if sub == "resume" then
            if ns.Debug and ns.Debug.Resume then
                ns.Debug:Resume()
                out("Debug resumed (appending + display updates re-enabled).")
            else
                out("debug system not ready")
            end
            return
        end

        local function toggleChannel(tbl, argStr)
            if not (ns.db and ns.db.debug) then
                out("saved variables not ready")
                return
            end
            local modTok, stateTok = (argStr or ""):match("^(%S*)%s*(%S*)$")
            local mod = (modTok or ""):lower()
            local stateArg = (stateTok or ""):lower()
            if mod == "" then
                out(("usage: |cffffd200/tenui debug %s <module>|r [|cffffd200off|r]  (e.g. |cffffd200/tenui debug %s auras|r)")
                    :format(tbl, tbl))
                return
            end
            ns.db.debug[tbl] = ns.db.debug[tbl] or {}
            local want
            if stateArg == "off" or stateArg == "0" or stateArg == "false" then
                want = false
            elseif stateArg == "on" or stateArg == "1" or stateArg == "true" then
                want = true
            else
                want = not (ns.db.debug[tbl][mod] and true or false)
            end
            ns.db.debug[tbl][mod] = want or nil
            out(("debug %s %s -> |cffffd200%s|r"):format(tbl, mod, want and "on" or "off"))
        end

        if sub == "verbose" then
            toggleChannel("verbose", subRest)
            return
        end

        if sub == "trace" then
            toggleChannel("trace", subRest)
            return
        end

        if sub == "chat" then
            if not (ns.db and ns.db.debug) then
                out("saved variables not ready")
                return
            end
            local arg = (subRest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
            if arg == "on" or arg == "1" or arg == "true" then
                ns.db.debug.chat = true
            elseif arg == "off" or arg == "0" or arg == "false" then
                ns.db.debug.chat = false
            elseif arg == "" then
                out(("debug chat mirror: |cffffd200%s|r"):format(ns.db.debug.chat and "on" or "off"))
                out("usage: |cffffd200/tenui debug chat on|off|r")
                return
            else
                out("usage: |cffffd200/tenui debug chat on|off|r")
                return
            end
            out(("debug chat mirror -> |cffffd200%s|r"):format(ns.db.debug.chat and "on" or "off"))
            return
        end

        if sub == "status" then
            if not (ns.db and ns.db.debug) then
                out("saved variables not ready")
                return
            end
            local d = ns.db.debug
            local paused = ns.Debug and ns.Debug.IsPaused and ns.Debug:IsPaused()
            out("debug status:")
            out(("  enabled=|cffffd200%s|r  paused=|cffffd200%s|r  chat=|cffffd200%s|r  maxLines=|cffffd200%s|r")
                :format(tostring(d.enabled), paused and "yes" or "no",
                    d.chat and "on" or "off", tostring(d.maxLines)))
            local function onList(t)
                local names = {}
                if type(t) == "table" then
                    for k, v in pairs(t) do
                        if v then names[#names + 1] = tostring(k) end
                    end
                end
                table.sort(names)
                return #names > 0 and table.concat(names, ", ") or "(none)"
            end
            out(("  verbose: |cffffd200%s|r"):format(onList(d.verbose)))
            out(("  trace:   |cffffd200%s|r"):format(onList(d.trace)))
            return
        end

        if ns.Debug and ns.Debug.Toggle then
            ns.Debug:Toggle()
        else
            out("debug system not ready")
        end
        return
    end

    if cmd == "lock" then
        if not ns.db then
            out("saved variables not ready")
            return
        end
        ns:LockAnchors()
        out("anchors locked")
        return
    end

    if cmd == "unlock" then
        if not ns.db then
            out("saved variables not ready")
            return
        end
        local ok, why = ns:UnlockAnchors()
        if not ok then
            if why == "combat" then
                out("cannot unlock anchors in combat")
            else
                out("could not unlock anchors")
            end
            return
        end
        out("anchors unlocked -- drag boxes to reposition, /tenui lock when done")
        return
    end

    if cmd == "reset" then
        local sub, subRest = rest:match("^(%S*)%s*(.-)$")
        sub = (sub or ""):lower()
        subRest = subRest or ""

        if sub == "" then
            out("This will wipe TenUIDB. Type |cffffd200/tenui reset confirm|r to proceed.")
            out("Or: |cffffd200/tenui reset anchors|r / |cffffd200/tenui reset anchor <name>|r")
            return
        end

        if sub == "confirm" then
            ns:WipeSavedVars()
            out("SavedVariables wiped. Reloading UI...")
            ReloadUI()
            return
        end

        if sub == "anchors" then
            local ok = ns:ResetAllAnchors()
            if ok then
                out("all anchors reset to defaults")
            else
                out("could not reset anchors (saved vars not ready?)")
            end
            return
        end

        if sub == "anchor" then
            handleResetAnchor(subRest)
            return
        end

        out("unknown reset target: |cffff7070" .. sub .. "|r. See |cffffd200/tenui help|r.")
        return
    end

    if cmd == "anchor" then
        handleAnchor(rest)
        return
    end

    if cmd == "demo" then
        handleDemo(rest)
        return
    end

    if cmd == "castbar" then
        handleCastBar(rest)
        return
    end

    if cmd == "resources" then
        handleResources(rest)
        return
    end

    if cmd == "combatalert" or cmd == "combatalerts" then
        handleCombatAlert(rest)
        return
    end

    if cmd == "general" then
        handleGeneral(rest)
        return
    end

    if cmd == "stealth" then
        handleStealth(rest)
        return
    end

    if cmd == "tooltipdump" then
        handleTooltipDump()
        return
    end

    if cmd == "classreminder" or cmd == "classreminders" then
        handleClassReminder(rest)
        return
    end

    if cmd == "talent" or cmd == "talents" then
        handleTalent(rest)
        return
    end

    if cmd == "bars" then
        handleBars(rest)
        return
    end

    if cmd == "trinkets" or cmd == "trinket" then
        handleTrinkets(rest)
        return
    end

    if cmd == "auras" or cmd == "aura" then
        handleAuras(rest)
        return
    end

    if cmd == "glow" then
        local sub = (rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
        if sub == "dump" then
            if not (ns.Glow and ns.Glow.GetDumpLines) then
                out("glow core not loaded (Modules/Glow.lua missing from TOC?)")
                return
            end
            if not (ns.Debug and ns.Debug.Log) then
                out("debug window unavailable")
                return
            end
            local lines = ns.Glow:GetDumpLines() or {}
            for i = 1, #lines do
                ns.Debug:Log("[Glow] %s", lines[i])
            end
            if ns.Auras and ns.Auras.GetGlowApplyLines then
                local okA, auraLines = pcall(ns.Auras.GetGlowApplyLines, ns.Auras)
                if okA and type(auraLines) == "table" then
                    for i = 1, #auraLines do
                        ns.Debug:Log("[Glow] %s", auraLines[i])
                    end
                end
            end
            if ns.Debug.Show then ns.Debug:Show() end
            out("glow dump sent to the debug window -- |cffffd200/tenui debug|r to view/copy")
            return
        end
        out("usage: |cffffd200/tenui glow dump|r")
        return
    end

    if cmd == "swipe" then
        local sub = (rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
        if sub == "dump" then
            if not (ns.Debug and ns.Debug.Log) then
                out("debug window unavailable")
                return
            end
            local function fmtState(st)
                if type(st) ~= "table" then return "no-state" end
                return "flag=" .. tostring(st.flag)
                    .. " cdDrawSwipe=" .. tostring(st.cdDrawSwipe)
                    .. " cdDrawEdge=" .. tostring(st.cdDrawEdge)
                    .. " hooked=" .. tostring(st.hooked)
                    .. " lastArm=" .. tostring(st.lastArmPath)
            end
            local function dumpWidget(label, w)
                if not (w and w.GetSwipeDebugState) then return end
                local ok, st = pcall(w.GetSwipeDebugState, w)
                local okFmt, line = pcall(fmtState, ok and st or nil)
                ns.Debug:Log("[Swipe] %s %s", label, okFmt and line or "format-error")
            end
            local barsFlag = not (ns.Bars and ns.Bars.profileRef
                and ns.Bars.profileRef.showDurationSwipe == false)
            local gcdFlag = not (ns.Bars and ns.Bars.profileRef
                and ns.Bars.profileRef.showGCDSwipe == false)
            local aurasFlag = true
            if ns.Auras and ns.Auras.GetIconDurationSwipe then
                local okA, vA = pcall(ns.Auras.GetIconDurationSwipe, ns.Auras)
                if okA then aurasFlag = vA end
            end
            ns.Debug:Log("[Swipe] profile: Bars.showDurationSwipe=%s Bars.showGCDSwipe=%s Auras.icons.showDurationSwipe=%s",
                tostring(barsFlag), tostring(gcdFlag), tostring(aurasFlag))
            if ns.Bars and ns.Bars.rows then
                for name, row in pairs(ns.Bars.rows) do
                    local icons = row and row.icons or {}
                    for i = 1, #icons do
                        dumpWidget("bars[" .. tostring(name) .. "][" .. i .. "]", icons[i])
                    end
                end
            end
            if ns.Auras and ns.Auras.IconDisplay and ns.Auras.IconDisplay.icons then
                local icons = ns.Auras.IconDisplay.icons
                for i = 1, #icons do
                    dumpWidget("auras.icons[" .. i .. "]", icons[i])
                end
            end
            if ns.Debug.Show then ns.Debug:Show() end
            out("swipe dump sent to the debug window -- |cffffd200/tenui debug|r to view/copy")
            return
        end
        out("usage: |cffffd200/tenui swipe dump|r")
        return
    end

    if cmd == "probe" then
        local probe = ns.CooldownProbe
        if not (probe and probe.IsLive) then
            out("CooldownProbe not loaded (Core/CooldownProbe.lua missing from TOC?)")
            return
        end
        local viewer = _G.BuffIconCooldownViewer
        if not (type(viewer) == "table" and viewer.GetItemFrames) then
            out("Probe N/A -- BuffIconCooldownViewer not loaded yet")
            return
        end
        local ok, items = pcall(viewer.GetItemFrames, viewer)
        if not (ok and type(items) == "table" and #items > 0) then
            out("Probe N/A -- no viewer item frames available")
            return
        end
        local spellID, cdInfo
        for i = 1, #items do
            local child = items[i]
            cdInfo = type(child) == "table" and child.cooldownInfo or nil
            if cdInfo and type(cdInfo.spellID) == "number" then
                spellID = cdInfo.spellID
                break
            end
        end
        if not spellID then
            out("Probe N/A -- no viewer child with a numeric spellID")
            return
        end
        if not (_G.C_Spell and _G.C_Spell.GetSpellCooldownDuration) then
            out("Probe N/A -- C_Spell.GetSpellCooldownDuration unavailable")
            return
        end
        local okDur, durObj = pcall(C_Spell.GetSpellCooldownDuration, spellID)
        if not okDur or durObj == nil then
            out(("Probe N/A -- no DurationObject for spellID=%d"):format(spellID))
            return
        end
        local live = probe:IsLive(durObj)
        out(("[Probe] spellID=%d IsLive=%s"):format(spellID, tostring(live)))
        return
    end

    if cmd == "options" or cmd == "config" then
        if ns.Options and ns.Options.Toggle then
            local ok, err = pcall(function() ns.Options:Toggle() end)
            if not ok then
                out("Options UI error: " .. tostring(err))
                out("Falling back to debug window.")
                if ns.Debug and ns.Debug.Show then ns.Debug:Show() end
            end
        else
            out("Options UI not ready. Opening debug window instead.")
            if ns.Debug and ns.Debug.Show then
                ns.Debug:Show()
            end
        end
        return
    end

    out("unknown command: |cffff7070" .. cmd .. "|r. Type |cffffd200/tenui help|r.")
end

SLASH_TENUI1 = "/tenui"
SLASH_TENUI2 = "/thud"
SlashCmdList["TENUI"] = handler

function TenUI_OnAddonCompartmentClick(addon, button)
    handler("options")
end

function TenUI_OnAddonCompartmentEnter(addon, menuButtonFrame)
    if not GameTooltip then return end
    GameTooltip:SetOwner(menuButtonFrame or UIParent, "ANCHOR_LEFT")
    GameTooltip:SetText("TenUI v" .. tostring(ns.version))
    GameTooltip:AddLine("Click for Options window.", 1, 1, 1)
    GameTooltip:AddLine("/tenui for commands.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function TenUI_OnAddonCompartmentLeave(addon, menuButtonFrame)
    if GameTooltip then
        GameTooltip:Hide()
    end
end
