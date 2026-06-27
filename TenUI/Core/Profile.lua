local addonName, ns = ...

local GetSpecialization     = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local UnitName              = UnitName
local GetRealmName          = GetRealmName

function ns:GetProfileKey()
    if self.db and self.db.activeProfile then
        return self.db.activeProfile
    end
    return "Default"
end

function ns:GetCharKey()
    local name = UnitName and UnitName("player")
    local realm = GetRealmName and GetRealmName()
    if type(name) ~= "string" or name == "" then return nil end
    if type(realm) ~= "string" then realm = "" end
    return name .. " - " .. realm
end

local function profileOrderContains(order, name)
    for i = 1, #order do
        if order[i] == name then return i end
    end
    return nil
end

function ns:_EnsureProfileOrder()
    if not self.db then return nil end
    self.db.profiles = self.db.profiles or {}
    if type(self.db.profileOrder) ~= "table" then
        self.db.profileOrder = {}
    end
    local order = self.db.profileOrder
    local seen = {}
    for i = #order, 1, -1 do
        local n = order[i]
        if type(n) ~= "string" or not self.db.profiles[n] or seen[n] then
            table.remove(order, i)
        else
            seen[n] = true
        end
    end
    if self.db.profiles["Default"] and not seen["Default"] then
        table.insert(order, 1, "Default")
        seen["Default"] = true
    end
    local missing = {}
    for n in pairs(self.db.profiles) do
        if type(n) == "string" and not seen[n] then
            missing[#missing + 1] = n
        end
    end
    table.sort(missing)
    for i = 1, #missing do
        order[#order + 1] = missing[i]
    end
    return order
end

function ns:_AddProfileToOrder(name)
    if not self.db or type(name) ~= "string" then return end
    self.db.profileOrder = self.db.profileOrder or {}
    if not profileOrderContains(self.db.profileOrder, name) then
        self.db.profileOrder[#self.db.profileOrder + 1] = name
    end
end

function ns:_RemoveProfileFromOrder(name)
    if not self.db or type(self.db.profileOrder) ~= "table" then return end
    local i = profileOrderContains(self.db.profileOrder, name)
    if i then table.remove(self.db.profileOrder, i) end
end

function ns:GetSpecScopeKey()
    local class
    if UnitClass then
        local ok, _, c = pcall(UnitClass, "player")
        if ok then class = c end
    end
    if type(class) ~= "string" or class == "" then class = "UNKNOWN" end
    local specIdx
    if GetSpecialization then
        local ok, s = pcall(GetSpecialization)
        if ok then specIdx = s end
    end
    if type(specIdx) == "number" and specIdx > 0 then
        return class .. "_" .. tostring(specIdx)
    end
    return class .. "_NIL"
end

function ns:GetSpecScope(domain, create)
    if not self.savedVarsReady then return nil end
    local p = self:GetProfile()
    if type(p) ~= "table" then return nil end
    local key = self:GetSpecScopeKey()
    if not create then
        local scopes = p.specScopes
        if type(scopes) ~= "table" then return nil, key end
        local scope = scopes[key]
        if type(scope) ~= "table" then return nil, key end
        return scope[domain], key
    end
    p.specScopes = p.specScopes or {}
    p.specScopes[key] = p.specScopes[key] or {}
    p.specScopes[key][domain] = p.specScopes[key][domain] or {}
    return p.specScopes[key][domain], key
end

function ns:GetProfile()
    local key = self:GetProfileKey()
    if not self.db then
        return {}
    end
    self.db.profiles = self.db.profiles or {}
    if not self.db.profiles[key] then
        self.db.profiles[key] = { modules = {} }
    end
    self.db.profiles[key].modules = self.db.profiles[key].modules or {}
    return self.db.profiles[key]
end

function ns:SetActiveProfile(name)
    if not self.savedVarsReady or not self.db then return false end
    if type(name) ~= "string" or name == "" then return false end
    if InCombatLockdown() then
        if self.Debug and self.Debug.Log then
            self.Debug:Log("[Profile] SetActiveProfile('%s') blocked in combat", name)
        end
        return false
    end
    if not (self.db.profiles and self.db.profiles[name]) then return false end
    if self.db.activeProfile == name then return true end
    self.db.activeProfile = name
    self:Fire("PROFILE_CHANGED", name)
    return true
end

function ns:ListProfiles()
    local out = {}
    if not (self.db and self.db.profiles) then return out end
    local order = self:_EnsureProfileOrder()
    if type(order) == "table" then
        for i = 1, #order do
            if self.db.profiles[order[i]] then
                out[#out + 1] = order[i]
            end
        end
    end
    return out
end

function ns:AssignProfileToSpec(name, specID)
    if not self.savedVarsReady or not self.db then return false end
    if type(name) ~= "string" or name == "" then return false end
    if type(specID) ~= "number" or specID <= 0 then return false end
    if not (self.db.profiles and self.db.profiles[name]) then return false end
    self.db.specProfiles = self.db.specProfiles or {}
    self.db.specProfiles[specID] = name
    return true
end

function ns:UnassignSpec(specID)
    if not self.savedVarsReady or not self.db then return false end
    if type(specID) ~= "number" or specID <= 0 then return false end
    if type(self.db.specProfiles) ~= "table" then return false end
    self.db.specProfiles[specID] = nil
    return true
end

function ns:GetSpecProfile(specID)
    if not self.savedVarsReady or not self.db then return nil end
    if type(specID) ~= "number" or specID <= 0 then return nil end
    if type(self.db.specProfiles) ~= "table" then return nil end
    return self.db.specProfiles[specID]
end

function ns:ResolveSpecProfile()
    if not self.savedVarsReady or not self.db then return nil end
    local specProfiles = self.db.specProfiles
    if type(specProfiles) ~= "table" or next(specProfiles) == nil then return nil end

    local charKey = self:GetCharKey()
    if not charKey then return nil end
    self.db.lastSpecByChar = self.db.lastSpecByChar or {}

    local resolvedSpecID = self.db.lastSpecByChar[charKey]

    if not resolvedSpecID then
        local specIdx = GetSpecialization and GetSpecialization()
        if type(specIdx) == "number" and specIdx > 0 then
            local liveSpecID = GetSpecializationInfo and GetSpecializationInfo(specIdx)
            if type(liveSpecID) == "number" and liveSpecID > 0 then
                resolvedSpecID = liveSpecID
                self.db.lastSpecByChar[charKey] = resolvedSpecID
            end
        end
    end

    if not resolvedSpecID then return nil end

    local targetProfile = specProfiles[resolvedSpecID]
    if not targetProfile then return nil, resolvedSpecID, charKey end

    if not (self.db.profiles and self.db.profiles[targetProfile]) then
        return nil, resolvedSpecID, charKey
    end

    return targetProfile, resolvedSpecID, charKey
end

function ns:RenameProfile(oldName, newName)
    if not self.savedVarsReady or not self.db then return false, "saved variables not ready" end
    if type(oldName) ~= "string" or oldName == "" then return false, "invalid source name" end
    if type(newName) == "string" then
        newName = newName:gsub("^%s+", ""):gsub("%s+$", "")
    end
    if type(newName) ~= "string" or newName == "" then return false, "invalid new name" end
    if #newName > 48 then return false, "profile name too long (max 48 characters)" end
    if oldName == "Default" then return false, "cannot rename the Default profile" end
    if newName == "Default" then return false, "cannot rename to Default" end
    self.db.profiles = self.db.profiles or {}
    if not self.db.profiles[oldName] then return false, "source profile does not exist" end
    if oldName == newName then return true, newName end
    if self.db.profiles[newName] then return false, ("profile '%s' already exists"):format(newName) end

    self.db.profiles[newName] = self.db.profiles[oldName]
    self.db.profiles[oldName] = nil

    if type(self.db.profileOrder) == "table" then
        local i = profileOrderContains(self.db.profileOrder, oldName)
        if i then
            self.db.profileOrder[i] = newName
        else
            self:_AddProfileToOrder(newName)
        end
    end

    if type(self.db.specProfiles) == "table" then
        for specID, pName in pairs(self.db.specProfiles) do
            if pName == oldName then self.db.specProfiles[specID] = newName end
        end
    end

    if self.db.activeProfile == oldName then
        self.db.activeProfile = newName
        if not InCombatLockdown() then
            self:Fire("PROFILE_CHANGED", newName)
        end
    end

    if self.Debug and self.Debug.Log then
        self.Debug:Log("[Profile] Renamed '%s' -> '%s'", oldName, newName)
    end
    return true, newName
end

function ns:DeleteProfile(name)
    if not self.savedVarsReady or not self.db then return false, "saved variables not ready" end
    if type(name) ~= "string" or name == "" then return false, "invalid name" end
    if name == "Default" then return false, "cannot delete the Default profile" end
    self.db.profiles = self.db.profiles or {}
    if not self.db.profiles[name] then return false, "profile does not exist" end

    self.db.profiles[name] = nil
    self:_RemoveProfileFromOrder(name)

    if type(self.db.specProfiles) == "table" then
        for specID, pName in pairs(self.db.specProfiles) do
            if pName == name then self.db.specProfiles[specID] = nil end
        end
    end

    self.db.profiles["Default"] = self.db.profiles["Default"] or { modules = {} }
    self:_AddProfileToOrder("Default")

    if self.db.activeProfile == name then
        self.db.activeProfile = "Default"
        if not InCombatLockdown() then
            self:Fire("PROFILE_CHANGED", "Default")
        end
    end

    if self.Debug and self.Debug.Log then
        self.Debug:Log("[Profile] Deleted '%s'", name)
    end
    return true
end

local function deepCopyData(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            out[k] = deepCopyData(v)
        else
            out[k] = v
        end
    end
    return out
end

function ns:GetLayoutVisuals(anchorName, create)
    if not self.savedVarsReady then return nil end
    if type(anchorName) ~= "string" or anchorName == "" then return nil end
    local p = self:GetProfile()
    if type(p) ~= "table" then return nil end

    if not create then
        local overlay = self:GetSpecScope("layoutVisuals", false)
        if type(overlay) == "table" and type(overlay[anchorName]) == "table" then
            return overlay[anchorName]
        end
        local base = p.modules and p.modules.Layout and p.modules.Layout.visuals
        if type(base) == "table" then
            return base[anchorName]
        end
        return nil
    end

    local overlay = self:GetSpecScope("layoutVisuals", true)
    if type(overlay) ~= "table" then return nil end
    if type(overlay[anchorName]) ~= "table" then
        local base = p.modules and p.modules.Layout and p.modules.Layout.visuals
        local src = type(base) == "table" and base[anchorName] or nil
        overlay[anchorName] = (type(src) == "table") and deepCopyData(src) or {}
    end
    return overlay[anchorName]
end

function ns:GetSpecBlock(overlayDomain, baseGetter, create, excludeKeys)
    if not self.savedVarsReady then
        return type(baseGetter) == "function" and baseGetter() or nil
    end
    local base = type(baseGetter) == "function" and baseGetter() or nil
    if not create then
        local overlay = self:GetSpecScope(overlayDomain, false)
        if type(overlay) == "table" then return overlay end
        return base
    end
    local overlay = self:GetSpecScope(overlayDomain, true)
    if type(overlay) ~= "table" then return base end
    if next(overlay) == nil and type(base) == "table" then
        local skip = {}
        if type(excludeKeys) == "table" then
            for i = 1, #excludeKeys do skip[excludeKeys[i]] = true end
        end
        for k, v in pairs(base) do
            if not skip[k] then
                if type(v) == "table" then
                    overlay[k] = deepCopyData(v)
                else
                    overlay[k] = v
                end
            end
        end
    end
    return overlay
end

local EXPORT_FORMAT_VERSION = 1
local EXPORT_HEADER_PATTERN = "^TenUI_Profile:v(%d+):([^:]*):(.*)$"
local LEGACY_EXPORT_HEADER_PATTERN = "^TendorHUD_Profile:v(%d+):([^:]*):(.*)$"

local LUA_KEYWORDS = {
    ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
    ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
    ["function"] = true, ["if"] = true, ["in"] = true, ["local"] = true,
    ["nil"] = true, ["not"] = true, ["or"] = true, ["repeat"] = true,
    ["return"] = true, ["then"] = true, ["true"] = true, ["until"] = true,
    ["while"] = true,
}

local math_huge = math.huge

local function isSerializableScalar(v)
    local tv = type(v)
    if tv == "boolean" or tv == "string" then return true end
    if tv == "number" then
        return v == v and v ~= math_huge and v ~= -math_huge
    end
    return false
end

local function sortedSerializableKeys(t)
    local nums, strs = {}, {}
    for k in pairs(t) do
        local tk = type(k)
        if tk == "number" and k == k and k ~= math_huge and k ~= -math_huge then
            nums[#nums + 1] = k
        elseif tk == "string" then
            strs[#strs + 1] = k
        end
    end
    table.sort(nums)
    table.sort(strs)
    for i = 1, #strs do nums[#nums + 1] = strs[i] end
    return nums
end

local function serializeValue(v, depth, seen)
    local tv = type(v)
    if tv == "boolean" then return tostring(v) end
    if tv == "number" then return tostring(v) end
    if tv == "string" then return string.format("%q", v) end
    if tv ~= "table" then return nil end
    if depth > 24 then return nil end
    if seen[v] then return nil end
    seen[v] = true

    local parts = {}
    for _, k in ipairs(sortedSerializableKeys(v)) do
        local val = v[k]
        local encoded
        if type(val) == "table" then
            encoded = serializeValue(val, depth + 1, seen)
        elseif isSerializableScalar(val) then
            encoded = serializeValue(val, depth + 1, seen)
        end
        if encoded then
            local keyPart
            if type(k) == "number" then
                keyPart = "[" .. tostring(k) .. "]"
            elseif k:match("^[%a_][%w_]*$") and not LUA_KEYWORDS[k] then
                keyPart = k
            else
                keyPart = "[" .. string.format("%q", k) .. "]"
            end
            parts[#parts + 1] = keyPart .. "=" .. encoded
        end
    end
    seen[v] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

local function parseTableLiteral(source)
    if type(source) ~= "string" or source == "" then
        return nil, "empty payload"
    end
    if #source > 500000 then
        return nil, "payload too large"
    end

    local pos, length = 1, #source
    local entryCount = 0
    local MAX_ENTRIES = 20000
    local MAX_DEPTH   = 32
    local parseValue

    local function fail(message)
        return nil, message .. " at character " .. tostring(pos)
    end

    local function skipWhitespace()
        while pos <= length and source:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end

    local function parseString()
        local quote = source:sub(pos, pos)
        if quote ~= '"' and quote ~= "'" then
            return fail("expected string")
        end
        pos = pos + 1
        local out = {}
        while pos <= length do
            local ch = source:sub(pos, pos)
            if ch == quote then
                pos = pos + 1
                return table.concat(out)
            end
            if ch == "\\" then
                pos = pos + 1
                local esc = source:sub(pos, pos)
                if esc == "" then
                    return fail("unfinished escape sequence")
                end
                local mapped = ({
                    a = "\a", b = "\b", f = "\f", n = "\n", r = "\r",
                    t = "\t", v = "\v", ["\\"] = "\\", ['"'] = '"', ["'"] = "'",
                    ["\n"] = "\n",
                })[esc]
                if mapped then
                    out[#out + 1] = mapped
                    pos = pos + 1
                elseif esc:match("%d") then
                    local digits = source:sub(pos, pos + 2):match("^(%d%d?%d?)")
                    local byte = tonumber(digits)
                    if not byte or byte > 255 then
                        return fail("invalid numeric escape")
                    end
                    out[#out + 1] = string.char(byte)
                    pos = pos + #digits
                else
                    return fail("unsupported string escape")
                end
            else
                out[#out + 1] = ch
                pos = pos + 1
            end
        end
        return fail("unterminated string")
    end

    local function parseNumber()
        local rest = source:sub(pos)
        local token = rest:match("^[%+%-]?%d+%.?%d*[eE][%+%-]?%d+")
            or rest:match("^[%+%-]?%d*%.%d+")
            or rest:match("^[%+%-]?%d+")
        if not token then
            return fail("expected number")
        end
        pos = pos + #token
        return tonumber(token)
    end

    local function parseIdentifier()
        return source:sub(pos):match("^([_%a][_%w]*)")
    end

    local function parseTable(depth)
        if depth > MAX_DEPTH then
            return fail("import is nested too deeply")
        end
        if source:sub(pos, pos) ~= "{" then
            return fail("expected table")
        end
        pos = pos + 1
        local tbl = {}
        local arrayIndex = 1
        while true do
            skipWhitespace()
            local ch = source:sub(pos, pos)
            if ch == "}" then
                pos = pos + 1
                return tbl
            end
            if ch == "" then
                return fail("unterminated table")
            end

            entryCount = entryCount + 1
            if entryCount > MAX_ENTRIES then
                return fail("import has too many entries")
            end

            local key, value, err
            if ch == "[" then
                pos = pos + 1
                key, err = parseValue(depth + 1)
                if err then return nil, err end
                if key == nil then
                    return fail("invalid table key")
                end
                skipWhitespace()
                if source:sub(pos, pos) ~= "]" then
                    return fail("expected closing bracket")
                end
                pos = pos + 1
                skipWhitespace()
                if source:sub(pos, pos) ~= "=" then
                    return fail("expected equals after table key")
                end
                pos = pos + 1
                value, err = parseValue(depth + 1)
                if err then return nil, err end
            else
                local ident = parseIdentifier()
                if ident then
                    local saved = pos
                    pos = pos + #ident
                    skipWhitespace()
                    if source:sub(pos, pos) == "=" then
                        pos = pos + 1
                        key = ident
                        value, err = parseValue(depth + 1)
                        if err then return nil, err end
                    else
                        pos = saved
                        key = arrayIndex
                        arrayIndex = arrayIndex + 1
                        value, err = parseValue(depth + 1)
                        if err then return nil, err end
                    end
                else
                    key = arrayIndex
                    arrayIndex = arrayIndex + 1
                    value, err = parseValue(depth + 1)
                    if err then return nil, err end
                end
            end

            if value ~= nil then
                tbl[key] = value
            end
            skipWhitespace()
            local sep = source:sub(pos, pos)
            if sep == "," or sep == ";" then
                pos = pos + 1
            elseif sep ~= "}" then
                return fail("expected comma or closing brace")
            end
        end
    end

    parseValue = function(depth)
        skipWhitespace()
        local ch = source:sub(pos, pos)
        if ch == "{" then
            return parseTable(depth)
        end
        if ch == '"' or ch == "'" then
            return parseString()
        end
        if ch:match("[%+%-%.%d]") then
            return parseNumber()
        end
        local ident = parseIdentifier()
        if ident == "true" then
            pos = pos + #ident
            return true
        elseif ident == "false" then
            pos = pos + #ident
            return false
        elseif ident == "nil" then
            pos = pos + #ident
            return nil
        end
        return fail("expected value")
    end

    local value, err = parseValue(1)
    if err then return nil, err end
    if type(value) ~= "table" then
        return nil, "payload did not decode to a table"
    end
    skipWhitespace()
    if pos <= length then
        return fail("unexpected trailing content")
    end
    return value
end

local function deepCopyProfileData(t, seen)
    if type(t) ~= "table" then return t end
    seen = seen or {}
    if seen[t] then return nil end
    seen[t] = true
    local out = {}
    for k, v in pairs(t) do
        local tk = type(k)
        if tk == "string" or tk == "number" then
            if type(v) == "table" then
                out[k] = deepCopyProfileData(v, seen)
            elseif isSerializableScalar(v) then
                out[k] = v
            end
        end
    end
    seen[t] = nil
    return out
end

function ns:CopyProfile(srcName, newName)
    if not self.savedVarsReady or not self.db then return false, "saved variables not ready" end
    if type(srcName) ~= "string" or srcName == "" then return false, "invalid source name" end
    if type(newName) == "string" then
        newName = newName:gsub("^%s+", ""):gsub("%s+$", "")
    end
    if type(newName) ~= "string" or newName == "" then return false, "invalid new name" end
    if #newName > 48 then return false, "profile name too long (max 48 characters)" end
    self.db.profiles = self.db.profiles or {}
    local src = self.db.profiles[srcName]
    if type(src) ~= "table" then return false, "source profile does not exist" end
    if self.db.profiles[newName] then
        return false, ("profile '%s' already exists"):format(newName)
    end

    local copy = deepCopyProfileData(src) or { modules = {} }
    copy.modules = copy.modules or {}
    if type(copy.modules.Profiles) == "table" and type(copy.modules.Profiles.specSwap) == "table" then
        copy.modules.Profiles.specSwap.assignments = {}
    end

    self.db.profiles[newName] = copy
    self:_AddProfileToOrder(newName)

    if self._deepCopyMissing and self.dbDefaults and self.dbDefaults.profiles then
        self._deepCopyMissing(self.db.profiles[newName], self.dbDefaults.profiles.Default)
    end

    if self.Debug and self.Debug.Log then
        self.Debug:Log("[Profile] Copied '%s' -> '%s'", srcName, newName)
    end
    return true, newName
end

function ns:SaveCurrentAsProfile(name)
    if not self.savedVarsReady or not self.db then return false, "saved variables not ready" end
    return self:CopyProfile(self:GetProfileKey(), name)
end

local function stripNonPortable(data)
    if type(data) ~= "table" then return end
    local m = data.modules
    if type(m) == "table" and type(m.Profiles) == "table"
       and type(m.Profiles.specSwap) == "table" then
        m.Profiles.specSwap.assignments = {}
    end
end

function ns:ExportProfileString()
    if not self.savedVarsReady then return nil, "saved variables not ready" end
    local p = self:GetProfile()
    if type(p) ~= "table" then return nil, "no active profile" end

    local data = deepCopyProfileData(p)
    stripNonPortable(data)

    local payload = serializeValue(data, 1, {})
    if type(payload) ~= "string" then
        return nil, "serialization failed"
    end
    return ("TenUI_Profile:v%d:%s:%s"):format(
        EXPORT_FORMAT_VERSION, tostring(self.version or "?"), payload)
end

function ns:DeserializeProfileString(str)
    if type(str) ~= "string" or str:match("^%s*$") then
        return nil, "empty import string"
    end
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    local ver, _addonVer, payload = str:match(EXPORT_HEADER_PATTERN)
    if not ver then
        ver, _addonVer, payload = str:match(LEGACY_EXPORT_HEADER_PATTERN)
    end
    if not ver then
        return nil, "invalid format (not a TenUI export string)"
    end
    if tonumber(ver) ~= EXPORT_FORMAT_VERSION then
        return nil, ("unsupported format version v%s (this client reads v%d)")
            :format(tostring(ver), EXPORT_FORMAT_VERSION)
    end

    local data, err = parseTableLiteral(payload)
    if not data then
        return nil, "parse error: " .. tostring(err)
    end

    if type(data.modules) ~= "table" then
        return nil, "invalid profile data (missing 'modules' table)"
    end
    for _, key in ipairs({ "anchors", "abilities", "auras",
                           "abilitiesDefaults", "aurasDefaults" }) do
        if data[key] ~= nil and type(data[key]) ~= "table" then
            return nil, ("invalid profile data ('%s' is not a table)"):format(key)
        end
    end
    return data
end

function ns:ImportProfile(str, profileName)
    if not self.savedVarsReady or not self.db then
        return false, "saved variables not ready"
    end

    local data, err = self:DeserializeProfileString(str)
    if not data then return false, err end

    self.db.profiles = self.db.profiles or {}

    local name = type(profileName) == "string"
        and profileName:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" then
        local base = "Imported"
        name = base
        local i = 2
        while self.db.profiles[name] do
            name = base .. " " .. i
            i = i + 1
        end
    elseif #name > 48 then
        return false, "profile name too long (max 48 characters)"
    elseif self.db.profiles[name] then
        return false, ("profile '%s' already exists -- choose another name"):format(name)
    end

    stripNonPortable(data)
    data.modules = data.modules or {}

    self.db.profiles[name] = data
    self:_AddProfileToOrder(name)

    if self._deepCopyMissing and self.dbDefaults and self.dbDefaults.profiles then
        self._deepCopyMissing(self.db.profiles[name], self.dbDefaults.profiles.Default)
    end

    if self.Debug and self.Debug.Log then
        self.Debug:Log("[Profile] Imported profile '%s' (%d chars)", name, #str)
    end
    return true, name
end
