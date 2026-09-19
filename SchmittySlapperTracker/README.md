# Schmitty Slapper Tracker

Health and power arcs around your character for WoW: Forever (beta, Interface 16001).
Standalone addon port of the WeakAura "Status Bars - Health/Mana/Rage/Energy"
(https://wago.io/YH_XvKsqX): same Aura3 texture window, colors, positions and fade.

- Left arc: health (green). Right arc: power, colored by type (mana blue, rage red, energy yellow).
- The dim part of an arc is the unfilled portion.
- Arcs show only in combat. Hover an arc to see its value.

Forever's client marks your own health and power as "secret" values that addons may only pass
to native widgets, so the fill is a StatusBar and the text uses SetFormattedText. Because of
that the WeakAura's "also show when not full" mode cannot be reproduced; `/sst combat off`
instead shows the arcs whenever you are alive.

Install: copy this folder to `World of Warcraft\_classic_beta_\Interface\AddOns\SchmittySlapperTracker`.

Commands (`/sst`):

| Command | What it does |
|---|---|
| `/sst test` | Show the arcs for 10 seconds |
| `/sst combat on` or `off` | Only in combat (default) or always while alive |
| `/sst linger 3` | Seconds the arcs stay up after combat ends (0 hides at once) |
| `/sst fade 1` | Seconds the fade-out takes |
| `/sst exact on` or `off` | Exact `cur/max` (default) or percent |
| `/sst text mouseover` or `always` | When the values show |
| `/sst scale 1.25` | Size |
| `/sst x 0`, `/sst y -16` | Offset from screen centre |
| `/sst reset` | Back to defaults |

Textures: `Aura3.tga` (addon icon) is from Power Auras Classic as shipped with WeakAuras;
`ArcLeft.tga` / `ArcRight.tga` are the exact crop windows the WeakAura displayed, baked out
of Aura3 at the aura's crop and offset settings.
