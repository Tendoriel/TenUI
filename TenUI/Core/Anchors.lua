local addonName, ns = ...

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UIParent = UIParent
local pairs = pairs
local type = type
local math_floor = math.floor
local math_huge = math.huge
local math_abs = math.abs

ns.anchors = ns.anchors or {}

local Anchors = {}
ns.Anchors = Anchors

local registry = ns.anchors

local dormantRegistry = {}

local TRACE_RING_SIZE = 10
local _trace = {}

local HISTORY_RING_SIZE = 200

local function _historyPush(event, name, fields)
    if not _G.TenUIDB then return end
    _G.TenUIDB.debug = _G.TenUIDB.debug or {}
    local hist = _G.TenUIDB.debug._anchor_history
    if type(hist) ~= "table" then
        hist = {}
        _G.TenUIDB.debug._anchor_history = hist
    end
    local entry = {
        event = event,
        name  = name,
        at    = date("%H:%M:%S"),
    }
    if type(fields) == "table" then
        for k, v in pairs(fields) do entry[k] = v end
    end
    hist[#hist + 1] = entry
    while #hist > HISTORY_RING_SIZE do
        table.remove(hist, 1)
    end
end

local function _tracePush(anchorName, event, fields)
    if type(anchorName) ~= "string" or anchorName == "" then return end
    local ring = _trace[anchorName]
    if not ring then
        ring = {}
        _trace[anchorName] = ring
    end
    local entry = {
        t      = (GetTime and GetTime()) or 0,
        wall   = date("%H:%M:%S"),
        event  = event,
        fields = fields or {},
    }
    ring[#ring + 1] = entry
    while #ring > TRACE_RING_SIZE do
        table.remove(ring, 1)
    end
    _historyPush(event, anchorName, fields)
end

function Anchors:GetTrace(anchorName)
    local ring = _trace[anchorName]
    if not ring then return {} end
    local out = {}
    for i = 1, #ring do out[i] = ring[i] end
    return out
end

function Anchors:ListTraced()
    local out = {}
    for k in pairs(_trace) do out[#out + 1] = k end
    table.sort(out)
    return out
end

function Anchors:PushTrace(anchorName, event, fields)
    _tracePush(anchorName, event, fields)
end

local DEFAULT_ANCHORS = {
    { name = "TrackedIcon",        label = "Tracked Icons",       point = "CENTER", x =    0, y =  240, width = 320, height = 40 },
    { name = "TrackedBars",        label = "Tracked Bars",        point = "CENTER", x =    0, y =  180, width = 320, height = 24 },
    { name = "EssentialCooldowns", label = "Essential Cooldowns", point = "CENTER", x =    0, y = -120, width = 320, height = 40 },
    { name = "UtilityCooldowns",   label = "Utility Cooldowns",   point = "CENTER", x =    0, y = -170, width = 320, height = 32 },
    { name = "DefensiveCooldowns", label = "Defensive Cooldowns", point = "CENTER", x = -200, y = -120, width = 160, height = 32 },
    { name = "Trinkets",           label = "Trinkets",            point = "CENTER", x =  200, y = -120, width =  80, height = 32 },
    { name = "Resources",          label = "Primary Resource",    point = "CENTER", x =    0, y =  -80, width = 240, height = 18 },
    { name = "ResourceSecondary",  label = "Secondary Resource",  point = "CENTER", x =    0, y = -100, width = 240, height = 16 },
    { name = "CastBar",            label = "Cast Bar",            point = "CENTER", x =    0, y =  -40, width = 240, height = 22 },
}

local function CreateAnchorParent()
    if ns.anchorParent then return ns.anchorParent end
    local p = CreateFrame("Frame", "TenUIAnchorParent", UIParent)
    p:SetAllPoints(UIParent)
    p:SetFrameStrata("MEDIUM")
    ns.anchorParent = p
    ns.parent = p
    return p
end

function ns:CreateAnchorParent()
    return CreateAnchorParent()
end

local parent = CreateAnchorParent()

local VALID_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function isFiniteNumber(v)
    if type(v) ~= "number" then return false end
    if v ~= v then return false end
    if v == math_huge or v == -math_huge then return false end
    return true
end

local function pointHFrac(point)
    if point == "LEFT" or point == "TOPLEFT" or point == "BOTTOMLEFT" then return 0 end
    if point == "RIGHT" or point == "TOPRIGHT" or point == "BOTTOMRIGHT" then return 1 end
    return 0.5
end

local function pointVFrac(point)
    if point == "TOP" or point == "TOPLEFT" or point == "TOPRIGHT" then return 0 end
    if point == "BOTTOM" or point == "BOTTOMLEFT" or point == "BOTTOMRIGHT" then return 1 end
    return 0.5
end

local function originHFrac(point)
    if point == "LEFT" or point == "TOPLEFT" or point == "BOTTOMLEFT" then return 0 end
    if point == "RIGHT" or point == "TOPRIGHT" or point == "BOTTOMRIGHT" then return 1 end
    return 0.5
end

local GROW_UP_ANCHORS = {
    TrackedBars = true,
}

local function originVFrac(point, name)
    if name and GROW_UP_ANCHORS[name] then return 1 end
    if point == "BOTTOM" or point == "BOTTOMLEFT" or point == "BOTTOMRIGHT" then return 1 end
    return 0
end

local function originToSetPoint(point, x, y, w, h, name)
    local setX = (x or 0) + (pointHFrac(point) - originHFrac(point)) * (w or 0)
    local setY = (y or 0) - (pointVFrac(point) - originVFrac(point, name)) * (h or 0)
    return setX, setY
end

local function setPointToOrigin(point, setX, setY, w, h, name)
    local x = (setX or 0) - (pointHFrac(point) - originHFrac(point)) * (w or 0)
    local y = (setY or 0) + (pointVFrac(point) - originVFrac(point, name)) * (h or 0)
    return x, y
end

local function migrateEntryToOriginModel(entry, name)
    if type(entry) ~= "table" then return end
    local point = entry.point
    if type(point) ~= "string" or not VALID_POINTS[point] then return end
    local w = entry.width  or 200
    local h = entry.height or 32
    local ox, oy = setPointToOrigin(point, entry.x or 0, entry.y or 0, w, h, name)
    entry.x = math_floor(ox + 0.5)
    entry.y = math_floor(oy + 0.5)
end

local migrateOriginModel

local function getProfileAnchors()
    local profile = ns:GetProfile()
    profile.anchors = profile.anchors or {}
    return profile.anchors
end

local function getOverlayAnchors(create)
    if not ns.savedVarsReady then return nil end
    return (ns.GetSpecScope and ns:GetSpecScope("anchors", create)) or nil
end

local function resolveSavedEntry(name)
    local overlay = getOverlayAnchors(false)
    if overlay and overlay[name] ~= nil then
        return overlay[name], "overlay"
    end
    return getProfileAnchors()[name], "base"
end

function Anchors:ResolveEntry(name)
    if not ns.savedVarsReady then return nil end
    return (resolveSavedEntry(name))
end

function Anchors:GetEditableEntry(name)
    if not ns.savedVarsReady then return {} end
    local overlay = getOverlayAnchors(true)
    if not overlay then return {} end
    if overlay[name] == nil then
        local base = getProfileAnchors()[name]
        local seed = {}
        if type(base) == "table" then
            seed.point  = base.point
            seed.x      = base.x
            seed.y      = base.y
            seed.width  = base.width
            seed.height = base.height
        end
        overlay[name] = seed
    end
    return overlay[name]
end

local function writeOverlayEntry(name, entry)
    local overlay = getOverlayAnchors(true)
    if overlay then
        overlay[name] = entry
    else
        getProfileAnchors()[name] = entry
    end
end

local function defaultPos(def)
    local d = def.default or {}
    return {
        point  = d.point  or "CENTER",
        x      = d.x      or 0,
        y      = d.y      or 0,
        width  = d.width  or 200,
        height = d.height or 32,
    }
end

local function validatePos(pos, def)
    local d = defaultPos(def)
    if type(pos) ~= "table" then
        return d, true
    end
    local corrupt = false
    local point = pos.point
    if type(point) ~= "string" or not VALID_POINTS[point] then
        point = d.point
        corrupt = true
    end
    local x = pos.x
    if not isFiniteNumber(x) then x = d.x corrupt = true end
    local y = pos.y
    if not isFiniteNumber(y) then y = d.y corrupt = true end
    local width = pos.width
    if not isFiniteNumber(width) or width <= 0 then width = d.width corrupt = true end
    local height = pos.height
    if not isFiniteNumber(height) or height <= 0 then height = d.height corrupt = true end
    return { point = point, x = x, y = y, width = width, height = height }, corrupt
end

local function clampToScreen(pos)
    local pw = UIParent:GetWidth() or 1920
    local ph = UIParent:GetHeight() or 1080
    local maxX = pw
    local maxY = ph
    local x, y = pos.x, pos.y
    if x >  maxX then x =  maxX end
    if x < -maxX then x = -maxX end
    if y >  maxY then y =  maxY end
    if y < -maxY then y = -maxY end
    if x ~= pos.x or y ~= pos.y then
        pos.x, pos.y = x, y
        return true
    end
    return false
end

local function applyPosition(anchor, pos)
    local w = pos.width or anchor:GetWidth() or 200
    local h = pos.height or anchor:GetHeight() or 32
    anchor:SetSize(w, h)
    local setX, setY = originToSetPoint(pos.point, pos.x, pos.y, w, h, anchor.anchorName)
    anchor:ClearAllPoints()
    anchor:SetPoint(pos.point, parent, pos.point, setX, setY)
end

local function anchor_OnDragStart(self)
    if not self:IsMovable() then return end
    if ns:AreAnchorsLocked() then return end
    self:StartMoving()
end

local function anchor_OnDragStop(self)
    self:StopMovingOrSizing()
    Anchors:SavePosition(self)
end

local function buildAnchor(def)
    local name = def.name
    if registry[name] then
        return registry[name]
    end

    local dormantRT = dormantRegistry[name]
    if dormantRT and dormantRT.frame then
        dormantRegistry[name] = nil
        registry[name] = dormantRT
        dormantRT.def.label = def.label or dormantRT.def.label or name
        if type(def.default) == "table" then
            dormantRT.def.default = def.default
        end
        dormantRT.frame.def = dormantRT.def
        if ns.savedVarsReady then
            local raw, tier = resolveSavedEntry(name)
            local hadEntry = raw ~= nil
            local entry, corrupt = validatePos(raw, dormantRT.def)
            if corrupt or not hadEntry then
                migrateEntryToOriginModel(entry, name)
            end
            if tier == "overlay" then
                writeOverlayEntry(name, entry)
            else
                getProfileAnchors()[name] = entry
            end
            applyPosition(dormantRT.frame, entry)
        end
        dormantRT.frame:Show()
        _tracePush(name, "REVIVE", {})
        if ns.Debug and ns.Debug.Log then
            ns.Debug:Log("Anchor revived from dormant cache: %s", name)
        end
        return dormantRT
    end

    local f = CreateFrame("Frame", "TenUIAnchor_" .. name, parent)
    f.anchorName = name
    f.def = def

    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(false)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(40, 16, 1000, 200)
    end
    f:EnableMouse(false)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", anchor_OnDragStart)
    f:SetScript("OnDragStop", anchor_OnDragStop)

    local pos
    if ns.savedVarsReady then
        local saved = getProfileAnchors()
        migrateOriginModel(saved)
        local raw, tier = resolveSavedEntry(name)
        local hadEntry = raw ~= nil
        local entry, corrupt = validatePos(raw, def)
        local dirty = false
        if corrupt or not hadEntry then
            migrateEntryToOriginModel(entry, name)
            dirty = true
        end
        if clampToScreen(entry) then
            dirty = true
        end
        if dirty then
            if tier == "overlay" then
                writeOverlayEntry(name, entry)
            else
                saved[name] = entry
            end
        end
        pos = entry
    else
        pos = defaultPos(def)
    end
    applyPosition(f, pos)

    local runtime = {
        name    = name,
        frame   = f,
        overlay = nil,
        def     = def,
    }
    registry[name] = runtime
    f.runtime = runtime

    if ns.Debug and ns.Debug.Log then
        ns.Debug:Log("Anchor registered: %s at %s (%d,%d) %dx%d",
            name, tostring(pos.point), pos.x or 0, pos.y or 0, pos.width or 0, pos.height or 0)
    end

    return runtime
end

function Anchors:Register(name, def)
    if type(name) ~= "string" or name == "" then
        error("Anchors:Register: name must be a non-empty string", 2)
    end
    if type(def) ~= "table" then
        error("Anchors:Register: def must be a table", 2)
    end
    def.name = name
    def.default = def.default or {}
    def.label = def.label or name
    local runtime = buildAnchor(def)
    return runtime.frame
end

function Anchors:Get(name)
    local r = registry[name]
    return r and r.frame or nil
end

function Anchors:Unregister(name)
    local runtime = registry[name]
    if not runtime then return false end
    registry[name] = nil
    dormantRegistry[name] = runtime
    if runtime.frame then
        runtime.frame:Hide()
        runtime.frame:EnableMouse(false)
    end
    if runtime.overlay then
        runtime.overlay:Hide()
        runtime.overlay:EnableMouse(false)
    end
    _tracePush(name, "UNREGISTER", {})
    if ns.Debug and ns.Debug.Log then
        ns.Debug:Log("Anchor unregistered (parked dormant): %s", name)
    end
    return true
end

function Anchors:SetLabel(name, label)
    local runtime = registry[name]
    if not (runtime and runtime.def) then return false end
    runtime.def.label = (type(label) == "string" and label ~= "") and label or name
    if ns.EditMode and ns.EditMode.RefreshOne and runtime.frame then
        pcall(ns.EditMode.RefreshOne, ns.EditMode, runtime.frame)
    end
    return true
end

function Anchors:Iterate()
    local k
    return function()
        local v
        k, v = next(registry, k)
        if v then return k, v.frame end
    end
end

function Anchors:SavePosition(anchor)
    if not anchor or not anchor.anchorName then return end
    if not ns.savedVarsReady then return end
    local def = anchor.def
    local entry = validatePos(resolveSavedEntry(anchor.anchorName), def)

    local point, _, relativePoint, x, y = anchor:GetPoint(1)
    if not point then
        return
    end
    if not VALID_POINTS[point] then point = entry.point end
    if not isFiniteNumber(x) then x = entry.x end
    if not isFiniteNumber(y) then y = entry.y end

    local canonPoint = (def and def.default and def.default.point) or "CENTER"
    if not VALID_POINTS[canonPoint] then canonPoint = "CENTER" end

    local liveW = anchor:GetWidth()  or entry.width  or 200
    local liveH = anchor:GetHeight() or entry.height or 32
    if not isFiniteNumber(liveW) or liveW <= 0 then liveW = entry.width  or 200 end
    if not isFiniteNumber(liveH) or liveH <= 0 then liveH = entry.height or 32  end

    if point ~= canonPoint then
        x = x + (pointHFrac(canonPoint) - pointHFrac(point)) * liveW
        y = y - (pointVFrac(canonPoint) - pointVFrac(point)) * liveH
        point = canonPoint
        anchor:ClearAllPoints()
        anchor:SetPoint(point, parent, point, x, y)
    elseif relativePoint and relativePoint ~= point then
        anchor:ClearAllPoints()
        anchor:SetPoint(point, parent, point, x, y)
    end

    entry.width  = entry.width  or anchor:GetWidth()  or 200
    entry.height = entry.height or anchor:GetHeight() or 32

    local ox, oy = setPointToOrigin(point, x, y, liveW, liveH, anchor.anchorName)

    entry.point = point
    entry.x = math_floor(ox + 0.5)
    entry.y = math_floor(oy + 0.5)

    writeOverlayEntry(anchor.anchorName, entry)

    _tracePush(anchor.anchorName, "SAVE", {
        point = entry.point, x = entry.x, y = entry.y,
        w = entry.width, h = entry.height,
    })

    if _G.TenUIDB then
        _G.TenUIDB.debug = _G.TenUIDB.debug or {}
        local map = _G.TenUIDB.debug._last_drag_save
        if type(map) ~= "table" then
            map = {}
            _G.TenUIDB.debug._last_drag_save = map
        end
        map[anchor.anchorName] = ("%s @ %d,%d at %s"):format(
            entry.point, entry.x, entry.y, date("%H:%M:%S"))
    end

    if ns.Debug and ns.Debug.Log then
        ns.Debug:Log("[Anchor] SAVE name=%s point=%s x=%d y=%d w=%d h=%d",
            anchor.anchorName, tostring(entry.point), entry.x, entry.y,
            entry.width or 0, entry.height or 0)
    end
end

function Anchors:SaveSize(anchor)
    if not anchor or not anchor.anchorName then return end
    if not ns.savedVarsReady then return end
    local def = anchor.def
    local entry = validatePos(resolveSavedEntry(anchor.anchorName), def)

    local w, h = anchor:GetSize()
    if not isFiniteNumber(w) or w <= 0 then w = entry.width end
    if not isFiniteNumber(h) or h <= 0 then h = entry.height end
    entry.width  = math_floor(w + 0.5)
    entry.height = math_floor(h + 0.5)
    writeOverlayEntry(anchor.anchorName, entry)
    applyPosition(anchor, entry)
    _tracePush(anchor.anchorName, "SIZE", {
        point = entry.point, x = entry.x, y = entry.y,
        w = entry.width, h = entry.height,
    })
    ns:Fire("ANCHOR_RESIZED", anchor.anchorName, entry.width, entry.height)
    if ns.Debug and ns.Debug.Log then
        ns.Debug:Log("Anchor resized: %s -> %s (%d,%d) %dx%d",
            anchor.anchorName, tostring(entry.point), entry.x or 0, entry.y or 0,
            entry.width, entry.height)
    end
end

function Anchors:AutoFitSize(name, w, h)
    if not ns.savedVarsReady then return end
    if InCombatLockdown() then return end
    if type(name) ~= "string" or name == "" then return end
    local runtime = registry[name]
    if not runtime or not runtime.frame then return end
    if not isFiniteNumber(w) or w <= 0 then return end
    if not isFiniteNumber(h) or h <= 0 then return end
    w = math_floor(w + 0.5)
    h = math_floor(h + 0.5)

    local entry = validatePos(resolveSavedEntry(name), runtime.def)
    if entry.width == w and entry.height == h
       and math_floor((runtime.frame:GetWidth() or 0) + 0.5) == w
       and math_floor((runtime.frame:GetHeight() or 0) + 0.5) == h then
        return
    end

    entry.width  = w
    entry.height = h
    writeOverlayEntry(name, entry)
    applyPosition(runtime.frame, entry)
    _tracePush(name, "AUTOFIT", { point = entry.point, x = entry.x, y = entry.y, w = w, h = h })
    if ns.EditMode and ns.EditMode.RefreshOne then
        pcall(ns.EditMode.RefreshOne, ns.EditMode, runtime.frame)
    end
end

local function forceFixTrackedAnchor(saved, anchorName, defaultW, defaultH, minW, minH)
    if type(saved) ~= "table" then return end
    saved[anchorName] = saved[anchorName] or {}
    local entry = saved[anchorName]
    if type(entry) ~= "table" then
        entry = {}
        saved[anchorName] = entry
    end

    local oldW = entry.width
    local oldH = entry.height
    local badW = not isFiniteNumber(oldW) or oldW < 1
    local badH = not isFiniteNumber(oldH) or oldH < 1

    local runtime = registry[anchorName]
    local liveW, liveH
    if runtime and runtime.frame then
        liveW = runtime.frame:GetWidth()
        liveH = runtime.frame:GetHeight()
    end

    if badW or badH then
        entry.width  = defaultW
        entry.height = defaultH
        if runtime and runtime.def then
            runtime.def.default = runtime.def.default or {}
            runtime.def.default.width  = defaultW
            runtime.def.default.height = defaultH
        end
        if runtime and runtime.frame then
            runtime.frame:SetSize(defaultW, defaultH)
        end

        if _G.TenUIDB then
            _G.TenUIDB.debug = _G.TenUIDB.debug or {}
            _G.TenUIDB.debug._last_force_reset = ("%s reset %dx%d (was w=%s h=%s, liveW=%s liveH=%s) at %s"):format(
                anchorName, defaultW, defaultH,
                tostring(oldW), tostring(oldH),
                tostring(liveW), tostring(liveH),
                date("%H:%M:%S"))
        end

        _tracePush(anchorName, "FORCEFIX", {
            w = defaultW, h = defaultH,
            oldW = oldW, oldH = oldH,
            liveW = liveW, liveH = liveH,
            note = "width/height only; point/x/y NEVER mutated here",
        })

        if ns.Debug and ns.Debug.Log then
            ns.Debug:Log("[Anchor] FORCE-RESET %s %dx%d (was w=%s h=%s liveW=%s liveH=%s)",
                anchorName, defaultW, defaultH,
                tostring(oldW), tostring(oldH),
                tostring(liveW), tostring(liveH))
        end
    end
end

local function migrateTinyTrackedAnchors(saved)
    if type(saved) ~= "table" then return end
    if saved._trackedAnchorMigration then return end

    if _G.TenUIDB then
        _G.TenUIDB.debug = _G.TenUIDB.debug or {}
        local ti = saved.TrackedIcon
        local tb = saved.TrackedBars
        _G.TenUIDB.debug._migration_trace = ("ran ONCE at %s; TrackedIcon w=%s h=%s; TrackedBars w=%s h=%s"):format(
            date("%H:%M:%S"),
            tostring(ti and ti.width),  tostring(ti and ti.height),
            tostring(tb and tb.width),  tostring(tb and tb.height))
    end

    if ns.Debug and ns.Debug.Log then
        local ti = saved.TrackedIcon
        local tb = saved.TrackedBars
        ns.Debug:Log("[Anchor] migrateTinyTrackedAnchors (ONE-TIME): checking TrackedIcon width="
            .. tostring(ti and ti.width)
            .. " TrackedBars width="
            .. tostring(tb and tb.width))
    end

    forceFixTrackedAnchor(saved, "TrackedIcon", 320, 40, 1, 1)
    forceFixTrackedAnchor(saved, "TrackedBars", 320, 24, 1, 1)

    saved._trackedAnchorMigration = true
end

function Anchors:ForceResetTracked(name)
    if not ns.savedVarsReady then return false end
    local saved = getProfileAnchors()
    local targets
    if name == nil then
        targets = { "TrackedIcon", "TrackedBars" }
    else
        targets = { name }
    end
    local overlay = getOverlayAnchors(false)
    for i = 1, #targets do
        local n = targets[i]
        local runtime = registry[n]
        if runtime then
            saved[n] = nil
            if overlay then overlay[n] = nil end
            local d = defaultPos(runtime.def)
            local entry = {
                point  = d.point,
                x      = d.x,
                y      = d.y,
                width  = d.width,
                height = d.height,
            }
            migrateEntryToOriginModel(entry, n)
            writeOverlayEntry(n, entry)
            applyPosition(runtime.frame, entry)
            if _G.TenUIDB then
                _G.TenUIDB.debug = _G.TenUIDB.debug or {}
                _G.TenUIDB.debug._last_slash_reset = ("%s slash-reset to %dx%d at %s"):format(
                    n, d.width, d.height, date("%H:%M:%S"))
            end
            if ns.Debug and ns.Debug.Log then
                ns.Debug:Log("[Anchor] SLASH-RESET %s -> %dx%d", n, d.width, d.height)
            end
        end
    end
    if ns.EditMode and ns.EditMode.Refresh then
        ns.EditMode:Refresh()
    end
    return true
end

function Anchors:Inspect()
    local out = {}
    for name, runtime in pairs(registry) do
        local e = ns.savedVarsReady and resolveSavedEntry(name) or nil
        local liveW, liveH, liveX, liveY, livePoint
        if runtime.frame then
            liveW = runtime.frame:GetWidth()
            liveH = runtime.frame:GetHeight()
            local p, _, _, lx, ly = runtime.frame:GetPoint(1)
            livePoint = p
            liveX = lx
            liveY = ly
        end
        out[#out + 1] = {
            name      = name,
            point     = e and e.point  or nil,
            x         = e and e.x      or nil,
            y         = e and e.y      or nil,
            savedW    = e and e.width  or nil,
            savedH    = e and e.height or nil,
            liveW     = liveW,
            liveH     = liveH,
            livePoint = livePoint,
            liveX     = liveX,
            liveY     = liveY,
        }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function wipeDeprecatedBuffsDebuffs(saved)
    if type(saved) ~= "table" then return end
    if saved.BuffsDebuffs ~= nil then
        saved.BuffsDebuffs = nil
        if _G.TenUIDB then
            _G.TenUIDB.debug = _G.TenUIDB.debug or {}
            _G.TenUIDB.debug._buffsdebuffs_wiped = ("wiped at %s"):format(date("%H:%M:%S"))
        end
        if ns.Debug and ns.Debug.Log then
            ns.Debug:Log("[Anchor] WIPED deprecated saved.BuffsDebuffs blob")
        end
    end
end

function migrateOriginModel(saved)
    if type(saved) ~= "table" then return end
    if saved._originModel then return end
    for name, entry in pairs(saved) do
        if type(name) == "string" and name:sub(1, 1) ~= "_" then
            migrateEntryToOriginModel(entry, name)
        end
    end
    saved._originModel = true
    if _G.TenUIDB then
        _G.TenUIDB.debug = _G.TenUIDB.debug or {}
        _G.TenUIDB.debug._origin_model_migrated = ("migrated at %s"):format(date("%H:%M:%S"))
    end
    if ns.Debug and ns.Debug.Log then
        ns.Debug:Log("[Anchor] MIGRATED saved entries to deterministic origin model")
    end
end

local function migratePointCanonicalization(saved)
    if type(saved) ~= "table" then return end
    if saved._pointCanon then return end
    for name, runtime in pairs(registry) do
        local entry = saved[name]
        if type(entry) == "table"
           and type(entry.point) == "string" and VALID_POINTS[entry.point] then
            local canon = (runtime.def and runtime.def.default and runtime.def.default.point) or "CENTER"
            if not VALID_POINTS[canon] then canon = "CENTER" end
            if entry.point ~= canon then
                local w = entry.width  or 200
                local h = entry.height or 32
                local sx, sy = originToSetPoint(entry.point, entry.x or 0, entry.y or 0, w, h, name)
                local cx = sx + (pointHFrac(canon) - pointHFrac(entry.point)) * w
                local cy = sy - (pointVFrac(canon) - pointVFrac(entry.point)) * h
                local ox, oy = setPointToOrigin(canon, cx, cy, w, h, name)
                entry.point = canon
                entry.x = math_floor(ox + 0.5)
                entry.y = math_floor(oy + 0.5)
                saved[name] = entry
                if ns.Debug and ns.Debug.Log then
                    ns.Debug:Log("[Anchor] POINT-CANON %s -> point=%s x=%d y=%d",
                        name, canon, entry.x, entry.y)
                end
            end
        end
    end
    saved._pointCanon = true
    if _G.TenUIDB then
        _G.TenUIDB.debug = _G.TenUIDB.debug or {}
        _G.TenUIDB.debug._point_canon_migrated = ("migrated at %s"):format(date("%H:%M:%S"))
    end
end

function Anchors:ApplyProfile()
    if not ns.savedVarsReady then return end
    local saved = getProfileAnchors()
    wipeDeprecatedBuffsDebuffs(saved)
    migrateTinyTrackedAnchors(saved)
    migrateOriginModel(saved)
    migratePointCanonicalization(saved)
    for name, runtime in pairs(registry) do
        local rawResolved, tier = resolveSavedEntry(name)
        if ns.Debug and ns.Debug.Log then
            local rawSaved = rawResolved
            if type(rawSaved) == "table" then
                ns.Debug:Log("[Anchor] LOAD name=%s tier=%s saved=%s,%s,%s w=%s h=%s",
                    name, tier,
                    tostring(rawSaved.point), tostring(rawSaved.x), tostring(rawSaved.y),
                    tostring(rawSaved.width), tostring(rawSaved.height))
            else
                ns.Debug:Log("[Anchor] LOAD name=%s tier=%s saved=<nil/non-table:%s>",
                    name, tier, tostring(rawSaved))
            end
        end
        local entry, corrupt = validatePos(rawResolved, runtime.def)
        _tracePush(name, "LOAD", {
            point = entry.point, x = entry.x, y = entry.y,
            w = entry.width, h = entry.height,
            corrupt = corrupt and true or false,
        })
        if corrupt or rawResolved == nil then
            migrateEntryToOriginModel(entry, name)
            if tier == "overlay" then
                writeOverlayEntry(name, entry)
            else
                saved[name] = entry
            end
            if ns.Debug and ns.Debug.Log then
                ns.Debug:Log("[Anchor] LOAD name=%s -> wrote DEFAULTS tier=%s (corrupt=%s)",
                    name, tier, tostring(corrupt))
            end
        end
        if clampToScreen(entry) then
            if tier == "overlay" then
                writeOverlayEntry(name, entry)
            else
                saved[name] = entry
            end
            _tracePush(name, "CLAMP", { x = entry.x, y = entry.y })
            if ns.Debug and ns.Debug.Log then
                ns.Debug:Log("[Anchor] LOAD name=%s clamped to screen", name)
            end
        end
        applyPosition(runtime.frame, entry)
        _tracePush(name, "APPLY", {
            point = entry.point, x = entry.x, y = entry.y,
            w = entry.width, h = entry.height,
        })
        if _G.TenUIDB then
            _G.TenUIDB.debug = _G.TenUIDB.debug or {}
            local lmap = _G.TenUIDB.debug._last_load
            if type(lmap) ~= "table" then
                lmap = {}
                _G.TenUIDB.debug._last_load = lmap
            end
            lmap[name] = ("loaded %s @ %d,%d (w=%d h=%d) at %s"):format(
                tostring(entry.point), entry.x or 0, entry.y or 0,
                entry.width or 0, entry.height or 0, date("%H:%M:%S"))
        end
        if ns.Debug and ns.Debug.Log then
            ns.Debug:Log("[Anchor] APPLY name=%s -> point=%s x=%d y=%d w=%d h=%d",
                name, tostring(entry.point), entry.x or 0, entry.y or 0,
                entry.width or 0, entry.height or 0)
        end
    end

    forceFixTrackedAnchor(saved, "TrackedIcon", 320, 40, 1, 1)
    forceFixTrackedAnchor(saved, "TrackedBars", 320, 24, 1, 1)

    if _G.TenUIDB then
        _G.TenUIDB.debug = _G.TenUIDB.debug or {}
        local diag = {}
        for n, rt in pairs(registry) do
            local e = resolveSavedEntry(n)
            local lw, lh
            if rt.frame then
                lw = rt.frame:GetWidth()
                lh = rt.frame:GetHeight()
            end
            diag[n] = {
                w      = lw,
                h      = lh,
                savedW = e and e.width  or nil,
                savedH = e and e.height or nil,
                from   = (e and type(e) == "table") and "saved" or "default",
                at     = date("%H:%M:%S"),
            }
        end
        _G.TenUIDB.debug._anchor_diagnostic_v1 = diag
    end

    if ns.EditMode and ns.EditMode.Refresh then
        ns.EditMode:Refresh()
    end
end

function Anchors:SetPositionDirect(name, x, y)
    if not ns.savedVarsReady then return false, "savedvars not ready" end
    if type(name) ~= "string" or name == "" then return false, "invalid name" end
    local runtime = registry[name]
    if not runtime then return false, "unknown anchor: " .. name end
    if not isFiniteNumber(x) or not isFiniteNumber(y) then
        return false, "invalid x/y"
    end
    local entry = validatePos(resolveSavedEntry(name), runtime.def)
    entry.x = math_floor(x + 0.5)
    entry.y = math_floor(y + 0.5)
    writeOverlayEntry(name, entry)
    if runtime.frame then
        applyPosition(runtime.frame, entry)
    end
    _tracePush(name, "SET", {
        point = entry.point, x = entry.x, y = entry.y,
        w = entry.width, h = entry.height,
    })
    if _G.TenUIDB then
        _G.TenUIDB.debug = _G.TenUIDB.debug or {}
        _G.TenUIDB.debug._last_slash_setpos = ("%s @ %d,%d at %s"):format(
            name, entry.x, entry.y, date("%H:%M:%S"))
    end
    if ns.Debug and ns.Debug.Log then
        ns.Debug:Log("[Anchor] SET name=%s point=%s x=%d y=%d w=%d h=%d",
            name, tostring(entry.point), entry.x, entry.y,
            entry.width or 0, entry.height or 0)
    end
    return true
end

function Anchors:Reset(name)
    if not ns.savedVarsReady then return false end
    if name then
        local runtime = registry[name]
        if not runtime then return false end
        local pos = defaultPos(runtime.def)
        migrateEntryToOriginModel(pos, name)
        writeOverlayEntry(name, pos)
        applyPosition(runtime.frame, pos)
        if ns.EditMode and ns.EditMode.RefreshOne then
            ns.EditMode:RefreshOne(runtime.frame)
        end
        return true
    end
    for n, runtime in pairs(registry) do
        local pos = defaultPos(runtime.def)
        migrateEntryToOriginModel(pos, n)
        writeOverlayEntry(n, pos)
        applyPosition(runtime.frame, pos)
    end
    if ns.EditMode and ns.EditMode.Refresh then
        ns.EditMode:Refresh()
    end
    return true
end

function Anchors:Reapply(name)
    if not ns.savedVarsReady then return false end
    local runtime = registry[name]
    if not runtime or not runtime.frame then return false end
    local raw, tier = resolveSavedEntry(name)
    local entry = validatePos(raw, runtime.def)
    if tier == "overlay" then
        writeOverlayEntry(name, entry)
    else
        getProfileAnchors()[name] = entry
    end
    applyPosition(runtime.frame, entry)
    return true
end

local function getSnapSettings()
    if not ns.savedVarsReady then return nil end
    local profile = ns:GetProfile()
    local modules = profile and profile.modules
    local layout = modules and modules.Layout
    local s = layout and layout.snapping
    if type(s) ~= "table" then return nil end
    if s.enabled ~= true then return nil end
    return s
end

function Anchors:IsSnapEnabled()
    return getSnapSettings() ~= nil
end

local function getSnapTable()
    if not ns.savedVarsReady then return nil end
    local profile = ns:GetProfile()
    local modules = profile and profile.modules
    local layout = modules and modules.Layout
    local s = layout and layout.snapping
    if type(s) ~= "table" then return nil end
    return s
end

local GRID_SIZE_MIN     = 16
local GRID_SIZE_MAX     = 128
local GRID_SIZE_DEFAULT = 32

local function getGridSize()
    local s = getSnapTable()
    local g = s and tonumber(s.gridSize) or GRID_SIZE_DEFAULT
    if g < GRID_SIZE_MIN then g = GRID_SIZE_MIN end
    if g > GRID_SIZE_MAX then g = GRID_SIZE_MAX end
    return g
end

local function gridSettingEnabled()
    local s = getSnapTable()
    return (s and s.showGrid == true) and true or false
end

local _gridEditModeActive = false

function Anchors:GetSnapPoint(x, y, w, h, excludeAnchorName)
    local s = getSnapSettings()
    if not s then return x, y, nil, nil end
    local dist = tonumber(s.distance) or 12
    if dist <= 0 then return x, y, nil, nil end
    w = (type(w) == "number" and w >= 0) and w or 0
    h = (type(h) == "number" and h >= 0) and h or 0
    local gap = tonumber(s.gap) or 2
    if gap < 0 then gap = 0 end

    local bestDX, bestX, bestGX = math_huge, nil, nil
    local bestDY, bestY, bestGY = math_huge, nil, nil

    local function tryX(targetCenterX, guideX)
        local d = math_abs(x - targetCenterX)
        if d <= dist and d < bestDX then
            bestDX, bestX, bestGX = d, targetCenterX, guideX
        end
    end
    local function tryY(targetCenterY, guideY)
        local d = math_abs(y - targetCenterY)
        if d <= dist and d < bestDY then
            bestDY, bestY, bestGY = d, targetCenterY, guideY
        end
    end

    if s.snapToCenter ~= false then
        tryX(0, 0)
        tryY(0, 0)
    end

    if s.snapToAnchors ~= false then
        local pcx, pcy = parent:GetCenter()
        if pcx and pcy then
            local halfW = w * 0.5
            local halfH = h * 0.5
            for name, runtime in pairs(registry) do
                if name ~= excludeAnchorName and runtime.frame then
                    local fcx, fcy = runtime.frame:GetCenter()
                    local tw = runtime.frame:GetWidth()
                    local th = runtime.frame:GetHeight()
                    if fcx and fcy and tw and th then
                        local ax = fcx - pcx
                        local ay = fcy - pcy
                        local tLeft   = ax - tw * 0.5
                        local tRight  = ax + tw * 0.5
                        local tTop    = ay + th * 0.5
                        local tBottom = ay - th * 0.5
                        tryY(tTop    + gap + halfH, tTop)
                        tryY(tBottom - gap - halfH, tBottom)
                        tryX(tRight  + gap + halfW, tRight)
                        tryX(tLeft   - gap - halfW, tLeft)
                        tryX(tLeft  + halfW, tLeft)
                        tryX(tRight - halfW, tRight)
                        tryX(ax, ax)
                        tryY(tTop    - halfH, tTop)
                        tryY(tBottom + halfH, tBottom)
                        tryY(ay, ay)
                    end
                end
            end
        end
    end

    local pw = parent:GetWidth()  or UIParent:GetWidth()  or 1920
    local ph = parent:GetHeight() or UIParent:GetHeight() or 1080
    local halfW = pw * 0.5
    local halfH = ph * 0.5
    tryX(-halfW + w * 0.5, -halfW)
    tryX( halfW - w * 0.5,  halfW)
    tryY( halfH - h * 0.5,  halfH)
    tryY(-halfH + h * 0.5, -halfH)

    if gridSettingEnabled() and _gridEditModeActive then
        local g = getGridSize()
        if g > 0 then
            local gx = math_floor(x / g + 0.5) * g
            local gy = math_floor(y / g + 0.5) * g
            tryX(gx, gx)
            tryY(gy, gy)
        end
    end

    return bestX or x, bestY or y, bestGX, bestGY
end

local guideFrame, guideV, guideH

local function ensureGuideFrame()
    if guideFrame then return guideFrame end
    guideFrame = CreateFrame("Frame", nil, UIParent)
    guideFrame:SetAllPoints(UIParent)
    guideFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    guideFrame:EnableMouse(false)

    guideV = guideFrame:CreateTexture(nil, "OVERLAY")
    guideV:SetColorTexture(0.2, 1, 0.6, 0.85)
    guideV:SetWidth(1)

    guideH = guideFrame:CreateTexture(nil, "OVERLAY")
    guideH:SetColorTexture(0.2, 1, 0.6, 0.85)
    guideH:SetHeight(1)

    guideFrame:Hide()
    return guideFrame
end

function Anchors:UpdateSnapGuides(guideX, guideY)
    local s = getSnapSettings()
    if not s or s.showLines == false or (guideX == nil and guideY == nil) then
        if guideFrame then guideFrame:Hide() end
        return
    end
    local f = ensureGuideFrame()
    if guideX ~= nil then
        guideV:ClearAllPoints()
        guideV:SetPoint("TOP", f, "TOP", guideX, 0)
        guideV:SetPoint("BOTTOM", f, "BOTTOM", guideX, 0)
        guideV:Show()
    else
        guideV:Hide()
    end
    if guideY ~= nil then
        guideH:ClearAllPoints()
        guideH:SetPoint("LEFT", f, "LEFT", 0, guideY)
        guideH:SetPoint("RIGHT", f, "RIGHT", 0, guideY)
        guideH:Show()
    else
        guideH:Hide()
    end
    f:Show()
end

function Anchors:HideSnapGuides()
    if guideFrame then guideFrame:Hide() end
end

local gridFrame = nil

local GRID_LINE_ALPHA   = 0.18
local GRID_CENTER_ALPHA = 0.40
local GRID_COLOR        = { 0.3, 0.8, 1.0 }

local function ensureGridFrame()
    if gridFrame then return gridFrame end
    gridFrame = CreateFrame("Frame", nil, UIParent)
    gridFrame:SetAllPoints(UIParent)
    gridFrame:SetFrameStrata("BACKGROUND")
    gridFrame:SetFrameLevel(0)
    gridFrame:EnableMouse(false)
    gridFrame._lines = {}
    gridFrame:Hide()
    return gridFrame
end

local function rebuildGridLines()
    local f = ensureGridFrame()
    local pool = f._lines
    for i = 1, #pool do pool[i]:Hide() end

    local w = UIParent:GetWidth()
    local h = UIParent:GetHeight()
    if not (w and h and w > 0 and h > 0) then return end
    local spacing = getGridSize()
    local r, g, b = GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3]
    local idx = 0

    local function acquire(subLevel)
        idx = idx + 1
        local tex = pool[idx]
        if not tex then
            tex = f:CreateTexture(nil, "BACKGROUND", nil, subLevel)
            pool[idx] = tex
        end
        return tex
    end

    local function addVertical(offset, alpha, subLevel)
        local tex = acquire(subLevel)
        tex:SetColorTexture(r, g, b, alpha)
        tex:ClearAllPoints()
        tex:SetWidth(1)
        tex:SetPoint("TOP", f, "TOP", offset, 0)
        tex:SetPoint("BOTTOM", f, "BOTTOM", offset, 0)
        tex:Show()
    end
    local function addHorizontal(offset, alpha, subLevel)
        local tex = acquire(subLevel)
        tex:SetColorTexture(r, g, b, alpha)
        tex:ClearAllPoints()
        tex:SetHeight(1)
        tex:SetPoint("LEFT", f, "LEFT", 0, offset)
        tex:SetPoint("RIGHT", f, "RIGHT", 0, offset)
        tex:Show()
    end

    addVertical(0, GRID_CENTER_ALPHA, -6)
    addHorizontal(0, GRID_CENTER_ALPHA, -6)

    local halfW = w * 0.5
    local halfH = h * 0.5
    local k = spacing
    while k < halfW do
        addVertical(k, GRID_LINE_ALPHA, -7)
        addVertical(-k, GRID_LINE_ALPHA, -7)
        k = k + spacing
    end
    k = spacing
    while k < halfH do
        addHorizontal(k, GRID_LINE_ALPHA, -7)
        addHorizontal(-k, GRID_LINE_ALPHA, -7)
        k = k + spacing
    end
end

function Anchors:UpdateGridOverlay()
    if gridSettingEnabled() and _gridEditModeActive then
        local spacing = getGridSize()
        local f = ensureGridFrame()
        if not f:IsShown() or f._builtSpacing ~= spacing then
            rebuildGridLines()
            f._builtSpacing = spacing
        end
        f:Show()
    elseif gridFrame then
        gridFrame:Hide()
    end
end

function Anchors:SetGridEditModeActive(active)
    _gridEditModeActive = active and true or false
    self:UpdateGridOverlay()
end

function Anchors:RefreshGridOverlay()
    self:UpdateGridOverlay()
end

ns:RegisterEvent("UI_SCALE_CHANGED", function()
    if gridFrame and gridFrame:IsShown() then rebuildGridLines() end
end)
ns:RegisterEvent("DISPLAY_SIZE_CHANGED", function()
    if gridFrame and gridFrame:IsShown() then rebuildGridLines() end
end)

function ns:RegisterAnchor(def)
    if type(def) ~= "table" then
        error("ns:RegisterAnchor: def must be a table", 2)
    end
    if type(def.name) ~= "string" or def.name == "" then
        error("ns:RegisterAnchor: def.name must be a non-empty string", 2)
    end
    local internal = {
        name    = def.name,
        label   = def.label or def.name,
        default = {
            point  = def.defaultPoint  or "CENTER",
            x      = def.defaultX      or 0,
            y      = def.defaultY      or 0,
            width  = def.width         or 200,
            height = def.height        or 32,
        },
    }
    return buildAnchor(internal)
end

function ns:GetAnchor(name)
    return registry[name]
end

function ns:UnregisterAnchor(name)
    return Anchors:Unregister(name)
end

function ns:SetAnchorLabel(name, label)
    return Anchors:SetLabel(name, label)
end

function ns:IterateAnchors()
    return pairs(registry)
end

function ns:AreAnchorsLocked()
    if InCombatLockdown() then return true end
    if self.db and self.db.locked then return true end
    return false
end

function ns:LockAnchors()
    if self.db then
        self.db.locked = true
    end
    self:Fire("LOCK_STATE_CHANGED", true)
end

function ns:UnlockAnchors()
    if InCombatLockdown() then
        return false, "combat"
    end
    if self.db then
        self.db.locked = false
    end
    self:Fire("LOCK_STATE_CHANGED", false)
    return true
end

function ns:ResetAnchor(name)
    return Anchors:Reset(name)
end

function ns:AutoFitAnchor(name, w, h)
    return Anchors:AutoFitSize(name, w, h)
end

function ns:ResetAllAnchors()
    return Anchors:Reset(nil)
end

for i = 1, #DEFAULT_ANCHORS do
    local a = DEFAULT_ANCHORS[i]
    Anchors:Register(a.name, {
        label = a.label,
        default = { point = a.point, x = a.x, y = a.y, width = a.width, height = a.height },
    })
end

ns:RegisterMessage("SAVEDVARS_READY", function()
    Anchors:ApplyProfile()
end)

ns:RegisterMessage("PROFILE_CHANGED", function()
    Anchors:ApplyProfile()
end)

local _pendingSpecReapply = false
ns:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(event, unit)
    if unit and unit ~= "player" then return end
    if not ns.savedVarsReady then return end
    if InCombatLockdown() then
        _pendingSpecReapply = true
        return
    end
    Anchors:ApplyProfile()
end)

ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if _pendingSpecReapply and ns.savedVarsReady then
        _pendingSpecReapply = false
        Anchors:ApplyProfile()
    end
end)

ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if not ns.savedVarsReady then return end
    local diverged = false
    for name, runtime in pairs(registry) do
        local f = runtime.frame
        local entry = resolveSavedEntry(name)
        local livePoint, _, liveRel, liveX, liveY = f:GetPoint(1)
        if ns.Debug and ns.Debug.Log then
            if type(entry) == "table" then
                ns.Debug:Log("[Anchor] PEW name=%s live=%s,%s,%.2f,%.2f saved=%s,%d,%d",
                    name,
                    tostring(livePoint), tostring(liveRel),
                    liveX or 0, liveY or 0,
                    tostring(entry.point), entry.x or 0, entry.y or 0)
            else
                ns.Debug:Log("[Anchor] PEW name=%s live=%s,%s,%.2f,%.2f saved=<missing>",
                    name,
                    tostring(livePoint), tostring(liveRel),
                    liveX or 0, liveY or 0)
            end
        end
        if type(entry) == "table"
           and type(entry.point) == "string"
           and isFiniteNumber(entry.x) and isFiniteNumber(entry.y) then
            local expX, expY = originToSetPoint(entry.point, entry.x, entry.y,
                entry.width or (f:GetWidth() or 0), entry.height or (f:GetHeight() or 0), name)
            local px = math_floor((liveX or 0) + 0.5)
            local py = math_floor((liveY or 0) + 0.5)
            if livePoint ~= entry.point or px ~= math_floor(expX + 0.5) or py ~= math_floor(expY + 0.5) then
                diverged = true
                if ns.Debug and ns.Debug.Log then
                    ns.Debug:Log("[Anchor] PEW name=%s DIVERGED -- re-applying", name)
                end
            end
        end
    end
    if diverged then
        Anchors:ApplyProfile()
    end
end)
