# Changelog

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
