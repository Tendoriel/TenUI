local _, ns = ...

local Prediction = {}
ns.PowerPrediction = Prediction

local Power = Enum.PowerType
local hosts = {}
local visuals = setmetatable({}, { __mode = "k" })
local driver, cast

-- These generators grant a fixed amount on cast completion in 12.1.5.
-- Other gains use signed power metadata when the client provides it.
local fixedGains = {
    [258] = { [8092] = { Power.Insanity, 6 }, [34914] = { Power.Insanity, 4 } },
    [62] = { [30451] = { Power.ArcaneCharges, 1 } },
}

local function secret(value)
    return issecretvalue and issecretvalue(value)
end

local function readChanges(spellID)
    local changes, required = {}, {}
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if ok and not secret(costs) and type(costs) == "table" then
        for _, entry in ipairs(costs) do
            if not secret(entry) and not secret(entry.type) and type(entry.type) == "number" then
                local power, value = entry.type, entry.cost
                local auraID, hasAura = entry.requiredAuraID, entry.hasRequiredAura
                local known = not (secret(auraID) or secret(hasAura))
                local conditional = known and type(auraID) == "number" and auraID > 0
                if known and (not conditional or hasAura) and (conditional or not required[power])
                    and (secret(value) or type(value) == "number") then
                    changes[power] = value
                    required[power] = conditional
                end
            end
        end
    end
    if not secret(spellID) then
        local _, _, spec = ns.Resources_Resolver:GetPlayerInfo()
        local spells = fixedGains[spec]
        local gain = spells and spells[spellID]
        if gain and not secret(changes[gain[1]]) and (changes[gain[1]] or 0) == 0 then
            changes[gain[1]] = -gain[2]
        end
    end
    return changes
end

local function hide(frame)
    local display = visuals[frame]
    if display then display.segment:Hide() end
end

local function makeVisual(frame, segmented)
    local clip = CreateFrame("Frame", nil, frame)
    if segmented then
        -- A thin band leaves the real pip fills, recharge swipes and count visible.
        clip:SetPoint("BOTTOMLEFT", frame)
        clip:SetPoint("BOTTOMRIGHT", frame)
        clip:SetHeight(5)
    else
        clip:SetAllPoints(frame)
    end
    clip:SetClipsChildren(true)
    clip:SetFrameLevel(frame:GetFrameLevel() + (segmented and 3 or 1))
    local segment = CreateFrame("StatusBar", nil, clip)
    segment:SetFrameLevel(clip:GetFrameLevel())
    local display = { segment = segment, clip = clip }
    if segmented then
        local ruler = CreateFrame("StatusBar", nil, clip)
        ruler:SetAllPoints(clip)
        ruler:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        ruler:SetStatusBarColor(1, 1, 1, 0.001)
        display.ruler = ruler
    end
    visuals[frame] = display
    return display
end

local function draw(host)
    local frame, power = host.frame, host.power
    local value = cast and cast.changes[power]
    local gain = not secret(value) and type(value) == "number" and value < 0
    if not secret(value) and (type(value) ~= "number" or value == 0) then hide(frame) return end
    local maximum = UnitPowerMax("player", power)
    if not secret(maximum) and maximum <= 0 then hide(frame) return end

    local display = visuals[frame] or makeVisual(frame, host.segmented)
    local bar, segment = display.ruler or frame, display.segment
    if display.ruler then
        bar:SetMinMaxValues(0, maximum)
        bar:SetValue(UnitPower("player", power))
    end
    local fill = bar:GetStatusBarTexture()
    if not fill then hide(frame) return end
    local texture = fill:GetTexture() or "Interface\\Buttons\\WHITE8X8"
    if texture ~= display.texture then
        display.texture = texture
        segment:SetStatusBarTexture(texture)
    end

    local reverse = bar:GetReverseFill()
    segment:ClearAllPoints()
    if bar:GetOrientation() == "VERTICAL" then
        local edge = reverse and "BOTTOM" or "TOP"
        local anchor = gain and (reverse and "TOP" or "BOTTOM") or edge
        segment:SetPoint(anchor .. "LEFT", fill, edge .. "LEFT")
        segment:SetPoint(anchor .. "RIGHT", fill, edge .. "RIGHT")
        segment:SetHeight(display.clip:GetHeight())
        segment:SetOrientation("VERTICAL")
    else
        local edge = reverse and "LEFT" or "RIGHT"
        local anchor = gain and (reverse and "RIGHT" or "LEFT") or edge
        segment:SetPoint("TOP" .. anchor, fill, "TOP" .. edge)
        segment:SetPoint("BOTTOM" .. anchor, fill, "BOTTOM" .. edge)
        segment:SetWidth(display.clip:GetWidth())
        segment:SetOrientation("HORIZONTAL")
    end
    segment:SetReverseFill(gain and reverse or not gain and not reverse)
    segment:SetRotatesTexture(bar:GetRotatesTexture())
    if gain then
        segment:SetStatusBarColor(0.43, 0.92, 0.63)
    elseif power ~= Power.Mana then
        segment:SetStatusBarColor(1, 0.68, 0.24)
    elseif POWERBAR_PREDICTION_COLOR_MANA then
        segment:SetStatusBarColor(POWERBAR_PREDICTION_COLOR_MANA:GetRGB())
    else
        segment:SetStatusBarColor(0.56, 0.8, 1)
    end
    segment:SetMinMaxValues(0, maximum)
    segment:SetValue(gain and -value or value)
    segment:Show()
end

local function refresh()
    for _, host in pairs(hosts) do draw(host) end
end

local function startCast(guid, spellID, barID)
    cast = nil
    if secret(spellID) or type(spellID) == "number" then
        cast = { guid = guid, barID = barID, changes = readChanges(spellID) }
    end
    refresh()
end

local function matches(expected, received)
    if not (secret(expected) or secret(received)) and expected ~= nil and received ~= nil then
        return expected == received
    end
end

local function onEvent(_, event, _, guid, spellID, arg4, arg5, arg6)
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_EMPOWER_START" then
        startCast(guid, spellID, arg4)
        return
    end
    local active = cast
    if not active then return end
    local barID = arg4
    if event == "UNIT_SPELLCAST_INTERRUPTED" then barID = arg5 end
    if event == "UNIT_SPELLCAST_EMPOWER_STOP" then barID = arg6 end
    local same = matches(active.barID, barID)
    if same == nil then same = matches(active.guid, guid) end
    if same == false then return end
    if same then
        cast = nil
        refresh()
    else
        C_Timer.After(0, function()
            if cast ~= active then return end
            local name = UnitCastingInfo("player")
            if secret(name) or name ~= nil then return end
            local _, _, _, _, _, _, _, _, empowered = UnitChannelInfo("player")
            if secret(empowered) or empowered then return end
            cast = nil
            refresh()
        end)
    end
end

function Prediction.UpdatePips()
    local host = hosts.secondary
    if not (cast and host and host.segmented) then return end
    local display = visuals[host.frame]
    if display and display.segment:IsShown() then
        display.ruler:SetValue(UnitPower("player", host.power))
    end
end

function Prediction.Attach(key, frame, power, segmented)
    local old = hosts[key]
    if old and old.frame ~= frame then hide(old.frame) end
    local wasListening = next(hosts) ~= nil
    local host = frame and power and { frame = frame, power = power, segmented = segmented } or nil
    hosts[key] = host
    if not next(hosts) then
        if driver then driver:UnregisterAllEvents() end
        cast = nil
        return
    end
    if not wasListening then
        if not driver then
            driver = CreateFrame("Frame")
            driver:SetScript("OnEvent", onEvent)
        end
        for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
            "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED",
            "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP" }) do
            driver:RegisterUnitEvent(event, "player")
        end
        local _, _, _, _, _, _, guid, _, spellID, barID = UnitCastingInfo("player")
        startCast(guid, spellID, barID)
    elseif host then
        draw(host)
    end
end
