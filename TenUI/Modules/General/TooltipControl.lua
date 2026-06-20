local addonName, ns = ...

local pcall          = pcall
local type           = type
local tostring       = tostring
local tonumber       = tonumber
local issecretvalue  = issecretvalue
local IsShiftKeyDown = IsShiftKeyDown

local DEFAULTS = {
    enabled         = false,
    showItemID      = true,
    showSpellID     = true,
    showIconID      = true,
    requireModifier = false,
}

local TooltipControl = {
    profileRef = nil,
    _hooked    = false,
    lastSeen   = { itemID = nil, spellID = nil, iconID = nil, source = nil },
}
ns.TooltipControl = TooltipControl

local function dlog(fmt, ...)
    if ns.Debug and ns.Debug.Verbose then
        ns.Debug:Verbose("tooltip", "[TooltipControl] " .. tostring(fmt), ...)
    end
end

local function getOpts()
    local parent = TooltipControl.profileRef
    if type(parent) ~= "table" then return nil end
    parent.tooltipControl = parent.tooltipControl or {}
    return parent.tooltipControl
end

local function safeNumber(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return tonumber(v)
end

local function addIDLine(tooltip, label, id)
    if not (tooltip and tooltip.AddLine) then return end
    local ok = pcall(tooltip.AddLine, tooltip,
        ("|cff9d9d9d%s:|r %d"):format(label, id), 1, 1, 1)
    if ok and tooltip.Show then
        pcall(tooltip.Show, tooltip)
    end
end

local function gate(tooltip)
    local o = getOpts()
    if not (o and o.enabled) then return nil end
    if o.requireModifier and not IsShiftKeyDown() then return nil end
    if not tooltip then return nil end
    if tooltip.IsForbidden then
        local ok, forbidden = pcall(tooltip.IsForbidden, tooltip)
        if not ok or forbidden then return nil end
    end
    return o
end

local function onItemTooltip(tooltip, data)
    local o = gate(tooltip)
    if not o then return end

    local itemID = safeNumber(data and data.id)
    if not itemID and tooltip.GetItem then
        local ok, _, link = pcall(tooltip.GetItem, tooltip)
        if ok and link ~= nil and not (issecretvalue and issecretvalue(link)) then
            itemID = tonumber(tostring(link):match("item:(%d+)"))
        end
    end
    if not itemID then return end

    TooltipControl.lastSeen.itemID = itemID
    TooltipControl.lastSeen.source = "item"

    if o.showItemID then
        addIDLine(tooltip, "Item ID", itemID)
    end

    if o.showIconID and C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
        local iconID = ok and safeNumber(icon) or nil
        if iconID then
            TooltipControl.lastSeen.iconID = iconID
            addIDLine(tooltip, "Icon", iconID)
        end
    end
end

local function onSpellTooltip(tooltip, data)
    local o = gate(tooltip)
    if not o then return end

    local spellID = safeNumber(data and data.id)
    if not spellID and tooltip.GetSpell then
        local ok, _, id = pcall(tooltip.GetSpell, tooltip)
        if ok then
            spellID = safeNumber(id)
        end
    end
    if not spellID then return end

    TooltipControl.lastSeen.spellID = spellID
    TooltipControl.lastSeen.source = "spell"

    if o.showSpellID then
        addIDLine(tooltip, "Spell ID", spellID)
    end

    if o.showIconID and C_Spell and C_Spell.GetSpellTexture then
        local ok, icon = pcall(C_Spell.GetSpellTexture, spellID)
        local iconID = ok and safeNumber(icon) or nil
        if iconID then
            TooltipControl.lastSeen.iconID = iconID
            addIDLine(tooltip, "Icon", iconID)
        end
    end
end

local function installHooks()
    if TooltipControl._hooked then return true end
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall) then
        dlog("TooltipDataProcessor unavailable -- hooks NOT installed")
        return false
    end
    if not (Enum and Enum.TooltipDataType) then
        dlog("Enum.TooltipDataType unavailable -- hooks NOT installed")
        return false
    end

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItemTooltip)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, onSpellTooltip)
    if Enum.TooltipDataType.Macro then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Macro, onSpellTooltip)
    end

    TooltipControl._hooked = true
    dlog("tooltip post-call hooks installed (Item, Spell, Macro)")
    return true
end

function TooltipControl:IsEnabled()
    local o = getOpts()
    return o and o.enabled == true or false
end

function TooltipControl:DumpLastSeen()
    if not (ns.Debug and ns.Debug.Log) then return false end
    local ls = self.lastSeen
    ns.Debug:Log("[TooltipControl] last-seen tooltip ids:")
    ns.Debug:Log("  itemID  : %s", tostring(ls.itemID))
    ns.Debug:Log("  spellID : %s", tostring(ls.spellID))
    ns.Debug:Log("  iconID  : %s", tostring(ls.iconID))
    ns.Debug:Log("  source  : %s", tostring(ls.source))
    ns.Debug:Log("  hooked  : %s  enabled : %s",
        tostring(self._hooked), tostring(self:IsEnabled()))
    if ns.Debug.Show then ns.Debug:Show() end
    return true
end

function TooltipControl:OnEnable()
    local p = ns:GetProfile()
    p.modules = p.modules or {}
    p.modules.General = p.modules.General or {}
    p.modules.General.tooltipControl = p.modules.General.tooltipControl or {}
    if ns._deepCopyMissing then
        ns._deepCopyMissing(p.modules.General.tooltipControl, DEFAULTS)
    end
    self.profileRef = p.modules.General

    installHooks()

    dlog("enabled (id lines %s)", self:IsEnabled() and "ON" or "off")
end

function TooltipControl:OnDisable()
end

TooltipControl.DEFAULTS = DEFAULTS

ns:RegisterModule("TooltipControl", {
    OnEnable  = function() TooltipControl:OnEnable() end,
    OnDisable = function() TooltipControl:OnDisable() end,
})
