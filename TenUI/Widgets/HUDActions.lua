local _, ns = ...
local gate

-- Independent screen-space buttons keep protected children out of movable HUD frames.
function ns.SyncHUDAction(owner, kind, value)
    if InCombatLockdown() then return end
    local button = owner._actionButton
    if not value or not owner:IsVisible() or owner:GetEffectiveAlpha() == 0
        or (ns.EditMode and ns.EditMode:IsActive()) then
        if button then button:Hide() end
        return
    end
    local x, y = owner:GetCenter()
    if not x or not y then
        if button then button:Hide() end
        return
    end
    if not gate then
        gate = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
        gate:SetAllPoints(UIParent)
        RegisterStateDriver(gate, "visibility", "[combat] hide; show")
    end
    if not button then
        button = CreateFrame("Button", nil, gate, "SecureActionButtonTemplate")
        owner._actionButton = button
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:SetAttribute("unit", "player")
        owner:HookScript("OnHide", function()
            if not InCombatLockdown() then button:Hide() end
        end)
    end
    local scale = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
    x, y = x * scale, y * scale
    local width, height = owner:GetWidth() * scale, owner:GetHeight() * scale
    if button.lastX ~= x or button.lastY ~= y then
        button:ClearAllPoints()
        button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        button.lastX, button.lastY = x, y
    end
    if button:GetWidth() ~= width or button:GetHeight() ~= height then button:SetSize(width, height) end
    local level, strata = owner:GetFrameLevel() + 1, owner:GetFrameStrata()
    if button:GetFrameStrata() ~= strata then button:SetFrameStrata(strata) end
    if button:GetFrameLevel() ~= level then button:SetFrameLevel(level) end
    if button.actionKind ~= kind or button.actionValue ~= value then
        button:SetAttribute("type1", kind)
        button:SetAttribute(kind .. "1", kind == "item" and ("item:" .. value) or value)
        button.actionKind, button.actionValue = kind, value
    end
    button:Show()
end
