# TenUI

A clean, combat-focused HUD for World of Warcraft: cooldowns, auras, resources, cast bar and trinkets in one configurable package.

TenUI 0.6.5 targets WoW Retail Midnight 12.1.5 (Interface 120105). See the [changelog](CHANGELOG.md) for version history.

[![Website](https://img.shields.io/badge/Website-tenuiaddon.com-08979c?style=flat)](https://tenuiaddon.com/) [![CurseForge](https://img.shields.io/badge/Download-CurseForge-F16436?style=flat)](https://www.curseforge.com/wow/addons/tenui) [![GitHub Releases](https://img.shields.io/badge/GitHub-Releases-181717?style=flat)](https://github.com/Tendoriel/TenUI/releases) [![WoW](https://img.shields.io/badge/WoW-12.1.5-blue?style=flat)](https://github.com/Tendoriel/TenUI) [![License](https://img.shields.io/badge/License-MIT-green?style=flat)](https://github.com/Tendoriel/TenUI/blob/main/LICENSE) [![Issues](https://img.shields.io/badge/Report-Issues-orange?style=flat)](https://github.com/Tendoriel/TenUI/issues)

## Screenshots

| HUD in combat | Cast bar and cooldown rows |
|:---:|:---:|
| ![Main HUD in combat: cooldown rows, tracked auras and resource bar](.github/media/hud-combat.png) | ![HUD with the player cast bar active alongside cooldown and aura rows](.github/media/hud-cast-meta.png) |

Options window, Resources page:

![Options window showing the Resources configuration page](.github/media/options-resources.png)

Cooldown Manager settings in an earlier release:

![Options window showing the CDM Bars page and tracked spell list](.github/media/options-cdm-bars.png)

## Features

### Cooldown Bars
- Rows of square cooldown icons driven by the built-in Cooldown Manager, organized into Essential, Utility, Defensive, Trinkets, Consumables and Custom groups.
- Per-ability settings: visibility, ordering and display behavior for each tracked spell.
- Reorder cooldowns in the pinned preview, move them between rows and right-click an icon to open its settings. A cooldown can show a selected active buff and its remaining time.
- Resource and usability color coding that mirrors the Cooldown Manager: ready, out of range, not enough resource and unusable are shown with distinct tints, and icons dim while on cooldown.
- Consumables tracker for healthstones, potions and more, with an icon grid to choose what to track and the option to add items by ID.
- Built-in scanner keeps tracked abilities in sync with your current spec and talents.

### Aura Tracking
- Track player buffs and your current target's debuffs as icons or timer bars, with stack counts and cooldown swipes. Set their order by dragging in the preview.
- Customize individual bars, keep their rows visible while inactive or position them separately.
- Choose timer colors, active and Pandemic glows, and a glow threshold in seconds for each aura.

### Cast Bar
- Replacement player cast bar with support for casts, channels and empowered spells.
- Configurable size, textures, fonts and position.
- Optional tick marks for supported channels and elapsed / total cast time. The bar can show the spell queue window and color empowered stages. Preview casts, channels, empowers, interruptions and cancellations in settings.

### Resources
- Primary and secondary resource bars for every class and spec, including discrete pips for combo points, holy power, chi and similar resources.
- Optional cast prediction highlights the expected gain in green or spend in red directly inside the bar or affected segments. Primary and secondary bars have separate controls. When the secondary bar displays Mana, it also honors the primary Mana prediction setting.
- Combat-aware visibility options.

### Glow Effects
- Animated border glows for procs and ability highlights, with ten distinct flipbook styles.
- Separate glows for procs, ready abilities, maximum charges, active auras and pandemic windows, each with its own style, color and on/off toggle.
- Per-purpose defaults with a live preview in the options window.

### Skyriding
- A skyriding HUD with a speed bar and a configurable Thrill of the Skies threshold marker.
- Charge pips for Skyward Ascent and Second Wind, plus the Whirling Surge cooldown.

### Quality of Life
- Combat enter/leave text alerts.
- Stealth, Prowl and Burning Rush indicators.
- Class buff, form, pet and talent build reminders. Preview the icons for your current class and specialization.
- Optional spell and item IDs in tooltips.

### Layout and Anchoring
- Every element sits on a named anchor: unlock, drag, snap and fine-tune with X/Y, scale and alpha controls.
- Smooth live snapping in edit mode, hold Shift to lock dragging to a single axis, and an adjustable snap distance.
- Per-element visibility by state (always, never, in combat, out of combat, in raid, in party or solo), with options to show only inside instances and to hide while in housing or while mounted.
- Anchor reset commands for individual elements or the whole layout.

### Profiles
- Multiple profiles with rename and copy support, and an ordered profile list.
- Automatic profile swapping by specialization or instance type (dungeon, raid, arena or battleground).
- Export a full profile or combine selected sections. Preview an import before creating a profile or applying selected sections to the active one. Undo restores the previous profile settings during the same session.

### Interface
- Search settings in the top-right of the options window. Select a result to open its page and highlight the control when available.
- SharedMedia support for fonts and bar textures, plus a set of bundled bar fill textures.

## Installation

### CurseForge (recommended)
1. Install the CurseForge app or visit the TenUI project page.
2. Search for "TenUI" and click Install.
3. Restart the game or reload your UI.

### Manual
1. Download the latest release from [GitHub Releases](https://github.com/Tendoriel/TenUI/releases).
2. Extract the archive so that the `TenUI` folder is inside `World of Warcraft/_retail_/Interface/AddOns/`.
3. Restart the game or run `/reload`.

### Build from source

Run `python3 scripts/build-release.py` from the checkout to build the ZIP in `releases/`. The script reads the version from `TenUI/TenUI.toc`, validates the TOC and XML includes, and writes the same ZIP bytes for the same source files. Pass `--output /path/to/TenUI.zip` to write elsewhere.

## Getting Started

1. Type `/tenui` or click TenUI in the minimap addon compartment to open settings.
2. Run `/tenui unlock` to unlock all anchors, drag elements where you want them, then `/tenui lock`.
3. Open the options window to configure modules, abilities and auras.

Useful commands:

| Command | Effect |
|---|---|
| `/tenui` / `/tenui help` | Open settings or list commands |
| `/tenui unlock` / `/tenui lock` | Unlock or lock anchors for dragging |
| `/tenui reset anchors` | Reset all element positions to defaults |
| `/tenui reset anchor <name>` | Reset a single element |
| `/tenui reset` | Prompt to wipe all saved settings |

## Configuration

The options window is organized by module:

- **Layout** — select any anchor and adjust position, scale and alpha with sliders and snap controls.
- **Cooldown Manager** groups **Cooldowns**, **Tracked Icons** and **Tracked Bars**. Drag in the preview to reorder entries and right-click for **CDM Settings** or **Aura Settings**.
- **Reminders** contains Class Reminders, Stealth and related alerts. Use **Test on HUD** to check reminder placement.
- **Glow Effects** — choose glow styles per purpose and preview them live.
- **Resources** — appearance, visibility, and cast cost and gain previews. Augmentation can move its separate Ebon Might bar in Layout or Edit Mode.
- **Cast Bar** — cast bar appearance and behavior.
- **Dragon Riding** — skyriding speed bar, charge pips and Whirling Surge cooldown.
- **Profiles** — manage, rename, copy, export and import profiles, and set up per-spec swapping.
- **Information** — version, module status and a quick command reference.

## FAQ

**Some aura timers behave differently in combat. Why?**
Since patch 12.0, the game hides certain combat data (exact health, aura durations and similar values) from addons while you are fighting. TenUI uses the supported display mechanisms so swipes, timers and colors keep updating, but a small number of details can only refresh fully once combat ends. This is a game-wide limitation that affects all addons.

**Can I move elements while in combat?**
No. Unlocking and dragging anchors is blocked during combat by the game. Leave combat, run `/tenui unlock`, and arrange your layout.

**Does TenUI replace the built-in Cooldown Manager?**
TenUI builds on top of it. The Cooldown Manager remains the source of truth for which abilities are tracked, and TenUI presents them with its own bars, icons and styling.

**How do I share my setup with a friend?**
In **Profiles**, choose the sections to share, generate the export and copy the string. The recipient can preview its contents and apply selected sections to their active profile. When creating a separate profile from a partial export, they can fill omitted sections with defaults or their current settings.

**My layout broke after an update. How do I recover?**
Run `/tenui reset anchors` to restore default positions without touching the rest of your settings. As a last resort, `/tenui reset` wipes all saved settings after a confirmation prompt.

## Feedback and Issues

Bug reports and feature requests are welcome on the [GitHub issue tracker](https://github.com/Tendoriel/TenUI/issues). When reporting a bug, please include your game version, the TenUI version (shown in the settings footer), and steps to reproduce.

## License

TenUI is released under the [MIT License](https://github.com/Tendoriel/TenUI/blob/main/LICENSE).
