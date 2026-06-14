local addonName, ns = ...

ns.name = addonName
ns.version = "0.1.1"

ns.modules = {}
ns.eventHandlers = {}
ns.customEventHandlers = {}
ns.savedVarsReady = false

_G.TenUI = ns
_G.TendorHUD = ns
