extends Node3D
## Ground-level feedback for the local player's controls (client-side only, never replicated):
##   - green move marker / red attack marker that shrink away
##   - attack-range ring while A (attack-move) is armed
##   - skill aim: cast-range ring plus the skill's shape (line, circle at cursor, target ring)
##   - the 15m squadron command ring while a squadron is selected
##   - Recall channel ring, ping beacons

const MOVE_COLOR = Color(0.45, 1.0, 0.45, 0.9)
const ATTACK_COLOR = Color(1.0, 0.3, 0.25, 0.95)
const RANGE_COLOR = Color(1.0, 0.85, 0.4, 0.55)
const AIM_COLOR = Color(0.55, 0.85, 1.0, 0.45)
const COMMAND_COLOR = Color(0.95, 0.8, 0.35, 0.28)

var _range_ring = null
var _aim_ring = null
var _aim_line = null
var _command_ring = null
var _recall_ring = null
var _target_marker = null
var _target_unit = null


func _ready():
	_range_ring = _flat_ring(1.0, 0.06, RANGE_COLOR)
	_aim_ring = _flat_ring(1.0, 0.08, AIM_COLOR)
	_command_ring = _flat_ring(GameData.COMMAND_RANGE, 0.015, COMMAND_COLOR)
	_recall_ring = _flat_ring(1.2, 0.18, Color(0.5, 0.85, 1.0, 0.8))
	_target_marker = _flat_ring(1.0, 0.18, ATTACK_COLOR)
	_aim_line = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(1, 0.02, 1)
	_aim_line.mesh = box
	_aim_line.material_override = _material(AIM_COLOR)
	_aim_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aim_line)
	for n in [_range_ring, _aim_ring, _command_ring, _recall_ring, _target_marker, _aim_line]:
		n.visible = false


# --- persistent indicators (call every frame while needed) ------------------------------------
func show_range(center: Vector3, radius: float):
	_place_ring(_range_ring, center, radius)


func hide_range():
	_range_ring.visible = false


func show_command_ring(center: Vector3):
	_place_ring(_command_ring, center, GameData.COMMAND_RANGE)


func hide_command_ring():
	_command_ring.visible = false


func show_aim(hero_pos: Vector3, aim: Dictionary, cursor):
	"""aim: {mode: unit|self|line|point, range, radius}. cursor: ground point or null."""
	show_range(hero_pos, max(aim.get("range", 0.0), 0.5) if aim.mode != "self" else aim.get("radius", 3.0))
	_aim_ring.visible = false
	_aim_line.visible = false
	if cursor == null:
		return
	match aim.mode:
		"point":
			var to = cursor - hero_pos
			to.y = 0.0
			if to.length() > aim.range:
				to = to.normalized() * aim.range
			_place_ring(_aim_ring, hero_pos + to, aim.get("radius", 2.0))
		"line":
			var dir = cursor - hero_pos
			dir.y = 0.0
			if dir.length() < 0.1:
				return
			dir = dir.normalized()
			var length = aim.range
			_aim_line.visible = true
			_aim_line.scale = Vector3(aim.get("width", 1.2), 1, length)
			_aim_line.global_position = hero_pos + dir * length * 0.5 + Vector3(0, 0.08, 0)
			_aim_line.rotation = Vector3(0, atan2(dir.x, dir.z), 0)
		"unit":
			_place_ring(_aim_ring, cursor, 0.9)


func hide_aim():
	hide_range()
	_aim_ring.visible = false
	_aim_line.visible = false


func show_recall(center: Vector3, fraction: float):
	_recall_ring.visible = true
	_recall_ring.global_position = center + Vector3(0, 0.1, 0)
	var s = 0.6 + 0.8 * (1.0 - fraction)
	_recall_ring.scale = Vector3(s, 1, s)
	_recall_ring.rotation.y += 0.08


func hide_recall():
	_recall_ring.visible = false


func set_attack_target(unit):
	_target_unit = unit


func _process(_delta):
	if _target_unit != null and is_instance_valid(_target_unit) and _target_unit.is_alive() and _target_unit.visible:
		var r = _target_unit.get("radius")
		_place_ring(_target_marker, _target_unit.global_position, (r if r != null else 0.5) + 0.35)
	else:
		_target_unit = null
		_target_marker.visible = false


# --- one-shot markers ---------------------------------------------------------------------------
func move_marker(point: Vector3):
	_shrinking_ring(point, MOVE_COLOR, 0.9, 0.55)


func attack_marker(unit):
	set_attack_target(unit)
	_shrinking_ring(unit.global_position, ATTACK_COLOR, 1.3, 0.45)


func ping(point: Vector3, danger: bool):
	var color = Color(1.0, 0.35, 0.3) if danger else Color(1.0, 0.9, 0.4)
	for i in range(3):
		var ring = _flat_ring(0.6, 0.12, color)
		ring.global_position = point + Vector3(0, 0.12, 0)
		var tween = ring.create_tween().set_parallel(true)
		tween.tween_interval(i * 0.35)
		tween.chain().tween_property(ring, "scale", Vector3(4, 1, 4), 0.9)
		tween.parallel().tween_property(ring.material_override, "albedo_color:a", 0.0, 0.9)
		tween.chain().tween_callback(ring.queue_free)
	# a beacon pillar so it reads from far away
	var pillar = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.25
	cyl.height = 6.0
	pillar.mesh = cyl
	pillar.material_override = _material(Color(color, 0.6))
	add_child(pillar)
	pillar.global_position = point + Vector3(0, 3.0, 0)
	var t = pillar.create_tween()
	t.tween_interval(1.4)
	t.tween_property(pillar.material_override, "albedo_color:a", 0.0, 0.6)
	t.tween_callback(pillar.queue_free)


func _shrinking_ring(point: Vector3, color: Color, radius: float, time: float):
	var ring = _flat_ring(radius, 0.18, color)
	ring.global_position = point + Vector3(0, 0.1, 0)
	var tween = ring.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(0.15, 1, 0.15), time)
	tween.tween_property(ring.material_override, "albedo_color:a", 0.0, time)
	tween.chain().tween_callback(ring.queue_free)


# --- helpers -----------------------------------------------------------------------------------
func _place_ring(ring, center: Vector3, radius: float):
	ring.visible = true
	ring.global_position = Vector3(center.x, 0.09, center.z)
	ring.scale = Vector3(radius, 1, radius)


func _flat_ring(radius: float, thickness: float, color: Color) -> MeshInstance3D:
	# a unit-radius torus scaled in x/z, so one mesh serves every radius
	var mesh = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 1.0 - thickness / max(radius, 0.1)
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 3
	mesh.mesh = torus
	mesh.material_override = _material(color)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.scale = Vector3(radius, 0.05, radius)
	add_child(mesh)
	return mesh


func _material(color: Color) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
