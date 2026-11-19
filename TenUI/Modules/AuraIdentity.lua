local _, ns = ...

function ns.CreateAuraIdentity(Auras, isSecret, _IsUsableSID)
    local function GetBaseSpellID(entry)
        return type(entry) == "table" and entry.spellID or nil
    end

    local function BuildMatchSpellIDs(entry)
        local out = {}
        if type(entry) ~= "table" then return out end
        local function add(v)
            v = tonumber(v)
            if _IsUsableSID(v) then
                for i = 1, #out do if out[i] == v then return end end
                out[#out + 1] = v
            end
        end
        if type(entry.linkedSpellIDs) == "table" then
            for i = 1, #entry.linkedSpellIDs do add(entry.linkedSpellIDs[i]) end
        end
        add(entry.overrideTooltipSpellID)
        add(entry.overrideSpellID)
        add(entry.spellID)
        return out
    end

    local function BuildStableEntryID(entry)
        if type(entry) ~= "table" then return nil end
        local cdID = tonumber(entry.cooldownID)
        if cdID then
            return "cdm:" .. cdID
        end
        local sid = tonumber(entry.spellID)
        if sid then return "spell:" .. sid end
        return nil
    end

    local function GetLinkedSpell(entry)
        return type(entry) == "table" and entry.linkedSpellID or nil
    end

    local function SetLinkedSpell(entry, linkedSpellID)
        if type(entry) ~= "table" then return false end
        if entry.linkedSpellID == linkedSpellID then return false end
        entry.linkedSpellID = linkedSpellID
        return true
    end

    local function GetAuraSpellID(entry)
        return type(entry) == "table" and entry.auraSpellID or nil
    end

    local function UpdateLinkedSpell(entry, spellID)
        if type(entry) ~= "table" then return false end
        local linked = entry.linkedSpellIDs
        if type(linked) ~= "table" then return false end
        if isSecret(spellID) then return false end
        if entry.linkedSpellID ~= nil and spellID == GetBaseSpellID(entry) then
            return SetLinkedSpell(entry, nil)
        end
        for i = 1, #linked do
            if linked[i] == spellID then
                entry._linkedFromAura = true
                return SetLinkedSpell(entry, spellID)
            end
        end
        return false
    end

    local function SpellIDMatchesAnyAssociatedSpellIDs(entry, spellID, excludeRawLinked)
        if type(entry) ~= "table" then return false end
        if isSecret(spellID) then return false end
        if spellID == nil then return false end
        local auraSpellID = GetAuraSpellID(entry)
        if not isSecret(auraSpellID) and auraSpellID ~= nil and spellID == auraSpellID then
            return true, "auraSpellID"
        end
        if entry.linkedSpellID == spellID then return true, "linkedSpellID" end
        if entry.overrideTooltipSpellID == spellID then return true, "overrideTooltipSpellID" end
        if entry.overrideSpellID == spellID then return true, "overrideSpellID" end
        if entry.spellID == spellID then return true, "spellID" end
        if excludeRawLinked then return false end
        local linked = entry.linkedSpellIDs
        if type(linked) == "table" then
            for i = 1, #linked do
                if linked[i] == spellID then return true, "linkedSpellIDs[" .. i .. "]" end
            end
        end
        return false
    end

    local function GetDisplaySpellID(entry)
        if type(entry) ~= "table" then return nil end
        local auraSpellID = GetAuraSpellID(entry)
        if auraSpellID and not isSecret(auraSpellID) then return auraSpellID end
        if entry.linkedSpellID and not isSecret(entry.linkedSpellID) then return entry.linkedSpellID end
        if entry.overrideTooltipSpellID and not isSecret(entry.overrideTooltipSpellID) then return entry.overrideTooltipSpellID end
        if entry.overrideSpellID and not isSecret(entry.overrideSpellID) then return entry.overrideSpellID end
        if entry.spellID and not isSecret(entry.spellID) then return entry.spellID end
        return nil
    end

    local function GetDisplayTexture(entry)
        if type(entry) ~= "table" then return nil, nil end
        local function tex(sid)
            if not (sid and C_Spell and C_Spell.GetSpellTexture) then return nil end
            if isSecret(sid) then return nil end
            local ok, t = pcall(C_Spell.GetSpellTexture, sid)
            if ok and Auras._validTexture(t) then return t end
            return nil
        end
        local auraSpellID = GetAuraSpellID(entry)
        if auraSpellID then
            local t = tex(auraSpellID)
            if t then return t, "aura" end
        end
        if entry.linkedSpellID then
            local t = tex(entry.linkedSpellID)
            if t then return t, "linked" end
        end
        if entry.overrideTooltipSpellID then
            local t = tex(entry.overrideTooltipSpellID)
            if t then return t, "overrideTooltip" end
        end
        local t = tex(entry.spellID)
        if t then return t, "base" end
        if Auras._validTexture(entry.icon) then return entry.icon, "fallback" end
        return nil, "fallback"
    end

    local function GetDisplayName(entry)
        if type(entry) ~= "table" then return nil, nil end
        local function nm(sid)
            if not (sid and C_Spell and C_Spell.GetSpellName) then return nil end
            if isSecret(sid) then return nil end
            local ok, n = pcall(C_Spell.GetSpellName, sid)
            if ok and type(n) == "string" and n ~= "" then return n end
            return nil
        end
        local auraSpellID = GetAuraSpellID(entry)
        if auraSpellID then
            local n = nm(auraSpellID)
            if n then return n, "aura" end
        end
        if entry.linkedSpellID then
            local n = nm(entry.linkedSpellID)
            if n then return n, "linked" end
        end
        if entry.overrideTooltipSpellID then
            local n = nm(entry.overrideTooltipSpellID)
            if n then return n, "overrideTooltip" end
        end
        if entry.overrideSpellID then
            local n = nm(entry.overrideSpellID)
            if n then return n, "override" end
        end
        local n = nm(entry.spellID)
        if n then return n, "base" end
        return entry.label, "label"
    end

    local function RefreshDisplayFields(entry)
        if type(entry) ~= "table" then return end
        entry.displaySpellID = GetDisplaySpellID(entry)
        local name, labelSource = GetDisplayName(entry)
        entry.displayName  = name
        entry.labelSource  = labelSource
        if not Auras._validTexture(entry.displayIcon) then
            local icon, iconSource = GetDisplayTexture(entry)
            entry.displayIcon  = icon
            entry.iconSource   = iconSource
        end
    end

    local function SetAuraInstanceInfo(entry, auraInfo, unit)
        if type(entry) ~= "table" or type(auraInfo) ~= "table" then return end
        local auraSpellID  = auraInfo.spellId
        local auraInstance = auraInfo.auraInstanceID
        entry.auraSpellID    = auraSpellID
        entry.auraInstanceID = auraInstance
        entry.auraDataUnit   = unit
        entry.activeAuraSource = "unitAura"
        UpdateLinkedSpell(entry, auraSpellID)
        RefreshDisplayFields(entry)
    end

    local function ClearAuraInstanceInfo(entry)
        if type(entry) ~= "table" then return end
        if entry._linkedFromAura then
            local auraSpellID = GetAuraSpellID(entry)
            if not isSecret(auraSpellID) and auraSpellID == GetLinkedSpell(entry) then
                SetLinkedSpell(entry, nil)
            else
                SetLinkedSpell(entry, nil)
            end
        end
        entry._linkedFromAura  = nil
        entry.auraSpellID      = nil
        entry.auraInstanceID   = nil
        entry.auraDataUnit     = nil
        entry.activeAuraSource = nil
        RefreshDisplayFields(entry)
    end

    return {
        GetBaseSpellID                     = GetBaseSpellID,
        BuildMatchSpellIDs                 = BuildMatchSpellIDs,
        BuildStableEntryID                 = BuildStableEntryID,
        GetLinkedSpell                     = GetLinkedSpell,
        SetLinkedSpell                     = SetLinkedSpell,
        GetAuraSpellID                     = GetAuraSpellID,
        UpdateLinkedSpell                  = UpdateLinkedSpell,
        SpellIDMatchesAnyAssociatedSpellIDs = SpellIDMatchesAnyAssociatedSpellIDs,
        GetDisplaySpellID                  = GetDisplaySpellID,
        GetDisplayTexture                  = GetDisplayTexture,
        GetDisplayName                     = GetDisplayName,
        RefreshDisplayFields               = RefreshDisplayFields,
        SetAuraInstanceInfo                = SetAuraInstanceInfo,
        ClearAuraInstanceInfo              = ClearAuraInstanceInfo,
        IsUsableSID                        = _IsUsableSID,
    }
end
