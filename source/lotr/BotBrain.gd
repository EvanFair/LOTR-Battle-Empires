extends Node
## A computer player. Runs on the host and only issues the same Commands a human could.
## Build order -> stand at foundations -> villagers on resources -> Age II -> auto-repeat
## squadrons down enemy lanes -> push with the hero, retreat when hurt, defend the base.

const THINK_INTERVAL = 1.0
const BUILD_ORDER = [
	"village_house", "barracks", "village_house", "village_house", "AGE",
	"archery_range", "storehouse", "village_house", "stables", "village_house", "watchtower",
	"village_house", "barracks", "village_house", "village_house",
]
const ASSIGNMENT_PLAN = [
	"food", "wood", "stone", "iron", "food", "wood", "food", "iron", "wood", "stone"
]
const RETREAT_HP = 0.3
const PUSH_AFTER = 150.0  # seconds before the hero leaves the base to fight

var player = null
var _think_left = 1.0
var _order_index = 0
var _elapsed = 0.0
var _rng = RandomNumberGenerator.new()
var _match = null


func _ready():
	_match = get_parent()
	_rng.seed = hash(player.slot_index * 7919 + int(Time.get_ticks_usec()))


func _physics_process(delta):
	if player == null or player.defeated or _match.ended or not player.is_bot:
		return
	_elapsed += delta
	_think_left -= delta
	if _think_left > 0.0:
		return
	_think_left = THINK_INTERVAL
	_think()


func _cmd(cmd: Dictionary):
	cmd["player"] = player.slot_index
	CommandBus.submit(cmd)


func _hero():
	var h = player.hero
	return h if h != null and is_instance_valid(h) else null


func _tc():
	var tcs = player.town_centers()
	return tcs[0] if not tcs.is_empty() else null


func _think():
	var hero = _hero()
	var tc = _tc()
	if hero == null or tc == null:
		return
	_assign_villagers()
	_configure_military()
	if not hero.is_alive():
		return
	_use_abilities(hero)
	if hero.hp < hero.hp_max * RETREAT_HP:
		_cmd({"type": "hero_move", "pos": tc.global_position + Vector3(0, 0, tc.stats_size() + 2)})
		return
	var threat = _base_threat(tc)
	if threat != null:
		_cmd({"type": "hero_attack", "target": threat.net_id})
		_order_nearby_squads(hero, "attack", threat)
		return
	var site = _unfinished_site()
	if site != null:
		_stand_at(hero, site)
		return
	if tc.age_target > 0:
		_stand_at(hero, tc)
		return
	if _advance_build_order(hero, tc):
		return
	if _elapsed > PUSH_AFTER:
		_push(hero, tc)


# --- economy ------------------------------------------------------------------------------------
func _assign_villagers():
	var houses = player.buildings("village_house").filter(func(h): return h.is_constructed())
	for i in range(houses.size()):
		var wanted = ASSIGNMENT_PLAN[i % ASSIGNMENT_PLAN.size()]
		if houses[i].assignment != wanted:
			_cmd({"type": "assign_villagers", "house": houses[i].net_id, "assignment": wanted})


func _configure_military():
	var lanes = _enemy_lanes()
	if lanes.is_empty():
		return
	var producers = player.buildings().filter(func(b): return b.trains != "" and b.is_constructed())
	for i in range(producers.size()):
		var b = producers[i]
		if not b.auto_repeat:
			var lane = lanes[i % lanes.size()]
			_cmd({"type": "set_auto_repeat", "building": b.net_id, "enabled": true, "lane": lane})


func _enemy_lanes() -> Array:
	var result = []
	for lane in _match.lanes_for_player(player):
		var other_slot = lane.b if lane.a == player.slot_index else lane.a
		var other = _match.player_for_slot(other_slot)
		if other != null and not other.defeated and Teams.is_enemy(other, player):
			result.append(lane.index)
	return result


# --- building -----------------------------------------------------------------------------------
func _unfinished_site():
	for b in player.buildings():
		if not b.is_constructed():
			return b
	return null


func _stand_at(hero, building):
	var reach = GameData.BUILD_RANGE + building.stats_size() - 1.5
	if hero.global_position.distance_to(building.global_position) > reach:
		_cmd({"type": "hero_move", "pos": building.global_position + Vector3(building.stats_size() + 1.2, 0, 0)})


func _advance_build_order(hero, tc) -> bool:
	if _order_index >= BUILD_ORDER.size():
		return false
	var step = BUILD_ORDER[_order_index]
	if step == "AGE":
		if player.age >= 2:
			_order_index += 1
			return false
		if not player.in_base(hero.global_position):
			_stand_at(hero, tc)
			return true
		if player.has_resources(GameData.AGES[2].cost):
			_cmd({"type": "advance_age"})
		return true
	var data = GameData.BUILDINGS[step]
	if data.age > player.age:
		return false
	if step == "village_house" and player.buildings("village_house").size() >= GameData.MAX_HOUSES:
		_order_index += 1
		return false
	if not player.has_resources(data.cost):
		return false  # wait and gather
	if not player.in_base(hero.global_position):
		_stand_at(hero, tc)
		return true
	var spot = _find_spot(step, tc)
	if spot == null:
		_order_index += 1
		return false
	_cmd({"type": "build", "building": step, "pos": spot})
	_order_index += 1
	return true


func _find_spot(key, tc):
	var center = Vector3(MapGen.SIZE / 2.0, 0, MapGen.SIZE / 2.0)
	var to_center = (center - tc.global_position).normalized()
	var base_angle = atan2(to_center.z, to_center.x)
	for attempt in range(40):
		var radius = _rng.randf_range(7.0, GameData.BASE_RADIUS - 4.0)
		var angle = base_angle + _rng.randf_range(-2.4, 2.4)
		var pos = tc.global_position + Vector3(cos(angle), 0, sin(angle)) * radius
		if key == "watchtower":
			pos = tc.global_position + to_center * _rng.randf_range(12.0, 18.0)
		if _match.placement_blocker(key, pos) == "" and player.in_base(pos):
			return pos
	return null


# --- fighting -----------------------------------------------------------------------------------
func _base_threat(tc):
	var enemies = Combat.enemies_in_radius(player, tc.global_position, GameData.BASE_RADIUS, get_tree())
	var best = null
	var best_d = INF
	for e in enemies:
		var d = e.global_position.distance_to(tc.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _push(hero, tc):
	var my_squads = get_tree().get_nodes_in_group("squadrons").filter(func(s): return s.player == player)
	var enemy = Combat.closest_enemy(hero, hero.global_position, 12.0)
	if enemy != null:
		_cmd({"type": "hero_attack", "target": enemy.net_id})
		_order_nearby_squads(hero, "attack", enemy)
		return
	if my_squads.is_empty():
		if hero.global_position.distance_to(tc.global_position) > 12.0:
			_stand_at(hero, tc)
		return
	# follow the squadron furthest from home
	var lead = my_squads[0]
	for s in my_squads:
		if s.center().distance_to(tc.global_position) > lead.center().distance_to(tc.global_position):
			lead = s
	var dest = lead.center()
	if hero.global_position.distance_to(dest) > 4.0:
		_cmd({"type": "hero_move", "pos": dest})


func _order_nearby_squads(hero, order, target):
	for s in get_tree().get_nodes_in_group("squadrons"):
		if s.player != player or s.state == s.State.ATTACK:
			continue
		if s.center().distance_to(hero.global_position) <= GameData.COMMAND_RANGE:
			_cmd({"type": "squad_order", "squad": s.squad_id, "order": order, "target": target.net_id})


func _use_abilities(hero):
	var enemy = Combat.closest_enemy(hero, hero.global_position, 10.0)
	if enemy == null:
		return
	for a in hero.abilities():
		if hero.cooldown_left(a.key) > 0.0 or hero.mana < a.mana:
			continue
		var cmd = {"type": "cast", "key": a.key, "pos": enemy.global_position}
		if a.kind in ["execute_strike", "pin_shot"]:
			var reach = a.get("range", 2.0)
			if hero.global_position.distance_to(enemy.global_position) > reach:
				continue
			cmd["target"] = enemy.net_id
		_cmd(cmd)
		return
