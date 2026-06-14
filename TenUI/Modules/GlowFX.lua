local addonName, ns = ...

local type      = type
local pairs     = pairs
local pcall     = pcall
local tonumber  = tonumber
local tinsert   = table.insert
local tremove   = table.remove
local tsort     = table.sort
local mathmin   = math.min
local mathfloor = math.floor
local CreateFrame = CreateFrame
local UIParent    = UIParent

local GlowFX = {}
ns.GlowFX = GlowFX

local MEDIA = "Interface\\AddOns\\TenUI\\Media\\Glow\\"

local SHEET_COLS   = 4
local SHEET_ROWS   = 4
local SHEET_FRAMES = 16

local PIECES = {
    { key = "CornerTL",   file = "corner_tl" },
    { key = "CornerTR",   file = "corner_tr" },
    { key = "CornerBL",   file = "corner_bl" },
    { key = "CornerBR",   file = "corner_br" },
    { key = "EdgeTop",    file = "edge_top" },
    { key = "EdgeBottom", file = "edge_bottom" },
    { key = "EdgeLeft",   file = "edge_left" },
    { key = "EdgeRight",  file = "edge_right" },
}

local STYLE_DB = {
    blue_neon           = { fps = 12 },
    red_neon            = { fps = 12 },
    orange_beam         = { fps = 16 },
    gold_lightning      = { fps = 14 },
    purple_plasma       = { fps = 14 },
    blue_electric       = { fps = 15 },
    yellow_energy_smoke = { fps = 13 },
    green_fire          = { fps = 12 },
    orange_fire         = { fps = 12 },
    red_fire            = { fps = 12 },
    purple_fire         = { fps = 12 },
    red_plasma          = { fps = 14 },
    green_plasma        = { fps = 14 },
    gold_plasma         = { fps = 14 },
    gold_sparkle        = { fps = 10 },
}

local DEFAULT_EXTENT = 14
local DEFAULT_OFFSET = 2
local MIN_EXTENT     = 3
local POOL_CAP       = 12

local _holder = CreateFrame("Frame", nil, UIParent)
_holder:Hide()

local _pool   = {}
local _active = setmetatable({}, { __mode = "k" })

local function _resolveFrame(x)
    if type(x) ~= "table" then return nil end
    if x.GetObjectType and x.CreateTexture then
        return x
    end
    local f = x.frame or x.bar or x.button or x.icon
    if type(f) == "table" and f.GetObjectType and f.CreateTexture then
        return f
    end
    return nil
end

local function _firstFrameTexCoord(t)
    t:SetTexCoord(0, 1 / SHEET_COLS, 0, 1 / SHEET_ROWS)
end

local function _setFrameTexCoord(t, idx)
    local col = idx % SHEET_COLS
    local row = mathfloor(idx / SHEET_COLS)
    local l = col / SHEET_COLS
    local top = row / SHEET_ROWS
    t:SetTexCoord(l, l + 1 / SHEET_COLS, top, top + 1 / SHEET_ROWS)
end

local function _onUpdateDriver(c, elapsed)
    local fps = c._fps or 12
    local e = (c._elapsed or 0) + elapsed
    if e > SHEET_FRAMES / fps then
        e = e % (SHEET_FRAMES / fps)
    end
    c._elapsed = e
    local idx = mathfloor(e * fps) % SHEET_FRAMES
    if idx ~= c._frameIdx then
        c._frameIdx = idx
        for i = 1, #PIECES do
            _setFrameTexCoord(c[PIECES[i].key], idx)
        end
    end
end

local function _layout(c)
    local w = c:GetWidth()
    local h = c:GetHeight()
    if not w or not h or w <= 0 or h <= 0 then return end
    local e = c._extent or DEFAULT_EXTENT
    e = mathmin(e, w / 4, h / 4)
    if e < MIN_EXTENT then e = MIN_EXTENT end
    local cs = e * 2
    local tl, tr, bl, br = c.CornerTL, c.CornerTR, c.CornerBL, c.CornerBR
    tl:ClearAllPoints()
    tl:SetSize(cs, cs)
    tl:SetPoint("CENTER", c, "TOPLEFT", 0, 0)
    tr:ClearAllPoints()
    tr:SetSize(cs, cs)
    tr:SetPoint("CENTER", c, "TOPRIGHT", 0, 0)
    bl:ClearAllPoints()
    bl:SetSize(cs, cs)
    bl:SetPoint("CENTER", c, "BOTTOMLEFT", 0, 0)
    br:ClearAllPoints()
    br:SetSize(cs, cs)
    br:SetPoint("CENTER", c, "BOTTOMRIGHT", 0, 0)
    c.EdgeTop:ClearAllPoints()
    c.EdgeTop:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
    c.EdgeTop:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT", 0, 0)
    c.EdgeBottom:ClearAllPoints()
    c.EdgeBottom:SetPoint("TOPLEFT", bl, "TOPRIGHT", 0, 0)
    c.EdgeBottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
    c.EdgeLeft:ClearAllPoints()
    c.EdgeLeft:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
    c.EdgeLeft:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT", 0, 0)
    c.EdgeRight:ClearAllPoints()
    c.EdgeRight:SetPoint("TOPLEFT", tr, "BOTTOMLEFT", 0, 0)
    c.EdgeRight:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
end

local function _onSizeChanged(c)
    _layout(c)
end

local function _acquire()
    local c = tremove(_pool)
    if c then return c end
    c = CreateFrame("Frame", nil, _holder)
    c:EnableMouse(false)
    c:Hide()
    for i = 1, #PIECES do
        local t = c:CreateTexture(nil, "OVERLAY", nil, 3)
        t:SetBlendMode("ADD")
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
        _firstFrameTexCoord(t)
        c[PIECES[i].key] = t
    end
    local ag = c:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local anims = {}
    for i = 1, #PIECES do
        local ok, fb = pcall(ag.CreateAnimation, ag, "FlipBook")
        if ok and fb and fb.SetFlipBookRows then
            fb:SetChildKey(PIECES[i].key)
            fb:SetOrder(1)
            fb:SetDuration(1)
            fb:SetFlipBookRows(SHEET_ROWS)
            fb:SetFlipBookColumns(SHEET_COLS)
            fb:SetFlipBookFrames(SHEET_FRAMES)
            fb:SetFlipBookFrameWidth(0)
            fb:SetFlipBookFrameHeight(0)
            anims[#anims + 1] = fb
        end
    end
    if #anims == #PIECES then
        c.animGroup = ag
        c.anims = anims
    end
    c:SetScript("OnSizeChanged", _onSizeChanged)
    return c
end

local function _release(c)
    if c.animGroup and c.animGroup.Stop then
        pcall(c.animGroup.Stop, c.animGroup)
    end
    c:SetScript("OnUpdate", nil)
    c:Hide()
    c:ClearAllPoints()
    c:SetParent(_holder)
    c._style = nil
    c._owner = nil
    c._offset = nil
    c._extent = nil
    c._alpha = nil
    c._fps = nil
    c._r, c._g, c._b = nil, nil, nil
    c._elapsed = nil
    c._frameIdx = nil
    if #_pool < POOL_CAP then
        tinsert(_pool, c)
    end
end

function GlowFX:Start(target, styleName, opts)
    local f = _resolveFrame(target)
    if not f then return false end
    local style = STYLE_DB[styleName]
    if not style then return false end
    if type(opts) ~= "table" then opts = nil end
    local offset = opts and tonumber(opts.offset) or DEFAULT_OFFSET
    local extent = opts and tonumber(opts.glowSize) or DEFAULT_EXTENT
    local owner  = (opts and opts.owner == "intent") and "intent" or "manual"
    local alpha  = opts and tonumber(opts.alpha) or 1
    local r = opts and tonumber(opts.colorR) or 1
    local g = opts and tonumber(opts.colorG) or 1
    local b = opts and tonumber(opts.colorB) or 1
    local fps = opts and tonumber(opts.fps) or style.fps or 12

    local c = _active[f]
    if c and c._style == styleName
       and c._owner == owner and c._offset == offset
       and c._extent == extent and c._fps == fps and c._alpha == alpha
       and c._r == r and c._g == g and c._b == b then
        local playing = false
        if c.animGroup then
            playing = c.animGroup:IsPlaying() and true or false
        else
            playing = c:GetScript("OnUpdate") ~= nil
        end
        if playing then
            c:Show()
            return true
        end
    end

    if not c then
        c = _acquire()
        _active[f] = c
    end
    c:SetParent(f)
    c:SetFrameLevel((f:GetFrameLevel() or 1) + 7)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", f, "TOPLEFT", -offset, offset)
    c:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", offset, -offset)
    c._offset = offset
    c._extent = extent
    c._owner = owner
    c._alpha = alpha
    c._r, c._g, c._b = r, g, b
    c:SetAlpha(alpha)
    local changed = c._style ~= styleName
    for i = 1, #PIECES do
        local p = PIECES[i]
        local t = c[p.key]
        if changed then
            t:SetTexture(MEDIA .. styleName .. "_" .. p.file .. ".png")
            _firstFrameTexCoord(t)
        end
        t:SetVertexColor(r, g, b)
    end
    c._style = styleName
    _layout(c)
    c._fps = fps
    if c.animGroup then
        if c.animGroup:IsPlaying() then
            c.animGroup:Stop()
        end
        local dur = SHEET_FRAMES / fps
        for i = 1, #c.anims do
            c.anims[i]:SetDuration(dur)
        end
        c:Show()
        c.animGroup:Play()
    else
        c._elapsed = 0
        c._frameIdx = nil
        c:SetScript("OnUpdate", _onUpdateDriver)
        c:Show()
    end
    return true
end

function GlowFX:Stop(target, expectedStyle, expectedOwner)
    local f = _resolveFrame(target)
    if not f then return false end
    local c = _active[f]
    if not c then return false end
    if expectedStyle and c._style ~= expectedStyle then return false end
    if expectedOwner and c._owner ~= expectedOwner then return false end
    _active[f] = nil
    _release(c)
    return true
end

function GlowFX:IsActive(target)
    local f = _resolveFrame(target)
    if not f then return false, nil end
    local c = _active[f]
    if not c then return false, nil end
    return true, c._style
end

function GlowFX:GetStyles()
    local names = {}
    for name in pairs(STYLE_DB) do
        names[#names + 1] = name
    end
    tsort(names)
    return names
end

function GlowFX:GetDumpLines()
    local lines = {}
    lines[#lines + 1] = "=== ns.GlowFX dump (flipbook border glows) ==="
    local probe = _pool[1]
    lines[#lines + 1] = ("pool=%d native_flipbook=%s"):format(
        #_pool, tostring(probe == nil or probe.animGroup ~= nil))
    local count = 0
    for f, c in pairs(_active) do
        count = count + 1
        local name = (f.GetName and f:GetName()) or tostring(f)
        lines[#lines + 1] = ("  frame %s -> style=%s owner=%s shown=%s"):format(
            name, tostring(c._style), tostring(c._owner), tostring(c:IsShown()))
    end
    lines[#lines + 1] = ("active: %d frame(s)"):format(count)
    lines[#lines + 1] = "=== end glowfx dump ==="
    return lines
end

local function _registerIntentStyles()
    local Glow = ns.Glow
    if not Glow or type(Glow.RegisterStyle) ~= "function" then return end
    for name in pairs(STYLE_DB) do
        local styleName = name
        Glow:RegisterStyle("fx_" .. styleName, {
            apply = function(f, intent, opts)
                local o = (type(opts) == "table") and opts or nil
                GlowFX:Start(f, styleName, {
                    owner    = "intent",
                    glowSize = o and o.glowSize,
                    offset   = o and o.offset,
                    fps      = o and o.fps,
                    alpha    = o and o.colorA,
                })
            end,
            clear = function(f)
                GlowFX:Stop(f, styleName, "intent")
            end,
        })
    end
end

_registerIntentStyles()

if ns.Glow then
    function ns.Glow:Start(target, styleName, opts)
        return GlowFX:Start(target, styleName, opts)
    end
    function ns.Glow:Stop(target)
        return GlowFX:Stop(target)
    end
end
