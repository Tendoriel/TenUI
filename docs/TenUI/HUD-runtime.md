# HUD module guide

| Module | Responsibility |
| --- | --- |
| [AuraIdentity](../../TenUI/Modules/AuraIdentity.lua) | Relates spell IDs, aliases and cooldown viewer entries so both trackers can resolve the same effect. |
| [AurasDiagnostics](../../TenUI/Modules/AurasDiagnostics.lua) | Reports the aura tracker's catalog, display and mirror state when investigating a missing or misplaced entry. |
| [AurasNative](../../TenUI/Modules/AurasNative.lua) | Maps catalog entries to player buffs and current-target debuffs, then configures native icon and bar displays. |
| [TrackedAuras](../../TenUI/Modules/TrackedAuras.lua) | Configures AuraContainer slots, icon and bar regions, timer formatting, stacks and glow. Blizzard updates bound values during combat. |
| [CDMLayout](../../TenUI/Core/CDMLayout.lua) | Reads Blizzard's saved cooldown viewer layout for consumers that need the player's categories and ordering. |
| [EbonMight](../../TenUI/Modules/Resources/EbonMight.lua) | Provides the optional Augmentation duration bar alongside mana and Essence. |
| [NativeResourceBar](../../TenUI/Modules/Resources/NativeResourceBar.lua) | Binds a resource bar to aura duration or applications. Reuses the last configured native slot under combat restrictions. |
| [PowerPrediction](../../TenUI/Modules/Resources/PowerPrediction.lua) | Resolves spell costs and supported resource gains for the prediction overlay. |
| [PixelPerfect](../../TenUI/Core/PixelPerfect.lua) | Converts physical pixels to frame units, sizes borders, aligns anchor edges and applies font flags. |

## When the HUD updates

Cooldown rows process game events as they arrive. Between events they check range and short-lived item or summon state every 0.2 seconds and request a full refresh once per second. A spellbook or override event invalidates the lookup used for press flashes.

Tracked Icons and Tracked Bars use Blizzard's native aura updates when both displays support them. Polling resumes for legacy displays and for summons with a locally tracked expiry.

Class Reminders hide on entry to combat or on death. Leaving combat or returning to life re-evaluates the current profile, group and auras. The six raid-buff switches take effect when group buff tracking is enabled and the roster includes a player of the providing class.
