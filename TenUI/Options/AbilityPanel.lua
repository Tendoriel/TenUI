local addonName, ns = ...

ns.AbilityPanel = ns.AbilityPanel or {}
local AbilityPanel = ns.AbilityPanel

local type     = type
local tostring = tostring
local tonumber = tonumber
local pcall    = pcall

local _currentSpellID = nil
local _currentEntry   = nil
local _currentRowName = nil

local function getAbilityProfile(spellID)
    if not ns.savedVarsReady or not spellID then return {} end
    local p = ns:GetProfile()
    p.abilities = p.abilities or {}
    if not p.abilities[spellID] then
        p.abilities[spellID] = {}
        if p.abilitiesDefaults and ns._deepCopyMissing then
            ns._deepCopyMissing(p.abilities[spellID], p.abilitiesDefaults)
        end
    end
    return p.abilities[spellID]
end

local function glowStyleValues(defaultKey, excludeBlizzard)
    local names
    if ns.Glow and ns.Glow.GetRegisteredStyles then
        names = ns.Glow:GetRegisteredStyles()
    else
        names = { "blizzard", "border", "overlay", "pixel", "solid" }
    end
    local values = {}
    for i = 1, #names do
        local k = names[i]
        if not (excludeBlizzard and k == "blizzard") then
            local label = (ns.Glow and ns.Glow.GetStyleLabel) and ns.Glow:GetStyleLabel(k) or k
            if k == defaultKey then
                label = label .. " (default)"
            end
            values[#values + 1] = { key = k, label = label }
        end
    end
    return values
end

local function buildAbilityPage(sc)
    local C = ns.UI
    if not C then return end
    local Theme = C.Theme
    local children = {}

    local spellID  = _currentSpellID
    local spellName = "No ability selected"
    if spellID and C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, spellID)
        if ok and n then spellName = n .. " (" .. tostring(spellID) .. ")" end
    end

    children[#children + 1] = C.CreateSection(sc, "CDM Settings: " .. spellName)

    if not spellID then
        children[#children + 1] = C.CreateHelpText(sc,
            "Right-click an ability in CDM Bars to open its settings.")
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

    local previewCDText = previewHolder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    previewCDText:SetTextColor(1, 1, 1, 1)

    local previewHint = C.Text(previewRow, C.Fonts.small, Theme.color.textDim,
        "Live sample: updates as you change settings.")
    previewHint:SetPoint("LEFT", previewHolder, "RIGHT", 12, 0)

    local function restylePreviewImpl()
        local ap = getAbilityProfile(spellID)

        local ct = (ap.warnings and ap.warnings.cooldownText) or {}
        local fontPath = (C.ResolveFontPath and C.ResolveFontPath(ct.font))
            or "Fonts\\FRIZQT__.TTF"
        local fontSize = tonumber(ct.size) or 13
        if fontSize < 6 then fontSize = 6 elseif fontSize > 64 then fontSize = 64 end
        pcall(previewCDText.SetFont, previewCDText, fontPath, fontSize, "OUTLINE")

        if ct.enabled == false then
            previewCDText:SetText("")
        else
            previewCDText:SetText("8")
        end
        local anchor = ct.anchor or "CENTER"
        local x = ct.x or 0
        local y = ct.y or 0
        previewCDText:ClearAllPoints()
        if anchor == "BELOW_ICON" then
            previewCDText:SetPoint("TOP", previewHolder, "BOTTOM", x, y)
        elseif anchor == "ABOVE_ICON" then
            previewCDText:SetPoint("BOTTOM", previewHolder, "TOP", x, y)
        else
            previewCDText:SetPoint(anchor, previewHolder, anchor, x, y)
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
            if g.proc and g.proc.enabled == false then
                pcall(ns.Glow.Clear, ns.Glow, previewHolder, "proc")
            else
                pcall(ns.Glow.Set, ns.Glow, previewHolder, "proc", glowOpts(g.proc))
            end
            if g.ready and g.ready.enabled == true then
                pcall(ns.Glow.Set, ns.Glow, previewHolder, "ready", glowOpts(g.ready))
            else
                pcall(ns.Glow.Clear, ns.Glow, previewHolder, "ready")
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
                ns.Debug:Log("[AbilityPanel] sample preview failed (hidden): %s", tostring(err))
            end
        end
    end
    restylePreview()

    children[#children + 1] = C.CreateSubSection(sc, "Proc Glow")

    children[#children + 1] = C.CreateCheckBox(sc, "Proc Glow Enabled",
        function()
            local ap = getAbilityProfile(spellID)
            return ap.glow and ap.glow.proc and ap.glow.proc.enabled ~= false
        end,
        function(v)
            local ap = getAbilityProfile(spellID)
            ap.glow = ap.glow or {}
            ap.glow.proc = ap.glow.proc or {}
            ap.glow.proc.enabled = v
            if ns.Bars and ns.Bars.ReapplyProcGlowForSpell then
                pcall(ns.Bars.ReapplyProcGlowForSpell, ns.Bars, spellID)
            end
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateDropdownLikeList(sc, "Proc Glow Style",
        glowStyleValues("blizzard"),
        function()
            local ap = getAbilityProfile(spellID)
            return (ap.glow and ap.glow.proc and ap.glow.proc.style) or "blizzard"
        end,
        function(v)
            local ap = getAbilityProfile(spellID)
            ap.glow = ap.glow or {}
            ap.glow.proc = ap.glow.proc or {}
            ap.glow.proc.style = v
            if ns.Bars and ns.Bars.ReapplyProcGlowForSpell then
                pcall(ns.Bars.ReapplyProcGlowForSpell, ns.Bars, spellID)
            end
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Proc Glow Color",
        function()
            local ap = getAbilityProfile(spellID)
            local c = ap.glow and ap.glow.proc and ap.glow.proc.color
            if c then return c[1], c[2], c[3], c[4] end
            return 1, 1, 1, 1
        end,
        function(r, g, b, a)
            local ap = getAbilityProfile(spellID)
            ap.glow = ap.glow or {}
            ap.glow.proc = ap.glow.proc or {}
            ap.glow.proc.color = { r, g, b, a }
            if ns.Bars and ns.Bars.ReapplyProcGlowForSpell then
                pcall(ns.Bars.ReapplyProcGlowForSpell, ns.Bars, spellID)
            end
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateHelpText(sc,
        "The Blizzard style uses the game's animated proc art and ignores the color. " ..
        "Color applies to the other styles.")

    children[#children + 1] = C.CreateSubSection(sc, "Ready Glow")

    children[#children + 1] = C.CreateCheckBox(sc, "Ready Glow Enabled",
        function()
            local ap = getAbilityProfile(spellID)
            return ap.glow and ap.glow.ready and ap.glow.ready.enabled == true
        end,
        function(v)
            local ap = getAbilityProfile(spellID)
            ap.glow = ap.glow or {}
            ap.glow.ready = ap.glow.ready or {}
            ap.glow.ready.enabled = v
            if ns.Bars and ns.Bars._TickAll then
                pcall(ns.Bars._TickAll, ns.Bars)
            end
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Only in Combat",
        function()
            local ap = getAbilityProfile(spellID)
            return not (ap.glow and ap.glow.ready and ap.glow.ready.combatOnly == false)
        end,
        function(v)
            local ap = getAbilityProfile(spellID)
            ap.glow = ap.glow or {}
            ap.glow.ready = ap.glow.ready or {}
            ap.glow.ready.combatOnly = v and true or false
            if ns.Bars and ns.Bars._TickAll then
                pcall(ns.Bars._TickAll, ns.Bars)
            end
        end
    )

    children[#children + 1] = C.CreateDropdownLikeList(sc, "Ready Glow Style",
        glowStyleValues("border", true),
        function()
            local ap = getAbilityProfile(spellID)
            local s = (ap.glow and ap.glow.ready and ap.glow.ready.style) or "border"
            if s == "blizzard" then s = "border" end
            return s
        end,
        function(v)
            local ap = getAbilityProfile(spellID)
            ap.glow = ap.glow or {}
            ap.glow.ready = ap.glow.ready or {}
            ap.glow.ready.style = v
            if ns.Bars and ns.Bars._TickAll then
                pcall(ns.Bars._TickAll, ns.Bars)
            end
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Ready Glow Color",
        function()
            local ap = getAbilityProfile(spellID)
            local c = ap.glow and ap.glow.ready and ap.glow.ready.color
            if c then return c[1], c[2], c[3], c[4] end
            return 0.3, 1, 0.3, 1
        end,
        function(r, g, b, a)
            local ap = getAbilityProfile(spellID)
            ap.glow = ap.glow or {}
            ap.glow.ready = ap.glow.ready or {}
            ap.glow.ready.color = { r, g, b, a }
            if ns.Bars and ns.Bars._TickAll then
                pcall(ns.Bars._TickAll, ns.Bars)
            end
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateHelpText(sc,
        "Glows while the ability is ready (ignores the global cooldown). " ..
        "'Only in Combat' limits it to combat.")

    children[#children + 1] = C.CreateSubSection(sc, "On Cooldown State")

    children[#children + 1] = C.CreateCheckBox(sc, "Show Cooldown Text",
        function()
            local ap = getAbilityProfile(spellID)
            return ap.warnings and ap.warnings.cooldownText and ap.warnings.cooldownText.enabled ~= false
        end,
        function(v)
            local ap = getAbilityProfile(spellID)
            ap.warnings = ap.warnings or {}
            ap.warnings.cooldownText = ap.warnings.cooldownText or {}
            ap.warnings.cooldownText.enabled = v
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Cooldown Text Size", 8, 32, 1,
        function()
            local ap = getAbilityProfile(spellID)
            return (ap.warnings and ap.warnings.cooldownText and ap.warnings.cooldownText.size) or 13
        end,
        function(v)
            local ap = getAbilityProfile(spellID)
            ap.warnings = ap.warnings or {}
            ap.warnings.cooldownText = ap.warnings.cooldownText or {}
            ap.warnings.cooldownText.size = math.floor(v + 0.5)
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateFontDropdown(sc, "Cooldown Text Font",
        function()
            local ap = getAbilityProfile(spellID)
            return (ap.warnings and ap.warnings.cooldownText and ap.warnings.cooldownText.font) or "default"
        end,
        function(v)
            local ap = getAbilityProfile(spellID)
            ap.warnings = ap.warnings or {}
            ap.warnings.cooldownText = ap.warnings.cooldownText or {}
            ap.warnings.cooldownText.font = v
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateTextAnchorDropdown(sc, "Text Anchor",
        function()
            local ap = getAbilityProfile(spellID)
            return (ap.warnings and ap.warnings.cooldownText and ap.warnings.cooldownText.anchor) or "CENTER"
        end,
        function(v)
            local ap = getAbilityProfile(spellID)
            ap.warnings = ap.warnings or {}
            ap.warnings.cooldownText = ap.warnings.cooldownText or {}
            ap.warnings.cooldownText.anchor = v
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Text X Offset", -50, 50, 1,
        function()
            local ap = getAbilityProfile(spellID)
            return (ap.warnings and ap.warnings.cooldownText and ap.warnings.cooldownText.x) or 0
        end,
        function(v)
            local ap = getAbilityProfile(spellID)
            ap.warnings = ap.warnings or {}
            ap.warnings.cooldownText = ap.warnings.cooldownText or {}
            ap.warnings.cooldownText.x = math.floor(v + 0.5)
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Text Y Offset", -50, 50, 1,
        function()
            local ap = getAbilityProfile(spellID)
            return (ap.warnings and ap.warnings.cooldownText and ap.warnings.cooldownText.y) or 0
        end,
        function(v)
            local ap = getAbilityProfile(spellID)
            ap.warnings = ap.warnings or {}
            ap.warnings.cooldownText = ap.warnings.cooldownText or {}
            ap.warnings.cooldownText.y = math.floor(v + 0.5)
            restylePreview()
        end
    )

    children[#children + 1] = C.CreateSubSection(sc, "Range Indicator")

    children[#children + 1] = C.CreateCheckBox(sc, "Range Tint Out-of-Range",
        function()
            local ap = getAbilityProfile(spellID)
            return ap.range and ap.range.enabled ~= false
        end,
        function(v)
            local ap = getAbilityProfile(spellID)
            ap.range = ap.range or {}
            ap.range.enabled = v
        end
    )

    children[#children + 1] = C.CreateSubSection(sc, "Resource Gating")

    children[#children + 1] = C.CreateCheckBox(sc, "Desaturate When Insufficient Resources",
        function()
            local ap = getAbilityProfile(spellID)
            return ap.resourceGating and ap.resourceGating.enabled ~= false
        end,
        function(v)
            local ap = getAbilityProfile(spellID)
            ap.resourceGating = ap.resourceGating or {}
            ap.resourceGating.enabled = v
        end
    )

    children[#children + 1] = C.CreateSubSection(sc, "Visibility Conditions")

    local entry   = _currentEntry
    local rowName = _currentRowName
    if type(entry) == "table" then
        children[#children + 1] = C.CreateCheckBox(sc, "Hide Until Learned",
            function()
                return entry.hideWhileUnknown and true or false
            end,
            function(v)
                if v then
                    entry.hideWhileUnknown = true
                else
                    entry.hideWhileUnknown = nil
                end
                if rowName and ns.Bars and ns.Bars.RebuildRow then
                    pcall(ns.Bars.RebuildRow, ns.Bars, rowName)
                end
            end
        )
        children[#children + 1] = C.CreateHelpText(sc,
            "When on, this bar slot is removed entirely while the spell is unlearned " ..
            "(no greyed icon, no gap) and reappears automatically when learned. " ..
            "When off (default), an unlearned spell shows greyed in place.")
    end

    children[#children + 1] = C.CreateCheckBox(sc, "Combat Only",
        function()
            local ap = getAbilityProfile(spellID)
            return ap.visibility and ap.visibility.combatOnly == true
        end,
        function(v)
            local ap = getAbilityProfile(spellID)
            ap.visibility = ap.visibility or {}
            ap.visibility.combatOnly = v
        end
    )

    local totalH = C.LayoutVertical(sc, children, 4, -8)
    sc:SetHeight(math.max(totalH, 10))
end

function AbilityPanel:OpenForSpell(spellID, context)
    _currentSpellID = spellID
    if type(context) == "table" then
        _currentEntry   = context.entry
        _currentRowName = context.rowName
    else
        _currentEntry   = nil
        _currentRowName = nil
    end
    if ns.Options then
        ns.Options:SelectPage("ability", true)
        ns.Options:Open()
    end
end

ns.Options:RegisterPage({
    key   = "ability",
    label = "CDM Settings",
    build = buildAbilityPage,
})
