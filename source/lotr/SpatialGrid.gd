class_name SpatialGrid
## A uniform grid over the map, rebuilt lazily once per physics frame, so "who is near this
## point?" looks at a few cells instead of every unit in the match. With 100+ soldiers each
## searching for enemies several times a second, this keeps target search roughly linear.

const CELL = 6.0

static var _cells = {}
static var _built_frame = -1
static var _tree: SceneTree = null


static func _key(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL), floori(z / CELL))


static func _ensure(tree: SceneTree):
	var frame = Engine.get_physics_frames()
	if frame == _built_frame and tree == _tree:
		return
	_built_frame = frame
	_tree = tree
	_cells.clear()
	for u in tree.get_nodes_in_group("units"):
		if not u.is_inside_tree():
			continue
		var p = u.global_position
		var k = _key(p.x, p.z)
		if _cells.has(k):
			_cells[k].append(u)
		else:
			_cells[k] = [u]


static func near(tree: SceneTree, from: Vector3, radius: float) -> Array:
	"""Units whose position is within the cells covering the circle (callers still check the
	exact distance). Includes dead units that haven't left the tree yet."""
	_ensure(tree)
	var result = []
	var lo = _key(from.x - radius, from.z - radius)
	var hi = _key(from.x + radius, from.z + radius)
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			var bucket = _cells.get(Vector2i(x, z))
			if bucket != null:
				result.append_array(bucket)
	return result


static func invalidate():
	_built_frame = -1
