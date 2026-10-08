class_name MapGen
## Builds the 4-base, 6-lane "Middle-earth" map. Deterministic from the seed so the host and
## every client generate the same map (resource nodes get the same net ids in the same order).
##
##  base 0 (Gondor) ------- north lane ------- base 1 (Mordor)
##        |   \                               /   |
##   west lane   diagonal         diagonal    east lane
##        |   /                               \   |
##  base 2 (Rohan) -------- south lane ------- base 3 (Isengard)

const MapScene = preload("res://source/match/Map.tscn")

const SIZE = 140.0
const INSET = 16.0
const LANE_STEP = 8.0
const LANE_CLEARANCE = 5.0
const HILL_TINT = Color(0.62, 0.7, 0.5)  # calms the pack's bright yellow grass to a meadow green
const GRASS = Color("5c7d3a")

# lanes: pairs of spawn indices. With the default teams (0+2 vs 1+3) the west and east edges
# are the ally routes, the rest are enemy lanes.
const LANE_DEFS = [
	{"a": 0, "b": 1, "name": "North"},
	{"a": 2, "b": 3, "name": "South"},
	{"a": 0, "b": 2, "name": "West"},
	{"a": 1, "b": 3, "name": "East"},
	{"a": 0, "b": 3, "name": "Diagonal NW-SE"},
	{"a": 1, "b": 2, "name": "Diagonal NE-SW"},
]


static func spawn_points() -> Array:
	return [
		Vector3(INSET, 0, INSET),
		Vector3(SIZE - INSET, 0, INSET),
		Vector3(INSET, 0, SIZE - INSET),
		Vector3(SIZE - INSET, 0, SIZE - INSET),
	]


static func build(seed_value: int) -> Node3D:
	var map = MapScene.instantiate()
	map.size = Vector2(SIZE, SIZE)
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	var spawns = spawn_points()
	var spawn_root = map.find_child("SpawnPoints")
	for i in range(spawns.size()):
		var marker = Marker3D.new()
		marker.name = "Spawn%d" % i
		marker.position = spawns[i]
		spawn_root.add_child(marker)
	var grass = StandardMaterial3D.new()
	grass.albedo_color = GRASS
	grass.roughness = 1.0
	map.find_child("Terrain").material_override = grass
	# land continues past the playable area so the edges aren't a black void
	var outer = MeshInstance3D.new()
	var outer_mesh = PlaneMesh.new()
	outer_mesh.size = Vector2(SIZE + 160, SIZE + 160)
	outer.mesh = outer_mesh
	var outer_mat = StandardMaterial3D.new()
	outer_mat.albedo_color = GRASS.darkened(0.12)
	outer_mat.roughness = 1.0
	outer.material_override = outer_mat
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	outer.position = Vector3(SIZE / 2.0, -0.05, SIZE / 2.0)
	map.find_child("Decorations").add_child(outer)
	var lanes = build_lanes()
	map.set_meta("lanes", lanes)
	_paint_lanes(map, lanes)
	_place_resources(map, rng, spawns, lanes)
	_place_decorations(map, rng, spawns, lanes)
	return map


static func build_lanes() -> Array:
	var spawns = spawn_points()
	var lanes = []
	for i in range(LANE_DEFS.size()):
		var d = LANE_DEFS[i]
		var a = spawns[d.a]
		var b = spawns[d.b]
		var points = []
		var dir = (b - a).normalized()
		var start = a + dir * 6.0
		var end = b - dir * 6.0
		var length = start.distance_to(end)
		var steps = maxi(2, int(length / LANE_STEP))
		for s in range(steps + 1):
			points.append(start.lerp(end, float(s) / steps))
		lanes.append({"index": i, "a": d.a, "b": d.b, "name": d.name, "points": points})
	return lanes


static func lane_points_from(lane: Dictionary, spawn_index: int) -> Array:
	"""Lane waypoints ordered starting at the given base."""
	var points = lane.points.duplicate()
	if lane.b == spawn_index:
		points.reverse()
	return points


static func lanes_for(spawn_index: int) -> Array:
	return build_lanes().filter(func(l): return l.a == spawn_index or l.b == spawn_index)


static func _paint_lanes(map, lanes):
	# dirt roads so lanes are readable on the ground
	var dirt = StandardMaterial3D.new()
	dirt.albedo_color = Color("8a7350")
	dirt.roughness = 1.0
	var root = map.find_child("Decorations")
	for lane in lanes:
		var pts = lane.points
		for i in range(pts.size() - 1):
			var a = pts[i]
			var b = pts[i + 1]
			var road = MeshInstance3D.new()
			var plane = PlaneMesh.new()
			plane.size = Vector2(3.2, a.distance_to(b) + 0.4)
			road.mesh = plane
			road.material_override = dirt
			road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			road.position = (a + b) / 2.0 + Vector3(0, 0.06, 0)
			road.rotation.y = atan2(b.x - a.x, b.z - a.z)
			root.add_child(road)


static func _distance_to_lanes(point: Vector3, lanes: Array) -> float:
	var best = INF
	var p = Vector2(point.x, point.z)
	for lane in lanes:
		var pts = lane.points
		for i in range(pts.size() - 1):
			var a = Vector2(pts[i].x, pts[i].z)
			var b = Vector2(pts[i + 1].x, pts[i + 1].z)
			var closest = Geometry2D.get_closest_point_to_segment(p, a, b)
			best = min(best, p.distance_to(closest))
	return best


static func _place_resources(map, rng, spawns, lanes):
	var root = map.find_child("Resources")
	var placed = []
	var counter = [0]
	# each base gets the same layout, rotated to face the map centre
	var layout = [
		["wood", 13.0, 0.0, 6], ["wood", 15.0, 1.25, 5], ["food", 10.0, 0.55, 4],
		["stone", 12.0, 0.95, 3], ["iron", 14.0, -0.3, 3],
	]
	var center = Vector3(SIZE / 2.0, 0, SIZE / 2.0)
	for spawn in spawns:
		var to_center = (center - spawn).normalized()
		var base_angle = atan2(to_center.z, to_center.x)
		for entry in layout:
			var angle = base_angle + PI / 4.0 + entry[2] * 1.6 - 0.9
			var cluster_center = spawn + Vector3(cos(angle), 0, sin(angle)) * entry[1]
			cluster_center = _push_off_lanes(cluster_center, lanes)
			for n in range(entry[3]):
				var p = cluster_center + Vector3(rng.randf_range(-2.5, 2.5), 0, rng.randf_range(-2.5, 2.5))
				_add_resource(root, entry[0], p, placed, counter)
	# contested mid-map resources between the lanes
	for q in [Vector3(0.5, 0, 0.25), Vector3(0.75, 0, 0.5), Vector3(0.5, 0, 0.75), Vector3(0.25, 0, 0.5)]:
		var c = Vector3(SIZE * q.x, 0, SIZE * q.z)
		c = _push_off_lanes(c, lanes)
		for type in ["iron", "stone", "wood", "wood"]:
			var p = c + Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-5, 5))
			_add_resource(root, type, p, placed, counter)


static func _push_off_lanes(point: Vector3, lanes: Array) -> Vector3:
	# nudge toward the map centre's perpendicular until clear of all lanes
	var p = point
	for i in range(12):
		if _distance_to_lanes(p, lanes) >= LANE_CLEARANCE + 3.0:
			break
		var away = Vector3(SIZE / 2.0, 0, SIZE / 2.0) - p
		p += Vector3(-away.z, 0, away.x).normalized() * 1.5
	return p


static func _add_resource(root, type, point, placed, counter):
	point.x = clamp(point.x, 3.0, SIZE - 3.0)
	point.z = clamp(point.z, 3.0, SIZE - 3.0)
	for other in placed:
		if other.distance_to(point) < 1.6:
			return
	placed.append(point)
	var node = UnitFactory.create({"kind": "resource", "type": type, "seed": counter[0]})
	node.position = point
	node.name = "Resource%d" % counter[0]
	counter[0] += 1
	root.add_child(node)


static func _place_decorations(map, rng, spawns, lanes):
	var root = map.find_child("Decorations")
	# mountain ranges frame the map
	# The camera looks north, so only the far (north) edge gets tall peaks; the near edges get
	# low hills pushed well outside the map so they never hide anything on the field.
	var rock_tint = Color(0.72, 0.7, 0.66)
	var step = 7.0
	var t = -6.0
	while t <= SIZE + 6.0:
		var edges = [
			[Vector3(t, 0, -5), ["mountain_A", "mountain_B", "mountain_C"], 10.0, 13.0, 0.8, 1.2],
			[Vector3(-7, 0, t), ["mountain_A", "mountain_B", "hills_A_trees"], 8.0, 10.0, 0.5, 0.7],
			[Vector3(SIZE + 7, 0, t), ["mountain_A", "mountain_B", "hills_B_trees"], 8.0, 10.0, 0.5, 0.7],
			[Vector3(t, 0, SIZE + 9), ["hills_A_trees", "hills_B_trees", "hills_C_trees"], 8.0, 10.0, 0.35, 0.5],
		]
		for e in edges:
			var pick = e[1][rng.randi() % e[1].size()]
			var m = Art.prop(pick, rng.randf_range(e[2], e[3]), rock_tint if pick.begins_with("mountain") else HILL_TINT)
			m.position = e[0] + Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
			m.rotation.y = rng.randf() * TAU
			m.scale.y *= rng.randf_range(e[4], e[5])
			root.add_child(m)
		t += step
	# forests, hills and boulders between the lanes
	var scenery = [
		["trees_A_large", 4.5, 5.5], ["trees_B_large", 4.5, 5.5], ["trees_A_medium", 3.0, 4.0],
		["tree_single_A", 1.2, 1.6], ["tree_single_B", 1.2, 1.6], ["hills_A_trees", 6.0, 8.0],
		["hills_B_trees", 6.0, 8.0], ["hills_C_trees", 6.0, 8.0], ["rock_single_B", 1.0, 1.6],
		["rock_single_D", 1.0, 1.6],
	]
	var placed = 0
	var attempts = 0
	while placed < 110 and attempts < 1200:
		attempts += 1
		var p = Vector3(rng.randf_range(4, SIZE - 4), 0, rng.randf_range(4, SIZE - 4))
		var pick = scenery[rng.randi() % scenery.size()]
		var width = rng.randf_range(pick[1], pick[2])
		if _distance_to_lanes(p, lanes) < LANE_CLEARANCE + width * 0.5 + 1.0:
			continue
		if spawns.any(func(sp): return sp.distance_to(p) < GameData.BASE_RADIUS + 3.0):
			continue
		var prop = Art.prop(pick[0], width, HILL_TINT if pick[0].begins_with("hills") else Color(1, 1, 1))
		prop.position = p
		prop.rotation.y = rng.randf() * TAU
		root.add_child(prop)
		placed += 1
