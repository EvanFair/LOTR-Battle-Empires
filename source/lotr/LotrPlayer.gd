extends "res://source/match/players/Player.gd"
## One player in the match: their faction, team, hero, and (through `bank`) the team's city.
##
## v3: a team shares ONE city and ONE war chest of Supplies. The team's first player is the
## "bank": it owns the stockpile, Age and upgrades; teammates read and spend through treasury().
## Costs in GameData stay per resource and are converted with GameData.price().

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
var _age = 1
var age:  # the team's Age (shared through the bank)
	get:
		return treasury()._age
	set(v):
		treasury()._age = v
var defeated = false
var storehouse_ready_at = 0.0  # time (s) when a lost Storehouse may be rebuilt
var hero = null
var bank = null  # the teammate holding the shared city and Supplies (null = this player)
@export var supplies = 0:
	set(v):
		supplies = v
		emit_changed()
var spend_log = []  # recent team purchases: [{who, what, amount, at}]
var _upgrades = {}
var upgrades:  # finished Blacksmith research, shared by the team: key -> true
	get:
		return treasury()._upgrades
	set(v):
		treasury()._upgrades = v
var focus = "balanced"  # villagers split themselves between resources, leaning towards this
var _shelter = false
var shelter:  # all the team's villagers hide in their houses
	get:
		return treasury()._shelter
	set(v):
		treasury()._shelter = v
var feats = 0  # (bank) lairs cleared: one is needed before the next Age
var steward = true  # (bank) the city builds houses and core buildings by itself
var income = {}  # resource -> gathered in the current minute window
var income_per_min = {}
var _income_window_start = 0.0


func _ready():
	if not is_neutral:
		add_to_group("lotr_players")


func treasury():
	"""The player that holds this team's shared stockpile."""
	return bank if bank != null and is_instance_valid(bank) else self


func resources() -> Dictionary:
	return {"supplies": treasury().supplies}


func set_resources(values: Dictionary):
	if values.has("supplies"):
		treasury().supplies = int(values.supplies)
	else:
		treasury().supplies = GameData.price(values)


func add_resources(values):
	var t = treasury()
	t.supplies += GameData.price(values)


func has_resources(values):
	if FeatureFlags.allow_resources_deficit_spending:
		return true
	return treasury().supplies >= GameData.price(values)


func subtract_resources(values):
	var t = treasury()
	t.supplies -= GameData.price(values)


func missing_text(cost: Dictionary) -> String:
	var need = GameData.price(cost) - treasury().supplies
	if need > 0:
		return "Not enough Supplies (need %d more)" % need
	return ""


func log_spend(what: String, amount: int):
	"""Team purchase feed (WorldQuest lesson: a shared purse needs to show who spent it)."""
	var t = treasury()
	t.spend_log.push_front({"who": player_name, "what": what, "amount": amount, "at": GameData.now()})
	if t.spend_log.size() > 6:
		t.spend_log.resize(6)


func on_storehouse_lost():
	var t = treasury()
	var lost = int(t.supplies * GameData.STOREHOUSE_LOSS_FACTOR)
	t.supplies -= lost
	storehouse_ready_at = GameData.now() + GameData.STOREHOUSE_REBUILD_COOLDOWN
	var parts = ["-%d Supplies" % lost]
	var match_node = get_tree().get_first_node_in_group("lotr_match")
	if match_node != null:
		match_node.toast_player(
			slot_index, "Storehouse destroyed: stockpile halved (%s)" % ", ".join(parts)
		)


func note_income(resource: String, amount: int):
	var t = treasury()
	if t != self:
		t.note_income(resource, amount)
		return
	var now = GameData.now()
	if now - _income_window_start >= 60.0:
		income_per_min = income.duplicate()
		income.clear()
		_income_window_start = now
	income[resource] = income.get(resource, 0) + amount


# --- buildings ---------------------------------------------------------------------------------
func buildings(key = ""):
	var t = treasury()
	return get_tree().get_nodes_in_group("buildings").filter(
		func(b): return b.is_alive() and (key == "" or b.building_key == key) and _same_city(b.player, t)
	)


func _same_city(owner, t) -> bool:
	return owner != null and (owner == self or (owner.has_method("treasury") and owner.treasury() == t))


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
			var stock = treasury().supplies
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


# --- automatic villagers -----------------------------------------------------------------------
const BASE_SHARES = {"food": 0.25, "wood": 0.30, "stone": 0.2, "iron": 0.25}
const FOCUS_BONUS = 0.45


func villager_shares() -> Dictionary:
	"""Fraction of villagers on each resource, from the focus and what is left on the map."""
	var shares = BASE_SHARES.duplicate()
	if shares.has(focus):
		shares[focus] += FOCUS_BONUS
	var available = {}
	var match_node = get_tree().get_first_node_in_group("lotr_match")
	for r in get_tree().get_nodes_in_group("lotr_resources"):
		if not r.is_depleted() and (match_node == null or not match_node.site_guarded(r.global_position)):
			available[r.resource_type] = true
	for res in shares.keys():
		if not available.has(res):
			shares.erase(res)  # nothing left of it on the map
	if shares.is_empty():
		return {"food": 1.0}
	var total = 0.0
	for res in shares:
		total += shares[res]
	for res in shares:
		shares[res] /= total
	return shares


func rebalance_villagers():
	"""Host: give every villager a job so the split matches villager_shares(), moving as few
	villagers as possible."""
	var workers = []
	for h in buildings("village_house"):
		workers.append_array(h.alive_villagers())
	if workers.is_empty():
		return
	workers.sort_custom(func(a, b): return a.net_id < b.net_id)
	var shares = villager_shares()
	var target = {}
	var assigned = 0
	var order = shares.keys()
	order.sort_custom(func(a, b): return shares[a] > shares[b])
	for res in order:
		target[res] = int(floor(shares[res] * workers.size()))
		assigned += target[res]
	var i = 0
	while assigned < workers.size():
		target[order[i % order.size()]] += 1
		assigned += 1
		i += 1
	var counts = {}
	var loose = []
	for v in workers:
		if v.job != "" and counts.get(v.job, 0) < target.get(v.job, 0):
			counts[v.job] = counts.get(v.job, 0) + 1
		else:
			loose.append(v)
	for v in loose:
		for res in order:
			if counts.get(res, 0) < target[res]:
				v.job = res
				counts[res] = counts.get(res, 0) + 1
				break
