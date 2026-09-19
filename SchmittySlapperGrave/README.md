# Schmitty Slapper Grave

Tracks the Undead racial passive **Touch of the Grave** on WoW: Forever. When it procs:

- a sound of your choice plays,
- the amount it healed flashes on screen, with session totals underneath,
- session and lifetime totals are kept (`/ssg stats`).

The text lives in HUD Edit Mode (Esc > Edit Mode, or `/ssg unlock`): drag it, resize it with the
corner grip, and click it for the settings dialog (sound, channel, on-screen text, seconds shown,
scale, detection mode) with Test sound and Reset totals buttons.

Install: copy this folder to `World of Warcraft\_classic_beta_\Interface\AddOns\SchmittySlapperGrave`,
log out to the character select screen and enable it.

## Options panel

Type /ssg (or open Esc > Options > AddOns > Schmitty Slapper Grave) for a panel with the sound dropdown and a Play button, sound channel, which lines the text shows (spell name, amount, session totals, lifetime totals, and what the totals include), seconds shown, text size, detection mode, plus buttons to fake a proc, reset totals and jump into Edit Mode.

## Sounds

`/ssg sound list` shows the choices. Built in: lightsaber (the default, the same clip the
"Extra Attack!" WeakAura uses), raid warning, ready check, level up, alarm clock,
boss whisper, PvP queue pop, whisper, auction house open, map ping, menu open, or none. If you have a
SharedMedia addon, its sounds are listed too.

Your own sound: drop an `.ogg` or `.mp3` into this folder's `Sounds` directory, restart the game
(new files are only found at launch), then `/ssg sound file MySound.ogg`.

The lightsaber clip is `sound_jedi1.ogg` from the Details! damage meter and is not included in the
download. If you have Details! installed the addon plays it from there on its own. If not, copy
`Interface\AddOns\Details\sounds\sound_jedi1.ogg` from any WoW install into this folder's `Sounds`
directory and restart the game. Until then, pick another sound with `/ssg sound list`.

## Commands

`/ssg` (or `/grave`)

| Command | What it does |
|---|---|
| `/ssg on` or `off` | Turn the tracker on or off |
| `/ssg sound <name>` | Pick a sound; `/ssg sound test` plays it; `/ssg sound file Name.ogg` uses your own |
| `/ssg channel Master` or `SFX` | Which volume slider the sound follows |
| `/ssg text on` or `off` | Show the healed amount on screen |
| `/ssg show label|amount|session|lifetime|procs|healed|best on` or `off` | What the text shows: the spell name, the amount, a session totals line, a lifetime totals line, and whether totals include the proc count, healed and best |
| `/ssg hold 3` | Seconds the text stays |
| `/ssg scale 1` | Size of the text |
| `/ssg unlock` then `/ssg lock` | Open and close HUD Edit Mode to move and resize it |
| `/ssg detect auto` | How the proc is spotted. Auto (default) uses the cast event, the heal event and the combat log line together; chat, spell or heal pick one |
| `/ssg spell <id>` | Add or remove a spell id to watch; `/ssg spell list` |
| `/ssg stats`, `/ssg resetstats` | Totals |
| `/ssg test` | Fake a proc |
| `/ssg debug on` | Print the raw cast and combat events in chat, for troubleshooting |

## How it works on Forever

The 12.x engine closed the combat log API to addons, marks combat-text numbers as secret, and hands
the chat combat log lines over as protected strings that cannot be read. The proc also does not fire
a cast event on Forever. What does work: the game's UNIT_COMBAT event for the player reports a heal
the moment it lands, and the same event for your target reports a Shadow hit at the same instant.
A rogue deals no other Shadow damage, so "heal on me right after a Shadow hit on my target" is
Touch of the Grave. Bandages, potions and healthstones are filtered out. If the client hides the
school of the hit, any heal in combat that is not one of those counts instead.

The amount comes from the heal event. If the game reports it as a plain number, totals are kept; if
it is secret, the amount still shows but totals fall back to a proc count.
