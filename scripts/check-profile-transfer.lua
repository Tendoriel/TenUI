-- Exercise section isolation and legacy imports with a stand-in for the client codec.
local encoded = {}
local function identity(value) return value end
C_EncodingUtil = {
    CompressString = identity, DecompressString = identity,
    EncodeBase64 = function(value)
        encoded[#encoded + 1] = value
        return tostring(#encoded)
    end,
    DecodeBase64 = function(key) return encoded[tonumber(key)] end,
}
local combat = false
InCombatLockdown = function() return combat end
local active = {
    modules = {
        Resources = { width = 91 }, CastBar = { width = 240 },
        Layout = { visuals = { Primary = { size = 11 } }, snapping = { distance = 7 } },
    },
    specScopes = { MAGE_1 = { resources = { width = 50 }, castbar = { width = 123 } } },
    _sharedSettingsSeeded = true,
}
local ns = {
    savedVarsReady = true, version = "0.6.2",
    db = { profiles = { Default = active }, activeProfile = "Default" },
    PrepareProfile = function() end, Fire = function() end,
}
assert(loadfile("TenUI/Core/Profile.lua"))("TenUI", ns)
local wire = assert(ns:ExportProfileString({resources = true, castbar = true}))
local imported, _, meta = ns:DeserializeProfileString(wire)
assert(meta.sections.resources and meta.sections.castbar and not meta.sections.positions)
assert(imported.specScopes.MAGE_1.castbar.width == 123 and not imported.modules.Layout)
imported.modules.CastBar.width = 100
imported.specScopes.MAGE_1.castbar.width = 88
assert(ns:ApplyProfileSections(imported, { castbar = true }))
assert(ns:GetProfile().modules.CastBar.width == 100 and active.modules.CastBar.width == 240)
assert(ns:GetProfile().specScopes.MAGE_1.resources.width == 50)
imported.modules.CastBar.width = 77
assert(ns:GetProfile().modules.CastBar.width == 100)
combat = true
assert(not ns:UndoProfileChange() and not ns:ApplyProfileSections(imported, { castbar = true }))
combat = false
assert(ns:UndoProfileChange() and ns:GetProfile().modules.CastBar.width == 240)
assert(not ns:UndoProfileChange())
local partial = "TenUI_Profile:v1:0.6.1:{modules={Layout={visuals={Primary={size=9}},snapping={distance=99}}}}"
local old, _, oldInfo = ns:DeserializeProfileString(partial)
assert(oldInfo.sections.visuals and not oldInfo.sections.all)
assert(ns:ApplyProfileSections(old, { visuals = true }))
assert(ns:GetProfile().modules.Layout.visuals.Primary.size == 9)
assert(ns:GetProfile().modules.Layout.snapping.distance == 7)
local legacy = "TendorHUD_Profile:v1:0.6.0:{modules={CastBar={width=55},General={mySetting=true}},customSetting=23}"
assert(ns:ImportProfile(legacy, "Legacy", true))
assert(ns.db.profiles.Legacy.customSetting == 23 and ns.db.profiles.Legacy.modules.General.mySetting)
assert(ns:ImportProfile(wire, "Inherited", true))
assert(ns.db.profiles.Inherited.modules.Layout.snapping.distance == 7)
assert(ns:GetProfileKey() == "Default" and not ns:ImportProfile(wire, "Inherited", true))
assert(not ns:DeserializeProfileString("TenUI:2:0.6.2:unknown:1"))
assert(not ns:DeserializeProfileString("TenUI_Profile:v1:0.6.1:{modules={CastBar=2}}"))
print("Profile section isolation, copy, undo and legacy import checks passed")
