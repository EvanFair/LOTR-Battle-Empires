extends TextureProgressBar
## Radial cooldown sweep (after League-of-Jinx clock.gd): the icon is both the dark under
## texture and the bright progress texture (clockwise from 12 o'clock); two edge lines mark
## the sweep.

var line_width = 1.5
var line_color = Color(1, 1, 1, 0.85)


func _init():
	fill_mode = TextureProgressBar.FILL_CLOCKWISE
	nine_patch_stretch = true
	step = 0.0
	max_value = 100.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint_under = Color(0.16, 0.18, 0.3, 1.0)
	tint_progress = Color(0.78, 0.82, 1.0, 1.0)


func _draw():
	if value <= 0.0 or value >= max_value:
		return
	var center = size * 0.5
	var length = size.length() * 0.5
	var angle = deg_to_rad(360.0 * (value / max_value) - 90.0)
	# clip the lines to the square by pulling them in
	var up_end = center + Vector2.UP * minf(length, size.y * 0.5)
	var dir = Vector2.from_angle(angle)
	var t = INF
	if absf(dir.x) > 0.0001:
		t = minf(t, (size.x * 0.5) / absf(dir.x))
	if absf(dir.y) > 0.0001:
		t = minf(t, (size.y * 0.5) / absf(dir.y))
	draw_line(center, up_end, line_color, line_width, true)
	draw_line(center, center + dir * t, line_color, line_width, true)
