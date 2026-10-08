extends Node
## A computer player. Runs on the host and only issues the same Commands a human could.
## Build order -> stand at foundations -> villagers on resources -> Age II -> auto-repeat
## squadrons down enemy lanes -> push with the hero, retreat when hurt, defend the base.

const THINK_INTERVAL = 1.0
const BUILD_ORDER = [
	"village_house", "barracks", "village_house", "village_house", "AGE2",
	"archery_range", "storehouse", "village_house", "stables", "village_house", "blacksmith",
	"R:forged_blades", "watchtower", "village_house", "R:plated_armour", "village_house",
	"AGE3", "siege_works", "village_house", "special_building", "R:war_drills",
	"R:master_smiths", "barracks",
]
const ASSIGNMENT_PLAN = [
	"food", "wood", "food", "iron", "stone", "food", "wood", "iron", "food", "stone"
]
const RETREAT_HP = 0.3
const PUSH_AFTER = 150.0  # seconds before the hero leaves the base to fight

var player = null
var _think_left = 1.0
var _order_index = 0
var _stall = 0  # thinks spent waiting on the current build step
var _elapsed = 0.0
var _rng = RandomNumberGenerator.new()
var _match = null


func _ready():
	_match = get_parent()
	# seeded from the match so a given match (and every test run) plays out the same way
	_rng.seed = hash(int(_match.match_settings.get("seed", 0)) * 31 + player.slot_index)


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
	_shop(hero)
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
	# villagers are automatic; bots just point the focus at whatever the next step lacks
	var short = _next_step_shortfall().filter(func(r): return r in GameData.GATHERABLE)
	var want = short[0] if not short.is_empty() else "balanced"
	if player.focus != want:
		_cmd({"type": "assign_villagers", "assignment": want})


func _next_step_shortfall() -> Array:
	if _order_index >= BUILD_ORDER.size():
		return []
	var step = BUILD_ORDER[_order_index]
	var cost = {}
	if step.begins_with("AGE"):
		cost = GameData.AGES[int(step.substr(3))].cost
	elif step.begins_with("R:"):
		cost = GameData.UPGRADES[step.substr(2)].cost
	else:
		cost = GameData.BUILDINGS[step].cost
	var short = []
	for res in cost:
		if player.get(res) < cost[res]:
			short.append(res)
	return short


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
	"""March targets for auto-repeat squads: every living enemy base."""
	var result = []
	for t in _match.lanes_for_player(player):
		if t.kind != "base":
			continue
		var other = _match.player_for_slot(t.slot)
		if other != null and not other.defeated and Teams.is_enemy(other, player):
			result.append(t.index)
	return result


func _claim_tower(hero) -> bool:
	"""Walk to the nearest unclaimed forgotten tower and stand on it until it is ours."""
	var best = -1
	var best_d = 55.0
	for i in range(_match.tower_state.size()):
		if _match.tower_holder(i) != null:
			continue
		var d = hero.global_position.distance_to(_match.tower_state[i].site.pos)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return false
	var pos = _match.tower_state[best].site.pos
	if hero.global_position.distance_to(pos) > 3.0:
		_cmd({"type": "hero_move", "pos": pos + Vector3(1.5, 0, 0)})
	return true


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
	if step.begins_with("AGE"):
		var target = int(step.substr(3))
		if player.age >= target:
			_order_index += 1
			return false
		if not player.has_resources(GameData.AGES[target].cost):
			return target == 2  # Age II is worth waiting for; Age III gathers while fighting
		if not player.in_base(hero.global_position):
			_stand_at(hero, tc)
			return true
		_cmd({"type": "advance_age"})
		return true
	if step.begins_with("R:"):
		var key = step.substr(2)
		var smiths = player.buildings("blacksmith").filter(func(b): return b.is_constructed())
		if player.upgrades.get(key, false) or smiths.is_empty():
			_order_index += 1
			return false
		if GameData.UPGRADES[key].age > player.age or smiths[0].research_key != "":
			return false
		if not player.has_resources(GameData.UPGRADES[key].cost):
			return false
		if not player.in_base(hero.global_position):
			_stand_at(hero, tc)
			return true
		_cmd({"type": "research", "upgrade": key})
		_order_index += 1
		return true
	var data = GameData.BUILDINGS[step]
	if data.age > player.age:
		return false
	if step == "village_house" and player.buildings("village_house").size() >= GameData.MAX_HOUSES:
		_order_index += 1
		return false
	if not player.has_resources(data.cost):
		# waiting a long time on one step: grow the economy with another house meanwhile
		_stall += 1
		if _stall > 60 and step != "village_house":
			var houses = player.buildings("village_house").size()
			if houses < GameData.MAX_HOUSES and player.has_resources(GameData.BUILDINGS.village_house.cost) and player.in_base(hero.global_position):
				var spot = _find_spot("village_house", tc)
				if spot != null:
					_cmd({"type": "build", "building": "village_house", "pos": spot})
					_stall = 0
					return true
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
	_stall = 0
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
		# no army in the field: farm the nearest jungle camp while healthy, else wait at home
		if hero.hp > hero.hp_max * 0.65 and (_claim_tower(hero) or _hunt(hero)):
			return
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


func _hunt(hero) -> bool:
	# a creature already fighting us comes first
	for c in get_tree().get_nodes_in_group("units"):
		if c.unit_kind == "creature" and c.is_alive() and c.get("order_target") == hero:
			_cmd({"type": "hero_attack", "target": c.net_id})
			return true
	var best = null
	var best_d = 45.0
	for camp in _match.camps:
		if camp.key == "troll" and hero.level < 8:
			continue  # the Cave Troll is for strong heroes
		for m in camp.members:
			if is_instance_valid(m) and m.is_alive():
				var d = hero.global_position.distance_to(m.global_position)
				if d < best_d:
					best_d = d
					best = m
	if best == null:
		return false
	if hero.order != hero.Order.ATTACK or hero.order_target != best:
		_cmd({"type": "hero_attack", "target": best.net_id})
	return true


func _order_nearby_squads(hero, order, target):
	for s in get_tree().get_nodes_in_group("squadrons"):
		if s.player != player or s.state == s.State.ATTACK:
			continue
		if s.center().distance_to(hero.global_position) <= GameData.COMMAND_RANGE:
			_cmd({"type": "squad_order", "squad": s.squad_id, "order": order, "target": target.net_id})


const BUILD_FIGHTER = ["horse_rohan", "elven_blade", "dwarf_mail", "westernesse"]
const BUILD_CASTER = ["horse_rohan", "ring_barahir", "dwarf_mail", "phial"]


func _shop(hero):
	if not player.in_base(hero.global_position) or hero.items.size() >= GameData.ITEM_SLOTS:
		return
	var caster = GameData.HEROES[hero.hero_key].role in ["Caster", "Enchanter"]
	var plan = BUILD_CASTER if caster else BUILD_FIGHTER
	var owned = hero.items.map(func(it): return it.key)
	for key in plan:
		if key in owned:
			continue
		# keep enough Gold for Age III and research once the Kingdom Age is reached
		var reserve = 100 if player.age >= 2 else 0
		if player.gold - reserve >= GameData.ITEMS[key].cost:
			_cmd({"type": "buy", "item": key})
		return


func _learn_abilities(hero):
	if hero.skill_points() <= 0:
		return
	# R whenever possible, otherwise the lowest-ranked of Q/W/E (Q first on ties)
	if hero.can_learn("R") == "":
		_cmd({"type": "learn", "key": "R"})
		return
	var best = ""
	for key in ["Q", "W", "E"]:
		if hero.can_learn(key) == "" and (best == "" or hero.ability_rank(key) < hero.ability_rank(best)):
			best = key
	if best != "":
		_cmd({"type": "learn", "key": best})


func _use_abilities(hero):
	_learn_abilities(hero)
	var enemy = Combat.closest_enemy(hero, hero.global_position, 12.0)
	if enemy == null:
		return
	var distance = hero.global_position.distance_to(enemy.global_position)
	for a in hero.abilities():
		if hero.ability_rank(a.key) < 1 or hero.cooldown_left(a.key) > 0.0 or hero.mana < a.mana:
			continue
		var aim = HeroAbilities.aim(a)
		var cmd = {"type": "cast", "key": a.key, "pos": enemy.global_position}
		match aim.mode:
			"unit":
				if distance > aim.range + 0.5:
					continue
				cmd["target"] = enemy.net_id
			"self":
				# novas need enemies in reach; buffs and rallies are for when a fight is close
				var reach = aim.radius if a.kind == "nova" else 8.0
				if distance > reach:
					continue
			"point", "line":
				if a.kind != "summon" and distance > aim.range:
					continue
				if a.kind == "dash" and hero.hp > hero.hp_max * 0.5:
					continue  # bots keep dashes for escaping or chasing low targets
		_cmd(cmd)
		return
