local addonName, ns = ...

local function deepCopyMissing(dst, src)
    if type(src) ~= "table" then return end
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            deepCopyMissing(dst[k], v)
        else
            if dst[k] == nil then
                dst[k] = v
            end
        end
    end
end

function ns:RegisterModule(name, def)
    if type(name) ~= "string" or name == "" then
        error("RegisterModule: name must be a non-empty string", 2)
    end
    if type(def) ~= "table" then
        error("RegisterModule: def must be a table", 2)
    end
    if self.modules[name] then
        error("RegisterModule: module already registered: " .. name, 2)
    end

    def.name = name
    def.enabled = false
    self.modules[name] = def

    if self.savedVarsReady and def.defaults then
        local profile = self:GetProfile()
        profile.modules = profile.modules or {}
        profile.modules[name] = profile.modules[name] or {}
        deepCopyMissing(profile.modules[name], def.defaults)
    end

    return def
end

function ns:GetModule(name)
    return self.modules[name]
end

function ns:IterateModules()
    return pairs(self.modules)
end

function ns:EnableModule(name)
    local mod = self.modules[name]
    if not mod then return false end
    if mod.enabled then return true end

    local profile = self:GetProfile()
    profile.modules = profile.modules or {}
    profile.modules[name] = profile.modules[name] or {}

    if mod.defaults then
        deepCopyMissing(profile.modules[name], mod.defaults)
    end

    mod.enabled = true
    if type(mod.OnEnable) == "function" then
        local ok, err = pcall(mod.OnEnable, mod, profile.modules[name])
        if not ok then
            mod.enabled = false
            if ns.Debug and ns.Debug.Log then
                ns.Debug:Log("EnableModule(%s) failed: %s", name, tostring(err))
            else
                geterrorhandler()(err)
            end
            return false
        end
    end
    return true
end

function ns:DisableModule(name)
    local mod = self.modules[name]
    if not mod then return false end
    if not mod.enabled then return true end
    mod.enabled = false
    if type(mod.OnDisable) == "function" then
        local ok, err = pcall(mod.OnDisable, mod)
        if not ok then
            if ns.Debug and ns.Debug.Log then
                ns.Debug:Log("DisableModule(%s) failed: %s", name, tostring(err))
            else
                geterrorhandler()(err)
            end
            return false
        end
    end
    return true
end

function ns:EnableAllModules()
    for name in pairs(self.modules) do
        self:EnableModule(name)
    end
end

function ns:DisableAllModules()
    for name, mod in pairs(self.modules) do
        if mod.enabled then
            self:DisableModule(name)
        end
    end
end

ns._deepCopyMissing = deepCopyMissing
