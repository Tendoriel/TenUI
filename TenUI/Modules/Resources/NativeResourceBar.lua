local _, ns = ...

local Native = {}
ns.NativeResourceBar = Native

local states = setmetatable({}, { __mode = "k" })
local durationFormatter

local function getDurationFormatter()
    if durationFormatter == nil then
        local ok, formatter = pcall(function()
            local fmt = C_StringUtil.CreateNumericRuleFormatter()
            local rounding = Enum.NumericRuleFormatRounding.Down
            fmt:SetBreakpoints({
                { threshold = 0, format = "%.1f", step = 0.1, rounding = rounding },
                { threshold = 60, format = "%dm", step = 60, rounding = rounding, components = { { div = 60 } } },
            })
            return fmt
        end)
        durationFormatter = ok and formatter or false
    end
    return durationFormatter or nil
end

function Native.Prepare(bar, auraID, maxApplications, texture, color, fontStyle, label)
    local frame = bar.frame
    local state = states[frame]
    if not state then
        state = { slots = {} }
        states[frame] = state
    end

    local key = auraID .. "/" .. (maxApplications or "duration")
    local slot = state.slots[key]
    if InCombatLockdown() or (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()) then
        return slot and slot.container
    end

    -- Widget getters can return secret values even when the aura container can
    -- be built. Use the same plain settings as the resource bar.
    local r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
    local appearance = texture .. "/" .. table.concat({ r, g, b, a }, "/")
    if fontStyle then appearance = appearance .. "/" .. table.concat(fontStyle, "/") end
    if label then appearance = appearance .. "/" .. label end
    if slot and slot.appearance == appearance then return slot.container end
    if slot and slot.failedAppearance == appearance then return slot.container end

    local container
    local ok, err = pcall(function()
        if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
            C_AddOns.LoadAddOn("Blizzard_AuraContainer")
        end
        container = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
        container:SetAllPoints(frame)
        container:SetFrameLevel(frame:GetFrameLevel() + 1)
        container:SetUnit("player")
        container:Hide()
        container:AddAuraSlot("resource", "HELPFUL", {
            candidateFilters = { includeSpellIDs = { [auraID] = true } },
            initializeFrame = function(button)
                button:SetAllPoints(container)
                button:SetMouseClickEnabled(false)
                button:SetMouseMotionEnabled(false)

                local fill = CreateFrame("StatusBar", nil, button)
                fill:SetAllPoints(button)
                fill:SetStatusBarTexture(texture)
                fill:SetStatusBarColor(r, g, b, a)
                if label then
                    local background = fill:CreateTexture(nil, "BACKGROUND")
                    background:SetAllPoints(fill)
                    background:SetColorTexture(0, 0, 0, 0.72)
                end
                if maxApplications then
                    button:SetApplicationBar(fill, { minApplications = 0, maxApplications = maxApplications })
                else
                    button:SetDurationBar(fill, { direction = Enum.StatusBarTimerDirection.RemainingTime })
                end
                if not fontStyle then return end
                local font, size, flags, point, x, y, justify = unpack(fontStyle)
                local text = fill:CreateFontString(nil, "OVERLAY")
                ns.Pixel.SetFont(text, font, size, flags)
                text:SetPoint(point, fill, point, x, y)
                text:SetJustifyH(justify)
                if label then
                    local name = fill:CreateFontString(nil, "OVERLAY")
                    ns.Pixel.SetFont(name, font, size, flags)
                    name:SetPoint("LEFT", fill, "LEFT", 4, 0)
                    name:SetText(label)
                end
                if maxApplications then
                    button:SetApplicationCount(text)
                else
                    local formatter = getDurationFormatter()
                    button:SetDurationText(text, formatter and { textFormatter = formatter } or nil)
                end
            end,
        })
        container:SetEnabled(true)
    end)
    if not ok then
        if container then container:Hide() end
        slot = slot or {}
        slot.failedAppearance = appearance
        state.slots[key] = slot
        if ns.Debug and ns.Debug.Warn then ns.Debug:Warn("[Resources] native aura bar: %s", tostring(err)) end
        return slot.container
    end
    if slot and slot.container then slot.container:Hide() end
    state.slots[key] = { container = container, appearance = appearance }
    return container
end

function Native.Hide(bar)
    local state = bar and states[bar.frame]
    if state and state.active then
        state.active:Hide()
        state.active = nil
    end
end

function Native.Show(bar, auraID, maxApplications, texture, color, fontStyle, label)
    local container = Native.Prepare(bar, auraID, maxApplications, texture, color, fontStyle, label)
    if not container then
        Native.Hide(bar)
        return false
    end
    local state = states[bar.frame]
    if state.active ~= container then
        Native.Hide(bar)
        state.active = container
        container:Show()
    end
    return true
end
