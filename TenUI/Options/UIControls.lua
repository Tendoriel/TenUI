local addonName, ns = ...

ns.UI = ns.UI or {}
local UI = ns.UI
local Theme = UI.Theme

local CreateFrame = CreateFrame
local type        = type
local pairs       = pairs
local ipairs      = ipairs
local tostring    = tostring
local tonumber    = tonumber
local unpack      = unpack
local math_floor  = math.floor
local math_min    = math.min
local math_max    = math.max

local ROW_W   = Theme.spacing.rowW
local ROW_H   = Theme.spacing.controlH
local C_INPUT = Theme.color.input
local C_LINE  = Theme.color.lineSoft

local function logErr(what, err)
    if ns.Debug and ns.Debug.Log then
        ns.Debug:Log("[UI] %s error: %s", tostring(what), tostring(err))
    end
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok then logErr("callback", err) end
end

function UI.CreateSection(parent, title)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(ROW_W, 22)
    local fs = UI.Text(f, UI.Fonts.section, Theme.color.accent, string.upper(tostring(title or "")))
    fs:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 5)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(unpack(Theme.color.lineFaint))
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f.text = fs
    f.searchHeading = true
    return f
end

function UI.CreateSubSection(parent, title)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(ROW_W, 20)
    UI.Rect(f, "BACKGROUND", Theme.color.section):SetAllPoints()
    local rule = UI.Rect(f, "ARTWORK", Theme.color.violet)
    rule:SetWidth(2)
    rule:SetPoint("TOPLEFT")
    rule:SetPoint("BOTTOMLEFT")
    local fs = UI.Text(f, UI.Fonts.section, Theme.color.violet, string.upper(tostring(title or "")))
    fs:SetPoint("LEFT", f, "LEFT", 8, 0)
    f.text = fs
    f.searchHeading = true
    return f
end

function UI.CreateHelpText(parent, text)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(30)
    local fs = UI.Text(f, UI.Fonts.small, Theme.color.textDim)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    fs:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    fs:SetText(tostring(text or ""))
    f.text = fs
    local function measure()
        local h = fs:GetStringHeight()
        if h and h > 0 then f:SetHeight(h + 4) end
    end
    f.AutoHeight = measure
    f:SetScript("OnSizeChanged", measure)
    return f
end

local BTN_TEXT_PAD = 16

local function buildButton(parent, text, callback, width, primary)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or ROW_W, ROW_H)
    local bg = UI.Rect(btn, "BACKGROUND", Theme.color.input)
    bg:SetAllPoints(btn)
    local borderColor = primary and Theme.color.violetDim or C_LINE
    local border = UI.Border(btn, borderColor)
    local labelColor = primary and Theme.color.violet or Theme.color.text
    local label = UI.Text(btn, UI.Fonts.label, labelColor, text)
    label:SetAllPoints(btn)
    label:SetJustifyH("CENTER")
    btn.label = label
    local tw = label:GetStringWidth() or 0
    if tw > 0 and (btn:GetWidth() or 0) < tw + BTN_TEXT_PAD then
        btn:SetWidth(math_floor(tw + BTN_TEXT_PAD + 0.5))
    end
    btn:SetScript("OnEnter", function()
        bg:SetColorTexture(unpack(Theme.color.hover))
        if primary then
            border.SetColor(unpack(Theme.color.violet))
            label:SetTextColor(unpack(Theme.color.textBright))
        else
            border.SetColor(unpack(Theme.color.line))
            label:SetTextColor(unpack(Theme.color.textBright))
        end
    end)
    btn:SetScript("OnLeave", function()
        bg:SetColorTexture(unpack(Theme.color.input))
        border.SetColor(unpack(borderColor))
        label:SetTextColor(unpack(labelColor))
    end)
    btn:SetScript("OnClick", function()
        safeCall(callback)
    end)
    return btn
end

function UI.CreateButton(parent, text, callback)
    local button = buildButton(parent, text, callback, ROW_W, false)
    button.layoutKind = "action"
    return button
end

function UI.CreateCompactButton(parent, text, callback, width)
    return buildButton(parent, text, callback, width or 80, false)
end

function UI.CreatePrimaryButton(parent, text, callback, width)
    return buildButton(parent, text, callback, width or ROW_W, true)
end

local function buildToggle(parent)
    local t = CreateFrame("Frame", nil, parent)
    t:SetSize(28, 14)
    local track = UI.Rect(t, "BACKGROUND", C_INPUT)
    track:SetAllPoints(t)
    local border = UI.Border(t, C_LINE)
    local knob = t:CreateTexture(nil, "ARTWORK")
    knob:SetSize(10, 10)
    knob:SetColorTexture(unpack(Theme.color.textDim))
    knob:SetPoint("LEFT", t, "LEFT", 2, 0)
    t.track = track
    t.border = border
    t.knob = knob
    function t.SetOn(self, on)
        knob:ClearAllPoints()
        if on then
            track:SetColorTexture(Theme.color.violet[1], Theme.color.violet[2], Theme.color.violet[3], 0.45)
            border.SetColor(unpack(Theme.color.violetDim))
            knob:SetColorTexture(unpack(Theme.color.textBright))
            knob:SetPoint("RIGHT", t, "RIGHT", -2, 0)
        else
            track:SetColorTexture(unpack(C_INPUT))
            border.SetColor(unpack(C_LINE))
            knob:SetColorTexture(unpack(Theme.color.textDim))
            knob:SetPoint("LEFT", t, "LEFT", 2, 0)
        end
    end
    return t
end

function UI.CreateCheckBox(parent, labelText, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(ROW_W, ROW_H)

    local label = UI.Text(f, UI.Fonts.label, Theme.color.text, labelText)
    label:SetPoint("LEFT", f, "LEFT", 0, 0)
    label:SetJustifyH("LEFT")
    f.label = label
    f.layoutKind, f.controlWidth = "toggle", 40

    local toggle = buildToggle(f)
    toggle:SetPoint("RIGHT", f, "RIGHT", -2, 0)
    f.toggle = toggle

    local function refresh()
        local val = type(get) == "function" and get() or false
        toggle:SetOn(val == true)
    end
    refresh()

    f:EnableMouse(true)
    f:SetScript("OnMouseDown", function(_, btn)
        if btn ~= "LeftButton" then return end
        if type(get) ~= "function" or type(set) ~= "function" then return end
        local newVal = not get()
        local ok, err = pcall(set, newVal)
        if not ok then logErr("CheckBox set", err) end
        refresh()
    end)
    f:SetScript("OnEnter", function()
        label:SetTextColor(unpack(Theme.color.textBright))
    end)
    f:SetScript("OnLeave", function()
        label:SetTextColor(unpack(Theme.color.text))
    end)

    f.Refresh = refresh
    return f
end

UI.CreateToggle = UI.CreateCheckBox

local function addReset(row, value, apply)
    if value == nil then return end
    row:EnableMouse(true)
    row:HookScript("OnMouseUp", function(_, button)
        if button ~= "RightButton" then return end
        if type(value) == "table" then apply(unpack(value)) else apply(value) end
        row.Refresh()
    end)
    row:HookScript("OnEnter", function()
        GameTooltip:SetOwner(row, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Right-click the label to restore its default")
        GameTooltip:Show()
    end)
    row:HookScript("OnLeave", function() if GameTooltip:IsOwned(row) then GameTooltip:Hide() end end)
end

function UI.CreateSlider(parent, labelText, minVal, maxVal, step, get, set, default)
    minVal = minVal or 0
    maxVal = maxVal or 1
    step   = step or 0.01

    local TRACK_W = 130
    local EB_W    = 46
    local STEP_W  = 14

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(ROW_W, ROW_H)

    local label = UI.Text(f, UI.Fonts.label, Theme.color.text, labelText)
    label:SetPoint("LEFT", f, "LEFT", 0, 0)
    label:SetJustifyH("LEFT")
    f.label = label
    f.layoutKind, f.controlWidth = "slider", 235

    local ebFrame = CreateFrame("Frame", nil, f)
    ebFrame:SetSize(EB_W, 18)
    ebFrame:SetPoint("RIGHT", f, "RIGHT", -(STEP_W + 4), 0)
    local ebBg = UI.Rect(ebFrame, "BACKGROUND", C_INPUT)
    ebBg:SetAllPoints(ebFrame)
    local ebLine = ebFrame:CreateTexture(nil, "BORDER")
    ebLine:SetColorTexture(unpack(C_LINE))
    ebLine:SetHeight(1)
    ebLine:SetPoint("BOTTOMLEFT", ebFrame, "BOTTOMLEFT", 0, 0)
    ebLine:SetPoint("BOTTOMRIGHT", ebFrame, "BOTTOMRIGHT", 0, 0)

    local eb = CreateFrame("EditBox", nil, ebFrame)
    eb:SetPoint("TOPLEFT", ebFrame, "TOPLEFT", 2, 0)
    eb:SetPoint("BOTTOMRIGHT", ebFrame, "BOTTOMRIGHT", -2, 1)
    eb:SetAutoFocus(false)
    eb:SetFontObject(UI.Fonts.value)
    eb:SetTextColor(unpack(Theme.color.textBright))
    eb:SetJustifyH("CENTER")
    eb:SetMaxLetters(8)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local slider = CreateFrame("Slider", nil, f)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(TRACK_W, 14)
    slider:SetPoint("RIGHT", ebFrame, "LEFT", -(STEP_W + 8), 0)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(1, 1, 1, 0.08)
    track:SetHeight(3)
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    slider:SetThumbTexture(Theme.texture.pixel)
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(7, 13)
    thumb:SetVertexColor(unpack(Theme.color.violet))
    local fill = slider:CreateTexture(nil, "BORDER")
    fill:SetColorTexture(Theme.color.violet[1], Theme.color.violet[2], Theme.color.violet[3], 0.45)
    fill:SetHeight(3)
    fill:SetPoint("LEFT", slider, "LEFT", 0, 0)
    fill:SetPoint("RIGHT", thumb, "CENTER", 0, 0)

    local function makeStepBtn(txt, anchorTo, side, delta)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(STEP_W, 16)
        local fs = UI.Text(b, UI.Fonts.value, Theme.color.textDim, txt)
        fs:SetPoint("CENTER", b, "CENTER", 0, 0)
        if side == "LEFT" then
            b:SetPoint("RIGHT", anchorTo, "LEFT", -2, 0)
        else
            b:SetPoint("LEFT", anchorTo, "RIGHT", 2, 0)
        end
        b:SetScript("OnEnter", function() fs:SetTextColor(unpack(Theme.color.accent)) end)
        b:SetScript("OnLeave", function() fs:SetTextColor(unpack(Theme.color.textDim)) end)
        b._delta = delta
        return b
    end

    local minusBtn = makeStepBtn("-", ebFrame, "LEFT", -step)
    local plusBtn  = makeStepBtn("+", ebFrame, "RIGHT", step)

    local function fmtNum(v)
        local fmt = (step >= 1) and "%d" or "%.2f"
        local ok, s = pcall(string.format, fmt, v)
        return ok and s or tostring(v)
    end

    local _updating = false

    local function updateDisplay(v)
        if _updating then return end
        _updating = true
        eb:SetText(fmtNum(v))
        _updating = false
    end

    local function applySet(v)
        if type(set) == "function" then
            local ok, err = pcall(set, v)
            if not ok then logErr("Slider set", err) end
        end
    end

    local function refresh()
        local v = type(get) == "function" and get() or minVal
        v = math_min(math_max(tonumber(v) or minVal, minVal), maxVal)
        if _updating then return end
        _updating = true
        slider:SetValue(v)
        _updating = false
        updateDisplay(v)
    end
    refresh()

    slider:SetScript("OnValueChanged", function(_, val, userInput)
        if not userInput then return end
        updateDisplay(val)
        applySet(val)
    end)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(_, delta)
        local v = (slider:GetValue() or minVal) + delta * step
        v = math_min(math_max(v, minVal), maxVal)
        slider:SetValue(v)
        updateDisplay(v)
        applySet(v)
    end)

    local function nudge(delta)
        local v = (slider:GetValue() or minVal) + delta
        v = math_floor(v / step + 0.5) * step
        v = math_min(math_max(v, minVal), maxVal)
        _updating = true
        slider:SetValue(v)
        _updating = false
        updateDisplay(v)
        applySet(v)
    end
    minusBtn:SetScript("OnClick", function(self) nudge(self._delta) end)
    plusBtn:SetScript("OnClick", function(self) nudge(self._delta) end)

    local function commitEditBox()
        local n = tonumber(eb:GetText())
        if not n then
            updateDisplay(slider:GetValue())
            eb:ClearFocus()
            return
        end
        n = math_min(math_max(n, minVal), maxVal)
        if step > 0 then
            n = math_floor(n / step + 0.5) * step
        end
        if _updating then
            eb:ClearFocus()
            return
        end
        _updating = true
        slider:SetValue(n)
        _updating = false
        updateDisplay(n)
        applySet(n)
        eb:ClearFocus()
    end

    eb:SetScript("OnEnterPressed", commitEditBox)
    eb:SetScript("OnEditFocusLost", commitEditBox)

    f.Refresh = refresh
    addReset(f, default, set)
    f.slider  = slider
    f.editBox = eb
    return f
end

function UI.CreateEditBox(parent, labelText, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(ROW_W, ROW_H)

    local label = UI.Text(f, UI.Fonts.label, Theme.color.text, labelText)
    label:SetPoint("LEFT", f, "LEFT", 0, 0)
    label:SetJustifyH("LEFT")
    f.label = label

    local ebFrame = CreateFrame("Frame", nil, f)
    ebFrame:SetSize(160, 20)
    ebFrame:SetPoint("RIGHT", f, "RIGHT", -2, 0)
    local ebBg = UI.Rect(ebFrame, "BACKGROUND", C_INPUT)
    ebBg:SetAllPoints(ebFrame)
    local ebLine = ebFrame:CreateTexture(nil, "BORDER")
    ebLine:SetColorTexture(unpack(C_LINE))
    ebLine:SetHeight(1)
    ebLine:SetPoint("BOTTOMLEFT", ebFrame, "BOTTOMLEFT", 0, 0)
    ebLine:SetPoint("BOTTOMRIGHT", ebFrame, "BOTTOMRIGHT", 0, 0)

    local eb = CreateFrame("EditBox", nil, ebFrame)
    eb:SetPoint("TOPLEFT", ebFrame, "TOPLEFT", 4, 0)
    eb:SetPoint("BOTTOMRIGHT", ebFrame, "BOTTOMRIGHT", -4, 1)
    eb:SetAutoFocus(false)
    eb:SetMultiLine(false)
    eb:SetFontObject(UI.Fonts.value)
    eb:SetTextColor(unpack(Theme.color.textBright))
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function()
        ebLine:SetColorTexture(unpack(Theme.color.accent))
    end)
    local function commit(self)
        ebLine:SetColorTexture(unpack(C_LINE))
        if type(set) == "function" then
            local ok, err = pcall(set, self:GetText())
            if not ok then logErr("EditBox set", err) end
        end
    end
    eb:SetScript("OnEnterPressed", function(self)
        commit(self)
        self:ClearFocus()
    end)
    eb:SetScript("OnEditFocusLost", commit)

    local function refresh()
        local v = type(get) == "function" and get() or ""
        eb:SetText(tostring(v or ""))
    end
    refresh()

    f.Refresh = refresh
    f.editBox = eb
    return f
end

local _popup
local _popupRows = {}
local _popupOwner

local function getPopup()
    if _popup then return _popup end
    local p = CreateFrame("Frame", "TenUIDropListPopup", UIParent)
    p:SetFrameStrata("TOOLTIP")
    p:SetClampedToScreen(true)
    p:Hide()
    local bg = UI.Rect(p, "BACKGROUND", { 0.024, 0.031, 0.063, 0.98 })
    bg:SetAllPoints(p)
    p._border = UI.Border(p, Theme.color.line)

    local catcher = CreateFrame("Frame", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("TOOLTIP")
    catcher:SetFrameLevel(1)
    p:SetFrameLevel(20)
    catcher:EnableMouse(true)
    catcher:Hide()
    catcher:SetScript("OnMouseDown", function() UI.CloseDropdownPopup() end)
    p._catcher = catcher

    local container, sc = UI.CreateScrollSection(p)
    container:SetPoint("TOPLEFT", p, "TOPLEFT", 1, -1)
    container:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -1, 1)
    p._listContainer = container
    p._listChild = sc

    tinsert(UISpecialFrames, "TenUIDropListPopup")
    p:SetScript("OnHide", function()
        catcher:Hide()
        _popupOwner = nil
    end)
    _popup = p
    return p
end

function UI.CloseDropdownPopup()
    if _popup and _popup:IsShown() then
        _popup:Hide()
    end
end

local function popupRow(parent, idx)
    local row = _popupRows[idx]
    if row then
        row:SetParent(parent)
        return row
    end
    row = CreateFrame("Button", nil, parent)
    row:SetHeight(20)
    local bg = UI.Rect(row, "BACKGROUND", { 0, 0, 0, 0 })
    bg:SetAllPoints(row)
    row._bg = bg
    local fs = UI.Text(row, UI.Fonts.value, Theme.color.text)
    fs:SetPoint("LEFT", row, "LEFT", 8, 0)
    fs:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    fs:SetJustifyH("LEFT")
    row._label = fs
    row:SetScript("OnEnter", function(self)
        self._bg:SetColorTexture(unpack(Theme.color.selected))
        self._label:SetTextColor(unpack(Theme.color.textBright))
    end)
    row:SetScript("OnLeave", function(self)
        self._bg:SetColorTexture(0, 0, 0, 0)
        if self._isCurrent then
            self._label:SetTextColor(unpack(Theme.color.accent))
        else
            self._label:SetTextColor(unpack(Theme.color.text))
        end
    end)
    _popupRows[idx] = row
    return row
end

local function openPopupFor(owner, anchorBtn, values, currentKey, onPick)
    local p = getPopup()
    if p:IsShown() and _popupOwner == owner then
        p:Hide()
        return
    end
    _popupOwner = owner

    local ROWH = 20
    local W = math_max(anchorBtn:GetWidth() or 180, 120)
    local count = values and #values or 0
    local visible = math_min(count, 8)
    local H = math_max(visible * ROWH + 2, ROWH + 2)

    for i = 1, #_popupRows do _popupRows[i]:Hide() end

    local sc = p._listChild
    sc:SetHeight(count * ROWH)
    local rowW = (count > visible) and (W - 14) or (W - 2)
    for idx = 1, count do
        local entry = values[idx]
        local row = popupRow(sc, idx)
        row:SetWidth(rowW)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, -(idx - 1) * ROWH)
        row._label:SetText(tostring(entry.label or entry.key))
        row._isCurrent = (entry.key == currentKey)
        if row._isCurrent then
            row._label:SetTextColor(unpack(Theme.color.accent))
        else
            row._label:SetTextColor(unpack(Theme.color.text))
        end
        local capturedKey = entry.key
        row:SetScript("OnClick", function()
            safeCall(onPick, capturedKey)
            p:Hide()
        end)
        row:Show()
    end

    p:SetSize(W, H + 2)
    p:ClearAllPoints()
    local bx, by = anchorBtn:GetLeft(), anchorBtn:GetBottom()
    local scale = anchorBtn:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if bx and by then
        bx, by = bx * scale, by * scale
        if by - H < 0 then
            local bt = (anchorBtn:GetTop() or by) * scale
            p:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", bx, bt)
        else
            p:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", bx, by)
        end
    else
        p:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, 0)
    end
    p._listContainer.scrollFrame:SetVerticalScroll(0)
    p._catcher:Show()
    p:Show()
end

function UI.CreateDropdownLikeList(parent, labelText, values, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(ROW_W, ROW_H)

    local label = UI.Text(f, UI.Fonts.label, Theme.color.text, labelText)
    label:SetPoint("LEFT", f, "LEFT", 0, 0)
    label:SetJustifyH("LEFT")
    f.label = label
    f.layoutKind, f.controlWidth = "dropdown", 176

    local segmented = { ["Icon Side"] = true, ["Orientation"] = true, ["Direction"] = true,
        ["Tracked bar icon"] = true, ["Timer direction"] = true, ["Growth"] = true }
    if segmented[labelText] and type(values) == "table" and #values >= 2 and #values <= 4 then
        local buttons = {}
        local function refresh()
            local current = get()
            for i, button in ipairs(buttons) do button:SetSelected(values[i].key == current) end
        end
        local nextButton
        local width = 0
        for i = #values, 1, -1 do
            local choice = values[i]
            local b = UI.CreateTabButton(f, choice.label, function() set(choice.key) refresh() end)
            b:SetHeight(20)
            b:SetPoint("RIGHT", nextButton or f, nextButton and "LEFT" or "RIGHT", -2, 0)
            width = width + b:GetWidth() + 2
            nextButton, buttons[i] = b, b
        end
        f.controlWidth = width + 12
        f.Refresh = refresh
        refresh()
        return f
    end

    local btn = CreateFrame("Button", nil, f)
    btn:SetSize(160, 20)
    btn:SetPoint("RIGHT", f, "RIGHT", -2, 0)
    local btnBg = UI.Rect(btn, "BACKGROUND", C_INPUT)
    btnBg:SetAllPoints(btn)
    local border = UI.Border(btn, C_LINE)

    local btnLabel = UI.Text(btn, UI.Fonts.value, Theme.color.textBright)
    btnLabel:SetPoint("LEFT", btn, "LEFT", 6, 0)
    btnLabel:SetPoint("RIGHT", btn, "RIGHT", -16, 0)
    btnLabel:SetJustifyH("LEFT")

    local chevron = UI.Text(btn, UI.Fonts.small, Theme.color.textDim, "v")
    chevron:SetPoint("RIGHT", btn, "RIGHT", -5, 0)

    local function getLabelForKey(k)
        if not values then return tostring(k or "") end
        for i = 1, #values do
            if values[i].key == k then return values[i].label or values[i].key end
        end
        return tostring(k or "")
    end

    local function refresh()
        local k = type(get) == "function" and get() or nil
        btnLabel:SetText(tostring(getLabelForKey(k)))
    end
    refresh()

    btn:SetScript("OnClick", function()
        local currentKey = type(get) == "function" and get() or nil
        openPopupFor(f, btn, values, currentKey, function(key)
            if type(set) == "function" then
                local ok, err = pcall(set, key)
                if not ok then logErr("Dropdown set", err) end
            end
            refresh()
        end)
    end)
    btn:SetScript("OnEnter", function()
        border.SetColor(unpack(Theme.color.line))
        chevron:SetTextColor(unpack(Theme.color.accent))
    end)
    btn:SetScript("OnLeave", function()
        border.SetColor(unpack(C_LINE))
        chevron:SetTextColor(unpack(Theme.color.textDim))
    end)

    f.Refresh = refresh
    f.btn = btn
    return f
end

UI.CreateDropdown = UI.CreateDropdownLikeList

function UI.CreateColorSwatch(parent, labelText, getRGBA, setRGBA, default)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(ROW_W, ROW_H)

    local label = UI.Text(f, UI.Fonts.label, Theme.color.text, labelText)
    label:SetPoint("LEFT", f, "LEFT", 0, 0)
    label:SetJustifyH("LEFT")
    f.label = label
    f.layoutKind, f.controlWidth = "color", 50

    local swatch = CreateFrame("Button", nil, f)
    swatch:SetSize(34, 16)
    swatch:SetPoint("RIGHT", f, "RIGHT", -2, 0)
    local swatchTex = swatch:CreateTexture(nil, "ARTWORK")
    swatchTex:SetPoint("TOPLEFT", swatch, "TOPLEFT", 1, -1)
    swatchTex:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -1, 1)
    local border = UI.Border(swatch, C_LINE)
    swatch:SetScript("OnEnter", function() border.SetColor(unpack(Theme.color.line)) end)
    swatch:SetScript("OnLeave", function() border.SetColor(unpack(C_LINE)) end)

    local function readColor()
        local r, g, b, a = 1, 1, 1, 1
        if type(getRGBA) == "function" then
            local ok, rr, gg, bb, aa = pcall(getRGBA)
            if ok then r, g, b, a = rr or 1, gg or 1, bb or 1, aa or 1 end
        end
        return r, g, b, a
    end

    local function refresh()
        swatchTex:SetColorTexture(readColor())
    end
    refresh()

    swatch:SetScript("OnClick", function()
        if InCombatLockdown and InCombatLockdown() then return end
        local r, g, b, a = readColor()
        if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
            local ready = false
            local function apply()
                if not ready then return end
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                if type(setRGBA) == "function" then
                    pcall(setRGBA, nr, ng, nb, ColorPickerFrame:GetColorAlpha())
                end
                refresh()
            end
            ColorPickerFrame:SetupColorPickerAndShow({
                r = r, g = g, b = b, opacity = a,
                hasOpacity = true,
                swatchFunc = apply,
                opacityFunc = apply,
                cancelFunc = function()
                    if type(setRGBA) == "function" then pcall(setRGBA, r, g, b, a) end
                    refresh()
                end,
            })
            ready = true
        end
    end)

    f.Refresh = refresh
    addReset(f, default, setRGBA)
    f.swatch = swatch
    return f
end

local ANCHOR_POINTS = {
    { key = "CENTER",      label = "Center" },
    { key = "TOP",         label = "Top" },
    { key = "BOTTOM",      label = "Bottom" },
    { key = "LEFT",        label = "Left" },
    { key = "RIGHT",       label = "Right" },
    { key = "TOPLEFT",     label = "Top Left" },
    { key = "TOPRIGHT",    label = "Top Right" },
    { key = "BOTTOMLEFT",  label = "Bottom Left" },
    { key = "BOTTOMRIGHT", label = "Bottom Right" },
    { key = "BELOW_ICON",  label = "Below Icon" },
    { key = "ABOVE_ICON",  label = "Above Icon" },
}

function UI.CreateTextAnchorDropdown(parent, labelText, get, set)
    return UI.CreateDropdownLikeList(parent, labelText, ANCHOR_POINTS, get, set)
end

local FONT_KEY_TO_PATH = {
    ["default"]    = "Fonts\\FRIZQT__.TTF",
    ["morpheus"]   = "Fonts\\MORPHEUS.TTF",
    ["skyline"]    = "Fonts\\skurri.TTF",
    ["arialn"]     = "Fonts\\ARIALN.TTF",
    ["accidental"] = "Fonts\\ARIALN.TTF",
}

local LEGACY_KEY_TO_LSM = {
    ["default"]  = "Friz Quadrata TT",
    ["plexmono"] = "IBM Plex Mono",
    ["morpheus"] = "Morpheus",
    ["skyline"]  = "Skurri",
    ["arialn"]   = "Arial Narrow",
}

function UI.ResolveFontPath(key)
    if not key or key == "default" or key == "GLOBAL" then key = ns:GetGlobalStyle().font or key end
    if key == nil or key == "" then return Theme.font.fallback end
    if type(key) == "string" and (key:find("\\", 1, true) or key:find("/", 1, true)) then
        return key
    end
    if key == "plexmono" then return Theme.font.regular end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true) or nil
    if LSM then
        local lsmName = LEGACY_KEY_TO_LSM[key] or key
        local found = LSM:Fetch("font", lsmName, true)
        if found then return found end
    end
    return FONT_KEY_TO_PATH[key] or Theme.font.fallback
end

UI.FONT_KEY_TO_PATH = FONT_KEY_TO_PATH

local function lsmFontValues(currentRaw)
    local values = {}
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true) or nil
    local seen = {}
    if LSM then
        local list = LSM:List("font")
        if type(list) == "table" then
            local sorted = {}
            for i = 1, #list do sorted[#sorted + 1] = list[i] end
            table.sort(sorted)
            for i = 1, #sorted do
                values[#values + 1] = { key = sorted[i], label = sorted[i] }
                seen[sorted[i]] = true
            end
        end
    end
    if #values == 0 then
        values[1] = { key = "Friz Quadrata TT", label = "Friz Quadrata TT" }
        seen["Friz Quadrata TT"] = true
    end
    if type(currentRaw) == "string" and currentRaw ~= "" and not seen[currentRaw] then
        if currentRaw:find("\\", 1, true) or currentRaw:find("/", 1, true) then
            values[#values + 1] = { key = currentRaw, label = "Custom (saved path)" }
        elseif LEGACY_KEY_TO_LSM[currentRaw] == nil and FONT_KEY_TO_PATH[currentRaw] == nil then
            values[#values + 1] = { key = currentRaw, label = currentRaw }
        end
    end
    return values
end

local function fontDisplayKey(stored)
    if stored == nil or stored == "" then
        return "Friz Quadrata TT"
    end
    if type(stored) ~= "string" then return stored end
    if stored:find("\\", 1, true) or stored:find("/", 1, true) then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true) or nil
        if LSM then
            local tbl = LSM:HashTable("font")
            if type(tbl) == "table" then
                for name, path in pairs(tbl) do
                    if path == stored then return name end
                end
            end
        end
        return stored
    end
    local mapped = LEGACY_KEY_TO_LSM[stored]
    if mapped then return mapped end
    if stored == "accidental" then return "Arial Narrow" end
    return stored
end

function UI.CreateFontDropdown(parent, labelText, get, set, globalPicker)
    local current = type(get) == "function" and get() or nil
    local values = lsmFontValues(current)
    if not globalPicker then table.insert(values, 1, { key = "default", label = "Global default" }) end
    return UI.CreateDropdownLikeList(parent, labelText, values,
        function()
            local v = type(get) == "function" and get() or nil
            if not globalPicker and (not v or v == "default") then return "default" end
            return fontDisplayKey(v)
        end,
        set
    )
end

local OUTLINE_LIST = {
    { key = "",             label = "None" },
    { key = "OUTLINE",      label = "Outline" },
    { key = "THICKOUTLINE", label = "Thick Outline" },
}

function UI.CreateOutlineDropdown(parent, labelText, get, set, globalPicker)
    local values = OUTLINE_LIST
    if not globalPicker then
        values = { { key = "GLOBAL", label = "Global default" }, unpack(OUTLINE_LIST) }
    end
    return UI.CreateDropdownLikeList(parent, labelText or "Outline", values, get, set)
end

local function barfxStatusbarSet()
    local set, order = {}, {}
    local forces = UI.BarFXForces
    if type(forces) == "table" then
        for i = 1, #forces do
            local key = "TenUI " .. forces[i]
            set[key] = forces[i]
            order[#order + 1] = key
        end
    end
    return set, order
end

local function lsmStatusbarValues(currentRaw)
    local values = {}
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true) or nil
    if LSM then
        local barfxSet, barfxOrder = barfxStatusbarSet()
        local list = LSM:List("statusbar")
        if type(list) == "table" then
            local sorted = {}
            for i = 1, #list do
                if not barfxSet[list[i]] then sorted[#sorted + 1] = list[i] end
            end
            table.sort(sorted)
            for i = 1, #sorted do
                values[#values + 1] = { key = sorted[i], label = sorted[i] }
            end
        end
        local hash = LSM:HashTable("statusbar")
        if type(hash) == "table" then
            for i = 1, #barfxOrder do
                local key = barfxOrder[i]
                if hash[key] then
                    values[#values + 1] = { key = key, label = barfxSet[key] }
                end
            end
        end
    end
    if #values == 0 then
        values[1] = { key = "Interface\\TargetingFrame\\UI-StatusBar", label = "Blizzard (default)" }
    end
    if type(currentRaw) == "string"
       and (currentRaw:find("\\", 1, true) or currentRaw:find("/", 1, true)) then
        local found = false
        if LSM then
            local tbl = LSM:HashTable("statusbar")
            if type(tbl) == "table" then
                for _, path in pairs(tbl) do
                    if path == currentRaw then found = true break end
                end
            end
        end
        if not found then
            values[#values + 1] = { key = currentRaw, label = "Custom (saved path)" }
        end
    end
    return values
end

local function statusbarDisplayKey(stored)
    if type(stored) ~= "string" or stored == "" then return stored end
    if not (stored:find("\\", 1, true) or stored:find("/", 1, true)) then
        return stored
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true) or nil
    if LSM then
        local tbl = LSM:HashTable("statusbar")
        if type(tbl) == "table" then
            for name, path in pairs(tbl) do
                if path == stored then return name end
            end
        end
    end
    return stored
end

function UI.CreateStatusBarTextureDropdown(parent, labelText, get, set, globalPicker)
    local current = type(get) == "function" and get() or nil
    local values = lsmStatusbarValues(current)
    if not globalPicker then table.insert(values, 1, { key = "default", label = "Global default" }) end
    return UI.CreateDropdownLikeList(parent, labelText, values,
        function()
            local v = type(get) == "function" and get() or nil
            if not v or v == "" then return globalPicker and "Blizzard" or "default" end
            return statusbarDisplayKey(v)
        end,
        set
    )
end

function UI.CreateIconButton(parent, data, callbacks)
    data      = data      or {}
    callbacks = callbacks or {}
    local SIZE = 32
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(SIZE, SIZE)
    f:EnableMouse(true)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local bg = UI.Rect(f, "BACKGROUND", C_INPUT)
    bg:SetAllPoints(f)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT",     f, "TOPLEFT",     2, -2)
    icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    if data.texture then
        icon:SetTexture(data.texture)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        icon:SetColorTexture(0.18, 0.20, 0.28, 1)
    end

    local border = UI.Border(f, C_LINE)

    if not data.isKnown then
        icon:SetDesaturated(true)
        icon:SetAlpha(0.5)
    end

    f:SetScript("OnClick", function(self, button)
        if button == "LeftButton" and type(callbacks.onClick) == "function" then
            pcall(callbacks.onClick, data)
        elseif button == "RightButton" and type(callbacks.onRightClick) == "function" then
            pcall(callbacks.onRightClick, data)
        end
    end)

    f:SetScript("OnEnter", function(self)
        border.SetColor(unpack(Theme.color.violet))
        if type(callbacks.onEnter) == "function" then
            pcall(callbacks.onEnter, self, data)
        else
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local name = data.label or (data.spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(data.spellID)) or "?"
            GameTooltip:SetText(tostring(name))
            if data.spellID then
                GameTooltip:AddLine("Spell ID: " .. tostring(data.spellID), 0.7, 0.7, 0.7)
            end
            if data.source then
                GameTooltip:AddLine("Source: " .. tostring(data.source), 0.7, 0.7, 0.7)
            end
            if data.isKnown == false then
                GameTooltip:AddLine("Not learned", 1, 0.5, 0.5)
            end
            GameTooltip:AddLine("Left-click: add to bar  Right-click: settings", 0.6, 0.6, 1)
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function(self)
        border.SetColor(unpack(C_LINE))
        if type(callbacks.onLeave) == "function" then
            pcall(callbacks.onLeave, self)
        else
            GameTooltip:Hide()
        end
    end)

    f.iconTex = icon
    f.data    = data
    return f
end

function UI.CreateIconGrid(parent, items, callbacks)
    local ICON_SIZE  = 32
    local ICON_GAP   = 4
    local pw = parent:GetWidth()
    if not pw or pw <= 0 then pw = 320 end
    local cols = math_floor(pw / (ICON_SIZE + ICON_GAP))
    if cols < 1 then cols = 1 end

    local frames = {}
    for idx, item in ipairs(items or {}) do
        local col = (idx - 1) % cols
        local row = math_floor((idx - 1) / cols)
        local btn = UI.CreateIconButton(parent, item, callbacks)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT",
            col * (ICON_SIZE + ICON_GAP),
            -row * (ICON_SIZE + ICON_GAP))
        frames[#frames + 1] = btn
    end
    return frames
end

function UI.CreateTwoColumnRow(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(ROW_W, ROW_H)

    local col1 = CreateFrame("Frame", nil, f)
    col1:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    col1:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    col1:SetWidth(ROW_W / 2)

    local col2 = CreateFrame("Frame", nil, f)
    col2:SetPoint("TOPRIGHT",    f, "TOPRIGHT",    0, 0)
    col2:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    col2:SetWidth(ROW_W / 2)

    f:SetScript("OnSizeChanged", function(self, w)
        if w and w > 0 then
            col1:SetWidth(w / 2)
            col2:SetWidth(w / 2)
        end
    end)

    f.col1 = col1
    f.col2 = col2
    return f
end

function UI.ClearChildren(frame)
    if not frame then return end
    local children = { frame:GetChildren() }
    for i = 1, #children do
        if children[i] and children[i].Hide then
            pcall(children[i].Hide, children[i])
        end
        if children[i] and children[i].SetParent then
            pcall(children[i].SetParent, children[i], nil)
        end
    end
    local regions = { frame:GetRegions() }
    for i = 1, #regions do
        if regions[i] and regions[i].Hide then
            pcall(regions[i].Hide, regions[i])
        end
    end
end

function UI.LayoutVertical(parent, children, spacing, startY)
    spacing = spacing or 6
    startY  = startY  or -8
    local y = startY
    local pw = parent:GetWidth()
    if not pw or pw <= 0 then pw = ROW_W end
    local usable, gap = pw - 16, 14
    local i = 1
    while i <= #children do
        local first = children[i]
        local count = 1
        local kind = first.layoutKind
        local columns = (kind == "chip" or kind == "color" or kind == "action") and 3 or 2
        if kind then
            for n = 2, columns do
                local candidate = children[i+n-1]
                if not candidate then break end
                local toggleColor = n == 2 and kind == "toggle" and candidate.layoutKind == "color"
                if candidate.layoutKind ~= kind and not toggleColor then break end
                local width = (usable - (n-1)*gap) / n
                local fits = true
                for k = i, i+n-1 do
                    local item = children[k]
                    local textWidth = item.label and item.label:GetStringWidth() or 0
                    if textWidth + (item.controlWidth or 16) > width then fits = false break end
                end
                if not fits then break end
                count = n
            end
        end
        local width, h = (usable-gap*(count-1))/count, 0
        for n = 1, count do
            local c = children[i+n-1]
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", parent, "TOPLEFT", 8+(n-1)*(width+gap), y)
            c:SetWidth(width)
            if c.AutoHeight then c.AutoHeight() end
            h = math_max(h, c:GetHeight() or ROW_H)
        end
        y = y - h - spacing
        i = i + count
    end
    return math.abs(y) + 8
end

ns.Controls = ns.Controls or {}
ns.Controls.ResolveFontPath = UI.ResolveFontPath
