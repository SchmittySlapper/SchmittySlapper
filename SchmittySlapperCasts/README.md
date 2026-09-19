# Schmitty Slapper Casts

A row of icons showing the abilities you just used, TrufiGCD style, for your own character on
WoW: Forever (beta, Interface 16001). Each cast pushes a new icon in at one end; older ones slide
along and fade out after a few seconds. A cancelled cast gets a red X. Hover an icon for its tooltip;
clicks pass straight through.

Install: copy this folder to `World of Warcraft\_classic_beta_\Interface\AddOns\SchmittySlapperCasts`,
then log out to the character select screen and enable it.

Commands (`/ssc`, alias `/casts`):

| Command | What it does |
|---|---|
| `/ssc test` | Show a few sample rogue icons |
| `/ssc size 36` | Icon size |
| `/ssc count 6` | How many icons stay on screen |
| `/ssc gap 4` | Space between icons |
| `/ssc hold 4` | Seconds before an icon fades |
| `/ssc direction right` or `left` | Which way older icons move |
| `/ssc x 0`, `/ssc y -160` | Offset from screen centre (default sits under the Tracker arcs) |
| `/ssc ignore <spell id or name>` | Hide a spell; run again to show it. `/ssc list` prints them |
| `/ssc reset` | Back to defaults |

Attack, Auto Shot and Overpower are ignored by default, same as TrufiGCD.
