import json, sys
from styles import STYLES, FACTIONS, WORLD
import assets as A

F = {k: v["look"] for k, v in FACTIONS.items()}
sections = []


def add(section, items):
    sections.append({"title": section[0], "id": section[1], "intro": section[2], "items": items})


def item(id_, file, style, title, subject, faction=None, note=""):
    parts = [STYLES[style]["text"], "", "Subject: " + subject.rstrip(".") + "."]
    if faction:
        parts.append("Faction look: " + F[faction])
    return {"id": id_, "file": file, "style": style, "title": title, "prompt": "\n".join(parts), "note": note}


# 0. style boards
boards = [item("board_world", "board_world.png", "S10", "World style board",
               "a style reference board for the whole game: a small floating low-poly diorama island showing a "
               "winding dirt road through green meadow, pine trees, grey boulders, a stone watchtower, a tiny "
               "Gondor soldier and a tiny orc facing each other on the road, seen from a high MOBA camera angle "
               "(55 degrees). Beside it, a row of eight flat colour swatch squares: meadow green, road brown, "
               "stone grey, pine green, Gondor blue, Rohan gold, Mordor ember red, Isengard black-and-white. "
               "Neutral dark background, no text.")]
for k, v in FACTIONS.items():
    boards.append(item(f"board_{k}", f"board_{k}.png", "S10", f"{v['name']} style board",
                       f"a faction style board for {v['name']}: a line-up of four low-poly figures of this faction "
                       f"(a hero, a footsoldier, an archer and a worker) standing in front of one of their "
                       f"buildings, with their banner on a pole, plus a row of five flat colour swatch squares of "
                       f"the faction palette. Plain dark {v['bg']} background, no text.", k))
add(("Step 0 · Style boards (make these first)", "boards",
     "Generate these six images first and pick the best of each. Then attach board_world.png plus the "
     "matching faction board as reference images to every later prompt (Nano Banana accepts reference "
     "images). That keeps every asset in one consistent style."), boards)

# 1. heroes
add(("Heroes · 3D turnaround sheets (12)", "heroes",
     "One sheet per hero. Use these to find or build the 3D model (image-to-3D tools work best on these "
     "front/side/back sheets)."),
    [item(f"hero_{h}", f"hero_{h}_turnaround.png", "S2" if h == "shelob" else "S1", f"{n} · {role}", desc, fac)
     for h, fac, n, role, desc in A.HEROES])

# 2. portraits
add(("Heroes · portraits (12)", "portraits", "Square busts for the hero panel, lobby and scoreboard."),
    [item(f"portrait_{h}", f"portrait_{h}.png", "S5", f"{n} portrait",
          (desc.split(". Show")[0].replace(":  ", ": ").rstrip(".") + ". Show only the head, shoulders and upper chest"
           + (" (for Shelob: her head, eyes, fangs and front legs)" if h == "shelob" else "")
           + f". Background tint: {FACTIONS[fac]['bg']}"), fac)
     for h, fac, n, role, desc in A.HEROES])

# 3. troops
troops = []
for fac, units in A.TROOPS.items():
    for uid, name, cls, desc in units:
        style = "S2" if uid == "heavy" and fac == "mordor" else "S1"
        troops.append(item(f"unit_{fac}_{uid}", f"unit_{fac}_{uid}_turnaround.png", style,
                           f"{FACTIONS[fac]['name']} · {name}", desc, fac))
for mid, name, desc in A.MOUNTS:
    troops.append(item(mid, f"{mid}_turnaround.png", "S2", f"Mount · {name}", desc))
for sid, name, fac, desc in A.SIEGE:
    troops.append(item(sid, f"{sid}_turnaround.png", "S1" if sid.startswith("summon") else "S2", name, desc, fac))
add(("Armies · troops, mounts, siege (28)", "troops",
     "Riders are drawn without their mount so the rider and the mount can be separate models. Siege "
     "engines and Grond are machines (S2)."), troops)

# 4. creatures
add(("The Wild · jungle creatures and boss (3)", "creatures", "Neutral camps between the lanes and the boss in the middle.",),
    [item(cid, f"{cid}_turnaround.png", "S2", name, desc, "wild") for cid, name, desc in A.CREATURES])

# 5. buildings
blds = []
for fac in ["gondor", "rohan", "mordor", "isengard"]:
    for key, name, descs in A.BUILDINGS:
        blds.append(item(f"bld_{fac}_{key}", f"bld_{fac}_{key}.png", "S3",
                         f"{FACTIONS[fac]['name']} · {name}", descs[fac], fac))
add(("Buildings · 10 per faction (40)", "buildings",
     "Same 10 buildings for every faction, each in that faction's architecture."), blds)

# 6. props
add(("Environment props (24)", "props", "Trees, rocks, resource nodes and camp dressing for the map."),
    [item(pid, f"{pid}.png", "S4", name, desc) for pid, name, desc in A.PROPS])

# 7. textures
add(("Ground textures (8)", "textures", "Seamless tiles for the terrain, roads and base grounds."),
    [item(tid, f"{tid}.png", "S11", name, desc) for tid, name, desc in A.TEXTURES])

# 8. map
add(("Map concept (2)", "map",
     "Reference for the new winding map layout (your feedback: the lanes are too straight)."),
    [item("map_concept", "map_concept.png", "S12", "Battlefield layout: winding lanes",
          "a square battlefield with four fortified bases in the four corners (top-left white stone Gondor, "
          "top-right black Mordor, bottom-left golden Rohan, bottom-right black-iron Isengard). Six dirt-road "
          "lanes connect the bases and every lane WINDS: the four outer lanes follow the map edges in long "
          "S-curves around hills and cliffs, and the two diagonal lanes snake through dense forest, cross a "
          "river on stone bridges and meet at a rocky cave lair in the exact centre. Between the lanes are "
          "patches of jungle with small clearings for creature camps, a river crossing the middle from top "
          "to bottom, snow mountains along the top edge."),
     item("map_minimap", "map_minimap.png", "S12", "Painted minimap",
          "the same battlefield as a simplified painted minimap: flat colours only, green land, brown winding "
          "roads, blue river, dark-green forests, grey mountains along the top edge, four faction-coloured "
          "corner bases (blue, gold, red, black). Very clean and readable at 256x256 pixels.")])

# 9. ability icons
abil = []
for h, fac, n, role, desc in A.HEROES:
    for key, name, visual in A.ABILITIES[h]:
        abil.append(item(f"ability_{h}_{key.lower()}", f"ability_{h}_{key.lower()}.png", "S6",
                         f"{n} {key} · {name}", visual + f" (ability '{name}' of {n})", fac))
add(("Ability icons (48)", "abilities", "Q, W, E and R for all 12 heroes. They must read at 64x64 pixels."), abil)

# 10. inventory-style icons
inv = [item(f"item_{i}", f"item_{i}.png", "S7", f"Item · {n}", d) for i, n, d in A.ITEMS]
inv += [item(f"res_{i}", f"res_{i}.png", "S7", f"Resource · {n}", d) for i, n, d in A.RESOURCES]
inv += [item(f"upgrade_{i}", f"upgrade_{i}.png", "S7", f"Blacksmith · {n}", d) for i, n, d in A.UPGRADES]
inv += [item(f"class_{i}", f"class_{i}.png", "S7", f"Unit class · {n}", d) for i, n, d in A.CLASSES]
BICON = {"town_center": "castle keep", "village_house": "cottage", "watchtower": "watchtower",
         "barracks": "barracks hall with a shield on the door", "archery_range": "archery target with a bow",
         "stables": "stable with a horseshoe sign", "storehouse": "storehouse with crates and sacks",
         "blacksmith": "forge with an anvil", "siege_works": "workshop with a small catapult",
         "special_building": "grand hall with a star banner"}
inv += [item(f"bicon_{k}", f"bicon_{k}.png", "S7", f"Build menu · {n}",
             f"a tiny neutral stone-and-timber miniature {BICON[k]}, like a board-game piece")
        for k, n, _ in A.BUILDINGS]
add(("Item, resource, upgrade and menu icons (36)", "icons", "Shop items, the top resource bar, Blacksmith research, unit classes and the build menu."), inv)

# 11. emblems
crests = {"gondor": "a white tree with seven white stars above it, on a black shield",
          "rohan": "a white running horse on a green shield",
          "mordor": "a red lidless eye wreathed in flame on a black shield",
          "isengard": "a white open hand print on a black shield",
          "wild": "a grey stone troll skull with green moss"}
emb = [item(f"crest_{k}", f"crest_{k}.png", "S8", f"Crest · {FACTIONS[k]['name']}", v) for k, v in crests.items()]
emb += [item(f"status_{i}", f"status_{i}.png", "S8", f"Status · {n}", f"{d}, in {c}") for i, n, d, c in A.STATUS]
emb += [item(i, f"{i}.png", "S8", n, d) for i, n, d in A.MAP_ICONS]
add(("Crests, status effects and minimap symbols (20)", "emblems", "Flat symbols that must read at 32x32 pixels."), emb)

# 12. UI
add(("UI kit (14)", "ui", "Frames and buttons; I cut them out and nine-slice them in Godot. Keep the centres empty."),
    [item(i, f"{i}.png", "S9", n, d) for i, n, d in A.UI])

# 13. screens
add(("Key art and screens (9)", "screens", "Main menu, lobby, loading screens and the end-of-match banners."),
    [item(i, f"{i}.png", "S10", n, d) for i, n, d in A.SCREENS])

# --- character list ----------------------------------------------------------------------------
ANIM = {
    "melee": "idle, walk, run, attack ×2, hit react, death",
    "ranged": "idle, walk, run, aim + shoot, hit react, death",
    "hero": "idle, walk, run, attack ×2, cast (point), cast (raise/shout), dash or leap, hit react, stun, death, victory",
    "rider": "ride idle, ride gallop, ride attack, death (sits on the mount's saddle bone)",
    "mount": "idle, walk, gallop, death",
    "villager": "idle, walk, chop wood, mine/gather, carry-walk, hit react, death",
    "creature": "idle, walk, run, attack ×2, hit react, death",
    "siege": "optional: fire/swing, roll (wheels can be animated in code)",
}
chars = []
for h, fac, n, role, desc in A.HEROES:
    chars.append({"id": f"hero_{h}", "name": n, "faction": FACTIONS[fac]["name"], "role": "Hero · " + role,
                  "anims": ANIM["creature"] + ", web/sting cast" if h == "shelob" else ANIM["hero"], "tris": "8–12k"})
for fac, units in A.TROOPS.items():
    for uid, name, cls, desc in units:
        if uid == "villager":
            a = ANIM["villager"]
        elif "rider only" in name:
            a = ANIM["rider"]
        elif uid == "heavy" and fac == "mordor":
            a = ANIM["creature"]
        elif cls in ("archer",) or (uid == "special" and fac in ("gondor",)):
            a = ANIM["ranged"]
        else:
            a = ANIM["melee"]
        chars.append({"id": f"unit_{fac}_{uid}", "name": name.replace(" (rider only)", "").replace(" (worker)", ""),
                      "faction": FACTIONS[fac]["name"], "role": cls.capitalize(), "anims": a,
                      "tris": "3–5k" if uid != "heavy" else "5–8k"})
for mid, name, desc in A.MOUNTS:
    chars.append({"id": mid, "name": name, "faction": "Shared", "role": "Mount", "anims": ANIM["mount"], "tris": "3–5k"})
for sid, name, fac, desc in A.SIEGE:
    chars.append({"id": sid, "name": name, "faction": FACTIONS[fac]["name"] if fac != "wild" else "Gondor (summon)",
                  "role": "Summon" if sid.startswith("summon") else "Siege machine",
                  "anims": ANIM["melee"] if sid.startswith("summon") else ANIM["siege"], "tris": "3–8k"})
for cid, name, desc in A.CREATURES:
    chars.append({"id": cid, "name": name.split(" (")[0], "faction": "The Wild", "role": name.split("(")[1].rstrip(")").capitalize(),
                  "anims": ANIM["creature"], "tris": "4–10k"})

styles = [{"id": k, "name": v["name"], "use": v["use"], "text": v["text"]} for k, v in STYLES.items()]
factions = [{"id": k, "name": v["name"], "look": v["look"]} for k, v in FACTIONS.items()]
data = {"sections": sections, "styles": styles, "factions": factions, "characters": chars, "world": WORLD}
json.dump(data, open(sys.argv[1], "w"), ensure_ascii=False, indent=1)
print("prompts:", sum(len(s["items"]) for s in sections), "characters:", len(chars))
