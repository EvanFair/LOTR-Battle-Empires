extends Node
## Renders a line-up of every hero, each faction's heavy and special troops, and the wild
## creatures, for visual review. Needs a display (xvfb-run ... --rendering-driver opengl3).
## Run: godot --rendering-driver opengl3 --resolution 1600x900 --path . res://tests/auto/Showcase.tscn -- --out=/tmp/show

const LoaderScript = preload("res://source/lotr/menu/MatchLoader.gd")
var out = "/tmp/show"
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
	await get_tree().create_timer(0.5).timeout
	for b in _m.get_children():
		if b.name.begins_with("Bot"):
			b.queue_free()  # keep the world still
	_m.fog_of_war.visible = false
	_m.find_child("FogOfWar").find_child("ScreenOverlay").visible = false
	_m.hero_controller.camera_locked = false
	var me = _m.local_player
	var cam = _m.find_child("IsometricCamera3D")
	# heroes, faction by faction
	var origin = Vector3(52, 0, 40)
	var x = 0
	for faction in GameData.PLAYABLE_FACTIONS:
		for key in GameData.FACTIONS[faction].heroes:
			var h = _m.spawn_unit({"kind": "hero", "hero": key}, origin + Vector3(x * 2.4, 0, 0), me)
			h.rotation.y = PI
			x += 1
	cam.set_size_safely(16.0)
	cam.set_position_safely(origin + Vector3(6.5, 0, 0))
	await _shot("heroes_left")
	cam.set_position_safely(origin + Vector3(20.0, 0, 0))
	await _shot("heroes_right")
	# heavy and special troops
	var row = Vector3(52, 0, 58)
	x = 0
	for faction in GameData.PLAYABLE_FACTIONS:
		for unit_class in ["heavy", "special"]:
			var u = _m.spawn_unit({"kind": "troop", "faction": faction, "class": unit_class}, row + Vector3(x * 3.6, 0, 0), me)
			u.auto_acquire = false
			x += 1
	cam.set_size_safely(18.0)
	cam.set_position_safely(row + Vector3(7.0, 0, 0))
	await _shot("troops_left")
	cam.set_position_safely(row + Vector3(21.0, 0, 0))
	await _shot("troops_right")
	# the wild: a spider camp and the Cave Troll
	var spider_camp = null
	for c in _m.camps:
		if c.key == "spiders":
			spider_camp = c
			break
	cam.set_size_safely(14.0)
	cam.set_position_safely(spider_camp.pos)
	await _shot("spider_camp")
	cam.set_position_safely(Vector3(MapGen.SIZE / 2.0, 0, MapGen.SIZE / 2.0))
	await _shot("cave_troll")
	# new buildings
	me.age = 3
	var tc = me.town_centers()[0]
	var spots = [Vector3(10, 0, 0), Vector3(-2, 0, 10), Vector3(8, 0, 10)]
	var keys = ["blacksmith", "siege_works", "special_building"]
	for i in range(3):
		_m.spawn_building(me, keys[i], tc.global_position + spots[i], false)
	cam.set_size_safely(22.0)
	cam.set_position_safely(tc.global_position + Vector3(5, 0, 5))
	await _shot("buildings")
	get_tree().quit()


func _shot(name):
	for i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)
