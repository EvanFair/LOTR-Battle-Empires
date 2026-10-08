# QA report: LOTR Battle Empires, 2026-10-08

QA run with the gstack-qa workflow, adapted from web to game: a scripted player (`tests/auto/PlayQA`) drives the real build with real mouse and keyboard events from the main menu, and screenshots every step under a virtual display. The automated suite (bot matches, 23 rule checks, LAN host and client) ran alongside it.

```
══════════════════════════════════════════
  QA REPORT — LOTR Battle Empires — 2026-10-08
══════════════════════════════════════════
Health Score: Before 5/10 → After 7.5/10

🔴 Critical (0)
🟡 High (4)     — 4 fixed, 0 remaining
🟢 Medium (5)   — 3 fixed, 2 deferred
⚪ Low (3)      — 3 noted

FIXES APPLIED:
  • fix: Esc never opened the match menu (HeroController swallowed it)
  • fix: match menu paused the whole game in LAN matches (Menu.gd)
  • fix: exiting a match didn't leave the network session (Menu.gd)
  • fix: a second match reused the first match's baked navmesh (LotrMatch.gd)
  • fix: fog of war covered visible land on the OpenGL renderer (fog shaders)
  • fix: open-rts ground-fog overlay washed the terrain beige (LotrMatch.gd)
  • feat: stand-in shapes replaced with animated KayKit models (the main
    complaint: "looks nothing like Lord of the Rings")

OPEN ITEMS:
  • World turns dark behind the pause menu — Low — source/match/Menu.tscn
  • Floating building labels are small at default zoom — Low — Building.gd
  • Toasts can overlap the base panel title — Low — LotrHud.gd
  • Bots run short of Food by minute 6 (balance) — Medium — GameData.gd
  • Right-clicks on top of HUD panels don't reach the map (by design,
    but the base panel is large) — Medium — LotrHud.gd

SHIP READINESS: READY (as a playable build); see "Gap to the full game"
══════════════════════════════════════════
```

## Critical path results (PlayQA, 27/27 after fixes)

| Flow | Result |
|---|---|
| Main menu → Play → Single player → Lobby → Start | ✅ |
| Right-click moves the hero; camera follows | ✅ |
| Y unlocks the camera; arrow keys pan; Space relocks | ✅ |
| Click a Village House → bubbles → assign Wood | ✅ |
| B opens the base panel → build a house → click to place the foundation | ✅ |
| E (Ranger's Dash) moves the hero; Q with no target shows a hint | ✅ |
| Tab with no squadrons nearby | ✅ |
| Esc opens the menu and pauses (offline) | ❌ → ✅ fixed |
| Exit to menu → play a second match | ⚠️ (navmesh assertion) → ✅ fixed |
| Victory screen → back to menu | ✅ |

## Gap to the full game

Updated after the "build it all" pass (armies, heroes, jungle, shop, sound, controls):

| Area | Built | Still missing |
|---|---|---|
| **Look** | KayKit animated units and buildings per faction, procedural siege engines, Shelob and jungle spiders, Cave Troll, ability and item icons (Open MOBA, CC-BY) | LOTR-specific hero models, real horse models, hero portraits, a parchment UI theme |
| **Heroes** | All 12 heroes of the 4 launch factions, four abilities each, ranks via skill points, stun/root/slow/weaken | Heroes for the other 4 factions, hero-specific voice lines |
| **Factions** | Gondor, Rohan, Mordor, Isengard | Eldar, Durin's Folk, Harad & the East, Guardians of the Wild |
| **Armies** | 5 classes per faction incl. unique heavy and special troops, Ages I–III, Siege Works, faction special building, Blacksmith research, auto-repeat lanes, counters | Walls and gates, formations |
| **Economy** | Villagers (3 per house), 5 resources, regrowing herds, Storehouse halving, hauling, jungle gold, Town Center shop (10 items) | Farms, trading |
| **Map** | 4-base 6-lane map, 8 jungle camps, Cave Troll lair | More maps (Pelennor, Helm's Deep, Osgiliath), terrain height |
| **Controls** | MOBA scheme from 4 reference MOBAs (docs/CONTROLS.md): hold-to-aim, attack-move, hold, recall, pings, minimap orders, markers, damage numbers | Key rebinding, quick-cast option toggle |
| **Multiplayer** | LAN host/join, discovery, bot takeover | Internet play, reconnecting |
| **AI** | Bots build through Age III, research, learn abilities, buy items, hunt camps, push lanes | Difficulty levels, team coordination |
| **Audio** | Music, combat/arrow/tower/death/level-up/UI sounds, synthesized horns, war drums, clashes, blasts | Unit voice lines, per-faction music |
| **Performance** | Spatial grid for targeting, 10 Hz fog visibility, throttled minimap, small squads and 3 villagers per house | Profiling on real laptop hardware |
| **Front end** | Main menu, lobby with all 12 heroes, end screen | Hero select with portraits, tutorial, settings menu |
