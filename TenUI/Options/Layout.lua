local addonName, ns = ...

local type      = type
local pairs     = pairs
local ipairs    = ipairs
local tonumber  = tonumber
local tostring  = tostring
local pcall     = pcall

local ANCHOR_KEYS = {
    { key = "Resources",          label = "Primary Resource" },
    { key = "ResourceSecondary",  label = "Secondary Resource" },
    { key = "CastBar",            label = "Cast Bar" },
    { key = "EssentialCooldowns", label = "Essential Cooldowns" },
    { key = "UtilityCooldowns",   label = "Utility Cooldowns" },
    { key = "DefensiveCooldowns", label = "Defensive Cooldowns" },
    { key = "Trinkets",           label = "Trinkets" },
    { key = "Consumables",        label = "Consumables" },
    { key = "TrackedIcon",        label = "Tracked Icons" },
    { key = "TrackedBars",        label = "Tracked Bars" },
    { key = "DragonRiding",       label = "Dragon Riding" },
}

local BAR_ANCHOR_SET = {
    EssentialCooldowns = true,
    UtilityCooldowns   = true,
    DefensiveCooldowns = true,
    Trinkets           = true,
    Consumables        = true,
    TrackedIcon        = true,
}

local ICON_VISUAL_SET = {
    EssentialCooldowns = true,
    UtilityCooldowns   = true,
    DefensiveCooldowns = true,
    Trinkets           = true,
    Consumables        = true,
    TrackedIcon        = true,
}
local BAR_VISUAL_SET = {
    TrackedBars = true,
}

local function isCustomBarKey(key)
    return type(key) == "string" and key:sub(1, 9) == "CustomBar"
end

local function isIconVisualAnchor(key)
    return ICON_VISUAL_SET[key] == true or isCustomBarKey(key)
end

local function isBarAnchor(key)
    return BAR_ANCHOR_SET[key] == true or isCustomBarKey(key)
end

local function buildAnchorKeyList()
    local out = {}
    for i = 1, #ANCHOR_KEYS do
        out[#out + 1] = ANCHOR_KEYS[i]
    end
    local ebon = ns:GetAnchor("EbonMight")
    local soul = ns:GetAnchor("ArcaneSoul")
    if soul then out[#out + 1] = { key = "ArcaneSoul", label = soul.def.label } end
    if ebon then out[#out + 1] = { key = "EbonMight", label = ebon.def.label } end
    if ns.Bars and ns.Bars.GetCustomBars and ns.Bars.CustomRowKey then
        for _, def in ipairs(ns.Bars:GetCustomBars()) do
            out[#out + 1] = {
                key   = ns.Bars:CustomRowKey(def.id),
                label = (def.name or ("Custom " .. tostring(def.id))) .. " (Custom Bar)",
            }
        end
    end
    return out
end

local function getVisualsProfile(anchorName)
    if not ns.savedVarsReady then return {} end
    if ns.GetLayoutVisuals then
        local vp = ns:GetLayoutVisuals(anchorName, true)
        if type(vp) == "table" then return vp end
    end
    local p = ns:GetProfile()
    p.modules = p.modules or {}
    p.modules.Layout = p.modules.Layout or {}
    p.modules.Layout.visuals = p.modules.Layout.visuals or {}
    p.modules.Layout.visuals[anchorName] = p.modules.Layout.visuals[anchorName] or {}
    return p.modules.Layout.visuals[anchorName]
end

local function getVisibilityProfile(anchorName)
    local vp = getVisualsProfile(anchorName)
    vp.visibility = vp.visibility or {}
    vp.visibility.state = vp.visibility.state or "always"
    vp.visibility.options = vp.visibility.options or {}
    return vp.visibility
end

local function requestVisibilityUpdate()
    if ns.Visibility and ns.Visibility.ScheduleUpdate then
        ns.Visibility:ScheduleUpdate()
    end
end

local function applyVisualSize(anchorName)
    if ns.Bars and ns.Bars.rows then
        for _, row in pairs(ns.Bars.rows) do
            if row.Layout then pcall(row.Layout, row) end
        end
    end
    if (anchorName == "TrackedIcon" or anchorName == "TrackedBars")
       and ns.Auras and ns.Auras.RequestRefresh then
        pcall(ns.Auras.RequestRefresh, ns.Auras)
    end
end

local function getIconCooldownTextProfile(anchorName)
    local vp = getVisualsProfile(anchorName)
    vp.textCooldown = vp.textCooldown or {}
    return vp.textCooldown
end

local function getIconStackTextProfile(anchorName)
    local vp = getVisualsProfile(anchorName)
    vp.textStack = vp.textStack or {}
    return vp.textStack
end

local function getBarsTextProfile(which)
    local vp = getVisualsProfile("TrackedBars")
    vp.text = vp.text or {}
    vp.text[which] = vp.text[which] or {}
    return vp.text[which]
end

local function applyTextStyle(anchorName)
    if anchorName == "TrackedIcon" then
        if ns.Auras and ns.Auras.IconDisplay and ns.Auras.IconDisplay.ApplyVisualOptions then
            pcall(ns.Auras.IconDisplay.ApplyVisualOptions, ns.Auras.IconDisplay)
        end
        return
    end
    if anchorName == "TrackedBars" then
        if ns.Auras and ns.Auras.BarDisplay and ns.Auras.BarDisplay.ApplyVisualOptions then
            pcall(ns.Auras.BarDisplay.ApplyVisualOptions, ns.Auras.BarDisplay)
        end
        return
    end
    if ns.Bars and ns.Bars.rows and ns.Bars.rows[anchorName]
       and ns.Bars.rows[anchorName].ApplyVisualOptions then
        pcall(ns.Bars.rows[anchorName].ApplyVisualOptions, ns.Bars.rows[anchorName])
    end
end

local _selectedAnchor = "Resources"

local _xSlider = nil
local _ySlider = nil

local _updatingFromAnchor = false
ns:RegisterMessage("ANCHOR_MOVED", function(_, anchorName, x, y)
    if anchorName ~= _selectedAnchor then return end
    if not (_xSlider and _ySlider) then return end
    if _updatingFromAnchor then return end
    _updatingFromAnchor = true
    local entry = ns.Anchors:ResolveEntry(anchorName)
    if entry and entry.attachTo then x, y = entry.attachX or 0, entry.attachY or -2 end
    local xi = math.floor((x or 0) + 0.5)
    local yi = math.floor((y or 0) + 0.5)
    if _xSlider.slider then _xSlider.slider:SetValue(xi) end
    if _xSlider.editBox then _xSlider.editBox:SetText(tostring(xi)) end
    if _ySlider.slider then _ySlider.slider:SetValue(yi) end
    if _ySlider.editBox then _ySlider.editBox:SetText(tostring(yi)) end
    _updatingFromAnchor = false
end)

local function getSelectedAnchorProfile()
    if not ns.savedVarsReady then return {} end
    if ns.Anchors and ns.Anchors.GetEditableEntry then
        return ns.Anchors:GetEditableEntry(_selectedAnchor)
    end
    local saved = ns:GetProfile()
    saved.anchors = saved.anchors or {}
    saved.anchors[_selectedAnchor] = saved.anchors[_selectedAnchor] or {}
    return saved.anchors[_selectedAnchor]
end

local function readSelectedAnchorProfile()
    if not ns.savedVarsReady then return {} end
    if ns.Anchors and ns.Anchors.ResolveEntry then
        return ns.Anchors:ResolveEntry(_selectedAnchor) or {}
    end
    local saved = ns:GetProfile()
    return (saved.anchors and saved.anchors[_selectedAnchor]) or {}
end

local function getSnapProfile()
    if not ns.savedVarsReady then return {} end
    local p = ns:GetProfile()
    p.modules = p.modules or {}
    p.modules.Layout = p.modules.Layout or {}
    p.modules.Layout.snapping = p.modules.Layout.snapping or {
        enabled      = false,
        distance     = 6,
        gap          = 2,
        showLines    = true,
        snapToCenter = true,
        snapToAnchors = true,
        showGrid     = false,
        gridSize     = 32,
    }
    return p.modules.Layout.snapping
end

local function addTextStyleControls(children, sc, C, label, getStyle, apply)
    if label and label ~= "" then
        children[#children + 1] = C.CreateSubSection(sc, label)
    end

    local firstTypeRow = #children + 1
    children[#children + 1] = C.CreateFontDropdown(sc, "Font",
        function() return getStyle().font or "default" end,
        function(v)
            getStyle().font = v
            apply()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Font Size", 6, 32, 1,
        function()
            local s = getStyle().size
            return (type(s) == "number" and s > 0) and s or 12
        end,
        function(v)
            getStyle().size = math.floor(v + 0.5)
            apply()
        end, 12)

    children[#children + 1] = C.CreateOutlineDropdown(sc, "Outline",
        function()
            local fl = getStyle().flags
            return (type(fl) == "string") and fl or "OUTLINE"
        end,
        function(v)
            getStyle().flags = (type(v) == "string") and v or "OUTLINE"
            apply()
        end
    )

    for i = firstTypeRow, #children do children[i].layoutGroup = "typography" end
    local size = children[firstTypeRow+1]
    size.slider:SetWidth(58)
    size.controlWidth = size.controlWidth - 72

    children[#children + 1] = C.CreateTextAnchorDropdown(sc, "Text Anchor",
        function() return getStyle().anchor or "BOTTOMRIGHT" end,
        function(v)
            getStyle().anchor = v
            apply()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "X Offset", -100, 100, 1,
        function()
            local x = getStyle().x
            return (type(x) == "number") and x or 0
        end,
        function(v)
            getStyle().x = math.floor(v + 0.5)
            apply()
        end, 0)

    children[#children + 1] = C.CreateSlider(sc, "Y Offset", -100, 100, 1,
        function()
            local y = getStyle().y
            return (type(y) == "number") and y or 0
        end,
        function(v)
            getStyle().y = math.floor(v + 0.5)
            apply()
        end, 0)
end

local function buildLayoutPage(sc)
    local C = ns.UI
    if not C then return end
    local children, starts = {}, {}

    _xSlider = nil
    _ySlider = nil

    children[#children + 1] = C.CreateSection(sc, "Anchor Positioning")

    local anchorItems = buildAnchorKeyList()
    do
        local found = false
        for i = 1, #anchorItems do
            if anchorItems[i].key == _selectedAnchor then
                found = true
                break
            end
        end
        if not found then _selectedAnchor = "Resources" end
    end

    ns.Options:ClearPinnedHeader("layout")
    sc.searchTab = _selectedAnchor
    children[#children + 1] = C.CreateDropdownLikeList(sc, "Anchor", anchorItems,
        function() return _selectedAnchor end,
        function(k)
            _selectedAnchor = k
            if ns.Options and ns.Options.RebuildPage then
                if InCombatLockdown() then
                    if ns.Options.MarkDirty then ns.Options:MarkDirty() end
                else
                    C_Timer.After(0, function()
                        if not InCombatLockdown() and ns.Options and ns.Options.RebuildPage then
                            ns.Options:RebuildPage("layout")
                        end
                    end)
                end
            elseif ns.Options and ns.Options.MarkDirty then
                ns.Options:MarkDirty()
            end
        end
    )
    local picker = table.remove(children)
    local header = ns.Options:GetPinnedHeader("layout", 59)
    picker:SetParent(header)
    picker:SetPoint("TOPLEFT", header, "TOPLEFT", 8, -2)
    picker:SetPoint("TOPRIGHT", header, "TOPRIGHT", -8, -2)

    if not readSelectedAnchorProfile().attachTo then
        local xsl = C.CreateSlider(sc, "X Offset", -960, 960, 1,
            function()
                local ap = readSelectedAnchorProfile()
                return ap.x or 0
            end,
            function(v)
                if _updatingFromAnchor then return end
                local ap = getSelectedAnchorProfile()
                ap.x = math.floor(v + 0.5)
                if not InCombatLockdown() and ns.Anchors and ns.Anchors.Reapply then
                    ns.Anchors:Reapply(_selectedAnchor)
                end
            end)
        _xSlider = xsl
        children[#children + 1] = xsl
    end

    if not readSelectedAnchorProfile().attachTo then
        local ysl = C.CreateSlider(sc, "Y Offset", -540, 540, 1,
            function()
                local ap = readSelectedAnchorProfile()
                return ap.y or 0
            end,
            function(v)
                if _updatingFromAnchor then return end
                local ap = getSelectedAnchorProfile()
                ap.y = math.floor(v + 0.5)
                if not InCombatLockdown() and ns.Anchors and ns.Anchors.Reapply then
                    ns.Anchors:Reapply(_selectedAnchor)
                end
            end)
        _ySlider = ysl
        children[#children + 1] = ysl
    end

    local targets = {{key = "screen", label = "Screen"}}
    for _, item in ipairs(anchorItems) do
        if ns.Anchors:CanAttach(_selectedAnchor, item.key) then targets[#targets+1] = item end
    end
    local function attachment(field, value)
        if InCombatLockdown() then return end
        local entry = ns.Anchors:GetEditableEntry(_selectedAnchor)
        entry[field] = value
        ns.Anchors:Reapply(_selectedAnchor)
    end
    children[#children+1] = C.CreateDropdownLikeList(sc, "Attach to", targets,
        function() return ns.Anchors:GetEditableEntry(_selectedAnchor).attachTo or "screen" end,
        function(v)
            attachment("attachTo", v ~= "screen" and v or nil)
            ns.Options:RebuildPage("layout")
        end)
    if ns.Anchors:GetEditableEntry(_selectedAnchor).attachTo then
        children[#children+1] = C.CreateDropdownLikeList(sc, "Attach to edge",
            {{key="BOTTOM",label="Below"}, {key="TOP",label="Above"}, {key="LEFT",label="Left"}, {key="RIGHT",label="Right"}},
            function() return ns.Anchors:GetEditableEntry(_selectedAnchor).attachSide or "BOTTOM" end, function(v) attachment("attachSide", v) end)
        for _, axis in ipairs({"X", "Y"}) do
            local key = "attach" .. axis
            children[#children+1] = C.CreateSlider(sc, "Attachment offset " .. axis, -500, 500, 1,
                function() return ns.Anchors:GetEditableEntry(_selectedAnchor)[key] or (key == "attachX" and 0 or -2) end,
                function(v) if not _updatingFromAnchor then attachment(key, v) end end)
            if axis == "X" then _xSlider = children[#children] else _ySlider = children[#children] end
        end
    end

    if ns.Anchors and ns.Anchors:CanMatchEssentialWidth(_selectedAnchor) then
        local anchorName = _selectedAnchor
        children[#children + 1] = C.CreateCheckBox(sc, "Match width of Essential Cooldowns",
            function()
                local visuals = ns:GetLayoutVisuals(anchorName, false)
                return visuals and visuals.matchEssentialWidth == true
            end,
            function(v)
                ns:GetLayoutVisuals(anchorName, true).matchEssentialWidth = v and true or nil
                if not InCombatLockdown() then ns.Anchors:Reapply(anchorName) end
            end
        )
    end

    local modulePage = ({CastBar="castbar", DragonRiding="dragonriding", Resources="resources",
        ResourceSecondary="resources", EbonMight="resources", ArcaneSoul="resources"})[_selectedAnchor]
    if modulePage then
        local title = ({castbar="Cast Bar", dragonriding="Dragon Riding", resources="Resources"})[modulePage]
        children[#children+1] = C.CreateButton(sc, "Configure " .. title .. " visuals", function()
            ns.Options:SelectPage(modulePage)
        end)
    end

    starts[#children+1] = "Style & Text"
    if isIconVisualAnchor(_selectedAnchor) then
        if _selectedAnchor ~= "TrackedIcon" and _selectedAnchor ~= "Consumables" then
            children[#children+1] = C.CreateCheckBox(sc, "Show action keybinds", function() return getVisualsProfile(_selectedAnchor).showKeybind end,
                function(v) getVisualsProfile(_selectedAnchor).showKeybind = v applyTextStyle(_selectedAnchor) end)
            children[#children+1] = C.CreateFontDropdown(sc, "Keybind font", function() return getVisualsProfile(_selectedAnchor).keybindFont end,
                function(v) getVisualsProfile(_selectedAnchor).keybindFont = v applyTextStyle(_selectedAnchor) end)
            children[#children+1] = C.CreateDropdownLikeList(sc, "Keybind corner",
                {{key="TOPLEFT",label="Top left"}, {key="TOPRIGHT",label="Top right"}, {key="BOTTOMLEFT",label="Bottom left"}, {key="BOTTOMRIGHT",label="Bottom right"}},
                function() return getVisualsProfile(_selectedAnchor).keybindCorner or "TOPLEFT" end,
                function(v) getVisualsProfile(_selectedAnchor).keybindCorner = v applyTextStyle(_selectedAnchor) end)
        end
        local function val(key, fallback)
            return function()
                local v = getVisualsProfile(_selectedAnchor)[key]
                if v == nil then return fallback end
                return v
            end
        end
        local function setter(key)
            return function(v)
                getVisualsProfile(_selectedAnchor)[key] = v
                applyTextStyle(_selectedAnchor)
            end
        end
        children[#children+1] = C.CreateSlider(sc,"Icon zoom (%)",0,30,1,val("zoom",8),setter("zoom"),8)
        children[#children+1] = C.CreateSlider(sc,"Swipe opacity (%)",0,100,1,val("swipeAlpha",80),setter("swipeAlpha"),80)
        local tracked = _selectedAnchor == "TrackedIcon"
        children[#children+1] = C.CreateCheckBox(sc,"Reverse cooldown swipe",val("reverseSwipe",tracked),setter("reverseSwipe"))
        if not tracked then
            children[#children+1] = C.CreateSegmentedControl(sc,"Growth",{{key="CENTER",label="Center"},{key="LEFT",label="Forward"},{key="RIGHT",label="Reverse"}},
                val("growth",(ns.Bars.profileRef or {}).iconAnchor or "CENTER"),setter("growth"))
            children[#children+1] = C.CreateCheckBox(sc,"Desaturate on cooldown",val("desaturateCooldown",true),setter("desaturateCooldown"))
            children[#children+1] = C.CreateCheckBox(sc,"Show assisted rotation hint",val("assisted",false),setter("assisted"))
            if LibStub("Masque",true) then children[#children+1] = C.CreateCheckBox(sc,"Use Masque skin",val("masque",false),setter("masque")) end
            for _, setting in ipairs({{"rangeTint","Out of range",{0.64,0.15,0.15,1}},{"powerTint","Insufficient power",{0.5,0.5,1,1}}}) do
                children[#children+1] = C.CreateColorSwatch(sc,setting[2],function() return unpack(val(setting[1],setting[3])()) end,
                    function(...) setter(setting[1])({...}) end,setting[3])
            end
            if _selectedAnchor ~= "Consumables" then
                for _, field in ipairs({{"keybindSize","Keybind size",6,30,10},{"keybindX","Keybind X",-30,30,0},{"keybindY","Keybind Y",-30,30,0}}) do
                    children[#children+1] = C.CreateSlider(sc,field[2],field[3],field[4],1,val(field[1],field[5]),setter(field[1]),field[5])
                end
            end
        end
        local sources = {{key="choose", label="Choose a container…"}}
        for _, item in ipairs(anchorItems) do
            if item.key ~= _selectedAnchor and isIconVisualAnchor(item.key) then sources[#sources+1] = item end
        end
        children[#children+1] = C.CreateDropdownLikeList(sc, "Copy visuals from", sources, function() return "choose" end,
            function(source)
                if source == "choose" or InCombatLockdown() then return end
                local from, to = getVisualsProfile(source), getVisualsProfile(_selectedAnchor)
                for _, key in ipairs({"iconWidth","iconHeight","spacing","orientation","showBorder","borderColor","textCooldown","textStack","text","zoom","swipeAlpha","reverseSwipe","growth","desaturateCooldown","assisted","masque","rangeTint","powerTint","showKeybind","keybindFont","keybindCorner","keybindSize","keybindX","keybindY"}) do
                    to[key] = type(from[key]) == "table" and CopyTable(from[key]) or from[key]
                end
                applyVisualSize(_selectedAnchor)
                applyTextStyle(_selectedAnchor)
                ns.Options:RebuildPage("layout")
            end)
        children[#children + 1] = C.CreateSlider(sc, "Icon Width", 8, 200, 1,
            function()
                local vp = getVisualsProfile(_selectedAnchor)
                return (type(vp.iconWidth) == "number" and vp.iconWidth > 0) and vp.iconWidth or 36
            end,
            function(v)
                local vp = getVisualsProfile(_selectedAnchor)
                vp.iconWidth = math.floor(v + 0.5)
                applyVisualSize(_selectedAnchor)
            end, 36)
        children[#children].settingsGroup = "Position & Size"
        children[#children + 1] = C.CreateSlider(sc, "Icon Height", 8, 200, 1,
            function()
                local vp = getVisualsProfile(_selectedAnchor)
                return (type(vp.iconHeight) == "number" and vp.iconHeight > 0) and vp.iconHeight or 36
            end,
            function(v)
                local vp = getVisualsProfile(_selectedAnchor)
                vp.iconHeight = math.floor(v + 0.5)
                applyVisualSize(_selectedAnchor)
            end, 36)
        children[#children].settingsGroup = "Position & Size"
        children[#children + 1] = C.CreateSlider(sc, "Icon Spacing", 0, 40, 1,
            function()
                local vp = getVisualsProfile(_selectedAnchor)
                return (type(vp.spacing) == "number" and vp.spacing >= 0) and vp.spacing or 2
            end,
            function(v)
                local vp = getVisualsProfile(_selectedAnchor)
                vp.spacing = math.floor(v + 0.5)
                applyVisualSize(_selectedAnchor)
            end, 2)
        children[#children].settingsGroup = "Position & Size"

        children[#children + 1] = C.CreateSegmentedControl(sc, "Orientation",
            {
                { key = "H", label = "Horizontal (default)" },
                { key = "V", label = "Vertical" },
            },
            function()
                local vp = getVisualsProfile(_selectedAnchor)
                return (vp.orientation == "V") and "V" or "H"
            end,
            function(v)
                local vp = getVisualsProfile(_selectedAnchor)
                vp.orientation = (v == "V") and "V" or "H"
                applyVisualSize(_selectedAnchor)
            end
        )

        children[#children + 1] = C.CreateCheckBox(sc, "Show Icon Border",
            function()
                local vp = getVisualsProfile(_selectedAnchor)
                return vp.showBorder ~= false
            end,
            function(v)
                local vp = getVisualsProfile(_selectedAnchor)
                vp.showBorder = v and true or false
                applyTextStyle(_selectedAnchor)
            end
        )

        children[#children + 1] = C.CreateColorSwatch(sc, "Icon Border Color",
            function()
                local vp = getVisualsProfile(_selectedAnchor)
                local c = vp.borderColor
                if type(c) == "table" then return c[1], c[2], c[3], c[4] or 1 end
                return 0, 0, 0, 1
            end,
            function(r, g, b, a)
                local vp = getVisualsProfile(_selectedAnchor)
                vp.borderColor = { r or 0, g or 0, b or 0, a or 1 }
                applyTextStyle(_selectedAnchor)
            end, { 0, 0, 0, 1 })
    elseif BAR_VISUAL_SET[_selectedAnchor] then
        children[#children + 1] = C.CreateSlider(sc, "Bar Width", 40, 600, 1,
            function()
                local vp = getVisualsProfile(_selectedAnchor)
                return (type(vp.barWidth) == "number" and vp.barWidth > 0) and vp.barWidth or 250
            end,
            function(v)
                local vp = getVisualsProfile(_selectedAnchor)
                local n = math.floor(v + 0.5)
                if n < 1 then n = 1 end
                vp.barWidth = n
                applyVisualSize(_selectedAnchor)
            end, 250)
        children[#children].settingsGroup = "Position & Size"
        local function setBar(key,v) getVisualsProfile("TrackedBars")[key] = v applyTextStyle("TrackedBars") end
        children[#children+1] = C.CreateSegmentedControl(sc,"Tracked bar icon",{{key="LEFT",label="Left"},{key="RIGHT",label="Right"},{key="NONE",label="None"}},
            function() return getVisualsProfile("TrackedBars").iconSide or "LEFT" end,function(v) setBar("iconSide",v) end)
        children[#children+1] = C.CreateSegmentedControl(sc,"Timer direction",{{key="drain",label="Drain"},{key="fill",label="Fill"}},
            function() return getVisualsProfile("TrackedBars").timerDirection or "drain" end,function(v) setBar("timerDirection",v) end)
        children[#children+1] = C.CreateDropdownLikeList(sc, "Active bar order outside combat",
            {{key="fixed",label="Configured order"},{key="short",label="Shortest time first"},{key="long",label="Longest time first"}},
            function() return getVisualsProfile("TrackedBars").barOrder or "fixed" end, function(v) setBar("barOrder",v) end)
        children[#children+1] = C.CreateCheckBox(sc,"Show spark at fill edge",function() return getVisualsProfile("TrackedBars").spark end,function(v) setBar("spark",v) end)
        children[#children + 1] = C.CreateSlider(sc, "Bar Height", 6, 60, 1,
            function()
                local vp = getVisualsProfile(_selectedAnchor)
                return (type(vp.barHeight) == "number" and vp.barHeight > 0) and vp.barHeight or 18
            end,
            function(v)
                local vp = getVisualsProfile(_selectedAnchor)
                vp.barHeight = math.floor(v + 0.5)
                applyVisualSize(_selectedAnchor)
            end, 18)
        children[#children].settingsGroup = "Position & Size"
        children[#children + 1] = C.CreateSlider(sc, "Bar Spacing", 0, 40, 1,
            function()
                local vp = getVisualsProfile(_selectedAnchor)
                return (type(vp.spacing) == "number" and vp.spacing >= 0) and vp.spacing or 2
            end,
            function(v)
                local vp = getVisualsProfile(_selectedAnchor)
                vp.spacing = math.floor(v + 0.5)
                applyVisualSize(_selectedAnchor)
            end, 2)
        children[#children].settingsGroup = "Position & Size"

        children[#children + 1] = C.CreateStatusBarTextureDropdown(sc, "Bar Texture",
            function()
                local vp = getVisualsProfile(_selectedAnchor)
                return vp.texture or "Blizzard"
            end,
            function(v)
                local vp = getVisualsProfile(_selectedAnchor)
                vp.texture = v
                applyTextStyle("TrackedBars")
            end
        )

        children[#children + 1] = C.CreateColorSwatch(sc, "Bar Fill Color",
            function()
                local vp = getVisualsProfile(_selectedAnchor)
                local c = vp.fillColor
                if type(c) == "table" then return c[1], c[2], c[3], c[4] or 1 end
                return 1, 1, 1, 1
            end,
            function(r, g, b, a)
                local vp = getVisualsProfile(_selectedAnchor)
                vp.fillColor = { r or 1, g or 1, b or 1, a or 1 }
                applyTextStyle("TrackedBars")
            end, { 1, 1, 1, 1 })

        children[#children + 1] = C.CreateCheckBox(sc, "Show Background",
            function()
                local vp = getVisualsProfile(_selectedAnchor)
                return vp.showBackground ~= false
            end,
            function(v)
                local vp = getVisualsProfile(_selectedAnchor)
                vp.showBackground = v and true or false
                applyTextStyle("TrackedBars")
            end
        )

        children[#children + 1] = C.CreateColorSwatch(sc, "Background Color",
            function()
                local vp = getVisualsProfile(_selectedAnchor)
                local c = vp.bgColor
                if type(c) == "table" then return c[1], c[2], c[3], c[4] or 1 end
                return 0, 0, 0, 0.5
            end,
            function(r, g, b, a)
                local vp = getVisualsProfile(_selectedAnchor)
                vp.bgColor = { r or 0, g or 0, b or 0, a or 0.5 }
                applyTextStyle("TrackedBars")
            end, { 0, 0, 0, 0.5 })

        children[#children + 1] = C.CreateCheckBox(sc, "Show Border",
            function()
                local vp = getVisualsProfile(_selectedAnchor)
                return vp.showBorder == true
            end,
            function(v)
                local vp = getVisualsProfile(_selectedAnchor)
                vp.showBorder = v and true or false
                applyTextStyle("TrackedBars")
            end
        )

        children[#children + 1] = C.CreateColorSwatch(sc, "Border Color",
            function()
                local vp = getVisualsProfile(_selectedAnchor)
                local c = vp.borderColor
                if type(c) == "table" then return c[1], c[2], c[3], c[4] or 1 end
                return 0, 0, 0, 1
            end,
            function(r, g, b, a)
                local vp = getVisualsProfile(_selectedAnchor)
                vp.borderColor = { r or 0, g or 0, b or 0, a or 1 }
                applyTextStyle("TrackedBars")
            end, { 0, 0, 0, 1 })
    else
        children[#children + 1] = C.CreateSlider(sc, "Width", 40, 1000, 1,
            function()
                local ap = getSelectedAnchorProfile()
                return ap.width or 200
            end,
            function(v)
                local ap = getSelectedAnchorProfile()
                ap.width = math.floor(v + 0.5)
                if not InCombatLockdown() then
                    local rt = ns:GetAnchor(_selectedAnchor)
                    if rt and rt.frame then
                        rt.frame:SetWidth(ap.width)
                        ns.Anchors:SaveSize(rt.frame)
                    end
                end
            end, 200)
        children[#children].settingsGroup = "Position & Size"
        children[#children + 1] = C.CreateSlider(sc, "Height", 8, 200, 1,
            function()
                local ap = getSelectedAnchorProfile()
                return ap.height or 32
            end,
            function(v)
                local ap = getSelectedAnchorProfile()
                ap.height = math.floor(v + 0.5)
                if not InCombatLockdown() then
                    local rt = ns:GetAnchor(_selectedAnchor)
                    if rt and rt.frame then
                        rt.frame:SetHeight(ap.height)
                        ns.Anchors:SaveSize(rt.frame)
                    end
                end
            end, 32)
        children[#children].settingsGroup = "Position & Size"
    end

    if not isBarAnchor(_selectedAnchor) then
        children[#children + 1] = C.CreateSlider(sc, "Scale", 0.5, 2.0, 0.05,
            function()
                local ap = getSelectedAnchorProfile()
                return ap.scale or 1.0
            end,
            function(v)
                local ap = getSelectedAnchorProfile()
                ap.scale = v
                if not InCombatLockdown() then
                    local rt = ns:GetAnchor(_selectedAnchor)
                    if rt and rt.frame then
                        ns.Anchors:Reapply(_selectedAnchor)
                        ns.Pixel.RefreshEdges()
                    end
                end
            end, 1.0)
        children[#children].settingsGroup = "Position & Size"
    end

    if isIconVisualAnchor(_selectedAnchor) then
        local selAnchor = _selectedAnchor
        addTextStyleControls(children, sc, C, "Cooldown Text",
            function() return getIconCooldownTextProfile(selAnchor) end,
            function() applyTextStyle(selAnchor) end
        )
        addTextStyleControls(children, sc, C, "Stack Text",
            function() return getIconStackTextProfile(selAnchor) end,
            function() applyTextStyle(selAnchor) end
        )
    elseif BAR_VISUAL_SET[_selectedAnchor] then
        addTextStyleControls(children, sc, C, "Name Text",
            function() return getBarsTextProfile("name") end,
            function() applyTextStyle("TrackedBars") end
        )
        addTextStyleControls(children, sc, C, "Timer Text",
            function() return getBarsTextProfile("timer") end,
            function() applyTextStyle("TrackedBars") end
        )
    end

    children[#children + 1] = C.CreateSlider(sc, "Alpha", 0.0, 1.0, 0.05,
        function()
            local ap = getSelectedAnchorProfile()
            return ap.alpha or 1.0
        end,
        function(v)
            local ap = getSelectedAnchorProfile()
            ap.alpha = v
            if not InCombatLockdown() then
                if ns.Anchors and ns.Anchors.ApplyAlpha then
                    ns.Anchors:ApplyAlpha(_selectedAnchor, v)
                else
                    local rt = ns:GetAnchor(_selectedAnchor)
                    if rt and rt.frame then
                        rt.frame:SetAlpha(v)
                    end
                end
            end
        end, 1.0)

    children[#children].settingsGroup = "Visibility & Snap"
    starts[#children+1] = "Visibility & Snap"
    children[#children + 1] = C.CreateSection(sc, "Visibility")
    children[#children + 1] = C.CreateHelpText(sc,
        "State sets when the bar can appear. The options below hide it in specific situations.")

    do
        local stateItems
        if ns.Visibility and ns.Visibility.STATE_LABELS then
            stateItems = {}
            for i = 1, #ns.Visibility.STATE_LABELS do
                stateItems[#stateItems + 1] = ns.Visibility.STATE_LABELS[i]
            end
        else
            stateItems = {
                { key = "always",        label = "Always" },
                { key = "never",         label = "Never" },
                { key = "in_combat",     label = "In Combat" },
                { key = "out_of_combat", label = "Out of Combat" },
                { key = "in_raid",       label = "In Raid" },
                { key = "in_party",      label = "In Party" },
                { key = "solo",          label = "Solo" },
            }
        end
        children[#children + 1] = C.CreateDropdownLikeList(sc, "State", stateItems,
            function()
                local vis = getVisibilityProfile(_selectedAnchor)
                return vis.state or "always"
            end,
            function(k)
                local vis = getVisibilityProfile(_selectedAnchor)
                vis.state = (type(k) == "string" and k ~= "") and k or "always"
                requestVisibilityUpdate()
            end
        )
    end

    children[#children + 1] = C.CreateCheckBox(sc, "Only Show in Instances",
        function()
            return getVisibilityProfile(_selectedAnchor).options.onlyInstances == true
        end,
        function(v)
            getVisibilityProfile(_selectedAnchor).options.onlyInstances = v and true or false
            requestVisibilityUpdate()
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Hide in Housing",
        function()
            return getVisibilityProfile(_selectedAnchor).options.hideHousing == true
        end,
        function(v)
            getVisibilityProfile(_selectedAnchor).options.hideHousing = v and true or false
            requestVisibilityUpdate()
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Hide when Mounted",
        function()
            return getVisibilityProfile(_selectedAnchor).options.hideMounted == true
        end,
        function(v)
            getVisibilityProfile(_selectedAnchor).options.hideMounted = v and true or false
            requestVisibilityUpdate()
        end
    )

    do
        local BTN_GUTTER = 8
        local resetRow = CreateFrame("Frame", nil, sc)
        resetRow:SetHeight(24)

        local btnSel = C.CreateButton(resetRow, "Reset Selected Anchor", function()
            if InCombatLockdown() then
                DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7TenUI|r: Cannot reset anchor in combat")
                return
            end
            ns:ResetAnchor(_selectedAnchor)
        end)
        btnSel:ClearAllPoints()
        btnSel:SetPoint("TOPLEFT", resetRow, "TOPLEFT", 0, 0)
        btnSel:SetPoint("BOTTOM", resetRow, "BOTTOM", 0, 0)
        btnSel:SetPoint("RIGHT", resetRow, "CENTER", -(BTN_GUTTER / 2), 0)

        local btnAll = C.CreateDestructiveButton(resetRow, "Reset ALL Anchors", function()
            if InCombatLockdown() then
                DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7TenUI|r: Cannot reset anchors in combat")
                return
            end
            ns:ResetAllAnchors()
        end)
        btnAll:ClearAllPoints()
        btnAll:SetPoint("TOPRIGHT", resetRow, "TOPRIGHT", 0, 0)
        btnAll:SetPoint("BOTTOM", resetRow, "BOTTOM", 0, 0)
        btnAll:SetPoint("LEFT", resetRow, "CENTER", (BTN_GUTTER / 2), 0)

        resetRow.settingsGroup = "Position & Size"
        children[#children + 1] = resetRow
    end

    children[#children + 1] = C.CreateSection(sc, "Snap System")
    children[#children + 1] = C.CreateHelpText(sc,
        "While dragging in Edit Mode, anchors snap to the screen center, edges and other anchors. Typed X/Y values never snap.")

    children[#children + 1] = C.CreateCheckBox(sc, "Enable Snapping",
        function() return getSnapProfile().enabled == true end,
        function(v)
            getSnapProfile().enabled = v and true or false
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Snap Distance (px)", 2, 64, 1,
        function() return getSnapProfile().distance or 6 end,
        function(v) getSnapProfile().distance = math.floor(v + 0.5) end, 6)

    children[#children + 1] = C.CreateSlider(sc, "Snap Gap (px)", 0, 20, 1,
        function()
            local g = getSnapProfile().gap
            return (type(g) == "number" and g >= 0) and g or 2
        end,
        function(v)
            local g = math.floor(v + 0.5)
            if g < 0 then g = 0 end
            getSnapProfile().gap = g
        end, 2)

    children[#children + 1] = C.CreateCheckBox(sc, "Show Snap Lines",
        function() return getSnapProfile().showLines ~= false end,
        function(v) getSnapProfile().showLines = v end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Snap to Screen Center",
        function() return getSnapProfile().snapToCenter ~= false end,
        function(v) getSnapProfile().snapToCenter = v end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Snap to Other TenUI Anchors",
        function() return getSnapProfile().snapToAnchors ~= false end,
        function(v) getSnapProfile().snapToAnchors = v end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Show Alignment Grid (Edit Mode)",
        function() return getSnapProfile().showGrid == true end,
        function(v)
            getSnapProfile().showGrid = v and true or false
            if ns.Anchors and ns.Anchors.RefreshGridOverlay then
                ns.Anchors:RefreshGridOverlay()
            end
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Grid Size (px)", 16, 128, 1,
        function()
            local g = getSnapProfile().gridSize
            return (type(g) == "number" and g >= 16 and g <= 128) and g or 32
        end,
        function(v)
            getSnapProfile().gridSize = math.floor(v + 0.5)
            if ns.Anchors and ns.Anchors.RefreshGridOverlay then
                ns.Anchors:RefreshGridOverlay()
            end
        end, 32)

    local byControl = {}
    for index, name in pairs(starts) do if children[index] then byControl[children[index]] = name end end
    local names = { "Position & Size", "Visibility & Snap" }
    if isIconVisualAnchor(_selectedAnchor) or BAR_VISUAL_SET[_selectedAnchor] then table.insert(names, 2, "Style & Text") end
    ns.Options:LayoutSettingsTabs("layout", sc, children, names, byControl, 30)
end

ns.Options.GetSnapSettings = getSnapProfile

function ns.Options:OpenLayoutForAnchor(anchor)
    if not anchor then return end
    _selectedAnchor = anchor
    self:SelectPage("layout", true)
end

ns.Options:RegisterPage({
    key   = "layout",
    label = "Layout",
    build = buildLayoutPage,
    rebuildOnShow = true,
})

ns:RegisterMessage("CUSTOM_BARS_CHANGED", function()
    local O = ns.Options
    if not (O and O.RebuildPage and O.GetCurrentPage) then return end
    if O:GetCurrentPage() == nil then return end
    C_Timer.After(0, function()
        if not InCombatLockdown() and ns.Options and ns.Options.RebuildPage then
            ns.Options:RebuildPage("layout")
        end
    end)
end)
