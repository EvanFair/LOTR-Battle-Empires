# LOTR Battle Empires

A Lord of the Rings **MOBA + RTS hybrid** built in **Godot 4.3** (3D).
You control only your Hero, Dota-style. Your villagers run the economy, your barracks feed squadrons into the lanes, and you command those squadrons by leading them in person.
Up to 4 players over LAN or against bots. Teams like Age of Empires: 2v2, 3v1 or free-for-all.

- **Plan:** [docs/PLAN.md](docs/PLAN.md): scope, architecture, milestones
- **Research:** [docs/RESEARCH.md](docs/RESEARCH.md): reference code, free LOTR models, tools
- **Claude Code skills:** [.claude/skills/](.claude/skills/README.md): Godot RTS, MOBA, navigation, combat and more

## Download (Windows)

1. Go to **[Releases](https://github.com/EvanFair/LOTR-Battle-Empires/releases/latest)** and download `LOTR-Battle-Empires-windows.zip`.
2. Unzip it anywhere (for example, your Desktop) and double-click **`LOTR Battle Empires.exe`**. Nothing to install.
3. Windows SmartScreen may say "Windows protected your PC", because the game isn't code-signed. Click **More info → Run anyway**.
4. The first time you host a LAN game, Windows Firewall asks for network access. Allow it on **Private networks**, or friends won't be able to join.

Every push to `main` builds a fresh `.exe` and publishes it as a new Release automatically (`.github/workflows/build.yml`).

## Play it from the source code

1. Install **Godot 4.3** (exactly 4.3): <https://godotengine.org/download/archive/4.3-stable/>
2. Open `project.godot` in Godot and press **F5**. The first open takes a minute to import files.
3. **Play** → choose:
   - **Single player:** you plus 3 bots.
   - **Host a LAN game:** friends on the same Wi-Fi pick **Join a LAN game** and see your game listed automatically (or type your IP). Empty slots can be bots.
4. In the lobby, pick your faction, hero and team. Then press **Start match**.

### Controls

| Input | Action |
|---|---|
| Right-click ground / enemy | Move your hero / attack |
| **Q W E R** | Hero abilities (aimed at the cursor or the enemy under it) |
| **S** | Stop |
| **Tab** | Cycle through squadrons within 15m of your hero |
| **1 / 2 / 3 / 4** | Selected squadron: **Attack** (then click an enemy) / **Defend** (then click a spot) / **Hold** / **Return home** (to heal) |
| **B** | Base panel (only inside your base): Build, Military, Age |
| Left-click your house or villager | Villager bubbles: Food / Wood / Stone / Iron / Return home |
| Left-click your building | Info (and cancel construction for a 75% refund) |
| **Y** / **Space** | Camera lock on/off / snap back to your hero |
| Arrow keys, mouse at screen edge | Pan the camera (when unlocked) |
| Mouse wheel / **Z**, **C** | Zoom / rotate the camera |
| **Esc** | Cancel placement or targeting; otherwise opens the menu |

### How a match works

- **Economy:** each Village House holds 5 villagers. Assign each house to Food, Wood, Stone or Iron; more houses on a resource means it comes in faster. A killed villager is replaced after 45s for 50 Food. **Gold** comes from kills.
- **Building:** only heroes build. Place a building from the base panel, then **stand next to it** while the timer runs. If you leave, it pauses. An enemy hero nearby also pauses it. Two heroes build 1.5× faster. Watchtowers can go anywhere; everything else goes inside your base.
- **Ages:** advance to the Kingdom Age at the Town Center (your hero must stay there) to unlock the Archery Range, Stables and Storehouse.
- **Armies:** Barracks (infantry), Archery Range (archers) and Stables (riders) train squadrons. Villagers must **carry supplies** to the building first. Turn on **Auto-repeat** and pick a lane, and you get a squadron every 60s that marches that lane.
- **Storehouse:** one extra drop-off point that shortens villager trips. **If it's destroyed you lose half your stockpile**, and you must wait 2 minutes before rebuilding it.
- **Counters:** infantry beats riders, riders beat archers, archers beat infantry, and heavy units wreck buildings.
- **Win:** destroy every enemy Town Center.

The heroes playable now are Aragorn (all four abilities), and Théoden, Gothmog and Lurtz (one signature ability each). Units use simple stand-in shapes until the LOTR models are imported (see the research doc).

## Tests

Every test runs headless. Use Godot 4.3:

```bash
# 4 bots play 6 game-minutes; checks the economy, building, armies and combat
godot --headless --fixed-fps 60 --path . res://tests/auto/BotMatchTest.tscn -- --minutes=6
godot --headless --fixed-fps 60 --path . res://tests/auto/BotMatchTest.tscn -- --minutes=6 --preset=ffa

# a scripted player checks 23 game rules (construction, hauling, Storehouse, abilities...)
godot --headless --fixed-fps 60 --path . res://tests/auto/RulesTest.tscn

# LAN: host and client on one machine
godot --headless --path . res://tests/auto/LanTest.tscn -- --role=host &
godot --headless --path . res://tests/auto/LanTest.tscn -- --role=client
```

GitHub Actions runs the bot and rules tests on every push (`.github/workflows/tests.yml`).

## Code map

| Path | What |
|---|---|
| `source/lotr/GameData.gd` | **All balance and content**: factions, units, heroes, buildings, costs, counters, timings |
| `source/lotr/LotrMatch.gd` | Match setup, command handlers (rules), win condition |
| `source/lotr/CommandBus.gd` | Every player action is a command; clients send theirs to the host |
| `source/lotr/net/` | LAN host/join/discovery/lobby (`Network.gd`) and state sync (`Replicator.gd`) |
| `source/lotr/units/` | Hero, Troop, Villager, Building, ResourceNode, and `UnitFactory` (builds them) |
| `source/lotr/Squadron.gd` | Squadron behaviour: march, attack, defend, hold, return |
| `source/lotr/HeroAbilities.gd` | Ability effects |
| `source/lotr/BotBrain.gd` | Computer players |
| `source/lotr/hud/LotrHud.gd`, `HeroController.gd` | Interface and input |
| `source/lotr/map/MapGen.gd` | The 4-base, 6-lane map |
| `source/match/…` | Reused from open-rts: navigation, fog of war, minimap, camera, unit traits |

Built on [lampe-games/godot-open-rts](https://github.com/lampe-games/godot-open-rts) (MIT, see `LICENSE-open-rts`).
Personal fan project, not affiliated with the Tolkien Estate or Warner Bros.
