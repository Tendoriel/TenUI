local _, ns = ...

local EbonMight = {}
ns.EbonMight = EbonMight

local SPEC_AUGMENTATION = 1473
local AURA_ID = 395296
local anchorName = "EbonMight"
local color = { 0.89, 0.64, 0.29, 1 }
local bar

function EbonMight.Hide()
    if not bar then return end
    ns.NativeResourceBar.Hide(bar)
    bar:Hide()
    ns:UnregisterAnchor(anchorName)
end

function EbonMight.SetAlpha(alpha)
    if bar and ns:GetAnchor(anchorName) then
        local editing = ns.EditMode and ns.EditMode:IsActive()
        bar.frame:SetAlpha(editing and 1 or alpha)
    end
end

function EbonMight.Update(profile, preview, alpha)
    local _, _, specID = ns.Resources_Resolver:GetPlayerInfo()
    if specID ~= SPEC_AUGMENTATION or profile.ebonMightEnabled == false then
        EbonMight.Hide()
        return
    end

    local label = C_Spell.GetSpellName(AURA_ID) or "Ebon Might"
    local anchor = ns:GetAnchor(anchorName)
    if not anchor then
        if InCombatLockdown() then return end
        anchor = ns:RegisterAnchor({
            name = anchorName, label = label, defaultX = 255, defaultY = -100, width = 160, height = 16,
        })
        if ns.Visibility then ns.Visibility:UpdateOne(anchorName) end
    end

    local widgets = ns.Widgets
    local primary = profile.primary or {}
    local texture = widgets.resolveMedia("statusbar", primary.texture, widgets.DEFAULT_STATUSBAR)
    local font = widgets.resolveMedia("font", primary.font, widgets.DEFAULT_FONT)
    local fontSize = primary.fontSize or 12
    local flags = primary.fontFlags or "OUTLINE"
    if not bar then
        bar = widgets.Bar:New(anchor.frame, {
            texture = texture, fgColor = color, bgColor = { 0, 0, 0, 0.72 },
            border = false, leftText = true, rightText = true,
        })
        bar.frame:SetAllPoints(anchor.frame)
        bar:SetMinMaxValues(0, 1)
    end

    local editing = ns.EditMode and ns.EditMode:IsActive()
    local showPreview = (preview or editing) and not InCombatLockdown()
    bar.frame:SetAlpha(showPreview and 1 or alpha)
    bar:SetBackground(showPreview)
    bar:SetValue(showPreview and 0.68 or 0)
    bar:SetLeftText(showPreview and label or "")
    bar:SetRightText(showPreview and "12.4" or "")
    bar:Show()
    if showPreview then
        ns.NativeResourceBar.Show(bar, AURA_ID, nil, texture, color,
            { font, fontSize, flags, "RIGHT", -4, 0, "RIGHT" }, label)
        ns.NativeResourceBar.Hide(bar)
        bar:SetFont(font, fontSize, flags)
        bar:SetTexture(texture)
    else
        ns.NativeResourceBar.Show(bar, AURA_ID, nil, texture, color,
            { font, fontSize, flags, "RIGHT", -4, 0, "RIGHT" }, label)
    end
end
