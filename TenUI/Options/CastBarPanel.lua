local addonName, ns = ...

local type        = type
local pcall       = pcall
local math_floor  = math.floor
local math_max    = math.max
local CreateFrame = CreateFrame

local function getCBBase()
    local p = ns:GetProfile()
    p.modules = p.modules or {}
    p.modules.CastBar = p.modules.CastBar or {}
    local cp = p.modules.CastBar
    cp.colors  = cp.colors  or {}
    cp.instant = cp.instant or {}
    return cp
end

local function getCBProfile()
    if not ns.savedVarsReady then return {} end
    if ns.GetSpecBlock then
        local cp = ns:GetSpecBlock("castbar", getCBBase, true)
        if type(cp) == "table" then
            cp.colors  = cp.colors  or {}
            cp.instant = cp.instant or {}
            return cp
        end
    end
    return getCBBase()
end

local function getCBResolved()
    if not ns.savedVarsReady then return {} end
    if ns.GetSpecBlock then
        local cp = ns:GetSpecBlock("castbar", getCBBase, false)
        if type(cp) == "table" then return cp end
    end
    return getCBBase()
end

local _previewRefresh = nil

local function applyOptions()
    if ns.CastBar and ns.CastBar.ApplyOptions then
        pcall(ns.CastBar.ApplyOptions, ns.CastBar)
    end
    if _previewRefresh then
        pcall(_previewRefresh)
    end
end

local PREVIEW_REGION_H  = 40
local PREVIEW_STRIP_H   = 12
local PREVIEW_BLOCK_H   = 6 + 14 + PREVIEW_REGION_H + 4 + PREVIEW_STRIP_H + 8

local PREVIEW_STAGE_FRACS    = { 0.22, 0.47, 0.72 }
local PREVIEW_TINT_STEP      = 0.18
local PREVIEW_TINT_CAP       = 0.66
local PREVIEW_PIP_COLOR      = { 1, 1, 1, 0.75 }

local PREVIEW_COLORS = {
    cast        = { 1.0, 0.7, 0.0, 1 },
    channel     = { 0.3, 0.7, 1.0, 1 },
    empower     = { 0.8, 0.3, 1.0, 1 },
    interrupted = { 1.0, 0.1, 0.1, 1 },
    success     = { 0.2, 1.0, 0.2, 1 },
}

local PREVIEW_PHASES = {
    { mode = "fill",    dur = 3.0, color = "cast",        name = "Test Cast",
      spell = 133,    fallback = [[Interface\Icons\Spell_Fire_Fireball02]] },
    { mode = "hold",    dur = 0.6, color = "success",     name = "",            fill = 1 },
    { mode = "drain",   dur = 3.0, color = "channel",     name = "Test Channel",
      spell = 15407,  fallback = [[Interface\Icons\Spell_Shadow_Twilight]] },
    { mode = "hold",    dur = 0.6, color = "interrupted", name = "Interrupted", fill = 1 },
    { mode = "fill",    dur = 3.0, color = "empower",     name = "Test Empower",
      spell = 382266, fallback = [[Interface\Icons\Ability_Evoker_Firebreath]], stages = true },
    { mode = "hold",    dur = 0.5, color = "success",     name = "",            fill = 1 },
    { mode = "instant", dur = 0.9 },
}

local function previewSpellTexture(phase)
    if phase.spell and C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, phase.spell)
        if ok and tex then return tex end
    end
    return phase.fallback
end

local function buildEmbeddedPreview(block)
    local Widgets = ns.Widgets
    if not (Widgets and Widgets.Bar and Widgets.Icon) then
        block:SetHeight(1)
        return
    end

    local UI = ns.UI
    UI.SkinPanel(block)

    local caption = UI.Text(block, UI.Fonts.small, UI.Theme.color.textDim,
        "Preview -- cycles cast / channel / empower, updates live")
    caption:SetPoint("TOPLEFT", block, "TOPLEFT", 8, -6)

    local holder = CreateFrame("Frame", nil, block)
    holder:SetHeight(PREVIEW_REGION_H)
    holder:SetPoint("TOPLEFT",  block, "TOPLEFT",  8, -20)
    holder:SetPoint("TOPRIGHT", block, "TOPRIGHT", -8, -20)

    local mock = CreateFrame("Frame", nil, holder)
    mock:SetPoint("CENTER", holder, "CENTER", 0, 0)
    mock:SetSize(240, 22)

    local cp0 = getCBResolved()
    local bar = Widgets.Bar:New(mock, {
        orientation = "HORIZONTAL",
        fgColor     = (cp0.colors and cp0.colors.cast) or PREVIEW_COLORS.cast,
        bgColor     = { 0, 0, 0, 0.7 },
        border      = true,
        leftText    = true,
        rightText   = true,
        font        = cp0.font,
        fontSize    = cp0.fontSize or 12,
        fontFlags   = cp0.fontFlags or "OUTLINE",
        texture     = cp0.texture,
    })
    bar:SetMinMaxValues(0, 1)

    local icon = Widgets.Icon:New(mock, {
        texture   = nil,
        border    = true,
        cooldown  = false,
        countdown = false,
        stackText = false,
        zoomIcon  = true,
    })
    icon:Hide()

    local pips = {}
    local function layoutPips()
        local w = bar.frame and bar.frame:GetWidth()
        if not w or w <= 0 then return end
        for i = 1, #PREVIEW_STAGE_FRACS do
            local frac = PREVIEW_STAGE_FRACS[i]
            local tex = pips[i]
            if not tex then
                tex = bar.frame:CreateTexture(nil, "OVERLAY", nil, 2)
                tex:SetColorTexture(PREVIEW_PIP_COLOR[1], PREVIEW_PIP_COLOR[2],
                    PREVIEW_PIP_COLOR[3], PREVIEW_PIP_COLOR[4])
                tex:Hide()
                pips[i] = tex
            end
            tex:ClearAllPoints()
            tex:SetWidth(1)
            tex:SetPoint("TOP",    bar.frame, "TOPLEFT",    w * frac, -1)
            tex:SetPoint("BOTTOM", bar.frame, "BOTTOMLEFT", w * frac, 1)
        end
    end
    local function setPipsShown(shown)
        for i = 1, #pips do pips[i]:SetShown(shown) end
    end

    local strip = CreateFrame("Frame", nil, block)
    strip:SetHeight(PREVIEW_STRIP_H)
    strip:SetPoint("TOPLEFT",  holder, "BOTTOMLEFT",  0, -4)
    strip:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 0, -4)
    strip:Hide()
    do
        local bg = strip:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(strip)
        bg:SetColorTexture(0, 0, 0, 0.6)
        local fg = strip:CreateTexture(nil, "ARTWORK")
        fg:SetAllPoints(strip)
        fg:SetColorTexture(0.2, 1.0, 0.2, 0.8)
        local iconTex = strip:CreateTexture(nil, "OVERLAY")
        iconTex:SetPoint("LEFT", strip, "LEFT", 0, 0)
        iconTex:SetSize(PREVIEW_STRIP_H, PREVIEW_STRIP_H)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        iconTex:SetTexture([[Interface\Icons\Spell_Nature_Lightning]])
        local nameFS = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameFS:SetPoint("LEFT", iconTex, "RIGHT", 3, 0)
        nameFS:SetPoint("RIGHT", strip, "RIGHT", -3, 0)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetText("Instant Cast")
    end

    local function getAnchorSize()
        local w, h = 240, 22
        local rt = ns:GetAnchor("CastBar")
        if rt and rt.frame then
            local aw, ah = rt.frame:GetWidth(), rt.frame:GetHeight()
            if aw and aw > 0 then w = aw end
            if ah and ah > 0 then h = ah end
        end
        return w, h
    end

    local function relayout()
        local cp = getCBResolved()
        local w, h = getAnchorSize()
        if h < 8 then h = 8 elseif h > PREVIEW_REGION_H then h = PREVIEW_REGION_H end
        local availW = holder:GetWidth()
        if availW and availW > 40 and w > availW then w = availW end
        mock:SetSize(w, h)

        bar.frame:ClearAllPoints()
        if cp.showIcon ~= false then
            local iconSize = cp.iconSize
            if iconSize == "auto" or type(iconSize) ~= "number" or iconSize <= 0 then
                iconSize = h
            else
                local maxIcon = h * 3
                if iconSize < 8 then iconSize = 8 elseif iconSize > maxIcon then iconSize = maxIcon end
            end
            local gap = cp.iconGap
            if type(gap) ~= "number" or gap < 0 then gap = 2 end
            icon.frame:ClearAllPoints()
            icon.frame:SetSize(iconSize, iconSize)
            if cp.iconSide == "RIGHT" then
                icon.frame:SetPoint("RIGHT", mock, "RIGHT", 0, 0)
                bar.frame:SetPoint("TOPLEFT",     mock, "TOPLEFT", 0, 0)
                bar.frame:SetPoint("BOTTOMRIGHT", icon.frame, "BOTTOMLEFT", -gap, 0)
            else
                icon.frame:SetPoint("LEFT", mock, "LEFT", 0, 0)
                bar.frame:SetPoint("TOPLEFT",     icon.frame, "TOPRIGHT", gap, 0)
                bar.frame:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", 0, 0)
            end
        else
            bar.frame:SetAllPoints(mock)
        end
        layoutPips()
    end
    holder:SetScript("OnSizeChanged", relayout)

    local phaseIdx     = 0
    local phaseElapsed = 0
    local lastTenths   = nil
    local curStage     = nil
    local showTimeFlag  = true
    local empowerBase   = PREVIEW_COLORS.empower

    local function phaseColor(cp, key)
        local c = cp.colors and cp.colors[key]
        if type(c) ~= "table" then c = PREVIEW_COLORS[key] end
        return c or { 1, 1, 1, 1 }
    end

    local function applyPhaseVisual()
        local phase = PREVIEW_PHASES[phaseIdx]
        if not phase then return end
        local cp = getCBResolved()
        showTimeFlag = cp.showTime ~= false
        empowerBase  = phaseColor(cp, "empower")

        if phase.mode == "instant" then
            bar:Hide()
            icon:Hide()
            setPipsShown(false)
            strip:Show()
            return
        end
        strip:Hide()
        bar:Show()

        local c = phaseColor(cp, phase.color)
        bar:SetColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        bar:SetLeftText((cp.showSpellName ~= false) and (phase.name or "") or "")

        if phase.spell then
            if cp.showIcon ~= false then
                icon:SetTexture(previewSpellTexture(phase))
                icon:Show()
            else
                icon:Hide()
            end
        elseif cp.showIcon == false then
            icon:Hide()
        end

        if phase.stages then
            layoutPips()
            setPipsShown(true)
            curStage = nil
        else
            setPipsShown(false)
        end

        if phase.mode == "hold" then
            bar:SetValue(phase.fill or 1)
            bar:SetRightText("")
        end
    end

    local function enterPhase(idx)
        local phase = PREVIEW_PHASES[idx]
        if phase and phase.mode == "instant" then
            local cp = getCBResolved()
            if cp.instant and cp.instant.enabled == false then
                idx = idx % #PREVIEW_PHASES + 1
                phase = PREVIEW_PHASES[idx]
            end
        end
        phaseIdx     = idx
        phaseElapsed = 0
        lastTenths   = nil
        curStage     = nil
        if phase and phase.mode ~= "hold" and phase.mode ~= "instant" then
            bar:SetValue(phase.mode == "drain" and 1 or 0)
        end
        applyPhaseVisual()
    end

    holder:SetScript("OnUpdate", function(_, elapsed)
        if phaseIdx == 0 then
            enterPhase(1)
            return
        end
        phaseElapsed = phaseElapsed + elapsed
        local phase = PREVIEW_PHASES[phaseIdx]
        if not phase or phaseElapsed >= phase.dur then
            enterPhase(phaseIdx % #PREVIEW_PHASES + 1)
            return
        end
        if phase.mode ~= "fill" and phase.mode ~= "drain" then return end

        local frac = phaseElapsed / phase.dur
        bar:SetValue(phase.mode == "drain" and (1 - frac) or frac)

        if showTimeFlag then
            local remaining = phase.dur - phaseElapsed
            if remaining < 0 then remaining = 0 end
            local tenths = math_floor(remaining * 10)
            if tenths ~= lastTenths then
                lastTenths = tenths
                local ok, txt = pcall(string.format, "%.1f", remaining)
                bar:SetRightText(ok and (txt .. "s") or "")
            end
        end

        if phase.stages then
            local stage = 0
            for i = 1, #PREVIEW_STAGE_FRACS do
                if frac >= PREVIEW_STAGE_FRACS[i] then stage = i else break end
            end
            if stage ~= curStage then
                curStage = stage
                local base = empowerBase
                local f = stage * PREVIEW_TINT_STEP
                if f > PREVIEW_TINT_CAP then f = PREVIEW_TINT_CAP end
                local r = (base[1] or 1) + (1 - (base[1] or 1)) * f
                local g = (base[2] or 1) + (1 - (base[2] or 1)) * f
                local b = (base[3] or 1) + (1 - (base[3] or 1)) * f
                bar:SetColor(r, g, b, base[4] or 1)
            end
        end
    end)

    holder:SetScript("OnShow", function()
        phaseIdx = 0
    end)

    local function restyle()
        if not ns.savedVarsReady then return end
        local cp = getCBResolved()
        if cp.texture and bar.SetTexture then
            pcall(bar.SetTexture, bar, cp.texture)
        end
        if bar.SetFont then
            pcall(bar.SetFont, bar, cp.font, cp.fontSize or 12, cp.fontFlags or "OUTLINE")
        end
        if bar.SetBackground
           and (cp.showBackground ~= nil or type(cp.bgColor) == "table") then
            local bgc = cp.bgColor
            if type(bgc) == "table" then
                bar:SetBackground(cp.showBackground ~= false,
                    bgc[1], bgc[2], bgc[3], bgc[4])
            else
                bar:SetBackground(cp.showBackground ~= false)
            end
        end
        if bar.SetBorder
           and (cp.showBorder ~= nil or type(cp.borderColor) == "table") then
            bar:SetBorder(cp.showBorder ~= false,
                (type(cp.borderColor) == "table") and cp.borderColor or nil)
        end
        relayout()
        applyPhaseVisual()
    end

    block:SetHeight(PREVIEW_BLOCK_H)
    restyle()
    _previewRefresh = restyle
end

local function buildCastBarPage(sc)
    local C = ns.UI
    if not C then return end
    local children = {}

    ns.Options:ClearPinnedHeader("castbar")
    local pinned = ns.Options:GetPinnedHeader("castbar", PREVIEW_BLOCK_H)
    local previewParent = pinned or sc

    local previewBlock = CreateFrame("Frame", nil, previewParent)
    previewBlock:SetHeight(PREVIEW_BLOCK_H)
    if pinned then
        previewBlock:SetPoint("TOPLEFT",  pinned, "TOPLEFT",  8, 0)
        previewBlock:SetPoint("TOPRIGHT", pinned, "TOPRIGHT", -4, 0)
    else
        children[#children + 1] = previewBlock
    end
    do
        _previewRefresh = nil
        local ok, err = pcall(buildEmbeddedPreview, previewBlock)
        if not ok then
            _previewRefresh = nil
            previewBlock:Hide()
            previewBlock:SetHeight(1)
            if pinned then ns.Options:GetPinnedHeader("castbar", 0) end
        elseif pinned then
            ns.Options:GetPinnedHeader("castbar", previewBlock:GetHeight() or PREVIEW_BLOCK_H)
        end
        if not ok and ns.Debug and ns.Debug.Log then
            ns.Debug:Log("[CastBarPanel] embedded preview build failed (hidden): %s", tostring(err))
        end
    end

    children[#children + 1] = C.CreateSection(sc, "Cast Bar")

    children[#children + 1] = C.CreateCheckBox(sc, "Enable Cast Bar",
        function()
            local cp = getCBProfile()
            return cp.enabled ~= false
        end,
        function(v)
            local cp = getCBProfile()
            cp.enabled = v
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateSubSection(sc, "Bar Dimensions")

    children[#children + 1] = C.CreateSlider(sc, "Width", 80, 800, 1,
        function()
            local rt = ns:GetAnchor("CastBar")
            if rt and rt.frame then
                local w = rt.frame:GetWidth()
                if w and w > 0 then return w end
            end
            return 240
        end,
        function(v)
            if not InCombatLockdown() then
                local rt = ns:GetAnchor("CastBar")
                if rt and rt.frame then
                    rt.frame:SetWidth(v)
                    ns.Anchors:SaveSize(rt.frame)
                end
            end
            if _previewRefresh then pcall(_previewRefresh) end
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Height", 8, 60, 1,
        function()
            local rt = ns:GetAnchor("CastBar")
            if rt and rt.frame then
                local h = rt.frame:GetHeight()
                if h and h > 0 then return h end
            end
            return 22
        end,
        function(v)
            if not InCombatLockdown() then
                local rt = ns:GetAnchor("CastBar")
                if rt and rt.frame then
                    rt.frame:SetHeight(v)
                    ns.Anchors:SaveSize(rt.frame)
                end
            end
            if _previewRefresh then pcall(_previewRefresh) end
        end
    )

    children[#children + 1] = C.CreateSubSection(sc, "Display")

    children[#children + 1] = C.CreateCheckBox(sc, "Show Spell Icon",
        function()
            local cp = getCBProfile()
            return cp.showIcon ~= false
        end,
        function(v)
            local cp = getCBProfile()
            cp.showIcon = v
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateDropdownLikeList(sc, "Icon Side",
        {
            { key = "LEFT",  label = "Left (default)" },
            { key = "RIGHT", label = "Right" },
        },
        function()
            local cp = getCBProfile()
            return (cp.iconSide == "RIGHT") and "RIGHT" or "LEFT"
        end,
        function(v)
            local cp = getCBProfile()
            cp.iconSide = (v == "RIGHT") and "RIGHT" or "LEFT"
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Auto Icon Size (match bar height)",
        function()
            local cp = getCBProfile()
            return type(cp.iconSize) ~= "number"
        end,
        function(v)
            local cp = getCBProfile()
            if v then
                cp.iconSize = "auto"
            else
                local h = 22
                local rt = ns:GetAnchor("CastBar")
                if rt and rt.frame then
                    local ah = rt.frame:GetHeight()
                    if ah and ah > 0 then h = math_floor(ah + 0.5) end
                end
                cp.iconSize = h
            end
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Icon Size (px)", 8, 64, 1,
        function()
            local cp = getCBProfile()
            if type(cp.iconSize) == "number" then return cp.iconSize end
            local rt = ns:GetAnchor("CastBar")
            if rt and rt.frame then
                local h = rt.frame:GetHeight()
                if h and h > 0 then return math_floor(h + 0.5) end
            end
            return 22
        end,
        function(v)
            local cp = getCBProfile()
            cp.iconSize = math_floor(v + 0.5)
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateHelpText(sc,
        "Moving the Icon Size slider turns Auto off. Re-enable Auto to match the bar height again.")

    children[#children + 1] = C.CreateSlider(sc, "Icon Gap", 0, 20, 1,
        function()
            local cp = getCBProfile()
            local g = cp.iconGap
            if type(g) ~= "number" or g < 0 then g = 2 end
            return g
        end,
        function(v)
            local cp = getCBProfile()
            cp.iconGap = math_floor(v + 0.5)
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Show Spell Name",
        function()
            local cp = getCBProfile()
            return cp.showSpellName ~= false
        end,
        function(v)
            local cp = getCBProfile()
            cp.showSpellName = v
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Show Timer Text",
        function()
            local cp = getCBProfile()
            return cp.showTime ~= false
        end,
        function(v)
            local cp = getCBProfile()
            cp.showTime = v
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Show Instant Casts",
        function()
            local cp = getCBProfile()
            return cp.instant.enabled ~= false
        end,
        function(v)
            local cp = getCBProfile()
            cp.instant.enabled = v
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateSubSection(sc, "Bar Font")

    children[#children + 1] = C.CreateFontDropdown(sc, "Font",
        function()
            local cp = getCBProfile()
            return cp.font or "Friz Quadrata TT"
        end,
        function(v)
            local cp = getCBProfile()
            cp.font = v
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Font Size", 8, 28, 1,
        function()
            local cp = getCBProfile()
            return cp.fontSize or 12
        end,
        function(v)
            local cp = getCBProfile()
            cp.fontSize = math_floor(v + 0.5)
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateOutlineDropdown(sc, "Font Outline",
        function()
            local cp = getCBProfile()
            local fl = cp.fontFlags
            return (type(fl) == "string") and fl or "OUTLINE"
        end,
        function(v)
            local cp = getCBProfile()
            cp.fontFlags = (type(v) == "string") and v or "OUTLINE"
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateSubSection(sc, "Bar Style")

    children[#children + 1] = C.CreateStatusBarTextureDropdown(sc, "Bar Texture",
        function()
            local cp = getCBProfile()
            return cp.texture or "Blizzard"
        end,
        function(v)
            local cp = getCBProfile()
            cp.texture = v
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Show Bar Background",
        function()
            local cp = getCBProfile()
            return cp.showBackground ~= false
        end,
        function(v)
            local cp = getCBProfile()
            cp.showBackground = v and true or false
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Bar Background Color",
        function()
            local cp = getCBProfile()
            local c = cp.bgColor
            if type(c) == "table" then return c[1], c[2], c[3], c[4] or 1 end
            return 0, 0, 0, 0.28
        end,
        function(r, g, b, a)
            local cp = getCBProfile()
            cp.bgColor = { r or 0, g or 0, b or 0, a or 1 }
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Show Bar Border",
        function()
            local cp = getCBProfile()
            return cp.showBorder ~= false
        end,
        function(v)
            local cp = getCBProfile()
            cp.showBorder = v and true or false
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Bar Border Color",
        function()
            local cp = getCBProfile()
            local c = cp.borderColor
            if type(c) == "table" then return c[1], c[2], c[3], c[4] or 1 end
            return 0, 0, 0, 1
        end,
        function(r, g, b, a)
            local cp = getCBProfile()
            cp.borderColor = { r or 0, g or 0, b or 0, a or 1 }
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateSubSection(sc, "Bar Colors")

    children[#children + 1] = C.CreateColorSwatch(sc, "Interruptible (Cast)",
        function()
            local cp = getCBProfile()
            local c = cp.colors.cast
            if c then return c[1], c[2], c[3], c[4] or 1 end
            return 1.0, 0.7, 0.0, 1
        end,
        function(r, g, b, a)
            local cp = getCBProfile()
            cp.colors.cast = { r, g, b, a or 1 }
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Non-Interruptible",
        function()
            local cp = getCBProfile()
            local c = cp.colors.uninterruptible
            if c then return c[1], c[2], c[3], c[4] or 1 end
            return 0.5, 0.5, 0.5, 1
        end,
        function(r, g, b, a)
            local cp = getCBProfile()
            cp.colors.uninterruptible = { r, g, b, a or 1 }
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Channel",
        function()
            local cp = getCBProfile()
            local c = cp.colors.channel
            if c then return c[1], c[2], c[3], c[4] or 1 end
            return 0.3, 0.7, 1.0, 1
        end,
        function(r, g, b, a)
            local cp = getCBProfile()
            cp.colors.channel = { r, g, b, a or 1 }
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Empower",
        function()
            local cp = getCBProfile()
            local c = cp.colors.empower
            if c then return c[1], c[2], c[3], c[4] or 1 end
            return 0.8, 0.3, 1.0, 1
        end,
        function(r, g, b, a)
            local cp = getCBProfile()
            cp.colors.empower = { r, g, b, a or 1 }
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Interrupted",
        function()
            local cp = getCBProfile()
            local c = cp.colors.interrupted
            if c then return c[1], c[2], c[3], c[4] or 1 end
            return 1.0, 0.1, 0.1, 1
        end,
        function(r, g, b, a)
            local cp = getCBProfile()
            cp.colors.interrupted = { r, g, b, a or 1 }
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Failed",
        function()
            local cp = getCBProfile()
            local c = cp.colors.failed
            if c then return c[1], c[2], c[3], c[4] or 1 end
            return 0.6, 0.6, 0.6, 1
        end,
        function(r, g, b, a)
            local cp = getCBProfile()
            cp.colors.failed = { r, g, b, a or 1 }
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Succeeded",
        function()
            local cp = getCBProfile()
            local c = cp.colors.success
            if c then return c[1], c[2], c[3], c[4] or 1 end
            return 0.2, 1.0, 0.2, 1
        end,
        function(r, g, b, a)
            local cp = getCBProfile()
            cp.colors.success = { r, g, b, a or 1 }
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateSubSection(sc, "Timing")

    children[#children + 1] = C.CreateSlider(sc, "Hold Time (s)", 0, 2, 0.1,
        function()
            local cp = getCBProfile()
            return cp.holdTime or 0.4
        end,
        function(v)
            local cp = getCBProfile()
            cp.holdTime = math_floor(v * 10 + 0.5) / 10
            applyOptions()
        end
    )

    local totalH = C.LayoutVertical(sc, children, 4, -8)
    sc:SetHeight(math_max(totalH, 10))
end

ns.Options:RegisterPage({
    key   = "castbar",
    label = "Cast Bar",
    build = buildCastBarPage,
})
