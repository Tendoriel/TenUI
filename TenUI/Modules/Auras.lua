local addonName, ns = ...

local CreateFrame        = CreateFrame
local C_CooldownViewer   = C_CooldownViewer
local C_Spell            = C_Spell
local C_DurationUtil     = C_DurationUtil
local C_Timer            = C_Timer
local C_UnitAuras        = C_UnitAuras
local GetSpecialization  = GetSpecialization
local GetTime            = GetTime
local InCombatLockdown   = InCombatLockdown
local UnitClass          = UnitClass
local pcall              = pcall
local type               = type
local pairs              = pairs
local ipairs             = ipairs
local tonumber           = tonumber
local tostring           = tostring
local wipe               = wipe
local math               = math

local ICON_VIEWER_NAME = "BuffIconCooldownViewer"
local BAR_VIEWER_NAME  = "BuffBarCooldownViewer"

local CATEGORY_TRACKED_BUFF = 2
local CATEGORY_TRACKED_BAR  = 3

local ICON_ANCHOR_NAME = "TrackedIcon"
local BAR_ANCHOR_NAME  = "TrackedBars"

local MIRROR_INTERVAL_SEC = 0.1

local DEFAULTS = {
    enabled = true,
    crossViewerPrefer = "bar",
    forceViewerPopulated = true,
    respectCDMHidden = false,
    lowTimeText = {
        enabled   = false,
        threshold = 5,
        normalR   = 1,
        normalG   = 1,
        normalB   = 1,
        normalA   = 0.9,
        lowR      = 1,
        lowG      = 0.15,
        lowB      = 0.10,
        lowA      = 1,
    },
    icons = {
        enabled       = true,
        spacing       = 2,
        align         = "CENTER",
        showStackText = true,
        showDurationSwipe = true,
        activeGlow = {
            enabled = false,
            colorR  = 1.0,
            colorG  = 0.85,
            colorB  = 0.3,
            colorA  = 0.85,
        },
    },
    bars = {
        enabled   = true,
        barHeight = 18,
        showName  = true,
        showTimer = true,
        showIcon  = true,
        showInactive = false,
        activeGlow = {
            enabled = false,
            colorR  = 1.0,
            colorG  = 0.85,
            colorB  = 0.3,
            colorA  = 0.85,
        },
        pandemic = {
            enabled         = false,
            threshold       = 0.30,
            graceSuppress   = 0.30,
            evalInterval    = 0.1,
            colorR          = 1.0,
            colorG          = 0.6,
            colorB          = 0.0,
            colorA          = 0.9,
            skip = {},
            only = {},
        },
    },
    scopes = {},
}

local Auras = {
    profileRef       = nil,
    _enabled         = false,
    _currentScopeKey = nil,
    _scopeEventFrame = nil,
    _mirrorFrame     = nil,
    _ticker          = nil,
    _resizeCB        = nil,
    IconDisplay      = nil,
    BarDisplay       = nil,
}
ns.Auras = Auras

local ensureAuraCacheFrame
local buildAuraCatalog
local cdmCategoryFor
local cdmCatalogAvailable
local liveCategorySet
local orderedConfiguredIDs
local cdmCategoryCount
local cdmActiveForInfo
local cdmLabelAndIcon
local rebuildPlayerAuraCache
local viewerActiveCooldownIDSet
local cdmHiddenByDefault
local infoAuraSpellIDs
local anyPlayerOrTargetAura
local buildActiveFromCatalog
local resolveLiveAuraForEntry
local _lowTimeStats

local AURAS_MODULE = "auras"

local function dlog(fmt, ...)
    if ns.Debug and ns.Debug.Verbose then
        ns.Debug:Verbose(AURAS_MODULE, "[Auras] " .. fmt, ...)
    end
end

local function dwarn(fmt, ...)
    if ns.Debug and ns.Debug.Warn then
        ns.Debug:Warn("[Auras] " .. fmt, ...)
    end
end

local function dinfo(fmt, ...)
    if ns.Debug and ns.Debug.Info then
        ns.Debug:Info("[Auras] " .. fmt, ...)
    end
end

local function dverbose(fmt, ...)
    if ns.Debug and ns.Debug.Verbose then
        ns.Debug:Verbose(AURAS_MODULE, "[Auras] " .. fmt, ...)
    end
end

local function dtrace(fmt, ...)
    if ns.Debug and ns.Debug.Trace then
        ns.Debug:Trace(AURAS_MODULE, "[Auras] " .. fmt, ...)
    end
end

function Auras._renderAlphaProbe(kind, slotFrame)
    if type(kind) ~= "string" then return "" end
    local anchorName = (kind == "TrackedBars") and BAR_ANCHOR_NAME or ICON_ANCHOR_NAME
    local disp = (kind == "TrackedBars") and Auras.BarDisplay or Auras.IconDisplay
    local container = disp and disp.container or nil
    local anchorFrame
    if ns.GetAnchor then
        local rt = ns:GetAnchor(anchorName)
        anchorFrame = rt and rt.frame or nil
    end
    local function ga(f) local ok, v = pcall(f.GetAlpha, f) return ok and v or nil end
    local function gea(f) local ok, v = pcall(f.GetEffectiveAlpha, f) return ok and v or nil end
    local function gsh(f) local ok, v = pcall(f.IsShown, f) return ok and (v and true or false) or nil end
    local selfA = (type(slotFrame) == "table") and ga(slotFrame) or nil
    local effA  = (type(slotFrame) == "table") and gea(slotFrame) or nil
    local cA    = (type(container) == "table") and ga(container) or nil
    local cSh   = (type(container) == "table") and gsh(container) or nil
    local aA    = (type(anchorFrame) == "table") and ga(anchorFrame) or nil
    local aSh   = (type(anchorFrame) == "table") and gsh(anchorFrame) or nil
    local visHidden = (ns.Anchors and ns.Anchors.IsAnchorVisHidden and ns.Anchors:IsAnchorVisHidden(anchorName)) and true or false
    local fillStr = "-"
    local barFrame = (kind == "TrackedBars" and disp and disp.bars and disp.bars[1] and disp.bars[1].bar) or nil
    if type(barFrame) == "table" and type(barFrame.GetValue) == "function" then
        local okV, v = pcall(barFrame.GetValue, barFrame)
        if okV then
            if isSecret(v) then fillStr = "<secret>"
            elseif type(v) == "number" then fillStr = ("%.3f"):format(v)
            else fillStr = tostring(v) end
        end
    end
    return ("selfAlpha=%s effAlpha=%s containerAlpha=%s containerShown=%s anchorAlpha=%s anchorShown=%s visHidden=%s fill=%s"):format(
        tostring(selfA), tostring(effA), tostring(cA), tostring(cSh),
        tostring(aA), tostring(aSh), tostring(visHidden), fillStr)
end

function Auras._renderTrace(kind, item, slotIdx, shownFlag, stage, slotFrame, decision)
    if not (ns.Debug and ns.Debug.IsVerbose and ns.Debug:IsVerbose(AURAS_MODULE)) then return end
    local cdID = "?"
    if type(item) == "table" then
        local id = item.cooldownID
        if type(id) == "number" then cdID = tostring(id) end
    end
    local probe = ""
    if (tonumber(slotIdx) == 1) and (stage == nil or stage == "reached-end") then
        local now = (GetTime and GetTime()) or 0
        Auras._renderProbeNext = Auras._renderProbeNext or {}
        local key = tostring(kind)
        if now >= (Auras._renderProbeNext[key] or 0) then
            Auras._renderProbeNext[key] = now + 1.0
            local okP, p = pcall(Auras._renderAlphaProbe, kind, slotFrame)
            if okP and type(p) == "string" and p ~= "" then probe = " " .. p end
        end
    end
    local decisionStr = ""
    if type(decision) == "string" and decision ~= "" then
        decisionStr = " " .. decision
    end
    dverbose("[RENDER %s] cdm:%s slot=%d shown=%s combat=%s%s%s stage=%s",
        tostring(kind), cdID, tonumber(slotIdx) or -1,
        shownFlag and "true" or "false",
        tostring(InCombatLockdown and InCombatLockdown() or false),
        decisionStr,
        probe,
        tostring(stage or "reached-end"))
end

local _warnOnceSeen = {}
local function dwarnOnce(key, fmt, ...)
    if _warnOnceSeen[key] then return end
    _warnOnceSeen[key] = true
    dwarn(fmt, ...)
end

local _lastPipelineLog = setmetatable({}, { __index = function() return 0 end })
local function dlogPipeline(tag, viewerShown, rawCount, activeCount, items)
    if not (ns.Debug and ns.Debug.IsTrace and ns.Debug:IsTrace(AURAS_MODULE)) then return end
    local now = GetTime and GetTime() or 0
    if now - _lastPipelineLog[tag] < 5 then return end
    _lastPipelineLog[tag] = now
    dtrace("%s viewerShown=%s raw=%d active=%d combat=%s",
        tostring(tag), tostring(viewerShown), rawCount, activeCount,
        tostring(InCombatLockdown and InCombatLockdown() or false))
    if type(items) ~= "table" then return end
    local limit = math.min(3, #items)
    for i = 1, limit do
        local it = items[i]
        if type(it) == "table" then
            local cdID  = it.cooldownID
            local aID   = it.auraInstanceID
            local nestedAID = type(it.Icon) == "table" and it.Icon.auraInstanceID or nil
            local tslot = it.preferredTotemUpdateSlot
            local wsa   = it.wasSetFromAura
            local cinfo = it.cooldownInfo ~= nil
            local shown = nil
            if type(it.IsShown) == "function" then
                local ok, s = pcall(it.IsShown, it)
                if ok then shown = s end
            end
            dtrace("  item[%d] cdID=%s aID=%s nestedAID=%s tslot=%s wasSetAura=%s cInfo=%s IsShown=%s",
                i, tostring(cdID), tostring(aID), tostring(nestedAID),
                tostring(tslot), tostring(wsa), tostring(cinfo), tostring(shown))
        end
    end
end

local _itemErrLogged = {}
local function dlogItemErrorOnce(item, where, err)
    local key
    if type(item) == "table" then
        key = tonumber(item.cooldownID)
            or tostring(item)
    else
        key = tostring(item)
    end
    Auras._lastItemError = {
        key    = tostring(key),
        where  = tostring(where),
        err    = tostring(err),
        at     = (GetTime and GetTime()) or 0,
        combat = (InCombatLockdown and InCombatLockdown()) and true or false,
    }
    if not (ns.Debug and ns.Debug.Warn) then return end
    if _itemErrLogged[key] then return end
    _itemErrLogged[key] = true
    dwarn("skipped item key=%s at %s err=%s",
        tostring(key), tostring(where), tostring(err))
end

local function isSecret(v)
    return type(issecretvalue) == "function" and issecretvalue(v)
end

ns._auraSafeText = function(v)
    if isSecret(v) then return v end
    if v == nil then return "" end
    return v
end

ns._auraPresentTruthy = function(v)
    if isSecret(v) then return true end
    if v == nil then return false end
    return v ~= false
end

local function _IsUsableSID(v)
    return type(v) == "number" and not isSecret(v) and v > 0 and v == math.floor(v)
end

Auras.PLACEHOLDER_ICON = [[Interface\Icons\INV_Misc_QuestionMark]]

Auras._useViewerChildEmit = false

Auras._useViewerStateAsPrimary = true

function Auras._validTexture(v)
    if isSecret(v) then return true end
    if type(v) == "string" then return v ~= "" end
    if type(v) == "number" then return v > 0 and v == math.floor(v) end
    return false
end

function Auras._catalogDisplayTexture(e)
    if type(e) ~= "table" then return nil end
    local cached = e.displayIcon
    if Auras._validTexture(cached) then return cached end
    cached = e.icon
    if Auras._validTexture(cached) then return cached end
    if C_Spell and C_Spell.GetSpellTexture then
        for _, sid in ipairs({ e.spellID, e.overrideTooltipSpellID, e.overrideSpellID, e.linkedSpellID }) do
            if type(sid) == "number" and not isSecret(sid) and sid > 0 then
                local ok, t = pcall(C_Spell.GetSpellTexture, sid)
                if ok and Auras._validTexture(t) then return t end
            end
        end
    end
    return nil
end

function Auras._catalogDisplayName(e)
    if type(e) ~= "table" then return nil end
    if type(e.displayName) == "string" and e.displayName ~= "" then return e.displayName end
    if type(e.label) == "string" and e.label ~= "" then return e.label end
    if C_Spell and C_Spell.GetSpellName then
        for _, sid in ipairs({ e.spellID, e.overrideTooltipSpellID, e.overrideSpellID, e.linkedSpellID }) do
            if type(sid) == "number" and not isSecret(sid) and sid > 0 then
                local ok, n = pcall(C_Spell.GetSpellName, sid)
                if ok and type(n) == "string" and n ~= "" then return n end
            end
        end
    end
    return nil
end

function Auras._forceShowOwnFrame(f, alpha)
    if type(f) ~= "table" then return end
    if type(f.Show) == "function" then pcall(f.Show, f) end
    if type(f.SetAlpha) == "function" then pcall(f.SetAlpha, f, alpha or 1) end
end

function Auras._repairOwnParentChain(f)
    if type(f) ~= "table" then return end
    local node = f
    local guard = 0
    while type(node) == "table" and guard < 12 do
        guard = guard + 1
        if type(node.GetName) == "function" then
            local okN, name = pcall(node.GetName, node)
            if okN and type(name) == "string" then
                if name == "UIParent" or name == "TenUIAnchorParent" then
                    break
                end
                if name:sub(1, 12) == "TenUIAnchor_" then
                    local anchorName = name:sub(13)
                    local hidden = ns.Anchors and ns.Anchors.IsAnchorVisHidden
                        and ns.Anchors:IsAnchorVisHidden(anchorName) or false
                    if not hidden and type(node.GetAlpha) == "function" then
                        local okA, av = pcall(node.GetAlpha, node)
                        if okA and type(av) == "number" and av <= 0 and type(node.SetAlpha) == "function" then
                            local restore = ns.Anchors and ns.Anchors.GetSavedAlpha
                                and ns.Anchors:GetSavedAlpha(anchorName) or 1
                            if type(restore) ~= "number" or restore <= 0 then restore = 1 end
                            pcall(node.SetAlpha, node, restore)
                        end
                    end
                    break
                end
            end
        end
        local a
        if type(node.GetAlpha) == "function" then
            local okA, v = pcall(node.GetAlpha, node)
            if okA then a = v end
        end
        if type(a) == "number" and a <= 0 and type(node.SetAlpha) == "function" then
            pcall(node.SetAlpha, node, 1)
        end
        if type(node.GetParent) ~= "function" then break end
        local okP, p = pcall(node.GetParent, node)
        if not okP then break end
        node = p
    end
end

local _lastAuraTrace = setmetatable({}, { __index = function() return 0 end })
local function dlogAura(unit, phase, auraInstanceID, spellIdSecret, matched)
    if not (ns.Debug and ns.Debug.IsTrace and ns.Debug:IsTrace(AURAS_MODULE)) then return end
    local now = GetTime and GetTime() or 0
    local k = tostring(unit) .. ":" .. tostring(phase)
    if now - _lastAuraTrace[k] < 0.25 then return end
    _lastAuraTrace[k] = now
    dtrace("[AURA UNIT_AURA] unit=%s phase=%s aInst=%s spellIdSecret=%s matched=%s combat=%s",
        tostring(unit), tostring(phase),
        (auraInstanceID == nil and "nil") or (isSecret(auraInstanceID) and "<secret>") or tostring(auraInstanceID),
        tostring(spellIdSecret), tostring(matched),
        tostring(InCombatLockdown and InCombatLockdown() or false))
end

local function getViewer(name)
    local f = _G[name]
    if type(f) == "table" and f.GetObjectType then
        return f
    end
    return nil
end

local function getItemFrames(viewer)
    if not viewer then return nil end
    local out = {}
    local seen = {}
    local function pushUnique(frame)
        if type(frame) ~= "table" then return end
        if seen[frame] then return end
        seen[frame] = true
        out[#out + 1] = frame
    end
    if type(viewer.GetItemFrames) == "function" then
        local ok, frames = pcall(viewer.GetItemFrames, viewer)
        if ok and type(frames) == "table" and #frames > 0 then
            for i = 1, #frames do pushUnique(frames[i]) end
            return out
        end
    end
    if type(viewer.itemFramePool) == "table"
       and type(viewer.itemFramePool.EnumerateActive) == "function" then
        local ok = pcall(function()
            for itemFrame in viewer.itemFramePool:EnumerateActive() do
                pushUnique(itemFrame)
            end
        end)
        if ok and #out > 0 then
            table.sort(out, function(a, b)
                local ai = (type(a) == "table" and tonumber(a.layoutIndex)) or 0
                local bi = (type(b) == "table" and tonumber(b.layoutIndex)) or 0
                return ai < bi
            end)
            return out
        end
        wipe(out)
        wipe(seen)
    end
    local ok, children = pcall(function() return { viewer:GetChildren() } end)
    if ok and type(children) == "table" then
        for i = 1, #children do
            local c = children[i]
            if type(c) == "table" and c.GetObjectType then
                pushUnique(c)
            end
        end
    end
    return out
end

local function itemHasCooldownID(item)
    if type(item) ~= "table" then return false end
    local id = item.cooldownID
    if type(id) == "number" and id > 0 then return true end
    if type(item.GetCooldownID) == "function" then
        local ok, gid = pcall(item.GetCooldownID, item)
        if ok and type(gid) == "number" and gid > 0 then return true end
    end
    return false
end

local function itemHasLiveAuraOrTotem(item)
    if type(item) ~= "table" then return false end
    return item.auraInstanceID ~= nil
end

local function readItemIconTexture(item)
    if type(item) ~= "table" then return nil end
    do
        local cached = item._iconTexture
        if isSecret(cached) then return cached end
        if cached ~= nil then return cached end
    end
    local iconField = item.Icon
    if type(iconField) == "table" then
        if type(iconField.GetTexture) == "function" then
            local ok, tex = pcall(iconField.GetTexture, iconField)
            if ok and ns._auraPresentTruthy(tex) then return tex end
        end
        local nested = iconField.Icon
        if type(nested) == "table" and type(nested.GetTexture) == "function" then
            local ok, tex = pcall(nested.GetTexture, nested)
            if ok and ns._auraPresentTruthy(tex) then return tex end
        end
    end
    if type(item.GetIconTexture) == "function" then
        local ok, region = pcall(item.GetIconTexture, item)
        if ok and type(region) == "table" and type(region.GetTexture) == "function" then
            local ok2, tex = pcall(region.GetTexture, region)
            if ok2 and ns._auraPresentTruthy(tex) then return tex end
        end
    end
    return nil
end

local function readItemStackText(item)
    if type(item) ~= "table" then return nil end
    do
        local cached = item._stackText
        if isSecret(cached) then return cached end
        if cached ~= nil then return cached end
    end
    local candidates = {}
    if type(item.Applications) == "table" then
        candidates[#candidates + 1] = item.Applications.Applications
        candidates[#candidates + 1] = item.Applications
    end
    if type(item.Icon) == "table" then
        candidates[#candidates + 1] = item.Icon.Applications
    end
    if type(item.GetApplicationsFontString) == "function" then
        local ok, fs = pcall(item.GetApplicationsFontString, item)
        if ok and type(fs) == "table" then candidates[#candidates + 1] = fs end
    end
    for i = 1, #candidates do
        local fs = candidates[i]
        if type(fs) == "table" and type(fs.GetText) == "function" then
            local ok, txt = pcall(fs.GetText, fs)
            if ok then return txt end
        end
    end
    return nil
end

local function readItemSpellID(item)
    if type(item) ~= "table" then return nil end
    do
        local cached = item._spellID
        if isSecret(cached) then return cached end
        if type(cached) == "number" and cached ~= 0 then
            return cached
        end
    end
    if type(item.GetSpellID) == "function" then
        local ok, sid = pcall(item.GetSpellID, item)
        if ok and type(sid) == "number" then
            if isSecret(sid) then return sid end
            if sid ~= 0 then return sid end
        end
    end
    if type(item.GetBaseSpellID) == "function" then
        local ok, sid = pcall(item.GetBaseSpellID, item)
        if ok and type(sid) == "number" then
            if isSecret(sid) then return sid end
            if sid ~= 0 then return sid end
        end
    end
    return nil
end

local function getDurationFor(slot)
    if slot._dur then return slot._dur end
    if not (C_DurationUtil and C_DurationUtil.CreateDuration) then return nil end
    slot._dur = C_DurationUtil.CreateDuration()
    return slot._dur
end

function Auras._totemChildHasLiveTotem(child)
    if type(child) ~= "table" then return false end
    local td = child.totemData
    if not isSecret(td) and td == nil then return false end
    local slot = child.preferredTotemUpdateSlot
    if not isSecret(slot) and slot == nil then return false end
    return true
end

function Auras._totemDurationFromChild(child)
    if not Auras._totemChildHasLiveTotem(child) then return nil end
    local durFn = (type(GetTotemDuration) == "function" and GetTotemDuration)
        or (C_TotemInfo and type(C_TotemInfo.GetTotemDuration) == "function"
            and C_TotemInfo.GetTotemDuration)
        or nil
    if not durFn then return nil end
    local ok, durObj = pcall(durFn, child.preferredTotemUpdateSlot)
    if not ok or durObj == nil then return nil end
    return durObj
end

function Auras._findTotemViewerChildForItem(item)
    if type(item) ~= "table" then return nil end
    if Auras._totemChildHasLiveTotem(item._viewerChild) then
        return item._viewerChild
    end
    local cooldownID = tonumber(item.cooldownID)
    if not cooldownID then return nil end
    for _, viewerName in ipairs({ ICON_VIEWER_NAME, BAR_VIEWER_NAME }) do
        local viewer = getViewer(viewerName)
        if viewer then
            local children = getItemFrames(viewer) or {}
            for i = 1, #children do
                local child = children[i]
                if type(child) == "table"
                   and tonumber(child.cooldownID) == cooldownID
                   and Auras._totemChildHasLiveTotem(child) then
                    return child
                end
            end
        end
    end
    return nil
end

function Auras._resolveTotemDuration(item)
    local child = Auras._findTotemViewerChildForItem(item)
    if not child then return nil end
    return Auras._totemDurationFromChild(child)
end

Auras.SUMMON_BAR_SPELLS = {
    [265187] = 15,
    [104316] = 12,
}

Auras.SUMMON_BAR_SPEC_GATE = {
    WARLOCK_2 = true,
}

Auras.SUMMON_MIRROR_VIEWER_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    ICON_VIEWER_NAME,
    BAR_VIEWER_NAME,
}

Auras._summonActiveUntil = {}
Auras._summonDurObjBySpell = {}
Auras._summonSpecGateOK = false

function Auras._summonSpellForEntry(e)
    if type(e) ~= "table" then return nil end
    local map = Auras.SUMMON_BAR_SPELLS
    local function ok(sid)
        return type(sid) == "number" and not isSecret(sid) and map[sid] ~= nil
    end
    if ok(e.spellID) then return e.spellID end
    if ok(e.overrideSpellID) then return e.overrideSpellID end
    if ok(e.overrideTooltipSpellID) then return e.overrideTooltipSpellID end
    if ok(e.linkedSpellID) then return e.linkedSpellID end
    if type(e.linkedSpellIDs) == "table" then
        for i = 1, #e.linkedSpellIDs do
            if ok(e.linkedSpellIDs[i]) then return e.linkedSpellIDs[i] end
        end
    end
    return nil
end

function Auras._summonDurationShowsCooldown(durObj)
    if not durObj then return false end
    local sc = Auras._summonScratchCooldown
    if not sc then
        local parent = CreateFrame("Frame", "TenUIAurasSummonScratchParent")
        parent:Hide()
        sc = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
        Auras._summonScratchCooldown = sc
    end
    local ok = pcall(sc.SetCooldownFromDurationObject, sc, durObj)
    if not ok then return false end
    local shown = sc:IsShown()
    pcall(sc.Clear, sc)
    return shown and true or false
end

function Auras._childMatchesSummonSpell(child, summonSpellID)
    if type(child) ~= "table" then return false end
    local cdInfo = child.cooldownInfo
    local function eq(sid)
        return type(sid) == "number" and not isSecret(sid) and sid == summonSpellID
    end
    if type(cdInfo) == "table" then
        if eq(cdInfo.spellID) then return true end
        if eq(cdInfo.overrideSpellID) then return true end
        if eq(cdInfo.overrideTooltipSpellID) then return true end
        if type(cdInfo.linkedSpellIDs) == "table" then
            for k = 1, #cdInfo.linkedSpellIDs do
                if eq(cdInfo.linkedSpellIDs[k]) then return true end
            end
        end
    end
    if type(child.GetSpellID) == "function" then
        local okS, s = pcall(child.GetSpellID, child)
        if okS and eq(s) then return true end
    end
    if type(child.GetBaseSpellID) == "function" then
        local okB, b = pcall(child.GetBaseSpellID, child)
        if okB and eq(b) then return true end
    end
    return false
end

function Auras._resolveSummonLiveTotem(summonSpellID)
    local durFn = (type(GetTotemDuration) == "function" and GetTotemDuration)
        or (C_TotemInfo and type(C_TotemInfo.GetTotemDuration) == "function"
            and C_TotemInfo.GetTotemDuration)
        or nil
    if not durFn then return nil end
    for _, viewerName in ipairs(Auras.SUMMON_MIRROR_VIEWER_NAMES) do
        local viewer = getViewer(viewerName)
        if viewer then
            local children = getItemFrames(viewer) or {}
            for i = 1, #children do
                local child = children[i]
                if Auras._childMatchesSummonSpell(child, summonSpellID)
                   and Auras._totemChildHasLiveTotem(child) then
                    local ok, durObj = pcall(durFn, child.preferredTotemUpdateSlot)
                    if ok and durObj ~= nil and Auras._summonDurationShowsCooldown(durObj) then
                        return durObj
                    end
                end
            end
        end
    end
    return nil
end

function Auras._resolveSummonFixedDuration(summonSpellID)
    local until_ = Auras._summonActiveUntil[summonSpellID]
    if type(until_) ~= "number" then return nil end
    local now = GetTime and GetTime() or 0
    if now >= until_ then
        Auras._summonActiveUntil[summonSpellID] = nil
        return nil
    end
    if not (C_DurationUtil and C_DurationUtil.CreateDuration) then return nil end
    local dur = Auras.SUMMON_BAR_SPELLS[summonSpellID]
    if type(dur) ~= "number" or dur <= 0 then return nil end
    local durObj = Auras._summonDurObjBySpell[summonSpellID]
    if not durObj then
        local okC, d = pcall(C_DurationUtil.CreateDuration)
        if not okC or d == nil then return nil end
        durObj = d
        Auras._summonDurObjBySpell[summonSpellID] = durObj
    end
    if type(durObj.SetTimeFromStart) ~= "function" then return nil end
    local startTime = until_ - dur
    local okSet = pcall(durObj.SetTimeFromStart, durObj, startTime, dur, 1)
    if not okSet then return nil end
    return durObj
end

function Auras._resolveSummonBarPresence(e, allowLive)
    local summonSpellID = Auras._summonSpellForEntry(e)
    if not summonSpellID then return false, nil, nil end

    if allowLive then
        local liveDur = Auras._resolveSummonLiveTotem(summonSpellID)
        if liveDur ~= nil then return true, liveDur, "summonBar:totem" end
    end

    local fixedDur = Auras._resolveSummonFixedDuration(summonSpellID)
    if fixedDur ~= nil then return true, fixedDur, "summonBar:fixed" end

    return false, nil, nil
end

function Auras._refreshSummonSpecGate()
    local key = Auras.GetCurrentScopeKey and Auras:GetCurrentScopeKey() or nil
    Auras._summonSpecGateOK = (type(key) == "string" and Auras.SUMMON_BAR_SPEC_GATE[key] == true)
    if not Auras._summonSpecGateOK then
        wipe(Auras._summonActiveUntil)
    end
end

function Auras._canonicalSummonKey(spellID)
    if type(spellID) ~= "number" or isSecret(spellID) then return nil end
    local map = Auras.SUMMON_BAR_SPELLS
    if map[spellID] ~= nil then return spellID end
    if C_Spell and type(C_Spell.GetOverrideSpell) == "function" then
        for baseID in pairs(map) do
            local ok, overrideID = pcall(C_Spell.GetOverrideSpell, baseID)
            if ok and type(overrideID) == "number" and not isSecret(overrideID)
               and overrideID == spellID then
                return baseID
            end
        end
    end
    return nil
end

function Auras._handleSummonCast(spellID)
    if type(spellID) ~= "number" or isSecret(spellID) then return end
    if not Auras._summonSpecGateOK then return end
    local canonical = Auras._canonicalSummonKey(spellID)
    if not canonical then return end
    local dur = Auras.SUMMON_BAR_SPELLS[canonical]
    if type(dur) ~= "number" or dur <= 0 then return end
    local until_ = (GetTime and GetTime() or 0) + dur
    Auras._summonActiveUntil[canonical] = until_
    if spellID ~= canonical then
        Auras._summonActiveUntil[spellID] = until_
    end
    if Auras.RequestRefresh then pcall(Auras.RequestRefresh, Auras) end
end

local function applySwipe(iconWidget, item, spellID)
    if not iconWidget then return end

    iconWidget._liveDurObj = nil
    iconWidget._liveDurObjType = nil
    iconWidget._liveDurObjSecret = nil

    if type(item) == "table" then
        local totemDur = Auras._resolveTotemDuration(item)
        if ns._auraPresentTruthy(totemDur) then
            iconWidget._liveDurObj = totemDur
            iconWidget._liveDurObjType = type(totemDur)
            iconWidget._liveDurObjSecret = isSecret(totemDur)
            pcall(iconWidget.SetCooldown, iconWidget, totemDur)
            iconWidget._lastArmPath = "auras:totem"
            return
        end
    end

    if type(item) == "table" and item.auraInstanceID ~= nil
       and C_UnitAuras and C_UnitAuras.GetAuraDuration then
        local unit = type(item.auraDataUnit) == "string" and item.auraDataUnit or "player"
        local ok, dur = pcall(C_UnitAuras.GetAuraDuration, unit, item.auraInstanceID)
        if ok and ns._auraPresentTruthy(dur) then
            iconWidget._liveDurObj = dur
            iconWidget._liveDurObjType = type(dur)
            iconWidget._liveDurObjSecret = isSecret(dur)
            pcall(iconWidget.SetCooldown, iconWidget, dur)
            iconWidget._lastArmPath = "auras:auraDur"
            return
        end
    end

    if type(item) == "table" and item._summonDurObj ~= nil then
        local sdur = item._summonDurObj
        iconWidget._liveDurObj = sdur
        iconWidget._liveDurObjType = type(sdur)
        iconWidget._liveDurObjSecret = isSecret(sdur)
        pcall(iconWidget.SetCooldown, iconWidget, sdur)
        iconWidget._lastArmPath = "auras:summonBar"
        return
    end

    if type(item) == "table" and item._probeDurObj ~= nil then
        local pdur = item._probeDurObj
        iconWidget._liveDurObj = pdur
        iconWidget._liveDurObjType = type(pdur)
        iconWidget._liveDurObjSecret = isSecret(pdur)
        pcall(iconWidget.SetCooldown, iconWidget, pdur)
        iconWidget._lastArmPath = "auras:spellIDprobe"
        return
    end

    if spellID and C_Spell and C_Spell.GetSpellCooldownDuration then
        local ok, dur = pcall(C_Spell.GetSpellCooldownDuration, spellID, false)
        if ok and ns._auraPresentTruthy(dur) then
            iconWidget._liveDurObj = dur
            iconWidget._liveDurObjType = type(dur)
            iconWidget._liveDurObjSecret = isSecret(dur)
            pcall(iconWidget.SetCooldown, iconWidget, dur)
            iconWidget._lastArmPath = "auras:spellCD"
            return
        end
    end

    if spellID and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok and type(aura) == "table" then
            local exp = aura.expirationTime
            local d   = aura.duration
            if type(exp) == "number" and type(d) == "number"
               and not isSecret(d) and not isSecret(exp) and d > 0 then
                local startTime = exp - d
                local durObj = iconWidget._slot and getDurationFor(iconWidget._slot) or nil
                if durObj and durObj.SetTimeFromStart then
                    local okSet = pcall(durObj.SetTimeFromStart, durObj, startTime, d, aura.timeMod or 1)
                    if okSet then
                        iconWidget._liveDurObj = durObj
                        iconWidget._liveDurObjType = type(durObj)
                        iconWidget._liveDurObjSecret = isSecret(durObj)
                        pcall(iconWidget.SetCooldown, iconWidget, durObj)
                        iconWidget._lastArmPath = "auras:synth"
                        return
                    end
                end
            end
        end
    end

    pcall(iconWidget.ClearCooldown, iconWidget)
end

local function readBarName(item)
    if type(item) ~= "table" then return nil end
    if type(item._barName) == "string" then return item._barName end
    if type(item.GetNameFontString) == "function" then
        local ok, fs = pcall(item.GetNameFontString, item)
        if ok and type(fs) == "table" and type(fs.GetText) == "function" then
            local ok2, txt = pcall(fs.GetText, fs)
            if ok2 then return txt end
        end
    end
    return nil
end

local function readBarDuration(item)
    if type(item) ~= "table" then return nil end
    if item._preview == true then
        if type(_lowTimeStats) == "table"
           and type(_lowTimeStats.pvTimerText) == "function" then
            local ok, txt = pcall(_lowTimeStats.pvTimerText, item._previewSlot)
            if ok then return txt end
        end
        return ""
    end
    if type(item.GetDurationFontString) == "function" then
        local ok, fs = pcall(item.GetDurationFontString, item)
        if ok and type(fs) == "table" and type(fs.GetText) == "function" then
            local ok2, txt = pcall(fs.GetText, fs)
            if ok2 then return txt end
        end
    end
    if type(item.Bar) == "table" and type(item.Bar.Duration) == "table" then
        local fs = item.Bar.Duration
        if type(fs.GetText) == "function" then
            local ok, txt = pcall(fs.GetText, fs)
            if ok then return txt end
        end
    end
    if type(Auras._readLiveBarDurationText) == "function"
       and type(item.cooldownID) == "number" then
        local txt = Auras._readLiveBarDurationText(item.cooldownID)
        if isSecret(txt) then return txt end
        if txt ~= nil then return txt end
    end
    return nil
end

local BAR_TIMER_DIR_REMAINING = (Enum and Enum.StatusBarTimerDirection
    and Enum.StatusBarTimerDirection.RemainingTime) or 1
local BAR_TIMER_INTERP_IMMEDIATE = (Enum and Enum.StatusBarInterpolation
    and Enum.StatusBarInterpolation.Immediate) or 0

_lowTimeStats = {}

_lowTimeStats.preview = {
    enabled    = false,
    count      = 2,
    loopSec    = 10,
    durs       = {},
    lastPct    = {},
    defaultWidth = 250,
}

_lowTimeStats.pvEnabled = function()
    return _lowTimeStats.preview.enabled == true
end

_lowTimeStats.pvDuration = function(i)
    if not (C_DurationUtil and C_DurationUtil.CreateDuration) then return nil end
    local pv = _lowTimeStats.preview
    local now = GetTime and GetTime() or 0
    local loop = pv.loopSec
    if type(loop) ~= "number" or loop <= 0 then loop = 10 end
    local phase = ((i - 1) * (loop / 3)) % loop
    local elapsed = (now + phase) % loop
    local startTime = now - elapsed
    pv.lastRemain = pv.lastRemain or {}
    pv.lastRemain[i] = loop - elapsed
    pv.lastPct[i] = (loop > 0) and ((loop - elapsed) / loop) or 0
    local dur = pv.durs[i]
    if not dur then
        local ok, d = pcall(C_DurationUtil.CreateDuration)
        if not ok or not d then return nil end
        dur = d
        pv.durs[i] = dur
    end
    if type(dur.SetTimeFromStart) ~= "function" then return dur end
    pcall(dur.SetTimeFromStart, dur, startTime, loop, 1)
    return dur
end

_lowTimeStats.pvTimerText = function(i)
    local pv = _lowTimeStats.preview
    local rem = pv.lastRemain and pv.lastRemain[tonumber(i) or 0]
    if type(rem) ~= "number" then return "" end
    if rem < 0 then rem = 0 end
    return tostring(math.ceil(rem))
end

_lowTimeStats.pvBuild = function()
    local n = _lowTimeStats.preview.count
    if type(n) ~= "number" or n < 1 then n = 1 elseif n > 3 then n = 3 end
    local items = {}
    for i = 1, n do
        local dur = _lowTimeStats.pvDuration(i)
        items[i] = {
            _preview     = true,
            _previewSlot = i,
            _previewDur  = dur,
            _barName     = "Preview " .. i,
            _spellID     = nil,
            _iconTexture = [[Interface\Icons\INV_Misc_QuestionMark]],
        }
    end
    return items
end

function Auras._parseDisplayedSeconds(text)
    if isSecret(text) then return nil end
    if text == nil then return nil end
    if type(text) ~= "string" then return nil end
    local num, unit = string.match(text, "^%s*(%d+%.?%d*)%s*([smhSMH]?)")
    if not num then return nil end
    local n = tonumber(num)
    if type(n) ~= "number" then return nil end
    local u = unit and string.lower(unit) or ""
    if u == "m" then
        n = n * 60
    elseif u == "h" then
        n = n * 3600
    end
    return n
end

function Auras._getLowTimeTextOptions(kind)
    local opts = {
        enabled = false,
        threshold = 5,
        normalR = 1, normalG = 1, normalB = 1, normalA = 0.9,
        lowR = 1, lowG = 0.15, lowB = 0.10, lowA = 1,
    }
    local p = Auras and Auras.profileRef
    local c = p and p.lowTimeText
    if type(c) ~= "table" then return opts end
    if c.enabled == true then opts.enabled = true end
    if type(c.threshold) == "number" then opts.threshold = c.threshold end
    if type(c.normalR) == "number" then opts.normalR = c.normalR end
    if type(c.normalG) == "number" then opts.normalG = c.normalG end
    if type(c.normalB) == "number" then opts.normalB = c.normalB end
    if type(c.normalA) == "number" then opts.normalA = c.normalA end
    if type(c.lowR) == "number" then opts.lowR = c.lowR end
    if type(c.lowG) == "number" then opts.lowG = c.lowG end
    if type(c.lowB) == "number" then opts.lowB = c.lowB end
    if type(c.lowA) == "number" then opts.lowA = c.lowA end
    return opts
end

function Auras._applyAuraTimerTextColor(fontString, displayedText, kind)
    if fontString == nil then return end
    if type(fontString.SetTextColor) ~= "function" then return end
    local opts = Auras._getLowTimeTextOptions(kind)
    if opts.enabled ~= true then
        return
    end
    local seconds = Auras._parseDisplayedSeconds(displayedText)
    if seconds ~= nil and seconds <= opts.threshold then
        pcall(fontString.SetTextColor, fontString, opts.lowR, opts.lowG, opts.lowB, opts.lowA)
    else
        pcall(fontString.SetTextColor, fontString, opts.normalR, opts.normalG, opts.normalB, opts.normalA)
    end
end

function Auras._findIconCooldownFontString(w)
    if type(w) ~= "table" then return nil end
    local f = w.frame
    local candidates = {
        w.cooldownText,
        w.timerText,
        w.countdownText,
        f and f.cooldown and f.cooldown.Text,
        f and f.Cooldown and f.Cooldown.Text,
        w.cooldown and w.cooldown.Text,
    }
    for i = 1, #candidates do
        local fs = candidates[i]
        if type(fs) == "table" and type(fs.SetTextColor) == "function" then
            return fs
        end
    end
    local cd = f and f.cooldown
    if cd and type(cd.GetCountdownFontString) == "function" then
        local ok, fs = pcall(cd.GetCountdownFontString, cd)
        if ok and type(fs) == "table" and type(fs.SetTextColor) == "function" then
            return fs
        end
    end
    return nil
end

function Auras._applyIconLowTimeTextColor(w, kind)
    local opts = Auras._getLowTimeTextOptions(kind)
    if opts.enabled ~= true then return end
    local fs = Auras._findIconCooldownFontString(w)
    if not fs then
        dwarnOnce("auras_lowtime_no_icon_fs",
            "Auras low-time color: no cooldown FontString found for icon widget")
        return
    end
    local ok, text = pcall(fs.GetText, fs)
    if not ok then text = nil end
    Auras._applyAuraTimerTextColor(fs, text, kind)
end

function Auras._applyBarLowTimeFill(slot, displayedText)
    if type(slot) ~= "table" then return end
    local bar = slot.bar
    if bar == nil or type(bar.SetStatusBarColor) ~= "function" then return end
    local opts = Auras._getLowTimeTextOptions("bar")
    if opts.enabled ~= true then
        return
    end
    local br = type(slot._baseFillR) == "number" and slot._baseFillR or 1
    local bg = type(slot._baseFillG) == "number" and slot._baseFillG or 1
    local bb = type(slot._baseFillB) == "number" and slot._baseFillB or 1
    local ba = type(slot._baseFillA) == "number" and slot._baseFillA or 1
    local seconds = Auras._parseDisplayedSeconds(displayedText)
    if seconds ~= nil and seconds <= opts.threshold then
        pcall(bar.SetStatusBarColor, bar, opts.lowR, opts.lowG, opts.lowB, opts.lowA)
    else
        pcall(bar.SetStatusBarColor, bar, br, bg, bb, ba)
    end
end

Auras._lowTimeCurves = Auras._lowTimeCurves or {}
Auras._lowTimeCurveGen = Auras._lowTimeCurveGen or 0
Auras._lowTimeCurveFailed = false

Auras._lowTimeDebug = Auras._lowTimeDebug or {}

function Auras._recordLowTimeDebug(slotKind, t)
    if type(slotKind) ~= "string" then return end
    if Auras._lowTimeDebug[slotKind] ~= nil then return end
    t = t or {}
    t.at = (type(GetTime) == "function") and GetTime() or 0
    t.inCombat = (type(InCombatLockdown) == "function") and InCombatLockdown() or false
    Auras._lowTimeDebug[slotKind] = t
end

function Auras._ensureLowTimeColorCurve(threshold, lr, lg, lb, la, br, bg, bb, ba)
    if Auras._lowTimeCurveFailed then return nil end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then
        Auras._lowTimeCurveFailed = true
        dwarnOnce("auras_lowtime_curve_api",
            "low-time curve: C_CurveUtil.CreateColorCurve unavailable")
        return nil
    end
    if not (Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step ~= nil) then
        Auras._lowTimeCurveFailed = true
        dwarnOnce("auras_lowtime_curve_enum",
            "low-time curve: Enum.LuaCurveType.Step unavailable")
        return nil
    end
    local thr = tonumber(threshold) or 5
    if thr <= 0 then thr = 0.001 end
    local key = string.format("%d|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f",
        Auras._lowTimeCurveGen, thr, lr, lg, lb, la, br, bg, bb, ba)
    local cached = Auras._lowTimeCurves[key]
    if cached then return cached end
    local okC, curve = pcall(C_CurveUtil.CreateColorCurve)
    if not okC or not curve then
        dwarnOnce("auras_lowtime_curve_create",
            "low-time curve: CreateColorCurve failed err=" .. tostring(curve))
        return nil
    end
    local ok1 = pcall(curve.SetType, curve, Enum.LuaCurveType.Step)
    local ok2 = pcall(curve.AddPoint, curve, 0,   CreateColor(lr, lg, lb, la))
    local ok3 = pcall(curve.AddPoint, curve, thr, CreateColor(br, bg, bb, ba))
    if not (ok1 and ok2 and ok3) then
        dwarnOnce("auras_lowtime_curve_setup", "low-time curve: curve setup failed")
        return nil
    end
    Auras._lowTimeCurves[key] = curve
    return curve
end

local function _isUsableLowTimeDuration(dur)
    if dur == nil then return false end
    if isSecret(dur) then return true end
    local dt = type(dur)
    if dt ~= "table" and dt ~= "userdata" then return false end
    if dt == "table" and type(dur.EvaluateRemainingDuration) ~= "function" then return false end
    return true
end

function Auras._resolveLowTimeDuration(item, spellID, dbg)
    if type(item) ~= "table" then
        if dbg then dbg.durPath = "no-item" end
        return nil
    end
    do
        local totemDur = Auras._resolveTotemDuration(item)
        if _isUsableLowTimeDuration(totemDur) then
            if dbg then dbg.durPath = "GetTotemDuration" end
            return totemDur
        end
    end
    if item.auraInstanceID ~= nil
       and C_UnitAuras and C_UnitAuras.GetAuraDuration then
        local unit = type(item.auraDataUnit) == "string" and item.auraDataUnit or "player"
        if isSecret(unit) then unit = "player" end
        local ok, dur = pcall(C_UnitAuras.GetAuraDuration, unit, item.auraInstanceID)
        if ok and _isUsableLowTimeDuration(dur) then
            if dbg then dbg.durPath = "GetAuraDuration:" .. tostring(unit) end
            return dur
        elseif dbg and not ok then
            dbg.durErr = "GetAuraDuration:" .. tostring(dur)
        end
    end
    if spellID and C_Spell and C_Spell.GetSpellCooldownDuration then
        local ok, dur = pcall(C_Spell.GetSpellCooldownDuration, spellID, false)
        if ok and _isUsableLowTimeDuration(dur) then
            if dbg then dbg.durPath = "GetSpellCooldownDuration" end
            return dur
        elseif dbg and not ok then
            dbg.durErr = (dbg.durErr or "") .. " GetSpellCooldownDuration:" .. tostring(dur)
        end
    end
    if dbg then dbg.durPath = dbg.durPath or "nil" end
    return nil
end

function Auras._evalLowTimeCurve(durObj, threshold, lr, lg, lb, la, br, bg, bb, ba, dbg)
    if dbg then
        dbg.evalType = type(durObj)
        dbg.evalSecret = isSecret(durObj)
    end
    local secretDur = isSecret(durObj)
    if not secretDur and durObj == nil then
        if dbg then dbg.evalErr = "no-durobj" end
        return nil
    end
    if not secretDur then
        local dt = type(durObj)
        if dt ~= "table" and dt ~= "userdata" then
            if dbg then dbg.evalErr = "non-evaluable-non-secret:" .. dt end
            return nil
        end
        if dt == "table" then
            if type(durObj.EvaluateRemainingDuration) ~= "function" then
                if dbg then dbg.evalErr = "no-EvaluateRemainingDuration" end
                return nil
            end
            if dbg then dbg.evalHasMethod = true end
        end
    end
    local curve = Auras._ensureLowTimeColorCurve(threshold, lr, lg, lb, la, br, bg, bb, ba)
    if not curve then
        if dbg then dbg.evalErr = "no-curve" end
        return nil
    end
    local okEv, result = pcall(function()
        return durObj:EvaluateRemainingDuration(curve)
    end)
    if dbg then
        dbg.evalOk = okEv and true or false
        if not okEv then dbg.evalErr = tostring(result) end
    end
    local rType = type(result)
    if not okEv or (rType ~= "table" and rType ~= "userdata") then
        if dbg and okEv and result ~= nil and not dbg.evalErr then
            dbg.evalErr = "result-unusable:" .. rType
        end
        return nil
    end
    if dbg then
        dbg.resultIsTable = true
        dbg.resultRSecret = isSecret(result.r)
        dbg.resultASecret = isSecret(result.a)
    end
    return result
end

function Auras._applyIconLowTimeCurve(w, item, spellID, kind)
    local opts = Auras._getLowTimeTextOptions(kind)
    if opts.enabled ~= true then return false end
    local dbg = nil
    if Auras._lowTimeDebug and Auras._lowTimeDebug.icon == nil then
        dbg = { kind = kind, enabled = true, threshold = opts.threshold }
    end
    local fs = Auras._findIconCooldownFontString(w)
    if not fs or type(fs.SetTextColor) ~= "function" then
        if dbg then dbg.fs = false Auras._recordLowTimeDebug("icon", dbg) end
        return false
    end
    if dbg then dbg.fs = true end
    local durObj = w._liveDurObj
    if ns._auraPresentTruthy(durObj) then
        if dbg then
            dbg.durSrc = "live-icon" dbg.durPath = "live-icon"
            dbg.stashType   = w._liveDurObjType
            dbg.stashSecret = w._liveDurObjSecret
        end
    else
        if dbg then dbg.durSrc = "resolve" end
        durObj = Auras._resolveLowTimeDuration(item, spellID, dbg)
        if dbg and not ns._auraPresentTruthy(durObj) then dbg.durSrc = "nil" end
    end
    if not ns._auraPresentTruthy(durObj) then
        if dbg then dbg.curveApplied = false Auras._recordLowTimeDebug("icon", dbg) end
        return false
    end
    local result = Auras._evalLowTimeCurve(durObj, opts.threshold,
        opts.lowR, opts.lowG, opts.lowB, opts.lowA,
        opts.normalR, opts.normalG, opts.normalB, opts.normalA, dbg)
    if not result then
        if dbg then dbg.curveApplied = false Auras._recordLowTimeDebug("icon", dbg) end
        return false
    end
    local okSet = pcall(fs.SetTextColor, fs, result.r, result.g, result.b, result.a)
    if dbg then
        dbg.sinkOk = okSet and true or false
        dbg.curveApplied = okSet and true or false
        Auras._recordLowTimeDebug("icon", dbg)
    end
    return okSet and true or false
end

function Auras._applyBarLowTimeCurve(slot, item, spellID)
    if type(slot) ~= "table" then return false end
    local opts = Auras._getLowTimeTextOptions("bar")
    if opts.enabled ~= true then return false end
    local dbg = nil
    if Auras._lowTimeDebug and Auras._lowTimeDebug.bar == nil then
        dbg = { kind = "bar", enabled = true, threshold = opts.threshold }
    end
    local durObj = slot._liveDurObj
    if ns._auraPresentTruthy(durObj) then
        if dbg then
            dbg.durSrc = "live-bar" dbg.durPath = "live-bar"
            dbg.stashType   = slot._liveDurObjType
            dbg.stashSecret = slot._liveDurObjSecret
        end
    else
        if dbg then dbg.durSrc = "resolve" end
        durObj = Auras._resolveLowTimeDuration(item, spellID, dbg)
        if dbg and not ns._auraPresentTruthy(durObj) then dbg.durSrc = "nil" end
    end
    if not ns._auraPresentTruthy(durObj) then
        if dbg then dbg.curveApplied = false Auras._recordLowTimeDebug("bar", dbg) end
        return false
    end

    local appliedText = false
    local fs = slot.durFS
    if fs ~= nil and type(fs.SetTextColor) == "function" then
        local rText = Auras._evalLowTimeCurve(durObj, opts.threshold,
            opts.lowR, opts.lowG, opts.lowB, opts.lowA,
            opts.normalR, opts.normalG, opts.normalB, opts.normalA, dbg)
        if rText then
            local okSet = pcall(fs.SetTextColor, fs, rText.r, rText.g, rText.b, rText.a)
            if okSet then appliedText = true end
            if dbg then dbg.textSinkOk = okSet and true or false end
        end
    end

    local appliedFill = false
    local bar = slot.bar
    if bar ~= nil and type(bar.SetStatusBarColor) == "function" then
        local fr = type(slot._baseFillR) == "number" and slot._baseFillR or 1
        local fg = type(slot._baseFillG) == "number" and slot._baseFillG or 1
        local fb = type(slot._baseFillB) == "number" and slot._baseFillB or 1
        local fa = type(slot._baseFillA) == "number" and slot._baseFillA or 1
        local rFill = Auras._evalLowTimeCurve(durObj, opts.threshold,
            opts.lowR, opts.lowG, opts.lowB, opts.lowA,
            fr, fg, fb, fa, nil)
        if rFill then
            local okSet = pcall(bar.SetStatusBarColor, bar, rFill.r, rFill.g, rFill.b, rFill.a)
            if okSet then appliedFill = true end
            if dbg then dbg.fillSinkOk = okSet and true or false end
        end
    end

    local applied = appliedText or appliedFill
    if dbg then
        dbg.curveApplied = applied
        Auras._recordLowTimeDebug("bar", dbg)
    end
    return applied
end

function Auras:GetLowTimeTextDiagnostic()
    local opts = Auras._getLowTimeTextOptions("bar")
    local out = { opts = opts }

    local function chosen(text)
        local sec = Auras._parseDisplayedSeconds(text)
        if sec == nil then return "normal (unparseable)", nil end
        if sec <= opts.threshold then
            return string.format("LOW (%.3f %.3f %.3f)", opts.lowR, opts.lowG, opts.lowB), sec
        end
        return string.format("normal (%.3f %.3f %.3f)", opts.normalR, opts.normalG, opts.normalB), sec
    end

    if type(self.BarDisplay) == "table" and type(self.BarDisplay.BuildActive) == "function" then
        local okB, barActive = pcall(self.BarDisplay.BuildActive, self.BarDisplay)
        if okB and type(barActive) == "table" and barActive[1] then
            local text = readBarDuration(barActive[1])
            local color, sec = chosen(text)
            out.bar = { text = text, seconds = sec, color = color }
        end
    end

    if type(self.IconDisplay) == "table" and type(self.IconDisplay.icons) == "table" then
        local w = self.IconDisplay.icons[1]
        if w then
            local fs = Auras._findIconCooldownFontString(w)
            if fs then
                local okT, text = pcall(fs.GetText, fs)
                if not okT then text = nil end
                local color, sec = chosen(text)
                out.icon = { text = text, seconds = sec, color = color, hasFS = true }
            else
                out.icon = { hasFS = false }
            end
        end
    end

    return out
end

function Auras:GetLowTimeEngineDebug()
    local opts = Auras._getLowTimeTextOptions("bar")
    return {
        opts = opts,
        inCombat = (type(InCombatLockdown) == "function") and InCombatLockdown() or false,
        curveFailedLatch = Auras._lowTimeCurveFailed and true or false,
        curveGen = Auras._lowTimeCurveGen,
        bar = Auras._lowTimeDebug and Auras._lowTimeDebug.bar or nil,
        icon = Auras._lowTimeDebug and Auras._lowTimeDebug.icon or nil,
    }
end

local function applyBarFill(slot, item, spellID)
    if not (slot and slot.bar) then return end
    local bar = slot.bar

    if type(bar.SetReverseFill) == "function" then
        pcall(bar.SetReverseFill, bar, false)
    end

    slot._liveDurObj = nil
    slot._liveDurObjType = nil
    slot._liveDurObjSecret = nil

    if type(item) == "table" and item._previewDur ~= nil
       and type(bar.SetTimerDuration) == "function" then
        local okSet = pcall(bar.SetTimerDuration, bar, item._previewDur,
            BAR_TIMER_INTERP_IMMEDIATE, BAR_TIMER_DIR_REMAINING)
        if okSet then
            slot._liveDurObj = item._previewDur
            slot._liveDurObjType = type(item._previewDur)
            slot._liveDurObjSecret = isSecret(item._previewDur)
            return
        end
        if type(item._previewDur.GetRemainingPercent) == "function" then
            local okEv, pct = pcall(item._previewDur.GetRemainingPercent, item._previewDur)
            if okEv and type(pct) == "number" then
                pcall(bar.SetTimerDuration, bar, nil)
                bar:SetMinMaxValues(0, 1)
                bar:SetValue(pct)
                return
            end
        end
    end

    if type(bar.SetTimerDuration) == "function"
       and type(item) == "table" and item.auraInstanceID ~= nil
       and C_UnitAuras and C_UnitAuras.GetAuraDuration then
        local unit = type(item.auraDataUnit) == "string" and item.auraDataUnit or "player"
        local ok, dur = pcall(C_UnitAuras.GetAuraDuration, unit, item.auraInstanceID)
        if ok and ns._auraPresentTruthy(dur) then
            local okSet = pcall(bar.SetTimerDuration, bar, dur,
                BAR_TIMER_INTERP_IMMEDIATE, BAR_TIMER_DIR_REMAINING)
            if okSet then
                slot._liveDurObj = dur
                slot._liveDurObjType = type(dur)
                slot._liveDurObjSecret = isSecret(dur)
                return
            end
        end
    end

    if type(bar.SetTimerDuration) == "function"
       and type(item) == "table" and item._summonDurObj ~= nil then
        local sdur = item._summonDurObj
        local okSet = pcall(bar.SetTimerDuration, bar, sdur,
            BAR_TIMER_INTERP_IMMEDIATE, BAR_TIMER_DIR_REMAINING)
        if okSet then
            slot._liveDurObj = sdur
            slot._liveDurObjType = type(sdur)
            slot._liveDurObjSecret = isSecret(sdur)
            return
        end
    end

    if type(bar.SetTimerDuration) == "function"
       and type(item) == "table" and item._probeDurObj ~= nil then
        local pdur = item._probeDurObj
        local okSet = pcall(bar.SetTimerDuration, bar, pdur,
            BAR_TIMER_INTERP_IMMEDIATE, BAR_TIMER_DIR_REMAINING)
        if okSet then
            slot._liveDurObj = pdur
            slot._liveDurObjType = type(pdur)
            slot._liveDurObjSecret = isSecret(pdur)
            return
        end
    end

    if type(bar.SetTimerDuration) == "function"
       and spellID and C_Spell and C_Spell.GetSpellCooldownDuration then
        local ok, dur = pcall(C_Spell.GetSpellCooldownDuration, spellID, false)
        if ok and ns._auraPresentTruthy(dur) then
            local okSet = pcall(bar.SetTimerDuration, bar, dur,
                BAR_TIMER_INTERP_IMMEDIATE, BAR_TIMER_DIR_REMAINING)
            if okSet then
                slot._liveDurObj = dur
                slot._liveDurObjType = type(dur)
                slot._liveDurObjSecret = isSecret(dur)
                return
            end
        end
    end

    if spellID and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok and type(aura) == "table" then
            local exp, d = aura.expirationTime, aura.duration
            if type(exp) == "number" and type(d) == "number"
               and not isSecret(d) and not isSecret(exp) and d > 0 then
                local rem = exp - GetTime()
                if rem < 0 then rem = 0 end
                if type(bar.SetTimerDuration) == "function" then
                    pcall(bar.SetTimerDuration, bar, nil)
                end
                bar:SetMinMaxValues(0, d)
                bar:SetValue(rem)
                return
            end
        end
    end

    if type(bar.SetTimerDuration) == "function" then
        pcall(bar.SetTimerDuration, bar, nil)
    end
    bar:SetMinMaxValues(0, 1)
    if type(item) == "table"
       and (item.auraInstanceID ~= nil or item._presentSecret == true) then
        bar:SetValue(1)
    else
        bar:SetValue(0)
    end
end

local pandemicState = {}

local spellDurationCache = {}

local _pandemicLogged = {}
local function pandemicLogOnce(cdID, reason, extra)
    if not (ns.Debug and ns.Debug.Verbose) then return end
    local key = tostring(cdID) .. ":" .. tostring(reason)
    if _pandemicLogged[key] then return end
    _pandemicLogged[key] = true
    dverbose("pandemic skip cdID=%s reason=%s%s",
        tostring(cdID), tostring(reason),
        extra and (" " .. tostring(extra)) or "")
end

local function resetComboLogState()
    wipe(spellDurationCache)
end

local function pandemicOpts(modOrSelf)
    local p = (modOrSelf and modOrSelf.profileRef) or (Auras and Auras.profileRef)
    local bars = p and p.bars
    local po = bars and bars.pandemic
    if type(po) ~= "table" then return nil end
    return po
end

local function activeGlowOpts(modOrSelf, kind)
    local p = (modOrSelf and modOrSelf.profileRef) or (Auras and Auras.profileRef)
    if not p then return nil end
    local sub
    if kind == "icon" then
        sub = p.icons
    elseif kind == "bar" then
        sub = p.bars
    else
        return nil
    end
    local ago = sub and sub.activeGlow
    if type(ago) ~= "table" then return nil end
    return ago
end

local function getPandemicSpellID(item)
    if type(item) ~= "table" then return nil end
    local cdInfo = item.cooldownInfo
    if type(cdInfo) == "table" then
        local sid = cdInfo.spellID
        if type(sid) == "number" and sid > 0 then return sid end
        local osid = cdInfo.overrideSpellID
        if type(osid) == "number" and osid > 0 then return osid end
    end
    return nil
end

function Auras._noteSpellBaseDuration(spellID, secs, src)
    if type(spellID) ~= "number" then return end
    secs = tonumber(secs)
    if not secs or secs <= 0 then return end
    local rec = spellDurationCache[spellID]
    local changed = false
    if type(rec) ~= "table" then
        spellDurationCache[spellID] = { base = secs, src = src }
        changed = true
    elseif src == "base-api" then
        if rec.src ~= "base-api" or rec.base ~= secs then
            rec.base, rec.src = secs, "base-api"
            changed = true
        end
    elseif rec.src ~= "base-api" and secs < (rec.base or math.huge) then
        rec.base = secs
        changed = true
    end
    if changed and not (InCombatLockdown and InCombatLockdown()) then
        pcall(Auras.PrebuildPandemicCurves, Auras)
    end
end

function Auras._pandemicThresholdSeconds(item, opts, sid)
    if sid == nil then sid = getPandemicSpellID(item) end
    if type(sid) ~= "number" then return nil end
    local rec = spellDurationCache[sid]
    if type(rec) ~= "table" then return nil end
    local base = tonumber(rec.base)
    if not base or base <= 0 then return nil end
    local thr = tonumber(opts and opts.threshold) or 0.30
    if thr > 1 then thr = thr / 100 end
    if thr < 0.01 then thr = 0.01 end
    if thr > 0.99 then thr = 0.99 end
    return base * thr, base, rec.src
end

local function itemPreferenceKeys(item)
    if type(item) ~= "table" then return nil, nil end
    local cdID = tonumber(item.cooldownID)
    local cdInfo = item.cooldownInfo
    local sid, osid
    if type(cdInfo) == "table" then
        local okS, s = pcall(function() return cdInfo.spellID end)
        if okS and type(s) == "number" and not isSecret(s) and s > 0 then sid = s end
        local okO, o = pcall(function() return cdInfo.overrideSpellID end)
        if okO and type(o) == "number" and not isSecret(o) and o > 0 then osid = o end
    end
    local primary = osid or sid
    if primary then
        if cdID then
            local cache = Auras._itemKeyCache
            if not cache then
                cache = {}
                Auras._itemKeyCache = cache
            end
            local rec = cache[cdID]
            if not rec then
                rec = {}
                cache[cdID] = rec
            end
            rec[1], rec[2] = primary, sid
        end
        return primary, sid
    end
    if cdID and Auras._itemKeyCache then
        local rec = Auras._itemKeyCache[cdID]
        if rec then return rec[1], rec[2] end
    end
    return nil, nil
end

local function itemDisplayEnabled(item)
    local primary, base = itemPreferenceKeys(item)
    if not primary then return true end
    if not (ns.GetProfile and ns.savedVarsReady) then return true end
    local ok, p = pcall(ns.GetProfile, ns)
    if not ok or type(p) ~= "table" or type(p.auras) ~= "table" then return true end
    local ap = p.auras[primary]
    if type(ap) == "table" and ap.enabled ~= nil then
        return ap.enabled ~= false
    end
    if base and base ~= primary then
        local apb = p.auras[base]
        if type(apb) == "table" and apb.enabled ~= nil then
            return apb.enabled ~= false
        end
    end
    return true
end

function Auras.PerAuraActiveGlow(item)
    if not (ns.GetProfile and ns.savedVarsReady) then return nil end
    local ok, p = pcall(ns.GetProfile, ns)
    if not ok or type(p) ~= "table" or type(p.auras) ~= "table" then return nil end
    local primary, base = itemPreferenceKeys(item)
    if not primary then return nil end
    local g
    local ap = p.auras[primary]
    if type(ap) == "table" and type(ap.glow) == "table"
       and type(ap.glow.activeAura) == "table"
       and ap.glow.activeAura.enabled ~= nil then
        g = ap.glow.activeAura
    end
    if not g and base and base ~= primary then
        local apb = p.auras[base]
        if type(apb) == "table" and type(apb.glow) == "table"
           and type(apb.glow.activeAura) == "table"
           and apb.glow.activeAura.enabled ~= nil then
            g = apb.glow.activeAura
        end
    end
    if not g then return nil end
    if g.enabled ~= true then return false end
    local s = Auras._perAuraGlowScratch
    if not s then
        s = {}
        Auras._perAuraGlowScratch = s
    end
    local c = g.color
    if type(c) ~= "table" then c = nil end
    s.colorR = c and tonumber(c[1]) or 0.4
    s.colorG = c and tonumber(c[2]) or 0.8
    s.colorB = c and tonumber(c[3]) or 1.0
    s.colorA = c and tonumber(c[4]) or 1.0
    s.style = (type(g.style) == "string") and g.style or nil
    return true, s
end

function Auras._resolveActiveGlowSticky(item)
    local okPA, perOn, perOpts = pcall(Auras.PerAuraActiveGlow, item)
    local cdID
    if type(item) == "table" then
        local okC, c = pcall(tonumber, item.cooldownID)
        if okC then cdID = c end
    end
    local cache = Auras._activeGlowVerdictCache
    if okPA then
        if cdID then
            if not cache then
                cache = {}
                Auras._activeGlowVerdictCache = cache
            end
            local rec = cache[cdID]
            if not rec then
                rec = {}
                cache[cdID] = rec
            end
            rec.perOn = perOn
            if perOn == true and type(perOpts) == "table" then
                rec.colorR, rec.colorG = perOpts.colorR, perOpts.colorG
                rec.colorB, rec.colorA = perOpts.colorB, perOpts.colorA
                rec.style = perOpts.style
            end
        end
        return perOn, perOpts, nil
    end
    dwarnOnce("agresolve:" .. tostring(cdID),
        "[ACTIVE GLOW] PerAuraActiveGlow threw (cdID=%s): %s",
        tostring(cdID), tostring(perOn))
    local rec = cdID and cache and cache[cdID]
    if rec and rec.perOn ~= nil then
        local s = Auras._perAuraGlowStickyScratch
        if not s then
            s = {}
            Auras._perAuraGlowStickyScratch = s
        end
        s.colorR, s.colorG = rec.colorR, rec.colorG
        s.colorB, s.colorA = rec.colorB, rec.colorA
        s.style = rec.style
        return rec.perOn, (rec.perOn == true) and s or nil,
            "resolver-error-served-cache: " .. tostring(perOn)
    end
    return nil, nil, "resolver-error: " .. tostring(perOn)
end

function Auras.PerAuraPandemicGlow(item, globalOpts)
    if not (ns.GetProfile and ns.savedVarsReady) then return nil end
    local ok, p = pcall(ns.GetProfile, ns)
    if not ok or type(p) ~= "table" or type(p.auras) ~= "table" then return nil end
    local primary, base = itemPreferenceKeys(item)
    if not primary then return nil end
    local g
    local ap = p.auras[primary]
    if type(ap) == "table" and type(ap.glow) == "table"
       and type(ap.glow.pandemic) == "table" then
        g = ap.glow.pandemic
    end
    if not g and base and base ~= primary then
        local apb = p.auras[base]
        if type(apb) == "table" and type(apb.glow) == "table"
           and type(apb.glow.pandemic) == "table" then
            g = apb.glow.pandemic
        end
    end
    if not g then return nil end
    if g.enabled == false then return false end
    if g.enabled ~= true or g.userSet ~= true then return nil end

    local s = Auras._perAuraPandemicScratch
    if not s then
        s = { only = {} }
        Auras._perAuraPandemicScratch = s
    end
    s.enabled = true
    wipe(s.only)
    local cdID = type(item) == "table" and tonumber(item.cooldownID) or nil
    if cdID then s.only[cdID] = true end
    s.skip = nil
    s.evalInterval  = globalOpts and globalOpts.evalInterval or nil
    s.graceSuppress = globalOpts and globalOpts.graceSuppress or nil
    s.threshold = tonumber(g.threshold)
        or (globalOpts and tonumber(globalOpts.threshold))
        or 0.30
    local c = g.color
    if type(c) ~= "table" then c = nil end
    s.colorR = c and tonumber(c[1]) or 1.0
    s.colorG = c and tonumber(c[2]) or 0.35
    s.colorB = c and tonumber(c[3]) or 0.1
    s.colorA = c and tonumber(c[4]) or 1.0
    s.style = (type(g.style) == "string") and g.style or nil
    return true, s
end

local function entryDisplayEnabled(entry)
    if type(entry) ~= "table" then return true end
    if not (ns.GetProfile and ns.savedVarsReady) then return true end
    local ok, p = pcall(ns.GetProfile, ns)
    if not ok or type(p) ~= "table" or type(p.auras) ~= "table" then return true end

    local sid = entry.stableEntryID
    if sid ~= nil then
        local ap = p.auras[sid]
        if type(ap) == "table" and ap.enabled ~= nil then
            return ap.enabled ~= false
        end
    end

    local primary = entry.overrideSpellID or entry.spellID
    local base = entry.spellID
    if primary then
        local ap = p.auras[primary]
        if type(ap) == "table" and ap.enabled ~= nil then
            return ap.enabled ~= false
        end
    end
    if base and base ~= primary then
        local apb = p.auras[base]
        if type(apb) == "table" and apb.enabled ~= nil then
            return apb.enabled ~= false
        end
    end
    return true
end

local function cdmPreviewOpen()
    local cvs = _G.CooldownViewerSettings
    if type(cvs) == "table" and type(cvs.IsShown) == "function" then
        local ok, shown = pcall(cvs.IsShown, cvs)
        if ok and shown then return true end
    end
    local emm = _G.EditModeManagerFrame
    if type(emm) == "table" and type(emm.IsShown) == "function" then
        local ok, shown = pcall(emm.IsShown, emm)
        if ok and shown then return true end
    end
    if ns.EditMode and type(ns.EditMode.IsActive) == "function" then
        local ok, active = pcall(ns.EditMode.IsActive, ns.EditMode)
        if ok and active then return true end
    end
    return false
end

local function itemAuraSpellIDs(item, out)
    out = out or {}
    if type(item) ~= "table" then return out end
    local cdInfo = item.cooldownInfo
    if type(cdInfo) ~= "table" then return out end
    local function add(v)
        if _IsUsableSID(v) then
            for i = 1, #out do if out[i] == v then return end end
            out[#out + 1] = v
        end
    end
    add(cdInfo.spellID)
    add(cdInfo.overrideSpellID)
    if type(cdInfo.linkedSpellIDs) == "table" then
        for i = 1, #cdInfo.linkedSpellIDs do add(cdInfo.linkedSpellIDs[i]) end
    end
    return out
end

local function itemRuntimeActive(item)
    if type(item) ~= "table" then return false end
    if item.auraInstanceID ~= nil then return true end
    if C_UnitAuras then
        local ids = itemAuraSpellIDs(item)
        local hasTarget = UnitExists and UnitExists("target")
        for i = 1, #ids do
            local sid = ids[i]
            if C_UnitAuras.GetPlayerAuraBySpellID then
                local ok, ad = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
                if ok and ad ~= nil then return true end
            end
            if hasTarget and C_UnitAuras.GetUnitAuraBySpellID then
                local ok, ad = pcall(C_UnitAuras.GetUnitAuraBySpellID, "target", sid)
                if ok and ad ~= nil then return true end
            elseif hasTarget and C_UnitAuras.GetAuraDataBySpellID then
                local ok, ad = pcall(C_UnitAuras.GetAuraDataBySpellID, "target", sid, "HARMFUL")
                if ok and ad ~= nil then return true end
            end
        end
    end
    if item.preferredTotemUpdateSlot ~= nil then return true end
    return false
end

local function pandemicHasAny(set)
    if type(set) ~= "table" then return false end
    for _ in pairs(set) do return true end
    return false
end

local function pandemicClassifyItem(item, opts)
    if type(item) ~= "table" then return "default-reject" end
    local cdID = tonumber(item.cooldownID)
    if not cdID then return "default-reject" end

    local only = opts and opts.only
    if pandemicHasAny(only) then
        if only[cdID] then return "only" end
        return "skip"
    end

    local skip = opts and opts.skip
    if type(skip) == "table" and skip[cdID] then return "skip" end

    local okU, unit = pcall(function() return item.auraDataUnit end)
    if not okU or type(unit) ~= "string" then return "default-reject" end
    if isSecret(unit) then return "default-reject" end
    if unit ~= "target" and unit ~= "focus" then return "default-reject" end

    local aiID = item.auraInstanceID
    if aiID == nil then return "default-reject" end
    if isSecret(aiID) then return "default-reject" end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID) then
        return "default-reject"
    end
    local okData, aData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, aiID)
    if not okData or type(aData) ~= "table" then return "default-reject" end
    if aData.isHarmful == true then return "default-pass" end
    return "default-reject"
end

local readBlizzardPandemic

local resolveGlowTarget
local applyAuraGlow

local ensurePandemicGlow

local function safeTruthy(v)
    if v == nil then return false end
    if isSecret and isSecret(v) then return false end
    return v == true
end

local _pandemicAlphaCurve = {}
local _pandemicAlphaCurveFailed = false

local function ensurePandemicAlphaCurve(threshold)
    local thr = tonumber(threshold) or 0.30
    if thr > 1 then thr = thr / 100 end
    if thr < 0.01 then thr = 0.01 end
    if thr > 0.99 then thr = 0.99 end
    local key = math.floor(thr * 100 + 0.5)
    local cached = _pandemicAlphaCurve[key]
    if cached then return cached, key end
    if _pandemicAlphaCurveFailed then return nil end

    if InCombatLockdown and InCombatLockdown() then
        local bestKey, bestDist
        for k in pairs(_pandemicAlphaCurve) do
            local d = (k > key) and (k - key) or (key - k)
            if bestDist == nil or d < bestDist then
                bestDist, bestKey = d, k
            end
        end
        if bestKey then return _pandemicAlphaCurve[bestKey], bestKey end
        return nil
    end

    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then
        _pandemicAlphaCurveFailed = true
        dwarn("pandemic secret-visual: C_CurveUtil.CreateColorCurve unavailable")
        return nil
    end
    if not (Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step ~= nil) then
        _pandemicAlphaCurveFailed = true
        dwarn("pandemic secret-visual: Enum.LuaCurveType.Step unavailable")
        return nil
    end
    local okC, curve = pcall(C_CurveUtil.CreateColorCurve)
    if not okC or not curve then
        if not Auras._curveBuildFailLogged then
            Auras._curveBuildFailLogged = true
            dwarn("pandemic secret-visual: CreateColorCurve failed err=%s (will retry out of combat)", tostring(curve))
        end
        return nil
    end
    local ok1 = pcall(curve.SetType, curve, Enum.LuaCurveType.Step)
    local thrX = key / 100
    local ok2 = pcall(curve.AddPoint, curve, 0,    CreateColor(1, 0.6, 0, 1))
    local ok3 = pcall(curve.AddPoint, curve, thrX, CreateColor(1, 0.6, 0, 0))
    if not (ok1 and ok2 and ok3) then
        if not Auras._curveBuildFailLogged then
            Auras._curveBuildFailLogged = true
            dwarn("pandemic secret-visual: curve setup failed (will retry out of combat)")
        end
        return nil
    end
    _pandemicAlphaCurve[key] = curve
    local pts = Auras._curvePoints
    if not pts then
        pts = {}
        Auras._curvePoints = pts
    end
    pts[key] = thrX
    return curve, key
end

function Auras._ensureTwoZoneCurve(threshold, pOpts, aOpts)
    if type(aOpts) ~= "table" then return nil end
    local thr = tonumber(threshold) or 0.30
    if thr > 1 then thr = thr / 100 end
    if thr < 0.01 then thr = 0.01 end
    if thr > 0.99 then thr = 0.99 end
    local tk = math.floor(thr * 100 + 0.5)
    local function q(v, d)
        local n = tonumber(v) or d
        if n < 0 then n = 0 end
        if n > 1 then n = 1 end
        return math.floor(n * 100 + 0.5)
    end
    local pr  = q(pOpts and pOpts.colorR, 1.0)
    local pg2 = q(pOpts and pOpts.colorG, 0.6)
    local pb  = q(pOpts and pOpts.colorB, 0.0)
    local ar  = q(aOpts.colorR, 1.0)
    local ag2 = q(aOpts.colorG, 0.6)
    local ab  = q(aOpts.colorB, 0.0)
    local aa  = q(aOpts.colorA, 0.9)
    local key = tk .. "|" .. pr .. "," .. pg2 .. "," .. pb
        .. "|" .. ar .. "," .. ag2 .. "," .. ab .. "," .. aa
    local cache = Auras._twoZoneCurves
    if not cache then
        cache = {}
        Auras._twoZoneCurves = cache
    end
    local cached = cache[key]
    if cached then return cached, key end
    if InCombatLockdown and InCombatLockdown() then return nil end
    if _pandemicAlphaCurveFailed then return nil end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then return nil end
    if not (Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step ~= nil) then return nil end
    if (Auras._twoZoneCurveCount or 0) >= 64 then return nil end
    local okC, curve = pcall(C_CurveUtil.CreateColorCurve)
    if not okC or not curve then return nil end
    local thrX = tk / 100
    local ok1 = pcall(curve.SetType, curve, Enum.LuaCurveType.Step)
    local ok2 = pcall(curve.AddPoint, curve, 0,
        CreateColor(pr / 100, pg2 / 100, pb / 100, 1))
    local ok3 = pcall(curve.AddPoint, curve, thrX,
        CreateColor(ar / 100, ag2 / 100, ab / 100, aa / 100))
    if not (ok1 and ok2 and ok3) then return nil end
    cache[key] = curve
    Auras._twoZoneCurveCount = (Auras._twoZoneCurveCount or 0) + 1
    return curve, key
end

function Auras._ensureSecAlphaCurve(thresholdSecs)
    local thr = tonumber(thresholdSecs)
    if not thr or thr <= 0 then return nil end
    if thr < 0.1 then thr = 0.1 end
    if thr > 300 then thr = 300 end
    local k = math.floor(thr * 10 + 0.5)
    local cache = Auras._secAlphaCurves
    if not cache then
        cache = {}
        Auras._secAlphaCurves = cache
    end
    local cached = cache[k]
    if cached then return cached, "S" .. k end
    if InCombatLockdown and InCombatLockdown() then return nil end
    if _pandemicAlphaCurveFailed then return nil end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then return nil end
    if not (Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step ~= nil) then return nil end
    if (Auras._secAlphaCurveCount or 0) >= 64 then return nil end
    local okC, curve = pcall(C_CurveUtil.CreateColorCurve)
    if not okC or not curve then return nil end
    local ok1 = pcall(curve.SetType, curve, Enum.LuaCurveType.Step)
    local thrX = k / 10
    local ok2 = pcall(curve.AddPoint, curve, 0,    CreateColor(1, 0.6, 0, 1))
    local ok3 = pcall(curve.AddPoint, curve, thrX, CreateColor(1, 0.6, 0, 0))
    if not (ok1 and ok2 and ok3) then return nil end
    cache[k] = curve
    Auras._secAlphaCurveCount = (Auras._secAlphaCurveCount or 0) + 1
    return curve, "S" .. k
end

function Auras._ensureTwoZoneSecCurve(thresholdSecs, pOpts, aOpts)
    if type(aOpts) ~= "table" then return nil end
    local thr = tonumber(thresholdSecs)
    if not thr or thr <= 0 then return nil end
    if thr < 0.1 then thr = 0.1 end
    if thr > 300 then thr = 300 end
    local tk = math.floor(thr * 10 + 0.5)
    local function q(v, d)
        local n = tonumber(v) or d
        if n < 0 then n = 0 end
        if n > 1 then n = 1 end
        return math.floor(n * 100 + 0.5)
    end
    local pr  = q(pOpts and pOpts.colorR, 1.0)
    local pg2 = q(pOpts and pOpts.colorG, 0.6)
    local pb  = q(pOpts and pOpts.colorB, 0.0)
    local ar  = q(aOpts.colorR, 1.0)
    local ag2 = q(aOpts.colorG, 0.6)
    local ab  = q(aOpts.colorB, 0.0)
    local aa  = q(aOpts.colorA, 0.9)
    local key = "S" .. tk .. "|" .. pr .. "," .. pg2 .. "," .. pb
        .. "|" .. ar .. "," .. ag2 .. "," .. ab .. "," .. aa
    local cache = Auras._twoZoneSecCurves
    if not cache then
        cache = {}
        Auras._twoZoneSecCurves = cache
    end
    local cached = cache[key]
    if cached then return cached, key end
    if InCombatLockdown and InCombatLockdown() then return nil end
    if _pandemicAlphaCurveFailed then return nil end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then return nil end
    if not (Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step ~= nil) then return nil end
    if (Auras._twoZoneSecCurveCount or 0) >= 64 then return nil end
    local okC, curve = pcall(C_CurveUtil.CreateColorCurve)
    if not okC or not curve then return nil end
    local thrX = tk / 10
    local ok1 = pcall(curve.SetType, curve, Enum.LuaCurveType.Step)
    local ok2 = pcall(curve.AddPoint, curve, 0,
        CreateColor(pr / 100, pg2 / 100, pb / 100, 1))
    local ok3 = pcall(curve.AddPoint, curve, thrX,
        CreateColor(ar / 100, ag2 / 100, ab / 100, aa / 100))
    if not (ok1 and ok2 and ok3) then return nil end
    cache[key] = curve
    Auras._twoZoneSecCurveCount = (Auras._twoZoneSecCurveCount or 0) + 1
    return curve, key
end

function Auras:PrebuildPandemicCurves()
    if InCombatLockdown and InCombatLockdown() then return end
    ensurePandemicAlphaCurve(0.30)
    local po = pandemicOpts(self)
    if po and po.threshold ~= nil then
        ensurePandemicAlphaCurve(po.threshold)
    end
    if ns.GetProfile and ns.savedVarsReady then
        local ok, p = pcall(ns.GetProfile, ns)
        if ok and type(p) == "table" and type(p.auras) == "table" then
            for _, ap in pairs(p.auras) do
                if type(ap) == "table" and type(ap.glow) == "table" then
                    local g = ap.glow.pandemic
                    if type(g) == "table" and g.userSet == true and g.threshold ~= nil then
                        ensurePandemicAlphaCurve(g.threshold)
                    end
                end
            end
        end
    end

    local pandSets = {}
    local activeSets = {}
    pandSets[#pandSets + 1] = {
        threshold = (po and po.threshold) or 0.30,
        colorR = po and po.colorR, colorG = po and po.colorG,
        colorB = po and po.colorB,
    }
    local agI = activeGlowOpts(self, "icon")
    if agI and agI.enabled == true then activeSets[#activeSets + 1] = agI end
    local agB = activeGlowOpts(self, "bar")
    if agB and agB.enabled == true then activeSets[#activeSets + 1] = agB end
    if ns.GetProfile and ns.savedVarsReady then
        local ok, p = pcall(ns.GetProfile, ns)
        if ok and type(p) == "table" and type(p.auras) == "table" then
            for _, ap in pairs(p.auras) do
                if type(ap) == "table" and type(ap.glow) == "table" then
                    local gp = ap.glow.pandemic
                    if type(gp) == "table" and gp.userSet == true and gp.enabled == true then
                        local c = type(gp.color) == "table" and gp.color or nil
                        pandSets[#pandSets + 1] = {
                            threshold = tonumber(gp.threshold)
                                or (po and tonumber(po.threshold)) or 0.30,
                            colorR = c and tonumber(c[1]) or 1.0,
                            colorG = c and tonumber(c[2]) or 0.35,
                            colorB = c and tonumber(c[3]) or 0.1,
                        }
                    end
                    local ga = ap.glow.activeAura
                    if type(ga) == "table" and ga.enabled == true then
                        local c = type(ga.color) == "table" and ga.color or nil
                        activeSets[#activeSets + 1] = {
                            colorR = c and tonumber(c[1]) or 0.4,
                            colorG = c and tonumber(c[2]) or 0.8,
                            colorB = c and tonumber(c[3]) or 1.0,
                            colorA = c and tonumber(c[4]) or 1.0,
                        }
                    end
                end
            end
        end
    end
    for i = 1, #pandSets do
        for j = 1, #activeSets do
            Auras._ensureTwoZoneCurve(pandSets[i].threshold, pandSets[i], activeSets[j])
        end
    end

    for _, rec in pairs(spellDurationCache) do
        local base = type(rec) == "table" and tonumber(rec.base) or nil
        if base and base > 0 then
            for i = 1, #pandSets do
                local thr = tonumber(pandSets[i].threshold) or 0.30
                if thr > 1 then thr = thr / 100 end
                if thr < 0.01 then thr = 0.01 end
                if thr > 0.99 then thr = 0.99 end
                local secs = base * thr
                Auras._ensureSecAlphaCurve(secs)
                for j = 1, #activeSets do
                    Auras._ensureTwoZoneSecCurve(secs, pandSets[i], activeSets[j])
                end
            end
        end
    end
end

function Auras.RecordGlow(slot, source, detail)
    if type(slot) ~= "table" then return end
    local rec = slot._glowLast
    if not rec then
        rec = {}
        slot._glowLast = rec
    end
    rec.src = source
    rec.detail = detail
    rec.at = (GetTime and GetTime()) or 0
end

function Auras.RecordActiveGlowEval(slot, reason)
    if type(slot) ~= "table" then return end
    local rec = slot._agEval
    if not rec then
        rec = {}
        slot._agEval = rec
    end
    rec.reason = reason
    rec.at = (GetTime and GetTime()) or 0
end

function Auras._resetSecretVisualOverlay(g)
    if not g then return end
    if g._pandemicMode == "two-zone" and g.edges then
        for i = 1, #g.edges do
            pcall(g.edges[i].SetVertexColor, g.edges[i], 1, 1, 1, 1)
        end
    end
    g._pandemicMode = nil
    g._twoZoneKey = nil
    g._pandemicAlphaR, g._pandemicAlphaG, g._pandemicAlphaB = nil, nil, nil
end

local function applySecretPandemicVisual(slot, durObj, opts, activeOpts, thresholdSecs)
    if not slot then return false end
    if not isSecret(durObj) then
        if durObj == nil then return false end
        local dt = type(durObj)
        if dt ~= "table" and dt ~= "userdata" then return false end
        if dt == "table" and type(durObj.EvaluateRemainingPercent) ~= "function" then
            return false
        end
    end

    if activeOpts ~= nil then
        local secsMode = false
        local curve2, key2
        if type(thresholdSecs) == "number" and thresholdSecs > 0 then
            curve2, key2 = Auras._ensureTwoZoneSecCurve(thresholdSecs, opts, activeOpts)
            secsMode = curve2 ~= nil
        end
        if not curve2 then
            curve2, key2 = Auras._ensureTwoZoneCurve(opts and opts.threshold, opts, activeOpts)
        end
        if curve2 then
            local g2 = ensurePandemicGlow(slot)
            if not g2 then return false end
            local okEv, cr, cg2, cb, ca = pcall(function()
                local result
                if secsMode then
                    result = durObj:EvaluateRemainingDuration(curve2)
                else
                    result = durObj:EvaluateRemainingPercent(curve2)
                end
                return result.r, result.g, result.b, result.a
            end)
            if okEv and ca ~= nil
               and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
                local okZ, a2 = pcall(function()
                    return C_CurveUtil.EvaluateColorValueFromBoolean(durObj:IsZero(), 0, ca)
                end)
                if okZ and a2 ~= nil then ca = a2 end
            end
            if not okEv or ca == nil then
                pcall(g2.Hide, g2)
                Auras._resetSecretVisualOverlay(g2)
                Auras.RecordGlow(slot, "pandemic-secret",
                    "two-zone-eval-failed: " .. tostring(okEv and "nil-color" or cr))
                return false
            end
            local needsSetup = g2._pandemicMode ~= "two-zone" or g2._twoZoneKey ~= key2
            if needsSetup then
                if g2.animGroup and g2.animGroup.IsPlaying and g2.animGroup:IsPlaying() then
                    pcall(g2.animGroup.Stop, g2.animGroup)
                end
                if g2.edges then
                    for i = 1, #g2.edges do
                        g2.edges[i]:SetColorTexture(1, 1, 1, 1)
                    end
                end
                g2:SetAlpha(1)
                g2._pandemicMode = "two-zone"
                g2._twoZoneKey = key2
                g2._pandemicAlphaR, g2._pandemicAlphaG, g2._pandemicAlphaB = nil, nil, nil
                slot._auraGlowActive = nil
                slot._auraGlowKind   = nil
                slot._auraGlowR, slot._auraGlowG, slot._auraGlowB, slot._auraGlowA = nil, nil, nil, nil
            end
            if g2.edges then
                for i = 1, #g2.edges do
                    g2.edges[i]:SetVertexColor(cr, cg2, cb, ca)
                end
            end
            if needsSetup then
                g2:Show()
            end
            Auras.RecordGlow(slot, "pandemic-secret",
                "two-zone-curve key=" .. tostring(key2))
            return true, "two-zone"
        end
    end

    local secsAlpha = false
    local curve, curveKey
    if type(thresholdSecs) == "number" and thresholdSecs > 0 then
        curve, curveKey = Auras._ensureSecAlphaCurve(thresholdSecs)
        secsAlpha = curve ~= nil
    end
    if not curve then
        curve, curveKey = ensurePandemicAlphaCurve(opts and opts.threshold)
    end
    if not curve then
        local g0 = slot.pandemicGlow
        if g0 and g0._pandemicMode then
            pcall(g0.Hide, g0)
            Auras._resetSecretVisualOverlay(g0)
        end
        Auras.RecordGlow(slot, "pandemic-secret", "no-curve-available")
        return false
    end

    local g = ensurePandemicGlow(slot)
    if not g then return false end

    local okEv, alpha = pcall(function()
        local result
        if secsAlpha then
            result = durObj:EvaluateRemainingDuration(curve)
        else
            result = durObj:EvaluateRemainingPercent(curve)
        end
        return result.a
    end)
    if okEv and alpha ~= nil
       and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local okZ, a2 = pcall(function()
            return C_CurveUtil.EvaluateColorValueFromBoolean(durObj:IsZero(), 0, alpha)
        end)
        if okZ and a2 ~= nil then alpha = a2 end
    end
    if not okEv or alpha == nil then
        pcall(g.Hide, g)
        Auras._resetSecretVisualOverlay(g)
        Auras.RecordGlow(slot, "pandemic-secret",
            "eval-failed: " .. tostring(okEv and "nil-alpha" or alpha))
        return false
    end

    local r  = opts and tonumber(opts.colorR) or 1.0
    local gg = opts and tonumber(opts.colorG) or 0.6
    local b  = opts and tonumber(opts.colorB) or 0.0
    local needsSetup = g._pandemicMode ~= "alpha"
        or g._pandemicAlphaR ~= r
        or g._pandemicAlphaG ~= gg
        or g._pandemicAlphaB ~= b
    if needsSetup then
        if g.animGroup and g.animGroup.IsPlaying and g.animGroup:IsPlaying() then
            pcall(g.animGroup.Stop, g.animGroup)
        end
        if g.edges then
            for i = 1, #g.edges do
                g.edges[i]:SetVertexColor(1, 1, 1, 1)
                g.edges[i]:SetColorTexture(r, gg, b, 1)
            end
        end
        g._pandemicMode = "alpha"
        g._twoZoneKey = nil
        g._pandemicAlphaR, g._pandemicAlphaG, g._pandemicAlphaB = r, gg, b
        slot._auraGlowActive = nil
        slot._auraGlowKind   = nil
        slot._auraGlowR, slot._auraGlowG, slot._auraGlowB, slot._auraGlowA = nil, nil, nil, nil
    end

    g:SetAlpha(alpha)
    if needsSetup then
        g:Show()
    end
    Auras.RecordGlow(slot, "pandemic-secret",
        string.format("alpha-curve key=%s color=%.2f/%.2f/%.2f",
            tostring(curveKey), r, gg, b))
    return true, "alpha"
end

function Auras._secretVisualActiveOpts(item, agOpts)
    local aiID = type(item) == "table" and item.auraInstanceID or nil
    if isSecret(aiID) or aiID == nil then return nil end
    local perOn, perOpts = Auras._resolveActiveGlowSticky(item)
    if perOn == false then return nil end
    if perOn == true then return perOpts end
    if agOpts and agOpts.enabled == true then return agOpts end
    return nil
end

local function clearSecretPandemicVisual(slot)
    if not slot then return end
    local g = slot.pandemicGlow
    if not g then return end
    if g._pandemicMode then
        g:SetAlpha(1)
        Auras._resetSecretVisualOverlay(g)
        pcall(g.Hide, g)
    end
end

local function evaluatePandemicForItem(item, opts, kind)
    if type(opts) ~= "table" or opts.enabled == false then return false, "none", nil end
    if type(item) ~= "table" then return false, "none", nil end

    local cdID = tonumber(item.cooldownID)
    if not cdID then return false, "none", nil end

    local aiID = item.auraInstanceID
    if aiID == nil then
        local st = pandemicState[cdID]
        if st then
            st.inWindow = false
            st.refreshedAt = nil
            st.source = "none"
        end
        return false, "none", nil
    end
    if isSecret(aiID) then
        pandemicLogOnce(cdID, "auraInstanceID secret")
        return false, "none", nil
    end

    local classification = pandemicClassifyItem(item, opts)
    local stEarly = pandemicState[cdID]
    if not stEarly then
        stEarly = { inWindow = false, lastPct = nil, lastEvalAt = 0,
                    refreshedAt = nil, suppressedUntil = 0, kind = kind }
        pandemicState[cdID] = stEarly
    elseif kind and stEarly.kind ~= kind then
        stEarly.kind = kind
    end
    stEarly.classification = classification
    if classification == "skip" or classification == "default-reject" then
        stEarly.inWindow = false
        stEarly.source = "none"
        return false, "none", nil
    end

    local bizNow = readBlizzardPandemic(item)
    stEarly.bizPandemic = bizNow
    if bizNow then
        stEarly.bizPandemicAt = GetTime()
    end
    if bizNow then
        local now = GetTime()
        if stEarly.suppressedUntil and now < stEarly.suppressedUntil then
            stEarly.source = "none"
            return false, "none", nil
        end
        stEarly.inWindow = true
        stEarly.source = "blizzard-icon"
        return true, "blizzard-icon", nil
    end

    local pSpellID = getPandemicSpellID(item)
    do
        local okC, cInfo = pcall(function() return item.cooldownInfo end)
        if okC and type(cInfo) == "table" then
            local okS, sid = pcall(function() return cInfo.spellID end)
            if okS and isSecret(sid) then
                pandemicLogOnce(cdID, "cooldownInfo.spellID secret")
            end
        end
    end

    stEarly.comboLogSpellID  = nil
    stEarly.comboLogPct      = nil
    stEarly.comboLogAppliedAt = nil
    stEarly.comboLogDuration = nil

    if not (C_UnitAuras and C_UnitAuras.GetAuraDuration) then
        stEarly.source = "none"
        return false, "none", nil
    end

    local now = GetTime()
    local interval = tonumber(opts.evalInterval) or 0.1
    if interval < 0.05 then interval = 0.05 end

    local st = pandemicState[cdID]
    if not st then
        st = { inWindow = false, lastPct = nil, lastEvalAt = 0,
               refreshedAt = nil, suppressedUntil = 0, kind = kind }
        pandemicState[cdID] = st
    elseif kind and st.kind ~= kind then
        st.kind = kind
    end

    local suppressed = st.suppressedUntil and now < st.suppressedUntil

    local okU, unit = pcall(function() return item.auraDataUnit end)
    if not okU or type(unit) ~= "string" then unit = "player" end
    if isSecret(unit) then unit = "player" end

    if pSpellID and not isSecret(pSpellID)
       and not (InCombatLockdown and InCombatLockdown())
       and C_UnitAuras.GetAuraBaseDuration
    then
        local recB = spellDurationCache[pSpellID]
        if not (type(recB) == "table" and recB.src == "base-api") then
            local okB, baseD = pcall(C_UnitAuras.GetAuraBaseDuration, unit, aiID, pSpellID)
            if okB and type(baseD) == "number" and not isSecret(baseD) and baseD > 0 then
                Auras._noteSpellBaseDuration(pSpellID, baseD, "base-api")
            end
        end
    end

    local thrSecs, baseDur, baseSrc = Auras._pandemicThresholdSeconds(item, opts, pSpellID)
    st.thresholdSecs, st.baseDur, st.baseSrc = thrSecs, baseDur, baseSrc

    local okDur, dur = pcall(C_UnitAuras.GetAuraDuration, unit, aiID)

    if okDur and ns._auraPresentTruthy(dur) then
        local hs = isSecret(dur)
        if not hs then
            local okHS, v = pcall(function() return dur:HasSecretValues() end)
            hs = okHS and v == true
        end
        if hs and not suppressed then
            st.source = "secret-visual"
            st.lastDurObj = dur
            return false, "secret-visual", dur
        end
    end

    if not (okDur and dur) then
        if not okDur then
            pandemicLogOnce(cdID, "GetAuraDuration errored",
                "unit=" .. tostring(unit) .. " err=" .. tostring(dur))
        else
            pandemicLogOnce(cdID, "GetAuraDuration returned nil",
                "unit=" .. tostring(unit) .. " aiID=" .. tostring(aiID))
        end
        st.inWindow = false
        st.source = "none"
        if suppressed then return false, "none", nil end
        return false, "none", nil
    end

    if now - (st.lastEvalAt or 0) >= interval then
        st.lastEvalAt = now
        if type(dur.GetRemainingPercent) == "function" then
            if pSpellID and not isSecret(pSpellID)
               and type(dur.GetTotalDuration) == "function"
            then
                local okT, total = pcall(dur.GetTotalDuration, dur)
                if okT and type(total) == "number" and not isSecret(total)
                   and total > 0
                then
                    Auras._noteSpellBaseDuration(pSpellID, total, "ooc-total")
                end
            end
            local okPct, pct = pcall(dur.GetRemainingPercent, dur)
            if okPct and type(pct) == "number" and not isSecret(pct) then
                local threshold = tonumber(opts.threshold) or 0.30
                if threshold > 1 then threshold = threshold / 100 end
                if threshold < 0 then threshold = 0 elseif threshold > 1 then threshold = 1 end

                local newInWindow = pct > 0 and pct <= threshold
                if thrSecs and type(dur.GetRemainingDuration) == "function" then
                    local okR2, rem2 = pcall(dur.GetRemainingDuration, dur)
                    if okR2 and type(rem2) == "number" and not isSecret(rem2) then
                        newInWindow = rem2 > 0 and rem2 <= thrSecs
                        st.secondsBased = true
                    else
                        st.secondsBased = false
                    end
                else
                    st.secondsBased = false
                end
                local prevInWindow = st.inWindow

                if not prevInWindow and newInWindow then
                    st.refreshedAt = now
                elseif prevInWindow and not newInWindow then
                    local grace = tonumber(opts.graceSuppress) or 0.3
                    if grace < 0 then grace = 0 end
                    st.suppressedUntil = now + grace
                    suppressed = true
                end

                st.inWindow = newInWindow
                st.lastPct = pct
            else
                if not okPct then
                    pandemicLogOnce(cdID, "GetRemainingPercent errored",
                        "err=" .. tostring(pct))
                elseif type(pct) ~= "number" then
                    pandemicLogOnce(cdID, "GetRemainingPercent non-number",
                        "type=" .. type(pct))
                else
                    pandemicLogOnce(cdID, "GetRemainingPercent secret unexpectedly")
                    st.source = "secret-visual"
                    st.lastDurObj = dur
                    return false, "secret-visual", dur
                end
                st.inWindow = false
            end
        else
            local okR, rem   = pcall(dur.GetRemainingDuration, dur)
            local okT, total = pcall(dur.GetTotalDuration, dur)
            if okR and okT and type(rem) == "number" and type(total) == "number"
               and not isSecret(rem) and not isSecret(total) and total > 0 then
                if pSpellID and not isSecret(pSpellID) then
                    Auras._noteSpellBaseDuration(pSpellID, total, "ooc-total")
                end
                local pct = rem / total
                if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
                local threshold = tonumber(opts.threshold) or 0.30
                if threshold > 1 then threshold = threshold / 100 end
                if threshold < 0 then threshold = 0 elseif threshold > 1 then threshold = 1 end
                local newInWindow = pct > 0 and pct <= threshold
                if thrSecs then
                    newInWindow = rem > 0 and rem <= thrSecs
                    st.secondsBased = true
                else
                    st.secondsBased = false
                end
                local prevInWindow = st.inWindow
                if not prevInWindow and newInWindow then
                    st.refreshedAt = now
                elseif prevInWindow and not newInWindow then
                    local grace = tonumber(opts.graceSuppress) or 0.3
                    if grace < 0 then grace = 0 end
                    st.suppressedUntil = now + grace
                    suppressed = true
                end
                st.inWindow = newInWindow
                st.lastPct = pct
            else
                pandemicLogOnce(cdID, "no GetRemainingPercent + fallback failed")
                st.inWindow = false
            end
        end
    end

    if suppressed then
        st.source = "none"
        return false, "none", nil
    end
    if st.inWindow == true then
        st.source = "duration-percent"
        return true, "duration-percent", nil
    end
    st.source = "duration-percent"
    return false, "duration-percent", nil
end

ensurePandemicGlow = function(slot)
    if not (slot and slot.bar) then return nil end
    if slot.pandemicGlow then return slot.pandemicGlow end

    local g = CreateFrame("Frame", nil, slot.bar)
    g:SetFrameLevel((slot.bar:GetFrameLevel() or 1) + 5)
    g:SetAllPoints(slot.bar)
    g:Hide()

    local function makeEdge(layer, anchorA, anchorB)
        local t = g:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 0.6, 0, 0.9)
        if layer == "TOP" then
            t:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
            t:SetPoint("TOPRIGHT", g, "TOPRIGHT", 0, 0)
            t:SetHeight(1.5)
        elseif layer == "BOTTOM" then
            t:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", 0, 0)
            t:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 0, 0)
            t:SetHeight(1.5)
        elseif layer == "LEFT" then
            t:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
            t:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", 0, 0)
            t:SetWidth(1.5)
        elseif layer == "RIGHT" then
            t:SetPoint("TOPRIGHT", g, "TOPRIGHT", 0, 0)
            t:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 0, 0)
            t:SetWidth(1.5)
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

    slot.pandemicGlow = g
    return g
end

resolveGlowTarget = function(slot)
    if type(slot) ~= "table" then return nil end
    return slot.bar or slot.frame or slot.button or slot.icon
end

function Auras._clearEdgeGlow(slot)
    local pg = slot and slot.pandemicGlow
    if not pg then return end
    if pg.animGroup and pg.animGroup:IsPlaying() then
        pcall(pg.animGroup.Stop, pg.animGroup)
    end
    Auras._resetSecretVisualOverlay(pg)
    pg:SetAlpha(1)
    pcall(pg.Hide, pg)
end

function Auras._stopSlotGlowFX(slot)
    if not (slot and ns.GlowFX) then return end
    local f = resolveGlowTarget(slot)
    if not f then return end
    pcall(ns.GlowFX.Stop, ns.GlowFX, f)
end

function Auras._activeGlowFXName(style)
    if type(style) ~= "string" then return nil end
    local fx = style:match("^fx_(.+)$")
    if fx and fx ~= "" then return fx end
    return nil
end

function Auras._releaseSlotGlowFX(slot)
    if not slot then return end
    Auras._stopSlotGlowFX(slot)
    if slot._auraGlowRenderer == "fx" then
        slot._auraGlowActive   = nil
        slot._auraGlowRenderer = nil
        slot._auraGlowFXName   = nil
    end
end

local function applyGlowInternal(slot, active, opts, kind)
    if not slot then return end
    local r  = opts and tonumber(opts.colorR) or 1.0
    local gg = opts and tonumber(opts.colorG) or 0.6
    local b  = opts and tonumber(opts.colorB) or 0.0
    local a  = opts and tonumber(opts.colorA) or 0.9
    local style = ((kind == "active" or kind == "pandemic") and opts
                   and type(opts.style) == "string") and opts.style or nil
    local fxName = Auras._activeGlowFXName(style)
    local renderer = fxName and "fx" or "edge"

    if slot._auraGlowActive == active
       and slot._auraGlowKind == kind
       and slot._auraGlowR == r and slot._auraGlowG == gg
       and slot._auraGlowB == b and slot._auraGlowA == a
       and slot._auraGlowRenderer == renderer
       and slot._auraGlowFXName == fxName then
        return
    end

    if slot._auraGlowRenderer == "fx" and (renderer ~= "fx" or not active) then
        Auras._stopSlotGlowFX(slot)
    end
    if slot._auraGlowRenderer == "edge" and (renderer ~= "edge" or not active) then
        Auras._clearEdgeGlow(slot)
    end

    slot._auraGlowActive = active
    slot._auraGlowKind   = kind
    slot._auraGlowR, slot._auraGlowG, slot._auraGlowB, slot._auraGlowA = r, gg, b, a
    slot._auraGlowRenderer = active and renderer or nil
    slot._auraGlowFXName   = active and fxName or nil

    Auras.RecordGlow(slot,
        active and ("pulse-" .. tostring(kind) .. (style and (":" .. style) or "")) or "off",
        string.format("color=%.2f/%.2f/%.2f/%.2f", r, gg, b, a))

    if not active then
        Auras._clearEdgeGlow(slot)
        Auras._stopSlotGlowFX(slot)
        return
    end

    if renderer == "fx" then
        Auras._clearEdgeGlow(slot)
        local f = resolveGlowTarget(slot)
        if f and ns.GlowFX then
            pcall(ns.GlowFX.Start, ns.GlowFX, f, fxName, {
                colorR = r, colorG = gg, colorB = b, colorA = a,
                alpha  = a,
                owner  = "active",
            })
        end
        return
    end

    local g = ensurePandemicGlow(slot)
    if not g then return end
    if g._pandemicMode then
        Auras._resetSecretVisualOverlay(g)
        g:SetAlpha(1)
    end
    if g.edges then
        for i = 1, #g.edges do
            g.edges[i]:SetColorTexture(r, gg, b, a)
        end
    end
    g:EnableMouse(false)
    g:Show()
    if g.animGroup and not g.animGroup:IsPlaying() then
        g.animGroup:Play()
    end
end

local function applyPandemicGlow(slot, active, opts)
    applyGlowInternal(slot, active, opts, "pandemic")
end

applyAuraGlow = function(slot, active, opts)
    local mergedOpts
    if opts then
        mergedOpts = opts
    else
        mergedOpts = { colorR = 1.0, colorG = 0.85, colorB = 0.3, colorA = 0.85 }
    end
    applyGlowInternal(slot, active, mergedOpts, "active")
end

local function wipeAllGlowState()
    local function wipeSlot(slot)
        if not slot then return end
        pcall(Auras._stopSlotGlowFX, slot)
        slot._auraGlowActive   = nil
        slot._auraGlowKind     = nil
        slot._auraGlowRenderer = nil
        slot._auraGlowFXName   = nil
        slot._auraGlowR, slot._auraGlowG, slot._auraGlowB, slot._auraGlowA = nil, nil, nil, nil
        local pg = slot.pandemicGlow
        if pg then
            if pg.animGroup and pg.animGroup.IsPlaying and pg.animGroup:IsPlaying() then
                pcall(pg.animGroup.Stop, pg.animGroup)
            end
            Auras._resetSecretVisualOverlay(pg)
            pcall(pg.Hide, pg)
        end
    end
    if Auras.BarDisplay and Auras.BarDisplay.bars then
        for i = 1, #Auras.BarDisplay.bars do wipeSlot(Auras.BarDisplay.bars[i]) end
    end
    if Auras.IconDisplay and Auras.IconDisplay.icons then
        for i = 1, #Auras.IconDisplay.icons do
            local w = Auras.IconDisplay.icons[i]
            if w then wipeSlot(w._pandemicSlot) end
        end
    end
end

local function ensurePandemicGlowIcon(iconWidget)
    if not iconWidget then return nil end
    local frame = iconWidget.frame or iconWidget
    if type(frame) ~= "table" then return nil end
    local pslot = iconWidget._pandemicSlot
    if not pslot then
        pslot = { bar = frame }
        iconWidget._pandemicSlot = pslot
    elseif pslot.bar ~= frame then
        pcall(Auras._releaseSlotGlowFX, pslot)
        if pslot.pandemicGlow then
            if pslot.pandemicGlow.animGroup
               and pslot.pandemicGlow.animGroup:IsPlaying() then
                pcall(pslot.pandemicGlow.animGroup.Stop, pslot.pandemicGlow.animGroup)
            end
            pcall(pslot.pandemicGlow.Hide, pslot.pandemicGlow)
            pcall(pslot.pandemicGlow.SetParent, pslot.pandemicGlow, nil)
        end
        pslot.bar = frame
        pslot.pandemicGlow = nil
    end
    ensurePandemicGlow(pslot)
    return pslot
end

local function resetPandemicState()
    wipe(pandemicState)
    wipe(_pandemicLogged)
    resetComboLogState()
end

readBlizzardPandemic = function(item)
    if type(item) ~= "table" then return false end

    local cdIDForLog = tonumber(item.cooldownID)

    if item.PandemicIcon ~= nil then
        if cdIDForLog then
            pandemicLogOnce(cdIDForLog, "PandemicIcon ~= nil -> true")
        end
        return true
    end

    local icon = item.PandemicIcon
    if icon ~= nil and type(icon) == "table" then
        if type(icon.IsShown) == "function" then
            local okS, sh = pcall(icon.IsShown, icon)
            if okS then
                if safeTruthy(sh) then return true end
                if isSecret and isSecret(sh) and cdIDForLog then
                    pandemicLogOnce(cdIDForLog, "ignored secret IsShown")
                end
            elseif cdIDForLog then
                pandemicLogOnce(cdIDForLog, "PandemicIcon:IsShown pcall failed",
                    tostring(sh))
            end
        end
        if type(icon.IsVisible) == "function" then
            local okV, vis = pcall(icon.IsVisible, icon)
            if okV then
                if safeTruthy(vis) then return true end
                if isSecret and isSecret(vis) and cdIDForLog then
                    pandemicLogOnce(cdIDForLog, "ignored secret IsVisible")
                end
            elseif cdIDForLog then
                pandemicLogOnce(cdIDForLog, "PandemicIcon:IsVisible pcall failed",
                    tostring(vis))
            end
        end
        return true
    end

    if type(item.IsInPandemicTime) == "function" then
        local okI, inT = pcall(item.IsInPandemicTime, item, GetTime())
        if okI then
            if safeTruthy(inT) then return true end
            if isSecret and isSecret(inT) and cdIDForLog then
                pandemicLogOnce(cdIDForLog, "ignored secret IsInPandemicTime")
            end
        elseif cdIDForLog then
            pandemicLogOnce(cdIDForLog, "IsInPandemicTime pcall failed",
                tostring(inT))
        end
    end

    local function tryShown(t)
        if type(t) ~= "table" then return false end
        if type(t.IsShown) == "function" then
            local ok, sh = pcall(t.IsShown, t)
            if ok and safeTruthy(sh) then return true end
        end
        if type(t.IsVisible) == "function" then
            local ok, vis = pcall(t.IsVisible, t)
            if ok and safeTruthy(vis) then return true end
        end
        return false
    end
    local function tryField(parent, fieldName)
        if type(parent) ~= "table" then return false end
        local ok, f = pcall(function() return parent[fieldName] end)
        if not ok then return false end
        if f ~= nil and fieldName == "PandemicIcon" then return true end
        return tryShown(f)
    end
    if tryField(item.Icon, "PandemicIcon") then return true end
    if tryField(item.Bar,  "PandemicIcon") then return true end
    if tryField(item,      "PandemicStateFrame") then return true end
    if tryField(item.Icon, "PandemicStateFrame") then return true end
    if tryField(item.Bar,  "PandemicStateFrame") then return true end

    local pStart = item.pandemicStartTime
    local pEnd   = item.pandemicEndTime
    if type(pStart) == "number" and type(pEnd) == "number"
       and not isSecret(pStart) and not isSecret(pEnd) then
        local now = GetTime()
        if now >= pStart and now <= pEnd then return true end
    end
    return false
end

local function installPandemicHooks() end

local viewerAuraMap        = {}
local viewerAuraAllMap     = {}
local viewerAuraMapDirty   = true

local BUFF_VIEWER_NAMES = {
    [ICON_VIEWER_NAME] = true,
    [BAR_VIEWER_NAME]  = true,
}

local function addViewerChildrenForMap(viewerName, multi)
    local viewer = getViewer(viewerName)
    if not viewer then return end
    local items = getItemFrames(viewer) or {}
    for i = 1, #items do
        local child = items[i]
        local cdInfo = type(child) == "table" and child.cooldownInfo or nil
        if cdInfo then
            local keys = {}
            local function addKey(k)
                if _IsUsableSID(k) then
                    keys[#keys + 1] = k
                end
            end
            addKey(cdInfo.spellID)
            addKey(cdInfo.overrideSpellID)
            addKey(cdInfo.overrideTooltipSpellID)
            if type(cdInfo.linkedSpellIDs) == "table" then
                for _, sid in ipairs(cdInfo.linkedSpellIDs) do
                    addKey(sid)
                end
            end
            for j = 1, #keys do
                local sid = keys[j]
                if viewerAuraMap[sid] == nil then
                    viewerAuraMap[sid] = child
                end
                if multi then
                    local list = viewerAuraAllMap[sid]
                    if not list then
                        list = {}
                        viewerAuraAllMap[sid] = list
                    end
                    local seen = false
                    for k = 1, #list do
                        if list[k] == child then seen = true break end
                    end
                    if not seen then
                        list[#list + 1] = child
                    end
                end
            end
        end
    end
end

local function rebuildViewerAuraMap()
    wipe(viewerAuraMap)
    wipe(viewerAuraAllMap)
    addViewerChildrenForMap(ICON_VIEWER_NAME, false)
    addViewerChildrenForMap(BAR_VIEWER_NAME, true)
    viewerAuraMapDirty = false
    if ns.Debug and ns.Debug.IsVerbose and ns.Debug:IsVerbose(AURAS_MODULE) then
        local n1, n2 = 0, 0
        for _ in pairs(viewerAuraMap) do n1 = n1 + 1 end
        for _ in pairs(viewerAuraAllMap) do n2 = n2 + 1 end
        dverbose("viewer-aura map rebuilt: %d keys, %d multi", n1, n2)
    end
end

function Auras:GetViewerChildBySpellID(spellID)
    if not spellID then return nil end
    if viewerAuraMapDirty then rebuildViewerAuraMap() end
    return viewerAuraMap[spellID]
end

function Auras:GetAllViewerChildrenBySpellID(spellID)
    if not spellID then return nil end
    if viewerAuraMapDirty then rebuildViewerAuraMap() end
    return viewerAuraAllMap[spellID]
end

function Auras:GetViewerAuraMapStats()
    if viewerAuraMapDirty then rebuildViewerAuraMap() end
    local single, multi = 0, 0
    for _ in pairs(viewerAuraMap) do single = single + 1 end
    for _ in pairs(viewerAuraAllMap) do multi = multi + 1 end
    return single, multi, viewerAuraMap, viewerAuraAllMap
end

function Auras:InvalidateViewerAuraMap()
    viewerAuraMapDirty = true
end

local function readChildCooldownID(child)
    if type(child) ~= "table" then return nil end
    local id = child.cooldownID
    if type(id) == "number" and id > 0 then return id end
    local cdInfo = child.cooldownInfo
    if type(cdInfo) == "table" then
        id = cdInfo.cooldownID
        if type(id) == "number" and id > 0 then return id end
    end
    local icon = child.Icon
    if type(icon) == "table" then
        id = icon.cooldownID
        if type(id) == "number" and id > 0 then return id end
    end
    if type(child.GetCooldownID) == "function" then
        local ok, gid = pcall(child.GetCooldownID, child)
        if ok and type(gid) == "number" and gid > 0 then return gid end
    end
    return nil
end

function Auras._childIsActiveSecretSafe(child)
    if type(child) ~= "table" then return nil end
    if child.auraInstanceID ~= nil then return true end
    local icon = child.Icon
    if type(icon) == "table" and icon.auraInstanceID ~= nil then return true end
    if type(child.IsActive) == "function" then
        local ok, active = pcall(child.IsActive, child)
        if ok then return active and true or false end
    end
    local sc = child.cooldownSwipeColor
    if sc and type(sc) ~= "number" and sc.GetRGBA then
        local r = sc:GetRGBA()
        if r and type(r) == "number" and not isSecret(r) then
            return r ~= 0
        end
    end
    local fieldActive
    local okF = pcall(function() fieldActive = child.isActive end)
    if okF then
        if isSecret(fieldActive) then
            return fieldActive and true or false
        elseif type(fieldActive) == "boolean" then
            return fieldActive
        end
    end
    return nil
end

local function childShownActive(child)
    if type(child) ~= "table" then return false end
    local active = Auras._childIsActiveSecretSafe(child)
    if active ~= nil then return active end
    if child.preferredTotemUpdateSlot ~= nil then return true end
    return false
end

local _viewerActiveSet      = {}
local _viewerActiveSetStamp = nil

viewerActiveCooldownIDSet = function(force)
    local now = (GetTime and GetTime()) or 0
    if not force and _viewerActiveSetStamp == now then
        return _viewerActiveSet
    end
    wipe(_viewerActiveSet)
    _viewerActiveSetStamp = now
    for vname in pairs(BUFF_VIEWER_NAMES) do
        local viewer = getViewer(vname)
        if viewer then
            local items = getItemFrames(viewer) or {}
            for i = 1, #items do
                local child = items[i]
                if childShownActive(child) then
                    local cdID = readChildCooldownID(child)
                    if cdID then _viewerActiveSet[cdID] = true end
                end
            end
        end
    end
    return _viewerActiveSet
end

function Auras:GetViewerActiveCooldownIDSet(force)
    return viewerActiveCooldownIDSet(force and true or false)
end

local _viewerReservedSet = {}
local _viewerReservedStamp = -1
local function viewerReservedCooldownIDSet(force)
    local now = (GetTime and GetTime()) or 0
    if not force and _viewerReservedStamp == now then
        return _viewerReservedSet
    end
    wipe(_viewerReservedSet)
    _viewerReservedStamp = now
    for vname in pairs(BUFF_VIEWER_NAMES) do
        local viewer = getViewer(vname)
        if viewer then
            local items = getItemFrames(viewer) or {}
            for i = 1, #items do
                local child = items[i]
                if itemHasCooldownID(child) then
                    local cdID = readChildCooldownID(child)
                    if cdID then _viewerReservedSet[cdID] = true end
                end
            end
        end
    end
    return _viewerReservedSet
end

function Auras:IsEntryCDMTracked(entry)
    if type(entry) ~= "table" then return false, "static" end
    local cdID = tonumber(entry.cooldownID)
    if not cdID then return false, "static" end
    local reserved = viewerReservedCooldownIDSet(false)
    if reserved and next(reserved) ~= nil then
        return reserved[cdID] == true, "live"
    end
    local info
    local ok = pcall(function()
        info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
    end)
    if ok and type(info) == "table" then
        return (not cdmHiddenByDefault(info)), "static"
    end
    return true, "static"
end

local DISPLAYTYPE_VIEWER_NAME = {
    TrackedIcon = ICON_VIEWER_NAME,
    icons       = ICON_VIEWER_NAME,
    TrackedBars = BAR_VIEWER_NAME,
    bars        = BAR_VIEWER_NAME,
}

local function findLiveViewerChildByCooldownID(cooldownID, displayType)
    if type(cooldownID) ~= "number" then return nil end
    local vname = DISPLAYTYPE_VIEWER_NAME[displayType]
    if not vname then return nil end
    local matchedInactive = false
    local poolCount = 0
    local function searchViewer(viewerName)
        local viewer = getViewer(viewerName)
        if not viewer then return nil end
        local items = getItemFrames(viewer) or {}
        poolCount = poolCount + #items
        for i = 1, #items do
            local child = items[i]
            if readChildCooldownID(child) == cooldownID then
                if childShownActive(child) then
                    return child
                end
                matchedInactive = true
            end
        end
        return nil
    end
    local child = searchViewer(vname)
    if not child then
        local otherName = (vname == BAR_VIEWER_NAME) and ICON_VIEWER_NAME or BAR_VIEWER_NAME
        child = searchViewer(otherName)
    end
    if child == nil and ns.Debug and ns.Debug.IsVerbose and ns.Debug:IsVerbose(AURAS_MODULE) then
        dverbose("findLiveViewerChild MISS cdID=%s type=%s pool=%d reason=%s",
            tostring(cooldownID), tostring(displayType), poolCount,
            (poolCount == 0 and "pool-empty(viewer-unpopulated)")
            or (matchedInactive and "matched-but-inactive")
            or "no-cdID-match")
    end
    return child
end

Auras._readLiveBarDurationText = function(cooldownID)
    local child = findLiveViewerChildByCooldownID(cooldownID, "TrackedBars")
    if type(child) ~= "table" then return nil end
    if type(child.GetDurationFontString) == "function" then
        local okFS, fs = pcall(child.GetDurationFontString, child)
        if okFS and type(fs) == "table" and type(fs.GetText) == "function" then
            local okTxt, txt = pcall(fs.GetText, fs)
            if okTxt then
                if isSecret(txt) then return txt end
                if txt ~= nil then return txt end
            end
        end
    end
    if type(child.Bar) == "table" and type(child.Bar.Duration) == "table"
       and type(child.Bar.Duration.GetText) == "function" then
        local okTxt, txt = pcall(child.Bar.Duration.GetText, child.Bar.Duration)
        if okTxt then
            if isSecret(txt) then return txt end
            if txt ~= nil then return txt end
        end
    end
    if type(child.Cooldown) == "table"
       and type(child.Cooldown.GetCountdownFontString) == "function" then
        local okFS, fs = pcall(child.Cooldown.GetCountdownFontString, child.Cooldown)
        if okFS and type(fs) == "table" and type(fs.GetText) == "function" then
            local okTxt, txt = pcall(fs.GetText, fs)
            if okTxt then
                if isSecret(txt) then return txt end
                if txt ~= nil then return txt end
            end
        end
    end
    return nil
end

function Auras._viewerChildIsLive(child)
    if type(child) ~= "table" then return false end
    for vname in pairs(BUFF_VIEWER_NAMES) do
        local viewer = getViewer(vname)
        if viewer then
            local items = getItemFrames(viewer) or {}
            for i = 1, #items do
                if items[i] == child then return true end
            end
        end
    end
    return false
end

function Auras._viewerChildActiveSignal(child)
    if type(child) ~= "table" then return nil end
    local active = Auras._childIsActiveSecretSafe(child)
    if active ~= nil then return active and true or false end
    if childShownActive(child) then return true end
    if type(child.IsShown) == "function" then
        local ok, shown = pcall(child.IsShown, child)
        if ok and not isSecret(shown) and shown == true then return true end
    end
    return nil
end

function Auras._viewerChildAuraInstanceID(child)
    if type(child) ~= "table" then return nil end
    local aInst
    local ok = pcall(function() aInst = child.auraInstanceID end)
    if ok and aInst ~= nil then return aInst end
    aInst = nil
    if type(child.Icon) == "table" then
        local ok2 = pcall(function() aInst = child.Icon.auraInstanceID end)
        if ok2 and aInst ~= nil then return aInst end
    end
    if type(child.GetAuraSpellInstanceID) == "function" then
        local ok3, v = pcall(child.GetAuraSpellInstanceID, child)
        if ok3 and v ~= nil then return v end
    end
    return nil
end

function Auras._viewerChildAuraUnit(child)
    if type(child) ~= "table" then return nil end
    local unit
    local ok = pcall(function() unit = child.auraDataUnit end)
    if ok and type(unit) == "string" and not isSecret(unit) then return unit end
    return nil
end

function Auras:ResolveAuraStateFromViewer(entry)
    if type(entry) ~= "table" then return nil, nil end

    local cdID = tonumber(entry.cooldownID)
    if not cdID then return nil, nil end

    local child = findLiveViewerChildByCooldownID(cdID, "TrackedBars")
        or findLiveViewerChildByCooldownID(cdID, "TrackedIcon")
    if type(child) ~= "table" then return false, nil end

    local aInst = Auras._viewerChildAuraInstanceID(child)
    if isSecret(aInst) then aInst = nil end
    local unit = Auras._viewerChildAuraUnit(child) or "player"
    local cooldownID = readChildCooldownID(child)

    local duration, expirationTime, startTime, applications

    local icon
    do
        local iconField = child.Icon
        if type(iconField) == "table" and type(iconField.GetTexture) == "function" then
            local ok, tex = pcall(iconField.GetTexture, iconField)
            if ok and ns._auraPresentTruthy(tex) then icon = tex end
        end
    end

    if aInst ~= nil and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
        local ok, txt = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, aInst)
        if ok and type(txt) == "string" then applications = txt end
    end

    local spellID = entry.overrideTooltipSpellID or entry.overrideSpellID or entry.spellID

    local info = {
        child          = child,
        auraInstanceID = aInst,
        auraDataUnit   = unit,
        cooldownID     = cooldownID,
        spellID        = spellID,
        duration       = duration,
        expirationTime = expirationTime,
        startTime      = startTime,
        applications   = applications,
        icon           = icon,
    }
    return true, info
end

function Auras:GetCurrentScopeKey()
    local class
    if UnitClass then
        local ok, _, c = pcall(UnitClass, "player")
        if ok then class = c end
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

local function getAurasProfile()
    local p = Auras.profileRef
    if not p then return nil end
    p.scopes = p.scopes or {}
    return p
end

local function ensureScope(scopeKey)
    local p = getAurasProfile()
    if not p then return nil end
    local s = p.scopes[scopeKey]
    if not s then
        s = {}
        p.scopes[scopeKey] = s
    end
    return s
end

function Auras:GetScopes()
    local p = getAurasProfile()
    local out = {}
    if not (p and p.scopes) then return out end
    for k in pairs(p.scopes) do out[#out + 1] = k end
    table.sort(out)
    return out
end

local function readItemBaseSpellID(item)
    if type(item) ~= "table" then return nil end
    local cdInfo = item.cooldownInfo
    if type(cdInfo) ~= "table" then return nil end
    local sid = cdInfo.spellID
    if _IsUsableSID(sid) then
        return sid
    end
    return nil
end

local function buildActiveSpellIndex(active)
    local idx = {}
    if type(active) ~= "table" then return idx end
    for i = 1, #active do
        local sid = readItemBaseSpellID(active[i])
        if sid then
            local list = idx[sid]
            if not list then
                list = {}
                idx[sid] = list
            end
            list[#list + 1] = i
        end
    end
    return idx
end

function Auras:_ComputeCrossViewerDedup(iconActive, barActive)
    local iconSuppress, barSuppress = {}, {}
    if type(iconActive) ~= "table" or type(barActive) ~= "table" then
        return iconSuppress, barSuppress
    end
    local p = self.profileRef
    local prefer = (p and p.crossViewerPrefer) or "bar"
    if prefer ~= "icon" and prefer ~= "bar" then prefer = "bar" end

    local iconIdx = buildActiveSpellIndex(iconActive)
    local barIdx  = buildActiveSpellIndex(barActive)

    for sid, iList in pairs(iconIdx) do
        local jList = barIdx[sid]
        if jList then
            if prefer == "bar" then
                for k = 1, #iList do iconSuppress[iList[k]] = true end
            else
                for k = 1, #jList do barSuppress[jList[k]] = true end
            end
        end
    end
    return iconSuppress, barSuppress
end

local ICON_SPACING_DEFAULT = 2

local function getTrackedIconVisuals()
    if not ns.savedVarsReady then return nil end
    if ns.GetLayoutVisuals then
        return ns:GetLayoutVisuals("TrackedIcon", false)
    end
    return nil
end

local function resolveTrackedIconSize(anchorH, anchorSpacing)
    local v = getTrackedIconVisuals()
    local fallback = (type(anchorH) == "number" and anchorH > 0) and anchorH or 32
    local iconW, iconH, spacing
    if v then
        if type(v.iconWidth)  == "number" and v.iconWidth  > 0 then iconW = math.floor(v.iconWidth)  end
        if type(v.iconHeight) == "number" and v.iconHeight > 0 then iconH = math.floor(v.iconHeight) end
        if type(v.spacing)    == "number" and v.spacing    >= 0 then spacing = math.floor(v.spacing) end
    end
    iconW = iconW or fallback
    iconH = iconH or fallback
    if not spacing then
        spacing = (type(anchorSpacing) == "number" and anchorSpacing >= 0) and anchorSpacing or ICON_SPACING_DEFAULT
    end
    return iconW, iconH, spacing
end

local function getTrackedIconTextStyle()
    local v = getTrackedIconVisuals()
    local t = (v and v.textStack) or (v and v.text) or nil
    return {
        font   = (t and t.font)   or "default",
        size   = (t and type(t.size) == "number" and t.size > 0 and t.size) or 12,
        flags  = (t and t.flags)  or "OUTLINE",
        anchor = (t and t.anchor) or "BOTTOMRIGHT",
        x      = (t and type(t.x) == "number") and t.x or -1,
        y      = (t and type(t.y) == "number") and t.y or  1,
    }
end

local function getTrackedIconCooldownTextStyle()
    local v = getTrackedIconVisuals()
    local t = (v and v.textCooldown) or (v and v.text) or nil
    return {
        font   = (t and t.font)   or "default",
        size   = (t and type(t.size) == "number" and t.size > 0 and t.size) or 14,
        flags  = (t and t.flags)  or "OUTLINE",
        anchor = (t and t.anchor) or "CENTER",
        x      = (t and type(t.x) == "number") and t.x or 0,
        y      = (t and type(t.y) == "number") and t.y or 0,
    }
end

local function getTrackedBarsVisuals()
    if not ns.savedVarsReady then return nil end
    if ns.GetLayoutVisuals then
        return ns:GetLayoutVisuals("TrackedBars", false)
    end
    return nil
end

local function resolveTrackedBarsGeometry(optBarHeight, optSpacing)
    local v = getTrackedBarsVisuals()
    local barW, barH, spacing
    if v then
        if type(v.barWidth)  == "number" and v.barWidth  > 0 then barW = math.floor(v.barWidth)  end
        if type(v.barHeight) == "number" and v.barHeight > 0 then barH = math.floor(v.barHeight) end
        if type(v.spacing)   == "number" and v.spacing   >= 0 then spacing = math.floor(v.spacing) end
    end
    if not barW then barW = _lowTimeStats.preview.defaultWidth end
    if not barH then
        barH = (type(optBarHeight) == "number" and optBarHeight > 0) and math.floor(optBarHeight) or 18
    end
    if not spacing then
        spacing = (type(optSpacing) == "number" and optSpacing >= 0) and math.floor(optSpacing) or 2
    end
    return barW, barH, spacing
end

local function resolveAuraFontPath(font)
    if type(font) == "string" and (font:find("\\", 1, true) or font:find("/", 1, true)) then
        return font
    end
    if ns.Controls and ns.Controls.ResolveFontPath then
        local ok, path = pcall(ns.Controls.ResolveFontPath, font)
        if ok and type(path) == "string" and path ~= "" then return path end
    end
    if ns.Widgets and ns.Widgets.resolveMedia then
        local key = (font ~= nil and font ~= "default") and font or nil
        return ns.Widgets.resolveMedia("font", key, ns.Widgets.DEFAULT_FONT)
    end
    return [[Fonts\FRIZQT__.TTF]]
end

local function applyBarTextStyle(fs, parent, style, defaultEdge)
    if not fs then return end
    style = style or {}
    local fontPath = resolveAuraFontPath(style.font)
    local size  = (type(style.size) == "number" and style.size > 0) and style.size or 11
    local flags = (type(style.flags) == "string") and style.flags or "OUTLINE"
    local anchor = style.anchor
    local ox = (type(style.x) == "number") and style.x or 0
    local oy = (type(style.y) == "number") and style.y or 0
    local valid = {
        CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
        TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
    }
    if anchor == "BELOW_ICON" then anchor = "BOTTOM"
    elseif anchor == "ABOVE_ICON" then anchor = "TOP" end
    if not (type(anchor) == "string" and valid[anchor]) then
        anchor = defaultEdge or "LEFT"
    end
    pcall(function()
        fs:SetFont(fontPath, size, flags)
        fs:ClearAllPoints()
        fs:SetPoint(anchor, parent, anchor, ox, oy)
    end)
end

local function getTrackedBarsTextStyles()
    local v = getTrackedBarsVisuals()
    local t = v and v.text or nil
    local name  = t and t.name  or nil
    local timer = t and t.timer or nil
    return name, timer
end

function Auras._styleBarCountdownNumbers(cd, bar, timerStyle)
    if type(cd) ~= "table" then return end
    local okFS, fs = pcall(cd.GetCountdownFontString, cd)
    if not (okFS and type(fs) == "table") then return end
    applyBarTextStyle(fs, bar, timerStyle, "RIGHT")
end

function Auras._driveBarCountdownNumbers(slot, durObj)
    if type(slot) ~= "table" then return false end
    local cd = slot.cdNumbers
    if type(cd) ~= "table" then return false end
    if durObj == nil or type(cd.SetCooldownFromDurationObject) ~= "function" then
        pcall(cd.Clear, cd)
        pcall(cd.Hide, cd)
        return false
    end
    local ok = pcall(cd.SetCooldownFromDurationObject, cd, durObj)
    if not ok then
        pcall(cd.Clear, cd)
        pcall(cd.Hide, cd)
        return false
    end
    pcall(cd.SetHideCountdownNumbers, cd, false)
    pcall(cd.Show, cd)
    return true
end

function Auras._clearBarCountdownNumbers(slot)
    if type(slot) ~= "table" then return end
    local cd = slot.cdNumbers
    if type(cd) ~= "table" then return end
    pcall(cd.Clear, cd)
    pcall(cd.Hide, cd)
end

Auras._blizzBarFSCache = Auras._blizzBarFSCache or setmetatable({}, { __mode = "k" })

function Auras._getBlizzBarFontStrings(blizzBar)
    if type(blizzBar) ~= "table" then return nil, nil end
    local cache = Auras._blizzBarFSCache
    local cached = cache[blizzBar]
    if cached and cached.nameFS ~= nil and cached.timerFS ~= nil then
        local nameFS = cached.nameFS or nil
        local timerFS = cached.timerFS or nil
        if nameFS == false then nameFS = nil end
        if timerFS == false then timerFS = nil end
        return nameFS, timerFS
    end
    local nameFS, timerFS
    if type(blizzBar.Name) == "table" and type(blizzBar.Name.GetText) == "function" then
        nameFS = blizzBar.Name
    end
    if type(blizzBar.Duration) == "table" and type(blizzBar.Duration.GetText) == "function" then
        timerFS = blizzBar.Duration
    end
    if (nameFS == nil or timerFS == nil) and type(blizzBar.GetRegions) == "function" then
        local okR, regions = pcall(function() return { blizzBar:GetRegions() } end)
        if okR and type(regions) == "table" then
            local fsIdx = 0
            for i = 1, #regions do
                local rgn = regions[i]
                if type(rgn) == "table" and type(rgn.GetObjectType) == "function" then
                    local okT, objType = pcall(rgn.GetObjectType, rgn)
                    if okT and objType == "FontString" then
                        fsIdx = fsIdx + 1
                        if fsIdx == 1 and nameFS == nil then nameFS = rgn end
                        if fsIdx == 2 and timerFS == nil then timerFS = rgn end
                    end
                end
            end
        end
    end
    cache[blizzBar] = { nameFS = nameFS or false, timerFS = timerFS or false }
    return nameFS, timerFS
end

function Auras._mirrorBlizzBarIntoSlot(slot, child, opts)
    if type(slot) ~= "table" or type(child) ~= "table" then return false end
    local bar = slot.bar
    if type(bar) ~= "table" then return false end
    opts = type(opts) == "table" and opts or nil

    local blizzBar
    do
        local ok, b = pcall(function() return child.Bar end)
        if ok and type(b) == "table" then blizzBar = b end
    end
    if blizzBar == nil and type(child.GetBarFrame) == "function" then
        local ok, b = pcall(child.GetBarFrame, child)
        if ok and type(b) == "table" then blizzBar = b end
    end
    if type(blizzBar) ~= "table" then return false end

    local active = true
    do
        local laundered = Auras._childIsActiveSecretSafe(child)
        if laundered ~= nil then
            active = laundered and true or false
        elseif type(child.IsShown) == "function" then
            local okS, shown = pcall(child.IsShown, child)
            if okS then active = shown and true or false end
        end
    end

    pcall(function()
        if type(bar.SetReverseFill) == "function" then bar:SetReverseFill(false) end
    end)
    pcall(function()
        if type(bar.SetTimerDuration) == "function" then bar:SetTimerDuration(nil) end
    end)
    slot._liveDurObj = nil
    slot._liveDurObjType = nil
    slot._liveDurObjSecret = nil

    pcall(function()
        bar:SetMinMaxValues(blizzBar:GetMinMaxValues())
    end)
    pcall(function()
        bar:SetValue(blizzBar:GetValue())
    end)

    if not (opts and opts.mirrorColor == false) then
        pcall(function()
            local srcTex = blizzBar:GetStatusBarTexture()
            local dstTex = bar:GetStatusBarTexture()
            if type(srcTex) == "table" and type(dstTex) == "table" then
                local r, g, b, a = srcTex:GetVertexColor()
                if r ~= nil then dstTex:SetVertexColor(r, g, b, a) end
            end
        end)
    end

    local aInst
    pcall(function() aInst = child.auraInstanceID end)
    if aInst == nil and type(child.Icon) == "table" then
        pcall(function() aInst = child.Icon.auraInstanceID end)
    end
    if isSecret(aInst) then aInst = nil end
    local unit
    pcall(function() unit = child.auraDataUnit end)
    if type(unit) ~= "string" or isSecret(unit) then unit = "player" end

    if slot.nameFS and slot.nameFS.IsShown and slot.nameFS:IsShown() then
        local nameStr
        if aInst ~= nil and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
            local ok, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, aInst)
            if ok and type(ad) == "table" and ad.name ~= nil then nameStr = ad.name end
        end
        if nameStr == nil then
            local blizzNameFS = Auras._getBlizzBarFontStrings(blizzBar)
            if type(blizzNameFS) == "table" and type(blizzNameFS.GetText) == "function" then
                local ok, txt = pcall(blizzNameFS.GetText, blizzNameFS)
                if ok and txt ~= nil then nameStr = txt end
            end
        end
        if nameStr == nil then
            local sid = type(slot._mirrorSpellID) == "number" and slot._mirrorSpellID or nil
            if sid and C_Spell and C_Spell.GetSpellInfo then
                local ok, si = pcall(C_Spell.GetSpellInfo, sid)
                if ok and type(si) == "table" and si.name ~= nil then nameStr = si.name end
            end
        end
        if nameStr ~= nil then pcall(slot.nameFS.SetText, slot.nameFS, ns._auraSafeText(nameStr)) end
    end

    if slot.icon and (slot._iconShown ~= false) then
        local iconTex
        if aInst ~= nil then iconTex = Auras._resolveLiveVariantIcon(unit, aInst) end
        if not ns._auraPresentTruthy(iconTex) then iconTex = readViewerChildIconTexture(child) end
        if not ns._auraPresentTruthy(iconTex) then
            local sid = type(slot._mirrorSpellID) == "number" and slot._mirrorSpellID or nil
            if sid and C_Spell and C_Spell.GetSpellInfo then
                local ok, si = pcall(C_Spell.GetSpellInfo, sid)
                if ok and type(si) == "table" and ns._auraPresentTruthy(si.iconID) then iconTex = si.iconID end
            end
        end
        if Auras._validTexture(iconTex) then pcall(slot.icon.SetTexture, slot.icon, iconTex) end
    end

    local durText = ""
    if not (opts and opts.showTimer == false) and slot.durFS then
        local _, blizzTimerFS = Auras._getBlizzBarFontStrings(blizzBar)
        if type(blizzTimerFS) == "table" and type(blizzTimerFS.GetText) == "function" then
            local ok, txt = pcall(blizzTimerFS.GetText, blizzTimerFS)
            if ok then durText = ns._auraSafeText(txt) end
        end
        pcall(slot.durFS.SetText, slot.durFS, durText)
    elseif slot.durFS then
        pcall(slot.durFS.SetText, slot.durFS, "")
    end
    pcall(Auras._clearBarCountdownNumbers, slot)
    slot._mirrorDurText = durText

    return active
end

local IconDisplay = {}
IconDisplay.__index = IconDisplay

function IconDisplay.New(parentMod)
    local self_ = setmetatable({}, IconDisplay)
    self_.mod         = parentMod
    self_.anchorName  = ICON_ANCHOR_NAME
    self_.anchor      = nil
    self_.container   = nil
    self_.icons       = {}
    self_.activeCount = 0
    return self_
end

function IconDisplay:Opts()
    local p = self.mod.profileRef
    local o = p and p.icons
    if type(o) ~= "table" then o = {} end
    return o
end

function IconDisplay:Enabled()
    return self:Opts().enabled ~= false
end

function IconDisplay:EnsureContainer()
    if self.container then return self.container end
    local anchor = ns:GetAnchor(self.anchorName)
    if not (anchor and anchor.frame) then
        dwarnOnce("nocontainer:" .. tostring(self.anchorName),
            "anchor %s missing -- cannot create icon container", tostring(self.anchorName))
        return nil
    end
    local c = CreateFrame("Frame", "TenUIAurasIconContainer", anchor.frame)
    c:SetAllPoints(anchor.frame)
    self.container = c
    self.anchor = anchor
    return c
end

function IconDisplay:GetIconSlot(i)
    local w = self.icons[i]
    if w then return w end
    local container = self:EnsureContainer()
    if not container then return nil end
    local o = self:Opts()
    local vb = getTrackedIconVisuals()
    w = ns.Widgets.Icon:New(container, {
        border          = not (vb and vb.showBorder == false),
        borderColor     = (vb and type(vb.borderColor) == "table") and vb.borderColor or nil,
        cooldown        = true,
        countdown       = true,
        cooldownSwipe   = o.showDurationSwipe ~= false,
        cooldownReverse = true,
        stackText       = o.showStackText ~= false,
        zoomIcon        = true,
    })
    if w and w.frame then
        w.frame:ClearAllPoints()
        w.frame:Hide()
        if w.SetCooldownReverse then pcall(w.SetCooldownReverse, w, true) end
    end
    if w and w.ApplyTextStyle then
        pcall(w.ApplyTextStyle, w, getTrackedIconTextStyle())
    end
    if w and w.ApplyCooldownTextStyle then
        pcall(w.ApplyCooldownTextStyle, w, getTrackedIconCooldownTextStyle())
    end
    w._slot = {}
    self.icons[i] = w
    return w
end

function IconDisplay:PrewarmSlots(count)
    if InCombatLockdown and InCombatLockdown() then return end
    if not self:EnsureContainer() then return end
    local o = self:Opts()
    local anchorH = (self.anchor and self.anchor.frame and self.anchor.frame:GetHeight()) or 32
    local iconW, iconH = resolveTrackedIconSize(anchorH, tonumber(o.spacing))
    local n = math.max(tonumber(count) or 0, 8)
    for i = 1, n do
        local w = self:GetIconSlot(i)
        if w and w.frame then
            pcall(w.frame.SetSize, w.frame, iconW, iconH)
            pcall(w.frame.ClearAllPoints, w.frame)
            if w.Hide then pcall(w.Hide, w) end
        end
    end
end

function IconDisplay:DestroyIcons()
    for i = 1, #self.icons do
        local w = self.icons[i]
        if w then
            if w._pandemicSlot then
                local pg = w._pandemicSlot.pandemicGlow
                if pg then
                    if pg.animGroup and pg.animGroup:IsPlaying() then
                        pcall(pg.animGroup.Stop, pg.animGroup)
                    end
                    pcall(pg.Hide, pg)
                    pcall(pg.SetParent, pg, nil)
                end
                w._pandemicSlot = nil
            end
            if w.ClearCooldown then pcall(w.ClearCooldown, w) end
            if w.Destroy then pcall(w.Destroy, w) end
        end
        self.icons[i] = nil
    end
end

function IconDisplay:BuildActive()
    if not self:Enabled() then return {} end
    local viewer = getViewer(ICON_VIEWER_NAME)

    local preview = cdmPreviewOpen()
    local active = buildActiveFromCatalog("TrackedIcon", preview) or {}

    local viewerShown = false
    if viewer and type(viewer.IsShown) == "function" then
        local okSh, s = pcall(viewer.IsShown, viewer)
        if okSh then viewerShown = s end
    end
    dlogPipeline("Icon", viewerShown, #active, #active, active)
    return active
end

function IconDisplay:RenderActive(active, suppressSet)
    active = active or {}
    local ok, err = pcall(self._RenderActiveImpl, self, active, suppressSet)
    if not ok then
        dwarnOnce("renderactive-icon-throw",
            "[AURA RENDER ERROR] IconDisplay:RenderActive threw: %s (combat=%s)",
            tostring(err), tostring(InCombatLockdown and InCombatLockdown() or false))
        Auras._lastRenderError = {
            kind = "icon", err = tostring(err),
            at = (GetTime and GetTime()) or 0,
            combat = (InCombatLockdown and InCombatLockdown()) and true or false,
        }
    end
end

function IconDisplay:_RenderActiveImpl(active, suppressSet)
    if not self:Enabled() then
        for i = 1, #self.icons do
            local w = self.icons[i]
            if w and w.Hide then pcall(w.Hide, w) end
            if w and w._pandemicSlot then
                pcall(applyPandemicGlow, w._pandemicSlot, false, nil)
            end
        end
        self.activeCount = 0
        if self.container then self.container:SetAlpha(0) end
        return
    end
    if self.container then self.container:SetAlpha(1) end
    active = active or {}
    suppressSet = suppressSet or {}
    if Auras._lowTimeDebug then Auras._lowTimeDebug.icon = nil end

    if next(suppressSet) ~= nil then
        local compact = {}
        for i = 1, #active do
            if not suppressSet[i] then
                compact[#compact + 1] = active[i]
            end
        end
        active = compact
    end

    local o = self:Opts()
    local showStack = o.showStackText ~= false
    local needed = #active

    local anchor = self.anchor or ns:GetAnchor(self.anchorName)
    local mode = o.align or "CENTER"
    if mode ~= "LEFT" and mode ~= "CENTER" and mode ~= "RIGHT" then mode = "CENTER" end
    local anchorH = (anchor and anchor.frame and anchor.frame:GetHeight()) or 32
    local iconW, iconH, spacing = resolveTrackedIconSize(anchorH, tonumber(o.spacing))
    if spacing < 0 then spacing = 0 end
    local totalW = needed * iconW + math.max(0, needed - 1) * spacing
    local vcfg = getTrackedIconVisuals()
    local vertical = (vcfg and vcfg.orientation == "V") and true or false
    local totalH = needed * iconH + math.max(0, needed - 1) * spacing

    local shown = 0
    for i = 1, needed do
        local item = active[i]
        local w = self:GetIconSlot(i)
        if w and w.frame and anchor and anchor.frame then
            local f = w.frame
            f:ClearAllPoints()
            f:SetSize(iconW, iconH)
            if f.cooldown then
                f.cooldown:ClearAllPoints()
                f.cooldown:SetAllPoints(f)
            end
            if vertical then
                local offset = (i - 1) * (iconH + spacing)
                if mode == "LEFT" then
                    f:SetPoint("TOP", anchor.frame, "TOP", 0, -offset)
                elseif mode == "RIGHT" then
                    f:SetPoint("BOTTOM", anchor.frame, "BOTTOM", 0, offset)
                else
                    local top = (totalH * 0.5) - offset
                    f:SetPoint("TOP", anchor.frame, "CENTER", 0, top)
                end
            else
                local offset = (i - 1) * (iconW + spacing)
                if mode == "LEFT" then
                    f:SetPoint("LEFT", anchor.frame, "LEFT", offset, 0)
                elseif mode == "RIGHT" then
                    f:SetPoint("RIGHT", anchor.frame, "RIGHT", -offset, 0)
                else
                    local left = -(totalW * 0.5) + offset
                    f:SetPoint("LEFT", anchor.frame, "CENTER", left, 0)
                end
            end

            if w.Show then pcall(w.Show, w) end
            Auras._forceShowOwnFrame(self.container, 1)
            Auras._forceShowOwnFrame(w.frame, 1)
            if w.frame and w.frame.icon then Auras._forceShowOwnFrame(w.frame.icon, 1) end
            Auras._repairOwnParentChain(w.frame)
            shown = shown + 1

            local sid
            local okSid, sidRes = pcall(readItemSpellID, item)
            if okSid then sid = sidRes end

            do
                local okTex = pcall(function()
                    local tex = readItemIconTexture(item)
                    if Auras._validTexture(tex) then w:SetTexture(tex) end
                end)
                if not okTex then Auras._renderTrace("TrackedIcon", item, i, true, "caught:texture") end
            end
            do
                local okCd = pcall(applySwipe, w, item, sid)
                if not okCd then Auras._renderTrace("TrackedIcon", item, i, true, "caught:cooldown") end
            end
            do
                local okCnt = pcall(function()
                    if showStack then
                        local stack = readItemStackText(item)
                        w:SetStackTextRaw(ns._auraSafeText(stack))
                    else
                        w:SetStackTextRaw("")
                    end
                end)
                if not okCnt then Auras._renderTrace("TrackedIcon", item, i, true, "caught:count") end
            end
            do
                local okCurve, curveApplied = pcall(Auras._applyIconLowTimeCurve, w, item, sid, "icon")
                if okCurve and curveApplied ~= true then
                    pcall(Auras._applyIconLowTimeTextColor, w, "icon")
                end
            end
            do
                local okGlow = pcall(function()
                local pslot = ensurePandemicGlowIcon(w)
                local pOpts = pandemicOpts(self.mod)
                local okPP, perPandOn, perPandOpts = pcall(Auras.PerAuraPandemicGlow, item, pOpts)
                if not okPP then perPandOn, perPandOpts = nil, nil end
                local effPOpts = (perPandOn == true and perPandOpts) or pOpts
                local pandemicOn = false
                local pandemicSource = "none"
                local pandemicDur = nil
                local pandemicEnabled
                if perPandOn == false then
                    pandemicEnabled = false
                elseif perPandOn == true then
                    pandemicEnabled = true
                else
                    pandemicEnabled = pOpts ~= nil and pOpts.enabled == true
                end
                if pandemicEnabled then
                    local okP, glowOn, src, durObj = pcall(evaluatePandemicForItem, item, effPOpts, "icon")
                    if okP then
                        if safeTruthy(glowOn) then pandemicOn = true end
                        if type(src) == "string" then pandemicSource = src end
                        if ns._auraPresentTruthy(durObj) then pandemicDur = durObj end
                    else
                        local cdIDForLog = type(item) == "table" and tonumber(item.cooldownID) or nil
                        if cdIDForLog then
                            pandemicLogOnce(cdIDForLog, "evaluatePandemicForItem pcall failed kind=icon",
                                tostring(glowOn))
                        end
                    end
                end
                local overlayOwned = false
                if pandemicSource == "secret-visual" then
                    if ns._auraPresentTruthy(pandemicDur) then
                        local svActive
                        local okAO, ao = pcall(Auras._secretVisualActiveOpts, item, activeGlowOpts(self.mod, "icon"))
                        if okAO then svActive = ao end
                        local thrSecs
                        local okTS, ts = pcall(Auras._pandemicThresholdSeconds, item, effPOpts)
                        if okTS then thrSecs = ts end
                        local okSV, applied, svMode = pcall(applySecretPandemicVisual, pslot, pandemicDur, effPOpts, svActive, thrSecs)
                        overlayOwned = okSV and applied == true
                        if overlayOwned then
                            pcall(Auras._releaseSlotGlowFX, pslot)
                            if svMode == "two-zone" then
                                Auras.RecordActiveGlowEval(pslot, "applied:two-zone-curve")
                            elseif svActive then
                                Auras.RecordActiveGlowEval(pslot, "overlay-owned:secret-visual(two-zone-pending)")
                            else
                                Auras.RecordActiveGlowEval(pslot, "overlay-owned:secret-visual")
                            end
                        end
                    end
                elseif pandemicOn then
                    pcall(clearSecretPandemicVisual, pslot)
                    pcall(applyPandemicGlow, pslot, true, effPOpts)
                    overlayOwned = true
                    Auras.RecordActiveGlowEval(pslot, "overlay-owned:pandemic-pulse")
                end
                if not overlayOwned then
                    pcall(clearSecretPandemicVisual, pslot)
                    local agOpts = activeGlowOpts(self.mod, "icon")
                    local perOn, perOpts, agNote = Auras._resolveActiveGlowSticky(item)
                    local aiID = type(item) == "table" and item.auraInstanceID or nil
                    local hasAura = not isSecret(aiID) and aiID ~= nil
                    local activeOn
                    local agReason
                    if perOn == true then
                        activeOn = hasAura
                        agReason = hasAura and "applied:per-aura"
                            or "skip:per-aura-on-but-no-live-aura"
                    elseif perOn == false then
                        activeOn = false
                        agReason = "skip:per-aura-off"
                    else
                        activeOn = agOpts and agOpts.enabled == true and hasAura
                        if activeOn then
                            agReason = "applied:global"
                        elseif agOpts and agOpts.enabled == true then
                            agReason = "skip:global-on-but-no-live-aura"
                        else
                            agReason = "skip:per-aura-unset+global-off"
                        end
                    end
                    if agNote then
                        agReason = agReason .. " (" .. agNote .. ")"
                    end
                    Auras.RecordActiveGlowEval(pslot, agReason)
                    if activeOn then
                        pcall(applyAuraGlow, pslot, true, (perOn == true) and perOpts or agOpts)
                    else
                        pcall(applyPandemicGlow, pslot, false, pOpts)
                    end
                end
                end)
                if not okGlow then Auras._renderTrace("TrackedIcon", item, i, true, "caught:glow") end
            end
            local iconSrc = "live"
            if type(item) == "table" then
                if item.activeAuraSource == "viewerState" then
                    iconSrc = "viewerState"
                elseif item.activeAuraSource == "spellIDprobe" then
                    iconSrc = "spellIDprobe"
                elseif item._fromViewer then
                    iconSrc = "viewerChild"
                elseif item.auraInstanceID == nil then
                    iconSrc = "live-secretInst"
                end
            end
            Auras._renderTrace("TrackedIcon", item, i, true, "reached-end", w.frame,
                "src=" .. iconSrc .. " arm=" .. tostring(w._lastArmPath))
        end
    end

    for i = needed + 1, #self.icons do
        local w = self.icons[i]
        if w then
            if w.ClearCooldown then pcall(w.ClearCooldown, w) end
            if w.SetStackTextRaw then pcall(w.SetStackTextRaw, w, "") end
            if w.Hide then pcall(w.Hide, w) end
            if w.frame and w.frame.ClearAllPoints then
                pcall(w.frame.ClearAllPoints, w.frame)
            end
            if w._pandemicSlot then
                pcall(applyPandemicGlow, w._pandemicSlot, false, nil)
            end
        end
    end

    self._lastRenderShown = shown
    self.activeCount = needed
    if self.container then self.container:SetAlpha(needed == 0 and 0 or 1) end

    if needed > 0 and ns.AutoFitAnchor then
        if vertical then
            ns:AutoFitAnchor(self.anchorName, iconW, totalH)
        else
            ns:AutoFitAnchor(self.anchorName, totalW, iconH)
        end
    end

    dtrace("IconDisplay:Refresh needed=%d shown=%d pool=%d iconW=%d totalW=%d",
        needed, shown, #self.icons, iconW, totalW)
end

function IconDisplay:Refresh()
    local active = self:BuildActive() or {}
    self:RenderActive(active, nil)
end

local _lastLayoutLog = setmetatable({}, { __index = function() return 0 end })
local function dlogLayout(tag, count, iconSize, spacing, totalW, anchorH, anchorW)
    if not (ns.Debug and ns.Debug.IsTrace and ns.Debug:IsTrace(AURAS_MODULE)) then return end
    local now = GetTime and GetTime() or 0
    if now - _lastLayoutLog[tag] < 5 then return end
    _lastLayoutLog[tag] = now
    dtrace("%s Layout count=%d iconSize=%s spacing=%s totalW=%s anchorH=%s anchorW=%s",
        tostring(tag), count, tostring(iconSize), tostring(spacing),
        tostring(totalW), tostring(anchorH), tostring(anchorW))
end

function IconDisplay:Layout(count)
    local anchor = self.anchor or ns:GetAnchor(self.anchorName)
    if not (anchor and anchor.frame) then return end
    if count == 0 then return end
    local o = self:Opts()
    local mode = o.align or "CENTER"
    if mode ~= "LEFT" and mode ~= "CENTER" and mode ~= "RIGHT" then mode = "CENTER" end

    local anchorH = anchor.frame:GetHeight() or 32
    local iconW, iconH, spacing = resolveTrackedIconSize(anchorH, tonumber(o.spacing))
    if spacing < 0 then spacing = 0 end
    local anchorW = anchor.frame:GetWidth() or 0
    local totalW = count * iconW + math.max(0, count - 1) * spacing
    local vcfg = getTrackedIconVisuals()
    local vertical = (vcfg and vcfg.orientation == "V") and true or false
    local totalH = count * iconH + math.max(0, count - 1) * spacing

    dlogLayout("Icon", count, iconW, spacing, totalW, iconH, anchorW)

    for i = 1, count do
        local w = self.icons[i]
        if w and w.frame then
            local f = w.frame
            f:ClearAllPoints()
            f:SetSize(iconW, iconH)
            if f.cooldown then
                f.cooldown:ClearAllPoints()
                f.cooldown:SetAllPoints(f)
            end
            if vertical then
                local offset = (i - 1) * (iconH + spacing)
                if mode == "LEFT" then
                    f:SetPoint("TOP", anchor.frame, "TOP", 0, -offset)
                elseif mode == "RIGHT" then
                    f:SetPoint("BOTTOM", anchor.frame, "BOTTOM", 0, offset)
                else
                    local top = (totalH * 0.5) - offset
                    f:SetPoint("TOP", anchor.frame, "CENTER", 0, top)
                end
            else
                local offset = (i - 1) * (iconW + spacing)
                if mode == "LEFT" then
                    f:SetPoint("LEFT", anchor.frame, "LEFT", offset, 0)
                elseif mode == "RIGHT" then
                    f:SetPoint("RIGHT", anchor.frame, "RIGHT", -offset, 0)
                else
                    local left = -(totalW * 0.5) + offset
                    f:SetPoint("LEFT", anchor.frame, "CENTER", left, 0)
                end
            end
        end
    end
end

function IconDisplay:ApplyVisualOptions()
    local style = getTrackedIconTextStyle()
    local cdStyle = getTrackedIconCooldownTextStyle()
    local vb = getTrackedIconVisuals()
    local borderOn = not (vb and vb.showBorder == false)
    local borderColor = (vb and type(vb.borderColor) == "table") and vb.borderColor or nil
    for i = 1, #self.icons do
        local w = self.icons[i]
        if w and w.ApplyTextStyle then
            pcall(w.ApplyTextStyle, w, style)
        end
        if w and w.ApplyCooldownTextStyle then
            pcall(w.ApplyCooldownTextStyle, w, cdStyle)
        end
        if w and w.SetBorder then
            pcall(w.SetBorder, w, borderOn, borderColor)
        end
    end
    if self.mod and self.mod.RequestRefresh then
        pcall(self.mod.RequestRefresh, self.mod)
    end
end

local BarDisplay = {}
BarDisplay.__index = BarDisplay

function BarDisplay.New(parentMod)
    local self_ = setmetatable({}, BarDisplay)
    self_.mod         = parentMod
    self_.anchorName  = BAR_ANCHOR_NAME
    self_.anchor      = nil
    self_.container   = nil
    self_.bars        = {}
    self_.activeCount = 0
    return self_
end

function BarDisplay:Opts()
    local p = self.mod.profileRef
    local o = p and p.bars
    if type(o) ~= "table" then o = {} end
    return o
end

function BarDisplay:Enabled()
    return self:Opts().enabled ~= false
end

function BarDisplay:EnsureContainer()
    if self.container then return self.container end
    local anchor = ns:GetAnchor(self.anchorName)
    if not (anchor and anchor.frame) then
        dwarnOnce("nocontainer:" .. tostring(self.anchorName),
            "anchor %s missing -- cannot create bar container", tostring(self.anchorName))
        return nil
    end
    local c = CreateFrame("Frame", "TenUIAurasBarContainer", anchor.frame)
    c:SetAllPoints(anchor.frame)
    self.container = c
    self.anchor = anchor
    return c
end

function BarDisplay:GetBarSlot(i)
    local b = self.bars[i]
    if b then return b end
    local container = self:EnsureContainer()
    if not container then return nil end
    local o = self:Opts()
    local _, barH = resolveTrackedBarsGeometry(tonumber(o.barHeight), tonumber(o.spacing))

    local frame = CreateFrame("Frame", nil, container)
    frame:SetHeight(barH)

    local iconTex = frame:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("LEFT", frame, "LEFT", 0, 0)
    iconTex:SetSize(barH, barH)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetPoint("LEFT", iconTex, "RIGHT", 2, 0)
    bar:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    bar:SetHeight(barH)
    local vts = getTrackedBarsVisuals()
    local fillTex = ns.Widgets and ns.Widgets.resolveMedia
        and ns.Widgets.resolveMedia("statusbar", vts and vts.texture or nil, ns.Widgets.DEFAULT_STATUSBAR)
    bar:SetStatusBarTexture(fillTex or [[Interface\TargetingFrame\UI-StatusBar]])
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0, 0, 0, 0.5)

    local nameFS = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFS:SetPoint("LEFT", bar, "LEFT", 3, 0)
    nameFS:SetJustifyH("LEFT")

    local durFS = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    durFS:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    durFS:SetJustifyH("RIGHT")

    local cdNumbers = CreateFrame("Cooldown", nil, bar, "CooldownFrameTemplate")
    cdNumbers:SetAllPoints(bar)
    cdNumbers:SetHideCountdownNumbers(false)
    cdNumbers:SetDrawSwipe(false)
    cdNumbers:SetDrawEdge(false)
    cdNumbers:SetDrawBling(false)
    cdNumbers:EnableMouse(false)
    cdNumbers:SetFrameLevel((bar:GetFrameLevel() or 1) + 1)
    cdNumbers:Hide()

    do
        local nameStyle, timerStyle = getTrackedBarsTextStyles()
        applyBarTextStyle(nameFS, bar, nameStyle, "LEFT")
        applyBarTextStyle(durFS,  bar, timerStyle, "RIGHT")
        Auras._styleBarCountdownNumbers(cdNumbers, bar, timerStyle)
    end

    frame:ClearAllPoints()
    frame:Hide()

    b = {
        frame   = frame,
        icon    = iconTex,
        bar     = bar,
        bg      = bg,
        nameFS  = nameFS,
        durFS   = durFS,
        cdNumbers = cdNumbers,
        _iconShown = true,
        _baseFillR = 1,
        _baseFillG = 1,
        _baseFillB = 1,
        _baseFillA = 1,
    }
    self:ApplyBarStyle(b)
    self.bars[i] = b
    return b
end

function BarDisplay:PrewarmSlots(count)
    if InCombatLockdown and InCombatLockdown() then return end
    if not self:EnsureContainer() then return end
    local o = self:Opts()
    local _, barH = resolveTrackedBarsGeometry(tonumber(o.barHeight), tonumber(o.spacing))
    local n = math.max(tonumber(count) or 0, 8)
    for i = 1, n do
        local slot = self:GetBarSlot(i)
        if slot and slot.frame then
            pcall(slot.frame.SetHeight, slot.frame, barH)
            pcall(slot.frame.ClearAllPoints, slot.frame)
            pcall(slot.frame.Hide, slot.frame)
        end
    end
end

function BarDisplay:ApplyBarStyle(slot)
    if not slot then return end
    local v = getTrackedBarsVisuals()

    do
        local fc = v and v.fillColor
        local fr, fg, fb, fa = 1, 1, 1, 1
        if type(fc) == "table" then
            fr = type(fc[1]) == "number" and fc[1] or 1
            fg = type(fc[2]) == "number" and fc[2] or 1
            fb = type(fc[3]) == "number" and fc[3] or 1
            fa = type(fc[4]) == "number" and fc[4] or 1
        end
        slot._baseFillR, slot._baseFillG, slot._baseFillB, slot._baseFillA = fr, fg, fb, fa
        if slot.bar and type(slot.bar.SetStatusBarColor) == "function" then
            pcall(slot.bar.SetStatusBarColor, slot.bar, fr, fg, fb, fa)
        end
    end

    if slot.bar and ns.Widgets and ns.Widgets.resolveMedia then
        local tex = ns.Widgets.resolveMedia("statusbar", v and v.texture or nil,
            ns.Widgets.DEFAULT_STATUSBAR)
        if tex then pcall(slot.bar.SetStatusBarTexture, slot.bar, tex) end
    end

    if slot.bg then
        slot.bg:SetShown(not (v and v.showBackground == false))
        local c = v and v.bgColor
        if type(c) == "table" then
            slot.bg:SetColorTexture(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 0.5)
        else
            slot.bg:SetColorTexture(0, 0, 0, 0.5)
        end
    end

    local wantBorder = v and v.showBorder == true
    if wantBorder and not slot._border and slot.frame then
        local f = slot.frame
        local function side()
            local t = f:CreateTexture(nil, "OVERLAY")
            return t
        end
        local top, bottom, left, right = side(), side(), side(), side()
        top:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        top:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        top:SetHeight(1)
        bottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        bottom:SetHeight(1)
        left:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        left:SetWidth(1)
        right:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        right:SetWidth(1)
        slot._border = { top = top, bottom = bottom, left = left, right = right }
    end
    if slot._border then
        local c = (v and type(v.borderColor) == "table") and v.borderColor or { 0, 0, 0, 1 }
        for _, t in pairs(slot._border) do
            t:SetColorTexture(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1)
            t:SetShown(wantBorder)
        end
    end
end

function BarDisplay:DestroyBars()
    for i = 1, #self.bars do
        local b = self.bars[i]
        if b then
            if b.pandemicGlow then
                if b.pandemicGlow.animGroup and b.pandemicGlow.animGroup:IsPlaying() then
                    pcall(b.pandemicGlow.animGroup.Stop, b.pandemicGlow.animGroup)
                end
                pcall(b.pandemicGlow.Hide, b.pandemicGlow)
                pcall(b.pandemicGlow.SetParent, b.pandemicGlow, nil)
                b.pandemicGlow = nil
            end
            if b.frame then
                b.frame:Hide()
                b.frame:ClearAllPoints()
                b.frame:SetParent(nil)
            end
        end
        self.bars[i] = nil
    end
end

function BarDisplay:BuildActive()
    if not self:Enabled() then return {} end
    local viewer = getViewer(BAR_VIEWER_NAME)

    local preview = cdmPreviewOpen()
    local active = buildActiveFromCatalog("TrackedBars", preview) or {}

    if #active == 0 and _lowTimeStats.pvEnabled() then
        active = _lowTimeStats.pvBuild()
    end

    local viewerShown = false
    if viewer and type(viewer.IsShown) == "function" then
        local okSh, s = pcall(viewer.IsShown, viewer)
        if okSh then viewerShown = s end
    end
    dlogPipeline("Bar", viewerShown, #active, #active, active)
    return active
end

function BarDisplay:RenderActive(active, suppressSet)
    active = active or {}
    local ok, err = pcall(self._RenderActiveImpl, self, active, suppressSet)
    if not ok then
        dwarnOnce("renderactive-bar-throw",
            "[AURA RENDER ERROR] BarDisplay:RenderActive threw: %s (combat=%s)",
            tostring(err), tostring(InCombatLockdown and InCombatLockdown() or false))
        Auras._lastRenderError = {
            kind = "bar", err = tostring(err),
            at = (GetTime and GetTime()) or 0,
            combat = (InCombatLockdown and InCombatLockdown()) and true or false,
        }
    end
end

function BarDisplay:_RenderActiveImpl(active, suppressSet)
    if not self:Enabled() then
        for i = 1, #self.bars do
            local slot = self.bars[i]
            if slot and slot.frame then pcall(slot.frame.Hide, slot.frame) end
            if slot then pcall(applyPandemicGlow, slot, false, nil) end
        end
        self.activeCount = 0
        if self.container then self.container:SetAlpha(0) end
        return
    end
    if self.container then self.container:SetAlpha(1) end
    active = active or {}
    suppressSet = suppressSet or {}
    if Auras._lowTimeDebug then Auras._lowTimeDebug.bar = nil end

    if next(suppressSet) ~= nil then
        local compact = {}
        for i = 1, #active do
            if not suppressSet[i] then
                compact[#compact + 1] = active[i]
            end
        end
        active = compact
    end

    local o = self:Opts()
    local showName  = o.showName ~= false
    local showTimer = o.showTimer ~= false
    local showIcon  = o.showIcon ~= false
    local needed = #active

    local anchor = self.anchor or ns:GetAnchor(self.anchorName)
    local barW, barH, spacing = resolveTrackedBarsGeometry(tonumber(o.barHeight), tonumber(o.spacing))

    dtrace("BarDisplay:RenderActive barW=%s barH=%d spacing=%d anchorW=%.0f",
        tostring(barW), barH or 0, spacing or 0,
        (anchor and anchor.frame and anchor.frame:GetWidth()) or 0)

    local shown = 0
    for i = 1, needed do
        local item = active[i]
        local slot = self:GetBarSlot(i)
        if slot and slot.frame and anchor and anchor.frame then
            local f = slot.frame
            f:ClearAllPoints()
            f:SetHeight(barH)
            local y = (i - 1) * (barH + spacing)
            f:SetWidth(barW)
            f:SetPoint("BOTTOMLEFT", anchor.frame, "BOTTOMLEFT", 0, y)

            if slot._iconShown ~= showIcon then
                slot._iconShown = showIcon
                if slot.icon then
                    if showIcon then slot.icon:Show() else slot.icon:Hide() end
                end
                if slot.bar then
                    slot.bar:ClearAllPoints()
                    if showIcon and slot.icon then
                        slot.bar:SetPoint("LEFT", slot.icon, "RIGHT", 2, 0)
                    else
                        slot.bar:SetPoint("LEFT", f, "LEFT", 0, 0)
                    end
                    slot.bar:SetPoint("RIGHT", f, "RIGHT", 0, 0)
                end
            end

            local isIdle = type(item) == "table" and item._idle == true

            pcall(slot.frame.SetAlpha, slot.frame, isIdle and 0.5 or 1)
            if slot.frame.Show then pcall(slot.frame.Show, slot.frame) end
            Auras._forceShowOwnFrame(self.container, 1)
            Auras._forceShowOwnFrame(slot.frame, isIdle and 0.5 or 1)
            if slot.icon and slot._iconShown ~= false then Auras._forceShowOwnFrame(slot.icon, 1) end
            if slot.bar then Auras._forceShowOwnFrame(slot.bar, 1) end
            Auras._repairOwnParentChain(slot.frame)
            shown = shown + 1

            do
                local okTex = pcall(function()
                    local tex = readItemIconTexture(item)
                    if slot.icon and Auras._validTexture(tex) then slot.icon:SetTexture(tex) end
                end)
                if not okTex then Auras._renderTrace("TrackedBars", item, i, true, "caught:texture") end
            end

            if isIdle then
                pcall(function()
                    if slot.nameFS then
                        slot.nameFS:SetText(ns._auraSafeText(readBarName(item)))
                    end
                    if slot.durFS then slot.durFS:SetText("") end
                    Auras._clearBarCountdownNumbers(slot)
                    if slot.bar then
                        if type(slot.bar.SetTimerDuration) == "function" then
                            pcall(slot.bar.SetTimerDuration, slot.bar, nil)
                        end
                        slot.bar:SetMinMaxValues(0, 1)
                        slot.bar:SetValue(0)
                        slot.bar:SetStatusBarColor(
                            type(slot._baseFillR) == "number" and slot._baseFillR or 1,
                            type(slot._baseFillG) == "number" and slot._baseFillG or 1,
                            type(slot._baseFillB) == "number" and slot._baseFillB or 1,
                            type(slot._baseFillA) == "number" and slot._baseFillA or 1)
                    end
                    slot._liveDurObj = nil
                    slot._liveDurObjType = nil
                    slot._liveDurObjSecret = nil
                end)
                pcall(clearSecretPandemicVisual, slot)
                pcall(applyPandemicGlow, slot, false, nil)
                Auras.RecordActiveGlowEval(slot, "skip:idle-row")
                Auras._renderTrace("TrackedBars", item, i, true, "reached-end", slot.frame,
                    "alphaBranch=idle(0.5) active=no")
            else
                local sid
                local okSid, sidRes = pcall(readItemSpellID, item)
                if okSid then sid = sidRes end
                slot._mirrorSpellID = sid

                local mirrorChild
                if type(item) == "table" and type(item.cooldownID) == "number" then
                    local okC, c = pcall(findLiveViewerChildByCooldownID, item.cooldownID, "TrackedBars")
                    if okC and type(c) == "table" then mirrorChild = c end
                end
                local mirrored = false
                local mirrorInactive = false
                if mirrorChild then
                    local okM, mActive = pcall(Auras._mirrorBlizzBarIntoSlot, slot, mirrorChild, {
                        showName  = showName,
                        showTimer = showTimer,
                        showIcon  = showIcon,
                    })
                    if okM then
                        if mActive == false then
                            mirrorInactive = true
                        else
                            mirrored = true
                        end
                    else
                        Auras._renderTrace("TrackedBars", item, i, true, "caught:mirror")
                    end
                end

                local durText = ""
                local isSummon = type(item) == "table" and item._summonDurObj ~= nil
                if mirrorInactive then
                    pcall(function()
                        if slot.frame then slot.frame:SetAlpha(0.5) end
                        if slot.nameFS then slot.nameFS:SetText(ns._auraSafeText(readBarName(item))) end
                        if slot.durFS then slot.durFS:SetText("") end
                        Auras._clearBarCountdownNumbers(slot)
                        if slot.bar then
                            if type(slot.bar.SetTimerDuration) == "function" then
                                pcall(slot.bar.SetTimerDuration, slot.bar, nil)
                            end
                            slot.bar:SetMinMaxValues(0, 1)
                            slot.bar:SetValue(0)
                            slot.bar:SetStatusBarColor(
                                type(slot._baseFillR) == "number" and slot._baseFillR or 1,
                                type(slot._baseFillG) == "number" and slot._baseFillG or 1,
                                type(slot._baseFillB) == "number" and slot._baseFillB or 1,
                                type(slot._baseFillA) == "number" and slot._baseFillA or 1)
                        end
                        slot._liveDurObj = nil
                        slot._liveDurObjType = nil
                        slot._liveDurObjSecret = nil
                    end)
                    pcall(clearSecretPandemicVisual, slot)
                    pcall(applyPandemicGlow, slot, false, nil)
                    Auras.RecordActiveGlowEval(slot, "skip:mirror-inactive")
                    Auras._renderTrace("TrackedBars", item, i, true, "reached-end", slot.frame,
                        "alphaBranch=idle(0.5) active=no src=viewerState arm=mirror:inactive")
                elseif mirrored then
                    durText = type(slot._mirrorDurText) == "string" and slot._mirrorDurText
                        or ns._auraSafeText(slot._mirrorDurText)
                    do
                        local okCurve, curveApplied = pcall(Auras._applyBarLowTimeCurve, slot, item, sid)
                        if not okCurve or curveApplied ~= true then
                            if slot.durFS then
                                pcall(Auras._applyAuraTimerTextColor, slot.durFS, durText, "bar")
                            end
                        end
                    end
                else
                do
                    local okName = pcall(function()
                        if slot.nameFS then
                            local nameText = ""
                            if showName then nameText = ns._auraSafeText(readBarName(item)) end
                            slot.nameFS:SetText(nameText)
                        end
                    end)
                    if not okName then Auras._renderTrace("TrackedBars", item, i, true, "caught:name") end
                end

                local okFill = pcall(applyBarFill, slot, item, sid)
                if not okFill then Auras._renderTrace("TrackedBars", item, i, true, "caught:cooldown") end

                local durDigits = false
                if showTimer then
                    local digitDurObj = isSummon and item._summonDurObj or slot._liveDurObj
                    local okDigits, drove = pcall(Auras._driveBarCountdownNumbers, slot, digitDurObj)
                    durDigits = okDigits and drove == true
                    if not okDigits then Auras._renderTrace("TrackedBars", item, i, true, "caught:count") end
                else
                    pcall(Auras._clearBarCountdownNumbers, slot)
                end
                if showTimer and not durDigits then
                    local okDur, dt = pcall(readBarDuration, item)
                    if okDur then durText = ns._auraSafeText(dt) end
                end
                pcall(function()
                    if slot.durFS then slot.durFS:SetText(durText) end
                end)
                do
                    local okCurve, curveApplied = pcall(Auras._applyBarLowTimeCurve, slot, item, sid)
                    if not okCurve or curveApplied ~= true then
                        if slot.durFS then
                            pcall(Auras._applyAuraTimerTextColor, slot.durFS, durText, "bar")
                        end
                        pcall(Auras._applyBarLowTimeFill, slot, durText)
                    end
                end
                end

                if not mirrorInactive then
                local okGlow = pcall(function()
                local pOpts = pandemicOpts(self.mod)
                local okPP, perPandOn, perPandOpts = pcall(Auras.PerAuraPandemicGlow, item, pOpts)
                if not okPP then perPandOn, perPandOpts = nil, nil end
                local effPOpts = (perPandOn == true and perPandOpts) or pOpts
                local pandemicOn = false
                local pandemicSource = "none"
                local pandemicDur = nil
                local pandemicEnabled
                if perPandOn == false then
                    pandemicEnabled = false
                elseif perPandOn == true then
                    pandemicEnabled = true
                else
                    pandemicEnabled = pOpts ~= nil and pOpts.enabled == true
                end
                if pandemicEnabled then
                    local okP, glowOn, src, durObj = pcall(evaluatePandemicForItem, item, effPOpts, "bar")
                    if okP then
                        if safeTruthy(glowOn) then pandemicOn = true end
                        if type(src) == "string" then pandemicSource = src end
                        if ns._auraPresentTruthy(durObj) then pandemicDur = durObj end
                    else
                        local cdIDForLog = type(item) == "table" and tonumber(item.cooldownID) or nil
                        if cdIDForLog then
                            pandemicLogOnce(cdIDForLog, "evaluatePandemicForItem pcall failed kind=bar",
                                tostring(glowOn))
                        end
                    end
                end
                local overlayOwned = false
                if pandemicSource == "secret-visual" then
                    if ns._auraPresentTruthy(pandemicDur) then
                        local svActive
                        local okAO, ao = pcall(Auras._secretVisualActiveOpts, item, activeGlowOpts(self.mod, "bar"))
                        if okAO then svActive = ao end
                        local thrSecs
                        local okTS, ts = pcall(Auras._pandemicThresholdSeconds, item, effPOpts)
                        if okTS then thrSecs = ts end
                        local okSV, applied, svMode = pcall(applySecretPandemicVisual, slot, pandemicDur, effPOpts, svActive, thrSecs)
                        overlayOwned = okSV and applied == true
                        if overlayOwned then
                            pcall(Auras._releaseSlotGlowFX, slot)
                            if svMode == "two-zone" then
                                Auras.RecordActiveGlowEval(slot, "applied:two-zone-curve")
                            elseif svActive then
                                Auras.RecordActiveGlowEval(slot, "overlay-owned:secret-visual(two-zone-pending)")
                            else
                                Auras.RecordActiveGlowEval(slot, "overlay-owned:secret-visual")
                            end
                        end
                    end
                elseif pandemicOn then
                    pcall(clearSecretPandemicVisual, slot)
                    pcall(applyPandemicGlow, slot, true, effPOpts)
                    overlayOwned = true
                    Auras.RecordActiveGlowEval(slot, "overlay-owned:pandemic-pulse")
                end
                if not overlayOwned then
                    pcall(clearSecretPandemicVisual, slot)
                    local agOpts = activeGlowOpts(self.mod, "bar")
                    local perOn, perOpts, agNote = Auras._resolveActiveGlowSticky(item)
                    local aiID = type(item) == "table" and item.auraInstanceID or nil
                    local hasAura = not isSecret(aiID) and aiID ~= nil
                    local activeOn
                    local agReason
                    if perOn == true then
                        activeOn = hasAura
                        agReason = hasAura and "applied:per-aura"
                            or "skip:per-aura-on-but-no-live-aura"
                    elseif perOn == false then
                        activeOn = false
                        agReason = "skip:per-aura-off"
                    else
                        activeOn = agOpts and agOpts.enabled == true and hasAura
                        if activeOn then
                            agReason = "applied:global"
                        elseif agOpts and agOpts.enabled == true then
                            agReason = "skip:global-on-but-no-live-aura"
                        else
                            agReason = "skip:per-aura-unset+global-off"
                        end
                    end
                    if agNote then
                        agReason = agReason .. " (" .. agNote .. ")"
                    end
                    Auras.RecordActiveGlowEval(slot, agReason)
                    if activeOn then
                        pcall(applyAuraGlow, slot, true, (perOn == true) and perOpts or agOpts)
                    else
                        pcall(applyPandemicGlow, slot, false, pOpts)
                    end
                end
                end)
                if not okGlow then Auras._renderTrace("TrackedBars", item, i, true, "caught:glow") end
                local presenceTag
                if mirrored then
                    presenceTag = "viewerState"
                elseif isSummon then
                    presenceTag = "summon"
                elseif type(item) == "table" and item.activeAuraSource == "viewerState" then
                    presenceTag = "viewerState"
                elseif type(item) == "table" and item.activeAuraSource == "spellIDprobe" then
                    presenceTag = "spellIDprobe"
                elseif type(item) == "table" and item._fromViewer then
                    presenceTag = "viewerChild"
                elseif type(item) == "table" and item.auraInstanceID == nil then
                    presenceTag = "live-secretInst"
                else
                    presenceTag = "reconstruct"
                end
                local fillState = "fill?"
                if mirrored then
                    fillState = "fillMirror"
                elseif slot._liveDurObj ~= nil then
                    fillState = "fill>0"
                elseif type(slot.bar) == "table" and type(slot.bar.GetValue) == "function" then
                    local okV, v = pcall(slot.bar.GetValue, slot.bar)
                    if okV and type(v) == "number" and not isSecret(v) then
                        fillState = v > 0 and "fill>0" or "fill=0"
                    elseif okV and isSecret(v) then
                        fillState = "fillSecret"
                    end
                end
                local armTag = mirrored and "mirror:blizzBar" or "reconstruct"
                Auras._renderTrace("TrackedBars", item, i, true, "reached-end", slot.frame,
                    "alphaBranch=present(1.0) active=yes src=" .. presenceTag .. " arm=" .. armTag
                    .. " " .. fillState)
                end
            end

            do
                local fw, iw = -1, -1
                if type(f.GetWidth) == "function" then
                    local okW, ww = pcall(f.GetWidth, f)
                    if okW and type(ww) == "number" then fw = ww end
                end
                if slot.bar and type(slot.bar.GetWidth) == "function" then
                    local okIW, ww = pcall(slot.bar.GetWidth, slot.bar)
                    if okIW and type(ww) == "number" then iw = ww end
                end
                dtrace("BarDisplay:slot[%d] barW=%s frameW=%.0f innerW=%.0f preview=%s",
                    i, tostring(barW), fw, iw, tostring(type(item) == "table" and item._preview == true))
            end
        end
    end

    for i = needed + 1, #self.bars do
        local slot = self.bars[i]
        if slot and slot.frame then
            pcall(slot.frame.Hide, slot.frame)
            pcall(slot.frame.ClearAllPoints, slot.frame)
            pcall(applyPandemicGlow, slot, false, nil)
            Auras._clearBarCountdownNumbers(slot)
        end
    end

    self._lastRenderShown = shown
    self.activeCount = needed
    if self.container then self.container:SetAlpha(needed == 0 and 0 or 1) end

    if needed > 0 and ns.AutoFitAnchor then
        local fitH = needed * barH + math.max(0, needed - 1) * spacing
        local fitW = barW
        if fitW and fitW > 0 and fitH > 0 then
            ns:AutoFitAnchor(self.anchorName, fitW, fitH)
        end
    end

    dtrace("BarDisplay:Refresh needed=%d shown=%d pool=%d barH=%d",
        needed, shown, #self.bars, barH)
end

function BarDisplay:Refresh()
    local active = self:BuildActive() or {}
    self:RenderActive(active, nil)
end

function BarDisplay:Layout(count)
    local anchor = self.anchor or ns:GetAnchor(self.anchorName)
    if not (anchor and anchor.frame) then return end
    if count == 0 then return end
    local o = self:Opts()
    local barW, barH, spacing = resolveTrackedBarsGeometry(tonumber(o.barHeight), tonumber(o.spacing))

    for i = 1, count do
        local slot = self.bars[i]
        if slot and slot.frame then
            local f = slot.frame
            f:ClearAllPoints()
            f:SetHeight(barH)
            local y = (i - 1) * (barH + spacing)
            f:SetWidth(barW)
            f:SetPoint("BOTTOMLEFT", anchor.frame, "BOTTOMLEFT", 0, y)
        end
    end
end

function BarDisplay:ApplyVisualOptions()
    local nameStyle, timerStyle = getTrackedBarsTextStyles()
    for i = 1, #self.bars do
        local slot = self.bars[i]
        if slot then
            if slot.nameFS then applyBarTextStyle(slot.nameFS, slot.bar, nameStyle, "LEFT") end
            if slot.durFS  then applyBarTextStyle(slot.durFS,  slot.bar, timerStyle, "RIGHT") end
            if slot.cdNumbers then Auras._styleBarCountdownNumbers(slot.cdNumbers, slot.bar, timerStyle) end
            pcall(self.ApplyBarStyle, self, slot)
        end
    end
    if self.mod and self.mod.RequestRefresh then
        pcall(self.mod.RequestRefresh, self.mod)
    end
end

function Auras:Refresh()
    if not self._enabled then return end
    local iconActive, barActive = {}, {}
    if self.IconDisplay and self.IconDisplay.BuildActive then
        local ok, res = pcall(self.IconDisplay.BuildActive, self.IconDisplay)
        if ok then
            iconActive = res or {}
        else
            dwarn("[AURA REFRESH ERROR] IconDisplay:BuildActive threw: %s (combat=%s)",
                tostring(res), tostring(InCombatLockdown and InCombatLockdown() or false))
        end
    end
    if self.BarDisplay and self.BarDisplay.BuildActive then
        local ok, res = pcall(self.BarDisplay.BuildActive, self.BarDisplay)
        if ok then
            barActive = res or {}
        else
            dwarn("[AURA REFRESH ERROR] BarDisplay:BuildActive threw: %s (combat=%s)",
                tostring(res), tostring(InCombatLockdown and InCombatLockdown() or false))
        end
    end
    local okDedup, s1, s2 = pcall(self._ComputeCrossViewerDedup, self, iconActive, barActive)
    local iconSuppress, barSuppress
    if okDedup then
        iconSuppress, barSuppress = s1, s2
    else
        iconSuppress, barSuppress = {}, {}
        dwarn("[AURA REFRESH ERROR] _ComputeCrossViewerDedup threw: %s", tostring(s1))
    end

    self._lastDedup = {
        iconCount      = #iconActive,
        barCount       = #barActive,
        iconSuppressed = iconSuppress,
        barSuppressed  = barSuppress,
        iconActive     = iconActive,
        barActive      = barActive,
    }

    if self.IconDisplay and self.IconDisplay.RenderActive then
        self.IconDisplay:RenderActive(iconActive, iconSuppress)
    elseif self.IconDisplay then
        self.IconDisplay:Refresh()
    end
    if self.BarDisplay and self.BarDisplay.RenderActive then
        self.BarDisplay:RenderActive(barActive, barSuppress)
    elseif self.BarDisplay then
        self.BarDisplay:Refresh()
    end
end

function Auras:RequestRefresh()
    if self._refreshScheduled then return end
    self._refreshScheduled = true
    C_Timer.After(0, function()
        self._refreshScheduled = false
        self:Refresh()
    end)
end

function Auras:PrewarmDisplays()
    if not self._enabled then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local iconCount = 8
    local barCount = 8
    if type(buildAuraCatalog) == "function" then
        local okI, ci = pcall(buildAuraCatalog, "TrackedIcon")
        if okI and type(ci) == "table" then iconCount = math.max(iconCount, #ci) end
        local okB, cb = pcall(buildAuraCatalog, "TrackedBars")
        if okB and type(cb) == "table" then barCount = math.max(barCount, #cb) end
    end
    if self.IconDisplay and self.IconDisplay.PrewarmSlots then
        pcall(self.IconDisplay.PrewarmSlots, self.IconDisplay, iconCount)
    end
    if self.BarDisplay and self.BarDisplay.PrewarmSlots then
        pcall(self.BarDisplay.PrewarmSlots, self.BarDisplay, barCount)
    end
end

function Auras:Rebuild()
    if self.IconDisplay then self.IconDisplay:DestroyIcons() end
    if self.BarDisplay then self.BarDisplay:DestroyBars() end
    resetPandemicState()
    self:Refresh()
end

function Auras:_ResyncScope()
    if not self._enabled then return end
    local newKey = self:GetCurrentScopeKey()
    if newKey == self._currentScopeKey then
        self:RequestRefresh()
        return
    end
    local oldKey = self._currentScopeKey
    self._currentScopeKey = newKey
    ensureScope(newKey)
    dlog("scope changed: %s -> %s", tostring(oldKey), tostring(newKey))
    self:Rebuild()
end

function Auras:SetDisplayEnabled(which, enabled)
    local p = self.profileRef
    if not p then return false, "profile not ready" end
    if which == "icons" then
        p.icons = p.icons or {}
        p.icons.enabled = enabled and true or false
    elseif which == "bars" then
        p.bars = p.bars or {}
        p.bars.enabled = enabled and true or false
    else
        return false, "which must be icons|bars"
    end
    self:Refresh()
    return true
end

function Auras:IsDisplayEnabled(which)
    local p = self.profileRef or {}
    if which == "icons" then
        return not (p.icons and p.icons.enabled == false)
    elseif which == "bars" then
        return not (p.bars and p.bars.enabled == false)
    end
    return false
end

function Auras:GetActiveCount(which)
    if which == "icons" then
        return (self.IconDisplay and self.IconDisplay.activeCount) or 0
    elseif which == "bars" then
        return (self.BarDisplay and self.BarDisplay.activeCount) or 0
    end
    local i = (self.IconDisplay and self.IconDisplay.activeCount) or 0
    local b = (self.BarDisplay and self.BarDisplay.activeCount) or 0
    return i + b
end

function Auras:Rescan()
    self:Rebuild()
    return true
end

function Auras:GetCrossViewerPrefer()
    local p = self.profileRef
    local v = p and p.crossViewerPrefer
    if v ~= "bar" and v ~= "icon" then return "bar" end
    return v
end

function Auras:SetCrossViewerPrefer(which)
    local p = self.profileRef
    if not p then return false, "profile not ready" end
    if which ~= "bar" and which ~= "icon" then
        return false, "which must be bar|icon"
    end
    p.crossViewerPrefer = which
    self:RequestRefresh()
    return true
end

function Auras:GetIconDurationSwipe()
    local p = self.profileRef
    local o = p and p.icons
    return not (type(o) == "table" and o.showDurationSwipe == false)
end

function Auras:SetIconDurationSwipe(flag)
    local p = self.profileRef
    if not p then return false, "profile not ready" end
    local value = flag and true or false
    p.icons = p.icons or {}
    p.icons.showDurationSwipe = value
    local disp = self.IconDisplay
    if disp and disp.icons then
        for _, w in pairs(disp.icons) do
            if w and w.SetDrawSwipe then
                pcall(w.SetDrawSwipe, w, value)
            end
        end
    end
    return true
end

function Auras:GetBarShowIcon()
    local p = self.profileRef
    local o = p and p.bars
    return not (type(o) == "table" and o.showIcon == false)
end

function Auras:SetBarShowIcon(flag)
    local p = self.profileRef
    if not p then return false, "profile not ready" end
    p.bars = p.bars or {}
    p.bars.showIcon = flag and true or false
    self:RequestRefresh()
    return true
end

function Auras:GetBarShowInactive()
    local p = self.profileRef
    local o = p and p.bars
    return type(o) == "table" and o.showInactive == true
end

function Auras:SetBarShowInactive(flag)
    local p = self.profileRef
    if not p then return false, "profile not ready" end
    p.bars = p.bars or {}
    p.bars.showInactive = flag and true or false
    self:RequestRefresh()
    return true
end

function Auras:OnAuraEnabledChanged(entryKey, enabled)
    self:RequestRefresh()
    return true
end

function Auras:GetForceViewerPopulated()
    local p = self.profileRef
    return p and p.forceViewerPopulated == true
end

function Auras:SetForceViewerPopulated(flag)
    local p = self.profileRef
    if not p then return false, "profile not ready" end
    local want = flag and true or false
    local changed = (p.forceViewerPopulated == true) ~= want
    p.forceViewerPopulated = want
    if self._enabled and self.ApplyViewerVisibilityMode then
        pcall(self.ApplyViewerVisibilityMode, self)
    end
    return true, changed
end

function Auras:GetRespectCDMHidden()
    local p = self.profileRef
    return p and p.respectCDMHidden == true
end

function Auras:SetRespectCDMHidden(flag)
    local p = self.profileRef
    if not p then return false, "profile not ready" end
    local want = flag and true or false
    local changed = (p.respectCDMHidden == true) ~= want
    p.respectCDMHidden = want
    if changed and self._enabled then
        if self.ScanBlizzardCDMAuras then
            pcall(self.ScanBlizzardCDMAuras, self)
        end
        if self.Refresh then
            pcall(self.Refresh, self)
        end
    end
    return true, changed
end

function Auras:OpenBlizzardCDMSettings()
    if InCombatLockdown and InCombatLockdown() then
        return false, "combat"
    end
    local panel = _G and _G.CooldownViewerSettings
    if type(panel) ~= "table" or type(panel.TogglePanel) ~= "function" then
        return false, "unavailable"
    end
    local shown = type(panel.IsShown) == "function" and panel:IsShown()
    if shown then return true, "already-open" end
    local ok = pcall(panel.TogglePanel, panel)
    if not ok then return false, "error" end
    return true, "opened"
end

function Auras._lowTimeTextClamp01(v)
    if v < 0 then return 0 elseif v > 1 then return 1 end
    return v
end

function Auras._invalidateLowTimeCurves()
    Auras._lowTimeCurveGen = (Auras._lowTimeCurveGen or 0) + 1
    Auras._lowTimeCurves = {}
    Auras._lowTimeCurveFailed = false
end

function Auras._ensureLowTimeText(p)
    if type(p.lowTimeText) ~= "table" then
        p.lowTimeText = {
            enabled = false, threshold = 5,
            normalR = 1, normalG = 1, normalB = 1, normalA = 0.9,
            lowR = 1, lowG = 0.15, lowB = 0.10, lowA = 1,
        }
    end
    return p.lowTimeText
end

function Auras:GetLowTimeTextEnabled()
    local p = self.profileRef
    local c = p and p.lowTimeText
    return type(c) == "table" and c.enabled == true
end

function Auras:GetLowTimeTextConfig()
    local p = self.profileRef
    local c = p and p.lowTimeText
    if type(c) ~= "table" then
        return false, 5, 1, 1, 1, 0.9, 1, 0.15, 0.10, 1
    end
    return c.enabled == true,
        tonumber(c.threshold) or 5,
        tonumber(c.normalR) or 1, tonumber(c.normalG) or 1,
        tonumber(c.normalB) or 1, tonumber(c.normalA) or 0.9,
        tonumber(c.lowR) or 1, tonumber(c.lowG) or 0.15,
        tonumber(c.lowB) or 0.10, tonumber(c.lowA) or 1
end

function Auras:SetLowTimeTextEnabled(flag)
    local p = self.profileRef
    if not p then return false, "profile not ready" end
    local c = Auras._ensureLowTimeText(p)
    local want = flag and true or false
    local changed = (c.enabled == true) ~= want
    c.enabled = want
    if self._enabled and self.RequestRefresh then
        pcall(self.RequestRefresh, self)
    end
    return true, changed
end

function Auras:SetLowTimeTextThreshold(n)
    local p = self.profileRef
    if not p then return false, "profile not ready" end
    local v = tonumber(n)
    if not v then return false, "threshold must be a number 1..60 (seconds)" end
    if v < 1 then v = 1 elseif v > 60 then v = 60 end
    local c = Auras._ensureLowTimeText(p)
    c.threshold = v
    Auras._invalidateLowTimeCurves()
    if self._enabled and self.RequestRefresh then
        pcall(self.RequestRefresh, self)
    end
    return true, v
end

function Auras:SetLowTimeTextLowRGB(r, g, b)
    local p = self.profileRef
    if not p then return false, "profile not ready" end
    local rr, gg, bb = tonumber(r), tonumber(g), tonumber(b)
    if not (rr and gg and bb) then return false, "r/g/b must be numbers 0..1" end
    rr, gg, bb = Auras._lowTimeTextClamp01(rr), Auras._lowTimeTextClamp01(gg), Auras._lowTimeTextClamp01(bb)
    local c = Auras._ensureLowTimeText(p)
    c.lowR, c.lowG, c.lowB = rr, gg, bb
    Auras._invalidateLowTimeCurves()
    if self._enabled and self.RequestRefresh then
        pcall(self.RequestRefresh, self)
    end
    return true, rr, gg, bb
end

function Auras:SetLowTimeTextNormalRGB(r, g, b)
    local p = self.profileRef
    if not p then return false, "profile not ready" end
    local rr, gg, bb = tonumber(r), tonumber(g), tonumber(b)
    if not (rr and gg and bb) then return false, "r/g/b must be numbers 0..1" end
    rr, gg, bb = Auras._lowTimeTextClamp01(rr), Auras._lowTimeTextClamp01(gg), Auras._lowTimeTextClamp01(bb)
    local c = Auras._ensureLowTimeText(p)
    c.normalR, c.normalG, c.normalB = rr, gg, bb
    Auras._invalidateLowTimeCurves()
    if self._enabled and self.RequestRefresh then
        pcall(self.RequestRefresh, self)
    end
    return true, rr, gg, bb
end

function Auras:_StartBarPreviewTicker()
    if self._barPreviewTicker then return end
    if not (C_Timer and C_Timer.NewTicker) then return end
    local mod = self
    self._barPreviewTicker = C_Timer.NewTicker(0.1, function()
        if not (_lowTimeStats.preview and _lowTimeStats.preview.enabled) then
            if mod._barPreviewTicker then
                pcall(mod._barPreviewTicker.Cancel, mod._barPreviewTicker)
                mod._barPreviewTicker = nil
            end
            return
        end
        if mod.RequestRefresh then pcall(mod.RequestRefresh, mod) end
    end)
end

function Auras:_StopBarPreviewTicker()
    if self._barPreviewTicker then
        pcall(self._barPreviewTicker.Cancel, self._barPreviewTicker)
        self._barPreviewTicker = nil
    end
end

function Auras:SetBarPreviewEnabled(flag, count)
    local pv = _lowTimeStats.preview
    local want = (flag == true)
    if type(count) == "number" and count >= 1 and count <= 3 then
        pv.count = math.floor(count + 0.5)
    end
    if want == pv.enabled then
        if want then self:_StartBarPreviewTicker() end
        return true, ("bar preview already %s (count=%d)"):format(
            want and "ON" or "OFF", pv.count)
    end
    pv.enabled = want
    if want then
        self:_StartBarPreviewTicker()
    else
        self:_StopBarPreviewTicker()
        wipe(pv.durs)
        wipe(pv.lastPct)
    end
    if self.RequestRefresh then pcall(self.RequestRefresh, self) end
    return true, ("bar preview -> %s (count=%d, %ds loop)"):format(
        want and "ON" or "OFF", pv.count, pv.loopSec)
end

function Auras:IsBarPreviewEnabled()
    return _lowTimeStats.preview.enabled == true
end

function Auras:SetBarPreviewAuto(flag)
    local auto = (flag == true)
    if auto == self._barPreviewAuto then return end
    self._barPreviewAuto = auto
    if auto then
        self:SetBarPreviewEnabled(true)
    elseif not self._barPreviewManual then
        self:SetBarPreviewEnabled(false)
    end
end

function Auras:SetBarPreviewManual(flag, count)
    self._barPreviewManual = (flag == true)
    if self._barPreviewManual or self._barPreviewAuto then
        return self:SetBarPreviewEnabled(true, count)
    end
    return self:SetBarPreviewEnabled(false)
end

function Auras:GetBarPreviewStats()
    local pv = _lowTimeStats.preview
    local parts = {}
    for i = 1, pv.count do
        local p = pv.lastPct[i]
        parts[i] = (type(p) == "number") and string.format("%.2f", p) or "-"
    end
    return pv.enabled == true, pv.count, table.concat(parts, ",")
end

function Auras:LookupSpellID(spellID)
    local n = tonumber(spellID)
    if not n then return nil, "spellID must be a number" end
    local lines = {}
    local function push(fmt, ...)
        if select("#", ...) > 0 then
            lines[#lines + 1] = string.format(fmt, ...)
        else
            lines[#lines + 1] = fmt
        end
    end

    local single = self:GetViewerChildBySpellID(n)
    local multi  = self:GetAllViewerChildrenBySpellID(n)

    push("=== /tenui auras lookup spellID=%d ===", n)
    if not single then
        push("  viewer-aura map: |cffaaaaaa(no match)|r")
        push("  (try /tenui auras rescan if you expected a match)")
        return lines
    end

    local function childInfo(c)
        if type(c) ~= "table" then return "?", "?", "?", "?" end
        local parent = type(c.GetParent) == "function" and c:GetParent() or nil
        local parentName = (parent and parent.GetName and parent:GetName()) or "?"
        local cdInfo = c.cooldownInfo
        local baseSID = (type(cdInfo) == "table" and cdInfo.spellID) or "?"
        local cdID = tonumber(c.cooldownID) or "?"
        local aiID = c.auraInstanceID
        return parentName, tostring(baseSID), tostring(cdID), tostring(aiID)
    end

    local pName, baseSID, cdID, aiID = childInfo(single)
    push("  viewer-aura map (single): parent=%s baseSpellID=%s cdID=%s auraInstanceID=%s",
        pName, baseSID, cdID, aiID)

    if multi and #multi > 1 then
        push("  viewer-aura map (multi): %d entries", #multi)
        for i = 1, #multi do
            local pN, bS, cI, aI = childInfo(multi[i])
            push("    [%d] parent=%s baseSpellID=%s cdID=%s auraInstanceID=%s",
                i, pN, bS, cI, aI)
        end
    end

    local last = self._lastDedup or {}
    local inIcon, inBar = false, false
    local iconSlot, barSlot
    if type(last.iconActive) == "table" then
        for i = 1, #last.iconActive do
            local sid = readItemBaseSpellID(last.iconActive[i])
            if sid == n then inIcon = true iconSlot = i break end
        end
    end
    if type(last.barActive) == "table" then
        for i = 1, #last.barActive do
            local sid = readItemBaseSpellID(last.barActive[i])
            if sid == n then inBar = true barSlot = i break end
        end
    end
    push("  active in IconDisplay: %s%s",
        inIcon and "|cff66ff66YES|r" or "|cffaaaaaano|r",
        iconSlot and (" (slot " .. tostring(iconSlot) .. ")") or "")
    push("  active in BarDisplay : %s%s",
        inBar and "|cff66ff66YES|r" or "|cffaaaaaano|r",
        barSlot and (" (slot " .. tostring(barSlot) .. ")") or "")

    if inIcon and inBar then
        local prefer = self:GetCrossViewerPrefer()
        push("  cross-viewer overlap: |cffffd200both|r -- prefer=|cffffd200%s|r wins; loser suppressed",
            prefer)
    end

    local probeStr = "|cffaaaaaaN/A|r"
    if ns.CooldownProbe and ns.CooldownProbe.IsLive
       and C_UnitAuras and C_UnitAuras.GetAuraDuration
       and type(single) == "table" then
        local aiIDN = single.auraInstanceID
        if aiIDN ~= nil and not isSecret(aiIDN) then
            local okU, unit = pcall(function() return single.auraDataUnit end)
            if not okU or type(unit) ~= "string" or isSecret(unit) then
                unit = "player"
            end
            local okDur, durObj = pcall(C_UnitAuras.GetAuraDuration, unit, aiIDN)
            if okDur and durObj then
                local okProbe, live = pcall(ns.CooldownProbe.IsLive, ns.CooldownProbe, durObj)
                if okProbe then
                    probeStr = live and "|cff66ff66live|r" or "|cffcc6666dead|r"
                else
                    probeStr = "|cffcc6666(probe errored)|r"
                end
            else
                probeStr = "|cffaaaaaa(no DurationObject -- aura not currently applied)|r"
            end
        else
            probeStr = "|cffaaaaaa(no auraInstanceID -- not currently applied)|r"
        end
    end
    push("  CooldownProbe.IsLive  : %s", probeStr)
    return lines
end

function Auras:DumpCrossViewerDedup()
    local lines = {}
    local function push(fmt, ...)
        if select("#", ...) > 0 then
            lines[#lines + 1] = string.format(fmt, ...)
        else
            lines[#lines + 1] = fmt
        end
    end

    local last = self._lastDedup
    if type(last) ~= "table" then
        push("|cffaaaaaa(no dedup snapshot yet -- run /tenui auras rescan)|r")
        return lines
    end

    local prefer = self:GetCrossViewerPrefer()
    push("=== cross-viewer dedup snapshot ===")
    push("  prefer=|cffffd200%s|r  iconActive=%d barActive=%d  (snapshot age <= 100ms)",
        prefer, last.iconCount or 0, last.barCount or 0)

    local iconIdx = buildActiveSpellIndex(last.iconActive or {})
    local barIdx  = buildActiveSpellIndex(last.barActive  or {})
    local overlaps = {}
    for sid in pairs(iconIdx) do
        if barIdx[sid] then overlaps[#overlaps + 1] = sid end
    end
    table.sort(overlaps)

    if #overlaps == 0 then
        push("  no cross-viewer overlaps detected")
        return lines
    end

    push("  overlaps: %d spellID(s)", #overlaps)
    for k = 1, #overlaps do
        local sid = overlaps[k]
        local name
        if C_Spell and C_Spell.GetSpellName then
            local ok, nm = pcall(C_Spell.GetSpellName, sid)
            if ok and type(nm) == "string" then name = nm end
        end
        local iconItem = last.iconActive[iconIdx[sid][1]]
        local barItem  = last.barActive[barIdx[sid][1]]
        local iconCdID = (type(iconItem) == "table" and tostring(iconItem.cooldownID)) or "?"
        local barCdID  = (type(barItem)  == "table" and tostring(barItem.cooldownID))  or "?"
        local winner = prefer == "bar" and "BAR" or "ICON"
        push("    spellID=%-7d %-25s iconCdID=%s barCdID=%s winner=|cff66ff66%s|r",
            sid, ("(" .. (name or "?") .. ")"), iconCdID, barCdID, winner)
    end
    return lines
end

function Auras:GetPandemicOpts()
    local p = self.profileRef
    if not p then return nil end
    p.bars = p.bars or {}
    p.bars.pandemic = p.bars.pandemic or {}
    return p.bars.pandemic
end

function Auras:GetActiveGlowOpts(kind)
    local p = self.profileRef
    if not p then return nil end
    if kind == "icon" then
        p.icons = p.icons or {}
        p.icons.activeGlow = p.icons.activeGlow or {}
        return p.icons.activeGlow
    elseif kind == "bar" then
        p.bars = p.bars or {}
        p.bars.activeGlow = p.bars.activeGlow or {}
        return p.bars.activeGlow
    end
    return nil
end

function Auras:IsActiveGlowEnabled(kind)
    local o = self:GetActiveGlowOpts(kind)
    return o and o.enabled == true
end

function Auras:SetActiveGlowEnabled(flag, kind)
    local p = self.profileRef
    if not p then return false, "profile not ready" end
    flag = flag and true or false
    if kind == nil or kind == "icon" then
        local o = self:GetActiveGlowOpts("icon")
        if o then o.enabled = flag end
    end
    if kind == nil or kind == "bar" then
        local o = self:GetActiveGlowOpts("bar")
        if o then o.enabled = flag end
    end
    if not flag then
        if (kind == nil or kind == "bar") and self.BarDisplay and self.BarDisplay.bars then
            for i = 1, #self.BarDisplay.bars do
                local slot = self.BarDisplay.bars[i]
                if slot and slot._auraGlowKind == "active" then
                    pcall(applyAuraGlow, slot, false, nil)
                end
            end
        end
        if (kind == nil or kind == "icon") and self.IconDisplay and self.IconDisplay.icons then
            for i = 1, #self.IconDisplay.icons do
                local w = self.IconDisplay.icons[i]
                if w and w._pandemicSlot and w._pandemicSlot._auraGlowKind == "active" then
                    pcall(applyAuraGlow, w._pandemicSlot, false, nil)
                end
            end
        end
    end
    self:RequestRefresh()
    return true
end

function Auras:DumpGlowDiagnostic(limitArg)
    local limit = tonumber(limitArg) or 12
    if limit < 1 then limit = 1 end
    if limit > 50 then limit = 50 end

    local lines = {}
    local function push(fmt, ...)
        if select("#", ...) > 0 then
            lines[#lines + 1] = string.format(fmt, ...)
        else
            lines[#lines + 1] = fmt
        end
    end

    local last = self._lastDedup or {}
    local inCombat = InCombatLockdown and InCombatLockdown() or false
    local pOpts = pandemicOpts(self)
    local agIcon = self:GetActiveGlowOpts("icon")
    local agBar  = self:GetActiveGlowOpts("bar")

    push("=== /tenui auras glow dump (limit=%d) ===", limit)
    push("  combat=%s pandemic.enabled=%s iconActiveGlow=%s barActiveGlow=%s",
        tostring(inCombat),
        tostring(pOpts and pOpts.enabled == true),
        tostring(agIcon and agIcon.enabled == true),
        tostring(agBar  and agBar.enabled  == true))
    push("  iconActive=%d barActive=%d (snapshot age <= 100ms)",
        last.iconCount or 0, last.barCount or 0)
    do
        local cp = self._curvePoints
        if type(cp) == "table" and next(cp) ~= nil then
            local keys = {}
            for k in pairs(cp) do keys[#keys + 1] = k end
            table.sort(keys)
            local parts = {}
            for i = 1, #keys do
                local k = keys[i]
                parts[#parts + 1] = string.format("key=%d pts[(0.00,a=1)(%.2f,a=0)]", k, cp[k])
            end
            push("  pandemic curves built: %s", table.concat(parts, "  "))
        else
            push("  pandemic curves built: (none)")
        end
        local sa = self._secAlphaCurves
        if type(sa) == "table" and next(sa) ~= nil then
            local keys = {}
            for k in pairs(sa) do keys[#keys + 1] = k end
            table.sort(keys)
            local parts = {}
            for i = 1, #keys do
                parts[#parts + 1] = string.format("S%d(%.1fs)", keys[i], keys[i] / 10)
            end
            push("  seconds alpha curves built: %s  (two-zone-sec=%d)",
                table.concat(parts, " "), self._twoZoneSecCurveCount or 0)
        else
            push("  seconds alpha curves built: (none)  (two-zone-sec=%d)",
                self._twoZoneSecCurveCount or 0)
        end
    end

    local count = 0
    local function dumpOne(item, kind, rawIdx, slotIdx, suppressed)
        if count >= limit then return end
        count = count + 1
        local cdID
        if type(item) == "table" then
            local okCd, cd = pcall(tonumber, item.cooldownID)
            if okCd then cdID = cd end
        end
        local aiID  = type(item) == "table" and item.auraInstanceID or nil
        local unit  = type(item) == "table" and item.auraDataUnit or nil
        local hasLive = aiID ~= nil
        local classification = "?"
        if pOpts then
            local okC, c = pcall(pandemicClassifyItem, item, pOpts)
            if okC and type(c) == "string" then classification = c end
        end
        local pandemicIconExists = type(item) == "table" and item.PandemicIcon ~= nil
        local bizPandemic
        local okB, b = pcall(readBlizzardPandemic, item)
        if okB then bizPandemic = safeTruthy(b) end
        local evalResult
        local evalSource = "?"
        local evalDurSecret
        local evalErr
        if pOpts then
            local okE, r, src, durObj = pcall(evaluatePandemicForItem, item, pOpts, kind)
            if okE then
                evalResult = safeTruthy(r)
                if type(src) == "string" then evalSource = src end
                if isSecret(durObj) then
                    evalDurSecret = true
                elseif durObj ~= nil then
                    local okHS, hs = pcall(function() return durObj:HasSecretValues() end)
                    if okHS then evalDurSecret = (hs == true) end
                end
            else
                evalErr = tostring(r)
            end
        end
        local keyLine
        do
            local okK, pk, bk = pcall(itemPreferenceKeys, item)
            if okK and pk then
                keyLine = string.format("primary=%s base=%s", tostring(pk), tostring(bk))
            elseif okK then
                keyLine = "key-unresolved-secret"
            else
                keyLine = "key-resolve-error: " .. tostring(pk)
            end
        end
        local perActiveStr, perPandStr = "?", "?"
        do
            local okA2, pOn = pcall(Auras.PerAuraActiveGlow, item)
            perActiveStr = okA2 and tostring(pOn) or ("err:" .. tostring(pOn))
            local okP2, ppOn, ppOpts = pcall(Auras.PerAuraPandemicGlow, item, pOpts)
            if okP2 then
                perPandStr = tostring(ppOn)
                if ppOn == true and type(ppOpts) == "table" and ppOpts.threshold ~= nil then
                    perPandStr = perPandStr .. string.format("(thr=%s)", tostring(ppOpts.threshold))
                end
            else
                perPandStr = "err:" .. tostring(ppOn)
            end
        end
        local targetFrame, glowFrame, glowShown, glowKind, glowMode, slotTbl
        if slotIdx == nil then
        elseif kind == "icon" and self.IconDisplay and self.IconDisplay.icons then
            local w = self.IconDisplay.icons[slotIdx]
            if w then
                targetFrame = w.frame
                local pslot = w._pandemicSlot
                if pslot then
                    slotTbl   = pslot
                    glowFrame = pslot.pandemicGlow
                    glowKind  = pslot._auraGlowKind
                    if glowFrame and type(glowFrame.IsShown) == "function" then
                        local okS, s = pcall(glowFrame.IsShown, glowFrame)
                        if okS then glowShown = s end
                    end
                    if glowFrame and glowFrame._pandemicMode then
                        glowMode = glowFrame._pandemicMode
                    end
                end
            end
        elseif kind == "bar" and self.BarDisplay and self.BarDisplay.bars then
            local slot = self.BarDisplay.bars[slotIdx]
            if slot then
                slotTbl     = slot
                targetFrame = resolveGlowTarget(slot)
                glowFrame   = slot.pandemicGlow
                glowKind    = slot._auraGlowKind
                if glowFrame and type(glowFrame.IsShown) == "function" then
                    local okS, s = pcall(glowFrame.IsShown, glowFrame)
                    if okS then glowShown = s end
                end
                if glowFrame and glowFrame._pandemicMode then
                    glowMode = glowFrame._pandemicMode
                end
            end
        end
        local pStMid = cdID and pandemicState[cdID] or nil
        local stPct = pStMid and pStMid.lastPct
        local pctStr = stPct and string.format("%.1f%%", stPct * 100) or "?"
        push("---- [%s item %d -> slot %s] cdID=%s%s ----",
            kind, rawIdx, tostring(slotIdx or "-"), tostring(cdID),
            suppressed and "  SUPPRESSED(cross-viewer-dedup)" or "")
        push("  combat=%s  auraInstanceID=%s  auraDataUnit=%s  hasLiveAura=%s",
            tostring(inCombat), tostring(aiID), tostring(unit), tostring(hasLive))
        push("  pandemicIconExists=%s  classification=%s",
            tostring(pandemicIconExists), classification)
        push("  blizzardPandemic=%s  evalResult=%s  source=%s  durHasSecret=%s  pct=%s%s",
            tostring(bizPandemic),
            tostring(evalResult),
            evalSource,
            tostring(evalDurSecret),
            pctStr,
            evalErr and (" evalPcallError=" .. evalErr) or "")
        push("  secretVisual=%s  glowMode=%s",
            tostring(glowMode == "alpha" or glowMode == "two-zone"),
            tostring(glowMode or "pulse"))
        push("  perAuraKey=%s  perActiveGlow=%s  perPandemicGlow=%s",
            keyLine, perActiveStr, perPandStr)
        local pSt = cdID and pandemicState[cdID] or nil
        local clSpellID = pSt and pSt.comboLogSpellID
        local clApplied = pSt and pSt.comboLogAppliedAt
        local clDur     = pSt and pSt.comboLogDuration
        local clPct     = pSt and pSt.comboLogPct
        push("  comboLog.spellID=%s  comboLog.appliedAt=%s  comboLog.duration=%s  comboLog.pct=%s",
            tostring(clSpellID),
            clApplied and string.format("%.2f", clApplied) or "nil",
            clDur and string.format("%.2f", clDur) or "nil",
            clPct and string.format("%.3f", clPct) or "nil")
        local dSID
        do
            local okS2, s2 = pcall(getPandemicSpellID, item)
            if okS2 and type(s2) == "number" and not isSecret(s2) then dSID = s2 end
        end
        local dRec  = dSID and spellDurationCache[dSID] or nil
        local dBase = type(dRec) == "table" and tonumber(dRec.base) or nil
        local dSrc  = type(dRec) == "table" and dRec.src or nil
        local thrS
        do
            local okT2, t2 = pcall(Auras._pandemicThresholdSeconds, item, pOpts, dSID)
            if okT2 then thrS = t2 end
        end
        push("  spellDurationCache[%s]=%s  thresholdSecs=%s (base=%s src=%s)  secondsBased=%s",
            tostring(dSID),
            dBase and string.format("%.2f", dBase) or "nil",
            thrS and string.format("%.1f", thrS) or "-",
            dBase and string.format("%.1fs", dBase) or "?",
            tostring(dSrc or "fallback-pct"),
            tostring(pSt and pSt.secondsBased))
        push("  targetFrame=%s  glowFrame=%s  glowShown=%s  cachedKind=%s",
            tostring(targetFrame ~= nil),
            tostring(glowFrame ~= nil),
            tostring(glowShown),
            tostring(glowKind))
        local gl = slotTbl and slotTbl._glowLast
        if gl then
            local age = (GetTime and (GetTime() - (gl.at or 0))) or -1
            push("  lastGlowApply=%s  detail=%s  age=%.1fs",
                tostring(gl.src), tostring(gl.detail), age)
        else
            push("  lastGlowApply=(none recorded)")
        end
        local ag = slotTbl and slotTbl._agEval
        if ag then
            local age = (GetTime and (GetTime() - (ag.at or 0))) or -1
            push("  activeGlow-skip=%s  age=%.1fs", tostring(ag.reason), age)
        else
            push("  activeGlow-skip=(none recorded)")
        end
    end

    if type(last.iconActive) == "table" then
        local sup = last.iconSuppressed or {}
        local phys = 0
        for i = 1, #last.iconActive do
            if count >= limit then break end
            if sup[i] then
                dumpOne(last.iconActive[i], "icon", i, nil, true)
            else
                phys = phys + 1
                dumpOne(last.iconActive[i], "icon", i, phys, false)
            end
        end
    end
    if type(last.barActive) == "table" then
        local sup = last.barSuppressed or {}
        local phys = 0
        for i = 1, #last.barActive do
            if count >= limit then break end
            if sup[i] then
                dumpOne(last.barActive[i], "bar", i, nil, true)
            else
                phys = phys + 1
                dumpOne(last.barActive[i], "bar", i, phys, false)
            end
        end
    end
    if count == 0 then
        push("  (no live items in either display -- try /tenui auras rescan)")
    end
    return lines
end

function Auras:GetGlowApplyLines()
    local lines = {}
    local now = (GetTime and GetTime()) or 0
    local function pushSlot(tag, idx, slotTbl)
        local gl = type(slotTbl) == "table" and slotTbl._glowLast or nil
        if not gl then return end
        local mode = slotTbl.pandemicGlow and slotTbl.pandemicGlow._pandemicMode or nil
        local shown
        local g = slotTbl.pandemicGlow
        if g and type(g.IsShown) == "function" then
            local okS, s = pcall(g.IsShown, g)
            if okS and not (isSecret and isSecret(s)) then shown = s end
        end
        lines[#lines + 1] = string.format(
            "  [%s %d] last=%s detail=%s age=%.1fs overlayShown=%s mode=%s",
            tag, idx, tostring(gl.src), tostring(gl.detail),
            now - (gl.at or 0), tostring(shown), tostring(mode or "pulse"))
    end
    lines[#lines + 1] = "--- Auras glow-apply log (last visual WRITE per slot) ---"
    if self.IconDisplay and self.IconDisplay.icons then
        for i = 1, #self.IconDisplay.icons do
            local w = self.IconDisplay.icons[i]
            if w and w._pandemicSlot then pushSlot("icon", i, w._pandemicSlot) end
        end
    end
    if self.BarDisplay and self.BarDisplay.bars then
        for i = 1, #self.BarDisplay.bars do
            pushSlot("bar", i, self.BarDisplay.bars[i])
        end
    end
    if #lines == 1 then
        lines[#lines + 1] = "  (no glow writes recorded yet this session)"
    end
    return lines
end

function Auras:DumpActiveDiagnostic()
    local lines = {}
    local function push(fmt, ...)
        if select("#", ...) > 0 then
            lines[#lines + 1] = string.format(fmt, ...)
        else
            lines[#lines + 1] = fmt
        end
    end

    local set = {}
    do
        local ok, s = pcall(viewerActiveCooldownIDSet, true)
        if ok and type(s) == "table" then set = s end
    end
    local setCount = 0
    for _ in pairs(set) do setCount = setCount + 1 end

    push("=== /tenui auras active -- per-entry active-detection dump ===")
    push("  viewer-mirror active set: %d cooldownID(s) currently shown by Blizzard",
        setCount)
    local inCombat = InCombatLockdown and InCombatLockdown()
    push("  context: %s   target=%s",
        inCombat and "IN COMBAT" or "out of combat",
        (UnitExists and UnitExists("target")) and "yes" or "no")

    local function dumpCategory(displayType, header)
        push("--- %s ---", header)
        local cat = buildAuraCatalog(displayType)
        if type(cat) ~= "table" or #cat == 0 then
            push("  (no entries -- is the Blizzard CDM addon configured for this category?)")
            return
        end
        for i = 1, #cat do
            local e = cat[i]
            local probe = {
                cooldownID             = e.cooldownID,
                spellID                = e.spellID,
                overrideSpellID        = e.overrideSpellID,
                overrideTooltipSpellID = e.overrideTooltipSpellID,
                linkedSpellIDs         = e.linkedSpellIDs,
            }
            local viewerActive = (e.cooldownID ~= nil) and set[e.cooldownID] == true
            local ids = infoAuraSpellIDs(probe)
            local fallbackActive = anyPlayerOrTargetAura(ids)
            local okF, finalActive = pcall(cdmActiveForInfo, probe)
            if not okF then finalActive = false end

            local runtimeActive, runtimeUnit, durState = false, "-", "-"
            do
                local ad, unit = resolveLiveAuraForEntry(e)
                if ad then
                    runtimeActive = true
                    runtimeUnit = unit or "-"
                    if ad.auraInstanceID ~= nil and C_UnitAuras
                       and C_UnitAuras.GetAuraDuration then
                        local okD, dur = pcall(C_UnitAuras.GetAuraDuration,
                            unit or "player", ad.auraInstanceID)
                        if okD and dur then
                            local okZ, isZero = pcall(dur.IsZero, dur)
                            if okZ and isZero == false then
                                durState = "DurationObject(live)"
                            elseif okZ then
                                durState = "DurationObject(zero/permanent)"
                            else
                                durState = "DurationObject(opaque)"
                            end
                        else
                            durState = "no-duration-object"
                        end
                    else
                        durState = "no-auraInstanceID"
                    end
                end
            end

            local linkedStr = "-"
            if type(e.linkedSpellIDs) == "table" and #e.linkedSpellIDs > 0 then
                local parts = {}
                for j = 1, #e.linkedSpellIDs do
                    parts[#parts + 1] = tostring(e.linkedSpellIDs[j])
                end
                linkedStr = table.concat(parts, ",")
            end

            push("  %-22s cdID=%-5s sid=%-7s override=%-7s linked=%s",
                ("[" .. tostring(e.label) .. "]"),
                tostring(e.cooldownID),
                tostring(e.spellID),
                tostring(e.overrideSpellID or "-"),
                linkedStr)
            push("        viewer=%s  fallback=%s  FINAL=%s",
                viewerActive   and "|cff66ff66ACTIVE|r" or "|cffaaaaaaidle|r",
                fallbackActive and "|cff66ff66ACTIVE|r" or "|cffaaaaaaidle|r",
                finalActive    and "|cff66ff66ACTIVE|r" or "|cffaaaaaaidle|r")
            push("        RUNTIME=%s  unit=%s  timer=%s",
                runtimeActive and "|cff66ff66ACTIVE|r" or "|cffaaaaaaidle|r",
                tostring(runtimeUnit), durState)
        end
    end

    dumpCategory("TrackedIcon", "Tracked Buffs (icons)")
    dumpCategory("TrackedBars", "Tracked Bars")
    return lines
end

function Auras:DumpViewerState()
    local lines = {}
    local function push(fmt, ...)
        if select("#", ...) > 0 then
            local ok, s = pcall(string.format, fmt, ...)
            lines[#lines + 1] = ok and s or fmt
        else
            lines[#lines + 1] = fmt
        end
    end
    local function S(v)
        if isSecret(v) then return "<secret>" end
        if v == nil then return "nil" end
        return tostring(v)
    end
    local function boolMethod(child, methodName)
        if type(child) ~= "table" or type(child[methodName]) ~= "function" then return "-" end
        local ok, v = pcall(child[methodName], child)
        if not ok then return "err" end
        return S(v)
    end
    local function fieldStr(child, fieldName)
        if type(child) ~= "table" then return "-" end
        local ok, v = pcall(function() return child[fieldName] end)
        if not ok then return "err" end
        if v == nil then return "-" end
        return S(v)
    end

    local function poolActiveChildren(viewer)
        local out = {}
        if type(viewer) ~= "table" then return out, false end
        local pool = viewer.itemFramePool
        if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then
            return out, false
        end
        pcall(function()
            for itemFrame in pool:EnumerateActive() do
                out[#out + 1] = itemFrame
            end
        end)
        return out, true
    end

    local function childName(child)
        if type(child) ~= "table" or type(child.GetName) ~= "function" then return "-" end
        local ok, n = pcall(child.GetName, child)
        if ok and type(n) == "string" and n ~= "" then return n end
        return "(anon)"
    end

    local inCombat = InCombatLockdown and InCombatLockdown()
    local totalActive = 0
    local resolvedActive = 0
    push("=== /tenui auras viewerstate -- buff-viewer pool + resolver dump ===")
    push("  context: %s   target=%s   useViewerStateAsPrimary=%s",
        inCombat and "IN COMBAT" or "out of combat",
        (UnitExists and UnitExists("target")) and "yes" or "no",
        tostring(self._useViewerStateAsPrimary == true))

    for _, vName in ipairs({ ICON_VIEWER_NAME, BAR_VIEWER_NAME }) do
        local viewer = getViewer(vName)
        if not viewer then
            push("  %s: GLOBAL FRAME ABSENT (getViewer returned nil)", vName)
        else
            local shownN = "?"
            if type(viewer.IsShown) == "function" then
                local ok, s = pcall(viewer.IsShown, viewer)
                if ok then shownN = s and "shown" or "hidden" end
            end
            local active, hasPool = poolActiveChildren(viewer)
            totalActive = totalActive + #active
            if not hasPool then
                push("  %s: EXISTS IsShown=%s  itemFramePool ABSENT or no EnumerateActive",
                    vName, shownN)
            else
                push("  %s: EXISTS IsShown=%s  itemFramePool:EnumerateActive() -> %d active child(ren)",
                    vName, shownN, #active)
            end
            do
                local hasSecret, anyAspect, anchorSecret = "n/a", "n/a", "n/a"
                if type(viewer.HasSecretValues) == "function" then
                    local ok, v = pcall(viewer.HasSecretValues, viewer)
                    if ok then hasSecret = v and "YES" or "no" end
                end
                if type(viewer.HasAnySecretAspect) == "function" then
                    local ok, v = pcall(viewer.HasAnySecretAspect, viewer)
                    if ok then anyAspect = v and "YES" or "no" end
                end
                if type(viewer.IsAnchoringSecret) == "function" then
                    local ok, v = pcall(viewer.IsAnchoringSecret, viewer)
                    if ok then anchorSecret = v and "YES" or "no" end
                end
                push("    TAINT: HasSecretValues=%s HasAnySecretAspect=%s IsAnchoringSecret=%s  (if any YES -> viewer tainted -> RefreshData faults on SPELL_UPDATE_COOLDOWN -> :382/:454 flood. Source: C_EditMode.SaveLayouts reapply. /reload to clear.)",
                    hasSecret, anyAspect, anchorSecret)
            end
            if #active == 0 then
                push("    POOL EMPTY (0 active children)")
            end
            for i = 1, #active do
                local child = active[i]
                local cdID = readChildCooldownID(child)
                push("    [%d] name=%s cdID=%s IsShown=%s inEnumerateActive=yes IsActive=%s childShownActive=%s",
                    i, childName(child), S(cdID),
                    boolMethod(child, "IsShown"),
                    boolMethod(child, "IsActive"),
                    tostring(childShownActive(child)))
                push("        auraInstanceID=%s auraDataUnit=%s isActive=%s isOnCooldown=%s",
                    fieldStr(child, "auraInstanceID"),
                    fieldStr(child, "auraDataUnit"),
                    fieldStr(child, "isActive"),
                    fieldStr(child, "isOnCooldown"))
                if type(child) == "table" and cdID then
                    local liveTxt = Auras._readLiveBarDurationText(cdID)
                    push("        liveDurationText=%s  (GetCooldownValues NOT called: mutates child -> taint)",
                        isSecret(liveTxt) and "<secret>" or S(liveTxt))
                end
            end
        end
    end

    local function dumpEntries(displayType, header)
        push("--- %s: per-tracked-entry resolver result ---", header)
        local cat = buildAuraCatalog(displayType)
        if type(cat) ~= "table" or #cat == 0 then
            push("  (no tracked entries configured for this category)")
            return
        end
        for i = 1, #cat do
            local e = cat[i]
            if type(e) == "table" then
                local cdNum = tonumber(e.cooldownID)
                local foundChild
                if cdNum then
                    foundChild = findLiveViewerChildByCooldownID(cdNum, "TrackedBars")
                        or findLiveViewerChildByCooldownID(cdNum, "TrackedIcon")
                end
                local active, info = self:ResolveAuraStateFromViewer(e)
                if active == true then resolvedActive = resolvedActive + 1 end
                local activeStr
                if active == nil then activeStr = "|cffffcc00nil(fall back)|r"
                elseif active == true then activeStr = "|cff66ff66ACTIVE|r"
                else activeStr = "|cffaaaaaafalse(no live child)|r" end
                push("  [%s] cdID=%s sid=%s -> childByCooldownID=%s resolver=%s",
                    S(e.label or e.displayName), S(e.cooldownID), S(e.spellID),
                    (type(foundChild) == "table") and "FOUND" or "none", activeStr)
                if type(info) == "table" then
                    push("        info: aInst=%s unit=%s cdID=%s dur=%s exp=%s stacks=%s icon=%s",
                        S(info.auraInstanceID), S(info.auraDataUnit), S(info.cooldownID),
                        S(info.duration), S(info.expirationTime), S(info.applications),
                        S(info.icon))
                end
            end
        end
    end
    local okI = pcall(dumpEntries, "TrackedIcon", "Tracked Buffs (icons)")
    if not okI then push("  (TrackedIcon entry dump errored)") end
    local okB = pcall(dumpEntries, "TrackedBars", "Tracked Bars")
    if not okB then push("  (TrackedBars entry dump errored)") end
    push("=== SUMMARY: %d total active pool child(ren) across both viewers; %d tracked entr(ies) resolved ACTIVE ===",
        totalActive, resolvedActive)
    if totalActive == 0 then
        push("  VERDICT: viewer pools are EMPTY -- Blizzard is not populating BuffIconCooldownViewer/BuffBarCooldownViewer, so cooldownID matching cannot find children. Next step: ensure the Blizzard CDM is enabled/populated for these categories.")
    elseif resolvedActive == 0 then
        push("  VERDICT: pools have children but NO tracked entry matched by cooldownID+active. Compare per-child cdID above against per-entry cdID.")
    else
        push("  VERDICT: %d entr(ies) resolve ACTIVE via cooldownID -- these should render in combat with src=viewerState.", resolvedActive)
    end
    return lines
end

function Auras:DumpAuraIdentity()
    local lines = {}
    local function push(fmt, ...)
        if select("#", ...) > 0 then
            lines[#lines + 1] = string.format(fmt, ...)
        else
            lines[#lines + 1] = fmt
        end
    end
    local function joinIDs(t)
        if type(t) ~= "table" or #t == 0 then return "-" end
        local parts = {}
        for i = 1, #t do parts[#parts + 1] = tostring(t[i]) end
        return table.concat(parts, ",")
    end
    local function safeStr(v)
        if isSecret(v) then return "<secret>" end
        if v == nil then return "-" end
        return tostring(v)
    end

    local inCombat = InCombatLockdown and InCombatLockdown()
    push("=== /tenui aura dump -- CDM identity/runtime/display/matching ===")
    push("  context: %s   target=%s",
        inCombat and "IN COMBAT" or "out of combat",
        (UnitExists and UnitExists("target")) and "yes" or "no")
    push("  DK verification notes: Virulent Plague + Dread Plague should appear")
    push("    as SEPARATE entries (distinct stableEntryID); applying a tracked")
    push("    debuff to target in combat sets auraInstanceID + auraDataUnit=target;")
    push("    Lesser Ghoul iconSource should be 'base' (not override).")

    local function dumpCat(displayType, header)
        push("--- %s ---", header)
        local cat = buildAuraCatalog(displayType)
        if type(cat) ~= "table" or #cat == 0 then
            push("  (no entries -- is the Blizzard CDM configured for this category?)")
            return
        end
        for i = 1, #cat do
            local e = cat[i]
            local activeSource = "none"
            local liveAuraInstanceID, liveAuraUnit, liveIconSource
            local rt = e

            local child = findLiveViewerChildByCooldownID(e.cooldownID, displayType)
            if child then
                activeSource = "viewerChild"
                liveAuraUnit = (type(child.auraDataUnit) == "string" and child.auraDataUnit) or "player"
                liveAuraInstanceID = child.auraInstanceID
                if liveAuraInstanceID == nil and type(child.Icon) == "table" then
                    liveAuraInstanceID = child.Icon.auraInstanceID
                end
                local childTex
                local iconField = child.Icon
                if type(iconField) == "table" then
                    if type(iconField.GetTexture) == "function" then
                        local okT, tex = pcall(iconField.GetTexture, iconField)
                        if okT then childTex = tex end
                    end
                    if childTex == nil and type(iconField.Icon) == "table"
                       and type(iconField.Icon.GetTexture) == "function" then
                        local okT, tex = pcall(iconField.Icon.GetTexture, iconField.Icon)
                        if okT then childTex = tex end
                    end
                end
                liveIconSource = (childTex ~= nil) and "child.Icon" or "catalog"
            else
                local ad, unit = resolveLiveAuraForEntry(e)
                if ad then
                    activeSource = "unitAuraCache"
                    liveAuraUnit = unit
                    liveAuraInstanceID = ad.auraInstanceID
                    liveIconSource = "catalog"
                    rt = {}
                    for k, v in pairs(e) do rt[k] = v end
                    Auras._cdm.SetAuraInstanceInfo(rt, ad, unit)
                end
            end

            push("  [%s]  %s", safeStr(rt.displayName or rt.label), tostring(rt.stableEntryID))
            push("      identity : cdID=%s cat=%s spellID=%s override=%s tooltip=%s linkedIDs=%s",
                tostring(e.cooldownID), tostring(e.category), tostring(e.spellID),
                tostring(e.overrideSpellID or "-"), tostring(e.overrideTooltipSpellID or "-"),
                joinIDs(e.linkedSpellIDs))
            push("      active   : source=%s cooldownID=%s stableEntryID=%s auraInstanceID=%s auraDataUnit=%s iconSource=%s",
                activeSource, tostring(e.cooldownID), tostring(e.stableEntryID),
                safeStr(liveAuraInstanceID), tostring(liveAuraUnit or "-"),
                tostring(liveIconSource or "-"))
            push("      runtime  : auraSpellID=%s auraInstanceID=%s linkedSpellID=%s unit=%s source=%s",
                safeStr(rt.auraSpellID), safeStr(rt.auraInstanceID),
                safeStr(rt.linkedSpellID), tostring(rt.auraDataUnit or "-"),
                tostring(rt.activeAuraSource or "-"))
            push("      display  : displaySpellID=%s displayName=%s iconSource=%s labelSource=%s",
                safeStr(rt.displaySpellID), safeStr(rt.displayName),
                tostring(rt.iconSource or "-"), tostring(rt.labelSource or "-"))
            push("      display  : displayIcon=%s", safeStr(rt.displayIcon))
            push("      matching : catalogKey=%s matchKey=%s matchSpellIDs=%s",
                tostring(e.catalogKey), tostring(e.matchKey), joinIDs(e.matchSpellIDs))
        end
    end

    dumpCat("TrackedIcon", "Tracked Buffs (icons)")
    dumpCat("TrackedBars", "Tracked Bars")
    return lines
end

local function debugBuildActiveFromViewerChildren(displayType)
    local vname = DISPLAYTYPE_VIEWER_NAME[displayType]
    local viewer = vname and getViewer(vname) or nil
    local details = {}
    if not viewer then
        return 0, 0, details
    end
    local items = getItemFrames(viewer) or {}
    local total = #items
    local activeCount = 0
    for i = 1, total do
        local child = items[i]
        if childShownActive(child) then
            activeCount = activeCount + 1
            local cdID = readChildCooldownID(child)
            local aInst
            if type(child) == "table" then
                aInst = child.auraInstanceID
                if aInst == nil and type(child.Icon) == "table" then
                    aInst = child.Icon.auraInstanceID
                end
            end
            local aInstStr = isSecret(aInst) and "<secret>" or tostring(aInst)
            details[#details + 1] = {
                index            = i,
                cooldownID       = cdID,
                auraInstanceIDStr = aInstStr,
            }
        end
    end
    return activeCount, total, details
end

function Auras:DumpPipeline()
    local lines = {}
    local function push(fmt, ...)
        if select("#", ...) > 0 then
            local ok, s = pcall(string.format, fmt, ...)
            lines[#lines + 1] = ok and s or fmt
        else
            lines[#lines + 1] = fmt
        end
    end
    local function safeStr(v)
        if isSecret(v) then return "<secret>" end
        if v == nil then return "-" end
        return tostring(v)
    end
    local function safeShown(f)
        if type(f) ~= "table" or type(f.IsShown) ~= "function" then return "?" end
        local ok, s = pcall(f.IsShown, f)
        if not ok then return "err" end
        return s and "yes" or "no"
    end
    local function safeAlpha(f)
        if type(f) ~= "table" or type(f.GetAlpha) ~= "function" then return "?" end
        local ok, a = pcall(f.GetAlpha, f)
        if not ok then return "err" end
        if isSecret(a) then return "<secret>" end
        if type(a) == "number" then return string.format("%.2f", a) end
        return tostring(a)
    end
    local function safeSize(f)
        if type(f) ~= "table" or type(f.GetSize) ~= "function" then return "?" end
        local ok, w, h = pcall(f.GetSize, f)
        if not ok then return "err" end
        if isSecret(w) or isSecret(h) then return "<secret>" end
        return string.format("%sx%s",
            type(w) == "number" and string.format("%.0f", w) or tostring(w),
            type(h) == "number" and string.format("%.0f", h) or tostring(h))
    end
    local function safePoint(f)
        if type(f) ~= "table" or type(f.GetPoint) ~= "function" then return "?" end
        local ok, p, rel, relP, x, y = pcall(f.GetPoint, f, 1)
        if not ok then return "err" end
        if p == nil then return "none" end
        local relName = "?"
        if type(rel) == "table" and type(rel.GetName) == "function" then
            local okN, n = pcall(rel.GetName, rel)
            if okN then relName = n or "<unnamed>" end
        elseif rel == nil then
            relName = "nil"
        end
        return string.format("%s->%s:%s x=%s y=%s",
            safeStr(p), relName, safeStr(relP), safeStr(x), safeStr(y))
    end
    local function safeStrataLevel(f)
        local strata, level = "?", "?"
        if type(f) == "table" then
            if type(f.GetFrameStrata) == "function" then
                local ok, s = pcall(f.GetFrameStrata, f)
                if ok then strata = tostring(s) end
            end
            if type(f.GetFrameLevel) == "function" then
                local ok, l = pcall(f.GetFrameLevel, f)
                if ok then level = tostring(l) end
            end
        end
        return strata, level
    end
    local function safeTexture(tex)
        if type(tex) ~= "table" or type(tex.GetTexture) ~= "function" then return "?" end
        local ok, t = pcall(tex.GetTexture, tex)
        if not ok then return "err" end
        return safeStr(t)
    end

    local inCombat = InCombatLockdown and InCombatLockdown()
    local forcePop = self.IsForceViewerPopulated and self:IsForceViewerPopulated()
    push("=== /tenui aura pipeline -- non-invasive display-chain diagnostic ===")
    push("  context: %s   target=%s",
        inCombat and "IN COMBAT" or "out of combat",
        (UnitExists and UnitExists("target")) and "yes" or "no")
    push("  forceViewerPopulated: %s  (%s)",
        forcePop and "ON" or "OFF (default)",
        forcePop
            and "viewerChild used as a presence source WHEN Blizzard shows the viewer (we never SetShown/Show the Blizzard viewer -- that would taint its refresh); primary presence is _liveAuraByEntry from UNIT_AURA deltas"
            or "engine spellID-family ticker query is the SOLE presence source")
    if self.GetLowTimeTextConfig then
        local ltEn, ltThr = self:GetLowTimeTextConfig()
        push("  lowTimeText (numbers): %s  thr=%gs  (timer-TEXT recolor on icons AND bars; /tenui aura lowtime)",
            ltEn and "ON" or "OFF (default)", ltThr)
    end
    if self.GetBarPreviewStats then
        local bpEn, bpCount, bpPcts = self:GetBarPreviewStats()
        push("  barPreview: %s  count=%d  lastRemainingFrac=[%s]  (PART A deterministic demo)",
            bpEn and "ON" or "OFF", bpCount, bpPcts)
        if bpEn then
            push("    -> synthetic bars inject ONLY when 0 real Tracked Bars are active;")
            push("       they run the REAL render path (Build/RenderActive/GetBarSlot/")
            push("       applyBarFill). Toggle: /tenui auras barpreview off")
        else
            push("    -> /tenui auras barpreview on  spawns draining demo bars to test")
            push("       Bar Width without a live aura.")
        end
    end
    push("  (read-only: calls buildActiveFromCatalog + RenderActive exactly as a")
    push("   normal Refresh tick does -- NO runtime logic is changed)")

    local verdict = {}

    local function dumpDisplay(displayType, viewerName, disp, isIcon)
        push("")
        push("================ %s ================", displayType)
        local v = verdict[displayType]
        if not v then v = {} verdict[displayType] = v end

        local viewer = getViewer(viewerName)
        push("[A] viewer state (Q1: does the Blizzard CDM viewer/children exist)")
        push("    viewer name      = %s", tostring(viewerName))
        push("    viewer exists    = %s", viewer and "yes" or "no")
        local viewerChildren = {}
        if viewer then
            push("    viewer shown     = %s", safeShown(viewer))
            push("    viewer alpha     = %s", safeAlpha(viewer))
            viewerChildren = getItemFrames(viewer) or {}
            push("    children count   = %d", #viewerChildren)
        else
            push("    (viewer missing -- CDM category not present for this spec?)")
        end

        push("[B] viewer children (first 20)  (Q2 cooldownID, Q3 auraInstanceID)")
        local huskCount = 0
        if #viewerChildren == 0 then
            push("    (no children)")
        else
            local limit = math.min(20, #viewerChildren)
            for i = 1, limit do
                local child = viewerChildren[i]
                local cdID = readChildCooldownID(child)
                local aInst, aUnit, iconTex
                if type(child) == "table" then
                    aInst = child.auraInstanceID
                    if aInst == nil and type(child.Icon) == "table" then
                        aInst = child.Icon.auraInstanceID
                    end
                    aUnit = child.auraDataUnit
                    local iconField = child.Icon
                    if type(iconField) == "table" then
                        if type(iconField.GetTexture) == "function" then
                            local okT, t = pcall(iconField.GetTexture, iconField)
                            if okT then iconTex = t end
                        end
                        if iconTex == nil and type(iconField.Icon) == "table"
                           and type(iconField.Icon.GetTexture) == "function" then
                            local okT, t = pcall(iconField.Icon.GetTexture, iconField.Icon)
                            if okT then iconTex = t end
                        end
                    end
                end
                if cdID == nil then huskCount = huskCount + 1 end
                push("    [%d] cdID=%s shown=%s alpha=%s auraInst=%s unit=%s",
                    i, safeStr(cdID), safeShown(child), safeAlpha(child),
                    safeStr(aInst), safeStr(aUnit))
                push("        tex=%s size=%s point=%s",
                    safeStr(iconTex), safeSize(child), safePoint(child))
            end
            if #viewerChildren > 20 then
                push("    ... (%d more children not shown)", #viewerChildren - 20)
            end
            if huskCount > 0 and huskCount == math.min(20, #viewerChildren) then
                push("    NOTE: ALL children are cdID-less husks -- this viewer's ordered")
                push("    layout list is EMPTY (minimum-2 placeholder frames). The catalog's")
                push("    cooldownIDs are likely assigned to the OTHER buff viewer in the")
                push("    user's CDM layout; see the crossViewer probe below.")
            end
        end

        push("[C] catalog/runtime  (Q4 synthetic item, Q5 entryDisplayEnabled, Q6 active list)")
        local active = {}
        if type(buildActiveFromCatalog) == "function" then
            local ok, res = pcall(buildActiveFromCatalog, displayType, false)
            if ok and type(res) == "table" then active = res end
            if not ok then push("    buildActiveFromCatalog ERROR: %s", safeStr(res)) end
        else
            push("    buildActiveFromCatalog not loaded")
        end
        push("    activeFromCatalog count = %d", #active)
        v.catalog = #active
        local idleCount = 0
        for ii = 1, #active do
            local it = active[ii]
            if type(it) == "table" and it._idle == true then
                idleCount = idleCount + 1
            end
        end
        v.catalogIdle = idleCount
        if idleCount > 0 then
            push("    (of which IDLE placeholder rows = %d -- ShowWhenInactive)", idleCount)
        end

        do
            local le = Auras._lastItemError
            if type(le) == "table" then
                local age = ((GetTime and GetTime()) or 0) - (le.at or 0)
                push("    lastSwallowedItemError: key=%s where=%s combat=%s age=%.1fs",
                    tostring(le.key), tostring(le.where), tostring(le.combat), age)
                push("        err=%s", tostring(le.err))
            else
                push("    lastSwallowedItemError: none this session")
            end
        end

        local engineActive = 0
        if type(buildAuraCatalog) == "function"
           and type(resolveLiveAuraForEntry) == "function" then
            local okC, catList = pcall(buildAuraCatalog, displayType)
            if okC and type(catList) == "table" then
                for ci = 1, #catList do
                    local ce = catList[ci]
                    if type(ce) == "table" then
                        local okR, ad = pcall(resolveLiveAuraForEntry, ce)
                        if okR and ad then engineActive = engineActive + 1 end
                    end
                end
            end
        end
        v.engine = engineActive
        local configuredCount = 0
        if type(buildAuraCatalog) == "function" then
            local okCfg, cl = pcall(buildAuraCatalog, displayType)
            if okCfg and type(cl) == "table" then configuredCount = #cl end
        end
        v.configured = configuredCount
        push("    configured (in CDM) = %d   |   active now = %d", configuredCount, #active)
        push("    activeFromEngineStore count = %d  (engine spellID-family query, viewer-independent)",
            engineActive)
        push("    (in combat = %s)", tostring(InCombatLockdown and InCombatLockdown() == true))
        for i = 1, #active do
            local item = active[i]
            if type(item) == "table" then
                local entryForGate = (type(item._entry) == "table") and item._entry or item
                local okE, en = pcall(entryDisplayEnabled, entryForGate)
                local enStr = okE and (en and "true" or "false") or "err"
                push("    [%d] cdID=%s stableEntryID=%s entryDisplayEnabled=%s",
                    i, safeStr(item.cooldownID), safeStr(item.stableEntryID), enStr)
                local src = (type(item._entry) == "table") and item._entry.activeAuraSource or nil
                push("        activeAuraSource=%s auraInst=%s unit=%s fromViewer=%s idle=%s",
                    safeStr(src), safeStr(item.auraInstanceID),
                    safeStr(item.auraDataUnit), tostring(item._fromViewer == true),
                    tostring(item._idle == true))
                push("        _spellID=%s _iconTexture=%s _barName=%s",
                    safeStr(item._spellID), safeStr(item._iconTexture), safeStr(item._barName))
            else
                push("    [%d] <non-table item>", i)
            end
        end

        local vcCount, vcTotal = debugBuildActiveFromViewerChildren(displayType)
        v.viewerChildren = vcCount
        push("    activeFromViewerChildren count = %d  (of %d children)", vcCount, vcTotal)

        local crossActive = 0
        do
            local catIDs = {}
            if type(buildAuraCatalog) == "function" then
                local okCl, cl = pcall(buildAuraCatalog, displayType)
                if okCl and type(cl) == "table" then
                    for ci = 1, #cl do
                        local ce = cl[ci]
                        if type(ce) == "table" and type(ce.cooldownID) == "number" then
                            catIDs[ce.cooldownID] = true
                        end
                    end
                end
            end
            local otherName = (viewerName == BAR_VIEWER_NAME)
                and ICON_VIEWER_NAME or BAR_VIEWER_NAME
            local otherViewer = getViewer(otherName)
            if otherViewer and next(catIDs) ~= nil then
                local oItems = getItemFrames(otherViewer) or {}
                for oi = 1, #oItems do
                    local oc = oItems[oi]
                    if childShownActive(oc) then
                        local ocdID = readChildCooldownID(oc)
                        if ocdID and catIDs[ocdID] then
                            crossActive = crossActive + 1
                            push("    crossViewer child: cdID=%s found ACTIVE in %s (layout/category mismatch)",
                                tostring(ocdID), otherName)
                        end
                    end
                end
            end
        end
        v.crossViewer = crossActive
        push("    activeFromCrossViewer count = %d  (catalog cooldownIDs active in the OTHER buff viewer)",
            crossActive)

        push("[D] render state (Q7 widget SetTexture/SetSize/Show, Q8 visibility/anchor)")
        if not disp then
            push("    display object not built yet (module idle / not enabled?)")
            v.widgets = 0
            return
        end
        if type(disp.RenderActive) == "function" then
            local okR, errR = pcall(disp.RenderActive, disp, active, nil)
            if not okR then push("    RenderActive ERROR: %s", safeStr(errR)) end
        else
            push("    display has no RenderActive method")
        end

        local container = disp.container
        push("    display frame exists = %s", container and "yes" or "no")
        if container then
            push("    display frame shown  = %s", safeShown(container))
            push("    display frame alpha  = %s", safeAlpha(container))
            push("    display frame size   = %s", safeSize(container))
            push("    display frame point  = %s", safePoint(container))
        end

        local pool = isIcon and disp.icons or disp.bars
        if type(pool) ~= "table" then pool = {} end
        push("    item/widget count    = %d (activeCount=%s)",
            #pool, tostring(disp.activeCount))
        v.widgets = tonumber(disp.activeCount) or 0
        v.anyVisible = false
        v.anyTexture = false
        local limit = math.min(20, #pool)
        for i = 1, limit do
            local slot = pool[i]
            local wframe, wtex
            if isIcon then
                wframe = (type(slot) == "table") and slot.frame or nil
                wtex   = (type(wframe) == "table") and wframe.icon or nil
            else
                wframe = (type(slot) == "table") and slot.frame or nil
                wtex   = (type(slot) == "table") and slot.icon or nil
            end
            local strata, level = safeStrataLevel(wframe)
            local parentShown = "?"
            if type(wframe) == "table" and type(wframe.GetParent) == "function" then
                local okP, par = pcall(wframe.GetParent, wframe)
                if okP and par then parentShown = safeShown(par) end
            end
            local shownStr = safeShown(wframe)
            local texStr = safeTexture(wtex)
            push("    [%d] shown=%s alpha=%s size=%s tex=%s",
                i, shownStr, safeAlpha(wframe), safeSize(wframe), texStr)
            push("        parentShown=%s strata=%s level=%s point=%s",
                parentShown, strata, level, safePoint(wframe))
            if i <= (tonumber(disp.activeCount) or 0) then
                if shownStr == "yes" then v.anyVisible = true end
                if texStr ~= "-" and texStr ~= "?" and texStr ~= "err" then
                    v.anyTexture = true
                    if texStr == "<secret>" then v.anySecretTexture = true end
                end
            end
        end
        if #pool > 20 then
            push("    ... (%d more widgets not shown)", #pool - 20)
        end
        v.containerVisible = container and safeShown(container) == "yes"
        v.containerAlpha = container and safeAlpha(container) or "-"
        v.containerSize = container and safeSize(container) or "-"
    end

    dumpDisplay("TrackedIcon", ICON_VIEWER_NAME, self.IconDisplay, true)
    dumpDisplay("TrackedBars", BAR_VIEWER_NAME, self.BarDisplay, false)

    push("")
    push("================ [E] BREAKPOINT verdict ================")
    local function verdictFor(displayType)
        local v = verdict[displayType] or {}
        local vc  = tonumber(v.viewerChildren) or 0
        local cv  = tonumber(v.crossViewer) or 0
        local eng = tonumber(v.engine) or 0
        local cat = tonumber(v.catalog) or 0
        local idle = tonumber(v.catalogIdle) or 0
        local catActive = cat - idle
        if catActive < 0 then catActive = 0 end
        local wid = tonumber(v.widgets) or 0
        local inCombat = InCombatLockdown and InCombatLockdown() == true
        local anyTexStr = "false"
        if v.anyTexture == true then
            anyTexStr = (v.anySecretTexture == true) and "true(secret)" or "true"
        end
        local cfg = tonumber(v.configured) or 0
        push("  %s: configured=%d  activeNow=%d (idle=%d)  forceViewerPopulated=%s engineStore=%d  viewerChildren=%d  crossViewer=%d  widgets=%d  anyTexture=%s  containerVisible=%s alpha=%s size=%s",
            displayType, cfg, catActive, idle, forcePop and "ON" or "OFF", eng, vc, cv, wid,
            anyTexStr,
            tostring(v.containerVisible == true),
            tostring(v.containerAlpha), tostring(v.containerSize))
        if inCombat and catActive == 0 and idle > 0 then
            push("    -> BREAKPOINT: %d row(s) rendered but ALL are IDLE placeholders IN COMBAT.", idle)
            push("       Every presence source is empty: engineStore=%d viewerChildren=%d crossViewer=%d.", eng, vc, cv)
            push("       If the tracked buffs ARE up, the in-combat presence chain is broken")
            push("       (engine query combat-blinded AND no populated viewer child found in")
            push("       EITHER buff viewer -- check section B husks + the crossViewer probe).")
        elseif cat > 0 and (wid == 0 or v.anyTexture ~= true) then
            push("    -> BREAKPOINT: render/widget problem (source produced %d but nothing drew)", cat)
        elseif wid > 0 and (v.containerVisible ~= true
               or v.containerAlpha == "0.00" or v.containerSize == "0x0") then
            push("    -> BREAKPOINT: display frame visibility/anchor problem")
        elseif eng == 0 and catActive > 0 then
            if forcePop then
                if vc > 0 or cv > 0 then
                    push("    -> chain OK (ON mode): %d active sourced from the populated viewer", catActive)
                    push("       child (viewerChildren=%d, crossViewer=%d) -- engine query had none;", vc, cv)
                    push("       this is the opt-in in-combat viewer-child path working as designed.")
                else
                    push("    -> NOTE: %d active with engineStore=0 AND no populated viewer child", catActive)
                    push("       (viewerChildren=0, crossViewer=0) -- presence came from neither")
                    push("       documented source; check buildActiveFromCatalog emission paths.")
                end
            else
                push("    -> NOTE: catalog produced %d active with engineStore=0 in OFF mode.", catActive)
                push("       (unexpected -- secondary viewer path is gated OFF; check source)")
            end
        elseif catActive == 0 and eng == 0 and idle > 0 then
            push("    -> chain OK: %d IDLE row(s) (Show When Inactive ON), nothing active", idle)
            push("       right now out of combat -- correct + expected.")
        elseif cat == 0 and eng == 0 then
            if inCombat then
                if forcePop then
                    push("    -> SOURCE produced 0 IN COMBAT with forceViewerPopulated ON.")
                    push("       Primary presence is _liveAuraByEntry (UNIT_AURA deltas); the")
                    push("       viewerChild fallback only works while BLIZZARD shows the viewer")
                    push("       (section A IsShown()==true). We never force-show it (taint). If")
                    push("       IsShown==false, set the spell's CDM visibility to Always/InCombat.")
                else
                    push("    -> SOURCE produced 0 IN COMBAT. If auras are actually up, the")
                    push("       engine by-spellID query is combat-blinded; presence then")
                    push("       depends on held UNIT_AURA removed-instance deltas. Confirm")
                    push("       the 0.1s ticker poll + combat-blind clear-guard are active.")
                    push("       (Consider /tenui aura forceviewer on for target debuffs.)")
                end
            else
                if cfg > 0 then
                    push("    -> %d entr%s CONFIGURED but 0 ACTIVE right now -- CORRECT + expected:",
                        cfg, cfg == 1 and "y" or "ies")
                    push("       the tracked cooldowns/buffs simply aren't up. NOT a breakpoint.")
                    push("       (Open TenUI edit mode to see them as draining demo bars for layout.)")
                else
                    push("    -> no entries configured for this category (nothing to display -- not a breakpoint)")
                end
            end
        elseif eng > 0 and cat == 0 then
            push("    -> BREAKPOINT: engine store has %d active but catalog produced 0", eng)
            push("       (gating/entryDisplayEnabled filtering an engine-active entry)")
        else
            push("    -> chain OK: engine source -> catalog -> widget -> visible all populated")
        end
    end
    verdictFor("TrackedIcon")
    verdictFor("TrackedBars")

    return lines
end

function Auras:DumpRawCategorySet()
    local lines = {}
    local function push(fmt, ...)
        if select("#", ...) > 0 then
            local ok, s = pcall(string.format, fmt, ...)
            lines[#lines + 1] = ok and s or fmt
        else
            lines[#lines + 1] = fmt
        end
    end
    local function safeStr(v)
        if isSecret(v) then return "<secret>" end
        if v == nil then return "-" end
        return tostring(v)
    end
    local function safeName(sid)
        if type(sid) ~= "number" or isSecret(sid) or sid <= 0 then return "-" end
        if not (C_Spell and type(C_Spell.GetSpellName) == "function") then return "?" end
        local ok, n = pcall(C_Spell.GetSpellName, sid)
        if not ok then return "?" end
        return safeStr(n)
    end
    local function joinLinked(linked)
        if type(linked) ~= "table" then return safeStr(linked) end
        local parts, n = {}, 0
        local okIter = pcall(function()
            for i = 1, #linked do
                n = n + 1
                parts[n] = safeStr(linked[i])
            end
        end)
        if not okIter then return "<err>" end
        return table.concat(parts, ",")
    end

    -- Targeted verdict accumulator: per target spellID -> hit record (or nil = not found)
    local TARGETS = { [265187] = "Summon Demonic Tyrant", [104316] = "Call Dreadstalkers" }
    local found = {}

    push("== /tenui auras rawset -- RAW Blizzard cooldown-viewer category sets (UNFILTERED) ==")
    push("   (read-only: GetCooldownViewerCategorySet / GetCooldownViewerCooldownInfo / GetSpellName)")

    local hasCV = (C_CooldownViewer ~= nil)
        and (type(C_CooldownViewer.GetCooldownViewerCategorySet) == "function")
        and (type(C_CooldownViewer.GetCooldownViewerCooldownInfo) == "function")
    if not hasCV then
        push("C_CooldownViewer category API unavailable on this client -- nothing to dump.")
        return lines
    end

    local enum = Enum and Enum.CooldownViewerCategory
    if type(enum) ~= "table" then
        push("Enum.CooldownViewerCategory unavailable on this client -- nothing to dump.")
        return lines
    end

    -- category order: TrackedBar + TrackedBuff are the point of this command; Essential/Utility for completeness
    local catDefs = {
        { name = "TrackedBar",  cat = enum.TrackedBar },
        { name = "TrackedBuff", cat = enum.TrackedBuff },
        { name = "Essential",   cat = enum.Essential },
        { name = "Utility",     cat = enum.Utility },
    }

    for _, def in ipairs(catDefs) do
        if def.cat == nil then
            push(" ")
            push("[%s] -- enum member missing on this client (skipped)", def.name)
        else
            local okSet, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, def.cat, true)
            push(" ")
            if not okSet or type(ids) ~= "table" then
                push("[%s] (cat=%s) -- GetCooldownViewerCategorySet failed/empty", def.name, safeStr(def.cat))
            else
                push("[%s] (cat=%s) count=%d", def.name, safeStr(def.cat), #ids)
                for i = 1, #ids do
                    local cdID = tonumber(ids[i])
                    if cdID then
                        local info
                        local okI = pcall(function()
                            info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                        end)
                        if not okI or type(info) ~= "table" then
                            push("  cdID=%s  <GetCooldownViewerCooldownInfo failed>", safeStr(cdID))
                        else
                            local sid   = info.spellID
                            local osid  = info.overrideSpellID
                            local hide  = cdmHiddenByDefault(info)
                            local known = info.isKnown
                            -- displaySpellID for name: prefer override when usable, else base
                            local nameSid = osid
                            if type(nameSid) ~= "number" or isSecret(nameSid) or nameSid <= 0 then
                                nameSid = sid
                            end
                            push("  cdID=%s  spellID=%s  override=%s  linked={%s}  hideByDefault=%s  isKnown=%s  name=%s",
                                safeStr(cdID), safeStr(sid), safeStr(osid),
                                joinLinked(info.linkedSpellIDs),
                                tostring(hide and true or false),
                                safeStr(known), safeName(nameSid))

                            -- targeted-verdict scan (compare only non-secret numbers)
                            local function matchTarget(v)
                                if type(v) ~= "number" or isSecret(v) then return end
                                if TARGETS[v] and not found[v] then
                                    found[v] = { cat = def.name, cdID = cdID, hide = hide and true or false }
                                end
                            end
                            matchTarget(sid)
                            matchTarget(osid)
                            if type(info.linkedSpellIDs) == "table" then
                                pcall(function()
                                    for li = 1, #info.linkedSpellIDs do
                                        matchTarget(tonumber(info.linkedSpellIDs[li]))
                                    end
                                end)
                            end
                        end
                    end
                end
            end
        end
    end

    push(" ")
    push("===================== TARGETED VERDICT =====================")
    local order = { 265187, 104316 }
    for _, tid in ipairs(order) do
        local label = TARGETS[tid]
        local hit = found[tid]
        if hit then
            push(">> %d (%s): FOUND in category=%s cdID=%s hideByDefault=%s",
                tid, label, hit.cat, safeStr(hit.cdID), tostring(hit.hide))
        else
            push(">> %d (%s): NOT FOUND in any tracked category set", tid, label)
        end
    end
    push("===========================================================")
    push("interpretation: FOUND + hideByDefault=true => a HideByDefault cooldownID exists")
    push("  (live duration possible via unhide/whitelist). NOT FOUND => no cooldownID =>")
    push("  the fix must be a self-driven bar (no Blizzard duration to mirror).")

    return lines
end

function Auras:VerifyDK()
    local lines = {}
    local function push(fmt, ...)
        if select("#", ...) > 0 then
            lines[#lines + 1] = string.format(fmt, ...)
        else
            lines[#lines + 1] = fmt
        end
    end
    local targets = {
        ["Virulent Plague"] = false,
        ["Dread Plague"]    = false,
        ["Lesser Ghoul"]    = false,
        ["Ghoul"]           = false,
    }
    push("=== /tenui aura verifydk -- DK linked-variant + icon self-test ===")
    local cats = { TrackedIcon = "Tracked Buffs", TrackedBars = "Tracked Bars" }
    local found = {}
    for displayType in pairs(cats) do
        local cat = buildAuraCatalog(displayType)
        for i = 1, #cat do
            local e = cat[i]
            local name = tostring(e.displayName or e.label or "")
            for needle in pairs(targets) do
                if name:find(needle, 1, true) then
                    found[#found + 1] = { needle = needle, entry = e, displayType = displayType }
                end
            end
        end
    end
    if #found == 0 then
        push("  No Virulent Plague / Dread Plague / Lesser Ghoul entries found.")
        push("  (Are you on a Death Knight with these configured in Blizzard's CDM?)")
        return lines
    end
    local function joinIDs(t)
        if type(t) ~= "table" or #t == 0 then return "-" end
        local parts = {}
        for i = 1, #t do parts[#parts + 1] = tostring(t[i]) end
        return table.concat(parts, ",")
    end
    for _, rec in ipairs(found) do
        local e = rec.entry
        push("  [%s] (%s)", tostring(e.displayName or e.label), rec.displayType)
        push("      stableEntryID = %s", tostring(e.stableEntryID))
        push("      displaySpellID= %s  iconSource=%s", tostring(e.displaySpellID), tostring(e.iconSource))
        push("      displayIcon   = %s", tostring(e.displayIcon))
        push("      cooldownID    = %s  linkedSpellIDs=%s",
            tostring(e.cooldownID), joinIDs(e.linkedSpellIDs))
    end
    local virCount, dreadCount = 0, 0
    for _, rec in ipairs(found) do
        if rec.needle == "Virulent Plague" then virCount = virCount + 1 end
        if rec.needle == "Dread Plague"    then dreadCount = dreadCount + 1 end
    end
    push("--- summary ---")
    push("  Virulent Plague entries: %d %s", virCount,
        virCount == 1 and "(OK)" or virCount > 1 and "(DUPLICATE!)" or "")
    push("  Dread Plague entries   : %d %s", dreadCount,
        dreadCount == 1 and "(OK)" or dreadCount > 1 and "(DUPLICATE!)" or "")
    push("  separate cooldownIDs   : %s",
        (virCount >= 1 and dreadCount >= 1)
        and "YES (distinct cooldownIDs -- correct)"
        or "single/none (not both configured for this spec)")
    return lines
end

function Auras:SetPandemicEnabled(flag)
    local po = self:GetPandemicOpts()
    if not po then return false, "profile not ready" end
    po.enabled = flag and true or false
    if not po.enabled then
        if self.BarDisplay and self.BarDisplay.bars then
            for i = 1, #self.BarDisplay.bars do
                local slot = self.BarDisplay.bars[i]
                if slot then pcall(applyPandemicGlow, slot, false, nil) end
            end
        end
        if self.IconDisplay and self.IconDisplay.icons then
            for i = 1, #self.IconDisplay.icons do
                local w = self.IconDisplay.icons[i]
                if w and w._pandemicSlot then
                    pcall(applyPandemicGlow, w._pandemicSlot, false, nil)
                end
            end
        end
    end
    self:RequestRefresh()
    return true
end

function Auras:IsPandemicEnabled()
    local po = self:GetPandemicOpts()
    return po and po.enabled ~= false
end

function Auras:SetPandemicThreshold(value)
    local po = self:GetPandemicOpts()
    if not po then return false, "profile not ready" end
    local n = tonumber(value)
    if not n then return false, "threshold must be a number" end
    if n > 1 then n = n / 100 end
    if n < 0 then n = 0 elseif n > 1 then n = 1 end
    po.threshold = n
    pcall(self.PrebuildPandemicCurves, self)
    self:RequestRefresh()
    return true, n
end

function Auras:GetPandemicThreshold()
    local po = self:GetPandemicOpts()
    return (po and tonumber(po.threshold)) or 0.30
end

local function ensurePandemicSet(po, name)
    if type(po) ~= "table" then return nil end
    po[name] = po[name] or {}
    if type(po[name]) ~= "table" then po[name] = {} end
    return po[name]
end

function Auras:AddPandemicSkip(cdID)
    local n = tonumber(cdID)
    if not n then return false, "cdID must be a number" end
    local po = self:GetPandemicOpts()
    if not po then return false, "profile not ready" end
    local s = ensurePandemicSet(po, "skip")
    s[n] = true
    self:RequestRefresh()
    return true
end

function Auras:RemovePandemicSkip(cdID)
    local n = tonumber(cdID)
    if not n then return false, "cdID must be a number" end
    local po = self:GetPandemicOpts()
    if not po or type(po.skip) ~= "table" then return false, "skip set empty" end
    if not po.skip[n] then return false, "not in skip" end
    po.skip[n] = nil
    self:RequestRefresh()
    return true
end

function Auras:AddPandemicOnly(cdID)
    local n = tonumber(cdID)
    if not n then return false, "cdID must be a number" end
    local po = self:GetPandemicOpts()
    if not po then return false, "profile not ready" end
    local s = ensurePandemicSet(po, "only")
    s[n] = true
    self:RequestRefresh()
    return true
end

function Auras:RemovePandemicOnly(cdID)
    local n = tonumber(cdID)
    if not n then return false, "cdID must be a number" end
    local po = self:GetPandemicOpts()
    if not po or type(po.only) ~= "table" then return false, "only set empty" end
    if not po.only[n] then return false, "not in only" end
    po.only[n] = nil
    self:RequestRefresh()
    return true
end

function Auras:GetPandemicFilters()
    local po = self:GetPandemicOpts()
    local skipList, onlyList = {}, {}
    if po then
        if type(po.skip) == "table" then
            for k in pairs(po.skip) do
                if type(k) == "number" then skipList[#skipList + 1] = k end
            end
            table.sort(skipList)
        end
        if type(po.only) == "table" then
            for k in pairs(po.only) do
                if type(k) == "number" then onlyList[#onlyList + 1] = k end
            end
            table.sort(onlyList)
        end
    end
    return skipList, onlyList
end

function Auras:PandemicProbe(cdID)
    local n = tonumber(cdID)
    if not n then return nil, "cdID must be a number" end

    local lines = {}
    local function push(fmt, ...)
        if select("#", ...) > 0 then
            lines[#lines + 1] = string.format(fmt, ...)
        else
            lines[#lines + 1] = fmt
        end
    end

    local function safeName(it)
        if type(it) ~= "table" or type(it.GetName) ~= "function" then return "?" end
        local ok, nm = pcall(it.GetName, it)
        if not ok then return "errored" end
        return tostring(nm)
    end
    local function safeType(it)
        if type(it) ~= "table" or type(it.GetObjectType) ~= "function" then return "?" end
        local ok, ot = pcall(it.GetObjectType, it)
        if not ok then return "errored" end
        return tostring(ot)
    end

    local function probeOneViewer(viewerName, kindLabel)
        local viewer = getViewer(viewerName)
        if not viewer then
            push("  (%s viewer not loaded)", viewerName)
            return 0
        end
        local items = getItemFrames(viewer) or {}
        local found = 0
        for i = 1, #items do
            local item = items[i]
            if type(item) == "table" and tonumber(item.cooldownID) == n then
                found = found + 1
                push("---- match in %s [kind=%s] ----", viewerName, kindLabel)
                push("  GetName()         = %s", safeName(item))
                push("  GetObjectType()   = %s", safeType(item))
                push("  cooldownID        = %s", tostring(item.cooldownID))
                push("  auraInstanceID    = %s  (nil = not currently applied)",
                    tostring(item.auraInstanceID))
                push("  auraDataUnit      = %s", tostring(item.auraDataUnit))
                push("  type(PandemicIcon)  = %s", type(item.PandemicIcon))
                push("  type(PandemicAlert) = %s  (alternate name probe)", type(item.PandemicAlert))
                push("  type(Pandemic)      = %s  (alternate name probe)", type(item.Pandemic))
                local picon = item.PandemicIcon
                if type(picon) == "table" then
                    push("  PandemicIcon:GetObjectType() = %s", safeType(picon))
                    if type(picon.IsShown) == "function" then
                        local okS, sh = pcall(picon.IsShown, picon)
                        push("  PandemicIcon:IsShown()       = %s", okS and tostring(sh) or "errored")
                    else
                        push("  PandemicIcon:IsShown         = (no method)")
                    end
                    if type(picon.IsVisible) == "function" then
                        local okV, vis = pcall(picon.IsVisible, picon)
                        push("  PandemicIcon:IsVisible()     = %s", okV and tostring(vis) or "errored")
                    else
                        push("  PandemicIcon:IsVisible       = (no method)")
                    end
                else
                    push("  PandemicIcon:* skipped (field nil; Blizzard nils it on Hide)")
                end
                push("  pandemicStartTime = %s", tostring(item.pandemicStartTime))
                push("  pandemicEndTime   = %s", tostring(item.pandemicEndTime))
                push("  pandemicAlertTriggerTime = %s", tostring(item.pandemicAlertTriggerTime))
                if type(item.IsInPandemicTime) == "function" then
                    local okI, inT = pcall(item.IsInPandemicTime, item, GetTime())
                    push("  IsInPandemicTime(now) = %s", okI and tostring(inT) or "errored")
                end
                local vat = type(item.validAlertTypes) == "table" and item.validAlertTypes or nil
                if vat then
                    local keys = {}
                    for k in pairs(vat) do keys[#keys + 1] = tostring(k) end
                    push("  validAlertTypes field: { %s }", table.concat(keys, ", "))
                else
                    push("  validAlertTypes field: %s  (GetValidAlertTypes NOT called: mutates child -> taint)",
                        item.validAlertTypes == nil and "nil" or type(item.validAlertTypes))
                end
                if type(item.IsShown) == "function" then
                    local okIS, ish = pcall(item.IsShown, item)
                    push("  item:IsShown()       = %s", okIS and tostring(ish) or "errored")
                end
                local okR, verdict = pcall(readBlizzardPandemic, item)
                push("  readBlizzardPandemic() = %s", okR and tostring(verdict) or "errored")
                push("  first 30 keys via pairs(item):")
                local count = 0
                for k, v in pairs(item) do
                    count = count + 1
                    if count > 30 then break end
                    push("    [%d] %s : %s", count, tostring(k), type(v))
                end
                if count == 0 then
                    push("    (pairs yielded nothing -- frame uses a metatable-only mixin)")
                end
            end
        end
        return found
    end

    push("=== pandemic probe cdID=%d ===", n)
    local foundIcon = probeOneViewer(ICON_VIEWER_NAME, "icon")
    local foundBar  = probeOneViewer(BAR_VIEWER_NAME,  "bar")
    if foundIcon + foundBar == 0 then
        push("(no match -- cdID %d not present in either viewer's item frames)", n)
        push("  hint: run /tenui auras pandemic dump to list the cdIDs currently tracked")
    end
    return lines
end

function Auras:DumpPandemicState()
    local rows = {}
    local now = GetTime()
    local cdToChild = {}
    local cdToKind  = {}
    local function indexViewer(viewerName, kind)
        local viewer = getViewer(viewerName)
        if not viewer then return end
        local items = getItemFrames(viewer) or {}
        for i = 1, #items do
            local it = items[i]
            if type(it) == "table" then
                local cdID = tonumber(it.cooldownID)
                if cdID and cdToChild[cdID] == nil then
                    cdToChild[cdID] = it
                    cdToKind[cdID]  = kind
                end
            end
        end
    end
    indexViewer(BAR_VIEWER_NAME,  "bar")
    indexViewer(ICON_VIEWER_NAME, "icon")
    local opts = self:GetPandemicOpts()
    for cdID, st in pairs(pandemicState) do
        local child = cdToChild[cdID]
        local sid = child and getPandemicSpellID(child) or nil
        local pct = st.lastPct
        local sup = (st.suppressedUntil and st.suppressedUntil > now)
            and (st.suppressedUntil - now) or 0
        local classification = st.classification or "?"
        if child and opts then
            local okC, c = pcall(pandemicClassifyItem, child, opts)
            if okC and type(c) == "string" then classification = c end
        end
        local biz = st.bizPandemic == true
        if child then
            local okB, b = pcall(readBlizzardPandemic, child)
            if okB then biz = b == true end
        end
        local durSecret
        if st.lastDurObj ~= nil then
            local snap = st.lastDurObj
            if isSecret(snap) then
                durSecret = true
            else
                local okHS, hs = pcall(function() return snap:HasSecretValues() end)
                if okHS then durSecret = (hs == true) end
            end
        end
        rows[#rows + 1] = {
            cdID = cdID,
            kind = cdToKind[cdID] or st.kind or "?",
            spellID = sid,
            pct = pct,
            inWindow = st.inWindow == true,
            suppressedDelta = sup,
            classification = classification,
            bizPandemic = biz,
            source = st.source or "?",
            durHasSecret = durSecret,
        }
    end
    for cdID, child in pairs(cdToChild) do
        if not pandemicState[cdID] then
            local classification = "default-reject"
            if opts then
                local okC, c = pcall(pandemicClassifyItem, child, opts)
                if okC and type(c) == "string" then classification = c end
            end
            local biz = false
            local okB, b = pcall(readBlizzardPandemic, child)
            if okB then biz = b == true end
            rows[#rows + 1] = {
                cdID = cdID,
                kind = cdToKind[cdID] or "?",
                spellID = getPandemicSpellID(child),
                pct = nil,
                inWindow = false,
                suppressedDelta = 0,
                classification = classification,
                bizPandemic = biz,
                source = "none",
                durHasSecret = nil,
            }
        end
    end
    table.sort(rows, function(a, b) return (a.cdID or 0) < (b.cdID or 0) end)
    return rows
end

local function migrateSchema(p)
    if type(p) ~= "table" then return end

    if not p._fvpDefaultMigrated then
        if p.forceViewerPopulated == nil then
            p.forceViewerPopulated = true
        end
        p._fvpDefaultMigrated = true
    end

    if p._migratedSplit then return end

    local hadOldShape = p.displayMode ~= nil
        or p.iconSpacing ~= nil
        or p.iconAnchor ~= nil
        or p.showStackText ~= nil
        or (p.barHeight ~= nil and type(p.bars) ~= "table")

    if hadOldShape then
        p.icons = type(p.icons) == "table" and p.icons or {}
        p.bars  = type(p.bars)  == "table" and p.bars  or {}

        if p.iconSpacing ~= nil and p.icons.spacing == nil then
            p.icons.spacing = p.iconSpacing
        end
        if p.iconAnchor ~= nil and p.icons.align == nil then
            p.icons.align = p.iconAnchor
        end
        if p.showStackText ~= nil and p.icons.showStackText == nil then
            p.icons.showStackText = p.showStackText
        end
        if p.barHeight ~= nil and p.bars.barHeight == nil then
            p.bars.barHeight = p.barHeight
        end

        local mode = p.displayMode
        if mode == "icons" then
            if p.icons.enabled == nil then p.icons.enabled = true end
            if p.bars.enabled  == nil then p.bars.enabled  = true end
        elseif mode == "bars" then
            if p.bars.enabled  == nil then p.bars.enabled  = true end
            if p.icons.enabled == nil then p.icons.enabled = true end
        end

        p.displayMode   = nil
        p.iconSpacing   = nil
        p.iconAnchor    = nil
        p.showStackText = nil
        p.barHeight     = nil

        dlog("migrated old displayMode=%s schema into split icons/bars",
            tostring(mode))
    end

    p._migratedSplit = true
end

if type(_G.StaticPopupDialogs) == "table" and not _G.StaticPopupDialogs["TENUI_CDM_EDITMODE_RELOAD"] then
    _G.StaticPopupDialogs["TENUI_CDM_EDITMODE_RELOAD"] = {
        text = "TenUI updated your Cooldown Manager Edit Mode settings so cooldown/aura tracking works in combat.\n\nA UI reload is REQUIRED now. Until you reload, cooldown/aura tracking will be broken in combat.",
        button1 = _G.RELOADUI or "Reload UI",
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,
        noCancelOnReuse = true,
        preferredIndex = 3,
        showAlert = true,
        OnAccept = function() if _G.ReloadUI then _G.ReloadUI() end end,
    }
end

function Auras:EnforceCDMViewerAlwaysVisible()
    if self._editModePolicyApplied then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts
            and Enum and Enum.EditModeSystem and Enum.EditModeSystem.CooldownViewer
            and Enum.EditModeCooldownViewerSetting and Enum.CooldownViewerVisibleSetting
            and Enum.EditModeCooldownViewerSetting.VisibleSetting ~= nil
            and Enum.CooldownViewerVisibleSetting.Always ~= nil) then
        return false
    end

    local okLayout, layoutInfo = pcall(C_EditMode.GetLayouts)
    if not okLayout or type(layoutInfo) ~= "table" or type(layoutInfo.layouts) ~= "table" then
        return false
    end

    local numPresets = 0
    if _G.EditModePresetLayoutManager
       and type(_G.EditModePresetLayoutManager.GetCopyOfPresetLayouts) == "function"
       and type(_G.tAppendAll) == "function" then
        local okP, presets = pcall(_G.EditModePresetLayoutManager.GetCopyOfPresetLayouts, _G.EditModePresetLayoutManager)
        if okP and type(presets) == "table" then
            numPresets = #presets
            _G.tAppendAll(presets, layoutInfo.layouts)
            layoutInfo.layouts = presets
        end
    end

    local activeIdx = layoutInfo.activeLayout
    local activeLayout = type(activeIdx) == "number" and layoutInfo.layouts[activeIdx]
    if type(activeLayout) ~= "table" or type(activeLayout.systems) ~= "table" then
        return false
    end

    if numPresets > 0 and type(activeIdx) == "number" and activeIdx <= numPresets then
        self._editModePolicyApplied = true
        return false
    end

    local cooldownSystem = Enum.EditModeSystem.CooldownViewer
    local visSetting     = Enum.EditModeCooldownViewerSetting.VisibleSetting
    local visAlways      = Enum.CooldownViewerVisibleSetting.Always
    local changed = false

    for _, sysInfo in ipairs(activeLayout.systems) do
        if sysInfo.system == cooldownSystem and type(sysInfo.settings) == "table" then
            for _, s in ipairs(sysInfo.settings) do
                if s.setting == visSetting then
                    if s.value ~= visAlways then
                        s.value = visAlways
                        changed = true
                    end
                    break
                end
            end
        end
    end

    self._editModePolicyApplied = true
    dinfo("EnforceCDMViewerAlwaysVisible: latched changed=%s presets=%d",
        tostring(changed), numPresets)
    if not changed then return false end

    dwarn("EnforceCDMViewerAlwaysVisible: calling C_EditMode.SaveLayouts -- this triggers EDIT_MODE_LAYOUTS_UPDATED -> UpdateSystems in TenUI's tainted context, which TAINTS the CooldownViewer system frames until /reload. Forcing a reload now. (one-shot per session)")
    local okSave = pcall(C_EditMode.SaveLayouts, layoutInfo)
    if not okSave then
        dwarn("EnforceCDMViewerAlwaysVisible: SaveLayouts failed")
        return false
    end

    if _G.StaticPopup_Show then
        pcall(_G.StaticPopup_Show, "TENUI_CDM_EDITMODE_RELOAD")
    end
    return true
end

function Auras:EnsureCDMViewerEditModePolicy()
    if self._editModePolicyApplied then return end
    if not (InCombatLockdown and InCombatLockdown()) then
        self:EnforceCDMViewerAlwaysVisible()
        return
    end
    if self._editModePolicyDeferred then return end
    self._editModePolicyDeferred = true
    local f = CreateFrame("Frame")
    self._editModePolicyDeferFrame = f
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(frame)
        frame:UnregisterAllEvents()
        frame:SetScript("OnEvent", nil)
        Auras._editModePolicyDeferred = nil
        Auras._editModePolicyDeferFrame = nil
        Auras:EnforceCDMViewerAlwaysVisible()
    end)
end

local SUPPRESSED_VIEWER_NAMES = { ICON_VIEWER_NAME, BAR_VIEWER_NAME }

local _lastLoggedAlpha = {}

local function setViewerAlpha(name, alpha)
    if InCombatLockdown and InCombatLockdown() then return false end
    local v = _G[name]
    if type(v) ~= "table" or type(v.SetAlpha) ~= "function" then
        if _lastLoggedAlpha[name] ~= "missing" then
            dtrace("setViewerAlpha " .. tostring(name) .. " -> " .. tostring(alpha)
                .. " SKIPPED (viewer not ready)")
            _lastLoggedAlpha[name] = "missing"
        end
        return false
    end
    local liveAlpha
    if type(v.GetAlpha) == "function" then
        local okG, a = pcall(v.GetAlpha, v)
        if okG then liveAlpha = a end
    end
    local changed = (_lastLoggedAlpha[name] ~= alpha) or (liveAlpha ~= nil and liveAlpha ~= alpha)
    if changed then
        dtrace("setViewerAlpha " .. tostring(name) .. " -> " .. tostring(alpha)
            .. " (was live=" .. tostring(liveAlpha) .. ")")
    end
    _lastLoggedAlpha[name] = alpha
    local ok, err = pcall(v.SetAlpha, v, alpha)
    if not ok then
        dwarn("SetAlpha(%s, %s) failed: %s", tostring(name), tostring(alpha), tostring(err))
        return false
    end
    return true
end

local _lastForceShownLog = {}
local function forceShownViewer(name)
    local v = _G[name]
    if type(v) ~= "table" then return false end
    local isShown
    if type(v.IsShown) == "function" then
        local okS, s = pcall(v.IsShown, v)
        if okS then isShown = s end
    end
    if isShown == false then
        if _lastForceShownLog[name] ~= true then
            dtrace("forceShownViewer " .. tostring(name)
                .. " -> Blizzard hides this viewer (CDM visibility); NOT force-shown (would taint Blizzard refresh)")
            _lastForceShownLog[name] = true
        end
    else
        _lastForceShownLog[name] = nil
    end
    return isShown == true
end

function Auras:IsForceViewerPopulated()
    local p = self.profileRef
    return p and p.forceViewerPopulated == true
end

function Auras:_ViewerFrameTainted(name)
    local v = _G[name]
    if type(v) ~= "table" then return false end
    if type(v.HasSecretValues) == "function" then
        local ok, s = pcall(v.HasSecretValues, v)
        if ok and s == true then return true end
    end
    if type(v.HasAnySecretAspect) == "function" then
        local ok, s = pcall(v.HasAnySecretAspect, v)
        if ok and s == true then return true end
    end
    if type(v.IsAnchoringSecret) == "function" then
        local ok, s = pcall(v.IsAnchoringSecret, v)
        if ok and s == true then return true end
    end
    return false
end

function Auras:_CheckViewerTaintAndPromptReload()
    if not (self:_ViewerFrameTainted(BAR_VIEWER_NAME)
            or self:_ViewerFrameTainted(ICON_VIEWER_NAME)
            or self:_ViewerFrameTainted("EssentialCooldownViewer")
            or self:_ViewerFrameTainted("UtilityCooldownViewer")) then
        self._viewerTaintPrompted = nil
        return
    end
    if self._viewerTaintPrompted then return end
    self._viewerTaintPrompted = true
    dwarn("CooldownViewer frame is TAINTED (secret aspect present) -- Blizzard RefreshData will fault on SPELL_UPDATE_COOLDOWN (:382/:454 flood) and tracked bars will not populate. A /reload clears it. Source: an addon (this session) called C_EditMode.SaveLayouts, whose reapply taints the viewers.")
    if _G.StaticPopup_Show and not (InCombatLockdown and InCombatLockdown()) then
        pcall(_G.StaticPopup_Show, "TENUI_CDM_EDITMODE_RELOAD")
    end
end

local _lastSuppressLog = 0
function Auras:SuppressNativeViewers()
    if ns.Debug and ns.Debug.IsTrace and ns.Debug:IsTrace(AURAS_MODULE) then
        local now = GetTime and GetTime() or 0
        if now - _lastSuppressLog >= 1.0 then
            _lastSuppressLog = now
            dtrace("SuppressNativeViewers called, viewers: "
                .. "BuffIcon=" .. tostring(_G.BuffIconCooldownViewer ~= nil)
                .. " BuffBar=" .. tostring(_G.BuffBarCooldownViewer ~= nil))
        end
    end
    pcall(self._CheckViewerTaintAndPromptReload, self)
    local forcePop = self:IsForceViewerPopulated()
    for i = 1, #SUPPRESSED_VIEWER_NAMES do
        local name = SUPPRESSED_VIEWER_NAMES[i]
        if forcePop then
            forceShownViewer(name)
        end
        if not (InCombatLockdown and InCombatLockdown()) then
            setViewerAlpha(name, 0)
            if name == BAR_VIEWER_NAME then
                local v = _G[name]
                if type(v) == "table" and type(v.SetPoint) == "function"
                   and type(v.ClearAllPoints) == "function" then
                    if not self._buffBarOrigPoints and type(v.GetNumPoints) == "function" then
                        local saved = {}
                        local okN, n = pcall(v.GetNumPoints, v)
                        if okN and type(n) == "number" and n > 0 then
                            for pi = 1, n do
                                local okP, point, rel, relPoint, x, y = pcall(v.GetPoint, v, pi)
                                if okP and point ~= nil then
                                    saved[#saved + 1] = { point, rel, relPoint, x, y }
                                end
                            end
                        end
                        self._buffBarOrigPoints = saved
                    end
                    pcall(v.ClearAllPoints, v)
                    pcall(v.SetPoint, v, "TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
                end
            end
        end
    end
end

function Auras:ApplyViewerVisibilityMode()
    if not self._enabled then return end
    if not self:IsForceViewerPopulated() then
        self:UnsuppressNativeViewers()
    end
    self:SuppressNativeViewers()
    if self.RequestRefresh then pcall(self.RequestRefresh, self) end
end

function Auras:UnsuppressNativeViewers()
    dinfo("UnsuppressNativeViewers called")
    for i = 1, #SUPPRESSED_VIEWER_NAMES do
        local name = SUPPRESSED_VIEWER_NAMES[i]
        local ok = setViewerAlpha(name, 1)
        dlog("unsuppress native viewer %s -> %s", name, tostring(ok))
        _lastForceShownLog[name] = nil
        if name == BAR_VIEWER_NAME and self._buffBarOrigPoints
           and not (InCombatLockdown and InCombatLockdown()) then
            local v = _G[name]
            if type(v) == "table" and type(v.SetPoint) == "function"
               and type(v.ClearAllPoints) == "function" then
                pcall(v.ClearAllPoints, v)
                local pts = self._buffBarOrigPoints
                for pi = 1, #pts do
                    local p = pts[pi]
                    pcall(v.SetPoint, v, p[1], p[2], p[3], p[4], p[5])
                end
            end
            self._buffBarOrigPoints = nil
        end
    end
end

local MIRROR_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TARGET_CHANGED",
    "SPELL_UPDATE_COOLDOWN",
}

function Auras:OnEnable(_, profile)
    if self._enabled then return end

    migrateSchema(profile)

    self.profileRef = profile
    self._enabled = true

    self._currentScopeKey = self:GetCurrentScopeKey()
    ensureScope(self._currentScopeKey)

    self.IconDisplay = IconDisplay.New(self)
    self.BarDisplay  = BarDisplay.New(self)
    self.IconDisplay:EnsureContainer()
    self.BarDisplay:EnsureContainer()

    pcall(self.EnsureCDMViewerEditModePolicy, self)

    ensureAuraCacheFrame()
    Auras._refreshSummonSpecGate()
    if self._auraCacheFrame then
        if self._auraCacheFrame.RegisterUnitEvent then
            pcall(self._auraCacheFrame.RegisterUnitEvent, self._auraCacheFrame,
                "UNIT_SPELLCAST_SUCCEEDED", "player")
        else
            pcall(self._auraCacheFrame.RegisterEvent, self._auraCacheFrame,
                "UNIT_SPELLCAST_SUCCEEDED")
        end
    end

    if not self._mirrorFrame then
        self._mirrorFrame = CreateFrame("Frame", "TenUIAurasMirrorFrame")
    end
    do
        local ef = self._mirrorFrame
        local mod = self
        ef:SetScript("OnEvent", function(_, event, ...)
            if event == "PLAYER_ENTERING_WORLD" then
                if mod._enabled then
                    mod:SuppressNativeViewers()
                end
                mod:InvalidateViewerAuraMap()
            end
            if event == "TRAIT_CONFIG_UPDATED"
               or event == "SPELLS_CHANGED"
               or event == "PLAYER_SPECIALIZATION_CHANGED"
               or event == "COOLDOWN_VIEWER_DATA_LOADED" then
                mod:InvalidateViewerAuraMap()
            end
            if event == "COOLDOWN_VIEWER_DATA_LOADED"
               or event == "PLAYER_SPECIALIZATION_CHANGED" then
                mod:_ResyncScope()
                if event == "COOLDOWN_VIEWER_DATA_LOADED" and mod._enabled then
                    mod:SuppressNativeViewers()
                end
                if mod._enabled then pcall(mod.PrewarmDisplays, mod) end
                return
            end
            if event == "TRAIT_CONFIG_UPDATED" or event == "SPELLS_CHANGED" then
                return
            end
            mod:RequestRefresh()
        end)
        for _, ev in ipairs(MIRROR_EVENTS) do
            ef:RegisterEvent(ev)
        end
        pcall(ef.RegisterEvent, ef, "COOLDOWN_VIEWER_DATA_LOADED")
        pcall(ef.RegisterEvent, ef, "TRAIT_CONFIG_UPDATED")
        pcall(ef.RegisterEvent, ef, "SPELLS_CHANGED")
        if ef.RegisterUnitEvent then
            pcall(ef.RegisterUnitEvent, ef, "UNIT_AURA", "player", "target")
        end
    end

    if not self._scopeEventFrame then
        self._scopeEventFrame = CreateFrame("Frame", "TenUIAurasScopeFrame")
    end
    do
        local ef = self._scopeEventFrame
        local mod = self
        ef:SetScript("OnEvent", function() mod:_ResyncScope() end)
        ef:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        ef:RegisterEvent("PLAYER_ENTERING_WORLD")
    end

    local mod = self
    self._resizeCB = ns:RegisterMessage("ANCHOR_RESIZED", function(_, anchorName)
        if anchorName == ICON_ANCHOR_NAME then
            if mod.IconDisplay then mod.IconDisplay:Layout(mod.IconDisplay.activeCount or 0) end
        elseif anchorName == BAR_ANCHOR_NAME then
            if mod.BarDisplay then mod.BarDisplay:Layout(mod.BarDisplay.activeCount or 0) end
        end
    end)

    if not self._viewerHooked then
        self._viewerHooked = true
        for _, vn in ipairs({ ICON_VIEWER_NAME, BAR_VIEWER_NAME }) do
            local v = getViewer(vn)
            if v and type(v.RefreshLayout) == "function" then
                pcall(hooksecurefunc, v, "RefreshLayout", function(self_)
                    mod:InvalidateViewerAuraMap()
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, function()
                            mod:Refresh()
                            pcall(installPandemicHooks)
                        end)
                    else
                        mod:Refresh()
                        pcall(installPandemicHooks)
                    end
                end)
            end
        end
    end

    if not self._suppressFrame then
        self._suppressFrame = CreateFrame("Frame", "TenUIAurasSuppressFrame")
    end
    do
        local ef = self._suppressFrame
        ef:UnregisterAllEvents()
        ef:SetScript("OnEvent", function(_, event)
            if not Auras._enabled then return end
            pcall(Auras.SuppressNativeViewers, Auras)
            if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" then
                pcall(Auras.PrebuildPandemicCurves, Auras)
            end
            if event == "PLAYER_REGEN_ENABLED"
               or event == "PLAYER_ENTERING_WORLD"
               or event == "COOLDOWN_VIEWER_DATA_LOADED" then
                pcall(Auras.PrewarmDisplays, Auras)
            end
        end)
        ef:RegisterEvent("PLAYER_REGEN_DISABLED")
        ef:RegisterEvent("PLAYER_REGEN_ENABLED")
        ef:RegisterEvent("PLAYER_TARGET_CHANGED")
        ef:RegisterEvent("PLAYER_ENTERING_WORLD")
        pcall(ef.RegisterEvent, ef, "COOLDOWN_VIEWER_DATA_LOADED")
    end

    if not self._ticker and C_Timer and C_Timer.NewTicker then
        self._ticker = C_Timer.NewTicker(MIRROR_INTERVAL_SEC, function()
            if mod._enabled and Auras._liveAura and Auras._liveAura.rescanUnitAuras then
                pcall(Auras._liveAura.rescanUnitAuras, "player", true)
                if UnitExists and UnitExists("target") then
                    pcall(Auras._liveAura.rescanUnitAuras, "target", true)
                end
            end
            mod:Refresh()
        end)
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if Auras._enabled then Auras:SuppressNativeViewers() end
        end)
    else
        self:SuppressNativeViewers()
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if Auras._enabled then pcall(installPandemicHooks) end
        end)
    else
        pcall(installPandemicHooks)
    end

    pcall(wipeAllGlowState)

    pcall(self.PrebuildPandemicCurves, self)

    pcall(self.PrewarmDisplays, self)

    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if not Auras._enabled then return end
            if Auras._liveAura and Auras._liveAura.rescanUnitAuras then
                pcall(Auras._liveAura.rescanUnitAuras, "player")
                if UnitExists and UnitExists("target") then
                    pcall(Auras._liveAura.rescanUnitAuras, "target")
                end
            end
            if Auras.RequestRefresh then pcall(Auras.RequestRefresh, Auras) end
        end)
    end

    self:Refresh()
    dlog("enabled scope=%s icons=%s bars=%s", tostring(self._currentScopeKey),
        tostring(self:IsDisplayEnabled("icons")), tostring(self:IsDisplayEnabled("bars")))
end

function Auras:OnDisable()
    if not self._enabled then return end
    self._enabled = false
    pcall(wipeAllGlowState)
    if self._ticker and self._ticker.Cancel then
        self._ticker:Cancel()
        self._ticker = nil
    end
    if self._mirrorFrame then
        self._mirrorFrame:UnregisterAllEvents()
        self._mirrorFrame:SetScript("OnEvent", nil)
    end
    if self._scopeEventFrame then
        self._scopeEventFrame:UnregisterAllEvents()
        self._scopeEventFrame:SetScript("OnEvent", nil)
    end
    if self._suppressFrame then
        self._suppressFrame:UnregisterAllEvents()
        self._suppressFrame:SetScript("OnEvent", nil)
    end
    if self._resizeCB then
        ns:UnregisterMessage("ANCHOR_RESIZED", self._resizeCB)
        self._resizeCB = nil
    end
    if self.IconDisplay then self.IconDisplay:DestroyIcons() end
    if self.BarDisplay then self.BarDisplay:DestroyBars() end
    resetPandemicState()

    if self._auraCacheFrame then
        pcall(self._auraCacheFrame.UnregisterEvent, self._auraCacheFrame, "UNIT_SPELLCAST_SUCCEEDED")
    end
    wipe(Auras._summonActiveUntil)
    Auras._summonSpecGateOK = false

    self:UnsuppressNativeViewers()
end

function cdmCategoryFor(displayType)
    local enum = Enum and Enum.CooldownViewerCategory
    if displayType == "TrackedIcon" or displayType == "icons" then
        return (enum and enum.TrackedBuff) or CATEGORY_TRACKED_BUFF, "CDM:TrackedBuff", "TrackedIcon"
    end
    if displayType == "TrackedBars" or displayType == "bars" then
        return (enum and enum.TrackedBar) or CATEGORY_TRACKED_BAR, "CDM:TrackedBar", "TrackedBars"
    end
    return nil
end

function cdmCatalogAvailable()
    if not C_CooldownViewer then return false end
    if type(C_CooldownViewer.GetCooldownViewerCategorySet) ~= "function" then return false end
    if type(C_CooldownViewer.GetCooldownViewerCooldownInfo) ~= "function" then return false end
    return true
end

function liveCategorySet(category)
    if category == nil then return nil end
    if not cdmCatalogAvailable() then return nil end
    local okS, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, true)
    if okS and type(ids) == "table" then
        return ids
    end
    return nil
end

local function cdmSettingsDataProvider()
    local cvs = _G.CooldownViewerSettings
    if type(cvs) ~= "table" or type(cvs.GetDataProvider) ~= "function" then
        return nil
    end
    local okP, provider = pcall(cvs.GetDataProvider, cvs)
    if not okP or type(provider) ~= "table" then
        return nil
    end
    if type(provider.GetOrderedCooldownIDsForCategory) ~= "function" then
        return nil
    end
    return provider
end

function orderedConfiguredIDs(category)
    if category == nil then return nil end
    local provider = cdmSettingsDataProvider()
    if provider then
        local okO, ids = pcall(provider.GetOrderedCooldownIDsForCategory, provider, category, true)
        if okO and type(ids) == "table" and #ids > 0 then
            return ids, "ordered"
        end
    end
    local fallback = liveCategorySet(category)
    if type(fallback) == "table" then
        return fallback, "static"
    end
    return nil
end

local _liveRenderCat = { map = nil, source = nil, rankByCategory = nil }

local function liveRenderCategoryMap()
    if _liveRenderCat.map ~= nil then
        return _liveRenderCat.map, _liveRenderCat.source
    end
    if not cdmCatalogAvailable() then
        return nil
    end
    if InCombatLockdown and InCombatLockdown() then
        return nil
    end

    local enum = Enum and Enum.CooldownViewerCategory
    local pairsCat = {
        { cat = (enum and enum.TrackedBuff) or CATEGORY_TRACKED_BUFF, displayType = "TrackedIcon" },
        { cat = (enum and enum.TrackedBar)  or CATEGORY_TRACKED_BAR,  displayType = "TrackedBars" },
    }

    local map = {}
    local rankByCategory = {}
    local sawOrdered = false
    for _, def in ipairs(pairsCat) do
        local ids, src = orderedConfiguredIDs(def.cat)
        if src == "ordered" then sawOrdered = true end
        local rank = {}
        if type(ids) == "table" then
            for i = 1, #ids do
                local cdID = tonumber(ids[i])
                if cdID then
                    map[cdID] = def.displayType
                    if rank[cdID] == nil then rank[cdID] = i end
                end
            end
        end
        rankByCategory[def.cat] = rank
    end

    _liveRenderCat.map = map
    _liveRenderCat.source = sawOrdered and "ordered" or "static"
    _liveRenderCat.rankByCategory = rankByCategory
    return _liveRenderCat.map, _liveRenderCat.source
end

function Auras:_invalidateLiveRenderCategoryMap()
    _liveRenderCat.map = nil
    _liveRenderCat.source = nil
    _liveRenderCat.rankByCategory = nil
end

local function resolveRenderDisplayType(cdID, staticDisplayType)
    local map = liveRenderCategoryMap()
    if type(map) == "table" then
        local live = map[tonumber(cdID)]
        if live ~= nil then return live, "live" end
    end
    return staticDisplayType, "static"
end

function cdmCategoryCount(category)
    if not cdmCatalogAvailable() or category == nil then return 0 end
    local ids = liveCategorySet(category)
    if type(ids) ~= "table" then return 0 end
    local n = 0
    for i = 1, #ids do
        local info
        local ok = pcall(function()
            info = C_CooldownViewer.GetCooldownViewerCooldownInfo(ids[i])
        end)
        if ok and type(info) == "table" and info.isKnown ~= false then
            n = n + 1
        end
    end
    return n
end

infoAuraSpellIDs = function(info, out)
    out = out or {}
    if type(info) ~= "table" then return out end
    local function add(v)
        v = tonumber(v)
        if _IsUsableSID(v) then
            for i = 1, #out do if out[i] == v then return end end
            out[#out + 1] = v
        end
    end
    add(info.overrideSpellID)
    add(info.spellID)
    add(info.overrideTooltipSpellID)
    if type(info.linkedSpellIDs) == "table" then
        for i = 1, #info.linkedSpellIDs do add(info.linkedSpellIDs[i]) end
    end
    return out
end

anyPlayerOrTargetAura = function(ids)
    if type(ids) ~= "table" or #ids == 0 then return false end
    local hasTarget = UnitExists and UnitExists("target")
    for i = 1, #ids do
        local sid = ids[i]
        if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
            local ok, ad = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
            if ok and ad ~= nil then return true end
        end
        if hasTarget and C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID then
            local ok, ad = pcall(C_UnitAuras.GetUnitAuraBySpellID, "target", sid)
            if ok and ad ~= nil then return true end
        elseif hasTarget and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID then
            local ok, ad = pcall(C_UnitAuras.GetAuraDataBySpellID, "target", sid, "HARMFUL")
            if ok and ad ~= nil then return true end
        end
    end
    return false
end

function cdmActiveForInfo(info)
    if type(info) ~= "table" then return nil end

    local cdID = tonumber(info.cooldownID)
    if cdID then
        local ok, set = pcall(viewerActiveCooldownIDSet, false)
        if ok and type(set) == "table" and set[cdID] then
            return true
        end
    end

    local ids = infoAuraSpellIDs(info)
    if anyPlayerOrTargetAura(ids) then return true end

    for i = 1, #ids do
        local ok, child = pcall(Auras.GetViewerChildBySpellID, Auras, ids[i])
        if ok and type(child) == "table" and childShownActive(child) then
            return true
        end
    end

    return false
end

function cdmLabelAndIcon(spellID)
    local label, icon
    if spellID and C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, spellID)
        if ok and type(n) == "string" and n ~= "" then label = n end
    end
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and tex then icon = tex end
    end
    if not label then label = "aura:" .. tostring(spellID) end
    return label, icon
end

local function GetBaseSpellID(entry)
    return type(entry) == "table" and entry.spellID or nil
end

local function BuildMatchSpellIDs(entry)
    local out = {}
    if type(entry) ~= "table" then return out end
    local function add(v)
        v = tonumber(v)
        if _IsUsableSID(v) then
            for i = 1, #out do if out[i] == v then return end end
            out[#out + 1] = v
        end
    end
    if type(entry.linkedSpellIDs) == "table" then
        for i = 1, #entry.linkedSpellIDs do add(entry.linkedSpellIDs[i]) end
    end
    add(entry.overrideTooltipSpellID)
    add(entry.overrideSpellID)
    add(entry.spellID)
    return out
end

local function BuildStableEntryID(entry)
    if type(entry) ~= "table" then return nil end
    local cdID = tonumber(entry.cooldownID)
    if cdID then
        return "cdm:" .. cdID
    end
    local sid = tonumber(entry.spellID)
    if sid then return "spell:" .. sid end
    return nil
end

local function GetLinkedSpell(entry)
    return type(entry) == "table" and entry.linkedSpellID or nil
end

local function SetLinkedSpell(entry, linkedSpellID)
    if type(entry) ~= "table" then return false end
    if entry.linkedSpellID == linkedSpellID then return false end
    entry.linkedSpellID = linkedSpellID
    return true
end

local function GetAuraSpellID(entry)
    return type(entry) == "table" and entry.auraSpellID or nil
end

local function UpdateLinkedSpell(entry, spellID)
    if type(entry) ~= "table" then return false end
    local linked = entry.linkedSpellIDs
    if type(linked) ~= "table" then return false end
    if isSecret(spellID) then return false end
    if entry.linkedSpellID ~= nil and spellID == GetBaseSpellID(entry) then
        return SetLinkedSpell(entry, nil)
    end
    for i = 1, #linked do
        if linked[i] == spellID then
            entry._linkedFromAura = true
            return SetLinkedSpell(entry, spellID)
        end
    end
    return false
end

local function SpellIDMatchesAnyAssociatedSpellIDs(entry, spellID, excludeRawLinked)
    if type(entry) ~= "table" then return false end
    if isSecret(spellID) then return false end
    if spellID == nil then return false end
    local auraSpellID = GetAuraSpellID(entry)
    if not isSecret(auraSpellID) and auraSpellID ~= nil and spellID == auraSpellID then
        return true, "auraSpellID"
    end
    if entry.linkedSpellID == spellID then return true, "linkedSpellID" end
    if entry.overrideTooltipSpellID == spellID then return true, "overrideTooltipSpellID" end
    if entry.overrideSpellID == spellID then return true, "overrideSpellID" end
    if entry.spellID == spellID then return true, "spellID" end
    if excludeRawLinked then return false end
    local linked = entry.linkedSpellIDs
    if type(linked) == "table" then
        for i = 1, #linked do
            if linked[i] == spellID then return true, "linkedSpellIDs[" .. i .. "]" end
        end
    end
    return false
end

local function GetDisplaySpellID(entry)
    if type(entry) ~= "table" then return nil end
    local auraSpellID = GetAuraSpellID(entry)
    if auraSpellID and not isSecret(auraSpellID) then return auraSpellID end
    if entry.linkedSpellID and not isSecret(entry.linkedSpellID) then return entry.linkedSpellID end
    if entry.overrideTooltipSpellID and not isSecret(entry.overrideTooltipSpellID) then return entry.overrideTooltipSpellID end
    if entry.overrideSpellID and not isSecret(entry.overrideSpellID) then return entry.overrideSpellID end
    if entry.spellID and not isSecret(entry.spellID) then return entry.spellID end
    return nil
end

local function GetDisplayTexture(entry)
    if type(entry) ~= "table" then return nil, nil end
    local function tex(sid)
        if not (sid and C_Spell and C_Spell.GetSpellTexture) then return nil end
        if isSecret(sid) then return nil end
        local ok, t = pcall(C_Spell.GetSpellTexture, sid)
        if ok and Auras._validTexture(t) then return t end
        return nil
    end
    local auraSpellID = GetAuraSpellID(entry)
    if auraSpellID then
        local t = tex(auraSpellID)
        if t then return t, "aura" end
    end
    if entry.linkedSpellID then
        local t = tex(entry.linkedSpellID)
        if t then return t, "linked" end
    end
    if entry.overrideTooltipSpellID then
        local t = tex(entry.overrideTooltipSpellID)
        if t then return t, "overrideTooltip" end
    end
    local t = tex(entry.spellID)
    if t then return t, "base" end
    if Auras._validTexture(entry.icon) then return entry.icon, "fallback" end
    return nil, "fallback"
end

local function GetDisplayName(entry)
    if type(entry) ~= "table" then return nil, nil end
    local function nm(sid)
        if not (sid and C_Spell and C_Spell.GetSpellName) then return nil end
        if isSecret(sid) then return nil end
        local ok, n = pcall(C_Spell.GetSpellName, sid)
        if ok and type(n) == "string" and n ~= "" then return n end
        return nil
    end
    local auraSpellID = GetAuraSpellID(entry)
    if auraSpellID then
        local n = nm(auraSpellID)
        if n then return n, "aura" end
    end
    if entry.linkedSpellID then
        local n = nm(entry.linkedSpellID)
        if n then return n, "linked" end
    end
    if entry.overrideTooltipSpellID then
        local n = nm(entry.overrideTooltipSpellID)
        if n then return n, "overrideTooltip" end
    end
    if entry.overrideSpellID then
        local n = nm(entry.overrideSpellID)
        if n then return n, "override" end
    end
    local n = nm(entry.spellID)
    if n then return n, "base" end
    return entry.label, "label"
end

local function RefreshDisplayFields(entry)
    if type(entry) ~= "table" then return end
    entry.displaySpellID = GetDisplaySpellID(entry)
    local name, labelSource = GetDisplayName(entry)
    entry.displayName  = name
    entry.labelSource  = labelSource
    if not Auras._validTexture(entry.displayIcon) then
        local icon, iconSource = GetDisplayTexture(entry)
        entry.displayIcon  = icon
        entry.iconSource   = iconSource
    end
end

local function SetAuraInstanceInfo(entry, auraInfo, unit)
    if type(entry) ~= "table" or type(auraInfo) ~= "table" then return end
    local auraSpellID  = auraInfo.spellId
    local auraInstance = auraInfo.auraInstanceID
    entry.auraSpellID    = auraSpellID
    entry.auraInstanceID = auraInstance
    entry.auraDataUnit   = unit
    entry.activeAuraSource = "unitAura"
    UpdateLinkedSpell(entry, auraSpellID)
    RefreshDisplayFields(entry)
end

local function ClearAuraInstanceInfo(entry)
    if type(entry) ~= "table" then return end
    if entry._linkedFromAura then
        local auraSpellID = GetAuraSpellID(entry)
        if not isSecret(auraSpellID) and auraSpellID == GetLinkedSpell(entry) then
            SetLinkedSpell(entry, nil)
        else
            SetLinkedSpell(entry, nil)
        end
    end
    entry._linkedFromAura  = nil
    entry.auraSpellID      = nil
    entry.auraInstanceID   = nil
    entry.auraDataUnit     = nil
    entry.activeAuraSource = nil
    RefreshDisplayFields(entry)
end

Auras._cdm = {
    GetBaseSpellID                     = GetBaseSpellID,
    BuildMatchSpellIDs                 = BuildMatchSpellIDs,
    BuildStableEntryID                 = BuildStableEntryID,
    GetLinkedSpell                     = GetLinkedSpell,
    SetLinkedSpell                     = SetLinkedSpell,
    GetAuraSpellID                     = GetAuraSpellID,
    UpdateLinkedSpell                  = UpdateLinkedSpell,
    SpellIDMatchesAnyAssociatedSpellIDs = SpellIDMatchesAnyAssociatedSpellIDs,
    GetDisplaySpellID                  = GetDisplaySpellID,
    GetDisplayTexture                  = GetDisplayTexture,
    GetDisplayName                     = GetDisplayName,
    RefreshDisplayFields               = RefreshDisplayFields,
    SetAuraInstanceInfo                = SetAuraInstanceInfo,
    ClearAuraInstanceInfo              = ClearAuraInstanceInfo,
    IsUsableSID                        = _IsUsableSID,
}

local function buildCatalogEntry(cdID, info, source, normCategory)
    local spellID         = tonumber(info.spellID)
    local overrideSpellID = tonumber(info.overrideSpellID)
    local overrideTooltipSpellID = tonumber(info.overrideTooltipSpellID)

    local linked
    if type(info.linkedSpellIDs) == "table" then
        linked = {}
        for j = 1, #info.linkedSpellIDs do
            local lsid = tonumber(info.linkedSpellIDs[j])
            if lsid then linked[#linked + 1] = lsid end
        end
        if #linked == 0 then linked = nil end
    end

    local isKnown = true
    if info.isKnown == false then isKnown = false end

    local entry = {
        cooldownID             = tonumber(cdID),
        category               = normCategory,
        spellID                = spellID,
        overrideSpellID        = overrideSpellID,
        overrideTooltipSpellID = overrideTooltipSpellID,
        linkedSpellIDs         = linked,
        linkedSpellID          = nil,
        auraSpellID            = nil,
        auraInstanceID         = nil,
        auraDataUnit           = nil,
        activeAuraSource       = nil,
        source                 = source,
        isKnown                = isKnown,
    }

    entry.matchSpellIDs = BuildMatchSpellIDs(entry)

    entry.stableEntryID = BuildStableEntryID(entry)
    entry.catalogKey = (entry.cooldownID ~= nil)
        and ("cdm:" .. tostring(entry.cooldownID) .. ":" .. tostring(normCategory))
        or  ("spell:" .. tostring(spellID))
    entry.matchKey = table.concat((function()
        local parts = {}
        for i = 1, #entry.matchSpellIDs do parts[#parts + 1] = tostring(entry.matchSpellIDs[i]) end
        return parts
    end)(), ",")

    RefreshDisplayFields(entry)
    entry.label = entry.displayName or cdmLabelAndIcon(GetDisplaySpellID(entry))
    entry.icon  = entry.displayIcon
    return entry
end

local function respectCDMHiddenEnabled()
    local p = Auras and Auras.profileRef
    return p and p.respectCDMHidden == true
end

cdmHiddenByDefault = function(info)
    if type(info) ~= "table" then return false end
    local flags = info.flags
    if flags == nil then return false end
    local ok, hidden = pcall(function()
        local E = Enum and Enum.CooldownSetSpellFlags
        local bit = E and E.HideByDefault
        if bit == nil then return false end
        if FlagsUtil and FlagsUtil.IsSet then
            return FlagsUtil.IsSet(flags, bit) and true or false
        end
        if type(flags) == "number" and type(bit) == "number" then
            return (flags % (bit * 2)) >= bit
        end
        return false
    end)
    return (ok and hidden) and true or false
end

function buildAuraCatalog(displayType)
    local out = {}
    local wantCategory = cdmCategoryFor(displayType)
    if wantCategory == nil then return out end
    if not cdmCatalogAvailable() then return out end

    local function unionStaticCandidates()
        local enum = Enum and Enum.CooldownViewerCategory
        local defs = {
            { cat = (enum and enum.TrackedBuff) or CATEGORY_TRACKED_BUFF, displayType = "TrackedIcon" },
            { cat = (enum and enum.TrackedBar)  or CATEGORY_TRACKED_BAR,  displayType = "TrackedBars" },
        }
        local order = {}
        local seen = {}
        for _, def in ipairs(defs) do
            local ids = liveCategorySet(def.cat)
            if type(ids) == "table" then
                for i = 1, #ids do
                    local cdID = tonumber(ids[i])
                    if cdID and not seen[cdID] then
                        seen[cdID] = true
                        order[#order + 1] = { cooldownID = cdID, staticDisplayType = def.displayType }
                    end
                end
            end
        end
        for _, def in ipairs(defs) do
            local oids = orderedConfiguredIDs(def.cat)
            if type(oids) == "table" then
                for i = 1, #oids do
                    local cdID = tonumber(oids[i])
                    if cdID and not seen[cdID] then
                        seen[cdID] = true
                        order[#order + 1] = { cooldownID = cdID, staticDisplayType = def.displayType }
                    end
                end
            end
        end
        return order
    end

    local candidates = unionStaticCandidates()
    if #candidates == 0 then return out end

    local respectHidden = respectCDMHiddenEnabled()

    for ci = 1, #candidates do
        local cand = candidates[ci]
        local cdID = cand.cooldownID
        local renderDisplayType = resolveRenderDisplayType(cdID, cand.staticDisplayType)
        if renderDisplayType == displayType then
        local _resCategory, source, normCategory = cdmCategoryFor(renderDisplayType)
        local info
        local ok2 = pcall(function()
            info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
        end)
        if ok2 and type(info) == "table"
           and not (respectHidden and cdmHiddenByDefault(info)) then
            local entry = buildCatalogEntry(cdID, info, source, normCategory)
            local okA, active = pcall(cdmActiveForInfo, {
                cooldownID             = entry.cooldownID,
                spellID                = entry.spellID,
                overrideSpellID        = entry.overrideSpellID,
                overrideTooltipSpellID = entry.overrideTooltipSpellID,
                linkedSpellIDs         = entry.linkedSpellIDs,
            })
            entry.active = okA and active or false
            do
                local seedSid  = entry.spellID
                local seedOsid = entry.overrideSpellID
                if type(seedSid)  ~= "number" or isSecret(seedSid)  or seedSid  <= 0 then seedSid  = nil end
                if type(seedOsid) ~= "number" or isSecret(seedOsid) or seedOsid <= 0 then seedOsid = nil end
                local seedPrimary = seedOsid or seedSid
                local seedCdID = tonumber(entry.cooldownID)
                if seedCdID and seedPrimary then
                    local cache = Auras._itemKeyCache
                    if not cache then
                        cache = {}
                        Auras._itemKeyCache = cache
                    end
                    local rec = cache[seedCdID]
                    if not rec then
                        rec = {}
                        cache[seedCdID] = rec
                    end
                    rec[1], rec[2] = seedPrimary, seedSid
                end
            end
            out[#out + 1] = entry
        end
        end
    end
    return out
end

local _auraCatalog = {
    TrackedIcon = {},
    TrackedBars = {},
}
local _lastCatalogCounts = { TrackedIcon = 0, TrackedBars = 0 }

local _aurasMigratedKeys = false
local function migrateAuraSettingsKeys()
    if _aurasMigratedKeys then return end
    if not (ns.GetProfile and ns.savedVarsReady) then return end
    local ok, p = pcall(ns.GetProfile, ns)
    if not ok or type(p) ~= "table" then return end
    p.auras = type(p.auras) == "table" and p.auras or {}

    do
        local linkedByBase = {}
        for k, _ in pairs(p.auras) do
            if type(k) == "string" then
                local base = k:match("^(cdm:%d+):linked:%d+$")
                if base then
                    linkedByBase[base] = linkedByBase[base] or {}
                    linkedByBase[base][#linkedByBase[base] + 1] = k
                end
            end
        end
        for base, keys in pairs(linkedByBase) do
            local function recEnabled(rec)
                if type(rec) ~= "table" then return nil end
                if rec.enabled == nil then return true end
                return rec.enabled ~= false
            end
            local anyShown = recEnabled(p.auras[base])
            local template = p.auras[base]
            for _, lk in ipairs(keys) do
                local le = recEnabled(p.auras[lk])
                if le == true then anyShown = true end
                if template == nil then template = p.auras[lk] end
            end
            local baseRec = p.auras[base]
            if type(baseRec) ~= "table" then
                baseRec = {}
                if type(template) == "table" then
                    for kk, vv in pairs(template) do baseRec[kk] = vv end
                end
                p.auras[base] = baseRec
            end
            if anyShown ~= nil then baseRec.enabled = anyShown and true or false end
            for _, lk in ipairs(keys) do
                p.auras[lk] = nil
            end
            dlog("aura settings migration: folded %d linked key(s) into %s (enabled=%s)",
                #keys, base, tostring(baseRec.enabled))
        end
    end

    local entries = {}
    for _, key in ipairs({ "TrackedIcon", "TrackedBars" }) do
        local cat = _auraCatalog[key]
        if type(cat) == "table" then
            for i = 1, #cat do entries[#entries + 1] = cat[i] end
        end
    end
    if #entries == 0 then
        return
    end

    for _, e in ipairs(entries) do
        local newKey = e.stableEntryID
        if newKey ~= nil and p.auras[newKey] == nil then
            local legacy = e.overrideSpellID or e.spellID
            local legacyRec = legacy and p.auras[legacy]
            if type(legacyRec) == "table" then
                local rec = {}
                for k, v in pairs(legacyRec) do rec[k] = v end
                p.auras[newKey] = rec
            end
        end
    end

    _aurasMigratedKeys = true
    dlog("aura settings migration complete (linked fold-back + legacy spellID -> stableEntryID)")
end

local _liveAuraByEntry  = {}
local _entryByInstance  = {}

local function instanceKey(unit, auraInstanceID)
    if unit == nil or auraInstanceID == nil then return nil end
    if isSecret(auraInstanceID) then return nil end
    return tostring(unit) .. ":" .. tostring(auraInstanceID)
end

local function forEachCatalogEntry(fn)
    for _, key in ipairs({ "TrackedIcon", "TrackedBars" }) do
        local cat = _auraCatalog[key]
        if type(cat) == "table" then
            for i = 1, #cat do
                local e = cat[i]
                if type(e) == "table" and e.stableEntryID ~= nil then
                    fn(e)
                end
            end
        end
    end
end

local function forEachEntryCopy(stableID, fn)
    forEachCatalogEntry(function(e)
        if e.stableEntryID == stableID then fn(e) end
    end)
end

local function storeLiveAura(entry, aura, unit, via)
    if type(entry) ~= "table" or type(aura) ~= "table" then return end
    local aInst = aura.auraInstanceID
    if aInst == nil then return end
    local instSecret = isSecret(aInst)
    local key = entry.stableEntryID
    if key == nil then return end
    local prev = _liveAuraByEntry[key]
    local changed
    if instSecret then
        changed = not (prev and prev._presentSecret == true and prev.auraDataUnit == unit)
    else
        changed = not (prev and prev.auraInstanceID == aInst and prev.auraDataUnit == unit)
    end
    if prev and prev.auraInstanceID ~= nil then
        local pk = instanceKey(prev.auraDataUnit, prev.auraInstanceID)
        if pk and _entryByInstance[pk] == key then _entryByInstance[pk] = nil end
    end
    forEachEntryCopy(key, function(copy)
        local needSet = changed or copy.auraDataUnit ~= unit
        if not needSet and not instSecret and copy.auraInstanceID ~= aInst then
            needSet = true
        end
        if needSet then
            SetAuraInstanceInfo(copy, aura, unit)
        end
    end)
    if instSecret then
        _liveAuraByEntry[key] = {
            auraInstanceID = nil,
            _presentSecret = true,
            auraDataUnit   = unit,
            auraSpellID    = entry.auraSpellID,
            linkedSpellID  = entry.linkedSpellID,
        }
    else
        _liveAuraByEntry[key] = {
            auraInstanceID = aInst,
            auraDataUnit   = unit,
            auraSpellID    = entry.auraSpellID,
            linkedSpellID  = entry.linkedSpellID,
        }
        local nk = instanceKey(unit, aInst)
        if nk then _entryByInstance[nk] = key end
    end
    if changed and ns.Debug and ns.Debug.IsVerbose and ns.Debug:IsVerbose(AURAS_MODULE) then
        local sid = aura.spellId
        local src = aura.sourceUnit
        dverbose("[ATTR] %s (%s) <- aura inst=%s spellId=%s source=%s unit=%s via=%s combat=%s",
            tostring(key), tostring(entry.displayName or entry.label),
            instSecret and "<secret>" or tostring(aInst),
            isSecret(sid) and "<secret>" or tostring(sid),
            isSecret(src) and "<secret>" or tostring(src),
            tostring(unit), tostring(via or "?"),
            tostring(InCombatLockdown and InCombatLockdown() or false))
    end
end

local function clearLiveAura(entry)
    if type(entry) ~= "table" then return end
    local key = entry.stableEntryID
    if key == nil then return end
    local rec = _liveAuraByEntry[key]
    if rec and rec.auraInstanceID ~= nil then
        local ik = instanceKey(rec.auraDataUnit, rec.auraInstanceID)
        if ik and _entryByInstance[ik] == key then _entryByInstance[ik] = nil end
    end
    local hadRec = rec ~= nil
    _liveAuraByEntry[key] = nil
    forEachEntryCopy(key, function(copy)
        ClearAuraInstanceInfo(copy)
    end)
    if hadRec and ns.Debug and ns.Debug.IsVerbose and ns.Debug:IsVerbose(AURAS_MODULE) then
        dverbose("[ATTR] %s cleared combat=%s", tostring(key),
            tostring(InCombatLockdown and InCombatLockdown() or false))
    end
end

local function tryResolveEntryBySpellID(entry, unit, filter)
    if not (C_UnitAuras and (C_UnitAuras.GetUnitAuraBySpellID or C_UnitAuras.GetAuraDataBySpellID)) then return nil end
    local function try(sid)
        if sid == nil or isSecret(sid) then return nil end
        local ad
        if C_UnitAuras.GetUnitAuraBySpellID then
            local ok, res = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, sid)
            if ok then ad = res end
        elseif C_UnitAuras.GetAuraDataBySpellID then
            local ok, res = pcall(C_UnitAuras.GetAuraDataBySpellID, unit, sid, filter)
            if ok then ad = res end
        end
        if type(ad) == "table" and ad.auraInstanceID ~= nil then
            return ad, sid
        end
        return nil
    end
    if unit == "player" then
        local ad, sid = try(entry.auraSpellID)
        if ad then return ad, sid end
        ad, sid = try(entry.linkedSpellID)
        if ad then return ad, sid end
        ad, sid = try(entry.overrideTooltipSpellID)
        if ad then return ad, sid end
        ad, sid = try(entry.overrideSpellID)
        if ad then return ad, sid end
        return try(entry.spellID)
    end
    local ids = entry.matchSpellIDs
    if type(ids) ~= "table" then return nil end
    for i = 1, #ids do
        local ad, sid = try(ids[i])
        if ad then return ad, sid end
    end
    return nil
end

local _rescanSeen = {}

local function rescanUnitAuras(unit, pollDriven, baseline)
    if unit == nil or not C_UnitAuras then return end
    local auras = {}
    local scanFilters = (unit == "player") and { "HELPFUL" } or { "HARMFUL|PLAYER" }
    if AuraUtil and AuraUtil.ForEachAura then
        for _, filter in ipairs(scanFilters) do
            pcall(AuraUtil.ForEachAura, unit, filter, nil, function(ad)
                if type(ad) == "table" then auras[#auras + 1] = ad end
            end, true)
        end
    elseif C_UnitAuras.GetAuraSlots and C_UnitAuras.GetAuraDataBySlot then
        for _, filter in ipairs(scanFilters) do
            local cont = nil
            while true do
                local ok, ret = pcall(function()
                    return { C_UnitAuras.GetAuraSlots(unit, filter, nil, cont) }
                end)
                if not ok or type(ret) ~= "table" or #ret == 0 then break end
                cont = ret[1]
                for si = 2, #ret do
                    local okA, ad = pcall(C_UnitAuras.GetAuraDataBySlot, unit, ret[si])
                    if okA and type(ad) == "table" then auras[#auras + 1] = ad end
                end
                if cont == nil then break end
            end
        end
    end

    local seenRec = _rescanSeen[unit]
    if not seenRec then
        seenRec = { primed = false, set = {} }
        _rescanSeen[unit] = seenRec
    end
    if baseline then seenRec.primed = false end
    local prevSeen = seenRec.set
    local primed = seenRec.primed
    local newSeen = {}

    local matchedKeys = {}

    for _, aura in ipairs(auras) do
        local sid = aura.spellId
        local aInst = aura.auraInstanceID
        local instKnown = aInst ~= nil and not isSecret(aInst)
        if instKnown then newSeen[aInst] = true end
        local excludeRawLinked = false
        if unit == "player" then
            local isNewInstance = instKnown and primed and not prevSeen[aInst]
            local src = aura.sourceUnit
            local srcOK = isSecret(src) or src == "player"
            excludeRawLinked = not (isNewInstance and srcOK)
        end
        forEachCatalogEntry(function(entry)
            if matchedKeys[entry.stableEntryID] then return end
            local okM, field = SpellIDMatchesAnyAssociatedSpellIDs(entry, sid, excludeRawLinked)
            if okM then
                storeLiveAura(entry, aura, unit, "rescan1:" .. tostring(field))
                matchedKeys[entry.stableEntryID] = true
            end
        end)
    end

    seenRec.set = newSeen
    seenRec.primed = true

    local filter = (unit == "player") and "HELPFUL" or "HARMFUL|PLAYER"
    forEachCatalogEntry(function(entry)
        if matchedKeys[entry.stableEntryID] then return end
        local ad, viaSid = tryResolveEntryBySpellID(entry, unit, filter)
        if ad then
            storeLiveAura(entry, ad, unit, "rescan2:bySpellID=" .. tostring(viaSid))
            matchedKeys[entry.stableEntryID] = true
            dlogAura(unit, "rescan-phase2", ad.auraInstanceID, isSecret(ad.spellId), "yes(bySpellID)")
        end
    end)

    local canAuthoritativelyClear = not (InCombatLockdown and InCombatLockdown())
    if canAuthoritativelyClear then
        forEachCatalogEntry(function(entry)
            local rec = _liveAuraByEntry[entry.stableEntryID]
            if rec and rec.auraDataUnit == unit and not matchedKeys[entry.stableEntryID] then
                clearLiveAura(entry)
            end
        end)
    end
end

local function handleUnitAura(unit, updateInfo)
    if unit ~= "player" and unit ~= "target" then return end
    if not C_UnitAuras then return end

    if (#( _auraCatalog.TrackedIcon or {}) == 0)
       and (#( _auraCatalog.TrackedBars or {}) == 0)
       and not (InCombatLockdown and InCombatLockdown()) then
        _auraCatalog.TrackedIcon = buildAuraCatalog("TrackedIcon")
        _auraCatalog.TrackedBars = buildAuraCatalog("TrackedBars")
    end

    if updateInfo == nil then
        rescanUnitAuras(unit, nil, true)
        return
    end

    if updateInfo.isFullUpdate then
        rescanUnitAuras(unit, nil, true)
        if type(updateInfo.addedAuras) ~= "table"
           and type(updateInfo.updatedAuraInstanceIDs) ~= "table"
           and type(updateInfo.removedAuraInstanceIDs) ~= "table" then
            return
        end
    end

    if type(updateInfo.addedAuras) == "table" then
        local sawSecretAdded = false
        for _, aura in ipairs(updateInfo.addedAuras) do
            local sid = aura.spellId
            local sidSecret = isSecret(sid)
            if sidSecret then
                sawSecretAdded = true
                dlogAura(unit, "added", aura.auraInstanceID, true, "secret-skip")
            else
                local src = aura.sourceUnit
                local srcOK = isSecret(src) or src == "player"
                local matched = false
                if srcOK then
                    forEachCatalogEntry(function(entry)
                        local okM, field = SpellIDMatchesAnyAssociatedSpellIDs(entry, sid)
                        if okM then
                            storeLiveAura(entry, aura, unit, "added:" .. tostring(field))
                            matched = true
                        end
                    end)
                end
                dlogAura(unit, "added", aura.auraInstanceID, false,
                    (not srcOK) and "no(srcNotPlayer)" or (matched and "yes" or "no"))
            end
        end
        if sawSecretAdded and not (InCombatLockdown and InCombatLockdown()) then
            rescanUnitAuras(unit)
        end
    end

    if type(updateInfo.updatedAuraInstanceIDs) == "table"
       and C_UnitAuras.GetAuraDataByAuraInstanceID then
        for _, aInst in ipairs(updateInfo.updatedAuraInstanceIDs) do
            if not isSecret(aInst) and aInst ~= nil then
                local key = _entryByInstance[instanceKey(unit, aInst) or ""]
                if key then
                    local okA, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, aInst)
                    if okA and type(ad) == "table" then
                        forEachCatalogEntry(function(entry)
                            if entry.stableEntryID == key then
                                storeLiveAura(entry, ad, unit, "updated")
                            end
                        end)
                    end
                end
            end
        end
    end

    if type(updateInfo.removedAuraInstanceIDs) == "table" then
        for _, aInst in ipairs(updateInfo.removedAuraInstanceIDs) do
            if not isSecret(aInst) and aInst ~= nil then
                local key = _entryByInstance[instanceKey(unit, aInst) or ""]
                if key then
                    forEachCatalogEntry(function(entry)
                        if entry.stableEntryID == key then clearLiveAura(entry) end
                    end)
                end
            end
        end
    end
end

local function handleTargetChanged()
    forEachCatalogEntry(function(entry)
        local rec = _liveAuraByEntry[entry.stableEntryID]
        if rec and rec.auraDataUnit == "target" then
            clearLiveAura(entry)
        end
    end)
    _rescanSeen.target = nil
    if UnitExists and UnitExists("target") then
        rescanUnitAuras("target")
    end
end

local function resetLiveAuraState()
    for key in pairs(_liveAuraByEntry) do _liveAuraByEntry[key] = nil end
    for key in pairs(_entryByInstance) do _entryByInstance[key] = nil end
    for key in pairs(_rescanSeen) do _rescanSeen[key] = nil end
    forEachCatalogEntry(function(entry) ClearAuraInstanceInfo(entry) end)
end

Auras._liveAura = {
    handleUnitAura      = handleUnitAura,
    handleTargetChanged = handleTargetChanged,
    rescanUnitAuras     = rescanUnitAuras,
    resetLiveAuraState  = resetLiveAuraState,
    byEntry             = _liveAuraByEntry,
}

resolveLiveAuraForEntry = function(e)
    if type(e) ~= "table" then return nil end
    local key = e.stableEntryID
    if key == nil then return nil end

    local rec = _liveAuraByEntry[key]
    if type(rec) ~= "table" then return nil end

    local unit = rec.auraDataUnit
    if type(unit) ~= "string" then return nil end

    if rec._presentSecret == true then
        local ad = {
            auraInstanceID = nil,
            spellId        = rec.auraSpellID,
            _presentSecret = true,
        }
        return ad, unit, rec.auraSpellID
    end

    local aInst = rec.auraInstanceID
    if aInst == nil or isSecret(aInst) then return nil end

    local ad = {
        auraInstanceID = aInst,
        spellId        = rec.auraSpellID,
    }
    return ad, unit, rec.auraSpellID
end

local function makeSyntheticItem(e, ad, unit)
    local rt = {
        cooldownID             = e.cooldownID,
        category               = e.category,
        spellID                = e.spellID,
        overrideSpellID        = e.overrideSpellID,
        overrideTooltipSpellID = e.overrideTooltipSpellID,
        linkedSpellIDs         = e.linkedSpellIDs,
        linkedSpellID          = e.linkedSpellID,
        matchSpellIDs          = e.matchSpellIDs,
        stableEntryID          = e.stableEntryID,
        icon                   = e.icon,
        label                  = e.label,
    }
    SetAuraInstanceInfo(rt, ad, unit)

    local safeSpellID = rt.linkedSpellID or rt.overrideTooltipSpellID
        or rt.overrideSpellID or rt.spellID

    local catalogIcon = Auras._catalogDisplayTexture(e)
    local catalogName = Auras._catalogDisplayName(e)
    local displayIcon = Auras._resolveLiveVariantIcon(unit, ad and ad.auraInstanceID)
    if not ns._auraPresentTruthy(displayIcon)
       and not isSecret(rt.displayIcon) and ns._auraPresentTruthy(rt.displayIcon) then
        displayIcon = rt.displayIcon
    end
    if not ns._auraPresentTruthy(displayIcon) then
        displayIcon = catalogIcon
    end
    if not ns._auraPresentTruthy(displayIcon) then
        displayIcon = Auras.PLACEHOLDER_ICON
    end
    local displayName = catalogName
    if (type(displayName) ~= "string" or displayName == "") then
        if type(rt.displayName) == "string" and rt.displayName ~= "" then
            displayName = rt.displayName
        elseif type(rt.label) == "string" and rt.label ~= "" then
            displayName = rt.label
        end
    end

    local item = {
        _synthetic     = true,
        _entry         = rt,
        _presentSecret = (type(ad) == "table" and ad._presentSecret == true) or nil,
        cooldownID     = rt.cooldownID,
        _spellID       = safeSpellID,
        _iconTexture   = displayIcon,
        _barName       = displayName,
        auraInstanceID = ad.auraInstanceID,
        auraDataUnit   = unit,
        auraSpellID    = rt.auraSpellID,
        stableEntryID  = rt.stableEntryID,
        activeAuraSource = rt.activeAuraSource,
        cooldownInfo   = {
            spellID                = rt.spellID,
            overrideSpellID        = rt.overrideSpellID,
            overrideTooltipSpellID = rt.overrideTooltipSpellID,
            linkedSpellIDs         = rt.linkedSpellIDs,
        },
    }
    if ad.auraInstanceID ~= nil and C_UnitAuras
       and C_UnitAuras.GetAuraApplicationDisplayCount then
        local ok, txt = pcall(C_UnitAuras.GetAuraApplicationDisplayCount,
            unit, ad.auraInstanceID)
        if ok and type(txt) == "string" then item._stackText = txt end
    end
    return item
end

local function readViewerChildIconTexture(child)
    if type(child) ~= "table" then return nil end
    local iconField = child.Icon
    if type(iconField) == "table" then
        if type(iconField.GetTexture) == "function" then
            local ok, tex = pcall(iconField.GetTexture, iconField)
            if ok and ns._auraPresentTruthy(tex) then return tex end
        end
        local nested = iconField.Icon
        if type(nested) == "table" and type(nested.GetTexture) == "function" then
            local ok, tex = pcall(nested.GetTexture, nested)
            if ok and ns._auraPresentTruthy(tex) then return tex end
        end
    end
    return nil
end

function Auras._resolveLiveVariantIcon(unit, auraInstanceID)
    if unit == nil or auraInstanceID == nil or isSecret(auraInstanceID) then return nil end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID) then return nil end
    local ok, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, auraInstanceID)
    if ok and type(ad) == "table" and ns._auraPresentTruthy(ad.icon) then return ad.icon end
    return nil
end

local function makeSyntheticItemFromViewerChild(entry, child)
    if type(entry) ~= "table" or type(child) ~= "table" then return nil end

    local aInst = child.auraInstanceID
    if aInst == nil and type(child.Icon) == "table" then
        aInst = child.Icon.auraInstanceID
    end
    local instSecret = isSecret(aInst)
    if instSecret then aInst = nil end
    local unit = child.auraDataUnit
    if type(unit) ~= "string" then unit = "player" end

    local safeSpellID = entry.overrideTooltipSpellID or entry.overrideSpellID or entry.spellID

    local iconTex = Auras._resolveLiveVariantIcon(unit, aInst)
    if not ns._auraPresentTruthy(iconTex) then
        iconTex = readViewerChildIconTexture(child)
    end
    if not ns._auraPresentTruthy(iconTex) then
        iconTex = Auras._catalogDisplayTexture(entry)
    end
    if not ns._auraPresentTruthy(iconTex) then
        iconTex = Auras.PLACEHOLDER_ICON
    end
    local barName = Auras._catalogDisplayName(entry)
    if type(barName) ~= "string" or barName == "" then
        barName = entry.displayName or entry.label
    end

    local item = {
        _synthetic     = true,
        _fromViewer    = true,
        _entry         = entry,
        cooldownID     = entry.cooldownID,
        _spellID       = safeSpellID,
        _iconTexture   = iconTex,
        _barName       = barName,
        auraInstanceID = aInst,
        _presentSecret = instSecret or (aInst == nil),
        auraDataUnit   = unit,
        stableEntryID  = entry.stableEntryID,
        cooldownInfo   = (type(entry.cooldownInfo) == "table" and entry.cooldownInfo) or {
            spellID                = entry.spellID,
            overrideSpellID        = entry.overrideSpellID,
            overrideTooltipSpellID = entry.overrideTooltipSpellID,
            linkedSpellIDs         = entry.linkedSpellIDs,
        },
    }

    if not isSecret(aInst) and aInst ~= nil and C_UnitAuras
       and C_UnitAuras.GetAuraApplicationDisplayCount then
        local ok, txt = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, aInst)
        if ok and type(txt) == "string" then item._stackText = txt end
    end

    return item
end

function Auras._makeSummonBarItem(entry, durObj)
    if type(entry) ~= "table" then return nil end
    local safeSpellID = entry.overrideTooltipSpellID or entry.overrideSpellID or entry.spellID
    local iconTex = Auras._catalogDisplayTexture(entry)
    if not ns._auraPresentTruthy(iconTex) then iconTex = Auras.PLACEHOLDER_ICON end
    local barName = Auras._catalogDisplayName(entry)
    if type(barName) ~= "string" or barName == "" then
        barName = entry.displayName or entry.label
    end
    return {
        _synthetic    = true,
        _summon       = true,
        _summonDurObj = durObj,
        _entry        = entry,
        cooldownID    = entry.cooldownID,
        _spellID      = safeSpellID,
        _iconTexture  = iconTex,
        _barName      = barName,
        stableEntryID = entry.stableEntryID,
        cooldownInfo  = (type(entry.cooldownInfo) == "table" and entry.cooldownInfo) or {
            spellID                = entry.spellID,
            overrideSpellID        = entry.overrideSpellID,
            overrideTooltipSpellID = entry.overrideTooltipSpellID,
            linkedSpellIDs         = entry.linkedSpellIDs,
        },
    }
end

function Auras._auraProbeShowsCooldown(durObj)
    if durObj == nil then return false end
    local sc = Auras._auraProbeScratchCooldown
    if not sc then
        local parent = CreateFrame("Frame", "TenUIAurasProbeScratchParent")
        parent:Hide()
        sc = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
        Auras._auraProbeScratchCooldown = sc
    end
    if type(sc.SetCooldownFromDurationObject) ~= "function" then return false end
    local ok = pcall(sc.SetCooldownFromDurationObject, sc, durObj)
    if not ok then return false end
    local shown = sc:IsShown()
    pcall(sc.Clear, sc)
    return shown and true or false
end

function Auras._entryKnownAuraSpellIDs(e, out)
    out = out or {}
    if type(e) ~= "table" then return out end
    local function add(v)
        if _IsUsableSID(v) then
            for i = 1, #out do if out[i] == v then return end end
            out[#out + 1] = v
        end
    end
    add(e.auraSpellID)
    add(e.linkedSpellID)
    add(e.overrideTooltipSpellID)
    add(e.overrideSpellID)
    add(e.spellID)
    if type(e.linkedSpellIDs) == "table" then
        for i = 1, #e.linkedSpellIDs do add(e.linkedSpellIDs[i]) end
    end
    if type(e.matchSpellIDs) == "table" then
        for i = 1, #e.matchSpellIDs do add(e.matchSpellIDs[i]) end
    end
    return out
end

function Auras._resolveTrackedAuraPresence(e)
    if type(e) ~= "table" then return false end
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return false end
    local ids = Auras._entryKnownAuraSpellIDs(e)
    if #ids == 0 then return false end
    local function resolveFrom(ad, unit, sid)
        local instId = ad.auraInstanceID
        local safeInst = (instId ~= nil and not isSecret(instId)) and instId or nil
        local durObj
        if safeInst ~= nil and C_UnitAuras.GetAuraDuration then
            local okD, dur = pcall(C_UnitAuras.GetAuraDuration, unit, safeInst)
            if okD and dur ~= nil and Auras._auraProbeShowsCooldown(dur) then
                durObj = dur
            end
        end
        local liveIcon
        if ns._auraPresentTruthy(ad.icon) then liveIcon = ad.icon end
        return true, safeInst, unit, durObj, sid, liveIcon
    end
    for i = 1, #ids do
        local ok, ad = pcall(C_UnitAuras.GetPlayerAuraBySpellID, ids[i])
        if ok and type(ad) == "table" then
            return resolveFrom(ad, "player", ids[i])
        end
    end
    if type(e.matchSpellIDs) == "table" and C_UnitAuras.GetUnitAuraBySpellID
       and UnitExists and UnitExists("target") then
        for i = 1, #ids do
            local ok, ad = pcall(C_UnitAuras.GetUnitAuraBySpellID, "target", ids[i])
            if ok and type(ad) == "table" then
                return resolveFrom(ad, "target", ids[i])
            end
        end
    end
    return false
end

function Auras._makeTrackedAuraProbeItem(e, instId, unit, matchedSpellID, liveIcon)
    if type(e) ~= "table" then return nil end
    local safeSpellID = e.overrideTooltipSpellID or e.overrideSpellID or e.spellID
        or matchedSpellID
    if type(unit) ~= "string" then unit = "player" end
    local iconTex = Auras._resolveLiveVariantIcon(unit, instId)
    if not ns._auraPresentTruthy(iconTex) and ns._auraPresentTruthy(liveIcon) then
        iconTex = liveIcon
    end
    if not ns._auraPresentTruthy(iconTex) then
        iconTex = Auras._catalogDisplayTexture(e)
    end
    if not ns._auraPresentTruthy(iconTex) then iconTex = Auras.PLACEHOLDER_ICON end
    local barName = Auras._catalogDisplayName(e)
    if type(barName) ~= "string" or barName == "" then
        barName = e.displayName or e.label
    end
    local item = {
        _synthetic       = true,
        _entry           = e,
        _presentSecret   = (instId == nil) or nil,
        cooldownID       = e.cooldownID,
        _spellID         = safeSpellID,
        _iconTexture     = iconTex,
        _barName         = barName,
        auraInstanceID   = instId,
        auraDataUnit     = unit,
        stableEntryID    = e.stableEntryID,
        activeAuraSource = "spellIDprobe",
        cooldownInfo     = (type(e.cooldownInfo) == "table" and e.cooldownInfo) or {
            spellID                = e.spellID,
            overrideSpellID        = e.overrideSpellID,
            overrideTooltipSpellID = e.overrideTooltipSpellID,
            linkedSpellIDs         = e.linkedSpellIDs,
        },
    }
    if instId ~= nil and not isSecret(instId) and C_UnitAuras
       and C_UnitAuras.GetAuraApplicationDisplayCount then
        local ok, txt = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, instId)
        if ok and type(txt) == "string" then item._stackText = txt end
    end
    return item
end

function Auras._makeSyntheticItemFromViewerChildDirect(child, displayType)
    if type(child) ~= "table" then return nil end

    local cooldownID = readChildCooldownID(child)

    local auraInstID = nil
    do
        local ok, v = pcall(function() return child.auraInstanceID end)
        if ok then auraInstID = v end
        if auraInstID == nil and type(child.Icon) == "table" then
            local ok2, v2 = pcall(function() return child.Icon.auraInstanceID end)
            if ok2 then auraInstID = v2 end
        end
    end

    local unit = "player"
    do
        local ok, v = pcall(function() return child.auraDataUnit end)
        if ok and type(v) == "string" and not isSecret(v) then unit = v end
    end

    local cooldownInfo = nil
    do
        local ok, v = pcall(function() return child.cooldownInfo end)
        if ok and type(v) == "table" then cooldownInfo = v end
    end

    local spellID = nil
    if type(cooldownInfo) == "table" then
        for _, field in ipairs({"overrideTooltipSpellID", "overrideSpellID", "spellID"}) do
            local ok, v = pcall(function() return cooldownInfo[field] end)
            if ok and type(v) == "number" and v > 0 and not isSecret(v) then
                spellID = v
                break
            end
        end
    end
    if not spellID then
        local ok, v = pcall(function() return child.spellID end)
        if ok and type(v) == "number" and v > 0 and not isSecret(v) then spellID = v end
    end

    local iconTexture = readViewerChildIconTexture(child)
    if not ns._auraPresentTruthy(iconTexture) and spellID and C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and tex ~= nil and not isSecret(tex) then iconTexture = tex end
    end
    if not ns._auraPresentTruthy(iconTexture) and cooldownID then
        local _, _, normCat = cdmCategoryFor(displayType)
        local catKey = normCat or displayType
        local cat = _auraCatalog[catKey]
        if type(cat) == "table" then
            for ci = 1, #cat do
                local ce = cat[ci]
                if type(ce) == "table" and ce.cooldownID == cooldownID then
                    local ct = Auras._catalogDisplayTexture(ce)
                    if ns._auraPresentTruthy(ct) then iconTexture = ct end
                    break
                end
            end
        end
    end
    if not ns._auraPresentTruthy(iconTexture) then
        iconTexture = Auras.PLACEHOLDER_ICON
    end

    local barName = "Aura"
    do
        local ok1, nameFrame = pcall(function() return child.Name end)
        if ok1 and type(nameFrame) == "table" and type(nameFrame.GetText) == "function" then
            local ok2, txt = pcall(nameFrame.GetText, nameFrame)
            if ok2 and type(txt) == "string" and txt ~= "" then barName = txt end
        end
        if barName == "Aura" and spellID and C_Spell and C_Spell.GetSpellName then
            local ok, name = pcall(C_Spell.GetSpellName, spellID)
            if ok and type(name) == "string" and name ~= "" then barName = name end
        end
        if barName == "Aura" and cooldownID then
            local _, _, normCat = cdmCategoryFor(displayType)
            local catKey = normCat or displayType
            local cat = _auraCatalog[catKey]
            if type(cat) == "table" then
                for ci = 1, #cat do
                    local ce = cat[ci]
                    if type(ce) == "table" and ce.cooldownID == cooldownID then
                        local n = ce.displayName or ce.label
                        if type(n) == "string" and n ~= "" then barName = n end
                        break
                    end
                end
            end
        end
    end

    local stackText = nil
    if auraInstID ~= nil and not isSecret(auraInstID)
       and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
        local ok, txt = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, auraInstID)
        if ok and type(txt) == "string" then stackText = txt end
    end

    local stableEntryID = cooldownID and ("cdm:" .. tostring(cooldownID)) or nil
    if cooldownID then
        local _, _, normCat = cdmCategoryFor(displayType)
        local catKey = normCat or displayType
        local cat = _auraCatalog[catKey]
        if type(cat) == "table" then
            for ci = 1, #cat do
                local ce = cat[ci]
                if type(ce) == "table" and ce.cooldownID == cooldownID
                   and type(ce.stableEntryID) == "string" then
                    stableEntryID = ce.stableEntryID
                    break
                end
            end
        end
    end

    return {
        _synthetic           = true,
        _fromViewer          = true,
        _fromViewerDirect    = true,
        stableEntryID        = stableEntryID,
        cooldownID           = cooldownID,
        auraInstanceID       = auraInstID,
        auraDataUnit         = unit,
        cooldownInfo         = cooldownInfo or {
            spellID                = spellID,
            overrideSpellID        = nil,
            overrideTooltipSpellID = nil,
            linkedSpellIDs         = nil,
        },
        _spellID             = spellID,
        _iconTexture         = iconTexture,
        _barName             = barName,
        _stackText           = stackText,
        activeAuraSource     = "viewerChild",
        displayType          = displayType,
        _viewerChild         = child,
    }
end

function Auras._buildActiveFromViewerChildren(displayType, preview)
    local viewerName = (displayType == "TrackedIcon")
        and ICON_VIEWER_NAME
        or  BAR_VIEWER_NAME

    local viewer = getViewer(viewerName)
    if not viewer then
        return {}
    end

    local children = getItemFrames(viewer) or {}
    local result = {}

    for _, child in ipairs(children) do
        local cooldownID = readChildCooldownID(child)
        if cooldownID then
            local auraInstID = nil
            do
                local ok, v = pcall(function() return child.auraInstanceID end)
                if ok then auraInstID = v end
                if auraInstID == nil and type(child.Icon) == "table" then
                    local ok2, v2 = pcall(function() return child.Icon.auraInstanceID end)
                    if ok2 then auraInstID = v2 end
                end
            end

            local skip = false
            if auraInstID == nil then
                dverbose("SKIP child: cooldownID=%s reason=no_auraInstanceID", tostring(cooldownID))
                skip = true
            end

            if not skip and ns.GetProfile and ns.savedVarsReady then
                local ok, p = pcall(ns.GetProfile, ns)
                if ok and type(p) == "table" and type(p.auras) == "table" then
                    local stableID = "cdm:" .. tostring(cooldownID)
                    local pe = p.auras[stableID]
                    if type(pe) == "table" and pe.enabled == false then
                        dverbose("SKIP child: cooldownID=%s reason=explicit_disabled", tostring(cooldownID))
                        skip = true
                    end
                    if not skip and pe == nil then
                        local _, _, normCat = cdmCategoryFor(displayType)
                        local catKey = normCat or displayType
                        local cat = _auraCatalog[catKey]
                        if type(cat) == "table" then
                            for ci = 1, #cat do
                                local ce = cat[ci]
                                if type(ce) == "table" and ce.cooldownID == cooldownID then
                                    local catPE = ce.stableEntryID and p.auras[ce.stableEntryID]
                                    if type(catPE) == "table" and catPE.enabled == false then
                                        dverbose("SKIP child: cooldownID=%s reason=catalog_disabled stableEntryID=%s",
                                            tostring(cooldownID), tostring(ce.stableEntryID))
                                        skip = true
                                    end
                                    break
                                end
                            end
                        end
                    end
                end
            end

            if not skip then
                local ok, item = pcall(Auras._makeSyntheticItemFromViewerChildDirect, child, displayType)
                if ok and item then
                    result[#result + 1] = item
                else
                    dlogItemErrorOnce(child, "makeSyntheticItemFromViewerChildDirect", item)
                end
            end
        end
    end

    return result
end

local _emitSrcLog = {}

local function logEmitTransition(displayType, e, emitSrc)
    if not (ns.Debug and ns.Debug.IsVerbose and ns.Debug:IsVerbose(AURAS_MODULE)) then return end
    local lk = tostring(displayType) .. ":" .. tostring(e.stableEntryID or e.cooldownID or e.spellID)
    if _emitSrcLog[lk] == emitSrc then return end
    _emitSrcLog[lk] = emitSrc
    dverbose("[EMIT %s] %s (%s) -> %s combat=%s",
        tostring(displayType),
        tostring(e.stableEntryID or "?"), tostring(e.displayName or e.label),
        tostring(emitSrc),
        tostring(InCombatLockdown and InCombatLockdown() or false))
end

buildActiveFromCatalog = function(displayType, preview)
    local _, _, normCategory = cdmCategoryFor(displayType)
    local key = normCategory or displayType
    local cat = _auraCatalog[key]
    if (type(cat) ~= "table" or #cat == 0)
       and not (InCombatLockdown and InCombatLockdown()) then
        cat = buildAuraCatalog(key)
        _auraCatalog[key] = cat
        _lastCatalogCounts[key] = #cat
    end
    if type(cat) ~= "table" then cat = {} end
    local out = {}

    if preview then
        for i = 1, #cat do
            local e = cat[i]
            if type(e) == "table" and entryDisplayEnabled(e) then
                local ad, unit = resolveLiveAuraForEntry(e)
                if ad then
                    local ok, item = pcall(makeSyntheticItem, e, ad, unit)
                    if ok and item then
                        out[#out + 1] = item
                        return out
                    end
                end
            end
        end
        local pdur = _lowTimeStats.pvDuration(1)
        local example = {
            _preview     = true,
            _previewSlot = 1,
            _previewDur  = pdur,
            _barName     = "Preview",
            _spellID     = nil,
            _iconTexture = [[Interface\Icons\INV_Misc_QuestionMark]],
        }
        out[#out + 1] = example
        return out
    end

    local forcePop = Auras.IsForceViewerPopulated and Auras:IsForceViewerPopulated()
    local _previewPlaceholderIndex = 0
    local showInactiveBars = false
    if displayType == "TrackedBars" and not preview then
        local pIB = Auras.profileRef
        local oIB = pIB and pIB.bars
        showInactiveBars = type(oIB) == "table" and oIB.showInactive == true
    end
    for i = 1, #cat do
        local e = cat[i]
        if type(e) == "table" then
            local enabled = entryDisplayEnabled(e)
            if enabled then
                local viewerStateEmitted = false
                if not preview and Auras._useViewerStateAsPrimary then
                    local okV, vActive, vInfo = pcall(Auras.ResolveAuraStateFromViewer, Auras, e)
                    if okV and vActive == true and type(vInfo) == "table"
                       and type(vInfo.child) == "table" then
                        local okI, item = pcall(makeSyntheticItemFromViewerChild, e, vInfo.child)
                        if okI and type(item) == "table" then
                            item.activeAuraSource = "viewerState"
                            item._fromViewer = nil
                            item._fromViewerDirect = nil
                            if vInfo.applications ~= nil then item._stackText = vInfo.applications end
                            out[#out + 1] = item
                            viewerStateEmitted = true
                            logEmitTransition(displayType, e,
                                "viewerState cdID=" .. tostring(vInfo.cooldownID)
                                .. " inst=" .. (vInfo.auraInstanceID == nil
                                    and "<secret/nil>" or tostring(vInfo.auraInstanceID)))
                        else
                            dlogItemErrorOnce(e, "makeViewerStateItem", item)
                        end
                    end
                end

                local ad, unit
                if not viewerStateEmitted then
                    ad, unit = resolveLiveAuraForEntry(e)
                end
                if not viewerStateEmitted and ad then
                    local ok, item = pcall(makeSyntheticItem, e, ad, unit)
                    if ok and item then
                        out[#out + 1] = item
                        logEmitTransition(displayType, e,
                            "liveAura unit=" .. tostring(unit)
                            .. " inst=" .. tostring(ad.auraInstanceID))
                    else
                        dlogItemErrorOnce(e, "makeSyntheticItem", item)
                    end
                elseif not viewerStateEmitted then
                    local emitted = false

                    if not preview and forcePop and Auras._useViewerChildEmit then
                        local child = findLiveViewerChildByCooldownID(e.cooldownID, displayType)
                        if child then
                            local ok, item = pcall(makeSyntheticItemFromViewerChild, e, child)
                            if ok and item then
                                out[#out + 1] = item
                                emitted = true
                                logEmitTransition(displayType, e,
                                    "viewerChild cdID=" .. tostring(e.cooldownID))
                            else
                                dlogItemErrorOnce(e, "makeSyntheticItemFromViewerChild", item)
                            end
                        end
                    end

                    if not emitted and not preview and displayType == "TrackedBars" then
                        local okC, child = pcall(findLiveViewerChildByCooldownID, e.cooldownID, "TrackedBars")
                        if okC and type(child) == "table" then
                            local okI, item = pcall(makeSyntheticItemFromViewerChild, e, child)
                            if okI and type(item) == "table" then
                                out[#out + 1] = item
                                emitted = true
                                logEmitTransition(displayType, e,
                                    "barViewerChild cdID=" .. tostring(e.cooldownID))
                            else
                                dlogItemErrorOnce(e, "barViewerChild", item)
                            end
                        end
                    end

                    if not emitted and not preview then
                        local okR, present, instId, unit, durObj, matchedSID, liveIcon =
                            pcall(Auras._resolveTrackedAuraPresence, e)
                        if okR and present then
                            local okI, item = pcall(Auras._makeTrackedAuraProbeItem, e, instId, unit, matchedSID, liveIcon)
                            if okI and item then
                                if durObj ~= nil then item._probeDurObj = durObj end
                                out[#out + 1] = item
                                emitted = true
                                logEmitTransition(displayType, e,
                                    "spellIDprobe sid=" .. tostring(matchedSID)
                                    .. " inst=" .. (instId == nil and "<secret/nil>" or tostring(instId)))
                            else
                                dlogItemErrorOnce(e, "makeTrackedAuraProbeItem", item)
                            end
                        end
                    end

                    if not emitted and not preview
                       and displayType == "TrackedBars"
                       and Auras._summonSpecGateOK
                       and Auras._summonSpellForEntry(e) then
                        local okP, active, durObj, srcTag = pcall(Auras._resolveSummonBarPresence, e, forcePop)
                        if okP and active then
                            local okI, item = pcall(Auras._makeSummonBarItem, e, durObj)
                            if okI and item then
                                out[#out + 1] = item
                                emitted = true
                                logEmitTransition(displayType, e, srcTag or "summonBar")
                            else
                                dlogItemErrorOnce(e, "makeSummonBarItem", item)
                            end
                        end
                    end

                    if not emitted then
                        logEmitTransition(displayType, e, "none")
                    end

                    if preview and not emitted then
                        local ad2, unit2 = resolveLiveAuraForEntry(e)
                        if ad2 then
                            local ok, item = pcall(makeSyntheticItem, e, ad2, unit2)
                            if ok and item then
                                out[#out + 1] = item
                            else
                                dlogItemErrorOnce(e, "makeSyntheticItem(preview)", item)
                            end
                        else
                            local ph = {
                                _synthetic    = true,
                                cooldownID    = e.cooldownID,
                                _spellID      = e.displaySpellID or e.spellID,
                                _iconTexture  = e.displayIcon or e.icon,
                                _barName      = e.displayName or e.label,
                                stableEntryID = e.stableEntryID,
                                cooldownInfo  = {
                                    spellID                = e.spellID,
                                    overrideSpellID        = e.overrideSpellID,
                                    overrideTooltipSpellID = e.overrideTooltipSpellID,
                                    linkedSpellIDs         = e.linkedSpellIDs,
                                },
                            }
                            if displayType == "TrackedBars" then
                                _previewPlaceholderIndex = _previewPlaceholderIndex + 1
                                local pdur = _lowTimeStats.pvDuration(_previewPlaceholderIndex)
                                if pdur ~= nil then
                                    ph._preview     = true
                                    ph._previewSlot = _previewPlaceholderIndex
                                    ph._previewDur  = pdur
                                end
                            end
                            out[#out + 1] = ph
                        end
                    end

                    if showInactiveBars and not emitted then
                        local idleIcon = Auras._catalogDisplayTexture(e)
                        if not ns._auraPresentTruthy(idleIcon) then idleIcon = Auras.PLACEHOLDER_ICON end
                        out[#out + 1] = {
                            _synthetic    = true,
                            _idle         = true,
                            cooldownID    = e.cooldownID,
                            _spellID      = e.displaySpellID or e.spellID,
                            _iconTexture  = idleIcon,
                            _barName      = Auras._catalogDisplayName(e) or e.displayName or e.label,
                            stableEntryID = e.stableEntryID,
                        }
                    end
                end
            end
        end
    end

    return out
end

function Auras:ScanBlizzardCDMAuras()
    if InCombatLockdown and InCombatLockdown() then
        dlog("ScanBlizzardCDMAuras: skipped (combat) cachedIcon=%d cachedBars=%d",
            _lastCatalogCounts.TrackedIcon or 0, _lastCatalogCounts.TrackedBars or 0)
        return _lastCatalogCounts.TrackedIcon, _lastCatalogCounts.TrackedBars
    end
    pcall(self._invalidateLiveRenderCategoryMap, self)
    pcall(liveRenderCategoryMap)
    _auraCatalog.TrackedIcon = buildAuraCatalog("TrackedIcon")
    _auraCatalog.TrackedBars = buildAuraCatalog("TrackedBars")
    _lastCatalogCounts.TrackedIcon = #_auraCatalog.TrackedIcon
    _lastCatalogCounts.TrackedBars = #_auraCatalog.TrackedBars
    pcall(migrateAuraSettingsKeys)
    local _, mapSrc = liveRenderCategoryMap()
    dlog("ScanBlizzardCDMAuras: TrackedIcon=%d TrackedBars=%d (liveCat src=%s)",
        _lastCatalogCounts.TrackedIcon, _lastCatalogCounts.TrackedBars,
        tostring(mapSrc))
    ns:Fire("AURA_LIST_UPDATED")
    return _lastCatalogCounts.TrackedIcon, _lastCatalogCounts.TrackedBars
end

function Auras:RefreshTrackedAuraCatalog()
    self:InvalidateViewerAuraMap()
    return self:ScanBlizzardCDMAuras()
end

function Auras:RefreshCatalogActiveStates()
    pcall(viewerActiveCooldownIDSet, true)
    local changed = false
    for _, key in ipairs({ "TrackedIcon", "TrackedBars" }) do
        local cat = _auraCatalog[key]
        if type(cat) == "table" then
            for i = 1, #cat do
                local e = cat[i]
                if type(e) == "table" then
                    local okN, now = pcall(cdmActiveForInfo, {
                        cooldownID             = e.cooldownID,
                        spellID                = e.spellID,
                        overrideSpellID        = e.overrideSpellID,
                        overrideTooltipSpellID = e.overrideTooltipSpellID,
                        linkedSpellIDs         = e.linkedSpellIDs,
                    })
                    if not okN then now = e.active end
                    if e.active ~= now then
                        e.active = now
                        changed = true
                    end
                end
            end
        end
    end
    if changed then ns:Fire("AURA_LIST_UPDATED") end
    return changed
end

local _playerAuraCache    = {}
local _auraCacheFrame     = nil
local _auraCacheDirty     = false

function rebuildPlayerAuraCache()
    wipe(_playerAuraCache)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    local idx = 1
    while true do
        local ok, ad = pcall(C_UnitAuras.GetAuraDataByIndex, "player", idx, "HELPFUL")
        if not ok or not ad then break end
        local spID = ad.spellId
        local name = ad.name
        local icon = ad.icon
        if isSecret(spID) or isSecret(name) then
            idx = idx + 1
        else
            local label
            if type(name) == "string" and name ~= "" then
                label = name
            end
            if not label and spID and C_Spell and C_Spell.GetSpellName then
                local okN, n = pcall(C_Spell.GetSpellName, spID)
                if okN and type(n) == "string" and n ~= "" then label = n end
            end
            _playerAuraCache[#_playerAuraCache + 1] = {
                spellID        = spID,
                name           = label or ("aura:" .. tostring(idx)),
                icon           = icon,
                count          = ad.count,
                auraInstanceID = ad.auraInstanceID,
                sourceUnit     = ad.sourceUnit,
            }
            idx = idx + 1
        end
    end
    _auraCacheDirty = false
    dtrace("rebuildPlayerAuraCache: %d entries", #_playerAuraCache)
    ns:Fire("AURA_LIST_UPDATED")
end

function ensureAuraCacheFrame()
    if _auraCacheFrame then return end
    _auraCacheFrame = CreateFrame("Frame", "TenUIPlayerAuraCacheFrame")
    Auras._auraCacheFrame = _auraCacheFrame
    _auraCacheFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            if arg1 == "player" then
                pcall(Auras._handleSummonCast, arg3)
            end
            return
        elseif event == "UNIT_AURA" then
            local unit, updateInfo = arg1, arg2
            if Auras._liveAura and Auras._liveAura.handleUnitAura then
                pcall(Auras._liveAura.handleUnitAura, unit, updateInfo)
            end
            if Auras.RequestRefresh then pcall(Auras.RequestRefresh, Auras) end
            if unit == "player" then
                rebuildPlayerAuraCache()
            end
            if Auras.RefreshCatalogActiveStates then
                pcall(Auras.RefreshCatalogActiveStates, Auras)
            end
        elseif event == "PLAYER_TARGET_CHANGED" then
            if Auras._liveAura and Auras._liveAura.handleTargetChanged then
                pcall(Auras._liveAura.handleTargetChanged)
            end
            if Auras.RequestRefresh then pcall(Auras.RequestRefresh, Auras) end
        elseif event == "ENCOUNTER_START"
            or event == "CHALLENGE_MODE_START"
            or event == "PLAYER_ENTERING_BATTLEGROUND" then
            if Auras._liveAura and Auras._liveAura.resetLiveAuraState then
                pcall(Auras._liveAura.resetLiveAuraState)
            end
            if Auras._liveAura and Auras._liveAura.rescanUnitAuras then
                pcall(Auras._liveAura.rescanUnitAuras, "player")
                if UnitExists and UnitExists("target") then
                    pcall(Auras._liveAura.rescanUnitAuras, "target")
                end
            end
            if Auras.RequestRefresh then pcall(Auras.RequestRefresh, Auras) end
        elseif event == "PLAYER_SPECIALIZATION_CHANGED"
            or event == "COOLDOWN_VIEWER_DATA_LOADED"
            or event == "TRAIT_CONFIG_UPDATED" then
            pcall(Auras._refreshSummonSpecGate)
            if Auras.RefreshTrackedAuraCatalog then
                pcall(Auras.RefreshTrackedAuraCatalog, Auras)
            end
            if Auras._liveAura and Auras._liveAura.resetLiveAuraState then
                pcall(Auras._liveAura.resetLiveAuraState)
            end
            if Auras._liveAura and Auras._liveAura.rescanUnitAuras then
                pcall(Auras._liveAura.rescanUnitAuras, "player")
                if UnitExists and UnitExists("target") then
                    pcall(Auras._liveAura.rescanUnitAuras, "target")
                end
            end
            rebuildPlayerAuraCache()
        else
            pcall(Auras._refreshSummonSpecGate)
            if Auras.ScanBlizzardCDMAuras then
                pcall(Auras.ScanBlizzardCDMAuras, Auras)
            end
            if Auras._liveAura and Auras._liveAura.rescanUnitAuras then
                pcall(Auras._liveAura.rescanUnitAuras, "player", nil, true)
                if UnitExists and UnitExists("target") then
                    pcall(Auras._liveAura.rescanUnitAuras, "target", nil, true)
                end
            end
            rebuildPlayerAuraCache()
        end
    end)
    if _auraCacheFrame.RegisterUnitEvent then
        pcall(_auraCacheFrame.RegisterUnitEvent, _auraCacheFrame, "UNIT_AURA", "player", "target")
        pcall(_auraCacheFrame.RegisterUnitEvent, _auraCacheFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")
    else
        _auraCacheFrame:RegisterEvent("UNIT_AURA")
        pcall(_auraCacheFrame.RegisterEvent, _auraCacheFrame, "UNIT_SPELLCAST_SUCCEEDED")
    end
    _auraCacheFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    _auraCacheFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    _auraCacheFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    pcall(_auraCacheFrame.RegisterEvent, _auraCacheFrame, "ENCOUNTER_START")
    pcall(_auraCacheFrame.RegisterEvent, _auraCacheFrame, "CHALLENGE_MODE_START")
    pcall(_auraCacheFrame.RegisterEvent, _auraCacheFrame, "PLAYER_ENTERING_BATTLEGROUND")
    pcall(_auraCacheFrame.RegisterEvent, _auraCacheFrame, "COOLDOWN_VIEWER_DATA_LOADED")
    pcall(_auraCacheFrame.RegisterEvent, _auraCacheFrame, "TRAIT_CONFIG_UPDATED")
    pcall(Auras._refreshSummonSpecGate)
end

function Auras:GetTrackedAuraList(displayType)
    local _, _, normCategory = cdmCategoryFor(displayType)
    local key = normCategory or "TrackedIcon"

    local cached = _auraCatalog[key]
    if (type(cached) ~= "table" or #cached == 0)
       and cdmCatalogAvailable()
       and not (InCombatLockdown and InCombatLockdown()) then
        local okScan, fresh = pcall(buildAuraCatalog, key)
        if okScan and type(fresh) == "table" then
            _auraCatalog[key] = fresh
            _lastCatalogCounts[key] = #fresh
            cached = fresh
        end
    end
    if type(cached) ~= "table" then
        cached = _auraCatalog[key]
    end
    if (type(cached) ~= "table" or #cached == 0)
       and not (InCombatLockdown and InCombatLockdown()) then
        local fresh = buildAuraCatalog(key)
        _auraCatalog[key] = fresh
        _lastCatalogCounts[key] = #fresh
        cached = fresh
    end
    if type(cached) ~= "table" then return {} end

    local out = {}
    for i = 1, #cached do
        local e = cached[i]
        local tracked = true
        local okT, t = pcall(self.IsEntryCDMTracked, self, e)
        if okT then tracked = (t == true) end
        out[#out + 1] = {
            cooldownID             = e.cooldownID,
            spellID                = e.spellID,
            overrideSpellID        = e.overrideSpellID,
            overrideTooltipSpellID = e.overrideTooltipSpellID,
            linkedSpellIDs         = e.linkedSpellIDs,
            stableEntryID          = e.stableEntryID,
            displaySpellID         = e.displaySpellID,
            displayName            = e.displayName,
            displayIcon            = e.displayIcon,
            label                  = e.label,
            icon                   = e.icon,
            source                 = e.source,
            isKnown                = e.isKnown,
            category               = e.category,
            active                 = e.active,
            cdmTracked             = tracked,
        }
    end
    return out
end

function Auras:GetConfiguredAuraList(displayType)
    local category, _source, normCategory = cdmCategoryFor(displayType)
    if category == nil then return {} end
    if not cdmCatalogAvailable() then return {} end

    local key = normCategory or displayType
    local cat = _auraCatalog[key]
    if (type(cat) ~= "table" or #cat == 0)
       and not (InCombatLockdown and InCombatLockdown()) then
        local okC, fresh = pcall(buildAuraCatalog, key)
        if okC and type(fresh) == "table" then
            _auraCatalog[key] = fresh
            _lastCatalogCounts[key] = #fresh
            cat = fresh
        end
    end
    if type(cat) ~= "table" then return {} end

    local orderRank = (type(_liveRenderCat.rankByCategory) == "table"
        and _liveRenderCat.rankByCategory[category]) or {}

    local out = {}
    for i = 1, #cat do
        local e = cat[i]
        if type(e) == "table" then
            local tracked = true
            local okT, t = pcall(self.IsEntryCDMTracked, self, e)
            if okT then tracked = (t == true) end
            out[#out + 1] = {
                cooldownID             = e.cooldownID,
                spellID                = e.spellID,
                overrideSpellID        = e.overrideSpellID,
                overrideTooltipSpellID = e.overrideTooltipSpellID,
                linkedSpellIDs         = e.linkedSpellIDs,
                stableEntryID          = e.stableEntryID,
                displaySpellID         = e.displaySpellID,
                displayName            = e.displayName,
                displayIcon            = e.displayIcon,
                label                  = e.label,
                icon                   = e.icon,
                source                 = e.source,
                isKnown                = e.isKnown,
                category               = e.category,
                active                 = e.active,
                cdmTracked             = tracked,
                _orderRank             = orderRank[tonumber(e.cooldownID)] or math.huge,
            }
        end
    end

    table.sort(out, function(a, b)
        if a._orderRank ~= b._orderRank then return a._orderRank < b._orderRank end
        return tostring(a.stableEntryID) < tostring(b.stableEntryID)
    end)
    for i = 1, #out do out[i]._orderRank = nil end

    dlog("GetConfiguredAuraList: %s src=%s catalog=%d listed=%d",
        tostring(normCategory), tostring(_liveRenderCat.source), #cat, #out)
    return out
end

function Auras:GetTrackedAuraDiagnostics(selectedTab)
    local lines = {}
    local cdmOK = cdmCatalogAvailable()
    lines[#lines + 1] = "C_CooldownViewer available: " .. (cdmOK and "yes" or "no")

    local buffCat = (Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBuff)
        or CATEGORY_TRACKED_BUFF
    local barCat  = (Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBar)
        or CATEGORY_TRACKED_BAR
    lines[#lines + 1] = "TrackedBuff category count: " .. tostring(cdmCategoryCount(buffCat))
    lines[#lines + 1] = "TrackedBar category count: "  .. tostring(cdmCategoryCount(barCat))

    local iconViewer = _G[ICON_VIEWER_NAME]
    local barViewer  = _G[BAR_VIEWER_NAME]
    lines[#lines + 1] = ICON_VIEWER_NAME .. " found: " .. (iconViewer and "yes" or "no")
    lines[#lines + 1] = BAR_VIEWER_NAME  .. " found: " .. (barViewer  and "yes" or "no")

    lines[#lines + 1] = "Selected tab: " .. tostring(selectedTab or "?")

    if not self._enabled then
        lines[#lines + 1] = "Auras module: disabled"
    else
        lines[#lines + 1] = "Auras module: enabled"
    end
    if self.IconDisplay then
        lines[#lines + 1] = "IconDisplay: " .. (self.IconDisplay:Enabled() and "enabled" or "disabled")
    else
        lines[#lines + 1] = "IconDisplay: nil"
    end
    if self.BarDisplay then
        lines[#lines + 1] = "BarDisplay: " .. (self.BarDisplay:Enabled() and "enabled" or "disabled")
    else
        lines[#lines + 1] = "BarDisplay: nil"
    end
    return lines
end

ns:RegisterModule("Auras", {
    defaults = DEFAULTS,
    OnEnable = function(mod, profile) Auras:OnEnable(mod, profile) end,
    OnDisable = function(mod) Auras:OnDisable() end,
})
