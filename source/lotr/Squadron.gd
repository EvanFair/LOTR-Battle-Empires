extends Node
## A group of soldiers of one type that fights as a unit. New squadrons march their lane;
## a Hero standing nearby can order them: Attack, Defend, Hold, or Return home (to heal).
## Runs on the host only; clients get a summary for the HUD.

enum State { IDLE, MARCH, ATTACK, DEFEND, HOLD, RETURN }

const STATE_NAMES = {
	State.IDLE: "Idle", State.MARCH: "Marching", State.ATTACK: "Attacking",
	State.DEFEND: "Defending", State.HOLD: "Holding", State.RETURN: "Returning home",
}
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
	var engage_from = c
	if state == State.DEFEND:
		engage_from = defend_point
	var reach = GameData.SQUAD_AGGRO_RANGE
	if state == State.HOLD:
		reach = alive[0].attack_range + 1.0
	var enemy = _closest_enemy_near(alive, engage_from, reach)
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
	var best = null
	var best_d = reach
	for other in get_tree().get_nodes_in_group("units"):
		if not other.is_alive() or not Teams.is_enemy(player, other.player):
			continue
		var d = Vector2(other.global_position.x - from.x, other.global_position.z - from.z).length()
		if d <= best_d:
			best_d = d
			best = other
	return best


func _engage(alive, focus):
	_last_dest = null
	for m in alive:
		if m.order == m.Order.ATTACK and m.order_target != null and is_instance_valid(m.order_target) and m.order_target.is_alive():
			continue
		if state == State.HOLD:
			continue  # holding units only shoot what's in range (handled by the unit itself)
		var own = Combat.closest_enemy(m, m.global_position, m.attack_range + 3.0)
		m.order_attack(own if own != null else focus)


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
	}
