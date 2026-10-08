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
const SPACING = 1.3

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

var _tick_left = 0.0
var _last_dest = null


func _ready():
	add_to_group("squadrons")


func setup(a_player, a_class, units: Array, home: Vector3):
	player = a_player
	unit_class = a_class
	members = units
	home_point = home
	for m in members:
		m.squad = self
	if not members.is_empty():
		display_name = members[0].display_name


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


func state_name():
	return STATE_NAMES[state]


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


func _tick():
	var alive = alive_members()
	if alive.is_empty():
		queue_free()
		return
	var c = center()
	if state == State.RETURN:
		_tick_return(c)
		return
	if state == State.FOLLOW:
		_tick_follow(alive, c)
		return
	var engage_from = c
	if state == State.DEFEND:
		engage_from = defend_point
	var reach = GameData.SQUAD_AGGRO_RANGE
	if state == State.HOLD:
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
		_engage(alive, enemy)
		return
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
		State.ATTACK:
			state = State.IDLE  # target gone
		State.DEFEND:
			if c.distance_to(defend_point) > 3.0:
				_move_formation(alive, defend_point, c)
		State.HOLD, State.IDLE:
			pass


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
	var back = -hero.global_transform.basis.z
	back.y = 0.0
	var dest = hero.global_position - (back.normalized() if back.length() > 0.1 else Vector3.FORWARD) * FOLLOW_DISTANCE
	if c.distance_to(dest) > 2.5:
		_move_formation(alive, dest, c)


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
	_last_dest = null
	var forced = state == State.ATTACK or state == State.FOLLOW  # the player/hero chose the target
	for m in alive:
		if state == State.HOLD:
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
	var dir = (dest - c)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	var side = Vector3(-dir.z, 0, dir.x)
	var cols = maxi(2, int(ceil(sqrt(alive.size()))))
	var changed = _last_dest == null or _last_dest.distance_to(dest) > 0.5
	_last_dest = dest
	for i in range(alive.size()):
		var m = alive[i]
		var row = i / cols
		var col = i % cols
		var slot = dest + side * (col - (cols - 1) / 2.0) * SPACING - dir * row * SPACING
		if not changed and (m.order == m.Order.MOVE or m.global_position.distance_to(slot) < 1.5):
			continue
		m.order_move(slot)


# --- HUD summary ------------------------------------------------------------------------------
func summary() -> Dictionary:
	var c = center()
	return {
		"id": squad_id, "player": player.slot_index, "class": unit_class,
		"name": display_name, "count": alive_members().size(), "state": state,
		"hp": hp_fraction(), "x": c.x, "z": c.z,
		"members": alive_members().map(func(m): return m.net_id),
	}
