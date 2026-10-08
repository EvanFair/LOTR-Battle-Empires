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

The full reasoning, and how other open-source MOBAs do it, is in [docs/CONTROLS.md](docs/CONTROLS.md).

| Input | Action |
|---|---|
| Right-click ground / enemy | Move your hero / attack (green / red marker) |
| **A**, then left-click | Attack-move: walk there, fighting anything on the way |
| **S** / **H** | Stop / hold position |
| **Q W E R** | Abilities. **Hold** to see the range and aim, **release** to cast. Right-click while holding cancels. A unit-target ability walks into range first. |
| **Ctrl + Q/W/E/R** | Learn or level up an ability (one skill point per hero level; ultimate R at levels 6/8/10) |
| **B** | In your base: base panel (Build, Military, Age, Blacksmith). Outside: **Recall** home (6s; moving, casting or taking damage cancels it) |
| **Tab** | Cycle through squadrons within 15m of your hero (a gold ring shows the 15m range) |
| **1 / 2 / 3 / 4** | Selected squadron: **Attack** (then click an enemy) / **Defend** (then click a spot) / **Hold** / **Return home** (to heal) |
| **Alt + left-click** | Ping for your team (**Alt+Shift**: danger ping) |
| Left-click your house or villager | Villager bubbles: Food / Wood / Stone / Iron / Return home |
| Left-click your building | Info (and cancel construction for a 75% refund) |
| **Y** / **Space** | Camera lock on/off / snap back to your hero |
| Arrow keys, mouse at screen edge | Pan the camera (when unlocked) |
| Minimap: left-click / right-click | Look there (frees the camera) / move your hero there |
| Mouse wheel / **Z**, **C** | Zoom / rotate the camera |
| **Esc** | Cancel aiming, placement or targeting; otherwise opens the menu |

### How a match works

- **Economy:** each Village House holds 5 villagers. Assign each house to Food, Wood, Stone or Iron; more houses on a resource means it comes in faster. Herds of game regrow; forests, quarries and mines run out. A killed villager is replaced after 45s for 50 Food. **Gold** comes from kills and from clearing jungle camps.
- **Building:** only heroes build. Place a building from the base panel, then **stand next to it** while the timer runs. If you leave, it pauses. An enemy hero nearby also pauses it. Two heroes build 1.5× faster. Watchtowers can go anywhere; everything else goes inside your base.
- **Ages:** advance at the Town Center (your hero must stay there).
  - **Kingdom Age** unlocks the Archery Range, Stables, Storehouse and Blacksmith.
  - **Empire Age** unlocks the Siege Works, your faction's special building (Ranger Hideout, Meduseld, Black Gate Forge, Orthanc Furnace) and the top Blacksmith research.
- **Armies:**
  - Barracks (infantry), Archery Range (archers), Stables (riders), Siege Works (heavy) and the special building train squadrons.
  - Villagers must **carry supplies** to the building first. Turn on **Auto-repeat** and pick a lane, and you get a squadron every 60s that marches that lane.
  - Every faction's heavy and special troops are different:
    - Gondor: Trebuchets and Rangers.
    - Rohan: the Royal Guard and Horse Archers.
    - Mordor: Mountain Trolls and Grond.
    - Isengard: Battering Rams and Berserker Sappers, who blow up.
  - Siege engines go for buildings first.
- **Blacksmith:** research Forged Blades, Plated Armour, War Drills (+2 soldiers per squadron) and Master Smiths. Upgrades apply to squadrons trained afterwards.
- **Storehouse:** one extra drop-off point that shortens villager trips. **If it's destroyed you lose half your stockpile**, and you must wait 2 minutes before rebuilding it.
- **Counters:** infantry beats riders, riders beat archers, archers beat infantry, and heavy units wreck buildings.
- **Heroes:** 12 heroes, 3 per faction, each with four abilities:
  - Gondor: Aragorn, Boromir, Faramir.
  - Rohan: Théoden, Éomer, Éowyn.
  - Mordor: Gothmog, the Witch-king, Shelob.
  - Isengard: Uglúk, Saruman, Lurtz.
  - You get a skill point per level. Spend it with **Ctrl+Q/W/E/R**; each ability has 3 ranks. Abilities stun, root, slow and weaken.
- **The Wild:**
  - Spider and warg camps sit between the lanes. They ignore you until struck, then the whole camp fights back. Pull them too far and they go home and heal.
  - Clearing a camp pays Gold and XP.
  - The **Cave Troll** lairs in the middle of the map, where the diagonal lanes cross. Slay it for Gold for your whole team and +20% damage for 2 minutes.
- **Shop:** the Shop tab of the base panel sells Lembas, Athelas, the Steed of Rohan, Elven Blade, Dwarven Mail, Mithril Coat, the Phial of Galadriel and more.
  - 4 item slots (keys **5–8** to use).
  - Selling refunds half.
- **Win:** destroy every enemy Town Center.

## Tests

Every test runs headless. Use Godot 4.3:

```bash
# 4 bots play 6 game-minutes; checks the economy, building, armies and combat
godot --headless --fixed-fps 60 --path . res://tests/auto/BotMatchTest.tscn -- --minutes=6
godot --headless --fixed-fps 60 --path . res://tests/auto/BotMatchTest.tscn -- --minutes=6 --preset=ffa

# a scripted player checks the game rules (construction, hauling, Storehouse, abilities, Ages,
# Blacksmith, siege, recall, shop, jungle camps...)
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

## Credits

- 3D art: [KayKit](https://kaylousberg.com) Adventurers, Skeletons and Medieval Hexagon packs by Kay Lousberg (CC0).
- Sound effects and music (`assets/omoba/audio/`, CC0), all from [Open MOBA](https://github.com/o-moba/omoba-bevy) (`LICENSE.md` there has the provenance):
  - "Exploration Theme" by Cleyton Kauffman.
  - RPG Audio by Kenney.
  - Synthesized effects by the Open MOBA contributors.
- Horn, war drums, sword clash, boulder, blast and building sounds (`assets/lotr/audio/`): synthesized for this game by `tools/synth_sfx.py` (CC0).
- Skill icon atlases (`assets/omoba/skills/`): **Open Moba contributors**, <https://github.com/o-moba/omoba-bevy>, licensed [CC-BY-4.0](assets/omoba/CC-BY-4.0.txt). They are unmodified.
- Item and HUD icons (`assets/omoba/icons/`): game-icons.net artists (Delapouite, Lorc and others), [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). Per-icon credits are in `assets/omoba/icons/LICENSES.md`.
- Control and MOBA-mechanic research drew on the designs of [Open MOBA](https://github.com/o-moba/omoba-bevy), [MOBA_CSharp_Unity](https://github.com/yasgamesdev/MOBA_CSharp_Unity), [OpenMOBA](https://github.com/yasgamesdev/OpenMOBA) and [amoba](https://github.com/AmbientRun/amoba). No code was copied from them; see [docs/CONTROLS.md](docs/CONTROLS.md).

Built on [lampe-games/godot-open-rts](https://github.com/lampe-games/godot-open-rts) (MIT, see `LICENSE-open-rts`).
Personal fan project, not affiliated with the Tolkien Estate or Warner Bros.
