extends "res://source/lotr/hud/widgets/TipArea.gd"
## HP / mana bar of the champion panel: gradient fill, a tick every 100 (HP) so you can read
## the bar in hit points, a white "recently lost" trail, an optional shield segment, a
## "991 / 1483" label in the middle and the regeneration ("+2.7") at the right end.

const HudTheme = preload("res://source/lotr/hud/widgets/HudTheme.gd")

var fill_top = HudTheme.HP_GREEN.lightened(0.25)
var fill_bottom = HudTheme.HP_GREEN_DARK
var tick_every = 100.0
var font_size = 15
var cur = 0.0
var maxv = 1.0
var shield = 0.0
var regen_text = ""
var regen_color = Color("b8e8c0")
var _trail = 0.0
var _trail_wait = 0.0
var _last_cur = -1.0


func set_values(c: float, m: float, regen = "", shield_amount = 0.0):
	m = maxf(1.0, m)
	c = clampf(c, 0.0, m)
	if c < _last_cur:
		_trail_wait = 0.45
	_last_cur = c
	if c != cur or m != maxv or regen != regen_text or shield_amount != shield:
		cur = c
		maxv = m
		regen_text = regen
		shield = shield_amount
		queue_redraw()
	if _trail < cur:
		_trail = cur


func _process(delta):
	if _trail > cur:
		if _trail_wait > 0.0:
			_trail_wait -= delta
		else:
			_trail = maxf(cur, _trail - maxv * 0.5 * delta)
		queue_redraw()


func _draw():
	var r = Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.02, 0.02, 0.03, 0.96))
	var inner = r.grow(-2)
	var w = inner.size.x
	var f = cur / maxv
	if _trail > cur:
		draw_rect(Rect2(inner.position, Vector2(w * (_trail / maxv), inner.size.y)), Color(1, 1, 1, 0.55))
	var fw = w * f
	if fw > 0.5:
		var half = inner.size.y * 0.5
		draw_rect(Rect2(inner.position, Vector2(fw, half)), fill_top)
		draw_rect(Rect2(inner.position + Vector2(0, half), Vector2(fw, inner.size.y - half)), fill_bottom)
		draw_line(inner.position + Vector2(0, 0.5), inner.position + Vector2(fw, 0.5), Color(1, 1, 1, 0.28), 1.0)
	if shield > 0.0:
		var sw = minf(w - fw, w * shield / maxv)
		draw_rect(Rect2(inner.position + Vector2(fw, 0), Vector2(sw, inner.size.y)), Color(0.9, 0.92, 0.95, 0.9))
	if tick_every > 0.0:
		var step = tick_every
		while maxv / step > w / 5.0:
			step *= 5.0
		var n = int(maxv / step)
		for i in range(1, n + 1):
			var x = inner.position.x + w * (i * step / maxv)
			if x >= inner.end.x - 1:
				break
			var big = int(i * step) % 1000 == 0
			draw_line(Vector2(x, inner.position.y + (0 if big else inner.size.y * 0.55)), Vector2(x, inner.end.y), Color(0, 0, 0, 0.75 if big else 0.55), 1.0)
	draw_rect(r, Color("6e5a30"), false, 1.0)
	draw_rect(r.grow(-1), Color(0, 0, 0, 0.7), false, 1.0)
	var font = HudTheme.font("bold")
	var text = "%d / %d" % [int(ceil(cur)), int(maxv)]
	var ts = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos = Vector2((size.x - ts.x) / 2.0, (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.9))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, HudTheme.TEXT)
	if regen_text != "":
		var rs = font.get_string_size(regen_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 3)
		var rp = Vector2(size.x - rs.x - 5, pos.y)
		draw_string_outline(font, rp, regen_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 3, 3, Color(0, 0, 0, 0.9))
		draw_string(font, rp, regen_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 3, regen_color)
