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
		"squad_size": 4, "cost": {"food": 200, "iron": 120, "gold": 60}, "building": "special",
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
# Abilities: key, name, cooldown (s), mana, kind (logic id implemented in HeroAbilities.gd),
# plus free-form params. Only the weekend heroes have abilities wired up so far.
const HEROES = {
	"aragorn":
	{
		"name": "Aragorn", "faction": "gondor", "role": "Fighter",
		"hp": 650, "mana": 200, "damage": 28, "interval": 1.0, "range": 1.8, "speed": 4.0,
		"sight": 12.0, "hp_per_level": 70, "damage_per_level": 4, "mana_regen": 2.0,
		"abilities":
		[
			{
				"key": "Q", "name": "Andúril Strike", "kind": "execute_strike", "cooldown": 8.0,
				"mana": 40, "range": 2.5, "damage": 60, "missing_hp_bonus": 0.25,
			},
			{
				"key": "W", "name": "For Frodo!", "kind": "rally_aura", "cooldown": 20.0,
				"mana": 60, "radius": 12.0, "duration": 8.0, "attack_speed": 1.3,
			},
			{
				"key": "E", "name": "Ranger's Dash", "kind": "dash", "cooldown": 10.0,
				"mana": 30, "distance": 8.0,
			},
			{
				"key": "R", "name": "Army of the Dead", "kind": "summon", "cooldown": 90.0,
				"mana": 120, "unit_class": "infantry", "count": 8, "duration": 15.0,
				"summon_name": "Army of the Dead",
			},
		],
	},
	"theoden":
	{
		"name": "Théoden", "faction": "rohan", "role": "Enchanter",
		"hp": 600, "mana": 220, "damage": 24, "interval": 1.0, "range": 1.8, "speed": 4.2,
		"sight": 12.0, "hp_per_level": 65, "damage_per_level": 3, "mana_regen": 2.5,
		"abilities":
		[
			{
				"key": "R", "name": "Ride of the Rohirrim", "kind": "team_haste",
				"cooldown": 80.0, "mana": 120, "radius": 30.0, "duration": 10.0, "speed": 1.5,
			},
		],
	},
	"gothmog":
	{
		"name": "Gothmog", "faction": "mordor", "role": "Vanguard",
		"hp": 780, "mana": 180, "damage": 24, "interval": 1.1, "range": 1.8, "speed": 3.8,
		"sight": 11.0, "hp_per_level": 90, "damage_per_level": 3, "mana_regen": 2.0,
		"abilities":
		[
			{
				"key": "W", "name": "Warg Pack", "kind": "summon", "cooldown": 45.0, "mana": 80,
				"unit_class": "rider", "count": 4, "duration": 20.0, "summon_name": "Wargs",
			},
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
			{
				"key": "Q", "name": "Heavy Arrow", "kind": "pin_shot", "cooldown": 10.0,
				"mana": 50, "range": 10.0, "damage": 80, "root": 2.0,
			},
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
}

const BUILD_MENU = [
	"village_house", "barracks", "archery_range", "stables", "storehouse", "watchtower"
]

const AGES = {
	2: {"name": "Kingdom", "cost": {"food": 400, "wood": 200, "stone": 100}, "time": 60.0},
	3: {"name": "Empire", "cost": {"food": 800, "stone": 300, "iron": 400, "gold": 200},
		"time": 90.0},
}
const AGE_NAMES = {1: "Settlement", 2: "Kingdom", 3: "Empire"}

const VILLAGER_STATS = {
	"hp": 40, "damage": 3, "interval": 1.5, "range": 1.2, "speed": 2.4, "sight": 6.0,
	"radius": 0.3,
}

# --- resource nodes on the map ----------------------------------------------------------------
const RESOURCE_NODES = {
	"food": {"name": "Game", "amount": 400, "color": Color("c98b5a")},
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
func troop_stats(faction: String, unit_class: String) -> Dictionary:
	var stats = CLASS_STATS[unit_class].duplicate(true)
	var mods = FACTIONS[faction]["mods"].get(unit_class, {})
	for stat in mods:
		if stat == "cost":
			for res in stats["cost"]:
				stats["cost"][res] = int(round(stats["cost"][res] * mods[stat]))
		elif stat == "squad_size":
			stats["squad_size"] = int(round(stats["squad_size"] * mods[stat]))
		else:
			stats[stat] = stats[stat] * mods[stat]
	stats["name"] = FACTIONS[faction]["units"][unit_class]
	stats["class"] = unit_class
	return stats


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
