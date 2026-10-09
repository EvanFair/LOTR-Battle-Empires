extends Control
## Cast / channel bar shown above the champion panel while the hero channels Recall (and any
## later channelled ability): gold fill, name on the left, seconds left on the right.

const HudTheme = preload("res://source/lotr/hud/widgets/HudTheme.gd")

var title = ""
var frac = 0.0
var left = 0.0


func _init():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func set_cast(name: String, fraction: float, seconds_left: float):
	title = name
	frac = clampf(fraction, 0.0, 1.0)
	left = seconds_left
	visible = true
	queue_redraw()


func clear():
	visible = false


func _draw():
	var r = Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.02, 0.02, 0.03, 0.92))
	var inner = r.grow(-2)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x * frac, inner.size.y * 0.5)), Color("f0d070"))
	draw_rect(Rect2(inner.position + Vector2(0, inner.size.y * 0.5), Vector2(inner.size.x * frac, inner.size.y * 0.5)), Color("b88a28"))
	draw_rect(r, HudTheme.GOLD_DIM, false, 1.5)
	var font = HudTheme.font("head")
	var fs = 13
	var y = (size.y + font.get_ascent(fs) - font.get_descent(fs)) / 2.0
	draw_string_outline(font, Vector2(8, y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(8, y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	var t = "%.1f" % left
	var ts = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string_outline(font, Vector2(size.x - ts.x - 8, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(size.x - ts.x - 8, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
