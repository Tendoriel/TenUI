local _, ns = ...
local catalog = {}
local function record(page, tab, label)
    if not label or label == "" then return end
    tab = tab or ""
    local id = page .. "/" .. tab .. "/" .. label:lower()
    catalog[id] = { page = page, tab = tab, label = label }
end
for _, group in ipairs(ns.SearchCatalog) do
    for label in group.labels:gmatch("[^\n]+") do record(group.page, group.tab, label) end
end

local function rowLabel(row)
    local label = row.label or row.text
    if label and label.GetText and (row.label or row.searchHeading) then return label:GetText() end
end

function ns.IndexSettingsPage(page, sc)
    local tab = sc.searchTab or ""
    for _, row in ipairs({sc:GetChildren()}) do record(page, tab, rowLabel(row)) end
end

function ns.AddSettingsSearch(header, pageMap, closeButton)
    local UI = ns.UI
    local colors = UI.Theme.color
    local input = CreateFrame("EditBox", nil, header)
    input:SetAutoFocus(false)
    input:SetSize(185, 20)
    input:SetPoint("RIGHT", closeButton, "LEFT", -10, 0)
    input:SetFontObject(UI.Fonts.value)
    input:SetTextColor(unpack(colors.textBright))
    input:SetTextInsets(8, 8, 0, 0)
    input:SetMaxLetters(100)
    UI.Rect(input, "BACKGROUND", colors.input):SetAllPoints()
    local border = UI.Border(input, colors.lineSoft)
    input:SetScript("OnEditFocusGained", function() border.SetColor(unpack(colors.accent)) end)
    input:SetScript("OnEditFocusLost", function() border.SetColor(unpack(colors.lineSoft)) end)
    local hint = UI.Text(input, UI.Fonts.value, colors.textDim, "Search settings…")
    hint:SetPoint("LEFT", 8, 0)
    local panel = CreateFrame("Frame", nil, input)
    panel:SetFrameStrata("TOOLTIP")
    panel:SetPoint("TOPRIGHT", input, "BOTTOMRIGHT", 0, -3)
    panel:SetSize(375, 26)
    ns.UI.SkinPanel(panel)
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:Hide()
    local buttons, matches, offset = {}, {}, 0
    local function open(hit)
        if not hit or InCombatLockdown() then return end
        input:ClearFocus()
        input:SetText("")
        if hit.page == "layout" and hit.tab ~= "" then
            ns.Options:OpenLayoutForAnchor(hit.tab)
        else
            if hit.tab ~= "" then ns:GetUIState().lastOptionsSub[hit.page] = hit.tab end
            ns.Options:SelectPage(hit.page, true)
        end
        local page = pageMap[hit.page]
        if not page or not page.scrollChild then return end
        C_Timer.After(0, function()
            for _, row in ipairs({page.scrollChild:GetChildren()}) do
                local label = rowLabel(row)
                if label and label:lower() == hit.label:lower() and row:GetTop() then
                    page.scrollFrame:SetVerticalScroll(math.max(0, math.min(page.scrollFrame:GetVerticalScrollRange(), page.scrollChild:GetTop()-row:GetTop()-6)))
                    local highlight = row.searchHighlight or ns.UI.Rect(row, "BACKGROUND", {0.48,0.39,0.94,0.25})
                    row.searchHighlight = highlight
                    highlight:SetAllPoints()
                    highlight:Show()
                    C_Timer.After(1.5, function() highlight:Hide() end)
                    return
                end
            end
        end)
    end
    local function render()
        local n = math.min(8,#matches)
        panel:SetHeight(math.max(n,1)*24+8)
        for i=1,8 do
            local b = buttons[i]
            if not b then
                b = ns.UI.CreateCompactButton(panel, "", function() open(buttons[i].hit) end, 367)
                b:SetPoint("TOPLEFT", 4, -4-(i-1)*24)
                buttons[i] = b
            end
            local hit = matches[offset+i]
            b.hit = hit
            b:SetShown(hit ~= nil or (i == 1 and n == 0))
            if hit then b.label:SetText(pageMap[hit.page].def.label .. "  /  " .. hit.label)
            elseif i == 1 then b.label:SetText("No matching settings") end
        end
        panel:Show()
    end
    input:SetScript("OnTextChanged", function()
        local query = (input:GetText() or ""):lower()
        hint:SetShown(query == "")
        if query == "" then panel:Hide() return end
        matches, offset = {}, 0
        for _, hit in pairs(catalog) do
            local page = pageMap[hit.page]
            if page and (hit.label .. " " .. page.def.label .. " " .. hit.tab):lower():find(query,1,true) then matches[#matches+1]=hit end
        end
        table.sort(matches,function(a,b)
            local x,y = a.label:lower(),b.label:lower()
            if (x:sub(1,#query)==query) ~= (y:sub(1,#query)==query) then return x:sub(1,#query)==query end
            if x == y then return a.page .. a.tab < b.page .. b.tab end
            return x < y
        end)
        render()
    end)
    panel:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0,math.min(math.max(0,#matches-8),offset-delta))
        render()
    end)
    input:SetScript("OnEnterPressed",function() open(matches[offset+1]) end)
    input:SetScript("OnEscapePressed",function() input:SetText("") input:ClearFocus() end)
    input:SetScript("OnHide",function() input:SetText("") input:ClearFocus() end)
    return input
end
