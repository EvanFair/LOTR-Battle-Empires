"""Turn the Nano Banana art (media.zip, codes from docs/ART_PROMPTS.txt) into game-ready files.

Usage: python3 tools/art/import_media.py <folder with the extracted media/*.jpg>
Writes assets/art/... The first version of each code is used; change PICK to choose another
(e.g. "AB02": "_2").
"""
import glob
import os
import sys

from PIL import Image

SRC = sys.argv[1]
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "art")
PICK = {}

HEROES = ["aragorn", "boromir", "faramir", "theoden", "eomer", "eowyn", "gothmog", "witch_king",
          "shelob", "ugluk", "saruman", "lurtz"]
ITEMS = {"IC04": "lembas", "IC05": "athelas", "IC06": "horse_rohan", "IC07": "elven_blade",
         "IC08": "dwarf_mail", "IC09": "ring_barahir", "IC10": "horn_mark", "IC11": "phial",
         "IC12": "westernesse", "IC13": "mithril"}
RES = {"IC14": "food", "IC15": "wood", "IC16": "stone", "IC17": "iron", "IC18": "gold"}
BUILDINGS = {"IC30": "town_center", "IC31": "village_house", "IC32": "watchtower", "IC33": "barracks",
             "IC34": "archery_range", "IC35": "stables", "IC36": "storehouse", "IC37": "blacksmith",
             "IC38": "siege_works", "IC39": "special_building"}
EMBLEMS = {"EM01": "gondor", "EM02": "rohan", "EM03": "mordor", "EM04": "isengard", "EM05": "wild"}
KEYART = {"KA11": "menu", "KA12": "lobby", "KA13": "loading_gondor", "KA05": "loading_rohan",
          "KA06": "loading_mordor", "KA07": "loading_isengard", "KA03": "victory", "KA04": "defeat"}


def find(code):
    files = sorted(glob.glob(os.path.join(SRC, code + "_*.jpg")))
    want = PICK.get(code, "")
    for f in files:
        stem = f.rsplit(".png_", 1)[-1][:-4]
        if (want == "" and "_" not in stem) or (want and stem.endswith(want)):
            return f
    return files[0] if files else None


def save(code, sub, name, size, crop=0.0, fmt="png"):
    f = find(code)
    if f is None:
        print("missing", code)
        return
    im = Image.open(f).convert("RGB")
    w, h = im.size
    if crop:
        im = im.crop((int(w * crop), int(h * crop), int(w * (1 - crop)), int(h * (1 - crop))))
    if isinstance(size, int):
        im = im.resize((size, size), Image.LANCZOS)
    else:
        im.thumbnail(size, Image.LANCZOS)
    os.makedirs(os.path.join(OUT, sub), exist_ok=True)
    path = os.path.join(OUT, sub, "%s.%s" % (name, fmt))
    if fmt == "webp":
        im.save(path, quality=82, method=6)
    else:
        im.save(path, optimize=True)


for i, hero in enumerate(HEROES):
    # portraits: swatches/labels sit in the outer corners, so take the centre
    save("HP%02d" % (i + 1), "portraits", hero, 256, crop=0.1)
    for j, key in enumerate("QWER"):
        save("AB%02d" % (4 + i * 4 + j), "abilities", "%s_%s" % (hero, key), 128, crop=0.04)
for group, sub, size, crop in [(ITEMS, "items", 128, 0.06), (RES, "resources", 64, 0.08),
                               (BUILDINGS, "buildings", 128, 0.06), (EMBLEMS, "emblems", 128, 0.06)]:
    for code, name in group.items():
        save(code, sub, name, size, crop)
for code, name in KEYART.items():
    save(code, "keyart", name, (1600, 900), fmt="webp")
print("done")
