# Schmitty Slapper

Two standalone addons for World of Warcraft: Forever, released together from this repository.

**Schmitty Slapper Tracker**, in two parts:

- **Arcs**: green health and colored power arcs that frame your character while you fight. A port of the WeakAura [Status Bars - Health/Mana/Rage/Energy](https://wago.io/YH_XvKsqX), rebuilt as an addon because Forever's client hides your health and power numbers from addons.
- **Abilities**: a row of icons showing the abilities you just used, in the style of TrufiGCD, for your own character.

Works for every class. The power arc reads whatever your character uses: rage red, energy yellow, mana blue. Both parts live in Blizzard's HUD Edit Mode: drag them, resize them with the corner grip, click one for its settings. Each can also be switched off on its own.

**Schmitty Slapper Grave**: tracks the Undead racial Touch of the Grave. When it procs, a sound you pick plays and the amount it healed flashes on screen, with session and lifetime totals. Also in Edit Mode. `/ssg` for its commands.

## Install

1. Open the **Releases** page of this repository. Each release has one zip per addon: `SchmittySlapperTracker-vX.Y.Z.zip` and `SchmittySlapperGrave-vX.Y.Z.zip`. They are standalone; take either or both (the Grave one only matters if you play an Undead).
2. Extract the ones you want. Each zip holds the addon folder plus a small shared helper folder, `SchmittySlapperEditMode`, which gives them HUD Edit Mode support (both zips carry the same helper; it is fine to overwrite it).
3. Copy the folders into `World of Warcraft\_classic_beta_\Interface\AddOns\`.
4. Log out to the character select screen, open AddOns, tick the ones you want (the helper needs no ticking), and log back in.

To update, download the newer zip and copy the folders over the old ones. Your settings are kept. If you installed the old separate `SchmittySlapperCasts` folder, delete it: the ability row is part of the Tracker now.

## Settings on Forever

The Forever beta client has a Blizzard bug: it writes addon settings at logout but never reads them
back, so every addon starts from defaults each launch. To get around it, each of these addons keeps
its settings in a macro in your General macros tab (`SSTsave1` for the Tracker, `SSGsave1` for
Grave) and restores them at login. Leave those macros alone. Their body is a slash command, so
clicking one just re-applies the settings. `/sst macro off` or `/ssg macro off` turns this off.

## Using it

Type `/sst` in game for the full command list. `/sst test` shows both parts out of combat. `/sst unlock` opens HUD Edit Mode (also Esc > Edit Mode), where you drag, resize and configure both parts; `/sst lock` closes it.

| Command | What it does |
| --- | --- |
| `/sst scale 1` | Size of both parts together |
| `/sst arcs on` or `off`, `/sst casts on` or `off` | Show or hide either part |
| `/sst arcs scale 1.25`, `/sst casts scale 1` | Size of either part on its own |
| `/sst arcs linger 1`, `/sst arcs fade 2` | How long the arcs stay after combat and how long they take to fade |
| `/sst casts tooltip off` | No spell tooltip when hovering an ability icon |

The addon folder's README lists every command.

## Credits

- Original WeakAura by Shaun: https://wago.io/YH_XvKsqX
- Arc texture `Aura3` from Power Auras Classic as shipped with [WeakAuras](https://github.com/WeakAuras/WeakAuras2)
- Ability row behaviour modelled on [TrufiGCD](https://github.com/Trufi/TrufiGCD)
- Edit Mode integration through [LibEditMode](https://github.com/p3lim-wow/LibEditMode) by p3lim

## License

GPL-2.0. See `LICENSE`.

## Releasing a new version

Maintainer note. One command from this folder, with the GitHub CLI signed in:

```
.\release.ps1 1.0.1
```

It stamps the version into both TOC files, commits, tags `v1.0.1`, pushes, zips both addon folders and publishes the zip on the Releases page. `deploy.ps1` copies both folders into the local beta AddOns directory for testing.
