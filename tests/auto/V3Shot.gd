extends Node
## v3 visual check: a 3v3 match (you + 5 bots) at 5x speed, screenshots of the city, a road
## and the whole map. Needs a display:
## xvfb-run godot --rendering-driver opengl3 --resolution 1600x900 --path . res://tests/auto/V3Shot.tscn -- --out=/tmp/v3

const LoaderScript = preload("res://source/lotr/menu/MatchLoader.gd")
var out = "/tmp/v3"
var _m = null


func _ready():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.split("=")[1]
	DirAccess.make_dir_recursive_absolute(out)
	Network.leave()
	Network.reset_slots()
	for i in range(1, Network.SLOT_COUNT):
		Network.slots[i].kind = "bot"
	var loader = LoaderScript.new()
	loader.settings = {"slots": Network.slots.duplicate(true), "seed": 777}
	get_tree().root.add_child.call_deferred(loader)
	_run()


func _run():
	while _m == null or not _m.started:
		await get_tree().process_frame
		_m = get_tree().get_first_node_in_group("lotr_match")
	_m.fog_of_war.visible = false
	_m.find_child("FogOfWar").find_child("ScreenOverlay").visible = false
	var me = _m.local_player
	_m._attach_bot(me)  # let a bot drive our hero too
	me.is_bot = true
	Engine.time_scale = 5.0
	Engine.max_physics_steps_per_frame = 40
	await _wait_game(150.0)
	Engine.time_scale = 1.0
	_m.hero_controller.camera_locked = false
	var cam = _m.find_child("IsometricCamera3D")
	cam.set_size_safely(26.0)
	cam.set_position_safely(_m.base_position(me))
	await _shot("city")
	# the busiest fight on the map
	var best = null
	var best_n = 0
	for u in get_tree().get_nodes_in_group("units"):
		if u.get("unit_kind") == "troop" and u.is_alive():
			var n = Combat.enemies_in_radius(u, u.global_position, 8.0, get_tree()).size()
			if n > best_n:
				best_n = n
				best = u
	if best != null:
		cam.set_size_safely(14.0)
		cam.set_position_safely(best.global_position)
		await _shot("battle")
	cam.set_size_safely(90.0)
	cam.set_position_safely(Vector3(MapGen.SIZE / 2.0, 0, MapGen.SIZE / 2.0))
	await _shot("map")
	get_tree().quit()


func _wait_game(seconds):
	var until = GameData.now() + seconds
	while GameData.now() < until:
		await get_tree().process_frame


func _shot(name):
	for i in range(8):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
