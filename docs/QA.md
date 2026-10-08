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

What exists today versus the design in `docs/PLAN.md`:

| Area | Built | Missing for the full game |
|---|---|---|
| **Look** | KayKit animated units and medieval buildings per faction, scenery, faction ground | LOTR-specific hero models (Sketchfab downloads need your login), real horse and siege models, hero portraits and unit icons, a parchment/Middle-earth UI theme, LOTR fonts |
| **Heroes** | 4 heroes (Aragorn full QWER; Théoden, Gothmog, Lurtz one ability each) | 20 more heroes; full kits for the three; ability levelling (Ctrl+key); hero items |
| **Factions** | Gondor, Rohan, Mordor, Isengard | Eldar, Durin's Folk, Harad & the East, Guardians of the Wild |
| **Armies** | Infantry, archers, riders; Barracks, Range, Stables; auto-repeat lanes; counters | Heavy and special units, Siege Works and faction special buildings, Age III, Blacksmith and squad-size upgrades, walls |
| **Economy** | Villagers, 5 resources, Storehouse halving, hauling, hero-only building, Ages I–II | Jungle camps and gold farming, the Town Center shop, farms, population cap |
| **Map** | One 4-base, 6-lane map | Central boss camp (Cave Troll), jungle creatures, more maps (Pelennor, Helm's Deep, Osgiliath…), terrain height |
| **Multiplayer** | LAN host/join, discovery, bot takeover | Internet play, reconnecting, a match browser |
| **AI** | Bots build, advance, train and push | Difficulty levels, smarter hero play, use of all abilities |
| **Audio** | Leftover open-rts sci-fi voice lines | Music, combat sound effects, LOTR-flavoured unit responses |
| **Front end** | Main menu, lobby, end screen | Hero select with portraits, how-to-play/tutorial, match stats, settings (graphics, keys, collision toggle) |
