extends "res://source/lotr/hud/widgets/TipArea.gd"
## Round hero portrait in the UI16 ring: a radial XP ring, the level on the shield badge, and
## a death state (grey portrait, dark veil, respawn countdown).

const HudTheme = preload("res://source/lotr/hud/widgets/HudTheme.gd")
const Tooltips = preload("res://source/lotr/hud/widgets/Tooltips.gd")

# in the 503x512 frame image: where the portrait circle sits and how big it is
const CENTER = Vector2(252.0, 235.0) / Vector2(503.0, 512.0)
const RADIUS = 158.0 / 503.0
const BADGE = Vector2(252.0, 447.0) / Vector2(503.0, 512.0)

var _portrait = null
var _ring = null
var _frame = null
var _level = null
var _timer = null
var _veil = null
var _hero_key = ""
var _mat = null


func build(width: float):
	var height = width * 512.0 / 503.0
	custom_minimum_size = Vector2(width, height)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	var diameter = RADIUS * 2.0 * width
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.size = Vector2(diameter, diameter)
	_portrait.position = Vector2(CENTER.x * width, CENTER.y * height) - _portrait.size / 2.0
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = HudTheme.circle_mask_material(0.015)
	_portrait.material = _mat
	add_child(_portrait)
	_veil = TextureRect.new()
	_veil.texture = HudTheme.ring_texture(128, 64)  # solid disc (thickness = radius)
	_veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_veil.size = _portrait.size
	_veil.position = _portrait.position
	_veil.modulate = Color(0.05, 0.0, 0.0, 0.62)
	_veil.visible = false
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)
	_ring = TextureProgressBar.new()
	var rd = diameter + 2.0
	_ring.size = Vector2(rd, rd)
	_ring.position = Vector2(CENTER.x * width, CENTER.y * height) - _ring.size / 2.0
	_ring.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	_ring.nine_patch_stretch = true
	_ring.texture_under = HudTheme.ring_texture(192, 6.0)
	_ring.texture_progress = HudTheme.ring_texture(192, 6.0)
	_ring.tint_under = Color(0.0, 0.0, 0.0, 0.55)
	_ring.tint_progress = Color("f4d060")
	_ring.max_value = 1000.0
	_ring.step = 0.0
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ring)
	_frame = TextureRect.new()
	_frame.texture = HudTheme.tex("portrait_frame")
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_frame.size = size
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_level = HudTheme.label(self, "1", int(width * 0.115), HudTheme.GOLD_BRIGHT, "head")
	_level.size = Vector2(width * 0.22, width * 0.14)
	_level.position = Vector2(BADGE.x * width, BADGE.y * height) - _level.size / 2.0 + Vector2(0, -width * 0.015)
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer = HudTheme.label(self, "", int(width * 0.26), Color("ff9a90"), "head")
	_timer.size = Vector2(diameter, diameter)
	_timer.position = _portrait.position
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer.add_theme_constant_override("outline_size", 6)
	_timer.visible = false


func apply(h):
	if h.hero_key != _hero_key:
		_hero_key = h.hero_key
		var t = load("res://assets/art/portraits/%s.png" % _hero_key) if ResourceLoader.exists("res://assets/art/portraits/%s.png" % _hero_key) else null
		_portrait.texture = t
	var lvl = str(h.level)
	if _level.text != lvl:
		_level.text = lvl
	# xp ring
	var xp_table = GameData.XP_PER_LEVEL
	var idx = mini(h.level - 1, xp_table.size() - 1)
	var lo = xp_table[idx]
	var hi = xp_table[mini(h.level, xp_table.size() - 1)]
	var frac = 1.0 if hi <= lo else clampf(float(h.xp - lo) / float(hi - lo), 0.0, 1.0)
	_ring.value = frac * 1000.0
	_mat.set_shader_parameter("gray", 1.0 if h.dead else 0.0)
	if h.dead != _veil.visible:
		_veil.visible = h.dead
		_timer.visible = h.dead
	if h.dead:
		var t2 = str(ceili(maxf(0.0, h.respawn_at - GameData.now())))
		if _timer.text != t2:
			_timer.text = t2
	tip = _tip.bind(h)


func _tip(h):
	if h == null or not is_instance_valid(h):
		return null
	var data = GameData.HEROES[h.hero_key]
	var xp_table = GameData.XP_PER_LEVEL
	var hi = xp_table[mini(h.level, xp_table.size() - 1)]
	var text = "[color=#c8c0b0]%s[/color]\n" % data.get("role", "")
	if h.level >= GameData.HERO_MAX_LEVEL or h.level >= xp_table.size():
		text += "Level %d (max)" % h.level
	else:
		text += "Level %d   [color=#e8c24a]XP %d / %d[/color]" % [h.level, h.xp, hi]
	var pts = h.skill_points()
	if pts > 0:
		text += "\n[color=#e8c24a]%d skill point%s to spend[/color]" % [pts, "" if pts == 1 else "s"]
	return Tooltips.make(h.display_name, "", text, 260.0)
