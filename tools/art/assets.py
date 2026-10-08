# Every 2D asset the game needs, in generation order. (id, filename, style, title, subject)
from styles import FACTIONS

F = {k: v["look"] for k, v in FACTIONS.items()}

HEROES = [
    ("aragorn", "gondor", "Aragorn", "Fighter, melee",
     "Aragorn, the ranger who becomes king: lean and weathered man, dark shoulder-length hair, short "
     "dark beard, grey-green hooded travel cloak over dark leather jerkin and a steel-plated chest "
     "with a faint white-tree emblem, leather bracers, tall boots. Holds Andúril, a long silver "
     "hand-and-a-half sword with faintly glowing elvish runes."),
    ("boromir", "gondor", "Boromir", "Vanguard / tank, melee",
     "Boromir, captain of Gondor: broad and powerful man, shoulder-length auburn hair and short beard, "
     "dark-red fur-trimmed cloak, steel breastplate engraved with the white tree, round steel-rimmed "
     "shield on the left arm, broad sword in the right hand, a white horn with silver bands on his belt."),
    ("faramir", "gondor", "Faramir", "Ranger, ranged",
     "Faramir, captain of the Rangers of Ithilien: slim young man, light-brown hair, mottled "
     "green-and-brown hooded ranger cloak, dark green leather, bracers, long dark-wood longbow in the "
     "left hand, full quiver on the back, short sword at the hip."),
    ("theoden", "rohan", "Théoden", "Enchanter / support, melee",
     "Théoden, king of Rohan: older man with long grey-gold hair and a short grey beard, thin gold "
     "crown circlet, gold-and-green royal armour with galloping-horse reliefs, long green cloak with "
     "gold trim, the sword Herugrim held point down."),
    ("eomer", "rohan", "Éomer", "Fighter, melee",
     "Éomer, Marshal of the Riddermark: tall young warrior, long blond hair, open-faced steel helmet "
     "with a long white horse-hair plume, bronze scale mail, green cloak, a long spear in the right "
     "hand and a round green shield with a white horse on the left arm."),
    ("eowyn", "rohan", "Éowyn", "Assassin, melee",
     "Éowyn, shieldmaiden of Rohan: young woman with long golden hair in a braid, determined "
     "expression, practical fitted Rohan mail and leather, grey-green skirt over trousers and boots, "
     "a slender sword in the right hand and a round shield with a gold horse on the left arm."),
    ("gothmog", "mordor", "Gothmog", "Vanguard / tank, melee",
     "Gothmog, orc lieutenant of Morgul: hulking hunched orc, pale lumpy scarred skin with a swollen "
     "misshapen face, crude spiked black iron armour with a red eye painted on the chest, tattered "
     "dark-red rags, a heavy iron mace with a spiked head."),
    ("witch_king", "mordor", "Witch-king", "Enchanter / caster, melee",
     "The Witch-king, lord of the Nazgûl: very tall figure in ragged black robes and jagged black "
     "plate armour, NO visible face (only darkness under a spiked iron crown-helm), gauntleted hands, "
     "a long black sword with a faint pale-green ghostly glow, wisps of cold mist around the hem."),
    ("shelob", "mordor", "Shelob", "Diver, melee (giant spider)",
     "Shelob, the ancient giant spider: enormous bloated black-brown abdomen with faint pale "
     "markings, eight long jointed hairy legs, cluster of many glowing green eyes, dripping fangs, "
     "torn cobwebs trailing from her body. Show as a creature turnaround (front, side, back three-quarter)."),
    ("ugluk", "isengard", "Uglúk", "Vanguard / tank, melee",
     "Uglúk, Uruk-hai captain: big muscular Uruk-hai with dark grey-brown skin and long black hair, "
     "a white hand print painted across his face, heavy black plate armour, a broad notched cleaver "
     "sword in the right hand and a round black shield with a white hand."),
    ("saruman", "isengard", "Saruman", "Caster, ranged",
     "Saruman the White: tall old wizard with a long straight white beard and long white hair, "
     "flowing pure white robes with subtle silver trim, a tall black iron staff topped with a white "
     "crystal held in the right hand, stern commanding face."),
    ("lurtz", "isengard", "Lurtz", "Diver, ranged",
     "Lurtz, the first Uruk-hai: very tall lean-muscled Uruk-hai, dark grey skin, bald head with a "
     "white hand print over his face, minimal black armour on the shoulders and forearms, a huge "
     "black recurve bow in the left hand and a quiver of black arrows on the back."),
]

ABILITIES = {  # hero -> [(key, name, visual)]
    "aragorn": [("Q", "Andúril Strike", "a silver longsword slashing diagonally, blade trailing white-blue light and elvish runes"),
                ("W", "For Frodo!", "a raised sword with a golden shockwave of courage radiating outward, warm gold glow"),
                ("E", "Ranger's Dash", "a hooded figure dashing forward leaving green motion streaks and leaves"),
                ("R", "Army of the Dead", "ghostly green skeletal warriors with swords rising from swirling green mist")],
    "boromir": [("Q", "Shield Bash", "a round steel shield slamming forward with a white impact burst and stars"),
                ("W", "Horn of Gondor", "a white horn with silver bands blowing a visible blue-white soundwave"),
                ("E", "Charge", "an armoured warrior charging with a shield, ground cracking with orange impact dust"),
                ("R", "Last Stand", "a battered shield and sword planted in the ground glowing with defiant red-gold light")],
    "faramir": [("Q", "Volley", "a rain of arrows falling from above in an arc, green fletching"),
                ("W", "Ithilien Stealth", "a green hooded cloak half-dissolving into leaves and shadow"),
                ("E", "Precise Shot", "a single long arrow piercing straight forward with a sharp white trail"),
                ("R", "Rangers of Ithilien", "three green-hooded archers emerging from a dark forest, bows drawn")],
    "theoden": [("Q", "Herugrim", "a golden sword sweeping in a full circle leaving a gold arc"),
                ("W", "Arise, Riders", "a golden crown above green healing light and rising sparks"),
                ("E", "Snowmane", "a galloping white horse head with a flowing mane, speed lines"),
                ("R", "Ride of the Rohirrim", "a wave of golden horses and spears charging, dawn light behind")],
    "eomer": [("Q", "Spear Throw", "a long spear flying forward with a green-white streak"),
              ("W", "Riders of the Mark", "three horse heads with plumed helmets in a row, green banner"),
              ("E", "Charge", "a plumed rider leaping forward, dust explosion on landing"),
              ("R", "Death!", "a raised spear and shield with a crimson-gold war-cry shockwave")],
    "eowyn": [("Q", "Shieldmaiden", "a slender sword thrusting forward with a sharp golden glint"),
              ("W", "Shield Wall", "a round shield with a gold horse glowing with a protective bubble"),
              ("E", "Dernhelm", "a cloaked figure rolling forward, motion streaks"),
              ("R", "I Am No Man", "a sword piercing a black iron crown-helm, burst of white light")],
    "gothmog": [("Q", "Cleave", "a spiked iron mace swinging in a circle, red sparks"),
                ("W", "Warg Pack", "three snarling warg heads with glowing yellow eyes"),
                ("E", "The Age of Men Is Over", "an orc war banner with a red eye, red-orange rage aura"),
                ("R", "Siege Fury", "burning siege towers and flaming boulders under a red sky")],
    "witch_king": [("Q", "Morgul Blade", "a jagged pale-green dagger dripping cold poison mist"),
                   ("W", "Black Breath", "a black shadow mist spreading from an empty hood, pale green wisps"),
                   ("E", "Fell Beast", "a black winged fell beast swooping down with spread leathery wings"),
                   ("R", "Dread Shriek", "a spiked crown-helm with a visible pale-green scream shockwave")],
    "shelob": [("Q", "Sting", "a glistening black stinger dripping green venom"),
               ("W", "Web", "a thick white spider web net flying outward"),
               ("E", "Lurk", "many glowing green eyes in total darkness"),
               ("R", "Feast", "giant fangs and a dark red aura, cocooned victim")],
    "ugluk": [("Q", "Cleave", "a black notched cleaver sweeping in a circle, white sparks"),
              ("W", "Bloodlust", "a white hand print smeared red with a pulsing red aura"),
              ("E", "Leap", "an armoured uruk leaping with a shockwave of dust below"),
              ("R", "Uruk Charge", "a column of black-armoured uruks charging behind a white hand banner")],
    "saruman": [("Q", "Fireball", "a roaring orange fireball with black smoke"),
                ("W", "Voice of Saruman", "a commanding open mouth with glowing white spellbinding rings"),
                ("E", "Staff Blast", "a white crystal staff firing a straight beam of white-blue energy"),
                ("R", "Fire of Orthanc", "a huge fiery explosion blowing apart a stone wall")],
    "lurtz": [("Q", "Heavy Arrow", "a thick black arrow pinning a target, chains of force"),
              ("W", "Volley", "a rain of black arrows falling in an arc"),
              ("E", "Hunter's Stride", "a dark uruk silhouette sprinting with red motion streaks"),
              ("R", "Uruk Ambush", "four uruk-hai bursting from the ground, white hand on their faces")],
}

# troops: faction -> list of (id, name, game class, subject)
TROOPS = {
    "gondor": [
        ("infantry", "Gondor Soldier", "infantry", "a Gondor footsoldier: tall winged-crest steel helmet, black surcoat with the white tree over mail, kite shield, sword"),
        ("archer", "Gondor Archer", "archer", "a Gondor archer: light steel cap, black-and-silver padded tunic, longbow, quiver"),
        ("rider", "Knight of Dol Amroth (rider only)", "rider", "a Knight of Dol Amroth seated in a riding pose (legs apart as if on a horse, no horse shown): blue-and-silver plate, swan-wing helmet, lance"),
        ("special", "Ranger of Ithilien", "special", "a Ranger of Ithilien: green-brown hooded camouflage cloak, face scarf, longbow"),
        ("villager", "Gondor Townsfolk (worker)", "villager", "a Gondor commoner worker: simple grey-blue tunic, leather apron, rolled sleeves, carrying a woodcutter's axe"),
    ],
    "rohan": [
        ("infantry", "Rohan Spearman", "infantry", "a Rohan spearman: round helmet with nose guard, green cloak, leather and mail, round wooden shield with a horse, long spear"),
        ("archer", "Westfold Bowman", "archer", "a Westfold bowman: leather cap, green-and-brown tunic, wooden longbow, quiver"),
        ("rider", "Rohirrim (rider only)", "rider", "a Rohirrim rider seated in a riding pose (no horse shown): horse-hair plumed helmet, scale mail, green cloak, spear and round shield"),
        ("heavy", "Royal Guard (rider only)", "heavy", "a Rohan Royal Guard rider seated in a riding pose (no horse shown): gold-trimmed heavy armour, tall gold helmet with long plume, green cloak, sword and shield"),
        ("special", "Horse Archer (rider only)", "special", "a Rohan horse archer seated in a riding pose (no horse shown): light leather armour, short recurve bow drawn, quiver"),
        ("villager", "Rohan Farmer (worker)", "villager", "a Rohan farmer worker: straw-coloured tunic, brown cloak, braided blond hair, carrying a pickaxe"),
    ],
    "mordor": [
        ("infantry", "Orc Warrior", "infantry", "a Mordor orc warrior: hunched, grey-green skin, crude black iron helmet, scrap-metal armour, jagged scimitar, crude round shield"),
        ("archer", "Orc Archer", "archer", "a Mordor orc archer: hunched, grey-green skin, leather hood, short black bow, quiver of crude arrows"),
        ("rider", "Warg Rider (rider only)", "rider", "a Mordor orc warg rider seated in a riding pose (no warg shown): spiked shoulder pads, curved blade, crude spear"),
        ("heavy", "Mountain Troll", "heavy", "a Mordor mountain troll: huge grey stone-like skin, small head, iron plates bolted on, chains, enormous stone club (creature turnaround)"),
        ("villager", "Orc Slave (worker)", "villager", "a Mordor orc slave worker: thin, chained ankle, ragged loincloth and sack tunic, carrying a pickaxe"),
    ],
    "isengard": [
        ("infantry", "Uruk-hai Pikeman", "infantry", "an Uruk-hai pikeman: tall, dark skin, black helmet with a face guard, black plate armour, white hand on the chest, long pike"),
        ("archer", "Uruk Crossbowman", "archer", "an Uruk-hai crossbowman: black half-helm, black leather and plate, heavy black crossbow"),
        ("rider", "Wolf Rider (rider only)", "rider", "an Isengard orc wolf rider seated in a riding pose (no wolf shown): black leather, white hand on the shoulder, curved sword"),
        ("special", "Berserker Sapper", "special", "an Uruk-hai berserker sapper: bare chest smeared with white hand prints, wild black hair, carrying a lit torch and a heavy black powder keg strapped to his back"),
        ("villager", "Dunlending Labourer (worker)", "villager", "a Dunlending labourer: wild hair, fur and rough wool clothes, soot-stained, carrying a woodcutter's axe"),
    ],
}

MOUNTS = [
    ("mount_gondor_horse", "Gondor warhorse", "a tall grey-white warhorse with blue-and-silver barding and a saddle (no rider)"),
    ("mount_rohan_horse", "Rohan horse", "a sturdy chestnut horse with a long flowing pale mane, green-and-gold saddle cloth (no rider)"),
    ("mount_warg", "Warg (Mordor and Isengard)", "a huge wolf-like warg with a hyena-like sloped back, matted dark fur, crude saddle (no rider)"),
]

SIEGE = [
    ("siege_gondor_trebuchet", "Gondor Trebuchet", "gondor", "a wheeled Gondor trebuchet: pale wood frame with steel fittings, long throwing arm, stone counterweight, blue banner"),
    ("siege_mordor_grond", "Grond (battering ram)", "mordor", "Grond, the colossal battering ram of Mordor: a huge black iron ram shaped like a snarling wolf head, glowing with fire, on a giant wheeled frame with chains"),
    ("siege_isengard_ram", "Isengard Battering Ram", "isengard", "an Isengard covered battering ram: black wooden frame with an iron-capped log, sloped roof with a white hand painted on it, wheels"),
    ("summon_army_of_dead", "Army of the Dead warrior", "wild", "a translucent ghostly green dead warrior: skeletal face under a broken helmet, ancient rotted armour, sword, glowing pale green"),
]

CREATURES = [
    ("creature_spider", "Mirkwood Spider (jungle)", "a large black-and-brown Mirkwood spider the size of a pony, hairy jointed legs, glowing eyes, dripping fangs"),
    ("creature_warg", "Wild Warg (jungle)", "a wild warg with no saddle: huge wolf, matted grey-black fur, scarred snout, bared fangs"),
    ("creature_cave_troll", "Cave Troll (boss)", "the Cave Troll boss: massive grey-blue troll with thick hide, chains on the wrists, a crude iron collar, small yellow eyes, huge wooden club"),
]

BUILDINGS = [  # key, name, description template keyed by faction
    ("town_center", "Town Center", {
        "gondor": "a white stone citadel keep with tiered towers, battlements and a tall blue banner with the white tree",
        "rohan": "a great wooden longhall on a raised stone base, golden thatched roof with crossed horse-head gables",
        "mordor": "a black iron and basalt fortress keep with jagged spikes and a burning red eye beacon on top",
        "isengard": "a black stone tower keep with sharp horn-like spires and forge chimneys glowing orange"}),
    ("village_house", "Village House", {
        "gondor": "a small white stone house with a dark slate roof and a blue door",
        "rohan": "a small timber cottage with a steep thatched roof and carved horse gable",
        "mordor": "a crude orc hut of black stone and scrap iron with a hide roof",
        "isengard": "a soot-stained timber-and-iron worker hut with a smoking chimney"}),
    ("watchtower", "Watchtower", {
        "gondor": "a tall slender white stone watchtower with a conical blue roof and arrow slits",
        "rohan": "a tall wooden palisade watchtower with a lookout platform and green banner",
        "mordor": "a jagged black iron watchtower with spikes and a red brazier at the top",
        "isengard": "a black timber and iron watchtower with an orange forge brazier"}),
    ("barracks", "Barracks (infantry)", {
        "gondor": "a white stone barracks hall with weapon racks and shields along the wall",
        "rohan": "a long wooden mead-hall barracks with spear racks and round shields on the walls",
        "mordor": "a crude black stone orc pit barracks with spikes, drums and weapon heaps",
        "isengard": "an Uruk-hai spawning barracks: dark iron hall with mud pits and white hand banners"}),
    ("archery_range", "Archery Range", {
        "gondor": "a stone-walled archery yard with straw targets and a small roofed shelter",
        "rohan": "a wooden archery yard with straw targets and a thatched shelter",
        "mordor": "a crude orc archery pit with target posts made of shields and bones",
        "isengard": "an Isengard crossbow range with iron target dummies and a black shed"}),
    ("stables", "Stables (riders)", {
        "gondor": "white stone stables with dark slate roof and blue-trimmed stall doors",
        "rohan": "large timber horse stables with a golden thatched roof and horse-head carvings",
        "mordor": "a black warg pen with iron cages, bones and chains",
        "isengard": "a wolf kennel of black timber and iron bars"}),
    ("storehouse", "Storehouse", {
        "gondor": "a stone granary-warehouse with stacked crates, barrels and sacks",
        "rohan": "a wooden barn with hay bales, barrels and sacks",
        "mordor": "a black iron loot depot heaped with crates, ore and scrap",
        "isengard": "an industrial timber storehouse with stacked lumber and ore carts"}),
    ("blacksmith", "Blacksmith", {
        "gondor": "a stone forge with a glowing furnace, anvil and racks of fine swords",
        "rohan": "a timber smithy with an open forge, anvil and horseshoes on the wall",
        "mordor": "a black iron orc forge with lava-red glow and crude weapons",
        "isengard": "a roaring Isengard forge with huge bellows and molten metal channels"}),
    ("siege_works", "Siege Works (Age III)", {
        "gondor": "a stone-and-timber workshop yard with a half-built trebuchet and crane",
        "rohan": "a timber workshop yard building armoured royal wagons and crane",
        "mordor": "a troll pen and siege yard with chains, cages and a half-built ram",
        "isengard": "a smoking siege workshop with a half-built battering ram and black-powder kegs"}),
    ("special_building", "Faction special building (Age III)", {
        "gondor": "Henneth Annûn, the Ranger Hideout: a hidden stone grotto behind a small waterfall with green banners",
        "rohan": "Meduseld, the Golden Hall: a grand golden-roofed royal hall on a stone terrace with gold pillars",
        "mordor": "the Black Gate Forge: a huge black iron gate-forge with glowing red furnaces and troll chains",
        "isengard": "the Orthanc Furnace: a smaller black spiked tower over a fiery pit with gears and chains"}),
]

PROPS = [
    ("prop_tree_pine", "Pine tree", "a tall low-poly pine tree with layered dark-green cone tiers"),
    ("prop_tree_oak", "Oak tree", "a broad low-poly oak tree with a round faceted green canopy"),
    ("prop_tree_dead", "Dead tree", "a bare twisted dead tree with grey bark"),
    ("prop_tree_mallorn", "Golden mallorn tree", "a tall silver-barked tree with golden leaves (accent tree for map variety)"),
    ("prop_forest_cluster", "Forest cluster (wood resource)", "a dense cluster of five pine and oak trees, one stump with an axe in it, woodcutting spot"),
    ("prop_rock_small", "Small boulders", "a cluster of three grey faceted boulders"),
    ("prop_rock_large", "Large rock outcrop", "a big grey faceted rock outcrop with moss patches"),
    ("prop_cliff", "Cliff wall piece", "a straight section of grey faceted cliff wall with grass on top, used to frame paths"),
    ("prop_mountain", "Mountain (map border)", "a large snow-capped grey low-poly mountain peak"),
    ("prop_quarry", "Stone quarry (resource)", "an open stone quarry: cut grey stone blocks, rubble and a wooden crane"),
    ("prop_iron_mine", "Iron mine (resource)", "a mine entrance in a rocky hillside with dark iron ore veins, wooden supports and an ore cart"),
    ("prop_game_herd", "Game herd (food resource)", "a small herd of three low-poly deer grazing"),
    ("prop_farm_field", "Farm field (food)", "a square wheat field with golden crops and a wooden fence"),
    ("prop_bush", "Bushes", "a cluster of round faceted green bushes with a few flowers"),
    ("prop_grass_tufts", "Grass tufts", "a cluster of tall faceted grass tufts and reeds"),
    ("prop_ruins", "Ancient ruins", "broken grey stone columns and a fallen arch, Númenórean ruins"),
    ("prop_bridge", "Stone bridge", "a short arched stone bridge over a narrow stream"),
    ("prop_lane_marker", "Lane waystone", "a carved standing stone waymarker with a small faction-neutral rune"),
    ("prop_spider_camp", "Spider camp dressing", "thick white cobwebs strung between dead trees, cocooned bundles and bones on the ground"),
    ("prop_warg_den", "Warg den dressing", "a rocky den entrance with gnawed bones and claw marks"),
    ("prop_troll_lair", "Cave Troll lair", "a large rocky cave mouth with broken weapons, bones and a crude stone throne"),
    ("prop_rubble", "Building rubble", "a heap of collapsed stone, broken beams and smoke"),
    ("prop_scaffold", "Construction scaffold", "wooden scaffolding with ropes, planks and a pile of materials around a half-built foundation"),
    ("prop_banner_set", "Faction banners", "four tall banner poles side by side: white tree on black, white horse on green, red eye on black, white hand on black"),
]

TEXTURES = [
    ("tex_grass", "Grass ground", "lush meadow green grass with slightly lighter and darker green patches"),
    ("tex_dirt_road", "Dirt road", "packed light-brown dirt road with small pebbles"),
    ("tex_stone_road", "Paved road (bases)", "worn grey flagstone paving"),
    ("tex_base_gondor", "Gondor base ground", "pale grey-white stone plaza tiles"),
    ("tex_base_rohan", "Rohan base ground", "golden-green grass with hay and dirt"),
    ("tex_base_mordor", "Mordor base ground", "black ash, cracked dark rock and faint red embers"),
    ("tex_base_isengard", "Isengard base ground", "churned dark mud, soot and gravel"),
    ("tex_jungle_floor", "Jungle floor", "dark moss, roots and fallen leaves, slightly purple shadows"),
]

ITEMS = [
    ("lembas", "Lembas Bread", "a square of elven waybread wrapped in a green mallorn leaf, tied with a silver thread"),
    ("athelas", "Athelas", "a sprig of kingsfoil herb with long green leaves and a faint healing glow"),
    ("horse_rohan", "Steed of Rohan", "a horseshoe with a small green-and-gold ribbon, speed lines"),
    ("elven_blade", "Elven Blade", "a slender curved elven sword with a leaf-shaped blade"),
    ("dwarf_mail", "Dwarven Mail", "a sturdy shirt of dwarven chain mail with bronze trim"),
    ("ring_barahir", "Ring of Barahir", "a silver ring of two entwined serpents with green emerald eyes"),
    ("horn_mark", "Horn of the Mark", "a curved ivory war horn with gold bands and a green cord"),
    ("phial", "Phial of Galadriel", "a small crystal phial glowing with bright white starlight"),
    ("westernesse", "Blade of Westernesse", "an ancient long dagger with red-gold runes along the blade"),
    ("mithril", "Mithril Coat", "a gleaming silver-white mithril mail shirt that shines like starlight"),
]

RESOURCES = [
    ("food", "Food", "a loaf of bread, a wheel of cheese and a haunch of meat"),
    ("wood", "Wood", "a stack of three cut logs"),
    ("stone", "Stone", "two cut grey stone blocks"),
    ("iron", "Iron", "a dark iron ingot with ore chunks"),
    ("gold", "Gold", "a small pile of gold coins with a gold bar"),
]

UPGRADES = [
    ("forged_blades", "Forged Blades", "a glowing hot sword blade on an anvil with sparks"),
    ("plated_armour", "Plated Armour", "a polished steel breastplate with rivets"),
    ("war_drills", "War Drills", "a row of three crossed spears behind a drum"),
    ("master_smiths", "Master Smiths", "a master smith's hammer crossed with a gleaming sword, golden glow"),
]

CLASSES = [
    ("infantry", "Infantry", "a crossed sword and shield"),
    ("archer", "Archer", "a drawn bow with an arrow"),
    ("rider", "Riders", "a horse head with a spear"),
    ("heavy", "Heavy / siege", "a battering ram head / boulder"),
    ("special", "Special", "a star-shaped faction badge with a gem"),
    ("villager", "Villager", "a crossed axe and pickaxe"),
    ("hero", "Hero", "a crown over a sword"),
]

STATUS = [
    ("stun", "Stunned", "yellow spinning stars", "yellow"),
    ("root", "Rooted", "green vines wrapped around a boot", "green"),
    ("slow", "Slowed", "a blue snail shell / heavy blue chains", "icy blue"),
    ("weaken", "Weakened", "a cracked sword", "purple"),
    ("haste", "Hasted", "a winged boot with speed lines", "white-gold"),
    ("damage_up", "Empowered", "a sword with an upward arrow", "red-orange"),
    ("armor_up", "Fortified", "a glowing shield", "steel blue"),
    ("troll_slayer", "Troll-slayer buff", "a broken troll club", "gold"),
    ("recall", "Recalling", "a swirling portal ring", "cyan"),
]

MAP_ICONS = [
    ("map_town_center", "Town Center (minimap)", "a castle silhouette"),
    ("map_tower", "Tower (minimap)", "a tower silhouette"),
    ("map_camp", "Jungle camp (minimap)", "a claw mark"),
    ("map_boss", "Cave Troll (minimap)", "a troll skull"),
    ("map_ping", "Ping 'look here'", "an exclamation mark inside a ring"),
    ("map_danger", "Ping 'danger'", "a skull inside a warning triangle"),
]

UI = [
    ("ui_hero_panel", "Hero panel frame", "a wide horizontal panel frame (about 6:1) for the bottom-centre hero bar: stone base, gold filigree top edge, a small laurel crest at the top centre"),
    ("ui_ability_slot", "Ability slot frame", "a square ability slot frame with thick bevelled gold border, empty dark centre, 1:1"),
    ("ui_ability_slot_ult", "Ultimate slot frame", "a square ability slot frame, more ornate than normal, with small wings and a gem at the top, 1:1"),
    ("ui_item_slot", "Item slot frame", "a small square item slot with a simpler bronze border, 1:1"),
    ("ui_side_panel", "Base panel (tall)", "a tall vertical panel frame (about 1:2) for the right-side base panel, with a header plate at the top"),
    ("ui_tab", "Tab button", "a horizontal tab button shape (about 4:1), slightly tapered sides; show normal, hover and selected states stacked vertically"),
    ("ui_button", "Main button", "a wide button (about 5:1) with pointed ends; show normal, hover, pressed and disabled states stacked vertically"),
    ("ui_resource_bar", "Top resource bar", "a long thin top-bar frame (about 10:1) with five empty circular sockets for resource icons"),
    ("ui_minimap_frame", "Minimap frame", "a square minimap frame with thick carved corners and a compass rose on one corner, empty centre, 1:1"),
    ("ui_tooltip", "Tooltip box", "a small dark parchment-and-stone tooltip box with thin gold border, empty"),
    ("ui_health_bar", "Unit health bar frame", "a thin horizontal health bar frame (about 8:1) with segment tick marks, empty"),
    ("ui_portrait_frame", "Portrait frame", "a circular portrait frame with gold rim and a small level badge socket at the bottom, 1:1"),
    ("ui_toast", "Notification banner", "a horizontal scroll/banner shape for notifications (about 6:1), empty"),
    ("ui_cursor_set", "Cursor set", "a sheet of five game mouse cursors in a row on white: gauntlet pointer (normal), sword (attack), glowing rune (cast), hammer (build), crossed-out circle (invalid); each about 64x64"),
]

SCREENS = [
    ("logo", "Game logo", "the game logo: the words BATTLE EMPIRES in heavy carved gold-and-stone fantasy capital letters, a sword standing behind the lettering and a thin golden ring circling it, small faceted gems, on a plain solid black background. The text must be spelled exactly BATTLE EMPIRES and nothing else."),
    ("bg_main_menu", "Main menu background", "four armies (white-tree Gondor, horse-banner Rohan, red-eye Mordor, white-hand Isengard) facing each other across a vast valley at sunset, a lone mountain with a fiery peak in the far distance; keep the left third darker and calm for the menu buttons"),
    ("bg_lobby", "Lobby background", "a war council table seen from above with a hand-drawn map of the battlefield, candles, banners of four factions around it; keep the centre calm"),
    ("loading_gondor", "Loading screen: Gondor", "the white city of Minas Tirith tiers glowing at dawn with Gondor soldiers marching out of the gate, white tree banner"),
    ("loading_rohan", "Loading screen: Rohan", "the Rohirrim charging down a green hill at sunrise, golden hall on a hill behind them"),
    ("loading_mordor", "Loading screen: Mordor", "orc legions marching past the black gate under a red ash sky, a fiery mountain behind"),
    ("loading_isengard", "Loading screen: Isengard", "Uruk-hai pouring out of fiery forge pits at the foot of a black spiked tower"),
    ("screen_victory", "Victory banner", "a golden victory laurel wreath with crossed swords and rays of light, plain dark background; leave a wide empty ribbon in the centre for text"),
    ("screen_defeat", "Defeat banner", "a broken sword and a torn banner lying in ash and smoke, plain dark background; leave a wide empty ribbon in the centre for text"),
]
