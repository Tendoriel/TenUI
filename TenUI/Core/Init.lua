local addonName, ns = ...

ns.name = addonName
ns.version = C_AddOns.GetAddOnMetadata(addonName, "Version")

ns.modules = {}
ns.eventHandlers = {}
ns.customEventHandlers = {}
ns.savedVarsReady = false

_G.TenUI = ns
_G.TendorHUD = ns
