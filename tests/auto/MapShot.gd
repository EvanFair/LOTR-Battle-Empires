extends Node
## Renders the whole map from high above (fog off) to review the lane layout.
## Run: godot --rendering-driver opengl3 --resolution 1400x1400 --path . res://tests/auto/MapShot.tscn -- --out=/tmp/map

const LoaderScript = preload("res://source/lotr/menu/MatchLoader.gd")
var out = "/tmp/map"


func _ready():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.split("=")[1]
	DirAccess.make_dir_recursive_absolute(out)
	Network.leave()
	Network.reset_slots()
	for i in range(1, 4):
		Network.slots[i].kind = "bot"
	var loader = LoaderScript.new()
	loader.settings = {"slots": Network.slots.duplicate(true), "seed": 4242}
	get_tree().root.add_child.call_deferred(loader)
	_run()


func _run():
	var m = null
	while m == null or not m.started:
		await get_tree().process_frame
		m = get_tree().get_first_node_in_group("lotr_match")
	m.fog_of_war.visible = false
	m.find_child("FogOfWar").find_child("ScreenOverlay").visible = false
	m.hero_controller.camera_locked = false
	var cam = Camera3D.new()
	m.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = MapGen.SIZE + 10.0
	cam.global_position = Vector3(MapGen.SIZE / 2.0, 120, MapGen.SIZE / 2.0)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.far = 400
	cam.make_current()
	for i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/map_top.png")
	get_tree().quit()
