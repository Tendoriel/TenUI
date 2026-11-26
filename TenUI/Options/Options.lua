local addonName, ns = ...

ns.Options = ns.Options or {}
local Options = ns.Options

local CreateFrame    = CreateFrame
local InCombatLockdown = InCombatLockdown
local UIParent       = UIParent
local type           = type
local pairs          = pairs
local ipairs         = ipairs
local tostring       = tostring
local pcall          = pcall

local WIN_W          = 920
local WIN_H          = 640
local SIDEBAR_W      = 160
local HEADER_H       = 40
local FOOTER_H       = 28
local SCROLL_PAD_TOP = 8
local GRAB_MARGIN    = 80
local PINNED_GAP     = 8
local SCROLLBAR_GUTTER = 12
local COOLDOWN_TABS = {
    { key = "cdmbars", label = "Cooldowns" },
    { key = "TrackedIcon", label = "Tracked Icons" },
    { key = "TrackedBars", label = "Tracked Bars" },
}

local _frame       = nil
local _currentPage = nil
local _dirty       = false
local _pages       = {}
local _pageMap     = {}
local _pendingPage = nil
local _built       = false

local SCALE_MIN  = 0.6
local SCALE_MAX  = 1.5
local SCALE_STEP = 0.1

local function getSavedOptionsScale()
    local ui = ns.GetUIState and ns:GetUIState()
    local v = ui and tonumber(ui.optionsScale) or 1.0
    if v < SCALE_MIN then v = SCALE_MIN end
    if v > SCALE_MAX then v = SCALE_MAX end
    return v
end

local function clampWindowToScreen()
    if not _frame then return end
    local scale = _frame:GetScale()
    if not scale or scale <= 0 then return end
    local sw = UIParent:GetWidth()  / scale
    local sh = UIParent:GetHeight() / scale
    local l, t = _frame:GetLeft(), _frame:GetTop()
    if not (l and t) then return end
    local w = _frame:GetWidth()
    local minL = GRAB_MARGIN - w
    local maxL = sw - GRAB_MARGIN
    local nl = math.max(minL, math.min(l, maxL))
    local nt = math.max(HEADER_H, math.min(t, sh))
    if nl ~= l or nt ~= t then
        _frame:ClearAllPoints()
        _frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", nl, nt)
    end
end

local function applyOptionsScale(v)
    v = tonumber(v) or 1.0
    if v < SCALE_MIN then v = SCALE_MIN end
    if v > SCALE_MAX then v = SCALE_MAX end
    v = math.floor(v * 100 + 0.5) / 100
    local ui = ns.GetUIState and ns:GetUIState()
    if ui then
        ui.optionsScale = v
    end
    if _frame then
        _frame:SetScale(v)
        clampWindowToScreen()
        if _frame.scaleLabel then
            _frame.scaleLabel:SetText(math.floor(v * 100 + 0.5) .. "%")
        end
    end
    return v
end

local PAGE_ORDER = {
    "general",
    "qolReminders",
    "layout",
    "cdmbars",
    "ability",
    "auras",
    "aura_settings",
    "glow",
    "resources",
    "castbar",
    "dragonriding",
    "profiles",
    "information",
}

local _pageOrderIndex = {}
for i = 1, #PAGE_ORDER do
    _pageOrderIndex[PAGE_ORDER[i]] = i
end

function Options:RegisterPage(def)
    if not def or not def.key then
        if ns.Debug and ns.Debug.Log then
            ns.Debug:Log("[Options] RegisterPage: missing key")
        end
        return
    end
    if _pageMap[def.key] then return end

    def._orderIndex = _pageOrderIndex[def.key] or (#PAGE_ORDER + 1 + #_pages)
    local pos = #_pages + 1
    for i = 1, #_pages do
        if def._orderIndex < (_pages[i]._orderIndex or 0) then
            pos = i
            break
        end
    end
    table.insert(_pages, pos, def)
    _pageMap[def.key] = { def = def, built = false }

    if _built and _frame then
        self:_RebuildSidebar()
    end
end

local function showErrorLabel(sc, msg)
    local UI = ns.UI
    local errLabel = UI.Text(sc, UI.Fonts.label, UI.Theme.color.danger, msg)
    errLabel:SetPoint("TOPLEFT", sc, "TOPLEFT", 8, -8)
end

function Options:_BuildWindow()
    if _frame then return end
    local UI = ns.UI
    local Theme = UI.Theme

    local f = CreateFrame("Frame", "TenUIOptionsFrame", UIParent)
    tinsert(UISpecialFrames, "TenUIOptionsFrame")
    f:SetScript("OnHide", function() Options._isOpen = false end)
    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(false)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if self:IsMovable() then self:StartMoving() end end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:Hide()

    UI.SkinWindow(f)

    local header = UI.CreateHeader(f, { height = HEADER_H })
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)
    f.header = header

    local closeBtn = UI.CreateCloseButton(header, function() Options:Close() end)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    header.searchField = ns.AddSettingsSearch(header, _pageMap, closeBtn)

    local unlockBtn = UI.CreateCompactButton(header, ns.db and ns.db.locked and "Edit Mode" or "Exit Edit", function()
        if InCombatLockdown() then
            DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7TenUI|r: Cannot unlock frames in combat")
            return
        end
        if ns.db and ns.db.locked then
            ns:UnlockAnchors()
        else
            ns:LockAnchors()
        end
    end, 80)
    unlockBtn:SetHeight(20)
    unlockBtn:SetPoint("RIGHT", header.searchField, "LEFT", -10, 0)
    unlockBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        if ns.db and ns.db.locked then
            GameTooltip:SetText("Edit Mode\nDrag anchors to reposition frames", 1, 1, 1, 1, true)
        else
            GameTooltip:SetText("Exit Edit Mode\nAnchors are currently unlocked", 1, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    unlockBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    f.unlockBtn = unlockBtn
    f.ubLabel   = unlockBtn.label

    local debugBtn = UI.CreateCompactButton(header, "Debug", function()
        if ns.Debug then
            if ns.Debug.Toggle then
                ns.Debug:Toggle()
            elseif ns.Debug.Show then
                ns.Debug:Show()
            end
        end
    end, 56)
    debugBtn:SetHeight(20)
    debugBtn:SetPoint("RIGHT", unlockBtn, "LEFT", -6, 0)
    debugBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("Debug Log\nRecent messages, copy-pasteable", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    debugBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    f.debugBtn = debugBtn

    local function makeScaleStepBtn(label, delta)
        local b = UI.CreateCompactButton(header, label, function()
            applyOptionsScale(getSavedOptionsScale() + delta)
        end, 18)
        b:SetHeight(20)
        b:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            GameTooltip:SetText("Window Scale\nResizes only this window (60-150%)", 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end

    local scalePlusBtn = makeScaleStepBtn("+", SCALE_STEP)
    scalePlusBtn:SetPoint("RIGHT", debugBtn, "LEFT", -10, 0)

    local scaleLabel = UI.Text(header, UI.Fonts.value, Theme.color.textDim)
    scaleLabel:SetPoint("RIGHT", scalePlusBtn, "LEFT", -3, 0)
    scaleLabel:SetWidth(34)
    scaleLabel:SetJustifyH("CENTER")
    scaleLabel:SetText(math.floor(getSavedOptionsScale() * 100 + 0.5) .. "%")
    f.scaleLabel = scaleLabel

    local scaleMinusBtn = makeScaleStepBtn("-", -SCALE_STEP)
    scaleMinusBtn:SetPoint("RIGHT", scaleLabel, "LEFT", -3, 0)

    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetPoint("TOPLEFT",    f, "TOPLEFT",    0, -HEADER_H - 6)
    sidebar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, FOOTER_H)
    sidebar:SetWidth(SIDEBAR_W)
    local divider = sidebar:CreateTexture(nil, "BORDER")
    divider:SetColorTexture(unpack(Theme.color.lineFaint))
    divider:SetPoint("TOPRIGHT",    sidebar, "TOPRIGHT",    0, 0)
    divider:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    divider:SetWidth(1)
    f.sidebar = sidebar

    local contentArea = CreateFrame("Frame", nil, f)
    contentArea:SetPoint("TOPLEFT",     f, "TOPLEFT",     SIDEBAR_W,  -HEADER_H - 6)
    contentArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4,          FOOTER_H)
    f.contentArea = contentArea

    UI.CreateFooter(f, "TenUI v" .. tostring(ns.version or "0.1.0") .. "  |  /tenui for commands", { height = FOOTER_H })

    _frame = f
    _built = true

    self:_RebuildSidebar()
end

function Options:_RebuildSidebar()
    if not _frame then return end
    local UI = ns.UI
    local sidebar = _frame.sidebar

    local y = -4
    for i = 1, #_pages do
        local def = _pages[i]
        local entry = _pageMap[def.key]
        if entry and not def.sidebarParent and not entry.tabBtn then
            local capturedKey = def.key
            local tab = UI.CreateSidebarItem(sidebar, def.label or def.key, function()
                Options:SelectPage(capturedKey)
            end)
            entry.tabBtn = tab
        end
    end
    for i = 1, #_pages do
        local entry = _pageMap[_pages[i].key]
        if entry and entry.tabBtn then
            entry.tabBtn:ClearAllPoints()
            entry.tabBtn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, y)
            entry.tabBtn:SetWidth(SIDEBAR_W - 1)
            y = y - 26 - 1
            local active = _pageMap[_currentPage]
            entry.tabBtn:SetSelected(active and (active.def.sidebarParent or _currentPage) == _pages[i].key)
        end
    end
end

function Options:_GetOrCreateScrollForPage(key)
    local entry = _pageMap[key]
    if not entry then return nil, nil end
    if entry.scrollFrame then
        return entry.scrollFrame, entry.scrollChild
    end

    local contentArea = _frame.contentArea
    if not contentArea then return nil, nil end

    local UI = ns.UI
    local container, sc = UI.CreateScrollSection(contentArea)
    container:SetPoint("TOPLEFT",     contentArea, "TOPLEFT",     8,  -SCROLL_PAD_TOP)
    container:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", -4, 4)
    container:Hide()

    local sfW = container.scrollFrame:GetWidth()
    sc:SetWidth((sfW and sfW > 0) and sfW or (WIN_W - SIDEBAR_W - 32))

    entry.container   = container
    entry.scrollFrame = container.scrollFrame
    entry.scrollChild = sc
    return entry.scrollFrame, sc
end

function Options:ClearPinnedHeader(key)
    local entry = _pageMap[key]
    if not entry or not entry.pinnedHeader then return end
    local C = ns.UI
    if C and C.ClearChildren then
        pcall(C.ClearChildren, entry.pinnedHeader)
    end
end

function Options:GetPinnedHeader(key, height)
    local entry = _pageMap[key]
    if not entry then return nil end

    self:_GetOrCreateScrollForPage(key)
    local container = entry.container
    local sf = entry.scrollFrame
    if not (container and sf) then return nil end

    height = tonumber(height) or 0
    if height < 0 then height = 0 end
    entry.pinnedHeight = height

    local ph = entry.pinnedHeader
    if not ph then
        ph = CreateFrame("Frame", nil, container)
        ph:SetPoint("TOPLEFT",  container, "TOPLEFT",  0, 0)
        ph:SetPoint("TOPRIGHT", container, "TOPRIGHT", -SCROLLBAR_GUTTER, 0)
        entry.pinnedHeader = ph
    end
    ph:SetHeight(math.max(height, 1))

    local topInset = (height > 0) and -(height + PINNED_GAP) or 0
    sf:ClearAllPoints()
    sf:SetPoint("TOPLEFT",     container, "TOPLEFT",     0, topInset)
    sf:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -SCROLLBAR_GUTTER, 0)

    return ph
end

function Options:BuildCooldownHeader(page, selected, height)
    self:ClearPinnedHeader(page)
    local header = self:GetPinnedHeader(page, height)
    local prev
    for _, tab in ipairs(COOLDOWN_TABS) do
        local key = tab.key
        local button = ns.UI.CreateTabButton(header, tab.label, function()
            if key == "cdmbars" then
                self:SelectPage(key)
            else
                ns.AuraPanel:OpenList(key)
            end
        end)
        if prev then
            button:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        else
            button:SetPoint("TOPLEFT", header, "TOPLEFT", 8, 0)
        end
        button:SetSelected(key == selected)
        prev = button
    end
    return header
end

function Options:CreateCooldownStrip(header, offset, callbacks, emptyText)
    local C = ns.UI
    local iconSize, padding = 32, 4
    local stride = iconSize + padding
    local strip = CreateFrame("Frame", nil, header)
    strip:SetPoint("TOPLEFT", header, "TOPLEFT", 8, offset)
    strip:SetPoint("TOPRIGHT", header, "TOPRIGHT", -8, offset)
    C.SkinPanel(strip)

    local buttons, lanes, selected = {}, {}, {}
    local function itemKey(item) return item.key or item.spellID end
    local function mark(button)
        local active = selected[itemKey(button.optionItem)] ~= nil
        button.selection:SetShown(active)
    end
    local columns, dragging, currentRows
    local function dropAtCursor()
        local left, top = strip:GetLeft(), strip:GetTop()
        if not (left and top) then return end
        local x, y = GetCursorPosition()
        local scale = strip:GetEffectiveScale()
        x, y = x / scale - left, top - y / scale
        if x < 0 or x > strip:GetWidth() or y < 0 or y > strip:GetHeight() then return end
        for row, lane in ipairs(lanes) do
            if y < lane.bottom then
                local column = math.max(1, math.min(columns, math.floor((x - padding) / stride) + 1))
                local line = math.max(0, math.floor((y - lane.top - padding) / stride))
                return row, math.min(#currentRows[row] + (dragging.row == row and 0 or 1), line * columns + column)
            end
        end
    end

    local marker = C.Rect(strip, "OVERLAY", C.Theme.color.accent)
    marker:SetSize(2, iconSize)
    marker:Hide()
    local function showDrop()
        local row, index = dropAtCursor()
        if not row or index < 1 then marker:Hide() return end
        local cell = index - 1
        local side = row == dragging.row and index > dragging.index and stride or 0
        marker:ClearAllPoints()
        marker:SetPoint("TOPLEFT", strip, "TOPLEFT", padding / 2 + (cell % columns) * stride + side,
            -lanes[row].top - padding - math.floor(cell / columns) * stride)
        marker:Show()
    end

    return function(rows)
        currentRows = rows
        local width = strip:GetWidth()
        columns = math.max(1, math.floor(((width > 0 and width or 700) - padding) / stride))
        local used, top = 0, 0
        for row, items in ipairs(rows) do
            local lane = lanes[row]
            if not lane then
                lane = { caption = C.Text(strip, C.Fonts.small, C.Theme.color.textDim) }
                lanes[row] = lane
            end
            lane.top = top
            lane.bottom = top + math.max(1, math.ceil(#items / columns)) * stride + padding
            lane.caption:ClearAllPoints()
            lane.caption:SetPoint("TOPLEFT", strip, "TOPLEFT", 8, -top - 10)
            lane.caption:SetText(row == 1 and emptyText or "Drag icons here for Row 2")
            lane.caption:SetShown(#items == 0)
            for index, item in ipairs(items) do
                used = used + 1
                local button = buttons[used]
                if not button then
                    button = C.CreateIconButton(strip, { isKnown = true, texture = 134400 }, {
                        onEnter = function(self)
                            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
                            GameTooltip:SetText(self.optionItem.label)
                            GameTooltip:AddLine("Drag to reorder", 0.6, 0.8, 1)
                            if self.optionItem.spellID then GameTooltip:AddLine("Ctrl-click to select multiple · Right-click for settings", 0.6, 0.8, 1) end
                            if callbacks.remove then GameTooltip:AddLine("Shift-right-click: remove", 0.6, 0.8, 1) end
                            GameTooltip:Show()
                        end,
                    })
                    button:SetSize(iconSize, iconSize)
                    button.selection = button:CreateTexture(nil, "OVERLAY")
                    button.selection:SetColorTexture(0.5, 0.4, 1, 0.9)
                    button.selection:SetPoint("BOTTOMLEFT")
                    button.selection:SetPoint("BOTTOMRIGHT")
                    button.selection:SetHeight(3)
                    button:RegisterForDrag("LeftButton")
                    button:SetScript("OnClick", function(self, mouse)
                        if mouse == "LeftButton" and IsControlKeyDown() and self.optionItem.spellID then
                            local key = itemKey(self.optionItem)
                            if selected[key] then selected[key] = nil else selected[key] = self.optionItem end
                            mark(self)
                            return
                        end
                        if mouse ~= "RightButton" then return end
                        GameTooltip:Hide()
                        if callbacks.remove and IsShiftKeyDown() then
                            callbacks.remove(self.optionItem, self.previewRow)
                        elseif self.optionItem.spellID then
                            local group = {}
                            if selected[itemKey(self.optionItem)] then
                                for _, visible in ipairs(buttons) do
                                    if visible:IsShown() and selected[itemKey(visible.optionItem)] then group[#group+1] = visible.optionItem end
                                end
                            end
                            callbacks.select(self.optionItem, group)
                        end
                    end)
                    button:SetScript("OnDragStart", function(self)
                        if InCombatLockdown() or IsControlKeyDown() then return end
                        GameTooltip:Hide()
                        dragging = { row = self.previewRow, index = self.previewIndex, item = self.optionItem }
                        self:SetAlpha(0.55)
                        self:SetScript("OnUpdate", showDrop)
                    end)
                    local function finishDrag(self, apply)
                        self:SetAlpha(1)
                        self:SetScript("OnUpdate", nil)
                        marker:Hide()
                        if not dragging then return end
                        local row, pos = dropAtCursor()
                        local previous = dragging
                        dragging = nil
                        if apply and row and pos > 0 and not InCombatLockdown()
                           and (row ~= previous.row or pos ~= previous.index) then
                            callbacks.move(previous, row, pos, currentRows[row][pos])
                        end
                    end
                    button:SetScript("OnDragStop", function(self) finishDrag(self, true) end)
                    button:SetScript("OnHide", function(self)
                        if self:GetScript("OnUpdate") then finishDrag(self, false) end
                    end)
                    buttons[used] = button
                end
                button.optionItem = item
                mark(button)
                button.previewRow, button.previewIndex = row, index
                button.iconTex:SetTexture(item.texture or 134400)
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", strip, "TOPLEFT", padding + (index - 1) % columns * stride,
                    -top - padding - math.floor((index - 1) / columns) * stride)
                button:Show()
            end
            top = lane.bottom
        end
        for i = used + 1, #buttons do buttons[i]:Hide() end
        for i = #lanes, #rows + 1, -1 do
            lanes[i].caption:Hide()
            lanes[i] = nil
        end
        strip:SetHeight(top)
        callbacks.resize(top - offset + 1)
    end
end

function Options:Build()
    if InCombatLockdown() then
        _pendingPage = _pendingPage or _currentPage
        return
    end
    self:_BuildWindow()
end

function Options:SelectPage(key, forceRebuild)
    if not key then return end

    local entry = _pageMap[key]
    if not entry or not _frame then return end

    local ui = ns.GetUIState and ns:GetUIState()
    if ui then
        ui.lastOptionsPage = entry.def.restorePage or key
    end

    if _currentPage and _pageMap[_currentPage] then
        local prev = _pageMap[_currentPage]
        if prev.container then prev.container:Hide() end
        local prevTab = _pageMap[prev.def.sidebarParent or _currentPage].tabBtn
        if prevTab then prevTab:SetSelected(false) end
    end

    _currentPage = key

    local tab = _pageMap[entry.def.sidebarParent or key].tabBtn
    if tab then
        tab:SetSelected(true)
    end

    if entry.profileDirty and entry.built then forceRebuild = true end
    entry.profileDirty = nil
    if forceRebuild and entry.built then
        self:RebuildPage(key)
    end

    if entry.built and not forceRebuild and entry.def.rebuildOnShow
       and not InCombatLockdown() then
        self:RebuildPage(key)
    end

    if not entry.built then
        local sf, sc = self:_GetOrCreateScrollForPage(key)
        if sc and type(entry.def.build) == "function" then
            local ok, err = pcall(entry.def.build, sc)
            if not ok then
                showErrorLabel(sc, "Page build error: " .. tostring(err))
                if ns.Debug and ns.Debug.Log then
                    ns.Debug:Log("[Options] Page '%s' build error: %s", key, tostring(err))
                end
            end
        end
        entry.built = true
    end

    if entry.scrollChild then ns.IndexSettingsPage(key, entry.scrollChild) end
    if entry.container then
        entry.container:Show()
    end
end

function Options:Open()
    if not _built then self:Build() end
    if not _frame then return end

    applyOptionsScale(getSavedOptionsScale())

    if not _currentPage then
        local savedPage
        local ui = ns.GetUIState and ns:GetUIState()
        if ui then
            savedPage = ui.lastOptionsPage
        end
        if not savedPage and ns.savedVarsReady then
            local profile = ns:GetProfile()
            if profile.modules and profile.modules.Options then
                savedPage = profile.modules.Options.selectedPage
            end
        end
        if not savedPage or not _pageMap[savedPage] then
            savedPage = "general"
        end
        savedPage = _pageMap[savedPage].def.restorePage or savedPage
        self:SelectPage(savedPage)
    end

    if _currentPage and _pageMap[_currentPage].profileDirty then self:SelectPage(_currentPage, true) end
    _frame:Show()
    Options._isOpen = true
end

function Options:Close()
    if _frame then _frame:Hide() end
    Options._isOpen = false
end

function Options:Toggle()
    if not _built then
        self:Build()
        self:Open()
        return
    end
    if _frame and _frame:IsShown() then
        self:Close()
    else
        self:Open()
    end
end

function Options:Refresh()
    if not _frame or not _frame:IsShown() then return end
    if _currentPage and _pageMap[_currentPage] then
        local entry = _pageMap[_currentPage]
        if entry.scrollChild and type(entry.def.refresh) == "function" then
            local ok, err = pcall(entry.def.refresh, entry.scrollChild)
            if not ok and ns.Debug and ns.Debug.Log then
                ns.Debug:Log("[Options] Page '%s' refresh error: %s", _currentPage, tostring(err))
            end
        end
    end
end

function Options:RebuildPage(key)
    local entry = _pageMap[key]
    if not entry then return end

    local sf, sc = self:_GetOrCreateScrollForPage(key)
    if not sc then return end

    local C = ns.UI
    if C and C.ClearChildren then
        pcall(C.ClearChildren, sc)
    end
    sc:SetHeight(1)
    if sf then sf:SetVerticalScroll(0) end

    entry.built = false
    if type(entry.def.build) == "function" then
        local ok, err = pcall(entry.def.build, sc)
        if not ok then
            showErrorLabel(sc, "Page rebuild error: " .. tostring(err))
            if ns.Debug and ns.Debug.Log then
                ns.Debug:Log("[Options] RebuildPage '%s' error: %s", key, tostring(err))
            end
        end
    end
    entry.built = true
end

function Options:MarkDirty()
    _dirty = true
end

function Options:GetCurrentPage()
    return _currentPage
end

ns:RegisterMessage("LOCK_STATE_CHANGED", function(_, locked)
    if _frame and _frame.ubLabel then
        _frame.ubLabel:SetText(locked and "Edit Mode" or "Exit Edit")
    end
end)

ns:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if _frame and _frame:IsShown() then
    end
end)

ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if _pendingPage then
        local p = _pendingPage
        _pendingPage = nil
        Options:SelectPage(p)
    end
    if _dirty and _frame and _frame:IsShown() then
        Options:Refresh()
        _dirty = false
    end
end)

ns:RegisterMessage("PROFILE_CHANGED", function()
    for _, entry in pairs(_pageMap) do entry.profileDirty = entry.built end
    C_Timer.After(0, function()
        if _frame and _frame:IsShown() and _currentPage and _pageMap[_currentPage].profileDirty then
            if InCombatLockdown() then _pendingPage = _currentPage
            else Options:SelectPage(_currentPage, true) end
        end
    end)
end)

local function getTooltipControl()
    if not ns.savedVarsReady then return {} end
    local p = ns:GetProfile()
    p.modules = p.modules or {}
    p.modules.General = p.modules.General or {}
    p.modules.General.tooltipControl = p.modules.General.tooltipControl or {}
    return p.modules.General.tooltipControl
end

local function buildGeneralPage(sc)
    local C = ns.UI
    if not C then return end
    local children = {}

    children[#children + 1] = C.CreateSection(sc, "General")

    children[#children + 1] = C.CreateCheckBox(sc, "Enable TenUI",
        function()
            local p = ns:GetProfile()
            return p.modules and p.modules.General and p.modules.General.enabled ~= false
        end,
        function(v)
            local p = ns:GetProfile()
            p.modules = p.modules or {}
            p.modules.General = p.modules.General or {}
            p.modules.General.enabled = v
            ns:ApplyHUDEnabled()
        end
    )

    children[#children + 1] = C.CreateSlider(sc, "Global Scale", 0.5, 2.0, 0.05,
        function()
            return (ns.db and ns.db.globalScale) or 1.0
        end,
        function(v)
            if ns.db then
                ns.db.globalScale = v
                if ns.anchorParent then
                    ns.anchorParent:SetScale(v)
                    ns.Pixel.RefreshEdges()
                    ns:Fire("GLOBAL_SCALE_CHANGED")
                end
            end
        end, 1.0)

    children[#children + 1] = C.CreateCheckBox(sc, "Show Minimap Button",
        function()
            local p = ns:GetProfile()
            local m = p.modules and p.modules.Minimap
            return m and m.enabled ~= false
        end,
        function(v)
            local p = ns:GetProfile()
            p.modules = p.modules or {}
            p.modules.Minimap = p.modules.Minimap or {}
            p.modules.Minimap.enabled = v
            if ns.MinimapButton and ns.MinimapButton.ApplyVisibility then
                ns.MinimapButton:ApplyVisibility()
            end
        end
    )

    children[#children+1] = C.CreateSection(sc, "Global Appearance")
    local function setGlobal(key, value)
        local p = ns:GetProfile()
        p.globalStyle = p.globalStyle or {}
        p.globalStyle[key] = value
        ns:Fire("PROFILE_CHANGED", ns:GetProfileKey())
    end
    children[#children+1] = C.CreateFontDropdown(sc, "Default font", function() return ns:GetGlobalStyle().font end,
        function(v) setGlobal("font", v) end, true)
    children[#children+1] = C.CreateStatusBarTextureDropdown(sc, "Default bar texture", function() return ns:GetGlobalStyle().texture end,
        function(v) setGlobal("texture", v) end, true)
    children[#children+1] = C.CreateOutlineDropdown(sc, "Default outline", function() return ns:GetGlobalStyle().outline or "OUTLINE" end,
        function(v) setGlobal("outline", v) end, true)
    children[#children+1] = C.CreateButton(sc, "Apply Global Appearance to All HUD Modules", function()
        StaticPopupDialogs.TENUI_GLOBAL_STYLE = {
            text = "Replace local HUD font, outline and bar texture overrides in this profile?",
            button1 = ACCEPT, button2 = CANCEL, timeout = 0, whileDead = true, hideOnEscape = true,
            OnAccept = function(_, key)
                if InCombatLockdown() or key ~= ns:GetProfileKey() then return end
                ns:BackupProfile()
                local function reset(t)
                    for field, value in pairs(t) do
                        if type(value) == "table" then reset(value)
                        elseif field == "font" or field == "fontKey" or field == "keybindFont" then t[field] = "default"
                        elseif field == "fontFlags" or (field == "flags" and type(value) == "string") then t[field] = "GLOBAL"
                        elseif (field == "texture" or field == "barTexture") and type(value) == "string" then t[field] = "default" end
                    end
                end
                local p = ns:GetProfile()
                for _, name in ipairs({"Layout","Resources","CastBar","DragonRiding","General","Auras"}) do
                    if p.modules[name] then reset(p.modules[name]) end
                end
                for _, scope in pairs(p.specScopes or {}) do reset(scope) end
                ns:Fire("PROFILE_CHANGED", key)
            end,
        }
        StaticPopup_Show("TENUI_GLOBAL_STYLE", nil, nil, ns:GetProfileKey())
    end)

    children[#children + 1] = C.CreateSection(sc, "Tooltip IDs")
    children[#children + 1] = C.CreateHelpText(sc, "Add item, spell and icon IDs to tooltips.")

    local tooltipChildren = {}
    children[#children + 1] = C.CreateCheckBox(sc, "Enable Tooltip IDs",
        function() return getTooltipControl().enabled == true end,
        function(v)
            getTooltipControl().enabled = v
            for _, row in ipairs(tooltipChildren) do row:SetAlpha(v and 1 or 0.45) row:EnableMouse(v) end
        end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Show Item ID",
        function() return getTooltipControl().showItemID == true end,
        function(v) getTooltipControl().showItemID = v end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Show Spell ID",
        function() return getTooltipControl().showSpellID == true end,
        function(v) getTooltipControl().showSpellID = v end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Show Icon (file) ID",
        function() return getTooltipControl().showIconID == true end,
        function(v) getTooltipControl().showIconID = v end
    )

    children[#children + 1] = C.CreateCheckBox(sc, "Only while Shift is held",
        function() return getTooltipControl().requireModifier == true end,
        function(v) getTooltipControl().requireModifier = v end
    )

    for i = #children-3, #children do
        local child = children[i]
        tooltipChildren[#tooltipChildren+1] = child
        local enabled = getTooltipControl().enabled == true
        child:SetAlpha(enabled and 1 or 0.45)
        child:EnableMouse(enabled)
    end

    local totalH = C.LayoutVertical(sc, children, 4, -8)
    sc:SetHeight(math.max(totalH, 10))
end

local function refreshGeneralPage(sc)
    local children = { sc:GetChildren() }
    for i = 1, #children do
        if children[i] and type(children[i].Refresh) == "function" then
            pcall(children[i].Refresh, children[i])
        end
    end
end

Options:RegisterPage({
    key     = "general",
    label   = "General",
    build   = buildGeneralPage,
    refresh = refreshGeneralPage,
})
