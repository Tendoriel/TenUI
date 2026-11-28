local _, ns = ...
local active, retired, pool = {}, {}, {}
local deferred = setmetatable({}, { __mode = "k" })
local gate

local function release(button)
    button:Hide()
    button:ClearAllPoints()
    for _, attr in ipairs({ "type1", "item1", "spell1", "unit1", "target-slot1" }) do button:SetAttribute(attr, nil) end
    button.actionKind, button.actionValue, button.slot = nil, nil, nil
    pool[#pool + 1] = button
end

function ns.ReleaseHUDAction(owner)
    if owner then deferred[owner] = nil end
    local button = owner and owner._actionButton
    if not button then return end
    active[owner], owner._actionButton, button.owner = nil, nil, nil
    if InCombatLockdown() then retired[button] = true else release(button) end
end

local function position(owner, button)
    if not owner:GetParent() or not owner:IsVisible() or owner:GetEffectiveAlpha() == 0
        or (ns.db and ns.db.locked == false) or (ns.EditMode and ns.EditMode:IsActive()) then
        button:Hide()
        return
    end
    local x, y = owner:GetCenter()
    if not x or not y then button:Hide() return end
    local scale = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
    button:ClearAllPoints()
    button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * scale, y * scale)
    button:SetSize(owner:GetWidth() * scale, owner:GetHeight() * scale)
    button:SetFrameStrata(owner:GetFrameStrata())
    button:SetFrameLevel(owner:GetFrameLevel() + 1)
    button:Show()
end

local function forward(button, script)
    local owner = button.owner
    local fn = owner and owner:GetScript(script)
    if fn then fn(owner) end
end

local function refresh()
    if InCombatLockdown() then return end
    for button in pairs(retired) do retired[button] = nil release(button) end
    for owner, request in pairs(deferred) do
        deferred[owner] = nil
        if owner:GetParent() then ns.SyncHUDAction(owner, request.kind, request.value, request.slot) end
    end
    for owner, button in pairs(active) do position(owner, button) end
    if gate then gate:Show() end
end

local queued
function ns.RefreshHUDActions()
    if (not gate and not next(deferred)) or InCombatLockdown() or queued then return end
    queued = true
    C_Timer.After(0, function() queued = nil refresh() end)
end

function ns.SyncHUDAction(owner, kind, value, slot)
    if not value then ns.ReleaseHUDAction(owner) return end
    if InCombatLockdown() then
        deferred[owner] = {kind=kind, value=value, slot=slot}
        return
    end
    deferred[owner] = nil
    if not gate then
        gate = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
        gate:SetAllPoints(UIParent)
        -- Keep the gate closed on combat exit until retired buttons are drained.
        gate:SetAttribute("_onstate-combat", 'if newstate == "1" then self:Hide() end')
        RegisterStateDriver(gate, "combat", "[combat] 1; 0")
        ns:RegisterEvent("UI_SCALE_CHANGED", ns.RefreshHUDActions)
        for _, event in ipairs({ "ANCHOR_MOVED", "ANCHOR_RESIZED", "GLOBAL_SCALE_CHANGED", "LOCK_STATE_CHANGED" }) do
            ns:RegisterMessage(event, ns.RefreshHUDActions)
        end
    end
    local button = active[owner] or table.remove(pool)
    if not button then
        button = CreateFrame("Button", nil, gate, "SecureActionButtonTemplate")
        button:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
        if button.SetPassThroughButtons then button:SetPassThroughButtons("RightButton", "MiddleButton") end
        button:SetScript("OnEnter", function(b) forward(b, "OnEnter") end)
        button:SetScript("OnLeave", function(b) forward(b, "OnLeave") end)
    end
    button.owner, active[owner], owner._actionButton = owner, button, button
    if not owner._hudActionHooked then
        owner._hudActionHooked = true
        owner:HookScript("OnHide", function(f)
            if active[f] and not InCombatLockdown() then active[f]:Hide() end
        end)
        owner:HookScript("OnShow", ns.RefreshHUDActions)
    end
    if button.actionKind ~= kind or button.actionValue ~= value or button.slot ~= slot then
        if button.actionKind then button:SetAttribute(button.actionKind .. "1", nil) end
        button:SetAttribute("type1", kind)
        button:SetAttribute("unit1", not slot and "player" or nil)
        button:SetAttribute("target-slot1", slot)
        button:SetAttribute(kind .. "1", kind == "item" and ("item:" .. value) or value)
        button.actionKind, button.actionValue, button.slot = kind, value, slot
    end
    position(owner, button)
end

ns:RegisterEvent("PLAYER_REGEN_ENABLED", ns.RefreshHUDActions)
