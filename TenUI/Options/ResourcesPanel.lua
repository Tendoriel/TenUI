local addonName, ns = ...

local type     = type
local pcall    = pcall
local math_floor = math.floor
local math_max   = math.max

local RESOURCE_POWER_OVERRIDE_LIST = {
    { key = "AUTO",       label = "Auto (Spec)" },
    { key = "Mana",       label = "Mana" },
    { key = "Rage",       label = "Rage" },
    { key = "Focus",      label = "Focus" },
    { key = "Energy",     label = "Energy" },
    { key = "RunicPower", label = "Runic Power" },
    { key = "LunarPower", label = "Lunar Power" },
    { key = "Maelstrom",  label = "Maelstrom" },
    { key = "Insanity",   label = "Insanity" },
    { key = "Fury",       label = "Fury" },
    { key = "Essence",    label = "Essence" },
    { key = "HolyPower",  label = "Holy Power" },
    { key = "Chi",        label = "Chi" },
    { key = "SoulShards", label = "Soul Shards" },
}

local function getResBase()
    local p = ns:GetProfile()
    p.modules = p.modules or {}
    p.modules.Resources = p.modules.Resources or {}
    local rp = p.modules.Resources
    rp.primary   = rp.primary   or {}
    rp.secondary = rp.secondary or {}
    return rp
end

local function getResProfile()
    if not ns.savedVarsReady then return {} end
    if ns.GetSpecBlock then
        local rp = ns:GetSpecBlock("resources", getResBase, true, { "specColors", "_specColorsMigrated" })
        if type(rp) == "table" then
            rp.primary   = rp.primary   or {}
            rp.secondary = rp.secondary or {}
            return rp
        end
    end
    return getResBase()
end

local _previewRefresh = nil

local function applyOptions()
    if ns.Resources and ns.Resources.ApplyOptions then
        pcall(ns.Resources.ApplyOptions, ns.Resources)
    end
    if _previewRefresh then
        pcall(_previewRefresh)
    end
end

local function getActiveSpecColorEntry()
    if not ns.savedVarsReady then return nil end
    local rp = getResProfile()
    local D = ns.Resources_Display
    if D and D.getActiveSpecColors then
        local entry = D.getActiveSpecColors(rp)
        return entry
    end
    return nil
end

local PREVIEW_FILL_PCT   = 65
local PREVIEW_ANIM_PERIOD = 7
local PREVIEW_TOP_PAD    = 36
local PREVIEW_BOTTOM_PAD = 10
local PREVIEW_SEC_GAP_H  = 20

local VALID_PREVIEW_ANCHORS = {
    CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

local function resolveSecTextStyle(rp, kindIsBar)
    local prim = rp.primary or {}
    local sec = rp.secondary or {}
    local t = (type(sec.text) == "table") and sec.text or {}
    local fontKey = t.font or prim.font
    local size  = tonumber(t.fontSize) or prim.fontSize or 12
    local flags = t.fontFlags or prim.fontFlags or "OUTLINE"
    local anchor = t.anchor
    if not (anchor and VALID_PREVIEW_ANCHORS[anchor]) then
        if kindIsBar then
            anchor = prim.fontAnchor
            if not (anchor and VALID_PREVIEW_ANCHORS[anchor]) then anchor = "RIGHT" end
        else
            anchor = "CENTER"
        end
    end
    local ox = tonumber(t.x)
    local oy = tonumber(t.y)
    if kindIsBar then
        if ox == nil then ox = tonumber(prim.fontX) end
        if oy == nil then oy = tonumber(prim.fontY) end
        if ox == nil then ox = (anchor == "RIGHT") and -4 or 0 end
    end
    if ox == nil then ox = 0 end
    if oy == nil then oy = 0 end
    local enabled
    if type(t.enabled) == "boolean" then
        enabled = t.enabled
    elseif kindIsBar then
        enabled = prim.showText ~= false
    else
        enabled = false
    end
    return enabled, fontKey, size, flags, anchor, ox, oy
end

local function resolveSecStyle(rp, kind)
    local prim = rp.primary or {}
    local sec = rp.secondary or {}
    local st = (type(sec.style) == "table") and sec.style or {}
    local kindIsBar = (kind == "bar")

    local showBorder
    if type(st.showBorder) == "boolean" then
        showBorder = st.showBorder
    elseif kindIsBar then
        showBorder = prim.showBorder ~= false
    else
        showBorder = true
    end

    local bc = (type(st.borderColor) == "table") and st.borderColor or nil
    if not bc and kindIsBar and type(prim.borderColor) == "table" then
        bc = prim.borderColor
    end
    bc = bc or { 0, 0, 0, 1 }

    local showBg
    if type(st.showBackground) == "boolean" then
        showBg = st.showBackground
    elseif kindIsBar then
        showBg = prim.showBackground ~= false
    else
        showBg = true
    end

    local bgc = (type(st.backgroundColor) == "table") and st.backgroundColor or nil
    if not bgc then
        if kindIsBar then
            bgc = (type(prim.bgColor) == "table") and prim.bgColor or { 0, 0, 0, 0.28 }
        elseif kind == "runes" then
            bgc = { 0.2, 0.2, 0.2, 0.6 }
        else
            bgc = { 0, 0, 0, 0.6 }
        end
    end
    return showBorder, bc, showBg, bgc
end

local function buildEmbeddedPreview(block)
    local Widgets = ns.Widgets
    if not (Widgets and Widgets.Bar) then
        block:SetHeight(1)
        return
    end
    local D = ns.Resources_Display

    local desc
    if D and D.getSpecDescriptor then
        local ok, d = pcall(D.getSpecDescriptor)
        if ok and type(d) == "table" then desc = d end
    end

    local UI = ns.UI
    UI.SkinPanel(block)

    local caption = UI.Text(block, UI.Fonts.small, UI.Theme.color.textDim,
        "Preview -- updates live as you change settings below")
    caption:SetPoint("TOPLEFT", block, "TOPLEFT", 8, -6)

    local PREVIEW_DEFAULT_W = 240
    local PREVIEW_MAX_BAR_H = 24

    local primHolder = CreateFrame("Frame", nil, block)
    primHolder:SetHeight(20)
    primHolder:SetPoint("TOP", block, "TOP", 0, -PREVIEW_TOP_PAD)
    primHolder:SetWidth(PREVIEW_DEFAULT_W)

    local function sizeMock()
        local w, h = PREVIEW_DEFAULT_W, 18
        local rt = ns:GetAnchor("Resources")
        if rt and rt.frame then
            local aw, ah = rt.frame:GetWidth(), rt.frame:GetHeight()
            if aw and aw > 0 then w = aw end
            if ah and ah > 0 then h = ah end
        end
        if h < 8 then h = 8 elseif h > PREVIEW_MAX_BAR_H then h = PREVIEW_MAX_BAR_H end
        local availW = (block:GetWidth() or 0) - 16
        if availW and availW > 40 and w > availW then w = availW end
        primHolder:SetWidth(w)
        primHolder:SetHeight(h)
    end

    local rp = getResProfile()
    local prim = rp.primary or {}
    local primBar = Widgets.Bar:New(primHolder, {
        orientation = "HORIZONTAL",
        bgColor     = { 0, 0, 0, 0.7 },
        border      = true,
        leftText    = false,
        rightText   = true,
        texture     = prim.texture,
        fontSize    = prim.fontSize or 12,
        fontFlags   = prim.fontFlags or "OUTLINE",
    })
    primBar:SetMinMaxValues(0, 100)
    primBar:SetValue(PREVIEW_FILL_PCT)

    local lines = {}
    do
        local LINE_SAMPLES = {
            { at = 0.30, color = { 0.2, 0.9, 0.2 }, cost = "30" },
            { at = 0.80, color = { 0.9, 0.2, 0.2 }, cost = "80" },
        }
        for i = 1, #LINE_SAMPLES do
            local s = LINE_SAMPLES[i]
            local tex = primBar.frame:CreateTexture(nil, "OVERLAY")
            tex:SetColorTexture(s.color[1], s.color[2], s.color[3], 1)
            tex:SetWidth(1)
            tex:Hide()
            local fs = primBar.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            pcall(fs.SetFont, fs, "Fonts\\ARIALN.TTF", 9, "OUTLINE")
            fs:SetTextColor(s.color[1], s.color[2], s.color[3], 1)
            fs:SetText(s.cost)
            fs:Hide()
            lines[i] = { tex = tex, text = fs, at = s.at }
        end
    end

    local function layoutLines()
        local w = primHolder:GetWidth()
        if not w or w <= 0 then return end
        for i = 1, #lines do
            local L = lines[i]
            L.tex:ClearAllPoints()
            L.tex:SetPoint("TOP", primBar.frame, "TOPLEFT", w * L.at, 0)
            L.tex:SetPoint("BOTTOM", primBar.frame, "BOTTOMLEFT", w * L.at, 0)
            L.text:ClearAllPoints()
            L.text:SetPoint("BOTTOM", L.tex, "TOP", 0, 1)
        end
    end
    primHolder:SetScript("OnSizeChanged", layoutLines)

    local sdesc = desc and desc.secondary
    local secHolder, secKind, secPips, secBarWidget, secCountFS
    if sdesc then
        secKind = sdesc.kind
        secHolder = CreateFrame("Frame", nil, block)
        secHolder:SetHeight(14)
        secHolder:SetPoint("TOPLEFT", primHolder, "BOTTOMLEFT", 0, -6)
        secHolder:SetPoint("TOPRIGHT", primHolder, "BOTTOMRIGHT", 0, -6)
        if secKind == "bar" then
            secBarWidget = Widgets.Bar:New(secHolder, {
                orientation = "HORIZONTAL",
                bgColor     = { 0, 0, 0, 0.7 },
                border      = true,
                rightText   = true,
                texture     = (rp.secondary or {}).texture,
                fontSize    = 11,
            })
            secBarWidget:SetMinMaxValues(0, 100)
            secBarWidget:SetValue(50)
            secBarWidget:SetRightText("50")
        else
            local n
            if secKind == "runes" then
                n = sdesc.runeCount or 6
            else
                n = sdesc.pipCount or 5
            end
            secPips = {}
            for i = 1, n do
                local p = CreateFrame("StatusBar", nil, secHolder)
                p:SetMinMaxValues(0, 1)
                local bg = p:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints(p)
                bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
                p.bg = bg
                local function side()
                    local t = p:CreateTexture(nil, "OVERLAY")
                    t:SetColorTexture(0, 0, 0, 1)
                    return t
                end
                local bTop, bBottom, bLeft, bRight = side(), side(), side(), side()
                bTop:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
                bTop:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
                bTop:SetHeight(1)
                bBottom:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
                bBottom:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
                bBottom:SetHeight(1)
                bLeft:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
                bLeft:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
                bLeft:SetWidth(1)
                bRight:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
                bRight:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
                bRight:SetWidth(1)
                p.borderParts = { bTop, bBottom, bLeft, bRight }
                if secKind == "runes" then
                    local t = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    pcall(t.SetFont, t, "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
                    t:SetPoint("CENTER", p, "CENTER", 0, 0)
                    t:SetTextColor(1, 1, 1, 1)
                    p.text = t
                end
                secPips[i] = p
            end
            local cntOverlay = CreateFrame("Frame", nil, secHolder)
            cntOverlay:SetAllPoints(secHolder)
            cntOverlay:SetFrameLevel(secHolder:GetFrameLevel() + 10)
            secCountFS = cntOverlay:CreateFontString(nil, "OVERLAY")
            pcall(secCountFS.SetFont, secCountFS, "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
            secCountFS:SetTextColor(1, 1, 1, 1)
            secCountFS:Hide()
        end
    end

    local function layoutPips()
        if not (secPips and secHolder) then return end
        local w = secHolder:GetWidth()
        local n = #secPips
        if not w or w <= 0 or n == 0 then return end
        local rp2 = getResProfile()
        local gap = ((rp2.secondary or {}).pipSpacing) or 2
        local pipW = (w - gap * (n - 1)) / n
        if pipW < 1 then pipW = 1 end
        for i = 1, n do
            local p = secPips[i]
            p:ClearAllPoints()
            p:SetWidth(pipW)
            p:SetPoint("TOPLEFT", secHolder, "TOPLEFT", (i - 1) * (pipW + gap), 0)
            p:SetPoint("BOTTOMLEFT", secHolder, "BOTTOMLEFT", (i - 1) * (pipW + gap), 0)
        end
    end
    if secHolder and secPips then
        secHolder:SetScript("OnSizeChanged", layoutPips)
    end

    local fillPct       = PREVIEW_FILL_PCT
    local baseColor     = { 0.5, 0.5, 0.5, 1 }
    local thEnabled     = false
    local thPct         = 20
    local thDir         = "below"
    local thColor       = { 1, 0.1, 0.1, 1 }
    local showValueText = true
    local lastShownPct  = nil
    local lastThHit     = nil

    local function applyFillVisual()
        primBar:SetValue(fillPct)
        local hit = false
        if thEnabled then
            if thDir == "above" then
                hit = fillPct >= thPct
            else
                hit = fillPct <= thPct
            end
        end
        if hit ~= lastThHit then
            lastThHit = hit
            local c = hit and thColor or baseColor
            primBar:SetColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        end
        local shown = math_floor(fillPct + 0.5)
        if shown ~= lastShownPct then
            lastShownPct = shown
            primBar:SetRightText(showValueText and tostring(shown) or "")
        end
    end

    local function animateSecondary()
        if not (secPips and secHolder and secHolder:IsShown()) then return end
        if secKind == "runes" then return end
        local n = #secPips
        if n == 0 then return end
        local filled = math_floor((fillPct / 100) * n + 0.5)
        for i = 1, n do
            secPips[i]:SetValue(i <= filled and 1 or 0)
        end
    end

    local animT = 0
    primHolder:SetScript("OnUpdate", function(_, elapsed)
        animT = (animT + elapsed) % PREVIEW_ANIM_PERIOD
        local phase = animT / PREVIEW_ANIM_PERIOD
        if phase < 0.5 then
            fillPct = phase * 2 * 100
        else
            fillPct = (1 - phase) * 2 * 100
        end
        applyFillVisual()
        animateSecondary()
    end)

    local function restyle()
        if not ns.savedVarsReady then return end
        sizeMock()
        local rp2 = getResProfile()
        local prim2 = rp2.primary or {}
        local sec2 = rp2.secondary or {}
        local entry = getActiveSpecColorEntry()
        local Ctl = ns.UI

        local pEnabled = true
        if entry and type(entry.primaryEnabled) == "boolean" then
            pEnabled = entry.primaryEnabled
        end
        primHolder:SetShown(pEnabled)
        if pEnabled then
            primBar:SetTexture(prim2.texture)

            if primBar.SetBackground then
                local bgc = prim2.bgColor
                if type(bgc) == "table" then
                    primBar:SetBackground(prim2.showBackground ~= false,
                        bgc[1], bgc[2], bgc[3], bgc[4])
                else
                    primBar:SetBackground(prim2.showBackground ~= false)
                end
            end
            if primBar.SetBorder then
                primBar:SetBorder(prim2.showBorder ~= false,
                    (type(prim2.borderColor) == "table") and prim2.borderColor or nil)
            end

            local c = entry and entry.primary
            if not c and desc and desc.primary then c = desc.primary.color end
            if not c and desc and desc.primary and desc.primary.powerName == "Mana"
               and D and D.getManaColor then
                local ok, mc = pcall(D.getManaColor)
                if ok and type(mc) == "table" then c = mc end
            end
            baseColor = c or { 0.5, 0.5, 0.5, 1 }

            thEnabled = false
            if entry and type(entry.thresholdEnabled) == "boolean" then
                thEnabled = entry.thresholdEnabled
            end
            local th = prim2.threshold or {}
            thPct = tonumber(th.pct) or 20
            thDir = (th.direction or "below") == "above" and "above" or "below"
            local r = th.r if r == nil then r = 1 end
            local g = th.g if g == nil then g = 0.1 end
            local b = th.b if b == nil then b = 0.1 end
            thColor = { r, g, b, 1 }

            showValueText = prim2.showText ~= false
            lastShownPct = nil
            lastThHit = nil
            applyFillVisual()

            local fontPath = (Ctl and Ctl.ResolveFontPath and Ctl.ResolveFontPath(prim2.font))
                or "Fonts\\FRIZQT__.TTF"
            pcall(primBar.SetFont, primBar, fontPath,
                prim2.fontSize or 12, prim2.fontFlags or "OUTLINE")
            local fs = primBar.frame and primBar.frame.rightText
            if fs then
                local anchor = prim2.fontAnchor
                if not (anchor and VALID_PREVIEW_ANCHORS[anchor]) then anchor = "RIGHT" end
                local ox = tonumber(prim2.fontX)
                local oy = tonumber(prim2.fontY)
                if ox == nil then ox = (anchor == "RIGHT") and -4 or 0 end
                if oy == nil then oy = 0 end
                fs:ClearAllPoints()
                fs:SetPoint(anchor, primBar.frame, anchor, ox, oy)
                if anchor:find("LEFT") then
                    fs:SetJustifyH("LEFT")
                elseif anchor:find("RIGHT") then
                    fs:SetJustifyH("RIGHT")
                else
                    fs:SetJustifyH("CENTER")
                end
            end

            local tl = prim2.thresholdLines or {}
            local showLines = tl.enabled == true
            local showCost = showLines and tl.showCost ~= false
            for i = 1, #lines do
                lines[i].tex:SetShown(showLines)
                lines[i].text:SetShown(showCost)
            end
            layoutLines()
        end

        if secHolder then
            local sEnabled = true
            if entry and type(entry.secondaryEnabled) == "boolean" then
                sEnabled = entry.secondaryEnabled
            end
            secHolder:SetShown(sEnabled)
            if sEnabled then
                local sc2 = entry and entry.secondary
                if not sc2 and sdesc then sc2 = sdesc.color end
                sc2 = sc2 or { 0.5, 0.5, 0.5, 1 }
                local stEnabled, stFontKey, stSize, stFlags, stAnchor, stX, stY =
                    resolveSecTextStyle(rp2, secKind == "bar")
                local stFontPath = (Ctl and Ctl.ResolveFontPath and Ctl.ResolveFontPath(stFontKey))
                    or "Fonts\\FRIZQT__.TTF"
                local sbShow, sbColor, sgShow, sgColor = resolveSecStyle(rp2, secKind)
                if secKind == "bar" and secBarWidget then
                    secBarWidget:SetTexture(sec2.texture)
                    secBarWidget:SetColor(sc2[1] or 1, sc2[2] or 1, sc2[3] or 1, sc2[4] or 1)
                    if secBarWidget.SetBackground then
                        secBarWidget:SetBackground(sgShow,
                            sgColor[1], sgColor[2], sgColor[3], sgColor[4])
                    end
                    if secBarWidget.SetBorder then
                        secBarWidget:SetBorder(sbShow, sbColor)
                    end
                    pcall(secBarWidget.SetFont, secBarWidget, stFontPath, stSize, stFlags)
                    local sfs = secBarWidget.frame and secBarWidget.frame.rightText
                    if sfs then
                        sfs:ClearAllPoints()
                        sfs:SetPoint(stAnchor, secBarWidget.frame, stAnchor, stX, stY)
                        if stAnchor:find("LEFT") then
                            sfs:SetJustifyH("LEFT")
                        elseif stAnchor:find("RIGHT") then
                            sfs:SetJustifyH("RIGHT")
                        else
                            sfs:SetJustifyH("CENTER")
                        end
                    end
                    secBarWidget:SetRightText(stEnabled and "50" or "")
                elseif secPips then
                    local texPath = sec2.texture
                    if Widgets.resolveMedia then
                        texPath = Widgets.resolveMedia("statusbar", sec2.texture,
                            Widgets.DEFAULT_STATUSBAR)
                    end
                    local n = #secPips
                    for i = 1, n do
                        local p = secPips[i]
                        if texPath then p:SetStatusBarTexture(texPath) end
                        if p.bg then
                            p.bg:SetColorTexture(sgColor[1] or 0, sgColor[2] or 0,
                                sgColor[3] or 0, sgColor[4] or 1)
                            p.bg:SetShown(sgShow)
                        end
                        if p.borderParts then
                            for k = 1, #p.borderParts do
                                local bt = p.borderParts[k]
                                bt:SetColorTexture(sbColor[1] or 0, sbColor[2] or 0,
                                    sbColor[3] or 0, sbColor[4] or 1)
                                bt:SetShown(sbShow)
                            end
                        end
                        if secKind == "runes" then
                            if i > n - 2 then
                                p:SetValue(0.5)
                                p:SetStatusBarColor((sc2[1] or 1) * 0.6,
                                    (sc2[2] or 1) * 0.6, (sc2[3] or 1) * 0.6, sc2[4] or 1)
                                if p.text then p.text:SetText("5") end
                            else
                                p:SetValue(1)
                                p:SetStatusBarColor(sc2[1] or 1, sc2[2] or 1,
                                    sc2[3] or 1, sc2[4] or 1)
                                if p.text then p.text:SetText("") end
                            end
                        else
                            p:SetValue(i <= 3 and 1 or 0)
                            p:SetStatusBarColor(sc2[1] or 1, sc2[2] or 1,
                                sc2[3] or 1, sc2[4] or 1)
                        end
                    end
                    layoutPips()
                    if secCountFS then
                        if stEnabled then
                            pcall(secCountFS.SetFont, secCountFS, stFontPath, stSize, stFlags)
                            secCountFS:ClearAllPoints()
                            secCountFS:SetPoint(stAnchor, secHolder, stAnchor, stX, stY)
                            if secKind == "runes" then
                                secCountFS:SetText(tostring(math_max(0, #secPips - 2)))
                            else
                                secCountFS:SetText("3")
                            end
                            secCountFS:Show()
                        else
                            secCountFS:SetText("")
                            secCountFS:Hide()
                        end
                    end
                end
            end
        end
    end

    block:SetScript("OnSizeChanged", function()
        sizeMock()
        layoutLines()
    end)

    local blockH = PREVIEW_TOP_PAD + PREVIEW_MAX_BAR_H + PREVIEW_BOTTOM_PAD
    if secHolder then blockH = blockH + PREVIEW_SEC_GAP_H end
    block:SetHeight(blockH)
    restyle()
    _previewRefresh = restyle
end

local function buildResourcesPage(sc)
    local C = ns.UI
    if not C then return end
    local children = {}

    local PREVIEW_EST_H = PREVIEW_TOP_PAD + 24 + PREVIEW_SEC_GAP_H + PREVIEW_BOTTOM_PAD
    ns.Options:ClearPinnedHeader("resources")
    local pinned = ns.Options:GetPinnedHeader("resources", PREVIEW_EST_H)
    local previewParent = pinned or sc

    local previewBlock = CreateFrame("Frame", nil, previewParent)
    previewBlock:SetHeight(PREVIEW_EST_H)
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
            if pinned then ns.Options:GetPinnedHeader("resources", 0) end
        elseif pinned then
            ns.Options:GetPinnedHeader("resources", previewBlock:GetHeight() or PREVIEW_EST_H)
        end
        if not ok and ns.Debug and ns.Debug.Log then
            ns.Debug:Log("[ResourcesPanel] embedded preview build failed (hidden): %s", tostring(err))
        end
    end

    children[#children + 1] = C.CreateSection(sc, "Resources")

    children[#children + 1] = C.CreateCheckBox(sc, "Hide Out of Combat",
        function()
            local rp = getResProfile()
            return rp.hideOutOfCombat == true
        end,
        function(v)
            local rp = getResProfile()
            rp.hideOutOfCombat = v
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateSubSection(sc, "Primary Resource Bar")

    children[#children + 1] = C.CreateCheckBox(sc, "Enable Primary Resource Bar",
        function()
            local entry = getActiveSpecColorEntry()
            if entry and type(entry.primaryEnabled) == "boolean" then
                return entry.primaryEnabled
            end
            return true
        end,
        function(v)
            local entry = getActiveSpecColorEntry()
            if entry then entry.primaryEnabled = v end
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Show Resource Text",
        function()
            local rp = getResProfile()
            return rp.primary.showText ~= false
        end,
        function(v)
            local rp = getResProfile()
            rp.primary.showText = v
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Primary Bar Color",
        function()
            local entry = getActiveSpecColorEntry()
            local c = entry and entry.primary
            if c then return c[1], c[2], c[3], c[4] or 1 end
            if ns.Resources and ns.Resources.Primary then
                local desc = ns.Resources.Primary.desc
                if desc and desc.color then
                    local dc = desc.color
                    return dc[1], dc[2], dc[3], dc[4] or 1
                end
            end
            return 0.5, 0.5, 0.5, 1
        end,
        function(r, g, b, a)
            local entry = getActiveSpecColorEntry()
            if entry then
                entry.primary = { r, g, b, a or 1 }
            end
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateStatusBarTextureDropdown(sc, "Primary Bar Texture",
        function()
            local rp = getResProfile()
            return rp.primary.texture or "Blizzard"
        end,
        function(v)
            local rp = getResProfile()
            rp.primary.texture = v
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Show Bar Background",
        function()
            local rp = getResProfile()
            return rp.primary.showBackground ~= false
        end,
        function(v)
            local rp = getResProfile()
            rp.primary.showBackground = v and true or false
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Bar Background Color",
        function()
            local rp = getResProfile()
            local c = rp.primary.bgColor
            if type(c) == "table" then return c[1], c[2], c[3], c[4] or 1 end
            return 0, 0, 0, 0.28
        end,
        function(r, g, b, a)
            local rp = getResProfile()
            rp.primary.bgColor = { r or 0, g or 0, b or 0, a or 1 }
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Show Bar Border",
        function()
            local rp = getResProfile()
            return rp.primary.showBorder ~= false
        end,
        function(v)
            local rp = getResProfile()
            rp.primary.showBorder = v and true or false
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Bar Border Color",
        function()
            local rp = getResProfile()
            local c = rp.primary.borderColor
            if type(c) == "table" then return c[1], c[2], c[3], c[4] or 1 end
            return 0, 0, 0, 1
        end,
        function(r, g, b, a)
            local rp = getResProfile()
            rp.primary.borderColor = { r or 0, g or 0, b or 0, a or 1 }
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateDropdownLikeList(sc, "Primary Power Type Override",
        RESOURCE_POWER_OVERRIDE_LIST,
        function()
            local rp = getResProfile()
            return rp.primary.powerTypeOverride or "AUTO"
        end,
        function(v)
            local rp = getResProfile()
            rp.primary.powerTypeOverride = v
            applyOptions()
        end
    )

    local function getThreshold()
        local rp = getResProfile()
        rp.primary.threshold = rp.primary.threshold or {}
        return rp.primary.threshold
    end

    children[#children + 1] = C.CreateCheckBox(sc, "Recolor at Threshold",
        function()
            local entry = getActiveSpecColorEntry()
            if entry and type(entry.thresholdEnabled) == "boolean" then
                return entry.thresholdEnabled
            end
            return false
        end,
        function(v)
            local entry = getActiveSpecColorEntry()
            if entry then entry.thresholdEnabled = v end
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Threshold (%)", 1, 99, 1,
        function()
            return getThreshold().pct or 20
        end,
        function(v)
            getThreshold().pct = math_floor(v + 0.5)
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateDropdownLikeList(sc, "Threshold Direction",
        {
            { key = "below", label = "Below (recolor at/under %)" },
            { key = "above", label = "Above (recolor at/over %)" },
        },
        function()
            return getThreshold().direction or "below"
        end,
        function(v)
            getThreshold().direction = (v == "above") and "above" or "below"
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Threshold Color",
        function()
            local t = getThreshold()
            local r = t.r if r == nil then r = 1 end
            local g = t.g if g == nil then g = 0.1 end
            local b = t.b if b == nil then b = 0.1 end
            return r, g, b, 1
        end,
        function(r, g, b)
            local t = getThreshold()
            t.r, t.g, t.b = r, g, b
            applyOptions()
        end
    )

    local function getThresholdLines()
        local rp = getResProfile()
        rp.primary.thresholdLines = rp.primary.thresholdLines or {}
        return rp.primary.thresholdLines
    end

    children[#children + 1] = C.CreateCheckBox(sc, "Threshold Lines (ability cost)",
        function()
            return getThresholdLines().enabled == true
        end,
        function(v)
            getThresholdLines().enabled = v
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Show Cost Number on Lines",
        function()
            return getThresholdLines().showCost ~= false
        end,
        function(v)
            getThresholdLines().showCost = v
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateFontDropdown(sc, "Primary Font",
        function()
            local rp = getResProfile()
            return rp.primary.font or "default"
        end,
        function(v)
            local rp = getResProfile()
            rp.primary.font = v
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Primary Font Size", 8, 28, 1,
        function()
            local rp = getResProfile()
            return rp.primary.fontSize or 12
        end,
        function(v)
            local rp = getResProfile()
            rp.primary.fontSize = math_floor(v + 0.5)
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateOutlineDropdown(sc, "Primary Font Outline",
        function()
            local rp = getResProfile()
            local fl = rp.primary.fontFlags
            return (type(fl) == "string") and fl or "OUTLINE"
        end,
        function(v)
            local rp = getResProfile()
            rp.primary.fontFlags = (type(v) == "string") and v or "OUTLINE"
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateTextAnchorDropdown(sc, "Primary Font Anchor",
        function()
            local rp = getResProfile()
            return rp.primary.fontAnchor or "RIGHT"
        end,
        function(v)
            local rp = getResProfile()
            rp.primary.fontAnchor = v
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Primary Font Offset X", -40, 40, 1,
        function()
            local rp = getResProfile()
            return rp.primary.fontX or 0
        end,
        function(v)
            local rp = getResProfile()
            rp.primary.fontX = math_floor(v + 0.5)
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Primary Font Offset Y", -40, 40, 1,
        function()
            local rp = getResProfile()
            return rp.primary.fontY or 0
        end,
        function(v)
            local rp = getResProfile()
            rp.primary.fontY = math_floor(v + 0.5)
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateSubSection(sc, "Secondary Resource (Pips / Runes)")

    children[#children + 1] = C.CreateCheckBox(sc, "Enable Secondary Resource",
        function()
            local entry = getActiveSpecColorEntry()
            if entry and type(entry.secondaryEnabled) == "boolean" then
                return entry.secondaryEnabled
            end
            return true
        end,
        function(v)
            local entry = getActiveSpecColorEntry()
            if entry then entry.secondaryEnabled = v end
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Secondary Color",
        function()
            local entry = getActiveSpecColorEntry()
            local c = entry and entry.secondary
            if c then return c[1], c[2], c[3], c[4] or 1 end
            if ns.Resources and ns.Resources.Secondary then
                local desc = ns.Resources.Secondary.desc
                if desc and desc.color then
                    local dc = desc.color
                    return dc[1], dc[2], dc[3], dc[4] or 1
                end
            end
            return 0.5, 0.5, 0.5, 1
        end,
        function(r, g, b, a)
            local entry = getActiveSpecColorEntry()
            if entry then
                entry.secondary = { r, g, b, a or 1 }
            end
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateStatusBarTextureDropdown(sc, "Secondary Bar Texture",
        function()
            local rp = getResProfile()
            return rp.secondary.texture or "Blizzard"
        end,
        function(v)
            local rp = getResProfile()
            rp.secondary.texture = v
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Pip Spacing", 0, 10, 1,
        function()
            local rp = getResProfile()
            return rp.secondary.pipSpacing or 2
        end,
        function(v)
            local rp = getResProfile()
            rp.secondary.pipSpacing = math_floor(v + 0.5)
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateHelpText(sc,
        "Bar-style secondaries (Insanity, Maelstrom...) follow the Primary bar's border/background until changed here.")

    local function getSecStyle()
        local rp = getResProfile()
        rp.secondary.style = rp.secondary.style or {}
        return rp.secondary.style
    end

    local function secLiveKind()
        local k = ns.Resources and ns.Resources.Secondary
            and ns.Resources.Secondary._kind
        return k or "shards"
    end

    children[#children + 1] = C.CreateCheckBox(sc, "Show Secondary Border",
        function()
            local rp = getResProfile()
            local showBorder = resolveSecStyle(rp, secLiveKind())
            return showBorder
        end,
        function(v)
            getSecStyle().showBorder = v and true or false
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Secondary Border Color",
        function()
            local rp = getResProfile()
            local _, bc = resolveSecStyle(rp, secLiveKind())
            return bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 1
        end,
        function(r, g, b, a)
            getSecStyle().borderColor = { r or 0, g or 0, b or 0, a or 1 }
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Show Secondary Background",
        function()
            local rp = getResProfile()
            local _, _, showBg = resolveSecStyle(rp, secLiveKind())
            return showBg
        end,
        function(v)
            getSecStyle().showBackground = v and true or false
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateColorSwatch(sc, "Secondary Background Color",
        function()
            local rp = getResProfile()
            local _, _, _, bgc = resolveSecStyle(rp, secLiveKind())
            return bgc[1] or 0, bgc[2] or 0, bgc[3] or 0, bgc[4] or 1
        end,
        function(r, g, b, a)
            getSecStyle().backgroundColor = { r or 0, g or 0, b or 0, a or 1 }
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateSubSection(sc, "Secondary Value Text")

    children[#children + 1] = C.CreateHelpText(sc,
        "Bar-style secondaries follow the Primary text settings until changed here. For pips and runes this adds a count digit (off by default).")

    local function getSecText()
        local rp = getResProfile()
        rp.secondary.text = rp.secondary.text or {}
        return rp.secondary.text
    end

    local function secKindIsBar()
        return ns.Resources and ns.Resources.Secondary
            and ns.Resources.Secondary._kind == "bar"
    end

    children[#children + 1] = C.CreateCheckBox(sc, "Show Secondary Value Text",
        function()
            local rp = getResProfile()
            local enabled = resolveSecTextStyle(rp, secKindIsBar())
            return enabled
        end,
        function(v)
            getSecText().enabled = v and true or false
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateFontDropdown(sc, "Secondary Text Font",
        function()
            local rp = getResProfile()
            local t = (type(rp.secondary.text) == "table") and rp.secondary.text or {}
            return t.font or rp.primary.font or "default"
        end,
        function(v)
            getSecText().font = v
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Secondary Text Size", 8, 28, 1,
        function()
            local rp = getResProfile()
            local t = (type(rp.secondary.text) == "table") and rp.secondary.text or {}
            return tonumber(t.fontSize) or rp.primary.fontSize or 12
        end,
        function(v)
            getSecText().fontSize = math_floor(v + 0.5)
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateOutlineDropdown(sc, "Secondary Text Outline",
        function()
            local rp = getResProfile()
            local t = (type(rp.secondary.text) == "table") and rp.secondary.text or {}
            local fl = t.fontFlags or rp.primary.fontFlags
            return (type(fl) == "string") and fl or "OUTLINE"
        end,
        function(v)
            getSecText().fontFlags = (type(v) == "string") and v or "OUTLINE"
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateTextAnchorDropdown(sc, "Secondary Text Anchor",
        function()
            local rp = getResProfile()
            local _, _, _, _, anchor = resolveSecTextStyle(rp, secKindIsBar())
            return anchor
        end,
        function(v)
            getSecText().anchor = v
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Secondary Text Offset X", -40, 40, 1,
        function()
            local rp = getResProfile()
            local _, _, _, _, _, ox = resolveSecTextStyle(rp, secKindIsBar())
            return ox
        end,
        function(v)
            getSecText().x = math_floor(v + 0.5)
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Secondary Text Offset Y", -40, 40, 1,
        function()
            local rp = getResProfile()
            local _, _, _, _, _, _, oy = resolveSecTextStyle(rp, secKindIsBar())
            return oy
        end,
        function(v)
            getSecText().y = math_floor(v + 0.5)
            applyOptions()
        end
    )

    children[#children + 1] = C.CreateSubSection(sc, "Bar Dimensions")

    children[#children + 1] = C.CreateSlider(sc, "Primary Width", 40, 600, 1,
        function()
            local rt = ns:GetAnchor("Resources")
            if rt and rt.frame then
                local w = rt.frame:GetWidth()
                if w and w > 0 then return w end
            end
            return 240
        end,
        function(v)
            if not InCombatLockdown() then
                local rt = ns:GetAnchor("Resources")
                if rt and rt.frame then
                    rt.frame:SetWidth(v)
                    ns.Anchors:SaveSize(rt.frame)
                end
            end
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Primary Height", 8, 60, 1,
        function()
            local rt = ns:GetAnchor("Resources")
            if rt and rt.frame then
                local h = rt.frame:GetHeight()
                if h and h > 0 then return h end
            end
            return 18
        end,
        function(v)
            if not InCombatLockdown() then
                local rt = ns:GetAnchor("Resources")
                if rt and rt.frame then
                    rt.frame:SetHeight(v)
                    ns.Anchors:SaveSize(rt.frame)
                end
            end
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Secondary Width", 40, 600, 1,
        function()
            local rt = ns:GetAnchor("ResourceSecondary")
            if rt and rt.frame then
                local w = rt.frame:GetWidth()
                if w and w > 0 then return w end
            end
            return 240
        end,
        function(v)
            if not InCombatLockdown() then
                local rt = ns:GetAnchor("ResourceSecondary")
                if rt and rt.frame then
                    rt.frame:SetWidth(v)
                    ns.Anchors:SaveSize(rt.frame)
                end
            end
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Secondary Height", 8, 60, 1,
        function()
            local rt = ns:GetAnchor("ResourceSecondary")
            if rt and rt.frame then
                local h = rt.frame:GetHeight()
                if h and h > 0 then return h end
            end
            return 16
        end,
        function(v)
            if not InCombatLockdown() then
                local rt = ns:GetAnchor("ResourceSecondary")
                if rt and rt.frame then
                    rt.frame:SetHeight(v)
                    ns.Anchors:SaveSize(rt.frame)
                end
            end
        end
    )

    local totalH = C.LayoutVertical(sc, children, 4, -8)
    sc:SetHeight(math_max(totalH, 10))
end

ns.Options:RegisterPage({
    key   = "resources",
    label = "Resources",
    build = buildResourcesPage,
})
