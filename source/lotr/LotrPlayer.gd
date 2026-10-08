extends "res://source/match/players/Player.gd"
## One player in the match: their faction, team, stockpile, Age and hero.

signal toast(text)

@export var food = 0:
	set(v):
		food = v
		emit_changed()
@export var wood = 0:
	set(v):
		wood = v
		emit_changed()
@export var stone = 0:
	set(v):
		stone = v
		emit_changed()
@export var iron = 0:
	set(v):
		iron = v
		emit_changed()
@export var gold = 0:
	set(v):
		gold = v
		emit_changed()

var slot_index = 0
var player_name = "Player"
var faction = "gondor"
var team = 1
var hero_key = "aragorn"
var peer_id = 0  # 0 = bot, 1 = host, >1 = client
var is_bot = false
var is_neutral = false  # the wild creatures' owner: enemy of everyone, never wins or loses
var age = 1
var defeated = false
var storehouse_ready_at = 0.0  # time (s) when a lost Storehouse may be rebuilt
var hero = null
var upgrades = {}  # finished Blacksmith research: key -> true
var income = {}  # resource -> gathered in the current minute window
var income_per_min = {}
var _income_window_start = 0.0


func _ready():
	if not is_neutral:
		add_to_group("lotr_players")


func resources() -> Dictionary:
	var result = {}
	for res in GameData.RESOURCES:
		result[res] = get(res)
	return result


func set_resources(values: Dictionary):
	for res in values:
		set(res, values[res])


func missing_text(cost: Dictionary) -> String:
	for res in GameData.RESOURCES:
		if cost.get(res, 0) > get(res):
			return "Not enough %s (need %d more)" % [res.capitalize(), cost[res] - get(res)]
	return ""


func on_storehouse_lost():
	var lost = {}
	for res in GameData.RESOURCES:
		var amount = get(res)
		var remaining = int(amount * (1.0 - GameData.STOREHOUSE_LOSS_FACTOR))
		lost[res] = amount - remaining
		set(res, remaining)
	storehouse_ready_at = GameData.now() + GameData.STOREHOUSE_REBUILD_COOLDOWN
	var parts = []
	for res in GameData.RESOURCES:
		if lost[res] > 0:
			parts.append("-%d %s" % [lost[res], res.capitalize()])
	var match_node = get_tree().get_first_node_in_group("lotr_match")
	if match_node != null:
		match_node.toast_player(
			slot_index, "Storehouse destroyed: stockpile halved (%s)" % ", ".join(parts)
		)


func note_income(resource: String, amount: int):
	var now = GameData.now()
	if now - _income_window_start >= 60.0:
		income_per_min = income.duplicate()
		income.clear()
		_income_window_start = now
	income[resource] = income.get(resource, 0) + amount


# --- buildings ---------------------------------------------------------------------------------
func buildings(key = ""):
	return get_tree().get_nodes_in_group("buildings").filter(
		func(b): return b.player == self and b.is_alive() and (key == "" or b.building_key == key)
	)


func town_centers():
	return buildings("town_center").filter(func(b): return b.is_constructed())


func closest_access_point(from: Vector3):
	var best = null
	var best_d = INF
	for b in buildings():
		if not b.is_access_point():
			continue
		var d = b.global_position.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = b
	return best


func in_base(point: Vector3) -> bool:
	for tc in buildings("town_center"):
		if tc.global_position_yless.distance_to(point * Vector3(1, 0, 1)) <= GameData.BASE_RADIUS:
			return true
	return false


# --- hauling -------------------------------------------------------------------------------------
func request_haul_job(villager) -> Dictionary:
	"""Called when a villager drops off. Returns {building, resource, amount} or {}."""
	var best = {}
	var best_d = INF
	for b in buildings():
		if not b.wants_supply():
			continue
		var missing = b.supply_missing()
		for res in missing:
			var stock = get(res)
			if stock <= 0:
				continue
			var d = b.global_position.distance_squared_to(villager.global_position)
			if d < best_d:
				best_d = d
				best = {"building": b, "resource": res, "amount": mini(
					GameData.HAUL_LOAD, mini(missing[res], stock))}
	if best.is_empty():
		return best
	subtract_resources({best.resource: best.amount})  # taken from the stockpile at pickup
	best.building.reserve_incoming(best.resource, best.amount)
	return best
