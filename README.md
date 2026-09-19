# Schmitty Slapper

Two small addons for World of Warcraft: Forever.

- **Schmitty Slapper Tracker**: green health and colored power arcs that frame your character while you fight. A port of the WeakAura [Status Bars - Health/Mana/Rage/Energy](https://wago.io/YH_XvKsqX), rebuilt as an addon because Forever's client hides your health and power numbers from addons.
- **Schmitty Slapper Casts**: a row of icons showing the abilities you just used, in the style of TrufiGCD, for your own character.

Both work for every class. The power arc reads whatever your character uses: rage red, energy yellow, mana blue.

## Install

1. Open the **Releases** page of this repository and download the newest `SchmittySlapper-vX.Y.Z.zip`.
2. Extract it. You get two folders: `SchmittySlapperTracker` and `SchmittySlapperCasts`.
3. Copy both folders into `World of Warcraft\_classic_beta_\Interface\AddOns\`.
4. Log out to the character select screen, open AddOns, tick both, and log back in.

To update, download the newer zip and copy the folders over the old ones. Your settings are kept.

## Using them

Type `/sst` for the Tracker's commands and `/ssc` for the Casts row. Try `/sst test` and `/ssc test` to see both out of combat.

| Tracker | |
| --- | --- |
| `/sst combat on` or `off` | Only in combat (default) or always while alive |
| `/sst linger 3` | Seconds the arcs stay after combat ends |
| `/sst fade 1` | Seconds the fade-out takes |
| `/sst exact on` or `off` | Hover values as current/max or percent |
| `/sst text mouseover` or `always` | When the values show |
| `/sst scale`, `/sst x`, `/sst y` | Size and position |

| Casts | |
| --- | --- |
| `/ssc size`, `count`, `gap`, `hold` | Icon size, how many, spacing, seconds before fading |
| `/ssc direction right` or `left` | Which way older icons move |
| `/ssc ignore <spell>` | Hide a spell by name or id; again to undo |
| `/ssc x`, `/ssc y` | Position |

Each addon folder has its own README with the full list.

## Credits

- Original WeakAura by Shaun: https://wago.io/YH_XvKsqX
- Arc texture `Aura3` from Power Auras Classic as shipped with [WeakAuras](https://github.com/WeakAuras/WeakAuras2)
- Cast row behaviour modelled on [TrufiGCD](https://github.com/Trufi/TrufiGCD)

## License

GPL-2.0. See `LICENSE`.

## Releasing a new version

Maintainer note. One command from this folder, with the GitHub CLI signed in:

```
.\release.ps1 1.0.1
```

It stamps the version into both TOC files, commits, tags `v1.0.1`, pushes, zips both addon folders and publishes the zip on the Releases page. `deploy.ps1` copies both folders into the local beta AddOns directory for testing.
