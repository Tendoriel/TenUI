local addonName, ns = ...

local LibStub = LibStub
local pcall = pcall
local type = type

local ICON_PATH = "Interface\\AddOns\\" .. addonName .. "\\Media\\UI\\minimap_icon.tga"
local OBJECT_NAME = "TenUI"

local MinimapButton = {
    launcher    = nil,
    registered  = false,
    _msgHandler = nil,
}
ns.MinimapButton = MinimapButton

local function dlog(fmt, ...)
    if ns.Debug and ns.Debug.Log then
        ns.Debug:Log("[MinimapButton] " .. tostring(fmt), ...)
    end
end

local function getLDB()
    return LibStub and LibStub("LibDataBroker-1.1", true) or nil
end

local function getIcon()
    return LibStub and LibStub("LibDBIcon-1.0", true) or nil
end

local function getIconDB()
    if not ns.db then return nil end
    ns.db.minimap = ns.db.minimap or {}
    if ns.db.minimap.hide == nil then
        ns.db.minimap.hide = false
    end
    if ns.db.minimap.minimapPos == nil then
        ns.db.minimap.minimapPos = 220
    end
    return ns.db.minimap
end

local function wantsButton()
    local p = ns:GetProfile()
    local m = p and p.modules and p.modules.Minimap
    if not m then return true end
    return m.enabled ~= false
end

local function openOptions()
    if ns.Options and ns.Options.Toggle then
        local ok, err = pcall(function() ns.Options:Toggle() end)
        if not ok then
            dlog("Options:Toggle failed: %s", tostring(err))
        end
    end
end

local function buildTooltip(tooltip)
    if not tooltip then return end
    tooltip:AddLine("TenUI")
    tooltip:AddLine("v" .. tostring(ns.version), 0.7, 0.7, 0.7)
    tooltip:AddLine("Click to open options.", 1, 1, 1)
end

local function ensureLauncher()
    if MinimapButton.launcher then return MinimapButton.launcher end
    local ldb = getLDB()
    if not ldb then
        dlog("LibDataBroker-1.1 missing; minimap button unavailable")
        return nil
    end
    local ok, obj = pcall(function()
        return ldb:NewDataObject(OBJECT_NAME, {
            type = "launcher",
            text = "TenUI",
            icon = ICON_PATH,
            OnClick = function(_, button)
                if button == "LeftButton" or button == "RightButton" then
                    openOptions()
                end
            end,
            OnTooltipShow = function(tooltip)
                buildTooltip(tooltip)
            end,
        })
    end)
    if not ok then
        dlog("NewDataObject failed: %s", tostring(obj))
        return nil
    end
    MinimapButton.launcher = obj
    return obj
end

function MinimapButton:ApplyVisibility()
    local iconDB = getIconDB()
    local icon = getIcon()
    if not (iconDB and icon and self.registered) then return end
    local show = wantsButton()
    iconDB.hide = not show
    local ok, err = pcall(function()
        if show then
            icon:Show(OBJECT_NAME)
        else
            icon:Hide(OBJECT_NAME)
        end
    end)
    if not ok then
        dlog("ApplyVisibility failed: %s", tostring(err))
    end
end

function MinimapButton:OnEnable()
    local iconDB = getIconDB()
    if not iconDB then
        dlog("savedvars not ready; minimap button not registered")
        return
    end

    local icon = getIcon()
    if not icon then
        dlog("LibDBIcon-1.0 missing; minimap button unavailable")
        return
    end

    local launcher = ensureLauncher()
    if not launcher then return end

    if not self.registered then
        local ok, err = pcall(function()
            if not icon:IsRegistered(OBJECT_NAME) then
                icon:Register(OBJECT_NAME, launcher, iconDB)
            end
        end)
        if not ok then
            dlog("Register failed: %s", tostring(err))
            return
        end
        self.registered = true
    end

    self:ApplyVisibility()

    if not self._msgHandler then
        self._msgHandler = ns:RegisterMessage("PROFILE_CHANGED", function()
            MinimapButton:ApplyVisibility()
        end)
    end

    dlog("registered (button %s)", wantsButton() and "ON" or "off")
end

function MinimapButton:OnDisable()
    if self._msgHandler then
        ns:UnregisterMessage("PROFILE_CHANGED", self._msgHandler)
        self._msgHandler = nil
    end
end

ns:RegisterModule("MinimapButton", {
    OnEnable  = function() MinimapButton:OnEnable() end,
    OnDisable = function() MinimapButton:OnDisable() end,
})
