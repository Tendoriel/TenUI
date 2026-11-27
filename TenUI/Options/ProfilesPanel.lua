local addonName, ns = ...

local type     = type
local pairs    = pairs
local tostring = tostring
local tonumber = tonumber
local pcall    = pcall
local math_max = math.max

local PROFILE_SOURCES = {
    content = "Assigned to the current instance type",
    character = "Selected for this character",
    spec = "Assigned to the current specialization",
    shared = "Shared account profile",
    default = "Default profile",
    pending = "Profile change pending",
}

local function makeNameBox(C, parent, placeholderText)
    local Theme = C.Theme
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(160, 20)
    local bg = C.Rect(box, "BACKGROUND", Theme.color.input)
    bg:SetAllPoints(box)
    local line = box:CreateTexture(nil, "BORDER")
    line:SetColorTexture(unpack(Theme.color.lineSoft))
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)

    local eb = CreateFrame("EditBox", nil, box)
    eb:SetPoint("TOPLEFT", box, "TOPLEFT", 4, 0)
    eb:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -4, 1)
    eb:SetFontObject(C.Fonts.value)
    eb:SetTextColor(unpack(Theme.color.textBright))
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(48)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function()
        line:SetColorTexture(unpack(Theme.color.accent))
    end)
    eb:SetScript("OnEditFocusLost", function()
        line:SetColorTexture(unpack(Theme.color.lineSoft))
    end)

    local placeholder = C.Text(box, C.Fonts.value, Theme.color.textFaint, placeholderText)
    placeholder:SetPoint("LEFT", eb, "LEFT", 0, 0)
    placeholder:SetPoint("RIGHT", eb, "RIGHT", 0, 0)
    placeholder:SetJustifyH("LEFT")
    placeholder:SetWordWrap(false)
    eb:SetScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
    end)

    return box, eb
end

local function makeTextArea(C, parent, height)
    local Theme = C.Theme
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(height or 60)
    C.SkinPanel(frame, { color = Theme.color.input })

    local sf = CreateFrame("ScrollFrame", nil, frame)
    sf:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)

    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(0)
    eb:SetFontObject(C.Fonts.value)
    eb:SetTextColor(unpack(Theme.color.textBright))
    eb:SetWidth(300)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sf:SetScrollChild(eb)
    sf:SetScript("OnSizeChanged", function(_, w)
        eb:SetWidth(math.max((w or 0) - 4, 50))
    end)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll() or 0
        local maxV = self:GetVerticalScrollRange() or 0
        local target = cur - delta * 30
        if target < 0 then target = 0 end
        if target > maxV then target = maxV end
        self:SetVerticalScroll(target)
    end)
    eb:SetScript("OnCursorChanged", function(_, _, y, _, h)
        local cur = sf:GetVerticalScroll() or 0
        local visible = sf:GetHeight() or 0
        y = -(y or 0)
        h = h or 0
        if y < cur then
            sf:SetVerticalScroll(y)
        elseif (y + h) > (cur + visible) then
            sf:SetVerticalScroll(y + h - visible)
        end
    end)

    return frame, eb
end

local function buildProfilesPage(sc)
    local C = ns.UI
    if not C then return end
    local Theme = C.Theme
    local children, starts = {}, {}

    local function pickSections(selection, allowed)
        local group = {}
        local actions = CreateFrame("Frame", nil, sc)
        actions:SetHeight(22)
        local function choose(value)
            for id, row in pairs(group) do
                selection[id] = (value and row:IsMouseEnabled()) or nil
                row.Refresh()
            end
        end
        local all = C.CreateCompactButton(actions, "All", function() choose(true) end, 42)
        all:SetPoint("LEFT")
        local clear = C.CreateCompactButton(actions, "None", function() choose(false) end, 50)
        clear:SetPoint("LEFT", all, "RIGHT", 4, 0)
        children[#children+1] = actions
        for _, id in ipairs(ns.ProfileSectionOrder) do
            local key = id
            local row = C.CreateCheckBox(sc, ns.ProfileSections[key].label,
                function() return selection[key] == true end,
                function(value) selection[key] = value or nil end)
            row.layoutKind = "chip"
            group[key] = row
            if allowed then allowed[key] = row end
            children[#children + 1] = row
        end
    end

    local refreshCopyValues
    local rebuildSpecMatrix
    local profileDropdown
    local refreshSelection

    children[#children + 1] = C.CreateSection(sc, "Profiles")

    children[#children + 1] = C.CreateSubSection(sc, "Active Profile")
    children[#children + 1] = C.CreateHelpText(sc,
        "A manually selected profile is shared with new characters. Specialization assignments apply when you change spec.")

    local profileValues = {}
    local function refreshProfileValues()
        for i = #profileValues, 1, -1 do profileValues[i] = nil end
        for _, k in ipairs(ns:ListProfiles()) do
            profileValues[#profileValues + 1] = { key = k, label = k }
        end
        if profileDropdown and profileDropdown.Refresh then
            profileDropdown.Refresh()
        end
    end
    refreshProfileValues()

    profileDropdown = C.CreateDropdownLikeList(sc, "Profile",
        profileValues,
        function() return ns:GetProfileKey() end,
        function(k)
            if InCombatLockdown() then
                if ns.Debug and ns.Debug.Log then
                    ns.Debug:Log("[ProfilesPanel] Cannot switch profile in combat")
                end
                return
            end
            if ns:SetActiveProfile(k) then refreshSelection() end
        end
    )
    children[#children + 1] = profileDropdown

    local source = C.CreateHelpText(sc)
    children[#children + 1] = source
    refreshSelection = function()
        profileDropdown.Refresh()
        source.text:SetText(PROFILE_SOURCES[ns:GetActiveProfileSource()] or "")
        source.AutoHeight()
    end
    sc._refreshProfileSelection = refreshSelection
    sc:SetScript("OnShow", refreshSelection)
    refreshSelection()

    local activeActionsRow = CreateFrame("Frame", nil, sc)
    activeActionsRow:SetHeight(24)
    children[#children + 1] = activeActionsRow

    local newProfileRow = CreateFrame("Frame", nil, sc)
    newProfileRow:SetHeight(24)
    children[#children + 1] = newProfileRow

    local newNameBox, newNameEB = makeNameBox(C, newProfileRow, "New profile name...")
    newNameBox:SetPoint("LEFT", newProfileRow, "LEFT", 0, 0)

    local function doCreateProfile()
        if InCombatLockdown() then return end
        local name = (newNameEB:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then return end
        if ns.db then
            ns.db.profiles = ns.db.profiles or {}
            if not ns.db.profiles[name] then
                ns.db.profiles[name] = { modules = {} }
                ns:_AddProfileToOrder(name)
                ns:SetActiveProfile(name)
                newNameEB:SetText("")
                if ns.Options and ns.Options.RebuildPage then
                    ns.Options:RebuildPage("profiles")
                end
            end
        end
    end
    newNameEB:SetScript("OnEnterPressed", function(self) doCreateProfile() self:ClearFocus() end)

    local createBtn = C.CreateCompactButton(newProfileRow, "Create", doCreateProfile, 80)
    createBtn:SetPoint("RIGHT", newProfileRow, "RIGHT", 0, 0)
    newNameBox:SetPoint("RIGHT", createBtn, "LEFT", -8, 0)

    local function doDeleteProfile()
        if InCombatLockdown() then return end
        if StaticPopupDialogs and not StaticPopupDialogs["TENUI_DELETE_PROFILE"] then
            StaticPopupDialogs["TENUI_DELETE_PROFILE"] = {
                text = "Delete profile '%s'? This cannot be undone.",
                button1 = "Delete",
                button2 = "Cancel",
                OnAccept = function(_, key)
                    if InCombatLockdown() or key ~= ns:GetProfileKey() then return end
                    if key == "Default" then
                        if ns.Debug and ns.Debug.Log then
                            ns.Debug:Log("[ProfilesPanel] Cannot delete Default profile")
                        end
                        return
                    end
                    ns:DeleteProfile(key)
                    if ns.Options and ns.Options.RebuildPage then
                        ns.Options:RebuildPage("profiles")
                    end
                end,
                timeout = 0,
                whileDead = false,
                hideOnEscape = true,
            }
        end
        if StaticPopup_Show then
            local key = ns:GetProfileKey()
            StaticPopup_Show("TENUI_DELETE_PROFILE", key, nil, key)
        end
    end

    local deleteBtn = C.CreateCompactButton(activeActionsRow, "Delete", doDeleteProfile, 80)
    deleteBtn:SetPoint("LEFT", activeActionsRow, "LEFT", 0, 0)

    local function doResetProfile()
        if InCombatLockdown() then return end
        if StaticPopupDialogs and not StaticPopupDialogs["TENUI_RESET_PROFILE2"] then
            StaticPopupDialogs["TENUI_RESET_PROFILE2"] = {
                text = "Reset current profile to defaults?",
                button1 = "Reset",
                button2 = "Cancel",
                OnAccept = function(_, key)
                    if InCombatLockdown() or key ~= ns:GetProfileKey() then return end
                    if ns.db and ns.db.profiles then
                        ns:BackupProfile()
                        local profile = { modules = {} }
                        ns.db.profiles[key] = profile
                        ns:PrepareProfile(profile)
                        ns:Fire("PROFILE_CHANGED", key)
                    end
                end,
                timeout = 0,
                whileDead = false,
                hideOnEscape = true,
            }
        end
        if StaticPopup_Show then
            StaticPopup_Show("TENUI_RESET_PROFILE2", nil, nil, ns:GetProfileKey())
        end
    end

    local resetBtn = C.CreateCompactButton(activeActionsRow, "Reset", doResetProfile, 80)
    resetBtn:SetPoint("LEFT", deleteBtn, "RIGHT", 4, 0)

    local fullCopyRow = CreateFrame("Frame", nil, sc)
    fullCopyRow:SetHeight(24)
    children[#children + 1] = fullCopyRow

    local fullCopyBox, fullCopyEB = makeNameBox(C, fullCopyRow, "New profile name...")
    fullCopyBox:SetPoint("LEFT", fullCopyRow, "LEFT", 0, 0)

    local fullCopyStatus = C.Text(sc, C.Fonts.value, Theme.color.textDim, "")
    fullCopyStatus:SetWordWrap(true)
    fullCopyStatus:SetHeight(18)
    fullCopyStatus:SetJustifyH("LEFT")

    local function doFullCopy()
        if InCombatLockdown() then
            fullCopyStatus:SetTextColor(unpack(Theme.color.danger))
            fullCopyStatus:SetText("Cannot copy in combat.")
            return
        end
        local src = ns:GetProfileKey()
        local newName = (fullCopyEB:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local ok, result = ns:CopyProfile(src, newName)
        if ok then
            fullCopyStatus:SetTextColor(0.3, 1, 0.3, 1)
            fullCopyStatus:SetText(("Created '%s' as a full copy of '%s'."):format(tostring(result), src))
            fullCopyEB:SetText("")
            if ns.Options and ns.Options.RebuildPage then
                ns.Options:RebuildPage("profiles")
            end
        else
            fullCopyStatus:SetTextColor(unpack(Theme.color.danger))
            fullCopyStatus:SetText("Copy failed: " .. tostring(result))
        end
    end
    fullCopyEB:SetScript("OnEnterPressed", function(self) doFullCopy() self:ClearFocus() end)

    local fullCopyBtn = C.CreateCompactButton(fullCopyRow, "Duplicate Active", doFullCopy, 124)
    fullCopyBtn:SetPoint("RIGHT", fullCopyRow, "RIGHT", 0, 0)
    fullCopyBox:SetPoint("RIGHT", fullCopyBtn, "LEFT", -8, 0)

    children[#children + 1] = fullCopyStatus

    if ns._lastProfileBackup and ns._lastProfileBackup.name == ns:GetProfileKey() then
        children[#children + 1] = C.CreateButton(sc, "Undo Last Change to This Profile", function() ns:UndoProfileChange() end)
    end

    local function doRename()
        if InCombatLockdown() then
            fullCopyStatus:SetTextColor(unpack(Theme.color.danger))
            fullCopyStatus:SetText("Cannot rename in combat.")
            return
        end
        local newName = (fullCopyEB:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local oldName = ns:GetProfileKey()
        local ok, result = ns:RenameProfile(oldName, newName)
        if ok then
            fullCopyStatus:SetTextColor(0.3, 1, 0.3, 1)
            fullCopyStatus:SetText(("Renamed to '%s'."):format(tostring(result)))
            fullCopyEB:SetText("")
            if ns.Options and ns.Options.RebuildPage then
                ns.Options:RebuildPage("profiles")
            end
        else
            fullCopyStatus:SetTextColor(unpack(Theme.color.danger))
            fullCopyStatus:SetText("Rename failed: " .. tostring(result))
        end
    end
    local renameBtn = C.CreateCompactButton(fullCopyRow, "Rename", doRename, 80)
    renameBtn:SetPoint("RIGHT", fullCopyRow, "RIGHT", 0, 0)
    fullCopyBtn:ClearAllPoints()
    fullCopyBtn:SetPoint("RIGHT", renameBtn, "LEFT", -4, 0)

    starts[#children+1] = "Copy & Specs"
    children[#children + 1] = C.CreateSubSection(sc, "Copy From Another Profile")

    local copyValues = {}
    local copyFromDropdown
    refreshCopyValues = function()
        for i = #copyValues, 1, -1 do copyValues[i] = nil end
        for _, k in ipairs(ns:ListProfiles()) do
            if k ~= ns:GetProfileKey() then
                copyValues[#copyValues + 1] = { key = k, label = k }
            end
        end
        if copyFromDropdown and copyFromDropdown.Refresh then
            copyFromDropdown.Refresh()
        end
    end
    refreshCopyValues()

    local _selectedCopyFrom = nil

    local copySelection = {positions = true}

    copyFromDropdown = C.CreateDropdownLikeList(sc, "Source Profile",
        copyValues,
        function() return _selectedCopyFrom end,
        function(k) _selectedCopyFrom = k end
    )
    children[#children + 1] = copyFromDropdown

    pickSections(copySelection)
    children[#children + 1] = C.CreateButton(sc, "Copy Selected to Current Profile", function()
        if _selectedCopyFrom then ns:ApplyProfileSections(ns.db.profiles[_selectedCopyFrom], copySelection) end
    end)

    starts[#children+1] = "Manage"
    children[#children + 1] = C.CreateSubSection(sc, "Spec Profile Swap")

    children[#children + 1] = C.CreateHelpText(sc,
        "Assign a profile to each specialization. Switching spec automatically activates the assigned profile (out of combat).")

    local clearValueKey = "__NONE__"

    local function buildSpecRowValues()
        local vals = { { key = clearValueKey, label = "(none)" } }
        for _, k in ipairs(ns:ListProfiles()) do
            vals[#vals + 1] = { key = k, label = k }
        end
        return vals
    end

    local function getPlayerClassID()
        local _, _, classID = UnitClass("player")
        return classID
    end

    local function getNumSpecs(classID)
        if C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID then
            return C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
        end
        return 0
    end

    local specMatrixContainer = CreateFrame("Frame", nil, sc)
    specMatrixContainer:SetHeight(1)
    children[#children + 1] = specMatrixContainer

    rebuildSpecMatrix = function()
        if C and C.ClearChildren then
            pcall(C.ClearChildren, specMatrixContainer)
        end
        local rows = {}
        local classID = getPlayerClassID()
        local numSpecs = classID and getNumSpecs(classID) or 0
        if not classID or numSpecs == 0 then
            local note = C.CreateHelpText(specMatrixContainer,
                "Specialization information is not available yet.")
            rows[#rows + 1] = note
        else
            for specIndex = 1, numSpecs do
                local specID, specName = GetSpecializationInfoForClassID(classID, specIndex)
                if specID and specID > 0 then
                    local capturedSpecID = specID
                    local label = specName or ("Spec " .. tostring(specIndex))
                    local rowFrame = CreateFrame("Frame", nil, specMatrixContainer)
                    rowFrame:SetHeight(24)

                    local dd = C.CreateDropdownLikeList(rowFrame, label,
                        buildSpecRowValues(),
                        function()
                            return ns:GetSpecProfile(capturedSpecID) or clearValueKey
                        end,
                        function(k)
                            if not ns.savedVarsReady then return end
                            if k == clearValueKey then
                                ns:UnassignSpec(capturedSpecID)
                                if ns.Debug and ns.Debug.Log then
                                    ns.Debug:Log("[ProfilesPanel] spec %d cleared", capturedSpecID)
                                end
                            else
                                ns:AssignProfileToSpec(k, capturedSpecID)
                                if ns.Debug and ns.Debug.Log then
                                    ns.Debug:Log("[ProfilesPanel] spec %d -> '%s'", capturedSpecID, tostring(k))
                                end
                            end
                        end
                    )
                    dd:ClearAllPoints()
                    dd:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 0, 0)
                    dd:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", 0, 0)
                    rows[#rows + 1] = rowFrame
                end
            end
        end
        local h = C.LayoutVertical(specMatrixContainer, rows, 4, 0)
        specMatrixContainer:SetHeight(math_max(h, 1))
    end
    rebuildSpecMatrix()

    children[#children + 1] = C.CreateSubSection(sc, "Content Auto-Switch")
    for _, rule in ipairs({{"none","Outside instances"}, {"raid","Raid"}, {"party","Dungeon / Mythic+"}, {"arena","Arena"}, {"pvp","Battleground"}}) do
        local kind = rule[1]
        children[#children + 1] = C.CreateDropdownLikeList(sc, rule[2], buildSpecRowValues(),
            function() return (ns.db.contentProfiles or {})[kind] or clearValueKey end,
            function(k)
                ns.db.contentProfiles = ns.db.contentProfiles or {}
                ns.db.contentProfiles[kind] = k ~= clearValueKey and k or nil
                ns._manualContent = nil
                ns:Fire("CONTENT_PROFILE_CHANGED")
            end)
    end
    starts[#children+1] = "Copy & Specs"
    children[#children + 1] = C.CreateSubSection(sc, "Specialization Overrides")
    local overrides = {}
    for key in pairs(ns:GetProfile().specScopes or {}) do overrides[#overrides+1] = {key=key, label=key} end
    table.sort(overrides, function(a,b) return a.key < b.key end)
    if #overrides > 0 then
        local selected = overrides[1].key
        children[#children + 1] = C.CreateDropdownLikeList(sc, "Saved specialization", overrides, function() return selected end, function(k) selected = k end)
        local function changeScope(reset)
            if InCombatLockdown() then return end
            local scopes = ns:GetProfile().specScopes
            local current = ns:GetSpecScopeKey()
            if not scopes[selected] or (not reset and (selected == current or current:match("_NIL$"))) then return end
            ns:BackupProfile()
            if reset then scopes[selected] = nil else scopes[current] = CopyTable(scopes[selected]) end
            ns:Fire("PROFILE_CHANGED", ns:GetProfileKey())
        end
        children[#children + 1] = C.CreateButton(sc, "Copy Overrides to Current Specialization", function() changeScope(false) end)
        children[#children + 1] = C.CreateButton(sc, "Reset Selected Specialization Overrides", function() changeScope(true) end)
    else
        children[#children + 1] = C.CreateHelpText(sc, "This profile uses shared settings for every specialization.")
    end

    starts[#children+1] = "Import / Export"
    children[#children + 1] = C.CreateSubSection(sc, "Export")
    local fullExport, exportSelection = true, {}
    local exportRows = {}
    local function updateExportRows()
        for _, row in pairs(exportRows) do row:SetAlpha(fullExport and 0.45 or 1) row:EnableMouse(not fullExport) end
    end
    children[#children + 1] = C.CreateCheckBox(sc, "Export full profile", function() return fullExport end,
        function(v) fullExport = v updateExportRows() end)
    pickSections(exportSelection, exportRows)
    updateExportRows()

    local exportEBFrame, exportEB = makeTextArea(C, sc, 60)
    exportEB:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    exportEB:SetScript("OnChar", function(self) self:SetText(self._exportText or "") self:HighlightText() end)
    children[#children + 1] = exportEBFrame

    children[#children + 1] = C.CreateButton(sc, "Generate Export", function()
        local str, err = ns:ExportProfileString(fullExport and "all" or exportSelection)
        exportEB._exportText = str or ""
        exportEB:SetText(str or ("Error: " .. tostring(err)))
        if str then
            exportEB:SetFocus()
            exportEB:HighlightText()
        end
    end)

    children[#children + 1] = C.CreateSubSection(sc, "Import")

    children[#children + 1] = C.CreateHelpText(sc,
        "Paste a profile string to review its sections. Choose the sections to apply here, or create a separate profile.")

    local importEBFrame, importEB = makeTextArea(C, sc, 60)
    children[#children + 1] = importEBFrame

    local importNameRow = CreateFrame("Frame", nil, sc)
    importNameRow:SetHeight(24)
    children[#children + 1] = importNameRow

    local importNameBox, importNameEB = makeNameBox(C, importNameRow, "New profile name (blank = auto)...")
    importNameBox:SetPoint("LEFT", importNameRow, "LEFT", 0, 0)

    local importStatus = C.Text(sc, C.Fonts.value, Theme.color.textDim, "")
    importStatus:SetWordWrap(true)
    importStatus:SetHeight(22)
    importStatus:SetJustifyH("LEFT")

    local function setImportStatus(ok, msg)
        if ok then
            importStatus:SetTextColor(0.3, 1, 0.3, 1)
        else
            importStatus:SetTextColor(unpack(Theme.color.danger))
        end
        importStatus:SetText(tostring(msg or ""))
    end

    local review, metadata, chosen = nil, nil, {}
    local importRows = {}
    pickSections(chosen, importRows)
    local function reviewInput()
        local err
        review, err, metadata = ns:DeserializeProfileString(importEB:GetText())
        local labels, scopes = {}, {}
        for _, key in ipairs(ns.ProfileSectionOrder) do
            local available = review and (metadata.sections.all or metadata.sections[key])
            chosen[key] = available or nil
            local row = importRows[key]
            local changed = available and ns:ProfileSectionDiffers(review, key)
            row.label:SetText(ns.ProfileSections[key].label .. (changed and " *" or ""))
            row:SetAlpha(available and 1 or 0.45)
            row:EnableMouse(available and true or false)
            row.Refresh()
            if available then labels[#labels+1] = ns.ProfileSections[key].label end
        end
        for key in pairs(review and review.specScopes or {}) do scopes[#scopes+1] = key end
        table.sort(scopes)
        local message = review and ("TenUI " .. metadata.version .. " · " .. table.concat(labels, ", ")
            .. (#scopes > 0 and (" · " .. table.concat(scopes, ", ")) or "")) or err
        if review then message = message .. " · * differs from your active profile. Applying replaces checked sections." end
        setImportStatus(review ~= nil, importEB:GetText() ~= "" and message or "")
        importStatus:SetHeight(math.max(22, importStatus:GetStringHeight() + 6))
    end
    importEB:SetScript("OnTextChanged", reviewInput)
    reviewInput()
    children[#children + 1] = C.CreateButton(sc, "Apply Selected Sections to Active Profile", function()
        if review and not ns:ApplyProfileSections(review, chosen) then setImportStatus(false, "Choose a section and leave combat to apply.") end
    end)
    local inherit = false
    children[#children + 1] = C.CreateCheckBox(sc, "Use current settings for omitted sections when creating a profile",
        function() return inherit end, function(v) inherit = v end)
    local function doImport()
        local ok, result = ns:ImportProfile(importEB:GetText(), importNameEB:GetText(), inherit, chosen)
        if not ok then setImportStatus(false, result) return end
        refreshProfileValues()
        refreshCopyValues()
        rebuildSpecMatrix()
        setImportStatus(true, "Created profile: " .. result)
    end

    local importBtn = C.CreateCompactButton(importNameRow, "Create as New", doImport, 80)
    importBtn:SetPoint("RIGHT", importNameRow, "RIGHT", 0, 0)
    importNameBox:SetPoint("RIGHT", importBtn, "LEFT", -8, 0)

    children[#children + 1] = importStatus

    ns.Options:ClearPinnedHeader("profiles")
    local byControl = {}
    for index, name in pairs(starts) do if children[index] then byControl[children[index]] = name end end
    ns.Options:LayoutSettingsTabs("profiles", sc, children, {"Manage", "Import / Export", "Copy & Specs"}, byControl)
end

ns.Options:RegisterPage({
    key   = "profiles",
    label = "Profiles",
    build = buildProfilesPage,
    refresh = function(sc)
        if sc._refreshProfileSelection then sc._refreshProfileSelection() end
    end,
})

local function refreshOpenProfiles()
    if ns.Options:GetCurrentPage() == "profiles" then ns.Options:Refresh() end
end
ns:RegisterMessage("PROFILE_CHANGED", refreshOpenProfiles)
ns:RegisterMessage("SPEC_PROFILE_ASSIGNMENT_CHANGED", refreshOpenProfiles)
