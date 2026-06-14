local addonName, ns = ...

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local GameTooltip = GameTooltip
local IsShiftKeyDown = IsShiftKeyDown
local pairs = pairs
local type = type
local tonumber = tonumber
local math = math

local EditMode = {}
ns.EditMode = EditMode

local editModeActive = false

local overlays = {}

local OVERLAY_BG            = { 0, 0, 0, 0.55 }
local OVERLAY_EDGE         = { 1, 1, 1, 0.30 }
local OVERLAY_EDGE_SELECTED = { 0.31, 0.76, 0.97, 0.95 }
local OVERLAY_BG_SELECTED   = { 0.06, 0.18, 0.24, 0.65 }
local LABEL_COLOR          = { 1, 1, 1 }

local selectedOverlay = nil

local NUDGE_SIZE          = 14
local NUDGE_GAP           = 3
local NUDGE_REPEAT_DELAY  = 0.35
local NUDGE_REPEAT_PERIOD = 0.10
local NUDGE_COARSE        = 10
local NUDGE_FINE          = 1
local NUDGE_BG            = { 0.05, 0.05, 0.05, 0.85 }
local NUDGE_BG_HOVER      = { 0.31, 0.76, 0.97, 0.95 }
local NUDGE_ARROW_COLOR   = { 1, 1, 1, 0.9 }

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
    return { top, bottom, left, right }
end

local function setBorderColor(sides, c)
    if not sides then return end
    for i = 1, #sides do
        sides[i]:SetColorTexture(c[1], c[2], c[3], c[4])
    end
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
    self._wasDrag = true
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

local function nudgeAnchor(anchorName, dx, dy)
    if not anchorName then return end
    if ns:AreAnchorsLocked() then return end
    if not (ns.Anchors and ns.Anchors.SetPositionDirect) then return end
    local entry = ns.Anchors:ResolveEntry(anchorName)
    local cx = (entry and tonumber(entry.x)) or 0
    local cy = (entry and tonumber(entry.y)) or 0
    ns.Anchors:SetPositionDirect(anchorName, cx + dx, cy + dy)
    if ns.Auras and type(ns.Auras.RequestRefresh) == "function" then
        pcall(ns.Auras.RequestRefresh, ns.Auras)
    end
    local savedAnchors = ns and ns.savedVarsReady and ns:GetProfile() and ns:GetProfile().anchors
    local savedEntry = savedAnchors and savedAnchors[anchorName]
    local nx, ny
    if savedEntry then
        nx, ny = savedEntry.x or (cx + dx), savedEntry.y or (cy + dy)
    else
        nx, ny = cx + dx, cy + dy
    end
    ns:Fire("ANCHOR_MOVED", anchorName, nx, ny)
end

local function nudge_step(self)
    local overlay = self:GetParent()
    local anchor = overlay and overlay.anchor
    if not anchor then return end
    local mult = IsShiftKeyDown() and NUDGE_COARSE or NUDGE_FINE
    nudgeAnchor(anchor.anchorName, self.dx * mult, self.dy * mult)
end

local function nudge_OnUpdate(self, elapsed)
    self._held = (self._held or 0) + elapsed
    if self._held < NUDGE_REPEAT_DELAY then return end
    self._accum = (self._accum or 0) + elapsed
    while self._accum >= NUDGE_REPEAT_PERIOD do
        self._accum = self._accum - NUDGE_REPEAT_PERIOD
        nudge_step(self)
    end
end

local function nudge_OnMouseDown(self)
    if ns:AreAnchorsLocked() then return end
    nudge_step(self)
    self._held = 0
    self._accum = 0
    self:SetScript("OnUpdate", nudge_OnUpdate)
    self.bg:SetColorTexture(NUDGE_BG_HOVER[1], NUDGE_BG_HOVER[2], NUDGE_BG_HOVER[3], NUDGE_BG_HOVER[4])
end

local function nudge_OnMouseUp(self)
    self:SetScript("OnUpdate", nil)
    self._held = nil
    self._accum = nil
    self.bg:SetColorTexture(NUDGE_BG[1], NUDGE_BG[2], NUDGE_BG[3], NUDGE_BG[4])
end

local function overlayFocused(overlay)
    if not overlay then return false end
    if overlay._selected then return true end
    if overlay:IsMouseOver() then return true end
    if overlay.nudges then
        for _, b in pairs(overlay.nudges) do
            if b:IsShown() and b:IsMouseOver() then return true end
        end
    end
    return false
end

local function showNudges(overlay)
    if not overlay or not overlay.nudges then return end
    for _, b in pairs(overlay.nudges) do
        b:Show()
    end
end

local function hideNudges(overlay)
    if not overlay or not overlay.nudges then return end
    for _, b in pairs(overlay.nudges) do
        b:SetScript("OnUpdate", nil)
        b._held = nil
        b._accum = nil
        b.bg:SetColorTexture(NUDGE_BG[1], NUDGE_BG[2], NUDGE_BG[3], NUDGE_BG[4])
        b:Hide()
    end
end

local function applySelectedVisual(overlay)
    if not overlay then return end
    setBorderColor(overlay.border, OVERLAY_EDGE_SELECTED)
    if overlay.bg then
        overlay.bg:SetColorTexture(OVERLAY_BG_SELECTED[1], OVERLAY_BG_SELECTED[2],
            OVERLAY_BG_SELECTED[3], OVERLAY_BG_SELECTED[4])
    end
end

local function applyDeselectedVisual(overlay)
    if not overlay then return end
    setBorderColor(overlay.border, OVERLAY_EDGE)
    if overlay.bg then
        overlay.bg:SetColorTexture(OVERLAY_BG[1], OVERLAY_BG[2], OVERLAY_BG[3], OVERLAY_BG[4])
    end
end

local function deselectOverlay(overlay)
    if not overlay then return end
    overlay._selected = false
    if selectedOverlay == overlay then selectedOverlay = nil end
    applyDeselectedVisual(overlay)
    if not overlayFocused(overlay) then
        overlay._hover = false
        hideNudges(overlay)
    end
end

local function clearSelection()
    if selectedOverlay then
        deselectOverlay(selectedOverlay)
    end
    selectedOverlay = nil
end

local function selectOverlay(overlay)
    if not overlay then return end
    if selectedOverlay and selectedOverlay ~= overlay then
        deselectOverlay(selectedOverlay)
    end
    selectedOverlay = overlay
    overlay._selected = true
    applySelectedVisual(overlay)
    showNudges(overlay)
end

local function nudge_OnEnter(self)
    local overlay = self:GetParent()
    if overlay then overlay._hover = true end
    showNudges(overlay)
    self.bg:SetColorTexture(NUDGE_BG_HOVER[1], NUDGE_BG_HOVER[2], NUDGE_BG_HOVER[3], NUDGE_BG_HOVER[4])
end

local function nudge_OnLeave(self)
    self:SetScript("OnUpdate", nil)
    self._held = nil
    self._accum = nil
    self.bg:SetColorTexture(NUDGE_BG[1], NUDGE_BG[2], NUDGE_BG[3], NUDGE_BG[4])
    local overlay = self:GetParent()
    if overlay and not overlayFocused(overlay) then
        overlay._hover = false
        hideNudges(overlay)
    end
end

local function overlay_OnMouseDown(self, button)
    if button ~= "LeftButton" then return end
    self._wasDrag = false
end

local function overlay_OnMouseUp(self, button)
    if button ~= "LeftButton" then return end
    if self._wasDrag or self._dragging then
        self._wasDrag = false
        return
    end
    if ns:AreAnchorsLocked() then return end
    if self._selected then
        deselectOverlay(self)
    else
        selectOverlay(self)
    end
end

local NUDGE_DEFS = {
    { key = "up",    dx =  0, dy =  1, point = "BOTTOM", rel = "TOP",    ox =  0, oy =  NUDGE_GAP },
    { key = "down",  dx =  0, dy = -1, point = "TOP",    rel = "BOTTOM", ox =  0, oy = -NUDGE_GAP },
    { key = "left",  dx = -1, dy =  0, point = "RIGHT",  rel = "LEFT",   ox = -NUDGE_GAP, oy =  0 },
    { key = "right", dx =  1, dy =  0, point = "LEFT",   rel = "RIGHT",  ox =  NUDGE_GAP, oy =  0 },
}

local function makeNudgeButton(overlay, def)
    local b = CreateFrame("Button", nil, overlay)
    b:SetSize(NUDGE_SIZE, NUDGE_SIZE)
    b:SetPoint(def.point, overlay, def.rel, def.ox, def.oy)
    b:SetFrameLevel(overlay:GetFrameLevel() + 2)
    b.dx = def.dx
    b.dy = def.dy

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(NUDGE_BG[1], NUDGE_BG[2], NUDGE_BG[3], NUDGE_BG[4])
    b.bg = bg

    local arrow = b:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
    arrow:SetVertexColor(NUDGE_ARROW_COLOR[1], NUDGE_ARROW_COLOR[2], NUDGE_ARROW_COLOR[3], NUDGE_ARROW_COLOR[4])
    arrow:SetSize(NUDGE_SIZE - 2, NUDGE_SIZE - 2)
    arrow:SetPoint("CENTER", b, "CENTER", 0, -1)
    if def.key == "up" then
        arrow:SetRotation(0)
    elseif def.key == "down" then
        arrow:SetRotation(math.pi)
    elseif def.key == "left" then
        arrow:SetRotation(math.pi * 0.5)
    else
        arrow:SetRotation(math.pi * 1.5)
    end
    b.arrow = arrow

    b:EnableMouse(true)
    b:SetScript("OnMouseDown", nudge_OnMouseDown)
    b:SetScript("OnMouseUp", nudge_OnMouseUp)
    b:SetScript("OnEnter", nudge_OnEnter)
    b:SetScript("OnLeave", nudge_OnLeave)
    b:Hide()
    return b
end

local function overlay_OnEnter(self)
    self._hover = true
    showNudges(self)
    local anchor = self.anchor
    if not anchor then return end
    local label = anchor.def and anchor.def.label or anchor.anchorName
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(label)
    GameTooltip:AddLine("Drag to move", 1, 1, 1)
    GameTooltip:AddLine("Click to select (pins the edge arrows)", 1, 1, 1)
    GameTooltip:AddLine("Edge arrows nudge 1px (Shift = 10px)", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Size is set in Options > Layout", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function overlay_OnLeave(self)
    GameTooltip:Hide()
    if not overlayFocused(self) then
        self._hover = false
        hideNudges(self)
    end
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

    f.border = makeBorder(f, OVERLAY_EDGE)

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
    f:SetScript("OnMouseDown", overlay_OnMouseDown)
    f:SetScript("OnMouseUp", overlay_OnMouseUp)
    f:SetScript("OnEnter", overlay_OnEnter)
    f:SetScript("OnLeave", overlay_OnLeave)

    f.nudges = {}
    for i = 1, #NUDGE_DEFS do
        local def = NUDGE_DEFS[i]
        f.nudges[def.key] = makeNudgeButton(f, def)
    end

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
    if not editModeActive then
        clearSelection()
    end
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
            if not overlayFocused(o) then
                o._hover = false
                hideNudges(o)
            end
        else
            anchor:EnableMouse(false)
            anchor:SetMovable(false)
            local o = overlays[name]
            if o then
                o:EnableMouse(false)
                o._hover = false
                o._selected = false
                applyDeselectedVisual(o)
                hideNudges(o)
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
