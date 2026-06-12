local addonName, ns = ...

local CreateFrame = CreateFrame
local pcall       = pcall

ns.CooldownProbe = ns.CooldownProbe or {}
local CooldownProbe = ns.CooldownProbe

local function ensureScratch(self)
    if self._frame then return self._frame end
    local parent = CreateFrame("Frame")
    parent:Hide()
    self._parent = parent
    local f = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
    f:SetSize(1, 1)
    f:SetAlpha(0)
    f:EnableMouse(false)
    f:SetPoint("CENTER", parent, "CENTER", 0, 0)
    f:Hide()
    self._frame = f
    return f
end

function CooldownProbe:IsLive(durObj)
    if not durObj then return false end
    local f = ensureScratch(self)
    if not f then return false end
    local ok = pcall(f.SetCooldownFromDurationObject, f, durObj)
    if not ok then return false end
    return f:IsShown() and true or false
end

function CooldownProbe:Clear()
    if not self._frame then return end
    pcall(self._frame.Clear, self._frame)
end
