extends Control
## B2: the selection panel above the champion panel (BFME Palantir / Age of Empires style).
##  - one horde: portrait, name, rank stars, soldiers "5/6", HP and XP bars, formation and stance
##    buttons, Follow / Return / Reinforce, Blacksmith upgrades
##  - several hordes: a grid of small portraits with mini HP bars (click = narrow to it,
##    Shift-click = remove it) and the commands they share
##  - a building: portrait, HP, production (train, queue and progress, auto-repeat, march target),
##    Blacksmith research
## Self-contained: attach(root, match_node, hud) places it and the floating horde bubbles; it
## watches the HeroController's selection by itself. Tests can drive it directly with
## set_selection(squads, building) and `source` (a Callable returning squad summaries).
## Commands go out as dictionaries through `command_requested` and (auto_submit) CommandBus.

signal command_requested(cmd)
signal mode_requested(mode)
signal squad_clicked(squad_id, shift)

const HudTheme = preload("res://source/lotr/hud/widgets/HudTheme.gd")
const PortraitFrame = preload("res://source/lotr/hud/widgets/PortraitFrame.gd")
const RankStars = preload("res://source/lotr/hud/widgets/RankStars.gd")
const HordeBubbles = preload("res://source/lotr/hud/widgets/HordeBubbles.gd")
const SquadronScript = preload("res://source/lotr/Squadron.gd")

const PANEL_SIZE = Vector2(860, 158)
const ACTIVE = Color("f4d060")
const CLASS_TAG = {"infantry": "Foot", "archer": "Archers", "rider": "Cavalry", "heavy": "Heavy", "special": "Elite"}

var match_node = null
var hud = null
var bubbles = null
var auto_submit = true
var source = Callable()  # () -> Array of squad summaries; default: the match's replicator
var mode = ""  # "", "single", "multi", "building"
var ids = []
var building = null

var _sig = ""
var _w = {}  # live widgets of the current layout
var _root = null
var _stats_left = 0.0
var _last_sel = ""


func _init():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = HudTheme.theme()
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	visible = false


func attach(root: Control, match_ref, hud_ref = null):
	"""Add the panel (bottom centre, above the hero panel) and the bubble layer to the HUD root."""
	match_node = match_ref
	hud = hud_ref
	root.add_child(self)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 6)
	offset_top = -(190.0 + 6.0 + PANEL_SIZE.y + 6.0)
	offset_bottom = -(190.0 + 12.0)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	bubbles = HordeBubbles.new()
	bubbles.hud = hud_ref
	root.add_child(bubbles)
	root.move_child(bubbles, 0)


# --- data ---------------------------------------------------------------------------------------------
func _summaries() -> Array:
	if source.is_valid():
		return source.call()
	if match_node != null and match_node.replicator != null:
		return match_node.replicator.squad_summaries()
	return []


func _by_id(all: Array, id):
	for s in all:
		if s.id == id:
			return s
	return null


func _local_player():
	return match_node.local_player if match_node != null else null


func _upgrades() -> Dictionary:
	var p = _local_player()
	return p.upgrades if p != null else {}


# --- selection ------------------------------------------------------------------------------------------
func set_selection(squads: Array, b = null):
	"""squads: summary dictionaries (or plain squad ids); b: a building node or null."""
	ids = []
	for s in squads:
		ids.append(s.id if s is Dictionary else int(s))
	building = b if b != null and is_instance_valid(b) else null
	_sig = "<reset>"
	_rebuild_if_needed()


func _rebuild_if_needed():
	var all = _summaries()
	var live = []
	for id in ids:
		var s = _by_id(all, id)
		if s != null:
			live.append(s)
	ids = live.map(func(s): return s.id)
	var new_mode = ""
	if not live.is_empty():
		new_mode = "single" if live.size() == 1 else "multi"
	elif building != null and is_instance_valid(building) and building.is_alive():
		new_mode = "building"
	var sig = new_mode
	match new_mode:
		"single":
			var s = live[0]
			sig += "%d|%s|%s|%s" % [s.id, s.cclass, s.spear, s.can_reinforce]
		"multi":
			sig += "|".join(ids.map(func(i): return str(i)))
		"building":
			sig += "%d|%s|%s" % [building.net_id, building.is_constructed(), building.trains]
	if sig == _sig:
		return live
	_sig = sig
	mode = new_mode
	for c in get_children():
		c.queue_free()
	_w = {}
	visible = mode != ""
	if mode == "":
		return live
	_root = PanelContainer.new()
	_root.add_theme_stylebox_override("panel", HudTheme.panel_box(10.0))
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.size = PANEL_SIZE
	add_child(_root)
	match mode:
		"single":
			_build_single(live[0])
		"multi":
			_build_multi(live)
		"building":
			_build_building(building)
	return live


# --- widgets -----------------------------------------------------------------------------------------------
func _portrait(texture, diameter: float) -> Control:
	var holder = Control.new()
	holder.custom_minimum_size = Vector2(diameter, diameter)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var disc = TextureRect.new()
	disc.texture = HudTheme.ring_texture(128, 64)
	disc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	disc.size = Vector2(diameter, diameter) * 0.82
	disc.position = Vector2(diameter, diameter) * 0.09
	disc.modulate = Color(0.1, 0.09, 0.08)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(disc)
	var pic = TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.size = Vector2(diameter, diameter) * 0.82
	pic.position = Vector2(diameter, diameter) * 0.09
	pic.texture = texture
	pic.material = HudTheme.circle_mask_material(0.02)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pic)
	var frame = TextureRect.new()
	frame.texture = HudTheme.tex("portrait_frame")
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.size = Vector2(diameter, diameter)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)
	holder.set_meta("pic", pic)
	return holder


func _bar(parent, color: Color, height = 12.0, width = 0.0) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, height)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL if width == 0.0 else Control.SIZE_SHRINK_BEGIN
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("fill", HudTheme.flat_box(color, color.darkened(0.5), 0, 2, 0.0))
	bar.add_theme_stylebox_override("background", HudTheme.flat_box(Color(0.02, 0.02, 0.03, 0.9), Color(0.25, 0.2, 0.1, 0.8), 1, 2, 0.0))
	parent.add_child(bar)
	return bar


func _btn(parent, text: String, callback: Callable, tip = "", width = 0.0) -> Button:
	var b = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(width, 26)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b


func _row(parent, title = "") -> HFlowContainer:
	var row = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 3)
	row.add_theme_constant_override("v_separation", 3)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	if title != "":
		var l = HudTheme.label(row, title, 12, HudTheme.TEXT_DIM)
		l.custom_minimum_size = Vector2(62, 22)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return row


func _portrait_for(s) -> Texture2D:
	return Icons.art("emblems", s.get("faction", "gondor"))


func _hp_text(s) -> String:
	return "%d / %d" % [s.get("hp_sum", 0), s.get("hp_max", 0)]


# --- one horde ------------------------------------------------------------------------------------------------
func _build_single(s):
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	_root.add_child(h)
	var left = VBoxContainer.new()
	left.custom_minimum_size = Vector2(104, 0)
	h.add_child(left)
	var pf = _portrait(_portrait_for(s), 96.0)
	left.add_child(pf)
	_w.pic = pf.get_meta("pic")
	var tag = HudTheme.label(left, CLASS_TAG.get(s.cclass, "Horde"), 13, HudTheme.GOLD)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var info = VBoxContainer.new()
	info.custom_minimum_size = Vector2(250, 0)
	info.add_theme_constant_override("separation", 4)
	h.add_child(info)
	_w.name = HudTheme.label(info, s.name, 20, HudTheme.TEXT, "head")
	var line = HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	info.add_child(line)
	_w.stars = RankStars.new(16.0)
	line.add_child(_w.stars)
	_w.count = HudTheme.label(line, "", 15)
	_w.banner = HudTheme.label(line, "", 12, HudTheme.GOLD)
	_w.hp = _bar(info, HudTheme.HP_GREEN, 16.0)
	_w.hp_text = HudTheme.label(_w.hp, "", 12)
	_w.hp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_w.hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_w.hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_w.xp = _bar(info, HudTheme.XP_GOLD, 6.0)
	_w.state = HudTheme.label(info, "", 13, HudTheme.TEXT_DIM)
	var ups = _row(info)
	_w.upgrades = {}
	for key in GameData.UPGRADES:
		var chip = HudTheme.label(ups, GameData.UPGRADES[key].name, 11)
		chip.tooltip_text = GameData.UPGRADES[key].desc
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		_w.upgrades[key] = chip
	var cmds = VBoxContainer.new()
	cmds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmds.add_theme_constant_override("separation", 3)
	h.add_child(cmds)
	_commands(cmds, [s])


func _commands(parent, list: Array):
	"""Formation, stance, order and reinforce buttons for the selected hordes (shared by all)."""
	_w.formation_btns = {}
	_w.stance_btns = {}
	var forms = []
	for key in GameData.FORMATION_ORDER:
		var ok = true
		for s in list:
			if not key in Formations.available_for(s.cclass, s.spear):
				ok = false
		if ok:
			forms.append(key)
	if forms.size() > 1:
		var row = _row(parent, "Formation")
		for key in forms:
			var d = GameData.FORMATIONS[key]
			_w.formation_btns[key] = _btn(row, d.name, _on_formation.bind(key), d.desc)
	var srow = _row(parent, "Stance")
	for key in GameData.STANCE_ORDER:
		_w.stance_btns[key] = _btn(srow, GameData.STANCES[key].name, _on_stance.bind(key), GameData.STANCES[key].desc)
	var orow = _row(parent, "Orders")
	_btn(orow, "Attack (T)", _on_mode.bind("squad_attack"), "Right-click or T then click an enemy")
	_btn(orow, "Move (X)", _on_mode.bind("squad_defend"), "Move and guard a point")
	_btn(orow, "Hold (N)", _on_order.bind("hold"), "Stand still and fight what comes in range")
	_btn(orow, "Return (J)", _on_order.bind("return"), "Go home to heal")
	_btn(orow, "Follow (G)", _on_order.bind("follow"), "Follow your hero and attack what it attacks")
	var any_reinforce = false
	for s in list:
		any_reinforce = any_reinforce or s.can_reinforce
	if any_reinforce:
		var rrow = _row(parent, "Army")
		_w.reinforce = _btn(rrow, "Reinforce (U)", _on_reinforce, "Refill lost soldiers for Supplies (while standing in your city)")
		_w.auto = _btn(rrow, "Auto-refill", _on_auto, "Refill by itself when idle in your city")


func _on_formation(key):
	_emit({"type": "squad_formation", "squads": ids.duplicate(), "formation": key})


func _on_stance(key):
	_emit({"type": "squad_stance", "squads": ids.duplicate(), "stance": key})


func _on_order(order):
	_emit({"type": "squad_order", "squads": ids.duplicate(), "order": order})


func _on_mode(m):
	mode_requested.emit(m)
	if auto_submit and match_node != null and match_node.hero_controller != null:
		match_node.hero_controller._start_mode(m)


func _on_reinforce():
	_emit({"type": "squad_reinforce", "squads": ids.duplicate(), "mode": "now"})


func _on_auto():
	var all = _summaries()
	var want = true
	for id in ids:
		var s = _by_id(all, id)
		if s != null and s.auto:
			want = false
	_emit({"type": "squad_reinforce", "squads": ids.duplicate(), "mode": "toggle", "enabled": want})


func _emit(cmd: Dictionary):
	command_requested.emit(cmd)
	if auto_submit and match_node != null and _local_player() != null:
		cmd["player"] = _local_player().slot_index
		CommandBus.submit(cmd)


# --- several hordes -------------------------------------------------------------------------------------------------
func _build_multi(list: Array):
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	_root.add_child(h)
	var left = VBoxContainer.new()
	left.custom_minimum_size = Vector2(430, 0)
	h.add_child(left)
	_w.title = HudTheme.label(left, "", 16, HudTheme.GOLD, "head")
	var grid = GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	left.add_child(grid)
	_w.cards = {}
	for s in list:
		var card = Button.new()
		card.focus_mode = Control.FOCUS_NONE
		card.custom_minimum_size = Vector2(50, 62)
		card.tooltip_text = "%s\nClick: select only this horde. Shift-click: remove it." % s.name
		card.pressed.connect(_on_card.bind(s.id))
		var box = VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 1)
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_child(box)
		var pf = _portrait(_portrait_for(s), 36.0)
		pf.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(pf)
		var bar = _bar(box, HudTheme.HP_GREEN, 5.0, 40.0)
		bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var n = HudTheme.label(box, "", 11)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pf.get_meta("pic").texture = _portrait_for(s)
		grid.add_child(card)
		_w.cards[s.id] = [bar, n]
	var cmds = VBoxContainer.new()
	cmds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmds.add_theme_constant_override("separation", 3)
	h.add_child(cmds)
	_commands(cmds, list)


func _on_card(id):
	var shift = Input.is_key_pressed(KEY_SHIFT)
	squad_clicked.emit(id, shift)
	if auto_submit and match_node != null and match_node.hero_controller != null:
		if shift:
			match_node.hero_controller.remove_squad(id)
		else:
			match_node.hero_controller.narrow_to(id)


# --- a building ----------------------------------------------------------------------------------------------------------
func _build_building(b):
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	_root.add_child(h)
	var pf = _portrait(Icons.art("buildings", b.building_key), 96.0)
	h.add_child(pf)
	var info = VBoxContainer.new()
	info.custom_minimum_size = Vector2(260, 0)
	info.add_theme_constant_override("separation", 4)
	h.add_child(info)
	_w.name = HudTheme.label(info, b.display_name, 20, HudTheme.TEXT, "head")
	_w.hp = _bar(info, HudTheme.HP_GREEN, 16.0)
	_w.hp_text = HudTheme.label(_w.hp, "", 12)
	_w.hp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_w.hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_w.hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_w.progress = _bar(info, HudTheme.MANA_BLUE, 10.0)
	_w.state = HudTheme.label(info, "", 13, HudTheme.TEXT_DIM)
	var cmds = VBoxContainer.new()
	cmds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmds.add_theme_constant_override("separation", 4)
	h.add_child(cmds)
	if not b.is_constructed():
		_btn(cmds, "Cancel construction (75% refund)", func(): _emit({"type": "cancel_build", "target": b.net_id}))
		return
	if b.trains != "":
		var st = b.squad_stats()
		var row = _row(cmds)
		_w.train = _btn(row, "Train %s" % st.name, _on_train, "%s\nCosts %d Supplies (%d soldiers)" % [st.name, GameData.price(b.squad_cost()), st.squad_size])
		_w.auto_repeat = _btn(row, "Auto-repeat", _on_auto_repeat, "Train a horde now and then by itself and send it to the march target")
		var mrow = _row(cmds, "March to")
		_w.lane = OptionButton.new()
		_w.lane.focus_mode = Control.FOCUS_NONE
		_w.lane.add_theme_font_size_override("font_size", 13)
		_w.lane.add_item("Rally here", 0)
		_w.lane.set_item_metadata(0, -1)
		var p = _local_player()
		if match_node != null and p != null:
			var i = 1
			for lane in match_node.lanes_for_player(p):
				_w.lane.add_item(match_node.lane_label(lane.index, p), i)
				_w.lane.set_item_metadata(i, lane.index)
				i += 1
		_w.lane.item_selected.connect(_on_lane)
		mrow.add_child(_w.lane)
		_w.queue = HudTheme.label(cmds, "", 13)
		_w.queue_bar = _bar(cmds, HudTheme.XP_GOLD, 8.0)
	if b.building_key == "blacksmith":
		var urow = _row(cmds, "Research")
		_w.research = {}
		for key in GameData.UPGRADES:
			var u = GameData.UPGRADES[key]
			_w.research[key] = _btn(urow, u.name, _on_research.bind(key), "%s\nCosts %d Supplies" % [u.desc, GameData.price(u.cost)])


func _on_train():
	if building != null and is_instance_valid(building):
		_emit({"type": "train", "building": building.net_id})


func _on_auto_repeat():
	if building != null and is_instance_valid(building):
		_emit({"type": "set_auto_repeat", "building": building.net_id, "enabled": not building.auto_repeat, "lane": building.lane})


func _on_lane(idx):
	if building != null and is_instance_valid(building):
		var lane = _w.lane.get_item_metadata(idx)
		_emit({"type": "set_auto_repeat", "building": building.net_id, "enabled": building.auto_repeat, "lane": lane})


func _on_research(key):
	_emit({"type": "research", "upgrade": key})


# --- per-frame -------------------------------------------------------------------------------------------------------------
func _process(delta):
	if match_node != null and match_node.hero_controller != null:
		var hc = match_node.hero_controller
		var key = "%s|%s" % [str(hc.selected_squads), str(hc.selected_building.get_instance_id() if hc.selected_building != null and is_instance_valid(hc.selected_building) else 0)]
		if key != _last_sel:
			_last_sel = key
			set_selection(hc.selected_squads, hc.selected_building)
	refresh()
	if bubbles != null:
		var shown = []
		var all = _summaries()
		for id in ids:
			var s = _by_id(all, id)
			if s != null:
				shown.append(s)
		bubbles.update(shown)


func refresh():
	var live = _rebuild_if_needed()
	match mode:
		"single":
			_refresh_single(live[0])
		"multi":
			_refresh_multi(live)
		"building":
			_refresh_building()


func _mark(btn: Button, active: bool, enabled = true):
	btn.modulate = ACTIVE if active else Color.WHITE
	btn.disabled = not enabled


func _refresh_single(s):
	_w.name.text = s.name
	_w.stars.rank = s.rank
	_w.count.text = "Soldiers %d/%d" % [s.count, s.max]
	_w.banner.text = "Banner" if s.banner != 0 else ""
	_w.hp.max_value = maxf(1.0, s.hp_max)
	_w.hp.value = s.hp_sum
	_w.hp_text.text = _hp_text(s)
	var rank_lo = GameData.RANK_XP[s.rank - 1]
	_w.xp.max_value = maxf(1.0, s.xp_next - rank_lo)
	_w.xp.value = s.xp - rank_lo if s.rank < GameData.RANK_XP.size() else _w.xp.max_value
	_w.state.text = "%s    Rank %d" % [SquadronScript.STATE_NAMES[s.state], s.rank]
	var ups = _upgrades()
	for key in _w.upgrades:
		_w.upgrades[key].modulate = ACTIVE if ups.get(key, false) else Color(1, 1, 1, 0.3)
	_refresh_commands([s])


func _refresh_commands(list: Array):
	var ups = _upgrades()
	for key in _w.formation_btns:
		var all_use = true
		var why = ""
		for s in list:
			var need = GameData.FORMATIONS[key].get("needs", "")
			if need != "" and not ups.get(need, false):
				all_use = false
				why = GameData.UPGRADES[need].name
		var b = _w.formation_btns[key]
		_mark(b, _all(list, "formation", key), all_use)
		b.tooltip_text = GameData.FORMATIONS[key].desc + ("\nNeeds %s" % why if why != "" else "")
	for key in _w.stance_btns:
		_mark(_w.stance_btns[key], _all(list, "stance", key))
	if _w.has("auto"):
		var on = true
		for s in list:
			on = on and s.auto
		_w.auto.modulate = ACTIVE if on else Color.WHITE
		_w.auto.text = "Auto-refill: %s" % ("on" if on else "off")
		var hurt = false
		for s in list:
			hurt = hurt or s.count < s.max
		_w.reinforce.disabled = not hurt


func _all(list: Array, field: String, value) -> bool:
	for s in list:
		if s[field] != value:
			return false
	return not list.is_empty()


func _refresh_multi(list: Array):
	var soldiers = 0
	for s in list:
		soldiers += s.count
		var c = _w.cards.get(s.id)
		if c != null:
			c[0].max_value = maxf(1.0, s.hp_max)
			c[0].value = s.hp_sum
			c[1].text = "%d/%d" % [s.count, s.max]
	_w.title.text = "%d hordes, %d soldiers" % [list.size(), soldiers]
	_refresh_commands(list)


func _refresh_building():
	var b = building
	_w.name.text = b.display_name
	_w.hp.max_value = maxf(1.0, b.hp_max)
	_w.hp.value = b.hp
	_w.hp_text.text = "%d / %d" % [b.hp, b.hp_max]
	if not b.is_constructed():
		_w.progress.visible = true
		_w.progress.max_value = 1.0
		_w.progress.value = b.progress
		_w.state.text = "Under construction: %d%%" % int(b.progress * 100)
		return
	_w.progress.visible = false
	_w.state.text = ""
	if b.building_key == "storehouse":
		_w.state.text = "Access point. If destroyed you lose half your stockpile."
	elif b.building_key == "town_center":
		_w.state.text = "Access point, Age advances, hero respawn."
	if _w.has("train"):
		var p = _local_player()
		_w.train.disabled = p != null and not p.has_resources(b.squad_cost())
		_mark(_w.auto_repeat, b.auto_repeat)
		var queued = b.manual_pending
		_w.queue.text = "Queued: %d" % queued if queued > 0 else ("Auto-repeat: next in %ds" % ceili(b.cycle_left) if b.auto_repeat else "Idle")
		_w.queue_bar.max_value = GameData.MANUAL_TRAIN_TIME if queued > 0 else GameData.AUTO_REPEAT_INTERVAL
		_w.queue_bar.value = (GameData.MANUAL_TRAIN_TIME - b.manual_left) if queued > 0 else (GameData.AUTO_REPEAT_INTERVAL - b.cycle_left if b.auto_repeat else 0.0)
		for i in range(_w.lane.item_count):
			if _w.lane.get_item_metadata(i) == b.lane and _w.lane.selected != i:
				_w.lane.select(i)
	if _w.has("research"):
		var ups = _upgrades()
		var p2 = _local_player()
		for key in _w.research:
			var u = GameData.UPGRADES[key]
			var done = ups.get(key, false)
			var btn = _w.research[key]
			btn.disabled = done or b.research_key != "" or (p2 != null and (u.age > p2.age or not p2.has_resources(u.cost)))
			btn.modulate = ACTIVE if done or b.research_key == key else Color.WHITE
