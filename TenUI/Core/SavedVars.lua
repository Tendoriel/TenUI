local addonName, ns = ...

ns.SCHEMA_VERSION = 7

ns.dbDefaults = {
    schema = ns.SCHEMA_VERSION,
    locked = true,
    globalScale = 1.0,
    activeProfile = "Default",
    profileOrder = { "Default" },
    specProfiles = {},
    lastSpecByChar = {},
    minimap = {
        hide = false,
        minimapPos = 220,
    },
    profiles = {
        Default = {
            modules = {},
            abilities = {},
            auras = {},
            abilitiesDefaults = {
                glow = {
                    proc      = { enabled = true,  style = "blizzard", color = {1, 1, 1, 1} },
                    ready     = { enabled = false, style = "border",   color = {0.3, 1, 0.3, 1}, combatOnly = true },
                    pandemic  = { enabled = true,  style = "pixel",    color = {1, 0.35, 0.1, 1} },
                    activeAura = { enabled = false, style = "solid",   color = {1, 1, 1, 1} },
                    maxStacks = { enabled = false, style = "solid",    color = {1, 0.5, 0, 1}, combatOnly = false },
                },
                warnings = {
                    readyText    = { enabled = false, text = "READY", font = "default", size = 14, anchor = "CENTER", x = 0, y = 0 },
                    cooldownText = { enabled = true,  font = "default", size = 13, anchor = "CENTER", x = 0, y = 0 },
                    sound        = { enabled = false, soundID = nil },
                },
                range          = { enabled = true },
                resourceGating = { enabled = true },
                visibility     = { hideUnlearned = true, hideNoProc = false, combatOnly = false },
            },
            aurasDefaults = {
                glow = {
                    pandemic   = { enabled = true,  threshold = 0.30, style = "pixel",  color = {1, 0.35, 0.1, 1} },
                    activeAura = { enabled = false, style = "border", color = {0.4, 0.8, 1, 1} },
                },
                display = { asIcon = true, asBar = true },
                text = {
                    duration = { enabled = true,  font = "default", size = 12, anchor = "BOTTOM",      x = 0,  y = -2 },
                    stacks   = { enabled = true,  font = "default", size = 11, anchor = "BOTTOMRIGHT", x = -1, y =  1 },
                },
                visibility = { combatOnly = false, ownOnly = true },
            },
        },
    },
    debug = {
        enabled = false,
        log = {},
        point = nil,
    },
}

ns.charDbDefaults = {
    schema = ns.SCHEMA_VERSION,
}

local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do
        out[k] = deepCopy(v)
    end
    return out
end

local function migrateConsumablesRow(db)
    if type(db) ~= "table" or type(db.profiles) ~= "table" then return end
    for _, profile in pairs(db.profiles) do
        if type(profile) == "table"
           and type(profile.modules) == "table"
           and type(profile.modules.Bars) == "table" then
            local bars = profile.modules.Bars
            bars.consumables = bars.consumables or {}
            bars.consumables.enabledPresets = bars.consumables.enabledPresets or {}
            bars.consumables.customItems    = bars.consumables.customItems or {}
            if bars.consumables.showItemCount == nil then bars.consumables.showItemCount = true end
            if bars.consumables.hideIfMissing == nil then bars.consumables.hideIfMissing = true end
            if bars.consumables.showTooltip   == nil then bars.consumables.showTooltip   = true end
            if type(bars.scopes) == "table" then
                for _, scope in pairs(bars.scopes) do
                    if type(scope) == "table" and type(scope.rows) == "table" then
                        scope.rows.Consumables = scope.rows.Consumables
                            or { displayed = {}, candidates = {} }
                        scope.rows.Consumables.displayed  = scope.rows.Consumables.displayed or {}
                        scope.rows.Consumables.candidates = scope.rows.Consumables.candidates or {}
                    end
                end
            end
        end
    end
end

local function migrateProfileOrder(db)
    if type(db.profiles) ~= "table" then db.profiles = {} end
    local existing = {}
    if type(db.profileOrder) == "table" then
        for i = 1, #db.profileOrder do
            local n = db.profileOrder[i]
            if type(n) == "string" and db.profiles[n] and not existing[n] then
                existing[n] = true
            end
        end
    end
    local order = { "Default" }
    local seen = { ["Default"] = true }
    if type(db.profileOrder) == "table" then
        for i = 1, #db.profileOrder do
            local n = db.profileOrder[i]
            if type(n) == "string" and n ~= "Default" and db.profiles[n] and not seen[n] then
                order[#order + 1] = n
                seen[n] = true
            end
        end
    end
    local names = {}
    for name in pairs(db.profiles) do
        if type(name) == "string" and name ~= "Default" and not seen[name] then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    for i = 1, #names do
        order[#order + 1] = names[i]
        seen[names[i]] = true
    end
    db.profileOrder = order
end

local function migrateSpecProfilesFromLegacy(db)
    if type(db.specProfiles) ~= "table" then db.specProfiles = {} end
    local classToken
    if UnitClass then
        local ok, _, token = pcall(UnitClass, "player")
        if ok then classToken = token end
    end
    if type(classToken) ~= "string" or classToken == "" then return end
    if not (GetSpecializationInfo and GetSpecialization) then return end
    for _, profile in pairs(db.profiles) do
        if type(profile) == "table"
           and type(profile.modules) == "table"
           and type(profile.modules.Profiles) == "table"
           and type(profile.modules.Profiles.specSwap) == "table"
           and type(profile.modules.Profiles.specSwap.assignments) == "table" then
            for key, profileName in pairs(profile.modules.Profiles.specSwap.assignments) do
                if type(key) == "string" and type(profileName) == "string"
                   and db.profiles[profileName] then
                    local token, idxStr = key:match("^(.+)_(%d+)$")
                    if token == classToken then
                        local idx = tonumber(idxStr)
                        if idx and idx > 0 then
                            local ok, specID = pcall(GetSpecializationInfo, idx)
                            if ok and type(specID) == "number" and specID > 0
                               and db.specProfiles[specID] == nil then
                                db.specProfiles[specID] = profileName
                            end
                        end
                    end
                end
            end
        end
    end
end

local function migrate(db)
    if (db.schema or 0) < 5 then
        migrateConsumablesRow(db)
    end
    if (db.schema or 0) < 6 then
        if not db._specProfilesMigrated then
            db.specProfiles = db.specProfiles or {}
            migrateSpecProfilesFromLegacy(db)
            db._specProfilesMigrated = true
        end
    end
    if (db.schema or 0) < 7 then
        if type(db.profiles) == "table" then
            for _, profile in pairs(db.profiles) do
                if type(profile) == "table" then
                    profile.modules = profile.modules or {}
                    profile.modules.DragonRiding = profile.modules.DragonRiding or {}
                end
            end
        end
    end
    migrateProfileOrder(db)
    db.schema = ns.SCHEMA_VERSION
end

local MODULE_DEFAULTS = {
    Options = {
        selectedPage            = "general",
        selectedCDMContainer    = "EssentialCooldowns",
        selectedAuraContainer   = "TrackedBars",
        selectedProfileToCopy   = nil,
    },
    Minimap = {
        enabled = true,
    },
    Layout = {
        snapping = {
            enabled       = false,
            distance      = 6,
            gap           = 2,
            showLines     = true,
            snapToCenter  = true,
            snapToAnchors = true,
            showGrid      = false,
            gridSize      = 32,
        },
        visuals = {
            EssentialCooldowns = {
                iconWidth = 36, iconHeight = 36, spacing = 2,
                text = { font = "default", size = 12, anchor = "BOTTOMRIGHT", x = -1, y = 1 },
                textCooldown = { font = "default", size = 14, anchor = "CENTER",      x =  0, y = 0 },
                textStack    = { font = "default", size = 12, anchor = "BOTTOMRIGHT", x = -1, y = 1 },
                visibility = { state = "always", options = { onlyInstances = false, hideHousing = false, hideMounted = false } },
            },
            UtilityCooldowns = {
                iconWidth = 36, iconHeight = 36, spacing = 2,
                text = { font = "default", size = 12, anchor = "BOTTOMRIGHT", x = -1, y = 1 },
                textCooldown = { font = "default", size = 14, anchor = "CENTER",      x =  0, y = 0 },
                textStack    = { font = "default", size = 12, anchor = "BOTTOMRIGHT", x = -1, y = 1 },
                visibility = { state = "always", options = { onlyInstances = false, hideHousing = false, hideMounted = false } },
            },
            DefensiveCooldowns = {
                iconWidth = 36, iconHeight = 36, spacing = 2,
                text = { font = "default", size = 12, anchor = "BOTTOMRIGHT", x = -1, y = 1 },
                textCooldown = { font = "default", size = 14, anchor = "CENTER",      x =  0, y = 0 },
                textStack    = { font = "default", size = 12, anchor = "BOTTOMRIGHT", x = -1, y = 1 },
                visibility = { state = "always", options = { onlyInstances = false, hideHousing = false, hideMounted = false } },
            },
            Trinkets = {
                iconWidth = 36, iconHeight = 36, spacing = 2,
                text = { font = "default", size = 12, anchor = "BOTTOMRIGHT", x = -1, y = 1 },
                textCooldown = { font = "default", size = 14, anchor = "CENTER",      x =  0, y = 0 },
                textStack    = { font = "default", size = 12, anchor = "BOTTOMRIGHT", x = -1, y = 1 },
                visibility = { state = "always", options = { onlyInstances = false, hideHousing = false, hideMounted = false } },
            },
            Consumables = {
                iconWidth = 36, iconHeight = 36, spacing = 2,
                text = { font = "default", size = 12, anchor = "BOTTOMRIGHT", x = -1, y = 1 },
                textCooldown = { font = "default", size = 14, anchor = "CENTER",      x =  0, y = 0 },
                textStack    = { font = "default", size = 12, anchor = "BOTTOMRIGHT", x = -1, y = 1 },
                visibility = { state = "always", options = { onlyInstances = false, hideHousing = false, hideMounted = false } },
            },
            TrackedIcon = {
                iconWidth = 36, iconHeight = 36, spacing = 2,
                text = { font = "default", size = 12, anchor = "BOTTOMRIGHT", x = -1, y = 1 },
                textCooldown = { font = "default", size = 14, anchor = "CENTER",      x =  0, y = 0 },
                textStack    = { font = "default", size = 12, anchor = "BOTTOMRIGHT", x = -1, y = 1 },
                visibility = { state = "always", options = { onlyInstances = false, hideHousing = false, hideMounted = false } },
            },
            TrackedBars = {
                barHeight = 18, spacing = 2,
                fillColor = { 1, 1, 1, 1 },
                text = {
                    name  = { font = "default", size = 11, anchor = "LEFT",  x =  4, y = 0 },
                    timer = { font = "default", size = 11, anchor = "RIGHT", x = -4, y = 0 },
                },
                visibility = { state = "always", options = { onlyInstances = false, hideHousing = false, hideMounted = false } },
            },
        },
    },
    Glow = {
        globalEnabled = true,
    },
    Profiles = {
        specSwap = {
            enabled     = false,
            assignments = {},
        },
    },
}

local SUBKEY_DEFAULTS = {
    Resources = {
        text = {
            enabled = true,
            font    = "default",
            size    = 12,
            anchor  = "CENTER",
            x = 0, y = 0,
        },
        primary = {
            font       = "default",
            fontSize   = 12,
            fontFlags  = "OUTLINE",
            fontAnchor = "RIGHT",
            fontX      = -4,
            fontY      = 0,
        },
    },
    CastBar = {
        text = {
            spellName = { enabled = true, font = "default", size = 12, anchor = "LEFT",  x =  4, y = 0 },
            timer     = { enabled = true, font = "default", size = 12, anchor = "RIGHT", x = -4, y = 0 },
        },
    },
}

function ns:InitializeSavedVars()
    if _G.TenUIDB == nil and type(_G.TendorHUDDB) == "table" then
        _G.TenUIDB = deepCopy(_G.TendorHUDDB)
    end
    if _G.TenUICharDB == nil and type(_G.TendorHUDCharDB) == "table" then
        _G.TenUICharDB = deepCopy(_G.TendorHUDCharDB)
    end

    if _G.TenUIDB == nil then
        _G.TenUIDB = deepCopy(self.dbDefaults)
    else
        self._deepCopyMissing(_G.TenUIDB, self.dbDefaults)
        migrate(_G.TenUIDB)
    end

    if _G.TenUICharDB == nil then
        _G.TenUICharDB = deepCopy(self.charDbDefaults)
    else
        self._deepCopyMissing(_G.TenUICharDB, self.charDbDefaults)
    end

    self.db = _G.TenUIDB
    self.charDb = _G.TenUICharDB
    self.savedVarsReady = true

    local profile = self:GetProfile()
    profile.modules   = profile.modules   or {}
    profile.abilities = profile.abilities or {}
    profile.auras     = profile.auras     or {}

    for name, mod in pairs(self.modules) do
        if mod.defaults then
            profile.modules[name] = profile.modules[name] or {}
            self._deepCopyMissing(profile.modules[name], mod.defaults)
        end
    end

    for modName, defaults in pairs(MODULE_DEFAULTS) do
        profile.modules[modName] = profile.modules[modName] or {}
        self._deepCopyMissing(profile.modules[modName], defaults)
    end

    for modName, subDefaults in pairs(SUBKEY_DEFAULTS) do
        if profile.modules[modName] then
            for subKey, subValue in pairs(subDefaults) do
                if type(subValue) == "table" then
                    profile.modules[modName][subKey] = profile.modules[modName][subKey] or {}
                    self._deepCopyMissing(profile.modules[modName][subKey], subValue)
                end
            end
        end
    end
end

function ns:GetUIState()
    if not self.savedVarsReady or not self.db then return nil end
    self.db.uiState = self.db.uiState or {}
    self.db.uiState.lastOptionsSub = self.db.uiState.lastOptionsSub or {}
    return self.db.uiState
end

function ns:WipeSavedVars()
    _G.TenUIDB = nil
    _G.TendorHUDDB = nil
    _G.TenUICharDB = nil
    _G.TendorHUDCharDB = nil
end
