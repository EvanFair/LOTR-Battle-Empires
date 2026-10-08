extends Node
## Local player input. Turns mouse and keyboard into Commands; never changes game state itself.
## See docs/CONTROLS.md for why the scheme looks like this.
##   Right-click ground / enemy ... move / attack (green / red marker)
##   A then left-click ............ attack-move (fight anything met on the way)
##   S / H ........................ stop / hold position
##   Q W E R ...................... abilities: hold to see range and aim, release to cast
##   Tab .......................... cycle squadrons within command range
##   1 2 3 4 ...................... squadron: Attack (click enemy) / Defend (click point) / Hold / Return
##   B ............................ in base: base panel; outside: Recall (6s channel)
##   Alt + left-click ............. ping for your team (Alt+Shift: danger)
##   Left-click house/villager .... resource bubbles
##   Y / Space .................... camera lock toggle / snap to hero

signal selected_squad_changed(squad_id)
signal mode_changed(mode)

const UNIT_LAYER = 2

var camera_locked = true
var selected_squad = 0
var mode = ""  # "", "squad_attack", "squad_defend", "place", "attack_move"
var placing_building = ""

var indicators = null
var aiming = ""  # ability key being aimed (held)

var _match = null
var _camera = null
var _ghost = null

const IndicatorsScript = preload("res://source/lotr/hud/Indicators.gd")


func _ready():
	_match = get_parent()
	_camera = _match.find_child("IsometricCamera3D")
	MatchSignals.terrain_targeted.connect(_on_minimap_move)
	indicators = IndicatorsScript.new()
	indicators.name = "Indicators"
	_match.add_child.call_deferred(indicators)


func local_player():
	return _match.local_player


func hero():
	var p = local_player()
	return p.hero if p != null and p.hero != null and is_instance_valid(p.hero) else null


func _submit(cmd: Dictionary):
	cmd["player"] = local_player().slot_index
	CommandBus.submit(cmd)


# --- camera -----------------------------------------------------------------------------------
func _process(_delta):
	var h = hero()
	if camera_locked and h != null and h.is_alive():
		_camera.set_position_safely(h.global_position)
	if mode == "place" and _ghost != null:
		var point = _mouse_ground()
		if point != null:
			_ghost.global_position = point
	if selected_squad != 0 and _squad_summary(selected_squad).is_empty():
		_set_selected_squad(0)
	_update_indicators(h)


func _update_indicators(h):
	if indicators == null or not indicators.is_inside_tree():
		return
	var alive = h != null and h.is_alive()
	if alive and aiming != "" and h.ability(aiming) != null:
		indicators.show_aim(h.global_position, HeroAbilities.aim(h.ability(aiming)), _mouse_ground())
	elif alive and mode == "attack_move":
		indicators.show_aim(h.global_position, {"mode": "self", "radius": h.attack_range + 0.5}, null)
	else:
		indicators.hide_aim()
	if alive and (selected_squad != 0 or mode.begins_with("squad")):
		indicators.show_command_ring(h.global_position)
	else:
		indicators.hide_command_ring()
	if alive and h.recall_until > 0.0:
		indicators.show_recall(h.global_position, h.recall_left() / h.RECALL_TIME)
	else:
		indicators.hide_recall()


func set_camera_locked(value: bool):
	camera_locked = value


# --- input ------------------------------------------------------------------------------------
func _unhandled_input(event):
	if _match.ended or local_player() == null:
		return
	if event is InputEventKey and not event.pressed and aiming != "" and mode != "cast":
		if OS.get_keycode_string(event.physical_keycode) == aiming:
			var key = aiming
			aiming = ""
			_cast(key)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click()


func _handle_key(event: InputEventKey):
	var key = event.physical_keycode
	match key:
		KEY_Q, KEY_W, KEY_E, KEY_R:
			if event.ctrl_pressed:
				learn_ability(OS.get_keycode_string(key))
			else:
				_start_aim(OS.get_keycode_string(key))
		KEY_5, KEY_6, KEY_7, KEY_8:
			use_item(key - KEY_5)
		KEY_A:
			if hero() != null and hero().is_alive():
				_start_mode("attack_move")
		KEY_H:
			_submit({"type": "hero_hold"})
		KEY_TAB:
			_cycle_squad()
		KEY_1:
			_start_mode("squad_attack")
		KEY_2:
			_start_mode("squad_defend")
		KEY_3:
			_squad_order("hold")
		KEY_4:
			_squad_order("return")
		KEY_Y:
			camera_locked = not camera_locked
		KEY_SPACE:
			camera_locked = true
		KEY_S:
			_submit({"type": "hero_stop"})
		KEY_B:
			if _match.hud.in_base() or _match.hud.base_panel_open():
				_match.hud.toggle_build_menu()
			else:
				_submit({"type": "recall"})
		KEY_ESCAPE:
			if aiming != "":
				aiming = ""
				if mode == "cast":
					cancel_mode()
			elif mode == "":
				return  # let the match menu have it
			else:
				cancel_mode()
		_:
			return
	get_viewport().set_input_as_handled()


func _handle_right_click():
	if aiming != "":
		aiming = ""  # right-click cancels an aimed ability (MOBA convention)
		if mode == "cast":
			cancel_mode()
		return
	if mode != "":
		cancel_mode()
		return
	var unit = _unit_under_mouse()
	var h = hero()
	if unit != null and h != null and h.is_enemy_of(unit):
		_submit({"type": "hero_attack", "target": unit.net_id})
		_flash(unit)
		indicators.attack_marker(unit)
		return
	var point = _mouse_ground()
	if point != null:
		_submit({"type": "hero_move", "pos": point})
		indicators.set_attack_target(null)
		indicators.move_marker(point)


func _handle_left_click():
	if Input.is_key_pressed(KEY_ALT):
		var p = _mouse_ground()
		if p != null:
			_submit({"type": "ping", "pos": p, "danger": Input.is_key_pressed(KEY_SHIFT)})
		get_viewport().set_input_as_handled()
		return
	match mode:
		"cast":
			var key = aiming
			aiming = ""
			cancel_mode()
			if key != "":
				_cast(key)
			get_viewport().set_input_as_handled()
		"attack_move":
			var unit = _unit_under_mouse()
			if unit != null and hero() != null and hero().is_enemy_of(unit):
				_submit({"type": "hero_attack", "target": unit.net_id})
				indicators.attack_marker(unit)
			else:
				var point = _mouse_ground()
				if point != null:
					_submit({"type": "hero_attack_move", "pos": point})
					indicators.set_attack_target(null)
					indicators._shrinking_ring(point, indicators.ATTACK_COLOR, 1.1, 0.6)
			cancel_mode()
			get_viewport().set_input_as_handled()
		"squad_attack":
			var unit = _unit_under_mouse()
			if unit != null and hero() != null and hero().is_enemy_of(unit):
				_squad_order("attack", {"target": unit.net_id})
				_flash(unit)
			cancel_mode()
		"squad_defend":
			var point = _mouse_ground()
			if point != null:
				_squad_order("defend", {"pos": point})
				_match.hud.ping(point)
			cancel_mode()
		"place":
			var point = _mouse_ground()
			if point != null:
				_submit({"type": "build", "building": placing_building, "pos": point})
			if not Input.is_key_pressed(KEY_SHIFT):
				cancel_mode()
		_:
			var unit = _unit_under_mouse()
			if unit == null or unit.player != local_player():
				return
			var house = null
			if unit.get("building_key") == "village_house":
				house = unit
			elif unit.get("unit_kind") == "villager" and unit.house != null and is_instance_valid(unit.house):
				house = unit.house
			if house != null:
				_match.hud.show_bubbles(house)
			elif unit.get("unit_kind") == "building":
				_match.hud.show_building(unit)


func _on_minimap_move(point):
	# right-click on the minimap moves the hero there
	if point == null or local_player() == null or _match.ended:
		return
	_submit({"type": "hero_move", "pos": point})
	indicators.move_marker(point)


# --- abilities --------------------------------------------------------------------------------
func _start_aim(key: String):
	var h = hero()
	if h == null:
		return
	if h.ability(key) == null:
		_match.toast.emit("%s has no %s ability yet" % [h.display_name, key])
		return
	if mode != "":
		cancel_mode()
	aiming = key  # indicator shows while the key is held; releasing casts


func _cast(key: String):
	var h = hero()
	if h == null:
		return
	var ability = h.ability(key)
	if ability == null:
		_match.toast.emit("%s has no %s ability yet" % [h.display_name, key])
		return
	var cmd = {"type": "cast", "key": key}
	var point = _mouse_ground()
	if point != null:
		cmd["pos"] = point
	var unit = _unit_under_mouse()
	if HeroAbilities.aim(ability).mode == "unit":
		if unit == null or not h.is_enemy_of(unit):
			unit = _closest_enemy_to_cursor(point, 3.0)
		if unit == null:
			_match.toast.emit("Hover over an enemy to use %s" % ability.name)
			return
		cmd["target"] = unit.net_id
		indicators.attack_marker(unit)
	_submit(cmd)


func arm_ability(key: String):
	_start_aim(key)
	if aiming == key:
		mode = "cast"
		mode_changed.emit(mode)


func use_item(slot: int):
	var h = hero()
	if h == null or slot >= h.items.size():
		return
	_submit({"type": "use_item", "slot": slot})


func learn_ability(key: String):
	_submit({"type": "learn", "key": key})


func _closest_enemy_to_cursor(point, radius):
	if point == null or hero() == null:
		return null
	var best = null
	var best_d = radius
	for u in get_tree().get_nodes_in_group("units"):
		if u.visible and u.is_alive() and hero().is_enemy_of(u):
			var d = u.global_position.distance_to(point)
			if d < best_d:
				best_d = d
				best = u
	return best


# --- squadrons --------------------------------------------------------------------------------
func squads_in_range() -> Array:
	var h = hero()
	if h == null or not h.is_alive():
		return []
	var mine = []
	for s in _match.replicator.squad_summaries():
		if s.player != local_player().slot_index:
			continue
		var d = Vector2(s.x - h.global_position.x, s.z - h.global_position.z).length()
		if d <= GameData.COMMAND_RANGE:
			mine.append(s)
	mine.sort_custom(func(a, b): return a.id < b.id)
	return mine


func _squad_summary(squad_id) -> Dictionary:
	for s in squads_in_range():
		if s.id == squad_id:
			return s
	return {}


func _cycle_squad():
	var list = squads_in_range()
	if list.is_empty():
		_set_selected_squad(0)
		_match.toast.emit("No squadron nearby. Move your hero closer to one.")
		return
	var idx = -1
	for i in range(list.size()):
		if list[i].id == selected_squad:
			idx = i
	_set_selected_squad(list[(idx + 1) % list.size()].id)


func select_squad(squad_id):
	_set_selected_squad(squad_id)


func _set_selected_squad(squad_id):
	if selected_squad == squad_id:
		return
	selected_squad = squad_id
	selected_squad_changed.emit(squad_id)


func _ensure_squad():
	if selected_squad == 0 or _squad_summary(selected_squad).is_empty():
		var list = squads_in_range()
		if list.is_empty():
			_match.toast.emit("No squadron nearby. Move your hero closer to one.")
			return false
		_set_selected_squad(list[0].id)
	return true


func _squad_order(order: String, extra = {}):
	if not _ensure_squad():
		return
	var cmd = {"type": "squad_order", "squad": selected_squad, "order": order}
	cmd.merge(extra)
	_submit(cmd)


func _start_mode(new_mode):
	if new_mode.begins_with("squad") and not _ensure_squad():
		return
	mode = new_mode
	mode_changed.emit(mode)


# --- building placement ---------------------------------------------------------------------
func start_placing(building_key: String):
	cancel_mode()
	placing_building = building_key
	mode = "place"
	var template = UnitFactory.create(
		{"kind": "building", "building": building_key, "faction": local_player().faction}
	)
	_ghost = template.find_child("Geometry")
	template.remove_child(_ghost)
	template.free()
	for node in _ghost.find_children("*", "MeshInstance3D", true, false):
		node.transparency = 0.55
	_match.add_child(_ghost)
	mode_changed.emit(mode)


func cancel_mode():
	mode = ""
	placing_building = ""
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	mode_changed.emit(mode)


# --- picking ----------------------------------------------------------------------------------
func _mouse_ground():
	var mouse = get_viewport().get_mouse_position()
	var point = _camera.get_ray_intersection(mouse)
	if point == null:
		return null
	point.x = clamp(point.x, 0.5, MapGen.SIZE - 0.5)
	point.z = clamp(point.z, 0.5, MapGen.SIZE - 0.5)
	return point


func _unit_under_mouse():
	var mouse = get_viewport().get_mouse_position()
	var origin = _camera.project_ray_origin(mouse)
	var query = PhysicsRayQueryParameters3D.create(
		origin, origin + _camera.project_ray_normal(mouse) * 500.0, UNIT_LAYER
	)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit = _camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var node = hit.collider
	if node.has_method("is_alive") and node.is_alive() and node.visible:
		return node
	return null


func _flash(unit):
	var t = unit.find_child("Targetability")
	if t != null and t.has_method("animate"):
		t.animate()
