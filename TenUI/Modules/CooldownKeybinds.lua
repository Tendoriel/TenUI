local _, ns = ...
local prefixes = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
local commands = {"ACTIONBUTTON", "MULTIACTIONBAR1BUTTON", "MULTIACTIONBAR2BUTTON", "MULTIACTIONBAR3BUTTON",
    "MULTIACTIONBAR4BUTTON", "MULTIACTIONBAR5BUTTON", "MULTIACTIONBAR6BUTTON", "MULTIACTIONBAR7BUTTON"}
local bindings
local dirty = true
local function invalidate() dirty = true end
for _, event in ipairs({"UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
    "SPELLS_CHANGED", "TRAIT_CONFIG_UPDATED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_EQUIPMENT_CHANGED",
    "UPDATE_BONUS_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED"}) do
    ns:RegisterEvent(event, invalidate)
end

local function actionID(value)
    if not issecretvalue(value) and type(value) == "number" and value > 0 then return value end
end

function ns.ResolveActionSlot(slot)
    if not actionID(slot) then return end
    local ok, value = pcall(C_ActionBar.GetSpell, slot)
    local spell = ok and actionID(value) or nil
    local item
    local readable, kind, id, sub = pcall(GetActionInfo, slot)
    if readable and not issecretvalue(kind) and not issecretvalue(id) and not issecretvalue(sub) then
        if kind == "item" or (kind == "macro" and sub == "item") then item = actionID(id)
        elseif kind == "macro" then
            if sub == "spell" then spell = spell or actionID(id) end
            local name = C_ActionBar.GetActionText(slot)
            if not issecretvalue(name) and name then
                local macro = GetMacroIndexByName(name)
                if macro and macro > 0 then
                    local _, link = GetMacroItem(macro)
                    if not issecretvalue(link) and type(link) == "string" then item = tonumber(link:match("item:(%d+)")) end
                    spell = spell or actionID(GetMacroSpell(macro))
                    if not item then
                        local body = GetMacroBody(macro)
                        if not issecretvalue(body) and type(body) == "string" then
                            for line in body:gmatch("[^\r\n]+") do
                                local equip = tonumber(line:match("^%s*/use%s+(%d+)%s*$"))
                                if equip == 13 or equip == 14 then item = actionID(GetInventoryItemID("player", equip)) break end
                            end
                        end
                    end
                end
            end
        end
    end
    return spell, item
end

local function scan()
    local result = { spell = {}, item = {} }
    for bar, prefix in ipairs(prefixes) do
        for index = 1, 12 do
            local button = _G[prefix .. index]
            if button and actionID(button.action) then
                local key = button.bindingAction and GetBindingKey(button.bindingAction)
                key = key or GetBindingKey(commands[bar] .. index) or GetBindingKey("CLICK " .. button:GetName() .. ":LeftButton")
                if key then
                    local label = key:gsub("SHIFT%-","S-"):gsub("CTRL%-","C-"):gsub("ALT%-","A-")
                        :gsub("MOUSEWHEELUP","MWU"):gsub("MOUSEWHEELDOWN","MWD"):gsub("MIDDLEBUTTON","M3")
                        :gsub("BUTTON(%d+)","M%1"):gsub("NUMPAD","N"):gsub("SPACEBAR","Spc")
                    local spell, item = ns.ResolveActionSlot(button.action)
                    if spell then
                        result.spell[spell] = result.spell[spell] or label
                        local base = actionID(C_Spell.GetBaseSpell(spell))
                        if base then result.spell[base] = result.spell[base] or label end
                    end
                    if item then result.item[item] = result.item[item] or label end
                end
            end
        end
    end
    return result
end

function ns:UpdateCooldownKeybind(icon, visuals, entry)
    local text = icon.bindLabel
    if not visuals or not visuals.showKeybind then
        if text then text:Hide() end
        return
    end
    if dirty and not InCombatLockdown() then
        bindings = scan()
        dirty = false
    end
    local keys = bindings and bindings[entry.type]
    local key = keys and keys[entry.id]
    if keys and not key then
        if entry.type == "spell" then
            key = keys[actionID(icon._activeSpellID)]
            if not key and actionID(entry.id) then key = keys[actionID(C_Spell.GetOverrideSpell(entry.id))] end
        elseif entry.slot then key = keys[actionID(GetInventoryItemID("player", entry.slot))] end
        for _, id in ipairs(entry.altItemIDs or {}) do key = key or keys[id] end
    end
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
    local size, x, y = visuals.keybindSize or 10, visuals.keybindX or 0, visuals.keybindY or 0
    if icon.bindFont ~= font or icon.bindCorner ~= corner or icon.bindSize ~= size or icon.bindX ~= x or icon.bindY ~= y or not text:IsShown() then
        icon.bindSize, icon.bindX, icon.bindY = size, x, y
        ns.Pixel.SetFont(text, ns.UI.ResolveFontPath(font), visuals.keybindSize or 10, "GLOBAL")
        text:ClearAllPoints()
        text:SetPoint(corner, icon.frame, corner, (visuals.keybindX or 0) + (corner:find("LEFT") and 1 or -1), (visuals.keybindY or 0) + (corner:find("TOP") and -1 or 1))
        icon.bindFont, icon.bindCorner = font, corner
    end
    if icon.bindValue ~= key then text:SetText(key) icon.bindValue = key end
    text:Show()
end

local noVisuals = {}
function ns.StyleCooldownIcon(icon, name, visuals)
    local v = visuals or noVisuals
    local f = icon.frame
    icon.iconZoom = (v.zoom or 8) / 100
    icon.swipeAlpha = (v.swipeAlpha or 80) / 100
    icon:SetCooldownReverse(v.reverseSwipe == true)
    icon:SetDrawSwipe(icon._drawSwipe ~= false)
    if InCombatLockdown() then
        if not icon.masqueGroup then ns.Widgets.Icon.ApplyCropTexCoord(f.icon, f:GetWidth(), f:GetHeight(), icon.iconZoom) end
        return
    end
    if v.masque and not icon.masqueGroup then
        local masque = LibStub("Masque", true)
        if masque then
            icon.masqueGroup = masque:Group("TenUI", name)
            icon:SetBorder(icon.borderEnabled, icon.borderColor)
            icon.masqueGroup:AddButton(f, {Icon = f.icon, Cooldown = f.cooldown, Count = f.stack}, "Action", true)
        end
    elseif not v.masque and icon.masqueGroup then
        icon.masqueGroup:RemoveButton(f)
        icon.masqueGroup = nil
        icon:SetBorder(icon.borderEnabled, icon.borderColor)
    end
    if not icon.masqueGroup then
        ns.Widgets.Icon.ApplyCropTexCoord(f.icon, f:GetWidth(), f:GetHeight(), icon.iconZoom)
    end
end

local nextHint, checkedAt
function ns.UpdateAssistedIcon(icon, base, active)
    local now = GetTime()
    if checkedAt ~= now then
        checkedAt, nextHint = now, nil
        if C_AssistedCombat and C_AssistedCombat.GetNextCastSpell then
            local ok, spell = pcall(C_AssistedCombat.GetNextCastSpell, false)
            if ok then nextHint = actionID(spell) end
        end
    end
    local shown = nextHint and (nextHint == base or nextHint == active)
    if shown and not icon.assistedMark then
        local mark = icon.frame:CreateTexture(nil, "OVERLAY")
        mark:SetColorTexture(1, 0.8, 0.15, 1)
        mark:SetPoint("BOTTOMLEFT", 1, 1)
        mark:SetPoint("BOTTOMRIGHT", -1, 1)
        mark:SetHeight(3)
        icon.assistedMark = mark
    end
    if icon.assistedMark then icon.assistedMark:SetShown(shown == true) end
end
