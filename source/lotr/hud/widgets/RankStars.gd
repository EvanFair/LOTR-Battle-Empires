extends Control
## Three small stars for a horde's rank (BFME veterancy): lit up to `rank`, dark outline for the rest.

const GOLD = Color("f4d060")
const DARK = Color(0.12, 0.1, 0.07, 0.85)

var rank = 1:
	set(value):
		if value != rank:
			rank = value
			queue_redraw()
var star_size = 14.0:
	set(value):
		star_size = value
		custom_minimum_size = Vector2(star_size * 3.0, star_size)
		queue_redraw()


func _init(a_size = 14.0):
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	star_size = a_size


func _draw():
	for i in range(3):
		var c = Vector2(star_size * (i + 0.5), star_size * 0.52)
		var pts = PackedVector2Array()
		for k in range(10):
			var r = star_size * (0.48 if k % 2 == 0 else 0.2)
			var a = -PI / 2.0 + k * PI / 5.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		if i < rank:
			draw_colored_polygon(pts, GOLD)
		else:
			draw_colored_polygon(pts, DARK)
		pts.append(pts[0])
		draw_polyline(pts, Color(0.35, 0.26, 0.08, 0.9), 1.0)
