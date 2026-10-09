class_name MapGen
## Builds the 2-team "Middle-earth" battlefield (v3). Deterministic from the seed so the host
## and every client generate the same map (resource nodes get the same net ids in the same order).
##
## LoL-style diagonal: team 1's city bottom-left, team 2's top-right. Three winding roads join
## them; each road has two forgotten towers (one nearer each city). Two jungles (one per side)
## hide monster lairs that guard the richest mines; two Cave Troll pits flank the middle.
##
##        TL ---TT1---------- B1          B = city (Town Center), T = forgotten tower,
##        |               /   |          M = middle-road tower, P = troll pit.
##       TT0     P0     M1    BT1
##        |          C        |
##       ...  M0       P1    ...
##        B0 ---BT0---------- BR

const MapScene = preload("res://source/match/Map.tscn")

const SIZE = 150.0
const INSET = 26.0  # Town Centers this far in from their corner
const EDGE = 14.0  # the top and bottom roads bend through corners this far from the edge
const LANE_STEP = 8.0
const LANE_CLEARANCE = 5.0
const HILL_TINT = Color(0.62, 0.7, 0.5)  # calms the pack's bright yellow grass to a meadow green
const GRASS = Color("5c7d3a")

# road graph edges: node ids (see road_nodes); "name" is what the HUD shows
const ROAD_DEFS = [
	["B0", "TT0"], ["TT0", "TL"], ["TL", "TT1"], ["TT1", "B1"],
	["B0", "M0"], ["M0", "C"], ["C", "M1"], ["M1", "B1"],
	["B0", "BT0"], ["BT0", "BR"], ["BR", "BT1"], ["BT1", "B1"],
]
const TOWER_NAMES = {
	"TT0": "Top road (south)", "TT1": "Top road (north)", "M0": "Middle road (south)",
	"M1": "Middle road (north)", "BT0": "Bottom road (west)", "BT1": "Bottom road (east)",
}


static func spawn_points() -> Array:
	"""One city per team: index 0 = team 1 (bottom-left), 1 = team 2 (top-right)."""
	return [Vector3(INSET, 0, SIZE - INSET), Vector3(SIZE - INSET, 0, INSET)]


static func road_nodes() -> Dictionary:
	var c = SIZE / 2.0
	var b = spawn_points()
	var nodes = {
		"B0": b[0], "B1": b[1], "C": Vector3(c, 0, c),
		"TL": Vector3(EDGE, 0, EDGE), "BR": Vector3(SIZE - EDGE, 0, SIZE - EDGE),
	}
	nodes["TT0"] = Vector3(EDGE + 2.0, 0, c + 8.0)
	nodes["TT1"] = Vector3(c - 8.0, 0, EDGE + 2.0)
	nodes["BT0"] = Vector3(c + 8.0, 0, SIZE - EDGE - 2.0)
	nodes["BT1"] = Vector3(SIZE - EDGE - 2.0, 0, c - 8.0)
	nodes["M0"] = b[0].lerp(nodes.C, 0.55)
	nodes["M1"] = b[1].lerp(nodes.C, 0.55)
	return nodes


static func pit_sites() -> Array:
	"""The two Cave Troll pits, either side of the middle road."""
	var c = SIZE / 2.0
	return [Vector3(c - 24.0, 0, c - 24.0), Vector3(c + 24.0, 0, c + 24.0)]


static func jungle_sites(side: int) -> Array:
	"""Centres of a team's two jungle quarters (between its middle road and its side roads)."""
	var n = road_nodes()
	var b = n["B%d" % side]
	return [(b + n.TL + n.C) / 3.0, (b + n.BR + n.C) / 3.0]


static func tower_sites() -> Array:
	"""Forgotten towers: [{id, name, pos}] in a fixed order (index = tower number)."""
	var nodes = road_nodes()
	var out = []
	for id in ["TT0", "TT1", "M0", "M1", "BT0", "BT1"]:
		out.append({"id": id, "name": TOWER_NAMES[id], "pos": nodes[id]})
	return out


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
	_place_tower_ruins(map)
	_place_decorations(map, rng, spawns, lanes)
	return map


static func _place_tower_ruins(map):
	# the forgotten towers start as overgrown ruins; a claimed tower is built on top
	var root = map.find_child("Decorations")
	for site in tower_sites():
		var ruin = Art.prop("building_destroyed", 3.4, Color(0.75, 0.78, 0.72))
		ruin.position = site.pos
		ruin.rotation.y = site.pos.x * 0.37
		root.add_child(ruin)
		var stone = Art.prop("rock_single_D", 1.2, Color(0.8, 0.8, 0.78))
		stone.position = site.pos + Vector3(2.2, 0, 1.4)
		root.add_child(stone)
		# broken temple columns ring the old tower
		for k in range(4):
			var ang = site.pos.x * 0.37 + TAU * k / 4.0 + 0.4
			var at = site.pos + Vector3(cos(ang), 0, sin(ang)) * 3.3
			var height = 1 + (k + int(site.pos.z)) % 3
			for level in range(height):
				var piece = Art.kit("Pillar_Large_Base" if level == 0 else "Pillar_Large_Middle", 1.2)
				piece.position = at + Vector3(0, level * 1.2, 0)
				root.add_child(piece)
			var rubble = Art.kit("Prop_Rubble_%d" % (1 + k % 2), 1.6)
			rubble.position = at + Vector3(0.9, 0, 0.5)
			rubble.rotation.y = ang
			root.add_child(rubble)


static func build_lanes() -> Array:
	"""Every road as {index, a, b, name, points}; a and b are road node ids."""
	var nodes = road_nodes()
	var lanes = []
	for i in range(ROAD_DEFS.size()):
		var a_id = ROAD_DEFS[i][0]
		var b_id = ROAD_DEFS[i][1]
		var a = nodes[a_id]
		var b = nodes[b_id]
		var dir = (b - a).normalized()
		var start = a + (dir * 6.0 if a_id.begins_with("B") else Vector3.ZERO)
		var end = b - (dir * 6.0 if b_id.begins_with("B") else Vector3.ZERO)
		var length = start.distance_to(end)
		# roads wind: an S-curve offset sideways from the straight line, zero at both ends
		var side = Vector3(-dir.z, 0, dir.x)
		var amplitude = 5.5
		var steps = maxi(2, int(length / 4.0))
		var points = []
		for s in range(steps + 1):
			var t = float(s) / steps
			var p = start.lerp(end, t) + side * amplitude * sin(TAU * t) * sin(PI * t) * (1.0 if i % 2 == 0 else -1.0)
			p.x = clamp(p.x, 6.0, SIZE - 6.0)
			p.z = clamp(p.z, 6.0, SIZE - 6.0)
			points.append(p)
		lanes.append({"index": i, "a": a_id, "b": b_id, "name": "%s-%s" % [a_id, b_id], "points": points})
	return lanes


static func route(lanes: Array, from_node: String, to_node: String) -> Array:
	"""Waypoints along the roads from one node to another (Dijkstra on the road graph)."""
	var dist = {from_node: 0.0}
	var prev = {}
	var open = [from_node]
	var done = {}
	while not open.is_empty():
		open.sort_custom(func(x, y): return dist[x] < dist[y])
		var n = open.pop_front()
		if done.has(n):
			continue
		done[n] = true
		if n == to_node:
			break
		for lane in lanes:
			var other = lane.b if lane.a == n else (lane.a if lane.b == n else "")
			if other == "" or done.has(other):
				continue
			var nd = dist[n] + lane.points[0].distance_to(lane.points[-1])
			if nd < dist.get(other, INF):
				dist[other] = nd
				prev[other] = [n, lane]
				open.append(other)
	if not prev.has(to_node) and from_node != to_node:
		return []
	var chain = []
	var cur = to_node
	while cur != from_node:
		chain.push_front(prev[cur])
		cur = prev[cur][0]
	var points = []
	for step in chain:
		var lane = step[1]
		var pts = lane.points.duplicate()
		if lane.a != step[0]:
			pts.reverse()
		points.append_array(pts)
	return points


static func nearest_node(point: Vector3) -> String:
	var best = ""
	var best_d = INF
	var nodes = road_nodes()
	for id in nodes:
		var d = nodes[id].distance_to(point)
		if d < best_d:
			best_d = d
			best = id
	return best


static func camp_sites() -> Array:
	"""Two jungle quarters per team with a spider nest and a warg den each (each guarding a
	rich mine), the two Cave Troll pits, and deer herds in the open land behind each city."""
	var lanes = build_lanes()
	var sites = []
	for pit in pit_sites():
		sites.append({"camp": "troll", "pos": pit})
	var c = Vector3(SIZE / 2.0, 0, SIZE / 2.0)
	for side in range(2):
		var quarters = jungle_sites(side)
		for q in range(quarters.size()):
			var centre = quarters[q]
			var across = (centre - c).normalized()
			var side_dir = Vector3(-across.z, 0, across.x)
			sites.append({"camp": "spiders" if q == 0 else "wargs", "pos": _push_off_lanes(centre + side_dir * 7.0, lanes)})
			sites.append({"camp": "wargs" if q == 0 else "spiders", "pos": _push_off_lanes(centre - side_dir * 7.0, lanes)})
	for spawn in spawn_points():
		var away = (spawn - c).normalized()
		var ang = atan2(away.z, away.x)
		for off in [-1.1, 1.1]:
			var p = spawn + Vector3(cos(ang + off), 0, sin(ang + off)) * 17.0
			sites.append({"camp": "herd", "pos": _push_off_lanes(p, lanes)})
	return sites


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
			# a round patch at each joint so bends have no gaps
			var joint = MeshInstance3D.new()
			var disc = CylinderMesh.new()
			disc.top_radius = 1.6
			disc.bottom_radius = 1.6
			disc.height = 0.01
			disc.radial_segments = 12
			joint.mesh = disc
			joint.material_override = dirt
			joint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			joint.position = b + Vector3(0, 0.065, 0)
			root.add_child(joint)


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
		["wood", 13.0, 0.0, 6], ["wood", 15.0, 1.25, 6], ["food", 10.0, 0.55, 5],
		["stone", 12.0, 0.95, 2], ["iron", 14.0, -0.3, 2], ["wood", 16.0, -0.9, 5],
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
	# rich mines inside every jungle lair: villagers only work them once a hero clears the lair
	for site in camp_sites():
		if site.camp == "herd":
			continue
		var types = ["iron", "stone", "iron"] if site.camp == "troll" else (["stone", "stone"] if site.camp == "spiders" else ["iron", "iron"])
		for k in range(types.size()):
			var ang = TAU * k / types.size() + 0.5
			var p = site.pos + Vector3(cos(ang), 0, sin(ang)) * 4.2
			_add_resource(root, types[k], p, placed, counter)


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
		["nature/CommonTree_1", 2.2, 3.0], ["nature/CommonTree_2", 2.2, 3.0],
		["nature/CommonTree_3", 2.2, 3.0], ["nature/Pine_1", 1.8, 2.4], ["nature/Pine_2", 1.8, 2.4],
		["nature/Pine_3", 1.8, 2.4], ["nature/DeadTree_1", 1.8, 2.4], ["nature/TwistedTree_1", 2.2, 2.8],
		["nature/TwistedTree_2", 2.2, 2.8], ["nature/Bush_Common", 1.0, 1.4],
		["nature/Bush_Common_Flowers", 1.0, 1.4], ["hills_A_trees", 6.0, 8.0],
		["hills_B_trees", 6.0, 8.0], ["hills_C_trees", 6.0, 8.0], ["nature/Rock_Medium_1", 1.2, 1.8],
		["nature/Rock_Medium_2", 1.2, 1.8], ["nature/Rock_Medium_3", 1.2, 1.8],
	]
	var placed = 0
	var attempts = 0
	while placed < 140 and attempts < 1500:
		attempts += 1
		var p = Vector3(rng.randf_range(4, SIZE - 4), 0, rng.randf_range(4, SIZE - 4))
		var pick = scenery[rng.randi() % scenery.size()]
		var width = rng.randf_range(pick[1], pick[2])
		if _distance_to_lanes(p, lanes) < LANE_CLEARANCE + width * 0.5 + 1.0:
			continue
		if spawns.any(func(sp): return sp.distance_to(p) < GameData.BASE_RADIUS + 3.0):
			continue
		if camp_sites().any(func(c): return c.pos.distance_to(p) < 6.0 + width * 0.5):
			continue
		if tower_sites().any(func(t): return t.pos.distance_to(p) < 7.0 + width * 0.5):
			continue
		var prop = Art.prop(pick[0], width, HILL_TINT if pick[0].begins_with("hills") else Color(1, 1, 1))
		prop.position = p
		prop.rotation.y = rng.randf() * TAU
		root.add_child(prop)
		placed += 1
	# roadside waystations: a cart, barrels, a lamp or a well halfway along each road
	var sets = [["Prop_Cart_1_Hay", "Prop_Barrel_1", "Prop_Lamp_Street"], ["Prop_Well_1", "Prop_Crate_1", "Prop_Hay_1"],
		["Prop_Cart_1_Barrels", "Prop_Hay_1", "Prop_Barrel_1"]]
	for lane in lanes:
		var pts = lane.points
		if pts.size() < 3:
			continue
		var mid = pts[pts.size() / 2]
		var dir = (pts[pts.size() / 2 + 1] - pts[pts.size() / 2 - 1]).normalized()
		var side = Vector3(-dir.z, 0, dir.x) * (1 if lane.index % 2 == 0 else -1)
		var base = mid + side * (LANE_CLEARANCE + 1.8)
		if camp_sites().any(func(c): return c.pos.distance_to(base) < 7.0):
			continue
		if tower_sites().any(func(t): return t.pos.distance_to(base) < 7.0):
			continue
		var set = sets[lane.index % sets.size()]
		for k in range(set.size()):
			var piece = Art.kit(set[k], 1.15)
			piece.position = base + dir * (k - 1) * 1.6
			piece.rotation.y = atan2(dir.x, dir.z) + rng.randf_range(-0.3, 0.3)
			root.add_child(piece)
