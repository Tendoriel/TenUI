local addonName, ns = ...

local type     = type
local pairs    = pairs
local math_max = math.max

local function cfg()
    if not ns.savedVarsReady then return nil end
    local p = ns:GetProfile()
    p.modules = p.modules or {}
    p.modules.DragonRiding = p.modules.DragonRiding or {}
    if ns.DragonRiding and ns.DragonRiding.DEFAULTS and ns._deepCopyMissing then
        ns._deepCopyMissing(p.modules.DragonRiding, ns.DragonRiding.DEFAULTS)
    end
    return p.modules.DragonRiding
end

local function getField(key)
    local c = cfg()
    return c and c[key]
end

local function setField(key, v)
    local c = cfg()
    if c then c[key] = v end
end

local function getSub(key, field, default)
    local c = cfg()
    local t = c and c[key]
    if type(t) ~= "table" then return default end
    local v = t[field]
    if v == nil then return default end
    return v
end

local function setSub(key, field, v)
    local c = cfg()
    if not c then return end
    c[key] = c[key] or {}
    c[key][field] = v
end

local function rebuild()
    if ns.dragonRidingRebuild then ns.dragonRidingRebuild() end
end

local function redraw()
    if ns.dragonRidingRedraw then ns.dragonRidingRedraw() end
end

local function colorGetter(key)
    return function()
        local c = cfg()
        local t = c and c[key]
        if type(t) ~= "table" then return 1, 1, 1, 1 end
        return t.r or 1, t.g or 1, t.b or 1, t.a or 1
    end
end

local function colorSetter(key)
    return function(r, g, b, a)
        local c = cfg()
        if not c then return end
        c[key] = c[key] or {}
        c[key].r, c[key].g, c[key].b, c[key].a = r, g, b, a
        redraw()
    end
end

local JUSTIFY_VALUES = {
    { key = "LEFT",   label = "Left" },
    { key = "CENTER", label = "Center" },
    { key = "RIGHT",  label = "Right" },
}

local function buildDragonRidingPage(sc)
    local C = ns.UI
    if not C then return end
    local children = {}

    children[#children + 1] = C.CreateSection(sc, "Dragon Riding")

    children[#children + 1] = C.CreateHelpText(sc,
        "Skyriding HUD: glide speed, Skyward Ascent / Second Wind charges and Whirling Surge cooldown. Shown only while on a skyriding mount.")

    children[#children + 1] = C.CreateCheckBox(sc, "Enable Dragon Riding HUD",
        function() return getField("enabled") ~= false end,
        function(v) setField("enabled", v) rebuild() end)

    children[#children + 1] = C.CreateCheckBox(sc, "Hide in Combat",
        function() return getField("hideInCombat") == true end,
        function(v) setField("hideInCombat", v) rebuild() end)

    children[#children + 1] = C.CreateCheckBox(sc, "Show in Instances (M+/Raid/Dungeon)",
        function() return getField("showInstances") == true end,
        function(v) setField("showInstances", v) rebuild() end)

    children[#children + 1] = C.CreateSubSection(sc, "Layout")

    children[#children + 1] = C.CreateSlider(sc, "Width", 80, 600, 1,
        function() return getField("width") or 240 end,
        function(v) setField("width", v) rebuild() end)

    children[#children + 1] = C.CreateSlider(sc, "Element Spacing", 0, 12, 1,
        function() return getField("gap") or 2 end,
        function(v) setField("gap", v) rebuild() end)

    children[#children + 1] = C.CreateSlider(sc, "Stack Spacing", 0, 10, 1,
        function() return getField("stackSpacing") or 2 end,
        function(v) setField("stackSpacing", v) rebuild() end)

    children[#children + 1] = C.CreateSubSection(sc, "Style")

    children[#children + 1] = C.CreateStatusBarTextureDropdown(sc, "Bar Texture",
        function() return getField("barTexture") or "Blizzard" end,
        function(v) setField("barTexture", v) redraw() end)

    children[#children + 1] = C.CreateSlider(sc, "Border Size", 0, 4, 1,
        function() return getField("borderThickness") or 0 end,
        function(v) setField("borderThickness", v) redraw() end)

    children[#children + 1] = C.CreateColorSwatch(sc, "Border Color",
        colorGetter("borderColor"), colorSetter("borderColor"))

    children[#children + 1] = C.CreateSubSection(sc, "Speed Bar")

    children[#children + 1] = C.CreateSlider(sc, "Speed Bar Height", 4, 40, 1,
        function() return getField("speedHeight") or 14 end,
        function(v) setField("speedHeight", v) rebuild() end)

    children[#children + 1] = C.CreateColorSwatch(sc, "Speed Color",
        colorGetter("normalColor"), colorSetter("normalColor"))

    children[#children + 1] = C.CreateColorSwatch(sc, "Speed Background",
        colorGetter("speedBarBg"), colorSetter("speedBarBg"))

    children[#children + 1] = C.CreateCheckBox(sc, "Thrill Color Change",
        function() return getField("thrillColorToggle") == true end,
        function(v) setField("thrillColorToggle", v) redraw() end)

    children[#children + 1] = C.CreateColorSwatch(sc, "Thrill Color",
        colorGetter("thrillColor"), colorSetter("thrillColor"))

    children[#children + 1] = C.CreateColorSwatch(sc, "Thrill Marker (tick)",
        colorGetter("tickColor"), colorSetter("tickColor"))

    children[#children + 1] = C.CreateCheckBox(sc, "Show Speed Text",
        function() return getSub("speedText", "enabled", true) ~= false end,
        function(v) setSub("speedText", "enabled", v) redraw() end)

    children[#children + 1] = C.CreateDropdownLikeList(sc, "Speed Text Align",
        JUSTIFY_VALUES,
        function() return getSub("speedText", "justify", "CENTER") end,
        function(v) setSub("speedText", "justify", v) redraw() end)

    children[#children + 1] = C.CreateSlider(sc, "Speed Text Size", 6, 32, 1,
        function() return getSub("speedText", "size", 12) end,
        function(v) setSub("speedText", "size", v) redraw() end)

    children[#children + 1] = C.CreateSlider(sc, "Speed Text Offset X", -200, 200, 1,
        function() return getSub("speedText", "offsetX", 0) end,
        function(v) setSub("speedText", "offsetX", v) redraw() end)

    children[#children + 1] = C.CreateSlider(sc, "Speed Text Offset Y", -200, 200, 1,
        function() return getSub("speedText", "offsetY", 0) end,
        function(v) setSub("speedText", "offsetY", v) redraw() end)

    children[#children + 1] = C.CreateSubSection(sc, "Skyward Ascent Charges")

    children[#children + 1] = C.CreateSlider(sc, "Charge Height", 2, 24, 1,
        function() return getField("skyridingHeight") or 10 end,
        function(v) setField("skyridingHeight", v) rebuild() end)

    children[#children + 1] = C.CreateColorSwatch(sc, "Charge Fill",
        colorGetter("skyridingFilled"), colorSetter("skyridingFilled"))

    children[#children + 1] = C.CreateColorSwatch(sc, "Charge Background",
        colorGetter("skyridingBg"), colorSetter("skyridingBg"))

    children[#children + 1] = C.CreateSubSection(sc, "Second Wind Charges")

    children[#children + 1] = C.CreateSlider(sc, "Second Wind Height", 2, 24, 1,
        function() return getField("secondWindHeight") or 6 end,
        function(v) setField("secondWindHeight", v) rebuild() end)

    children[#children + 1] = C.CreateColorSwatch(sc, "Second Wind Fill",
        colorGetter("secondWindFilled"), colorSetter("secondWindFilled"))

    children[#children + 1] = C.CreateColorSwatch(sc, "Second Wind Background",
        colorGetter("secondWindBg"), colorSetter("secondWindBg"))

    children[#children + 1] = C.CreateSubSection(sc, "Whirling Surge")

    children[#children + 1] = C.CreateCheckBox(sc, "Show Cooldown Text",
        function() return getSub("whirlingSurgeText", "enabled", true) ~= false end,
        function(v) setSub("whirlingSurgeText", "enabled", v) redraw() end)

    children[#children + 1] = C.CreateDropdownLikeList(sc, "Cooldown Text Align",
        JUSTIFY_VALUES,
        function() return getSub("whirlingSurgeText", "justify", "CENTER") end,
        function(v) setSub("whirlingSurgeText", "justify", v) redraw() end)

    children[#children + 1] = C.CreateSlider(sc, "Cooldown Text Size", 6, 32, 1,
        function() return getSub("whirlingSurgeText", "size", 12) end,
        function(v) setSub("whirlingSurgeText", "size", v) redraw() end)

    local totalH = C.LayoutVertical(sc, children, 4, -8)
    sc:SetHeight(math_max(totalH, 10))
end

local function refreshDragonRidingPage(sc)
    local kids = { sc:GetChildren() }
    for i = 1, #kids do
        if kids[i] and type(kids[i].Refresh) == "function" then
            pcall(kids[i].Refresh, kids[i])
        end
    end
end

ns.Options:RegisterPage({
    key     = "dragonriding",
    label   = "Dragon Riding",
    build   = buildDragonRidingPage,
    refresh = refreshDragonRidingPage,
})
