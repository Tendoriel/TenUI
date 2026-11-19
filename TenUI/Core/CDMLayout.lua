local _, ns = ...

local snapshot

local function isSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function readDisplayData(provider)
    local manager = provider:GetLayoutManager()
    local currentTag = CooldownViewerUtil.GetCurrentClassAndSpecTag()
    if not manager or not currentTag then return nil end
    local applied = manager:GetActiveLayout(Enum.CDMLayoutMode.AccessOnly)
    local active = applied
    if active and CooldownManagerLayout_GetClassAndSpecTag(active) ~= currentTag then active = nil end
    if not active and not manager:IsPreviouslyActiveLayoutForSpecDefault(currentTag) then
        active = manager:GetLayout(manager:GetPreviouslyActiveLayoutIDForSpec(currentTag))
        if not active then
            for _, layout in manager:EnumerateLayouts() do
                if CooldownManagerLayout_GetClassAndSpecTag(layout) == currentTag then
                    active = layout
                    break
                end
            end
        end
    end
    local updating = provider.IsLayoutUpdateQueued and provider:IsLayoutUpdateQueued()
    if active == applied and not updating and provider:IsDirty() == false then
        local built = provider:GetDisplayData()
        if built then return built end
    end
    local customOrder = active and CooldownManagerLayout_GetOrderedCooldownIDs(active)
    local overrides = active and CooldownManagerLayout_GetCooldownInfo(active)

    -- The provider's ordered getters may write to Blizzard's layout when its display data is dirty.
    local categories = Enum.CooldownViewerCategory
    local hideFlag = Enum.CooldownSetSpellFlags.HideByDefault
    local infoByID, defaults = {}, {}
    for _, category in ipairs(CooldownViewerSettingsDataProvider_GetCategories()) do
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
                        category = categories.HiddenPassive
                    elseif category == categories.Essential or category == categories.Utility then
                        category = categories.HiddenActive
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
    if not (settings and settings.GetDataProvider) then return previous end

    local ok, data = pcall(function()
        local provider = settings:GetDataProvider()
        if provider then return readDisplayData(provider) end
    end)
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
