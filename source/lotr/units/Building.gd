extends "res://source/lotr/units/LotrUnit.gd"
## Every building. Heroes build them by standing nearby. Depending on its type a building also:
##  - trains squadrons (Barracks / Archery Range / Stables), fed by villagers hauling supply
##  - houses a villager group (Village House)
##  - advances Ages and is an access point (Town Center), or an access point that halves the
##    stockpile when lost (Storehouse)
##  - shoots at enemies (Town Center, Watchtower)

const UNDER_CONSTRUCTION_ALPHA = 0.45

var building_key = "barracks"
var progress = 1.0  # 0..1 construction progress
var build_paused_reason = ""  # "", "no_hero", "enemy_hero"

# production
var trains = ""  # unit class, "" if this building doesn't train
var auto_repeat = false
var lane = -1  # lane index squadrons march down; -1 = gather at the rally point
var cycle_left = GameData.AUTO_REPEAT_INTERVAL
var manual_pending = 0
var manual_left = 0.0
var supply = {}  # resource -> delivered
var incoming = {}  # resource -> on the way

# village house
var assignment = "food"
var villagers = []
var respawn_left = 0.0
var initial_villagers_spawned = false

# town center: age advance in progress
var age_target = 0
var age_progress = 0.0


var _label3d = null


func _ready():
	await super()
	add_to_group("buildings")
	_label3d = Label3D.new()
	_label3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label3d.no_depth_test = true
	_label3d.font_size = 40
	_label3d.outline_size = 10
	_label3d.pixel_size = 0.01
	_label3d.position.y = 3.6 if building_key != "watchtower" else 6.6
	add_child(_label3d)
	trains = GameData.BUILDINGS[building_key].get("trains", "")
	auto_acquire = attack_damage != null
	if progress < 1.0:
		_apply_construction_look(true)
		hp = max(1, int(hp_max * 0.1))


func stats_size():
	return GameData.BUILDINGS[building_key].size


func is_constructed():
	return progress >= 1.0


func is_access_point():
	return is_constructed() and building_key in ["town_center", "storehouse"] and is_alive()


func is_revealing():
	return super() and is_constructed()


# --- construction ------------------------------------------------------------------------------
func mark_under_construction():
	progress = 0.0


func hero_presence() -> Dictionary:
	var friendly = 0
	var enemy = 0
	var reach = GameData.BUILD_RANGE + stats_size()
	for hero in get_tree().get_nodes_in_group("heroes"):
		if not hero.is_alive():
			continue
		if hero.global_position_yless.distance_to(global_position_yless) > reach:
			continue
		if Teams.is_enemy(hero.player, player):
			enemy += 1
		else:
			friendly += 1
	return {"friendly": friendly, "enemy": enemy}


func _construction_tick(delta):
	var presence = hero_presence()
	if presence.enemy > 0:
		build_paused_reason = "enemy_hero"
		return
	if presence.friendly == 0:
		build_paused_reason = "no_hero"
		return
	build_paused_reason = ""
	var speed = GameData.MULTI_HERO_BUILD_SPEED if presence.friendly >= 2 else 1.0
	var build_time = max(1.0, GameData.BUILDINGS[building_key].build_time)
	var step = delta * speed / build_time
	var hp_before = progress * hp_max
	progress = min(1.0, progress + step)
	hp = min(hp_max, hp + max(0, int(progress * hp_max) - int(hp_before)))
	if progress >= 1.0:
		_finish_construction()


func _finish_construction():
	_apply_construction_look(false)
	MatchSignals.unit_construction_finished.emit(self)


func _apply_construction_look(under_construction: bool):
	var geometry = find_child("Geometry")
	if geometry == null:
		return
	for node in geometry.find_children("*", "MeshInstance3D", true, false):
		node.transparency = UNDER_CONSTRUCTION_ALPHA if under_construction else 0.0


func cancel_construction():
	"""Refunds 75% of the cost. Host only."""
	if is_constructed():
		return
	var refund = {}
	var cost = GameData.BUILDINGS[building_key].cost
	for res in cost:
		refund[res] = int(cost[res] * GameData.CONSTRUCTION_REFUND)
	player.add_resources(refund)
	queue_free()


func _process(_delta):
	if _label3d == null:
		return
	var text = ""
	if not is_constructed():
		text = "%d%%" % int(progress * 100)
		if build_paused_reason == "no_hero":
			text += "  needs a hero nearby"
		elif build_paused_reason == "enemy_hero":
			text += "  ENEMY HERO!"
	elif building_key == "village_house" and is_in_group("controlled_units"):
		var alive = alive_villagers().size() if not puppet else get_meta("villagers_alive", 0)
		text = "%s %d/%d" % [assignment.capitalize() if assignment != "home" else "Home", alive, GameData.VILLAGERS_PER_HOUSE]
	elif trains != "" and is_in_group("controlled_units") and (auto_repeat or manual_pending > 0):
		text = "Supply %d%%" % int(supply_fraction() * 100) if not supply_full() else "Next %ds" % ceili(cycle_left)
	elif building_key == "town_center" and age_target > 0:
		text = "Age %d%%" % int(age_progress * 100)
	_label3d.text = text
	_label3d.visible = text != "" and find_child("Geometry").visible


# --- main loop (host) --------------------------------------------------------------------------
func _physics_process(delta):
	if puppet or not is_alive():
		return
	if not is_constructed():
		_construction_tick(delta)
		return
	if attack_damage != null:
		super(delta)
	if trains != "":
		_production_tick(delta)
	if building_key == "village_house":
		_villager_tick(delta)
	if building_key == "town_center" and age_target > 0:
		_age_tick(delta)


# --- production -------------------------------------------------------------------------------
func squad_stats():
	return GameData.troop_stats(player.faction, trains)


func squad_cost() -> Dictionary:
	return squad_stats().cost


func wants_supply():
	return trains != "" and is_constructed() and (auto_repeat or manual_pending > 0)


func supply_missing() -> Dictionary:
	var missing = {}
	if not wants_supply():
		return missing
	var cost = squad_cost()
	for res in cost:
		var need = cost[res] - supply.get(res, 0) - incoming.get(res, 0)
		if need > 0:
			missing[res] = need
	return missing


func supply_full() -> bool:
	var cost = squad_cost()
	for res in cost:
		if supply.get(res, 0) < cost[res]:
			return false
	return true


func supply_fraction() -> float:
	var cost = squad_cost()
	var total = 0
	var have = 0
	for res in cost:
		total += cost[res]
		have += min(cost[res], supply.get(res, 0))
	return 1.0 if total == 0 else float(have) / total


func reserve_incoming(resource: String, amount: int):
	incoming[resource] = incoming.get(resource, 0) + amount


func cancel_incoming(resource: String, amount: int):
	incoming[resource] = max(0, incoming.get(resource, 0) - amount)


func deliver_supply(resource: String, amount: int):
	cancel_incoming(resource, amount)
	supply[resource] = supply.get(resource, 0) + amount


func _production_tick(delta):
	if not supply_full():
		return
	if manual_pending > 0:
		manual_left -= delta
		if manual_left <= 0.0:
			manual_pending -= 1
			manual_left = GameData.MANUAL_TRAIN_TIME
			_train_squad()
		return
	if auto_repeat:
		cycle_left -= delta
		if cycle_left <= 0.0:
			cycle_left = GameData.AUTO_REPEAT_INTERVAL
			_train_squad()


func _train_squad():
	var cost = squad_cost()
	for res in cost:
		supply[res] = supply.get(res, 0) - cost[res]
	var match_node = get_tree().get_first_node_in_group("lotr_match")
	match_node.spawn_squadron(player, trains, self, lane)


func set_auto_repeat(enabled: bool, lane_index: int):
	auto_repeat = enabled
	lane = lane_index
	if enabled and cycle_left <= 0.0:
		cycle_left = GameData.AUTO_REPEAT_INTERVAL


func queue_manual():
	manual_pending += 1
	if manual_pending == 1:
		manual_left = GameData.MANUAL_TRAIN_TIME


# --- village house ------------------------------------------------------------------------------
func alive_villagers():
	villagers = villagers.filter(func(v): return is_instance_valid(v) and v.is_inside_tree())
	return villagers


func _villager_tick(delta):
	var count = alive_villagers().size()
	if not initial_villagers_spawned:
		initial_villagers_spawned = true
		for i in range(GameData.VILLAGERS_PER_HOUSE):
			_spawn_villager(i)
		return
	if count >= GameData.VILLAGERS_PER_HOUSE:
		respawn_left = GameData.VILLAGER_RESPAWN_TIME
		return
	respawn_left -= delta
	if respawn_left <= 0.0:
		if player.has_resources(GameData.VILLAGER_RESPAWN_COST):
			player.subtract_resources(GameData.VILLAGER_RESPAWN_COST)
			_spawn_villager(count)
			respawn_left = GameData.VILLAGER_RESPAWN_TIME
		else:
			respawn_left = 0.0  # waits until the player can afford the Food


func _spawn_villager(index: int):
	var match_node = get_tree().get_first_node_in_group("lotr_match")
	var angle = TAU * index / GameData.VILLAGERS_PER_HOUSE
	var offset = Vector3(cos(angle), 0, sin(angle)) * (stats_size() + 1.0)
	var villager = match_node.spawn_unit(
		{"kind": "villager", "faction": player.faction}, global_position + offset, player
	)
	villager.house = self
	villagers.append(villager)


func set_assignment(value: String):
	assignment = value


# --- town center: Ages -------------------------------------------------------------------------
func start_age_advance(target_age: int):
	age_target = target_age
	age_progress = 0.0


func _age_tick(delta):
	var presence = hero_presence()
	if presence.friendly == 0 or presence.enemy > 0:
		build_paused_reason = "enemy_hero" if presence.enemy > 0 else "no_hero"
		return
	build_paused_reason = ""
	age_progress += delta / GameData.AGES[age_target].time
	if age_progress >= 1.0:
		player.age = age_target
		age_target = 0
		age_progress = 0.0
		var match_node = get_tree().get_first_node_in_group("lotr_match")
		match_node.toast_player(
			player.slot_index, "Advanced to the %s Age" % GameData.AGE_NAMES[player.age]
		)


# --- death ---------------------------------------------------------------------------------------
func _handle_unit_death():
	if not puppet and building_key == "storehouse" and is_constructed():
		player.on_storehouse_lost()
	for v in alive_villagers():
		if v.is_sheltered():
			v.hp = 0  # sheltered villagers die with their house
		else:
			v.house = null
	super()
