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
	[150.0, "04_battle", "battle"],
]
var _index = 0
var _busy = false


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
			var best = null
			for s in get_tree().get_nodes_in_group("squadrons"):
				if best == null or s.state == s.State.ATTACK:
					best = s
			_match.hero_controller.camera_locked = false
			if best != null:
				_match.find_child("IsometricCamera3D").set_position_safely(best.center())
