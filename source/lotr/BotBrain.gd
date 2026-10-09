extends Node
## A computer player and the team Steward. Runs on the host and only issues the same Commands
## a human could.
## - Steward (the team bank, human or bot, while "steward" is on): builds houses and the core
##   buildings and advances the Age from the shared war chest, keeping a reserve for the heroes.
##   On an all-bot team it also researches and sets the barracks marching.
## - Bot hero: hunts camps, claims forgotten towers, pushes its road, retreats when hurt.

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
const PUSH_AFTER = 8.0  # seconds before the hero leaves the base to fight
const HUMAN_RESERVE = 250  # Supplies the Steward leaves for a human team's heroes

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
	if player == null or player.defeated or _match.ended:
		return
	if not player.is_bot and not (player.bank == null and player.steward):
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
	var tc = _tc()
	if tc == null:
		return
	if player.bank == null and player.steward:
		_steward(tc)
	if not player.is_bot:
		return
	var hero = _hero()
	if hero == null or not hero.is_alive():
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
	if _elapsed > PUSH_AFTER:
		_push(hero, tc)


func _steward(tc):
	var full = player.is_bot  # an all-bot city also researches and marches its barracks
	if full:
		_configure_military()
	for i in range(3):  # a few cheap steps per think
		if not _advance_build_order(tc, full):
			break
	# build order done and the chest is overflowing: an all-bot city adds production
	if full and _order_index >= BUILD_ORDER.size() and player.treasury().supplies > 1500:
		for key in ["barracks", "archery_range", "stables", "siege_works"]:
			if GameData.BUILDINGS[key].age <= player.age and player.buildings(key).size() < 3 and _affordable(GameData.BUILDINGS[key].cost):
				var spot = _find_spot(key, tc)
				if spot != null:
					_cmd({"type": "build", "building": key, "pos": spot})
				break


# --- economy ------------------------------------------------------------------------------------


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
	return [] if player.has_resources(cost) else ["supplies"]


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
		var other = _match.team_bank(t.team)
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


func _affordable(cost) -> bool:
	var reserve = 0 if player.is_bot else HUMAN_RESERVE
	return player.treasury().supplies - reserve >= GameData.price(cost)


func _advance_build_order(tc, full) -> bool:
	if _order_index >= BUILD_ORDER.size():
		return false
	var step = BUILD_ORDER[_order_index]
	if step.begins_with("R:") and not full:
		_order_index += 1  # a human team picks its own research
		return true
	if step.begins_with("AGE"):
		var target = int(step.substr(3))
		if player.age >= target:
			_order_index += 1
			return false
		if player.treasury().feats + _match._team_towers(player) < GameData.AGES[target].get("feats", 0):
			return false  # the heroes have to earn the Age first
		if tc.age_target > 0 or not _affordable(GameData.AGES[target].cost):
			return false
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
		if not _affordable(GameData.UPGRADES[key].cost):
			return false
		_cmd({"type": "research", "upgrade": key})
		_order_index += 1
		return true
	var data = GameData.BUILDINGS[step]
	if data.age > player.age:
		return false
	if step == "village_house" and player.buildings("village_house").size() >= GameData.MAX_HOUSES:
		_order_index += 1
		return false
	if not _affordable(data.cost):
		# waiting a long time on one step: grow the economy with another house meanwhile
		_stall += 1
		if _stall > 60 and step != "village_house":
			var houses = player.buildings("village_house").size()
			if houses < GameData.MAX_HOUSES and _affordable(GameData.BUILDINGS.village_house.cost):
				var spot = _find_spot("village_house", tc)
				if spot != null:
					_cmd({"type": "build", "building": "village_house", "pos": spot})
					_stall = 0
					return true
		return false  # wait and gather
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
		# no army in the field: claim towers and clear lairs (that is where the Supplies are),
		# else walk this hero's road towards the enemy city
		if hero.hp > hero.hp_max * 0.6 and (_claim_tower(hero) or _hunt(hero)):
			return
		_walk_road(hero)
		return
	# follow the squadron furthest from home
	var lead = my_squads[0]
	for s in my_squads:
		if s.center().distance_to(tc.global_position) > lead.center().distance_to(tc.global_position):
			lead = s
	var dest = lead.center()
	if hero.global_position.distance_to(dest) > 4.0:
		_cmd({"type": "hero_move", "pos": dest})


func _walk_road(hero):
	"""Each bot hero owns a road (top / middle / bottom by slot) and pushes along it: its own
	tower, then the enemy-side tower, then the enemy city."""
	var nodes = MapGen.road_nodes()
	var road = player.slot_index % 3
	var mine = ["TT0", "M0", "BT0"] if player.team == 1 else ["TT1", "M1", "BT1"]
	var theirs = ["TT1", "M1", "BT1"] if player.team == 1 else ["TT0", "M0", "BT0"]
	var home = _match.base_position(player)
	var enemy_home = MapGen.spawn_points()[1 if player.team == 1 else 0]
	var my_progress = hero.global_position.distance_to(home)
	for goal in [nodes[mine[road]], nodes[theirs[road]], enemy_home]:
		if goal.distance_to(home) > my_progress + 3.0:
			_cmd({"type": "hero_attack_move", "pos": goal})
			return
	_cmd({"type": "hero_attack_move", "pos": enemy_home})


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
		if player.treasury().supplies - reserve >= GameData.ITEMS[key].cost:
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
