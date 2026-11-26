local _, ns = ...

local Soul = {}
ns.ArcaneSoul = Soul
local anchorName = "ArcaneSoul"
local proxy, sample
local font, size, flags
local normalColor, lastColor
local defaultNormal, defaultLast = {0.8, 0.65, 1, 1}, {1, 0.75, 0.25, 1}
local phases = {
    { id = 365362, label = "Soul in " },
    { id = 451038, label = "Barrage " },
}

local function gcdLength()
    local haste = UnitSpellHaste("player")
    if issecretvalue(haste) or type(haste) ~= "number" then return nil end
    return math.max(0.75, 1.5 / (1 + haste / 100))
end

local function bind(phase, gcd)
    if not phase.button or phase.gcd == gcd then return end
    local points = {}
    for index = 1, 6 do
        points[index] = {
            threshold = index == 1 and 0 or (index - 1) * gcd + 0.0001,
            format = phase.label .. index,
        }
    end
    if phase == phases[1] then points[7] = { threshold = 6 * gcd, format = " " } end
    local fmt = C_StringUtil.CreateNumericRuleFormatter()
    fmt:SetBreakpoints(points)
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, CreateColor(unpack(lastColor)))
    curve:AddPoint(gcd + 0.0001, CreateColor(unpack(normalColor)))
    phase.button:SetDurationText(phase.text, {
        textFormatter = fmt,
        textColor = { curve = curve, property = Enum.DurationTextBindingProperty.RemainingDuration },
    })
    phase.gcd = gcd
end

local function prepare(phase, gcd)
    if not phase.container then
        local f = CreateFrame("AuraContainer", nil, proxy, "CustomAuraContainerTemplate")
        phase.pending = f
        f:SetAllPoints(proxy)
        f:SetUnit("player")
        f:AddAuraSlot("phase", "HELPFUL", {
            candidateFilters = { includeSpellIDs = { [phase.id] = true } },
            initializeFrame = function(button)
                button:SetAllPoints(f)
                button:SetMouseClickEnabled(false)
                button:SetMouseMotionEnabled(false)
                local text = button:CreateFontString(nil, "OVERLAY")
                ns.Pixel.SetFont(text, font, size, flags)
                text:SetPoint("CENTER")
                phase.button, phase.text, phase.gcd = button, text, nil
                bind(phase, phase.desiredGcd or gcd)
            end,
        })
        f:SetEnabled(true)
        phase.container, phase.pending = f, nil
    end
    bind(phase, gcd)
end

function Soul.Hide()
    if proxy then proxy:Hide() end
    if ns:GetAnchor(anchorName) then ns:UnregisterAnchor(anchorName) end
end

function Soul.SetAlpha(alpha)
    if proxy then proxy:SetAlpha(alpha) end
end

function Soul.Update(profile, preview, alpha)
    if not profile.arcaneSoulEnabled then
        Soul.Hide()
        return
    end
    local _, _, spec = ns.Resources_Resolver:GetPlayerInfo()
    if spec ~= 62 or C_ClassTalents.GetActiveHeroTalentSpec() ~= 39 then
        Soul.Hide()
        return
    end
    local anchor = ns:GetAnchor(anchorName)
    if not anchor then
        if InCombatLockdown() then return end
        anchor = ns:RegisterAnchor({ name = anchorName, label = "Arcane Soul",
            defaultX = 255, defaultY = -100, width = 150, height = 22 })
        if ns.Visibility then ns.Visibility:UpdateOne(anchorName) end
    end
    local primary = profile.primary or {}
    font = ns.Widgets.resolveMedia("font", primary.font, ns.Widgets.DEFAULT_FONT)
    size, flags = profile.arcaneSoulFontSize or primary.fontSize or 14, primary.fontFlags or "OUTLINE"
    local normal, last = profile.arcaneSoulColor or defaultNormal, profile.arcaneSoulLastColor or defaultLast
    if normal ~= normalColor or last ~= lastColor then
        for _, phase in ipairs(phases) do phase.gcd = nil end
    end
    normalColor, lastColor = normal, last
    if not proxy then
        proxy = CreateFrame("Frame", nil, anchor.frame)
        sample = proxy:CreateFontString(nil, "OVERLAY")
        sample:SetPoint("CENTER")
        sample:SetText("Barrage 3")
    end
    ns.Pixel.SetFont(sample, font, size, flags)
    sample:SetTextColor(unpack(normalColor))
    for _, phase in ipairs(phases) do
        if phase.text and not InCombatLockdown() then ns.Pixel.SetFont(phase.text, font, size, flags) end
    end
    if proxy:GetParent() ~= anchor.frame then proxy:SetParent(anchor.frame) end
    proxy:SetAllPoints(anchor.frame)
    local editing = (preview or ns.EditMode:IsActive()) and not InCombatLockdown()
    proxy:SetAlpha(editing and 1 or alpha)
    proxy:Show()
    sample:SetShown(editing)
    if not InCombatLockdown() then
        if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then C_AddOns.LoadAddOn("Blizzard_AuraContainer") end
        for _, phase in ipairs(phases) do
            local gcd = gcdLength() or phase.gcd or 1.5
            phase.desiredGcd = gcd
            if (not phase.retryAfter or GetTime() >= phase.retryAfter) and (not phase.container or not C_Secrets.ShouldAurasBeSecret()) then
                local ok, err = pcall(prepare, phase, gcd)
                if ok then
                    phase.retryAfter = nil
                else
                    phase.retryAfter = GetTime() + 5
                    if phase.pending then
                        phase.pending:Hide()
                        phase.pending, phase.button, phase.text, phase.gcd = nil, nil, nil, nil
                    end
                    if ns.Debug then ns.Debug:Warn("[Arcane Soul] %s", tostring(err)) end
                end
            end
            if phase.container then phase.container:SetShown(not editing) end
        end
    else
        for _, phase in ipairs(phases) do
            if phase.container then phase.container:Show() end
        end
    end
end
