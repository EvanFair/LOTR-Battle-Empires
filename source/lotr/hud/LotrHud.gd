extends CanvasLayer
## The in-match interface. LotrHud lays out the widgets in widgets/ (champion panel, over-head
## bars, damage numbers, tooltips, cursors) and still builds the older code-made panels:
##  top bar (stockpile, Age, houses, clock), squadron panel, base panel (Build / Military / Age /
##  Shop), villager bubbles, building info, toasts, end screen, plus 3D effects (arrows, hits,
##  pings, cast rings). Everything sits under one scaled root (see _apply_scale) and uses the
##  Theme from widgets/HudTheme.gd.

const HudTheme = preload("res://source/lotr/hud/widgets/HudTheme.gd")
const ChampionPanel = preload("res://source/lotr/hud/widgets/ChampionPanel.gd")
const OverheadBars = preload("res://source/lotr/hud/widgets/OverheadBars.gd")
const DamageNumbers = preload("res://source/lotr/hud/widgets/DamageNumbers.gd")
const Tooltips = preload("res://source/lotr/hud/widgets/Tooltips.gd")
const Cursors = preload("res://source/lotr/hud/widgets/Cursors.gd")

const REFERENCE_SIZE = Vector2(1920, 1080)  # the HUD is laid out for this and scaled to fit
const PANEL_BG = Color(0.08, 0.07, 0.06, 0.82)
const ACCENT = Color("e8c24a")
const RES_ICONS = {"food": "Food", "wood": "Wood", "stone": "Stone", "iron": "Iron", "gold": "Gold"}
const ASSIGN_LABELS = {
	"balanced": "Balanced", "food": "Food", "wood": "Wood", "stone": "Stone", "iron": "Iron",
	"home": "Shelter",
}
const TOAST_TIME = 4.0
const SQUAD_ORDER_BUTTONS = [
	["G Follow me", "follow"], ["1 Attack", "squad_attack"], ["2 Move", "squad_defend"],
	["3 Hold", "hold"], ["4 Return", "return"],
]

var _match = null
var _root = null
var _top_label = null
var _res_labels = {}
var _champion = null
var _overhead = null
var _numbers = null
var hud_scale = 1.0  # effective factor: window fit * user_scale
static var user_scale = 1.0  # the 75-125% setting (options menu can write this)
var _squad_box = null
var _squad_list = null
var _squad_detail = null
var _squad_hint = null
var _mode_label = null
var _base_panel = null
var _build_tab = null
var _military_tab = null
var _age_tab = null
var _upgrades_tab = null
var _focus_pick = null
var _steward_button = null
var _shelter_button = null
var _feed_label = null
var _base_tabs = null
var _squad_lane = null
var _drag_box = null
var _shop_tab = null
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
	_root.theme = HudTheme.theme()
	Tooltips.host = _root
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_apply_scale()
	get_viewport().size_changed.connect(_apply_scale)
	_numbers = DamageNumbers.new(_match)
	_build_top_bar()
	_build_toasts()
	if _match.local_player != null:
		_build_champion_panel()
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


func _exit_tree():
	Cursors.reset()


func _apply_scale():
	"""One scale factor for the whole HUD: window size against the 1920x1080 layout, times the
	75-125% user setting. The root Control is made bigger by 1/scale so anchors still reach the
	screen edges."""
	var vp = get_viewport().get_visible_rect().size
	hud_scale = clampf(minf(vp.x / REFERENCE_SIZE.x, vp.y / REFERENCE_SIZE.y), 0.6, 2.0) * clampf(user_scale, 0.75, 1.25)
	_root.scale = Vector2(hud_scale, hud_scale)
	_root.position = Vector2.ZERO
	_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_root.size = vp / hud_scale


func to_hud(screen: Vector2) -> Vector2:
	"""Screen pixels -> HUD (scaled root) coordinates."""
	return screen / hud_scale


func _process(_delta):
	_refresh_top_bar()
	_refresh_tower_labels()
	if _match.local_player == null:
		return
	_refresh_hero()
	_refresh_squads()
	_refresh_base_panel()
	_refresh_bubbles()
	_refresh_info()


# --- helpers ------------------------------------------------------------------------------------
func _panel(parent, anchors: int, min_size = Vector2.ZERO, plate = false) -> PanelContainer:
	var panel = PanelContainer.new()
	if plate:
		panel.add_theme_stylebox_override("panel", HudTheme.plate_box())
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


func _label(parent, text = "", size = 14, color = HudTheme.TEXT) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size + 1)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent, text, callback: Callable, min_width = 0) -> Button:
	var button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.x = min_width
	button.pressed.connect(callback)
	button.pressed.connect(func(): Sfx.play("ui_click"))
	parent.add_child(button)
	return button


func _bar(parent, color: Color, height = 12) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, height)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("fill", HudTheme.flat_box(color, Color(0, 0, 0, 0), 0, 2, 0))
	bar.add_theme_stylebox_override("background", HudTheme.flat_box(Color(0.02, 0.02, 0.03, 0.9), HudTheme.GOLD_DIM, 1, 2, 0))
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
	var panel = _panel(_root, Control.PRESET_CENTER_TOP, Vector2.ZERO, true)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	# v3: one shared war chest for the whole team
	var chest = TextureRect.new()
	chest.texture = Icons.art("resources", "gold")
	chest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chest.custom_minimum_size = Vector2(26, 26)
	chest.tooltip_text = "Supplies: your team's shared war chest. Everything costs Supplies; every teammate can spend them."
	row.add_child(chest)
	_res_labels["supplies"] = _label(row, "", 18, ACCENT)
	_top_label = _label(row, "", 16)
	_steward_button = _button(row, "", func(): _submit({"type": "assign_villagers", "assignment": "steward"}))
	_steward_button.tooltip_text = "Steward ON: the city builds houses, core buildings and the next Age by itself (keeping 250 Supplies for your heroes). Turn off to build yourself."
	_shelter_button = _button(row, "", func(): _submit({"type": "assign_villagers", "assignment": "home"}))
	_shelter_button.tooltip_text = "Send every villager into the houses (raid!) or back to work"
	# purchase feed under the bar: who spent the team's Supplies on what
	_feed_label = _label(_root, "", 12, Color(1, 1, 1, 0.75))
	_feed_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_feed_label.position.y = 44
	_feed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _refresh_top_bar():
	var elapsed = int(GameData.now() - _start_time)
	var clock = "%02d:%02d" % [elapsed / 60, elapsed % 60]
	var p = _match.local_player
	if p == null:
		_top_label.text = "Spectating    " + clock
		return
	var t = p.treasury()
	var income = 0
	for res in t.income_per_min:
		income += GameData.price({res: t.income_per_min[res]})
	_res_labels["supplies"].text = "%d Supplies" % t.supplies + ("  (+%d/min)" % income if income > 0 else "")
	var parts = []
	var houses = p.buildings("village_house").size()
	parts.append("Houses %d/%d" % [houses, GameData.MAX_HOUSES])
	parts.append("Age: %s" % GameData.AGE_NAMES[p.age])
	parts.append(clock)
	_top_label.text = "    ".join(parts)
	_steward_button.text = "Steward: %s" % ("ON" if t.steward else "off")
	_shelter_button.text = "Villagers: %s" % ("SHELTERED" if p.shelter else "working")
	var feed = []
	for e in t.spend_log:
		if GameData.now() - e.at < 25.0:
			feed.append("%s bought %s (-%d)" % [e.who, e.what, e.amount])
	_feed_label.text = "\n".join(feed.slice(0, 3))


# --- champion panel (widgets/ChampionPanel.gd) ----------------------------------------------------
func _build_champion_panel():
	_overhead = OverheadBars.new()
	_overhead.match_node = _match
	_root.add_child(_overhead)
	_root.move_child(_overhead, 0)  # under every panel
	_champion = ChampionPanel.new()
	_root.add_child(_champion)
	_champion.build(_match)
	_champion.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 6)
	_champion.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_champion.grow_horizontal = Control.GROW_DIRECTION_BOTH


func _refresh_hero():
	if _champion != null:
		_champion.refresh()


# --- squadrons --------------------------------------------------------------------------------
func _build_squad_panel():
	var panel = _panel(_root, Control.PRESET_BOTTOM_LEFT, Vector2(300, 0))
	panel.offset_bottom = -228  # sits above the minimap and grows upward
	panel.offset_top = -228
	_squad_box = VBoxContainer.new()
	panel.add_child(_squad_box)
	_label(_squad_box, "Your squadrons", 14, ACCENT)
	_squad_hint = _label(_squad_box, "Drag a box over soldiers or press Tab to select. Right-click orders them. G: follow me", 12, Color(1, 1, 1, 0.6))
	_squad_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_squad_list = VBoxContainer.new()
	_squad_box.add_child(_squad_list)
	_squad_detail = HFlowContainer.new()
	_squad_box.add_child(_squad_detail)
	for entry in SQUAD_ORDER_BUTTONS:
		_button(_squad_detail, entry[0], _on_squad_order.bind(entry[1]))
	_squad_lane = OptionButton.new()
	_squad_lane.focus_mode = Control.FOCUS_NONE
	_squad_lane.item_selected.connect(_on_squad_lane)
	_squad_detail.add_child(_squad_lane)
	_drag_box = ReferenceRect.new()
	_drag_box.border_color = Color(0.55, 1.0, 0.55)
	_drag_box.border_width = 1.5
	_drag_box.editor_only = false
	_drag_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_box.visible = false
	_root.add_child(_drag_box)


func _on_squad_order(order):
	var hc = _match.hero_controller
	if order in ["squad_attack", "squad_defend"]:
		hc._start_mode(order)
	elif order == "follow":
		hc._follow_me()
	else:
		hc._squad_order(order)


func _on_squad_lane(idx):
	var lane_index = _squad_lane.get_item_metadata(idx)
	if lane_index != null and lane_index >= 0:
		_match.hero_controller._squad_order("lane", {"lane": lane_index})
	_squad_lane.select(0)


func draw_drag_box(start, end):
	if _drag_box == null:
		return
	if start == null or end == null or start.distance_to(end) < 8.0:
		_drag_box.visible = false
		return
	var r = Rect2(to_hud(start), Vector2.ZERO).expand(to_hud(end))
	_drag_box.position = r.position
	_drag_box.size = r.size
	_drag_box.visible = true


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
	if _squad_lane.item_count == 0 and _match.local_player != null:
		_squad_lane.add_item("March to...", 0)
		_squad_lane.set_item_metadata(0, -1)
		var li = 1
		for lane in _match.lanes_for_player(_match.local_player):
			_squad_lane.add_item(_match.lane_label(lane.index, _match.local_player), li)
			_squad_lane.set_item_metadata(li, lane.index)
			li += 1
	var squads = _match.hero_controller.my_squads()
	_squad_hint.visible = true
	_squad_detail.visible = not _match.hero_controller.selected_squads.is_empty()
	var chosen = _match.hero_controller.selected_squads
	var buttons = _squad_list.get_children()
	for i in range(max(buttons.size(), squads.size())):
		if i >= squads.size():
			buttons[i].queue_free()
			continue
		var s = squads[i]
		var b = buttons[i] if i < buttons.size() else _button(_squad_list, "", func(): pass)
		if i >= buttons.size():
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var marker = "> " if s.id in chosen else "   "
		b.text = "%s%s x%d  %d%%  %s" % [
			marker, s.name, s.count, int(s.hp * 100), _squad_state_name(s.state)
		]
		for c in b.pressed.get_connections():
			b.pressed.disconnect(c.callable)
		b.pressed.connect(func(): _match.hero_controller.select_squad(s.id, Input.is_key_pressed(KEY_SHIFT)))


func _squad_state_name(state):
	return ["Idle", "Marching", "Attacking", "Defending", "Holding", "Returning", "Following you"][state]


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
		"attack_move":
			_mode_label.text = "Attack-move: left-click where to go (your hero fights anything on the way)"
		"place_wall":
			_mode_label.text = "Walls: click where the wall starts, then where it ends (Shift keeps going). Roads get gates automatically."
		"cast":
			_mode_label.text = "Left-click to cast (right-click cancels)"
		_:
			_mode_label.text = ""


# --- base panel -------------------------------------------------------------------------------
func _build_base_panel():
	_base_panel = _panel(_root, Control.PRESET_RIGHT_WIDE, Vector2(380, 0))
	_base_panel.offset_top = 60
	_base_panel.offset_bottom = -60
	var box = VBoxContainer.new()
	_base_panel.add_child(box)
	_label(box, "Base  (B)", 16, ACCENT)
	var tabs = TabContainer.new()
	_base_tabs = tabs
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	_build_tab = _scroll_tab(tabs, "Build")
	_military_tab = _scroll_tab(tabs, "Military")
	_age_tab = _scroll_tab(tabs, "Age")
	_upgrades_tab = _scroll_tab(tabs, "Blacksmith")
	_shop_tab = _scroll_tab(tabs, "Shop")
	var faction = _match.local_player.faction if _match.local_player != null else "gondor"
	for key in GameData.BUILD_MENU:
		var data = GameData.BUILDINGS[key]
		var b = _button(_build_tab, "", _on_build_pressed.bind(key))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.set_meta("key", key)
		var trains = ""
		if data.has("trains"):
			trains = "\nTrains: %s" % GameData.FACTIONS[faction].units[data.trains]
		b.tooltip_text = "%s\n%s\nCost: %s\nBuild time: %ds (your hero must stay nearby)%s" % [
			GameData.building_name(key, faction), data.get("desc", ""), GameData.cost_text(data.cost), int(data.build_time), trains
		]
	_base_panel.visible = false
	_base_hint = _label(_root, "", 13, Color(1, 1, 1, 0.75))
	_base_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)


func _scroll_tab(tabs, title):
	var scroll = ScrollContainer.new()
	scroll.name = title
	# never scroll sideways, and don't let long entries widen the panel: buttons clip their
	# text (the tooltip has it in full) and labels wrap
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	tabs.add_child(scroll)
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.child_entered_tree.connect(func(child):
		if child is Button:
			child.clip_text = true
			if child.tooltip_text == "":
				child.tooltip_text = child.text
		elif child is Label:
			child.autowrap_mode = TextServer.AUTOWRAP_WORD
			child.custom_minimum_size.x = 300)
	scroll.add_child(box)
	return box


var _tower_labels = []


func _refresh_tower_labels():
	if _tower_labels.is_empty():
		for st in _match.tower_state:
			var l = Label3D.new()
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.font_size = 34
			l.outline_size = 8
			l.pixel_size = 0.01
			l.modulate = Color(0.9, 0.85, 0.65)
			_match.add_child(l)
			l.global_position = st.site.pos + Vector3(0, 3.2, 0)
			_tower_labels.append(l)
	for i in range(_tower_labels.size()):
		var st = _match.tower_state[i]
		var l = _tower_labels[i]
		if _match.tower_holder(i) != null:
			l.visible = false
			continue
		l.visible = true
		if st.progress > 0.0 and st.claimer >= 0:
			var who = _match.player_for_slot(st.claimer)
			l.text = "%s claiming %d%%" % [who.player_name if who != null else "?", int(st.progress * 100)]
		else:
			l.text = "Forgotten tower\nstand here with your hero to claim"


func in_base() -> bool:
	return _in_base()


func base_panel_open() -> bool:
	return _base_panel != null and _base_panel.visible


func show_ping(pos: Vector3, kind: String, from_player):
	var hc = _match.hero_controller
	if hc != null and hc.indicators != null:
		hc.indicators.ping(pos, kind == "danger")
	Sfx.play("ui_confirm" if kind != "danger" else "vital_break")
	var who = from_player.player_name if from_player != null else "Ally"
	show_toast("%s: %s" % [who, "Danger here!" if kind == "danger" else "Look here"])
	minimap_ping(pos, Color(1, 0.35, 0.3) if kind == "danger" else Color(1.0, 0.9, 0.4))


func minimap_ping(pos: Vector3, color = Color(1.0, 0.9, 0.4)):
	var minimap = _match.find_child("Minimap")
	if minimap != null and minimap.has_method("ping"):
		minimap.ping(pos, color)


var _opened_anywhere = false


func toggle_build_menu(anywhere = false):
	"""B opens the base panel at home; V opens it anywhere on the Build tab (you can build
	anywhere; training, research, Ages and the shop still need you at home)."""
	if _base_panel == null:
		return
	if not _base_panel.visible and not _in_base() and not anywhere:
		show_toast("Return to your base for the base panel. Press V to build out here.")
		return
	_base_panel.visible = not _base_panel.visible
	_opened_anywhere = _base_panel.visible and not _in_base()
	if _opened_anywhere:
		_base_tabs.current_tab = 0


func _on_build_pressed(key):
	_match.hero_controller.start_placing(key)


func _refresh_base_panel():
	var in_base = _in_base()
	if _base_panel.visible and not in_base and not _opened_anywhere and _match.hero_controller.mode != "place":
		_base_panel.visible = false
	_base_hint.text = "" if _base_panel.visible else ("B: base panel   V: build" if in_base else "V: build here")
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
			GameData.building_name(key, p.faction), limit, GameData.cost_text(data.cost),
			("   (needs %s Age)" % GameData.AGE_NAMES[data.age]) if locked else ""
		]
		b.disabled = locked or not p.has_resources(data.cost)
	_refresh_military()
	_refresh_age_tab()
	_refresh_upgrades_tab()
	_refresh_shop_tab()


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
		_label(_military_tab, "Build a Barracks, Archery Range, Stables, Siege Works or %s first." % GameData.building_name("special_building", p.faction), 13)
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
	row.lane.add_item("Stay by the building", 0)
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
	var status = "Cost per squadron: " + GameData.cost_text(b.squad_cost())
	if (b.auto_repeat or b.manual_pending > 0) and not b.supply_full():
		status += "\nWaiting for resources (paid from your stockpile)"
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
	var sig = "%d|%d|%s|%s" % [
		p.age, p.treasury().feats + _match._team_towers(p), p.has_resources(GameData.AGES.get(p.age + 1, {"cost": {}}).cost),
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
	if not GameData.AGES.has(next):
		_label(_age_tab, "You have reached the final Age.", 13)
		return
	var age = GameData.AGES[next]
	var have = p.treasury().feats + _match._team_towers(p)
	_label(_age_tab, "Next: %s Age\nCost: %s\nTime: %ds\nFeats: %d / %d (clear monster lairs, hold forgotten towers)" % [
		age.name, GameData.cost_text(age.cost), int(age.time), have, age.get("feats", 0)
	], 13)
	var unlocks = []
	for key in GameData.BUILD_MENU:
		if GameData.BUILDINGS[key].age == next:
			unlocks.append(GameData.building_name(key, p.faction))
	for key in GameData.UPGRADES:
		if GameData.UPGRADES[key].age == next:
			unlocks.append(GameData.UPGRADES[key].name)
	_label(_age_tab, "Unlocks: " + ", ".join(unlocks), 12, Color(1, 1, 1, 0.7)).autowrap_mode = TextServer.AUTOWRAP_WORD
	var b = _button(_age_tab, "Advance to the %s Age" % age.name, func(): _submit({"type": "advance_age"}))
	b.disabled = not p.has_resources(age.cost)


var _shop_signature = ""


func _refresh_shop_tab():
	var h = _hero()
	if h == null:
		return
	var p = _match.local_player
	var sig = "%d|%s|%d" % [p.treasury().supplies, str(h.items.map(func(it): return it.key)), int(h.dead)]
	if sig == _shop_signature:
		return
	_shop_signature = sig
	for child in _shop_tab.get_children():
		child.queue_free()
	_label(_shop_tab, "Team Supplies: %d    Bags: %d/%d" % [p.treasury().supplies, h.items.size(), GameData.ITEM_SLOTS], 14, ACCENT)
	for i in range(h.items.size()):
		var data = GameData.ITEMS[h.items[i].key]
		var slot = i
		var sell = _button(_shop_tab, "Sell %s (+%d Supplies)" % [data.name, int(data.cost * GameData.SELL_REFUND)], func(): _submit({"type": "sell", "slot": slot}))
		sell.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_shop_tab.add_child(HSeparator.new())
	for key in GameData.SHOP_ORDER:
		var data = GameData.ITEMS[key]
		var b = _button(_shop_tab, "%s - %d gold" % [data.name, data.cost], func(): _submit({"type": "buy", "item": key}))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon = Icons.item(key)
		b.add_theme_constant_override("icon_max_width", 26)
		b.tooltip_text = data.desc
		b.disabled = h.dead or p.treasury().supplies < data.cost or h.items.size() >= GameData.ITEM_SLOTS
		_label(_shop_tab, data.desc, 11, Color(1, 1, 1, 0.65)).autowrap_mode = TextServer.AUTOWRAP_WORD


var _upgrades_signature = ""


func _refresh_upgrades_tab():
	var p = _match.local_player
	var smiths = p.buildings("blacksmith").filter(func(b): return b.is_constructed())
	var busy = "" if smiths.is_empty() else "%s:%d" % [smiths[0].research_key, ceili(smiths[0].research_left)]
	var affordable = []
	for key in GameData.UPGRADES:
		affordable.append(p.has_resources(GameData.UPGRADES[key].cost))
	var sig = "%d|%d|%s|%s|%s" % [p.age, smiths.size(), busy, str(p.upgrades), str(affordable)]
	if sig == _upgrades_signature:
		return
	_upgrades_signature = sig
	for child in _upgrades_tab.get_children():
		child.queue_free()
	if smiths.is_empty():
		_label(_upgrades_tab, "Build a Blacksmith (Kingdom Age) to research upgrades.\nUpgrades apply to squadrons trained afterwards.", 13).autowrap_mode = TextServer.AUTOWRAP_WORD
		return
	var smith = smiths[0]
	if smith.research_key != "":
		_label(_upgrades_tab, "Researching %s: %ds left" % [GameData.UPGRADES[smith.research_key].name, ceili(smith.research_left)], 13, ACCENT)
	for key in GameData.UPGRADES:
		var data = GameData.UPGRADES[key]
		var done = p.upgrades.get(key, false)
		var text = "%s - %s" % [data.name, "done" if done else GameData.cost_text(data.cost)]
		if data.age > p.age:
			text += "   (needs %s Age)" % GameData.AGE_NAMES[data.age]
		var b = _button(_upgrades_tab, text, func(): _submit({"type": "research", "upgrade": key}))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = "%s\n%s\nTime: %ds" % [data.name, data.desc, int(data.time)]
		b.disabled = done or data.age > p.age or smith.research_key != "" or not p.has_resources(data.cost)
		_label(_upgrades_tab, data.desc, 11, Color(1, 1, 1, 0.65))


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
	_label(box, "Villagers work on their own: they pick the safest, richest site. Mines inside monster lairs open up once a hero clears the lair.", 12, Color(1, 1, 1, 0.7))
	var row = HBoxContainer.new()
	box.add_child(row)
	for assignment in ["home"]:
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
	_submit({"type": "assign_villagers", "assignment": assignment})


func _refresh_bubbles():
	if not _bubbles.visible:
		return
	if _bubble_house == null or not is_instance_valid(_bubble_house) or not _bubble_house.is_alive():
		_bubbles.visible = false
		return
	var screen = to_hud(get_viewport().get_camera_3d().unproject_position(_bubble_house.global_position))
	_bubbles.position = screen + Vector2(-_bubbles.size.x / 2.0, 30)
	var alive = _bubble_house.alive_villagers().size() if _match.is_host() else _bubble_house.get_meta("villagers_alive", 0)
	var title = "Villagers in this house %d/%d" % [alive, GameData.VILLAGERS_PER_HOUSE]
	if alive < GameData.VILLAGERS_PER_HOUSE:
		title += "   next villager in %ds" % ceili(max(0.0, _bubble_house.respawn_left))
	_bubbles.get_meta("title").text = title
	var p = _match.local_player
	for b in _bubbles.get_meta("row").get_children():
		var key = b.get_meta("assignment")
		var active = key == "home" and p.shelter
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
	var screen = to_hud(get_viewport().get_camera_3d().unproject_position(b.global_position))
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
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)


func show_toast(text: String):
	var plate = PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", _toast_box())
	var label = HudTheme.label(plate, text, 18, Color("ffe9a8"), "head_reg")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toasts.add_child(plate)
	while _toasts.get_child_count() > 5:
		_toasts.get_child(0).free()
	var tween = plate.create_tween()
	tween.tween_interval(TOAST_TIME)
	tween.tween_property(plate, "modulate:a", 0.0, 0.6)
	tween.tween_callback(plate.queue_free)


func _toast_box() -> StyleBox:
	var tex = HudTheme.scaled_tex("toast", 0.42)
	if tex == null:
		return HudTheme.flat_box(Color(0.03, 0.035, 0.05, 0.85), HudTheme.GOLD_DIM, 1, 4, 6)
	var sb = StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = 34
	sb.texture_margin_right = 34
	sb.texture_margin_top = 16
	sb.texture_margin_bottom = 16
	sb.content_margin_left = 38
	sb.content_margin_right = 38
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func show_end_screen(text: String, won: bool):
	if _end_screen != null:
		return
	var path = "res://assets/art/keyart/%s.webp" % ("victory" if won else "defeat")
	if ResourceLoader.exists(path):
		var art = TextureRect.new()
		art.texture = load(path)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		_root.add_child(art)
	_end_screen = _panel(_root, Control.PRESET_CENTER, Vector2(420, 180))
	var box = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_end_screen.add_child(box)
	var title = HudTheme.label(box, text, 46, ACCENT if won else Color("ff6b6b"), "head")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(box, "Back to main menu", _back_to_menu)
	Sfx.stop_music()
	Sfx.play("victory" if won else "defeat")


func _back_to_menu():
	Sfx.stop_music()
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
			Sfx.play("arrow", from)
		"tower_shot":
			_arrow(from, to)
			Sfx.play("tower", from)
		"hit":
			_spark(to, Color(1, 0.85, 0.5), 0.25)
			Sfx.play("clash" if randf() < 0.35 else "melee", to)
		"cast":
			_ring(from, ACCENT, 3.0)
			Sfx.play("arcane", from)
		"blast":
			_explosion(from, 0.6)
			_spark(from, Color(1, 0.55, 0.15), 1.8)
			_ring(from, Color(1, 0.4, 0.1), 3.5)
			Sfx.play("blast", from)
		"boulder":
			_boulder(from, to)
		"nova":
			_ring(from, Color(1.0, 0.75, 0.35), max(1.0, from.distance_to(to)))
			Sfx.play("holy", from)
		"volley":
			# from = landing point, to = the shooter
			for i in range(6):
				var spread = Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
				_arrow(to + Vector3(0, 1.5, 0), from + spread)
			Sfx.play("arrow", to)
		"bolt":
			_bolt(from, to)
			Sfx.play("arcane", from)
		"dmg":
			_damage_number(from, int(to.x), int(to.y), int(to.z))
		"loot":
			var me = _match.local_player
			if me != null and _match.player_for_slot(int(to.y)) != null and Teams.is_ally(_match.player_for_slot(int(to.y)), me):
				_numbers.text(from, "+%d" % int(to.x), DamageNumbers.COLORS.gold, 54 if int(to.y) == me.slot_index else 38)
				if int(to.y) == me.slot_index:
					Sfx.play("coin", from)
		# sound-only events
		"death":
			Sfx.play("death", from, 0.0, 0.2)
		"collapse":
			Sfx.play("collapse", from)
		"build_done":
			Sfx.play("build_done", from)
		"level_up":
			Sfx.play("level_up", from)
			_ring(from, Color(1, 0.85, 0.3), 1.6)
		"respawn":
			Sfx.play("respawn", from)
		"horn":
			Sfx.play("horn", from)
		"drums":
			Sfx.play("drums", from)
		"kill":
			Sfx.play("kill", from)


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


func _damage_number(at: Vector3, amount: int, from_slot: int, to_slot: int):
	var me = _match.local_player
	var kind = "other"
	var mine = false
	if me != null and to_slot == me.slot_index:
		kind = "taken"  # damage you take
		mine = true
	elif me != null and from_slot == me.slot_index:
		kind = "physical"  # damage you deal (magic arrives as its own kind once abilities carry a damage type)
		mine = true
	_numbers.damage(at, amount, kind, mine)


func _bolt(from: Vector3, to: Vector3):
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	var length = max(0.2, from.distance_to(to))
	box.size = Vector3(0.18, 0.18, length)
	mesh.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.9, 1.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.8, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	_match.add_child(mesh)
	var a = from + Vector3(0, 1.0, 0)
	var b = to + Vector3(0, 1.0, 0)
	mesh.global_position = (a + b) / 2.0
	if a.distance_to(b) > 0.1:
		mesh.look_at(b, Vector3.UP)
	var tween = mesh.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tween.tween_callback(mesh.queue_free)


func _boulder(from: Vector3, to: Vector3):
	# a lobbed stone: arcs up and lands with a dust burst
	var mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	sphere.radial_segments = 6
	sphere.rings = 3
	mesh.mesh = sphere
	mesh.material_override = UnitFactory._material(Color("8a857a"))
	_match.add_child(mesh)
	var start = from + Vector3(0, 2.0, 0)
	var end = to + Vector3(0, 0.5, 0)
	mesh.global_position = start
	var time = clamp(start.distance_to(end) / 12.0, 0.4, 1.4)
	var arc = func(t: float):
		if is_instance_valid(mesh):
			mesh.global_position = start.lerp(end, t) + Vector3(0, sin(t * PI) * 5.0, 0)
	var tween = mesh.create_tween()
	tween.tween_method(arc, 0.0, 1.0, time)
	tween.tween_callback(func(): _explosion(to, 0.35))
	tween.tween_callback(func(): _spark(to, Color(0.75, 0.65, 0.5), 1.2))
	tween.tween_callback(func(): Sfx.play("boulder", to))
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


const EXPLOSION_PATH = "res://assets/BinbunVFX_Vol2/ExplosionFX/effects/ground/vfx_ground_explosion_01.tscn"
static var _explosion_scene = null


func _explosion(at: Vector3, size: float):
	# Stylized Explosion FX by Binbun3D (CC0)
	if _explosion_scene == null:
		_explosion_scene = load(EXPLOSION_PATH) if ResourceLoader.exists(EXPLOSION_PATH) else false
	if not _explosion_scene:
		return
	var fx = _explosion_scene.instantiate()
	fx.scale = Vector3.ONE * size
	_match.add_child(fx)
	fx.global_position = at
	get_tree().create_timer(4.0).timeout.connect(fx.queue_free)
