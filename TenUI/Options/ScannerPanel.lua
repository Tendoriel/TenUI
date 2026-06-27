local addonName, ns = ...

local type     = type
local pairs    = pairs
local ipairs   = ipairs
local tostring = tostring
local tonumber = tonumber
local pcall    = pcall
local math_floor = math.floor
local math_max   = math.max
local math_ceil  = math.ceil

local CONTAINERS = {
    { key = "EssentialCooldowns", label = "Essential" },
    { key = "UtilityCooldowns",   label = "Utility" },
    { key = "DefensiveCooldowns", label = "Defensive" },
    { key = "Trinkets",           label = "Trinkets" },
    { key = "Consumables",        label = "Consumables" },
    { key = "Custom",             label = "Custom" },
}

local _selectedContainer = "EssentialCooldowns"
local _showKnownOnly     = false
local _sourceFilter      = ""

local _selectedCustomBarID = nil

local function customBars()
    if ns.Bars and ns.Bars.GetCustomBars then
        return ns.Bars:GetCustomBars()
    end
    return {}
end

local function selectedCustomDef()
    local defs = customBars()
    if #defs == 0 then return nil end
    if _selectedCustomBarID then
        for i = 1, #defs do
            if tonumber(defs[i].id) == tonumber(_selectedCustomBarID) then
                return defs[i]
            end
        end
    end
    _selectedCustomBarID = tonumber(defs[1].id)
    return defs[1]
end

local function currentRowKey()
    if _selectedContainer ~= "Custom" then
        return _selectedContainer
    end
    local def = selectedCustomDef()
    if def and ns.Bars and ns.Bars.CustomRowKey then
        return ns.Bars:CustomRowKey(def.id)
    end
    return nil
end

local function rebuildPageDeferred()
    C_Timer.After(0, function()
        if not InCombatLockdown() and ns.Options and ns.Options.RebuildPage then
            ns.Options:RebuildPage("cdmbars")
        end
    end)
end

local function persistCustomBarSelection()
    local ui = ns.GetUIState and ns:GetUIState()
    if ui and ui.lastOptionsSub then
        ui.lastOptionsSub.cdmbarsCustomBar = _selectedCustomBarID
    end
end

local _sc                  = nil
local _candidateListFrame  = nil
local _barLayoutListFrame  = nil
local _barLayoutHeader     = nil
local _addSpellIDEditBox   = nil
local _statusLabel         = nil
local _addingToLabel       = nil
local _tabBgMap            = {}
local _scanBtnRow          = nil
local _scanCDMBtn          = nil
local _scanSpellBookBtn    = nil
local _scanTrinketsBtn     = nil
local _SECTION_GAP         = 8
local _HEADER_H            = 16

local function _widthOr(frame, fallback)
    local w = frame and frame:GetWidth() or 0
    if w > 0 then return w end
    return fallback
end

local function getOptionsProfile()
    if not ns.savedVarsReady then return {} end
    local p = ns:GetProfile()
    p.modules = p.modules or {}
    p.modules.Options = p.modules.Options or {}
    return p.modules.Options
end

local function getSpellLabel(spellID)
    if not spellID then return "?" end
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and name then return name end
    end
    return "Spell " .. tostring(spellID)
end

local function getSpellIcon(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
        if ok then return tex end
    end
    return nil
end

local function getItemIconTex(itemID)
    if not itemID then return nil end
    if C_Item and C_Item.GetItemIconByID then
        local ok, tex = pcall(C_Item.GetItemIconByID, itemID)
        if ok and tex then return tex end
    end
    if GetItemIcon then
        local ok, tex = pcall(GetItemIcon, itemID)
        if ok and tex then return tex end
    end
    return nil
end

local function isSpellKnown(spellID)
    if not spellID then return false end
    if C_Spell and C_Spell.IsSpellKnown then
        local ok, known = pcall(C_Spell.IsSpellKnown, spellID)
        if ok then return known == true end
    end
    return true
end

local function updateStatusLabel(text)
    if _statusLabel then
        _statusLabel:SetText(tostring(text or ""))
    end
end

local function updateAddingToLabel()
    if not _addingToLabel then return end
    local label = _selectedContainer
    for _, def in ipairs(CONTAINERS) do
        if def.key == _selectedContainer then
            label = def.label
            break
        end
    end
    if _selectedContainer == "Custom" then
        local def = selectedCustomDef()
        if def then
            label = "Custom \226\128\148 " .. tostring(def.name or ("Custom " .. tostring(def.id)))
        else
            label = "Custom (no bars yet)"
        end
    end
    _addingToLabel:SetText("Adding to: " .. label)
end

local function updateScanButtons()
    if not _scanBtnRow then return end
    local visible
    if _selectedContainer == "Trinkets" then
        visible = { _scanTrinketsBtn }
    elseif _selectedContainer == "Consumables" then
        visible = {}
    elseif _selectedContainer == "Custom" then
        visible = { _scanSpellBookBtn }
    else
        visible = { _scanCDMBtn, _scanSpellBookBtn }
    end
    local all = { _scanCDMBtn, _scanSpellBookBtn, _scanTrinketsBtn }
    for _, b in ipairs(all) do
        if b then b:Hide() end
    end
    local x = 0
    for _, b in ipairs(visible) do
        if b then
            b:ClearAllPoints()
            b:SetPoint("LEFT", _scanBtnRow, "LEFT", x, 0)
            b:Show()
            x = x + (b:GetWidth() or 140) + 8
        end
    end
end

local function selectTab(key)
    _selectedContainer = key
    for k, tab in pairs(_tabBgMap) do
        tab:SetSelected(k == key)
    end
    updateAddingToLabel()
    updateScanButtons()
    local opts = getOptionsProfile()
    opts.selectedCDMContainer = key
    local ui = ns.GetUIState and ns:GetUIState()
    if ui then
        ui.lastOptionsSub.cdmbars = key
    end
end

local function relayoutBarSection()
    if not (_candidateListFrame and _barLayoutListFrame) then return end

    if _barLayoutHeader then
        _barLayoutHeader:ClearAllPoints()
        _barLayoutHeader:SetPoint("TOPLEFT", _candidateListFrame, "BOTTOMLEFT", 0, -_SECTION_GAP)
        if _sc then
            _barLayoutHeader:SetWidth(_widthOr(_sc, 340) - 16)
        end
        _barLayoutListFrame:ClearAllPoints()
        _barLayoutListFrame:SetPoint("TOPLEFT", _barLayoutHeader, "BOTTOMLEFT", 0, -_SECTION_GAP)
        if _sc then
            _barLayoutListFrame:SetWidth(_widthOr(_sc, 340) - 16)
        end
    else
        _barLayoutListFrame:ClearAllPoints()
        _barLayoutListFrame:SetPoint("TOPLEFT", _candidateListFrame, "BOTTOMLEFT", 0, -_SECTION_GAP)
        if _sc then
            _barLayoutListFrame:SetWidth(_widthOr(_sc, 340) - 16)
        end
    end

    if _sc then
        local scTop = _sc:GetTop()
        local barBottom = _barLayoutListFrame:GetBottom()
        if scTop and barBottom then
            local totalUsed = scTop - barBottom + _SECTION_GAP
            _sc:SetHeight(math_max(totalUsed, 10))
        else
            local cH = _candidateListFrame:GetHeight() or 80
            local hH = (_barLayoutHeader and (_barLayoutHeader:GetHeight() or _HEADER_H)) or 0
            local bH = _barLayoutListFrame:GetHeight() or 60
            local _, _, _, _, cY = _candidateListFrame:GetPoint(1)
            local topOffset = math.abs(cY or 8)
            local totalUsed = topOffset + cH + _SECTION_GAP + hH + _SECTION_GAP + bH + _SECTION_GAP
            _sc:SetHeight(math_max(totalUsed, 10))
        end
    end
end

local rebuildBarLayoutList

local function rebuildCandidateGrid()
    if not (_candidateListFrame and ns.UI) then return end
    local C = ns.UI
    C.ClearChildren(_candidateListFrame)

    local rowKey = currentRowKey()
    if not rowKey then
        _candidateListFrame:SetHeight(10)
        relayoutBarSection()
        return
    end

    local filter = {
        knownOnly     = _showKnownOnly,
        sourceTag     = (_sourceFilter ~= "") and _sourceFilter or nil,
        hideDisplayed = true,
    }

    local candidates
    if ns.Scanner and ns.Scanner.GetCandidates then
        candidates = ns.Scanner:GetCandidates(rowKey, filter)
    else
        candidates = {}
        if ns.Bars and ns.Bars.GetCurrentRows then
            local rows = ns.Bars:GetCurrentRows() or {}
            local row  = rows[rowKey]
            if row and row.candidates then
                for _, entry in ipairs(row.candidates) do
                    if entry and entry.type == "spell" then
                        local known = isSpellKnown(entry.id)
                        if not _showKnownOnly or known then
                            candidates[#candidates + 1] = entry
                        end
                    end
                end
            end
        end
    end

    local items = {}
    for i = 1, #candidates do
        local entry = candidates[i]
        if entry then
            if entry.type == "spell" then
                local spellID = entry.id
                local known   = entry.isKnown
                if known == nil then known = isSpellKnown(spellID) end
                items[#items + 1] = {
                    texture  = entry.icon or getSpellIcon(spellID),
                    label    = entry.name or getSpellLabel(spellID),
                    spellID  = spellID,
                    source   = entry.source or "cdm",
                    isKnown  = known,
                    entryRef = entry,
                }
            elseif entry.type == "item" then
                items[#items + 1] = {
                    texture  = nil,
                    label    = "Item " .. tostring(entry.id),
                    spellID  = nil,
                    source   = entry.source or "item",
                    isKnown  = true,
                    entryRef = entry,
                }
            end
        end
    end

    if #items == 0 then
        local msg = C.Text(_candidateListFrame, C.Fonts.small, C.Theme.color.textDim,
            "No candidates here. Click 'Re-scan Blizzard CDM' or 'Scan Spell Book'.")
        msg:SetPoint("TOPLEFT", _candidateListFrame, "TOPLEFT", 8, -8)
        _candidateListFrame:SetHeight(30)
        updateStatusLabel("0 candidates")
        relayoutBarSection()
        return
    end

    local callbacks = {
        onClick = function(data)
            if ns.Scanner and ns.Scanner.AddToBar then
                local ok, err = ns.Scanner:AddToBar(rowKey, data.spellID or (data.entryRef and data.entryRef.id), data.source)
                if ok then
                    rebuildBarLayoutList()
                    rebuildCandidateGrid()
                else
                    if ns.Debug and ns.Debug.Log then
                        ns.Debug:Log("[ScannerPanel] AddToBar failed: %s", tostring(err))
                    end
                end
            elseif ns.Bars and ns.Bars.AddEntry and data.entryRef then
                local ok, err = ns.Bars:AddEntry(rowKey, data.entryRef)
                if ok then
                    rebuildBarLayoutList()
                    rebuildCandidateGrid()
                end
            end
        end,
        onRightClick = function(data)
            if data.spellID then
                local ap = ns.AbilityPanel or (ns.Options and ns.Options.AbilityPanel)
                if ap and ap.OpenForSpell then
                    ap:OpenForSpell(data.spellID)
                end
            end
        end,
    }

    local frames = C.CreateIconGrid(_candidateListFrame, items, callbacks)
    local ICON_SIZE  = 32
    local ICON_GAP   = 4
    local cols = math_max(1, math_floor(_widthOr(_candidateListFrame, 300) / (ICON_SIZE + ICON_GAP)))
    local numRows = math_ceil(#items / cols)
    _candidateListFrame:SetHeight(math_max(numRows * (ICON_SIZE + ICON_GAP), 36))
    updateStatusLabel(#items .. " candidates · " .. (ns.Scanner and ns.Scanner:GetLastScanSummary() or "") )
    relayoutBarSection()
end

local _dragState = nil

local _dropIndicator = nil

local function ensureDropIndicator(parent)
    local C = ns.UI
    if not (_dropIndicator and _dropIndicator.line) then
        local ind = CreateFrame("Frame", nil, parent)
        ind:SetHeight(2)
        ind:SetFrameStrata("DIALOG")
        local line = ind:CreateTexture(nil, "OVERLAY")
        line:SetAllPoints(ind)
        line:SetColorTexture(C.Theme.color.accent[1], C.Theme.color.accent[2], C.Theme.color.accent[3], 1)
        ind.line = line
        _dropIndicator = ind
    else
        _dropIndicator:SetParent(parent)
    end
    _dropIndicator:ClearAllPoints()
    _dropIndicator:Hide()
    return _dropIndicator
end

local function computeInsertPos(state, cursorY)
    local rows = state.sectionRows
    local n = #rows
    if n == 0 then return 1 end
    for i = 1, n do
        local r = rows[i]
        local top = r:GetTop()
        local bottom = r:GetBottom()
        if top and bottom then
            local mid = (top + bottom) * 0.5
            if cursorY >= mid then
                return i
            end
        end
    end
    return n + 1
end

local function insertPosToTarget(insertPos, fromIdx)
    local target = insertPos
    if insertPos > fromIdx then
        target = insertPos - 1
    end
    return target
end

local function moveDropIndicator(state, insertPos)
    local ind = state.indicator
    if not ind then return end
    local rows = state.sectionRows
    local n = #rows
    if insertPos < 1 then insertPos = 1 end
    if insertPos > n + 1 then insertPos = n + 1 end
    ind:ClearAllPoints()
    if insertPos <= n then
        ind:SetPoint("TOPLEFT", rows[insertPos], "TOPLEFT", 0, 2)
        ind:SetPoint("TOPRIGHT", rows[insertPos], "TOPRIGHT", 0, 2)
    else
        ind:SetPoint("BOTTOMLEFT", rows[n], "BOTTOMLEFT", 0, -2)
        ind:SetPoint("BOTTOMRIGHT", rows[n], "BOTTOMRIGHT", 0, -2)
    end
    ind:Show()
end

local function buildBarLayoutEntryRow(parent, entry, idx, totalCount,
                                      isRow2, totalH, capturedContainer, sectionRows)
    local C = ns.UI
    local Theme = C.Theme
    local ROW_H = 26
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, -totalH)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -totalH)
    row:SetHeight(ROW_H)
    if sectionRows then
        sectionRows[idx] = row
    end
    local rowBg = row:CreateTexture(nil, "BACKGROUND")
    rowBg:SetAllPoints(row)
    local baseAlpha = (idx % 2 == 0) and 0.05 or 0.02
    if isRow2 then
        rowBg:SetColorTexture(Theme.color.violet[1], Theme.color.violet[2], Theme.color.violet[3], baseAlpha + 0.03)
    else
        rowBg:SetColorTexture(1, 1, 1, baseAlpha)
    end

    local idxLabel = C.Text(row, C.Fonts.value, Theme.color.textDim, tostring(idx) .. ".")
    idxLabel:SetPoint("LEFT", row, "LEFT", 4, 0)
    idxLabel:SetWidth(20)
    idxLabel:SetJustifyH("LEFT")

    local ICON_W = 20
    local iconTex = row:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(ICON_W, ICON_W)
    iconTex:SetPoint("LEFT", idxLabel, "RIGHT", 2, 0)
    local entryIcon
    if entry.type == "spell" then
        entryIcon = getSpellIcon(entry.id)
    elseif entry.type == "item" then
        entryIcon = getItemIconTex(entry.id)
    end
    if entryIcon then
        iconTex:SetTexture(entryIcon)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        iconTex:SetColorTexture(0.18, 0.20, 0.28, 1)
    end

    local nameLabel = C.Text(row, C.Fonts.value, Theme.color.text)
    nameLabel:SetPoint("LEFT", iconTex, "RIGHT", 4, 0)
    if entry.type == "spell" then
        nameLabel:SetText(getSpellLabel(entry.id) .. " (" .. tostring(entry.id) .. ")")
    elseif entry.type == "item" then
        nameLabel:SetText("item:" .. tostring(entry.id))
    else
        nameLabel:SetText("?")
    end

    local capturedEntry = entry
    local capturedIdx   = idx
    local capturedLen   = totalCount

    local removeBtn = C.CreateGlyphButton(row, "x", function()
        if isRow2 then
            if ns.Bars and ns.Bars.RemoveEntryFromRow2 then
                ns.Bars:RemoveEntryFromRow2(capturedContainer, capturedEntry)
                rebuildBarLayoutList()
            end
        else
            if ns.Bars and ns.Bars.RemoveEntry then
                ns.Bars:RemoveEntry(capturedContainer, capturedEntry)
                rebuildBarLayoutList()
                rebuildCandidateGrid()
            end
        end
    end)
    removeBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)

    local downBtn = C.CreateGlyphButton(row, "down", function()
        if isRow2 then
            if ns.Bars and ns.Bars.ReorderRow2 then
                local ok = ns.Bars:ReorderRow2(capturedContainer, capturedIdx, capturedIdx + 1)
                if ok then rebuildBarLayoutList() end
            end
        else
            if ns.Scanner and ns.Scanner.ReorderBar then
                local ok = ns.Scanner:ReorderBar(capturedContainer, capturedIdx, capturedIdx + 1)
                if ok then rebuildBarLayoutList() end
            end
        end
    end)
    downBtn:SetPoint("RIGHT", removeBtn, "LEFT", -2, 0)
    downBtn:SetEnabledVisual(capturedIdx < capturedLen)

    local upBtn = C.CreateGlyphButton(row, "up", function()
        if isRow2 then
            if ns.Bars and ns.Bars.ReorderRow2 then
                local ok = ns.Bars:ReorderRow2(capturedContainer, capturedIdx, capturedIdx - 1)
                if ok then rebuildBarLayoutList() end
            end
        else
            if ns.Scanner and ns.Scanner.ReorderBar then
                local ok = ns.Scanner:ReorderBar(capturedContainer, capturedIdx, capturedIdx - 1)
                if ok then rebuildBarLayoutList() end
            end
        end
    end)
    upBtn:SetPoint("RIGHT", downBtn, "LEFT", -2, 0)
    upBtn:SetEnabledVisual(capturedIdx > 1)

    local moveBtn = C.CreateCompactButton(row, isRow2 and "R1" or "R2", function()
        if isRow2 then
            if ns.Bars and ns.Bars.MoveEntryToRow1 then
                ns.Bars:MoveEntryToRow1(capturedContainer, capturedEntry)
                rebuildBarLayoutList()
            end
        else
            if ns.Bars and ns.Bars.MoveEntryToRow2 then
                ns.Bars:MoveEntryToRow2(capturedContainer, capturedEntry)
                rebuildBarLayoutList()
            end
        end
    end, 28)
    moveBtn:SetHeight(16)
    moveBtn:SetPoint("RIGHT", upBtn, "LEFT", -2, 0)
    moveBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText(isRow2 and "Move to Row 1" or "Move to Row 2", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    moveBtn:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    row:EnableMouse(true)
    row:SetScript("OnMouseDown", function(self, btn)
        if btn == "RightButton" and entry.type == "spell" then
            local ap = ns.AbilityPanel or (ns.Options and ns.Options.AbilityPanel)
            if ap and ap.OpenForSpell then
                ap:OpenForSpell(entry.id, { entry = capturedEntry, rowName = capturedContainer })
            end
        end
    end)

    if sectionRows then
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", function(self)
            local indicator = ensureDropIndicator(parent)
            _dragState = {
                row          = self,
                fromIdx      = idx,
                isRow2       = isRow2,
                container    = capturedContainer,
                sectionRows  = sectionRows,
                indicator    = indicator,
            }
            self:SetAlpha(0.6)
            rowBg:SetColorTexture(Theme.color.accent[1], Theme.color.accent[2], Theme.color.accent[3], 0.25)
            self:SetScript("OnUpdate", function()
                if not _dragState then return end
                local _, cy = GetCursorPosition()
                cy = cy / (self:GetEffectiveScale() or 1)
                local insertPos = computeInsertPos(_dragState, cy)
                moveDropIndicator(_dragState, insertPos)
            end)
        end)
        row:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
            self:SetAlpha(1)
            local state = _dragState
            _dragState = nil
            if state and state.indicator then state.indicator:Hide() end
            if not state then return end
            local _, cy = GetCursorPosition()
            cy = cy / (self:GetEffectiveScale() or 1)
            local insertPos = computeInsertPos(state, cy)
            local n = #state.sectionRows
            local target = insertPosToTarget(insertPos, state.fromIdx)
            if target < 1 then target = 1 end
            if target > n then target = n end
            if target == state.fromIdx then
                rebuildBarLayoutList()
                return
            end
            if state.isRow2 then
                if ns.Bars and ns.Bars.ReorderRow2 then
                    ns.Bars:ReorderRow2(state.container, state.fromIdx, target)
                end
            else
                if ns.Scanner and ns.Scanner.ReorderBar then
                    ns.Scanner:ReorderBar(state.container, state.fromIdx, target)
                end
            end
            rebuildBarLayoutList()
        end)
    end

    return ROW_H
end

local function makeListCheck(C, parent, initial, onToggle)
    local Theme = C.Theme
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(16, 16)
    local bg = C.Rect(btn, "BACKGROUND", Theme.color.input)
    bg:SetAllPoints(btn)
    local border = C.Border(btn, Theme.color.lineSoft)
    local mark = btn:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", btn, "TOPLEFT", 4, -4)
    mark:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -4, 4)
    mark:SetColorTexture(unpack(Theme.color.violet))
    local checked = initial and true or false
    mark:SetShown(checked)
    function btn.GetChecked(self) return checked end
    function btn.SetChecked(self, v)
        checked = v and true or false
        mark:SetShown(checked)
    end
    btn:SetScript("OnClick", function(self)
        checked = not checked
        mark:SetShown(checked)
        if type(onToggle) == "function" then pcall(onToggle, self) end
    end)
    btn:SetScript("OnEnter", function() border.SetColor(unpack(Theme.color.line)) end)
    btn:SetScript("OnLeave", function() border.SetColor(unpack(Theme.color.lineSoft)) end)
    return btn
end

rebuildBarLayoutList = function()
    if not (_barLayoutListFrame and ns.UI) then return end
    local C = ns.UI
    local Theme = C.Theme
    C.ClearChildren(_barLayoutListFrame)

    local capturedContainer = currentRowKey()
    if not capturedContainer then
        _barLayoutListFrame:SetHeight(10)
        relayoutBarSection()
        return
    end

    local displayed1 = {}
    local displayed2 = {}
    local row2enabled = false
    if ns.Bars and ns.Bars.GetCurrentRows then
        local rows = ns.Bars:GetCurrentRows() or {}
        local rowData = rows[capturedContainer]
        if rowData then
            displayed1 = rowData.displayed or {}
            local rp2 = rowData.rows2
            if rp2 then
                row2enabled = rp2.enabled and true or false
                displayed2 = rp2.displayed or {}
            end
        end
    end

    local cbFrame = makeListCheck(C, _barLayoutListFrame, row2enabled, function(self)
        local newVal = self:GetChecked()
        if ns.Bars and ns.Bars.rows then
            local barRow = ns.Bars.rows[capturedContainer]
            if barRow and barRow.SetRow2Enabled then
                barRow:SetRow2Enabled(newVal)
            end
        end
        rebuildBarLayoutList()
    end)
    cbFrame:SetPoint("TOPLEFT", _barLayoutListFrame, "TOPLEFT", 2, -4)
    local cbLabel = C.Text(_barLayoutListFrame, C.Fonts.value, Theme.color.text, "Enable 2nd Row")
    cbLabel:SetPoint("LEFT", cbFrame, "RIGHT", 6, 0)

    local CHECKBOX_H = 24
    local GAP        = 4
    local totalH     = CHECKBOX_H + GAP

    if #displayed1 == 0 and not row2enabled then
        local msg = C.Text(_barLayoutListFrame, C.Fonts.small, Theme.color.textDim,
            "No spells in this bar. Add from the Candidates section above.")
        msg:SetPoint("TOPLEFT", _barLayoutListFrame, "TOPLEFT", 8, -totalH)
        totalH = totalH + 20
        _barLayoutListFrame:SetHeight(math_max(totalH, 30))
        relayoutBarSection()
        return
    end

    local hdr1 = C.Text(_barLayoutListFrame, C.Fonts.small, Theme.color.accent, "ROW 1")
    hdr1:SetPoint("TOPLEFT", _barLayoutListFrame, "TOPLEFT", 4, -totalH)
    totalH = totalH + 14

    if #displayed1 == 0 then
        local emptyLabel = C.Text(_barLayoutListFrame, C.Fonts.small, Theme.color.textFaint,
            "(empty — add from Candidates above)")
        emptyLabel:SetPoint("TOPLEFT", _barLayoutListFrame, "TOPLEFT", 12, -totalH)
        totalH = totalH + 16
    else
        local sectionRows1 = {}
        for idx, entry in ipairs(displayed1) do
            local rowH = buildBarLayoutEntryRow(
                _barLayoutListFrame, entry, idx, #displayed1,
                false, totalH, capturedContainer, sectionRows1)
            totalH = totalH + rowH + 2
        end
    end

    if row2enabled then
        totalH = totalH + 6

        local hdr2 = C.Text(_barLayoutListFrame, C.Fonts.small, Theme.color.violet, "ROW 2")
        hdr2:SetPoint("TOPLEFT", _barLayoutListFrame, "TOPLEFT", 4, -totalH)
        totalH = totalH + 14

        if #displayed2 == 0 then
            local emptyLabel2 = C.Text(_barLayoutListFrame, C.Fonts.small, Theme.color.textFaint,
                "(empty — use R2 buttons in Row 1 to move entries here)")
            emptyLabel2:SetPoint("TOPLEFT", _barLayoutListFrame, "TOPLEFT", 12, -totalH)
            totalH = totalH + 16
        else
            local sectionRows2 = {}
            for idx, entry in ipairs(displayed2) do
                local rowH = buildBarLayoutEntryRow(
                    _barLayoutListFrame, entry, idx, #displayed2,
                    true, totalH, capturedContainer, sectionRows2)
                totalH = totalH + rowH + 2
            end
        end
    end

    _barLayoutListFrame:SetHeight(math_max(totalH, 30))
    relayoutBarSection()
end

ns:RegisterMessage("SCANNER_CANDIDATES_UPDATED", function(_, container)
    if container == _selectedContainer or container == "__spellbook" then
        rebuildCandidateGrid()
        if rebuildBarLayoutList then rebuildBarLayoutList() end
    end
end)

local function getConsumablesProfile()
    if not ns.savedVarsReady then return nil end
    local p = ns:GetProfile()
    p.modules = p.modules or {}
    p.modules.Bars = p.modules.Bars or {}
    local bars = p.modules.Bars
    bars.consumables = bars.consumables or {}
    bars.consumables.enabledPresets = bars.consumables.enabledPresets or {}
    bars.consumables.customItems    = bars.consumables.customItems or {}
    if bars.consumables.showItemCount == nil then bars.consumables.showItemCount = true end
    if bars.consumables.hideIfMissing == nil then bars.consumables.hideIfMissing = true end
    if bars.consumables.showTooltip   == nil then bars.consumables.showTooltip   = true end
    return bars.consumables
end

local function consumablesScanner()
    return ns.Bars and ns.Bars.Scanner and ns.Bars.Scanner.Consumables
end

local function resyncConsumables()
    local sc = consumablesScanner()
    if sc and sc.Sync then sc:Sync() end
    if ns.Bars and ns.Bars.RebuildRow then
        ns.Bars:RebuildRow("Consumables")
    end
end

local _consIconGen = 0
local _consPendingLoads = {}
local _consLoadFrame = nil

local function ensureConsLoadFrame()
    if _consLoadFrame then return _consLoadFrame end
    local f = CreateFrame("Frame")
    f:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    f:SetScript("OnEvent", function(_, _, loadedID)
        local list = _consPendingLoads[loadedID]
        if not list then return end
        _consPendingLoads[loadedID] = nil
        for i = 1, #list do
            local target = list[i]
            if target and target.gen == _consIconGen and type(target.apply) == "function" then
                pcall(target.apply)
            end
        end
    end)
    _consLoadFrame = f
    return f
end

local function consInBagsItemID(itemID, altItemIDs)
    if ns.Bars and ns.Bars.ConsumableDisplayItemID then
        local ok, id = pcall(ns.Bars.ConsumableDisplayItemID, ns.Bars, itemID, altItemIDs)
        if ok and id then return id end
    end
    if C_Item and C_Item.GetItemCount then
        local function count(id)
            local okC, total = pcall(C_Item.GetItemCount, id, false, true)
            if not okC then return 0 end
            if type(issecretvalue) == "function" and issecretvalue(total) then return 0 end
            return (type(total) == "number" and total > 0) and total or 0
        end
        if count(itemID) > 0 then return itemID end
        if type(altItemIDs) == "table" then
            for i = 1, #altItemIDs do
                if count(altItemIDs[i]) > 0 then return altItemIDs[i] end
            end
        end
    end
    return itemID
end

local function resolveConsIconTex(presetIcon, itemID)
    if presetIcon then return presetIcon end
    return getItemIconTex(itemID)
end

local function requestConsItemLoad(itemID, gen, apply)
    if not itemID then return end
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
    ensureConsLoadFrame()
    local list = _consPendingLoads[itemID]
    if not list then
        list = {}
        _consPendingLoads[itemID] = list
    end
    list[#list + 1] = { gen = gen, apply = apply }
end

local function createConsIconButton(parent, def)
    local C = ns.UI
    local Theme = C.Theme
    local SIZE = 36
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(SIZE, SIZE)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local bg = C.Rect(btn, "BACKGROUND", Theme.color.input)
    bg:SetAllPoints(btn)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn._iconTex = icon

    local border = C.Border(btn, Theme.color.lineSoft)

    local sel = {}
    local function selSide()
        local t = btn:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(unpack(Theme.color.accent))
        sel[#sel + 1] = t
        return t
    end
    local selTop, selBot, selLft, selRgt = selSide(), selSide(), selSide(), selSide()
    selTop:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
    selTop:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 1, 1)
    selTop:SetHeight(2)
    selBot:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", -1, -1)
    selBot:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
    selBot:SetHeight(2)
    selLft:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
    selLft:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", -1, -1)
    selLft:SetWidth(2)
    selRgt:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 1, 1)
    selRgt:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
    selRgt:SetWidth(2)
    local function selShown(shown)
        for i = 1, #sel do sel[i]:SetShown(shown) end
    end

    local function applyTexture(tex)
        if tex then
            icon:SetTexture(tex)
        else
            icon:SetColorTexture(0.18, 0.20, 0.28, 1)
        end
    end

    local resolvedID = def.itemID
    if def.altItemIDs then
        resolvedID = consInBagsItemID(def.itemID, def.altItemIDs)
    end
    btn._tooltipItemID = resolvedID or def.itemID

    local tex = resolveConsIconTex(def.icon, resolvedID)
    applyTexture(tex)
    if not tex then
        local capturedID = resolvedID or def.itemID
        local capturedGen = _consIconGen
        requestConsItemLoad(capturedID, capturedGen, function()
            applyTexture(resolveConsIconTex(def.icon, capturedID))
        end)
    end

    local function applyState(on)
        btn._enabled = on and true or false
        if on then
            icon:SetDesaturated(false)
            btn:SetAlpha(1)
            selShown(true)
            border.SetColor(unpack(Theme.color.line))
        else
            icon:SetDesaturated(true)
            btn:SetAlpha(0.4)
            selShown(false)
            border.SetColor(unpack(Theme.color.lineSoft))
        end
    end
    btn._applyState = applyState
    applyState(def.enabled and true or false)

    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if type(def.onClick) == "function" then pcall(def.onClick, self) end
        elseif button == "RightButton" then
            if type(def.onRightClick) == "function" then pcall(def.onRightClick, self) end
        end
    end)

    btn:SetScript("OnEnter", function(self)
        if not self._enabled then
            self:SetAlpha(0.7)
        end
        border.SetColor(unpack(Theme.color.violet))
        local id = self._tooltipItemID
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        local shown = false
        if id then
            shown = pcall(GameTooltip.SetItemByID, GameTooltip, id)
        end
        if not shown then
            GameTooltip:SetText(tostring(def.name or "Item " .. tostring(id or "?")), 1, 1, 1, 1, true)
        end
        if def.hintLine then
            GameTooltip:AddLine(def.hintLine, 0.6, 0.6, 1)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        if self._applyState then self._applyState(self._enabled) end
        GameTooltip:Hide()
    end)

    return btn
end

local function buildConsumablesIconGrid(parent, defs)
    local SIZE = 36
    local GAP  = 5
    local pw = _widthOr(parent, 320)
    local cols = math_max(1, math_floor(pw / (SIZE + GAP)))
    local n = #defs
    for idx = 1, n do
        local def = defs[idx]
        local col = (idx - 1) % cols
        local row = math_floor((idx - 1) / cols)
        local btn = createConsIconButton(parent, def)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT",
            col * (SIZE + GAP),
            -row * (SIZE + GAP))
    end
    local numRows = math_max(1, math_ceil(n / cols))
    return numRows * (SIZE + GAP) - GAP
end

local function buildConsumablesSection(sc, children)
    local C = ns.UI
    local Theme = C.Theme
    local cp = getConsumablesProfile()
    if not cp then return end

    _consIconGen = _consIconGen + 1

    children[#children + 1] = C.CreateSubSection(sc, "Tracked Consumables (click an icon to toggle)")

    local presets = (ns.CONSUMABLE_PRESETS) or {}
    local scanner = consumablesScanner()
    if (not presets or #presets == 0) and scanner and scanner.GetPresets then
        presets = scanner:GetPresets()
    end

    local gridDefs = {}

    for _, pr in ipairs(presets) do
        local capturedKey = pr.key
        local label = pr.name or capturedKey
        if pr.combatLockout then
            label = label .. " (combat-locked)"
        end
        gridDefs[#gridDefs + 1] = {
            icon       = pr.icon,
            itemID     = pr.itemID,
            altItemIDs = pr.altItemIDs,
            name       = label,
            enabled    = cp.enabledPresets[capturedKey] == true,
            hintLine   = "Left-click to toggle tracking",
            onClick    = function(btn)
                local newVal = not (cp.enabledPresets[capturedKey] == true)
                if scanner and scanner.SetPresetEnabled then
                    scanner:SetPresetEnabled(capturedKey, newVal)
                    if ns.Bars and ns.Bars.RebuildRow then
                        ns.Bars:RebuildRow("Consumables")
                    end
                else
                    cp.enabledPresets[capturedKey] = newVal and true or nil
                    resyncConsumables()
                end
                btn._applyState(newVal)
                updateStatusLabel((newVal and "Enabled " or "Disabled ") .. label)
            end,
        }
    end

    local custom = cp.customItems or {}
    local customIDs = {}
    for itemID in pairs(custom) do
        local id = tonumber(itemID)
        if id then customIDs[#customIDs + 1] = id end
    end
    table.sort(customIDs)

    for _, id in ipairs(customIDs) do
        local capturedID = id
        local nameTxt = "Item " .. tostring(capturedID)
        if C_Item and C_Item.GetItemNameByID then
            local okN, nm = pcall(C_Item.GetItemNameByID, capturedID)
            if okN and nm then nameTxt = nm .. " (" .. tostring(capturedID) .. ")" end
        end
        gridDefs[#gridDefs + 1] = {
            itemID       = capturedID,
            name         = nameTxt .. " (custom)",
            enabled      = true,
            hintLine     = "Right-click to remove",
            onRightClick = function()
                local s = consumablesScanner()
                if s and s.RemoveCustomItem then
                    s:RemoveCustomItem(capturedID)
                    updateStatusLabel("Removed item " .. capturedID)
                    rebuildPageDeferred()
                end
            end,
        }
    end

    local gridFrame = CreateFrame("Frame", nil, sc)
    children[#children + 1] = gridFrame
    if #gridDefs == 0 then
        gridFrame:SetHeight(10)
    else
        local h = buildConsumablesIconGrid(gridFrame, gridDefs)
        gridFrame:SetHeight(math_max(h, 36))
    end

    children[#children + 1] = C.CreateSubSection(sc, "Custom Consumables (track any item by ID)")

    local addRow = CreateFrame("Frame", nil, sc)
    addRow:SetHeight(26)
    children[#children + 1] = addRow

    local addLabel = C.Text(addRow, C.Fonts.label, Theme.color.text, "Add by Item ID:")
    addLabel:SetPoint("LEFT", addRow, "LEFT", 0, 0)

    local addEBFrame = CreateFrame("Frame", nil, addRow)
    addEBFrame:SetSize(80, 20)
    addEBFrame:SetPoint("LEFT", addLabel, "RIGHT", 6, 0)
    local addEBBg = C.Rect(addEBFrame, "BACKGROUND", Theme.color.input)
    addEBBg:SetAllPoints(addEBFrame)
    local addEBLine = addEBFrame:CreateTexture(nil, "BORDER")
    addEBLine:SetColorTexture(unpack(Theme.color.lineSoft))
    addEBLine:SetHeight(1)
    addEBLine:SetPoint("BOTTOMLEFT", addEBFrame, "BOTTOMLEFT", 0, 0)
    addEBLine:SetPoint("BOTTOMRIGHT", addEBFrame, "BOTTOMRIGHT", 0, 0)

    local addEB = CreateFrame("EditBox", nil, addEBFrame)
    addEB:SetPoint("TOPLEFT", addEBFrame, "TOPLEFT", 4, 0)
    addEB:SetPoint("BOTTOMRIGHT", addEBFrame, "BOTTOMRIGHT", -4, 1)
    addEB:SetFontObject(C.Fonts.value)
    addEB:SetTextColor(unpack(Theme.color.textBright))
    addEB:SetAutoFocus(false)
    addEB:SetNumeric(true)
    addEB:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    addEB:SetScript("OnEditFocusGained", function()
        addEBLine:SetColorTexture(unpack(Theme.color.accent))
    end)
    addEB:SetScript("OnEditFocusLost", function()
        addEBLine:SetColorTexture(unpack(Theme.color.lineSoft))
    end)

    local addBtn = C.CreateCompactButton(addRow, "Add", nil, 60)
    addBtn:SetHeight(20)
    addBtn:SetPoint("LEFT", addEBFrame, "RIGHT", 4, 0)
    addBtn:SetScript("OnClick", function()
        local id = tonumber(addEB:GetText() or "")
        if not id or id <= 0 then
            updateStatusLabel("Invalid item ID")
            return
        end
        local s = consumablesScanner()
        if s and s.AddCustomItem then
            local ok, err = s:AddCustomItem(id)
            if ok then
                addEB:SetText("")
                updateStatusLabel("Added item " .. id)
                rebuildPageDeferred()
            else
                updateStatusLabel("Add failed: " .. tostring(err))
            end
        end
    end)
    addEB:SetScript("OnEnterPressed", function(self)
        addBtn:Click()
        self:ClearFocus()
    end)

    children[#children + 1] = C.CreateHelpText(sc,
        "Added items appear in the grid above (always tracked). Right-click an item's icon to remove it.")

    children[#children + 1] = C.CreateSubSection(sc, "Display Options")

    children[#children + 1] = C.CreateCheckBox(sc, "Show Item Count",
        function() return cp.showItemCount ~= false end,
        function(v)
            cp.showItemCount = v and true or false
            resyncConsumables()
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Hide If Missing",
        function() return cp.hideIfMissing ~= false end,
        function(v)
            cp.hideIfMissing = v and true or false
            resyncConsumables()
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Show Tooltip On Hover",
        function() return cp.showTooltip ~= false end,
        function(v)
            cp.showTooltip = v and true or false
            resyncConsumables()
        end
    )
end

local function buildScannerPage(sc)
    _sc = sc
    local C = ns.UI
    if not C then return end
    local Theme = C.Theme
    local children = {}
    wipe(_tabBgMap)

    local opts = getOptionsProfile()
    local ui = ns.GetUIState and ns:GetUIState()
    local savedContainer = (ui and ui.lastOptionsSub.cdmbars) or opts.selectedCDMContainer
    if savedContainer then
        for _, cont in ipairs(CONTAINERS) do
            if cont.key == savedContainer then
                _selectedContainer = savedContainer
                break
            end
        end
    end

    children[#children + 1] = C.CreateSection(sc, "CDM Bars")

    children[#children + 1] = C.CreateCheckBox(sc, "Show GCD Swipe",
        function()
            if not ns.savedVarsReady then return true end
            local p = ns:GetProfile()
            local bp = (p.modules and p.modules.Bars) or {}
            return bp.showGCDSwipe ~= false
        end,
        function(v)
            if not ns.savedVarsReady then return end
            local p = ns:GetProfile()
            p.modules = p.modules or {}
            p.modules.Bars = p.modules.Bars or {}
            p.modules.Bars.showGCDSwipe = v
            if ns.Bars and ns.Bars.ApplyGCDSwipe then
                ns.Bars:ApplyGCDSwipe(v)
            end
            updateStatusLabel(v and "GCD swipe enabled" or "GCD swipe disabled")
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Show Duration Swipe",
        function()
            if not ns.savedVarsReady then return true end
            local p = ns:GetProfile()
            local bp = (p.modules and p.modules.Bars) or {}
            return bp.showDurationSwipe ~= false
        end,
        function(v)
            if not ns.savedVarsReady then return end
            local p = ns:GetProfile()
            p.modules = p.modules or {}
            p.modules.Bars = p.modules.Bars or {}
            p.modules.Bars.showDurationSwipe = v
            if ns.Bars and ns.Bars.ApplyDurationSwipe then
                ns.Bars:ApplyDurationSwipe(v)
            end
            updateStatusLabel(v and "Duration swipe enabled" or "Duration swipe disabled")
        end
    )

    local addingLabel = C.Text(sc, C.Fonts.title, Theme.color.accent)
    addingLabel:SetHeight(16)
    addingLabel:SetJustifyH("LEFT")
    _addingToLabel = addingLabel
    children[#children + 1] = addingLabel

    local tabRow = CreateFrame("Frame", nil, sc)
    tabRow:SetHeight(28)
    children[#children + 1] = tabRow

    local prevTab
    for i, cont in ipairs(CONTAINERS) do
        local capturedKey = cont.key
        local tb = C.CreateTabButton(tabRow, cont.label, function()
            selectTab(capturedKey)
            rebuildCandidateGrid()
            rebuildBarLayoutList()
            if not InCombatLockdown() then
                rebuildPageDeferred()
            end
        end)
        if prevTab then
            tb:SetPoint("LEFT", prevTab, "RIGHT", 2, 0)
        else
            tb:SetPoint("LEFT", tabRow, "LEFT", 0, 0)
        end
        prevTab = tb
        tb:SetSelected(cont.key == _selectedContainer)
        _tabBgMap[cont.key] = tb
    end

    if _selectedContainer == "Custom" then
        children[#children + 1] = C.CreateSubSection(sc, "Custom Bars (cooldown tracking)")

        if not _selectedCustomBarID and ui and ui.lastOptionsSub then
            _selectedCustomBarID = tonumber(ui.lastOptionsSub.cdmbarsCustomBar)
        end
        local defs = customBars()
        local selDef = selectedCustomDef()

        if #defs > 0 then
            local items = {}
            for _, d in ipairs(defs) do
                items[#items + 1] = {
                    key   = tostring(d.id),
                    label = tostring(d.name or ("Custom " .. tostring(d.id))),
                }
            end
            children[#children + 1] = C.CreateDropdownLikeList(sc, "Selected Bar", items,
                function()
                    local d = selectedCustomDef()
                    return d and tostring(d.id) or ""
                end,
                function(k)
                    _selectedCustomBarID = tonumber(k)
                    persistCustomBarSelection()
                    rebuildPageDeferred()
                end
            )
        else
            children[#children + 1] = C.CreateHelpText(sc,
                "No custom bars yet. Click 'Create New Bar'. Each bar tracks cooldowns and has its own movable anchor.")
        end

        local mgrRow = CreateFrame("Frame", nil, sc)
        mgrRow:SetHeight(24)
        children[#children + 1] = mgrRow

        local createBtn = C.CreateCompactButton(mgrRow, "Create New Bar", function()
            if not (ns.Bars and ns.Bars.CreateCustomBar) then return end
            local def, err = ns.Bars:CreateCustomBar()
            if def then
                _selectedCustomBarID = tonumber(def.id)
                persistCustomBarSelection()
                updateStatusLabel("Created '" .. tostring(def.name) .. "'")
                rebuildPageDeferred()
            else
                updateStatusLabel("Create failed: " .. tostring(err))
            end
        end, 130)
        createBtn:ClearAllPoints()
        createBtn:SetPoint("LEFT", mgrRow, "LEFT", 0, 0)

        if selDef then
            local armed = false
            local capturedID = tonumber(selDef.id)
            local deleteBtn
            deleteBtn = C.CreateCompactButton(mgrRow, "Delete Bar", function()
                if not armed then
                    armed = true
                    deleteBtn.label:SetText("Confirm Delete?")
                    deleteBtn.label:SetTextColor(unpack(Theme.color.danger))
                    C_Timer.After(4, function()
                        if armed then
                            armed = false
                            deleteBtn.label:SetText("Delete Bar")
                            deleteBtn.label:SetTextColor(unpack(Theme.color.text))
                        end
                    end)
                    return
                end
                armed = false
                if ns.Bars and ns.Bars.DeleteCustomBar then
                    local ok, err = ns.Bars:DeleteCustomBar(capturedID)
                    if ok then
                        _selectedCustomBarID = nil
                        persistCustomBarSelection()
                        updateStatusLabel("Bar deleted")
                        rebuildPageDeferred()
                    else
                        updateStatusLabel("Delete failed: " .. tostring(err))
                    end
                end
            end, 130)
            deleteBtn:SetPoint("LEFT", createBtn, "RIGHT", 8, 0)

            children[#children + 1] = C.CreateEditBox(sc, "Rename Bar",
                function()
                    local d = selectedCustomDef()
                    return d and d.name or ""
                end,
                function(text)
                    local d = selectedCustomDef()
                    if not d then return end
                    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                    if text == "" or text == d.name then return end
                    if ns.Bars and ns.Bars.RenameCustomBar then
                        local ok = ns.Bars:RenameCustomBar(d.id, text)
                        if ok then
                            updateStatusLabel("Renamed to '" .. text .. "'")
                            rebuildPageDeferred()
                        end
                    end
                end
            )
        end
    end

    local statusLabel = C.Text(sc, C.Fonts.small, Theme.color.textDim, "No scan run yet.")
    statusLabel:SetHeight(14)
    statusLabel:SetJustifyH("LEFT")
    _statusLabel = statusLabel
    children[#children + 1] = statusLabel

    local scanBtnRow = CreateFrame("Frame", nil, sc)
    scanBtnRow:SetHeight(24)
    _scanBtnRow = scanBtnRow
    children[#children + 1] = scanBtnRow

    _scanCDMBtn = C.CreateCompactButton(scanBtnRow, "Re-scan Blizzard CDM", function()
        if ns.Scanner and ns.Scanner.ScanCDM then
            ns.Scanner:ScanCDM()
            updateStatusLabel(ns.Scanner:GetLastScanSummary())
        else
            if ns.Debug and ns.Debug.Log then
                ns.Debug:Log("[ScannerPanel] Scanner module not loaded")
            end
        end
    end, 170)

    _scanSpellBookBtn = C.CreateCompactButton(scanBtnRow, "Scan Spell Book", function()
        if ns.Scanner and ns.Scanner.ScanSpellBook then
            ns.Scanner:ScanSpellBook()
            updateStatusLabel(ns.Scanner:GetLastScanSummary())
        else
            if ns.Debug and ns.Debug.Log then
                ns.Debug:Log("[ScannerPanel] Scanner.ScanSpellBook not available")
            end
        end
    end, 170)

    _scanTrinketsBtn = C.CreateCompactButton(scanBtnRow, "Scan Trinkets", function()
        if ns.Scanner and ns.Scanner.ScanTrinkets then
            ns.Scanner:ScanTrinkets()
            updateStatusLabel(ns.Scanner:GetLastScanSummary())
        else
            if ns.Debug and ns.Debug.Log then
                ns.Debug:Log("[ScannerPanel] Scanner.ScanTrinkets not available")
            end
        end
    end, 170)

    updateScanButtons()

    local isConsumables = _selectedContainer == "Consumables"
    local hasEditableBar = (not isConsumables) and currentRowKey() ~= nil
    if not hasEditableBar then
        _candidateListFrame = nil
        _barLayoutListFrame = nil
        _barLayoutHeader    = nil
        _addSpellIDEditBox  = nil
    end

    if isConsumables then
        buildConsumablesSection(sc, children)
    end

    if hasEditableBar then
        children[#children + 1] = C.CreateCheckBox(sc, "Show Known Spells Only",
            function() return _showKnownOnly end,
            function(v)
                _showKnownOnly = v
                rebuildCandidateGrid()
            end
        )

        local addRow = CreateFrame("Frame", nil, sc)
        addRow:SetHeight(26)
        children[#children + 1] = addRow

        local addLabel = C.Text(addRow, C.Fonts.label, Theme.color.text, "Add by Spell ID:")
        addLabel:SetPoint("LEFT", addRow, "LEFT", 0, 0)

        local addEBFrame = CreateFrame("Frame", nil, addRow)
        addEBFrame:SetSize(80, 20)
        addEBFrame:SetPoint("LEFT", addLabel, "RIGHT", 6, 0)
        local addEBBg = C.Rect(addEBFrame, "BACKGROUND", Theme.color.input)
        addEBBg:SetAllPoints(addEBFrame)
        local addEBLine = addEBFrame:CreateTexture(nil, "BORDER")
        addEBLine:SetColorTexture(unpack(Theme.color.lineSoft))
        addEBLine:SetHeight(1)
        addEBLine:SetPoint("BOTTOMLEFT", addEBFrame, "BOTTOMLEFT", 0, 0)
        addEBLine:SetPoint("BOTTOMRIGHT", addEBFrame, "BOTTOMRIGHT", 0, 0)

        local addEB = CreateFrame("EditBox", nil, addEBFrame)
        addEB:SetPoint("TOPLEFT", addEBFrame, "TOPLEFT", 4, 0)
        addEB:SetPoint("BOTTOMRIGHT", addEBFrame, "BOTTOMRIGHT", -4, 1)
        addEB:SetFontObject(C.Fonts.value)
        addEB:SetTextColor(unpack(Theme.color.textBright))
        addEB:SetAutoFocus(false)
        addEB:SetNumeric(true)
        addEB:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        addEB:SetScript("OnEditFocusGained", function()
            addEBLine:SetColorTexture(unpack(Theme.color.accent))
        end)
        addEB:SetScript("OnEditFocusLost", function()
            addEBLine:SetColorTexture(unpack(Theme.color.lineSoft))
        end)
        _addSpellIDEditBox = addEB

        local addBtn = C.CreateCompactButton(addRow, "Add", nil, 60)
        addBtn:SetHeight(20)
        addBtn:SetPoint("LEFT", addEBFrame, "RIGHT", 4, 0)
        addBtn:SetScript("OnClick", function()
            local id = tonumber(addEB:GetText() or "")
            if not id or id <= 0 then
                if ns.Debug and ns.Debug.Log then
                    ns.Debug:Log("[ScannerPanel] Add by ID: invalid spell ID")
                end
                return
            end
            if ns.Scanner and ns.Scanner.ValidateSpellID then
                local result = ns.Scanner:ValidateSpellID(id)
                if not result.valid then
                    if ns.Debug and ns.Debug.Log then
                        ns.Debug:Log("[ScannerPanel] Spell ID %d invalid: %s", id, tostring(result.reason))
                    end
                    updateStatusLabel("Invalid spell ID " .. id .. ": " .. tostring(result.reason))
                    return
                end
            end
            local rowKey = currentRowKey()
            if not rowKey then
                updateStatusLabel("Create a custom bar first (Create New Bar above)")
                return
            end
            local entry = { type = "spell", id = id, source = "custom" }
            if ns.Bars and ns.Bars.AddEntry then
                local ok, err = ns.Bars:AddEntry(rowKey, entry)
                if ok then
                    rebuildBarLayoutList()
                    rebuildCandidateGrid()
                    addEB:SetText("")
                else
                    if ns.Debug and ns.Debug.Log then
                        ns.Debug:Log("[ScannerPanel] AddEntry failed: %s", tostring(err))
                    end
                    updateStatusLabel("Add failed: " .. tostring(err))
                end
            end
        end)
        addEB:SetScript("OnEnterPressed", function(self)
            addBtn:Click()
            self:ClearFocus()
        end)

        children[#children + 1] = C.CreateSubSection(sc, "Candidates (click = add, right-click = settings)")

        local candidateContainer = CreateFrame("Frame", nil, sc)
        candidateContainer:SetHeight(80)
        _candidateListFrame = candidateContainer
        children[#children + 1] = candidateContainer

        local barLayoutHeader = C.CreateSubSection(sc, "Bar Layout (R2 = move row, arrows = reorder, right-click = settings)")
        _barLayoutHeader = barLayoutHeader
        children[#children + 1] = barLayoutHeader

        local barContainer = CreateFrame("Frame", nil, sc)
        barContainer:SetHeight(60)
        _barLayoutListFrame = barContainer
        children[#children + 1] = barContainer
    end

    local totalH = C.LayoutVertical(sc, children, 4, -8)
    sc:SetHeight(math_max(totalH, 10))

    updateAddingToLabel()

    if hasEditableBar then
        rebuildCandidateGrid()
        rebuildBarLayoutList()
    end
end

ns.Options:RegisterPage({
    key   = "cdmbars",
    label = "CDM Bars",
    build = buildScannerPage,
})
