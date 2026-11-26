# Changelog

## [0.6.2] - 2026-11-26

For WoW Retail 12.1.5 (Interface 120105).

### Settings and layout

- Search from the right-hand side of the settings header. Selecting a result opens its page or tab and highlights the matching control when available.
- Attach one HUD element to the edge of another and adjust the gap. Edit Mode now has controls for the grid, snapping, grid size, Undo, Cancel and Save & Lock. Right-click an unlocked element to open its Layout settings.
- General now includes shared font, outline and bar texture settings. Use Global Appearance to apply them across HUD modules. Settings with a resettable slider or color allow a right-click on the label to restore the default.
- Ctrl-click entries in the cooldown or aura preview to edit supported settings together. Layout can copy visuals between cooldown rows and display optional action-bar keybindings.
- Escape closes the settings window. Changing profiles refreshes open settings, and changing the global scale realigns HUD anchors.

### Profiles

- Export multiple sections in one compressed string. Import Preview lists the included sections and specialization data. Older TenUI profile strings remain readable.
- Apply selected sections to the active profile or create a new profile. A partial import can inherit omitted settings from the active profile.
- Copy sections between local profiles, duplicate the active profile, or undo the last reset or merge during the current session.
- Copy or reset specialization overrides and assign profiles by instance type. Use `/tenui profile list` and `/tenui profile NAME` to list or switch profiles.

### Combat HUD and reminders

- Fixed CDM stack counters that stopped updating if the buff first appeared after the icon was created. Added target-debuff handling for Flame Shock, Frost Fever, Blood Plague, Fire Breath and Unstable Affliction.
- The optional Cast Bar latency band filters queued casts out of its measurements. The spell queue and empower overlays respect hidden borders. Arcane Missiles tick markers also check for the tier bonus aura when readable.
- Entering combat dismisses resource preview samples. The Arcane Soul indicator uses the configured font, with separate size and color settings. Ebon Might prepares its live display while previewing.
- Class Reminders suspend aura subscriptions during combat. Between pulls in an active Mythic+ run, supported shields and poisons can show their last known state and its age. Raid buff and Tooltip ID options dim when their parent is disabled.

## [0.6.1] - 2026-11-26

For WoW Retail 12.1.5 (Interface 120105).

### Class Reminders

- Buff, form and pet reminders now hide as soon as you enter combat, including while testing or moving the HUD. After combat, the addon checks your current buffs and visibility settings again.
- Each of the six supported raid buffs has its own icon, localized spell name and switch. The settings also group self buffs and forms, targeted buffs and pet reminders separately. Existing profiles retain their group buff setting.

### Cooldown Manager and aura trackers

- Fixed a Lua error in the cooldown viewer's spellbook and spell override event handler, including on `SPELLS_CHANGED`.
- Cooldown rows check range and summon expiry between full icon updates. Action button flashes use an index that updates when the layout or spell overrides change.
- Tracked Icons and Tracked Bars stop their fallback timer when both use native aura tracking and no summon timer is active.

### Cast Bar, resources and layout

- Early recasts of Disintegrate, Arcane Missiles and Rapid Fire preserve the next channel tick marker when WoW provides the timing.
- An optional red band on the Cast Bar shows the measured delay between sending a cast and its start.
- Sunfury Arcane Mages can enable an Arcane Soul indicator in Resources. It counts down the final six global cooldowns of Arcane Surge and shows how many Barrages fit in Arcane Soul.
- HUD anchors realign after resolution or UI scale changes, including centered frames with odd pixel dimensions.

## [0.6.0] - 2026-11-25

For WoW Retail 12.1.5 (Interface 120105).

### Class reminders

- Buff, form and pet reminders disappear as soon as the player dies, including in raids. They stay hidden after releasing spirit and are evaluated again on resurrection.
- Holy Paladin Beacon reminders refresh when a party or raid member gains or loses an aura. Another group member changing specialization no longer clears the player's last known shield or poison state.
- The mounted visibility setting for Class Reminders and Stealth Tracking also recognizes skyriding.

### Cast Bar and cooldowns

- Fixed two Lua errors that could occur when WoW restricts channel and empower data.
- Empower stage colors preserve the border and stage dividers. The spell queue window stays inside the border, follows mid-cast resizing and uses readable cast timestamps when available.
- Interrupted and failed casts hold a full bar during their feedback animation.
- CDM press flashes appear above the cooldown swipe and support item actions and macros when WoW exposes the resolved spell or item.
- Player buff stack overlays, including Void Volley, let mouse input pass through to the underlying icon or game world.
- Tracked Icons and Tracked Bars group six additional target debuffs: Moonfire, Sunfire, Rake, Rip, Garrote and Rupture.

### Resources, skyriding and profiles

- Affliction and Demonology display whole Soul Shards when power values are restricted. Destruction retains partial shards.
- Disabling a resource bar or switching away from its resource detaches cast prediction. Native aura fills respect the resource border.
- Skyriding bars use the shared font rendering and pixel-scaled borders. Whirling Surge can use the native cooldown countdown when its remaining time is restricted.
- Profiles can export Resources or Cast Bar separately, including specialization overrides. Both import through the existing profile import screen.

## [0.5.9] - 2026-11-21

For WoW Retail 12.1.5 (Interface 120105).

### Resources

- Cast prediction now shows the expected change inside the resource bar. Green marks a gain and red marks a cost. On segmented bars, the highlight follows the affected portions of each segment and preserves the gaps between them.
- Primary and secondary bars have separate prediction toggles. A secondary Mana bar also honors the primary Mana prediction setting. TenUI reads cast costs for the displayed power type across classes. It also predicts base gains for selected casts in Balance, Elemental, Demonology, Destruction, Marksmanship, Devourer, Shadow and Arcane. Destruction predictions account for partial Soul Shards.
- Fixed initialization of the native resource display after a reload outside combat when aura data is restricted. This affects Augmentation’s Ebon Might and Devourer’s Soul Fragments.

### Cooldowns and auras

- Added an optional flash on a matching cooldown icon when its action button is pressed.
- Consecutive known target debuffs can share a native tracker group. This reduces the number of groups used by Tracked Icons and Tracked Bars while preserving the configured order of buffs and debuffs.

### Cast Bar and reminders

- Added an optional spell queue window to the Cast Bar for casts and channels. Its width follows the client’s spell queue setting and the cast duration.
- Empowered casts can display a different color for each stage. Select the Empower preview to adjust the display between casts.
- During temporary aura restrictions, personal shield and Rogue poison reminders can display their last known state for up to 30 seconds, labeled `(last seen)`. Group buff reminders continue to use current data.

## [0.5.8] - 2026-11-20

For WoW Retail 12.1.5 (Interface 120105).

### Resources

- Augmentation Evoker has a separate, movable Ebon Might countdown bar alongside Mana and Essence. It follows the player’s aura duration, including extensions, and can be disabled under Resources.
- Added optional cast prediction for secondary power bars and segmented resources. Amber shows the expected spend and green shows supported gains. The primary Mana bar keeps its separate prediction toggle.
- Added Whirlwind stacks for Fury, Sweeping Strikes stacks for Arms, and six Soul Fragment segments for Vengeance. Improved Devourer Soul Fragment tracking under aura restrictions and corrected Enhancement’s Maelstrom Weapon cap for builds with and without Raging Maelstrom.
- Druids can opt to show Mana on the secondary bar while in Cat or Bear Form.

### HUD and cooldowns

- Layout includes Consumables and Dragon Riding. The resource bars and Cast Bar can match the width of Essential Cooldowns.
- Resetting an anchor restores its live opacity. In Edit Mode, scroll over overlapping anchors to select the one you want to move.
- Centralized pixel snapping and HUD border thickness and enabled SLUG font rendering where supported.
- Kept the configured CDM icon geometry when switching to a target debuff timer and reduced swipe restarts during aura refreshes.
- Fixed the Expiring Aura Glow when a tracked slot becomes active after being empty. Added optional decimal seconds for Tracked Icons and Tracked Bars.
- Reduced the number of native aura groups used to measure tracker layout. Improved Cast Bar handling of restricted spell names and interrupt events.
- Group buff reminders skip NPC followers and guard against restricted aura data.

## [0.5.7] - 2026-11-19

For WoW Retail 12.1.5 (Interface 120105).

### Fixed

- **Tracked Bars.** With `Show Inactive` enabled, Call Dreadstalkers and Summon Demonic Tyrant keep their configured rows when either or both summons are active and after their timers expire.
- **Burning Rush.** The reminder appears while the buff is active, including in combat, and disappears when the buff is cancelled.

## [0.5.6] - 2026-11-17

For WoW Retail 12.1.5 (Interface 120105).

### Cooldown Manager

- Drag the larger icons in the pinned preview to reorder Cooldowns, Tracked Icons, and Tracked Bars. Right-click an icon to open its settings.
- `Enable 2nd Row` is at the top of Cooldown Display. Move cooldowns between rows directly in the preview. The duplicate list has been removed, and entries in either row stay out of Candidates.
- `Group Layout` opens the layout settings for the current group. Tracked Icons and Tracked Bars also have a shortcut to `Display Settings`.
- A cooldown can show the selected player buff's icon and remaining duration while the buff is active, then return to its usual display.

### Tracked Bars

- Set each bar's visibility, fill color and direction, icon, name, and timer. A bar can keep its group position or use its own X and Y offsets.
- Copy another tracked bar's appearance or reset to the group's appearance.

### Cast Bar and Resources

- The Cast Bar can show tick marks for supported channels and elapsed / total cast time. Both options are reflected in the settings preview.
- The Primary Resource Bar can fill the space of an unavailable Secondary Resource Bar when the two are aligned and close together.

### Reminders

- Class Reminders and Stealth have pinned icon previews. Click an icon to jump to its setting, or use `Test on HUD` to see the display in game.
- Class Reminders shows a preview for your class and spec. Class buffs and forms, pets, and group buffs have their own sections alongside appearance, visibility, and position.
- Stealth previews Stealth, Prowl, and Burning Rush. Class Reminder labels have space to stay readable at larger font sizes.

### Tracked Auras and Cast Bar

- Tracked Icons and active-only Tracked Bars follow the same order as the preview, including when player buffs and current-target debuffs are interleaved.
- In Aura Settings, `Expiring Aura Glow` lets you choose a threshold in seconds, a glow style and a color for each aura. It has its own preview and works independently of the Pandemic warning and timer color.
- Animated aura glows use the configured icon and bar dimensions, keeping them visible when Blizzard restricts access to live frame dimensions.
- Added channel tick marks for Arcane Missiles, Rapid Fire, Disintegrate, Fel Devastation, Eye Beam, Void Ray, Mind Sear and Void Torrent. Arcane Missiles, Rapid Fire, Disintegrate and Penance account for supported tick-count modifiers.
- Aura identity, native tracker configuration and diagnostics now live in separate modules.

## [0.5.5] - 2026-11-17

For WoW Retail 12.1.5 (Interface 120105).

### Fixed

- Choosing an Active Aura glow style enables it for that aura when the setting was inherited. Explicit Off remains available.
- Restored custom Active Aura styles that older profiles left inherited, including the Power Infusion selection saved at zero opacity.
- Color pickers now use Blizzard's opacity scale directly. Cancelling restores the original color and opacity.

### Added

- Auras has a tooltip setting for Tracked Icons and Tracked Bars with Always, Out of combat and Off modes.

## [0.5.4] - 2026-11-17

For WoW Retail 12.1.5 (Interface 120105).

### Added

- Aura Settings previews the selected custom Pandemic, Active and Proc glows in the chosen color.
- Profiles can export CDM, Auras or Layout separately, or export the full profile. Importing a partial export creates a new profile with defaults for the other sections.
- Cast Bar can hold a channel, interrupted cast or cancelled cast in its settings preview. The automatic preview cycle is still available.
- Class Reminders can warn Balance Druids when Moonkin Form is inactive.
- Skyriding adds separate horizontal and vertical offsets for the Whirling Surge cooldown text.

### Fixed

- Aura Settings applies the selected custom proc, active and Pandemic effects in Tracked Icons and Tracked Bars. Pandemic follows Blizzard's refresh window, and effects render above icon swipes and bar fills. Refreshing an aura keeps its timer without replaying the proc flash.
- Auras loads the configured CDM entries at startup without requiring the Blizzard Cooldown Manager settings to be opened first.
- With `Show Inactive` enabled, a Tracked Bars entry shared by a player buff and a current-target debuff shows one timer. The player buff takes priority while active.

### Improved

- Selecting a proc style enables the effect for auras that have no explicit proc setting.
- Tracked Icons and active-only Tracked Bars keep Blizzard's order within each unit. Tracked Icons stays centered when several spell IDs refer to the same tracked entry.
- CDM row updates reuse icons for existing entries, including moves between the two rows.
- Profiles shows why the current profile is active and indicates when a change is pending.

## [0.5.3] - 2026-11-16

### Fixed

- Tracked Bars keeps summons matched to the installed rows when combat delays a layout change. Unlearned auras stay out of the HUD by default.
- Tracked Icons and Tracked Bars can prepare fresh aura containers on reload while combat is active. Changes to existing containers retry when restrictions lift.
- Aura settings migrated from older profiles keep independent glow styles.
- Maelstrom Weapon uses Blizzard's aura stack bindings for its segments and count. If the native display is unavailable, the fallback clears unreadable counts.
- CDM updates target-debuff filters when spells change and waits for valid Blizzard layout data before applying layout changes or seeding a new specialization.
- Holy Paladin reminders distinguish your Beacon effects from another Paladin's. The General page's Enable TenUI switch now controls the HUD and keeps the minimap launcher available.

## [0.5.2] - 2026-11-16

### Added

- Aura Settings offers the CDM glow styles, including animated FX, for Pandemic warnings, active auras, and the moment an aura appears.
- Each tracked aura can use its own timer color and low-time threshold. Auras also has separate stack and active-highlight controls for Tracked Icons and Tracked Bars.

### Fixed

- Tracked Bars places player buffs and current-target debuffs in one column. Native aura filters are prepared during Edit Mode so the trackers are ready when combat starts.
- Void Volley shows the stack count from its buff on the CDM icon and updates after each cast.
- CDM debuff timers match linked spell IDs. Scanner keeps an equipment entry's item type and slot when adding it to a bar.
- Cast Bar ignores late stop events for a previous cast, clears ended channels, and preserves the interrupted state.
- Layout restores Global Scale and preserves saved anchor opacity and scale. Copy Positions and profile exports handle older specialization layouts.
- Stagger updates the bar with restricted values. Devourer can use the Collapsing Star aura to identify Void Metamorphosis. Skyriding detection uses the client's gliding state for Soar and flight forms.

## [0.5.1] - 2026-11-15

### Added

- CDM Settings can show the remaining time of your debuff on your current target directly on the ability icon.
- Class Reminders can show a check mark on active buffs and present pets.

### Fixed

- CDM icons and timers follow temporary spell replacements such as Voidform into Void Volley and switch back on expiry. Void Volley shows its remaining uses and updates after each cast.
- Tracked Icons centers player buffs and your current target's debuffs as one row, including in combat. Switching targets refreshes the tracked debuffs and CDM debuff timers.
- Timers on Tracked Icons and CDM debuff overlays show seconds without the `s` suffix.
- TenUI Edit Mode previews one bar per enabled Tracked Bars entry, including entries whose auras are currently inactive.
- Specialization changes refresh the HUD even when both specializations use the same profile. Entering a dungeon rechecks specialization after the loading screen.
- Per-ability cooldown text, range and resource tint, and combat-only settings now apply to CDM icons.

### Changed

- Simplified Aura Settings and Glow Effects to show options supported by the 12.1.5 renderer. The client provides the Pandemic warning.
- Grouped the most relevant controls in Resources and Cast Bar.

## [0.5.0] - 2026-11-15

### Changed

- Targeted WoW Retail 12.1.5 (Interface 120105).
- Tracked Icons and Tracked Bars use Blizzard's aura containers for player buffs and the player's debuffs on the current target. The client drives aura icons, stack counts, timers, and the Pandemic indicator. Target auras use a separate row or column.
- Removed automatic changes to Blizzard Cooldown Manager visibility and Edit Mode layouts.
- New specializations inherit the profile layout and initialize their ability rows from compatible entries or the current CDM configuration. New characters inherit the shared profile. Existing layouts and configured rows remain available in their original specialization.

### Fixed

- Tracked Icons and Tracked Bars render at their configured size in and out of combat. Inactive bars keep their native timers when the aura becomes active.
- The hidden cooldown filter follows the active Blizzard Cooldown Manager layout and refreshes when that layout changes.
- Elements with visibility set to Never stay hidden in TenUI Edit Mode.
- Mount visibility also accounts for skyriding forms, including Druid flight form.
- Profile changes reapply the layout, aura settings, cast bar, resources, consumables, trinkets, and reminder settings. Profile imports keep the legacy v1 format and carry a layout for characters without an existing specialization override.
- Essential and Utility timers use duration objects with the configured GCD behavior. The scanner includes specialization-independent cooldowns and eligible equipment slots.
- Class Reminders recognizes active Shadowform and Voidform through the shapeshift state, including when the aura lookup has restricted visibility.
- Cast Bar uses the player's cast bar ID when available and clears short casts after the grace period. Skyriding follows the selected Whirling Surge override and refreshes charges when the HUD appears.
- Warlock Soul Shard pips render partial shards from restricted power values. Aura-based resources retain the last readable value while the client restricts aura data.

## [0.3.1] - 2026-06-28

### Fixed

- Tracked auras (both tracked icons and tracked bars) now display correctly during combat instead of staying idle.
- Resolved Lua error spam and conflicts with the Blizzard Cooldown Manager that could occur in combat.
- Essential cooldown icons no longer flash as usable for a moment right after a cast when the resource requirement is not met; they now stay correctly dimmed and colored to match the Blizzard Cooldown Manager.
- Abilities enabled in the Blizzard Cooldown Manager are no longer mislabeled as "out of combat only".
- Some abilities could show an incorrect or placeholder icon; tracked displays now only use valid ability icons.

### Changed

- Tracked-aura display now follows the Blizzard Cooldown Manager more closely for both icons and bars.

## [0.3.0] - 2026-06-27

### Added

- Per-bar Visibility: every bar can be shown or hidden by state (always, never, in combat, out of combat, in raid, in party or solo), with independent options to show only inside instances, hide while in housing, and hide while mounted or skyriding.
- Max Stacks glow in the Cooldown Manager: charge abilities can now glow when they reach maximum charges, alongside the existing Proc and Ready glows.
- Active Aura Glow and Pandemic Glow: the glow texture and style are now selectable and play on live auras for both the icon and bar displays, including the animated glow textures.
- Consumables tracker in the Cooldown Manager (Healthstone, potions and more), with an icon grid to toggle which consumables are tracked and an option to add items by item ID; tracked consumables show their count, cooldown and combat lockout.
- Profiles: assign a profile to each specialization so it switches automatically when you change spec, rename a profile, copy a whole profile, and an ordered profile list.
- New Dragon Riding (Skyriding) HUD and settings tab: a skyriding speed bar with a Thrill threshold marker, Skyward Ascent and Second Wind charge pips, and the Whirling Surge cooldown.

### Changed

- Edit mode: smooth live snapping with no jitter or jump when you release an element, Shift to lock dragging to a single axis, and an adjustable snap distance; the element you are dragging now stays visible while it moves, and the pixel-nudge arrows appear only on the currently selected element.

### Fixed

- Demonology Soul Shard pip count no longer shows one shard too few.
- Guardian summons (Summon Demonic Tyrant and Call Dreadstalkers) now show both their remaining duration and the countdown digits on Tracked Bars.
- Tracked Bars and Tracked Icons now respect the "hide when mounted" option.
- Improved cast bar empower and secret-value handling, and various combat-display robustness fixes.

## [0.2.0] - 2026-06-20

### Added

- Demonology guardian summons (Summon Demonic Tyrant and Call Dreadstalkers) now show their remaining duration in Tracked Bars, using the live guardian duration when available and a cast-driven estimate otherwise, alongside the existing Essential icons.
- Implosion now shows the active Wild Imp count as a stack number, matching Blizzard's action bar.
- New read-only diagnostic: `/tenui auras rawset`.

### Fixed

- Updated for WoW patch 12.0.7 (Interface 120007).
- Primary Resource Bar: the "disable" toggle now reliably hides the bar instead of re-showing it on every power tick; the enable and alpha settings now persist correctly.
- Secondary Resource Bar: width and height are now restored after relog, and the anchor Alpha (Layout, Anchor Positioning) now persists and restores correctly.
- Diabolist "Demonic Art" (Diabolic Ritual): the tracked icon now shows the active variant's icon (Pit Lord, Mother of Chaos or Overlord) instead of a static base icon.

### Changed

- Debug logging is now silenced by default; per-module verbose channels can be enabled on demand with `/tenui debug verbose <module>`.

## 0.1.1 - 2026-06-14

- Tracked buff/debuff icons and bars now display correctly while in combat.
- Tracked bars now stay in sync with every configured Cooldown Manager bar group.
- Rune- and resource-spender abilities (such as proc-triggered spells) are no longer shown as unavailable.
- Tracked spells you have not learned for the current spec are hidden until they become available.
- Tracked icons and bars can now be reordered by dragging.
- Added a fill-color option for tracked bars.
- Cooldown swipe on tracked auras now winds down in the correct direction.
- The cast bar and resource bars can now be pinned in place while previewing them in the options.
- Anchor positioning gained nudge controls for precise placement.
- Fixed an in-combat error (ADDON_ACTION_BLOCKED) caused by the cooldown-viewer desaturation mirror.
- The cast bar now applies the font selected in its options.
- The bundled TenUI fonts are registered with SharedMedia, and the font dropdowns now list every SharedMedia font.
- Added a minimap button (via LibDBIcon, so it is detected by minimap-button collector addons) with a show/hide toggle in the options.
- Reworked the proc and ready glows so they no longer conflict with each other or animate incorrectly. Ready glow now animates smoothly and no longer conflicts with proc glow.
- Fixed anchor dragging so elements can be placed freely without jumping when snapping is off.
- Fixed the options window so it moves smoothly and no longer snaps to the screen edges.

## 0.1.0

Initial release.

- Cooldown bars built on the built-in Cooldown Manager, with Essential, Utility, Defensive, Trinkets and Custom groups and per-ability settings.
- Buff and debuff tracking as icon rows or timer bars, with stack counts, cooldown swipes and low-time coloring.
- Player cast bar supporting casts, channels and empowered spells.
- Primary and secondary resource bars for all classes and specs, including pip displays for discrete resources.
- Animated border glow effects with ten flipbook styles and a live preview.
- Quality-of-life extras: combat alerts, stealth indicator, class buff and talent reminders, optional spell/item IDs in tooltips.
- Anchor-based layout system: unlock, drag, snap, and fine-tune position, scale and alpha for every element.
- Profile management with copy, per-spec automatic swapping, and text-based export/import.
- Unified styled options window, SharedMedia support, and bundled bar fill textures.
- Slash command surface under `/tenui` (lock/unlock, resets, diagnostics).
