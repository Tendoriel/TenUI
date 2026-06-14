local addonName, ns = ...

ns.Widgets = ns.Widgets or {}

local LibStub = LibStub
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true) or nil

local DEFAULT_FONT = [[Fonts\FRIZQT__.TTF]]
local DEFAULT_STATUSBAR = [[Interface\TargetingFrame\UI-StatusBar]]

local FONT_DIR = [[Interface\AddOns\TenUI\Media\Fonts\]]
local BUNDLED_FONTS = {
    { name = "IBM Plex Mono",          path = FONT_DIR .. "IBMPlexMono-Regular.ttf" },
    { name = "IBM Plex Mono SemiBold", path = FONT_DIR .. "IBMPlexMono-SemiBold.ttf" },
}

if LSM then
    for i = 1, #BUNDLED_FONTS do
        pcall(LSM.Register, LSM, "font", BUNDLED_FONTS[i].name, BUNDLED_FONTS[i].path)
    end
end

local function looksLikePath(s)
    if type(s) ~= "string" then return false end
    if s:find("\\", 1, true) then return true end
    if s:find("/", 1, true) then return true end
    return false
end

local function resolveFont(key, fallback)
    if not key or key == "" then return fallback end
    if looksLikePath(key) then return key end
    if ns.Controls and ns.Controls.ResolveFontPath then
        local ok, path = pcall(ns.Controls.ResolveFontPath, key)
        if ok and type(path) == "string" and path ~= "" then
            return path
        end
    end
    if LSM then
        local found = LSM:Fetch("font", key, true)
        if found then return found end
    end
    return fallback or key
end

local function resolveMedia(kind, key, fallback)
    if kind == "font" then
        return resolveFont(key, fallback)
    end
    if not key or key == "" then return fallback end
    if looksLikePath(key) then return key end
    if not LSM then return fallback or key end
    local found = LSM:Fetch(kind, key, true)
    return found or fallback or key
end

ns.Widgets.resolveMedia = resolveMedia
ns.Widgets.DEFAULT_FONT = DEFAULT_FONT
ns.Widgets.DEFAULT_STATUSBAR = DEFAULT_STATUSBAR
