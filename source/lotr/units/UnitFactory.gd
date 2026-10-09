class_name UnitFactory
## Builds every unit, building and resource node from a plain params Dictionary, so the host
## and clients can build identical nodes from the same params (used by replication).
## Geometry is simple low-poly stand-ins until the real LOTR models are imported.

const HighlightScene = preload("res://source/match/units/traits/Highlight.tscn")
const HealthBarScene = preload("res://source/match/units/traits/HealthBar.tscn")
const MovementScene = preload("res://source/match/units/traits/Movement.tscn")
const ObstacleScene = preload("res://source/match/units/traits/MovementObstacle.tscn")
const TargetabilityScene = preload("res://source/match/units/traits/Targetability.tscn")

const TroopScript = preload("res://source/lotr/units/Troop.gd")
const VillagerScript = preload("res://source/lotr/units/Villager.gd")
const HeroScript = preload("res://source/lotr/units/Hero.gd")
const BuildingScript = preload("res://source/lotr/units/Building.gd")
const ResourceScript = preload("res://source/lotr/units/ResourceNode.gd")
const CreatureScript = preload("res://source/lotr/units/Creature.gd")
const CreatureAnimScript = preload("res://source/lotr/art/CreatureAnim.gd")
const AnimDriverScript = preload("res://source/lotr/art/AnimDriver.gd")

const SKIN = Color("e0b48c")
const ORC_SKIN = Color("5d6b3a")
const URUK_SKIN = Color("4a3a30")
const STEEL = Color("b8bcc4")
const WOOD = Color("7a5230")
const ROOF = Color("8c3b2a")
const STONE = Color("a39e93")

static var _materials = {}


static func create(params: Dictionary) -> Node3D:
	var node = null
	match params.kind:
		"troop":
			node = _create_troop(params)
		"villager":
			node = _create_villager(params)
		"hero":
			node = _create_hero(params)
		"building":
			node = _create_building(params)
		"resource":
			node = _create_resource(params)
		"creature":
			node = _create_creature(params)
		_:
			push_error("unknown unit kind %s" % params.kind)
			return null
	_claim_ownership(node, node)
	return node


static func _claim_ownership(root, node):
	# find_child() only sees owned nodes; code-built children have no owner until we set one.
	# Nodes inside instanced trait scenes keep their own scene as owner.
	for child in node.get_children():
		if child.owner == null:
			child.owner = root
		_claim_ownership(root, child)


# --- units ------------------------------------------------------------------------------------
static func _create_troop(params):
	var stats = GameData.troop_stats(params.faction, params["class"], params.get("upgrades", {}))
	if params.has("summon_name"):
		stats["name"] = params.summon_name
	var unit = _new_unit(TroopScript, params, stats)
	unit.unit_kind = "troop"
	unit.unit_class = stats.counter_as  # which column of the counter table it attacks with
	unit.target_kind = stats.counter_as if stats.counter_as in GameData.TARGET_KINDS else "infantry"
	unit.display_name = stats.name
	unit.armor = stats.armor
	unit.siege = stats.siege
	unit.explode = stats.explode
	var geometry = _geometry(unit)
	var unit_class = params["class"]
	var look = Art.unit_look(params.faction, unit_class)
	if params.get("ghost", false):
		# Army of the Dead: risen skeleton warriors, translucent green
		var dead = _character(unit, geometry, "Skeleton_Warrior", [], Color(1, 1, 1), 1.0, "melee")
		Art.ghost(dead)
		var anim = dead.get_meta("anim")
		if anim.has_animation("Skeletons_Awaken_Standing"):
			anim.play("Skeletons_Awaken_Standing")
	elif Art.siege_kind(params.faction, unit_class) != "":
		match Art.siege_kind(params.faction, unit_class):
			"trebuchet":
				_trebuchet(geometry)
			"ram":
				_ram(geometry, Color("2b2622"), false)
			"grond":
				_ram(geometry, Color("1c1716"), true)
	elif unit_class == "heavy" and not Art.UNITS.get(params.faction, {}).has("heavy"):
		_siege(geometry)
	elif Art.is_mounted(params.faction, unit_class):
		_mount(geometry, params.faction)
		var anim_set = "rider_ranged" if stats.ranged else "rider"
		var rider = _character(unit, geometry, look[0], look[1], look[2], look[3], anim_set)
		rider.position = Vector3(0, 0.62, 0.05)
	else:
		_character(unit, geometry, look[0], look[1], look[2], look[3], look[4])
	var bar = 1.9
	if unit_class == "heavy" or Art.siege_kind(params.faction, unit_class) != "":
		bar = 3.4 if Art.siege_kind(params.faction, unit_class) != "grond" else 4.2
	_finish_mobile(unit, stats, bar)
	return unit


static func _create_creature(params):
	var data = GameData.CREATURES[params.creature]
	var stats = data.duplicate()
	stats["ranged"] = false
	var unit = _new_unit(CreatureScript, params, stats)
	unit.unit_kind = "creature"
	unit.unit_class = "infantry" if params.creature != "cave_troll" else "heavy"
	unit.target_kind = unit.unit_class
	unit.creature_key = params.creature
	unit.display_name = data.name
	unit.armor = data.get("armor", 0.0)
	var geometry = _geometry(unit)
	match params.creature:
		"deer":
			var deer = _deer(geometry)
			var danim = CreatureAnimScript.new()
			danim.name = "CreatureAnim"
			danim.body = deer
			unit.add_child(danim)
		"spider":
			_spider(unit, geometry, Color(0.2, 0.17, 0.15), 1.0)
		"warg":
			var body = _mount(geometry, "mordor")
			var anim = CreatureAnimScript.new()
			anim.name = "CreatureAnim"
			anim.body = body
			unit.add_child(anim)
		"cave_troll":
			var troll = _character(unit, geometry, "Barbarian", ["2H_Axe"], Color(1, 1, 1), 2.7, "melee2h", ["Barbarian_Cape"])
			# grey-green stony hide
			Art.recolor(troll, {"Barbarian_Head": Color(0.48, 0.55, 0.45), "Barbarian_ArmLeft": Color(0.46, 0.53, 0.43),
				"Barbarian_ArmRight": Color(0.46, 0.53, 0.43), "Barbarian_Body": Color(0.36, 0.33, 0.28),
				"Barbarian_LegLeft": Color(0.34, 0.31, 0.27), "Barbarian_LegRight": Color(0.34, 0.31, 0.27)})
	_finish_mobile(unit, stats, 2.0 if params.creature != "cave_troll" else 5.2)
	return unit


static func _character(unit, geometry, model, props, tint, scale, anim_set, hide = []):
	var node = Art.character(model, props, tint, scale, hide)
	geometry.add_child(node)
	if node.has_meta("anim"):
		var driver = AnimDriverScript.new()
		driver.name = "AnimDriver"
		driver.player = node.get_meta("anim")
		driver.anim_set = anim_set
		unit.add_child(driver)
		unit.anim_driver = driver
	return node


static func _create_villager(params):
	var stats = GameData.VILLAGER_STATS.duplicate()
	var unit = _new_unit(VillagerScript, params, stats)
	unit.unit_kind = "villager"
	unit.unit_class = "villager"
	unit.target_kind = "villager"
	unit.display_name = "Villager"
	var geometry = _geometry(unit)
	var tint = Art.ORC if params.faction == "mordor" else (Art.URUK if params.faction == "isengard" else Color(0.95, 0.85, 0.7))
	_character(unit, geometry, "Mage", [], tint, 0.85, "worker", ["Mage_Hat"])
	_finish_mobile(unit, stats, 1.5)
	return unit


static func _create_hero(params):
	var data = GameData.HEROES[params.hero]
	var stats = {
		"hp": data.hp, "damage": data.damage, "interval": data.interval, "range": data.range,
		"speed": data.speed, "sight": data.sight, "radius": 0.45,
		"ranged": data.get("ranged", false),
	}
	var unit = _new_unit(HeroScript, params, stats)
	unit.unit_kind = "hero"
	unit.unit_class = "hero"
	unit.target_kind = "hero"
	unit.hero_key = params.hero
	unit.display_name = data.name
	var geometry = _geometry(unit)
	var look = Art.HEROES.get(params.hero, Art.HEROES.aragorn)
	if look[0] == "spider":
		_spider(unit, geometry, look[2], look[3])
	else:
		var model = _character(unit, geometry, look[0], look[1], look[2], look[3], look[4], look[5])
		if Art.RECOLOR.has(params.hero):
			Art.recolor(model, Art.RECOLOR[params.hero])
	# a gold ring at the feet so heroes stand out in a crowd
	_part(geometry, _torus(0.62, 0.72), Color("e8c24a"), Vector3(0, 0.04, 0))
	_finish_mobile(unit, stats, 2.6)
	# heroes walk straight through units (not buildings: those are cut out of the navmesh).
	# Avoidance stays on (Movement relies on its velocity signal); the hero just sits on its own
	# avoidance layer and avoids nothing, so units and the hero ignore each other.
	var hero_move = unit.get_node("Movement")
	hero_move.avoidance_layers = 2
	hero_move.avoidance_mask = 0
	unit.add_to_group("heroes")
	return unit


static func _finish_mobile(unit, stats, bar_height):
	var radius = stats.get("radius", 0.4)
	_collision(unit, radius, 1.6)
	var movement = MovementScene.instantiate()
	movement.name = "Movement"
	movement.radius = radius
	movement.speed = stats.get("speed", 2.5)
	movement.path_desired_distance = 0.5
	movement.target_desired_distance = 0.4
	movement.path_height_offset = 0.5
	movement.path_max_distance = 0.51
	movement.neighbor_distance = 4.0
	movement.max_neighbors = 6  # cheaper avoidance; plenty for small squads
	movement.time_horizon_agents = 1.5
	unit.add_child(movement)
	_common_traits(unit, radius + 0.15, bar_height)


# --- buildings --------------------------------------------------------------------------------
static func _create_building(params):
	var data = GameData.BUILDINGS[params.building]
	var stats = {"hp": data.hp, "sight": data.sight}
	if data.has("attack"):
		stats["damage"] = data.attack.damage
		stats["interval"] = data.attack.interval
		stats["range"] = data.attack.range
		stats["ranged"] = true
	var unit = _new_unit(BuildingScript, params, stats)
	unit.unit_kind = "building"
	unit.unit_class = "building"
	unit.target_kind = "building"
	unit.building_key = params.building
	unit.display_name = data.name
	unit.armor = 0.2
	var geometry = _geometry(unit)
	if data.get("wall", false):
		return _finish_wall(unit, geometry, params, data)
	var faction_color = GameData.FACTIONS[params.get("faction", "gondor")].color
	var s = data.size
	var model = Art.building(params.building, params.get("faction", "gondor"), s)
	if model != null:
		model.name = "BuildingModel"
		geometry.add_child(model)
		unit.set_meta("model_height", Art.prop_height(Art.BUILDING_MODELS[params.building][0] % Art.BUILDING_COLOR.get(params.get("faction", "gondor"), "blue")) * model.scale.y)
	match params.building if model == null else "":
		"town_center":
			_part(geometry, _box(Vector3(s * 1.6, 1.6, s * 1.6)), STONE, Vector3(0, 0.8, 0))
			_part(geometry, _prism(Vector3(s * 1.7, 1.2, s * 1.7)), null, Vector3(0, 2.2, 0), true)
			_part(geometry, _cylinder(0.7, 0.8, 3.6), STONE, Vector3(s * 0.5, 1.8, s * 0.5))
			_part(geometry, _cone(0.9, 1.2), faction_color, Vector3(s * 0.5, 4.2, s * 0.5))
		"village_house":
			_part(geometry, _box(Vector3(s * 1.4, 1.0, s * 1.2)), Color("c8b28a"), Vector3(0, 0.5, 0))
			_part(geometry, _prism(Vector3(s * 1.5, 0.8, s * 1.3)), ROOF, Vector3(0, 1.4, 0))
			_part(geometry, _box(Vector3(0.3, 0.3, 0.3)), null, Vector3(s * 0.55, 1.2, 0), true)
		"watchtower":
			_part(geometry, _cylinder(0.7, 0.9, 4.0), STONE, Vector3(0, 2.0, 0))
			_part(geometry, _cylinder(1.0, 0.8, 0.6), STONE, Vector3(0, 4.3, 0))
			_part(geometry, _cone(1.1, 1.0), null, Vector3(0, 5.1, 0), true)
		"barracks":
			_part(geometry, _box(Vector3(s * 1.8, 1.4, s * 1.2)), WOOD, Vector3(0, 0.7, 0))
			_part(geometry, _prism(Vector3(s * 1.9, 0.9, s * 1.3)), null, Vector3(0, 1.85, 0), true)
			_banner(geometry, Vector3(s * 0.9, 0, s * 0.6))
		"archery_range":
			_part(geometry, _box(Vector3(s * 1.6, 1.2, s * 1.0)), WOOD, Vector3(0, 0.6, -s * 0.2))
			_part(geometry, _prism(Vector3(s * 1.7, 0.7, s * 1.1)), null, Vector3(0, 1.55, -s * 0.2), true)
			_part(geometry, _cylinder(0.5, 0.5, 0.08), Color("d64545"), Vector3(0, 0.9, s * 0.7),
				false, Vector3(PI / 2, 0, 0))
			_banner(geometry, Vector3(-s * 0.8, 0, s * 0.5))
		"stables":
			_part(geometry, _box(Vector3(s * 1.8, 1.1, s * 1.1)), Color("8a6a3a"), Vector3(0, 0.55, 0))
			_part(geometry, _prism(Vector3(s * 1.9, 0.8, s * 1.2)), null, Vector3(0, 1.5, 0), true)
			for i in range(4):
				_part(geometry, _box(Vector3(0.1, 0.6, 0.1)), WOOD,
					Vector3(-s * 0.8 + i * s * 0.53, 0.3, s * 0.85))
			_part(geometry, _box(Vector3(s * 1.7, 0.08, 0.08)), WOOD, Vector3(0, 0.5, s * 0.85))
		"storehouse":
			_part(geometry, _box(Vector3(s * 1.5, 1.3, s * 1.3)), Color("9c7b4b"), Vector3(0, 0.65, 0))
			_part(geometry, _prism(Vector3(s * 1.6, 0.8, s * 1.4)), null, Vector3(0, 1.7, 0), true)
			for i in range(3):
				_part(geometry, _box(Vector3(0.5, 0.5, 0.5)), WOOD,
					Vector3(s * 0.9, 0.25, -0.6 + i * 0.6))
	_collision(unit, s, 2.0)
	var obstacle = ObstacleScene.instantiate()
	obstacle.name = "MovementObstacle"
	obstacle.radius = s
	obstacle.affect_navigation_mesh = true
	obstacle.path_height_offset = 0.0
	var verts = PackedVector3Array()
	for i in range(8):
		var angle = TAU * i / 8.0
		verts.append(Vector3(cos(angle), 0, sin(angle)) * s * 0.9)
	obstacle.vertices = verts
	unit.add_child(obstacle)
	_common_traits(unit, s + 0.3, unit.get_meta("model_height", 3.0) + 0.4)
	return unit


# --- resources --------------------------------------------------------------------------------
static func _create_resource(params):
	var node = Area3D.new()
	node.set_script(ResourceScript)
	node.name = "Resource"
	node.resource_type = params.type
	node.amount = params.get("amount", GameData.RESOURCE_NODES[params.type].amount)
	node.spawn_params = params
	node.collision_layer = 2
	node.collision_mask = 0
	node.add_to_group("resource_units")
	node.add_to_group("lotr_resources")
	var geometry = Node3D.new()
	geometry.name = "Geometry"
	node.add_child(geometry)
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(params.get("seed", 0))
	var yaw = rng.randf() * TAU
	match params.type:
		"wood":
			# a small grove of Quaternius trees
			var kinds = ["nature/Pine_1", "nature/Pine_2", "nature/Pine_3", "nature/CommonTree_1", "nature/CommonTree_2"]
			for k in range(3):
				var tree = Art.prop(kinds[rng.randi() % kinds.size()], rng.randf_range(1.1, 1.5))
				var ang = yaw + TAU * k / 3.0
				tree.position = Vector3(cos(ang), 0, sin(ang)) * 0.6
				tree.rotation.y = rng.randf() * TAU
				geometry.add_child(tree)
		"stone":
			for k in range(3):
				var rock = Art.prop("nature/Rock_Medium_%d" % (1 + rng.randi() % 3), rng.randf_range(0.7, 1.1))
				rock.position = Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
				rock.rotation.y = rng.randf() * TAU
				geometry.add_child(rock)
			var pile = Art.prop("resource_stone", 0.9)
			pile.position = Vector3(0.4, 0, 0.4)
			geometry.add_child(pile)
		"iron":
			# dark, rust-streaked rock outcrop
			var outcrop = Art.prop("mountain_A", 2.0, Color(0.45, 0.4, 0.38))
			outcrop.scale.y *= 0.55
			outcrop.rotation.y = yaw
			geometry.add_child(outcrop)
			var ore = Art.prop("resource_stone", 0.8, Color(0.75, 0.42, 0.28))
			ore.position = Vector3(0.7, 0, 0.5)
			geometry.add_child(ore)
		"food":
			var field = Art.prop("building_grain", 2.2)
			field.rotation.y = yaw
			geometry.add_child(field)
			var sacks = Art.prop("sack", 0.45)
			sacks.position = Vector3(0.9, 0.05, 0.6)
			geometry.add_child(sacks)
	_collision(node, 0.8, 1.2)
	var obstacle = ObstacleScene.instantiate()
	obstacle.name = "MovementObstacle"
	obstacle.radius = 0.6
	obstacle.affect_navigation_mesh = true
	obstacle.path_height_offset = 0.6
	obstacle.vertices = PackedVector3Array(
		[Vector3(0, 0, -0.3), Vector3(0.3, 0, 0), Vector3(0, 0, 0.3), Vector3(-0.3, 0, 0)]
	)
	node.add_child(obstacle)
	var highlight = HighlightScene.instantiate()
	highlight.radius = 1.0
	highlight.position.y = 0.05
	node.add_child(highlight)
	return node


# --- assembly helpers -------------------------------------------------------------------------
static func _new_unit(script, params, stats):
	var unit = Area3D.new()
	unit.set_script(script)
	unit.collision_layer = 2
	unit.collision_mask = 0
	unit.spawn_params = params
	unit.stats = stats
	return unit


static func _geometry(unit):
	var geometry = Node3D.new()
	geometry.name = "Geometry"
	unit.add_child(geometry)
	return geometry


static func _collision(unit, radius, height):
	var shape = CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var cylinder = CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	shape.shape = cylinder
	shape.position.y = height / 2.0
	unit.add_child(shape)


static func _common_traits(unit, ring_radius, bar_height):
	var highlight = HighlightScene.instantiate()
	highlight.name = "Highlight"
	highlight.radius = ring_radius
	highlight.position.y = 0.05
	unit.add_child(highlight)
	var targetability = TargetabilityScene.instantiate()
	targetability.name = "Targetability"
	targetability.radius = ring_radius
	targetability.position.y = 0.05
	unit.add_child(targetability)
	var bar = HealthBarScene.instantiate()
	bar.name = "HealthBar"
	bar.position.y = bar_height
	bar.size = Vector2(120, 10)
	unit.add_child(bar)


static func _skin_for(faction):
	if faction == "mordor":
		return ORC_SKIN
	if faction == "isengard":
		return URUK_SKIN
	return SKIN


static func _humanoid(geometry, faction, skin, weapon, scale):
	var armor = GameData.FACTIONS[faction].color
	var root = Node3D.new()
	root.scale = Vector3.ONE * scale
	geometry.add_child(root)
	_part(root, _capsule(0.22, 1.0), armor, Vector3(0, 0.75, 0))  # body
	_part(root, _box(Vector3(0.46, 0.25, 0.3)), null, Vector3(0, 0.95, 0), true)  # tabard
	_part(root, _sphere(0.17), skin, Vector3(0, 1.42, 0))  # head
	match weapon:
		"sword":
			_part(root, _box(Vector3(0.05, 0.7, 0.05)), STEEL, Vector3(0.3, 0.9, -0.25),
				false, Vector3(-0.5, 0, 0))
			_part(root, _box(Vector3(0.08, 0.45, 0.35)), null, Vector3(-0.28, 0.85, -0.05), true)
		"bow":
			_part(root, _torus(0.3, 0.34), WOOD, Vector3(-0.3, 0.95, -0.1), false,
				Vector3(0, PI / 2, 0))
		"spear":
			_part(root, _cylinder(0.025, 0.025, 1.8), WOOD, Vector3(0.28, 0.9, -0.2))
		"tool":
			_part(root, _cylinder(0.025, 0.025, 0.8), WOOD, Vector3(0.28, 0.7, -0.15),
				false, Vector3(-0.6, 0, 0))
	return root


static func _rider(geometry, faction, skin):
	var horse_color = Color("6b4a2b") if faction in ["gondor", "rohan"] else Color("3a3a3a")
	_part(geometry, _box(Vector3(0.45, 0.5, 1.2)), horse_color, Vector3(0, 0.75, 0))
	_part(geometry, _box(Vector3(0.25, 0.45, 0.35)), horse_color, Vector3(0, 1.1, -0.65),
		false, Vector3(-0.5, 0, 0))
	for x in [-0.15, 0.15]:
		for z in [-0.45, 0.45]:
			_part(geometry, _cylinder(0.06, 0.06, 0.55), horse_color, Vector3(x, 0.27, z))
	var rider = _humanoid(geometry, faction, skin, "spear", 0.85)
	rider.position = Vector3(0, 0.55, 0.05)


static func _mount(geometry, faction):
	"""A horse for the Free Peoples, a warg for the Shadow, built from simple shapes."""
	var shadow = GameData.FACTIONS[faction].side == "shadow"
	var coat = Color("3b332c") if shadow else Color("7a5434")
	var mane = Color("1f1a17") if shadow else Color("3a2617")
	var root = Node3D.new()
	geometry.add_child(root)
	var body_len = 1.15 if not shadow else 1.0
	var leg_h = 0.62 if not shadow else 0.45
	_part(root, _capsule(0.27, body_len + 0.3), coat, Vector3(0, leg_h + 0.12, 0), false, Vector3(PI / 2, 0, 0))
	# neck and head
	var neck_tilt = -0.75 if not shadow else -0.25
	_part(root, _capsule(0.13, 0.62), coat, Vector3(0, leg_h + 0.42, -body_len * 0.52), false, Vector3(neck_tilt, 0, 0))
	_part(root, _box(Vector3(0.2, 0.22, 0.48 if not shadow else 0.4)), coat, Vector3(0, leg_h + 0.66 - (0.25 if shadow else 0.0), -body_len * 0.72), false, Vector3(0.35 if not shadow else 0.05, 0, 0))
	_part(root, _box(Vector3(0.06, 0.4, 0.35)), mane, Vector3(0, leg_h + 0.55, -body_len * 0.45), false, Vector3(neck_tilt, 0, 0))
	if shadow:  # warg ears
		for x in [-0.07, 0.07]:
			_part(root, _cone(0.05, 0.14), mane, Vector3(x, leg_h + 0.52, -body_len * 0.6))
	for x in [-0.15, 0.15]:
		for z in [-body_len * 0.42, body_len * 0.42]:
			_part(root, _cylinder(0.055, 0.045, leg_h), mane if shadow else coat, Vector3(x, leg_h / 2.0, z))
	_part(root, _capsule(0.05, 0.5), mane, Vector3(0, leg_h + 0.1, body_len * 0.62), false, Vector3(0.9, 0, 0))
	# saddle cloth in team colour
	if not shadow:
		_part(root, _box(Vector3(0.6, 0.06, 0.5)), null, Vector3(0, leg_h + 0.38, 0.05), true)
	return root


static func _deer(geometry):
	"""A red deer: slim body, long legs, white tail, antlers."""
	var coat = Color("9a6a3e")
	var root = Node3D.new()
	geometry.add_child(root)
	var leg_h = 0.62
	_part(root, _capsule(0.2, 1.0), coat, Vector3(0, leg_h + 0.12, 0), false, Vector3(PI / 2, 0, 0))
	_part(root, _capsule(0.08, 0.55), coat, Vector3(0, leg_h + 0.42, -0.42), false, Vector3(-0.6, 0, 0))
	_part(root, _box(Vector3(0.14, 0.16, 0.34)), coat.darkened(0.1), Vector3(0, leg_h + 0.66, -0.6), false, Vector3(0.3, 0, 0))
	for x in [-0.08, 0.08]:
		_part(root, _cylinder(0.015, 0.02, 0.35), Color("d8cdb5"), Vector3(x * 1.4, leg_h + 0.9, -0.55), false, Vector3(0, 0, x * 5.0))
	for x in [-0.11, 0.11]:
		for z in [-0.3, 0.32]:
			_part(root, _cylinder(0.035, 0.025, leg_h), coat.darkened(0.25), Vector3(x, leg_h / 2.0, z))
	_part(root, _sphere(0.07), Color("eee6d6"), Vector3(0, leg_h + 0.2, 0.55))
	root.set_meta("base_y", 0.0)
	return root


static func _finish_wall(unit, geometry, params, data):
	"""A wall piece WALL_SEGMENT long along its local X axis (palisade, stone or gate)."""
	var key = params.building
	var length = GameData.WALL_SEGMENT
	var stone = params.get("stone", key == "stone_wall")
	match key:
		"wall":
			for i in range(5):
				var x = -length / 2.0 + 0.24 + i * (length - 0.48) / 4.0
				_part(geometry, _cylinder(0.17, 0.2, 1.9), WOOD, Vector3(x, 0.95, 0))
				_part(geometry, _cone(0.18, 0.4), WOOD.lightened(0.1), Vector3(x, 2.1, 0))
			_part(geometry, _box(Vector3(length, 0.12, 0.08)), WOOD.darkened(0.3), Vector3(0, 1.3, 0.2))
		"stone_wall":
			_part(geometry, _box(Vector3(length, 2.2, 0.9)), STONE, Vector3(0, 1.1, 0))
			for i in range(3):
				_part(geometry, _box(Vector3(0.45, 0.4, 0.95)), STONE.darkened(0.08), Vector3(-0.8 + i * 0.8, 2.4, 0))
		"gate":
			var post = STONE if stone else WOOD
			for x in [-length / 2.0 + 0.2, length / 2.0 - 0.2]:
				_part(geometry, _box(Vector3(0.4, 2.8, 0.6)), post, Vector3(x, 1.4, 0))
			_part(geometry, _box(Vector3(length, 0.35, 0.6)), post.darkened(0.15), Vector3(0, 2.75, 0))
			# two door leaves that swing open (Building animates "DoorL"/"DoorR")
			for side in [-1, 1]:
				var hinge = Node3D.new()
				hinge.name = "DoorL" if side < 0 else "DoorR"
				hinge.position = Vector3(side * (length / 2.0 - 0.4), 0, 0)
				geometry.add_child(hinge)
				_part(hinge, _box(Vector3(length / 2.0 - 0.4, 2.2, 0.15)), WOOD.darkened(0.15), Vector3(-side * (length / 4.0 - 0.2), 1.1, 0))
				_part(hinge, _box(Vector3(0.5, 0.25, 0.17)), null, Vector3(-side * (length / 4.0 - 0.2), 1.6, 0), true)
	_collision_box(unit, Vector3(length, 2.4, 0.9))
	var obstacle = ObstacleScene.instantiate()
	obstacle.name = "MovementObstacle"
	obstacle.radius = 0.6
	obstacle.affect_navigation_mesh = true
	obstacle.path_height_offset = 0.0
	# navmesh baking ignores node rotation, so the footprint is rotated here
	var yaw = float(params.get("yaw", 0.0))
	var verts = PackedVector3Array()
	for c in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
		verts.append(Basis(Vector3.UP, yaw) * Vector3(c.x * length / 2.0, 0, c.z * 0.45))
	obstacle.vertices = verts
	unit.add_child(obstacle)
	_common_traits(unit, 1.3, 3.0)
	return unit


static func _collision_box(unit, size: Vector3):
	var shape = CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box = BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y / 2.0
	unit.add_child(shape)


static func _troll(geometry, faction):
	var color = Color("6a6a5a") if faction == "mordor" else GameData.FACTIONS[faction].color
	_part(geometry, _capsule(0.6, 2.2), color, Vector3(0, 1.1, 0))
	_part(geometry, _sphere(0.38), color, Vector3(0, 2.35, -0.1))
	_part(geometry, _cylinder(0.12, 0.2, 1.4), WOOD, Vector3(0.65, 1.2, -0.3), false,
		Vector3(-0.7, 0, 0))
	_part(geometry, _box(Vector3(0.9, 0.3, 0.6)), null, Vector3(0, 1.6, 0), true)


static func _siege(geometry):
	_part(geometry, _box(Vector3(1.0, 0.4, 1.6)), WOOD, Vector3(0, 0.5, 0))
	for x in [-0.55, 0.55]:
		for z in [-0.55, 0.55]:
			_part(geometry, _cylinder(0.3, 0.3, 0.12), WOOD, Vector3(x, 0.3, z), false,
				Vector3(0, 0, PI / 2))
	_part(geometry, _box(Vector3(0.12, 0.12, 2.0)), WOOD, Vector3(0, 1.2, 0), false,
		Vector3(0.6, 0, 0))
	_part(geometry, _box(Vector3(0.6, 0.3, 0.3)), null, Vector3(0, 0.85, 0.6), true)


static func _spider(unit, geometry, color: Color, size: float):
	"""A giant spider: abdomen, head, glowing eyes and eight jointed legs that scuttle."""
	var anim = load("res://source/lotr/art/CreatureAnim.gd").new()
	anim.name = "CreatureAnim"
	var body = Node3D.new()
	body.name = "Body"
	geometry.add_child(body)
	var s = size
	var leg_h = 0.32 * s
	body.position.y = leg_h
	body.set_meta("base_y", leg_h)
	var abdomen = _part(body, _sphere(0.42 * s), color, Vector3(0, 0.12 * s, 0.38 * s))
	abdomen.scale = Vector3(1.0, 0.8, 1.25)
	_part(body, _sphere(0.24 * s), color.lightened(0.08), Vector3(0, 0.05 * s, -0.18 * s))
	_part(body, _sphere(0.15 * s), color, Vector3(0, 0.02 * s, -0.42 * s))
	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.9, 0.2, 0.1)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.9, 0.15, 0.05)
	for x in [-0.05, 0.05]:
		var eye = _part(body, _sphere(0.03 * s), color, Vector3(x * s, 0.08 * s, -0.55 * s))
		eye.material_override = eye_mat
	# fangs
	for x in [-0.05, 0.05]:
		_part(body, _cone(0.025 * s, 0.12 * s), Color(0.85, 0.82, 0.7), Vector3(x * s, -0.06 * s, -0.55 * s), false, Vector3(PI, 0, 0))
	for side in [-1, 1]:
		for i in range(4):
			var pivot = Node3D.new()
			pivot.position = Vector3(side * 0.12 * s, 0.02 * s, (-0.28 + i * 0.13) * s)
			pivot.rotation.y = side * (0.4 - i * 0.28)
			body.add_child(pivot)
			var upper = _part(pivot, _cylinder(0.025 * s, 0.03 * s, 0.42 * s), color, Vector3(side * 0.2 * s, 0.1 * s, 0), false, Vector3(0, 0, side * -1.1))
			_part(pivot, _cylinder(0.015 * s, 0.025 * s, 0.5 * s), color, Vector3(side * 0.43 * s, -0.12 * s, 0), false, Vector3(0, 0, side * 0.45))
			anim.legs.append(pivot)
	anim.body = body
	unit.add_child(anim)
	return body


static func _trebuchet(geometry):
	"""Gondor's stone-thrower: a wheeled frame, a throwing arm and a counterweight."""
	_part(geometry, _box(Vector3(1.3, 0.25, 2.0)), WOOD, Vector3(0, 0.45, 0))
	for x in [-0.7, 0.7]:
		for z in [-0.7, 0.7]:
			_part(geometry, _cylinder(0.32, 0.32, 0.12), WOOD.darkened(0.3), Vector3(x, 0.32, z), false,
				Vector3(0, 0, PI / 2))
		# A-frame uprights
		_part(geometry, _box(Vector3(0.12, 1.8, 0.14)), WOOD, Vector3(x * 0.8, 1.35, -0.25), false, Vector3(0.25, 0, 0))
		_part(geometry, _box(Vector3(0.12, 1.8, 0.14)), WOOD, Vector3(x * 0.8, 1.35, 0.35), false, Vector3(-0.25, 0, 0))
	_part(geometry, _cylinder(0.07, 0.07, 1.3), STEEL, Vector3(0, 2.1, 0.05), false, Vector3(0, 0, PI / 2))
	_part(geometry, _box(Vector3(0.12, 0.12, 3.0)), WOOD.lightened(0.1), Vector3(0, 2.5, 0.2), false, Vector3(-0.5, 0, 0))
	_part(geometry, _box(Vector3(0.5, 0.5, 0.5)), STONE.darkened(0.3), Vector3(0, 1.75, -0.65))
	_part(geometry, _box(Vector3(0.9, 0.06, 0.4)), null, Vector3(0, 0.6, 0.95), true)


static func _ram(geometry, frame_color: Color, grond: bool):
	"""A covered battering ram; Grond is a huge black one with a burning wolf's head."""
	var s = 1.0 if not grond else 1.9
	_part(geometry, _box(Vector3(1.1 * s, 0.2, 2.2 * s)), frame_color, Vector3(0, 0.45 * s, 0))
	for x in [-0.6 * s, 0.6 * s]:
		for z in [-0.8 * s, 0.0, 0.8 * s]:
			_part(geometry, _cylinder(0.28 * s, 0.28 * s, 0.14 * s), frame_color.darkened(0.3),
				Vector3(x, 0.28 * s, z), false, Vector3(0, 0, PI / 2))
		_part(geometry, _box(Vector3(0.1 * s, 1.0 * s, 0.1 * s)), frame_color, Vector3(x * 0.85, 0.95 * s, -0.7 * s))
		_part(geometry, _box(Vector3(0.1 * s, 1.0 * s, 0.1 * s)), frame_color, Vector3(x * 0.85, 0.95 * s, 0.7 * s))
	# the roof (team colour on the plain ram, black iron on Grond)
	if grond:
		_part(geometry, _prism(Vector3(1.3 * s, 0.6 * s, 2.0 * s)), Color("2a2522"), Vector3(0, 1.7 * s, 0))
	else:
		_part(geometry, _prism(Vector3(1.3 * s, 0.6 * s, 2.0 * s)), null, Vector3(0, 1.7 * s, 0), true)
	_part(geometry, _cylinder(0.16 * s, 0.16 * s, 2.6 * s), frame_color.lightened(0.15),
		Vector3(0, 0.95 * s, -0.4 * s), false, Vector3(PI / 2, 0, 0))
	if grond:
		var head = _part(geometry, _cone(0.35 * s, 0.7 * s), Color("ff6a1a"), Vector3(0, 0.95 * s, -1.85 * s), false, Vector3(-PI / 2, 0, 0))
		var fire = StandardMaterial3D.new()
		fire.albedo_color = Color("ff7a20")
		fire.emission_enabled = true
		fire.emission = Color("ff5a10")
		fire.emission_energy_multiplier = 2.0
		head.material_override = fire
		for x in [-0.15 * s, 0.15 * s]:
			_part(geometry, _cone(0.08 * s, 0.3 * s), Color("2a2522"), Vector3(x, 1.25 * s, -1.6 * s))
	else:
		_part(geometry, _box(Vector3(0.36, 0.36, 0.3)), STEEL, Vector3(0, 0.95, -1.7))


static func _banner(geometry, at):
	_part(geometry, _cylinder(0.04, 0.04, 2.6), WOOD, at + Vector3(0, 1.3, 0))
	_part(geometry, _box(Vector3(0.6, 0.4, 0.03)), null, at + Vector3(0.3, 2.3, 0), true)


static func _ghostify(geometry):
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 1.0, 0.8, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.9, 0.6)
	for node in geometry.find_children("*", "MeshInstance3D", true, false):
		node.material_override = mat
		node.remove_meta("team_color")


static func _part(parent, mesh, color, position, team_color = false, rotation = Vector3.ZERO):
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.rotation = rotation
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if team_color or color == null:
		instance.set_meta("team_color", true)
		instance.material_override = _material(Color.WHITE)
	else:
		instance.material_override = _material(color)
	parent.add_child(instance)
	return instance


static func _material(color: Color):
	var key = color.to_html()
	if not _materials.has(key):
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.85
		_materials[key] = mat
	return _materials[key]


static func _box(size):
	var mesh = BoxMesh.new()
	mesh.size = size
	return mesh


static func _prism(size):
	var mesh = PrismMesh.new()
	mesh.size = size
	return mesh


static func _capsule(radius, height):
	var mesh = CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 3
	return mesh


static func _sphere(radius):
	var mesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 8
	mesh.rings = 4
	return mesh


static func _cylinder(top, bottom, height):
	var mesh = CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 8
	return mesh


static func _cone(radius, height):
	return _cylinder(0.0, radius, height)


static func _torus(inner, outer):
	var mesh = TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 8
	mesh.ring_segments = 4
	return mesh
