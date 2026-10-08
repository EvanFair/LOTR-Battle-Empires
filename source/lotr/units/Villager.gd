extends "res://source/lotr/units/LotrUnit.gd"
## A local who gathers whatever their house is assigned to, carries it to the nearest access
## point (Town Center or Storehouse), and on the way back hauls supplies to military buildings
## that need them. "Home" sends them inside their house, safe but idle.

enum State { IDLE, TO_NODE, GATHER, TO_DROP, TO_HAUL, TO_HOME, HOME }

const ARRIVE_SLACK = 1.4
const REPATH = 1.0

var house = null
var state = State.IDLE
var carrying_type = ""
var carrying_amount = 0
var haul = {}  # {building, resource, amount}

var _target = null
var _gather_left = 0.0
var _repath_left = 0.0


func _ready():
	await super()
	auto_acquire = false


func is_alive():
	# sheltered villagers leave the "units" group (so nothing can target them) but are still alive
	return is_inside_tree() and hp != null and hp > 0


func assignment():
	return house.assignment if house != null and is_instance_valid(house) else "home"


func _brain(delta):
	var wanted = assignment()
	if wanted == "home" and state not in [State.TO_HOME, State.HOME, State.TO_HAUL]:
		_go_home()
	elif wanted != "home" and state in [State.TO_HOME, State.HOME]:
		_leave_home()
	match state:
		State.IDLE:
			_pick_node()
		State.TO_NODE:
			if not _valid(_target):
				_pick_node()
			elif _arrived(_target):
				_order_halt()
				state = State.GATHER
				_gather_left = GameData.GATHER_TIME.get(wanted, 4.0)
			else:
				_keep_moving(delta)
		State.GATHER:
			if not _valid(_target):
				_pick_node()
				return
			_gather_left -= delta
			if _gather_left <= 0.0:
				carrying_type = _target.resource_type
				carrying_amount = _target.take(GameData.VILLAGER_CARRY)
				_head_to_drop()
		State.TO_DROP:
			if not _valid(_target):
				_head_to_drop()
			elif _arrived(_target):
				_order_halt()
				_deposit()
			else:
				_keep_moving(delta)
		State.TO_HAUL:
			if not _valid(haul.get("building")) or not haul.building.is_alive():
				_cancel_haul()
			elif _arrived(haul.building):
				_order_halt()
				haul.building.deliver_supply(haul.resource, haul.amount)
				haul = {}
				_pick_node()
			else:
				_keep_moving(delta)
		State.TO_HOME:
			if not _valid(house):
				state = State.IDLE
			elif _arrived(house):
				_order_halt()
				state = State.HOME
				_set_sheltered(true)
			else:
				_keep_moving(delta)


func _pick_node():
	var wanted = assignment()
	if wanted == "home":
		_go_home()
		return
	if carrying_amount > 0 and carrying_type != wanted:
		_head_to_drop()
		return
	_target = _closest_resource(wanted)
	if _target == null:
		state = State.IDLE
		return
	state = State.TO_NODE
	_move_to(_target.global_position)


func _head_to_drop():
	_target = player.closest_access_point(global_position) if player.has_method("closest_access_point") else null
	if _target == null:
		state = State.IDLE
		return
	state = State.TO_DROP
	_move_to(_target.global_position)


func _deposit():
	if carrying_amount > 0:
		player.add_resources({carrying_type: carrying_amount})
		player.note_income(carrying_type, carrying_amount)
	carrying_amount = 0
	carrying_type = ""
	# on the way back out, carry supplies to a military building if one is waiting
	var job = player.request_haul_job(self)
	if not job.is_empty():
		haul = job
		state = State.TO_HAUL
		_move_to(haul.building.global_position)
		return
	_pick_node()


func _cancel_haul():
	if not haul.is_empty():
		if _valid(haul.get("building")):
			haul.building.cancel_incoming(haul.resource, haul.amount)
		# bring the goods back to the stockpile
		carrying_type = haul.resource
		carrying_amount = haul.amount
		haul = {}
	_head_to_drop()


func _go_home():
	if not _valid(house):
		return
	if not haul.is_empty():
		return  # finish the delivery first
	state = State.TO_HOME
	_move_to(house.global_position)


func _leave_home():
	_set_sheltered(false)
	state = State.IDLE


func _set_sheltered(value: bool):
	# inside the house: invisible and untargetable
	find_child("Geometry").visible = not value
	input_ray_pickable = not value
	if value:
		remove_from_group("units")
	elif not is_in_group("units"):
		add_to_group("units")


func is_sheltered():
	return state == State.HOME


func _handle_unit_death():
	if not haul.is_empty() and _valid(haul.get("building")):
		haul.building.cancel_incoming(haul.resource, haul.amount)  # the load is lost
	haul = {}
	super()


# --- movement helpers ---------------------------------------------------------------------------
func _move_to(pos: Vector3):
	_repath_left = REPATH
	if _movement != null:
		_movement.move(pos)


func _keep_moving(delta):
	_repath_left -= delta
	if _repath_left <= 0.0 or (_movement != null and _movement.target_position == Vector3.INF):
		var dest = _target if state != State.TO_HAUL else haul.building
		if state == State.TO_HOME:
			dest = house
		if _valid(dest):
			_move_to(dest.global_position)


func _order_halt():
	if _movement != null:
		_movement.stop()


func _arrived(node) -> bool:
	var reach = ARRIVE_SLACK
	var r = node.get("radius")
	if r != null:
		reach += r
	if "building_key" in node:
		reach = GameData.BUILDINGS[node.building_key].size + ARRIVE_SLACK
	return global_position_yless.distance_to(node.global_position * Vector3(1, 0, 1)) <= reach


func _valid(node) -> bool:
	return node != null and is_instance_valid(node) and node.is_inside_tree()


func _closest_resource(type: String):
	var best = null
	var best_d = INF
	for node in get_tree().get_nodes_in_group("lotr_resources"):
		if node.resource_type != type or node.is_depleted():
			continue
		var d = node.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = node
	return best
