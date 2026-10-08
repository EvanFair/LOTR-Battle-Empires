extends Node
## Renders a few screenshots of a single-player match (needs a display; use xvfb-run).
## godot --rendering-driver opengl3 --path . res://tests/auto/Screenshots.tscn -- --out=/tmp/shots

const LoaderScript = preload("res://source/lotr/menu/MatchLoader.gd")

var out_dir = "user://shots"
var _match = null
var _shots = [
	[3.0, "01_start", ""],
	[40.0, "02_base_panel", "base"],
	[45.0, "03_bubbles", "bubbles"],
	[300.0, "04_battle", "battle"],
	[302.0, "05_battle_close", "battle_close"],
	[304.0, "06_hero_close", "hero_close"],
	[306.0, "07_mordor_base", "mordor"],
	[308.0, "08_rohan_base", "rohan"],
]
var _index = 0
var _busy = false
var _battle_focus = Vector3.ZERO


func _ready():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.split("=")[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	Network.leave()
	Network.reset_slots()
	for i in range(1, Network.SLOT_COUNT):
		Network.slots[i].kind = "bot"
	Network.apply_team_preset("team")
	var loader = LoaderScript.new()
	loader.settings = {"slots": Network.slots.duplicate(true), "seed": 4242}
	get_tree().root.add_child.call_deferred(loader)
	Engine.time_scale = 4.0


func _process(_delta):
	if _match == null:
		_match = get_tree().get_first_node_in_group("lotr_match")
		return
	if _busy:
		return
	if _index >= _shots.size():
		get_tree().quit()
		return
	var shot = _shots[_index]
	if GameData.now() < shot[0]:
		return
	_index += 1
	_busy = true
	_prepare(shot[2])
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	var path = "%s/%s.png" % [out_dir, shot[1]]
	img.save_png(path)
	print("saved ", path)
	_busy = false


func _prepare(kind):
	var me = _match.local_player
	match kind:
		"base":
			_match.hud._base_panel.visible = true
		"bubbles":
			_match.hud._base_panel.visible = false
			_match.hud.show_bubbles(me.buildings("village_house")[0])
		"battle":
			_match.hud._bubbles.visible = false
			# look at the busiest fight on the map
			# the squadron furthest from every base is the one out fighting in the lanes
			var best = null
			var best_d = -1.0
			for s in get_tree().get_nodes_in_group("squadrons"):
				var c = s.center()
				var d = INF
				for sp in MapGen.spawn_points():
					d = min(d, c.distance_to(sp))
				if d > best_d:
					best_d = d
					best = s
			_match.hero_controller.camera_locked = false
			if best != null:
				_match.find_child("IsometricCamera3D").set_position_safely(best.center())
			_battle_focus = best.center() if best != null else Vector3.ZERO
		"battle_close":
			var cam = _match.find_child("IsometricCamera3D")
			cam.set_size_safely(13.0)
			cam.set_position_safely(_battle_focus)
		"hero_close":
			var cam = _match.find_child("IsometricCamera3D")
			cam.set_size_safely(10.0)
			cam.set_position_safely(me.hero.global_position)
		"mordor", "rohan":
			var slot = 1 if kind == "mordor" else 2
			var cam = _match.find_child("IsometricCamera3D")
			cam.set_size_safely(24.0)
			cam.set_position_safely(MapGen.spawn_points()[slot])
			_match.fog_of_war.reveal()
			_match.find_child("UnitVisibilityHandler").visible = false  # show enemy buildings too
