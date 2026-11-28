local _, ns = ...

local snapshot

local function isSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function readDisplayData(provider)
    local manager = provider and provider.layoutManager
    local currentTag = CooldownViewerUtil and CooldownViewerUtil.GetCurrentClassAndSpecTag()
    if not currentTag then return end
    -- Layout getters can initialize the manager and notify Blizzard's secure
    -- listeners. Only inspect data the client has already materialized.
    local layouts = manager and manager.layouts
    local applied = layouts and layouts[manager.activeLayoutID]
    local active = applied
    if not active or active.classAndSpecTag ~= currentTag then
        local saved = manager and manager.lastActiveLayoutIDsPerSpec
        local id = saved and saved[currentTag]
        active = layouts and layouts[id]
        if active and active.classAndSpecTag ~= currentTag then active = nil end
        if not active and id ~= 0 then
            for _, layout in pairs(layouts or {}) do
                if layout.classAndSpecTag == currentTag then active = layout break end
            end
        end
    end
    if active and applied == active and not provider.displayDataDirty and not provider.layoutUpdateQueued
        and provider.displayData then return provider.displayData end
    local customOrder = active and active.orderedCooldownIDs
    local overrides = active and active.cooldownInfo
    local categories = Enum.CooldownViewerCategory
    local hideFlag = Enum.CooldownSetSpellFlags.HideByDefault
    local infoByID, defaults = {}, {}
    for _, category in ipairs({ categories.Essential, categories.Utility, categories.TrackedBuff, categories.TrackedBar }) do
        local ids = C_CooldownViewer.GetCooldownViewerCategorySet(category, true)
        if isSecret(ids) or type(ids) ~= "table" then return nil end
        for _, id in ipairs(ids) do
            if isSecret(id) or type(id) ~= "number" then return nil end
            local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
            if isSecret(info) then return nil end
            if info and not infoByID[id] then
                local category = info.category
                local override = overrides and overrides[id]
                if override and override.category ~= nil then
                    category = tonumber(override.category)
                elseif FlagsUtil.IsSet(info.flags, hideFlag) then
                    if category == categories.TrackedBuff or category == categories.TrackedBar then
                        category = categories.HiddenPassive or categories.HiddenAura
                    elseif category == categories.Essential or category == categories.Utility then
                        category = categories.HiddenActive or categories.HiddenSpell
                    end
                end
                infoByID[id] = { category = category, isKnown = info.isKnown, isInvisible = info.isInvisible }
                defaults[#defaults + 1] = id
            end
        end
    end

    local ordered, seen = {}, {}
    for _, ids in ipairs({ customOrder or defaults, defaults }) do
        for _, id in ipairs(ids) do
            if isSecret(id) or type(id) ~= "number" then return nil end
            if infoByID[id] and not seen[id] then
                seen[id] = true
                ordered[#ordered + 1] = id
            end
        end
    end
    return { orderedCooldownIDs = ordered, cooldownInfoByID = infoByID }
end

function ns:ReadCooldownLayout()
    local _, class = UnitClass("player")
    local specID = self:GetLiveSpecID()
    local previous = snapshot and snapshot.class == class and snapshot.specID == specID and snapshot or nil
    local settings = CooldownViewerSettings
    if InCombatLockdown() or (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()) then
        return previous, false
    end
    local ok, data = pcall(readDisplayData, settings and settings.dataProvider)
    if not ok or isSecret(data) or type(data) ~= "table" then return previous, false end
    local ids, infoByID = data.orderedCooldownIDs, data.cooldownInfoByID
    if isSecret(ids) or isSecret(infoByID) or type(ids) ~= "table" or type(infoByID) ~= "table" then
        return previous, false
    end

    local layout = { class = class, specID = specID, byID = {}, ordered = {}, configured = {} }
    for _, id in ipairs(ids) do
        if isSecret(id) or type(id) ~= "number" then return previous, false end
        local info = infoByID[id]
        if isSecret(info) or type(info) ~= "table" then return previous, false end
        local category, known, invisible = info.category, info.isKnown, info.isInvisible
        if isSecret(category) or isSecret(known) or isSecret(invisible) or type(category) ~= "number" then
            return previous, false
        end
        layout.byID[id] = { category = category, isInvisible = invisible }
        if not invisible then
            local ordered = layout.ordered[category] or {}
            ordered[#ordered + 1] = id
            layout.ordered[category] = ordered
            if known then
                local configured = layout.configured[category] or {}
                configured[#configured + 1] = id
                layout.configured[category] = configured
            end
        end
    end
    snapshot = layout
    return layout, true
end

-- Enumerate widget children without executing the viewer or its layout mixins.
function ns.GetCooldownViewerFrames(viewer)
    local frames = {}
    if not viewer or not viewer.GetChildren then return frames end
    for _, child in ipairs({ viewer:GetChildren() }) do
        if not child:IsForbidden() then
            local index = child.layoutIndex
            if not isSecret(index) and type(index) == "number" then
                frames[#frames + 1] = child
            end
        end
    end
    table.sort(frames, function(a, b) return a.layoutIndex < b.layoutIndex end)
    return frames
end
