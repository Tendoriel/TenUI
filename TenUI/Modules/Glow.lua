local addonName, ns = ...

local pairs    = pairs
local type     = type
local pcall    = pcall
local tostring = tostring
local tonumber = tonumber

local Glow = {}
ns.Glow = Glow

local PRIORITY = {
    proc       = 4,
    pandemic   = 3,
    ready      = 2,
    activeAura = 1,
}

local CHANNEL = {
    proc       = "overlay",
    pandemic   = "outline",
    ready      = "outline",
    activeAura = "outline",
}

local EXCLUSIVE = {
    proc       = { ready = true },
    activeAura = { ready = true },
}

local function _computeWinners(rec)
    local suppressed
    for intent in pairs(rec) do
        local ex = EXCLUSIVE[intent]
        if ex then
            for victim in pairs(ex) do
                if rec[victim] ~= nil then
                    suppressed = suppressed or {}
                    suppressed[victim] = true
                end
            end
        end
    end
    local winners = {}
    for intent in pairs(rec) do
        if not (suppressed and suppressed[intent]) then
            local ch = CHANNEL[intent]
            if ch then
                local cur = winners[ch]
                if not cur or (PRIORITY[intent] or 0) > (PRIORITY[cur] or 0) then
                    winners[ch] = intent
                end
            end
        end
    end
    return winners, suppressed
end

local INTENT_STYLE = {
    proc       = "blizzard",
    pandemic   = "pixel",
    ready      = "border",
    activeAura = "pixel",
}

local INTENT_COLOR = {
    pandemic   = { 1.0, 0.6,  0.0, 0.9  },
    ready      = { 1.0, 0.7,  0.0, 1.0  },
    activeAura = { 1.0, 0.85, 0.3, 0.85 },
}

local _state = setmetatable({}, { __mode = "k" })

local _previewTokens = setmetatable({}, { __mode = "k" })

local _widgets = setmetatable({}, { __mode = "kv" })

local _lastApplied = setmetatable({}, { __mode = "k" })

local function _resolveTarget(x)
    if type(x) ~= "table" then return nil end
    if x.GetObjectType and x.CreateTexture then
        return x, nil
    end
    if type(x.SetProcGlow) == "function" and type(x.SetActiveBorder) == "function" then
        local wf = x.frame
        if type(wf) == "table" and wf.GetObjectType and wf.CreateTexture then
            return wf, x
        end
    end
    local f = x.bar or x.frame or x.button or x.icon
    if type(f) == "table" and f.GetObjectType and f.CreateTexture then
        return f, nil
    end
    return nil
end

local function _isGlobalEnabled()
    if not ns.savedVarsReady then return true end
    local ok, p = pcall(ns.GetProfile, ns)
    if not ok or type(p) ~= "table" then return true end
    local g = p.modules and p.modules.Glow
    if type(g) ~= "table" then return true end
    return g.globalEnabled ~= false
end

local function _globalDefault(intent)
    if not ns.savedVarsReady then return nil end
    local ok, p = pcall(ns.GetProfile, ns)
    if not ok or type(p) ~= "table" then return nil end
    local g = p.modules and p.modules.Glow
    if type(g) ~= "table" or type(g.defaults) ~= "table" then return nil end
    local d = g.defaults[intent]
    if type(d) ~= "table" then return nil end
    return d
end

local function _resolveColor(intent, opts)
    local d = INTENT_COLOR[intent] or INTENT_COLOR.ready
    local gd = _globalDefault(intent)
    local gc = gd and gd.color
    if type(gc) ~= "table" then gc = nil end
    local r = opts and tonumber(opts.colorR) or gc and tonumber(gc[1]) or d[1]
    local g = opts and tonumber(opts.colorG) or gc and tonumber(gc[2]) or d[2]
    local b = opts and tonumber(opts.colorB) or gc and tonumber(gc[3]) or d[3]
    local a = opts and tonumber(opts.colorA) or gc and tonumber(gc[4]) or d[4]
    return r, g, b, a
end

local STYLES = {}

local function disableProcGlowMouse(frame)
    if type(frame) ~= "table" then return end
    if type(frame.EnableMouse) == "function" then
        pcall(frame.EnableMouse, frame, false)
    end
    if type(frame.EnableMouseMotion) == "function" then
        pcall(frame.EnableMouseMotion, frame, false)
    end
    if type(frame.SetMouseClickEnabled) == "function" then
        pcall(frame.SetMouseClickEnabled, frame, false)
    end
    if type(frame.GetChildren) == "function" then
        local ok, n = pcall(select, "#", frame:GetChildren())
        if ok and n and n > 0 then
            local children = { frame:GetChildren() }
            for i = 1, #children do
                disableProcGlowMouse(children[i])
            end
        end
    end
end

local function blizzardEnsure(f)
    if f._thudGlowProc then return f._thudGlowProc end
    local ok, glow = pcall(CreateFrame, "Frame", nil, f, "ActionButtonSpellAlertTemplate")
    if not ok or not glow then
        if ns.Debug and ns.Debug.Log then
            ns.Debug:Log("Glow: ActionButtonSpellAlertTemplate unavailable (%s)", tostring(glow))
        end
        return nil
    end
    local w, h = f:GetSize()
    if w and h and w > 0 and h > 0 then
        glow:SetSize(w * 1.4, h * 1.4)
        glow:SetPoint("CENTER", f, "CENTER", 0, 0)
    end
    pcall(glow.SetScript, glow, "OnHide", nil)
    disableProcGlowMouse(glow)
    glow:Hide()
    f._thudGlowProc = glow
    return glow
end

STYLES.blizzard = {
    apply = function(f, intent, opts)
        f._thudGlowBlizzardIntent = intent
        local w = _widgets[f]
        if intent == "proc" and w and w.SetProcGlow then
            w:SetProcGlow(true)
            return
        end
        local glow = blizzardEnsure(f)
        if not glow then return end
        if f._thudGlowProcActive and glow:IsShown() then
            if glow:IsVisible()
               and glow.ProcLoop and glow.ProcLoop.Play
               and glow.ProcLoop.IsPlaying and not glow.ProcLoop:IsPlaying() then
                pcall(glow.ProcLoop.Play, glow.ProcLoop)
            end
            return
        end
        f._thudGlowProcActive = true
        glow:Show()
        if glow.ProcStartAnim and glow.ProcStartAnim.Play then
            pcall(glow.ProcStartAnim.Play, glow.ProcStartAnim)
        elseif glow.ProcLoop and glow.ProcLoop.Play then
            pcall(glow.ProcLoop.Play, glow.ProcLoop)
        end
    end,
    clear = function(f)
        local owner = f._thudGlowBlizzardIntent
        f._thudGlowBlizzardIntent = nil
        local w = _widgets[f]
        if w and w.SetProcGlow and (owner == "proc" or owner == nil) then
            w:SetProcGlow(false)
        end
        f._thudGlowProcActive = false
        local glow = f._thudGlowProc
        if not glow then return end
        if glow.ProcLoop and glow.ProcLoop.Stop and glow.ProcLoop.IsPlaying and glow.ProcLoop:IsPlaying() then
            pcall(glow.ProcLoop.Stop, glow.ProcLoop)
        end
        if glow.ProcStartAnim and glow.ProcStartAnim.Stop and glow.ProcStartAnim.IsPlaying and glow.ProcStartAnim:IsPlaying() then
            pcall(glow.ProcStartAnim.Stop, glow.ProcStartAnim)
        end
        glow:Hide()
    end,
}

local BORDER_THICKNESS = 2
local BORDER_OUTSET    = 1

local function borderEnsure(f)
    if f._thudGlowBorder then return f._thudGlowBorder end
    local function side()
        local t = f:CreateTexture(nil, "OVERLAY", nil, 2)
        return t
    end
    local top, bottom, left, right = side(), side(), side(), side()
    local out = BORDER_OUTSET
    top:SetPoint("TOPLEFT",     f, "TOPLEFT",     -out,  out)
    top:SetPoint("TOPRIGHT",    f, "TOPRIGHT",     out,  out)
    top:SetHeight(BORDER_THICKNESS)
    bottom:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  -out, -out)
    bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  out, -out)
    bottom:SetHeight(BORDER_THICKNESS)
    left:SetPoint("TOPLEFT",     f, "TOPLEFT",     -out,  out)
    left:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  -out, -out)
    left:SetWidth(BORDER_THICKNESS)
    right:SetPoint("TOPRIGHT",    f, "TOPRIGHT",     out,  out)
    right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  out, -out)
    right:SetWidth(BORDER_THICKNESS)
    f._thudGlowBorder = { top = top, bottom = bottom, left = left, right = right }
    return f._thudGlowBorder
end

STYLES.border = {
    apply = function(f, intent, opts)
        f._thudGlowBorderIntent = intent
        local w = _widgets[f]
        if intent == "activeAura" and w and w.SetActiveBorder then
            local r, g, b, a = _resolveColor(intent, opts)
            w:SetActiveBorder(true, r, g, b, a)
            local gb = f._thudGlowBorder
            if gb then
                for _, t in pairs(gb) do t:Hide() end
            end
            return
        end
        if w and w.SetActiveBorder then
            w:SetActiveBorder(false)
        end
        local border = borderEnsure(f)
        if not border then return end
        local r, g, b, a = _resolveColor(intent, opts)
        for _, t in pairs(border) do
            t:SetColorTexture(r, g, b, a)
            t:Show()
        end
    end,
    clear = function(f)
        local owner = f._thudGlowBorderIntent
        f._thudGlowBorderIntent = nil
        local w = _widgets[f]
        if w and w.SetActiveBorder and (owner == "activeAura" or owner == nil) then
            w:SetActiveBorder(false)
        end
        local border = f._thudGlowBorder
        if not border then return end
        for _, t in pairs(border) do
            t:Hide()
        end
    end,
}

local PIXEL_THICKNESS = 1.5

local function pixelEnsure(f)
    if f._thudGlowPixel then return f._thudGlowPixel end

    local g = CreateFrame("Frame", nil, f)
    g:SetFrameLevel((f:GetFrameLevel() or 1) + 5)
    g:SetAllPoints(f)
    g:Hide()

    local function makeEdge(which)
        local t = g:CreateTexture(nil, "OVERLAY")
        if which == "TOP" then
            t:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
            t:SetPoint("TOPRIGHT", g, "TOPRIGHT", 0, 0)
            t:SetHeight(PIXEL_THICKNESS)
        elseif which == "BOTTOM" then
            t:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", 0, 0)
            t:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 0, 0)
            t:SetHeight(PIXEL_THICKNESS)
        elseif which == "LEFT" then
            t:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
            t:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", 0, 0)
            t:SetWidth(PIXEL_THICKNESS)
        else
            t:SetPoint("TOPRIGHT", g, "TOPRIGHT", 0, 0)
            t:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 0, 0)
            t:SetWidth(PIXEL_THICKNESS)
        end
        return t
    end

    g.edges = {
        makeEdge("TOP"),
        makeEdge("BOTTOM"),
        makeEdge("LEFT"),
        makeEdge("RIGHT"),
    }

    local ag = g:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1.0)
    fadeOut:SetToAlpha(0.3)
    fadeOut:SetDuration(0.5)
    fadeOut:SetOrder(1)
    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0.3)
    fadeIn:SetToAlpha(1.0)
    fadeIn:SetDuration(0.5)
    fadeIn:SetOrder(2)
    g.animGroup = ag

    f._thudGlowPixel = g
    return g
end

STYLES.pixel = {
    apply = function(f, intent, opts)
        local g = pixelEnsure(f)
        if not g then return end
        local r, gr, b, a = _resolveColor(intent, opts)
        for i = 1, #g.edges do
            g.edges[i]:SetColorTexture(r, gr, b, a)
        end
        g:Show()
        if g.animGroup and not g.animGroup:IsPlaying() then
            g.animGroup:Play()
        end
    end,
    clear = function(f)
        local g = f._thudGlowPixel
        if not g then return end
        if g.animGroup and g.animGroup.Stop then
            pcall(g.animGroup.Stop, g.animGroup)
        end
        g:Hide()
    end,
}

local OVERLAY_ALPHA_SCALE = 0.4

STYLES.overlay = {
    apply = function(f, intent, opts)
        local t = f._thudGlowOverlay
        if not t then
            t = f:CreateTexture(nil, "OVERLAY", nil, 1)
            t:SetAllPoints(f)
            t:Hide()
            f._thudGlowOverlay = t
        end
        local r, g, b, a = _resolveColor(intent, opts)
        t:SetColorTexture(r, g, b, a * OVERLAY_ALPHA_SCALE)
        t:Show()
    end,
    clear = function(f)
        local t = f._thudGlowOverlay
        if t then t:Hide() end
    end,
}

local SOLID_THICKNESS = 5
local SOLID_OUTSET    = 2

local function solidEnsure(f)
    if f._thudGlowSolid then return f._thudGlowSolid end
    local function side()
        return f:CreateTexture(nil, "OVERLAY", nil, 2)
    end
    local top, bottom, left, right = side(), side(), side(), side()
    local out = SOLID_OUTSET
    top:SetPoint("TOPLEFT",     f, "TOPLEFT",     -out,  out)
    top:SetPoint("TOPRIGHT",    f, "TOPRIGHT",     out,  out)
    top:SetHeight(SOLID_THICKNESS)
    bottom:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  -out, -out)
    bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  out, -out)
    bottom:SetHeight(SOLID_THICKNESS)
    left:SetPoint("TOPLEFT",     f, "TOPLEFT",     -out,  out)
    left:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  -out, -out)
    left:SetWidth(SOLID_THICKNESS)
    right:SetPoint("TOPRIGHT",    f, "TOPRIGHT",     out,  out)
    right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  out, -out)
    right:SetWidth(SOLID_THICKNESS)
    f._thudGlowSolid = { top = top, bottom = bottom, left = left, right = right }
    return f._thudGlowSolid
end

STYLES.solid = {
    apply = function(f, intent, opts)
        local edges = solidEnsure(f)
        if not edges then return end
        local r, g, b, a = _resolveColor(intent, opts)
        for _, t in pairs(edges) do
            t:SetColorTexture(r, g, b, a)
            t:Show()
        end
    end,
    clear = function(f)
        local edges = f._thudGlowSolid
        if not edges then return end
        for _, t in pairs(edges) do
            t:Hide()
        end
    end,
}

local function _styleFor(intent, opts)
    if opts and type(opts.style) == "string" and STYLES[opts.style] then
        return opts.style
    end
    local gd = _globalDefault(intent)
    if gd and type(gd.style) == "string" and STYLES[gd.style] then
        return gd.style
    end
    return INTENT_STYLE[intent]
end

local function _Resolve(f)
    local rec = _state[f]
    if rec and next(rec) == nil then
        _state[f] = nil
        rec = nil
    end

    local applied = {}

    if rec and _isGlobalEnabled() then
        local winners = _computeWinners(rec)
        local ordered = {}
        for _, intent in pairs(winners) do
            ordered[#ordered + 1] = intent
        end
        table.sort(ordered, function(a, b)
            return (PRIORITY[a] or 0) > (PRIORITY[b] or 0)
        end)
        for i = 1, #ordered do
            local intent = ordered[i]
            local opts = rec[intent]
            local styleName = _styleFor(intent, opts)
            local style = styleName and STYLES[styleName]
            if style and not applied[styleName] then
                local ok, err = pcall(style.apply, f, intent, opts)
                if ok then
                    applied[styleName] = true
                    local la = _lastApplied[f]
                    if not la then
                        la = {}
                        _lastApplied[f] = la
                    end
                    la.intent = intent
                    la.style  = styleName
                    la.reason = (opts and opts.reason) or nil
                    la.at     = GetTime()
                elseif ns.Debug and ns.Debug.Log then
                    ns.Debug:Log("Glow: style '%s' apply failed: %s", tostring(styleName), tostring(err))
                end
            end
        end
    end

    for name, style in pairs(STYLES) do
        if not applied[name] then
            pcall(style.clear, f)
        end
    end

    if next(applied) == nil then
        local la = _lastApplied[f]
        if la and la.intent ~= "(cleared)" then
            la.intent = "(cleared)"
            la.style  = "-"
            la.at     = GetTime()
        end
    end
end

function Glow:Set(target, intent, opts)
    local f, widget = _resolveTarget(target)
    if not f then return false end
    if not PRIORITY[intent] then return false end
    if widget then
        _widgets[f] = widget
    end
    local rec = _state[f]
    if not rec then
        rec = {}
        _state[f] = rec
    end
    rec[intent] = (type(opts) == "table") and opts or {}
    _Resolve(f)
    return true
end

function Glow:Clear(target, intent)
    local f = _resolveTarget(target)
    if not f then return false end
    local rec = _state[f]
    if not rec or rec[intent] == nil then return false end
    rec[intent] = nil
    _Resolve(f)
    return true
end

function Glow:ClearAll(target)
    local f = _resolveTarget(target)
    if not f then return false end
    _state[f] = nil
    if _previewTokens[f] then _previewTokens[f] = nil end
    _Resolve(f)
    return true
end

function Glow:IsActive(target, intent)
    local f = _resolveTarget(target)
    if not f then return false end
    local rec = _state[f]
    return (rec ~= nil) and (rec[intent] ~= nil)
end

function Glow:Preview(target, intent, opts, duration)
    local f = _resolveTarget(target)
    if not f then return false end
    if not PRIORITY[intent] then return false end
    duration = tonumber(duration) or 3

    if not self:Set(f, intent, opts) then return false end

    local tokens = _previewTokens[f]
    if not tokens then
        tokens = {}
        _previewTokens[f] = tokens
    end
    local token = {}
    tokens[intent] = token

    C_Timer.After(duration, function()
        local cur = _previewTokens[f]
        if cur and cur[intent] == token then
            cur[intent] = nil
            Glow:Clear(f, intent)
        end
    end)
    return true
end

function Glow:RegisterStyle(name, def)
    if type(name) ~= "string" or name == "" then return false end
    if type(def) ~= "table" then return false end
    if type(def.apply) ~= "function" or type(def.clear) ~= "function" then return false end
    if STYLES[name] then return false end
    STYLES[name] = def
    return true
end

function Glow:GetRegisteredStyles()
    local names = {}
    for name in pairs(STYLES) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

local STYLE_LABELS = {
    blizzard = "Blizzard",
    border   = "Border",
    pixel    = "Pixel",
    overlay  = "Overlay",
    solid    = "Solid Outline",
}

function Glow:GetStyleLabel(name)
    if type(name) ~= "string" then return tostring(name) end
    local label = STYLE_LABELS[name]
    if label then return label end
    local fx = name:match("^fx_(.+)$")
    if fx then
        local pretty = fx:gsub("_", " "):gsub("(%a)([%w]*)", function(a, b)
            return a:upper() .. b
        end)
        return "FX: " .. pretty
    end
    return name
end

function Glow:GetGlobalDefault(intent)
    local d = _globalDefault(intent)
    if not d then return nil, nil end
    local style = nil
    if type(d.style) == "string" and STYLES[d.style] then
        style = d.style
    end
    local color = (type(d.color) == "table") and d.color or nil
    return style, color
end

function Glow:ResolveAll()
    for f in pairs(_state) do
        _Resolve(f)
    end
end

local INTENT_ORDER = { "proc", "pandemic", "ready", "activeAura" }

function Glow:GetDumpLines()
    local lines = {}
    local function L(fmt, ...)
        lines[#lines + 1] = fmt:format(...)
    end

    L("=== ns.Glow dump (G4: full registry + global defaults; Auras pandemic/active stay on their own engine) ===")
    L("masterToggle (profile.modules.Glow.globalEnabled): %s",
        _isGlobalEnabled() and "ON" or "OFF")

    do
        local rules = {}
        for excluder, victims in pairs(EXCLUSIVE) do
            for victim in pairs(victims) do
                rules[#rules + 1] = excluder .. " suppresses " .. victim
            end
        end
        table.sort(rules)
        L("exclusivity: %s (one glow at a time, victim restored when the excluder ends)",
            table.concat(rules, "; "))
    end
    L("intents (priority / channel / builtin style / builtin color):")
    for i = 1, #INTENT_ORDER do
        local intent = INTENT_ORDER[i]
        local c = INTENT_COLOR[intent]
        local colorStr = c and ("%.2f %.2f %.2f %.2f"):format(c[1], c[2], c[3], c[4])
            or "(template art)"
        L("  %-10s prio=%d channel=%-7s style=%-8s color=%s",
            intent, PRIORITY[intent], CHANNEL[intent], INTENT_STYLE[intent], colorStr)
    end

    L("global defaults (profile.modules.Glow.defaults):")
    local anyDefault = false
    for i = 1, #INTENT_ORDER do
        local intent = INTENT_ORDER[i]
        local d = _globalDefault(intent)
        if d and (d.style ~= nil or d.color ~= nil) then
            anyDefault = true
            local c = d.color
            local colorStr = "(builtin)"
            if type(c) == "table" then
                colorStr = ("%.2f %.2f %.2f %.2f"):format(
                    tonumber(c[1]) or 0, tonumber(c[2]) or 0,
                    tonumber(c[3]) or 0, tonumber(c[4]) or 1)
            end
            L("  %-10s style=%-8s color=%s",
                intent, tostring(d.style or "(builtin)"), colorStr)
        end
    end
    if not anyDefault then
        L("  (none -- builtin visuals)")
    end

    local styleNames = {}
    for name in pairs(STYLES) do styleNames[#styleNames + 1] = name end
    table.sort(styleNames)
    L("styles registered: %s", table.concat(styleNames, ", "))

    local frameCount = 0
    for f, rec in pairs(_state) do
        frameCount = frameCount + 1
        local name = (f.GetName and f:GetName()) or tostring(f)
        local winners, suppressed = _computeWinners(rec)
        local parts = {}
        for i = 1, #INTENT_ORDER do
            local intent = INTENT_ORDER[i]
            if rec[intent] then
                local ch = CHANNEL[intent]
                local mark
                if suppressed and suppressed[intent] then
                    mark = "suppressed"
                elseif winners[ch] == intent then
                    mark = "WINNER"
                else
                    mark = "loser"
                end
                parts[#parts + 1] = ("%s(%s:%s)"):format(intent, ch, mark)
            end
        end
        L("  frame %s -> %s", name, table.concat(parts, "  "))

        local function shownOf(obj)
            if type(obj) ~= "table" or type(obj.IsShown) ~= "function" then return "-" end
            local ok, s = pcall(obj.IsShown, obj)
            if not ok then return "?" end
            return s and "shown" or "hidden"
        end
        local procFrame = f._thudGlowProc or f._procGlow
        local procShown = shownOf(procFrame)
        local procLoopPlaying = "-"
        if type(procFrame) == "table" and type(procFrame.ProcLoop) == "table"
           and type(procFrame.ProcLoop.IsPlaying) == "function" then
            local ok, p = pcall(procFrame.ProcLoop.IsPlaying, procFrame.ProcLoop)
            if ok then procLoopPlaying = p and "playing" or "stopped" else procLoopPlaying = "?" end
        end
        local readyShown = "-"
        local gb = f._thudGlowBorder
        if type(gb) == "table" and type(gb.top) == "table" then
            readyShown = shownOf(gb.top)
        end
        L("    actual: procFrame=%s procLoop=%s readyBorder=%s blizzActiveFlag=%s blizzIntent=%s borderIntent=%s",
            procShown, procLoopPlaying, readyShown,
            tostring(f._thudGlowProcActive),
            tostring(f._thudGlowBlizzardIntent),
            tostring(f._thudGlowBorderIntent))
    end
    if frameCount == 0 then
        L("live state: (empty -- no frames carry glow intents)")
    else
        L("live state: %d frame(s)", frameCount)
    end

    local now = GetTime()
    local lastCount = 0
    L("last applied (per frame, includes cleared):")
    for f, la in pairs(_lastApplied) do
        lastCount = lastCount + 1
        local name = (f.GetName and f:GetName()) or tostring(f)
        L("  frame %s -> intent=%s style=%s reason=%s age=%.1fs",
            name, tostring(la.intent), tostring(la.style),
            tostring(la.reason or "-"), now - (la.at or 0))
    end
    if lastCount == 0 then
        L("  (no applies recorded yet this session)")
    end
    L("=== end glow dump ===")
    return lines
end
