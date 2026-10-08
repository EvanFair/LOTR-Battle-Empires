class_name Art
## Every 3D model in the game comes from here. Uses the CC0 KayKit packs in assets/kaykit/
## (characters with 76 animations, medieval buildings in 4 colours, nature props).
## Faction identity comes from building colour, a per-faction tint on characters (orc skin,
## dark Uruk armour, ghostly dead) and which weapons each unit carries.

const CHAR_DIR = "res://assets/kaykit/characters/"
const MED_DIR = "res://assets/kaykit/medieval/"
const CHARACTER_SCALE = 0.62  # KayKit characters are ~2.5m tall; ours are ~1.6m

# meshes inside the character models that are weapons/props (hidden unless a unit asks for them)
const PROP_MESHES = [
	"1H_Sword_Offhand", "Badge_Shield", "Rectangle_Shield", "Round_Shield", "Spike_Shield",
	"1H_Sword", "2H_Sword", "1H_Axe_Offhand", "Barbarian_Round_Shield", "1H_Axe", "2H_Axe", "Mug",
	"Knife_Offhand", "1H_Crossbow", "2H_Crossbow", "Knife", "Throwable", "Spellbook",
	"Spellbook_open", "1H_Wand", "2H_Staff",
]

const ORC = Color(0.55, 0.68, 0.42)
const URUK = Color(0.38, 0.34, 0.33)
const STEEL = Color(1, 1, 1)

# building colour variant per faction (the KayKit buildings come in blue/green/red/yellow)
const BUILDING_COLOR = {
	"gondor": "blue", "rohan": "green", "mordor": "red", "isengard": "yellow",
	"eldar": "yellow", "dwarves": "blue", "harad": "red", "wild": "green",
}
# darken the evil factions' buildings so they read grim rather than toy-like
const BUILDING_TINT = {
	"mordor": Color(0.5, 0.42, 0.42), "isengard": Color(0.45, 0.45, 0.48),
	"harad": Color(0.85, 0.7, 0.55),
}

const BUILDING_MODELS = {
	"town_center": ["building_castle_%s", 1.0],
	"village_house": ["building_home_A_%s", 1.15],
	"watchtower": ["building_tower_A_%s", 1.1],
	"barracks": ["building_barracks_%s", 1.0],
	"archery_range": ["building_archeryrange_%s", 1.0],
	"stables": ["building_tavern_%s", 1.0],
	"storehouse": ["building_market_%s", 1.05],
	"blacksmith": ["building_blacksmith_%s", 1.1],
	"siege_works": ["building_tower_catapult_%s", 1.0],
	"special_building": ["building_church_%s", 1.0],
}

# classes that ride (a horse for the Free Peoples, a warg for the Shadow)
const MOUNTED = {"rohan": ["rider", "heavy", "special"]}
const DEFAULT_MOUNTED = ["rider"]
# siege engines built procedurally in UnitFactory (no KayKit model for them)
const SIEGE = {
	"gondor": {"heavy": "trebuchet"}, "isengard": {"heavy": "ram"}, "mordor": {"heavy": "grond"},
}

# unit look: model, visible props, tint, scale, animation set, hidden meshes
# anim sets: melee, melee2h, ranged, ranged1h, cast, worker
const UNITS = {
	"gondor":
	{
		"infantry": ["Knight", ["1H_Sword", "Badge_Shield"], STEEL, 1.0, "melee"],
		"archer": ["Rogue", ["2H_Crossbow"], Color(0.9, 0.92, 1.0), 1.0, "ranged"],
		"rider": ["Knight", ["1H_Sword", "Round_Shield"], STEEL, 0.9, "melee"],
		"special": ["Rogue_Hooded", ["2H_Crossbow"], Color(0.75, 0.9, 0.7), 1.0, "ranged"],
	},
	"rohan":
	{
		"infantry": ["Knight", ["1H_Sword", "Round_Shield"], Color(1.0, 0.92, 0.78), 1.0, "melee"],
		"archer": ["Rogue", ["2H_Crossbow"], Color(1.0, 0.93, 0.8), 1.0, "ranged"],
		"rider": ["Knight", ["1H_Sword", "Round_Shield"], Color(1.0, 0.92, 0.78), 0.9, "melee"],
		"heavy": ["Knight", ["1H_Sword", "Badge_Shield"], Color(1.0, 0.85, 0.55), 0.95, "melee"],
		"special": ["Rogue", ["1H_Crossbow"], Color(1.0, 0.93, 0.8), 0.9, "ranged1h"],
	},
	"mordor":
	{
		"infantry": ["Barbarian", ["1H_Axe", "Barbarian_Round_Shield"], ORC, 0.92, "melee"],
		"archer": ["Rogue", ["1H_Crossbow"], ORC, 0.9, "ranged1h"],
		"rider": ["Barbarian", ["1H_Axe"], ORC, 0.85, "melee"],
		"special": ["Barbarian", ["2H_Axe"], Color(0.6, 0.6, 0.55), 2.1, "melee2h"],  # Mountain Trolls
	},
	"isengard":
	{
		"infantry": ["Knight", ["1H_Sword", "Spike_Shield"], URUK, 1.05, "melee"],
		"archer": ["Rogue", ["2H_Crossbow"], URUK, 1.0, "ranged"],
		"rider": ["Barbarian", ["1H_Axe"], URUK, 0.85, "melee"],
		"special": ["Rogue", ["Throwable", "Knife"], URUK, 0.95, "melee"],
	},
}

const HEROES = {
	"aragorn": ["Rogue_Hooded", ["Knife", "Knife_Offhand"], Color(0.62, 0.66, 0.58), 1.25, "melee", []],
	"theoden": ["Knight", ["2H_Sword"], Color(1.0, 0.88, 0.6), 1.25, "melee2h", []],
	"gothmog": ["Barbarian", ["2H_Axe"], Color(0.62, 0.62, 0.5), 1.4, "melee2h", ["Barbarian_Hat"]],
	"lurtz": ["Rogue", ["2H_Crossbow"], Color(0.4, 0.36, 0.34), 1.35, "ranged", []],
	"saruman": ["Mage", ["2H_Staff"], Color(1, 1, 1), 1.25, "cast", []],  # robes whitened below
	"boromir": ["Knight", ["1H_Sword", "Badge_Shield"], Color(0.95, 0.92, 1.0), 1.3, "melee", []],
	"faramir": ["Rogue_Hooded", ["2H_Crossbow"], Color(0.6, 0.75, 0.55), 1.25, "ranged", []],
	"eomer": ["Knight", ["1H_Sword", "Round_Shield"], Color(1.0, 0.88, 0.62), 1.3, "melee", []],
	"eowyn": ["Rogue", ["Knife"], Color(1.0, 0.95, 0.85), 1.2, "melee", []],
	# the Witch-king: black armour and no face under the helm
	"witch_king": ["Knight", ["1H_Sword", "Spike_Shield"], Color(0.2, 0.2, 0.23), 1.45, "melee", ["Knight_Head"]],
	"shelob": ["spider", [], Color(0.16, 0.14, 0.13), 2.2, "", []],
	"ugluk": ["Barbarian", ["1H_Axe", "Barbarian_Round_Shield"], URUK, 1.4, "melee", ["Barbarian_Hat"]],
}

# meshes painted a flat colour instead of their texture (Saruman the White)
const RECOLOR = {
	"saruman": {
		"Mage_Hat": Color(0.93, 0.93, 0.9), "Mage_Cape": Color(0.88, 0.88, 0.86),
		"Mage_Body": Color(0.95, 0.95, 0.93), "Mage_ArmLeft": Color(0.95, 0.95, 0.93),
		"Mage_ArmRight": Color(0.95, 0.95, 0.93), "Mage_LegLeft": Color(0.9, 0.9, 0.88),
		"Mage_LegRight": Color(0.9, 0.9, 0.88),
	},
}
# the KayKit barbarian's bear-skin hat reads as a bear, not an orc: always hidden
const ALWAYS_HIDE = ["Barbarian_Hat"]

const ANIMS = {
	"melee": {"idle": "Idle", "walk": "Walking_A", "run": "Running_A",
		"attack": ["1H_Melee_Attack_Chop", "1H_Melee_Attack_Slice_Diagonal", "1H_Melee_Attack_Stab"]},
	"melee2h": {"idle": "2H_Melee_Idle", "walk": "Walking_A", "run": "Running_A",
		"attack": ["2H_Melee_Attack_Chop", "2H_Melee_Attack_Slice"]},
	"ranged": {"idle": "Idle", "walk": "Walking_A", "run": "Running_A",
		"attack": ["2H_Ranged_Shoot"]},
	"ranged1h": {"idle": "Idle", "walk": "Walking_A", "run": "Running_A",
		"attack": ["1H_Ranged_Shoot"]},
	"cast": {"idle": "Idle", "walk": "Walking_A", "run": "Running_A",
		"attack": ["Spellcast_Shoot"]},
	"rider": {"idle": "Sit_Chair_Idle", "walk": "Sit_Chair_Idle", "run": "Sit_Chair_Idle",
		"attack": ["1H_Melee_Attack_Chop", "1H_Melee_Attack_Slice_Horizontal"]},
	"rider_ranged": {"idle": "Sit_Chair_Idle", "walk": "Sit_Chair_Idle", "run": "Sit_Chair_Idle",
		"attack": ["1H_Ranged_Shoot"]},
	"worker": {"idle": "Idle", "walk": "Walking_A", "run": "Walking_A",
		"attack": ["1H_Melee_Attack_Chop"], "work": "Interact"},
}
const LOOPING = [
	"Idle", "2H_Melee_Idle", "Walking_A", "Walking_B", "Running_A", "Running_B", "Interact",
	"Sit_Chair_Idle", "Skeletons_Inactive_Floor_Pose",
]

static var _scenes = {}
static var _tinted = {}
static var _sizes = {}


# --- characters --------------------------------------------------------------------------------
static func unit_look(faction: String, unit_class: String) -> Array:
	var table = UNITS.get(faction, UNITS.gondor)
	if table.has(unit_class):
		return table[unit_class]
	return UNITS.gondor.get(unit_class, UNITS.gondor.infantry)


static func is_mounted(faction: String, unit_class: String) -> bool:
	return unit_class in MOUNTED.get(faction, DEFAULT_MOUNTED)


static func siege_kind(faction: String, unit_class: String) -> String:
	return SIEGE.get(faction, {}).get(unit_class, "")


static func character(model: String, props: Array, tint: Color, scale: float, hide = []) -> Node3D:
	var node = _scene(CHAR_DIR + model + ".glb").instantiate()
	node.name = "Model"
	node.scale = Vector3.ONE * CHARACTER_SCALE * scale
	node.rotation.y = PI  # KayKit faces +Z; our units face -Z
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var n = String(mesh.name)
		if (n in PROP_MESHES and not n in props) or n in hide or n in ALWAYS_HIDE:
			mesh.visible = false
			continue
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if tint != Color(1, 1, 1):
			_tint_mesh(mesh, tint, model)
	var player = node.find_children("*", "AnimationPlayer", true, false)
	if not player.is_empty():
		_set_loops(player[0])
		player[0].play("Idle")
		node.set_meta("anim", player[0])
	return node


static func recolor(model: Node3D, colors: Dictionary):
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		if colors.has(String(mesh.name)):
			var mat = StandardMaterial3D.new()
			mat.albedo_color = colors[String(mesh.name)]
			mat.roughness = 0.9
			mesh.material_override = mat


static func ghost(model: Node3D):
	"""Army of the Dead: translucent glowing green."""
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 1.0, 0.75, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.85, 0.5)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = mat


static func _set_loops(player: AnimationPlayer):
	for anim_name in LOOPING:
		if player.has_animation(anim_name):
			var anim = player.get_animation(anim_name)
			if anim.loop_mode != Animation.LOOP_LINEAR:
				anim.loop_mode = Animation.LOOP_LINEAR


static func _tint_mesh(mesh: MeshInstance3D, tint: Color, key: String):
	for i in range(mesh.mesh.get_surface_count()):
		var base = mesh.get_active_material(i)
		if base == null:
			continue
		var cache_key = "%s|%s|%d|%s" % [key, mesh.name, i, tint.to_html()]
		if not _tinted.has(cache_key):
			var m = base.duplicate()
			if m is BaseMaterial3D:
				m.albedo_color = m.albedo_color * tint
			_tinted[cache_key] = m
		mesh.set_surface_override_material(i, _tinted[cache_key])


# --- buildings and props ---------------------------------------------------------------------------
static func building(key: String, faction: String, footprint_radius: float) -> Node3D:
	var spec = BUILDING_MODELS.get(key)
	if spec == null:
		return null
	var color = BUILDING_COLOR.get(faction, "blue")
	var node = prop(spec[0] % color, footprint_radius * 2.0 * spec[1], BUILDING_TINT.get(faction, Color(1, 1, 1)))
	return node


static func prop(name: String, target_width: float, tint = Color(1, 1, 1)) -> Node3D:
	"""Instantiate a medieval-pack model scaled so its footprint is target_width metres wide."""
	var path = MED_DIR + name + ".gltf"
	var node = _scene(path).instantiate()
	var size = _footprint(path, node)
	var s = target_width / max(0.01, max(size.x, size.z))
	node.scale = Vector3.ONE * s
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if tint != Color(1, 1, 1):
			_tint_mesh(mesh, tint, name)
	return node


static func prop_height(name: String) -> float:
	var path = MED_DIR + name + ".gltf"
	if not _sizes.has(path):
		var n = _scene(path).instantiate()
		_footprint(path, n)
		n.free()
	return _sizes[path].y


static func _footprint(path: String, node: Node3D) -> Vector3:
	if _sizes.has(path):
		return _sizes[path]
	var aabb = AABB()
	var first = true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var a = mesh.mesh.get_aabb()
		var t = Transform3D()
		var x = mesh
		while x != node and x != null:
			t = x.transform * t
			x = x.get_parent()
		a = t * a
		aabb = a if first else aabb.merge(a)
		first = false
	_sizes[path] = aabb.size
	return aabb.size


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]
