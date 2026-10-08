# Art bible styles for LOTR Battle Empires. Every prompt starts with one of these blocks so each
# prompt is self-contained when pasted into Nano Banana 2.

WORLD = (
    "Art direction: stylized LOW-POLY 3D fantasy in the spirit of a big MOBA (League of Legends "
    "readability) set in Tolkien's Middle-earth. Faceted, flat-shaded polygons with visible facets, "
    "simple solid colour fills (no photo textures, no noise), soft ambient occlusion, gentle warm key "
    "light with cool shadows. Proportions are heroic and slightly exaggerated (broad shoulders, big "
    "hands and feet, strong chins) but adult, not chibi. Silhouettes must read clearly from a high "
    "top-down camera. Muted, earthy base colours with one strong faction accent colour. "
    "Original designs inspired by Tolkien's books; no character may resemble a real actor."
)

STYLES = {
    "S1": {
        "name": "S1 · Character turnaround (for 3D modelling)",
        "use": "Heroes, troops, villagers, mounts. Feed the result to an image-to-3D tool (Meshy, Tripo, Hunyuan3D) or hand it to a modeller.",
        "text": WORLD + " Format: a character turnaround sheet of ONE character shown three times side by "
        "side at the same scale: front view, left side view, back view. Full body head to toe, relaxed "
        "A-pose with arms angled 30 degrees away from the body, legs slightly apart, weapon held in the "
        "right hand pointing down (or slung on the back if stated). Orthographic camera at chest height, "
        "even flat studio lighting, no cast shadows, plain flat medium-grey background (#7a7f87), no "
        "ground plane, no text, no labels, no UI. 16:9 landscape.",
    },
    "S2": {
        "name": "S2 · Creature / large unit turnaround",
        "use": "Trolls, spiders, wargs, Shelob, Grond, siege engines.",
        "text": WORLD + " Format: a creature turnaround sheet of ONE creature or machine shown three "
        "times at the same scale: front view, side view, back three-quarter view. Neutral standing pose, "
        "orthographic camera, even flat studio lighting, no cast shadows, plain flat medium-grey "
        "background (#7a7f87), no ground plane, no text, no labels. 16:9 landscape.",
    },
    "S3": {
        "name": "S3 · Building (single model)",
        "use": "Every faction building. One building per image, for modelling or image-to-3D.",
        "text": WORLD + " Format: ONE game building seen from a high three-quarter isometric angle "
        "(camera about 45 degrees above, rotated 45 degrees), exactly like an RTS/MOBA building "
        "preview. The whole building is visible and centred, standing on a small round patch of its own "
        "ground (stone, dirt or grass as fitting) that fades out at the edge. Chunky exaggerated "
        "proportions, thick walls, oversized roofs and banners so it reads from far away. Soft studio "
        "lighting, plain flat light-grey background (#c9ccd1), no other buildings, no people, no text. "
        "1:1 square.",
    },
    "S4": {
        "name": "S4 · Environment prop",
        "use": "Trees, rocks, resource nodes, decorations, camp dressing.",
        "text": WORLD + " Format: ONE environment prop (or a small cluster where stated) seen from a high "
        "three-quarter angle (about 45 degrees above), centred, whole object visible, soft studio "
        "lighting, plain flat light-grey background (#c9ccd1), no ground plane except a small patch "
        "directly under it, no text. 1:1 square.",
    },
    "S5": {
        "name": "S5 · Hero portrait (UI)",
        "use": "Hero panel, lobby hero select, scoreboard.",
        "text": WORLD + " Format: a game hero portrait. Low-poly faceted 3D bust (head, shoulders and "
        "upper chest) at a slight three-quarter angle, eyes toward the viewer, strong warm key light "
        "from the upper left and a cool rim light from behind, head fills the upper two thirds of the "
        "frame. Dark smoky background tinted with the faction colour. No text, no frame, no border, no "
        "watermark. 1:1 square, crisp at 128x128 pixels.",
    },
    "S6": {
        "name": "S6 · Ability icon",
        "use": "Q/W/E/R buttons. Must read at 64x64 pixels.",
        "text": WORLD + " Format: a square MOBA ability icon. ONE bold central subject filling about 80% "
        "of the frame, low-poly faceted 3D render with glowing magical effects, very high contrast "
        "between subject and background, strong silhouette that still reads at 64x64 pixels, dark "
        "background with a soft coloured vignette in the ability's colour. No text, no letters, no "
        "numbers, no frame, no border. 1:1 square.",
    },
    "S7": {
        "name": "S7 · Item / resource / upgrade icon",
        "use": "Shop items, resources, Blacksmith upgrades, building and class icons.",
        "text": WORLD + " Format: a square game inventory icon. ONE object, slightly angled, centred and "
        "filling about 75% of the frame, low-poly faceted 3D render with a soft glow behind it, warm "
        "key light, dark charcoal background (#1d1f24) with a subtle radial highlight. Readable at 48x48 "
        "pixels. No text, no frame, no border. 1:1 square.",
    },
    "S8": {
        "name": "S8 · Emblem / status badge",
        "use": "Faction crests, buff/debuff icons, minimap symbols.",
        "text": "Flat low-poly heraldic emblem for a Middle-earth MOBA game: a bold symmetrical symbol "
        "built from flat faceted shapes in two or three solid colours, thick clean edges, readable at "
        "32x32 pixels, centred on a plain solid black background. No text, no letters, no gradients, "
        "no photo detail. 1:1 square.",
    },
    "S9": {
        "name": "S9 · UI element",
        "use": "Panels, frames, buttons, bars, cursors.",
        "text": "2D game UI element for a Middle-earth MOBA: front-facing and perfectly flat "
        "(orthographic), made of dark weathered slate stone and dark wood with thin antique-gold "
        "filigree trim and small low-poly faceted bevels, subtle inner shadow. The centre is EMPTY (no "
        "icons, no text, no letters). Isolated on a plain solid pure white background (#ffffff) with "
        "crisp edges so it can be cut out. Symmetrical where it makes sense.",
    },
    "S10": {
        "name": "S10 · Key art / screen background",
        "use": "Main menu, loading screens, lobby, victory/defeat, logo.",
        "text": WORLD + " Format: cinematic key art, 16:9 landscape. The whole scene is a low-poly "
        "faceted 3D world with dramatic volumetric light rays, atmospheric fog and depth, epic fantasy "
        "mood, composition like a League of Legends splash or loading screen. Leave calm, darker space "
        "where stated for UI. No text, no logos, no watermark unless stated.",
    },
    "S11": {
        "name": "S11 · Seamless ground texture",
        "use": "Terrain, roads, base ground.",
        "text": "Seamless tileable ground texture for a low-poly MOBA, viewed straight down from above, "
        "1:1 square. Stylized: flat colour patches made of large irregular triangles and polygons with "
        "very subtle facet shading, no photographic detail, no noise, no shadows from objects, evenly "
        "lit. All four edges must tile seamlessly. No objects, no text.",
    },
    "S12": {
        "name": "S12 · Map concept (top-down)",
        "use": "Map layout reference and minimap art.",
        "text": WORLD + " Format: a top-down orthographic overview of an entire square MOBA battlefield, "
        "like a strategy board, 1:1 square. Low-poly faceted terrain, readable roads, clear base areas "
        "in the four corners, no UI, no text, no labels.",
    },
}

FACTIONS = {
    "gondor": {
        "name": "Gondor",
        "look": "Gondor: white and pale-grey stone, polished steel, deep midnight-blue cloth, black "
        "leather; accent colour silver-white with sapphire blue; heraldry is a white tree with seven "
        "stars on black.",
        "bg": "deep midnight blue",
    },
    "rohan": {
        "name": "Rohan",
        "look": "Rohan: honey-coloured carved wood, thatch and straw gold, forest green and mossy cloth, "
        "bronze and gold metal, horse-hair plumes; accent colour gold and green; heraldry is a running "
        "white horse on green.",
        "bg": "dark forest green",
    },
    "mordor": {
        "name": "Mordor",
        "look": "Mordor: black pitted iron, rusted spikes, charred leather, ash-grey skin, dried-blood "
        "red rags; accent colour ember orange and blood red; heraldry is a red lidless eye on black.",
        "bg": "ember red and black",
    },
    "isengard": {
        "name": "Isengard",
        "look": "Isengard: black and gunmetal steel plate, crude industrial rivets, dark grey-brown "
        "skin, white paint; accent colour stark white hand print with forge-fire orange; heraldry is a "
        "white hand on black.",
        "bg": "black with forge orange",
    },
    "wild": {
        "name": "The Wild (neutral)",
        "look": "The Wild: moss, bark, bone, pale fungus, grey stone, cobwebs; accent colour sickly "
        "green and violet.",
        "bg": "murky moss green",
    },
}
