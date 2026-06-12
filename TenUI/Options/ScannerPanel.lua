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

local function buildBarLayoutEntryRow(parent, entry, idx, totalCount,
                                      isRow2, totalH, capturedContainer)
    local C = ns.UI
    local Theme = C.Theme
    local ROW_H = 26
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, -totalH)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -totalH)
    row:SetHeight(ROW_H)
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
                ap:OpenForSpell(entry.id)
            end
        end
    end)
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
        for idx, entry in ipairs(displayed1) do
            local rowH = buildBarLayoutEntryRow(
                _barLayoutListFrame, entry, idx, #displayed1,
                false, totalH, capturedContainer)
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
            for idx, entry in ipairs(displayed2) do
                local rowH = buildBarLayoutEntryRow(
                    _barLayoutListFrame, entry, idx, #displayed2,
                    true, totalH, capturedContainer)
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

    local hasEditableBar = currentRowKey() ~= nil
    if not hasEditableBar then
        _candidateListFrame = nil
        _barLayoutListFrame = nil
        _barLayoutHeader    = nil
        _addSpellIDEditBox  = nil
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
