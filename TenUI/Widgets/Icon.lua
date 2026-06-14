local addonName, ns = ...

ns.Widgets = ns.Widgets or {}

local CreateFrame = CreateFrame
local setmetatable = setmetatable
local pcall = pcall
local hooksecurefunc = hooksecurefunc

local Widgets = ns.Widgets
local Icon = {}
Icon.__index = Icon
Widgets.Icon = Icon

local function makeBorder(parent, color)
    local function side()
        local t = parent:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
        return t
    end
    local top, bottom, left, right = side(), side(), side(), side()
    top:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    top:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(1)
    left:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    left:SetWidth(1)
    right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(1)
    return { top = top, bottom = bottom, left = left, right = right }
end

local function applyBorderColor(border, color)
    if not border then return end
    for _, t in pairs(border) do
        t:SetColorTexture(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
    end
end

local CROP_TRIM_HALF = 0.42

local function cropTexCoords(w, h)
    local left, right, top, bottom = 0.08, 0.92, 0.08, 0.92
    if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 and w ~= h then
        if w > h then
            local half = CROP_TRIM_HALF * (h / w)
            top, bottom = 0.5 - half, 0.5 + half
        else
            local half = CROP_TRIM_HALF * (w / h)
            left, right = 0.5 - half, 0.5 + half
        end
    end
    return left, right, top, bottom
end

function Icon.ApplyCropTexCoord(tex, w, h)
    if not (tex and tex.SetTexCoord) then return end
    local l, r, t, b = cropTexCoords(w, h)
    pcall(tex.SetTexCoord, tex, l, r, t, b)
end

function Icon:New(parent, opts)
    opts = opts or {}
    local resolveMedia = Widgets.resolveMedia
    local self_ = setmetatable({}, Icon)
    self_._opts = opts
    self_._state = "live"

    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetAllPoints(parent)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(f)
    if opts.zoomIcon ~= false then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f:SetScript("OnSizeChanged", function(_, w, h)
            Icon.ApplyCropTexCoord(icon, w, h)
        end)
    end
    if opts.texture then
        icon:SetTexture(opts.texture)
    else
        icon:SetColorTexture(0.1, 0.1, 0.1, 1)
    end
    if opts.desaturated then
        icon:SetDesaturated(true)
    end
    f.icon = icon

    if opts.border ~= false then
        f.border = makeBorder(f, opts.borderColor or { 0, 0, 0, 1 })
    end

    if opts.cooldown ~= false then
        local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        cd:SetAllPoints(f)
        self_._drawSwipe = opts.cooldownSwipe ~= false
        self_._drawEdge = opts.cooldownEdge ~= false
        self_._cooldownReverse = opts.cooldownReverse == true
        cd:SetDrawSwipe(self_._drawSwipe)
        if self_._drawSwipe then
            pcall(cd.SetSwipeColor, cd, 0, 0, 0, opts.cooldownSwipeAlpha or 0.8)
        else
            cd:SetSwipeColor(0, 0, 0, 0)
        end
        if type(cd.SetReverse) == "function" then
            pcall(cd.SetReverse, cd, self_._cooldownReverse)
        end
        cd:SetDrawEdge(self_._drawSwipe and self_._drawEdge)
        cd._ownerWidget = self_
        if not cd._swipeHooked then
            cd._swipeHooked = true
            hooksecurefunc(cd, "SetDrawSwipe", function(frame)
                if frame._inSwipeHook then return end
                local owner = frame._ownerWidget
                if owner and owner._drawSwipe == false then
                    frame._inSwipeHook = true
                    pcall(frame.SetDrawSwipe, frame, false)
                    frame._inSwipeHook = false
                end
            end)
            hooksecurefunc(cd, "SetSwipeColor", function(frame)
                if frame._inSwipeHook then return end
                local owner = frame._ownerWidget
                if owner and owner._drawSwipe == false then
                    frame._inSwipeHook = true
                    pcall(frame.SetSwipeColor, frame, 0, 0, 0, 0)
                    frame._inSwipeHook = false
                end
            end)
        end
        cd:SetHideCountdownNumbers(not (opts.countdown ~= false))
        if opts.countdown ~= false
           and opts.countdownFormatter
           and cd.SetCountdownFormatter then
            local ok, err = pcall(cd.SetCountdownFormatter, cd, opts.countdownFormatter)
            if not ok and ns.Debug and ns.Debug.Log then
                ns.Debug:Log("Icon: SetCountdownFormatter rejected formatter (" ..
                             tostring(err) .. ") -- falling back to default.")
            end
        end
        f.cooldown = cd
    end

    if opts.stackText ~= false then
        local fontPath = resolveMedia("font", opts.font, Widgets.DEFAULT_FONT)
        local size = opts.fontSize or 12
        local flags = opts.fontFlags or "OUTLINE"
        local fs = f:CreateFontString(nil, "OVERLAY")
        fs:SetFont(fontPath, size, flags)
        fs:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        fs:SetJustifyH("RIGHT")
        fs:SetTextColor(1, 1, 1, 1)
        f.stack = fs
    end

    self_.frame = f
    return self_
end

local function texturePresent(v)
    if type(issecretvalue) == "function" and issecretvalue(v) then return true end
    if v == nil then return false end
    return v ~= false
end

function Icon:SetTexture(texture)
    if texturePresent(texture) then
        self.frame.icon:SetTexture(texture)
    else
        self.frame.icon:SetColorTexture(0.1, 0.1, 0.1, 1)
    end
end

function Icon:SetDesaturated(b)
    self.frame.icon:SetDesaturated(b and true or false)
end

function Icon:SetVertexColor(r, g, b, a)
    if not (self.frame and self.frame.icon) then return end
    if r == nil then
        self.frame.icon:SetVertexColor(1, 1, 1, 1)
    else
        self.frame.icon:SetVertexColor(r, g, b or 1, a or 1)
    end
end

function Icon:SetCooldown(durationObject)
    local cd = self.frame.cooldown
    if not cd then return end
    if not durationObject then
        cd:Clear()
        self._lastArmPath = "clear-nil"
        return
    end
    cd:SetCooldownFromDurationObject(durationObject)
    self._lastArmPath = "duration-arm"
    if self._drawSwipe == false then
        cd._inSwipeHook = true
        pcall(cd.SetDrawSwipe, cd, false)
        pcall(cd.SetSwipeColor, cd, 0, 0, 0, 0)
        pcall(cd.SetDrawEdge, cd, false)
        cd._inSwipeHook = false
    end
end

function Icon:SetDrawSwipe(enabled)
    local value = enabled ~= false
    self._drawSwipe = value
    local cd = self.frame and self.frame.cooldown
    if not cd then return end
    cd._inSwipeHook = true
    pcall(cd.SetDrawSwipe, cd, value)
    if value then
        pcall(cd.SetSwipeColor, cd, 0, 0, 0, 0.8)
        pcall(cd.SetDrawEdge, cd, self._drawEdge ~= false)
    else
        pcall(cd.SetSwipeColor, cd, 0, 0, 0, 0)
        pcall(cd.SetDrawEdge, cd, false)
    end
    cd._inSwipeHook = false
end

function Icon:SetCooldownReverse(enabled)
    local value = enabled == true
    self._cooldownReverse = value
    local cd = self.frame and self.frame.cooldown
    if not cd or type(cd.SetReverse) ~= "function" then return end
    pcall(cd.SetReverse, cd, value)
end

function Icon:ClearCooldown()
    if self.frame.cooldown then
        self.frame.cooldown:Clear()
        self._lastArmPath = "clear"
    end
end

function Icon:GetSwipeDebugState()
    local st = {
        flag        = self._drawSwipe,
        edgeOpt     = self._drawEdge,
        lastArmPath = self._lastArmPath,
    }
    local cd = self.frame and self.frame.cooldown
    if cd then
        st.hooked = cd._swipeHooked and true or false
        local ok, v = pcall(function() return cd:GetDrawSwipe() and true or false end)
        if ok then st.cdDrawSwipe = v else st.cdDrawSwipe = "secret?" end
        local ok2, e = pcall(function() return cd:GetDrawEdge() and true or false end)
        if ok2 then st.cdDrawEdge = e else st.cdDrawEdge = "secret?" end
    else
        st.hooked = false
    end
    return st
end

function Icon:SetStackText(n)
    local fs = self.frame.stack
    if not fs then return end
    if n == nil or n == 0 or n == 1 then
        fs:SetText("")
    else
        fs:SetText(tostring(n))
    end
end

function Icon:SetStackTextRaw(value)
    local fs = self.frame.stack
    if not fs then return end
    fs:SetText(value)
end

local function resolveStyleFont(font)
    if type(font) == "string" and (font:find("\\", 1, true) or font:find("/", 1, true)) then
        return font
    end
    if ns.Controls and ns.Controls.ResolveFontPath then
        local ok, path = pcall(ns.Controls.ResolveFontPath, font)
        if ok and type(path) == "string" and path ~= "" then
            return path
        end
    end
    if Widgets.resolveMedia then
        local key = (font ~= nil and font ~= "default") and font or nil
        return Widgets.resolveMedia("font", key, Widgets.DEFAULT_FONT)
    end
    return Widgets.DEFAULT_FONT
end

local function resolveStyleAnchor(anchor, x, y)
    local ox = (type(x) == "number") and x or 0
    local oy = (type(y) == "number") and y or 0
    if anchor == "BELOW_ICON" then
        return "TOP", "BOTTOM", ox, oy
    elseif anchor == "ABOVE_ICON" then
        return "BOTTOM", "TOP", ox, oy
    end
    local valid = {
        CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
        TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
    }
    local p = (type(anchor) == "string" and valid[anchor]) and anchor or "BOTTOMRIGHT"
    return p, p, ox, oy
end

function Icon:ApplyTextStyle(style)
    local fs = self.frame and self.frame.stack
    if not fs then return end
    style = style or {}

    local fontPath = resolveStyleFont(style.font)
    local size  = (type(style.size) == "number" and style.size > 0) and style.size or 12
    local flags = (type(style.flags) == "string") and style.flags or "OUTLINE"
    local p, rp, ox, oy = resolveStyleAnchor(style.anchor, style.x, style.y)

    pcall(function()
        fs:SetFont(fontPath, size, flags)
        fs:ClearAllPoints()
        fs:SetPoint(p, self.frame, rp, ox, oy)
    end)
    self._textStyle = {
        font   = style.font,
        size   = size,
        flags  = flags,
        anchor = style.anchor,
        x      = ox,
        y      = oy,
    }
end

local function cooldownCountdownFontString(cd)
    if not cd then return nil end
    if cd.GetCountdownFontString then
        local ok, fs = pcall(cd.GetCountdownFontString, cd)
        if ok and fs and fs.SetFont then return fs end
    end
    if cd.GetRegions then
        local ok, regions = pcall(function() return { cd:GetRegions() } end)
        if ok and regions then
            for i = 1, #regions do
                local r = regions[i]
                if r and r.IsObjectType and r:IsObjectType("FontString") then
                    return r
                end
            end
        end
    end
    return nil
end

function Icon:ApplyCooldownTextStyle(style)
    local cd = self.frame and self.frame.cooldown
    if not cd then return end
    style = style or {}

    local fontPath = resolveStyleFont(style.font)
    local size  = (type(style.size) == "number" and style.size > 0) and style.size or 12
    local flags = (type(style.flags) == "string") and style.flags or "OUTLINE"
    local p, rp, ox, oy = resolveStyleAnchor(style.anchor or "CENTER", style.x, style.y)

    local fs = cooldownCountdownFontString(cd)
    if not fs then
        if cd.SetCountdownFont then
            local fo = self._cdFontObject
            if not fo then
                Widgets._cdFontSeq = (Widgets._cdFontSeq or 0) + 1
                local ok2, created = pcall(CreateFont, "TenUIIconCDFont" .. Widgets._cdFontSeq)
                if ok2 and created then
                    fo = created
                    self._cdFontObject = fo
                end
            end
            if fo then
                pcall(fo.SetFont, fo, fontPath, size, flags)
                pcall(cd.SetCountdownFont, cd, fo:GetName())
            end
        end
        self._cdTextStyle = { font = style.font, size = size, flags = flags, anchor = style.anchor, x = ox, y = oy }
        return
    end

    pcall(function()
        fs:SetFont(fontPath, size, flags)
        fs:ClearAllPoints()
        fs:SetPoint(p, self.frame, rp, ox, oy)
    end)
    self._cdTextStyle = {
        font   = style.font,
        size   = size,
        flags  = flags,
        anchor = style.anchor,
        x      = ox,
        y      = oy,
    }
end

function Icon:SetTextFont(fontPath, size, flags)
    local fs = self.frame and self.frame.stack
    if not fs then return end
    if not fontPath then return end
    local s = (type(size) == "number" and size > 0) and size or 12
    local fl = (type(flags) == "string") and flags or "OUTLINE"
    local ok = pcall(fs.SetFont, fs, fontPath, s, fl)
    if not ok and ns.Debug and ns.Debug.Log then
        ns.Debug:Log("Icon:SetTextFont failed for path=" .. tostring(fontPath))
    end
end

function Icon:SetTextAnchor(point, relPoint, x, y)
    local fs = self.frame and self.frame.stack
    if not fs then return end
    if relPoint == nil then
        local p, rp, ox, oy = resolveStyleAnchor(point, x, y)
        pcall(function()
            fs:ClearAllPoints()
            fs:SetPoint(p, self.frame, rp, ox, oy)
        end)
        return
    end
    local p  = (type(point)    == "string") and point    or "BOTTOMRIGHT"
    local rp = (type(relPoint) == "string") and relPoint or "BOTTOMRIGHT"
    local ox = (type(x) == "number") and x or -1
    local oy = (type(y) == "number") and y or 1
    pcall(function()
        fs:ClearAllPoints()
        fs:SetPoint(p, self.frame, rp, ox, oy)
    end)
end

function Icon:SetBorder(enabled, color)
    if enabled then
        if not self.frame.border then
            self.frame.border = makeBorder(self.frame, color or { 0, 0, 0, 1 })
        else
            applyBorderColor(self.frame.border, color or { 0, 0, 0, 1 })
            for _, t in pairs(self.frame.border) do t:Show() end
        end
    else
        if self.frame.border then
            for _, t in pairs(self.frame.border) do t:Hide() end
        end
    end
end

local ACTIVE_BORDER_THICKNESS = 2
local ACTIVE_BORDER_OUTSET    = 1

local function makeActiveBorder(parent, color)
    local r = color[1] or 1
    local g = color[2] or 0.7
    local b = color[3] or 0
    local a = color[4] or 1
    local function side()
        local t = parent:CreateTexture(nil, "OVERLAY", nil, 2)
        t:SetColorTexture(r, g, b, a)
        return t
    end
    local top, bottom, left, right = side(), side(), side(), side()
    local out = ACTIVE_BORDER_OUTSET
    top:SetPoint("TOPLEFT",     parent, "TOPLEFT",     -out,  out)
    top:SetPoint("TOPRIGHT",    parent, "TOPRIGHT",     out,  out)
    top:SetHeight(ACTIVE_BORDER_THICKNESS)
    bottom:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  -out, -out)
    bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT",  out, -out)
    bottom:SetHeight(ACTIVE_BORDER_THICKNESS)
    left:SetPoint("TOPLEFT",     parent, "TOPLEFT",     -out,  out)
    left:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  -out, -out)
    left:SetWidth(ACTIVE_BORDER_THICKNESS)
    right:SetPoint("TOPRIGHT",    parent, "TOPRIGHT",     out,  out)
    right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT",  out, -out)
    right:SetWidth(ACTIVE_BORDER_THICKNESS)
    return { top = top, bottom = bottom, left = left, right = right }
end

local function applyActiveBorderColor(border, color)
    if not border then return end
    local r = color[1] or 1
    local g = color[2] or 0.7
    local b = color[3] or 0
    local a = color[4] or 1
    for _, t in pairs(border) do
        t:SetColorTexture(r, g, b, a)
    end
end

function Icon:SetActiveBorder(enabled, r, g, b, a)
    if enabled then
        local color = { r or 1, g or 0.7, b or 0, a or 1 }
        if not self.frame._activeBorder then
            self.frame._activeBorder = makeActiveBorder(self.frame, color)
        else
            applyActiveBorderColor(self.frame._activeBorder, color)
            for _, t in pairs(self.frame._activeBorder) do t:Show() end
        end
    else
        if self.frame._activeBorder then
            for _, t in pairs(self.frame._activeBorder) do t:Hide() end
        end
    end
end

local function disableProcGlowMouse(frame)
    if type(frame) ~= "table" then return end
    if type(frame.EnableMouse) == "function" then
        pcall(frame.EnableMouse, frame, false)
    end
    if type(frame.EnableMouseMotion) == "function" then
        pcall(frame.EnableMouseMotion, frame, false)
    end
    if type(frame.SetMouseClickEnabled) == "function" then
        pcall(frame.SetMouseClickEnabled, frame, false)
    end
    if type(frame.GetChildren) == "function" then
        local ok, n = pcall(select, "#", frame:GetChildren())
        if ok and n and n > 0 then
            local children = { frame:GetChildren() }
            for i = 1, #children do
                disableProcGlowMouse(children[i])
            end
        end
    end
end

local function ensureProcGlow(self_)
    local f = self_.frame
    if not f then return nil end
    if f._procGlow then return f._procGlow end
    local ok, glow = pcall(CreateFrame, "Frame", nil, f, "ActionButtonSpellAlertTemplate")
    if not ok or not glow then
        if ns.Debug and ns.Debug.Log then
            ns.Debug:Log("Icon: ActionButtonSpellAlertTemplate unavailable (" .. tostring(glow) .. ")")
        end
        return nil
    end
    local w, h = f:GetSize()
    if w and h and w > 0 and h > 0 then
        glow:SetSize(w * 1.4, h * 1.4)
        glow:SetPoint("CENTER", f, "CENTER", 0, 0)
    end
    pcall(glow.SetScript, glow, "OnHide", nil)
    disableProcGlowMouse(glow)
    glow:Hide()
    f._procGlow = glow
    return glow
end

function Icon:SetProcGlow(enabled)
    local f = self.frame
    if not f then return end
    if enabled then
        local glow = ensureProcGlow(self)
        if not glow then return end
        self._procGlowActive = true
        if glow:IsShown() then
            if glow:IsVisible()
               and glow.ProcLoop and glow.ProcLoop.Play
               and glow.ProcLoop.IsPlaying and not glow.ProcLoop:IsPlaying() then
                pcall(glow.ProcLoop.Play, glow.ProcLoop)
            end
            return
        end
        glow:Show()
        if glow.ProcStartAnim and glow.ProcStartAnim.Play then
            pcall(glow.ProcStartAnim.Play, glow.ProcStartAnim)
        elseif glow.ProcLoop and glow.ProcLoop.Play then
            pcall(glow.ProcLoop.Play, glow.ProcLoop)
        end
    else
        self._procGlowActive = false
        local glow = f._procGlow
        if not glow then return end
        if glow.ProcLoop and glow.ProcLoop.Stop and glow.ProcLoop.IsPlaying and glow.ProcLoop:IsPlaying() then
            pcall(glow.ProcLoop.Stop, glow.ProcLoop)
        end
        if glow.ProcStartAnim and glow.ProcStartAnim.Stop and glow.ProcStartAnim.IsPlaying and glow.ProcStartAnim:IsPlaying() then
            pcall(glow.ProcStartAnim.Stop, glow.ProcStartAnim)
        end
        glow:Hide()
    end
end

local function applyState(self_)
    local f = self_.frame
    if not f then return end
    if self_._state == "hidden" then
        f:SetAlpha(0)
        if f.icon then f.icon:SetDesaturated(false) end
    elseif self_._state == "disabled" then
        f:SetAlpha(0.4)
        if f.icon then f.icon:SetDesaturated(true) end
    else
        f:SetAlpha(1)
        if f.icon then f.icon:SetDesaturated(self_._opts.desaturated and true or false) end
    end
end

function Icon:Show()
    self.frame:Show()
    applyState(self)
end

function Icon:Hide()
    self.frame:Hide()
end

function Icon:SetShown(shown)
    if shown then
        self:Show()
    else
        self:Hide()
    end
end

function Icon:SetState(state)
    if state ~= "live" and state ~= "hidden" and state ~= "disabled" then
        return
    end
    self._state = state
    applyState(self)
end

function Icon:GetState()
    return self._state
end

function Icon:Destroy()
    local f = self.frame
    if f then
        if f.cooldown then
            f.cooldown:Clear()
        end
        f:Hide()
        f:ClearAllPoints()
        f:SetParent(nil)
    end
    self.frame = nil
end
