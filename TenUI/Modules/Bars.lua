local addonName, ns = ...

local CreateFrame       = CreateFrame
local C_CooldownViewer  = C_CooldownViewer
local C_Spell           = C_Spell
local C_Item            = C_Item
local C_Container       = C_Container
local C_DurationUtil    = C_DurationUtil
local C_SpellBook       = C_SpellBook
local C_Timer           = C_Timer
local IsPlayerSpell     = IsPlayerSpell
local IsSpellKnown      = IsSpellKnown
local GetInventoryItemID = GetInventoryItemID
local GetItemCooldown   = GetItemCooldown
local GetSpecialization = GetSpecialization
local GetTime           = GetTime
local UnitCastingInfo   = UnitCastingInfo
local UnitChannelInfo   = UnitChannelInfo
local UnitClass         = UnitClass
local UnitExists        = UnitExists
local UnitIsDead        = UnitIsDead
local pcall             = pcall
local type              = type
local pairs             = pairs
local ipairs            = ipairs
local tonumber          = tonumber
local tostring          = tostring
local tinsert           = table.insert
local tremove           = table.remove
local wipe              = wipe
local math_floor        = math.floor
local math_max          = math.max

local TINT_NORMAL_R, TINT_NORMAL_G, TINT_NORMAL_B = 1.0, 1.0, 1.0
local TINT_OOR_R,    TINT_OOR_G,    TINT_OOR_B    = 1.0, 0.3, 0.3

local POLL_INTERVAL_SEC = 0.2

local _cdSnapshot = {}
local _castReadyLogAt = {}

local _castStateAt, _castStateVal
local function playerHasCastOrChannel()
    local now = GetTime()
    if _castStateAt == now then return _castStateVal end
    _castStateAt = now
    local ok, has = pcall(function()
        if UnitCastingInfo and UnitCastingInfo("player") then return true end
        if UnitChannelInfo and UnitChannelInfo("player") then return true end
        return false
    end)
    _castStateVal = (ok and has == true) and true or false
    return _castStateVal
end

local Bars = {
    profileRef        = nil,
    rows              = {},
    _enabled          = false,
    _resizeCB         = nil,
    _currentScopeKey  = nil,
    _scopeEventFrame  = nil,
    _procEventFrame   = nil,
    _activeProcs      = {},
}
ns.Bars = Bars

local ROW_NAMES = {
    "EssentialCooldowns",
    "UtilityCooldowns",
    "DefensiveCooldowns",
    "Trinkets",
}

local ROW_ALIASES = {
    essential          = "EssentialCooldowns",
    essentials         = "EssentialCooldowns",
    essentialcooldowns = "EssentialCooldowns",
    utility            = "UtilityCooldowns",
    utilities          = "UtilityCooldowns",
    utilitycooldowns   = "UtilityCooldowns",
    defensive          = "DefensiveCooldowns",
    defensives         = "DefensiveCooldowns",
    defensivecooldowns = "DefensiveCooldowns",
    trinket            = "Trinkets",
    trinkets           = "Trinkets",
}

local DEFAULTS = {
    enabled              = true,
    iconSpacing          = 2,
    iconAnchor           = "CENTER",
    showCooldownText     = true,
    desaturateUnlearned  = true,
    iconSize             = 36,
    autoTrinkets         = true,
    showGCDSwipe         = true,
    showDurationSwipe    = true,
    scopes               = {},
    customBars           = {},
    customBarsNextID     = 1,
}

local KNOWN_SUMMON_DURATIONS = {
    [1122]   = 30,
    [205180] = 25,
    [111898] = 17,
    [264119] = 15,
    [455476] = 30,
    [42650]  = 30,
    [49206]  = 25,
    [275699] = 20,
    [455395] = 30,
    [383269] = 30,
}

local function dlog(fmt, ...)
    if ns.Debug and ns.Debug.Log then
        ns.Debug:Log("[Bars] " .. fmt, ...)
    end
end

local BARS_VERBOSE = false

local function verboseOn()
    if BARS_VERBOSE then return true end
    if ns.db and ns.db.debug and ns.db.debug.verbose
       and ns.db.debug.verbose.bars then
        return true
    end
    return false
end

local function vlog(fmt, ...)
    if not verboseOn() then return end
    if ns.Debug and ns.Debug.Log then
        ns.Debug:Log("[Bars] " .. fmt, ...)
    end
end

local function isSecret(v)
    return type(issecretvalue) == "function" and issecretvalue(v)
end

local GCD_SPELL_ID = 61304

local scratchCooldownParent = CreateFrame("Frame")
scratchCooldownParent:Hide()
local scratchCooldown = CreateFrame("Cooldown", nil, scratchCooldownParent, "CooldownFrameTemplate")

local function durationShowsCooldown(durObj)
    if not durObj then return false end
    local ok = pcall(scratchCooldown.SetCooldownFromDurationObject, scratchCooldown, durObj)
    if not ok then return false end
    local shown = scratchCooldown:IsShown()
    scratchCooldown:Clear()
    return shown and true or false
end

local function realCooldownShown(spellID)
    if not (spellID and C_Spell and C_Spell.GetSpellCooldownDuration) then return false end
    local ok, dur = pcall(C_Spell.GetSpellCooldownDuration, spellID, true)
    if not ok then return false end
    return durationShowsCooldown(dur)
end

local MIRROR_VIEWER_NAMES = { "EssentialCooldownViewer", "UtilityCooldownViewer" }

local _mirrorMap = {}
local _mirrorMapDirty = true
local _mirrorHooked = {}

local function mirrorForcePopEnabled()
    local a = ns.Auras
    if a and type(a.IsForceViewerPopulated) == "function" then
        local ok, v = pcall(a.IsForceViewerPopulated, a)
        if ok then return v == true end
    end
    return false
end

local function getMirrorViewer(name)
    local v = _G[name]
    if type(v) == "table" and v.GetObjectType then return v end
    return nil
end

local function mirrorViewerItems(viewer)
    if not viewer then return nil end
    if type(viewer.GetItemFrames) == "function" then
        local ok, frames = pcall(viewer.GetItemFrames, viewer)
        if ok and type(frames) == "table" then return frames end
    end
    local out = {}
    if type(viewer.itemFramePool) == "table"
       and type(viewer.itemFramePool.EnumerateActive) == "function" then
        pcall(function()
            for itemFrame in viewer.itemFramePool:EnumerateActive() do
                out[#out + 1] = itemFrame
            end
        end)
    end
    return out
end

local function mirrorSetItemMouse(viewer, enabled)
    local items = mirrorViewerItems(viewer) or {}
    for i = 1, #items do
        local it = items[i]
        if type(it) == "table" and type(it.EnableMouse) == "function" then
            pcall(it.EnableMouse, it, enabled and true or false)
        end
    end
end

local function hookMirrorViewer(name, viewer)
    if _mirrorHooked[name] then return end
    if type(viewer.RefreshLayout) ~= "function" then return end
    _mirrorHooked[name] = true
    pcall(hooksecurefunc, viewer, "RefreshLayout", function()
        _mirrorMapDirty = true
    end)
end

local function suppressMirrorViewers()
    if not mirrorForcePopEnabled() then return end
    for i = 1, #MIRROR_VIEWER_NAMES do
        local name = MIRROR_VIEWER_NAMES[i]
        local viewer = getMirrorViewer(name)
        if viewer then
            hookMirrorViewer(name, viewer)
            local shown
            if type(viewer.IsShown) == "function" then
                local okS, s = pcall(viewer.IsShown, viewer)
                if okS then shown = s end
            end
            if shown == false and not (InCombatLockdown and InCombatLockdown()) then
                pcall(viewer.SetShown, viewer, true)
                _mirrorMapDirty = true
                vlog("mirror force-show %s", name)
            end
            local alpha
            if type(viewer.GetAlpha) == "function" then
                local okA, a = pcall(viewer.GetAlpha, viewer)
                if okA and not isSecret(a) then alpha = a end
            end
            if alpha ~= 0 then
                pcall(viewer.SetAlpha, viewer, 0)
                pcall(viewer.EnableMouse, viewer, false)
                mirrorSetItemMouse(viewer, false)
            end
        end
    end
end

local function unsuppressMirrorViewers()
    for i = 1, #MIRROR_VIEWER_NAMES do
        local viewer = getMirrorViewer(MIRROR_VIEWER_NAMES[i])
        if viewer then
            pcall(viewer.SetAlpha, viewer, 1)
            pcall(viewer.EnableMouse, viewer, true)
            mirrorSetItemMouse(viewer, true)
            if type(viewer.UpdateShownState) == "function"
               and not (InCombatLockdown and InCombatLockdown()) then
                pcall(viewer.UpdateShownState, viewer)
            end
        end
    end
end

local function addMirrorKey(child, sid)
    if isSecret(sid) then return end
    if type(sid) ~= "number" or sid <= 0 then return end
    if _mirrorMap[sid] == nil then
        _mirrorMap[sid] = child
    end
end

local function rebuildMirrorMap()
    wipe(_mirrorMap)
    _mirrorMapDirty = false
    for i = 1, #MIRROR_VIEWER_NAMES do
        local viewer = getMirrorViewer(MIRROR_VIEWER_NAMES[i])
        if viewer then
            local items = mirrorViewerItems(viewer) or {}
            for j = 1, #items do
                local child = items[j]
                if type(child) == "table" then
                    local cdInfo = child.cooldownInfo
                    if type(cdInfo) == "table" then
                        addMirrorKey(child, cdInfo.spellID)
                        addMirrorKey(child, cdInfo.overrideSpellID)
                        addMirrorKey(child, cdInfo.overrideTooltipSpellID)
                        if type(cdInfo.linkedSpellIDs) == "table" then
                            for k = 1, #cdInfo.linkedSpellIDs do
                                addMirrorKey(child, cdInfo.linkedSpellIDs[k])
                            end
                        end
                    end
                    if type(child.GetSpellID) == "function" then
                        local ok, s = pcall(child.GetSpellID, child)
                        if ok then addMirrorKey(child, s) end
                    end
                    if type(child.GetBaseSpellID) == "function" then
                        local ok, b = pcall(child.GetBaseSpellID, child)
                        if ok then addMirrorKey(child, b) end
                    end
                end
            end
        end
    end
end

local function mirrorChildLive(child)
    local viewer
    if type(child.GetViewerFrame) == "function" then
        local ok, v = pcall(child.GetViewerFrame, child)
        if ok then viewer = v end
    end
    if type(viewer) ~= "table" or type(viewer.IsShown) ~= "function" then return false end
    local ok, shown = pcall(viewer.IsShown, viewer)
    return (ok and shown == true) and true or false
end

local function viewerMirrorOnRealCD(sid, activeSID, baseSID)
    if _mirrorMapDirty then rebuildMirrorMap() end
    local child = _mirrorMap[activeSID] or _mirrorMap[sid]
    if not child and baseSID then child = _mirrorMap[baseSID] end
    if type(child) ~= "table" then return nil end
    if not mirrorChildLive(child) then return nil end
    local v = child.isOnActualCooldown
    if v ~= nil and not isSecret(v) and type(v) == "boolean" then
        return v, "field"
    end
    local tex = child.Icon
    if type(child.GetIconTexture) == "function" then
        local okT, t = pcall(child.GetIconTexture, child)
        if okT and type(t) == "table" then tex = t end
    end
    if type(tex) == "table" and type(tex.IsDesaturated) == "function" then
        local okD, d = pcall(tex.IsDesaturated, tex)
        if okD and not isSecret(d) and type(d) == "boolean" then
            return d, "texture"
        end
    end
    return nil
end

function Bars:GetCurrentScopeKey()
    local _, class
    if UnitClass then
        local ok, n, c = pcall(UnitClass, "player")
        if ok then _, class = n, c end
    end
    if type(class) ~= "string" or class == "" then class = "UNKNOWN" end
    local specID
    if GetSpecialization then
        local ok, s = pcall(GetSpecialization)
        if ok then specID = s end
    end
    if type(specID) == "number" and specID > 0 then
        return class .. "_" .. tostring(specID)
    end
    return class .. "_NIL"
end

local function getBarsProfile()
    local p = Bars.profileRef
    if not p then return nil end
    p.scopes = p.scopes or {}
    return p
end

local function getVisualProfileForRow(rowName)
    local DEFAULT = 36
    local iconW, iconH, spacing

    local v
    if ns.savedVarsReady and ns.GetLayoutVisuals then
        v = ns:GetLayoutVisuals(rowName, false)
    end
    if v then
        if type(v.iconWidth)  == "number" and v.iconWidth  > 0 then iconW = math_floor(v.iconWidth)  end
        if type(v.iconHeight) == "number" and v.iconHeight > 0 then iconH = math_floor(v.iconHeight) end
        if type(v.spacing)    == "number" and v.spacing    >= 0 then spacing = math_floor(v.spacing) end
    end

    local bp = Bars.profileRef or {}
    if not iconW and type(bp.iconWidth)  == "number" and bp.iconWidth  > 0 then iconW = math_floor(bp.iconWidth)  end
    if not iconH and type(bp.iconHeight) == "number" and bp.iconHeight > 0 then iconH = math_floor(bp.iconHeight) end
    if (not iconW or not iconH) and type(bp.iconSize) == "number" and bp.iconSize > 0 then
        local s = math_floor(bp.iconSize)
        iconW = iconW or s
        iconH = iconH or s
    end
    iconW = iconW or DEFAULT
    iconH = iconH or DEFAULT

    if not spacing then
        if type(bp.iconSpacing) == "number" and bp.iconSpacing >= 0 then
            spacing = math_floor(bp.iconSpacing)
        else
            spacing = 2
        end
    end

    return iconW, iconH, spacing
end

local function rowVisualsBlock(rowName)
    if ns.savedVarsReady and ns.GetLayoutVisuals then
        return ns:GetLayoutVisuals(rowName, false)
    end
    return nil
end

local function styleFromTable(t, dFont, dSize, dFlags, dAnchor, dX, dY)
    return {
        font   = (t and t.font)   or dFont   or "default",
        size   = (t and type(t.size) == "number" and t.size > 0 and t.size) or dSize or 12,
        flags  = (t and t.flags)  or dFlags  or "OUTLINE",
        anchor = (t and t.anchor) or dAnchor or "BOTTOMRIGHT",
        x      = (t and type(t.x) == "number") and t.x or dX or 0,
        y      = (t and type(t.y) == "number") and t.y or dY or 0,
    }
end

local function rowOrientation(rowName)
    local v = rowVisualsBlock(rowName)
    if v and v.orientation == "V" then return "V" end
    return "H"
end

local function rowIconBorderStyle(rowName)
    local v = rowVisualsBlock(rowName)
    local enabled = not (v and v.showBorder == false)
    local color = (v and type(v.borderColor) == "table") and v.borderColor or nil
    return enabled, color
end

local function getVisualProfileTextForRow(rowName)
    local bp = Bars.profileRef or {}
    local v = rowVisualsBlock(rowName)
    local t = (v and v.textStack) or (v and v.text) or nil

    local legacyFont   = bp.stackTextFont
    local legacySize   = (type(bp.stackTextSize) == "number" and bp.stackTextSize > 0) and bp.stackTextSize or nil
    local legacyAnchor = bp.stackTextAnchor

    return styleFromTable(t,
        legacyFont, legacySize, "OUTLINE", legacyAnchor or "BOTTOMRIGHT", -1, 1)
end

local function getVisualProfileCooldownTextForRow(rowName)
    local v = rowVisualsBlock(rowName)
    local t = (v and v.textCooldown) or (v and v.text) or nil
    return styleFromTable(t, "default", 14, "OUTLINE", "CENTER", 0, 0)
end

local function getRowsForScope(scopeKey)
    local p = getBarsProfile()
    if not p then return nil end
    local s = p.scopes[scopeKey]
    if not s then
        s = { rows = {} }
        p.scopes[scopeKey] = s
    end
    s.rows = s.rows or {}
    for _, n in ipairs(ROW_NAMES) do
        s.rows[n] = s.rows[n] or { displayed = {}, candidates = {} }
        s.rows[n].displayed  = s.rows[n].displayed  or {}
        s.rows[n].candidates = s.rows[n].candidates or {}
    end
    return s.rows
end

function Bars:GetCurrentRows()
    local key = self._currentScopeKey or self:GetCurrentScopeKey()
    return getRowsForScope(key)
end

function Bars:GetScopes()
    local p = getBarsProfile()
    local out = {}
    if not (p and p.scopes) then return out end
    for k in pairs(p.scopes) do
        out[#out + 1] = k
    end
    table.sort(out)
    return out
end

local function migrateLegacyRows()
    local p = getBarsProfile()
    if not p then return nil end
    local legacy = rawget(p, "rows")
    if type(legacy) ~= "table" then return nil end
    local hasContent = false
    for _, n in ipairs(ROW_NAMES) do
        local r = legacy[n]
        if type(r) == "table" then
            if (type(r.displayed) == "table" and #r.displayed > 0)
               or (type(r.candidates) == "table" and #r.candidates > 0) then
                hasContent = true
                break
            end
        end
    end
    local key = Bars:GetCurrentScopeKey()
    local destRows = getRowsForScope(key)
    if hasContent and destRows then
        for _, n in ipairs(ROW_NAMES) do
            local src = legacy[n]
            if type(src) == "table" then
                local dst = destRows[n]
                local dstEmpty = (#dst.displayed == 0 and #dst.candidates == 0)
                if dstEmpty then
                    if type(src.displayed) == "table" then
                        for i = 1, #src.displayed do dst.displayed[i] = src.displayed[i] end
                    end
                    if type(src.candidates) == "table" then
                        for i = 1, #src.candidates do dst.candidates[i] = src.candidates[i] end
                    end
                end
            end
        end
        dlog("migrated legacy Bars rows -> scope=%s", key)
    end
    p.rows = nil
    return hasContent and key or nil
end

local function backfillSummonDurations()
    local p = getBarsProfile()
    if not (p and p.scopes) then return 0 end
    local n = 0
    for scopeKey, scope in pairs(p.scopes) do
        if type(scope) == "table" and type(scope.rows) == "table" then
            for rowName, row in pairs(scope.rows) do
                if type(row) == "table" and type(row.displayed) == "table" then
                    for i = 1, #row.displayed do
                        local e = row.displayed[i]
                        if type(e) == "table" and e.type == "spell" then
                            local id = tonumber(e.id)
                            local known = id and KNOWN_SUMMON_DURATIONS[id]
                            if known and not (tonumber(e.summonDuration) and tonumber(e.summonDuration) > 0) then
                                e.summonDuration = known
                                n = n + 1
                                dlog("backfilled summonDuration=%d for spell:%d (scope=%s row=%s)",
                                     known, id, tostring(scopeKey), tostring(rowName))
                            end
                        end
                    end
                end
            end
        end
    end
    if n > 0 then
        dlog("backfillSummonDurations: %d entries updated", n)
    end
    return n
end

local function getRowProfile(name)
    if not Bars.profileRef then return nil end
    local rows = Bars:GetCurrentRows()
    if not rows then return nil end
    rows[name] = rows[name] or { displayed = {}, candidates = {} }
    rows[name].displayed  = rows[name].displayed  or {}
    rows[name].candidates = rows[name].candidates or {}
    rows[name].rows2 = rows[name].rows2 or { enabled = false, displayed = {} }
    rows[name].rows2.displayed = rows[name].rows2.displayed or {}
    return rows[name]
end

local function entriesEqual(a, b)
    return a and b
        and a.type == b.type
        and tonumber(a.id) == tonumber(b.id)
end

local function findEntry(list, entry)
    if not (list and entry) then return nil end
    for i = 1, #list do
        if entriesEqual(list[i], entry) then
            return i
        end
    end
    return nil
end

local CDM = {}

local CATEGORY_TO_ROW = {
    [0] = "EssentialCooldowns",
    [1] = "UtilityCooldowns",
}

local function cdmAvailable()
    if not C_CooldownViewer then return false end
    if type(C_CooldownViewer.GetCooldownViewerCategorySet) ~= "function" then return false end
    if type(C_CooldownViewer.GetCooldownViewerCooldownInfo) ~= "function" then return false end
    return true
end

local function scanCategory(cat)
    local out = {}
    if not cdmAvailable() then return out end
    local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat, true)
    if not ok or type(ids) ~= "table" then
        dlog("CDM: GetCooldownViewerCategorySet(%s) failed or returned non-table", tostring(cat))
        return out
    end
    for i = 1, #ids do
        local cdID = ids[i]
        local info
        local ok2 = pcall(function()
            info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
        end)
        if ok2 and type(info) == "table" then
            local sid = tonumber(info.overrideSpellID) or tonumber(info.spellID)
            if sid and sid > 0 then
                tinsert(out, { type = "spell", id = sid })
            end
        end
    end
    return out
end

local function dedupForRow(rowName, entries)
    local rp = getRowProfile(rowName)
    if not rp then return entries end
    local seen = {}
    local displayed = rp.displayed or {}
    for i = 1, #displayed do
        local d = displayed[i]
        if d and d.type and d.id then
            seen[d.type .. ":" .. tostring(d.id)] = true
        end
    end
    local out = {}
    for i = 1, #entries do
        local e = entries[i]
        if e and e.type and e.id then
            local key = e.type .. ":" .. tostring(e.id)
            if not seen[key] then
                seen[key] = true
                tinsert(out, e)
            end
        end
    end
    return out
end

function CDM:ScanRow(rowName)
    if not cdmAvailable() then
        dlog("CDM:ScanRow(%s): CDM API unavailable", tostring(rowName))
        return false, "CDM API unavailable"
    end
    local cat
    for c, r in pairs(CATEGORY_TO_ROW) do
        if r == rowName then cat = c break end
    end
    if cat == nil then
        dlog("CDM:ScanRow(%s): no CDM category mapped (manual-add row)", tostring(rowName))
        return false, "no CDM category for this row"
    end
    local entries = scanCategory(cat)
    entries = dedupForRow(rowName, entries)
    local rp = getRowProfile(rowName)
    if not rp then return false, "profile not ready" end
    wipe(rp.candidates)
    for i = 1, #entries do rp.candidates[i] = entries[i] end
    dlog("CDM:ScanRow(%s): %d candidates", rowName, #rp.candidates)
    return true, #rp.candidates
end

function CDM:ScanAll()
    if not cdmAvailable() then
        dlog("CDM:ScanAll: CDM API unavailable")
        return false, "CDM API unavailable"
    end
    local total = 0
    for cat, rowName in pairs(CATEGORY_TO_ROW) do
        local entries = scanCategory(cat)
        entries = dedupForRow(rowName, entries)
        local rp = getRowProfile(rowName)
        if rp then
            wipe(rp.candidates)
            for i = 1, #entries do rp.candidates[i] = entries[i] end
            total = total + #rp.candidates
            dlog("CDM:ScanAll: row=%s cat=%d candidates=%d", rowName, cat, #rp.candidates)
        end
    end
    return true, total
end

Bars.Scanner = Bars.Scanner or {}
Bars.Scanner.CDM = CDM

local TRINKET_SLOTS = { 13, 14 }
local TRINKET_SLOT_SET = { [13] = true, [14] = true }

local function readSlotIfOnUse(slot)
    local itemID
    do
        local ok, v = pcall(GetInventoryItemID, "player", slot)
        if ok then itemID = v end
    end
    if type(itemID) ~= "number" or itemID <= 0 then return nil end
    if not (C_Item and C_Item.GetItemSpell) then return nil end
    local spellID
    do
        local ok, _name, sid = pcall(C_Item.GetItemSpell, itemID)
        if ok then spellID = sid end
    end
    if type(spellID) ~= "number" or spellID <= 0 then return nil end
    return itemID, spellID
end

local function readEquippedOnUseTrinkets()
    local out = {}
    for _, slot in ipairs(TRINKET_SLOTS) do
        local itemID, spellID = readSlotIfOnUse(slot)
        if itemID then
            tinsert(out, { slot = slot, itemID = itemID, spellID = spellID })
        end
    end
    return out
end

local TrinketScanner = {}

function TrinketScanner:Sync()
    local rp = getRowProfile("Trinkets")
    if not rp then return false, "profile not ready" end
    local p = getBarsProfile() or {}
    local trinkets = readEquippedOnUseTrinkets()

    wipe(rp.candidates)
    for i = 1, #trinkets do
        rp.candidates[i] = { type = "item", id = trinkets[i].itemID }
    end

    if p.autoTrinkets == false then
        dlog("Trinkets:Sync: autoTrinkets=false -- displayed list preserved (%d trinkets equipped)", #trinkets)
        return true, "manual"
    end

    local desired = {}
    for i = 1, #trinkets do
        desired[i] = { type = "item", id = trinkets[i].itemID }
    end

    local cur = rp.displayed
    local changed = (#cur ~= #desired)
    if not changed then
        for i = 1, #desired do
            if not entriesEqual(cur[i], desired[i]) then
                changed = true
                break
            end
        end
    end

    if not changed then
        dlog("Trinkets:Sync: noop (%d on-use trinkets equipped, displayed already matches)", #desired)
        return true, "noop"
    end

    wipe(rp.displayed)
    for i = 1, #desired do rp.displayed[i] = desired[i] end
    dlog("Trinkets:Sync: %d on-use trinkets equipped -> displayed updated", #desired)

    local row = Bars.rows and Bars.rows["Trinkets"]
    if row and row.Rebuild then
        row:Rebuild()
    end
    return true, "updated"
end

function TrinketScanner:Scan()
    local rp = getRowProfile("Trinkets")
    if not rp then return false, "profile not ready" end
    local trinkets = readEquippedOnUseTrinkets()
    wipe(rp.candidates)
    for i = 1, #trinkets do
        rp.candidates[i] = { type = "item", id = trinkets[i].itemID }
    end
    dlog("Trinkets:Scan: %d on-use candidates", #rp.candidates)
    return true, #rp.candidates
end

function TrinketScanner:AutoAdd()
    local rp = getRowProfile("Trinkets")
    if not rp then return false, "profile not ready" end
    self:Sync()
    dlog("Trinkets:AutoAdd (legacy): displayed=%d", #rp.displayed)
    return true, #rp.displayed
end

function TrinketScanner:GetStatus()
    local out = {}
    local trinkets = readEquippedOnUseTrinkets()
    for i = 1, #trinkets do
        local t = trinkets[i]
        local entry = {
            slot    = t.slot,
            itemID  = t.itemID,
            spellID = t.spellID,
        }
        if C_Item and C_Item.GetItemCooldown then
            local ok, s, d = pcall(C_Item.GetItemCooldown, t.itemID)
            if ok then
                entry.cdStart    = s
                entry.cdDuration = d
                if type(s) == "number" and type(d) == "number" and d > 0
                   and not isSecret(s) and not isSecret(d) then
                    local remaining = (s + d) - GetTime()
                    entry.ready     = remaining <= 0
                    entry.remaining = remaining > 0 and remaining or 0
                end
            end
        end
        out[i] = entry
    end
    return out
end

Bars.Scanner.Trinkets = TrinketScanner

local function abilityKeyCandidates(spellID)
    local out = { spellID }
    if C_SpellBook and C_SpellBook.FindBaseSpellByID then
        local ok, b = pcall(C_SpellBook.FindBaseSpellByID, spellID)
        if ok and type(b) == "number" and b ~= 0 and b ~= spellID then
            out[#out + 1] = b
        end
    end
    if C_Spell and C_Spell.GetOverrideSpell then
        local ok, o = pcall(C_Spell.GetOverrideSpell, spellID)
        if ok and type(o) == "number" and o ~= 0 and o ~= out[1] and o ~= out[2] then
            out[#out + 1] = o
        end
    end
    return out
end

local function procGlowEnabledForSpell(spellID)
    if not (ns.savedVarsReady and ns.GetProfile) then return true end
    local ok, p = pcall(ns.GetProfile, ns)
    if not ok or type(p) ~= "table" then return true end
    local abilities = p.abilities
    if type(abilities) ~= "table" then return true end
    local keys = abilityKeyCandidates(spellID)
    for i = 1, #keys do
        local ap = abilities[keys[i]]
        if type(ap) == "table" and type(ap.glow) == "table" then
            local proc = ap.glow.proc
            if type(proc) == "table" and proc.enabled == false then return false end
        end
    end
    return true
end

local function abilityGlowOpts(spellID, which)
    if not (ns.savedVarsReady and ns.GetProfile) then return nil end
    local ok, p = pcall(ns.GetProfile, ns)
    if not ok or type(p) ~= "table" or type(p.abilities) ~= "table" then return nil end
    local keys = abilityKeyCandidates(spellID)
    for i = 1, #keys do
        local ap = p.abilities[keys[i]]
        if type(ap) == "table" and type(ap.glow) == "table" then
            local g = ap.glow[which]
            if type(g) == "table" then return g end
        end
    end
    return nil
end

local function procGlowSetOpts(spellID)
    local opts = { spellID = spellID, reason = "proc:" .. tostring(spellID) }
    local g = abilityGlowOpts(spellID, "proc")
    if g then
        if type(g.style) == "string" then opts.style = g.style end
        local c = g.color
        if type(c) == "table" then
            opts.colorR = tonumber(c[1])
            opts.colorG = tonumber(c[2])
            opts.colorB = tonumber(c[3])
            opts.colorA = tonumber(c[4])
        end
    end
    return opts
end

local function applyReadyGlow(icon, spellID, ready)
    if not (icon and ns.Glow) then return end
    local g = abilityGlowOpts(spellID, "ready")
    local enabled = type(g) == "table" and g.enabled == true
    if enabled and ready and g.combatOnly ~= false
       and not (InCombatLockdown and InCombatLockdown()) then
        ready = false
    end
    if enabled and ready then
        local opts = icon._readyGlowOpts
        if not opts then
            opts = {}
            icon._readyGlowOpts = opts
        end
        opts.reason = "ready:" .. tostring(spellID)
        local gdStyle, gdColor
        if ns.Glow.GetGlobalDefault then
            gdStyle, gdColor = ns.Glow:GetGlobalDefault("ready")
        end
        if type(g.style) == "string" then
            opts.style = g.style
        else
            opts.style = gdStyle or "border"
        end
        if opts.style == "blizzard" then
            opts.style = "border"
        end
        local c = g.color
        if type(c) ~= "table" then c = gdColor end
        if type(c) == "table" then
            opts.colorR = tonumber(c[1]) or 0.3
            opts.colorG = tonumber(c[2]) or 1.0
            opts.colorB = tonumber(c[3]) or 0.3
            opts.colorA = tonumber(c[4]) or 1.0
        else
            opts.colorR, opts.colorG, opts.colorB, opts.colorA = 0.3, 1.0, 0.3, 1.0
        end
        ns.Glow:Set(icon, "ready", opts)
        icon._readyGlowOn = true
    elseif icon._readyGlowOn then
        ns.Glow:Clear(icon, "ready")
        icon._readyGlowOn = nil
    end
end

local function activeSpellID(baseID)
    if not baseID then return baseID end
    if C_Spell and C_Spell.GetOverrideSpell then
        local ok, o = pcall(C_Spell.GetOverrideSpell, baseID)
        if ok and type(o) == "number" and o ~= 0 then return o end
    end
    return baseID
end

local function resolveCooldownSource(sid, activeSID, baseSID)
    local cdSpellID = activeSID
    local cdInfo, activeCDInfo, fallbackCDInfo
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, activeSID)
        if ok then cdInfo = info end
        activeCDInfo = cdInfo
        local primaryReal = cdInfo and cdInfo.isActive and not cdInfo.isOnGCD
        if not primaryReal then
            local chosen
            local cand1 = (sid ~= activeSID) and sid or nil
            local cand2 = (baseSID and baseSID ~= activeSID and baseSID ~= sid)
                          and baseSID or nil
            if cand1 then
                local ok2, info2 = pcall(C_Spell.GetSpellCooldown, cand1)
                if ok2 and info2 then
                    fallbackCDInfo = info2
                    if info2.isActive and not info2.isOnGCD then
                        chosen, cdInfo = cand1, info2
                    end
                end
            end
            if not chosen and cand2 then
                local ok3, info3 = pcall(C_Spell.GetSpellCooldown, cand2)
                if ok3 and info3 then
                    fallbackCDInfo = info3
                    if info3.isActive and not info3.isOnGCD then
                        chosen, cdInfo = cand2, info3
                    end
                end
            end
            if chosen then
                cdSpellID = chosen
            end
        end
    end
    return cdSpellID, cdInfo, activeCDInfo, fallbackCDInfo
end

local function resolveBaseSpellID(sid)
    if C_SpellBook and C_SpellBook.FindBaseSpellByID then
        local okB, b = pcall(C_SpellBook.FindBaseSpellByID, sid)
        if okB and type(b) == "number" and b ~= 0 then return b end
    end
    return nil
end

local function snapshotFor(holdKey)
    local snap = _cdSnapshot[holdKey]
    if not snap then
        snap = {}
        _cdSnapshot[holdKey] = snap
    end
    return snap
end

local function spellFamilyMatches(baseID, eventID)
    if not (baseID and eventID) then return false end
    if baseID == eventID then return true end
    if C_Spell and C_Spell.GetOverrideSpell then
        local ok, o = pcall(C_Spell.GetOverrideSpell, baseID)
        if ok and o == eventID then return true end
    end
    if C_SpellBook and C_SpellBook.FindBaseSpellByID then
        local ok, b = pcall(C_SpellBook.FindBaseSpellByID, eventID)
        if ok and b == baseID then return true end
    end
    return false
end

local function setIconProcGlow(icon, baseID, wanted)
    if not icon then return end
    local suppressed = (wanted and icon._effOnRealCD) and true or false
    if suppressed then
        if not icon._procSuppressLogged then
            icon._procSuppressLogged = true
            dlog("proc glow SUPPRESSED (real CD wins) spell=%s", tostring(baseID))
        end
    else
        icon._procSuppressLogged = nil
    end
    local on = wanted and not suppressed and procGlowEnabledForSpell(baseID)
    if on then
        if not icon._procApplied and ns.Glow then
            icon._procApplied = true
            ns.Glow:Set(icon, "proc", procGlowSetOpts(baseID))
        end
    elseif icon._procApplied then
        icon._procApplied = nil
        if ns.Glow then
            ns.Glow:Clear(icon, "proc")
            applyReadyGlow(icon, baseID, icon._readyNowCached == true)
        end
    end
end

local function entryActiveProcID(baseID)
    if not (baseID and Bars._activeProcs) then return nil end
    for procID in pairs(Bars._activeProcs) do
        if spellFamilyMatches(baseID, procID) then return procID end
    end
    return nil
end

local function dispatchProcGlow(spellID, enabled)
    if type(spellID) ~= "number" then return end
    if not Bars.rows then return end
    for _, row in pairs(Bars.rows) do
        if row and row.icons then
            for i = 1, #row.icons do
                local icon = row.icons[i]
                local entry = icon and icon._entry
                if entry and entry.type == "spell"
                   and spellFamilyMatches(tonumber(entry.id), spellID) then
                    setIconProcGlow(icon, tonumber(entry.id), enabled)
                end
            end
        end
    end
end

function Bars:ReapplyProcGlowForSpell(spellID)
    spellID = tonumber(spellID)
    if not spellID then return end
    local active = false
    if self._activeProcs then
        if self._activeProcs[spellID] == true then
            active = true
        else
            for procID in pairs(self._activeProcs) do
                if spellFamilyMatches(spellID, procID) then
                    active = true
                    break
                end
            end
        end
    end
    dispatchProcGlow(spellID, active)
end

function Bars:ProcDiagnostic()
    if not (ns.Debug and ns.Debug.Log) then return 0 end
    local n = 0
    ns.Debug:Log("[Bars] === procdump (proc-override usability + glow) ===")
    if not self.rows then
        ns.Debug:Log("[Bars] procdump: no rows")
        return 0
    end
    for name, row in pairs(self.rows) do
        if row and row.icons then
            for i = 1, #row.icons do
                local icon = row.icons[i]
                local entry = icon and icon._entry
                if entry and entry.type == "spell" then
                    local base = tonumber(entry.id)
                    local active = activeSpellID(base)
                    local usable, noMana = "?", "?"
                    if C_Spell and C_Spell.IsSpellUsable then
                        local ok, u, m = pcall(C_Spell.IsSpellUsable, active)
                        if ok then
                            usable = (u == true) and "true" or "false"
                            noMana = (m == true) and "true" or "false"
                        end
                    end
                    local procSeen = "no"
                    if self._activeProcs then
                        for procID in pairs(self._activeProcs) do
                            if spellFamilyMatches(base, procID) then
                                procSeen = "yes(" .. tostring(procID) .. ")"
                                break
                            end
                        end
                    end
                    ns.Debug:Log(
                        "[Bars] %s[%d] base=%s active=%s override=%s usable=%s noMana=%s procGlow=%s",
                        tostring(name), i, tostring(base), tostring(active),
                        (active ~= base) and "YES" or "no",
                        usable, noMana, procSeen)
                    n = n + 1
                end
            end
        end
    end
    ns.Debug:Log("[Bars] procdump: %d spell icon(s) reported", n)
    return n
end

local function applyActiveProcsToIcon(icon)
    if not (icon and icon._entry and icon._entry.type == "spell") then return end
    local id = tonumber(icon._entry.id)
    if not id then return end
    if not Bars._activeProcs then return end
    for procID in pairs(Bars._activeProcs) do
        if spellFamilyMatches(id, procID) then
            setIconProcGlow(icon, id, true)
            break
        end
    end
end

local Row = {}
Row.__index = Row
Bars.Row = Row

local function spellIsKnown(spellID)
    if not spellID then return false end
    if IsPlayerSpell then
        local ok, k = pcall(IsPlayerSpell, spellID)
        if ok and k == true then return true end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, k = pcall(C_SpellBook.IsSpellKnown, spellID)
        if ok and k == true then return true end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
        local ok, k = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, spellID)
        if ok and k == true then return true end
    end
    if IsSpellKnown then
        local ok, k = pcall(IsSpellKnown, spellID)
        if ok and k == true then return true end
    end
    return false
end

local function spellInActiveSpellbook(spellID)
    if not spellID then return false end
    if not (C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell
            and Enum and Enum.SpellBookSpellBank) then
        return spellIsKnown(spellID)
    end
    local okSlot, slot, slotBank = pcall(
        C_SpellBook.FindSpellBookSlotForSpell, spellID, false, true, false, false)
    if not okSlot or not slot then return false end
    if slotBank ~= Enum.SpellBookSpellBank.Player
       and slotBank ~= Enum.SpellBookSpellBank.Pet then
        return false
    end
    if C_SpellBook.IsSpellBookItemOffSpec then
        local okOff, off = pcall(C_SpellBook.IsSpellBookItemOffSpec, slot, slotBank)
        if okOff and off == true then return false end
    end
    if C_SpellBook.GetSpellBookItemType and Enum.SpellBookItemType then
        local okT, itemType = pcall(C_SpellBook.GetSpellBookItemType, slot, slotBank)
        if okT and itemType == Enum.SpellBookItemType.FutureSpell then return false end
    end
    return true
end

local _resourceGatedCache = {}

local function spellHasPositiveResourceGateCost(spellID)
    if not (C_Spell and C_Spell.GetSpellPowerCost) then return false end
    local rune    = Enum and Enum.PowerType and Enum.PowerType.Runes
    local essence = Enum and Enum.PowerType and Enum.PowerType.Essence
    if rune == nil and essence == nil then return false end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if not ok or type(costs) ~= "table" then return false end
    for i = 1, #costs do
        local c = costs[i]
        if type(c) == "table" and (c.type == rune or c.type == essence) then
            local cost = c.cost
            local minCost = c.minCost
            if (not isSecret(cost) and (tonumber(cost) or 0) > 0)
               or (not isSecret(minCost) and (tonumber(minCost) or 0) > 0) then
                return true
            end
        end
    end
    return false
end

local function spellHasCooldownSurface(spellID)
    if GetSpellBaseCooldown then
        local ok, base = pcall(GetSpellBaseCooldown, spellID)
        if ok and type(base) == "number" and base > 0 then return true end
    end
    if C_Spell and C_Spell.GetSpellCharges then
        local ok, charges = pcall(C_Spell.GetSpellCharges, spellID)
        if ok and type(charges) == "table" then
            local mc = charges.maxCharges
            if not isSecret(mc) and (tonumber(mc) or 0) > 0 then return true end
        end
    end
    return false
end

local function isResourceGatedNoCooldownSpell(spellID)
    if type(spellID) ~= "number" or spellID <= 0 then return false end
    local cached = _resourceGatedCache[spellID]
    if cached ~= nil then return cached end
    local gated = spellHasPositiveResourceGateCost(spellID)
                  and not spellHasCooldownSurface(spellID)
    _resourceGatedCache[spellID] = gated
    return gated
end

local function getSpellTexture(spellID)
    if not (C_Spell and C_Spell.GetSpellTexture) then return nil end
    local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
    if ok then return tex end
    return nil
end

local function getItemTexture(itemID)
    if C_Item and C_Item.GetItemIconByID then
        local ok, tex = pcall(C_Item.GetItemIconByID, itemID)
        if ok and tex then return tex end
    end
    return nil
end

local function getDurationFor(icon)
    if icon._dur then return icon._dur end
    if not (C_DurationUtil and C_DurationUtil.CreateDuration) then return nil end
    icon._dur = C_DurationUtil.CreateDuration()
    return icon._dur
end

function Row:New(name)
    local anchor = ns:GetAnchor(name)
    if not (anchor and anchor.frame) then
        dlog("Row:New(%s): anchor missing -- skipping", tostring(name))
        return nil
    end
    local self_ = setmetatable({}, Row)
    self_.name      = name
    self_.anchor    = anchor
    self_.icons      = {}
    self_._iconsRow1 = {}
    self_._iconsRow2 = {}
    self_._row2enabled = false
    self_.eventFrame = nil

    local c = CreateFrame("Frame", "TenUIBarsContainer_" .. name, anchor.frame)
    c:SetAllPoints(anchor.frame)
    self_.container = c

    return self_
end

function Row:SetRow2Enabled(enabled)
    local rp = getRowProfile(self.name)
    if not rp then return end
    rp.rows2 = rp.rows2 or { enabled = false, displayed = {} }
    rp.rows2.enabled = enabled and true or false
    self._row2enabled = rp.rows2.enabled
    self:Rebuild()
end

local function destroyIconList(list)
    for i = 1, #list do
        local icon = list[i]
        if icon then
            if ns.Glow and ns.Glow.ClearAll then
                pcall(ns.Glow.ClearAll, ns.Glow, icon)
            end
            if icon.ClearCooldown then
                pcall(icon.ClearCooldown, icon)
            end
            if icon.Destroy then
                pcall(icon.Destroy, icon)
            end
        end
        list[i] = nil
    end
end

function Row:DestroyIcons()
    destroyIconList(self._iconsRow1)
    destroyIconList(self._iconsRow2)
    for i = 1, #self.icons do self.icons[i] = nil end
end

local function countVisibleIcons(iconList)
    if type(iconList) ~= "table" then return 0 end
    local n = 0
    for i = 1, #iconList do
        local icon = iconList[i]
        if icon and not icon._hiddenUnknown then n = n + 1 end
    end
    return n
end

local function buildIconsForList(container, displayedList, showText, rowName)
    local out = {}
    local textStyle = rowName and getVisualProfileTextForRow(rowName) or nil
    local cdTextStyle = rowName and getVisualProfileCooldownTextForRow(rowName) or nil
    local drawSwipe = not (Bars.profileRef and Bars.profileRef.showDurationSwipe == false)
    local borderOn, borderColor = true, nil
    if rowName then borderOn, borderColor = rowIconBorderStyle(rowName) end
    for i = 1, #displayedList do
        local entry = displayedList[i]
        local tex
        if entry.type == "spell" then
            tex = getSpellTexture(entry.id)
        elseif entry.type == "item" then
            tex = getItemTexture(entry.id)
        end
        local icon = ns.Widgets.Icon:New(container, {
            texture        = tex,
            border         = borderOn,
            borderColor    = borderColor,
            cooldown       = true,
            countdown      = showText,
            cooldownSwipe  = drawSwipe,
            stackText      = true,
            zoomIcon       = true,
        })
        icon._entry = entry
        out[i] = icon
        local hideThis = entry.hideWhileUnknown == true
                     and entry.type == "spell"
                     and not spellInActiveSpellbook(entry.id)
        icon._hiddenUnknown = hideThis
        if icon.SetShown then
            pcall(icon.SetShown, icon, not hideThis)
        end
        applyActiveProcsToIcon(icon)
        if textStyle and icon.ApplyTextStyle then
            icon:ApplyTextStyle(textStyle)
        end
        if cdTextStyle and icon.ApplyCooldownTextStyle then
            icon:ApplyCooldownTextStyle(cdTextStyle)
        end
    end
    return out
end

local function hiddenUnknownSignature(displayedList)
    local sig = ""
    for i = 1, #displayedList do
        local entry = displayedList[i]
        if entry.hideWhileUnknown and entry.type == "spell" then
            local known = spellInActiveSpellbook(entry.id) and "1" or "0"
            sig = sig .. tostring(entry.id) .. ":" .. known .. ";"
        end
    end
    return sig
end

function Row:Rebuild()
    local rp = getRowProfile(self.name)
    if not rp then return end
    local displayed1 = rp.displayed or {}
    local rows2      = rp.rows2 or { enabled = false, displayed = {} }
    local displayed2 = (rows2.enabled and rows2.displayed) or {}
    self._row2enabled = rows2.enabled and true or false

    local parent = Bars.profileRef or {}
    self:DestroyIcons()

    if #displayed1 == 0 and #displayed2 == 0 then
        self._hiddenSig = ""
        if self.container then self.container:SetAlpha(0) end
        return
    end

    local showText = parent.showCooldownText ~= false
    self._iconsRow1 = buildIconsForList(self.container, displayed1, showText, self.name)
    self._iconsRow2 = buildIconsForList(self.container, displayed2, showText, self.name)
    self._hiddenSig = hiddenUnknownSignature(displayed1) .. "|" .. hiddenUnknownSignature(displayed2)

    local flat = self.icons
    local n = 0
    for i = 1, #self._iconsRow1 do
        n = n + 1
        flat[n] = self._iconsRow1[i]
    end
    for i = 1, #self._iconsRow2 do
        n = n + 1
        flat[n] = self._iconsRow2[i]
    end

    local visible = countVisibleIcons(self._iconsRow1) + countVisibleIcons(self._iconsRow2)
    if self.container then self.container:SetAlpha(visible > 0 and 1 or 0) end

    self:Layout()
    self:Refresh()
end

function Row:GetIconSize()
    local p = Bars.profileRef or {}
    local s = p.iconSize
    if type(s) == "number" and s > 0 then return math_floor(s) end
    return 36
end

local function layoutIconRow(anchor, iconList, iconW, iconH, spacing, mode, crossOffset, orient)
    local count = countVisibleIcons(iconList)
    if count == 0 then return end
    local vertical = orient == "V"
    local totalW = count * iconW + (count - 1) * spacing
    local totalH = count * iconH + (count - 1) * spacing
    local slot = 0
    for i = 1, #iconList do
        local icon = iconList[i]
        if icon and icon._hiddenUnknown then
            if icon.frame then icon.frame:ClearAllPoints() end
        elseif icon and icon.frame then
            local f = icon.frame
            f:ClearAllPoints()
            f:SetSize(iconW, iconH)
            if f.cooldown then
                f.cooldown:ClearAllPoints()
                f.cooldown:SetAllPoints(f)
            end
            if vertical then
                local step = slot * (iconH + spacing)
                if mode == "LEFT" then
                    f:SetPoint("TOPLEFT", anchor.frame, "TOPLEFT", crossOffset, -step)
                elseif mode == "RIGHT" then
                    f:SetPoint("BOTTOMLEFT", anchor.frame, "BOTTOMLEFT", crossOffset, step)
                else
                    local top = (totalH / 2) - step
                    f:SetPoint("TOPLEFT", anchor.frame, "LEFT", crossOffset, top)
                end
            else
                if mode == "LEFT" then
                    local x = slot * (iconW + spacing)
                    f:SetPoint("TOPLEFT", anchor.frame, "TOPLEFT", x, crossOffset)
                elseif mode == "RIGHT" then
                    local x = -(slot * (iconW + spacing))
                    f:SetPoint("TOPRIGHT", anchor.frame, "TOPRIGHT", x, crossOffset)
                else
                    local left = -(totalW / 2) + slot * (iconW + spacing)
                    f:SetPoint("TOPLEFT", anchor.frame, "TOP", left, crossOffset)
                end
            end
            slot = slot + 1
        end
    end
end

function Row:Layout()
    local anchor = self.anchor
    if not (anchor and anchor.frame) then return end
    local count1 = countVisibleIcons(self._iconsRow1 or {})
    local count2 = countVisibleIcons(self._iconsRow2 or {})
    if count1 == 0 and count2 == 0 then return end

    local parent = Bars.profileRef or {}
    local mode = parent.iconAnchor or "CENTER"
    if mode ~= "LEFT" and mode ~= "CENTER" and mode ~= "RIGHT" then mode = "CENTER" end

    local iconW, iconH, spacing = getVisualProfileForRow(self.name)
    if type(spacing) ~= "number" or spacing < 0 then spacing = 0 end

    local orient = rowOrientation(self.name)

    if count1 > 0 then
        layoutIconRow(anchor, self._iconsRow1, iconW, iconH, spacing, mode, 0, orient)
    end

    if count2 > 0 then
        local cross2
        if orient == "V" then
            cross2 = iconW + spacing
        else
            cross2 = -(iconH + spacing)
        end
        layoutIconRow(anchor, self._iconsRow2, iconW, iconH, spacing, mode, cross2, orient)
    end

    if ns.AutoFitAnchor then
        local fitW, fitH
        if orient == "V" then
            local function colSpan(n)
                if n <= 0 then return 0 end
                return n * iconH + (n - 1) * spacing
            end
            fitH = math_max(colSpan(count1), colSpan(count2))
            fitW = iconW
            if count2 > 0 then fitW = iconW + spacing + iconW end
        else
            local function rowSpan(n)
                if n <= 0 then return 0 end
                return n * iconW + (n - 1) * spacing
            end
            fitW = math_max(rowSpan(count1), rowSpan(count2))
            fitH = iconH
            if count2 > 0 then fitH = iconH + spacing + iconH end
        end
        if fitW > 0 and fitH > 0 then
            ns:AutoFitAnchor(self.name, fitW, fitH)
        end
    end
end

function Row:ApplyVisualOptions()
    local textStyle = getVisualProfileTextForRow(self.name)
    local cdTextStyle = getVisualProfileCooldownTextForRow(self.name)
    local borderOn, borderColor = rowIconBorderStyle(self.name)
    for i = 1, #self.icons do
        local icon = self.icons[i]
        if icon and icon.ApplyTextStyle then
            icon:ApplyTextStyle(textStyle)
        end
        if icon and icon.ApplyCooldownTextStyle then
            icon:ApplyCooldownTextStyle(cdTextStyle)
        end
        if icon and icon.SetBorder then
            pcall(icon.SetBorder, icon, borderOn, borderColor)
        end
    end
    self:Layout()
    self:Refresh()
end

function Row:Refresh()
    local parent = Bars.profileRef or {}
    local desat = parent.desaturateUnlearned ~= false
    for i = 1, #self.icons do
        local icon = self.icons[i]
        local entry = icon and icon._entry
        if icon and entry and not icon._hiddenUnknown then
            self:RefreshIcon(icon, entry, desat)
        end
    end
end

function Row:UpdateHiddenVisibility()
    local changed = false
    for i = 1, #self.icons do
        local icon = self.icons[i]
        local entry = icon and icon._entry
        if icon and entry then
            local hideThis = entry.hideWhileUnknown == true
                         and entry.type == "spell"
                         and not spellInActiveSpellbook(entry.id)
            if (icon._hiddenUnknown == true) ~= hideThis then
                icon._hiddenUnknown = hideThis
                if icon.SetShown then
                    pcall(icon.SetShown, icon, not hideThis)
                end
                changed = true
            end
        end
    end
    return changed
end

function Row:MaybeRebuildForHidden()
    local rp = getRowProfile(self.name)
    if not rp then return end
    local displayed1 = rp.displayed or {}
    local rows2      = rp.rows2 or { enabled = false, displayed = {} }
    local displayed2 = (rows2.enabled and rows2.displayed) or {}
    local sig = hiddenUnknownSignature(displayed1) .. "|" .. hiddenUnknownSignature(displayed2)
    if sig == self._hiddenSig then return end
    self._hiddenSig = sig
    if self:UpdateHiddenVisibility() then
        local visible = countVisibleIcons(self._iconsRow1) + countVisibleIcons(self._iconsRow2)
        if self.container then self.container:SetAlpha(visible > 0 and 1 or 0) end
        self:Layout()
        self:RequestRefresh()
    end
end

local SUMMON_BORDER_R, SUMMON_BORDER_G, SUMMON_BORDER_B, SUMMON_BORDER_A = 1, 0.7, 0, 1

function Row:RefreshIcon(icon, entry, desat)
    if not (icon and entry) then return end
    if entry.type == "spell" then
        local sid = entry.id
        if not sid then return end
        local activeSID = activeSpellID(sid)

        local summonDur = tonumber(entry.summonDuration) or 0
        if summonDur > 0 and icon._summonActiveUntil then
            local now = GetTime()
            if now < icon._summonActiveUntil then
                local startTime = icon._summonActiveUntil - summonDur
                if C_DurationUtil and C_DurationUtil.CreateDuration then
                    local d = icon._summonDurObj
                    if not d then
                        d = C_DurationUtil.CreateDuration()
                        icon._summonDurObj = d
                    end
                    if d.SetTimeFromStart then
                        local okSet = pcall(d.SetTimeFromStart, d, startTime, summonDur, 1)
                        if okSet then
                            if icon._summonAppliedUntil ~= icon._summonActiveUntil then
                                icon:SetCooldown(d)
                                icon._summonAppliedUntil = icon._summonActiveUntil
                            end
                            if ns.Glow then
                                ns.Glow:Set(icon, "activeAura", {
                                    style  = "border",
                                    colorR = SUMMON_BORDER_R,
                                    colorG = SUMMON_BORDER_G,
                                    colorB = SUMMON_BORDER_B,
                                    colorA = SUMMON_BORDER_A,
                                })
                            end
                            local tex = getSpellTexture(sid)
                            if tex then icon:SetTexture(tex) end
                            icon:SetDesaturated(false)
                            icon:SetVertexColor(TINT_NORMAL_R, TINT_NORMAL_G, TINT_NORMAL_B, 1)
                            icon._readyNowCached = false
                            applyReadyGlow(icon, sid, false)
                            return
                        end
                    end
                end
            else
                icon._summonActiveUntil   = nil
                icon._summonAppliedUntil  = nil
                if ns.Glow then
                    ns.Glow:Clear(icon, "activeAura")
                end
                icon:ClearCooldown()
            end
        end
        local tex = getSpellTexture(sid)
        if tex then icon:SetTexture(tex) end

        local known = spellIsKnown(sid)
        if not known and desat then
            icon:SetDesaturated(true)
            icon:SetVertexColor(TINT_NORMAL_R, TINT_NORMAL_G, TINT_NORMAL_B, 1)
            icon:ClearCooldown()
            icon:SetStackTextRaw("")
            icon._readyNowCached = false
            applyReadyGlow(icon, sid, false)
            return
        end

        local usable, _noMana = true, false
        if C_Spell and C_Spell.IsSpellUsable then
            local ok, u, n = pcall(C_Spell.IsSpellUsable, activeSID)
            if ok then
                if isSecret(u) then u = true end
                if isSecret(n) then n = false end
                usable, _noMana = u, n
            end
        end

        local inRange
        if C_Spell and C_Spell.IsSpellInRange and UnitExists and UnitExists("target") then
            local ok, r = pcall(C_Spell.IsSpellInRange, activeSID, "target")
            if ok then inRange = r end
        end
        if inRange == false then
            icon:SetVertexColor(TINT_OOR_R, TINT_OOR_G, TINT_OOR_B, 1)
        else
            icon:SetVertexColor(TINT_NORMAL_R, TINT_NORMAL_G, TINT_NORMAL_B, 1)
        end

        local chargesInfo
        if C_Spell and C_Spell.GetSpellCharges then
            local ok, info = pcall(C_Spell.GetSpellCharges, activeSID)
            if ok and type(info) == "table" then chargesInfo = info end
        end
        local isChargeSpell = chargesInfo
                           and type(chargesInfo.maxCharges) == "number"
                           and chargesInfo.maxCharges > 1

        local baseSID = resolveBaseSpellID(sid)
        local holdKey = baseSID or sid
        local snap = _cdSnapshot[holdKey]
        local cdSpellID = (snap and snap.cdSpellID) or activeSID

        local cdInfo
        if C_Spell and C_Spell.GetSpellCooldown then
            local ok, info = pcall(C_Spell.GetSpellCooldown, cdSpellID)
            if ok then cdInfo = info end
        end
        local cdActive = (cdInfo and cdInfo.isActive) and true or false

        local viewerReal, viewerSrc = viewerMirrorOnRealCD(sid, activeSID, baseSID)

        local onRealCooldown
        if viewerReal ~= nil then
            onRealCooldown = viewerReal
        else
            if snap then
                onRealCooldown = snap.onReal == true
            else
                onRealCooldown = realCooldownShown(cdSpellID)
            end
            if onRealCooldown and not playerHasCastOrChannel()
               and not cdActive and not realCooldownShown(cdSpellID) then
                onRealCooldown = false
                if snap then
                    snap.onReal = false
                    vlog("poll READY clear holdKey=%s cdSrc=%s",
                         tostring(holdKey), tostring(cdSpellID))
                end
            end
        end

        local resourceGated = (not isChargeSpell)
            and (isResourceGatedNoCooldownSpell(sid)
                 or (baseSID and isResourceGatedNoCooldownSpell(baseSID)))
        if resourceGated then
            if not icon._resourceGatedLogged then
                icon._resourceGatedLogged = true
                dlog("resource-gated (no real CD) spell=%s base=%s", tostring(sid), tostring(baseSID))
            end
            onRealCooldown = false
        end

        local showGCD = (Bars.profileRef and Bars.profileRef.showGCDSwipe) ~= false
        local realGCD = (cdInfo and cdInfo.isOnGCD) and true or false
        local onGCD = cdActive and not onRealCooldown
        if resourceGated and not realGCD then
            onGCD = false
        end

        if isChargeSpell then
            if chargesInfo.isActive then
                local dur
                if C_Spell and C_Spell.GetSpellChargeDuration then
                    local ok, d = pcall(C_Spell.GetSpellChargeDuration, activeSID)
                    if ok then dur = d end
                end
                if dur then
                    icon:SetCooldown(dur)
                    icon._lastArmPath = "bars:charge"
                else
                    icon:ClearCooldown()
                end
            else
                icon:ClearCooldown()
            end
        elseif onRealCooldown then
            if C_Spell and C_Spell.GetSpellCooldownDuration then
                local ok, dur = pcall(C_Spell.GetSpellCooldownDuration, cdSpellID, false)
                if ok and dur then
                    icon:SetCooldown(dur)
                    icon._lastArmPath = "bars:realCD"
                else
                    icon:ClearCooldown()
                end
            else
                icon:ClearCooldown()
            end
        elseif onGCD and showGCD then
            local dur
            if C_Spell and C_Spell.GetSpellCooldownDuration then
                local ok, d = pcall(C_Spell.GetSpellCooldownDuration, activeSID, false)
                if ok then dur = d end
                if not dur then
                    local ok2, d2 = pcall(C_Spell.GetSpellCooldownDuration, GCD_SPELL_ID, false)
                    if ok2 then dur = d2 end
                end
            end
            if dur then
                icon:SetCooldown(dur)
                icon._lastArmPath = "bars:gcd"
            else
                icon:ClearCooldown()
            end
        else
            icon:ClearCooldown()
        end

        if isChargeSpell then
            local current = chargesInfo.currentCharges
            local okCmp, isZero = pcall(function() return current == 0 end)
            if okCmp and isZero then
                icon:SetStackTextRaw("")
            else
                icon:SetStackTextRaw(current)
            end
        else
            icon:SetStackTextRaw("")
        end

        icon._effOnRealCD = onRealCooldown or nil
        local procID = entryActiveProcID(sid)
        setIconProcGlow(icon, sid, procID ~= nil)

        local hasEmphasis = (icon._summonActiveUntil and GetTime() < icon._summonActiveUntil)
                         or (icon._procApplied == true)
        local readyVisual = (not onRealCooldown) and (usable ~= false)
        local shouldDesat = (not hasEmphasis)
                         and (not onGCD)
                         and (not readyVisual)
        icon:SetDesaturated(shouldDesat and true or false)

        local readyNow = (known and readyVisual) and true or false
        icon._readyNowCached = readyNow

        if playerHasCastOrChannel() then
            local becameReady = readyNow and icon._wasReadyVisual == false
            local becameLit = (not shouldDesat) and icon._wasDesatVisual == true
            if becameReady or becameLit then
                local now = GetTime()
                local lastAt = _castReadyLogAt[sid]
                if not lastAt or (now - lastAt) > 3 then
                    _castReadyLogAt[sid] = now
                    local snapAge = (snap and snap.at) and (now - snap.at) or -1
                    dlog("CASTREADY(snapshot) sid=%s active=%s base=%s cdSrc=%s holdKey=%s snapReal=%s snapAge=%.2f cdActive=%s realShown=%s real=%s proc=%s emphasis=%s readyGlow=%s desatCleared=%s usable=%s viewerDesat=%s viewerSrc=%s",
                        tostring(sid), tostring(activeSID), tostring(baseSID),
                        tostring(cdSpellID), tostring(holdKey),
                        tostring(snap and snap.onReal), snapAge,
                        tostring(cdActive),
                        tostring(realCooldownShown(cdSpellID)),
                        tostring(onRealCooldown), tostring(procID),
                        tostring(hasEmphasis), tostring(becameReady),
                        tostring(becameLit), tostring(usable),
                        tostring(viewerReal), tostring(viewerSrc))
                end
            end
        end
        icon._wasReadyVisual = readyNow
        icon._wasDesatVisual = shouldDesat

        if icon._lastReadyLogged ~= readyNow then
            icon._lastReadyLogged = readyNow
            vlog("readyGlow %s spell=%s cdSrc=%s cdActive=%s real=%s viewer=%s snap=%s usable=%s casting=%s",
                readyNow and "ON" or "off", tostring(sid), tostring(cdSpellID),
                tostring(cdActive), tostring(onRealCooldown),
                tostring(viewerReal),
                tostring(snap and snap.onReal),
                tostring(usable),
                tostring(playerHasCastOrChannel()))
        end
        applyReadyGlow(icon, sid, readyNow)

    elseif entry.type == "item" then
        local iid = entry.id
        if not iid then return end
        local tex = getItemTexture(iid)
        if tex then icon:SetTexture(tex) end
        icon:SetDesaturated(false)
        icon:SetVertexColor(TINT_NORMAL_R, TINT_NORMAL_G, TINT_NORMAL_B, 1)

        local start, duration
        if C_Item and C_Item.GetItemCooldown then
            local ok, s, d = pcall(C_Item.GetItemCooldown, iid)
            if ok then start, duration = s, d end
        end
        if (not start or not duration) and C_Container and C_Container.GetItemCooldown then
            local ok, s, d = pcall(C_Container.GetItemCooldown, iid)
            if ok then start, duration = s, d end
        end
        if (not start or not duration) and GetItemCooldown then
            local ok, s, d = pcall(GetItemCooldown, iid)
            if ok then start, duration = s, d end
        end

        if type(start) == "number" and type(duration) == "number" and duration > 0
           and not isSecret(start) and not isSecret(duration) then
            local dur = getDurationFor(icon)
            if dur and dur.SetTimeFromStart then
                local okSet = pcall(dur.SetTimeFromStart, dur, start, duration, 1)
                if okSet then
                    icon:SetCooldown(dur)
                else
                    icon:ClearCooldown()
                end
            else
                icon:ClearCooldown()
            end
        else
            icon:ClearCooldown()
        end
    end
end

function Row:SnapshotCooldowns()
    if not self.icons then return end
    local now = GetTime()
    for i = 1, #self.icons do
        local icon = self.icons[i]
        local entry = icon and icon._entry
        if entry and entry.type == "spell" then
            local sid = tonumber(entry.id)
            if sid then
                local activeSID = activeSpellID(sid)
                local baseSID = resolveBaseSpellID(sid)
                local cdSpellID, cdInfo = resolveCooldownSource(sid, activeSID, baseSID)
                local snap = snapshotFor(baseSID or sid)
                local onReal = (cdInfo and cdInfo.isActive and not cdInfo.isOnGCD) and true or false
                if snap.onReal ~= onReal or snap.cdSpellID ~= cdSpellID then
                    vlog("snapshot holdKey=%s onReal=%s cdSrc=%s active=%s",
                         tostring(baseSID or sid), tostring(onReal),
                         tostring(cdSpellID), tostring(activeSID))
                end
                snap.onReal = onReal
                snap.cdSpellID = cdSpellID
                snap.at = now
            end
        end
    end
end

function Row:RequestRefresh()
    if self._refreshScheduled then return end
    self._refreshScheduled = true
    C_Timer.After(0, function()
        self._refreshScheduled = false
        self:Refresh()
    end)
end

local ROW_EVENTS_COMMON = {
    "SPELL_UPDATE_COOLDOWN",
    "SPELL_UPDATE_CHARGES",
    "BAG_UPDATE_COOLDOWN",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TARGET_CHANGED",
    "SPELL_UPDATE_USABLE",
    "SPELLS_CHANGED",
    "TRAIT_CONFIG_UPDATED",
    "PLAYER_REGEN_ENABLED",
}

local SNAPSHOT_EVENTS = {
    SPELL_UPDATE_COOLDOWN = true,
    SPELL_UPDATE_CHARGES  = true,
    BAG_UPDATE_COOLDOWN   = true,
}

function Row:Enable()
    if self._enabled then return end
    self._enabled = true

    if not self.eventFrame then
        local ef = CreateFrame("Frame", "TenUIBarsRowEventFrame_" .. self.name)
        self.eventFrame = ef
        local row = self
        ef:SetScript("OnEvent", function(_, event, ...)
            if SNAPSHOT_EVENTS[event] then
                row:SnapshotCooldowns()
                row:RequestRefresh()
                return
            end
            if event == "UNIT_SPELLCAST_SUCCEEDED" then
                local _unit, _castGUID, spellID = ...
                if type(spellID) == "number" then
                    vlog("UNIT_SPELLCAST_SUCCEEDED spellID=%s row=%s",
                         tostring(spellID), tostring(row.name))
                    if row.icons then
                        for i = 1, #row.icons do
                            local icon = row.icons[i]
                            local entry = icon and icon._entry
                            if entry then
                                vlog("  checking icon[%d] entry.type=%s entry.id=%s entry.summonDuration=%s",
                                     i,
                                     tostring(entry.type),
                                     tostring(entry.id),
                                     tostring(entry.summonDuration))
                            end
                            if entry and entry.type == "spell" and tonumber(entry.id) == spellID then
                                local sd = tonumber(entry.summonDuration) or 0
                                if sd > 0 then
                                    dlog("  -> setting summonActiveUntil for icon[%d] dur=%d", i, sd)
                                    icon._summonActiveUntil  = GetTime() + sd
                                    icon._summonAppliedUntil = nil
                                end
                            end
                        end
                    end
                end
                row:RequestRefresh()
                return
            end
            if event == "SPELLS_CHANGED"
               or event == "TRAIT_CONFIG_UPDATED" then
                row:MaybeRebuildForHidden()
                row:RequestRefresh()
                return
            end
            if event == "PLAYER_REGEN_ENABLED" then
                row:MaybeRebuildForHidden()
                row:RequestRefresh()
                return
            end
            if event == "PLAYER_SPECIALIZATION_CHANGED"
               or event == "PLAYER_ENTERING_WORLD" then
                wipe(_cdSnapshot)
                wipe(_resourceGatedCache)
                if row.name == "Trinkets" then
                    local scanner = Bars.Scanner and Bars.Scanner.Trinkets
                    if scanner and scanner.Sync then
                        scanner:Sync()
                    end
                end
                row:MaybeRebuildForHidden()
                row:RequestRefresh()
                return
            end
            if event == "PLAYER_EQUIPMENT_CHANGED" then
                local slotID = ...
                if row.name == "Trinkets" and TRINKET_SLOT_SET[slotID] then
                    local scanner = Bars.Scanner and Bars.Scanner.Trinkets
                    if scanner and scanner.Sync then
                        scanner:Sync()
                    end
                end
                row:RequestRefresh()
                return
            end
            row:RequestRefresh()
        end)
    end
    for _, ev in ipairs(ROW_EVENTS_COMMON) do
        self.eventFrame:RegisterEvent(ev)
    end
    if self.name == "Trinkets" then
        self.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    end
    if self.eventFrame.RegisterUnitEvent then
        self.eventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        self.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    end

    local row = self
    self._resizeCB = ns:RegisterMessage("ANCHOR_RESIZED", function(_, anchorName)
        if anchorName == row.name then
            row:Layout()
            row:Refresh()
        end
    end)

    self:Rebuild()
end

function Row:Disable()
    if not self._enabled then return end
    self._enabled = false
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
        self.eventFrame:SetScript("OnEvent", nil)
    end
    if self._resizeCB then
        ns:UnregisterMessage("ANCHOR_RESIZED", self._resizeCB)
        self._resizeCB = nil
    end
    self:DestroyIcons()
end

function Bars:ResolveRowName(input)
    if type(input) ~= "string" then return nil end
    local key = input:lower():gsub("%s+", "")
    local alias = ROW_ALIASES[key]
    if alias then return alias end
    local id = key:match("^custombar(%d+)$") or key:match("^custom(%d+)$")
    if id and self.GetCustomBar and self:GetCustomBar(tonumber(id)) then
        return self:CustomRowKey(tonumber(id))
    end
    return nil
end

function Bars:GetRowNames()
    return ROW_NAMES
end

function Bars:GetRow(name)
    return self.rows[name]
end

function Bars:ApplyGCDSwipe(enabled)
    local value = enabled ~= false
    if self.profileRef then
        self.profileRef.showGCDSwipe = value
    end
    local drawSwipe = not (self.profileRef and self.profileRef.showDurationSwipe == false)
    for _, row in pairs(self.rows) do
        for _, icon in ipairs(row.icons or {}) do
            if icon and icon.SetDrawSwipe then
                pcall(icon.SetDrawSwipe, icon, drawSwipe)
            end
        end
    end
    for _, row in pairs(self.rows) do
        if row.Refresh then
            row:Refresh()
        end
    end
end

function Bars:ApplyDurationSwipe(enabled)
    local value = enabled ~= false
    if self.profileRef then
        self.profileRef.showDurationSwipe = value
    end
    for _, row in pairs(self.rows) do
        for _, icon in ipairs(row.icons or {}) do
            if icon and icon.SetDrawSwipe then
                pcall(icon.SetDrawSwipe, icon, value)
            end
        end
    end
end

function Bars:AddEntry(rowName, entry)
    local rp = getRowProfile(rowName)
    if not rp then return false, "profile not ready" end
    if not (entry and entry.type and entry.id) then return false, "bad entry" end
    if findEntry(rp.displayed, entry) then
        return false, "already in row"
    end
    local clean = { type = entry.type, id = entry.id }
    local sd = tonumber(entry.summonDuration)
    if sd and sd > 0 then
        clean.summonDuration = sd
    end
    if clean.type == "spell" and not clean.summonDuration then
        local known = KNOWN_SUMMON_DURATIONS[tonumber(clean.id)]
        if known then clean.summonDuration = known end
    end
    tinsert(rp.displayed, clean)
    local row = self.rows[rowName]
    if row then
        row:Rebuild()
    end
    return true
end

function Bars:RebuildRow(rowName)
    local row = self.rows[rowName]
    if row and row.Rebuild then
        row:Rebuild()
        return true
    end
    return false
end

function Bars:RemoveEntry(rowName, entry)
    local rp = getRowProfile(rowName)
    if not rp then return false, "profile not ready" end
    local idx = findEntry(rp.displayed, entry)
    if not idx then return false, "not in row" end
    tremove(rp.displayed, idx)
    local row = self.rows[rowName]
    if row then
        row:Rebuild()
    end
    return true
end

function Bars:ClearDisplayed(rowName)
    local rp = getRowProfile(rowName)
    if not rp then return false, "profile not ready" end
    wipe(rp.displayed)
    local row = self.rows[rowName]
    if row then
        row:Rebuild()
    end
    return true
end

function Bars:GetRow2Profile(rowName)
    local rp = getRowProfile(rowName)
    if not rp then return nil end
    return rp.rows2
end

function Bars:MoveEntryToRow2(rowName, entry)
    local rp = getRowProfile(rowName)
    if not rp then return false, "profile not ready" end
    local rp2 = rp.rows2
    local idx = findEntry(rp.displayed, entry)
    if idx then tremove(rp.displayed, idx) end
    if not findEntry(rp2.displayed, entry) then
        local clean = { type = entry.type, id = entry.id }
        local sd = tonumber(entry.summonDuration)
        if sd and sd > 0 then clean.summonDuration = sd end
        if entry.hideWhileUnknown then clean.hideWhileUnknown = true end
        tinsert(rp2.displayed, clean)
    end
    local row = self.rows[rowName]
    if row then row:Rebuild() end
    return true
end

function Bars:MoveEntryToRow1(rowName, entry)
    local rp = getRowProfile(rowName)
    if not rp then return false, "profile not ready" end
    local rp2 = rp.rows2
    local idx2 = findEntry(rp2.displayed, entry)
    if idx2 then tremove(rp2.displayed, idx2) end
    if not findEntry(rp.displayed, entry) then
        local clean = { type = entry.type, id = entry.id }
        local sd = tonumber(entry.summonDuration)
        if sd and sd > 0 then clean.summonDuration = sd end
        if entry.hideWhileUnknown then clean.hideWhileUnknown = true end
        tinsert(rp.displayed, clean)
    end
    local row = self.rows[rowName]
    if row then row:Rebuild() end
    return true
end

function Bars:RemoveEntryFromRow2(rowName, entry)
    local rp = getRowProfile(rowName)
    if not rp then return false, "profile not ready" end
    local rp2 = rp.rows2
    local idx = findEntry(rp2.displayed, entry)
    if not idx then return false, "not in row2" end
    tremove(rp2.displayed, idx)
    local row = self.rows[rowName]
    if row then row:Rebuild() end
    return true
end

function Bars:ReorderRow2(rowName, fromIndex, toIndex)
    local rp = getRowProfile(rowName)
    if not rp then return false, "profile not ready" end
    local disp = rp.rows2.displayed
    if not (fromIndex >= 1 and toIndex >= 1
            and fromIndex <= #disp and toIndex <= #disp
            and fromIndex ~= toIndex) then
        return false, "invalid indices"
    end
    local entry = tremove(disp, fromIndex)
    tinsert(disp, toIndex, entry)
    local row = self.rows[rowName]
    if row then row:Rebuild() end
    return true
end

local CUSTOM_PREFIX = "CustomBar"

local function getCustomBarDefs()
    local p = getBarsProfile()
    if not p then return nil end
    if type(p.customBars) ~= "table" then p.customBars = {} end
    if type(p.customBarsNextID) ~= "number" or p.customBarsNextID < 1 then
        local maxID = 0
        for i = 1, #p.customBars do
            local d = p.customBars[i]
            local id = (type(d) == "table") and tonumber(d.id) or nil
            if id and id > maxID then maxID = id end
        end
        p.customBarsNextID = maxID + 1
    end
    return p.customBars
end

function Bars:IsCustomRowKey(key)
    return type(key) == "string" and key:sub(1, #CUSTOM_PREFIX) == CUSTOM_PREFIX
end

function Bars:CustomRowKey(id)
    return CUSTOM_PREFIX .. tostring(tonumber(id) or 0)
end

function Bars:GetCustomBars()
    local out = {}
    local defs = getCustomBarDefs()
    if not defs then return out end
    for i = 1, #defs do
        local d = defs[i]
        if type(d) == "table" and tonumber(d.id) then
            out[#out + 1] = d
        end
    end
    return out
end

function Bars:GetCustomBar(id)
    id = tonumber(id)
    local defs = getCustomBarDefs()
    if not (id and defs) then return nil end
    for i = 1, #defs do
        local d = defs[i]
        if type(d) == "table" and tonumber(d.id) == id then
            return d, i
        end
    end
    return nil
end

local function ensureCustomRow(def, index)
    local key = Bars:CustomRowKey(def.id)
    ns:RegisterAnchor({
        name         = key,
        label        = def.name or key,
        defaultPoint = "CENTER",
        defaultX     = 0,
        defaultY     = -220 - (((index or 1) - 1) % 8) * 46,
        width        = 320,
        height       = 36,
    })
    if ns.Anchors and ns.Anchors.SetLabel then
        ns.Anchors:SetLabel(key, def.name or key)
    end
    getRowProfile(key)
    local row = Bars.rows[key]
    if not row then
        row = Row:New(key)
        if row then
            Bars.rows[key] = row
        end
    end
    if row and Bars._enabled and not row._enabled then
        row:Enable()
    end
    return row
end

function Bars:SyncCustomRows()
    if not self.profileRef then return end
    local defs = self:GetCustomBars()
    local want = {}
    for i = 1, #defs do
        want[self:CustomRowKey(defs[i].id)] = true
        ensureCustomRow(defs[i], i)
    end
    for key, row in pairs(self.rows) do
        if self:IsCustomRowKey(key) and not want[key] then
            if row and row.Disable then pcall(row.Disable, row) end
            self.rows[key] = nil
            if ns.UnregisterAnchor then
                pcall(ns.UnregisterAnchor, ns, key)
            end
        end
    end
    if ns.EditMode and ns.EditMode.Refresh then
        pcall(ns.EditMode.Refresh, ns.EditMode)
    end
end

function Bars:CreateCustomBar(name)
    if InCombatLockdown and InCombatLockdown() then
        return nil, "cannot create bars in combat"
    end
    local p = getBarsProfile()
    local defs = getCustomBarDefs()
    if not (p and defs) then return nil, "profile not ready" end
    local id = p.customBarsNextID
    p.customBarsNextID = id + 1
    local def = {
        id   = id,
        name = (type(name) == "string" and name ~= "") and name or ("Custom " .. tostring(id)),
    }
    defs[#defs + 1] = def
    self:SyncCustomRows()
    dlog("CreateCustomBar: id=%d name=%s", id, def.name)
    ns:Fire("CUSTOM_BARS_CHANGED", "create", id)
    return def
end

function Bars:DeleteCustomBar(id)
    if InCombatLockdown and InCombatLockdown() then
        return false, "cannot delete bars in combat"
    end
    local def, idx = self:GetCustomBar(id)
    if not def then return false, "unknown custom bar" end
    local defs = getCustomBarDefs()
    tremove(defs, idx)
    local key = self:CustomRowKey(def.id)
    local p = getBarsProfile()
    if p and type(p.scopes) == "table" then
        for _, scope in pairs(p.scopes) do
            if type(scope) == "table" and type(scope.rows) == "table" then
                scope.rows[key] = nil
            end
        end
    end
    if ns.savedVarsReady and ns.GetProfile then
        local ok, prof = pcall(ns.GetProfile, ns)
        if ok and type(prof) == "table" then
            local visuals = prof.modules and prof.modules.Layout
                            and prof.modules.Layout.visuals
            if type(visuals) == "table" then visuals[key] = nil end
            if type(prof.anchors) == "table" then prof.anchors[key] = nil end
            if type(prof.specScopes) == "table" then
                for _, scope in pairs(prof.specScopes) do
                    if type(scope) == "table" then
                        if type(scope.anchors) == "table" then scope.anchors[key] = nil end
                        if type(scope.layoutVisuals) == "table" then scope.layoutVisuals[key] = nil end
                    end
                end
            end
        end
    end
    self:SyncCustomRows()
    dlog("DeleteCustomBar: id=%s key=%s", tostring(id), key)
    ns:Fire("CUSTOM_BARS_CHANGED", "delete", id)
    return true
end

function Bars:RenameCustomBar(id, newName)
    if type(newName) ~= "string" or newName == "" then
        return false, "empty name"
    end
    local def = self:GetCustomBar(id)
    if not def then return false, "unknown custom bar" end
    def.name = newName
    if ns.Anchors and ns.Anchors.SetLabel then
        ns.Anchors:SetLabel(self:CustomRowKey(def.id), newName)
    end
    dlog("RenameCustomBar: id=%s -> %s", tostring(id), newName)
    ns:Fire("CUSTOM_BARS_CHANGED", "rename", id)
    return true
end

function Bars:_TickAll()
    suppressMirrorViewers()
    for _, r in pairs(self.rows) do
        if r and r._enabled and r.RequestRefresh then
            r:RequestRefresh()
        end
    end
end

function Bars:_ResyncScope()
    if not self._enabled then return end
    local newKey = self:GetCurrentScopeKey()
    if newKey == self._currentScopeKey then return end
    local oldKey = self._currentScopeKey
    self._currentScopeKey = newKey
    getRowsForScope(newKey)
    dlog("scope changed: %s -> %s", tostring(oldKey), tostring(newKey))
    for _, r in pairs(self.rows) do
        if r and r.Rebuild then
            r:Rebuild()
        end
    end
end

function Bars:OnEnable(_, profile)
    if self._enabled then return end
    self.profileRef = profile
    self._enabled = true

    migrateLegacyRows()

    backfillSummonDurations()

    if not self.profileRef._migratedDefaultAlign then
        if self.profileRef.iconAnchor == "LEFT" then
            self.profileRef.iconAnchor = "CENTER"
            dlog("migrated iconAnchor: LEFT -> CENTER (one-time default-flip)")
        end
        self.profileRef._migratedDefaultAlign = true
    end

    self._currentScopeKey = self:GetCurrentScopeKey()

    for _, name in ipairs(ROW_NAMES) do
        getRowProfile(name)
    end

    for _, name in ipairs(ROW_NAMES) do
        local r = Row:New(name)
        if r then
            self.rows[name] = r
            r:Enable()
        end
    end

    self:SyncCustomRows()

    if self.rows["Trinkets"] and TrinketScanner and TrinketScanner.Sync then
        TrinketScanner:Sync()
        if C_Timer and C_Timer.After then
            C_Timer.After(1.0, function()
                if Bars._enabled and TrinketScanner and TrinketScanner.Sync then
                    TrinketScanner:Sync()
                end
            end)
        end
    end

    if not self._scopeEventFrame then
        self._scopeEventFrame = CreateFrame("Frame", "TenUIBarsScopeFrame")
    end
    do
        local ef = self._scopeEventFrame
        local mod = self
        ef:SetScript("OnEvent", function(_, event, ...)
            mod:_ResyncScope()
        end)
        ef:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        ef:RegisterEvent("PLAYER_ENTERING_WORLD")
    end

    if not self._procEventFrame then
        self._procEventFrame = CreateFrame("Frame", "TenUIBarsProcFrame")
    end
    do
        local ef = self._procEventFrame
        local mod = self
        ef:SetScript("OnEvent", function(_, event, ...)
            local spellID = ...
            if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
                if type(spellID) == "number" then
                    mod._activeProcs[spellID] = true
                    dlog("proc SHOW spellID=%s", tostring(spellID))
                    dispatchProcGlow(spellID, true)
                end
            elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
                if type(spellID) == "number" then
                    mod._activeProcs[spellID] = nil
                    dlog("proc HIDE spellID=%s", tostring(spellID))
                    dispatchProcGlow(spellID, false)
                end
            end
        end)
        ef:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        ef:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    end

    if not self._mirrorEventFrame then
        self._mirrorEventFrame = CreateFrame("Frame", "TenUIBarsViewerMirrorFrame")
    end
    do
        local ef = self._mirrorEventFrame
        ef:UnregisterAllEvents()
        ef:SetScript("OnEvent", function()
            _mirrorMapDirty = true
            suppressMirrorViewers()
        end)
        ef:RegisterEvent("PLAYER_ENTERING_WORLD")
        ef:RegisterEvent("PLAYER_REGEN_DISABLED")
        ef:RegisterEvent("PLAYER_REGEN_ENABLED")
        ef:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        ef:RegisterEvent("SPELLS_CHANGED")
        pcall(ef.RegisterEvent, ef, "COOLDOWN_VIEWER_DATA_LOADED")
    end
    suppressMirrorViewers()

    if not self._pollTicker and C_Timer and C_Timer.NewTicker then
        local mod = self
        self._pollTicker = C_Timer.NewTicker(POLL_INTERVAL_SEC, function()
            mod:_TickAll()
        end)
    end

    dlog("enabled scope=%s with %d rows", tostring(self._currentScopeKey), (function()
        local n = 0
        for _ in pairs(self.rows) do n = n + 1 end
        return n
    end)())
end

function Bars:OnDisable()
    if not self._enabled then return end
    self._enabled = false
    if self._pollTicker and self._pollTicker.Cancel then
        self._pollTicker:Cancel()
        self._pollTicker = nil
    end
    if self._scopeEventFrame then
        self._scopeEventFrame:UnregisterAllEvents()
        self._scopeEventFrame:SetScript("OnEvent", nil)
    end
    if self._procEventFrame then
        self._procEventFrame:UnregisterAllEvents()
        self._procEventFrame:SetScript("OnEvent", nil)
    end
    if self._mirrorEventFrame then
        self._mirrorEventFrame:UnregisterAllEvents()
        self._mirrorEventFrame:SetScript("OnEvent", nil)
    end
    unsuppressMirrorViewers()
    wipe(_mirrorMap)
    _mirrorMapDirty = true
    wipe(self._activeProcs)
    wipe(_cdSnapshot)
    wipe(_castReadyLogAt)
    for _, r in pairs(self.rows) do
        if r and r.Disable then r:Disable() end
    end
end

ns:RegisterModule("Bars", {
    defaults = DEFAULTS,
    OnEnable = function(mod, profile) Bars:OnEnable(mod, profile) end,
    OnDisable = function(mod) Bars:OnDisable() end,
})

ns:RegisterMessage("PROFILE_CHANGED", function()
    if not Bars._enabled then return end
    local ok, prof = pcall(ns.GetProfile, ns)
    if not ok or type(prof) ~= "table" then return end
    prof.modules = prof.modules or {}
    prof.modules.Bars = prof.modules.Bars or {}
    if ns._deepCopyMissing then
        ns._deepCopyMissing(prof.modules.Bars, DEFAULTS)
    end
    Bars.profileRef = prof.modules.Bars
    Bars._currentScopeKey = Bars:GetCurrentScopeKey()
    getRowsForScope(Bars._currentScopeKey)
    Bars:SyncCustomRows()
    for _, r in pairs(Bars.rows) do
        if r and r.Rebuild then pcall(r.Rebuild, r) end
    end
    dlog("PROFILE_CHANGED: profileRef re-pointed, %d custom bars synced",
         #Bars:GetCustomBars())
end)
