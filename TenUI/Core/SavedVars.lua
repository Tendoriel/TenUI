local addonName, ns = ...

ns.SCHEMA_VERSION = 2

ns.dbDefaults = {
    schema = ns.SCHEMA_VERSION,
    locked = true,
    globalScale = 1.0,
    activeProfile = "Default",
    profiles = {
        Default = {
            modules = {},
            abilities = {},
            auras = {},
            abilitiesDefaults = {
                glow = {
                    proc     = { enabled = true,  style = "blizzard", color = {1, 1, 1, 1} },
                    ready    = { enabled = false, style = "border",   color = {0.3, 1, 0.3, 1}, combatOnly = true },
                    pandemic = { enabled = true,  style = "pixel",    color = {1, 0.35, 0.1, 1} },
                    activeAura = { enabled = false, style = "solid",  color = {1, 1, 1, 1} },
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

local function migrate(db)
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
            distance      = 12,
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
            },
            UtilityCooldowns = {
                iconWidth = 36, iconHeight = 36, spacing = 2,
                text = { font = "default", size = 12, anchor = "BOTTOMRIGHT", x = -1, y = 1 },
                textCooldown = { font = "default", size = 14, anchor = "CENTER",      x =  0, y = 0 },
                textStack    = { font = "default", size = 12, anchor = "BOTTOMRIGHT", x = -1, y = 1 },
            },
            DefensiveCooldowns = {
                iconWidth = 36, iconHeight = 36, spacing = 2,
                text = { font = "default", size = 12, anchor = "BOTTOMRIGHT", x = -1, y = 1 },
                textCooldown = { font = "default", size = 14, anchor = "CENTER",      x =  0, y = 0 },
                textStack    = { font = "default", size = 12, anchor = "BOTTOMRIGHT", x = -1, y = 1 },
            },
            Trinkets = {
                iconWidth = 36, iconHeight = 36, spacing = 2,
                text = { font = "default", size = 12, anchor = "BOTTOMRIGHT", x = -1, y = 1 },
                textCooldown = { font = "default", size = 14, anchor = "CENTER",      x =  0, y = 0 },
                textStack    = { font = "default", size = 12, anchor = "BOTTOMRIGHT", x = -1, y = 1 },
            },
            TrackedIcon = {
                iconWidth = 36, iconHeight = 36, spacing = 2,
                text = { font = "default", size = 12, anchor = "BOTTOMRIGHT", x = -1, y = 1 },
                textCooldown = { font = "default", size = 14, anchor = "CENTER",      x =  0, y = 0 },
                textStack    = { font = "default", size = 12, anchor = "BOTTOMRIGHT", x = -1, y = 1 },
            },
            TrackedBars = {
                barHeight = 18, spacing = 2,
                text = {
                    name  = { font = "default", size = 11, anchor = "LEFT",  x =  4, y = 0 },
                    timer = { font = "default", size = 11, anchor = "RIGHT", x = -4, y = 0 },
                },
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
