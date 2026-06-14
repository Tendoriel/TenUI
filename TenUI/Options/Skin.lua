local addonName, ns = ...

ns.UI = ns.UI or {}
local UI = ns.UI

local CreateFrame = CreateFrame
local type        = type
local pairs       = pairs
local unpack      = unpack
local tostring    = tostring

local MEDIA = "Interface\\AddOns\\TenUI\\Media\\UI\\"
local FONTS = "Interface\\AddOns\\TenUI\\Media\\Fonts\\"

local Theme = {
    color = {
        bg          = { 0.020, 0.031, 0.063, 0.96 },
        bgOverlay   = { 0.012, 0.020, 0.043, 0.60 },
        panel       = { 0.031, 0.043, 0.086, 0.92 },
        panelLight  = { 0.047, 0.063, 0.118, 0.95 },
        input       = { 0.016, 0.024, 0.055, 0.92 },
        line        = { 0.46, 0.46, 0.60, 0.55 },
        lineSoft    = { 0.32, 0.32, 0.44, 0.35 },
        lineFaint   = { 0.26, 0.26, 0.36, 0.22 },
        text        = { 0.784, 0.811, 0.878, 1.0 },
        textBright  = { 0.92, 0.94, 1.0, 1.0 },
        textDim     = { 0.52, 0.55, 0.66, 1.0 },
        textFaint   = { 0.38, 0.40, 0.50, 1.0 },
        accent      = { 0.349, 0.761, 1.0, 1.0 },
        accentDim   = { 0.349, 0.761, 1.0, 0.45 },
        violet      = { 0.557, 0.486, 1.0, 1.0 },
        violetDim   = { 0.557, 0.486, 1.0, 0.40 },
        danger      = { 1.0, 0.35, 0.38, 1.0 },
        hover       = { 1.0, 1.0, 1.0, 0.05 },
        selected    = { 0.557, 0.486, 1.0, 0.10 },
    },
    spacing = {
        pad        = 10,
        gap        = 8,
        rowGap     = 6,
        controlH   = 24,
        rowW       = 340,
        sectionGap = 14,
    },
    texture = {
        nebula   = MEDIA .. "nebula_bg.tga",
        panel    = MEDIA .. "panel_bg.tga",
        pixel    = MEDIA .. "pixel.tga",
        edgeGlow = MEDIA .. "edge_glow.tga",
        glowSoft = MEDIA .. "glow_soft.tga",
        logo     = MEDIA .. "logo_tenui.tga",
        minimap  = MEDIA .. "minimap_icon.tga",
    },
    font = {
        regular  = FONTS .. "IBMPlexMono-Regular.ttf",
        semibold = FONTS .. "IBMPlexMono-SemiBold.ttf",
        fallback = "Fonts\\FRIZQT__.TTF",
    },
}

UI.Theme = Theme

local function makeFontObject(name, path, size, flags)
    local fo = _G[name] or CreateFont(name)
    local ok = pcall(fo.SetFont, fo, path, size, flags or "")
    if not ok or not fo:GetFont() then
        fo:SetFont(Theme.font.fallback, size, flags or "")
    end
    return fo
end

UI.Fonts = {
    header  = makeFontObject("TenUI_FontHeader",  Theme.font.semibold, 14),
    title   = makeFontObject("TenUI_FontTitle",   Theme.font.semibold, 12),
    section = makeFontObject("TenUI_FontSection", Theme.font.semibold, 11),
    label   = makeFontObject("TenUI_FontLabel",   Theme.font.regular,  12),
    value   = makeFontObject("TenUI_FontValue",   Theme.font.regular,  11),
    small   = makeFontObject("TenUI_FontSmall",   Theme.font.regular,  10),
}

local BARFX = "Interface\\AddOns\\TenUI\\Media\\BarFX\\"

local BARFX_FORCES = {
    "Void", "Shadow", "Fire", "Ice", "Light", "Nature",
    "Unholy", "Frost", "Chaos", "Cosmic",
}

UI.BarFXForces = BARFX_FORCES

do
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true) or nil
    if LSM then
        for i = 1, #BARFX_FORCES do
            local force = BARFX_FORCES[i]
            pcall(LSM.Register, LSM, "statusbar", "TenUI " .. force, BARFX .. force:lower() .. ".tga")
        end
    end
end

function UI.Rect(parent, layer, color)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(unpack(color or Theme.color.panel))
    return t
end

function UI.Text(parent, fontObj, color, text)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(fontObj or UI.Fonts.label)
    fs:SetTextColor(unpack(color or Theme.color.text))
    if text then fs:SetText(tostring(text)) end
    return fs
end

function UI.Border(frame, color, layer)
    color = color or Theme.color.line
    local edges = {}
    local function side()
        local t = frame:CreateTexture(nil, layer or "BORDER")
        t:SetColorTexture(unpack(color))
        edges[#edges + 1] = t
        return t
    end
    local top = side()
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetHeight(1)
    local bot = side()
    bot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bot:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bot:SetHeight(1)
    local lft = side()
    lft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -1)
    lft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 1)
    lft:SetWidth(1)
    local rgt = side()
    rgt:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -1)
    rgt:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 1)
    rgt:SetWidth(1)
    local api = { edges = edges }
    function api.SetColor(r, g, b, a)
        for i = 1, #edges do
            edges[i]:SetColorTexture(r, g, b, a or 1)
        end
    end
    function api.SetShown(shown)
        for i = 1, #edges do
            edges[i]:SetShown(shown)
        end
    end
    return api
end

function UI.GlowLine(parent, layer, color)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(Theme.texture.edgeGlow)
    local c = color or Theme.color.violet
    t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    return t
end

function UI.Glow(parent, layer, color)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(Theme.texture.glowSoft)
    local c = color or Theme.color.violet
    t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    return t
end

local function cornerAccents(frame, size, color)
    size = size or 12
    color = color or Theme.color.violetDim
    local defs = {
        { "TOPLEFT", 1, -1, 1, 1 },
        { "TOPRIGHT", -1, -1, -1, 1 },
        { "BOTTOMLEFT", 1, 1, 1, -1 },
        { "BOTTOMRIGHT", -1, 1, -1, -1 },
    }
    for i = 1, #defs do
        local point, ox, oy, dx, dy = unpack(defs[i])
        local h = frame:CreateTexture(nil, "OVERLAY")
        h:SetColorTexture(unpack(color))
        h:SetSize(size, 1)
        h:SetPoint(point, frame, point, ox, oy)
        local v = frame:CreateTexture(nil, "OVERLAY")
        v:SetColorTexture(unpack(color))
        v:SetSize(1, size)
        v:SetPoint(point, frame, point, ox, oy)
    end
end

UI.CornerAccents = cornerAccents

function UI.SkinPanel(frame, opts)
    opts = opts or {}
    local bg = UI.Rect(frame, "BACKGROUND", opts.color or Theme.color.panel)
    bg:SetAllPoints(frame)
    local border
    if opts.border ~= false then
        border = UI.Border(frame, opts.borderColor or Theme.color.lineSoft)
    end
    return { bg = bg, border = border }
end

function UI.SkinWindow(frame, opts)
    opts = opts or {}
    local nebula = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    nebula:SetTexture(Theme.texture.nebula)
    nebula:SetAllPoints(frame)
    nebula:SetVertexColor(1, 1, 1, opts.nebulaAlpha or 0.95)
    nebula:SetHorizTile(false)
    nebula:SetVertTile(false)
    local overlay = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    overlay:SetColorTexture(unpack(Theme.color.bgOverlay))
    overlay:SetAllPoints(frame)
    local border = UI.Border(frame, Theme.color.line, "OVERLAY")
    if opts.corners ~= false then
        cornerAccents(frame, opts.cornerSize or 14, Theme.color.violetDim)
    end
    return { nebula = nebula, overlay = overlay, border = border }
end

local function makeCrossIcon(btn, size, color)
    size = size or 9
    local a = btn:CreateTexture(nil, "ARTWORK")
    a:SetColorTexture(unpack(color or Theme.color.textDim))
    a:SetSize(size, 1.2)
    a:SetPoint("CENTER")
    a:SetRotation(math.rad(45))
    local b = btn:CreateTexture(nil, "ARTWORK")
    b:SetColorTexture(unpack(color or Theme.color.textDim))
    b:SetSize(size, 1.2)
    b:SetPoint("CENTER")
    b:SetRotation(math.rad(-45))
    return a, b
end

function UI.CreateCloseButton(parent, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(20, 20)
    local t1, t2 = makeCrossIcon(btn, 9, Theme.color.textDim)
    btn:SetScript("OnEnter", function()
        t1:SetColorTexture(unpack(Theme.color.danger))
        t2:SetColorTexture(unpack(Theme.color.danger))
    end)
    btn:SetScript("OnLeave", function()
        t1:SetColorTexture(unpack(Theme.color.textDim))
        t2:SetColorTexture(unpack(Theme.color.textDim))
    end)
    btn:SetScript("OnClick", function()
        if type(onClick) == "function" then pcall(onClick) end
    end)
    return btn
end

local function makeChevronIcon(btn, dir, size, color)
    size = size or 7
    local c = color or Theme.color.textDim
    local rot = dir == "up" and 1 or -1
    local a = btn:CreateTexture(nil, "ARTWORK")
    a:SetColorTexture(unpack(c))
    a:SetSize(size, 1.2)
    a:SetPoint("CENTER", btn, "CENTER", -size * 0.36, 0)
    a:SetRotation(math.rad(38 * rot))
    local b = btn:CreateTexture(nil, "ARTWORK")
    b:SetColorTexture(unpack(c))
    b:SetSize(size, 1.2)
    b:SetPoint("CENTER", btn, "CENTER", size * 0.36, 0)
    b:SetRotation(math.rad(-38 * rot))
    return a, b
end

function UI.CreateGlyphButton(parent, kind, onClick, opts)
    opts = opts or {}
    local btn = CreateFrame("Button", nil, parent)
    local size = opts.size or 16
    btn:SetSize(size, size)
    local bg = UI.Rect(btn, "BACKGROUND", { 0, 0, 0, 0 })
    bg:SetAllPoints(btn)
    local baseColor = opts.color or Theme.color.textDim
    local hoverColor = opts.hoverColor or (kind == "x" and Theme.color.danger or Theme.color.textBright)
    local t1, t2
    if kind == "x" then
        t1, t2 = makeCrossIcon(btn, opts.glyphSize or 7, baseColor)
    else
        t1, t2 = makeChevronIcon(btn, kind, opts.glyphSize or 7, baseColor)
    end
    btn:SetScript("OnEnter", function()
        bg:SetColorTexture(unpack(Theme.color.hover))
        t1:SetColorTexture(unpack(hoverColor))
        t2:SetColorTexture(unpack(hoverColor))
    end)
    btn:SetScript("OnLeave", function()
        bg:SetColorTexture(0, 0, 0, 0)
        t1:SetColorTexture(unpack(baseColor))
        t2:SetColorTexture(unpack(baseColor))
    end)
    btn:SetScript("OnClick", function()
        if type(onClick) == "function" then pcall(onClick) end
    end)
    function btn.SetEnabledVisual(self, enabled)
        if enabled then
            self:Enable()
            self:SetAlpha(1)
        else
            self:Disable()
            self:SetAlpha(0.3)
            bg:SetColorTexture(0, 0, 0, 0)
            t1:SetColorTexture(unpack(baseColor))
            t2:SetColorTexture(unpack(baseColor))
        end
    end
    return btn
end

function UI.CreateHeader(parent, opts)
    opts = opts or {}
    local h = CreateFrame("Frame", nil, parent)
    h:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    h:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    h:SetHeight(opts.height or 40)
    local bg = UI.Rect(h, "BACKGROUND", { 0.016, 0.024, 0.051, 0.75 })
    bg:SetAllPoints(h)
    local logo = h:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(Theme.texture.logo)
    logo:SetSize(110, 27.5)
    logo:SetPoint("LEFT", h, "LEFT", 12, 0)
    local divider = UI.GlowLine(h, "OVERLAY", { 0.557, 0.486, 1.0, 0.35 })
    divider:SetHeight(8)
    divider:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, -4)
    divider:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, -4)
    h.logo = logo
    h.bg = bg
    return h
end

function UI.CreateFooter(parent, text, opts)
    opts = opts or {}
    local fbar = CreateFrame("Frame", nil, parent)
    fbar:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    fbar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    fbar:SetHeight(opts.height or 28)
    local bg = UI.Rect(fbar, "BACKGROUND", { 0.016, 0.024, 0.051, 0.75 })
    bg:SetAllPoints(fbar)
    local line = fbar:CreateTexture(nil, "BORDER")
    line:SetColorTexture(unpack(Theme.color.lineFaint))
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", fbar, "TOPLEFT", 0, 0)
    line:SetPoint("TOPRIGHT", fbar, "TOPRIGHT", 0, 0)
    local fs = UI.Text(fbar, UI.Fonts.small, Theme.color.textFaint, text)
    fs:SetPoint("CENTER", fbar, "CENTER", 0, 0)
    fbar.text = fs
    return fbar
end

function UI.CreateSidebarItem(parent, label, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(160, 26)
    local bg = UI.Rect(btn, "BACKGROUND", { 0, 0, 0, 0 })
    bg:SetAllPoints(btn)
    local edge = btn:CreateTexture(nil, "BORDER")
    edge:SetColorTexture(unpack(Theme.color.violet))
    edge:SetWidth(2)
    edge:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -2)
    edge:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 2)
    edge:Hide()
    local glow = UI.GlowLine(btn, "ARTWORK", { 0.557, 0.486, 1.0, 0.18 })
    glow:SetAllPoints(btn)
    glow:Hide()
    local fs = UI.Text(btn, UI.Fonts.label, Theme.color.textDim, label)
    fs:SetPoint("LEFT", btn, "LEFT", 12, 0)
    btn.label = fs
    btn._selected = false
    function btn.SetSelected(self, sel)
        self._selected = sel and true or false
        if self._selected then
            edge:Show()
            glow:Show()
            bg:SetColorTexture(unpack(Theme.color.selected))
            fs:SetTextColor(unpack(Theme.color.textBright))
        else
            edge:Hide()
            glow:Hide()
            bg:SetColorTexture(0, 0, 0, 0)
            fs:SetTextColor(unpack(Theme.color.textDim))
        end
    end
    btn:SetScript("OnEnter", function(self)
        if not self._selected then
            bg:SetColorTexture(unpack(Theme.color.hover))
            fs:SetTextColor(unpack(Theme.color.text))
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if not self._selected then
            bg:SetColorTexture(0, 0, 0, 0)
            fs:SetTextColor(unpack(Theme.color.textDim))
        end
    end)
    btn:SetScript("OnClick", function()
        if type(onClick) == "function" then pcall(onClick) end
    end)
    return btn
end

function UI.CreateTabButton(parent, label, onClick)
    local btn = CreateFrame("Button", nil, parent)
    local fs = UI.Text(btn, UI.Fonts.label, Theme.color.textDim, label)
    fs:SetPoint("CENTER", btn, "CENTER", 0, 2)
    btn:SetSize(math.max(fs:GetStringWidth() + 20, 50), 26)
    local underline = btn:CreateTexture(nil, "ARTWORK")
    underline:SetColorTexture(unpack(Theme.color.accent))
    underline:SetHeight(2)
    underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 4, 0)
    underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -4, 0)
    underline:Hide()
    btn.label = fs
    btn._selected = false
    function btn.SetSelected(self, sel)
        self._selected = sel and true or false
        if self._selected then
            underline:Show()
            fs:SetTextColor(unpack(Theme.color.textBright))
        else
            underline:Hide()
            fs:SetTextColor(unpack(Theme.color.textDim))
        end
    end
    btn:SetScript("OnEnter", function(self)
        if not self._selected then fs:SetTextColor(unpack(Theme.color.text)) end
    end)
    btn:SetScript("OnLeave", function(self)
        if not self._selected then fs:SetTextColor(unpack(Theme.color.textDim)) end
    end)
    btn:SetScript("OnClick", function()
        if type(onClick) == "function" then pcall(onClick) end
    end)
    return btn
end

function UI.CreateScrollSection(parent)
    local container = CreateFrame("Frame", nil, parent)

    local sf = CreateFrame("ScrollFrame", nil, container)
    sf:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -12, 0)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(1)
    sc:SetHeight(1)
    sf:SetScrollChild(sc)
    sf:SetScript("OnSizeChanged", function(_, w)
        if w and w > 0 then sc:SetWidth(w) end
    end)

    local bar = CreateFrame("Slider", nil, container)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(6)
    bar:SetPoint("TOPRIGHT", container, "TOPRIGHT", -2, 0)
    bar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -2, 0)
    local track = UI.Rect(bar, "BACKGROUND", { 1, 1, 1, 0.05 })
    track:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, 0)
    track:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 0)
    bar:SetThumbTexture(Theme.texture.pixel)
    local thumb = bar:GetThumbTexture()
    thumb:SetSize(4, 40)
    thumb:SetVertexColor(Theme.color.violet[1], Theme.color.violet[2], Theme.color.violet[3], 0.55)
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    bar:SetValueStep(1)
    bar:Hide()

    local syncing = false
    bar:SetScript("OnValueChanged", function(_, v)
        if syncing then return end
        syncing = true
        sf:SetVerticalScroll(v)
        syncing = false
    end)
    sf:SetScript("OnVerticalScroll", function(_, off)
        if syncing then return end
        syncing = true
        bar:SetValue(off)
        syncing = false
    end)
    sf:SetScript("OnScrollRangeChanged", function(_, _, yrange)
        yrange = yrange or 0
        if yrange > 1 then
            bar:SetMinMaxValues(0, yrange)
            local visible = sf:GetHeight() or 1
            local total = visible + yrange
            local frac = visible / total
            thumb:SetHeight(math.max(20, (bar:GetHeight() or 100) * frac))
            bar:Show()
        else
            bar:SetMinMaxValues(0, 0)
            bar:SetValue(0)
            bar:Hide()
        end
    end)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(_, delta)
        local cur = sf:GetVerticalScroll() or 0
        local _, maxV = bar:GetMinMaxValues()
        local target = cur - delta * 44
        if target < 0 then target = 0 end
        if target > (maxV or 0) then target = maxV or 0 end
        sf:SetVerticalScroll(target)
    end)

    container.scrollFrame = sf
    container.scrollChild = sc
    container.scrollBar = bar
    return container, sc
end

function UI.AttachTooltip(frame, title, body)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local t = type(title) == "function" and title() or title
        if t then
            GameTooltip:SetText(tostring(t), Theme.color.text[1], Theme.color.text[2], Theme.color.text[3], 1, true)
        end
        local b = type(body) == "function" and body() or body
        if b then
            GameTooltip:AddLine(tostring(b), Theme.color.textDim[1], Theme.color.textDim[2], Theme.color.textDim[3], true)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end
