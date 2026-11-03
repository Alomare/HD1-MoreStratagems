# Remixed Stratagems

A mod for HELLDIVERS (2015) with new stratagems built from units and effects already in the game, for [Obsidian Mod Manager](https://github.com/Alomare/ObsidianModManager).

## A/AC-90 Repair Tower

A Tesla Tower that sends REP-80 beams in place of lightning. Each beam heals a Helldiver or repairs a vehicle or turret in range. Downed targets go first (from Mk3), then the most hurt, then the nearest, and a beam drops once the target is back to full health.

- Code: ← ↓ ↓ ↑ ← →, the Tesla Tower code with the last two arrows swapped.
- Icon: the Tesla Tower's, with REP-80 hearts in place of its bolts (with Obsidian API 1.22.0 or later; the REP-80 icon before that).
- Listed right after the Tesla Tower in the Arsenal and the Loadout screen (Obsidian API 1.22.0 or later).
- Unlocks at rank 5, with the defensive stratagems in the Loadout screen.
- Cooldown, uses, call-in and time on the ground come from the Tesla Tower: 180 seconds, 3 uses, 7 seconds and 150 seconds.

| | Mk1 | Mk2 | Mk3 |
| --- | --- | --- | --- |
| Range | 8 m | 12 m | 12 m |
| Targets at once | 1 | 3 | 3 |
| Helldiver healing per second | 10 | 10 | 20 |
| Vehicle and turret repair per second | 50 | 50 | 100 |
| Gets downed Helldivers up and saves burning vehicles | No | No | Yes |
| Upgrade cost | | 2 | 3 |

## Playing with others

Other players see a Tesla Tower land, and the heals reach them with or without the mod. Players who run Remixed Stratagems see the beams as well.

When the player who called the tower leaves, another player in the lobby takes the tower over. If that player runs Remixed Stratagems, the tower keeps healing. If not, it becomes an ordinary Tesla Tower and fires at enemies and players alike.

While the lobby isn't cleared for session mods, the stratagem calls down an ordinary Tesla Tower.

Needs Obsidian API 1.12.0 or later.
