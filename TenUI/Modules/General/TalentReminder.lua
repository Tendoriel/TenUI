local addonName, ns = ...

local CreateFrame           = CreateFrame
local UIParent              = UIParent
local GetInstanceInfo       = GetInstanceInfo
local GetSpecialization     = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local InCombatLockdown      = InCombatLockdown
local pcall                 = pcall
local type                  = type
local tostring              = tostring
local wipe                  = wipe

local POPUP_KEY = "TENUI_TALENT_MISMATCH"
local BANNER_SECONDS = 6

local DEFAULTS = {
    enabled            = true,
    showOnReadyCheck   = true,
    checkOnReadyCheck  = true,
    checkOnEntry       = true,
    showPopup          = true,
    expected           = {},
}

local TalentReminder = {
    profileRef    = nil,
    banner        = nil,
    _handlers     = nil,
    _pendingPopup = nil,
}
ns.TalentReminder = TalentReminder

local function dlog(fmt, ...)
    if ns.Debug and ns.Debug.Verbose then
        ns.Debug:Verbose("talent", "[TalentReminder] " .. tostring(fmt), ...)
    end
end

local function chat(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7TenUI|r: " .. tostring(msg))
end

local function getOpts()
    local parent = TalentReminder.profileRef
    if type(parent) ~= "table" then return nil end
    parent.talentReminder = parent.talentReminder or {}
    return parent.talentReminder
end

local function currentSpecID()
    local idx = GetSpecialization and GetSpecialization()
    if not idx then return nil end
    local ok, specID = pcall(GetSpecializationInfo, idx)
    if ok and type(specID) == "number" then return specID end
    return nil
end

local function activeBuildInfo()
    local specID = currentSpecID()
    local activeID
    if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
        local ok, id = pcall(C_ClassTalents.GetActiveConfigID)
        if ok and type(id) == "number" then activeID = id end
    end

    local savedID
    if specID and C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID then
        local ok, id = pcall(C_ClassTalents.GetLastSelectedSavedConfigID, specID)
        if ok and type(id) == "number" then savedID = id end
    end

    local name
    local lookupID = savedID or activeID
    if lookupID and C_Traits and C_Traits.GetConfigInfo then
        local ok, info = pcall(C_Traits.GetConfigInfo, lookupID)
        if ok and type(info) == "table" and type(info.name) == "string"
            and info.name ~= "" then
            name = info.name
        end
    end

    if not name then
        if activeID then
            name = "Default Loadout"
        else
            name = "Unknown"
        end
    end

    return savedID or activeID, name
end

local function currentKey()
    local specID = currentSpecID()
    if not specID then return nil end

    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        local ok, mapID = pcall(C_ChallengeMode.GetActiveChallengeMapID)
        if ok and type(mapID) == "number" then
            return specID .. ":m+" .. mapID
        end
    end

    local ok, _, instanceType, difficultyID, _, _, _, _, instanceID =
        pcall(GetInstanceInfo)
    if ok and (instanceType == "party" or instanceType == "raid")
        and type(instanceID) == "number" and type(difficultyID) == "number" then
        return specID .. ":" .. instanceID .. ":" .. difficultyID
    end

    return nil
end

local function resolveFont()
    if ns.Controls and ns.Controls.ResolveFontPath then
        local p = ns.Controls.ResolveFontPath("default")
        if p then return p end
    end
    local W = ns.Widgets
    if W and W.resolveMedia then
        return W.resolveMedia("font", "default", W.DEFAULT_FONT)
    end
    return [[Fonts\FRIZQT__.TTF]]
end

local function buildBanner()
    if TalentReminder.banner then return TalentReminder.banner end
    local f = CreateFrame("Frame", "TenUITalentBannerFrame", UIParent)
    f:SetSize(500, 30)
    f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER")
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)
    f.text = fs
    f:Hide()
    TalentReminder.banner = f
    return f
end

local function showBanner(text)
    local f = buildBanner()
    f.text:SetFont(resolveFont(), 18, "OUTLINE")
    f.text:SetTextColor(0.4, 0.85, 1, 1)
    f.text:SetText(text or "")
    f:Show()
    if C_Timer and C_Timer.After then
        C_Timer.After(BANNER_SECONDS, function()
            if f:IsShown() and f.text:GetText() == text then
                f:Hide()
            end
        end)
    end
end

StaticPopupDialogs[POPUP_KEY] = {
    text = "%s",
    button1 = OKAY,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    showAlert = true,
}

local function showMismatchPopup(text)
    if InCombatLockdown() then
        TalentReminder._pendingPopup = text
        showBanner(text)
        return
    end
    TalentReminder._pendingPopup = nil
    if StaticPopup_Show then
        pcall(StaticPopup_Show, POPUP_KEY, text)
    end
end

local function checkExpected(trigger)
    local o = getOpts()
    if not (o and o.enabled) then return end

    local key = currentKey()
    if not key then return end
    local exp = o.expected and o.expected[key]
    if type(exp) ~= "table" then return end

    local configID, name = activeBuildInfo()
    local mismatch
    if exp.configID and configID then
        mismatch = exp.configID ~= configID
    else
        mismatch = (exp.name or "") ~= (name or "")
    end

    dlog("check (%s) key=%s current=%s expected=%s mismatch=%s",
        tostring(trigger), key, tostring(name), tostring(exp.name), tostring(mismatch))

    if mismatch then
        local text = ("|cffff5050Talent build mismatch!|r\nCurrent: %s\nExpected: %s")
            :format(tostring(name), tostring(exp.name or "?"))
        if o.showPopup then
            showMismatchPopup(text)
        else
            showBanner(("Talent mismatch -- Current: %s / Expected: %s")
                :format(tostring(name), tostring(exp.name or "?")))
        end
    end
end

function TalentReminder:GetCurrentBuildName()
    local _, name = activeBuildInfo()
    return name
end

function TalentReminder:GetCurrentKey()
    return currentKey()
end

function TalentReminder:GetExpectedForCurrentKey()
    local o = getOpts()
    local key = currentKey()
    if not (o and key and type(o.expected) == "table") then return nil, key end
    return o.expected[key], key
end

function TalentReminder:SaveCurrentBuild()
    local o = getOpts()
    if not o then return false, "savedvars not ready" end
    local key = currentKey()
    if not key then return false, "not in a dungeon/raid/keystone zone" end
    local configID, name = activeBuildInfo()
    o.expected = o.expected or {}
    o.expected[key] = { configID = configID, name = name }
    dlog("saved expected build key=%s name=%s configID=%s",
        key, tostring(name), tostring(configID))
    return true, key, name
end

function TalentReminder:ClearCurrentBuild()
    local o = getOpts()
    if not o then return false, "savedvars not ready" end
    local key = currentKey()
    if not key then return false, "not in a dungeon/raid/keystone zone" end
    if type(o.expected) == "table" then
        o.expected[key] = nil
    end
    dlog("cleared expected build for key=%s", key)
    return true, key
end

function TalentReminder:ClearAllBuilds()
    local o = getOpts()
    if not o then return false end
    if type(o.expected) == "table" then
        wipe(o.expected)
    else
        o.expected = {}
    end
    dlog("cleared ALL expected builds")
    return true
end

function TalentReminder:PrintCurrentBuild()
    local _, name = activeBuildInfo()
    chat("current talent build: |cffffd200" .. tostring(name) .. "|r")
end

function TalentReminder:CheckNow(trigger)
    checkExpected(trigger or "manual")
end

function TalentReminder:IsEnabled()
    local o = getOpts()
    return o and o.enabled == true or false
end

function TalentReminder:ApplyOptions()
end

local function onReadyCheck()
    local o = getOpts()
    if not (o and o.enabled) then return end
    if o.showOnReadyCheck then
        local _, name = activeBuildInfo()
        showBanner("Talents: " .. tostring(name))
        chat("talents: |cffffd200" .. tostring(name) .. "|r")
    end
    if o.checkOnReadyCheck then
        checkExpected("ready-check")
    end
end

local function onEnteringWorld()
    local o = getOpts()
    if not (o and o.enabled and o.checkOnEntry) then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(4, function()
            local ok, _, instanceType = pcall(GetInstanceInfo)
            if ok and (instanceType == "party" or instanceType == "raid") then
                checkExpected("instance-entry")
            end
        end)
    end
end

local function onChallengeStart()
    local o = getOpts()
    if not (o and o.enabled and o.checkOnEntry) then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function()
            checkExpected("m+-start")
        end)
    end
end

local function onRegenEnabled()
    local pending = TalentReminder._pendingPopup
    if pending then
        TalentReminder._pendingPopup = nil
        local o = getOpts()
        if o and o.enabled and o.showPopup then
            if StaticPopup_Show then
                pcall(StaticPopup_Show, POPUP_KEY, pending)
            end
        end
    end
end

local function onMisc()
    if ns.Options and ns.Options.RefreshCurrentPage then
        pcall(ns.Options.RefreshCurrentPage, ns.Options)
    end
end

local EVENTS = {
    { event = "READY_CHECK",                   fn = onReadyCheck },
    { event = "PLAYER_ENTERING_WORLD",         fn = onEnteringWorld },
    { event = "CHALLENGE_MODE_START",          fn = onChallengeStart },
    { event = "CHALLENGE_MODE_COMPLETED",      fn = onMisc },
    { event = "PLAYER_SPECIALIZATION_CHANGED", fn = onMisc },
    { event = "TRAIT_CONFIG_UPDATED",          fn = onMisc },
    { event = "PLAYER_REGEN_ENABLED",          fn = onRegenEnabled },
}

function TalentReminder:OnEnable()
    local p = ns:GetProfile()
    p.modules = p.modules or {}
    p.modules.General = p.modules.General or {}
    p.modules.General.talentReminder = p.modules.General.talentReminder or {}
    if ns._deepCopyMissing then
        ns._deepCopyMissing(p.modules.General.talentReminder, DEFAULTS)
    end
    self.profileRef = p.modules.General

    self._handlers = {}
    for i = 1, #EVENTS do
        local e = EVENTS[i]
        self._handlers[#self._handlers + 1] = {
            event = e.event,
            fn    = ns:RegisterEvent(e.event, e.fn),
        }
    end

    dlog("enabled (reminder %s)", self:IsEnabled() and "ON" or "off")
end

function TalentReminder:OnDisable()
    if self._handlers then
        for i = 1, #self._handlers do
            local h = self._handlers[i]
            ns:UnregisterEvent(h.event, h.fn)
        end
        self._handlers = nil
    end
    if self.banner then
        self.banner:Hide()
    end
    self._pendingPopup = nil
end

TalentReminder.DEFAULTS = DEFAULTS

ns:RegisterModule("TalentReminder", {
    OnEnable  = function() TalentReminder:OnEnable() end,
    OnDisable = function() TalentReminder:OnDisable() end,
})
