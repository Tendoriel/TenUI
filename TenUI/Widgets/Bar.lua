local addonName, ns = ...

ns.Widgets = ns.Widgets or {}

local CreateFrame = CreateFrame
local setmetatable = setmetatable

local Widgets = ns.Widgets
local resolveMedia

local Bar = {}
Bar.__index = Bar
Widgets.Bar = Bar

local DEFAULT_OPTS = {
    texture     = nil,
    orientation = "HORIZONTAL",
    reverseFill = false,
    bgAlpha     = 0.4,
    fgColor     = { 1, 1, 1, 1 },
    bgColor     = { 0, 0, 0, 0.6 },
    border      = true,
    borderColor = { 0, 0, 0, 1 },
    leftText    = false,
    rightText   = false,
    font        = nil,
    fontSize    = 12,
    fontFlags   = "OUTLINE",
}

local function applyColor(tex, c)
    if not tex or not c then return end
    tex:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
end

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

function Bar:New(parent, opts)
    resolveMedia = resolveMedia or Widgets.resolveMedia
    opts = opts or {}

    local self_ = setmetatable({}, Bar)
    self_._opts = opts
    self_._state = "live"

    local f = CreateFrame("StatusBar", nil, parent, "BackdropTemplate")
    f:SetAllPoints(parent)
    f:SetMinMaxValues(0, 1)
    f:SetValue(0)
    f:SetOrientation(opts.orientation or DEFAULT_OPTS.orientation)
    f:SetReverseFill(opts.reverseFill and true or false)

    local texPath = resolveMedia("statusbar", opts.texture, Widgets.DEFAULT_STATUSBAR)
    f:SetStatusBarTexture(texPath)

    local fgC = opts.fgColor or DEFAULT_OPTS.fgColor
    f:SetStatusBarColor(fgC[1] or 1, fgC[2] or 1, fgC[3] or 1, fgC[4] or 1)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetTexture(texPath)
    local bgC = opts.bgColor or DEFAULT_OPTS.bgColor
    local bgA = opts.bgAlpha or DEFAULT_OPTS.bgAlpha
    bg:SetVertexColor(bgC[1] or 0, bgC[2] or 0, bgC[3] or 0, (bgC[4] or 1) * bgA)
    f.bg = bg

    if opts.border ~= false then
        local borderColor = opts.borderColor or DEFAULT_OPTS.borderColor
        f.border = makeBorder(f, borderColor)
    end

    local fontPath = resolveMedia("font", opts.font, Widgets.DEFAULT_FONT)
    local fontSize = opts.fontSize or DEFAULT_OPTS.fontSize
    local fontFlags = opts.fontFlags or DEFAULT_OPTS.fontFlags

    if opts.leftText then
        local fs = f:CreateFontString(nil, "OVERLAY")
        fs:SetFont(fontPath, fontSize, fontFlags)
        fs:SetPoint("LEFT", f, "LEFT", 4, 0)
        fs:SetJustifyH("LEFT")
        fs:SetTextColor(1, 1, 1, 1)
        f.leftText = fs
    end

    if opts.rightText then
        local fs = f:CreateFontString(nil, "OVERLAY")
        fs:SetFont(fontPath, fontSize, fontFlags)
        fs:SetPoint("RIGHT", f, "RIGHT", -4, 0)
        fs:SetJustifyH("RIGHT")
        fs:SetTextColor(1, 1, 1, 1)
        f.rightText = fs
    end

    self_.frame = f
    return self_
end

function Bar:SetMinMaxValues(minV, maxV)
    self.frame:SetMinMaxValues(minV, maxV)
    local secret = (type(issecretvalue) == "function") and issecretvalue
    if secret and (secret(minV) or secret(maxV)) then return end
    if type(minV) == "number" and type(maxV) == "number" then
        self._thlLastMin = minV
        self._thlLastMax = maxV
    end
end

function Bar:SetValue(v)
    self.frame:SetValue(v)
end

function Bar:SetTexture(textureOrKey)
    local path = (Widgets.resolveMedia or resolveMedia)("statusbar", textureOrKey, Widgets.DEFAULT_STATUSBAR)
    self.frame:SetStatusBarTexture(path)
    if self.frame.bg then
        self.frame.bg:SetTexture(path)
    end
end

function Bar:SetColor(r, g, b, a)
    self.frame:SetStatusBarColor(r or 1, g or 1, b or 1, a or 1)
end

function Bar:SetBackgroundColor(r, g, b, a)
    if not self.frame.bg then return end
    self.frame.bg:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
end

function Bar:SetOrientation(o)
    self.frame:SetOrientation(o or "HORIZONTAL")
end

function Bar:SetReverseFill(b)
    self.frame:SetReverseFill(b and true or false)
end

function Bar:SetTimerDuration(durationObject, interpolation, direction)
    if not self.frame or not self.frame.SetTimerDuration then return false end
    local durSecret = type(issecretvalue) == "function" and issecretvalue(durationObject)
    if not durSecret and not durationObject then return false end
    local ok, err = pcall(self.frame.SetTimerDuration, self.frame,
        durationObject, interpolation, direction)
    if not ok then
        if ns.Debug and ns.Debug.Log then
            ns.Debug:Log("Bar:SetTimerDuration rejected: " .. tostring(err))
        end
        return false
    end
    return true
end

function Bar:SetLeftText(text)
    if not self.frame.leftText then return end
    self.frame.leftText:SetText(text or "")
end

function Bar:SetRightText(text)
    if not self.frame.rightText then return end
    self.frame.rightText:SetText(text or "")
end

function Bar:SetFont(fontKey, size, flags)
    local fontPath = (Widgets.resolveMedia or resolveMedia)("font", fontKey, Widgets.DEFAULT_FONT)
    size = size or 12
    flags = flags or "OUTLINE"
    if self.frame.leftText then
        self.frame.leftText:SetFont(fontPath, size, flags)
    end
    if self.frame.rightText then
        self.frame.rightText:SetFont(fontPath, size, flags)
    end
end

function Bar:SetBorder(enabled, color)
    if enabled then
        if not self.frame.border then
            self.frame.border = makeBorder(self.frame, color or { 0, 0, 0, 1 })
        else
            local c = color or { 0, 0, 0, 1 }
            for _, t in pairs(self.frame.border) do
                t:SetColorTexture(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1)
                t:Show()
            end
        end
    else
        if self.frame.border then
            for _, t in pairs(self.frame.border) do
                t:Hide()
            end
        end
    end
end

function Bar:SetBackground(enabled, r, g, b, a)
    local bg = self.frame and self.frame.bg
    if not bg then return end
    bg:SetShown(enabled ~= false)
    if r ~= nil then
        bg:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
    end
end

local STATE_LIVE     = "live"
local STATE_HIDDEN   = "hidden"
local STATE_DISABLED = "disabled"

local function applyState(self_)
    local f = self_.frame
    if not f then return end
    if self_._state == STATE_HIDDEN then
        f:SetAlpha(0)
    elseif self_._state == STATE_DISABLED then
        f:SetAlpha(0.4)
    else
        f:SetAlpha(1)
    end
end

function Bar:Show()
    self.frame:Show()
    applyState(self)
end

function Bar:Hide()
    self.frame:Hide()
end

function Bar:SetState(state)
    if state ~= STATE_LIVE and state ~= STATE_HIDDEN and state ~= STATE_DISABLED then
        return
    end
    self._state = state
    applyState(self)
end

function Bar:GetState()
    return self._state
end

function Bar:Destroy()
    local f = self.frame
    if f then
        f:Hide()
        f:ClearAllPoints()
        f:SetParent(nil)
    end
    self.frame = nil
end
