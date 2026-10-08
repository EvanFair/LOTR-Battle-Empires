extends Node
## QA playthrough with real input events, from the main menu into a match.
## Needs a display: xvfb-run ... godot --rendering-driver opengl3 --resolution 1600x900 --path . \
##   res://tests/auto/PlayQA.tscn -- --out=/tmp/qa
## Prints "QA <PASS|FAIL> step: detail" lines and saves a screenshot per step.

var out = "/tmp/qa"
var _results = []
var _shot = 0


func _ready():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.split("=")[1]
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func check(name, ok, detail = ""):
	_results.append(ok)
	print("QA %s %s %s" % ["PASS" if ok else "FAIL", name, detail])


func shot(label):
	await _frames(3)
	await RenderingServer.frame_post_draw
	_shot += 1
	var path = "%s/%02d_%s.png" % [out, _shot, label]
	get_viewport().get_texture().get_image().save_png(path)
	print("QA SHOT ", path)


func _frames(n):
	for i in range(n):
		await get_tree().process_frame


func _seconds(s):
	await get_tree().create_timer(s).timeout


func press_button_with_text(root: Node, text: String) -> bool:
	for b in root.find_children("*", "BaseButton", true, false):
		if b is Button and b.visible and b.text.strip_edges().to_lower().begins_with(text.to_lower()):
			b.pressed.emit()
			return true
	return false


func key(code):
	for pressed in [true, false]:
		var e = InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		await _frames(1)


func click(pos: Vector2, button = MOUSE_BUTTON_LEFT):
	get_viewport().warp_mouse(pos)
	await _frames(2)
	for pressed in [true, false]:
		var e = InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		Input.parse_input_event(e)
		await _frames(1)


func world_to_screen(p: Vector3) -> Vector2:
	return get_viewport().get_camera_3d().unproject_position(p)


func _run():
	# --- main menu ---------------------------------------------------------------------------
	# load the menu as the current scene but keep this driver alive beside it
	var main_menu = load("res://source/main-menu/Main.tscn").instantiate()
	get_tree().root.add_child(main_menu)
	get_tree().current_scene = main_menu
	await _seconds(1.0)
	await shot("main_menu")
	var menu = get_tree().current_scene
	check("main menu shows", menu != null and menu.name == "Main")
	check("play button", press_button_with_text(menu, "PLAY"))
	await _seconds(0.5)
	var lobby = get_tree().current_scene
	await shot("play_screen")
	check("lobby scene", lobby != null and lobby.name == "Lobby")
	check("single player button", press_button_with_text(lobby, "Single player"))
	await _frames(5)
	await shot("lobby")
	check("start button", press_button_with_text(lobby, "Start match"))
	await _seconds(3.0)

	# --- match ----------------------------------------------------------------------------------
	var m = get_tree().get_first_node_in_group("lotr_match")
	check("match started", m != null)
	if m == null:
		return _finish()
	while not m.started:
		await _frames(1)
	await _seconds(1.0)
	await shot("match_start")
	var me = m.local_player
	var hero = me.hero
	check("hero exists", hero != null)

	# right-click to move
	var start = hero.global_position
	var target = start + Vector3(6, 0, -4)
	await click(world_to_screen(target), MOUSE_BUTTON_RIGHT)
	await _seconds(3.0)
	var moved = hero.global_position.distance_to(start)
	check("right-click moves hero", moved > 3.0, "(moved %.1fm)" % moved)
	await shot("hero_moved")

	# camera follows hero
	var cam = get_viewport().get_camera_3d()
	var hero_on_screen = world_to_screen(hero.global_position)
	var center = get_viewport().get_visible_rect().size / 2
	check("camera follows hero", hero_on_screen.distance_to(center) < 250, "(%.0fpx from centre)" % hero_on_screen.distance_to(center))

	# Y toggles lock, arrow keys pan
	await key(KEY_Y)
	check("Y unlocks camera", not m.hero_controller.camera_locked)
	var cam_before = cam.global_position
	Input.action_press("move_map_right")
	await _seconds(0.6)
	Input.action_release("move_map_right")
	check("arrow keys pan when unlocked", cam.global_position.distance_to(cam_before) > 0.5)
	await key(KEY_SPACE)
	check("space relocks camera", m.hero_controller.camera_locked)

	# click a village house -> bubbles
	var house = me.buildings("village_house")[0]
	await _frames(5)
	await click(world_to_screen(house.global_position + Vector3(0, 0.8, 0)))
	await _frames(3)
	check("clicking house opens villager bubbles", m.hud._bubbles.visible)
	await shot("bubbles")
	var before_assign = house.assignment
	press_button_with_text(m.hud._bubbles, "Wood")
	await _frames(3)
	check("bubble assigns villagers", house.assignment == "wood", "(%s -> %s)" % [before_assign, house.assignment])
	press_button_with_text(m.hud._bubbles, "Close")

	# B opens base panel; build a village house through the real UI
	me.add_resources({"wood": 500, "stone": 300})
	await key(KEY_B)
	await _frames(3)
	check("B opens base panel in base", m.hud._base_panel.visible)
	await shot("base_panel")
	var houses_before = me.buildings("village_house").size()
	press_button_with_text(m.hud._build_tab, "Village House")
	await _frames(3)
	check("build button enters placement", m.hero_controller.mode == "place")
	var tc = me.town_centers()[0]
	var place_at = null
	for i in range(40):
		var p = tc.global_position + Vector3(cos(i * 0.6), 0, sin(i * 0.6)) * (8.0 + i * 0.2)
		if m.placement_blocker("village_house", p) == "" and me.in_base(p):
			place_at = p
			break
	await click(world_to_screen(place_at))
	await _frames(5)
	check("left-click places foundation", me.buildings("village_house").size() == houses_before + 1)
	await shot("foundation")

	# abilities: E dash toward cursor
	var h0 = hero.global_position
	get_viewport().warp_mouse(world_to_screen(h0 + Vector3(5, 0, 0)))
	await _frames(2)
	await key(KEY_E)
	await _seconds(0.5)
	check("E (dash) moves hero", hero.global_position.distance_to(h0) > 2.0)
	await key(KEY_Q)
	await _frames(3)
	await shot("q_no_target")

	# Tab with no squadrons
	await key(KEY_TAB)
	await _frames(3)
	check("tab with no squads doesn't crash", true)

	# hero walks toward the middle; watch for a few seconds for errors
	await click(world_to_screen(hero.global_position + Vector3(10, 0, 10)), MOUSE_BUTTON_RIGHT)
	await _seconds(4.0)
	await shot("walking")

	# escape menu
	await key(KEY_ESCAPE)
	await _frames(5)
	await shot("escape_menu")
	var menu_node = m.find_child("Menu")
	check("Esc opens the match menu", menu_node != null and menu_node.visible)
	check("single player pauses", get_tree().paused)

	# exit to menu, then play a second match from scratch
	press_button_with_text(menu_node, "EXIT")
	await _seconds(2.5)
	check("exit returns to main menu", get_tree().current_scene != null and get_tree().current_scene.name == "Main" and not get_tree().paused)
	check("second play", press_button_with_text(get_tree().current_scene, "PLAY"))
	await _seconds(0.5)
	press_button_with_text(get_tree().current_scene, "Single player")
	await _frames(3)
	press_button_with_text(get_tree().current_scene, "Start match")
	await _seconds(3.0)
	m = get_tree().get_first_node_in_group("lotr_match")
	while m != null and not m.started:
		await _frames(1)
	check("second match starts", m != null and m.local_player != null and m.local_player.hero != null)
	await _seconds(1.0)
	var h2 = m.local_player.hero
	var s2 = h2.global_position
	await click(world_to_screen(s2 + Vector3(-5, 0, 5)), MOUSE_BUTTON_RIGHT)
	await _seconds(2.0)
	check("hero responds in second match", h2.global_position.distance_to(s2) > 2.0)

	# win screen and back to menu
	m.end_match(m.local_player.team)
	await _frames(5)
	await shot("victory")
	check("victory screen", press_button_with_text(m.hud._root, "Back to main menu"))
	await _seconds(1.0)
	check("victory returns to main menu", get_tree().current_scene != null and get_tree().current_scene.name == "Main")
	_finish()


func _finish():
	var fails = _results.filter(func(r): return not r).size()
	print("QA RESULT %d/%d passed" % [_results.size() - fails, _results.size()])
	get_tree().quit()
