extends "res://source/lotr/hud/widgets/TipArea.gd"
## One action slot of the champion panel (ability, item or recall). Frame art from the UI kit,
## the icon inside its window, a radial cooldown sweep with seconds, mana cost, key badge,
## rank pips, a gold "+" learn button, a blue "not enough mana" overlay and a dark
## "unavailable" overlay.

signal pressed
signal learn_pressed

const HudTheme = preload("res://source/lotr/hud/widgets/HudTheme.gd")
const Sweep = preload("res://source/lotr/hud/widgets/CooldownSweep.gd")

# source rectangles (px of the cut-out PNGs) and the icon window inside them, normalised
const FRAMES = {
	"slot": {"tex": "slot", "region": Rect2(36, 33, 184, 177), "window": Rect2(0.158, 0.147, 0.693, 0.712)},
	"item": {"tex": "slot_item", "region": Rect2(30, 27, 197, 198), "window": Rect2(0.162, 0.162, 0.665, 0.672)},
	"ult": {"tex": "slot_ult", "region": Rect2(0, 0, 224, 256), "window": Rect2(0.223, 0.3125, 0.558, 0.469)},
}

var frame_kind = "slot"
var key_text = ""
var max_rank = 0  # >0 draws rank pips
var rank = 0
var glow = false

var _frame = null
var _icon = null
var _sweep = null
var _low = null
var _dark = null
var _cd_label = null
var _cost_label = null
var _key_label = null
var _count_label = null
var _learn = null
var _window = Rect2()
var _hover = false
var _last = {}


## `window_px` is the side of the icon window in pixels; the frame is sized around it.
func build(kind: String, window_px: float, key: String, pips = 0):
	frame_kind = kind
	key_text = key
	max_rank = pips
	var spec = FRAMES[kind]
	var region: Rect2 = spec.region
	var win: Rect2 = spec.window
	var scale = window_px / (region.size.x * win.size.x)
	custom_minimum_size = region.size * scale
	size = custom_minimum_size
	_window = Rect2(win.position * size, Vector2(win.size.x * size.x, win.size.y * size.y))
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var at = AtlasTexture.new()
	at.atlas = HudTheme.tex(spec.tex)
	at.region = region
	_frame = TextureRect.new()
	_frame.texture = at
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_SCALE
	_place(_icon)
	add_child(_icon)
	_sweep = Sweep.new()
	_place(_sweep)
	_sweep.visible = false
	add_child(_sweep)
	_low = ColorRect.new()
	_low.color = Color(0.05, 0.16, 0.6, 0.5)
	_low.visible = false
	_low.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_low)
	add_child(_low)
	_dark = ColorRect.new()
	_dark.color = Color(0, 0, 0, 0.5)
	_dark.visible = false
	_dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_dark)
	add_child(_dark)
	var big = clampi(int(window_px * 0.42), 14, 26)
	_cd_label = HudTheme.label(self, "", big, Color.WHITE, "head")
	_place(_cd_label)
	_cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cd_label.add_theme_constant_override("outline_size", 5)
	_cd_label.visible = false
	var small = clampi(int(window_px * 0.22), 11, 15)
	_cost_label = HudTheme.label(self, "", small, Color("7fb4ff"), "bold")
	_cost_label.position = _window.position + Vector2(3, 0)
	_count_label = HudTheme.label(self, "", small + 2, Color("ffe9a8"), "bold")
	_count_label.visible = false
	_count_label.position = _window.position + Vector2(_window.size.x - 14, _window.size.y - small - 8)
	# key badge straddling the bottom edge
	if key != "":
		var badge = Panel.new()
		var sb = HudTheme.flat_box(Color(0.03, 0.035, 0.05, 0.96), HudTheme.GOLD_DIM, 1, 3, 0)
		badge.add_theme_stylebox_override("panel", sb)
		var bw = 18.0 if window_px >= 50 else 14.0
		badge.size = Vector2(bw, bw)
		badge.position = Vector2((size.x - bw) / 2.0, size.y - bw * 0.62)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(badge)
		_key_label = HudTheme.label(badge, key, int(bw * 0.72), HudTheme.GOLD_BRIGHT, "head")
		_key_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_key_label.add_theme_constant_override("outline_size", 2)
	if pips > 0:
		_learn = Button.new()
		_learn.text = "+"
		_learn.focus_mode = Control.FOCUS_NONE
		_learn.size = Vector2(24, 24)
		_learn.position = Vector2((size.x - 24) / 2.0, -26)
		_learn.visible = false
		_learn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var gold = HudTheme.flat_box(Color("c8961e"), Color("fff0a0"), 2, 12, 0)
		gold.shadow_color = Color(1, 0.85, 0.3, 0.45)
		gold.shadow_size = 5
		_learn.add_theme_stylebox_override("normal", gold)
		var hover = gold.duplicate()
		hover.bg_color = Color("f0c030")
		_learn.add_theme_stylebox_override("hover", hover)
		_learn.add_theme_stylebox_override("pressed", hover)
		_learn.add_theme_font_override("font", HudTheme.font("head"))
		_learn.add_theme_font_size_override("font_size", 20)
		_learn.add_theme_color_override("font_color", Color("2a1a00"))
		_learn.add_theme_color_override("font_hover_color", Color("2a1a00"))
		_learn.add_theme_color_override("font_outline_color", Color(1, 0.95, 0.7, 0.4))
		_learn.add_theme_constant_override("outline_size", 1)
		_learn.pressed.connect(func(): learn_pressed.emit())
		_learn.tooltip_text = "Learn (Ctrl+%s)" % key
		add_child(_learn)
	mouse_entered.connect(func():
		_hover = true
		queue_redraw())
	mouse_exited.connect(func():
		_hover = false
		queue_redraw())


func _place(c: Control):
	c.position = _window.position
	c.size = _window.size


func _gui_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed.emit()
		accept_event()


func _draw():
	if _hover:
		draw_rect(_window.grow(1), Color(1, 0.92, 0.6, 0.18))
		draw_rect(_window.grow(1), Color(1, 0.92, 0.6, 0.7), false, 1.5)
	if glow:
		var a = 0.5 + 0.4 * sin(Time.get_ticks_msec() / 150.0)
		draw_rect(_window.grow(2), Color(1, 0.9, 0.4, a), false, 2.5)
	if max_rank > 0:
		var d = 5.0
		var gap = 4.0
		var total = max_rank * d * 2 + (max_rank - 1) * gap
		var x0 = (size.x - total) / 2.0 + d
		var y = size.y + 7.0
		for i in range(max_rank):
			var c = Vector2(x0 + i * (d * 2 + gap), y)
			var pts = PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)])
			var lit = i < rank
			draw_colored_polygon(pts, Color("f0d070") if lit else Color(0.08, 0.08, 0.1, 0.95))
			pts.append(pts[0])
			draw_polyline(pts, Color("a8842c") if lit else Color("4a4030"), 1.2, true)


## d: tex, cd_left, cd_total, cost (mana, 0 hides), mana_ok, dim (greyed: dead / not learned),
##    rank, can_learn, count ("" hides), sweep_color (optional), label (overrides the cd text)
func apply(d: Dictionary):
	if _icon == null:
		return
	var t = d.get("tex")
	if t != _last.get("tex"):
		_icon.texture = t
		_sweep.texture_under = t
		_sweep.texture_progress = t
		_icon.visible = t != null
	var cd = d.get("cd_left", 0.0)
	var total = maxf(0.001, d.get("cd_total", 1.0))
	var on_cd = cd > 0.0
	if on_cd:
		_sweep.visible = true
		_sweep.value = 100.0 - clampf(cd / total, 0.0, 1.0) * 100.0
		_sweep.queue_redraw()
		var txt = d.get("label", HudTheme.fmt_time(cd))
		if txt != _cd_label.text:
			_cd_label.text = txt
		_cd_label.visible = true
	else:
		if _sweep.visible:
			_sweep.visible = false
		_cd_label.visible = d.has("label")
		if d.has("label"):
			_cd_label.text = d.label
	var sc = d.get("sweep_color")
	if sc != null:
		_sweep.tint_progress = sc
	var cost = d.get("cost", 0)
	var cost_text = str(cost) if cost > 0 else ""
	if cost_text != _cost_label.text:
		_cost_label.text = cost_text
	var dim = d.get("dim", false)
	var low = cost > 0 and not d.get("mana_ok", true) and not dim
	if low != _low.visible:
		_low.visible = low
	if dim != _dark.visible:
		_dark.visible = dim
	_icon.modulate = Color(0.55, 0.55, 0.6) if dim else Color.WHITE
	var count = d.get("count", "")
	if count != _count_label.text:
		_count_label.text = count
		_count_label.visible = count != ""
	var new_rank = d.get("rank", 0)
	var can_learn = d.get("can_learn", false)
	if _learn != null:
		if can_learn != _learn.visible:
			_learn.visible = can_learn
		if can_learn:
			_learn.modulate = Color(1, 1, 1, 0.8 + 0.2 * sin(Time.get_ticks_msec() / 200.0))
	if new_rank != rank or glow != d.get("glow", false):
		rank = new_rank
		glow = d.get("glow", false)
		queue_redraw()
	elif glow:
		queue_redraw()
	if d.get("frame_modulate") != _last.get("frame_modulate"):
		_frame.modulate = d.get("frame_modulate", Color.WHITE)
	_last = d
