extends Node
## A group of soldiers of one type that fights as a unit. New squadrons march their lane.
## The owner can order them from anywhere: Follow (stay with the hero and attack what the hero
## attacks), Attack, Move/Defend, Hold, Return home (to heal) or back to a Lane.
## Runs on the host only; clients get a summary for the HUD.

enum State { IDLE, MARCH, ATTACK, DEFEND, HOLD, RETURN, FOLLOW }

const STATE_NAMES = {
	State.IDLE: "Idle", State.MARCH: "Marching", State.ATTACK: "Attacking",
	State.DEFEND: "Defending", State.HOLD: "Holding", State.RETURN: "Returning home",
	State.FOLLOW: "Following you",
}
const FOLLOW_DISTANCE = 3.5  # how far behind the hero the formation keeps
const FOLLOW_ASSIST_RANGE = 9.0  # enemies this close to the hero get attacked
const TICK = 0.4
const WAYPOINT_REACHED = 5.0
const HOME_REACHED = 7.0
const REGEN_PER_TICK = 0.04  # fraction of max HP healed per tick while home
const LAG_MAX = 4.0  # the banner waits while the soldiers trail this far behind their slots
const LEAD = 3.0  # soldiers aim this far ahead of their slot while marching (smooth walking)
const REORDER = 1.4  # a soldier is re-ordered when its slot target moved this far

var squad_id = 0
var player = null
var unit_class = "infantry"
var display_name = ""
var members = []
var state = State.IDLE
var lane_points = []
var waypoint = 0
var target_unit = null
var defend_point = Vector3.ZERO
var home_point = Vector3.ZERO

var formation = "line"
var stance = "aggressive"
var xp = 0
var rank = 1
var max_size = 0  # full strength (reinforcements refill up to this)
var banner_unit = null
var anchor = Vector3.ZERO  # where the banner stands: the formation slots hang off it
var facing = Vector3(0, 0, -1)
var guard_point = Vector3.ZERO  # Defensive stance: the spot this horde holds
var reinforceable = false  # only hordes trained at a building can be topped up
var auto_reinforce = true  # refill by itself when idle in the city (toggle)
var reinforce_now = false  # one-off request from the Reinforce button
var _reinforce_left = 0.0
var reinforce_spent = 0  # Supplies spent on replacements so far
var _anchored = false
var _engaged = false

var _tick_left = 0.0
var _last_dest = null


func _ready():
	add_to_group("squadrons")


func setup(a_player, a_class, units: Array, home: Vector3):
	player = a_player
	unit_class = a_class
	members = units
	home_point = home
	max_size = members.size()
	for m in members:
		_adopt(m)
	if not members.is_empty():
		display_name = members[0].display_name
	guard_point = center()
	anchor = guard_point


func faction() -> String:
	return player.faction if player != null else ""


func first_member():
	for m in members:
		if is_instance_valid(m):
			return m
	return null


func _adopt(m):
	m.squad = self
	m.aggro_range = Formations.aggro_for(m)
	m.trample_mode = _trample_for(m)
	m.mark_stats_dirty()


func _trample_for(m) -> String:
	if Formations.def(formation).get("trample", false):
		return "charge"
	return "crush" if m.base_stats.get("crusher", false) else ""


func alive_members():
	members = members.filter(func(m): return is_instance_valid(m) and m.is_alive())
	return members


func center() -> Vector3:
	var alive = alive_members()
	if alive.is_empty():
		return home_point
	var sum = Vector3.ZERO
	for m in alive:
		sum += m.global_position
	return sum / alive.size()


func hp_fraction() -> float:
	var hp = 0
	var hp_max = 0
	for m in alive_members():
		hp += m.hp
		hp_max += m.hp_max
	return 0.0 if hp_max == 0 else float(hp) / hp_max


func hp_sum() -> int:
	var hp = 0
	for m in alive_members():
		hp += m.hp
	return hp


func hp_max_sum() -> int:
	var hp = 0
	for m in alive_members():
		hp += m.hp_max
	return hp


func state_name():
	return STATE_NAMES[state]


# --- formation, stance, rank ---------------------------------------------------------------------------
func set_formation(key: String) -> String:
	"""'' on success, else the reason it was refused."""
	var why = Formations.refusal(self, key)
	if why != "":
		return why
	if key == formation:
		return ""
	formation = key
	_refresh_members()
	_last_dest = null
	return ""


func set_stance(key: String) -> String:
	if not GameData.STANCES.has(key):
		return "Unknown stance"
	stance = key
	guard_point = center()
	_refresh_members()
	return ""


func _refresh_members():
	for m in alive_members():
		m.aggro_range = Formations.aggro_for(m)
		m.trample_mode = _trample_for(m)
		m.mark_stats_dirty()


func add_xp(amount: int):
	xp += amount
	var r = Formations.rank_for_xp(xp)
	if r == rank:
		return
	rank = r
	_refresh_members()
	var match_node = get_tree().get_first_node_in_group("lotr_match") if is_inside_tree() else null
	if match_node != null and player != null and match_node.has_method("toast_player"):
		match_node.toast_player(player.slot_index, "%s reached rank %d" % [display_name, rank])


func xp_next() -> int:
	return GameData.RANK_XP[rank] if rank < GameData.RANK_XP.size() else xp


func _ensure_banner(alive):
	var want = rank >= 2
	if not want:
		if banner_unit != null:
			for m in alive:
				m.set_banner(false)
			banner_unit = null
		return
	if banner_unit == null or not is_instance_valid(banner_unit) or not banner_unit.is_alive() or not banner_unit in alive:
		var idx = Formations.banner_slot(Formations.def(formation).layout, alive.size())
		banner_unit = alive[mini(idx, alive.size() - 1)]
		for m in alive:
			m.set_banner(m == banner_unit)


# --- reinforcements -----------------------------------------------------------------------------------------
func in_city(c: Vector3) -> bool:
	if player == null:
		return false
	for tc in player.town_centers():
		if tc.global_position.distance_to(c) <= GameData.CITY_RADIUS:
			return true
	return false


func soldier_cost() -> Dictionary:
	var st = GameData.troop_stats(player.faction, unit_class, player.upgrades)
	var out = {}
	for r in st.cost:
		out[r] = int(ceil(st.cost[r] * GameData.REINFORCE_COST_FACTOR / maxf(1.0, st.squad_size)))
	return out


func missing() -> int:
	return maxi(0, max_size - alive_members().size())


func _reinforce_tick(alive, c):
	if not reinforceable or alive.size() >= max_size or alive.is_empty():
		reinforce_now = false
		return
	var calm = state in [State.IDLE, State.HOLD, State.DEFEND, State.RETURN] and not _engaged
	if not (reinforce_now or (auto_reinforce and calm)) or not in_city(c):
		return
	_reinforce_left -= TICK
	if _reinforce_left > 0.0:
		return
	var cost = soldier_cost()
	if not player.has_resources(cost):
		return
	var match_node = get_tree().get_first_node_in_group("lotr_match")
	if match_node == null:
		return
	player.subtract_resources(cost)
	reinforce_spent += GameData.price(cost)
	var params = alive[0].spawn_params.duplicate(true)
	params["upgrades"] = player.upgrades.duplicate()
	var side = Vector3(-facing.z, 0, facing.x)
	var spot = c - facing * 1.5 + side * randf_range(-1.5, 1.5)
	var unit = match_node.spawn_unit(params, spot, player)
	members.append(unit)
	_adopt(unit)
	unit.set_banner(false)
	_reinforce_left = GameData.REINFORCE_INTERVAL
	if alive.size() + 1 >= max_size:
		reinforce_now = false


# --- orders -----------------------------------------------------------------------------------
func march(points: Array):
	lane_points = points
	waypoint = 0
	state = State.MARCH if not points.is_empty() else State.IDLE
	_last_dest = null


func order_attack(target):
	target_unit = target
	state = State.ATTACK
	_last_dest = null


func order_defend(point: Vector3):
	defend_point = point
	guard_point = point
	state = State.DEFEND
	_last_dest = null


func order_hold():
	state = State.HOLD
	for m in alive_members():
		m.order_hold()


func order_follow():
	state = State.FOLLOW
	target_unit = null
	_last_dest = null


func order_lane(points: Array):
	"""Back to a lane, joining it at the nearest waypoint instead of walking home first."""
	var c = center()
	var best = 0
	for i in range(points.size()):
		if points[i].distance_to(c) < points[best].distance_to(c):
			best = i
	march(points)
	waypoint = best


func order_return():
	state = State.RETURN
	_last_dest = null
	for m in alive_members():
		m.order_stop()


# --- loop -------------------------------------------------------------------------------------
func _physics_process(delta):
	if not multiplayer.is_server() and Network.is_online():
		return
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = TICK
	_tick()


func _holding() -> bool:
	"""Hold position: the Hold order, or the Hold Ground stance while standing around."""
	return state == State.HOLD or (stance == "hold" and (state == State.IDLE or state == State.DEFEND))


func _tick():
	var alive = alive_members()
	if alive.is_empty():
		queue_free()
		return
	var c = center()
	if not _anchored:
		_anchored = true
		anchor = c
		guard_point = c
	_ensure_banner(alive)
	_reinforce_tick(alive, c)
	alive = members
	if state == State.RETURN:
		_tick_return(c)
		return
	if state == State.FOLLOW:
		_tick_follow(alive, c)
		return
	if stance == "defensive" and state == State.IDLE:
		state = State.DEFEND  # a Defensive horde guards its spot
		defend_point = guard_point
	var engage_from = c
	if state == State.DEFEND:
		engage_from = defend_point
	var reach = GameData.SQUAD_AGGRO_RANGE
	if stance == "defensive":
		reach = GameData.STANCES.defensive.radius
	if _holding():
		reach = alive[0].attack_range + 1.0
	var enemy = _closest_enemy_near(alive, engage_from, reach)
	if enemy != null and alive[0].get("siege") != true:
		# squads pick by priority too (hero-attackers first), not just the nearest enemy
		var urgent = Combat.pick_target(alive[0], engage_from, reach)
		if urgent != null:
			enemy = urgent
	if state == State.ATTACK and _valid_target():
		enemy = target_unit
	if enemy != null:
		var to_enemy = enemy.global_position - c
		to_enemy.y = 0.0
		if to_enemy.length() > 0.5:
			facing = to_enemy.normalized()
		_engage(alive, enemy)
		return
	if _engaged:
		_engaged = false  # the fight is over: close up around where we stand
		anchor = c
		_last_dest = null
	match state:
		State.MARCH:
			if waypoint < lane_points.size():
				if c.distance_to(lane_points[waypoint]) < WAYPOINT_REACHED:
					waypoint += 1
					_last_dest = null
				if waypoint < lane_points.size():
					_move_formation(alive, lane_points[waypoint], c)
			else:
				state = State.IDLE
				guard_point = c
		State.ATTACK:
			state = State.IDLE  # target gone
			guard_point = c
		State.DEFEND:
			if c.distance_to(defend_point) > 3.0 or anchor.distance_to(defend_point) > 0.6:
				_move_formation(alive, defend_point, c)
			else:
				_regroup(alive)
		State.HOLD:
			pass
		State.IDLE:
			_regroup(alive)


func _tick_follow(alive, c):
	var hero = player.hero if player != null else null
	if hero == null or not is_instance_valid(hero) or not hero.is_alive():
		var engaged = _closest_enemy_near(alive, c, GameData.SQUAD_AGGRO_RANGE)
		if engaged != null:
			_engage(alive, engaged)
		return  # hero is dead: hold here and defend ourselves until they respawn
	# attack what the hero attacks, else anything threatening the hero
	var focus = null
	if hero.order == hero.Order.ATTACK and hero.order_target != null and is_instance_valid(hero.order_target) and hero.order_target.is_alive():
		focus = hero.order_target
	if focus == null:
		focus = Combat.pick_target(alive[0], hero.global_position, FOLLOW_ASSIST_RANGE)
	if focus != null:
		_engage(alive, focus)
		return
	# otherwise trail the hero in formation
	if _engaged:
		_engaged = false
		anchor = c
	var back = -hero.global_transform.basis.z
	back.y = 0.0
	var dest = hero.global_position - (back.normalized() if back.length() > 0.1 else Vector3.FORWARD) * FOLLOW_DISTANCE
	if c.distance_to(dest) > 2.5:
		_move_formation(alive, dest, c)
	else:
		_regroup(alive)


func _tick_return(c):
	if c.distance_to(home_point) > HOME_REACHED:
		_move_formation(alive_members(), home_point, c)
		return
	var all_full = true
	for m in alive_members():
		if m.hp < m.hp_max:
			m.hp = min(m.hp_max, m.hp + max(1, int(m.hp_max * REGEN_PER_TICK)))
			all_full = false
	if all_full:
		state = State.IDLE


func _valid_target():
	return target_unit != null and is_instance_valid(target_unit) and target_unit.is_alive()


func _closest_enemy_near(alive, from, reach):
	# siege squadrons (rams, trebuchets, Grond, sappers) go for buildings when any are close
	var siege = alive[0].get("siege") == true
	if siege:
		reach = max(reach, alive[0].attack_range + 2.0)
	var best = null
	var best_d = reach
	var best_building = null
	var best_building_d = reach + 4.0
	for other in SpatialGrid.near(get_tree(), from, max(reach, best_building_d) + 1.0):
		if not is_instance_valid(other) or not other.is_alive() or not Teams.is_enemy(player, other.player):
			continue
		if Combat.is_wild(other) and other.get("order_target") == null:
			continue  # leave the camps alone unless a creature is fighting someone
		var d = Vector2(other.global_position.x - from.x, other.global_position.z - from.z).length()
		if siege and other.unit_kind == "building" and d <= best_building_d:
			best_building_d = d
			best_building = other
		if d <= best_d:
			best_d = d
			best = other
	return best_building if best_building != null else best


func _engage(alive, focus):
	_engaged = true
	_last_dest = null
	var forced = state == State.ATTACK or state == State.FOLLOW  # the player/hero chose the target
	for m in alive:
		if _holding():
			continue  # holding units only shoot what's in range (handled by the unit itself)
		var busy = m.order == m.Order.ATTACK and m.order_target != null and is_instance_valid(m.order_target) and m.order_target.is_alive()
		var own = null
		if forced:
			own = focus
		elif not (m.get("siege") == true and focus.unit_kind == "building"):
			own = Combat.pick_target(m, m.global_position, m.attack_range + 3.0)
		if own == null:
			own = focus
		# keep fighting the current target unless the new one is more urgent (hits our hero)
		if busy and m.order_target != own and not forced and Combat.target_tier(m, own) > 1:
			continue
		if busy and m.order_target == own:
			continue
		m.order_attack(own)


func _move_formation(alive, dest: Vector3, c: Vector3):
	"""March the banner toward dest and send every soldier to its slot around it. Runs at 2.5 Hz."""
	if anchor.distance_to(c) > 7.0:
		anchor = c  # the banner got left behind (a long chase): close up where we are
	var d = dest - anchor
	d.y = 0.0
	var dist = d.length()
	if dist > 0.4:
		facing = d / dist
	var lag = _mean_lag(alive)
	if dist > 0.05 and lag < LAG_MAX:
		anchor += facing * minf(dist, _squad_speed(alive) * TICK * 1.05)
		dist = maxf(0.0, dist - _squad_speed(alive) * TICK * 1.05)
	_assign_slots(alive, minf(LEAD, dist), false)


func _regroup(alive):
	"""Idle: soldiers that are out of place walk back to their slot (after a fight, after spawning)."""
	var c = center()
	if anchor.distance_to(c) > 7.0:
		anchor = c  # moved some other way (recall, teleport): the banner follows, soldiers do not trek back
	_assign_slots(alive, 0.0, true)


func _squad_speed(alive) -> float:
	var v = 99.0
	for m in alive:
		if m.stats.move_speed > 0.1:
			v = minf(v, m.stats.move_speed)
	return 2.5 if v > 90.0 else v


func _mean_lag(alive) -> float:
	var sum = 0.0
	var n = 0
	for m in alive:
		if m.slot_pos != Vector3.ZERO:  # not assigned yet
			sum += m.global_position.distance_to(m.slot_pos)
			n += 1
	return sum / maxf(1.0, n)


func _assign_slots(alive, lead: float, only_idle: bool):
	var f = Formations.def(formation)
	var layout = f.layout
	var spacing = f.spacing
	var side = Vector3(-facing.z, 0, facing.x)
	var n = alive.size()
	for i in range(n):
		var m = alive[i]
		var o = Formations.slot_offset(layout, i, n, spacing)
		var slot = anchor + side * o.x - facing * o.y
		m.slot_pos = slot
		if only_idle:
			if m.order != m.Order.IDLE or m.global_position.distance_to(slot) < 1.2:
				continue
		else:
			slot += facing * lead
			if m.order == m.Order.MOVE and m.order_position != null and m.order_position.distance_to(slot) < REORDER:
				continue
			if m.order != m.Order.MOVE and lead <= 0.0 and m.global_position.distance_to(slot) < 0.8:
				continue
		m.order_move(slot)


# --- HUD summary ------------------------------------------------------------------------------
func summary() -> Dictionary:
	var c = center()
	var alive = alive_members()
	return {
		"id": squad_id, "player": player.slot_index, "class": unit_class,
		"name": display_name, "count": alive.size(), "state": state,
		"hp": hp_fraction(), "x": c.x, "z": c.z,
		"members": alive.map(func(m): return m.net_id),
		"max": max_size, "hp_sum": hp_sum(), "hp_max": hp_max_sum(), "rank": rank, "xp": xp, "xp_next": xp_next(),
		"formation": formation, "stance": stance,
		"banner": banner_unit.net_id if banner_unit != null and is_instance_valid(banner_unit) else 0,
		"auto": auto_reinforce, "can_reinforce": reinforceable, "in_city": in_city(c),
		"faction": faction(), "cclass": Formations.counter_class(self), "spear": Formations.is_spear(self),
	}
