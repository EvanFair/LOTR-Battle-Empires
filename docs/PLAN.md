# LOTR Battle Empires: Build Plan

_Produced with the gstack-autoplan pipeline (CEO, then Eng, then Design review). Revision 3, 2026-10-08: villagers assigned per house, Stone added, heroes are the only builders, AoE-style team picker._

## Executive summary

LOTR Battle Empires is a 4-player Lord of the Rings game with **Team (2v2)** and **Free-for-All** modes. Each player controls **only their Hero**, Dota-style. You assign villagers to gather resources, build in person with your Hero, and pay for troops like Age of Empires. The troops fight as **squadrons** that march down lanes, and you command them in person by standing near them.
We fork **lampe-games/godot-open-rts** (MIT, Godot 4.3, 3D), which already has the economy, construction, pathfinding, fog of war, minimap and AI.
Milestone 1 (the weekend) is a playable slice with 4 factions and 3 unit classes. Six more milestones take it to 8 factions, 5 unit classes each, 24 heroes, and LAN multiplayer.

---

## Design decisions (from you)

| Area | Decision |
|---|---|
| **Modes / teams** | Pick teams **like AoE**: each of the 4 lobby slots has a Team 1–4 dropdown. 2v2, 3v1 and FFA (all different teams) are just combinations. "Team" and "FFA" buttons are presets. All use the same map. |
| **Control** | You control **only the Hero**. Right-click moves and attacks (Dota). You build, train and shop **only inside your base**. You order squadrons only when the Hero is **near** them. |
| **Camera** | Locked to the Hero by default. Release it to look around freely. |
| **Economy** | **Villagers (locals)** live in **Village Houses**. Each house holds one group of villagers, and you assign each group to **Food, Wood, Stone or Iron**. The number of groups on a resource sets how fast it's gathered. Killed villagers are replaced only after a **respawn delay**. **Gold** comes from killing jungle creatures, enemy units and heroes. You pay for every building and squadron, AoE-style. |
| **Construction** | **Only heroes build.** The Hero places a building, then must **stay within build range** for the whole build timer (for example, a guard tower takes 2:00). Leaving pauses it. **Two or more heroes in range build 1.5× faster.** |
| **Production** | **Each unit class has its own building.** Every building can train a squadron once (manual) or be set to **Auto-repeat**: choose a lane, and it trains 1 squadron every 60s, paid automatically. If you can't afford it, that cycle is skipped with a warning. |
| **New squadrons** | **March their assigned lane** and fight until the Hero gives them a new order nearby. |
| **Squadrons** | **One unit type each** (for example, 8 Gondor Archers). Orders: Attack this, Defend this, Hold position, Return home (regen). |
| **Counters** | **AoE-style** damage multipliers (table below). |
| **Unit progression** | Units don't level up. Upgrades at buildings make **newly trained** squads stronger or bigger. |
| **Heroes** | QWER abilities, XP and levels, a LoL-style respawn timer, and items from a shop. 3 heroes per faction, 24 in total. |
| **Base** | Town Center with 3 guard towers, plus an outer ring of towers. You can build anywhere inside your base zone. |
| **Map** | Lanes, a jungle with neutral monsters, and fog of war. |
| **Win** | Last team with a Town Center standing wins. |
| **Shop** | Hero items are bought at the **Town Center only**. |
| **Match / scale** | About 30 minutes. 100+ units. Must run on an average laptop. Troops are AoE-style low-poly; heroes are more detailed. |
| **Multiplayer** | LAN/Wi-Fi plus bots (Milestone 3). |
| **Settings** | Unit collision on/off, mode, bot difficulty, starting resources. |

---

## Game modes and map

One square map with 4 corner bases. There are **6 lanes**: the 4 edges and 2 diagonals that cross at a central boss camp. Jungle camps sit in the four quadrants.

```
 Gondor ●━━━━━━━━━ north lane ━━━━━━━━━● Mordor
   ┃  ╲     jungle        jungle    ╱  ┃
 west  ╲          ╲      ╱         ╱  east
 lane   diagonal    ╲  ╱  boss    diagonal lane
   ┃     ╱          ╱  ╲  camp     ╲   ┃
   ┃  ╱     jungle        jungle    ╲  ┃
 Rohan ●━━━━━━━━━ south lane ━━━━━━━━━● Isengard
```

| | **Team preset (2v2)** | **FFA preset** |
|---|---|---|
| Teams | Any pairing from the lobby team dropdowns (Gondor + Rohan vs Mordor + Isengard is the preset) | Everyone on a different team |
| Edge to your neighbour | An **ally route**: safe, so you can reinforce and share vision | A contested lane |
| Lanes to enemies | 2 per base (straight + diagonal) | 3 per base (2 edges + 1 diagonal) |
| Vision | Shared with your ally | Your own only |
| Win | Both enemy Town Centers destroyed | Last player standing |

In code, FFA is simply "each player is their own team", so supporting both modes costs almost nothing once teams exist.

---

## Economy, Ages and buildings

**Resources:** Food, Wood, Stone, Iron and Gold.

| Resource | Gathered from | Mainly spent on |
|---|---|---|
| Food | Hunting (deer and boar near the base), farms | Squadrons, Age advances |
| Wood | Forests | Buildings, archers, siege |
| **Stone** | Quarries | **Towers, walls, Town Center**, Age advances |
| Iron | Mines | Heavy and armoured units, Blacksmith upgrades |
| Gold | **Not gathered.** Earned from kills, jungle camps and heroes | Hero shop, Age III, special units |

### Villagers (locals)
- Each **Village House** holds **one group of 5 villagers**. Building more houses gives more groups (and raises the population cap for squadrons).
- **Clicking a house or its villagers shows 5 bubbles:** 🍖 Food · 🪵 Wood · 🪨 Stone · ⛏️ Iron · 🏠 **Return home**.
  - Picking a resource sends that group to the nearest node of that type. The villagers walk there and back physically, so enemies can raid them.
  - **Return home** pulls the group inside its house: safe from raids, but not gathering (like AoE's town bell).
- **Gathering rate** = the groups assigned × the villagers alive in each group × the base rate. So in your example, with 5 houses you can put 2 groups on Wood and 1 each on Food, Stone and Iron, and Wood comes in twice as fast.
- **When a villager dies,** its house replaces it after a **respawn delay** (default 45s per villager, free). A wiped-out group comes back one villager at a time.
- **Command rule:** you can change assignments when the Hero is **inside the base** or **within command range** (15m) of the group, the same proximity rule as squadrons.
- **Top bar:** shows each resource with its income per minute and how many groups are on it (for example, `🪵 340  +48/min  (2)`).

**Ages are the "criteria" that unlock attack units, as in AoE.** You advance an Age at the Town Center by paying resources:

| Age | Unlocks | Advance cost (draft) |
|---|---|---|
| **I: Settlement** (start) | Town Center, Village Houses, Lumber Camp, Quarry, Mine, Hunting Lodge/Farm, Watchtower, **Barracks** | — |
| **II: Kingdom** | **Archery Range**, **Stables**, Blacksmith (upgrades), stone walls | 400 Food, 200 Wood, 100 Stone |
| **III: Empire** | **Siege Works** (heavy units), the faction's **Special building**, Tier-3 upgrades, bigger squads | 800 Food, 300 Stone, 400 Iron, 200 Gold |

| Building | Trains / does | Class |
|---|---|---|
| Town Center | Comes with 1 Village House. Advances Ages, respawns your Hero, **Hero Shop (the only one)** | Economy |
| **Village House** | Holds 1 villager group (5) and raises the population cap | Economy |
| Lumber Camp / Quarry / Mine / Hunting Lodge | Drop-off points; villagers nearby gather faster | Economy |
| **Barracks** | **Infantry** | Military |
| **Archery Range** | **Archers** | Military |
| **Stables** | **Riders** | Military |
| **Siege Works** | **Heavy** units | Military |
| **Special building** (one per faction) | **Special** unit | Military |
| Blacksmith | +Attack/+Armour upgrades for all newly trained squads | Upgrade |
| Watchtower / Walls | Defence | Defence |

### Construction (heroes only)
- From the base panel, the Hero picks a building and places it inside the base zone. A ghost foundation appears.
- The build timer runs **only while a friendly Hero is within build range (8m)** of the foundation. If the Hero walks away, it pauses (with a progress ring on the foundation) and resumes when a Hero returns.
- **Speed:** 1 hero = 1×; **2 or more heroes in range (you plus allies) = 1.5×**.
- Cost is paid when placing. Cancelling refunds 75%.
- Draft times: Village House 0:30, Watchtower 2:00, Barracks 1:30, Archery Range and Stables 1:45, Siege Works 2:30, Special building 3:00, walls 0:20 per segment, Age advance 1:00 (the Hero stands at the Town Center).
- This makes **building a real tradeoff**: every minute spent building is a minute your Hero isn't fighting, farming or leading squads.
- open-rts already has `ConstructingWhileInRange.gd` and a structure placement handler. Both are reused, with the Hero as the only constructor.

Each military building has a **Train** button, an **Auto-repeat** toggle, a **lane picker**, and an **upgrade** that raises squad size (for example, Infantry 8 → 10 → 12).

### Counter table (attacker damage multiplier)

| Attacker ↓ \ Target → | Infantry | Archers | Riders | Heavy | Buildings |
|---|---|---|---|---|---|
| **Infantry** (spears/swords) | 1.0 | 1.2 | **1.75** | 0.75 | 0.5 |
| **Archers** | **1.5** | 1.0 | 0.6 | 0.5 | 0.25 |
| **Riders** | 1.0 | **1.75** | 1.0 | 0.6 | 0.5 |
| **Heavy** (trolls/siege) | 1.25 | 0.75 | 1.0 | 1.0 | **3.0** |
| **Special** | per unit | per unit | per unit | per unit | per unit |

Heroes take 1.0 from everything, and abilities ignore the table. All values live in one data file so balancing is a data change.

---

## The 8 factions

**Launch factions** (Milestones 1–2) are listed first. Heroes come from your roster; units are the default proposal, so change any of them.

| Faction | Infantry (Barracks) | Archers (Range) | Riders (Stables) | Heavy (Siege Works) | Special (building → unit) | Heroes |
|---|---|---|---|---|---|---|
| 🏰 **Gondor** | Gondor Soldiers | Gondor Archers | Knights of Dol Amroth | Trebuchet | Ranger Hideout → **Rangers of Ithilien** (camouflaged archers) | Boromir, Aragorn, Faramir |
| 🐴 **Rohan** | Rohan Spearmen | Westfold Bowmen | **Rohirrim** (best riders) | Royal Guard (armoured heavy cavalry) | Meduseld → **Horse Archers** (shoot while moving) | Théoden, Éomer, Éowyn |
| 🌋 **Mordor** | Orc Warriors (cheap, many) | Orc Archers | Warg Riders | Mountain Trolls | Black Gate Forge → **Grond** (giant ram that wrecks gates) | Gothmog, Witch-king, Shelob |
| ⚒️ **Isengard** | Uruk-hai Pikemen | Uruk Crossbowmen | Wolf Riders | Battering Ram | Orthanc Furnace → **Uruk Berserker Sappers** (Fire of Orthanc bombs) | Uglúk, Saruman, Lurtz |
| 🧝 **Eldar** | Lórien Swordsmen | **Galadhrim Archers** (longest range) | Rivendell Lancers | Rivendell Guard (high armour) | Mallorn Grove → **Lórien Wardens** (invisible in trees) | Elrond, Galadriel, Legolas |
| ⛏️ **Durin's Folk** | Iron Hills Axemen | Dwarven Crossbowmen | Iron Hills Boar Riders | Dwarven Catapult | Great Forge → **Iron Guard Phalanx** (immovable, reflects arrows) | Dáin, Thorin, Gimli |
| 🐘 **Harad & the East** | Easterling Spearmen | Haradrim Archers | Easterling Cavalry | **Mûmak** (carries archers) | Umbar Docks → **Corsairs of Umbar** (fast raiders) | Mahûd Chieftain, Khamûl, Suladân |
| 🌲 **Guardians of the Wild** | Beorning Woodmen | Woodman Archers | Great Bears | **Ents** (siege) | Eyrie → **Great Eagles** (flying) | Treebeard, Beorn, Gwaihir |

The last two factions need new systems (units that carry others, and flying units), so they come last. open-rts already has **air navigation**, so it is **kept but disabled** in Milestone 1 rather than deleted.

---

## Milestones

| # | Milestone | Content | Est. |
|---|---|---|---|
| **M1** | **Weekend slice** | Hero loop, squadrons and proximity orders, **villager groups with resource bubbles and respawn delay**, Food/Wood/Stone/Iron/Gold, **hero-only construction (1.5× with 2+ heroes)**, **Ages I–II**, **Barracks, Archery Range and Stables** with auto-repeat, counter table, **AoE-style team picker** (Team and FFA presets), 6-lane map, jungle, 6-item shop, bots, **4 launch factions with 1 hero each** (Aragorn, Théoden, Gothmog, Lurtz). Faction units share stat templates and differ by model and colour. | 2–3 days |
| **M2** | Full launch factions | **Age III**, **Siege Works and Special buildings** with heavy and special units for the 4 launch factions, Blacksmith upgrades, squad-size upgrades, Houses and population, walls. **The other 8 launch heroes** (12 total). Faction-specific stats, a bigger shop. | 1–2 weeks |
| **M3** | Multiplayer | LAN/Wi-Fi via Godot ENet, using the Command Bus (see Eng). Host-authoritative. Lobby with mode, faction and bot slots. | 1–2 weeks |
| **M4** | Eldar + Durin's Folk | 2 factions × (5 unit classes + 3 heroes). Mostly data and models. | 1 week |
| **M5** | Harad & the East + Guardians of the Wild | Carrier units (Mûmak) and flying units (Eagles, Gwaihir, Witch-king's Fell Beast). Turns the air domain back on. | 1–2 weeks |
| **M6** | Polish | Audio and music, more maps, bot difficulty levels, balance passes (the installed skills include a Monte Carlo balancer), settings menu. | ongoing |

---

## Phase 1: CEO review

### Premises
| Premise | Status | Risk if wrong |
|---|---|---|
| open-rts can be bent into a hero-centric game | **Validated** by reading its code: there's an `Action` system (`Moving`, `Following`, `AutoAttacking`), formation moves exist, and production queues and construction already work | Low |
| 100+ units run on an average laptop | **Unproven.** open-rts gives every unit its own `NavigationAgent3D` and uses the Forward+ renderer | **High.** Benchmark first; path only squad leaders; use the Mobile renderer |
| Team + FFA on one map | **Validated** in design: FFA is one-player teams | Low |
| Free LOTR hero models exist | **Partly.** Aragorn, Orc, Uruk-hai and Witch-king exist (CC-BY). There is **no Rohan hero** and no faction troops. | Medium. Troops use low-poly CC0 packs anyway |
| Multiplayer can be added later | Only if all inputs go through one command layer from day one | **High** without the Command Bus |

### Alternatives
| Approach | Verdict |
|---|---|
| **A. Fork open-rts and add Hero, Squadrons, Lanes and Ages** | ✅ About 60% of the systems already exist (MIT, 3D, same engine) |
| B. Start from scratch with the gd-agentic-skills scripts | ❌ Rebuilds economy, fog, AI and minimap: 3–4 extra weekends |
| C. Port Shotcaller | ❌ 2D and non-commercial. Use for ideas only |

```
══════════════════════════════
  CEO REVIEW
══════════════════════════════
Premises: NEEDS VALIDATION (performance, multiplayer readiness)
Recommended approach: A, fork godot-open-rts
Scope decision: REDUCED for M1, with the full game laid out as M2–M6
══════════════════════════════
```

---

## Phase 2: Eng review

### Architecture decisions
1. **Command Bus (makes multiplayer possible).** Every intent is a small serialisable `Command`: `HeroMove`, `HeroAttack`, `CastAbility`, `SquadOrder`, `SetAutoRepeat`, `TrainSquad`, `Build`, `AdvanceAge`, `BuyItem`, `AssignVillagers`. Both human input and bots emit commands into one `CommandBus` autoload, and nothing else mutates game state. In M3 the bus forwards commands to the host by RPC.
2. **Everything is data.** `FactionData`, `HeroData`, `AbilityData`, `UnitData` (class, stats, cost, squad size, building, model), `BuildingData` (age, cost, produces), `ItemData`, and one `CounterTable`. Adding a faction means adding data files and models, plus scripts only for its unique abilities.
3. **Teams.** `Player.team` (set from the lobby dropdown) with `Utils.is_enemy(a, b)` everywhere. Allies share fog and can co-build.
4. **Squadron performance.** Only the leader runs a `NavigationAgent3D`; members steer to formation slots. Unit meshes use LOD, and identical idle units can use `MultiMeshInstance3D` later if needed.
5. **Production.** `ProductionBuilding` holds `unit_data`, `auto_repeat`, `lane` and a 60s timer. Each tick it calls `Economy.try_spend(cost)`, then spawns a squadron that runs `MarchLane(lane)`; otherwise it raises the "Can't afford" signal.
6. **Renderer and engine.** Use Godot 4.3, and switch Forward+ to Mobile. Upgrading Godot is a separate task.
7. **Villagers.** `VillageHouse` owns a `VillagerGroup` of 5 units, with `assignment` set to FOOD, WOOD, STONE, IRON or HOME and a respawn queue. Villagers reuse open-rts's `Worker` gather loop (`CollectingResourcesSequentially`). Assignment changes go through the Command Bus (`AssignVillagers`).
8. **Construction.** `Structure` gets `build_progress` and `build_time`. Every tick it counts friendly heroes within 8m: zero means paused, one means 1×, two or more means 1.5×. This reuses `ConstructingWhileInRange.gd`.

### Files

**Create (under `source/`):**
- `CommandBus.gd` and `commands/*.gd`
- `data/` resource scripts: `FactionData`, `HeroData`, `AbilityData`, `UnitData`, `BuildingData`, `ItemData`, `CounterTable`
- `data/factions/{gondor,rohan,mordor,isengard}/`: `.tres` files for faction, units, buildings and heroes
- `match/units/Hero.gd` and `.tscn`, and `match/abilities/Ability.gd` plus 16 M1 ability scripts
- `match/squads/Squadron.gd` (states: MARCH_LANE, ATTACK, DEFEND, HOLD, RETURN, IDLE)
- `match/squads/SquadOrderPanel.gd` and `.tscn`
- `match/production/ProductionBuilding.gd` (auto-repeat, lane, upgrades)
- `match/economy/Economy.gd` (Food/Wood/Stone/Iron/Gold ledger, population, income per minute) and `Ages.gd`
- `match/economy/VillageHouse.gd`, `VillagerGroup.gd` and `ResourceBubbleMenu.tscn` (the 5 bubbles)
- `match/lanes/Lane.gd` (`Path3D` with team endpoints)
- `match/jungle/CreepCamp.gd`, `match/base/BaseZone.gd`, `match/shop/Shop.gd` and `ShopPanel.tscn`
- `match/players/bot/BotPlayer.gd` (hero plus economy brain; it reuses open-rts's `EconomyController` ideas)
- `match/HeroCamera.gd`
- `match/maps/MiddleEarth4.tscn`
- `main-menu/Lobby.tscn` (mode, factions, teams, bots, settings)
- `tests/unit/*.gd` (GUT)

**Modify (from open-rts):** `Player.gd` (team, ledger), `Human.gd` and `UnitActionsController.gd` (hero-only input through the Command Bus), the selection handlers (disabled), `AutoAttacking.gd` and the turrets (`is_enemy`, counter table), `FogOfWar.gd` (ally vision), `MatchEndHandler.gd` (Team/FFA win), `Worker.gd` → `Villager.gd` and `CommandCenter.gd` (villager groups, 5 resources, Stone and Iron nodes), `ConstructingWhileInRange.gd` and `StructurePlacementHandler.gd` (hero builds, multi-hero speed-up), `MatchConstants.gd` (move constants into data), and `project.godot` (renderer, inputs, autoloads).

### M1 steps (in order)
**Friday night**
1. Copy open-rts into the repo (keeping `LICENSE-open-rts`), rename it, and disable the air units. Get it running.
2. Switch to the Mobile renderer. **Benchmark 150 units** on the laptop.
3. Add the Command Bus and route the existing orders through it.

**Saturday**
4. Hero: move, auto-attack, camera follow and free-look, respawn.
5. Squadrons replace unit selection. Proximity orders (Tab plus 1–4). **Playtest that it's fun**, and change it now if it isn't.
6. Economy: 5 resources, Village Houses with villager groups, the bubble menu, respawn delay, Age I → II, and `BaseZone` gating.
6b. Hero-only construction: place, stand in range, timer, pause, 1.5× with 2+ heroes.
7. `ProductionBuilding` with auto-repeat and lanes for the Barracks, Archery Range and Stables. Apply the counter table.
8. Ability framework, then Aragorn's QWER, XP and levels.
9. Import the LOTR hero models (Mixamo, then Godot BoneMap). 3h budget, with KayKit as the fallback.

**Sunday**
10. Teams, `is_enemy`, shared fog, last-team-standing win condition, lobby with team dropdowns.
11. The `MiddleEarth4` map: 4 bases, Town Center with 3 towers plus an outer ring, 6 lanes, jungle and boss camp.
12. Jungle camps, gold, and a 6-item shop.
13. Théoden, Gothmog and Lurtz abilities.
14. Bot players (economy, auto-repeat on lanes, hero farming and pushing, retreating at low HP).
15. Play full matches in both modes and balance.

### Tests
- **Unit (GUT, headless):** gathering rate vs groups assigned, villager respawn delay, Return home stops income, build timer (paused with 0 heroes, 1× with 1, 1.5× with 2), counter multipliers, the economy ledger (no overspending, auto-repeat skips when broke), Age gating, the population cap, `is_enemy` in Team vs FFA, squad state transitions, the respawn curve, XP thresholds, ability cooldown and mana, shop purchases.
- **Smoke:** `godot --headless --quit-after 600` runs a 4-bot match in each mode without script errors. This runs in GitHub Actions CI.
- **Performance:** a 150-unit benchmark scene, at least 45 FPS on the target laptop.

```
══════════════════════════════
  ENG REVIEW
══════════════════════════════
Architecture: SOUND, with 3 concerns
  - No allies in open-rts → is_enemy() + shared fog (step 10)
  - 100+ units on laptops → leader-only pathing, Mobile renderer, benchmark at step 2
  - Multiplayer retrofit → Command Bus from step 3
Plan: M1 = 15 steps, ~30 new files, ~12 modified
Complexity: L (M1); XL overall
Risk: MEDIUM
══════════════════════════════
```

---

## Phase 3: Design review (UX spec)

**Flow:** Main menu, then Lobby (4 slots, each with You/Bot, faction and a **Team 1–4 dropdown**, plus Team/FFA preset buttons and settings), then Hero pick, then Match, then Results (kills, gold, squads trained, buildings lost), then back to the menu.

| Input | Action |
|---|---|
| Right-click ground / enemy | Move the Hero / attack |
| Q W E R (Ctrl+key levels one up) | Abilities |
| Y / Space | Camera lock toggle / snap back to the Hero |
| Tab | Cycle through squadrons within 15m |
| 1 / 2 / 3 / 4 | Squad: Attack (click) / Defend (click) / Hold / Return home |
| Left-click a house or villagers | Resource bubbles: Food / Wood / Stone / Iron / Return home (in base or within 15m) |
| B / P | Build panel / Shop (base only; the shop is at the Town Center) |

**HUD:**
- **Bottom centre:** Hero portrait, HP and mana, XP, QWER cooldowns, 6 item slots.
- **Top:** Food, Wood, Iron, Gold, population, Age, clock.
- **Bottom right:** minimap with lanes and squad pings.
- **Bottom left:** squad order panel (visible only when a squad is in range).
- **Base panel** (while inside the base) has tabs:
  - **Build:** buildings filtered by Age.
  - **Military:** each production building with Train, Auto-repeat, lane picker, upgrade, and "next squad in 0:42".
  - **Age:** advance to the next Age.
  - **Shop:** hero items.

**States:**
- **No squad nearby:** the order panel is hidden, with the tip "Move closer to a squadron to command it".
- **Outside the base:** pressing B or P shows "Return to your base".
- **Building paused:** the foundation shows a grey progress ring and the label "Paused: a Hero must stay nearby". The minimap marks unfinished foundations.
- **Villagers dead:** the house shows `3/5 ⏳ 0:32` until the next villager returns.
- **Hero dead:** the screen turns greyscale with a respawn countdown, and squad orders are locked.
- **Auto-repeat can't afford:** the building icon flashes red, and a toast reads "Archery Range skipped: need 40 Wood".
- **Locked by Age:** the button is greyed out with "Requires Age II".

---

## Open questions (answer when ready; defaults are in **bold**)
1. **Unit rosters:** change any unit you don't like. They're defaults, not decisions.
2. **Villagers per house:** **5** per house, and how many houses can you have at most? Default: **10 houses (50 villagers)**.
3. **Villager respawn delay:** **45s per villager**, free? Or should replacing villagers cost Food?
4. **Can the enemy stop construction?** For example, an enemy Hero within range pauses it. Default: **no, but enemies can attack the foundation**.
5. **Building outside the base:** can heroes build Watchtowers in the field (for example, to hold a lane), or only inside the base? Default: **towers anywhere, everything else base-only**.
6. **Multiplayer before or after M2?** Default: **after** (M3).
7. **Rohan hero model:** look for a paid or commissioned Théoden model, or keep the KayKit stand-in?
