extends "res://source/match/units/Unit.gd"
## Base for every LOTR unit and building. Replaces open-rts's action system with a small
## order "brain" (idle / move / attack) that only runs on the host. On clients, units are
## puppets whose position and HP come from the host's snapshots.

signal died_on_host

enum Order { IDLE, MOVE, ATTACK, HOLD }

const RETARGET_INTERVAL = 0.35
const REPATH_INTERVAL = 0.5

var unit_kind = "troop"  # troop | villager | hero | building
var unit_class = "infantry"  # counter class: infantry/archer/rider/heavy/special/hero/villager
var target_kind = "infantry"  # how counters see this unit as a target
var display_name = ""
var stats = {}
var spawn_params = {}  # everything the factory needs to rebuild this unit on a client
var net_id = 0
var puppet = false
var squad = null
var auto_acquire = true
var aggro_range = 0.0  # 0 means use sight range
var ranged = false
var armor = 0.0  # flat damage reduction fraction (0..0.9)
var damage_mult = 1.0
var attack_speed_mult = 1.0
var speed_mult = 1.0:
	set(value):
		speed_mult = value
		_apply_speed()
var rooted_until = 0.0
var buffs = []  # {stat, mult, until}
var last_attacker = null

var order = Order.IDLE
var order_target = null  # unit for ATTACK
var order_position = null  # Vector3 for MOVE

var _retarget_timer = 0.0
var _repath_timer = 0.0
var _next_hit_at = 0.0
var _base_speed = 0.0
var _movement = null


func _ready():
	await super()
	_movement = find_child("Movement")
	if _movement != null:
		_base_speed = _movement.speed
		_apply_speed()
	if puppet:
		_make_puppet()


func is_alive():
	return is_inside_tree() and hp != null and hp > 0 and is_in_group("units")


func is_enemy_of(other):
	if other == null or not is_instance_valid(other) or not "player" in other:
		return false
	return Teams.is_enemy(player, other.player)


func is_revealing():
	return super() and is_alive()


# --- orders (host only) ---------------------------------------------------------------------
func order_move(position: Vector3):
	order = Order.MOVE
	order_position = position
	order_target = null
	if _movement != null:
		_movement.move(position)


func order_attack(target):
	if target == null or not is_instance_valid(target):
		return
	order = Order.ATTACK
	order_target = target
	_repath_timer = 0.0


func order_stop():
	order = Order.IDLE
	order_target = null
	if _movement != null:
		_movement.stop()


func order_hold():
	order_stop()
	order = Order.HOLD


func _physics_process(delta):
	if puppet or not is_alive():
		return
	_expire_buffs()
	_brain(delta)


# --- buffs --------------------------------------------------------------------------------------
func apply_buff(stat: String, mult: float, duration: float):
	"""stat: damage | attack_speed | speed. Same stat buffs don't stack; the stronger one wins."""
	var until = GameData.now() + duration
	buffs = buffs.filter(func(b): return b.stat != stat or b.mult > mult)
	buffs.append({"stat": stat, "mult": mult, "until": until})
	_recompute_buffs()


func _expire_buffs():
	if buffs.is_empty():
		return
	var now = GameData.now()
	var before = buffs.size()
	buffs = buffs.filter(func(b): return b.until > now)
	if buffs.size() != before:
		_recompute_buffs()


func _recompute_buffs():
	var mults = {"damage": 1.0, "attack_speed": 1.0, "speed": 1.0}
	for b in buffs:
		mults[b.stat] = max(mults[b.stat], b.mult)
	damage_mult = mults.damage
	attack_speed_mult = mults.attack_speed
	speed_mult = mults.speed


func _brain(delta):
	if GameData.now() < rooted_until and _movement != null:
		_movement.stop()
	match order:
		Order.MOVE:
			if _movement == null or _movement.target_position == Vector3.INF:
				order = Order.IDLE
			elif global_position_yless.distance_to(order_position * Vector3(1, 0, 1)) < 0.6:
				order_stop()
		Order.ATTACK:
			_process_attack(delta)
		Order.IDLE, Order.HOLD:
			_process_idle(delta)


func _process_idle(delta):
	if not auto_acquire or attack_damage == null:
		return
	_retarget_timer -= delta
	if _retarget_timer > 0.0:
		return
	_retarget_timer = RETARGET_INTERVAL
	var reach = attack_range if order == Order.HOLD else _acquire_range()
	var enemy = Combat.closest_enemy(self, global_position, reach)
	if enemy == null:
		return
	if order == Order.HOLD or _movement == null:
		_try_hit(enemy)  # stationary: only shoot what is in range
	else:
		order_attack(enemy)


func _acquire_range():
	return aggro_range if aggro_range > 0.0 else sight_range


func _process_attack(delta):
	if order_target == null or not is_instance_valid(order_target) or not order_target.is_alive():
		order_stop()
		return
	var distance = global_position_yless.distance_to(order_target.global_position_yless)
	var reach = attack_range + _target_radius(order_target)
	if distance > reach:
		if _movement == null:
			order_stop()
			return
		_repath_timer -= delta
		if _repath_timer <= 0.0:
			_repath_timer = REPATH_INTERVAL
			_movement.move(order_target.global_position)
		return
	if _movement != null and _movement.target_position != Vector3.INF:
		_movement.stop()
	_face(order_target.global_position)
	_try_hit(order_target)


func _target_radius(target):
	var r = target.get("radius")
	return r if r != null else 0.5


func _try_hit(target):
	var now = GameData.now()
	if now < _next_hit_at:
		return
	var distance = global_position_yless.distance_to(target.global_position_yless)
	if distance > attack_range + _target_radius(target) + 0.2:
		return
	_next_hit_at = now + attack_interval / attack_speed_mult
	Combat.attack(self, target, attack_damage * damage_mult)


func _face(point: Vector3):
	var flat = Vector3(point.x, global_position.y, point.z)
	if flat.distance_to(global_position) > 0.05:
		global_transform = global_transform.looking_at(flat, Vector3.UP)


func _apply_speed():
	if _movement != null and _base_speed > 0.0:
		_movement.speed = _base_speed * speed_mult


# --- stats ------------------------------------------------------------------------------------
func _setup_default_properties_from_constants():
	hp_max = int(stats.get("hp", 100))
	hp = hp_max
	if stats.has("damage"):
		attack_damage = stats.damage
		attack_interval = stats.get("interval", 1.0)
		attack_range = stats.get("range", 1.5)
		attack_domains = [Constants.Match.Navigation.Domain.TERRAIN]
	sight_range = stats.get("sight", 8.0)
	ranged = stats.get("ranged", false)


func _setup_color():
	var material = player.get_color_material()
	for node in find_children("*", "MeshInstance3D", true, false):
		if node.has_meta("team_color"):
			node.material_override = material


func _safety_checks():
	return true


func _set_action(action_node):
	# LOTR units don't use open-rts actions; keep the property inert
	if action_node != null:
		action_node.queue_free()


func _handle_unit_death():
	died_on_host.emit()
	super()


# --- puppets (clients) ------------------------------------------------------------------------
func _make_puppet():
	set_physics_process(false)
	if _movement != null:
		_movement.avoidance_enabled = false
		_movement.process_mode = Node.PROCESS_MODE_DISABLED
