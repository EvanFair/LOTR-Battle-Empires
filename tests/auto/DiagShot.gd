extends Node
## Diagnostic renders of one spot with fog / shadows toggled. Writes PNGs to --out.

const LoaderScript = preload("res://source/lotr/menu/MatchLoader.gd")
var out = "/tmp/diag"
var _m = null


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
	while _m == null or not _m.started:
		await get_tree().process_frame
		_m = get_tree().get_first_node_in_group("lotr_match")
	await get_tree().create_timer(1.0).timeout
	_m.hero_controller.camera_locked = false
	var cam = _m.find_child("IsometricCamera3D")
	cam.set_size_safely(24.0)
	cam.set_position_safely(MapGen.spawn_points()[2])
	await _shot("a_normal")
	var cv = _m.fog_of_war.find_child("CombinedViewport")
	cv.get_texture().get_image().save_png(out + "/fog_texture.png")
	var fv = _m.fog_of_war.find_child("FogViewport")
	fv.get_texture().get_image().save_png(out + "/fog_inner.png")
	print("combined size ", cv.size, " inner ", fv.size, " revealed units ", get_tree().get_nodes_in_group("revealed_units").size())
	_m.fog_of_war.visible = false
	_m.find_child("FogOfWar").find_child("ScreenOverlay").visible = false
	await _shot("b_no_fog")
	_m.find_child("DirectionalLight3D").shadow_enabled = false
	await _shot("c_no_fog_no_shadow")
	print("cam pos ", cam.global_position, " size ", cam.size, " far ", cam.far, " near ", cam.near)
	get_tree().quit()


func _shot(name):
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)
