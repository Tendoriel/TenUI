local addonName, ns = ...

local type     = type
local pairs    = pairs
local tostring = tostring
local tonumber = tonumber
local pcall    = pcall
local math_max = math.max

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
    local children = {}

    local refreshCopyValues
    local rebuildSpecMatrix
    local profileDropdown

    if ns.savedVarsReady and ns.db and not InCombatLockdown() then
        local specIdx = GetSpecialization and GetSpecialization() or 0
        local specID = specIdx and specIdx > 0 and GetSpecializationInfo and GetSpecializationInfo(specIdx) or nil
        if type(specID) == "number" and specID > 0 then
            local ck = ns.GetCharKey and ns:GetCharKey()
            if ck then
                ns.db.lastSpecByChar = ns.db.lastSpecByChar or {}
                ns.db.lastSpecByChar[ck] = specID
            end
            local assigned = ns:GetSpecProfile(specID)
            if assigned and assigned ~= ns:GetProfileKey()
               and ns.db.profiles and ns.db.profiles[assigned] then
                ns:SetActiveProfile(assigned)
            end
        end
    end

    children[#children + 1] = C.CreateSection(sc, "Profiles")

    children[#children + 1] = C.CreateSubSection(sc, "Active Profile")

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
            if ns.db then
                ns.db.activeProfile = k
                ns:Fire("PROFILE_CHANGED", k)
            end
        end
    )
    children[#children + 1] = profileDropdown

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
                ns.db.activeProfile = name
                ns:Fire("PROFILE_CHANGED", name)
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
                OnAccept = function()
                    local key = ns:GetProfileKey()
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
            StaticPopup_Show("TENUI_DELETE_PROFILE", ns:GetProfileKey())
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
                OnAccept = function()
                    local key = ns:GetProfileKey()
                    if ns.db and ns.db.profiles then
                        ns.db.profiles[key] = { modules = {} }
                        ns:Fire("PROFILE_CHANGED", key)
                    end
                end,
                timeout = 0,
                whileDead = false,
                hideOnEscape = true,
            }
        end
        if StaticPopup_Show then
            StaticPopup_Show("TENUI_RESET_PROFILE2")
        end
    end

    local resetBtn = C.CreateCompactButton(activeActionsRow, "Reset", doResetProfile, 80)
    resetBtn:SetPoint("LEFT", deleteBtn, "RIGHT", 4, 0)

    children[#children + 1] = C.CreateSubSection(sc, "Rename Active Profile")

    local renameRow = CreateFrame("Frame", nil, sc)
    renameRow:SetHeight(24)
    children[#children + 1] = renameRow

    local renameBox, renameEB = makeNameBox(C, renameRow, "New name for active profile...")
    renameBox:SetPoint("LEFT", renameRow, "LEFT", 0, 0)

    local renameStatus = C.Text(sc, C.Fonts.value, Theme.color.textDim, "")
    renameStatus:SetWordWrap(true)
    renameStatus:SetHeight(18)
    renameStatus:SetJustifyH("LEFT")

    local function doRename()
        if InCombatLockdown() then
            renameStatus:SetTextColor(unpack(Theme.color.danger))
            renameStatus:SetText("Cannot rename in combat.")
            return
        end
        local newName = (renameEB:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local oldName = ns:GetProfileKey()
        local ok, result = ns:RenameProfile(oldName, newName)
        if ok then
            renameStatus:SetTextColor(0.3, 1, 0.3, 1)
            renameStatus:SetText(("Renamed to '%s'."):format(tostring(result)))
            renameEB:SetText("")
            if ns.Options and ns.Options.RebuildPage then
                ns.Options:RebuildPage("profiles")
            end
        else
            renameStatus:SetTextColor(unpack(Theme.color.danger))
            renameStatus:SetText("Rename failed: " .. tostring(result))
        end
    end
    renameEB:SetScript("OnEnterPressed", function(self) doRename() self:ClearFocus() end)

    local renameBtn = C.CreateCompactButton(renameRow, "Rename", doRename, 80)
    renameBtn:SetPoint("RIGHT", renameRow, "RIGHT", 0, 0)
    renameBox:SetPoint("RIGHT", renameBtn, "LEFT", -8, 0)

    children[#children + 1] = renameStatus

    children[#children + 1] = C.CreateSubSection(sc, "Copy Positions From")

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

    local function doCopyPositions()
        if InCombatLockdown() then return end
        if not _selectedCopyFrom then return end
        if not ns.db or not ns.db.profiles then return end
        local src = ns.db.profiles[_selectedCopyFrom]
        if not src then return end
        local dst = ns:GetProfile()
        if src.anchors then
            local function deepCopy(t)
                if type(t) ~= "table" then return t end
                local o = {}
                for k, v in pairs(t) do o[k] = deepCopy(v) end
                return o
            end
            dst.anchors = deepCopy(src.anchors)
            ns:Fire("PROFILE_CHANGED", ns:GetProfileKey())
            if ns.Debug and ns.Debug.Log then
                ns.Debug:Log("[ProfilesPanel] Anchor positions copied from '%s'", _selectedCopyFrom)
            end
        end
    end

    copyFromDropdown = C.CreateDropdownLikeList(sc, "Source Profile",
        copyValues,
        function() return _selectedCopyFrom end,
        function(k) _selectedCopyFrom = k end
    )
    children[#children + 1] = copyFromDropdown

    children[#children + 1] = C.CreateButton(sc, "Copy Positions to Current Profile", doCopyPositions)

    children[#children + 1] = C.CreateHelpText(sc,
        "Copies only frame positions into the current profile. All other settings stay untouched.")

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
        local src = _selectedCopyFrom or ns:GetProfileKey()
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

    local fullCopyBtn = C.CreateCompactButton(fullCopyRow, "Copy All", doFullCopy, 80)
    fullCopyBtn:SetPoint("RIGHT", fullCopyRow, "RIGHT", 0, 0)
    fullCopyBox:SetPoint("RIGHT", fullCopyBtn, "LEFT", -8, 0)

    children[#children + 1] = fullCopyStatus

    children[#children + 1] = C.CreateHelpText(sc,
        "Creates a brand-new profile that is a complete copy of the selected source profile (or the active profile when none is selected).")

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

    children[#children + 1] = C.CreateSubSection(sc, "Export")

    children[#children + 1] = C.CreateHelpText(sc,
        "Exports the active profile as text. Click the box, then Ctrl+A / Ctrl+C to copy.")

    local exportEBFrame, exportEB = makeTextArea(C, sc, 60)
    exportEB:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    exportEB:SetScript("OnChar", function(self) self:SetText(self._exportText or "") self:HighlightText() end)
    children[#children + 1] = exportEBFrame

    children[#children + 1] = C.CreateButton(sc, "Export Active Profile", function()
        local str, err = ns:ExportProfileString()
        exportEB._exportText = str or ""
        exportEB:SetText(str or ("Error: " .. tostring(err)))
        if str then
            exportEB:SetFocus()
            exportEB:HighlightText()
        end
    end)

    children[#children + 1] = C.CreateSubSection(sc, "Import")

    children[#children + 1] = C.CreateHelpText(sc,
        "Paste an export string, optionally name the new profile, then click Import. Existing profiles are never overwritten.")

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

    local function doImport()
        local str = importEB:GetText() or ""
        local name = importNameEB:GetText() or ""
        local ok, result = ns:ImportProfile(str, name)
        if not ok then
            setImportStatus(false, "Import failed: " .. tostring(result))
            return
        end
        refreshProfileValues()
        if refreshCopyValues then refreshCopyValues() end
        if rebuildSpecMatrix then rebuildSpecMatrix() end
        if InCombatLockdown() then
            setImportStatus(true, ("Imported as '%s'. In combat -- switch to it after combat ends."):format(result))
        elseif ns:SetActiveProfile(result) then
            setImportStatus(true, ("Imported and activated profile '%s'."):format(result))
        else
            setImportStatus(true, ("Imported as '%s'. Select it in the Active Profile dropdown to activate."):format(result))
        end
        importEB:SetText("")
        importNameEB:SetText("")
    end

    local importBtn = C.CreateCompactButton(importNameRow, "Import", doImport, 80)
    importBtn:SetPoint("RIGHT", importNameRow, "RIGHT", 0, 0)
    importNameBox:SetPoint("RIGHT", importBtn, "LEFT", -8, 0)

    children[#children + 1] = importStatus

    local totalH = C.LayoutVertical(sc, children, 4, -8)
    sc:SetHeight(math_max(totalH, 10))
end

ns.Options:RegisterPage({
    key   = "profiles",
    label = "Profiles",
    build = buildProfilesPage,
})
