# Controls: what other MOBAs do, and the scheme for LOTR Battle Empires

Four open-source MOBAs were compared (cloned read-only, nothing copied from their code):

| Repo | Engine, licence | What's worth taking |
|---|---|---|
| [o-moba/omoba-bevy](https://github.com/o-moba/omoba-bevy) | Rust/Bevy. Client code MPL-2.0, sim/server code AGPL-3.0. Art CC-BY-4.0 / CC0 | The most complete reference. Hold a skill key to aim (shape indicator), release to cast. Out-of-range casts walk in, then fire. B recall (7s channel, cancelled by move, cast or damage). Y/Space camera, P shop at base. Tower-range ground fill. Camp leashing. **CC0 audio and CC-BY icons are now used in this game** (see Credits). |
| [yasgamesdev/MOBA_CSharp_Unity](https://github.com/yasgamesdev/MOBA_CSharp_Unity) | Unity C#, MIT (Ethan model and particles are Unity Asset Store, not reusable) | The clearest small reference. QWER shows an indicator and left-click confirms. Cursor changes for move/attack/cast. Green move ring and red attack ring (shrinking). Attack lands halfway through the swing; a move order cancels the swing. Monsters only aggro when hit, then leash home. B recall (5s). Items on 1–6. |
| [yasgamesdev/OpenMOBA](https://github.com/yasgamesdev/OpenMOBA) | UE4 Blueprints, MIT (UE mannequin and AnimStarterPack are Unreal-only) | An AttackMove command. B recall, 1–6 items, P shop, Space follow. |
| [AmbientRun/amoba](https://github.com/AmbientRun/amoba) | Rust/Ambient proof of concept (Mixamo assets, not redistributable) | Not much: left-click move and a short-lived click cross. Its edge-pan zone (outer quarter of the screen) is a warning, not a model. |

## The scheme

RMB and QWER stay, because every MOBA uses them. What changes is that the RTS layer (squadrons, base panel) has to share the keyboard, so items go on 5–8 and **B becomes context-sensitive**: inside your base it opens the base panel, outside it starts Recall. Recall is useless at home and the base panel only works there, so the two never clash.

| Input | Action |
|---|---|
| **Right-click** ground / enemy | Move / attack (smart click) |
| **A**, then left-click | Attack-move: walk there, fighting anything on the way. A + click on an enemy attacks it. |
| **S** / **H** | Stop / hold position |
| **Q W E R** | Quick-cast at the cursor on press (default). Optional setting: hold to show the indicator, cast on release. A unit-target spell picks the unit under the cursor or the nearest enemy near it, and walks into range first. |
| **Ctrl + Q/W/E/R** | Spend a skill point to level that ability |
| **D / F** | Hero utilities (faction horn/rally, heal) |
| **5 6 7 8** | Item slots |
| **B** | In base: base panel (Build / Military / Age / Blacksmith / Shop). Outside: **Recall** (6s, cancelled by moving, casting or taking damage) |
| **P** | Shop (only at base) |
| **V** | Build menu anywhere (buildings can go anywhere since the 8 Oct playtest) |
| Left-drag / click a soldier | Select squadrons anywhere; one soldier in the box selects its whole squadron; Shift adds |
| Right-click with squadrons selected | They attack / move there; the hero stays |
| **G** | Follow me: selected (or all) squadrons follow the hero and attack what it attacks |
| **Tab** / **Ctrl+A** | Cycle / select all squadrons (no 15m limit any more) |
| **1 2 3 4** | Selected squadrons: Attack / Move / Hold / Return home |
| **Alt + left-click** (map or minimap) | Ping |
| **Y** / **Space** | Camera lock on/off / snap to hero |
| Arrows, thin screen-edge band, middle-drag | Pan |
| Wheel / **Z C** | Zoom / rotate |
| Minimap left-click / right-click | Move the camera / move the hero |
| **Esc** | Cancel targeting or placement; otherwise the menu |
| **F8** | Game speed 1x / 2x / 5x (testing aid; host only) |

## Feedback each control needs

- **Move:** a green ring on the ground that shrinks away (about 0.6s).
- **Attack:** a red ring that follows the target.
- **Cursor:** shape changes over enemies.
- **A pressed:** the hero's attack-range circle.
- **Skill held** (or in indicator mode): the cast-range circle, plus the skill's shape (line for a skillshot, circle at the cursor for ground AoE, highlight for a unit target).
- **Selection:** a ring under every soldier of the selected squadrons, and a green drag box while selecting.
- **Defend:** a gold flag where the squad will defend.
- **Recall:** a channel ring with a progress arc.
- **Ping:** an expanding ring in the world and a blip on the minimap.
- **Enemy tower:** its range shows on the ground when your hero is near it.
- **Attack timing:** the hit lands partway into the swing. A move order cancels the swing (lets you kite).
