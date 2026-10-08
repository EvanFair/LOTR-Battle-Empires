# Research: code bases, models, and tools

Engine decision: **Godot 4 (GDScript), 3D.** The best open-source RTS base is Godot 4 3D and MIT-licensed, so everything else is chosen to fit it.

## 1. Code bases

All of these were cloned and inspected. Rebuild the local `references/` folder (git-ignored) with:

```bash
mkdir -p references && cd references
git clone --depth 1 https://github.com/lampe-games/godot-open-rts
git clone --depth 1 https://github.com/spicylobstergames/shotcaller-godot
```

| Repo | Engine | License | Verdict |
|---|---|---|---|
| [lampe-games/godot-open-rts](https://github.com/lampe-games/godot-open-rts) | **Godot 4.3, 3D** | **MIT** | **The base.** It already has workers, 2 resources, a command center, factories, a production queue, box-select, swarm movement (NavigationAgent3D with stuck prevention), fog of war, a minimap, and a working AI (economy, offense and defense controllers). Code can be copied in freely if the credit is kept. |
| [spicylobstergames/shotcaller-godot](https://github.com/spicylobstergames/shotcaller-godot) | Godot 4.x, **2D** | PolyForm **NonCommercial** | **Ideas only.** This is the MOBA/RTS hybrid design to study. It has leaders (heroes) with active and passive skills (`prototype/skills/`, e.g. `aura_of_courage.gd`), shops and items, and lane spawns. Since it is 2D, port the ideas rather than the code. It's fine for personal use, but don't ship its code commercially. |
| [jahd2602/godomoba](https://github.com/jahd2602/godomoba) | Godot **3**, 2D | — | Skip. It's a tiny Bomberman-style networking demo and very outdated. |
| [yasgamesdev/OpenMOBA](https://github.com/yasgamesdev/OpenMOBA) | Unreal 4 Blueprints | MIT | Skip, because it's a different engine. Its ability and minion Blueprints are readable as design reference. |
| [SFTtech/openage](https://github.com/SFTtech/openage) | C++/Python | GPL-3 | Skip. It's an Age of Empires engine clone, but too heavy for a weekend. |
| [spring/spring](https://github.com/spring/spring) | C++ | GPL | Skip. It's a big RTS engine, and you can't mix its code with Godot code. |

### How open-rts maps to this game

| open-rts | LOTR Battle Empires |
|---|---|
| `CommandCenter` | Citadel (Minas Tirith / Barad-dûr): the win condition |
| `Worker` | Peasant / Orc slave (gathers gold and wood) |
| `VehicleFactory` | Barracks |
| `Tank` | Gondor Soldier / Orc Warrior |
| `AntiGroundTurret` | Watchtower |
| `Drone` / `Helicopter` / `AircraftFactory` | Disabled in M1; air navigation kept for Eagles and Fell Beasts (M5) |
| *(new)* | **Hero**: a click-to-move commander with QWER abilities that issues orders to troops near it |

## 2. Lord of the Rings models

> ⚠️ LOTR characters are Tolkien Estate / Warner Bros IP. That's fine for a personal game you never sell or publish. Fan models on Sketchfab are usually **CC-BY**, which means you must credit the artist (keep a `CREDITS.md`).

### LOTR-specific (Sketchfab, free, CC Attribution)
- Aragorn, by PhixerArt: https://sketchfab.com/3d-models/lord-of-the-rings-style-character-aragorn-975745bf7fed43888089b1d1249114fd (14k tris, made for a fan game, Mixamo-friendly)
- Orc, by PhixerArt: https://sketchfab.com/3d-models/orc-lord-of-the-rings-style-character-af3ca656575046218a722c67ab0cf33c (same style as the Aragorn model, so they match)
- Uruk-hai: https://sketchfab.com/3d-models/uruk-hai-lotr-c86d316b3f314d11bf3234771b2cc212 (42k tris, so decimate it before using it as a mass unit)
- Witch-king of Angmar: https://sketchfab.com/3d-models/lord-of-the-rings-the-witch-king-of-angmar-063e0e96abea42c3a25b0fa64ba1440a (109k tris, hero/boss only)
- Andúril: https://sketchfab.com/3d-models/anduril-the-lord-of-the-rings-sword-05ffb422e16d483ab739b9a5042f43c2
- Browse more: https://sketchfab.com/tags/lotr (filter: Downloadable, then Animated/Rigged)
- Faramir / Gondor outfits from the Kingdoms of Arda fan mod: https://rigmodels.com/index.php?searchkeyword=lotr (there's a 1.3k-poly version; license unclear)

### Free CC0 fantasy packs (army filler: rigged, animated, glTF, Godot-ready)
- KayKit Adventurers (knight, mage, rogue, barbarian): https://kaylousberg.itch.io/kaykit-adventurers
- KayKit Skeletons (stand-ins for Mordor/undead): https://kaylousberg.itch.io/kaykit-skeletons
- KayKit Character Animations (133 animations, same rig as above): https://kaylousberg.itch.io/kaykit-character-animations
- Quaternius LowPoly Animated Knight: https://opengameart.org/content/lowpoly-animated-knight
- Quaternius LowPoly RPG Characters (wizard, warrior, ranger): https://opengameart.org/content/lowpoly-rpg-characters

**Recommended mix for the weekend:** use KayKit/Quaternius (CC0, already animated, same rig) for every mass unit, and recolour them to Gondor silver/black and Mordor red/black. Use the PhixerArt Aragorn and Orc for the two heroes, rigged through **Mixamo** (free auto-rig and animations: https://www.mixamo.com).

### Avoid this weekend
- Ripping Battle for Middle-earth `.big` files: it needs special tools and the models belong to EA.
- High-poly models (over 50k tris) as mass units.

## 3. Claude Code skills (installed in `.claude/skills/`)

These come from [thedivergentai/gd-agentic-skills](https://github.com/thedivergentai/gd-agentic-skills) (LGPL-3.0). Ten were installed: RTS, MOBA, navigation, camera, combat, abilities, economy, input, GDScript, and project foundations. See `.claude/skills/README.md`.
