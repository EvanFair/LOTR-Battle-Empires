extends Node
## HUD visual check (M3): a 3v3 match, then the champion panel in different states (cooldowns,
## buffs, skill points, tooltips, death, recall), over-head bars and damage numbers.
## xvfb-run godot --rendering-driver opengl3 --resolution 1600x900 --path . res://tests/auto/HudShot.tscn -- --out=/tmp/hud

const LoaderScript = preload("res://source/lotr/menu/MatchLoader.gd")
const Tooltips = preload("res://source/lotr/hud/widgets/Tooltips.gd")
var out = "/tmp/hud"
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
	Engine.time_scale = 5.0
	Engine.max_physics_steps_per_frame = 40
	await _wait_game(40.0)
	Engine.time_scale = 1.0
	var h = me.hero
	var cam = _m.find_child("IsometricCamera3D")
	cam.set_size_safely(16.0)
	# a few levels, items, one learned rank per ability
	h.add_xp(560)
	h.ranks = {"Q": 2, "W": 1, "E": 1}
	h.items = [{"key": "elven_blade", "ready_at": 0.0}, {"key": "horn_mark", "ready_at": GameData.now() + 22.0}, {"key": "lembas", "ready_at": 0.0}]
	h.recompute_stats()
	h.hp = int(h.hp_max * 0.62)
	h.mana = h.mana_max * 0.35
	h.cooldowns["Q"] = GameData.now() + 5.0
	h.cooldowns["W"] = GameData.now() + 14.0
	h.apply_buff("speed", 1.3, 30.0)
	h.apply_buff("damage", 0.8, 30.0)
	h.apply_buff("armor", 0.2, 30.0)
	# put an ally and an enemy hero next to ours
	var ally = null
	var enemy = null
	for u in get_tree().get_nodes_in_group("heroes"):
		if u == h:
			continue
		if Teams.is_ally(u.player, me) and ally == null:
			ally = u
		elif Teams.is_enemy(me, u.player) and enemy == null:
			enemy = u
	ally.global_position = h.global_position + Vector3(4, 0, 4)
	enemy.global_position = h.global_position + Vector3(-4, 0, 3)
	enemy.hp = int(enemy.hp_max * 0.4)
	enemy.stun(60.0)
	ally.hp = int(ally.hp_max * 0.8)
	cam.set_position_safely(h.global_position)
	for i in range(4):
		_m.fx("dmg", enemy.global_position, Vector3(87 + i * 11, me.slot_index, 2))
		_m.fx("dmg", h.global_position, Vector3(34 + i * 7, 2, me.slot_index))
	_m.fx("loot", enemy.global_position, Vector3(24, me.slot_index, 0))
	await _shot("hud_a")
	# a real hover tooltip over the Q slot
	var q = _m.hud._champion.slots["Q"]
	get_viewport().warp_mouse(q.get_global_transform_with_canvas() * (q.size / 2.0))
	for i in range(30):
		await get_tree().process_frame
	await _shot("hud_hover")
	get_viewport().warp_mouse(Vector2(900, 100))
	# tooltips as the HUD would show them
	var root = _m.hud._root
	var tips = []
	tips.append(Tooltips.ability(h, h.ability("Q")))
	tips.append(Tooltips.ability(h, h.ability("R")))
	tips.append(Tooltips.item("horn_mark", 1))
	var x = 330.0
	for t in tips:
		root.add_child(t)
		t.position = Vector2(x, 380)
		x += 380
	await _shot("hud_tips")
	for t in tips:
		t.queue_free()
	h.skill_points()
	h.recall_until = GameData.now() + 3.4
	await _shot("hud_recall")
	h.recall_until = 0.0
	h.set_dead(true)
	h.respawn_at = GameData.now() + 17.0
	await _shot("hud_dead")
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
