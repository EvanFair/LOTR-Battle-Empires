extends Node
## All game balance and content lives here so tuning is a data change, not a code change.

const RESOURCES = ["food", "wood", "stone", "iron", "gold"]

var _game_time = 0.0  # seconds of simulated (unpaused) game time
const GATHERABLE = ["food", "wood", "stone", "iron"]

const STARTING_RESOURCES = {"food": 300, "wood": 300, "stone": 150, "iron": 100, "gold": 0}

# --- distances (metres) and timings (seconds) -------------------------------------------------
const COMMAND_RANGE = 15.0  # hero must be this close to order a squadron or villager group
const BUILD_RANGE = 8.0  # hero must stay this close for construction to progress
const BASE_RADIUS = 22.0  # building zone around a Town Center
const MULTI_HERO_BUILD_SPEED = 1.5
const AUTO_REPEAT_INTERVAL = 60.0
const VILLAGERS_PER_HOUSE = 5
const MAX_HOUSES = 10
const VILLAGER_RESPAWN_TIME = 45.0
const VILLAGER_RESPAWN_COST = {"food": 50}
const VILLAGER_CARRY = 10
const HAUL_LOAD = 10
const STOREHOUSE_REBUILD_COOLDOWN = 120.0
const STOREHOUSE_LOSS_FACTOR = 0.5
const CONSTRUCTION_REFUND = 0.75
const GATHER_TIME = {"food": 3.0, "wood": 3.5, "stone": 4.5, "iron": 5.0}
const SQUAD_AGGRO_RANGE = 9.0
const MANUAL_TRAIN_TIME = 15.0  # a one-off "Train" takes this long once supply is delivered
const HERO_RESPAWN_BASE = 10.0
const HERO_RESPAWN_PER_LEVEL = 3.0
const HERO_MAX_LEVEL = 10
const XP_PER_LEVEL = [0, 100, 250, 450, 700, 1000, 1350, 1750, 2200, 2700]
const XP_RADIUS = 14.0

# --- unit classes and counters ---------------------------------------------------------------
const CLASSES = ["infantry", "archer", "rider", "heavy", "special"]
const TARGET_KINDS = ["infantry", "archer", "rider", "heavy", "building", "hero", "villager"]

# attacker class -> target kind -> damage multiplier
const COUNTERS = {
	"infantry": {"infantry": 1.0, "archer": 1.2, "rider": 1.75, "heavy": 0.75, "building": 0.5},
	"archer": {"infantry": 1.5, "archer": 1.0, "rider": 0.6, "heavy": 0.5, "building": 0.25},
	"rider": {"infantry": 1.0, "archer": 1.75, "rider": 1.0, "heavy": 0.6, "building": 0.5},
	"heavy": {"infantry": 1.25, "archer": 0.75, "rider": 1.0, "heavy": 1.0, "building": 3.0},
}

# baseline stats per class; factions apply multipliers on top. "cost" is per squadron.
const CLASS_STATS = {
	"infantry":
	{
		"hp": 90, "damage": 9, "interval": 1.0, "range": 1.4, "speed": 2.6, "sight": 8.0,
		"squad_size": 8, "cost": {"food": 150, "iron": 40}, "building": "barracks",
		"radius": 0.35, "ranged": false,
	},
	"archer":
	{
		"hp": 60, "damage": 8, "interval": 1.4, "range": 7.0, "speed": 2.5, "sight": 10.0,
		"squad_size": 8, "cost": {"food": 120, "wood": 100}, "building": "archery_range",
		"radius": 0.35, "ranged": true,
	},
	"rider":
	{
		"hp": 130, "damage": 12, "interval": 1.2, "range": 1.6, "speed": 4.6, "sight": 10.0,
		"squad_size": 6, "cost": {"food": 180, "iron": 100}, "building": "stables",
		"radius": 0.55, "ranged": false,
	},
	"heavy":
	{
		"hp": 400, "damage": 30, "interval": 2.5, "range": 2.0, "speed": 1.6, "sight": 8.0,
		"squad_size": 2, "cost": {"food": 200, "wood": 250, "iron": 150}, "building": "siege_works",
		"radius": 0.85, "ranged": false,
	},
	"special":
	{
		"hp": 150, "damage": 16, "interval": 1.2, "range": 5.0, "speed": 3.2, "sight": 11.0,
		"squad_size": 4, "cost": {"food": 200, "iron": 120, "gold": 60}, "building": "special_building",
		"radius": 0.4, "ranged": true,
	},
}

# --- factions ---------------------------------------------------------------------------------
# "units": display name per class; "mods": stat multipliers per class
# "playable": false factions are planned for later milestones
const FACTIONS = {
	"gondor":
	{
		"name": "Gondor", "color": Color("d8dde6"), "side": "free", "playable": true,
		"units":
		{
			"infantry": "Gondor Soldiers", "archer": "Gondor Archers",
			"rider": "Knights of Dol Amroth", "heavy": "Trebuchet",
			"special": "Rangers of Ithilien",
		},
		"mods": {"infantry": {"hp": 1.1}},
		"heroes": ["aragorn", "boromir", "faramir"],
	},
	"rohan":
	{
		"name": "Rohan", "color": Color("3f8f3a"), "side": "free", "playable": true,
		"units":
		{
			"infantry": "Rohan Spearmen", "archer": "Westfold Bowmen", "rider": "Rohirrim",
			"heavy": "Royal Guard", "special": "Horse Archers",
		},
		"mods": {"rider": {"hp": 1.15, "damage": 1.1, "speed": 1.05}, "infantry": {"hp": 0.95}},
		"heroes": ["theoden", "eomer", "eowyn"],
	},
	"mordor":
	{
		"name": "Mordor", "color": Color("8a1c1c"), "side": "shadow", "playable": true,
		"units":
		{
			"infantry": "Orc Warriors", "archer": "Orc Archers", "rider": "Warg Riders",
			"heavy": "Mountain Trolls", "special": "Grond",
		},
		"mods":
		{
			"infantry": {"hp": 0.8, "damage": 0.85, "squad_size": 1.5, "cost": 0.7},
		},
		"heroes": ["gothmog", "witch_king", "shelob"],
	},
	"isengard":
	{
		"name": "Isengard", "color": Color("2b2b2b"), "side": "shadow", "playable": true,
		"units":
		{
			"infantry": "Uruk-hai Pikemen", "archer": "Uruk Crossbowmen", "rider": "Wolf Riders",
			"heavy": "Battering Ram", "special": "Berserker Sappers",
		},
		"mods": {"infantry": {"hp": 1.15, "damage": 1.1, "cost": 1.15}, "archer": {"damage": 1.15}},
		"heroes": ["ugluk", "saruman", "lurtz"],
	},
	"eldar":
	{
		"name": "Eldar", "color": Color("c9b458"), "side": "free", "playable": false,
		"units":
		{
			"infantry": "Lórien Swordsmen", "archer": "Galadhrim Archers",
			"rider": "Rivendell Lancers", "heavy": "Rivendell Guard", "special": "Lórien Wardens",
		},
		"mods": {}, "heroes": ["elrond", "galadriel", "legolas"],
	},
	"dwarves":
	{
		"name": "Durin's Folk", "color": Color("6b4a2b"), "side": "free", "playable": false,
		"units":
		{
			"infantry": "Iron Hills Axemen", "archer": "Dwarven Crossbowmen",
			"rider": "Boar Riders", "heavy": "Dwarven Catapult", "special": "Iron Guard Phalanx",
		},
		"mods": {}, "heroes": ["dain", "thorin", "gimli"],
	},
	"harad":
	{
		"name": "Harad & the East", "color": Color("c46a1b"), "side": "shadow", "playable": false,
		"units":
		{
			"infantry": "Easterling Spearmen", "archer": "Haradrim Archers",
			"rider": "Easterling Cavalry", "heavy": "Mûmak", "special": "Corsairs of Umbar",
		},
		"mods": {}, "heroes": ["mahud", "khamul", "suladan"],
	},
	"wild":
	{
		"name": "Guardians of the Wild", "color": Color("5a7d2a"), "side": "free",
		"playable": false,
		"units":
		{
			"infantry": "Beorning Woodmen", "archer": "Woodman Archers", "rider": "Great Bears",
			"heavy": "Ents", "special": "Great Eagles",
		},
		"mods": {}, "heroes": ["treebeard", "beorn", "gwaihir"],
	},
}

const PLAYABLE_FACTIONS = ["gondor", "rohan", "mordor", "isengard"]

# --- heroes -----------------------------------------------------------------------------------
# Ability fields (all optional except key/name/kind/cooldown/mana):
#   range, radius, distance, width ... targeting (see HeroAbilities.aim)
#   damage, stun, root, slow (speed mult) + slow_time, heal ... effects on whoever is hit
#   stat + mult + duration ......... buffs (damage | attack_speed | speed | armor)
#   unit_class, count, summon_name, duration ... summons
# Ranks: each ability has 3 ranks bought with skill points (1 per level, Ctrl+key).
# Q/W/E rank r needs hero level 2r-1; R needs level 6/8/10. Every rank past the first adds
# 30% to damage/heal/stun and takes 10% off the cooldown.
const HEROES = {
	# --- Gondor -----------------------------------------------------------------------------
	"aragorn":
	{
		"name": "Aragorn", "faction": "gondor", "role": "Fighter",
		"hp": 650, "mana": 200, "damage": 28, "interval": 1.0, "range": 1.8, "speed": 4.0,
		"sight": 12.0, "hp_per_level": 70, "damage_per_level": 4, "mana_regen": 2.0,
		"abilities":
		[
			{"key": "Q", "name": "Andúril Strike", "kind": "execute_strike", "cooldown": 8.0,
				"mana": 40, "range": 2.5, "damage": 60, "missing_hp_bonus": 0.25,
				"desc": "Strike one enemy; deals more the more wounded it is."},
			{"key": "W", "name": "For Frodo!", "kind": "rally_aura", "cooldown": 20.0,
				"mana": 60, "radius": 12.0, "duration": 8.0, "stat": "attack_speed", "mult": 1.3,
				"desc": "Nearby troops attack 30% faster."},
			{"key": "E", "name": "Ranger's Dash", "kind": "dash", "cooldown": 10.0,
				"mana": 30, "distance": 8.0, "desc": "Dash toward the cursor."},
			{"key": "R", "name": "Army of the Dead", "kind": "summon", "cooldown": 90.0,
				"mana": 120, "unit_class": "infantry", "count": 8, "duration": 15.0,
				"summon_name": "Army of the Dead", "range": 8.0,
				"desc": "Raise 8 spectral warriors for 15s."},
		],
	},
	"boromir":
	{
		"name": "Boromir", "faction": "gondor", "role": "Vanguard",
		"hp": 760, "mana": 180, "damage": 25, "interval": 1.05, "range": 1.8, "speed": 3.9,
		"sight": 11.0, "hp_per_level": 85, "damage_per_level": 3, "mana_regen": 2.0,
		"abilities":
		[
			{"key": "Q", "name": "Shield Bash", "kind": "strike", "cooldown": 9.0, "mana": 40,
				"range": 2.2, "damage": 45, "stun": 1.2, "desc": "Bash one enemy, stunning it."},
			{"key": "W", "name": "Horn of Gondor", "kind": "rally_aura", "cooldown": 24.0,
				"mana": 60, "radius": 14.0, "duration": 8.0, "stat": "damage", "mult": 1.25,
				"enemy_slow": 0.7, "desc": "Allies deal 25% more damage; nearby enemies are slowed."},
			{"key": "E", "name": "Charge", "kind": "leap", "cooldown": 12.0, "mana": 45,
				"distance": 7.0, "radius": 2.5, "damage": 40, "stun": 0.6,
				"desc": "Charge to a point, knocking down enemies where you land."},
			{"key": "R", "name": "Last Stand", "kind": "buff_self", "cooldown": 70.0, "mana": 100,
				"duration": 8.0, "buffs": {"armor": 0.45, "damage": 1.35},
				"desc": "Take 45% less damage and deal 35% more for 8s."},
		],
	},
	"faramir":
	{
		"name": "Faramir", "faction": "gondor", "role": "Ranger",
		"hp": 540, "mana": 210, "damage": 26, "interval": 1.1, "range": 7.5, "speed": 4.1,
		"sight": 13.0, "hp_per_level": 60, "damage_per_level": 4, "mana_regen": 2.4,
		"ranged": true,
		"abilities":
		[
			{"key": "Q", "name": "Volley", "kind": "ground_aoe", "cooldown": 9.0, "mana": 45,
				"range": 11.0, "radius": 3.0, "damage": 65, "slow": 0.7, "slow_time": 2.0,
				"desc": "Rain arrows on an area, slowing enemies."},
			{"key": "W", "name": "Ithilien Stealth", "kind": "buff_self", "cooldown": 18.0,
				"mana": 50, "duration": 5.0, "buffs": {"speed": 1.4, "attack_speed": 1.3},
				"desc": "Move 40% and shoot 30% faster for 5s."},
			{"key": "E", "name": "Precise Shot", "kind": "skillshot", "cooldown": 11.0,
				"mana": 50, "range": 13.0, "width": 1.0, "damage": 95, "root": 1.0,
				"desc": "A long arrow that pins the first enemy hit."},
			{"key": "R", "name": "Rangers of Ithilien", "kind": "summon", "cooldown": 85.0,
				"mana": 120, "unit_class": "special", "count": 5, "duration": 25.0,
				"summon_name": "Rangers of Ithilien", "range": 8.0,
				"desc": "Call 5 Rangers to fight for 25s."},
		],
	},
	# --- Rohan --------------------------------------------------------------------------------
	"theoden":
	{
		"name": "Théoden", "faction": "rohan", "role": "Enchanter",
		"hp": 600, "mana": 220, "damage": 24, "interval": 1.0, "range": 1.8, "speed": 4.2,
		"sight": 12.0, "hp_per_level": 65, "damage_per_level": 3, "mana_regen": 2.5,
		"abilities":
		[
			{"key": "Q", "name": "Herugrim", "kind": "nova", "cooldown": 8.0, "mana": 40,
				"radius": 3.2, "damage": 55, "desc": "A sweeping cut that hits every enemy around you."},
			{"key": "W", "name": "Arise, Riders", "kind": "heal_allies", "cooldown": 22.0,
				"mana": 70, "radius": 12.0, "heal": 90, "duration": 6.0, "stat": "attack_speed",
				"mult": 1.2, "desc": "Heal nearby allies and quicken their attacks."},
			{"key": "E", "name": "Snowmane", "kind": "buff_self", "cooldown": 14.0, "mana": 35,
				"duration": 4.0, "buffs": {"speed": 1.6}, "desc": "Ride hard: 60% faster for 4s."},
			{"key": "R", "name": "Ride of the Rohirrim", "kind": "team_haste",
				"cooldown": 80.0, "mana": 120, "radius": 30.0, "duration": 10.0, "speed": 1.5,
				"desc": "Every ally nearby moves 50% faster and shrugs off roots."},
		],
	},
	"eomer":
	{
		"name": "Éomer", "faction": "rohan", "role": "Fighter",
		"hp": 640, "mana": 190, "damage": 27, "interval": 1.0, "range": 1.9, "speed": 4.3,
		"sight": 12.0, "hp_per_level": 72, "damage_per_level": 4, "mana_regen": 2.0,
		"abilities":
		[
			{"key": "Q", "name": "Spear Throw", "kind": "skillshot", "cooldown": 8.0, "mana": 40,
				"range": 10.0, "width": 1.0, "damage": 75, "slow": 0.6, "slow_time": 2.0,
				"desc": "Hurl a spear; the first enemy hit is slowed."},
			{"key": "W", "name": "Riders of the Mark", "kind": "summon", "cooldown": 45.0,
				"mana": 80, "unit_class": "rider", "count": 4, "duration": 20.0,
				"summon_name": "Riders of the Mark", "range": 8.0,
				"desc": "Summon 4 Rohirrim for 20s."},
			{"key": "E", "name": "Charge", "kind": "leap", "cooldown": 11.0, "mana": 45,
				"distance": 8.0, "radius": 2.5, "damage": 45, "stun": 0.5,
				"desc": "Charge to a point, knocking down enemies where you land."},
			{"key": "R", "name": "Death!", "kind": "rally_aura", "cooldown": 75.0, "mana": 110,
				"radius": 18.0, "duration": 10.0, "stat": "damage", "mult": 1.35,
				"heroes_too": true, "desc": "Every ally nearby deals 35% more damage for 10s."},
		],
	},
	"eowyn":
	{
		"name": "Éowyn", "faction": "rohan", "role": "Assassin",
		"hp": 560, "mana": 180, "damage": 29, "interval": 0.9, "range": 1.7, "speed": 4.3,
		"sight": 12.0, "hp_per_level": 62, "damage_per_level": 5, "mana_regen": 2.0,
		"abilities":
		[
			{"key": "Q", "name": "Shieldmaiden", "kind": "execute_strike", "cooldown": 7.0,
				"mana": 35, "range": 2.2, "damage": 50, "missing_hp_bonus": 0.2,
				"desc": "A quick strike; deals more to wounded enemies."},
			{"key": "W", "name": "Shield Wall", "kind": "buff_self", "cooldown": 16.0,
				"mana": 40, "duration": 4.0, "buffs": {"armor": 0.4},
				"desc": "Take 40% less damage for 4s."},
			{"key": "E", "name": "Dernhelm", "kind": "dash", "cooldown": 9.0, "mana": 30,
				"distance": 7.0, "desc": "Dash toward the cursor."},
			{"key": "R", "name": "I Am No Man", "kind": "strike", "cooldown": 70.0, "mana": 100,
				"range": 2.5, "damage": 190, "stun": 1.8, "hero_bonus": 1.5,
				"desc": "A mighty blow: huge damage and a long stun, +50% against heroes."},
		],
	},
	# --- Mordor -------------------------------------------------------------------------------
	"gothmog":
	{
		"name": "Gothmog", "faction": "mordor", "role": "Vanguard",
		"hp": 780, "mana": 180, "damage": 24, "interval": 1.1, "range": 1.8, "speed": 3.8,
		"sight": 11.0, "hp_per_level": 90, "damage_per_level": 3, "mana_regen": 2.0,
		"abilities":
		[
			{"key": "Q", "name": "Cleave", "kind": "nova", "cooldown": 8.0, "mana": 35,
				"radius": 3.0, "damage": 50, "desc": "Hit every enemy around you."},
			{"key": "W", "name": "Warg Pack", "kind": "summon", "cooldown": 45.0, "mana": 80,
				"unit_class": "rider", "count": 4, "duration": 20.0, "summon_name": "Wargs",
				"range": 8.0, "desc": "Loose 4 wargs for 20s."},
			{"key": "E", "name": "The Age of Men Is Over", "kind": "rally_aura", "cooldown": 22.0,
				"mana": 60, "radius": 14.0, "duration": 8.0, "stat": "attack_speed", "mult": 1.35,
				"desc": "Nearby orcs attack 35% faster."},
			{"key": "R", "name": "Siege Fury", "kind": "rally_aura", "cooldown": 80.0, "mana": 110,
				"radius": 22.0, "duration": 12.0, "stat": "damage", "mult": 1.4,
				"heroes_too": true, "desc": "Allies nearby deal 40% more damage for 12s."},
		],
	},
	"witch_king":
	{
		"name": "Witch-king", "faction": "mordor", "role": "Enchanter",
		"hp": 600, "mana": 240, "damage": 27, "interval": 1.1, "range": 1.9, "speed": 4.0,
		"sight": 13.0, "hp_per_level": 68, "damage_per_level": 4, "mana_regen": 2.6,
		"abilities":
		[
			{"key": "Q", "name": "Morgul Blade", "kind": "strike", "cooldown": 8.0, "mana": 45,
				"range": 2.4, "damage": 60, "slow": 0.55, "slow_time": 3.0,
				"desc": "A cursed wound: damage and a heavy slow."},
			{"key": "W", "name": "Black Breath", "kind": "nova", "cooldown": 14.0, "mana": 60,
				"radius": 6.0, "damage": 40, "slow": 0.6, "slow_time": 3.0, "weaken": 0.75,
				"desc": "Enemies around you are slowed and deal 25% less damage."},
			{"key": "E", "name": "Fell Beast", "kind": "leap", "cooldown": 14.0, "mana": 50,
				"distance": 11.0, "radius": 2.5, "damage": 35,
				"desc": "Swoop to a distant point on your fell beast."},
			{"key": "R", "name": "Dread Shriek", "kind": "nova", "cooldown": 80.0, "mana": 130,
				"radius": 14.0, "damage": 70, "stun": 1.6, "weaken": 0.6, "slow_time": 6.0,
				"desc": "Every enemy in a wide area is stunned and weakened."},
		],
	},
	"shelob":
	{
		"name": "Shelob", "faction": "mordor", "role": "Diver",
		"hp": 700, "mana": 170, "damage": 30, "interval": 1.0, "range": 1.9, "speed": 4.4,
		"sight": 11.0, "hp_per_level": 78, "damage_per_level": 5, "mana_regen": 2.0,
		"abilities":
		[
			{"key": "Q", "name": "Sting", "kind": "strike", "cooldown": 9.0, "mana": 40,
				"range": 2.4, "damage": 55, "stun": 1.3, "desc": "Paralysing sting: damage and a stun."},
			{"key": "W", "name": "Web", "kind": "ground_aoe", "cooldown": 13.0, "mana": 50,
				"range": 9.0, "radius": 3.0, "damage": 20, "root": 2.2,
				"desc": "Throw a web that roots everything in it."},
			{"key": "E", "name": "Lurk", "kind": "leap", "cooldown": 11.0, "mana": 40,
				"distance": 9.0, "radius": 2.0, "damage": 30, "desc": "Pounce from the shadows."},
			{"key": "R", "name": "Feast", "kind": "buff_self", "cooldown": 75.0, "mana": 100,
				"duration": 8.0, "buffs": {"damage": 1.5, "attack_speed": 1.4}, "heal": 220,
				"desc": "Heal and attack far harder for 8s."},
		],
	},
	# --- Isengard -----------------------------------------------------------------------------
	"ugluk":
	{
		"name": "Uglúk", "faction": "isengard", "role": "Vanguard",
		"hp": 770, "mana": 170, "damage": 26, "interval": 1.05, "range": 1.8, "speed": 3.9,
		"sight": 11.0, "hp_per_level": 88, "damage_per_level": 3, "mana_regen": 2.0,
		"abilities":
		[
			{"key": "Q", "name": "Cleave", "kind": "nova", "cooldown": 8.0, "mana": 35,
				"radius": 3.0, "damage": 50, "desc": "Hit every enemy around you."},
			{"key": "W", "name": "Bloodlust", "kind": "buff_self", "cooldown": 16.0, "mana": 45,
				"duration": 6.0, "buffs": {"attack_speed": 1.5}, "desc": "Attack 50% faster for 6s."},
			{"key": "E", "name": "Leap", "kind": "leap", "cooldown": 11.0, "mana": 40,
				"distance": 7.0, "radius": 2.5, "damage": 40, "stun": 0.5,
				"desc": "Leap onto enemies."},
			{"key": "R", "name": "Uruk Charge", "kind": "team_haste", "cooldown": 75.0,
				"mana": 110, "radius": 20.0, "duration": 10.0, "speed": 1.35,
				"damage_mult": 1.25, "desc": "Allies nearby run 35% faster and hit 25% harder."},
		],
	},
	"saruman":
	{
		"name": "Saruman", "faction": "isengard", "role": "Caster",
		"hp": 520, "mana": 260, "damage": 24, "interval": 1.2, "range": 7.0, "speed": 3.9,
		"sight": 13.0, "hp_per_level": 55, "damage_per_level": 4, "mana_regen": 3.0,
		"ranged": true,
		"abilities":
		[
			{"key": "Q", "name": "Fireball", "kind": "ground_aoe", "cooldown": 7.0, "mana": 45,
				"range": 12.0, "radius": 2.5, "damage": 85, "fx": "blast",
				"desc": "Hurl fire at an area."},
			{"key": "W", "name": "Voice of Saruman", "kind": "nova", "cooldown": 16.0, "mana": 60,
				"radius": 7.0, "damage": 20, "stun": 1.4, "desc": "Enemies around you are spellbound."},
			{"key": "E", "name": "Staff Blast", "kind": "skillshot", "cooldown": 9.0, "mana": 45,
				"range": 11.0, "width": 1.4, "damage": 70, "pierce": true,
				"desc": "A bolt that hits every enemy in a line."},
			{"key": "R", "name": "Fire of Orthanc", "kind": "ground_aoe", "cooldown": 80.0,
				"mana": 140, "range": 14.0, "radius": 5.0, "damage": 240, "building_mult": 2.0,
				"fx": "blast", "desc": "A huge blast that also wrecks buildings."},
		],
	},
	"lurtz":
	{
		"name": "Lurtz", "faction": "isengard", "role": "Diver",
		"hp": 560, "mana": 180, "damage": 30, "interval": 1.2, "range": 7.0, "speed": 4.1,
		"sight": 12.0, "hp_per_level": 60, "damage_per_level": 5, "mana_regen": 2.0,
		"ranged": true,
		"abilities":
		[
			{"key": "Q", "name": "Heavy Arrow", "kind": "pin_shot", "cooldown": 10.0,
				"mana": 50, "range": 10.0, "damage": 80, "root": 2.0,
				"desc": "Pin one enemy in place."},
			{"key": "W", "name": "Volley", "kind": "ground_aoe", "cooldown": 10.0, "mana": 45,
				"range": 11.0, "radius": 3.0, "damage": 60, "desc": "Rain arrows on an area."},
			{"key": "E", "name": "Hunter's Stride", "kind": "dash", "cooldown": 10.0, "mana": 30,
				"distance": 7.0, "desc": "Dash toward the cursor."},
			{"key": "R", "name": "Uruk Ambush", "kind": "summon", "cooldown": 85.0, "mana": 120,
				"unit_class": "infantry", "count": 6, "duration": 22.0, "summon_name": "Uruk-hai",
				"range": 8.0, "desc": "Six Uruk-hai join the fight for 22s."},
		],
	},
}

# --- buildings and ages -----------------------------------------------------------------------
# size: footprint radius (m). base_only: must be placed inside your base zone.
const BUILDINGS = {
	"town_center":
	{
		"name": "Town Center", "hp": 3000, "cost": {}, "build_time": 0.0, "age": 1,
		"size": 3.0, "sight": 14.0, "attack": {"damage": 12, "interval": 1.5, "range": 9.0},
		"buildable": false,
	},
	"village_house":
	{
		"name": "Village House", "hp": 400, "cost": {"wood": 50}, "build_time": 30.0, "age": 1,
		"size": 1.6, "sight": 6.0, "base_only": true,
	},
	"watchtower":
	{
		"name": "Watchtower", "hp": 700, "cost": {"wood": 50, "stone": 125}, "build_time": 120.0,
		"age": 1, "size": 1.2, "sight": 13.0, "base_only": false,
		"attack": {"damage": 10, "interval": 1.5, "range": 10.0},
	},
	"barracks":
	{
		"name": "Barracks", "hp": 1200, "cost": {"wood": 150, "stone": 50}, "build_time": 90.0,
		"age": 1, "size": 2.6, "sight": 8.0, "base_only": true, "trains": "infantry",
	},
	"archery_range":
	{
		"name": "Archery Range", "hp": 1100, "cost": {"wood": 175}, "build_time": 105.0,
		"age": 2, "size": 2.6, "sight": 8.0, "base_only": true, "trains": "archer",
	},
	"stables":
	{
		"name": "Stables", "hp": 1100, "cost": {"wood": 175, "stone": 25}, "build_time": 105.0,
		"age": 2, "size": 2.6, "sight": 8.0, "base_only": true, "trains": "rider",
	},
	"storehouse":
	{
		"name": "Storehouse", "hp": 900, "cost": {"wood": 100, "stone": 75}, "build_time": 60.0,
		"age": 2, "size": 2.0, "sight": 7.0, "base_only": true, "max": 1,
	},
	"blacksmith":
	{
		"name": "Blacksmith", "hp": 900, "cost": {"wood": 125, "stone": 75}, "build_time": 75.0,
		"age": 2, "size": 2.0, "sight": 7.0, "base_only": true, "max": 1, "researches": true,
	},
	"siege_works":
	{
		"name": "Siege Works", "hp": 1300, "cost": {"wood": 250, "stone": 100, "iron": 50},
		"build_time": 150.0, "age": 3, "size": 2.8, "sight": 8.0, "base_only": true,
		"trains": "heavy",
	},
	"special_building":
	{
		"name": "Special", "hp": 1400, "cost": {"wood": 200, "stone": 150, "gold": 50},
		"build_time": 180.0, "age": 3, "size": 2.6, "sight": 9.0, "base_only": true,
		"trains": "special", "max": 1,
	},
}

# per-faction names for the faction special building
const SPECIAL_BUILDING_NAMES = {
	"gondor": "Ranger Hideout", "rohan": "Meduseld", "mordor": "Black Gate Forge",
	"isengard": "Orthanc Furnace", "eldar": "Mallorn Grove", "dwarves": "Great Forge",
	"harad": "Umbar Docks", "wild": "Eyrie",
}

# heavy and special units differ a lot between factions, so they override the class baseline.
# "counter_as": which column of the counter table they attack with.
# "siege": prefers buildings when choosing targets. "explode": dies dealing its damage once.
const UNIT_OVERRIDES = {
	"gondor":
	{
		"heavy": {"hp": 260, "damage": 70, "interval": 4.0, "range": 14.0, "speed": 1.3,
			"ranged": true, "siege": true, "squad_size": 2, "counter_as": "heavy", "radius": 1.0},
		"special": {"hp": 110, "damage": 15, "interval": 1.2, "range": 9.5, "speed": 3.0,
			"ranged": true, "squad_size": 5, "counter_as": "archer", "sight": 13.0},
	},
	"rohan":
	{
		"heavy": {"hp": 320, "damage": 26, "interval": 1.4, "range": 1.8, "speed": 4.0,
			"ranged": false, "squad_size": 4, "counter_as": "rider", "armor": 0.25, "radius": 0.55},
		"special": {"hp": 120, "damage": 11, "interval": 1.3, "range": 7.0, "speed": 4.6,
			"ranged": true, "squad_size": 5, "counter_as": "archer", "radius": 0.55},
	},
	"mordor":
	{
		"heavy": {"hp": 650, "damage": 42, "interval": 2.2, "range": 2.2, "speed": 2.0,
			"ranged": false, "squad_size": 2, "counter_as": "heavy", "armor": 0.15},
		"special": {"hp": 1600, "damage": 220, "interval": 5.0, "range": 2.6, "speed": 1.1,
			"ranged": false, "siege": true, "squad_size": 1, "counter_as": "heavy",
			"armor": 0.35, "radius": 1.6},
	},
	"isengard":
	{
		"heavy": {"hp": 520, "damage": 90, "interval": 3.5, "range": 2.0, "speed": 1.4,
			"ranged": false, "siege": true, "squad_size": 1, "counter_as": "heavy",
			"armor": 0.3, "radius": 1.0},
		"special": {"hp": 140, "damage": 320, "interval": 1.0, "range": 1.8, "speed": 3.4,
			"ranged": false, "siege": true, "explode": true, "squad_size": 3,
			"counter_as": "heavy"},
	},
}

# Blacksmith research. Applies to squadrons trained after it finishes.
const UPGRADES = {
	"forged_blades": {"name": "Forged Blades", "desc": "+15% damage for all troops",
		"cost": {"iron": 150, "gold": 30}, "time": 45.0, "age": 2},
	"plated_armour": {"name": "Plated Armour", "desc": "Troops take 12% less damage",
		"cost": {"iron": 200, "gold": 40}, "time": 50.0, "age": 2},
	"war_drills": {"name": "War Drills", "desc": "+2 soldiers in infantry and archer squadrons",
		"cost": {"food": 300, "gold": 60}, "time": 60.0, "age": 3},
	"master_smiths": {"name": "Master Smiths", "desc": "+15% damage and +10% HP for all troops",
		"cost": {"iron": 350, "gold": 120}, "time": 75.0, "age": 3},
}

const BUILD_MENU = [
	"village_house", "barracks", "archery_range", "stables", "storehouse", "blacksmith",
	"siege_works", "special_building", "watchtower",
]

const AGES = {
	2: {"name": "Kingdom", "cost": {"food": 400, "wood": 200, "stone": 100}, "time": 60.0},
	3: {"name": "Empire", "cost": {"food": 800, "stone": 300, "iron": 300, "gold": 100},
		"time": 90.0},
}
const AGE_NAMES = {1: "Settlement", 2: "Kingdom", 3: "Empire"}

const VILLAGER_STATS = {
	"hp": 40, "damage": 3, "interval": 1.5, "range": 1.2, "speed": 2.4, "sight": 6.0,
	"radius": 0.3,
}

# --- the wild: jungle camps and the Cave Troll ---------------------------------------------------
# Creatures belong to nobody. They ignore everything until struck, then the whole camp fights
# back; dragged further than LEASH_RANGE from home they walk back and heal (MOBA leashing).
const LEASH_RANGE = 14.0
const CREATURES = {
	"spider":
	{
		"name": "Mirkwood Spider", "hp": 240, "damage": 15, "interval": 1.1, "range": 1.5,
		"speed": 3.6, "sight": 7.0, "radius": 0.6, "armor": 0.0, "gold": 22, "xp": 35,
	},
	"warg":
	{
		"name": "Wild Warg", "hp": 280, "damage": 17, "interval": 1.0, "range": 1.6,
		"speed": 4.2, "sight": 7.0, "radius": 0.55, "armor": 0.05, "gold": 24, "xp": 40,
	},
	"cave_troll":
	{
		"name": "Cave Troll", "hp": 3400, "damage": 75, "interval": 2.3, "range": 2.6,
		"speed": 2.8, "sight": 9.0, "radius": 1.3, "armor": 0.25, "gold": 160, "xp": 320,
		"team_gold": 80, "boss": true,
		# whoever slays the troll: their team's heroes and troops hit harder for a while
		"buff": {"name": "Troll-slayer", "stat": "damage", "mult": 1.2, "duration": 120.0},
	},
}
const CAMPS = {
	"spiders": {"creatures": ["spider", "spider", "spider"], "respawn": 75.0},
	"wargs": {"creatures": ["warg", "warg", "warg"], "respawn": 75.0},
	"troll": {"creatures": ["cave_troll"], "respawn": 240.0},
}

# --- the Town Center shop ---------------------------------------------------------------------------
# Heroes carry 4 items (keys 5-8). Buy and sell only inside your base. Selling refunds half.
const ITEM_SLOTS = 4
const SELL_REFUND = 0.5
const ITEMS = {
	"lembas": {"name": "Lembas Bread", "cost": 50, "consumable": true, "use": {"heal": 260},
		"desc": "Use: restore 260 health. One bite is enough to fill a grown man's stomach."},
	"athelas": {"name": "Athelas", "cost": 80, "consumable": true, "use": {"heal": 150, "mana": 120},
		"desc": "Use: restore 150 health and 120 mana."},
	"horse_rohan": {"name": "Steed of Rohan", "cost": 320, "stats": {"speed": 0.15},
		"desc": "+15% movement speed."},
	"elven_blade": {"name": "Elven Blade", "cost": 400, "stats": {"damage": 14},
		"desc": "+14 attack damage."},
	"dwarf_mail": {"name": "Dwarven Mail", "cost": 420, "stats": {"hp": 180, "armor": 0.08},
		"desc": "+180 health, take 8% less damage."},
	"ring_barahir": {"name": "Ring of Barahir", "cost": 450, "stats": {"mana": 150, "mana_regen": 2.0},
		"desc": "+150 mana, +2 mana per second."},
	"horn_mark": {"name": "Horn of the Mark", "cost": 600, "stats": {"hp": 120},
		"active": {"radius": 14.0, "stat": "speed", "mult": 1.35, "duration": 5.0, "cooldown": 45.0},
		"desc": "+120 health. Use: allies around you move 35% faster for 5s."},
	"phial": {"name": "Phial of Galadriel", "cost": 700, "stats": {"mana": 100},
		"active": {"radius": 12.0, "heal": 180, "cooldown": 60.0},
		"desc": "+100 mana. Use: a light in dark places heals allies around you by 180."},
	"westernesse": {"name": "Blade of Westernesse", "cost": 950, "stats": {"damage": 30, "attack_speed": 0.15},
		"desc": "+30 attack damage, +15% attack speed."},
	"mithril": {"name": "Mithril Coat", "cost": 1050, "stats": {"hp": 250, "armor": 0.22},
		"desc": "+250 health, take 22% less damage."},
}
const SHOP_ORDER = [
	"lembas", "athelas", "horse_rohan", "elven_blade", "dwarf_mail", "ring_barahir", "horn_mark",
	"phial", "westernesse", "mithril",
]

# --- resource nodes on the map ----------------------------------------------------------------
const RESOURCE_NODES = {
	# herds breed back: food nodes never vanish, they regrow (amount per second) up to "amount"
	"food": {"name": "Game", "amount": 800, "regrow": 1.2, "color": Color("c98b5a")},
	"wood": {"name": "Forest", "amount": 600, "color": Color("2f6b2a")},
	"stone": {"name": "Quarry", "amount": 800, "color": Color("9a9a9a")},
	"iron": {"name": "Iron Mine", "amount": 800, "color": Color("5a6573")},
}


# --- game clock -------------------------------------------------------------------------------
func _physics_process(delta):
	_game_time += delta


func now() -> float:
	"""Game time in seconds. Advances with physics, stops when paused, speeds up in tests."""
	return _game_time


func reset_clock():
	_game_time = 0.0


# --- helpers ----------------------------------------------------------------------------------
func troop_stats(faction: String, unit_class: String, upgrades = {}) -> Dictionary:
	"""Stats for one soldier of a faction's class, after faction overrides and Blacksmith upgrades.
	upgrades: the owning player's finished research (key -> true)."""
	var stats = CLASS_STATS[unit_class].duplicate(true)
	stats["armor"] = 0.0
	stats["counter_as"] = unit_class
	stats["siege"] = unit_class == "heavy"
	stats["explode"] = false
	var overrides = UNIT_OVERRIDES.get(faction, {}).get(unit_class, {})
	for stat in overrides:
		stats[stat] = overrides[stat]
	var mods = FACTIONS[faction]["mods"].get(unit_class, {})
	for stat in mods:
		if stat == "cost":
			for res in stats["cost"]:
				stats["cost"][res] = int(round(stats["cost"][res] * mods[stat]))
		elif stat == "squad_size":
			stats["squad_size"] = int(round(stats["squad_size"] * mods[stat]))
		else:
			stats[stat] = stats[stat] * mods[stat]
	if upgrades.get("forged_blades", false):
		stats["damage"] *= 1.15
	if upgrades.get("master_smiths", false):
		stats["damage"] *= 1.15
		stats["hp"] *= 1.1
	if upgrades.get("plated_armour", false):
		stats["armor"] = min(0.6, stats["armor"] + 0.12)
	if upgrades.get("war_drills", false) and unit_class in ["infantry", "archer"]:
		stats["squad_size"] += 2
	stats["name"] = FACTIONS[faction]["units"][unit_class]
	stats["class"] = unit_class
	return stats


func building_name(key: String, faction: String) -> String:
	if key == "special_building":
		return SPECIAL_BUILDING_NAMES.get(faction, BUILDINGS[key]["name"])
	return BUILDINGS[key]["name"]


func counter(attacker_class: String, target_kind: String) -> float:
	if not COUNTERS.has(attacker_class):
		return 1.0
	return COUNTERS[attacker_class].get(target_kind, 1.0)


func hero_stats_at_level(hero_key: String, level: int) -> Dictionary:
	var h = HEROES[hero_key]
	return {
		"hp": h["hp"] + h["hp_per_level"] * (level - 1),
		"damage": h["damage"] + h["damage_per_level"] * (level - 1),
	}


const ABILITY_MAX_RANK = 3


func ability_rank_level(key: String, rank: int) -> int:
	"""Hero level needed to put a point into rank `rank` of ability `key`."""
	if key == "R":
		return 4 + 2 * rank  # 6, 8, 10
	return 2 * rank - 1  # 1, 3, 5


func ability_at_rank(ability: Dictionary, rank: int) -> Dictionary:
	var a = ability.duplicate(true)
	var bonus = 0.3 * max(0, rank - 1)
	for stat in ["damage", "heal", "stun"]:
		if a.has(stat):
			a[stat] = a[stat] * (1.0 + bonus)
	if a.has("count"):
		a["count"] = a["count"] + max(0, rank - 1)
	a["cooldown"] = a["cooldown"] * (1.0 - 0.1 * max(0, rank - 1))
	a["rank"] = rank
	return a


func hero_respawn_time(level: int) -> float:
	return HERO_RESPAWN_BASE + HERO_RESPAWN_PER_LEVEL * level


func level_for_xp(xp: int) -> int:
	var level = 1
	for i in range(XP_PER_LEVEL.size()):
		if xp >= XP_PER_LEVEL[i]:
			level = i + 1
	return min(level, HERO_MAX_LEVEL)


func cost_text(cost: Dictionary) -> String:
	var parts = []
	for res in RESOURCES:
		if cost.get(res, 0) > 0:
			parts.append("%d %s" % [cost[res], res.capitalize()])
	return ", ".join(parts) if not parts.is_empty() else "free"
