local addonName, ns = ...

local type     = type
local pairs    = pairs
local tostring = tostring
local pcall    = pcall

local function buildInformationPage(sc)
    local C = ns.UI
    if not C then return end
    local Theme = C.Theme
    local children = {}

    children[#children + 1] = C.CreateSection(sc, "Information")

    local verLabel = C.Text(sc, C.Fonts.title, Theme.color.accent,
        "TenUI  v" .. tostring(ns.version or "0.1.0") .. "  (WoW 12.0.5)")
    children[#children + 1] = verLabel

    children[#children + 1] = C.CreateSubSection(sc, "Loaded Modules")

    local function getModuleList()
        if not ns.modules then return "No modules registered." end
        local lines = {}
        for name, mod in pairs(ns.modules) do
            local state = (mod.enabled) and "enabled" or "disabled"
            lines[#lines + 1] = "  " .. tostring(name) .. " (" .. state .. ")"
        end
        table.sort(lines)
        return table.concat(lines, "\n")
    end

    local modLabel = C.Text(sc, C.Fonts.value, Theme.color.text, getModuleList())
    modLabel:SetJustifyH("LEFT")
    modLabel:SetWordWrap(true)
    children[#children + 1] = modLabel

    children[#children + 1] = C.CreateSubSection(sc, "Slash Commands")

    local cmdText = table.concat({
        "/tenui options         - open this window",
        "/tenui debug           - toggle debug log window",
        "/tenui debug clear     - clear debug log",
        "/tenui lock / unlock   - lock/unlock anchor frames",
        "/tenui reset anchors   - reset all anchors to defaults",
        "/tenui bars scan       - re-scan Blizzard CDM",
        "/tenui trinkets rescan - re-scan trinkets",
        "/tenui auras rescan    - refresh aura mirror",
        "/tenui castbar test    - test cast bar animation",
        "/tenui version         - print version",
    }, "\n")

    local cmdLabel = C.Text(sc, C.Fonts.value, Theme.color.textDim, cmdText)
    cmdLabel:SetJustifyH("LEFT")
    cmdLabel:SetWordWrap(true)
    children[#children + 1] = cmdLabel

    children[#children + 1] = C.CreateSubSection(sc, "Last Scanner Summary")

    local function getScannerSummary()
        if ns.Scanner and ns.Scanner.GetLastScanSummary then
            local ok, s = pcall(ns.Scanner.GetLastScanSummary, ns.Scanner)
            if ok and s then return tostring(s) end
        end
        if ns.Bars and ns.Bars.Scanner and ns.Bars.Scanner.CDM then
            return "(CDM scanner loaded - use /tenui bars scan to run)"
        end
        return "Scanner module not loaded."
    end

    local scanLabel = C.Text(sc, C.Fonts.value, Theme.color.textDim, getScannerSummary())
    scanLabel:SetJustifyH("LEFT")
    scanLabel:SetWordWrap(true)
    children[#children + 1] = scanLabel

    children[#children + 1] = C.CreateButton(sc, "Refresh", function()
        modLabel:SetText(getModuleList())
        scanLabel:SetText(getScannerSummary())
    end)

    local totalH = C.LayoutVertical(sc, children, 4, -8)
    sc:SetHeight(math.max(totalH, 10))
end

ns.Options:RegisterPage({
    key   = "information",
    label = "Information",
    build = buildInformationPage,
})
