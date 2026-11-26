local _, ns = ...
local prefixes = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
local bindings
local dirty = true
local function invalidate() dirty = true end
for _, event in ipairs({"UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_BONUS_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED"}) do
    ns:RegisterEvent(event, invalidate)
end

local function scan()
    local result = {}
    for _, prefix in ipairs(prefixes) do
        for index = 1, 12 do
            local button = _G[prefix .. index]
            if button and button.bindingAction and not issecretvalue(button.action) and button.action then
                local spell = C_ActionBar.GetSpell(button.action)
                if not issecretvalue(spell) and spell and not result[spell] then
                    local key = GetBindingKey(button.bindingAction) or GetBindingKey("CLICK " .. button:GetName() .. ":LeftButton")
                    if key then result[spell] = GetBindingText(key, true) end
                end
            end
        end
    end
    return result
end

function ns:UpdateCooldownKeybind(icon, visuals, entry)
    local text = icon.bindLabel
    if not visuals or not visuals.showKeybind or entry.type ~= "spell" then
        if text then text:Hide() end
        return
    end
    if dirty and not InCombatLockdown() then
        bindings = scan()
        dirty = false
    end
    local key = bindings and bindings[entry.id]
    if not key then
        if text then text:Hide() end
        return
    end
    if not text then
        local layer = icon.frame.stack and icon.frame.stack:GetParent() or icon.frame
        text = layer:CreateFontString(nil, "OVERLAY")
        icon.bindLabel = text
    end
    local font, corner = visuals.keybindFont or "default", visuals.keybindCorner or "TOPLEFT"
    if icon.bindFont ~= font or icon.bindCorner ~= corner or not text:IsShown() then
        ns.Pixel.SetFont(text, ns.UI.ResolveFontPath(font), 10, "OUTLINE")
        text:ClearAllPoints()
        text:SetPoint(corner, icon.frame, corner, corner:find("LEFT") and 1 or -1, corner:find("TOP") and -1 or 1)
        icon.bindFont, icon.bindCorner = font, corner
    end
    if icon.bindValue ~= key then text:SetText(key) icon.bindValue = key end
    text:Show()
end
