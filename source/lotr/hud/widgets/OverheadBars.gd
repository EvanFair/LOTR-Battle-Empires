extends Control
## B7 over-head bars. Heroes: name, level box, HP bar with a tick per 100 HP, mana sliver, CC
## text; you green, allies blue, enemies red. Buildings: a wide bar (with construction %).
## Everything for heroes and buildings is drawn here in one _draw (a handful of units); troops
## and creatures keep the cheap 3D bar of the base project (shown when selected or hurt) and are
## only recoloured once, when first seen, so 200 units cost nothing per frame.

const HudTheme = preload("res://source/lotr/hud/widgets/HudTheme.gd")

const HERO_W = 140.0
const HERO_H = 12.0
const MANA_H = 4.0
const ALWAYS_SHOW = ["town_center"]

var match_node = null
var _seen = {}  # instance id -> true (3D bars already recoloured)
var _bar_height = {}  # instance id -> bar height above the unit (from its 3D bar)
var _scan_left = 0.0
var _heroes = []
var _buildings = []
var _me = null


func _init():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta):
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = 0.5
		_scan()
	queue_redraw()


func _relation_color(u) -> Color:
	if _me == null or u.player == null:
		return HudTheme.CREEP_YELLOW
	if u.player == _me:
		return HudTheme.HP_GREEN
	if Teams.is_ally(u.player, _me):
		return HudTheme.ALLY_BLUE
	return HudTheme.ENEMY_RED


func _scan():
	_me = match_node.local_player if match_node != null else null
	_heroes = get_tree().get_nodes_in_group("heroes")
	_buildings = get_tree().get_nodes_in_group("buildings")
	for id in _seen.keys():
		if not is_instance_id_valid(id):
			_seen.erase(id)
			_bar_height.erase(id)
	for u in get_tree().get_nodes_in_group("units"):
		var id = u.get_instance_id()
		if _seen.has(id):
			continue
		_seen[id] = true
		var bar = u.find_child("HealthBar", false, false)
		if bar == null:
			continue
		var kind = u.get("unit_kind")
		_bar_height[id] = bar.position.y
		var sprite = bar.get_node_or_null("ActualBar")
		if sprite == null:
			continue
		if kind == "hero" or kind == "building":
			sprite.visible = false  # drawn here instead
			continue
		var col = HudTheme.CREEP_YELLOW if kind == "creature" else _relation_color(u)
		if kind == "villager":
			col = col.darkened(0.15)
		var grad = sprite.texture.gradient if sprite.texture != null else null
		if grad != null:
			grad.set_color(0, col)
			grad.set_color(1, Color(0.07, 0.07, 0.09))
		if kind == "troop" or kind == "creature" or kind == "villager":
			bar.size = Vector2(84, 7)


func _to_local_pos(world: Vector3, cam) -> Variant:
	if cam.is_position_behind(world):
		return null
	return get_global_transform_with_canvas().affine_inverse() * cam.unproject_position(world)


func _draw():
	var cam = get_viewport().get_camera_3d()
	if cam == null or match_node == null:
		return
	var rect = Rect2(Vector2.ZERO, size).grow(80)
	for b in _buildings:
		if not is_instance_valid(b) or not b.is_inside_tree() or not b.visible:
			continue
		var constructed = b.is_constructed()
		var damaged = b.hp != null and b.hp_max != null and b.hp < b.hp_max
		if constructed and not damaged and not (b.building_key in ALWAYS_SHOW):
			continue
		if not b.is_alive():
			continue
		var p = _to_local_pos(b.global_position + Vector3(0, _bar_height.get(b.get_instance_id(), 3.0), 0), cam)
		if p == null or not rect.has_point(p):
			continue
		_draw_building(b, p, constructed)
	for h in _heroes:
		if not is_instance_valid(h) or not h.is_inside_tree() or not h.is_visible_in_tree() or h.dead:
			continue
		var p2 = _to_local_pos(h.global_position + Vector3(0, _bar_height.get(h.get_instance_id(), 2.8) + 0.2, 0), cam)
		if p2 == null or not rect.has_point(p2):
			continue
		_draw_hero(h, p2)


func _draw_hero(h, p: Vector2):
	var col = _relation_color(h)
	var x0 = p.x - HERO_W / 2.0
	var top = p.y
	var total_h = HERO_H + MANA_H + 1.0
	# level box on the left
	var box = Rect2(x0 - 24.0, top - 1.0, 22.0, total_h + 2.0)
	draw_rect(box, Color(0.02, 0.02, 0.03, 0.92))
	draw_rect(box, HudTheme.GOLD_DIM, false, 1.5)
	var f = HudTheme.font("head")
	var lv = str(h.level)
	var lw = f.get_string_size(lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var ly = box.position.y + (box.size.y + f.get_ascent(13) - f.get_descent(13)) / 2.0
	draw_string_outline(f, Vector2(box.position.x + (box.size.x - lw) / 2.0, ly), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color(0, 0, 0, 0.9))
	draw_string(f, Vector2(box.position.x + (box.size.x - lw) / 2.0, ly), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, HudTheme.GOLD_BRIGHT)
	# hp bar
	var hp_rect = Rect2(x0, top, HERO_W, HERO_H)
	draw_rect(hp_rect.grow(1.5), Color(0.0, 0.0, 0.0, 0.88))
	draw_rect(hp_rect, Color(0.1, 0.1, 0.12))
	var frac = clampf(float(h.hp) / maxf(1.0, float(h.hp_max)), 0.0, 1.0)
	if frac > 0.0:
		draw_rect(Rect2(x0, top, HERO_W * frac, HERO_H * 0.5), col.lightened(0.28))
		draw_rect(Rect2(x0, top + HERO_H * 0.5, HERO_W * frac, HERO_H * 0.5), col.darkened(0.25))
	var hp_max = float(h.hp_max)
	var step = 100.0
	while hp_max / step > HERO_W / 4.0:
		step *= 2.0
	var n = int(hp_max / step)
	for i in range(1, n + 1):
		var tx = x0 + HERO_W * (i * step / hp_max)
		if tx >= x0 + HERO_W - 1.0:
			break
		var big = int(i * step) % 1000 == 0
		draw_line(Vector2(tx, top + (0.0 if big else HERO_H * 0.45)), Vector2(tx, top + HERO_H), Color(0, 0, 0, 0.8), 1.0)
	# mana sliver
	var mana_rect = Rect2(x0, top + HERO_H + 1.0, HERO_W, MANA_H)
	draw_rect(mana_rect.grow(1.0), Color(0, 0, 0, 0.88))
	draw_rect(mana_rect, Color(0.05, 0.07, 0.14))
	var mf = clampf(h.mana / maxf(1.0, h.mana_max), 0.0, 1.0)
	draw_rect(Rect2(mana_rect.position, Vector2(HERO_W * mf, MANA_H)), HudTheme.MANA_BLUE)
	# name (and a CC flash) above
	var name_font = HudTheme.font("head")
	var name_y = top - 6.0
	var nw = name_font.get_string_size(h.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string_outline(name_font, Vector2(p.x - nw / 2.0, name_y), h.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(0, 0, 0, 0.95))
	draw_string(name_font, Vector2(p.x - nw / 2.0, name_y), h.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(HudTheme.TEXT).lerp(col, 0.25))
	var cc = ""
	if h.is_stunned():
		cc = "Stunned"
	elif h.rooted_until > GameData.now():
		cc = "Rooted"
	if cc != "":
		var cw = name_font.get_string_size(cc, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var pulse = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 90.0)
		draw_string_outline(name_font, Vector2(p.x - cw / 2.0, name_y - 17.0), cc, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.95))
		draw_string(name_font, Vector2(p.x - cw / 2.0, name_y - 17.0), cc, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(HudTheme.CC_PURPLE.lightened(0.3), pulse))


func _draw_building(b, p: Vector2, constructed: bool):
	var w = 112.0 if b.building_key in ALWAYS_SHOW else 84.0
	var h = 9.0
	var col = HudTheme.CREEP_YELLOW
	if _me != null and b.player != null:
		col = HudTheme.ALLY_BLUE if Teams.is_ally(b.player, _me) else HudTheme.ENEMY_RED
	var rect = Rect2(p.x - w / 2.0, p.y, w, h)
	draw_rect(rect.grow(1.5), Color(0, 0, 0, 0.88))
	draw_rect(rect, Color(0.1, 0.1, 0.12))
	var frac = clampf(float(b.hp) / maxf(1.0, float(b.hp_max)), 0.0, 1.0)
	if not constructed:
		frac = clampf(b.progress, 0.0, 1.0)
		col = HudTheme.XP_GOLD
	if frac > 0.0:
		draw_rect(Rect2(rect.position, Vector2(w * frac, h * 0.5)), col.lightened(0.28))
		draw_rect(Rect2(rect.position + Vector2(0, h * 0.5), Vector2(w * frac, h * 0.5)), col.darkened(0.25))
	var hp_max = float(b.hp_max)
	var step = 250.0
	while hp_max / step > w / 6.0:
		step *= 2.0
	for i in range(1, int(hp_max / step) + 1):
		var tx = rect.position.x + w * (i * step / hp_max)
		if tx >= rect.end.x - 1.0:
			break
		draw_line(Vector2(tx, rect.position.y + h * 0.5), Vector2(tx, rect.end.y), Color(0, 0, 0, 0.7), 1.0)
	draw_rect(rect, HudTheme.GOLD_DIM, false, 1.0)
	if not constructed:
		var t = "Building %d%%" % int(b.progress * 100.0)
		var f = HudTheme.font("bold")
		var tw = f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string_outline(f, Vector2(p.x - tw / 2.0, rect.position.y - 4.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.95))
		draw_string(f, Vector2(p.x - tw / 2.0, rect.position.y - 4.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("ffe9a8"))
