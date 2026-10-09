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
var base_stats = {}  # factory data (hp, damage, interval, range, speed, armor...) used to seed Stats
var stats = null  # Stats: every number that can change in a fight; read stats.armour, stats.move_speed...
var status = null  # Status: can_move / can_attack / can_cast / stunned ... (only buffs write it)
var bm = null  # BuffManager: bm.add(StunBuff.new(1.0), source), bm.cleanse(Buff.ROOT) ...
var spawn_params = {}  # everything the factory needs to rebuild this unit on a client
var net_id = 0
var puppet = false
var squad = null
var auto_acquire = true
var aggro_range = 0.0  # 0 means use sight range
var ranged = false
# --- legacy shims: read-only mirrors of Stats / Status for older code and the HUD -----------------------
# (written by _sync_from_stats; change a stat through a Buff or the Stats layers, not these)
var armor = 0.0  # damage reduction fraction 0..0.9 (stats.armour is the real number, in points)
var damage_mult = 1.0  # buff multiplier on attack_damage
var attack_speed_mult = 1.0  # buff multiplier on attack speed
var attack_speed_bonus = 0.0  # percent layers (items, haste) on attack speed
var speed_bonus = 0.0  # percent layers on move speed
var speed_mult = 1.0  # final move speed / (base * (1 + speed_bonus))
var rooted_until = 0.0
var stunned_until = 0.0
var _base_armor = 0.0  # armour fraction before buffs
var buffs:  # old {stat, mult, until} list, built from the BuffManager (HUD compatibility)
	get:
		return _legacy_buffs()
var credit = {}  # hero instance id -> [hero, time]: who damaged / CC'd this unit (assist window)
var support = {}  # hero instance id -> [hero, time]: allied heroes who healed / shielded this unit
var last_credit = {}  # set when this unit is killed: {killer, assists}
var _death_ctx = null
var _stats_timer = 0.0
var _stats_dirty = false
var _rebuilding = false
var _synced = {}  # last stat-derived values written into the legacy fields (delta sync)
var last_attacker = null
var anim_driver = null
var last_attack_at = -10.0  # game time of the latest swing (replicated so puppets animate too)
var last_hit_target = null  # who that swing was aimed at (target priority reads it)

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


func _init():
	stats = Stats.new()
	status = Status.new()
	bm = BuffManager.new(self)
	_stats_timer = randf() * GameData.STATS_TICK  # staggered so 200 units don't rebuild together


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
	if _forced():
		return
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
	if target == null or not is_instance_valid(target) or _forced():
		return
	var resume = attack_move_target if keep_attack_move else null
	order = Order.ATTACK
	order_target = target
	attack_move_target = resume
	_repath_timer = 0.0


func force_attack(target):
	"""A taunt: attack `target` no matter what the player ordered."""
	order = Order.ATTACK
	order_target = target
	attack_move_target = null


func _forced() -> bool:
	"""Feared, charmed or taunted units ignore orders (the buff steers them)."""
	return status.feared or status.charmed or status.taunted


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
	bm.process(delta)
	_stats_timer -= delta
	if _stats_timer <= 0.0:
		_stats_timer += GameData.STATS_TICK
		if _stats_dirty or not bm.is_empty() or unit_kind == "hero":
			rebuild_stats()
	_land_pending_hit()
	_brain(delta)


# --- buffs, status and stats (see source/lotr/combat/) ------------------------------------------------------
func apply_buff(stat: String, mult: float, duration: float, source = null):
	"""Old-style timed multiplier, now a real Buff. stat: damage | attack_speed | speed (multipliers)
	or armor (a fraction added, e.g. 0.3). The strongest buff and the strongest debuff of a stat
	apply; a speed < 1 is a slow (one per source, floor 30% of base speed)."""
	var buff = null
	match stat:
		"damage":
			buff = StatModBuff.new("mod_damage_up" if mult >= 1.0 else "mod_damage_down", duration).best_mult("attack_damage", mult)
		"attack_speed":
			buff = StatModBuff.new("mod_attack_speed_up" if mult >= 1.0 else "mod_attack_speed_down", duration).best_mult("attack_speed", mult)
		"speed":
			if mult >= 1.0:
				buff = HasteBuff.new(mult - 1.0, duration)
			else:
				buff = SlowBuff.new(1.0 - mult, duration)
		"armor":
			buff = StatModBuff.new("armor_up", duration).best_flat("armour", Stats.points_from_fraction(mult))
	if buff != null:
		bm.add(buff, source)


func stun(duration: float, source = null):
	bm.add(StunBuff.new(duration), source)


func is_stunned() -> bool:
	if puppet:
		return GameData.now() < stunned_until
	return status.stunned or status.airborne


func is_rooted() -> bool:
	if puppet:
		return GameData.now() < rooted_until or is_stunned()
	return status.rooted or is_stunned()


func mark_stats_dirty():
	_stats_dirty = true


func rebuild_stats(first = false):
	"""Rebuild the temp stat layer from items, research, level, buffs and auras, then write the
	result into the legacy fields. Runs every 0.25 s (staggered), and at once when a buff comes or goes."""
	if _rebuilding:
		return
	_rebuilding = true
	stats.level = _stat_level()
	stats.begin()
	_contribute_stats(stats)
	stats.mark_gear()
	bm.apply_stats(stats)
	stats.finish()
	_rebuilding = false
	_stats_dirty = false
	_sync_from_stats(first)


func _stat_level() -> int:
	return 1


func _contribute_stats(_s):
	"""Subclasses add their own temp-layer sources here (a hero's items, research...)."""
	pass


func _status_changed():
	var now = GameData.now()
	stunned_until = now + bm.longest_remaining(Buff.STUN | Buff.KNOCKUP) if (status.stunned or status.airborne) else 0.0
	rooted_until = now + bm.longest_remaining(Buff.ROOT) if status.rooted else 0.0
	if (status.stunned or status.airborne or status.rooted) and _movement != null and not puppet:
		_movement.stop()
	if not status.can_attack:
		_pending_hit = null


func _sync_from_stats(first = false):
	"""Push Stats into the fields older code reads. Values are applied as deltas so a direct write
	(a test setting hp_max) survives until the stat itself changes."""
	var s = stats
	var new_hp_max = int(s.max_hp)
	if first or not _synced.has("hp"):
		hp_max = new_hp_max
		hp = hp_max
	elif new_hp_max != _synced.hp:
		var diff = new_hp_max - _synced.hp
		hp_max += diff
		if diff > 0:
			hp = hp + diff
		if hp > hp_max:
			hp = hp_max
	_synced.hp = new_hp_max
	if attack_damage != null:
		var m = s.mult_part[Stats.S.ATTACK_DAMAGE]
		var pre = s.attack_damage / m
		if first or not _synced.has("ad"):
			attack_damage = pre
		else:
			attack_damage += pre - _synced.ad
		_synced.ad = pre
		damage_mult = m
		var r = s.attack_range
		if first or not _synced.has("range"):
			attack_range = r
		else:
			attack_range += r - _synced.range
		_synced.range = r
	attack_speed_mult = s.mult_part[Stats.S.ATTACK_SPEED]
	attack_speed_bonus = s.pct_part[Stats.S.ATTACK_SPEED]
	speed_bonus = s.pct_part[Stats.S.MOVE_SPEED]
	var nominal = maxf(0.01, s.base_move_speed * (1.0 + speed_bonus))
	speed_mult = s.move_speed / nominal if s.base_move_speed > 0.0 else 1.0
	armor = s.armour_fraction()
	_base_armor = Stats.fraction_from_points(s.armour_before_buffs)
	_apply_speed()
	_sync_extra(first)


func _sync_extra(_first):
	pass


func _legacy_buffs() -> Array:
	var out = []
	var now = GameData.now()
	for b in bm.active:
		if not b.active or b.remaining == INF:
			continue
		var until = now + b.remaining
		if b is HasteBuff:
			out.append({"stat": "speed", "mult": 1.0 + b.value, "until": until})
		elif b is SlowBuff:
			out.append({"stat": "speed", "mult": 1.0 - b.value, "until": until})
		elif b is StatModBuff:
			for m in b.mods:
				var name = Stats.NAMES[m[0]]
				if m[1] == "best_mult" and name in ["attack_damage", "attack_speed", "move_speed"]:
					out.append({"stat": {"attack_damage": "damage", "attack_speed": "attack_speed", "move_speed": "speed"}[name], "mult": m[2], "until": until})
				elif m[1] == "best_flat" and name == "armour":
					out.append({"stat": "armor", "mult": Stats.fraction_from_points(m[2]), "until": until})
	return out


func buff_list() -> Array:
	"""For the HUD: [{key, icon, title, tooltip, stacks, remaining, duration, negative}] (one per
	buff key, host and clients alike), plus recall for heroes is shown by the HUD itself."""
	return bm.list()


func _brain(delta):
	if status.stunned or status.airborne:
		if _movement != null:
			_movement.stop()
		return
	if status.feared or status.charmed:
		return  # the buff steers them
	if status.rooted and _movement != null:
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
	if _movement == null:
		reach = attack_range + 1.0  # towers only consider what they can actually hit
	var enemy = Combat.pick_target(self, global_position, reach)
	# stick with the current victim unless something more urgent (someone hitting our hero)
	# turns up: LoL towers and minions don't flicker between targets
	var current = last_hit_target
	if current != null and is_instance_valid(current) and current.is_alive() and enemy != current:
		var in_reach = global_position_yless.distance_to(current.global_position_yless) <= reach + _target_radius(current)
		if in_reach and (enemy == null or Combat.target_tier(self, enemy) > 1):
			enemy = current
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
	if now < _next_hit_at or not status.can_attack:
		return
	var distance = global_position_yless.distance_to(target.global_position_yless)
	if distance > attack_range + _target_radius(target) + 0.2:
		return
	_next_hit_at = now + 1.0 / maxf(0.05, stats.attack_speed)
	last_hit_target = target
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
	if not status.can_attack:
		_pending_hit = null
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
	if _movement != null and _base_speed > 0.0 and not puppet:
		_movement.speed = stats.move_speed if stats.move_speed > 0.0 else _base_speed * speed_mult * (1.0 + speed_bonus)


# --- stats ------------------------------------------------------------------------------------
func _setup_default_properties_from_constants():
	hp_max = int(base_stats.get("hp", 100))
	hp = hp_max
	if base_stats.has("damage"):
		attack_damage = base_stats.damage
		attack_interval = base_stats.get("interval", 1.0)
		attack_range = base_stats.get("range", 1.5)
		attack_domains = [Constants.Match.Navigation.Domain.TERRAIN]
	sight_range = base_stats.get("sight", 8.0)
	ranged = base_stats.get("ranged", false)
	_seed_stats()
	rebuild_stats(true)


func _seed_stats():
	"""Permanent layer of Stats from the factory data. Subclasses (Hero) override for level growth."""
	var d = base_stats
	stats.set_base("max_hp", float(d.get("hp", 100)))
	if d.has("damage"):
		stats.set_base("attack_damage", float(d.damage))
		stats.set_base("attack_speed", 1.0 / maxf(0.05, float(d.get("interval", 1.0))))
		stats.set_base("attack_range", float(d.get("range", 1.5)))
	stats.set_base("move_speed", float(d.get("speed", 0.0)) if unit_kind != "building" else 0.0)
	stats.set_base("armour", Stats.points_from_fraction(d.get("armor", 0.0)))
	stats.set_base("magic_resist", float(d.get("magic_resist", 0.0)))
	stats.set_base("hp_regen", float(d.get("hp_regen", 0.0)))


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


func _on_death_common():
	"""on_death hooks, then every buff goes (the unit is done or, for heroes, respawns clean)."""
	if not puppet:
		if not bm.is_empty():
			bm.fire_death(_death_ctx)
			bm.clear_all(true)
	_death_ctx = null


func _handle_unit_death():
	_on_death_common()
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
