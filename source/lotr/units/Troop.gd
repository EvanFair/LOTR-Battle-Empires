extends "res://source/lotr/units/LotrUnit.gd"
## A soldier in a squadron. The Squadron decides what it does; it fights on its own when idle.
## Horde extras (plan C1-C4): formation slot, banner, wedge first blow, trample, stance leash.

const EXPLODE_RADIUS = 3.5

var summon_expires_at = 0.0  # summoned units (Army of the Dead, Wargs) vanish after this time
var siege = false  # prefers buildings (squadron targeting)
var explode = false  # Isengard sappers: blow up on the first hit, damaging everything nearby
var slot_pos = Vector3.ZERO  # where the squad wants this soldier (formation slot, no look-ahead)
var trample_mode = ""  # "" | "charge" (cavalry in Charge formation) | "crush" (trolls)
var trampled_until = 0.0  # just got run over: immune to another trample until then
var _banner = null
var _first_target = null  # Wedge: the target of the last "first blow"
var _first_time = -100.0
var _trample_left = 0.0
var _trample_from = Vector3.ZERO
var _leash_left = 0.0


func _ready():
	await super()
	aggro_range = Formations.aggro_for(self)
	if base_stats.get("crusher", false) and trample_mode == "":
		trample_mode = "crush"


func _contribute_stats(s):
	Formations.contribute(self, s)


func _physics_process(delta):
	super(delta)
	if puppet or not is_alive():
		return
	if summon_expires_at > 0.0 and GameData.now() > summon_expires_at:
		hp = 0
		return
	if trample_mode != "":
		_trample_left -= delta
		if _trample_left <= 0.0:
			_trample_left = 0.2
			_trample()
	if squad != null and order == Order.ATTACK:
		_leash_left -= delta
		if _leash_left <= 0.0:
			_leash_left = 0.5
			_check_leash()


# --- banner ------------------------------------------------------------------------------------------
func set_banner(on: bool):
	if on == (_banner != null):
		return
	if not on:
		_banner.queue_free()
		_banner = null
		return
	var mat = player.get_color_material() if player != null else null
	_banner = Formations.make_banner(player.faction if player != null else "gondor", mat)
	_banner.position = Vector3(-0.38, 0, 0.1)
	var geo = find_child("Geometry")
	(geo if geo != null else self).add_child(_banner)


func has_banner() -> bool:
	return _banner != null


# --- wedge: the first blow on a fresh target hits harder ---------------------------------------------------
func _land_pending_hit():
	if _pending_hit == null or GameData.now() < _pending_hit.at:
		return
	var bonus = 1.0
	if squad != null and is_instance_valid(squad):
		var f = GameData.FORMATIONS.get(squad.formation, {})
		if f.has("first_hit"):
			var t = _pending_hit.target
			var now = GameData.now()
			if t != _first_target or now - _first_time > 5.0:
				bonus = f.first_hit
				_first_target = t
				_first_time = now
	if bonus > 1.0:
		var saved = attack_damage
		attack_damage = saved * bonus
		super()
		attack_damage = saved
	else:
		super()


# --- stance leash: Defensive / Hold Ground soldiers do not chase far ----------------------------------------
func _check_leash():
	if squad.state == squad.State.ATTACK or squad.state == squad.State.FOLLOW or squad.stance == "aggressive":
		return
	var t = order_target
	if t == null or not is_instance_valid(t):
		return
	if squad.stance == "hold":
		if global_position_yless.distance_to(t.global_position_yless) > attack_range + _target_radius(t) + 1.0:
			order_stop()
	elif squad.guard_point.distance_to(t.global_position) > GameData.STANCES.defensive.radius + 3.0:
		order_stop()


# --- trample (cavalry charge, trolls) -----------------------------------------------------------------------
func _trample():
	var here = global_position
	var moved = here.distance_to(_trample_from) / 0.2
	_trample_from = here
	var m = stats.move_speed
	if m <= 0.1 or moved < m * 0.5:
		return  # only while actually running into things
	var now = GameData.now()
	for other in SpatialGrid.near(get_tree(), here, 1.8):
		if other == self or not is_instance_valid(other) or other.get("unit_kind") != "troop":
			continue
		if not other.is_alive() or not Teams.is_enemy(player, other.player):
			continue
		if not other.target_kind in ["infantry", "archer"] or other.trampled_until > now:
			continue
		if global_position_yless.distance_to(other.global_position_yless) > 0.8 + _target_radius(other):
			continue
		other.trampled_until = now + 2.5
		if trample_mode == "charge" and Formations.is_pike(other.squad):
			bm.add(StunBuff.new(GameData.PIKE_STUN), other)  # the charge breaks on the pikes
			if _movement != null:
				_movement.stop()
			continue
		var away = other.global_position - here
		away.y = 0.0
		away = away.normalized() if away.length() > 0.05 else -global_transform.basis.z
		other.global_position += away * GameData.KNOCKBACK
		other.bm.add(StunBuff.new(GameData.CHARGE_STUN), self)


func _try_hit(target):
	if not explode:
		super(target)
		return
	var distance = global_position_yless.distance_to(target.global_position_yless)
	if distance > attack_range + _target_radius(target) + 0.2:
		return
	var match_node = get_tree().get_first_node_in_group("lotr_match")
	if match_node != null:
		match_node.fx("blast", global_position, global_position)
	for other in Combat.enemies_in_radius(self, global_position, EXPLODE_RADIUS + _target_radius(target), get_tree()):
		var falloff = 1.0 if other == target or other.unit_kind == "building" else 0.5
		Combat.deal_damage(self, other, attack_damage * damage_mult * falloff, Combat.PHYSICAL, Combat.BASIC, ["aoe", "siege"])
	hp = 0
