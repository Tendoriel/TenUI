local addonName, ns = ...

ns.Widgets = ns.Widgets or {}

local CreateFrame = CreateFrame
local setmetatable = setmetatable

local Widgets = ns.Widgets
local Text = {}
Text.__index = Text
Widgets.Text = Text

function Text:New(parent, opts)
    opts = opts or {}
    local resolveMedia = Widgets.resolveMedia
    local self_ = setmetatable({}, Text)
    self_._opts = opts
    self_._state = "live"

    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)

    local fontPath = resolveMedia("font", opts.font, Widgets.DEFAULT_FONT)
    local size = opts.fontSize or 14
    local flags = opts.fontFlags or "OUTLINE"

    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetFont(fontPath, size, flags)
    fs:SetAllPoints(f)
    fs:SetJustifyH(opts.justifyH or "CENTER")
    fs:SetJustifyV(opts.justifyV or "MIDDLE")

    local c = opts.color or { 1, 1, 1, 1 }
    fs:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)

    if opts.shadow ~= false then
        local sc = opts.shadowColor or { 0, 0, 0, 1 }
        fs:SetShadowColor(sc[1] or 0, sc[2] or 0, sc[3] or 0, sc[4] or 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowColor(0, 0, 0, 0)
        fs:SetShadowOffset(0, 0)
    end

    if opts.text then
        fs:SetText(opts.text)
    end

    f.text = fs
    self_.frame = f
    return self_
end

function Text:SetText(s)
    self.frame.text:SetText(s or "")
end

function Text:SetColor(r, g, b, a)
    self.frame.text:SetTextColor(r or 1, g or 1, b or 1, a or 1)
end

function Text:SetFont(fontKey, size, flags)
    local fontPath = (Widgets.resolveMedia)("font", fontKey, Widgets.DEFAULT_FONT)
    self.frame.text:SetFont(fontPath, size or 14, flags or "OUTLINE")
end

function Text:SetJustifyH(j)
    self.frame.text:SetJustifyH(j or "CENTER")
end

function Text:SetJustifyV(j)
    self.frame.text:SetJustifyV(j or "MIDDLE")
end

function Text:SetShadow(enabled, color)
    local fs = self.frame.text
    if enabled then
        local c = color or { 0, 0, 0, 1 }
        fs:SetShadowColor(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowColor(0, 0, 0, 0)
        fs:SetShadowOffset(0, 0)
    end
end

local function applyState(self_)
    local f = self_.frame
    if not f then return end
    if self_._state == "hidden" then
        f:SetAlpha(0)
    elseif self_._state == "disabled" then
        f:SetAlpha(0.4)
    else
        f:SetAlpha(1)
    end
end

function Text:Show()
    self.frame:Show()
    applyState(self)
end

function Text:Hide()
    self.frame:Hide()
end

function Text:SetState(state)
    if state ~= "live" and state ~= "hidden" and state ~= "disabled" then
        return
    end
    self._state = state
    applyState(self)
end

function Text:GetState()
    return self._state
end

function Text:Destroy()
    local f = self.frame
    if f then
        f:Hide()
        f:ClearAllPoints()
        f:SetParent(nil)
    end
    self.frame = nil
end
