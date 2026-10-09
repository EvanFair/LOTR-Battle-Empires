# Developer notes (for contributors and coding agents)

## Project
- **What:** LOTR Battle Empires, a Godot **4.3** (GDScript only) LOTR MOBA+RTS hybrid: 3v3, one shared city per team, one "Supplies" currency, heroes with QWER abilities, squads, villagers.
- **Repo:** /home/user/lotr-battle-empires. Commits go to `main`. The overseer commits, so agents do NOT commit or push.
- **Docs:** docs/BUILD_PLAN_v4.txt (the current plan, milestones M0–M11), docs/DESIGN_v3.txt, docs/CONTROLS.md.
- **Base project:** lampe-games/godot-open-rts under source/match (navigation, fog of war, minimap, camera). Our code is in source/lotr.

## Key files
| Path | Holds |
|---|---|
| `source/lotr/GameData.gd` | All data: factions, heroes (abilities with ranks), buildings, units, items, creatures, ages, costs. Autoload `GameData`; `GameData.now()` is the game clock. |
| `source/lotr/LotrMatch.gd` | Host match logic: players and team banks, spawning, commands (`CommandBus.register("type", _cmd_x)`), camps, forgotten towers, win check, income. |
| `source/lotr/LotrPlayer.gd` | Per player. `treasury()` is the team bank. `supplies`, `has_resources`, `subtract_resources`, `log_spend`; `age` and `upgrades` are shared through the bank. |
| `source/lotr/Combat.gd` | `deal_damage(src, target, amount, type, source_kind, tags)` pipeline, `heal`, `shield`, assist credit (`assists_for`), kill rewards, target priority (`pick_target`). |
| `source/lotr/combat/` | v4 plan A1-A5. `Stats.gd` (layers, armour maths), `Status.gd` (flags), `Buff.gd` + `BuffSlot.gd` + `BuffManager.gd` (add types, crowd-control rules, shields), `DamageCtx.gd`, and one script per reusable buff in `buffs/`. Every unit has `unit.stats`, `unit.status`, `unit.bm`. Apply a buff: `target.bm.add(StunBuff.new(1.2), source)`; read a stat: `unit.stats.armour`; check state: `unit.status.can_cast`. The old fields (`armor`, `speed_mult`, `stunned_until`, `buffs`, `apply_buff`) are read-only shims. Tests: `tests/auto/CombatTest.tscn`. |
| `source/lotr/HeroAbilities.gd` | Ability kinds (strike, nova, skillshot, ...). Replaced by Spell scripts in M2. |
| `source/lotr/units/` | `LotrUnit.gd` (base: hp, buffs, attacks, stun/root), `Hero.gd`, `Troop.gd`, `Villager.gd`, `Creature.gd`, `Building.gd`, `UnitFactory.gd` (builds nodes/models). |
| `source/lotr/Squadron.gd` | Squads: orders, follow, march. |
| `source/lotr/HeroController.gd` | Local input: keys, selection box, casting, placement. |
| `source/lotr/hud/LotrHud.gd` | The whole in-match HUD (code-built Controls). `Indicators.gd` holds ground rings and aim shapes. |
| `source/lotr/net/Replicator.gd` | LAN: host-authoritative snapshots. The fast packet is a PackedByteArray of 12 bytes per unit; the slow state is a dict at 2 Hz. |
| `source/lotr/BotBrain.gd` | Bots plus the team Steward. |
| `source/lotr/art/Art.gd` | Models. Soldiers use the low-poly Quaternius mannequin (`Art.mannequin`); heroes are still KayKit. |
| `source/lotr/art/Icons.gd` | Icons: `Icons.art(group, key)` reads `assets/art/<group>/<key>.png` and returns null if missing. `Icons.ability(dict)` and `Icons.item(key)` are the specific lookups. |
| `assets/art/` | Nano Banana art: portraits, abilities, items, resources, buildings, emblems, keyart. |

## Commands
- **Godot binary:** `/home/user/tools/Godot_v4.3-stable_linux.x86_64` (written `$G` below).
- **Import new assets:** `$G --headless --path . --import`
- **Parse-check one script:** `$G --headless --path . --check-only -s path.gd`. "Identifier not found: GameData" and similar autoload errors are expected there; only real parse errors matter.
- **Tests:** run the .tscn, not the .gd, so autoloads load.
  - `timeout 600 $G --headless --fixed-fps 60 --path . res://tests/auto/BotMatchTest.tscn -- --minutes=6` (3v3 bots; RESULT: PASS/FAIL)
  - `res://tests/auto/RulesTest.tscn` (rules)
  - `res://tests/auto/CombatTest.tscn` (stats, buffs, damage pipeline, crowd control; RESULT: PASS/FAIL)
  - `res://tests/auto/LanTest.tscn -- --role=host|client --seconds=30` (run both at once; see `.github/workflows/tests.yml`)
- **Screenshots** need xvfb and GL: `xvfb-run -a $G --rendering-driver opengl3 --resolution 1600x900 --path . res://tests/auto/V3Shot.tscn -- --out=/some/dir`
- **Noise to ignore:** headless runs print shader errors "Unknown character #35" (pre-existing fog shaders), "Parameter m is null" and RID leak messages at exit.
- **Killing a stuck Godot:** never use `pkill -f` (it kills your own shell). Use `for p in /proc/[0-9]*; do c=$(cat $p/comm 2>/dev/null); case "$c" in Godot*) kill ${p#/proc/};; esac; done`
- **CI:** `.github/workflows/tests.yml` runs BotMatch (two seeds, 3v3), Rules, then LAN.

## Conventions
- GDScript, tabs, no static typing required; match the surrounding style and comment density.
- Godot **4.3** only:
  - no typed dictionaries `Dictionary[K,V]`
  - no `@export_tool_button`
  - no `.uid` files
  - multi-line lambdas inside a call's parentheses don't parse, so use a helper func
- The host is authoritative: gameplay changes happen on the host, and clients get state through Replicator. Check `is_host()` / `puppet` where the surrounding code does.
- Keep gameplay data in GameData tables, not hard-coded in logic.
- **Reference repos** (read-only, for copying patterns or code) are under `/tmp/claude-0/-home-user/11830cd4-db11-509f-ba13-bf47ce1014e3/scratchpad/refs/`:
  - `loj/`: League-of-Jinx, Godot 4.4 LoL port. Remove typed dicts when copying.
  - `omoba/`: omoba-bevy, Rust; hero and item design numbers.
  - `os/`: OpenSAGE parts.
  - `bp/`: the OpenSAGE Blender W3D plugin.
