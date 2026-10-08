extends CanvasLayer
## The whole in-match interface, built in code:
##  top bar (stockpile, Age, houses, clock), hero panel (HP/mana/XP, QWER), squadron panel,
##  base panel (Build / Military / Age), villager bubbles, building info, toasts, end screen,
##  plus 3D effects (arrows, hits, pings, cast rings).

const PANEL_BG = Color(0.08, 0.07, 0.06, 0.82)
const ACCENT = Color("e8c24a")
const RES_ICONS = {"food": "Food", "wood": "Wood", "stone": "Stone", "iron": "Iron", "gold": "Gold"}
const ASSIGN_LABELS = {
	"food": "Food", "wood": "Wood", "stone": "Stone", "iron": "Iron", "home": "Return home",
}
const TOAST_TIME = 4.0
const SQUAD_ORDER_BUTTONS = [
	["1 Attack", "squad_attack"], ["2 Defend", "squad_defend"], ["3 Hold", "hold"],
	["4 Return", "return"],
]

var _match = null
var _root = null
var _top_label = null
var _hero_name = null
var _hp_bar = null
var _mana_bar = null
var _xp_bar = null
var _ability_buttons = {}
var _respawn_label = null
var _squad_box = null
var _squad_list = null
var _squad_detail = null
var _squad_hint = null
var _mode_label = null
var _base_panel = null
var _build_tab = null
var _military_tab = null
var _age_tab = null
var _base_hint = null
var _bubbles = null
var _bubble_house = null
var _info_panel = null
var _info_building = null
var _toasts = null
var _end_screen = null
var _start_time = 0.0
var _military_rows = {}


func _ready():
	_match = get_parent()
	layer = 5
	_start_time = GameData.now()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_top_bar()
	_build_toasts()
	if _match.local_player != null:
		_build_hero_panel()
		_build_squad_panel()
		_build_base_panel()
		_build_bubbles()
		_build_info_panel()
		_build_mode_label()
	_match.toast.connect(show_toast)
	await get_tree().process_frame
	if _match.hero_controller != null:
		_match.hero_controller.selected_squad_changed.connect(func(_id): _refresh_squads())
		_match.hero_controller.mode_changed.connect(_on_mode_changed)


func _process(_delta):
	_refresh_top_bar()
	if _match.local_player == null:
		return
	_refresh_hero()
	_refresh_squads()
	_refresh_base_panel()
	_refresh_bubbles()
	_refresh_info()


# --- helpers ------------------------------------------------------------------------------------
func _panel(parent, anchors: int, min_size = Vector2.ZERO) -> PanelContainer:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	style.border_color = Color(ACCENT, 0.35)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = min_size
	parent.add_child(panel)
	panel.set_anchors_and_offsets_preset(anchors, Control.PRESET_MODE_MINSIZE, 8)
	# grow away from the screen edge the panel is anchored to
	if anchors in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM, Control.PRESET_BOTTOM_WIDE]:
		panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	if anchors in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_RIGHT_WIDE, Control.PRESET_CENTER_RIGHT]:
		panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	if anchors in [Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER]:
		panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	if anchors == Control.PRESET_CENTER:
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	return panel


func _label(parent, text = "", size = 14, color = Color.WHITE) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent, text, callback: Callable, min_width = 0) -> Button:
	var button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.x = min_width
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _bar(parent, color: Color, height = 12) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, height)
	bar.show_percentage = false
	var fill = StyleBoxFlat.new()
	fill.bg_color = color
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	parent.add_child(bar)
	return bar


func _submit(cmd):
	cmd["player"] = _match.local_player.slot_index
	CommandBus.submit(cmd)


func _hero():
	var p = _match.local_player
	return p.hero if p != null and p.hero != null and is_instance_valid(p.hero) else null


func _in_base():
	var h = _hero()
	return h != null and h.is_alive() and _match.local_player.in_base(h.global_position)


# --- top bar ----------------------------------------------------------------------------------
func _build_top_bar():
	var panel = _panel(_root, Control.PRESET_CENTER_TOP)
	_top_label = _label(panel, "", 16)


func _refresh_top_bar():
	var elapsed = int(GameData.now() - _start_time)
	var clock = "%02d:%02d" % [elapsed / 60, elapsed % 60]
	var p = _match.local_player
	if p == null:
		_top_label.text = "Spectating    " + clock
		return
	var parts = []
	for res in GameData.RESOURCES:
		var income = p.income_per_min.get(res, 0)
		var text = "%s %d" % [RES_ICONS[res], p.get(res)]
		if income > 0:
			text += " (+%d/min)" % income
		parts.append(text)
	var houses = p.buildings("village_house").size()
	parts.append("Houses %d/%d" % [houses, GameData.MAX_HOUSES])
	parts.append("Age: %s" % GameData.AGE_NAMES[p.age])
	parts.append(clock)
	_top_label.text = "    ".join(parts)


# --- hero panel -------------------------------------------------------------------------------
func _build_hero_panel():
	var panel = _panel(_root, Control.PRESET_CENTER_BOTTOM, Vector2(620, 0))
	var box = VBoxContainer.new()
	panel.add_child(box)
	_hero_name = _label(box, "", 16, ACCENT)
	_hp_bar = _bar(box, Color("c0392b"), 14)
	_mana_bar = _bar(box, Color("2e6fd8"), 8)
	_xp_bar = _bar(box, ACCENT, 4)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	for key in ["Q", "W", "E", "R"]:
		var b = _button(row, key, _on_ability_pressed.bind(key), 148)
		b.custom_minimum_size.y = 46
		b.add_theme_font_size_override("font_size", 13)
		b.clip_text = true
		_ability_buttons[key] = b
	_respawn_label = _label(box, "", 18, Color("ff8080"))
	_respawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _on_ability_pressed(key):
	var event = InputEventKey.new()
	event.physical_keycode = OS.find_keycode_from_string(key)
	event.pressed = true
	_match.hero_controller._handle_key(event)


func _refresh_hero():
	var h = _hero()
	if h == null:
		_hero_name.text = "Waiting for your hero..."
		return
	_hero_name.text = "%s - Level %d %s    HP %d/%d    Mana %d/%d" % [
		h.display_name, h.level, GameData.HEROES[h.hero_key].role, max(0, h.hp) if not h.dead else 0,
		h.hp_max, int(h.mana), int(h.mana_max)
	]
	_hp_bar.max_value = h.hp_max
	_hp_bar.value = h.hp if not h.dead else 0
	_hp_bar.tooltip_text = "%d / %d HP" % [h.hp, h.hp_max]
	_mana_bar.max_value = max(1.0, h.mana_max)
	_mana_bar.value = h.mana
	var lvl_xp = GameData.XP_PER_LEVEL[min(h.level - 1, GameData.XP_PER_LEVEL.size() - 1)]
	var next_xp = GameData.XP_PER_LEVEL[min(h.level, GameData.XP_PER_LEVEL.size() - 1)]
	_xp_bar.max_value = max(1, next_xp - lvl_xp)
	_xp_bar.value = h.xp - lvl_xp
	for key in _ability_buttons:
		var b = _ability_buttons[key]
		var a = h.ability(key)
		if a == null:
			b.text = "%s\n-" % key
			b.disabled = true
			b.tooltip_text = "Coming in a later milestone"
			continue
		var cd = h.cooldown_left(key)
		b.disabled = h.dead or cd > 0.0 or h.mana < a.mana
		b.text = "%s %s\n%s" % [key, a.name, ("%ds" % ceili(cd)) if cd > 0 else ("%d mana" % a.mana)]
		b.tooltip_text = "%s: %s" % [a.name, a.kind.replace("_", " ")]
	if h.dead:
		_respawn_label.text = "Respawning in %ds" % ceili(max(0.0, h.respawn_at - GameData.now()))
	else:
		_respawn_label.text = ""


# --- squadrons --------------------------------------------------------------------------------
func _build_squad_panel():
	var panel = _panel(_root, Control.PRESET_BOTTOM_LEFT, Vector2(300, 0))
	panel.offset_bottom = -228  # sits above the minimap and grows upward
	panel.offset_top = -228
	_squad_box = VBoxContainer.new()
	panel.add_child(_squad_box)
	_label(_squad_box, "Squadrons nearby (Tab)", 14, ACCENT)
	_squad_hint = _label(_squad_box, "Move closer to a squadron to command it", 12, Color(1, 1, 1, 0.6))
	_squad_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_squad_list = VBoxContainer.new()
	_squad_box.add_child(_squad_list)
	_squad_detail = HBoxContainer.new()
	_squad_box.add_child(_squad_detail)
	for entry in SQUAD_ORDER_BUTTONS:
		_button(_squad_detail, entry[0], _on_squad_order.bind(entry[1]))


func _on_squad_order(order):
	var hc = _match.hero_controller
	if order in ["squad_attack", "squad_defend"]:
		hc._start_mode(order)
	else:
		hc._squad_order(order)


func _refresh_squads():
	if _squad_list == null or _match.hero_controller == null:
		return
	var minimap = _match.find_child("Minimap")
	if minimap != null:
		var panel = _squad_box.get_parent()
		var bottom = -(minimap.size.y + 18)
		if panel.offset_bottom != bottom:
			panel.offset_bottom = bottom
			panel.offset_top = bottom
	var squads = _match.hero_controller.squads_in_range()
	_squad_hint.visible = squads.is_empty()
	_squad_detail.visible = not squads.is_empty()
	var selected = _match.hero_controller.selected_squad
	var buttons = _squad_list.get_children()
	for i in range(max(buttons.size(), squads.size())):
		if i >= squads.size():
			buttons[i].queue_free()
			continue
		var s = squads[i]
		var b = buttons[i] if i < buttons.size() else _button(_squad_list, "", func(): pass)
		if i >= buttons.size():
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var marker = "> " if s.id == selected else "   "
		b.text = "%s%s x%d  %d%%  %s" % [
			marker, s.name, s.count, int(s.hp * 100), _squad_state_name(s.state)
		]
		for c in b.pressed.get_connections():
			b.pressed.disconnect(c.callable)
		b.pressed.connect(_match.hero_controller.select_squad.bind(s.id))


func _squad_state_name(state):
	return ["Idle", "Marching", "Attacking", "Defending", "Holding", "Returning"][state]


func _build_mode_label():
	_mode_label = _label(_root, "", 18, ACCENT)
	_mode_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_mode_label.offset_top = 140
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _on_mode_changed(mode):
	match mode:
		"squad_attack":
			_mode_label.text = "Left-click an enemy for the squadron to attack (right-click cancels)"
		"squad_defend":
			_mode_label.text = "Left-click the spot to defend (right-click cancels)"
		"place":
			_mode_label.text = "Left-click to place (hold Shift to place more, right-click cancels)"
		_:
			_mode_label.text = ""


# --- base panel -------------------------------------------------------------------------------
func _build_base_panel():
	_base_panel = _panel(_root, Control.PRESET_RIGHT_WIDE, Vector2(330, 0))
	_base_panel.offset_top = 60
	_base_panel.offset_bottom = -60
	var box = VBoxContainer.new()
	_base_panel.add_child(box)
	_label(box, "Base  (B)", 16, ACCENT)
	var tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	_build_tab = _scroll_tab(tabs, "Build")
	_military_tab = _scroll_tab(tabs, "Military")
	_age_tab = _scroll_tab(tabs, "Age")
	for key in GameData.BUILD_MENU:
		var data = GameData.BUILDINGS[key]
		var b = _button(_build_tab, "", _on_build_pressed.bind(key))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.set_meta("key", key)
		b.tooltip_text = "%s\nCost: %s\nBuild time: %ds (your hero must stay nearby)" % [
			data.name, GameData.cost_text(data.cost), int(data.build_time)
		]
	_base_panel.visible = false
	_base_hint = _label(_root, "", 13, Color(1, 1, 1, 0.75))
	_base_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)


func _scroll_tab(tabs, title):
	var scroll = ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box


func toggle_build_menu():
	if _base_panel == null:
		return
	if not _base_panel.visible and not _in_base():
		show_toast("Return to your base to build (Watchtowers can go anywhere: open in base, place anywhere)")
		return
	_base_panel.visible = not _base_panel.visible


func _on_build_pressed(key):
	_match.hero_controller.start_placing(key)


func _refresh_base_panel():
	var in_base = _in_base()
	if _base_panel.visible and not in_base and _match.hero_controller.mode != "place":
		_base_panel.visible = false
	_base_hint.text = "" if _base_panel.visible else ("Press B for the base panel" if in_base else "")
	if not _base_panel.visible:
		return
	var p = _match.local_player
	for b in _build_tab.get_children():
		var key = b.get_meta("key")
		var data = GameData.BUILDINGS[key]
		var locked = data.age > p.age
		var count = p.buildings(key).size()
		var limit = ""
		if key == "village_house":
			limit = " (%d/%d)" % [count, GameData.MAX_HOUSES]
		elif data.has("max"):
			limit = " (%d/%d)" % [count, data.max]
		b.text = "%s%s - %s%s" % [
			data.name, limit, GameData.cost_text(data.cost),
			("   (needs %s Age)" % GameData.AGE_NAMES[data.age]) if locked else ""
		]
		b.disabled = locked or not p.has_resources(data.cost)
	_refresh_military()
	_refresh_age_tab()


func _refresh_military():
	var p = _match.local_player
	var producers = p.buildings().filter(func(b): return b.trains != "" and b.is_constructed())
	var seen = {}
	for b in producers:
		seen[b.net_id] = true
		if not _military_rows.has(b.net_id):
			_military_rows[b.net_id] = _make_military_row(b)
		_update_military_row(_military_rows[b.net_id], b)
	for id in _military_rows.keys():
		if not seen.has(id):
			_military_rows[id].root.queue_free()
			_military_rows.erase(id)
	if producers.is_empty() and _military_tab.get_child_count() == 0:
		_label(_military_tab, "Build a Barracks, Archery Range or Stables first.", 13)
	elif not producers.is_empty():
		for child in _military_tab.get_children():
			if child is Label:
				child.queue_free()


func _make_military_row(b):
	var row = {}
	var box = VBoxContainer.new()
	_military_tab.add_child(box)
	row.root = box
	row.title = _label(box, "", 14, ACCENT)
	row.supply = _bar(box, Color("d89a2e"), 10)
	row.status = _label(box, "", 12)
	row.status.autowrap_mode = TextServer.AUTOWRAP_WORD
	var line = HBoxContainer.new()
	box.add_child(line)
	row.auto = CheckBox.new()
	row.auto.text = "Auto-repeat"
	row.auto.focus_mode = Control.FOCUS_NONE
	line.add_child(row.auto)
	row.lane = OptionButton.new()
	row.lane.focus_mode = Control.FOCUS_NONE
	row.lane.add_item("Rally (no lane)", 0)
	row.lane.set_item_metadata(0, -1)
	var i = 1
	for lane in _match.lanes_for_player(_match.local_player):
		row.lane.add_item(_match.lane_label(lane.index, _match.local_player), i)
		row.lane.set_item_metadata(i, lane.index)
		i += 1
	line.add_child(row.lane)
	row.train = _button(box, "Train one squadron", func(): _submit({"type": "train", "building": b.net_id}))
	row.auto.toggled.connect(func(on): _send_auto(b, row, on))
	row.lane.item_selected.connect(func(_idx): _send_auto(b, row, row.auto.button_pressed))
	box.add_child(HSeparator.new())
	return row


func _send_auto(b, row, enabled):
	var lane_index = row.lane.get_item_metadata(row.lane.selected)
	_submit({"type": "set_auto_repeat", "building": b.net_id, "enabled": enabled, "lane": lane_index})


func _update_military_row(row, b):
	var stats = b.squad_stats()
	row.title.text = "%s: %s x%d" % [b.display_name, stats.name, stats.squad_size]
	row.supply.value = b.supply_fraction() * 100.0
	var cost = b.squad_cost()
	var have = []
	for res in cost:
		have.append("%s %d/%d" % [RES_ICONS[res], b.supply.get(res, 0), cost[res]])
	var status = "Supply: " + ", ".join(have)
	if b.wants_supply() and not b.supply_full():
		status += "\nWaiting for villagers to deliver supplies"
	elif b.manual_pending > 0:
		status += "\nTraining (%d queued)" % b.manual_pending
	elif b.auto_repeat:
		status += "\nNext squadron in %ds" % ceili(b.cycle_left)
	row.status.text = status
	if not row.auto.has_focus():
		row.auto.set_pressed_no_signal(b.auto_repeat)
	for idx in range(row.lane.item_count):
		if row.lane.get_item_metadata(idx) == b.lane:
			if row.lane.selected != idx:
				row.lane.select(idx)


var _age_signature = ""


func _refresh_age_tab():
	var p = _match.local_player
	var tcs_now = p.town_centers()
	var sig = "%d|%s|%s" % [
		p.age, p.has_resources(GameData.AGES.get(p.age + 1, {"cost": {}}).cost),
		"" if tcs_now.is_empty() else "%d:%d:%s" % [
			tcs_now[0].age_target, int(tcs_now[0].age_progress * 100), tcs_now[0].build_paused_reason
		]
	]
	if sig == _age_signature:
		return
	_age_signature = sig
	for child in _age_tab.get_children():
		child.queue_free()
	_label(_age_tab, "Current Age: %s" % GameData.AGE_NAMES[p.age], 15, ACCENT)
	var next = p.age + 1
	var tcs = p.town_centers()
	if not tcs.is_empty() and tcs[0].age_target > 0:
		var pct = int(tcs[0].age_progress * 100)
		var paused = _paused_text(tcs[0].build_paused_reason)
		_label(_age_tab, "Advancing to %s: %d%% %s" % [GameData.AGE_NAMES[tcs[0].age_target], pct, paused], 13)
		return
	if next > 2 or not GameData.AGES.has(next):
		_label(_age_tab, "The Empire Age arrives in a later milestone.", 13)
		return
	var age = GameData.AGES[next]
	_label(_age_tab, "Next: %s Age\nCost: %s\nTime: %ds with your hero at the Town Center" % [
		age.name, GameData.cost_text(age.cost), int(age.time)
	], 13)
	_label(_age_tab, "Unlocks: Archery Range, Stables, Storehouse", 12, Color(1, 1, 1, 0.7))
	var b = _button(_age_tab, "Advance to the %s Age" % age.name, func(): _submit({"type": "advance_age"}))
	b.disabled = not p.has_resources(age.cost)


func _paused_text(reason):
	match reason:
		"no_hero":
			return "PAUSED: a hero must stay nearby"
		"enemy_hero":
			return "PAUSED: enemy hero nearby!"
	return ""


# --- villager bubbles -------------------------------------------------------------------------
func _build_bubbles():
	_bubbles = _panel(_root, Control.PRESET_TOP_LEFT)
	var box = VBoxContainer.new()
	_bubbles.add_child(box)
	_bubbles.set_meta("title", _label(box, "Villagers", 14, ACCENT))
	var row = HBoxContainer.new()
	box.add_child(row)
	for assignment in ["food", "wood", "stone", "iron", "home"]:
		var b = _button(row, ASSIGN_LABELS[assignment], _on_assign.bind(assignment))
		b.set_meta("assignment", assignment)
	_bubbles.set_meta("row", row)
	_button(box, "Close", func(): _bubbles.visible = false)
	_bubbles.visible = false


func show_bubbles(house):
	_bubble_house = house
	_bubbles.visible = true
	_info_panel.visible = false


func _on_assign(assignment):
	if _bubble_house == null or not is_instance_valid(_bubble_house):
		return
	_submit({"type": "assign_villagers", "house": _bubble_house.net_id, "assignment": assignment})


func _refresh_bubbles():
	if not _bubbles.visible:
		return
	if _bubble_house == null or not is_instance_valid(_bubble_house) or not _bubble_house.is_alive():
		_bubbles.visible = false
		return
	var screen = get_viewport().get_camera_3d().unproject_position(_bubble_house.global_position)
	_bubbles.position = screen + Vector2(-_bubbles.size.x / 2.0, 30)
	var alive = _bubble_house.alive_villagers().size() if _match.is_host() else _bubble_house.get_meta("villagers_alive", 0)
	var title = "Villagers %d/%d" % [alive, GameData.VILLAGERS_PER_HOUSE]
	if alive < GameData.VILLAGERS_PER_HOUSE:
		title += "   next villager in %ds (50 Food)" % ceili(max(0.0, _bubble_house.respawn_left))
	_bubbles.get_meta("title").text = title
	for b in _bubbles.get_meta("row").get_children():
		var active = b.get_meta("assignment") == _bubble_house.assignment
		b.modulate = ACCENT if active else Color.WHITE


# --- building info ----------------------------------------------------------------------------
func _build_info_panel():
	_info_panel = _panel(_root, Control.PRESET_TOP_LEFT)
	var box = VBoxContainer.new()
	_info_panel.add_child(box)
	_info_panel.set_meta("label", _label(box, "", 13))
	_info_panel.set_meta("cancel", _button(box, "Cancel construction (75% refund)", _on_cancel_build))
	_button(box, "Close", func(): _info_panel.visible = false)
	_info_panel.visible = false


func show_building(b):
	_info_building = b
	_info_panel.visible = true
	_bubbles.visible = false


func _on_cancel_build():
	if _info_building != null and is_instance_valid(_info_building):
		_submit({"type": "cancel_build", "target": _info_building.net_id})
	_info_panel.visible = false


func _refresh_info():
	if not _info_panel.visible:
		return
	var b = _info_building
	if b == null or not is_instance_valid(b) or not b.is_alive():
		_info_panel.visible = false
		return
	var screen = get_viewport().get_camera_3d().unproject_position(b.global_position)
	_info_panel.position = screen + Vector2(-_info_panel.size.x / 2.0, 30)
	var text = "%s   %d/%d HP" % [b.display_name, b.hp, b.hp_max]
	if not b.is_constructed():
		text += "\nUnder construction: %d%% %s" % [int(b.progress * 100), _paused_text(b.build_paused_reason)]
	elif b.building_key == "storehouse":
		text += "\nAccess point. If it's destroyed you lose half your stockpile."
	elif b.building_key == "town_center":
		text += "\nAccess point, Age advances, hero respawn."
	_info_panel.get_meta("label").text = text
	_info_panel.get_meta("cancel").visible = not b.is_constructed()


# --- toasts and end screen --------------------------------------------------------------------
func _build_toasts():
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toasts.offset_top = 60
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)


func show_toast(text: String):
	var label = _label(_toasts, text, 16, Color("ffe9a8"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	while _toasts.get_child_count() > 5:
		_toasts.get_child(0).free()
	var tween = label.create_tween()
	tween.tween_interval(TOAST_TIME)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


func show_end_screen(text: String, won: bool):
	if _end_screen != null:
		return
	_end_screen = _panel(_root, Control.PRESET_CENTER, Vector2(420, 180))
	var box = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_end_screen.add_child(box)
	var title = _label(box, text, 42, ACCENT if won else Color("ff6b6b"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(box, "Back to main menu", _back_to_menu)


func _back_to_menu():
	Network.leave()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://source/main-menu/Main.tscn")


# --- 3D effects ---------------------------------------------------------------------------------
func play_fx(kind: String, from: Vector3, to: Vector3):
	if not is_inside_tree():
		return
	match kind:
		"arrow":
			_arrow(from, to)
		"hit":
			_spark(to, Color(1, 0.85, 0.5), 0.25)
		"cast":
			_ring(from, ACCENT, 3.0)


func ping(point: Vector3):
	_ring(point, Color(0.5, 1, 0.5), 1.2)


func _arrow(from: Vector3, to: Vector3):
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.05, 0.05, 0.6)
	mesh.mesh = box
	mesh.material_override = UnitFactory._material(Color("3a2a1a"))
	_match.add_child(mesh)
	var start = from + Vector3(0, 1.2, 0)
	var end = to + Vector3(0, 0.8, 0)
	mesh.global_position = start
	if start.distance_to(end) > 0.1:
		mesh.look_at_from_position(start, end, Vector3.UP)
	var tween = mesh.create_tween()
	tween.tween_property(mesh, "global_position", end, clamp(start.distance_to(end) / 25.0, 0.08, 0.5))
	tween.tween_callback(mesh.queue_free)


func _spark(at: Vector3, color: Color, size: float):
	var mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2
	sphere.radial_segments = 6
	sphere.rings = 3
	mesh.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	_match.add_child(mesh)
	mesh.global_position = at + Vector3(0, 0.9, 0)
	var tween = mesh.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tween.tween_callback(mesh.queue_free)


func _ring(at: Vector3, color: Color, radius: float):
	var mesh = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = radius * 0.85
	torus.outer_radius = radius
	torus.rings = 16
	torus.ring_segments = 4
	mesh.mesh = torus
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	_match.add_child(mesh)
	mesh.global_position = at + Vector3(0, 0.1, 0)
	mesh.scale = Vector3(0.3, 1, 0.3)
	var tween = mesh.create_tween().set_parallel(true)
	tween.tween_property(mesh, "scale", Vector3.ONE, 0.4)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tween.chain().tween_callback(mesh.queue_free)
