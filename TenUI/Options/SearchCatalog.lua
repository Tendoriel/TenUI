local _, ns = ...

-- Labels for pages the player has not opened yet. Visible controls supplement this index.
ns.SearchCatalog = {
    { page = "castbar", tab = "", labels = [[
Auto Icon Size (match bar height)
Bar Background Color
Bar Border Color
Bar Colors
Bar Dimensions
Bar Font
Bar Style
Bar Texture
Cast Bar
Cast Information
Channel
Custom Icon Size
Empower
Enable Cast Bar
Failed
Font
Font Outline
Font Size
Height
Hold Time (s)
Icon Gap
Icon Side
Interrupted
Interruptible (Cast)
Non-Interruptible
Show Bar Background
Show Bar Border
Show Instant Casts
Show Spell Icon
Show Spell Name
Show Timer Text
Show channel tick marks
Show elapsed / total cast time
Show measured cast latency (red)
Show spell queue window on casts and channels
Spell Icon
Succeeded
Timing
Width
]] },
    { page = "resources", tab = "", labels = [[
Arcane Soul font size
Bar Background Color
Bar Border Color
Bar Dimensions
Enable Primary Resource Bar
Enable Secondary Resource
Fill the space of an unavailable secondary bar
Hide resources out of combat
Pip Spacing
Primary Bar Color
Primary Bar Texture
Primary Font
Primary Font Anchor
Primary Font Offset X
Primary Font Offset Y
Primary Font Outline
Primary Font Size
Primary Height
Primary Power Type Override
Primary Resource Bar
Primary Resource Thresholds
Primary Width
Recolor at Threshold
Resources
Secondary Background Color
Secondary Bar Texture
Secondary Border Color
Secondary Color
Secondary Height
Secondary Resource
Secondary Text Anchor
Secondary Text Font
Secondary Text Offset X
Secondary Text Offset Y
Secondary Text Outline
Secondary Text Size
Secondary Value Text
Secondary Width
Show Bar Background
Show Bar Border
Show Cost Number on Lines
Show Ebon Might bar
Show Resource Text
Show Secondary Background
Show Secondary Border
Show Secondary Value Text
Show cast prediction (green gain, red spend)
Show mana in Cat and Bear Form
Sunfury: show Arcane Soul countdown in GCDs
Threshold (%)
Threshold Color
Threshold Direction
Threshold Lines (ability cost)
]] },
    { page = "glow", tab = "", labels = [[
Cooldown Glow Defaults
Enable Glow Effects
Glow Effects
Preview
]] },
    { page = "dragonriding", tab = "", labels = [[
Bar Texture
Border Color
Border Size
Charge Background
Charge Fill
Charge Height
Cooldown Text Align
Cooldown Text Offset X
Cooldown Text Offset Y
Cooldown Text Size
Dragon Riding
Element Spacing
Enable Dragon Riding HUD
Hide in Combat
Layout
Second Wind Background
Second Wind Charges
Second Wind Fill
Second Wind Height
Show Cooldown Text
Show Speed Text
Show in Instances (M+/Raid/Dungeon)
Skyward Ascent Charges
Speed Background
Speed Bar
Speed Bar Height
Speed Color
Speed Text Align
Speed Text Offset X
Speed Text Offset Y
Speed Text Size
Stack Spacing
Style
Thrill Color
Thrill Color Change
Thrill Marker (tick)
Whirling Surge
Width
]] },
    { page = "profiles", tab = "", labels = [[
Active Profile
Apply Selected Sections to Active Profile
Content Auto-Switch
Copy From Another Profile
Copy Overrides to Current Specialization
Copy Selected to Current Profile
Export
Export full profile
Generate Export
Import
Profile
Profiles
Rename Active Profile
Reset Selected Specialization Overrides
Saved specialization
Source Profile
Spec Profile Swap
Specialization Overrides
Undo Last Change to This Profile
Use current settings for omitted sections when creating a profile
]] },
    { page = "information", tab = "", labels = [[
Information
Last Scanner Summary
Loaded Modules
Refresh
Slash Commands
]] },
    { page = "ability", tab = "", labels = [[
Combat Only
Cooldown Text Font
Cooldown Text Size
Hide Until Learned
Max Stacks Glow
Max Stacks Glow Color
Max Stacks Glow Enabled
Max Stacks Glow Style
On Cooldown State
Only in Combat
Proc Glow
Proc Glow Color
Proc Glow Enabled
Proc Glow Style
Range Indicator
Ready Glow
Ready Glow Color
Ready Glow Enabled
Ready Glow Style
Replace with active player buff
Resource Gating
Show Cooldown Text
Show your debuff time on the current target
Text Anchor
Text X Offset
Text Y Offset
Tint abilities with insufficient resources
Tint out-of-range abilities
Visibility Conditions
]] },
    { page = "general", tab = "", labels = [[
Apply Global Appearance to All HUD Modules
Default bar texture
Default font
Default outline
Enable TenUI
Enable Tooltip IDs
General
Global Appearance
Global Scale
Only while Shift is held
Show Icon (file) ID
Show Item ID
Show Minimap Button
Show Spell ID
Tooltip IDs
]] },
    { page = "auras", tab = "TrackedBars", labels = [[
Active aura highlight
Color expiring aura timers
Display Settings
Duplicate aura shown in
Hide auras disabled in Blizzard Cooldown Manager
Keep inactive bars visible
Low time (seconds)
Low-time color
Open Blizzard Cooldown Manager
Refresh Aura List
Show Blizzard's Pandemic warning
Show Duration Swipe
Show Icon on Bars
Show stacks
Timer Colors
Timer decimals below (0 = off)
Tracked Auras
Tracked aura tooltips
]] },
    { page = "aura_settings", tab = "", labels = [[
Active Aura
Active aura glow style
Active aura highlight
Active aura highlight color
Aura Proc
Bar Settings
Bar fill color
Color expiring aura timer
Copy appearance from
Expiring Aura Glow
Expiring aura glow color
Expiring aura glow style
Glow Effects
Glow below a time threshold
Glow threshold (seconds)
Glow when aura appears
Independent position
Low Time
Low-time color
Open Blizzard Cooldown Manager
Pandemic
Pandemic color
Pandemic glow style
Pandemic warning
Proc glow color
Proc glow style
Timer color threshold (seconds)
Visibility
]] },
    { page = "layout", tab = "Resources", labels = [[
Alpha
Anchor
Anchor Positioning
Attach to
Attach to edge
Enable Snapping
Font
Font Size
Grid Size (px)
Hide in Housing
Hide when Mounted
Match width of Essential Cooldowns
Only Show in Instances
Outline
Scale
Show Alignment Grid (Edit Mode)
Show Snap Lines
Snap Distance (px)
Snap Gap (px)
Snap System
Snap to Other TenUI Anchors
Snap to Screen Center
State
Text Anchor
Visibility
X Offset
Y Offset
]] },
    { page = "layout", tab = "EssentialCooldowns", labels = [[
Copy visuals from
Icon Border Color
Icon Height
Icon Spacing
Icon Width
Keybind corner
Keybind font
Orientation
Show Icon Border
Show action keybinds
]] },
    { page = "layout", tab = "TrackedBars", labels = [[
Background Color
Bar Fill Color
Bar Height
Bar Spacing
Bar Texture
Bar Width
Border Color
Height
Show Background
Show Border
Width
]] },
    { page = "cdmbars", tab = "Consumables", labels = [[
Custom Consumables (track any item by ID)
Display Options
Hide If Missing
Show Item Count
Show Tooltip On Hover
Tracked Consumables (click an icon to toggle)
]] },
    { page = "cdmbars", tab = "EssentialCooldowns", labels = [[
Candidates (click = add, right-click = settings)
Cooldown Display
Custom Bars (cooldown tracking)
Enable 2nd Row
Flash cooldown icon on action button press
Rename Bar
Selected Bar
Show Duration Swipe
Show GCD Swipe
Show Known Spells Only
]] },
    { page = "qolReminders", tab = "combatAlerts", labels = [[
Center Horizontally
Combat Alerts
Enable Combat Alerts
Enter Color
Enter Combat Text
Fade In (s)
Fade Out (s)
Font
Font Size
Hold Duration (s)
Leave Color
Leave Combat Text
Play Sound on Alert
Reset Position
Test Combat Alert
Unlock to move
]] },
    { page = "qolReminders", tab = "classReminders", labels = [[
Appearance
Arcane Intellect
Battle Shout
Beacon of Light and Beacon of Faith
Blessing of the Bronze
Center Horizontally
Glow when a reminder needs attention
Hide in rested areas
Hide while mounted
Icon Size
Label Font Size
Lethal and non-lethal poisons
Mark of the Wild
Missing or incorrect pet
Moonkin Form
Only show in instances
Pet Reminders
Pet on passive
Position
Power Word: Fortitude
Raid Buffs
Reset Position
Self Buffs and Forms
Shadowform
Shaman shields
Show active buffs, forms and pets with a check mark
Show in raid groups
Skyfury
Targeted Buffs
Track buffs provided by players in your group
Unlock to move
Visibility
]] },
    { page = "qolReminders", tab = "stealth", labels = [[
Appearance
Balance Druid (Prowl in cat form)
Burning Rush
Center Horizontally
Feral Druid (Prowl)
Glow when a reminder needs attention
Guardian Druid (Prowl in cat form)
Hide in rested areas
Hide while mounted
Icon Size
Label Font Size
Only show in instances
Position
Reset Position
Restoration Druid (Prowl in cat form)
Rogue (Stealth)
Show active buffs, forms and pets with a check mark
Show in raid groups
Stealth Indicators
Unlock to move
Visibility
Warlock: show while Burning Rush is active
]] },
    { page = "qolReminders", tab = "talentReminder", labels = [[
Check expected build on Ready Check
Check expected build on dungeon/raid entry
Clear all saved builds
Clear saved build for current zone
Enable Talent Reminder
Print Current Talent Build
Save current build for current zone
Show build name on Ready Check
Show mismatch warning popup
Talent Reminder
]] },
}
