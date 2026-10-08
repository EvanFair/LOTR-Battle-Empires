extends "res://source/match/Match.gd"
## The LOTR match. Reuses open-rts's map, navigation, fog of war, camera and minimap, and adds
## players with teams, heroes, villagers, squadrons, lanes and LAN replication.
## The host simulates everything; clients render puppets fed by the Replicator.

signal toast(text)
signal match_over(won)

const LotrPlayerScript = preload("res://source/lotr/LotrPlayer.gd")
const SquadronScript = preload("res://source/lotr/Squadron.gd")
const ReplicatorScript = preload("res://source/lotr/net/Replicator.gd")
const HeroControllerScript = preload("res://source/lotr/HeroController.gd")
const HudScript = preload("res://source/lotr/hud/LotrHud.gd")
const BotScript = preload("res://source/lotr/BotBrain.gd")

const INNER_TOWER_DISTANCE = 7.5
const OUTER_TOWER_DISTANCE = 18.0
const WIN_CHECK_INTERVAL = 1.0

var match_settings = {}  # {"slots": [...], "seed": int}
var players_by_slot = {}
var local_player = null
var lanes = []
var replicator = null
var hud = null
var hero_controller = null
var ended = false
var started = false
var winning_team = -1

var _next_net_id = 1
var _next_squad_id = 1
var _registry = {}
var _squads_root = null
var _win_check_left = WIN_CHECK_INTERVAL


func _enter_tree():
	add_to_group("lotr_match")
	assert(map != null, "map must be set before adding the match")


func _ready():
	GameData.reset_clock()
	seed(int(match_settings.get("seed", 0)))
	lanes = map.get_meta("lanes")
	_setup_subsystems_dependent_on_map()
	_squads_root = Node.new()
	_squads_root.name = "Squadrons"
	add_child(_squads_root)
	_create_players()
	_register_resources()
	_register_commands()
	replicator = ReplicatorScript.new()
	replicator.name = "Replicator"
	add_child(replicator)
	if is_host():
		_start_host_simulation()
	if local_player == null:
		fog_of_war.reveal()
	hud = HudScript.new()
	hud.name = "LotrHud"
	add_child(hud)
	if local_player != null:
		hero_controller = HeroControllerScript.new()
		hero_controller.name = "HeroController"
		add_child(hero_controller)
	_move_camera_to_start()
	Network.peer_left.connect(_on_peer_left)
	Network.host_left.connect(_on_host_left)
	MatchSignals.match_started.emit()


func _start_host_simulation():
	await replicator.wait_for_clients()
	_spawn_bases()
	_attach_bots()
	started = true


func _unhandled_input(_event):
	pass  # no RTS selection in this game


func _exit_tree():
	CommandBus.clear()


func is_host():
	return Network.is_host()


func _get_visible_players():
	if local_player == null:
		return get_tree().get_nodes_in_group("lotr_players")
	return get_tree().get_nodes_in_group("lotr_players").filter(
		func(p): return Teams.is_ally(p, local_player)
	)


func _set_visible_player(_player):
	pass  # visibility follows the local player's team


# --- players ----------------------------------------------------------------------------------
func _create_players():
	var slots = match_settings.slots
	var me = Network.local_peer_id()
	for i in range(slots.size()):
		var slot = slots[i]
		if slot.kind == "open":
			continue
		var p = LotrPlayerScript.new()
		p.name = "Player%d" % i
		p.slot_index = i
		p.player_name = slot.name
		p.faction = slot.faction
		p.team = slot.team
		p.hero_key = slot.hero
		p.peer_id = slot.peer if slot.kind == "human" else 0
		p.is_bot = slot.kind == "bot"
		p.color = Constants.Player.COLORS[i]
		p.set_resources(GameData.STARTING_RESOURCES)
		_players.add_child(p)
		p.add_to_group("players")
		players_by_slot[i] = p
		if slot.kind == "human" and slot.peer == me:
			local_player = p


func player_for_slot(slot):
	return players_by_slot.get(int(slot))


func _owner_check(player_index, peer_id) -> bool:
	var p = player_for_slot(player_index)
	return p != null and p.peer_id == peer_id and not p.is_bot


func _attach_bots():
	for p in players_by_slot.values():
		if p.is_bot:
			_attach_bot(p)


func _attach_bot(p):
	var bot = BotScript.new()
	bot.name = "Bot%d" % p.slot_index
	bot.player = p
	add_child(bot)


func _on_peer_left(peer_id):
	if not is_host():
		return
	for p in players_by_slot.values():
		if p.peer_id == peer_id and not p.is_bot:
			p.is_bot = true
			p.peer_id = 0
			_attach_bot(p)
			broadcast_toast("%s disconnected; a bot is taking over" % p.player_name)


func _on_host_left():
	if hud != null:
		hud.show_end_screen("The host left the game.", false)


# --- spawning (host) --------------------------------------------------------------------------
func _spawn_bases():
	var spawns = MapGen.spawn_points()
	var center = Vector3(MapGen.SIZE / 2.0, 0, MapGen.SIZE / 2.0)
	for slot in players_by_slot:
		var p = players_by_slot[slot]
		var origin = spawns[slot]
		var to_center = (center - origin).normalized()
		spawn_building(p, "town_center", origin, false)
		var house_pos = origin - to_center * 6.0 + Vector3(to_center.z, 0, -to_center.x) * 3.0
		spawn_building(p, "village_house", house_pos, false)
		for i in range(3):
			var a = atan2(to_center.z, to_center.x) + (i - 1) * 0.9
			var inner = origin + Vector3(cos(a), 0, sin(a)) * INNER_TOWER_DISTANCE
			spawn_building(p, "watchtower", inner, false)
			var outer = origin + Vector3(cos(a), 0, sin(a)) * OUTER_TOWER_DISTANCE
			spawn_building(p, "watchtower", outer, false)
		var hero = spawn_unit(
			{"kind": "hero", "hero": p.hero_key}, origin + to_center * 4.5, p
		)
		hero.home_position = hero.global_position
		p.hero = hero


func spawn_building(p, key: String, position: Vector3, under_construction = true):
	var params = {"kind": "building", "building": key, "faction": p.faction}
	return spawn_unit(params, position, p, {"under_construction": under_construction})


func spawn_unit(params: Dictionary, position: Vector3, p, extra = {}):
	var unit = UnitFactory.create(params)
	unit.net_id = _alloc_net_id()
	if extra.get("under_construction", false):
		unit.mark_under_construction()
	_add_unit(unit, position, p, extra.get("yaw", 0.0))
	replicator.on_host_spawn(unit)
	return unit


func spawn_puppet(net_id: int, params: Dictionary, position: Vector3, yaw: float, p, extra = {}):
	"""Client side: build a puppet that mirrors a host unit."""
	var unit = UnitFactory.create(params)
	unit.net_id = net_id
	unit.puppet = true
	if extra.get("under_construction", false):
		unit.mark_under_construction()
	_add_unit(unit, position, p, yaw)
	if unit.unit_kind == "hero":
		p.hero = unit
	return unit


func _add_unit(unit, position: Vector3, p, yaw: float):
	unit.transform = Transform3D(Basis(Vector3.UP, yaw), position)
	_setup_unit_groups(unit, p)
	p.add_child(unit)
	_registry[unit.net_id] = unit
	unit.tree_exited.connect(_on_unit_exit.bind(unit.net_id))
	MatchSignals.unit_spawned.emit(unit)


func _setup_unit_groups(unit, p):
	unit.add_to_group("units")
	if local_player != null and Teams.is_ally(p, local_player):
		unit.add_to_group("controlled_units")
	else:
		unit.add_to_group("adversary_units")
	if p in visible_players:
		unit.add_to_group("revealed_units")


func _on_unit_exit(net_id):
	_registry.erase(net_id)
	if replicator != null and is_inside_tree():
		replicator.on_host_despawn(net_id)


func _alloc_net_id():
	var id = _next_net_id
	_next_net_id += 1
	return id


func _register_resources():
	# resource nodes come from the map; both sides generate them identically, so ids line up
	for node in map.find_child("Resources").get_children():
		node.net_id = _alloc_net_id()
		node.puppet = not is_host()
		_registry[node.net_id] = node
		node.tree_exited.connect(_on_unit_exit.bind(node.net_id))


func by_net_id(net_id):
	var node = _registry.get(int(net_id))
	return node if node != null and is_instance_valid(node) else null


func spawn_squadron(p, unit_class: String, building, lane_index: int):
	var stats = GameData.troop_stats(p.faction, unit_class)
	var front = building.global_position
	var center = Vector3(MapGen.SIZE / 2.0, 0, MapGen.SIZE / 2.0)
	var out_dir = (center - front).normalized()
	front += out_dir * (building.stats_size() + 2.5)
	var units = []
	for i in range(stats.squad_size):
		var offset = Vector3((i % 4) - 1.5, 0, int(i / 4)) * 1.1
		units.append(
			spawn_unit({"kind": "troop", "faction": p.faction, "class": unit_class}, front + offset, p)
		)
	var squad = make_squadron(p, unit_class, units, building.global_position)
	if lane_index >= 0 and lane_index < lanes.size():
		squad.march(MapGen.lane_points_from(lanes[lane_index], p.slot_index))
	else:
		squad.order_defend(front + out_dir * 3.0)
	return squad


func make_squadron(p, unit_class, units, home):
	var squad = SquadronScript.new()
	squad.squad_id = _next_squad_id
	_next_squad_id += 1
	_squads_root.add_child(squad)
	var tc = p.town_centers()
	squad.setup(p, unit_class, units, tc[0].global_position if not tc.is_empty() else home)
	return squad


func squad_by_id(squad_id):
	for s in get_tree().get_nodes_in_group("squadrons"):
		if s.squad_id == int(squad_id):
			return s
	return null


func lanes_for_player(p) -> Array:
	return lanes.filter(func(l): return l.a == p.slot_index or l.b == p.slot_index)


func lane_label(lane_index: int, p) -> String:
	var lane = lanes[lane_index]
	var other = lane.b if lane.a == p.slot_index else lane.a
	var other_player = player_for_slot(other)
	var who = other_player.player_name if other_player != null else "empty base"
	var relation = ""
	if other_player != null:
		relation = " (ally)" if Teams.is_ally(other_player, p) else " (enemy)"
	return "%s lane → %s%s" % [lane.name, who, relation]


# --- commands (host) --------------------------------------------------------------------------
func _register_commands():
	CommandBus.clear()
	CommandBus.set_owner_check(_owner_check)
	CommandBus.register("hero_move", _cmd_hero_move)
	CommandBus.register("hero_attack", _cmd_hero_attack)
	CommandBus.register("hero_stop", _cmd_hero_stop)
	CommandBus.register("cast", _cmd_cast)
	CommandBus.register("squad_order", _cmd_squad_order)
	CommandBus.register("assign_villagers", _cmd_assign_villagers)
	CommandBus.register("build", _cmd_build)
	CommandBus.register("cancel_build", _cmd_cancel_build)
	CommandBus.register("set_auto_repeat", _cmd_set_auto_repeat)
	CommandBus.register("train", _cmd_train)
	CommandBus.register("advance_age", _cmd_advance_age)


func _hero_of(cmd):
	var p = player_for_slot(cmd.player)
	if p == null or p.defeated:
		return null
	var hero = p.hero
	return hero if hero != null and is_instance_valid(hero) else null


func _alive_hero(cmd):
	var hero = _hero_of(cmd)
	if hero == null or not hero.is_alive():
		return null
	return hero


func _cmd_hero_move(cmd):
	var hero = _alive_hero(cmd)
	if hero == null:
		return "Your hero is dead"
	hero.order_move(cmd.pos)
	return ""


func _cmd_hero_attack(cmd):
	var hero = _alive_hero(cmd)
	var target = by_net_id(cmd.target)
	if hero == null or target == null or not hero.is_enemy_of(target):
		return ""
	hero.order_attack(target)
	return ""


func _cmd_hero_stop(cmd):
	var hero = _alive_hero(cmd)
	if hero != null:
		hero.order_stop()
	return ""


func _cmd_cast(cmd):
	var hero = _alive_hero(cmd)
	if hero == null:
		return "Your hero is dead"
	var target = by_net_id(cmd.get("target", 0)) if cmd.get("target", 0) else null
	return HeroAbilities.cast(self, hero, cmd.key, cmd.get("pos"), target)


func _cmd_squad_order(cmd):
	var hero = _alive_hero(cmd)
	if hero == null:
		return "Your hero is dead"
	var squad = squad_by_id(cmd.squad)
	if squad == null or squad.player != hero.player:
		return "That squadron is gone"
	if squad.center().distance_to(hero.global_position) > GameData.COMMAND_RANGE + 2.0:
		return "Move closer to the squadron to command it"
	match cmd.order:
		"attack":
			var target = by_net_id(cmd.get("target", 0))
			if target == null or not hero.is_enemy_of(target):
				return "Pick an enemy to attack"
			squad.order_attack(target)
		"defend":
			squad.order_defend(cmd.pos)
		"hold":
			squad.order_hold()
		"return":
			squad.order_return()
	return ""


func _cmd_assign_villagers(cmd):
	var hero = _alive_hero(cmd)
	var house = by_net_id(cmd.house)
	if hero == null or house == null or house.player != hero.player:
		return "Your hero is dead" if hero == null else ""
	if cmd.assignment not in GameData.GATHERABLE and cmd.assignment != "home":
		return ""
	var near = house.global_position.distance_to(hero.global_position) <= GameData.COMMAND_RANGE
	if not near and not hero.player.in_base(hero.global_position):
		return "Get your hero into the base or near the villagers"
	house.set_assignment(cmd.assignment)
	return ""


func _cmd_build(cmd):
	var hero = _alive_hero(cmd)
	if hero == null:
		return "Your hero is dead"
	var p = hero.player
	var key = cmd.building
	if not GameData.BUILDINGS.has(key) or not GameData.BUILDINGS[key].get("buildable", true):
		return "Can't build that"
	var data = GameData.BUILDINGS[key]
	if data.age > p.age:
		return "Requires the %s Age" % GameData.AGE_NAMES[data.age]
	var pos: Vector3 = cmd.pos
	if data.get("base_only", true) and not p.in_base(pos):
		return "%s must be built inside your base" % data.name
	if not data.get("base_only", true) and not p.in_base(pos):
		if pos.distance_to(hero.global_position) > GameData.COMMAND_RANGE * 2:
			return "Too far from your hero"
	if key == "village_house" and p.buildings("village_house").size() >= GameData.MAX_HOUSES:
		return "You already have %d Village Houses" % GameData.MAX_HOUSES
	if data.has("max") and p.buildings(key).size() >= data.max:
		return "You can only have %d %s" % [data.max, data.name]
	if key == "storehouse" and GameData.now() < p.storehouse_ready_at:
		return "Storehouse can be rebuilt in %ds" % ceili(p.storehouse_ready_at - GameData.now())
	var blocked = placement_blocker(key, pos)
	if blocked != "":
		return blocked
	if not p.has_resources(data.cost):
		return p.missing_text(data.cost)
	p.subtract_resources(data.cost)
	spawn_building(p, key, pos, true)
	return ""


func placement_blocker(key: String, pos: Vector3) -> String:
	var size = GameData.BUILDINGS[key].size
	if pos.x < size or pos.z < size or pos.x > MapGen.SIZE - size or pos.z > MapGen.SIZE - size:
		return "Too close to the map edge"
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.is_alive() and b.global_position_yless.distance_to(pos * Vector3(1, 0, 1)) < size + b.stats_size() + 0.6:
			return "Something is in the way"
	for r in get_tree().get_nodes_in_group("lotr_resources"):
		if r.global_position_yless.distance_to(pos * Vector3(1, 0, 1)) < size + 1.2:
			return "Something is in the way"
	return ""


func _cmd_cancel_build(cmd):
	var b = by_net_id(cmd.target)
	var p = player_for_slot(cmd.player)
	if b != null and b.player == p and not b.is_constructed():
		b.cancel_construction()
	return ""


func _base_panel_check(cmd):
	var hero = _alive_hero(cmd)
	if hero == null:
		return "Your hero is dead"
	if not hero.player.in_base(hero.global_position):
		return "Return to your base first"
	return ""


func _cmd_set_auto_repeat(cmd):
	var err = _base_panel_check(cmd)
	if err != "":
		return err
	var b = by_net_id(cmd.building)
	if b == null or b.player != player_for_slot(cmd.player) or b.trains == "":
		return ""
	b.set_auto_repeat(cmd.enabled, int(cmd.get("lane", -1)))
	return ""


func _cmd_train(cmd):
	var err = _base_panel_check(cmd)
	if err != "":
		return err
	var b = by_net_id(cmd.building)
	if b == null or b.player != player_for_slot(cmd.player) or b.trains == "" or not b.is_constructed():
		return ""
	b.queue_manual()
	return ""


func _cmd_advance_age(cmd):
	var err = _base_panel_check(cmd)
	if err != "":
		return err
	var p = player_for_slot(cmd.player)
	var target = p.age + 1
	if not GameData.AGES.has(target) or target > 2:
		return "No further Ages yet"
	var tc = p.town_centers()
	if tc.is_empty():
		return "You need a Town Center"
	if tc[0].age_target > 0:
		return "Already advancing"
	var cost = GameData.AGES[target].cost
	if not p.has_resources(cost):
		return p.missing_text(cost)
	p.subtract_resources(cost)
	tc[0].start_age_advance(target)
	return ""


# --- win condition (host) ---------------------------------------------------------------------
func _physics_process(delta):
	if ended or not started or not is_host():
		return
	_win_check_left -= delta
	if _win_check_left > 0.0:
		return
	_win_check_left = WIN_CHECK_INTERVAL
	for p in players_by_slot.values():
		if not p.defeated and p.town_centers().is_empty():
			_defeat(p)
	var teams_alive = {}
	for p in players_by_slot.values():
		if not p.defeated:
			teams_alive[p.team] = true
	if teams_alive.size() <= 1:
		var team = teams_alive.keys()[0] if teams_alive.size() == 1 else -1
		end_match(team)


func _defeat(p):
	p.defeated = true
	broadcast_toast("%s (%s) has been defeated!" % [p.player_name, GameData.FACTIONS[p.faction].name])
	for child in p.get_children():
		if child.has_method("is_alive") and child.is_alive():
			child.hp = 0


func end_match(team):
	ended = true
	winning_team = team
	replicator.send_match_over(team)
	_show_match_over(team)


func _show_match_over(team):
	ended = true
	winning_team = team
	var won = local_player != null and local_player.team == team
	if local_player == null:
		hud.show_end_screen("Team %d wins!" % team, true)
	else:
		hud.show_end_screen("Victory!" if won else "Defeat", won)
	if won:
		MatchSignals.match_finished_with_victory.emit()
	else:
		MatchSignals.match_finished_with_defeat.emit()
	match_over.emit(won)


# --- toasts and effects -----------------------------------------------------------------------
func toast_player(slot, text: String):
	var p = player_for_slot(slot)
	if p == null:
		return
	if p == local_player:
		toast.emit(text)
	elif p.peer_id > 1 and Network.is_online():
		replicator.send_toast(p.peer_id, text)


func broadcast_toast(text: String):
	toast.emit(text)
	if is_host():
		replicator.send_toast(0, text)


func fx(kind: String, from: Vector3, to: Vector3):
	if hud != null:
		hud.play_fx(kind, from, to)
	if is_host() and replicator != null:
		replicator.queue_fx(kind, from, to)


func _move_camera_to_start():
	_camera.set_size_safely(30.0)
	var focus = Vector3(MapGen.SIZE / 2.0, 0, MapGen.SIZE / 2.0)
	if local_player != null:
		focus = MapGen.spawn_points()[local_player.slot_index]
	_camera.set_position_safely(focus)
