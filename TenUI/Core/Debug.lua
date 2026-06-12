local addonName, ns = ...

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local date = date
local tinsert = table.insert
local tremove = table.remove
local tconcat = table.concat
local format = string.format
local select = select
local type = type
local tostring = tostring
local pcall = pcall
local pairs = pairs

local REFRESH_INTERVAL = 0.5

local DEFAULT_MAX_LINES = 300

local Debug = {}
ns.Debug = Debug

local frame
local pendingLogs = {}

Debug._paused = false

Debug._dirty = false
Debug._refreshScheduled = false

local function _isSecret(v)
    return type(issecretvalue) == "function" and issecretvalue(v)
end

local function _scrub(line, indexHint)
    if _isSecret(line) then
        if indexHint then
            return "[secret-tainted line " .. tostring(indexHint) .. " dropped]"
        end
        return "[secret-tainted message dropped]"
    end
    return line
end

local function maxLines()
    if ns.db and ns.db.debug and type(ns.db.debug.maxLines) == "number" and ns.db.debug.maxLines > 0 then
        return ns.db.debug.maxLines
    end
    return DEFAULT_MAX_LINES
end

local function ensureLogTable()
    if ns.db and ns.db.debug then
        ns.db.debug.log = ns.db.debug.log or {}
        return ns.db.debug.log
    end
    return nil
end

local function scrubLogTable(log)
    if not log then return end
    local maxIdx = 0
    for k in pairs(log) do
        if type(k) == "number" and k > maxIdx then
            maxIdx = k
        end
    end
    local dense = {}
    for i = 1, maxIdx do
        local v = log[i]
        if v == nil then
            dense[#dense + 1] = "[entry " .. i .. " dropped]"
        elseif _isSecret(v) then
            dense[#dense + 1] = "[secret-tainted line " .. i .. " dropped]"
        else
            dense[#dense + 1] = v
        end
    end
    for k in pairs(log) do
        log[k] = nil
    end
    for i = 1, #dense do
        log[i] = dense[i]
    end
end

local function scheduleRefresh()
    if Debug._paused then return end
    if not (frame and frame:IsShown()) then return end
    Debug._dirty = true
    if Debug._refreshScheduled then return end
    Debug._refreshScheduled = true
    if C_Timer and C_Timer.After then
        C_Timer.After(REFRESH_INTERVAL, function()
            Debug._refreshScheduled = false
            if Debug._paused then return end
            if Debug._dirty and frame and frame:IsShown() then
                Debug._dirty = false
                Debug:Refresh()
            end
        end)
    else
        Debug._refreshScheduled = false
        Debug._dirty = false
        Debug:Refresh()
    end
end

local function pushLine(line)
    if Debug._paused then return end
    line = _scrub(line)
    if line == nil then
        line = "[nil log entry]"
    elseif type(line) ~= "string" then
        line = tostring(line)
    end
    local cap = maxLines()
    local log = ensureLogTable()
    if log then
        tinsert(log, line)
        while #log > cap do
            tremove(log, 1)
        end
    else
        tinsert(pendingLogs, line)
        while #pendingLogs > cap do
            tremove(pendingLogs, 1)
        end
    end
    scheduleRefresh()
end

local function formatMessage(fmt, ...)
    local msg
    if select("#", ...) == 0 then
        msg = tostring(fmt)
    else
        local ok, formatted = pcall(format, tostring(fmt), ...)
        if ok then
            msg = formatted
        else
            local parts = { tostring(fmt) }
            for i = 1, select("#", ...) do
                local v = (select(i, ...))
                if _isSecret(v) then
                    parts[#parts + 1] = "<secret>"
                else
                    parts[#parts + 1] = tostring(v)
                end
            end
            msg = tconcat(parts, " ")
        end
    end
    if _isSecret(msg) then
        msg = "[secret-tainted message dropped]"
    end
    return msg
end

local function emit(prefix, msg)
    local stamp = date("%H:%M:%S")
    local line = stamp .. "  " .. prefix .. " " .. msg
    if ns.db and ns.db.debug and ns.db.debug.chat then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cff9a9a9aTHUD|r " .. line)
        end
    end
    pushLine(line)
end

function Debug:Error(fmt, ...)
    emit("[ERROR]", formatMessage(fmt, ...))
end

function Debug:Warn(fmt, ...)
    emit("[WARN]", formatMessage(fmt, ...))
end

function Debug:Info(fmt, ...)
    emit("[INFO]", formatMessage(fmt, ...))
end

function Debug:Verbose(module, fmt, ...)
    local key = tostring(module)
    if not (ns.db and ns.db.debug and ns.db.debug.verbose and ns.db.debug.verbose[key]) then
        return
    end
    emit("[V:" .. key .. "]", formatMessage(fmt, ...))
end

function Debug:Trace(module, fmt, ...)
    local key = tostring(module)
    if not (ns.db and ns.db.debug and ns.db.debug.trace and ns.db.debug.trace[key]) then
        return
    end
    emit("[T:" .. key .. "]", formatMessage(fmt, ...))
end

function Debug:Log(fmt, ...)
    emit("[INFO]", formatMessage(fmt, ...))
end

function Debug:IsVerbose(module)
    local key = tostring(module)
    return (ns.db and ns.db.debug and ns.db.debug.verbose and ns.db.debug.verbose[key]) and true or false
end

function Debug:IsTrace(module)
    local key = tostring(module)
    return (ns.db and ns.db.debug and ns.db.debug.trace and ns.db.debug.trace[key]) and true or false
end

function Debug:Pause()
    self._paused = true
    if frame and frame.UpdateTitle then
        frame:UpdateTitle()
    end
end

function Debug:Resume()
    if not self._paused then return end
    self._paused = false
    if frame and frame.UpdateTitle then
        frame:UpdateTitle()
    end
    if frame and frame:IsShown() then
        self._dirty = false
        self:Refresh()
    end
end

function Debug:IsPaused()
    return self._paused and true or false
end

function Debug:Clear()
    local log = ensureLogTable()
    if log then
        for i = #log, 1, -1 do
            log[i] = nil
        end
    end
    for i = #pendingLogs, 1, -1 do
        pendingLogs[i] = nil
    end
    if frame then
        self._dirty = false
        self:Refresh()
    end
end

function Debug:EnsureDefaults()
    if not ns.db then return end
    if type(ns.db.debug) ~= "table" then
        ns.db.debug = {}
    end
    local d = ns.db.debug
    if d.enabled == nil then d.enabled = false end
    if type(d.log) ~= "table" then d.log = {} end
    if type(d.verbose) ~= "table" then d.verbose = {} end
    if type(d.trace) ~= "table" then d.trace = {} end
    if d.chat == nil then d.chat = false end
    if type(d.maxLines) ~= "number" or d.maxLines <= 0 then d.maxLines = DEFAULT_MAX_LINES end
end

function Debug:OnSavedVarsReady()
    if not (ns.db and ns.db.debug) then return end
    self:EnsureDefaults()
    local log = ensureLogTable()
    if not log then return end
    scrubLogTable(log)
    scrubLogTable(pendingLogs)
    local cap = maxLines()
    for i = 1, #pendingLogs do
        local entry = pendingLogs[i]
        tinsert(log, _scrub(entry))
        while #log > cap do
            tremove(log, 1)
        end
    end
    for i = #pendingLogs, 1, -1 do
        pendingLogs[i] = nil
    end
    while #log > cap do
        tremove(log, 1)
    end
end

local function savePosition(f)
    if not (ns.db and ns.db.debug) then return end
    local point, _, relativePoint, x, y = f:GetPoint(1)
    ns.db.debug.point = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

local function restorePosition(f)
    f:ClearAllPoints()
    if ns.db and ns.db.debug and ns.db.debug.point then
        local p = ns.db.debug.point
        f:SetPoint(p.point or "CENTER", UIParent, p.relativePoint or "CENTER", p.x or 0, p.y or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function createFrame()
    local f = CreateFrame("Frame", "TenUIDebugFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(600, 400)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition(self)
    end)

    if f.TitleBg then
        f.TitleBg:SetHeight(30)
    end
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", f.TitleBg or f, "TOPLEFT", 6, -4)
    title:SetText("TenUI Debug Log")
    f.title = title

    function f:UpdateTitle()
        if Debug._paused then
            self.title:SetText("TenUI Debug Log  |cffffd200[PAUSED]|r")
        else
            self.title:SetText("TenUI Debug Log")
        end
    end

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -28)
    hint:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -28)
    hint:SetJustifyH("LEFT")
    hint:SetText("Click in the text area, Cmd+A to select all, Cmd+C to copy.")
    f.hint = hint

    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(70, 20)
    clearBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 6)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        Debug:Clear()
    end)
    f.clearBtn = clearBtn

    local scroll = CreateFrame("ScrollFrame", "TenUIDebugScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -46)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 30)
    f.scroll = scroll

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(scroll:GetWidth())
    edit:SetMaxLetters(0)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnTextChanged", function(self) self:HighlightText(0, 0) end)
    scroll:SetScrollChild(edit)
    f.editBox = edit

    scroll:SetScript("OnSizeChanged", function(self, w, h)
        edit:SetWidth(w)
    end)

    f:SetScript("OnShow", function(self)
        if self.UpdateTitle then self:UpdateTitle() end
        Debug._dirty = false
        Debug:Refresh()
    end)

    restorePosition(f)
    f:Hide()
    return f
end

function Debug:GetFrame()
    if not frame then
        frame = createFrame()
    end
    return frame
end

function Debug:Refresh()
    local f = frame or self:GetFrame()
    local log = ensureLogTable()
    local lines = log or pendingLogs
    local maxIdx = 0
    for k in pairs(lines) do
        if type(k) == "number" and k > maxIdx then
            maxIdx = k
        end
    end
    local safe = {}
    for i = 1, maxIdx do
        local v = lines[i]
        if v == nil then
            safe[#safe + 1] = "[entry " .. i .. " dropped]"
        elseif _isSecret(v) then
            safe[#safe + 1] = "[secret-tainted line " .. i .. " dropped]"
        else
            safe[#safe + 1] = v
        end
    end
    local ok, text = pcall(tconcat, safe, "\n")
    if not ok then
        text = "[Debug:Refresh concat failed: " .. tostring(text) .. "]"
    end
    f.editBox:SetText(text)
end

function Debug:Show()
    local f = self:GetFrame()
    restorePosition(f)
    f:Show()
end

function Debug:Hide()
    if frame then frame:Hide() end
end

function Debug:Toggle()
    local f = self:GetFrame()
    if f:IsShown() then
        f:Hide()
    else
        self:Show()
    end
end
