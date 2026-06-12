local addonName, ns = ...

local type  = type
local pcall = pcall
local math_max   = math.max
local math_floor = math.floor

local function getGlowProfile()
    if not ns.savedVarsReady then return {} end
    local p = ns:GetProfile()
    p.modules = p.modules or {}
    p.modules.Glow = p.modules.Glow or { globalEnabled = true }
    return p.modules.Glow
end

local function readGlowDefault(intent)
    local g = getGlowProfile()
    local d = g.defaults and g.defaults[intent]
    if type(d) == "table" then return d end
    return nil
end

local function writeGlowDefault(intent)
    local g = getGlowProfile()
    g.defaults = g.defaults or {}
    g.defaults[intent] = g.defaults[intent] or {}
    return g.defaults[intent]
end

local function applyGlowDefaultsLive()
    if ns.Glow and ns.Glow.ResolveAll then
        pcall(ns.Glow.ResolveAll, ns.Glow)
    end
    if ns.Bars and ns.Bars._TickAll then
        pcall(ns.Bars._TickAll, ns.Bars)
    end
end

local function styleLabel(name)
    if ns.Glow and ns.Glow.GetStyleLabel then
        return ns.Glow:GetStyleLabel(name)
    end
    return name
end

local function defaultStyleValues(builtinKey)
    local values = {
        { key = "__builtin", label = "Built-in (" .. styleLabel(builtinKey) .. ")" },
    }
    local names
    if ns.Glow and ns.Glow.GetRegisteredStyles then
        names = ns.Glow:GetRegisteredStyles()
    else
        names = { "blizzard", "border", "overlay", "pixel", "solid" }
    end
    for i = 1, #names do
        values[#values + 1] = { key = names[i], label = styleLabel(names[i]) }
    end
    return values
end

local DEFAULT_INTENT_DEFS = {
    { intent = "proc",  label = "Proc",  builtinStyle = "blizzard", builtinColor = { 1, 1, 1, 1 } },
    { intent = "ready", label = "Ready", builtinStyle = "border",   builtinColor = { 0.3, 1, 0.3, 1 } },
}

local PREVIEW_INTENTS = {
    { label = "Proc",       intent = "proc"       },
    { label = "Pandemic",   intent = "pandemic"   },
    { label = "Ready",      intent = "ready"      },
    { label = "Active Aura",intent = "activeAura" },
}

local function buildGlowPage(sc)
    local C = ns.UI
    if not C then return end
    local Theme = C.Theme
    local children = {}

    children[#children + 1] = C.CreateSection(sc, "Glow Effects")

    children[#children + 1] = C.CreateCheckBox(sc, "Enable Glow Effects (Master Toggle)",
        function()
            return getGlowProfile().globalEnabled ~= false
        end,
        function(v)
            getGlowProfile().globalEnabled = v
            if ns.Glow and ns.Glow.ResolveAll then
                pcall(ns.Glow.ResolveAll, ns.Glow)
            end
        end
    )

    children[#children + 1] = C.CreateHelpText(sc,
        "Priority: Proc > Pandemic > Ready > Active Aura. " ..
        "Per-ability glow: CDM Bars > right-click an ability. " ..
        "Per-aura glow: Auras > right-click an aura.")

    children[#children + 1] = C.CreateSubSection(sc, "Global Glow Defaults")

    for _, def in ipairs(DEFAULT_INTENT_DEFS) do
        local intent = def.intent

        local styleCtl, colorCtl
        styleCtl = C.CreateDropdownLikeList(sc, def.label .. " Default Style",
            defaultStyleValues(def.builtinStyle),
            function()
                local d = readGlowDefault(intent)
                if d and type(d.style) == "string" then return d.style end
                return "__builtin"
            end,
            function(v)
                if v == "__builtin" then
                    local d = readGlowDefault(intent)
                    if d then d.style = nil end
                else
                    writeGlowDefault(intent).style = v
                end
                applyGlowDefaultsLive()
            end
        )
        children[#children + 1] = styleCtl

        colorCtl = C.CreateColorSwatch(sc, def.label .. " Default Color",
            function()
                local d = readGlowDefault(intent)
                local c = d and d.color
                if type(c) == "table" then return c[1], c[2], c[3], c[4] end
                local bc = def.builtinColor
                return bc[1], bc[2], bc[3], bc[4]
            end,
            function(r, g, b, a)
                writeGlowDefault(intent).color = { r, g, b, a }
                applyGlowDefaultsLive()
            end
        )
        children[#children + 1] = colorCtl

        children[#children + 1] = C.CreateCompactButton(sc,
            "Reset " .. def.label .. " Default",
            function()
                local d = readGlowDefault(intent)
                if d then
                    d.style = nil
                    d.color = nil
                end
                applyGlowDefaultsLive()
                if styleCtl and styleCtl.Refresh then pcall(styleCtl.Refresh) end
                if colorCtl and colorCtl.Refresh then pcall(colorCtl.Refresh) end
            end,
            150
        )
    end

    children[#children + 1] = C.CreateHelpText(sc,
        "Defaults apply to abilities without their own style or color override. " ..
        "The Blizzard style uses the game's animated proc art and ignores color. " ..
        "Changes apply immediately.")

    children[#children + 1] = C.CreateSubSection(sc, "Preview")

    local glowAvailable = (ns.Glow ~= nil) and type(ns.Glow.Preview) == "function"

    if not glowAvailable then
        children[#children + 1] = C.CreateHelpText(sc,
            "Glow preview is unavailable in this build.")
    end

    local previewRow = CreateFrame("Frame", nil, sc)
    previewRow:SetHeight(60)
    C.SkinPanel(previewRow)
    children[#children + 1] = previewRow

    local sampleIcon = CreateFrame("Frame", nil, previewRow)
    sampleIcon:SetSize(40, 40)
    sampleIcon:SetPoint("LEFT", previewRow, "LEFT", 10, 0)
    local sampleTex = sampleIcon:CreateTexture(nil, "ARTWORK")
    sampleTex:SetAllPoints(sampleIcon)
    sampleTex:SetTexture("Interface\\Icons\\Spell_Nature_Lightning")
    local sampleBorder = sampleIcon:CreateTexture(nil, "BORDER")
    sampleBorder:SetAllPoints(sampleIcon)
    sampleBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")

    local BTN_GAP = 4
    local previewBtns = {}
    for i, pv in ipairs(PREVIEW_INTENTS) do
        local capturedIntent = pv.intent
        local btn = C.CreateCompactButton(previewRow, pv.label, function()
            if glowAvailable then
                pcall(ns.Glow.Preview, ns.Glow, sampleIcon, capturedIntent, {}, 3)
            end
        end, 90)
        if not glowAvailable then
            btn:SetAlpha(0.4)
        end
        previewBtns[i] = btn
    end
    local btnW = 90
    for i = 1, #previewBtns do
        local lw = previewBtns[i].label and previewBtns[i].label:GetStringWidth() or 0
        if lw + 16 > btnW then btnW = math_floor(lw + 16.5) end
    end
    for i = 1, #previewBtns do
        previewBtns[i]:SetWidth(btnW)
        previewBtns[i]:SetPoint("LEFT", previewRow, "LEFT", 60 + (i - 1) * (btnW + BTN_GAP), 0)
    end

    local totalH = C.LayoutVertical(sc, children, 4, -8)
    sc:SetHeight(math_max(totalH, 10))
end

ns.Options:RegisterPage({
    key   = "glow",
    label = "Glow Effects",
    build = buildGlowPage,
})
