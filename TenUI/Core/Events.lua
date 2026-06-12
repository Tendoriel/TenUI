local addonName, ns = ...

local CreateFrame = CreateFrame
local pairs = pairs
local tinsert = table.insert
local tremove = table.remove

local dispatcher = CreateFrame("Frame", "TenUIEventFrame")
ns.eventFrame = dispatcher

local function dispatch(event, ...)
    local handlers = ns.eventHandlers[event]
    if not handlers then return end
    for i = 1, #handlers do
        local h = handlers[i]
        if h then
            local ok, err = pcall(h, event, ...)
            if not ok then
                if ns.Debug and ns.Debug.Log then
                    ns.Debug:Log("Event handler error for %s: %s", event, tostring(err))
                else
                    geterrorhandler()(err)
                end
            end
        end
    end
end

dispatcher:SetScript("OnEvent", function(self, event, ...)
    dispatch(event, ...)
end)

function ns:RegisterEvent(event, handler)
    if type(event) ~= "string" or event == "" then
        error("RegisterEvent: event must be a non-empty string", 2)
    end
    if type(handler) ~= "function" then
        error("RegisterEvent: handler must be a function", 2)
    end
    local list = self.eventHandlers[event]
    if not list then
        list = {}
        self.eventHandlers[event] = list
        dispatcher:RegisterEvent(event)
    end
    tinsert(list, handler)
    return handler
end

function ns:UnregisterEvent(event, handler)
    local list = self.eventHandlers[event]
    if not list then return false end
    for i = #list, 1, -1 do
        if list[i] == handler then
            tremove(list, i)
        end
    end
    if #list == 0 then
        self.eventHandlers[event] = nil
        dispatcher:UnregisterEvent(event)
    end
    return true
end

function ns:RegisterMessage(message, handler)
    if type(message) ~= "string" or message == "" then
        error("RegisterMessage: message must be a non-empty string", 2)
    end
    if type(handler) ~= "function" then
        error("RegisterMessage: handler must be a function", 2)
    end
    local list = self.customEventHandlers[message]
    if not list then
        list = {}
        self.customEventHandlers[message] = list
    end
    tinsert(list, handler)
    return handler
end

function ns:UnregisterMessage(message, handler)
    local list = self.customEventHandlers[message]
    if not list then return false end
    for i = #list, 1, -1 do
        if list[i] == handler then
            tremove(list, i)
        end
    end
    return true
end

function ns:Fire(message, ...)
    local list = self.customEventHandlers[message]
    if not list then return end
    for i = 1, #list do
        local h = list[i]
        if h then
            local ok, err = pcall(h, message, ...)
            if not ok then
                if ns.Debug and ns.Debug.Log then
                    ns.Debug:Log("Message handler error for %s: %s", message, tostring(err))
                else
                    geterrorhandler()(err)
                end
            end
        end
    end
end

ns:RegisterEvent("ADDON_LOADED", function(event, loadedName)
    if loadedName ~= addonName then return end
    ns:InitializeSavedVars()
    if ns.Debug and ns.Debug.OnSavedVarsReady then
        ns.Debug:OnSavedVarsReady()
    end
    ns:Fire("SAVEDVARS_READY")
end)

ns:RegisterEvent("PLAYER_LOGIN", function()
    ns:EnableAllModules()
    if ns.Debug and ns.Debug.Log then
        ns.Debug:Log("PLAYER_LOGIN: TenUI v%s loaded", tostring(ns.version))
    end
    DEFAULT_CHAT_FRAME:AddMessage(("|cff4fc3f7TenUI|r v%s loaded. Type |cffffd200/tenui|r for commands."):format(tostring(ns.version)))
    ns:Fire("READY")
end)

ns:RegisterEvent("PLAYER_LOGOUT", function()
    ns:DisableAllModules()
    ns:Fire("SHUTDOWN")
end)
