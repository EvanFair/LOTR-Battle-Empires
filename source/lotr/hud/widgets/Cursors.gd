extends RefCounted
## B11: custom mouse cursors cut from the UI15 set (hand, sword, rune, hammer, forbidden).
## HeroController calls update() a few times a second; everything else is cached.

const HudTheme = preload("res://source/lotr/hud/widgets/HudTheme.gd")

const SIZE = 40
# name -> [texture name, hotspot (fraction of the image)]
const SET = {
	"default": ["cursor_hand", Vector2(0.28, 0.02)],
	"attack": ["cursor_sword", Vector2(0.12, 0.04)],
	"ally": ["cursor_hand", Vector2(0.28, 0.02)],
	"cast": ["cursor_cast", Vector2(0.5, 0.5)],
	"build": ["cursor_hammer", Vector2(0.15, 0.1)],
	"forbidden": ["cursor_no", Vector2(0.5, 0.5)],
}

static var _current = ""
static var _textures = {}


static func set_cursor(kind: String):
	if kind == _current:
		return
	_current = kind
	if not SET.has(kind):
		Input.set_custom_mouse_cursor(null)
		return
	var spec = SET[kind]
	if not _textures.has(kind):
		var t = HudTheme.tex(spec[0])
		var img = null
		if t != null:
			img = t.get_image()
			if img != null:
				img = img.duplicate()
				if img.is_compressed():
					img.decompress()
				var k = float(SIZE) / maxf(img.get_width(), img.get_height())
				img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
		_textures[kind] = ImageTexture.create_from_image(img) if img != null else null
	var tex = _textures[kind]
	if tex == null:
		Input.set_custom_mouse_cursor(null)
		return
	var hot = Vector2(tex.get_width() * spec[1].x, tex.get_height() * spec[1].y)
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, hot)


static func reset():
	_current = ""
	Input.set_custom_mouse_cursor(null)


## Picks the cursor for the current situation. `hc` is the HeroController.
static func update(hc):
	var vp = hc.get_viewport()
	var over_ui = false
	if vp.has_method("gui_get_hovered_control"):
		var c = vp.gui_get_hovered_control()
		over_ui = c != null and c.mouse_filter != Control.MOUSE_FILTER_IGNORE
	var kind = "default"
	if over_ui:
		kind = "default"
	elif hc.mode == "cast" or hc.aiming != "":
		kind = "cast"
	elif hc.mode in ["place", "place_wall"]:
		kind = "build"
	elif hc.mode in ["attack_move", "squad_attack"]:
		kind = "attack"
	else:
		var unit = hc._unit_under_mouse()
		var h = hc.hero()
		if unit != null and h != null:
			if h.is_enemy_of(unit):
				kind = "attack"
			elif unit != h and unit.get("player") != null and Teams.is_ally(unit.player, hc.local_player()):
				kind = "ally"
	set_cursor(kind)
