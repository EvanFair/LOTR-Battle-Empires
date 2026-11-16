extends Node
## M5 visual check: hordes in several formations with the selection panel. Needs a display:
## xvfb-run godot --rendering-driver opengl3 --resolution 1600x900 --path . res://tests/auto/ArmyShot.tscn -- --out=/tmp/army

const LoaderScript = preload("res://source/lotr/menu/MatchLoader.gd")
var out = "/tmp/army"
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
	for i in range(3):
		Network.slots[i].faction = "rohan"
		Network.slots[i].hero = Network.faction_heroes("rohan")[i % 3]
	var loader = LoaderScript.new()
	loader.settings = {"slots": Network.slots.duplicate(true), "seed": 777}
	get_tree().root.add_child.call_deferred(loader)
	_run()


func _squad(p, cls, pos):
	var st = GameData.troop_stats(p.faction, cls, p.upgrades)
	var units = []
	for i in range(st.squad_size):
		units.append(_m.spawn_unit({"kind": "troop", "faction": p.faction, "class": cls, "upgrades": {}}, pos + Vector3((i % 4) - 1.5, 0, int(i / 4)) * 1.1, p))
	var sq = _m.make_squadron(p, cls, units, pos)
	sq.reinforceable = true
	return sq


func _run():
	while _m == null or not _m.started:
		await get_tree().process_frame
		_m = get_tree().get_first_node_in_group("lotr_match")
	_m.fog_of_war.visible = false
	_m.find_child("FogOfWar").find_child("ScreenOverlay").visible = false
	for n in _m.get_children():
		if n.name.begins_with("Bot"):
			n.set_physics_process(false)
	var me = _m.local_player
	me.set_resources({"supplies": 9000})
	var tc = me.town_centers()[0].global_position
	var center = Vector3(MapGen.SIZE / 2.0, 0, MapGen.SIZE / 2.0)
	var dir = (center - tc).normalized()
	var side = Vector3(-dir.z, 0, dir.x)
	var base = tc + dir * 34.0
	var rows = [["infantry", "line"], ["infantry", "shield_wall"], ["infantry", "wedge"], ["infantry", "pike_wall"], ["archer", "spread"], ["rider", "charge"]]
	var squads = []
	for i in range(rows.size()):
		var sq = _squad(me, rows[i][0], base + side * (i - 2.5) * 7.0)
		sq.set_formation(rows[i][1])
		squads.append(sq)
	squads[1].add_xp(150)  # rank 2: banner
	squads[2].add_xp(400)  # rank 3
	await _wait_game(1.0)
	for sq in squads:
		sq.order_defend(sq.center() + dir * 14.0)
	await _wait_game(9.0)
	var hc = _m.hero_controller
	hc.camera_locked = false
	var cam = _m.find_child("IsometricCamera3D")
	cam.set_size_safely(30.0)
	cam.set_position_safely(base + dir * 8.0)
	hc.set_selection([squads[1].squad_id])
	await _shot("single")
	hc.set_selection([squads[0].squad_id, squads[1].squad_id, squads[2].squad_id, squads[5].squad_id])
	await _shot("multi")
	cam.set_size_safely(14.0)
	cam.set_position_safely(squads[1].center())
	hc.set_selection([squads[2].squad_id])
	await _shot("closeup")
	hc.set_selection([], me.town_centers()[0])
	await _shot("building")
	get_tree().quit()


func _wait_game(seconds):
	var until = GameData.now() + seconds
	while GameData.now() < until:
		await get_tree().process_frame


func _shot(name):
	for i in range(10):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
