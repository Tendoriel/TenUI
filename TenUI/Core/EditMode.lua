local addonName, ns = ...

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local GameTooltip = GameTooltip
local pairs = pairs
local type = type

local EditMode = {}
ns.EditMode = EditMode

local editModeActive = false

local overlays = {}

local OVERLAY_BG   = { 0, 0, 0, 0.55 }
local OVERLAY_EDGE = { 1, 1, 1, 0.30 }
local LABEL_COLOR  = { 1, 1, 1 }

local function out(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7TenUI|r: " .. tostring(msg))
end

local function makeBorder(parent, edgeColor)
    local r, g, b, a = edgeColor[1], edgeColor[2], edgeColor[3], edgeColor[4]
    local function side()
        local t = parent:CreateTexture(nil, "BORDER")
        t:SetColorTexture(r, g, b, a)
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
end

local function overlayCenterRelative(self)
    local fx, fy = self:GetCenter()
    local p = self:GetParent()
    local px, py
    if p then px, py = p:GetCenter() end
    if not fx or not fy or not px or not py then return nil end
    return fx - px, fy - py
end

local function overlay_OnUpdate(self)
    local anchor = self.anchor
    if not anchor or not self._dragging then return end
    local cx, cy = overlayCenterRelative(self)
    if not cx then return end
    local _, _, gx, gy = ns.Anchors:GetSnapPoint(cx, cy,
        self:GetWidth() or 0, self:GetHeight() or 0, anchor.anchorName)
    ns.Anchors:UpdateSnapGuides(gx, gy)
end

local function overlay_OnDragStart(self)
    if ns:AreAnchorsLocked() then return end
    local anchor = self.anchor
    if not anchor then return end
    self._dragging = true
    self:ClearAllPoints()
    local p, _, rp, x, y = anchor:GetPoint(1)
    if p then
        self:SetPoint(p, anchor:GetParent(), rp or p, x or 0, y or 0)
    else
        self:SetPoint("CENTER", anchor:GetParent(), "CENTER", 0, 0)
    end
    self:SetSize(anchor:GetWidth() or 200, anchor:GetHeight() or 32)
    self:SetMovable(true)
    self:StartMoving()
    if ns.Anchors and ns.Anchors.IsSnapEnabled and ns.Anchors:IsSnapEnabled() then
        self:SetScript("OnUpdate", overlay_OnUpdate)
    end
end

local function overlay_OnDragStop(self)
    self:SetScript("OnUpdate", nil)
    if ns.Anchors and ns.Anchors.HideSnapGuides then
        ns.Anchors:HideSnapGuides()
    end
    local anchor = self.anchor
    if not anchor then
        self._dragging = false
        return
    end
    self:StopMovingOrSizing()
    self._dragging = false
    if ns.Anchors and ns.Anchors.GetSnapPoint
       and ns.Anchors.IsSnapEnabled and ns.Anchors:IsSnapEnabled() then
        local cx, cy = overlayCenterRelative(self)
        if cx then
            local sx, sy = ns.Anchors:GetSnapPoint(cx, cy,
                self:GetWidth() or 0, self:GetHeight() or 0, anchor.anchorName)
            if sx ~= cx or sy ~= cy then
                self:ClearAllPoints()
                self:SetPoint("CENTER", anchor:GetParent(), "CENTER", sx, sy)
            end
        end
    end
    local livePoint, liveParent, liveRel, liveX, liveY = self:GetPoint(1)
    if livePoint then
        anchor:ClearAllPoints()
        anchor:SetPoint(livePoint, anchor:GetParent(), liveRel or livePoint,
            liveX or 0, liveY or 0)
    end
    self:ClearAllPoints()
    self:SetAllPoints(anchor)
    if ns.Anchors and ns.Anchors.PushTrace then
        ns.Anchors:PushTrace(anchor.anchorName, "DRAGSTOP", {
            point = livePoint, rel = liveRel,
            x = liveX, y = liveY,
        })
    end
    if ns.Debug and ns.Debug.Log then
        ns.Debug:Log("[Anchor] DRAGSTOP name=%s live=%s,%s,%.2f,%.2f",
            anchor.anchorName,
            tostring(livePoint), tostring(liveRel),
            liveX or 0, liveY or 0)
    end
    ns.Anchors:SavePosition(anchor)
    do
        local savedAnchors = ns and ns.savedVarsReady and ns:GetProfile() and ns:GetProfile().anchors
        local savedEntry   = savedAnchors and savedAnchors[anchor.anchorName]
        if savedEntry then
            ns:Fire("ANCHOR_MOVED", anchor.anchorName, savedEntry.x or 0, savedEntry.y or 0)
        elseif liveX then
            ns:Fire("ANCHOR_MOVED", anchor.anchorName, math.floor((liveX or 0) + 0.5), math.floor((liveY or 0) + 0.5))
        end
    end
end

local function overlay_OnEnter(self)
    local anchor = self.anchor
    if not anchor then return end
    local label = anchor.def and anchor.def.label or anchor.anchorName
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(label)
    GameTooltip:AddLine("Drag to move", 1, 1, 1)
    GameTooltip:AddLine("Size is set in Options > Layout", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function overlay_OnLeave(self)
    GameTooltip:Hide()
end

local function createOverlay(anchor)
    local overlayParent = anchor:GetParent() or anchor
    local f = CreateFrame("Frame", "TenUIAnchorOverlay_" .. anchor.anchorName, overlayParent)
    f:SetAllPoints(anchor)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel((anchor:GetFrameLevel() or 0) + 5)
    f.anchor = anchor

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(OVERLAY_BG[1], OVERLAY_BG[2], OVERLAY_BG[3], OVERLAY_BG[4])
    f.bg = bg

    makeBorder(f, OVERLAY_EDGE)

    local label = f:CreateFontString(nil, "OVERLAY")
    label:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    label:SetPoint("CENTER", f, "CENTER", 0, 0)
    label:SetTextColor(LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], 1)
    label:SetText(anchor.def and anchor.def.label or anchor.anchorName)
    f.label = label

    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", overlay_OnDragStart)
    f:SetScript("OnDragStop", overlay_OnDragStop)
    f:SetScript("OnEnter", overlay_OnEnter)
    f:SetScript("OnLeave", overlay_OnLeave)

    f:Hide()
    return f
end

local function ensureOverlay(anchor)
    local f = overlays[anchor.anchorName]
    if not f then
        f = createOverlay(anchor)
        overlays[anchor.anchorName] = f
        local runtime = anchor.runtime
        if runtime then runtime.overlay = f end
    end
    return f
end

local function requestAurasPreviewRefresh()
    if ns.Auras and type(ns.Auras.RequestRefresh) == "function" then
        pcall(ns.Auras.RequestRefresh, ns.Auras)
    end
end

local function syncAurasBarPreviewAuto()
    if ns.Auras and type(ns.Auras.SetBarPreviewAuto) == "function" then
        pcall(ns.Auras.SetBarPreviewAuto, ns.Auras, editModeActive == true)
    end
end

local function applyState()
    syncAurasBarPreviewAuto()
    requestAurasPreviewRefresh()
    if not editModeActive and ns.Anchors and ns.Anchors.HideSnapGuides then
        ns.Anchors:HideSnapGuides()
    end
    if ns.Anchors and ns.Anchors.SetGridEditModeActive then
        ns.Anchors:SetGridEditModeActive(editModeActive)
    end
    if not editModeActive and ns.CastBar and ns.CastBar.icon
       and ns.CastBar._state == "idle" then
        ns.CastBar.icon:Hide()
    end
    for name, anchor in ns.Anchors:Iterate() do
        if editModeActive then
            anchor:SetMovable(true)
            anchor:EnableMouse(false)
            local o = ensureOverlay(anchor)
            if not o._dragging then
                o:SetAllPoints(anchor)
            end
            if o.label and anchor.def then
                o.label:SetText(anchor.def.label or anchor.anchorName)
            end
            o:EnableMouse(true)
            o:Show()
        else
            anchor:EnableMouse(false)
            anchor:SetMovable(false)
            local o = overlays[name]
            if o then
                o:EnableMouse(false)
                o:Hide()
            end
        end
    end
end

function EditMode:Enable()
    if InCombatLockdown() then
        return false
    end
    editModeActive = true
    applyState()
    return true
end

function EditMode:Disable()
    editModeActive = false
    applyState()
end

function EditMode:IsActive()
    return editModeActive
end

function EditMode:Refresh()
    applyState()
end

function EditMode:RefreshOne(anchor)
    if not anchor then return end
    local o = overlays[anchor.anchorName]
    if not o then return end
    if o._dragging then return end
    o:SetAllPoints(anchor)
    if o.label and anchor.def then
        o.label:SetText(anchor.def.label or anchor.anchorName)
    end
end

ns:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    ns._lockBeforeCombat = (ns.db and ns.db.locked) and true or false
    if editModeActive then
        editModeActive = false
        applyState()
        out("anchors locked for combat")
    end
end)

ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if ns._lockBeforeCombat == false then
        editModeActive = true
        applyState()
    end
    ns._lockBeforeCombat = nil
end)

local function syncFromDb()
    if not ns.db then return end
    if ns.db.locked then
        editModeActive = false
    else
        if InCombatLockdown() then
            editModeActive = false
            ns._lockBeforeCombat = false
        else
            editModeActive = true
        end
    end
    applyState()
end

ns:RegisterMessage("SAVEDVARS_READY", function()
    syncFromDb()
end)

ns:RegisterEvent("PLAYER_LOGIN", function()
    syncFromDb()
end)

ns:RegisterMessage("PROFILE_CHANGED", function()
    syncFromDb()
end)

ns:RegisterMessage("LOCK_STATE_CHANGED", function(_, locked)
    syncFromDb()
end)
