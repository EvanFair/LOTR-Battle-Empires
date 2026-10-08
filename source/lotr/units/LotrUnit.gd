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
var attack_speed_bonus = 0.0  # from items (+0.15 = 15% faster)
var speed_bonus = 0.0  # from items
var speed_mult = 1.0:
	set(value):
		speed_mult = value
		_apply_speed()
var rooted_until = 0.0
var stunned_until = 0.0
var buffs = []  # {stat, mult, until}; mult > 1 is a buff, < 1 a debuff (slow, weaken)
var _base_armor = -1.0
var last_attacker = null
var anim_driver = null
var last_attack_at = -10.0  # game time of the latest swing (replicated so puppets animate too)

var order = Order.IDLE
var order_target = null  # unit for ATTACK
var order_position = null  # Vector3 for MOVE
var attack_move_target = null  # Vector3 while attack-moving: fight anything met on the way
var _pending_hit = null  # {target, at}: the swing has started, the blow lands at "at"

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
	attack_move_target = null
	_pending_hit = null  # moving cancels a swing that hasn't landed yet (kiting)
	if _movement != null:
		_movement.move(position)


func order_attack_move(position: Vector3):
	"""Walk to position, stopping to fight any enemy met on the way, then carry on."""
	order_move(position)
	attack_move_target = position
	_retarget_timer = 0.0


func order_attack(target, keep_attack_move = false):
	if target == null or not is_instance_valid(target):
		return
	var resume = attack_move_target if keep_attack_move else null
	order = Order.ATTACK
	order_target = target
	attack_move_target = resume
	_repath_timer = 0.0


func order_stop():
	order = Order.IDLE
	order_target = null
	attack_move_target = null
	_pending_hit = null
	if _movement != null:
		_movement.stop()


func order_hold():
	order_stop()
	order = Order.HOLD


func _physics_process(delta):
	if puppet or not is_alive():
		return
	_expire_buffs()
	_land_pending_hit()
	_brain(delta)


# --- buffs --------------------------------------------------------------------------------------
func apply_buff(stat: String, mult: float, duration: float):
	"""stat: damage | attack_speed | speed (multipliers) or armor (added, e.g. 0.3).
	The strongest buff and the strongest debuff of a stat apply; same-sign ones don't stack."""
	var until = GameData.now() + duration
	var debuff = mult < 1.0 and stat != "armor"
	buffs = buffs.filter(func(b):
		if b.stat != stat or (b.mult < 1.0 and stat != "armor") != debuff:
			return true
		return (b.mult < mult) if debuff else (b.mult > mult))
	buffs.append({"stat": stat, "mult": mult, "until": until})
	_recompute_buffs()


func stun(duration: float):
	stunned_until = max(stunned_until, GameData.now() + duration)
	_pending_hit = null
	if _movement != null:
		_movement.stop()


func is_stunned() -> bool:
	return GameData.now() < stunned_until


func is_rooted() -> bool:
	return GameData.now() < rooted_until or is_stunned()


func _expire_buffs():
	if buffs.is_empty():
		return
	var now = GameData.now()
	var before = buffs.size()
	buffs = buffs.filter(func(b): return b.until > now)
	if buffs.size() != before:
		_recompute_buffs()


func _recompute_buffs():
	var up = {"damage": 1.0, "attack_speed": 1.0, "speed": 1.0}
	var down = {"damage": 1.0, "attack_speed": 1.0, "speed": 1.0}
	var armor_bonus = 0.0
	for b in buffs:
		if b.stat == "armor":
			armor_bonus = max(armor_bonus, b.mult)
		elif b.mult >= 1.0:
			up[b.stat] = max(up[b.stat], b.mult)
		else:
			down[b.stat] = min(down[b.stat], b.mult)
	damage_mult = up.damage * down.damage
	attack_speed_mult = up.attack_speed * down.attack_speed
	speed_mult = up.speed * down.speed
	if _base_armor < 0.0:
		_base_armor = armor
	armor = min(0.9, _base_armor + armor_bonus)


func _brain(delta):
	if is_stunned():
		if _movement != null:
			_movement.stop()
		return
	if GameData.now() < rooted_until and _movement != null:
		_movement.stop()
	match order:
		Order.MOVE:
			if attack_move_target != null and _scan_attack_move(delta):
				return
			if _movement == null or _movement.target_position == Vector3.INF:
				order = Order.IDLE
				attack_move_target = null
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


func _scan_attack_move(delta) -> bool:
	_retarget_timer -= delta
	if _retarget_timer > 0.0:
		return false
	_retarget_timer = RETARGET_INTERVAL
	var enemy = Combat.closest_enemy(self, global_position, max(attack_range + 2.0, _acquire_range()))
	if enemy == null:
		return false
	order_attack(enemy, true)
	return true


func _process_attack(delta):
	if order_target == null or not is_instance_valid(order_target) or not order_target.is_alive():
		if attack_move_target != null:
			order_attack_move(attack_move_target)  # target down: carry on to the destination
		else:
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
	_next_hit_at = now + attack_interval / (attack_speed_mult * (1.0 + attack_speed_bonus))
	_face(target.global_position)
	notify_attack()
	# the blow lands partway into the swing (or the arrow leaves the string); towers fire at once
	var windup = min(0.3, attack_interval * 0.3) / attack_speed_mult
	if unit_kind == "building" or windup < 0.05:
		Combat.attack(self, target, attack_damage * damage_mult)
	else:
		_pending_hit = {"target": target, "at": now + windup}


func _land_pending_hit():
	if _pending_hit == null or GameData.now() < _pending_hit.at:
		return
	var target = _pending_hit.target
	_pending_hit = null
	if target == null or not is_instance_valid(target) or not target.is_alive():
		return
	if global_position_yless.distance_to(target.global_position_yless) > attack_range + _target_radius(target) + 1.0:
		return
	Combat.attack(self, target, attack_damage * damage_mult)


func notify_attack():
	last_attack_at = GameData.now()
	if anim_driver != null:
		anim_driver.play_attack()


func _face(point: Vector3):
	var flat = Vector3(point.x, global_position.y, point.z)
	if flat.distance_to(global_position) > 0.05:
		global_transform = global_transform.looking_at(flat, Vector3.UP)


func _apply_speed():
	if _movement != null and _base_speed > 0.0:
		_movement.speed = _base_speed * speed_mult * (1.0 + speed_bonus)


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
	var match_node = get_tree().get_first_node_in_group("lotr_match") if is_inside_tree() else null
	if match_node != null and not puppet:
		match_node.fx("collapse" if unit_kind == "building" else "death", global_position, global_position)
	_leave_remains()
	super()


func _leave_remains():
	"""Fallen units collapse and sink away; destroyed buildings leave rubble for a while."""
	var match_node = get_tree().get_first_node_in_group("lotr_match") if is_inside_tree() else null
	if match_node == null:
		return
	var model = find_child("Model")
	if model != null and model.has_meta("anim"):
		var t = model.global_transform
		model.get_parent().remove_child(model)
		match_node.add_child(model)
		model.global_transform = t
		var anim = model.get_meta("anim")
		anim.play(["Death_A", "Death_B"][randi() % 2], 0.1)
		var tween = model.create_tween()
		tween.tween_interval(4.0)
		tween.tween_property(model, "position:y", model.position.y - 1.2, 2.5)
		tween.tween_callback(model.queue_free)
	elif unit_kind == "building":
		var rubble = Art.prop("building_destroyed", get("stats_size").call() * 2.0 if has_method("stats_size") else 3.0)
		match_node.add_child(rubble)
		rubble.global_position = global_position
		var tween = rubble.create_tween()
		tween.tween_interval(20.0)
		tween.tween_property(rubble, "position:y", rubble.position.y - 2.0, 4.0)
		tween.tween_callback(rubble.queue_free)


# --- puppets (clients) ------------------------------------------------------------------------
func _make_puppet():
	set_physics_process(false)
	if _movement != null:
		_movement.avoidance_enabled = false
		_movement.process_mode = Node.PROCESS_MODE_DISABLED
