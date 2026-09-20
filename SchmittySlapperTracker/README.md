# Schmitty Slapper Tracker

One addon, two parts, for WoW: Forever (beta, Interface 16001):

- **Arcs**: green health and colored power arcs that frame your character in combat. A port of the WeakAura "Status Bars - Health/Mana/Rage/Energy" (https://wago.io/YH_XvKsqX). The dim part of an arc is what is missing. Hover an arc for its value.
- **Abilities**: a row of icons showing the abilities you just used, TrufiGCD style. New casts push in at one end, older icons slide along and fade. A cancelled cast gets a red X.

Each part can be switched off, moved and sized on its own, and `/sst scale` sizes both together.

Both parts live in Blizzard's **HUD Edit Mode** (Esc > Edit Mode, or `/sst unlock`): drag them, drag the
grip in the bottom-right corner to resize, click one to open its settings (scale, combat rules, icon count,
tooltips, and so on). Positions are saved per Edit Mode layout.

Forever's client marks your own health and power as "secret" values that addons may only pass to
native widgets, so the arcs are StatusBars and the text uses SetFormattedText. Because of that the
WeakAura's "also show when not full" mode cannot be reproduced; `/sst arcs combat off` shows the arcs
whenever you are alive instead.

Install: copy this folder to `World of Warcraft\_classic_beta_\Interface\AddOns\SchmittySlapperTracker`,
log out to the character select screen and enable it.

## Options panel

Type /sst on its own (or open Esc > Options > AddOns > Schmitty Slapper Tracker) for a panel with everything: master size, Edit Mode and preview buttons, then the arcs (on/off, only in combat, also show while healing, stay-after-combat and fade-out sliders, exact values, always show values, size) and the ability row (on/off, tooltips, size, icon size, icons kept, spacing, seconds before fading, direction).

## Commands

`/sst` (or `/slapper`). Arc commands work with or without the word `arcs`; `/ssc` is short for `/sst casts`.

| Both parts | |
|---|---|
| `/sst test` | Show both parts for a moment |
| `/sst unlock` | Open HUD Edit Mode (drag, resize with the corner grip, click for settings) |
| `/sst lock` | Close Edit Mode |
| `/sst scale 1` | Master size for both parts |
| `/sst reset` | Everything back to defaults |

| Arcs | |
|---|---|
| `/sst arcs on` or `off` | Show or hide the arcs completely |
| `/sst arcs scale 1.25` | Size of the arcs (1.25 = the WeakAura size) |
| `/sst arcs combat on` or `off` | Only in combat (default) or always while alive |
| `/sst arcs heal on` or `off` | Also show while being healed out of combat, e.g. food or bandages (default on) |
| `/sst arcs linger 1` | Seconds the arcs stay up after combat ends (0 fades at once) |
| `/sst arcs fade 2` | Seconds the fade-out takes |
| `/sst arcs exact on` or `off` | Hover values as current/max or percent |
| `/sst arcs text mouseover` or `always` | When the values show |
| `/sst arcs x 0`, `/sst arcs y -16` | Offset from screen centre |

| Abilities | |
|---|---|
| `/sst casts on` or `off` | Show or hide the row completely |
| `/sst casts scale 1` | Size of the whole row |
| `/sst casts tooltip on` or `off` | Spell tooltip when hovering an icon (off also stops icons catching the mouse) |
| `/sst casts size 36`, `count 6`, `gap 4` | Icon size, how many, spacing |
| `/sst casts hold 4` | Seconds before an icon fades |
| `/sst casts direction right` or `left` | Which way older icons move |
| `/sst casts x 0`, `/sst casts y -160` | Offset from screen centre |
| `/sst casts ignore <spell id or name>` | Hide a spell; run again to show it. `/sst casts list` prints them |
| `/sst casts test` | Show a few sample icons |

Attack, Auto Shot and Overpower are ignored by default, same as TrufiGCD.

Libraries: [LibEditMode](https://github.com/p3lim-wow/LibEditMode) by p3lim (see `Libs/LibEditMode/LICENSE.txt`) and LibStub.

Textures: `Aura3.tga` (addon icon) is from Power Auras Classic as shipped with WeakAuras;
`ArcLeft.tga` / `ArcRight.tga` are the exact crop windows the WeakAura displayed, baked out of Aura3.
