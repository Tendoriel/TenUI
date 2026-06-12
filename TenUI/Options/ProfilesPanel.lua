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

    children[#children + 1] = C.CreateSection(sc, "Profiles")

    children[#children + 1] = C.CreateSubSection(sc, "Active Profile")

    local profileValues = {}
    local function refreshProfileValues()
        for i = #profileValues, 1, -1 do profileValues[i] = nil end
        for _, k in ipairs(ns:ListProfiles()) do
            profileValues[#profileValues + 1] = { key = k, label = k }
        end
    end
    refreshProfileValues()

    children[#children + 1] = C.CreateDropdownLikeList(sc, "Profile",
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
                ns.db.activeProfile = name
                ns:Fire("PROFILE_CHANGED", name)
                refreshProfileValues()
                newNameEB:SetText("")
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
                    if ns.db and ns.db.profiles then
                        ns.db.profiles[key] = nil
                        ns.db.activeProfile = "Default"
                        ns.db.profiles["Default"] = ns.db.profiles["Default"] or { modules = {} }
                        ns:Fire("PROFILE_CHANGED", "Default")
                        refreshProfileValues()
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

    children[#children + 1] = C.CreateSubSection(sc, "Copy Positions From")

    local copyValues = {}
    local function refreshCopyValues()
        for i = #copyValues, 1, -1 do copyValues[i] = nil end
        for _, k in ipairs(ns:ListProfiles()) do
            if k ~= ns:GetProfileKey() then
                copyValues[#copyValues + 1] = { key = k, label = k }
            end
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

    local copyRow = C.CreateDropdownLikeList(sc, "Source Profile",
        copyValues,
        function() return _selectedCopyFrom end,
        function(k) _selectedCopyFrom = k end
    )
    children[#children + 1] = copyRow

    children[#children + 1] = C.CreateButton(sc, "Copy Positions to Current Profile", doCopyPositions)

    children[#children + 1] = C.CreateHelpText(sc,
        "Copies only frame positions. All other settings stay untouched.")

    children[#children + 1] = C.CreateSubSection(sc, "Spec Profile Swap")

    children[#children + 1] = C.CreateCheckBox(sc, "Enable Spec-Based Profile Swap",
        function()
            if not ns.savedVarsReady then return false end
            local p = ns:GetProfile()
            return p.modules and p.modules.Profiles and p.modules.Profiles.specSwap and
                   p.modules.Profiles.specSwap.enabled == true
        end,
        function(v)
            if not ns.savedVarsReady then return end
            local p = ns:GetProfile()
            p.modules = p.modules or {}
            p.modules.Profiles = p.modules.Profiles or {}
            p.modules.Profiles.specSwap = p.modules.Profiles.specSwap or { enabled = false, assignments = {} }
            p.modules.Profiles.specSwap.enabled = v
        end
    )

    children[#children + 1] = C.CreateHelpText(sc,
        "Switching spec automatically activates the profile assigned to that spec.")

    local specText = C.Text(sc, C.Fonts.value, Theme.color.text)
    local function updateSpecText()
        local classToken = select(2, UnitClass("player")) or "?"
        local specIdx = GetSpecialization and GetSpecialization() or "?"
        specText:SetText("Current: " .. tostring(classToken) .. " spec " .. tostring(specIdx))
    end
    updateSpecText()
    children[#children + 1] = specText

    local specActionsRow = CreateFrame("Frame", nil, sc)
    specActionsRow:SetHeight(24)
    children[#children + 1] = specActionsRow

    local assignBtn = C.CreateCompactButton(specActionsRow, "Assign", function()
        if not ns.savedVarsReady then return end
        local p = ns:GetProfile()
        p.modules = p.modules or {}
        p.modules.Profiles = p.modules.Profiles or {}
        p.modules.Profiles.specSwap = p.modules.Profiles.specSwap or { enabled = false, assignments = {} }
        local classToken = select(2, UnitClass("player")) or "UNKNOWN"
        local specIdx = GetSpecialization and GetSpecialization() or 0
        local key = classToken .. "_" .. tostring(specIdx)
        p.modules.Profiles.specSwap.assignments[key] = ns:GetProfileKey()
        if ns.Debug and ns.Debug.Log then
            ns.Debug:Log("[ProfilesPanel] spec %s -> '%s'", key, ns:GetProfileKey())
        end
    end, 80)
    assignBtn:SetPoint("LEFT", specActionsRow, "LEFT", 0, 0)

    local clearBtn = C.CreateCompactButton(specActionsRow, "Clear", function()
        if not ns.savedVarsReady then return end
        local p = ns:GetProfile()
        if not (p.modules and p.modules.Profiles and p.modules.Profiles.specSwap) then return end
        local classToken = select(2, UnitClass("player")) or "UNKNOWN"
        local specIdx = GetSpecialization and GetSpecialization() or 0
        local key = classToken .. "_" .. tostring(specIdx)
        p.modules.Profiles.specSwap.assignments[key] = nil
        if ns.Debug and ns.Debug.Log then
            ns.Debug:Log("[ProfilesPanel] spec %s assignment cleared", key)
        end
    end, 80)
    clearBtn:SetPoint("LEFT", assignBtn, "RIGHT", 4, 0)

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
        refreshCopyValues()
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
