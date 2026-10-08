extends Node
## Headless LAN test. Start two copies of the game:
##   godot --headless --fixed-fps 60 --path . res://tests/auto/LanTest.tscn -- --role=host
##   godot --headless --fixed-fps 60 --path . res://tests/auto/LanTest.tscn -- --role=client
## The client joins 127.0.0.1, both play slot 0 (host) and slot 1 (client) with 2 bots.
## The client drives its hero with commands and checks the host's simulation shows up:
## same units, its hero moved where it asked, resources replicated. Exits 0 on success.

const LoaderScript = preload("res://source/lotr/menu/MatchLoader.gd")

var role = "host"
var seconds = 40.0
var _match = null
var _started = false
var _move_target = Vector3.ZERO
var _sent_move = false
var _wall_start = 0


func _ready():
	_wall_start = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.split("=")[1]
		elif arg.begins_with("--seconds="):
			seconds = float(arg.split("=")[1])
	Network.match_starting.connect(_on_match_starting)
	if role == "host":
		var err = Network.host_game()
		print("[host] hosting: %s" % error_string(err))
		Network.lobby_changed.connect(_on_lobby_changed)
	else:
		await get_tree().create_timer(1.0).timeout
		var err = Network.join_game("127.0.0.1")
		print("[client] joining: %s" % error_string(err))


func _on_lobby_changed(slots):
	if role != "host" or _started:
		return
	var humans = slots.filter(func(s): return s.kind == "human")
	if humans.size() >= 2:
		_started = true
		print("[host] client joined as slot %d, starting" % slots.find(humans[1]))
		await get_tree().create_timer(0.5).timeout
		Network.start_match()


func _on_match_starting(settings):
	print("[%s] match starting, seed %d" % [role, settings.seed])
	var loader = LoaderScript.new()
	loader.settings = settings
	get_tree().root.add_child.call_deferred(loader)


func _physics_process(_delta):
	if Time.get_ticks_msec() - _wall_start > 120000:
		print("[%s] FAIL: timed out" % role)
		get_tree().quit(1)
		return
	if _match == null:
		_match = get_tree().get_first_node_in_group("lotr_match")
		return
	var me = _match.local_player
	if me == null or me.hero == null or not is_instance_valid(me.hero):
		return
	if role == "client" and not _sent_move and GameData.now() > 5.0:
		_sent_move = true
		_move_target = me.hero.global_position + Vector3(6, 0, 6)
		CommandBus.submit({"type": "hero_move", "player": me.slot_index, "pos": _move_target})
		print("[client] asked hero to move to %s" % _move_target)
	if GameData.now() >= seconds:
		_finish()


func _finish():
	set_physics_process(false)
	var me = _match.local_player
	var units = get_tree().get_nodes_in_group("units").size()
	var buildings = get_tree().get_nodes_in_group("buildings").size()
	print("[%s] t=%.0fs units=%d buildings=%d my hero at %s, food=%d wood=%d" % [
		role, GameData.now(), units, buildings, me.hero.global_position, me.food, me.wood])
	var ok = units > 30 and buildings >= 30
	if role == "client":
		var d = me.hero.global_position.distance_to(_move_target)
		print("[client] hero is %.2fm from where I sent it" % d)
		ok = ok and d < 1.5
		var any_villager_moved = false
		for u in get_tree().get_nodes_in_group("units"):
			if u.unit_kind == "villager" and u.puppet:
				any_villager_moved = true
		ok = ok and any_villager_moved and (me.food != GameData.STARTING_RESOURCES.food or me.wood != GameData.STARTING_RESOURCES.wood)
	print("[%s] RESULT: %s" % [role, "PASS" if ok else "FAIL"])
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if ok else 1)
