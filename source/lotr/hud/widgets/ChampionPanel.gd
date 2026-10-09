extends Control
## B1: the bottom-centre champion panel. Layout (left to right): stats column, round portrait
## with XP ring, QWER slots (radial cooldown, cost, rank pips, "+" learn) over the HP and mana
## bars, the item grid (3x2, four unlocked today) and the B recall slot. Buff row and cast bar
## float above. LotrHud.gd only places this node and calls refresh() every frame.

const HudTheme = preload("res://source/lotr/hud/widgets/HudTheme.gd")
const AbilitySlot = preload("res://source/lotr/hud/widgets/AbilitySlot.gd")
const PortraitFrame = preload("res://source/lotr/hud/widgets/PortraitFrame.gd")
const ResourceBar = preload("res://source/lotr/hud/widgets/ResourceBar.gd")
const StatBlock = preload("res://source/lotr/hud/widgets/StatBlock.gd")
const BuffRow = preload("res://source/lotr/hud/widgets/BuffRow.gd")
const CastBar = preload("res://source/lotr/hud/widgets/CastBar.gd")
const TipArea = preload("res://source/lotr/hud/widgets/TipArea.gd")
const Tooltips = preload("res://source/lotr/hud/widgets/Tooltips.gd")

const PANEL_SIZE = Vector2(985, 190)
const ITEM_GRID = 6  # slots drawn; GameData.ITEM_SLOTS of them are usable today

var match_node = null
var portrait = null
var stats = null
var buffs = null
var cast_bar = null
var hp_bar = null
var mana_bar = null
var slots = {}  # "Q".. -> AbilitySlot
var item_slots = []
var recall_slot = null
var _ability_name = {}  # key -> ability name the tooltip was bound for
var _item_key = {}  # slot index -> item key (or "")


func _init():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE


func build(match_ref):
	match_node = match_ref
	# the wooden plate behind the slots, bars and items
	var plate = Panel.new()
	plate.add_theme_stylebox_override("panel", HudTheme.plate_box())
	plate.position = Vector2(312, 38)
	plate.size = Vector2(PANEL_SIZE.x - 312, 152)
	plate.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(plate)
	# stats plate
	var stat_plate = Panel.new()
	stat_plate.add_theme_stylebox_override("panel", HudTheme.flat_box(Color(0.03, 0.035, 0.05, 0.88), Color("5a4a2a"), 1, 4, 0))
	stat_plate.position = Vector2(0, 92)
	stat_plate.size = Vector2(158, 98)
	stat_plate.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(stat_plate)
	stats = StatBlock.new()
	stats.position = Vector2(6, 98)
	add_child(stats)
	portrait = PortraitFrame.new()
	portrait.build(176)
	portrait.position = Vector2(150, 12)
	add_child(portrait)
	# ability slots
	var x = 344.0
	for key in ["Q", "W", "E", "R"]:
		var s = AbilitySlot.new()
		s.build("ult" if key == "R" else "slot", 57.0 if key != "R" else 56.0, key, GameData.ABILITY_MAX_RANK)
		s.position = Vector2(x, 128.0 - s.size.y)
		x += s.size.x + 7.0
		s.pressed.connect(_on_ability.bind(key))
		s.learn_pressed.connect(_on_learn.bind(key))
		add_child(s)
		slots[key] = s
	var bars_x = 344.0
	var bars_w = x - 7.0 - bars_x
	hp_bar = ResourceBar.new()
	hp_bar.position = Vector2(bars_x, 148)
	hp_bar.size = Vector2(bars_w, 22)
	add_child(hp_bar)
	mana_bar = ResourceBar.new()
	mana_bar.fill_top = HudTheme.MANA_BLUE.lightened(0.3)
	mana_bar.fill_bottom = HudTheme.MANA_BLUE_DARK
	mana_bar.regen_color = Color("b8d0ff")
	mana_bar.tick_every = 0.0
	mana_bar.font_size = 13
	mana_bar.position = Vector2(bars_x, 172)
	mana_bar.size = Vector2(bars_w, 14)
	add_child(mana_bar)
	# items 3x2
	var ix = x + 14.0
	for i in range(ITEM_GRID):
		var s2 = AbilitySlot.new()
		s2.build("item", 39.0, str(i + 5) if i < GameData.ITEM_SLOTS else "")
		s2.position = Vector2(ix + (i % 3) * (s2.size.x + 5), 56 + (i / 3) * (s2.size.y + 5))
		s2.pressed.connect(_on_item.bind(i))
		add_child(s2)
		item_slots.append(s2)
		_item_key[i] = "?"
	var last = item_slots[2]
	recall_slot = AbilitySlot.new()
	recall_slot.build("item", 44.0, "B")
	recall_slot.position = Vector2(last.position.x + last.size.x + 10, 56 + (last.size.y * 2 + 5 - recall_slot.size.y) / 2.0)
	recall_slot.pressed.connect(_on_recall)
	recall_slot.tip = _recall_tip
	add_child(recall_slot)
	buffs = BuffRow.new()
	buffs.position = Vector2(bars_x, -16)
	add_child(buffs)
	cast_bar = CastBar.new()
	cast_bar.size = Vector2(300, 20)
	cast_bar.position = Vector2(bars_x + (bars_w - 300) / 2.0, -46)
	add_child(cast_bar)
	hp_bar.tip = _bar_tip.bind("hp")
	mana_bar.tip = _bar_tip.bind("mana")


func _hero():
	var p = match_node.local_player
	return p.hero if p != null and p.hero != null and is_instance_valid(p.hero) else null


func _hc():
	return match_node.hero_controller


func _on_ability(key):
	if _hc() != null:
		_hc().arm_ability(key)


func _on_learn(key):
	if _hc() != null:
		_hc().learn_ability(key)


func _on_item(slot):
	if _hc() != null:
		_hc().use_item(slot)


func _on_recall():
	var p = match_node.local_player
	if p != null:
		CommandBus.submit({"type": "recall", "player": p.slot_index})


func _recall_tip():
	return Tooltips.make("Recall", "[B]", "[color=#8fa0b8]Channel:[/color] %d s\n\n[color=#c8c0b0]Return to your Town Center. Moving, casting or taking damage cancels it.\nInside your base, B opens the base panel instead.[/color]" % int(_hero_recall_time()), 280.0)


func _hero_recall_time():
	var h = _hero()
	return h.RECALL_TIME if h != null else 6.0


func _bar_tip(which):
	var h = _hero()
	if h == null:
		return null
	if which == "hp":
		return Tooltips.make("Health", "%d / %d" % [int(h.hp), int(h.hp_max)], "[color=#c8c0b0]Each tick on the bar is 100 health.\nAt your Town Center you recover quickly.[/color]", 260.0, HudTheme.HEAL_GREEN)
	return Tooltips.make("Mana", "%d / %d" % [int(h.mana), int(h.mana_max)], "[color=#c8c0b0]Abilities cost mana. Regenerates %.1f per second.[/color]" % h.mana_regen, 260.0, HudTheme.MANA_BLUE.lightened(0.3))


func refresh():
	var h = _hero()
	visible = h != null
	if h == null:
		return
	var now = GameData.now()
	var dead = h.dead
	portrait.apply(h)
	stats.update_from(h)
	buffs.update_from(h)
	# --- abilities
	for key in slots:
		var s = slots[key]
		var a = h.ability(key)
		if a == null:
			s.apply({"dim": true})
			continue
		var rank = h.ability_rank(key)
		var live = GameData.ability_at_rank(a, maxi(1, rank))
		s.apply({
			"tex": Icons.ability(a), "cd_left": h.cooldown_left(key) if rank > 0 else 0.0,
			"cd_total": live.cooldown, "cost": a.mana, "mana_ok": h.mana >= a.mana,
			"dim": dead or rank < 1, "rank": rank, "can_learn": (not dead) and h.can_learn(key) == "",
		})
		if _ability_name.get(key) != a.name:
			_ability_name[key] = a.name
			s.tip = _ability_tip.bind(key)
	# --- items
	for i in range(item_slots.size()):
		var s2 = item_slots[i]
		var usable_slot = i < GameData.ITEM_SLOTS
		if i >= h.items.size():
			s2.apply({"frame_modulate": Color.WHITE if usable_slot else Color(1, 1, 1, 0.4)})
			if _item_key[i] != "":
				_item_key[i] = ""
				s2.tip = _empty_item_tip.bind(usable_slot)
			continue
		var it = h.items[i]
		var data = GameData.ITEMS[it.key]
		var wait = maxf(0.0, it.ready_at - now)
		s2.apply({
			"tex": Icons.item(it.key), "cd_left": wait,
			"cd_total": data.active.cooldown if data.has("active") else 1.0,
			"dim": dead and (data.get("consumable", false) or data.has("active")),
		})
		if _item_key[i] != it.key:
			_item_key[i] = it.key
			s2.tip = _item_tip.bind(i)
	# --- recall
	var left = h.recall_left()
	recall_slot.apply({
		"tex": HudTheme.status_tex("recall"), "cd_left": left, "cd_total": h.RECALL_TIME,
		"dim": dead, "sweep_color": Color(0.5, 0.8, 1.0),
	})
	if left > 0.0:
		cast_bar.set_cast("Recall", 1.0 - left / h.RECALL_TIME, left)
	else:
		cast_bar.clear()
	# --- bars
	var hp_regen = h.get("hp_regen")
	hp_bar.set_values(0.0 if dead else float(h.hp), float(h.hp_max), ("+%.1f" % hp_regen) if hp_regen != null and hp_regen > 0.0 else "", float(h.get("shield") if h.get("shield") != null else 0.0))
	mana_bar.set_values(float(h.mana), float(h.mana_max), "+%.1f" % h.mana_regen)


func _ability_tip(key):
	var h = _hero()
	var a = h.ability(key) if h != null else null
	if a == null:
		return null
	return Tooltips.ability(h, a)


func _item_tip(slot):
	var h = _hero()
	if h == null or slot >= h.items.size():
		return null
	return Tooltips.item(h.items[slot].key, slot)


func _empty_item_tip(usable):
	if usable:
		return Tooltips.make("Empty item slot", "", "[color=#c8c0b0]Buy items at the Shop tab of the base panel (B at home).[/color]", 260.0)
	return Tooltips.make("Locked slot", "", "[color=#c8c0b0]Heroes will carry six items; this slot is not unlocked yet.[/color]", 260.0)
