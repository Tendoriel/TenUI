local _, ns = ...

function ns.InstallAuraDiagnostics(Auras, runtime)
    local BAR_VIEWER_NAME = runtime.BAR_VIEWER_NAME
    local DISPLAYTYPE_VIEWER_NAME = runtime.DISPLAYTYPE_VIEWER_NAME
    local ICON_VIEWER_NAME = runtime.ICON_VIEWER_NAME
    local anyPlayerOrTargetAura = runtime.anyPlayerOrTargetAura
    local buildActiveFromCatalog = runtime.buildActiveFromCatalog
    local buildAuraCatalog = runtime.buildAuraCatalog
    local cdmActiveForInfo = runtime.cdmActiveForInfo
    local cdmHiddenByDefault = runtime.cdmHiddenByDefault
    local childShownActive = runtime.childShownActive
    local entryDisplayEnabled = runtime.entryDisplayEnabled
    local evaluatePandemicForItem = runtime.evaluatePandemicForItem
    local findLiveViewerChildByCooldownID = runtime.findLiveViewerChildByCooldownID
    local getItemFrames = runtime.getItemFrames
    local getPandemicSpellID = runtime.getPandemicSpellID
    local getViewer = runtime.getViewer
    local infoAuraSpellIDs = runtime.infoAuraSpellIDs
    local isSecret = runtime.isSecret
    local itemPreferenceKeys = runtime.itemPreferenceKeys
    local pandemicClassifyItem = runtime.pandemicClassifyItem
    local pandemicOpts = runtime.pandemicOpts
    local pandemicState = runtime.pandemicState
    local readBlizzardPandemic = runtime.readBlizzardPandemic
    local readChildCooldownID = runtime.readChildCooldownID
    local resolveGlowTarget = runtime.resolveGlowTarget
    local resolveLiveAuraForEntry = runtime.resolveLiveAuraForEntry
    local safeTruthy = runtime.safeTruthy
    local spellDurationCache = runtime.spellDurationCache
    local viewerActiveCooldownIDSet = runtime.viewerActiveCooldownIDSet

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
                    push("    HasSecretValues=%s HasAnySecretAspect=%s IsAnchoringSecret=%s",
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
        push("=== /tenui aura pipeline -- non-invasive display-chain diagnostic ===")
        push("  context: %s   target=%s",
            inCombat and "IN COMBAT" or "out of combat",
            (UnitExists and UnitExists("target")) and "yes" or "no")
        push("  Blizzard AuraContainer: icons=%s bars=%s",
            self._nativeIcons and "ready" or "fallback", self._nativeBars and "ready" or "fallback")
        if self._nativeIcons and self._nativeBars then return lines end
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
            push("  %s: configured=%d  activeNow=%d (idle=%d)  engineStore=%d  viewerChildren=%d  crossViewer=%d  widgets=%d  anyTexture=%s  containerVisible=%s alpha=%s size=%s",
                displayType, cfg, catActive, idle, eng, vc, cv, wid,
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
                push("    -> Legacy fallback produced %d active entries from secondary sources.", catActive)
            elseif catActive == 0 and eng == 0 and idle > 0 then
                push("    -> chain OK: %d IDLE row(s) (Show When Inactive ON), nothing active", idle)
                push("       right now out of combat -- correct + expected.")
            elseif cat == 0 and eng == 0 then
                if inCombat then
                    push("    -> Legacy fallback has no readable active entries in this combat context.")
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
end
