local addonName, ns = ...

local CreateFrame = CreateFrame
local UIParent    = UIParent
local math_abs    = math.abs

local QoLDrag = {}
ns.QoLDrag = QoLDrag

local SNAP_THRESHOLD = 10

local guide

local function getGuide()
    if guide then return guide end
    guide = CreateFrame("Frame", nil, UIParent)
    guide:SetFrameStrata("TOOLTIP")
    guide:SetWidth(1)
    guide:SetPoint("TOP", UIParent, "TOP", 0, 0)
    guide:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
    guide:EnableMouse(false)
    local tex = guide:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(guide)
    tex:SetColorTexture(0.2, 0.9, 0.4, 0.75)
    guide:Hide()
    return guide
end

local function centerOffset(frame)
    local cx, cy = frame:GetCenter()
    local px, py = UIParent:GetCenter()
    if not (cx and cy and px and py) then return nil end
    local fs = frame:GetEffectiveScale() or 1
    local us = UIParent:GetEffectiveScale() or 1
    if fs ~= us and us > 0 then
        cx = cx * fs / us
        cy = cy * fs / us
    end
    return cx - px, cy - py
end

QoLDrag.CenterOffset = centerOffset

function QoLDrag.Attach(frame, getOpts, onStop)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)

    frame:SetScript("OnDragStart", function(self)
        if self._locked ~= false then return end
        self._dragging = true
        self:StartMoving()
        self:SetScript("OnUpdate", function(s)
            local dx = centerOffset(s)
            local g = getGuide()
            if dx and math_abs(dx) <= SNAP_THRESHOLD then
                g:Show()
            else
                g:Hide()
            end
        end)
    end)

    frame:SetScript("OnDragStop", function(self)
        if not self._dragging then return end
        self._dragging = false
        self:SetScript("OnUpdate", nil)
        if guide then guide:Hide() end
        self:StopMovingOrSizing()

        local o = getOpts and getOpts()
        if not o then return end

        local dx, dy = centerOffset(self)
        if not dx then return end
        if math_abs(dx) <= SNAP_THRESHOLD then dx = 0 end

        o.point = "CENTER"
        o.x = dx
        o.y = dy
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", dx, dy)

        if onStop then onStop(o) end
    end)
end
