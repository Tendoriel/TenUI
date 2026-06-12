local addonName, ns = ...

local CreateFrame           = CreateFrame
local UIParent              = UIParent
local UnitClass             = UnitClass
local UnitExists            = UnitExists
local UnitIsDead            = UnitIsDead
local UnitGUID              = UnitGUID
local IsMounted             = IsMounted
local IsResting             = IsResting
local IsInInstance          = IsInInstance
local IsInGroup             = IsInGroup
local IsInRaid              = IsInRaid
local GetNumGroupMembers    = GetNumGroupMembers
local GetSpecialization     = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local InCombatLockdown      = InCombatLockdown
local IsPlayerSpell         = IsPlayerSpell
local UnitClassBase         = UnitClassBase
local GetTime               = GetTime
local issecretvalue         = issecretvalue
local pcall                 = pcall
local type                  = type
local tonumber              = tonumber
local strsplit              = strsplit
local select                = select

local EARTH_SHIELD       = 974
local EARTH_SHIELD_SELF  = { 974, 383648 }
local LIGHTNING_SHIELD   = 192106
local WATER_SHIELD       = 52127

local HOLY_PALADIN_SPEC  = 65
local BEACON_OF_LIGHT    = 53563
local BEACON_OF_FAITH    = 156910
local BEACON_OF_VIRTUE   = 200025

local SHADOW_SPEC        = 258
local SHADOWFORM         = 232698
local SHADOWFORM_AURAS   = { 232698, 15473 }

local DEMONOLOGY_SPEC    = 266
local SUMMON_FELGUARD    = 30146
local GRIM_SAC_BUFF      = 196099
local WARLOCK_SUMMONS    = { 688, 697, 366222, 691, 30146 }
local FELGUARD_NPC_IDS   = { [17252] = true, [58965] = true }

local MARKSMANSHIP_SPEC  = 254
local HUNTER_PET_TALENT  = 1223323
local UNHOLY_SPEC        = 252
local DK_RAISE_DEAD_ICON = 1100170
local FROST_MAGE_SPEC    = 64
local WATER_ELEMENTAL    = 31687

local LETHAL_POISONS     = { 315584, 8679, 2823, 381664 }
local NONLETHAL_POISONS  = { 3408, 381637, 5761 }

local RAID_BUFFS = {
    { class = "WARRIOR", label = "Battle Shout",   iconSpell = 6673,
      fallback = 132333, buffIDs = { 6673 } },
    { class = "MAGE",    label = "Arcane Intellect", iconSpell = 1459,
      fallback = 135932, buffIDs = { 1459, 432778 } },
    { class = "PRIEST",  label = "Fortitude",      iconSpell = 21562,
      fallback = 135987, buffIDs = { 21562 } },
    { class = "DRUID",   label = "Mark of the Wild", iconSpell = 1126,
      fallback = 136078, buffIDs = { 1126, 432661 } },
    { class = "EVOKER",  label = "Bronze Blessing", iconSpell = 364342,
      fallback = 5198685, buffIDs = {
          381732, 381741, 381746, 381748, 381749, 381750, 381751,
          381752, 381753, 381754, 381756, 381757, 381758 } },
    { class = "SHAMAN",  label = "Skyfury",        iconSpell = 462854,
      fallback = 135990, buffIDs = { 462854, 204330 } },
}

local FALLBACK_SHIELD    = 136024
local FALLBACK_BEACON    = 1030094
local FALLBACK_PET       = 132599
local FALLBACK_SHADOW    = 136200
local FALLBACK_POISON    = 132273
local FALLBACK_PASSIVE   = 132311

local MAX_SLOTS = 8

local DEFAULTS = {
    enabled          = false,
    shamanShields    = true,
    paladinBeacons   = true,
    pets             = true,
    petPassive       = true,
    shadowform       = true,
    roguePoisons     = true,
    raidBuffs        = true,
    instanceOnly     = false,
    showInRaid       = true,
    hideInRested     = true,
    hideWhileMounted = true,
    onlyOutOfCombat  = false,
    glow             = true,
    iconSize         = 36,
    fontSize         = 11,
    point            = "CENTER",
    x                = 0,
    y                = -220,
}

local ClassReminders = {
    profileRef   = nil,
    frame        = nil,
    _testUntil   = 0,
    _handlers    = nil,
    _unitFrame   = nil,
    _updateQueued = false,
    _rosterQueued = false,
    _rosterClasses = {},
}
ns.ClassReminders = ClassReminders

local function dlog(fmt, ...)
    if ns.Debug and ns.Debug.Log then
        ns.Debug:Log("[ClassReminders] " .. tostring(fmt), ...)
    end
end

local function getOpts()
    local parent = ClassReminders.profileRef
    if type(parent) ~= "table" then return nil end
    parent.classReminders = parent.classReminders or {}
    return parent.classReminders
end

local function playerClass()
    local _, token = UnitClass("player")
    return token
end

local function currentSpecID()
    local idx = GetSpecialization and GetSpecialization()
    if not idx then return nil end
    local ok, specID = pcall(GetSpecializationInfo, idx)
    if ok and type(specID) == "number" then return specID end
    return nil
end

local function spellKnown(spellID)
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, spellID)
        if ok and known == true then return true end
        if ok then return false end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
        if ok and known == true then return true end
    end
    return false
end

local function spellIcon(spellID, fallback)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and tex ~= nil then
            return tex
        end
    end
    return fallback
end

local function playerAuraPresent(spellID)
    if not C_UnitAuras then return false end
    if C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok then return aura ~= nil end
    end
    if C_UnitAuras.GetUnitAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, "player", spellID)
        if ok then return aura ~= nil end
    end
    if C_UnitAuras.GetAuraDataBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellID, "player", spellID, "HELPFUL")
        if ok then return aura ~= nil end
    end
    return false
end

local function anyPlayerAuraPresent(list)
    for i = 1, #list do
        if playerAuraPresent(list[i]) then return true end
    end
    return false
end

local function unitAuraPresent(unit, spellID)
    if not C_UnitAuras then return false end
    if C_UnitAuras.GetUnitAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, spellID)
        if ok then return aura ~= nil end
    end
    if C_UnitAuras.GetAuraDataBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellID, unit, spellID, "HELPFUL")
        if ok then return aura ~= nil end
    end
    return false
end

local function groupHasAura(spellID)
    if unitAuraPresent("player", spellID) then return true end
    if IsInRaid() then
        local n = GetNumGroupMembers() or 0
        for i = 1, n do
            if unitAuraPresent("raid" .. i, spellID) then return true end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) and unitAuraPresent(unit, spellID) then return true end
        end
    end
    return false
end

local function rebuildRoster()
    local classes = {}
    local function add(unit)
        if not UnitExists(unit) then return end
        local ok, token = pcall(UnitClassBase, unit)
        if ok and type(token) == "string"
            and not (issecretvalue and issecretvalue(token)) then
            classes[token] = true
        end
    end
    add("player")
    if IsInRaid() then
        local n = GetNumGroupMembers() or 0
        for i = 1, n do add("raid" .. i) end
    elseif IsInGroup() then
        for i = 1, 4 do add("party" .. i) end
    end
    ClassReminders._rosterClasses = classes
end

local function petAlive()
    return UnitExists("pet") and not UnitIsDead("pet")
end

local function petOnPassive()
    if not UnitExists("pet") then return false end
    local getters = {}
    if C_PetBar and C_PetBar.GetPetActionInfo then
        getters[#getters + 1] = C_PetBar.GetPetActionInfo
    end
    if C_ActionBar and C_ActionBar.GetPetActionInfo then
        getters[#getters + 1] = C_ActionBar.GetPetActionInfo
    end
    if GetPetActionInfo then
        getters[#getters + 1] = GetPetActionInfo
    end
    local slots = NUM_PET_ACTION_SLOTS or 10
    for g = 1, #getters do
        local getInfo = getters[g]
        for i = 1, slots do
            local ok, name, _, _, isActive = pcall(getInfo, i)
            if ok then
                if type(name) == "table" then
                    local t = name
                    name = t.name
                    isActive = t.isActive
                end
                if name ~= nil
                    and not (issecretvalue and issecretvalue(name))
                    and type(name) == "string"
                    and (name == "PET_MODE_PASSIVE" or name == "PET_ACTION_MODE_PASSIVE") then
                    if isActive ~= nil
                        and not (issecretvalue and issecretvalue(isActive))
                        and isActive == true then
                        return true
                    end
                    return false
                end
            end
        end
    end
    return false
end

local function petIsFelguard()
    if not UnitExists("pet") then return nil end
    local ok, guid = pcall(UnitGUID, "pet")
    if not ok or guid == nil then return nil end
    if issecretvalue and issecretvalue(guid) then return nil end
    if type(guid) ~= "string" then return nil end
    local npcID = select(6, strsplit("-", guid))
    npcID = tonumber(npcID)
    if not npcID then return nil end
    return FELGUARD_NPC_IDS[npcID] == true
end

local function evaluate(o)
    local out = {}
    local class = playerClass()
    local function push(icon, label)
        if #out < MAX_SLOTS then
            out[#out + 1] = { icon = icon, label = label }
        end
    end

    if class == "SHAMAN" and o.shamanShields then
        local knowsAny = spellKnown(EARTH_SHIELD) or spellKnown(LIGHTNING_SHIELD)
            or spellKnown(WATER_SHIELD)
        if knowsAny then
            local active = anyPlayerAuraPresent(EARTH_SHIELD_SELF)
                or playerAuraPresent(LIGHTNING_SHIELD)
                or playerAuraPresent(WATER_SHIELD)
            if not active then
                local spec = GetSpecialization and GetSpecialization()
                local iconSpell
                if spec == 3 and spellKnown(EARTH_SHIELD) then
                    iconSpell = EARTH_SHIELD
                elseif spec == 2 and spellKnown(LIGHTNING_SHIELD) then
                    iconSpell = LIGHTNING_SHIELD
                elseif spellKnown(LIGHTNING_SHIELD) then
                    iconSpell = LIGHTNING_SHIELD
                elseif spellKnown(EARTH_SHIELD) then
                    iconSpell = EARTH_SHIELD
                else
                    iconSpell = WATER_SHIELD
                end
                push(spellIcon(iconSpell, FALLBACK_SHIELD), "Shield")
            end
        end
    end

    if class == "PALADIN" and o.paladinBeacons
        and currentSpecID() == HOLY_PALADIN_SPEC
        and not spellKnown(BEACON_OF_VIRTUE) then
        if spellKnown(BEACON_OF_LIGHT) and not groupHasAura(BEACON_OF_LIGHT) then
            push(spellIcon(BEACON_OF_LIGHT, FALLBACK_BEACON), "Beacon")
        end
        if spellKnown(BEACON_OF_FAITH) and not groupHasAura(BEACON_OF_FAITH) then
            push(spellIcon(BEACON_OF_FAITH, FALLBACK_BEACON), "Faith")
        end
    end

    if o.pets then
        local petExpected = false
        local missingIcon, missingLabel
        if class == "HUNTER" then
            if currentSpecID() == MARKSMANSHIP_SPEC then
                petExpected = spellKnown(HUNTER_PET_TALENT)
            else
                petExpected = true
            end
            missingIcon, missingLabel = FALLBACK_PET, "Pet"
        elseif class == "WARLOCK" then
            local knowsSummon = false
            for i = 1, #WARLOCK_SUMMONS do
                if spellKnown(WARLOCK_SUMMONS[i]) then knowsSummon = true break end
            end
            petExpected = knowsSummon and not playerAuraPresent(GRIM_SAC_BUFF)
            missingIcon, missingLabel = spellIcon(688, FALLBACK_PET), "Pet"
        elseif class == "DEATHKNIGHT" then
            petExpected = currentSpecID() == UNHOLY_SPEC
            missingIcon, missingLabel = DK_RAISE_DEAD_ICON, "Ghoul"
        elseif class == "MAGE" then
            petExpected = currentSpecID() == FROST_MAGE_SPEC
                and spellKnown(WATER_ELEMENTAL)
            missingIcon = spellIcon(WATER_ELEMENTAL, FALLBACK_PET)
            missingLabel = "Elemental"
        end

        if petExpected and not petAlive() then
            push(missingIcon, missingLabel)
        end

        if class == "WARLOCK" and currentSpecID() == DEMONOLOGY_SPEC
            and petAlive() and spellKnown(SUMMON_FELGUARD) then
            if petIsFelguard() == false then
                push(spellIcon(SUMMON_FELGUARD, FALLBACK_PET), "Felguard!")
            end
        end

        if o.petPassive and petAlive() and petOnPassive() then
            push(FALLBACK_PASSIVE, "Passive!")
        end
    end

    if class == "PRIEST" and o.shadowform
        and currentSpecID() == SHADOW_SPEC
        and spellKnown(SHADOWFORM) then
        if not anyPlayerAuraPresent(SHADOWFORM_AURAS) then
            push(spellIcon(SHADOWFORM, FALLBACK_SHADOW), "Shadowform")
        end
    end

    if class == "ROGUE" and o.roguePoisons then
        local knowsLethal, knowsNonLethal = false, false
        for i = 1, #LETHAL_POISONS do
            if spellKnown(LETHAL_POISONS[i]) then knowsLethal = true break end
        end
        for i = 1, #NONLETHAL_POISONS do
            if spellKnown(NONLETHAL_POISONS[i]) then knowsNonLethal = true break end
        end
        if knowsLethal and not anyPlayerAuraPresent(LETHAL_POISONS) then
            push(spellIcon(LETHAL_POISONS[1], FALLBACK_POISON), "Lethal")
        end
        if knowsNonLethal and not anyPlayerAuraPresent(NONLETHAL_POISONS) then
            push(spellIcon(NONLETHAL_POISONS[1], FALLBACK_POISON), "Non-lethal")
        end
    end

    if o.raidBuffs and IsInGroup() then
        local roster = ClassReminders._rosterClasses or {}
        for i = 1, #RAID_BUFFS do
            local def = RAID_BUFFS[i]
            if roster[def.class] and not anyPlayerAuraPresent(def.buffIDs) then
                push(spellIcon(def.iconSpell, def.fallback), def.label)
            end
        end
    end

    return out
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

local function buildSlot(f)
    local slot = CreateFrame("Frame", nil, f)
    slot:EnableMouse(false)

    local tex = slot:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(slot)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slot.icon = tex

    local glow = slot:CreateTexture(nil, "OVERLAY")
    glow:SetTexture([[Interface\Buttons\UI-ActionButton-Border]])
    glow:SetBlendMode("ADD")
    glow:SetPoint("CENTER", slot, "CENTER", 0, 0)
    glow:SetVertexColor(1, 0.85, 0.1, 0.8)
    glow:Hide()
    slot.glow = glow

    local ag = glow:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(0.25)
    a:SetToAlpha(0.9)
    a:SetDuration(0.7)
    slot.glowAnim = ag

    local label = slot:CreateFontString(nil, "OVERLAY")
    label:SetPoint("TOP", slot, "BOTTOM", 0, -2)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    slot.label = label

    slot:Hide()
    return slot
end

local function buildFrame()
    if ClassReminders.frame then return ClassReminders.frame end

    local f = CreateFrame("Frame", "TenUIClassRemindersFrame", UIParent)
    f:SetSize(40, 52)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f._locked = true
    f:Hide()

    f.slots = {}
    for i = 1, MAX_SLOTS do
        f.slots[i] = buildSlot(f)
    end

    ns.QoLDrag.Attach(f, getOpts, function(o)
        dlog("position saved -> %.0f, %.0f", o.x or 0, o.y or 0)
    end)

    ClassReminders.frame = f
    return f
end

local function render(entries)
    local f = ClassReminders.frame
    local o = getOpts()
    if not (f and o) then return end

    local n = #entries
    if n == 0 then
        f:Hide()
        return
    end

    local size    = o.iconSize or DEFAULTS.iconSize
    local fontSz  = o.fontSize or DEFAULTS.fontSize
    local spacing = 6
    local labelH  = fontSz + 4
    local width   = n * size + (n - 1) * spacing
    local fontPath = resolveFont()

    f:SetSize(width, size + labelH)
    if not f._dragging then
        f:ClearAllPoints()
        f:SetPoint(o.point or "CENTER", UIParent, o.point or "CENTER", o.x or 0, o.y or 0)
    end

    for i = 1, MAX_SLOTS do
        local slot = f.slots[i]
        local e = entries[i]
        if e then
            slot:SetSize(size, size)
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * (size + spacing), 0)
            slot.icon:SetTexture(e.icon)
            slot.glow:SetSize(size * 1.6, size * 1.6)
            slot.label:SetFont(fontPath, fontSz, "OUTLINE")
            slot.label:SetText(e.label or "")
            if o.glow then
                slot.glow:Show()
                if not slot.glowAnim:IsPlaying() then slot.glowAnim:Play() end
            else
                slot.glowAnim:Stop()
                slot.glow:Hide()
            end
            slot:Show()
        else
            slot.glowAnim:Stop()
            slot.glow:Hide()
            slot:Hide()
        end
    end

    f:SetAlpha(1)
    f:Show()
end

local TEST_ENTRIES = nil

local function buildTestEntries()
    if TEST_ENTRIES then return TEST_ENTRIES end
    TEST_ENTRIES = {
        { icon = spellIcon(EARTH_SHIELD, FALLBACK_SHIELD), label = "Shield" },
        { icon = FALLBACK_PET,     label = "Pet" },
        { icon = FALLBACK_PASSIVE, label = "Passive!" },
        { icon = spellIcon(21562, 135987), label = "Fortitude" },
    }
    return TEST_ENTRIES
end

local function update()
    local f = ClassReminders.frame
    if not f then return end
    local o = getOpts()
    if not o then return end

    if f._locked == false then
        render(buildTestEntries())
        return
    end

    local now = GetTime and GetTime() or 0
    local testing = ClassReminders._testUntil > now

    if testing then
        render(buildTestEntries())
        return
    end

    if not o.enabled then
        f:Hide()
        return
    end

    if o.hideWhileMounted and IsMounted() then f:Hide() return end
    if o.hideInRested and IsResting() then f:Hide() return end
    if o.onlyOutOfCombat and InCombatLockdown() then f:Hide() return end
    if o.instanceOnly and not IsInInstance() then f:Hide() return end
    if not o.showInRaid and IsInRaid() then f:Hide() return end

    render(evaluate(o))
end

local function scheduleUpdate()
    if ClassReminders._updateQueued then return end
    ClassReminders._updateQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, function()
            ClassReminders._updateQueued = false
            update()
        end)
    else
        ClassReminders._updateQueued = false
        update()
    end
end

local function scheduleRosterRebuild()
    if ClassReminders._rosterQueued then return end
    ClassReminders._rosterQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            ClassReminders._rosterQueued = false
            rebuildRoster()
            scheduleUpdate()
        end)
    else
        ClassReminders._rosterQueued = false
        rebuildRoster()
        update()
    end
end

function ClassReminders:Test(seconds)
    if not self.frame then buildFrame() end
    local o = getOpts()
    if not o then
        dlog("Test: no profile (savedvars not ready?)")
        return false
    end
    local dur = tonumber(seconds) or 5
    self._testUntil = (GetTime and GetTime() or 0) + dur
    update()
    if C_Timer and C_Timer.After then
        C_Timer.After(dur + 0.1, function()
            update()
        end)
    end
    dlog("test display forced for %ds", dur)
    return true
end

function ClassReminders:ApplyOptions()
    if not self.frame then return end
    rebuildRoster()
    update()
end

function ClassReminders:IsEnabled()
    local o = getOpts()
    return o and o.enabled == true or false
end

function ClassReminders:SetUnlocked(unlocked)
    if not self.frame then buildFrame() end
    local f = self.frame
    f._locked = not unlocked
    f:EnableMouse(unlocked and true or false)
    update()
end

function ClassReminders:ResetPosition()
    local o = getOpts()
    if not o then return end
    o.point = DEFAULTS.point
    o.x     = DEFAULTS.x
    o.y     = DEFAULTS.y
    update()
    dlog("position reset to default (%s %d, %d)", DEFAULTS.point, DEFAULTS.x, DEFAULTS.y)
end

function ClassReminders:CenterHorizontally()
    local o = getOpts()
    if not o then return end
    o.point = "CENTER"
    o.x = 0
    update()
    dlog("centered horizontally (x = 0, y = %.0f)", o.y or 0)
end

local LIFECYCLE_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_UPDATE_RESTING",
    "PLAYER_MOUNT_DISPLAY_CHANGED",
    "ZONE_CHANGED_NEW_AREA",
    "SPELLS_CHANGED",
    "PET_BAR_UPDATE",
    "PLAYER_SPECIALIZATION_CHANGED",
    "TRAIT_CONFIG_UPDATED",
}

local function onLifecycleEvent(event)
    if event == "PLAYER_ENTERING_WORLD" then
        scheduleRosterRebuild()
    end
    scheduleUpdate()
end

local function onRosterEvent()
    scheduleRosterRebuild()
end

local function syncUnitEvents()
    local uf = ClassReminders._unitFrame
    if not uf then
        uf = CreateFrame("Frame")
        uf:SetScript("OnEvent", function()
            scheduleUpdate()
        end)
        ClassReminders._unitFrame = uf
    end
    if not uf._registered then
        uf:RegisterUnitEvent("UNIT_AURA", "player", "pet")
        uf:RegisterUnitEvent("UNIT_PET", "player")
        uf._registered = true
    end
end

function ClassReminders:OnEnable()
    local p = ns:GetProfile()
    p.modules = p.modules or {}
    p.modules.General = p.modules.General or {}
    p.modules.General.classReminders = p.modules.General.classReminders or {}
    if ns._deepCopyMissing then
        ns._deepCopyMissing(p.modules.General.classReminders, DEFAULTS)
    end
    self.profileRef = p.modules.General

    buildFrame()
    syncUnitEvents()

    self._handlers = {}
    for i = 1, #LIFECYCLE_EVENTS do
        local ev = LIFECYCLE_EVENTS[i]
        self._handlers[#self._handlers + 1] = {
            event = ev,
            fn    = ns:RegisterEvent(ev, onLifecycleEvent),
        }
    end
    self._handlers[#self._handlers + 1] = {
        event = "GROUP_ROSTER_UPDATE",
        fn    = ns:RegisterEvent("GROUP_ROSTER_UPDATE", onRosterEvent),
    }

    rebuildRoster()
    scheduleUpdate()

    dlog("enabled (reminders %s)", self:IsEnabled() and "ON" or "off")
end

function ClassReminders:OnDisable()
    if self._handlers then
        for i = 1, #self._handlers do
            local h = self._handlers[i]
            ns:UnregisterEvent(h.event, h.fn)
        end
        self._handlers = nil
    end
    if self._unitFrame and self._unitFrame._registered then
        self._unitFrame:UnregisterEvent("UNIT_AURA")
        self._unitFrame:UnregisterEvent("UNIT_PET")
        self._unitFrame._registered = false
    end
    if self.frame then
        self.frame:Hide()
    end
end

ClassReminders.DEFAULTS = DEFAULTS

ns:RegisterModule("ClassReminders", {
    OnEnable  = function() ClassReminders:OnEnable() end,
    OnDisable = function() ClassReminders:OnDisable() end,
})
