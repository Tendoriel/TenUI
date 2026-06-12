local addonName, ns = ...

ns.Widgets = ns.Widgets or {}

local LibStub = LibStub
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true) or nil

local DEFAULT_FONT = [[Fonts\FRIZQT__.TTF]]
local DEFAULT_STATUSBAR = [[Interface\TargetingFrame\UI-StatusBar]]

local function looksLikePath(s)
    if type(s) ~= "string" then return false end
    if s:find("\\", 1, true) then return true end
    if s:find("/", 1, true) then return true end
    return false
end

local function resolveMedia(kind, key, fallback)
    if not key or key == "" then return fallback end
    if looksLikePath(key) then return key end
    if not LSM then return fallback or key end
    local found = LSM:Fetch(kind, key, true)
    return found or fallback or key
end

ns.Widgets.resolveMedia = resolveMedia
ns.Widgets.DEFAULT_FONT = DEFAULT_FONT
ns.Widgets.DEFAULT_STATUSBAR = DEFAULT_STATUSBAR
