local _, ns = ...

local snapshot

local function isSecret(value)
    return issecretvalue and issecretvalue(value)
end

function ns:ReadCooldownLayout()
    local _, class = UnitClass("player")
    local specID = self:GetLiveSpecID()
    local previous = snapshot and snapshot.class == class and snapshot.specID == specID and snapshot or nil
    local settings = CooldownViewerSettings
    if not (settings and settings.GetDataProvider) then return previous end

    local ok, data = pcall(function()
        local provider = settings:GetDataProvider()
        if provider and provider:IsDirty() == false then return provider:GetDisplayData() end
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
