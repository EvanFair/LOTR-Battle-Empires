extends Control
## The stats column left of the portrait: icon + number per stat, two columns. Hover a stat for
## a breakdown (base from level + items + buffs). Stats the hero doesn't have yet (ability power,
## magic resist, crit, haste: M1) appear automatically once Hero exposes them.

const HudTheme = preload("res://source/lotr/hud/widgets/HudTheme.gd")
const TipArea = preload("res://source/lotr/hud/widgets/TipArea.gd")
const Tooltips = preload("res://source/lotr/hud/widgets/Tooltips.gd")

const COL_W = 74.0
const ROW_H = 27.0

# id, title, property that must exist (or ""), colour
const STATS = [
	["ad", "Attack Damage", "", Color("f0a050")],
	["ap", "Ability Power", "ability_power", Color("78b8ff")],
	["armor", "Armor", "", Color("e8d070")],
	["mr", "Magic Resist", "magic_resist", Color("80d0e8")],
	["as", "Attack Speed", "", Color("f0e090")],
	["ms", "Move Speed", "", Color("a0e0a0")],
	["range", "Attack Range", "", Color("d8d0c0")],
	["regen", "Regeneration", "", Color("78e098")],
	["crit", "Critical Strike", "crit_chance", Color("f06050")],
	["haste", "Ability Haste", "ability_haste", Color("c0a0f0")],
]

var _hero = null
var _rows = {}
var _label = {}


func _init():
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ensure_rows(h):
	var active = []
	for s in STATS:
		if s[2] == "" or s[2] in h:
			active.append(s)
	if active.size() == _rows.size() and _hero == h:
		return
	_hero = h
	for c in get_children():
		c.queue_free()
	_rows.clear()
	_label.clear()
	var i = 0
	for s in active:
		var row = TipArea.new()
		row.custom_minimum_size = Vector2(COL_W, ROW_H)
		row.size = row.custom_minimum_size
		row.position = Vector2((i % 2) * COL_W, (i / 2) * ROW_H)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.draw.connect(_draw_row_icon.bind(row, s[0], s[3]))
		var l = HudTheme.label(row, "", 15, HudTheme.TEXT, "bold")
		l.position = Vector2(24, 2)
		add_child(row)
		row.tip = _tip.bind(s[0])
		_rows[s[0]] = row
		_label[s[0]] = l
		i += 1
	size = Vector2(COL_W * 2, ceil(i / 2.0) * ROW_H)


func update_from(h):
	if h == null:
		return
	_ensure_rows(h)
	for id in _rows:
		var t = _value(h, id)
		var l = _label[id]
		if l.text != t:
			l.text = t


func _hero_speed(h) -> float:
	var base = GameData.HEROES[h.hero_key].speed
	return base * h.speed_mult * (1.0 + h.speed_bonus)


func _attack_speed(h) -> float:
	return h.attack_speed_mult * (1.0 + h.attack_speed_bonus) / maxf(0.1, h.attack_interval)


func _value(h, id) -> String:
	match id:
		"ad":
			return str(int(round(h.attack_damage * h.damage_mult)))
		"ap":
			return str(int(round(h.ability_power)))
		"armor":
			return "%d%%" % int(round(h.armor * 100.0))
		"mr":
			return "%d%%" % int(round(h.magic_resist * 100.0))
		"as":
			return "%.2f" % _attack_speed(h)
		"ms":
			return "%.1f" % _hero_speed(h)
		"range":
			return "%.1f" % h.attack_range
		"regen":
			return "%.1f" % (h.get("hp_regen") if h.get("hp_regen") != null else h.mana_regen)
		"crit":
			return "%d%%" % int(round(h.crit_chance * 100.0))
		"haste":
			return str(int(round(h.ability_haste)))
	return ""


func _tip(id):
	var h = _hero
	if h == null or not is_instance_valid(h):
		return null
	var data = GameData.HEROES[h.hero_key]
	var base = GameData.hero_stats_at_level(h.hero_key, h.level)
	match id:
		"ad":
			var items = h.item_bonus("damage")
			return Tooltips.stat("Attack Damage", _value(h, id), [
				"Damage of each basic attack.",
				"Base (level %d): %d" % [h.level, int(base.damage)],
				"Items: +%d" % int(items),
				"Buffs: x%.2f" % h.damage_mult,
			])
		"armor":
			return Tooltips.stat("Armor", _value(h, id), [
				"Reduces all damage you take.",
				"Items: %d%%" % int(round(h.item_bonus("armor") * 100.0)),
				"Buffs: +%d%%" % int(round((h.armor - h._base_armor) * 100.0)) if h._base_armor >= 0.0 else "",
			])
		"as":
			return Tooltips.stat("Attack Speed", _value(h, id) + " / s", [
				"Basic attacks per second.",
				"Base: %.2f (one every %.2fs)" % [1.0 / data.interval, data.interval],
				"Items: +%d%%" % int(round(h.item_bonus("attack_speed") * 100.0)),
				"Buffs: x%.2f" % h.attack_speed_mult,
			])
		"ms":
			return Tooltips.stat("Move Speed", _value(h, id), [
				"Distance covered per second.",
				"Base: %.1f" % data.speed,
				"Items: +%d%%" % int(round(h.item_bonus("speed") * 100.0)),
				"Buffs and slows: x%.2f" % h.speed_mult,
			])
		"range":
			return Tooltips.stat("Attack Range", _value(h, id), ["How far your basic attacks reach.", "Ranged heroes shoot, others strike in melee."])
		"regen":
			return Tooltips.stat("Regeneration", _value(h, id), [
				"Mana regenerated each second: %.1f" % h.mana_regen,
				"Standing at your Town Center restores health and mana quickly.",
			])
		"ap":
			return Tooltips.stat("Ability Power", _value(h, id), ["Strengthens the magic damage of your abilities."])
		"mr":
			return Tooltips.stat("Magic Resist", _value(h, id), ["Reduces magic damage you take."])
		"crit":
			return Tooltips.stat("Critical Strike", _value(h, id), ["Chance for a basic attack to deal extra damage."])
		"haste":
			return Tooltips.stat("Ability Haste", _value(h, id), ["Shortens your ability cooldowns."])
	return null


func _draw_row_icon(row, id, color):
	var c = Vector2(11, 14)
	var o = Color(0, 0, 0, 0.9)
	match id:
		"ad":
			row.draw_line(Vector2(4, 22), Vector2(17, 6), o, 4.5, true)
			row.draw_line(Vector2(4, 22), Vector2(17, 6), color, 2.5, true)
			row.draw_line(Vector2(5, 15), Vector2(11, 21), o, 4.5, true)
			row.draw_line(Vector2(5, 15), Vector2(11, 21), color.darkened(0.2), 2.5, true)
		"ap", "crit":
			var pts = PackedVector2Array()
			for i in range(10):
				var a = -PI / 2 + i * PI / 5
				pts.append(c + Vector2.from_angle(a) * (9.0 if i % 2 == 0 else 4.0))
			row.draw_colored_polygon(pts, color)
			pts.append(pts[0])
			row.draw_polyline(pts, o, 1.2, true)
		"armor", "mr":
			var pts2 = PackedVector2Array([Vector2(3, 6), Vector2(11, 3), Vector2(19, 6), Vector2(18, 15), Vector2(11, 23), Vector2(4, 15)])
			row.draw_colored_polygon(pts2, color.darkened(0.15))
			var inner = PackedVector2Array([Vector2(6, 8), Vector2(11, 6), Vector2(16, 8), Vector2(15, 14), Vector2(11, 19), Vector2(7, 14)])
			row.draw_colored_polygon(inner, color)
			pts2.append(pts2[0])
			row.draw_polyline(pts2, o, 1.4, true)
		"as":
			var bolt = PackedVector2Array([Vector2(12, 3), Vector2(5, 15), Vector2(10, 15), Vector2(8, 25), Vector2(18, 11), Vector2(12, 11)])
			row.draw_colored_polygon(bolt, color)
			bolt.append(bolt[0])
			row.draw_polyline(bolt, o, 1.2, true)
		"ms":
			for i in range(2):
				var x = 4.0 + i * 7.0
				var chev = PackedVector2Array([Vector2(x, 6), Vector2(x + 6, 14), Vector2(x, 22)])
				row.draw_polyline(chev, o, 5.0, true)
				row.draw_polyline(chev, color, 3.0, true)
		"range":
			row.draw_arc(c + Vector2(0, 0), 7.0, 0, TAU, 20, o, 4.0, true)
			row.draw_arc(c, 7.0, 0, TAU, 20, color, 2.0, true)
			row.draw_line(c + Vector2(-10, 0), c + Vector2(10, 0), color, 1.5, true)
			row.draw_line(c + Vector2(0, -10), c + Vector2(0, 10), color, 1.5, true)
		"regen", "haste":
			row.draw_line(c + Vector2(-7, 0), c + Vector2(7, 0), o, 6.0, true)
			row.draw_line(c + Vector2(0, -7), c + Vector2(0, 7), o, 6.0, true)
			row.draw_line(c + Vector2(-7, 0), c + Vector2(7, 0), color, 3.5, true)
			row.draw_line(c + Vector2(0, -7), c + Vector2(0, 7), color, 3.5, true)
