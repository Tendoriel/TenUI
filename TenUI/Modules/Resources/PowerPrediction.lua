local _, ns = ...

local Prediction = {}
ns.PowerPrediction = Prediction

local Power = Enum.PowerType
local hosts = {}
local visuals = setmetatable({}, { __mode = "k" })
local driver, cast

-- Base single-target gains, in displayed resource units (one Soul Shard = ten fragments).
-- Other gains use signed power metadata when the client provides it.
local fixedGains = {
    [102] = { [190984] = { Power.LunarPower, 6 }, [194153] = { Power.LunarPower, 8 },
        [202347] = { Power.LunarPower, 12 } },
    [262] = { [188196] = { Power.Maelstrom, 6 }, [51505] = { Power.Maelstrom, 8 },
        [188443] = { Power.Maelstrom, 2 }, [462818] = { Power.Maelstrom, 10 } },
    [266] = { [686] = { Power.SoulShards, 1 }, [264178] = { Power.SoulShards, 2 },
        [434506] = { Power.SoulShards, 3 } },
    [267] = { [29722] = { Power.SoulShards, 0.2 }, [6353] = { Power.SoulShards, 1 },
        [434506] = { Power.SoulShards, 2 } },
    [254] = { [56641] = { Power.Focus, 20 } },
    [1480] = { [473662] = { Power.Fury, 8 } },
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
            local amount = gain[2]
            if spellID == 56641 and C_SpellBook.IsSpellKnown(450379) then amount = amount + 5 end
            if spellID == 473662 and C_SpellBook.IsSpellKnown(1253415) then amount = amount + 2 end
            if spellID == 29722 and C_SpellBook.IsSpellKnown(387173) then amount = amount + 0.2 end
            if (spellID == 190984 or spellID == 194153) and C_SpellBook.IsSpellKnown(406890) then amount = amount + 2 end
            if spellID == 194153 and C_SpellBook.IsSpellKnown(429520) then amount = amount + 2 end
            changes[gain[1]] = -amount
        end
    end
    return changes
end

local WHITE = "Interface\\Buttons\\WHITE8X8"

local function hide(frame)
    local display = visuals[frame]
    if not display then return end
    for _, layer in ipairs(display.layers) do layer.clip:Hide() end
    if display.ruler then display.ruler:Hide() end
end

local function paintLayer(display, index, frame, ruler, offset, gain, amount, maximum)
    local layer = display.layers[index]
    if not layer then
        local clip = CreateFrame("Frame", nil, frame)
        clip:SetClipsChildren(true)
        clip:SetFrameLevel(frame:GetFrameLevel() + 1)
        local segment = CreateFrame("StatusBar", nil, clip)
        segment:SetFrameLevel(clip:GetFrameLevel())
        layer = { clip = clip, segment = segment }
        display.layers[index] = layer
    end

    local clip, segment = layer.clip, layer.segment
    local texture = frame:GetStatusBarTexture()
    local fill = ruler:GetStatusBarTexture()
    if not texture or not fill then clip:Hide() return end
    local border = frame.borderParts and frame.borderParts[1] or frame.border and frame.border.top
    local inset = border and border:IsShown() and ns.Pixel.Size(frame, 1) or 0
    clip:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    clip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)

    local path = texture:GetTexture() or WHITE
    if layer.path ~= path then
        segment:SetStatusBarTexture(path)
        layer.path = path
    end
    segment:ClearAllPoints()
    local reverse = ruler:GetReverseFill()
    if ruler:GetOrientation() == "VERTICAL" then
        local edge = reverse and "BOTTOM" or "TOP"
        local anchor = gain and (reverse and "TOP" or "BOTTOM") or edge
        segment:SetPoint(anchor .. "LEFT", fill, edge .. "LEFT")
        segment:SetPoint(anchor .. "RIGHT", fill, edge .. "RIGHT")
        segment:SetHeight(ruler:GetHeight())
        segment:SetOrientation("VERTICAL")
    else
        local edge = reverse and "LEFT" or "RIGHT"
        local anchor = gain and (reverse and "RIGHT" or "LEFT") or edge
        segment:SetPoint("TOP" .. anchor, fill, "TOP" .. edge, offset, 0)
        segment:SetPoint("BOTTOM" .. anchor, fill, "BOTTOM" .. edge, offset, 0)
        segment:SetWidth(ruler:GetWidth())
        segment:SetOrientation("HORIZONTAL")
    end
    segment:SetReverseFill(gain and reverse or not gain and not reverse)
    segment:SetRotatesTexture(frame:GetRotatesTexture())
    if gain then
        segment:SetStatusBarColor(0.36, 0.90, 0.48)
    else
        segment:SetStatusBarColor(0.96, 0.32, 0.24)
    end
    segment:SetMinMaxValues(0, maximum)
    segment:SetValue(amount)
    clip:Show()
end

local function draw(host)
    local frame, power = host.frame, host.power
    local value = cast and cast.changes[power]
    if not secret(value) and (type(value) ~= "number" or value == 0) then hide(frame) return end
    local maximum = UnitPowerMax("player", power)
    if not secret(maximum) and maximum <= 0 then hide(frame) return end
    local gain = not secret(value) and value < 0
    local amount = gain and -value or value
    local display = visuals[frame]
    if not display then
        display = { layers = {} }
        visuals[frame] = display
    end

    local pips = host.pips
    if pips then
        if #pips == 0 then hide(frame) return end
        -- The ruler measures only the fillable widths. Shift its edge by the
        -- preceding gaps for each pip, then clip to that pip's own borders.
        local length = pips[1]:GetWidth() * #pips
        local ruler = display.ruler
        if not ruler then
            ruler = CreateFrame("StatusBar", nil, frame)
            ruler:SetStatusBarTexture(WHITE)
            ruler:SetAlpha(0)
            display.ruler = ruler
        end
        ruler:SetPoint("TOPLEFT", pips[1], "TOPLEFT")
        ruler:SetPoint("BOTTOMLEFT", pips[1], "BOTTOMLEFT")
        ruler:SetWidth(length)
        local rulerMaximum = maximum
        if host.rawRuler then rulerMaximum = UnitPowerMax("player", power, true) end
        ruler:SetMinMaxValues(0, rulerMaximum)
        ruler:SetValue(UnitPower("player", power, host.rawRuler))
        ruler:Show()
        for i, pip in ipairs(pips) do
            paintLayer(display, i, pip, ruler, (i - 1) * host.spacing, gain, amount, maximum)
        end
        for i = #pips + 1, #display.layers do display.layers[i].clip:Hide() end
    else
        paintLayer(display, 1, frame, frame, 0, gain, amount, maximum)
    end
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
    if not (cast and host and host.pips) then return end
    local display = visuals[host.frame]
    if display and display.ruler and display.ruler:IsShown() then
        display.ruler:SetValue(UnitPower("player", host.power, host.rawRuler))
    end
end

function Prediction.Attach(key, frame, power, pips, spacing)
    local old = hosts[key]
    if old and old.frame ~= frame then hide(old.frame) end
    local wasListening = next(hosts) ~= nil
    local host = frame and power and { frame = frame, power = power, pips = pips, spacing = spacing } or nil
    if host and pips and power == Power.SoulShards then
        local _, _, spec = ns.Resources_Resolver:GetPlayerInfo()
        host.rawRuler = spec == 267
    end
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
