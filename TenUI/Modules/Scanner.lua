local addonName, ns = ...

local CreateFrame   = CreateFrame
local C_SpellBook   = C_SpellBook
local C_Spell       = C_Spell
local C_Item        = C_Item
local GetTime       = GetTime
local InCombatLockdown = InCombatLockdown
local type          = type
local pairs         = pairs
local ipairs        = ipairs
local tostring      = tostring
local tonumber      = tonumber
local pcall         = pcall
local tinsert       = table.insert
local tremove       = table.remove
local wipe          = wipe

local Scanner = {}
ns.Scanner = Scanner

local _dirty = {}

local _cache = {}

local ERROR_RING_MAX = 100
local _errorRing     = {}
local _errorHead     = 0

local _perf = {
    scanCount       = 0,
    lastScanAt      = 0,
    lastScanDurationMs = 0,
    cacheHits       = 0,
    cacheMisses     = 0,
}

local _lastSummary = "No scan run yet."

local _deferredScans = {}

local function pushError(msg)
    _errorHead = _errorHead + 1
    _errorRing[_errorHead] = date("%H:%M:%S") .. " " .. tostring(msg)
    if #_errorRing > ERROR_RING_MAX then
        tremove(_errorRing, 1)
        _errorHead = _errorHead - 1
    end
    if ns.Debug and ns.Debug.Log then
        ns.Debug:Log("[Scanner] " .. tostring(msg))
    end
end

local function markDirty(container)
    _dirty[container] = true
end

local function markAllDirty()
    for _, name in ipairs({ "EssentialCooldowns", "UtilityCooldowns", "DefensiveCooldowns", "Trinkets", "Custom" }) do
        _dirty[name] = true
    end
end

local function getSpellName(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, spellID)
        if ok and n then return n end
    end
    return nil
end

local function getSpellIcon(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, spellID)
        if ok then return t end
    end
    return nil
end

local function isSpellKnown(spellID)
    if not spellID then return false end
    if C_SpellBook and C_SpellBook.IsSpellKnown
       and Enum and Enum.SpellBookSpellBank then
        local ok, k = pcall(C_SpellBook.IsSpellKnown, spellID,
                            Enum.SpellBookSpellBank.Player)
        if ok then return k == true end
    end
    if C_Spell and C_Spell.IsSpellKnown then
        local ok, k = pcall(C_Spell.IsSpellKnown, spellID)
        if ok then return k == true end
    end
    return false
end

local function isPassiveSpell(spellID)
    if not spellID then return false end
    if C_Spell and C_Spell.IsSpellPassive then
        local ok, passive = pcall(C_Spell.IsSpellPassive, spellID)
        if ok and passive == true then return true end
    end
    return false
end

function Scanner:ScanCDM()
    if InCombatLockdown() then
        _deferredScans.cdm = true
        pushError("ScanCDM deferred (in combat)")
        return false, "in combat"
    end
    local t0 = GetTime()
    _perf.scanCount = _perf.scanCount + 1
    _perf.lastScanAt = t0

    local bars = ns.Bars
    if not (bars and bars.Scanner and bars.Scanner.CDM) then
        pushError("ScanCDM: Bars.Scanner.CDM not loaded")
        return false, "CDM scanner not loaded"
    end

    local ok, total = bars.Scanner.CDM:ScanAll()
    local elapsed = math.floor((GetTime() - t0) * 1000 + 0.5)
    _perf.lastScanDurationMs = elapsed

    local containers = { "EssentialCooldowns", "UtilityCooldowns", "DefensiveCooldowns" }
    for _, container in ipairs(containers) do
        markDirty(container)
        local rows = ns.Bars and ns.Bars.GetCurrentRows and ns.Bars:GetCurrentRows() or {}
        local row  = rows[container]
        if row and row.candidates then
            local i = 1
            while i <= #row.candidates do
                local entry = row.candidates[i]
                if not entry.source then
                    entry.source = "cdm"
                end
                if entry.type == "spell" and isPassiveSpell(entry.id) then
                    table.remove(row.candidates, i)
                else
                    i = i + 1
                end
            end
        end
        ns:Fire("SCANNER_CANDIDATES_UPDATED", container)
    end

    _lastSummary = ("CDM scan: ok=%s total=%s  (%dms)"):format(
        tostring(ok), tostring(total), elapsed)
    pushError("ScanCDM complete: " .. _lastSummary)
    return ok, total
end

function Scanner:ScanSpellBook()
    if InCombatLockdown() then
        _deferredScans.spellbook = true
        pushError("ScanSpellBook deferred (in combat)")
        return false, "in combat"
    end
    local t0 = GetTime()
    _perf.scanCount = _perf.scanCount + 1

    if not C_SpellBook then
        pushError("ScanSpellBook: C_SpellBook not available")
        return false, "C_SpellBook unavailable"
    end

    local results = {}
    local count   = 0

    local numTabs = C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetNumSpellBookSkillLines() or 0
    for tabIdx = 1, numTabs do
        local tabInfo = C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookSkillLineInfo(tabIdx)
        if tabInfo then
            if tabInfo.offSpecID == nil then
                local offset    = tabInfo.itemIndexOffset or 0
                local numSpells = tabInfo.numSpellBookItems or 0
                for slotIdx = offset + 1, offset + numSpells do
                    local ok, slotType, spellID = pcall(C_SpellBook.GetSpellBookItemType, slotIdx, Enum.SpellBookSpellBank.Player)
                    if ok and slotType == Enum.SpellBookItemType.Spell and spellID then
                        local passive = false
                        if C_SpellBook.IsSpellBookItemPassive then
                            local okP, p = pcall(C_SpellBook.IsSpellBookItemPassive, slotIdx, Enum.SpellBookSpellBank.Player)
                            if okP and p then passive = true end
                        end
                        if not passive then
                            passive = isPassiveSpell(spellID)
                        end
                        if not passive then
                            local known = isSpellKnown(spellID)
                            local name  = getSpellName(spellID)
                            local icon  = getSpellIcon(spellID)
                            results[#results + 1] = {
                                type    = "spell",
                                id      = spellID,
                                source  = "spellbook",
                                name    = name,
                                icon    = icon,
                                isKnown = known,
                            }
                            count = count + 1
                        end
                    end
                end
            end
        end
    end

    _cache["__spellbook"] = results

    local elapsed = math.floor((GetTime() - t0) * 1000 + 0.5)
    _perf.lastScanDurationMs = elapsed
    _lastSummary = ("SpellBook scan: %d spells  (%dms)"):format(count, elapsed)
    pushError("ScanSpellBook complete: " .. _lastSummary)
    ns:Fire("SCANNER_CANDIDATES_UPDATED", "__spellbook")
    return true, count
end

function Scanner:ScanTrinkets()
    if InCombatLockdown() then
        _deferredScans.trinkets = true
        pushError("ScanTrinkets deferred (in combat)")
        return false, "in combat"
    end
    local t0 = GetTime()
    _perf.scanCount = _perf.scanCount + 1

    local bars = ns.Bars
    if not (bars and bars.Scanner and bars.Scanner.Trinkets) then
        pushError("ScanTrinkets: Bars.Scanner.Trinkets not loaded")
        return false, "Trinkets scanner not loaded"
    end

    local ok, info = bars.Scanner.Trinkets:Sync()
    markDirty("Trinkets")

    local rows = ns.Bars and ns.Bars.GetCurrentRows and ns.Bars:GetCurrentRows() or {}
    local trow = rows["Trinkets"]
    if trow and trow.candidates then
        for _, entry in ipairs(trow.candidates) do
            if not entry.source then
                entry.source = "trinket"
            end
        end
    end

    local elapsed = math.floor((GetTime() - t0) * 1000 + 0.5)
    _perf.lastScanDurationMs = elapsed
    _lastSummary = ("Trinkets scan: ok=%s  (%dms)"):format(tostring(ok), elapsed)
    pushError("ScanTrinkets complete: " .. _lastSummary)
    ns:Fire("SCANNER_CANDIDATES_UPDATED", "Trinkets")
    return ok, info
end

function Scanner:GetCandidates(container, filter)
    if not container then return {} end
    filter = filter or {}

    local merged = {}
    local seen   = {}

    local function addEntry(entry)
        if not entry then return end
        local key = (entry.type or "?") .. ":" .. tostring(entry.id or "")
        if not seen[key] then
            seen[key] = true
            merged[#merged + 1] = entry
        end
    end

    if container ~= "__spellbook" and container ~= "__trinkets" then
        if ns.Bars and ns.Bars.GetCurrentRows then
            local rows = ns.Bars:GetCurrentRows() or {}
            local row  = rows[container]
            if row and row.candidates then
                for _, entry in ipairs(row.candidates) do
                    addEntry(entry)
                end
                _perf.cacheHits = _perf.cacheHits + 1
            else
                _perf.cacheMisses = _perf.cacheMisses + 1
            end
        end
    end

    if not filter.sourceTag or filter.sourceTag == "spellbook" then
        local sb = _cache["__spellbook"] or {}
        for _, entry in ipairs(sb) do
            addEntry(entry)
        end
    end

    if container == "Trinkets" or filter.sourceTag == "trinket" or not filter.sourceTag then
        if container ~= "Trinkets" and (filter.sourceTag == "trinket" or not filter.sourceTag) then
            if ns.Bars and ns.Bars.GetCurrentRows then
                local rows = ns.Bars:GetCurrentRows() or {}
                local trow = rows["Trinkets"]
                if trow and trow.candidates then
                    for _, entry in ipairs(trow.candidates) do
                        addEntry(entry)
                    end
                end
            end
        end
    end

    local custom = _cache["__custom"] or {}
    for _, entry in ipairs(custom) do
        addEntry(entry)
    end

    local displayedSet = {}
    if filter.hideDisplayed and ns.Bars and ns.Bars.GetCurrentRows then
        local rows = ns.Bars:GetCurrentRows() or {}
        for _, row in pairs(rows) do
            if type(row) == "table" and type(row.displayed) == "table" then
                for _, entry in ipairs(row.displayed) do
                    local k = (entry.type or "?") .. ":" .. tostring(entry.id or "")
                    displayedSet[k] = true
                end
            end
        end
    end

    local out = {}
    for _, entry in ipairs(merged) do
        if filter.sourceTag and entry.source ~= filter.sourceTag then
        else
            if entry.type == "spell" and isPassiveSpell(entry.id) then
            else
                local known = entry.isKnown
                if known == nil then known = isSpellKnown(entry.id) end
                if filter.knownOnly and not known then
                else
                    local name = entry.name or getSpellName(entry.id) or ""
                    local searchOk = true
                    if filter.search and filter.search ~= "" then
                        local lo = filter.search:lower()
                        searchOk = name:lower():find(lo, 1, true) ~= nil
                    end
                    if searchOk then
                        local key = (entry.type or "?") .. ":" .. tostring(entry.id or "")
                        if filter.hideDisplayed and displayedSet[key] then
                        else
                            out[#out + 1] = entry
                        end
                    end
                end
            end
        end
    end

    return out
end

function Scanner:ValidateSpellID(id)
    id = tonumber(id)
    if not id or id <= 0 then
        return { valid = false, known = false, name = nil, icon = nil, reason = "invalid ID" }
    end
    local name = getSpellName(id)
    local icon = getSpellIcon(id)
    if not name then
        return { valid = false, known = false, name = nil, icon = nil, reason = "spell not found in client data" }
    end
    local known = isSpellKnown(id)
    return { valid = true, known = known, name = name, icon = icon, reason = nil }
end

function Scanner:RebuildCandidateCache()
    if InCombatLockdown() then
        pushError("RebuildCandidateCache deferred (in combat)")
        return false
    end
    for container in pairs(_dirty) do
        _dirty[container] = nil
    end
    return true
end

function Scanner:AddToBar(container, spellID, source)
    if not (ns.Bars and ns.Bars.AddEntry) then
        return false, "Bars module not loaded"
    end
    local entry = { type = "spell", id = tonumber(spellID) }
    return ns.Bars:AddEntry(container, entry)
end

function Scanner:RemoveFromBar(container, spellID)
    if not (ns.Bars and ns.Bars.RemoveEntry) then
        return false, "Bars module not loaded"
    end
    local entry = { type = "spell", id = tonumber(spellID) }
    return ns.Bars:RemoveEntry(container, entry)
end

function Scanner:ReorderBar(container, fromIndex, toIndex)
    if not ns.savedVarsReady then return false, "not ready" end
    if not (ns.Bars and ns.Bars.GetCurrentRows) then
        return false, "Bars module not loaded"
    end
    local rows = ns.Bars:GetCurrentRows() or {}
    local row  = rows[container]
    if not (row and row.displayed) then
        return false, "no displayed list"
    end
    local list = row.displayed
    local n = #list
    if fromIndex < 1 or fromIndex > n or toIndex < 1 or toIndex > n then
        return false, "index out of range"
    end
    local item = tremove(list, fromIndex)
    tinsert(list, toIndex, item)
    if ns.Bars and ns.Bars.rows and ns.Bars.rows[container] then
        local row_obj = ns.Bars.rows[container]
        if type(row_obj.Rebuild) == "function" then
            pcall(row_obj.Rebuild, row_obj)
        end
    end
    return true
end

function Scanner:GetLastScanSummary()
    local lines = { _lastSummary }
    lines[#lines + 1] = ("scans=%d  lastMs=%d  hits=%d  misses=%d"):format(
        _perf.scanCount, _perf.lastScanDurationMs, _perf.cacheHits, _perf.cacheMisses)
    if #_errorRing > 0 then
        local last = _errorRing[#_errorRing]
        lines[#lines + 1] = "last log: " .. tostring(last)
    end
    return table.concat(lines, "\n")
end

function Scanner:GetErrors()
    local out = {}
    for i = 1, #_errorRing do out[i] = _errorRing[i] end
    return out
end

ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    local deferred = {}
    for k in pairs(_deferredScans) do deferred[#deferred + 1] = k end
    wipe(_deferredScans)

    for i = 1, #deferred do
        local which = deferred[i]
        if which == "cdm" then
            Scanner:ScanCDM()
        elseif which == "spellbook" then
            Scanner:ScanSpellBook()
        elseif which == "trinkets" then
            Scanner:ScanTrinkets()
        end
    end
end)

local _specScanScheduled = false
local function scheduleSpecRescan()
    markAllDirty()
    if InCombatLockdown() then
        _deferredScans.cdm = true
        pushError("spec/CDM change while in combat -- deferred CDM rescan")
        return
    end
    if _specScanScheduled then return end
    _specScanScheduled = true
    C_Timer.After(0, function()
        _specScanScheduled = false
        if InCombatLockdown() then
            _deferredScans.cdm = true
            return
        end
        Scanner:ScanCDM()
    end)
end

ns:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", scheduleSpecRescan)
pcall(ns.RegisterEvent, ns, "COOLDOWN_VIEWER_DATA_LOADED", scheduleSpecRescan)
pcall(ns.RegisterEvent, ns, "TRAIT_CONFIG_UPDATED", scheduleSpecRescan)

local function refreshAllRowDisplays()
    if not (ns.Bars and ns.Bars.rows) then return end
    for _, row in pairs(ns.Bars.rows) do
        if row and type(row.RequestRefresh) == "function" then
            pcall(row.RequestRefresh, row)
        end
    end
end

local function revalidateSpellbookCacheKnown()
    local sb = _cache["__spellbook"]
    if not sb then return end
    local changed = false
    for i = 1, #sb do
        local entry = sb[i]
        if entry and entry.type == "spell" and entry.id then
            local known = isSpellKnown(entry.id)
            if entry.isKnown ~= known then
                entry.isKnown = known
                changed = true
            end
        end
    end
    if changed then
        ns:Fire("SCANNER_CANDIDATES_UPDATED", "__spellbook")
    end
end

local _spellsChangedScheduled    = false
local _combatRevalidateAt        = 0
local SPELLS_CHANGED_COMBAT_GAP  = 2.0

local function scheduleSpellsChangedRescan()
    markDirty("__spellbook")
    if _spellsChangedScheduled then return end
    _spellsChangedScheduled = true
    C_Timer.After(0, function()
        _spellsChangedScheduled = false
        if InCombatLockdown() then
            _deferredScans.spellbook = true
            local now = (GetTime and GetTime()) or 0
            if (now - _combatRevalidateAt) >= SPELLS_CHANGED_COMBAT_GAP then
                _combatRevalidateAt = now
                revalidateSpellbookCacheKnown()
            end
            return
        end
        Scanner:ScanSpellBook()
        refreshAllRowDisplays()
    end)
end

ns:RegisterEvent("SPELLS_CHANGED", scheduleSpellsChangedRescan)

local TRINKET_SLOT_SET = { [13] = true, [14] = true }

local _trinketScanScheduled = false
local function scheduleTrinketRescan()
    markDirty("Trinkets")
    if _trinketScanScheduled then return end
    _trinketScanScheduled = true
    C_Timer.After(0, function()
        _trinketScanScheduled = false
        Scanner:ScanTrinkets()
    end)
end

ns:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function(_, slotID)
    if TRINKET_SLOT_SET[slotID] then
        scheduleTrinketRescan()
    end
end)

ns:RegisterEvent("BAG_UPDATE_DELAYED", function()
    markDirty("Trinkets")
end)
