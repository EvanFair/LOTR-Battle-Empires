extends RefCounted
## HUD look: colours, fonts (Cinzel headings/numbers, Alegreya Sans body), the UI-kit textures
## from assets/art/ui (cut out by tools/art/import_ui.py), nine-patch styleboxes and the Theme
## every HUD Control inherits. All static; nothing here needs a node.

const GOLD = Color("c8aa6e")
const GOLD_BRIGHT = Color("f0d890")
const GOLD_DIM = Color("785a28")
const TEXT = Color("f0e6d2")
const TEXT_DIM = Color("a09b8c")
const PLATE = Color(0.035, 0.04, 0.055, 0.94)
const HP_GREEN = Color("2fb84a")
const HP_GREEN_DARK = Color("14602a")
const MANA_BLUE = Color("3c7ae0")
const MANA_BLUE_DARK = Color("163a80")
const XP_GOLD = Color("e8c24a")
const RED = Color("e04848")
const ALLY_BLUE = Color("3b8ee8")
const ENEMY_RED = Color("d83a34")
const CREEP_YELLOW = Color("d8b830")
const PHYSICAL = Color("f08a30")
const MAGIC = Color("5aa8ff")
const TRUE_DMG = Color("ffffff")
const HEAL_GREEN = Color("5ee07a")
const CC_PURPLE = Color("b07ae8")

const FONT_DIR = "res://assets/fonts/"
const UI_DIR = "res://assets/art/ui/"
const STATUS_DIR = "res://assets/art/status/"

static var _cache = {}
static var _fonts = {}


# --- textures -------------------------------------------------------------------------------------
static func tex(name: String) -> Texture2D:
	"""assets/art/ui/<name>.png; falls back to reading the file when it isn't imported yet."""
	return _load_png(UI_DIR + name + ".png")


static func status_tex(name: String) -> Texture2D:
	return _load_png(STATUS_DIR + name + ".png")


static func _load_png(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var t = null
	if ResourceLoader.exists(path):
		t = load(path)
	elif FileAccess.file_exists(path):
		var img = Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null:
			t = ImageTexture.create_from_image(img)
	_cache[path] = t
	return t


static func scaled_tex(name: String, scale: float, region = null) -> Texture2D:
	"""A downscaled (optionally cropped) copy of a UI texture, so nine-patch margins can be
	small on screen while the source art stays big."""
	var key = "%s@%s@%s" % [name, scale, str(region)]
	if _cache.has(key):
		return _cache[key]
	var base = tex(name)
	var result = null
	if base != null:
		var img = base.get_image()
		if img != null:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			if region != null:
				img = img.get_region(Rect2i(region))
			img.resize(maxi(2, int(img.get_width() * scale)), maxi(2, int(img.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
			result = ImageTexture.create_from_image(img)
	_cache[key] = result
	return result


# --- fonts ----------------------------------------------------------------------------------------
static func font(kind: String) -> Font:
	"""kind: head (Cinzel bold), head_reg (Cinzel), body (Alegreya Sans medium), bold, italic."""
	if _fonts.has(kind):
		return _fonts[kind]
	var f = null
	match kind:
		"head", "head_reg":
			var base = _font_file("Cinzel-Variable.ttf")
			if base != null:
				var v = FontVariation.new()
				v.base_font = base
				var tag = TextServerManager.get_primary_interface().name_to_tag("weight")
				v.variation_opentype = {tag: 700 if kind == "head" else 500}
				f = v
		"body":
			f = _font_file("AlegreyaSans-Medium.ttf")
		"bold":
			f = _font_file("AlegreyaSans-Bold.ttf")
		"italic":
			f = _font_file("AlegreyaSans-Italic.ttf")
	if f == null:
		f = ThemeDB.fallback_font
	_fonts[kind] = f
	return f


static func _font_file(file: String):
	var path = FONT_DIR + file
	if ResourceLoader.exists(path):
		return load(path)
	if FileAccess.file_exists(path):
		var ff = FontFile.new()
		ff.load_dynamic_font(ProjectSettings.globalize_path(path))
		return ff
	return null


# --- styleboxes -----------------------------------------------------------------------------------
static func texture_box(name: String, scale: float, margin: float, region = null, content = 8.0) -> StyleBoxTexture:
	var sb = StyleBoxTexture.new()
	sb.texture = scaled_tex(name, scale, region)
	sb.set_texture_margin_all(margin)
	sb.set_content_margin_all(content)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return sb


static func panel_box(content = 12.0) -> StyleBox:
	"""The bronze frame around a dark window (UI05), used for side panels."""
	if tex("slot_item") == null:
		return flat_box(PLATE, GOLD_DIM, 2, 4, content)
	return texture_box("slot_item", 0.5, 16, Rect2(30, 27, 197, 198), content)


static func plate_box() -> StyleBox:
	"""Slimmer bronze frame (UI05) used as the base under the champion panel."""
	if tex("slot_item") == null:
		return flat_box(PLATE, GOLD_DIM, 2, 4, 6)
	return texture_box("slot_item", 0.42, 14, Rect2(30, 27, 197, 198), 6)


static func flat_box(color: Color, border: Color, border_w = 1, radius = 3, content = 6.0) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(content)
	return s


static func tooltip_box() -> StyleBoxFlat:
	var s = flat_box(Color(0.03, 0.035, 0.05, 0.97), GOLD, 2, 3, 10.0)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 6
	s.border_color = Color("8f7646")
	return s


static func button_box(state: String) -> StyleBox:
	var name = {"normal": "tab_normal", "hover": "tab_hover", "pressed": "tab_selected", "disabled": "tab_normal", "focus": "tab_hover"}.get(state, "tab_normal")
	if tex(name) == null:
		return flat_box(Color(0.15, 0.13, 0.1), GOLD_DIM, 1, 3, 6)
	var sb = texture_box(name, 0.4, 14, null, 6)
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	if state == "disabled":
		sb.modulate_color = Color(0.55, 0.55, 0.55, 0.8)
	return sb


# --- the Theme ------------------------------------------------------------------------------------
static var _theme = null


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t = Theme.new()
	t.default_font = font("body")
	t.default_font_size = 17
	var outline = Color(0.02, 0.02, 0.03, 0.95)
	for cls in ["Label", "Button", "CheckBox", "OptionButton", "TabContainer", "TabBar", "RichTextLabel", "LinkButton"]:
		t.set_color("font_outline_color", cls, outline)
		t.set_constant("outline_size", cls, 3)
		t.set_font("font", cls, font("body"))
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("font_outline_color", "RichTextLabel", outline)
	t.set_constant("outline_size", "RichTextLabel", 3)
	t.set_font("normal_font", "RichTextLabel", font("body"))
	t.set_font("bold_font", "RichTextLabel", font("bold"))
	t.set_font("italics_font", "RichTextLabel", font("italic"))
	t.set_color("font_color", "Label", TEXT)
	# buttons
	t.set_stylebox("normal", "Button", button_box("normal"))
	t.set_stylebox("hover", "Button", button_box("hover"))
	t.set_stylebox("pressed", "Button", button_box("pressed"))
	t.set_stylebox("disabled", "Button", button_box("disabled"))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", GOLD_BRIGHT)
	t.set_color("font_pressed_color", "Button", GOLD_BRIGHT)
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.52, 0.47))
	t.set_font("font", "Button", font("bold"))
	t.set_font_size("font_size", "Button", 16)
	t.set_constant("h_separation", "Button", 6)
	# option button reuses the button look
	for state in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(state, "OptionButton", button_box(state))
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_color("font_hover_color", "OptionButton", GOLD_BRIGHT)
	t.set_font("font", "OptionButton", font("bold"))
	# panels
	t.set_stylebox("panel", "PanelContainer", panel_box(10))
	t.set_stylebox("panel", "PopupPanel", flat_box(PLATE, GOLD_DIM, 2, 3, 6))
	t.set_stylebox("panel", "PopupMenu", flat_box(PLATE, GOLD_DIM, 2, 3, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", GOLD_BRIGHT)
	t.set_stylebox("hover", "PopupMenu", flat_box(Color(0.25, 0.2, 0.1, 0.9), Color(0, 0, 0, 0), 0, 2, 2))
	# tabs
	t.set_stylebox("panel", "TabContainer", flat_box(Color(0.02, 0.025, 0.035, 0.6), Color(0, 0, 0, 0), 0, 0, 4))
	t.set_stylebox("tab_selected", "TabContainer", button_box("pressed"))
	t.set_stylebox("tab_unselected", "TabContainer", button_box("normal"))
	t.set_stylebox("tab_hovered", "TabContainer", button_box("hover"))
	t.set_stylebox("tab_disabled", "TabContainer", button_box("disabled"))
	t.set_color("font_selected_color", "TabContainer", GOLD_BRIGHT)
	t.set_color("font_unselected_color", "TabContainer", TEXT)
	t.set_color("font_hovered_color", "TabContainer", GOLD_BRIGHT)
	t.set_font("font", "TabContainer", font("bold"))
	t.set_font_size("font_size", "TabContainer", 15)
	# check boxes read as text
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_font("font", "CheckBox", font("body"))
	# progress bars
	t.set_stylebox("background", "ProgressBar", flat_box(Color(0.02, 0.02, 0.03, 0.9), Color("5a4a2a"), 1, 2, 0))
	t.set_stylebox("fill", "ProgressBar", flat_box(GOLD, Color(0, 0, 0, 0), 0, 2, 0))
	# scroll bars slimmer
	t.set_constant("separation", "VBoxContainer", 4)
	t.set_constant("separation", "HBoxContainer", 6)
	t.set_stylebox("separator", "HSeparator", flat_box(Color(GOLD_DIM, 0.6), Color(0, 0, 0, 0), 0, 0, 0))
	t.set_constant("separation", "HSeparator", 6)
	t.set_stylebox("panel", "TooltipPanel", tooltip_box())
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 16)
	_theme = t
	return t


# --- little draw helpers --------------------------------------------------------------------------
static func ring_texture(diameter: int, thickness: float) -> Texture2D:
	"""A white antialiased ring (for radial progress bars)."""
	var key = "ring%d_%s" % [diameter, thickness]
	if _cache.has(key):
		return _cache[key]
	var img = Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var c = (diameter - 1) / 2.0
	var r_out = diameter / 2.0
	var r_in = r_out - thickness
	for y in range(diameter):
		for x in range(diameter):
			var d = Vector2(x - c, y - c).length()
			var a = clampf(r_out - d, 0.0, 1.0) * clampf(d - r_in, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var t = ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


static func circle_mask_material(feather = 0.03) -> ShaderMaterial:
	"""Clips a TextureRect to a circle."""
	if not _cache.has("circle_shader"):
		var sh = Shader.new()
		sh.code = "shader_type canvas_item;\nuniform float feather = 0.03;\nuniform float gray = 0.0;\nuniform vec4 tint : source_color = vec4(1.0);\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV) * tint;\n\tfloat l = dot(c.rgb, vec3(0.299, 0.587, 0.114));\n\tc.rgb = mix(c.rgb, vec3(l), gray);\n\tfloat d = distance(UV, vec2(0.5));\n\tc.a *= 1.0 - smoothstep(0.5 - feather, 0.5, d);\n\tCOLOR = c;\n}\n"
		_cache["circle_shader"] = sh
	var m = ShaderMaterial.new()
	m.shader = _cache["circle_shader"]
	m.set_shader_parameter("feather", feather)
	return m


static func fmt_time(seconds: float) -> String:
	if seconds < 1.0:
		return "%.1f" % maxf(0.0, seconds)
	if seconds <= 60.0:
		return str(ceili(seconds))
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]


static func label(parent, text = "", size = 16, color = TEXT, kind = "body") -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.95))
	l.add_theme_constant_override("outline_size", 3 if size < 22 else 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(l)
	return l
