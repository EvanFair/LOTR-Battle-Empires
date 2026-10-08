# LOTR Battle Empires: Build Plan

_Produced with the gstack-autoplan pipeline (CEO, then Eng, then Design review), 2026-10-08._

## Executive summary

LOTR Battle Empires is a 4-faction, 2v2 game played on a single map. Each player controls **only their Hero**, Dota-style. The army is **squadrons** that you command by standing near them, while the economy runs itself and you build only inside your own base.
We fork **lampe-games/godot-open-rts** (MIT, Godot 4.3, 3D). It already has the economy, construction, pathfinding, fog of war, minimap and AI. On top of it we add the Hero, squadrons, lanes, a jungle and a shop.
**This weekend's target is a vertical slice:** 4 factions, 1 hero each, one map, bots, single-player. Multiplayer and the full 24-hero roster come after.

---

## Your design decisions (from the questionnaire)

| # | Decision |
|---|---|
| Control | You control **only the Hero**. Right-click moves and attacks (Dota). You can build and shop **only inside your base**. You can order troops only when the Hero is **near** them. |
| Camera | Locked to the Hero by default (MOBA). Release it to look around freely. |
| Economy | Workers **auto-spawn and auto-gather** wood, stone (mine) and meat (hunting). **Gold** comes from killing jungle creatures and enemies. |
| Army | **Squadrons**, not individual units. Orders: Attack this, Defend this, Hold position, Return home (regen). Squad size grows over time and with upgrades. |
| Waves | Attack units unlock after a criterion is met. Once you **activate a lane**, that lane's barracks spawn a squadron **every 60s**. |
| Base | Town Center plus 3 guard towers, with an outer ring of towers. You can build anywhere inside your base. |
| Heroes | QWER abilities, levels and XP, and a LoL-style respawn timer. 8 factions × 3 heroes are designed (24 total). |
| Units | Units don't level up. Barracks upgrades unlock better troops. |
| Shop | Yes, simpler than LoL's. |
| Map | Open map with lanes. 4+ teams. Each base has 1 route to its ally and 2 lanes to the two enemies. Neutral jungle monsters. Fog of war. |
| Match | About 30 minutes. 100+ units on screen. Win by destroying the enemy teams. |
| Multiplayer | LAN/Wi-Fi plus bots (later). |
| Graphics | Must run on any laptop: low-poly, Age of Empires-style troops and buildings, with more detail on heroes. |
| Collision | Unit collision is a toggle in settings. |
| Models | Real LOTR models from day one (for heroes; troops use low-poly packs, per the graphics decision). |

---

## Phase 1: CEO review (strategy and scope)

### Premises

| Premise | Status | Risk if wrong |
|---|---|---|
| open-rts can be bent into a hero-centric game | **Validated.** I read its code: orders go through an `Action` system (`Moving`, `Following`, `AutoAttacking`), and `Utils.Match.Unit.Movement.crowd_moved_to_new_pivot` already does formation moves. A Hero is a new `Unit` subclass. | Low |
| 100+ units run on a weak laptop | **Needs validation.** open-rts gives every unit its own `NavigationAgent3D` and uses the Forward+ renderer. | High: we may need to switch renderer and path only squad leaders |
| Free LOTR hero models are usable | **Partly validated.** Free CC-BY models exist for Aragorn, Orc, Uruk-hai and Witch-king. **None was found for Théoden or any Rohan hero.** Sketchfab models usually come unrigged, so they need Mixamo. | Medium: rigging costs 1–2 hours per hero |
| 4 teams fit open-rts | **Needs work.** open-rts treats every other player as an enemy. It has **no concept of allies**. | Medium: touches targeting, fog of war and win checks |
| Multiplayer can be added later | **Needs care.** open-rts is single-player only. Retrofitting networking is the most expensive change in this whole plan. | High, unless every input goes through one command layer from day one (see Eng) |

### Problem framing
- The real goal this weekend is to **feel the hybrid loop**: walk your Hero to a squadron, order it into a lane, fight beside it, recall, build, and push. Everything that doesn't serve that loop waits.
- **Riskiest assumption:** proximity command is fun and not annoying. Prove it on Saturday before building content.
- **The simpler 80% version:** 1 hero per faction, 3 squad types, 1 map, bots, no multiplayer.

### Alternatives considered

| Approach | Tradeoffs | Verdict |
|---|---|---|
| **A. Fork open-rts and add Hero, Squadrons and Lanes** | Economy, construction, fog, minimap, AI and nav already work. We have to retrofit allies and hero-only input. | ✅ **Chosen** |
| B. Start from an empty Godot project and copy in the gd-agentic-skills scripts | Clean architecture, but everything (economy, fog, AI, minimap) gets rebuilt. That's 3–4 weekends. | ❌ |
| C. Port Shotcaller (a real MOBA/RTS hybrid) | Its design is closest, but it's **2D** and **non-commercial** licensed. | ❌ Use for ideas only |

### Scope decisions

| Item | Weekend | Why |
|---|---|---|
| Hero: click-to-move, auto-attack, QWER, XP/levels, respawn | **IN** | Core |
| MOBA camera with free-look toggle | **IN** | Core, and small |
| Squadrons plus 4 proximity orders | **IN** | Core: it's the riskiest mechanic |
| Auto-spawning, auto-gathering workers (wood, stone, meat) | **IN** | Mostly exists in open-rts |
| Lane activation and barracks waves every 60s | **IN** | Core MOBA pressure |
| Building and shopping only inside your base | **IN** | Small: an `Area3D` gate |
| 2v2 map with 4 bases, ally route and lanes | **IN** | Needed for 4 teams |
| Allies (team field) | **IN** | Required for 2v2 |
| 4 heroes (one per faction) | **IN** | Vertical slice |
| Jungle camps with gold | **IN** (1 camp type) | Cheap, and gold drives the shop |
| Shop with about 6 items | **IN** | User calls it "a lot of fun" |
| Bot heroes (simple) | **IN** | You need someone to fight |
| Town Center with 3 towers plus an outer ring | **IN** | Placed in the map, not built |
| Collision on/off setting | **IN** | Very small |
| Barracks upgrade tiers | DEFER | After the core loop |
| The other 20 heroes | DEFER | Data-driven, so each is cheap once the system exists |
| LAN/Wi-Fi multiplayer | DEFER | Large. The architecture is designed for it now (Command Bus) |
| Flying heroes (Witch-king, Gwaihir), map-wide ults, mind control | DEFER | Need special systems |
| More than 4 teams / free-for-all | DEFER | |
| Voice and music | DEFER | |

```
══════════════════════════════
  CEO REVIEW
══════════════════════════════
Premises: NEEDS VALIDATION (2 of 5)
  - Low-spec performance at 100+ units: unproven. Benchmark on Saturday morning.
  - Multiplayer later: only safe if the Command Bus exists from day one.

Recommended approach: A, fork godot-open-rts
  Why: about 60% of the systems already exist under MIT, in 3D, on the same engine.

Deferred to TODOS: barracks tiers, 20 more heroes, multiplayer,
  flying/global abilities, FFA/6+ teams, audio.

Scope decision: REDUCED (weekend = vertical slice)
══════════════════════════════
```

---

## Phase 2: Eng review (architecture)

### Key architecture decisions

1. **Command Bus (the multiplayer insurance).** Every player intent is a small serialisable `Command` (`HeroMove`, `HeroAttack`, `CastAbility`, `SquadOrder`, `ActivateLane`, `Build`, `BuyItem`) sent through one `CommandBus` autoload. Human input and bot AI **both** emit commands, and nothing else changes game state directly. For LAN later, the bus forwards commands to the host by RPC, and the rest of the game is untouched.
2. **Data-driven heroes.** `HeroData.tres` holds the stats, model and 4 `AbilityData` entries. Each ability is a small script extending `Ability.gd` (`can_cast()`, `cast(target)`). Adding hero #5 to #24 is then a data file plus 4 small scripts.
3. **Teams.** Add `team: int` to `Player`. Replace every "is enemy" check in open-rts with `Utils.is_enemy(a, b)`, which compares teams. Allies share vision in `FogOfWar`.
4. **Squadrons for performance.** Only the squad **leader** runs a `NavigationAgent3D`. Members steer to formation slots around the leader. This cuts pathfinding cost about 8x, which is what makes 100+ units possible on laptops.
5. **Renderer.** Switch from Forward+ to **Mobile** (or Compatibility if needed) for weak laptops. Verify that the fog-of-war shader still works.
6. **Engine version.** Stay on **Godot 4.3**, which open-rts targets, for the weekend. Upgrade later as its own task.

### Data model (Resources, no database)
- `HeroData`: name, faction, class, base stats, stat gain per level, model scene, `abilities[4]`, respawn curve
- `AbilityData`: key (Q/W/E/R), cooldown, mana cost, range, targeting (self/unit/point/area), script
- `SquadData`: unit scene, size (grows over time), stats, cost
- `ItemData`: cost, stat modifiers
- `FactionData`: colour, heroes, squad types, building skins
- Lane: a `Path3D` per lane on the map, tagged with `from_team` and `to_team`

### Implementation plan

#### Files to create (all under `source/`)
- `CommandBus.gd` (autoload): the command queue and dispatch. This is where networking hooks in later.
- `commands/*.gd`: `HeroMove`, `HeroAttack`, `CastAbility`, `SquadOrder`, `ActivateLane`, `Build`, `BuyItem`
- `match/units/Hero.gd` and `Hero.tscn`: the `Unit` subclass with XP, level, mana, inventory and respawn
- `match/abilities/Ability.gd`, plus `aragorn/*.gd`, `theoden/*.gd`, `gothmog/*.gd`, `lurtz/*.gd` (16 abilities)
- `match/squads/Squadron.gd`: leader, formation, state machine (IDLE, ATTACK, DEFEND, HOLD, RETURN)
- `match/squads/SquadOrderPanel.gd` and `.tscn`: the contextual HUD for squads in range
- `match/lanes/LaneManager.gd`: lane activation and 60s wave timer per barracks
- `match/jungle/CreepCamp.gd`: respawning neutral camp that drops gold and XP
- `match/base/BaseZone.gd`: `Area3D` that enables the build and shop panels only while the Hero is inside
- `match/shop/Shop.gd` and `ShopPanel.tscn`
- `match/players/bot/BotHero.gd`: a simple bot that farms, pushes its lane, retreats at low HP, orders nearby squads and buys items
- `match/HeroCamera.gd`: extends `IsometricCamera3D` with follow and free-look modes
- `match/maps/MiddleEarth2v2.tscn`: 4 corner bases, ally routes, lanes and jungle
- `data/heroes/*.tres`, `data/items/*.tres`, `data/factions/*.tres`
- `tests/`: GUT unit tests (see below)

#### Files to modify (from open-rts)
- `match/players/Player.gd`: add `team`, `gold`, `wood`, `stone`, `meat`
- `match/players/human/Human.gd`, `UnitActionsController.gd`: remove box-select and per-unit orders; right-click goes to `CommandBus` as a hero command
- `match/handlers/*SelectionHandler.gd`: disable them, since there's no unit selection in hero-only mode
- `match/units/actions/AutoAttacking.gd` and turret targeting: use `Utils.is_enemy()`
- `match/FogOfWar.gd`: shared vision between allies
- `match/handlers/MatchEndHandler.gd`: a team loses when all its Town Centers are gone
- `match/units/Worker.gd` and `CommandCenter.gd`: auto-spawn workers up to a cap and auto-assign them to the nearest resource type with the lowest stock
- `MatchConstants.gd`: 3 resources plus gold; rename units (Tank → Soldier and so on)
- `project.godot`: renderer, input map (QWER, camera toggle, squad hotkeys), autoloads
- Remove air units: `Drone`, `Helicopter`, `AircraftFactory`, `AntiAirTurret`, `AirNavigation`

#### Steps (in order)
**Friday night: foundation (2–3h)**
1. Copy open-rts into the repo root and keep its MIT `LICENSE` as `LICENSE-open-rts`. Rename the project. Delete the air units. Get it running. _We need a known-good base before changing anything._
2. Switch the renderer. **Benchmark** 150 Tanks on `BigArena` on the laptop. _This validates the riskiest premise first._
3. Add `CommandBus` and route the existing right-click orders through it. _Every later system depends on it._

**Saturday: the hybrid loop (8–10h)**
4. Hero: click-to-move, auto-attack, HP/mana, camera follow and free-look, death and respawn timer.
5. Remove unit selection. Add `Squadron` (leader plus formation) and change the barracks to spawn squadrons.
6. Proximity orders: squads within 15m light up, and you choose one with Tab and give it Attack, Defend, Hold or Return. **Playtest here.** If it isn't fun, change the controls before going further.
7. Auto-workers and 3 resources. `BaseZone` gates the build menu.
8. Ability framework, then Aragorn's QWER. XP and levels.
9. Import the LOTR heroes (Aragorn, Orc as Gothmog, Uruk-hai as Lurtz) through Mixamo and Godot `BoneMap` retargeting. _Budget 3h. If it overruns, fall back to KayKit for now._

**Sunday: the game (8–10h)**
10. Teams, `is_enemy`, shared fog, team win condition.
11. 2v2 map: 4 corner bases, Town Center with 3 towers plus an outer ring, ally route, lanes and jungle.
12. `LaneManager`: activate a lane, then barracks waves every 60s. Squad size grows every 5 minutes.
13. Jungle camps, gold, and a shop with 6 items.
14. Théoden, Gothmog and Lurtz abilities (12 abilities).
15. `BotHero` AI, so there are 3 bots plus you.
16. Main menu with faction/hero pick and the collision toggle. Then play full matches and balance.

### Tests needed
- **Unit (GUT, headless):** damage and true-damage maths (Aragorn's passive), cooldown and mana checks, the respawn timer curve, XP level thresholds, resource ledger (can't overspend), `is_enemy` with allies, squad state transitions (ATTACK → target dead → IDLE), lane wave timer, shop purchase.
- **Smoke (headless):** `godot --headless --path . --quit-after 600` boots the match scene with 4 bots and no script errors. This runs in CI on GitHub Actions.
- **Manual:** the playtest checklist in `tests/manual/` (open-rts already has this folder).
- **Performance:** the 150-unit benchmark scene; at least 45 FPS on the target laptop.

```
══════════════════════════════
  ENG REVIEW
══════════════════════════════
Architecture: SOUND, with 3 concerns
  - No ally concept in open-rts → Mitigation: Utils.is_enemy() everywhere + shared fog (step 10)
  - 100+ units on weak laptops → Mitigation: leader-only pathing, Mobile renderer, benchmark first (step 2)
  - Multiplayer retrofit → Mitigation: CommandBus from step 3; bots use it too

Plan: 16 steps, ~20 new files, ~12 modified
Complexity: L for the weekend slice (XL for the full design)
Risk: MEDIUM. Performance and model rigging are the unknowns; both are tested early with fallbacks.
══════════════════════════════
```

---

## Phase 3: Design review (UX spec)

### Flow
Main menu, then Pick faction (Gondor, Rohan, Mordor, Isengard), then Pick hero, then Loading, then Match, then Victory or Defeat screen (stats: kills, gold, squads lost), then back to the menu.

### Controls

| Input | Action |
|---|---|
| Right-click ground | Move the Hero |
| Right-click enemy | Hero auto-attacks it |
| Q W E R | Abilities (Ctrl+key levels one up) |
| Y | Toggle camera lock or free-look. Edge-scrolling and middle-drag work while free. |
| Space | Snap the camera back to the Hero |
| Tab | Cycle through squadrons within command range |
| 1 / 2 / 3 / 4 | Selected squad: **Attack** (click a target) / **Defend** (click a point or building) / **Hold** / **Return home** |
| B | Build menu (only inside the base) |
| P | Shop (only inside the base) |

### HUD
- **Bottom centre:** hero portrait, HP and mana bars, level and XP ring, the QWER bar with cooldown sweeps and mana-cost greying, and 6 item slots.
- **Top:** wood, stone, meat, gold, match clock, and team scores.
- **Bottom right:** minimap showing lanes, fog, and pings for squads under attack.
- **Squad Order panel (contextual, bottom left):** appears only when a squad is within 15m. It shows the squad icon, size, HP and current order, plus the 1–4 order buttons. A 15m ring is drawn on the ground around the Hero.
- **Base panel:** opens while the Hero is inside the base zone. It has tabs for Build, Barracks (lane activation and upgrades) and Shop.

### States
- **No squads nearby:** the order panel is hidden, and a faint tip reads "Move closer to a squadron to command it." The minimap shows where the squads are.
- **Outside the base:** the B and P keys show the toast "Return to your base to build or shop."
- **Hero dead:** the screen goes greyscale with a countdown ("Respawning in 0:23"), and the camera switches to free-look. You can't issue squad orders until you respawn.
- **Can't afford something:** the cost turns red and a tooltip names the missing resource.
- **Lane not activated yet:** the barracks show "Choose a lane", with arrows on the map.
- **Mobile:** not applicable. The target is desktop and laptop with mouse and keyboard.

---

## Weekend heroes (one per faction)

| Faction | Hero | Q | W | E | R | Model |
|---|---|---|---|---|---|---|
| Gondor | **Aragorn** (Fighter) | Andúril Strike: bonus true damage based on the target's missing HP | "For Frodo!": nearby troops get +30% attack speed | Ranger's Dash | **Army of the Dead**: summon a ghost squadron for 15s | Sketchfab Aragorn (PhixerArt) |
| Rohan | **Théoden** (Enchanter) | Royal Guard: shield an ally squad | Horn of Rohan: AoE fear | Rally Aura (passive): troop regen | **Ride of the Rohirrim**: cleanse plus team-wide speed | ⚠️ No free model found, so KayKit knight with a recolour |
| Mordor | **Gothmog** (Vanguard tank) | Cleaver: cone damage | **Warg Pack**: summon wargs that slow | Iron Hide: damage reduction | Siege Lord: troops deal +50% to buildings | Sketchfab Orc (PhixerArt) |
| Isengard | **Lurtz** (Diver) | Heavy Arrow: damage plus pin (root) | The Hunt: speed toward low-HP enemies | Volley: area arrows | Berserker Charge: dash plus execute | Sketchfab Uruk-hai (decimate to about 15k tris) |

The other 20 heroes from your roster go in `data/heroes/` after the weekend, since the system is data-driven.

---

## Proposed 2v2 map layout

```
 Gondor ●━━━━━━━━ lane ━━━━━━━━● Mordor
   ┃  ╲    jungle   jungle   ╱  ┃
 ally   ╲      ╲    ╱       ╱   ally
 route   lane    ╲╱  centre   route
   ┃     ╱      ╱  ╲  camp ╲    ┃
   ┃  ╱    jungle   jungle   ╲  ┃
 Rohan ●━━━━━━━━━ lane ━━━━━━━━● Isengard
```
Each base has 1 route to its ally and 2 lanes to the enemies (straight and diagonal). The diagonals cross at a central boss camp (a Cave Troll that gives a team buff).

---

## Open questions
1. **Teams:** is this 2v2 (Gondor + Rohan vs Mordor + Isengard), or 4-way free-for-all? The plan assumes 2v2, because "1 route to an ally" implies teams.
2. **Which 4 factions** to start with? The plan assumes Gondor, Rohan, Mordor and Isengard. Harad, Elves, Dwarves and the Wild come later.
3. **Attack-unit unlock criterion:** what has to happen first? The default is a Barracks plus a stockpile, or 3 minutes of match time.
4. **Free vs paid squads:** are lane waves free (MOBA) or paid from resources (RTS)? The default is free base waves, with resources buying upgrades and extra squads.
5. **Multiplayer priority:** is LAN next after the slice, or more heroes first?
6. **Rohan hero model:** you'll need to find or commission a Théoden model, or keep the KayKit stand-in.
7. **Downloads you must do yourself:** Sketchfab and Mixamo need your login, so I can't fetch those models from here.
