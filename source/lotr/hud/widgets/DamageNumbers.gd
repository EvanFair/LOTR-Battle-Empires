extends RefCounted
## Floating combat text (B7, after League-of-Jinx font_emitter): Label3D in Cinzel with a thick
## outline that pops, rises and fades. Colours: physical white, magic blue, true grey, damage
## you take red, healing green, gold for last-hit "+N". Numbers that don't involve the local
## player are small and dropped when the screen is already crowded.

const HudTheme = preload("res://source/lotr/hud/widgets/HudTheme.gd")

const COLORS = {
	"physical": Color(1, 1, 1),
	"magic": Color("5aa8ff"),
	"true": Color("c8ccd4"),
	"taken": Color("ff4a40"),
	"heal": Color("5ee07a"),
	"gold": Color("ffd740"),
	"other": Color(1, 1, 1, 0.8),
}
const MAX_LIVE = 40

var host = null  # the Node3D the labels are added to (the match)
var _live = 0


func _init(host_node):
	host = host_node


func damage(at: Vector3, amount: int, kind: String, mine: bool):
	"""kind: physical | magic | true | taken | heal | other"""
	var size = 54 if mine else 34
	if kind == "other" and _live >= MAX_LIVE:
		return
	if kind == "taken":
		size = 60
	_spawn(at + Vector3(randf_range(-0.45, 0.45), 2.3, randf_range(-0.45, 0.45)), str(amount), COLORS.get(kind, Color.WHITE), size, 1.0 if mine else 0.8, 1.1)


func text(at: Vector3, text_value: String, color: Color, size: int):
	_spawn(at + Vector3(0, 2.8, 0), text_value, color, size, 1.0, 1.4)


func _spawn(pos: Vector3, text_value: String, color: Color, size: int, alpha: float, rise: float):
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return
	var label = Label3D.new()
	label.text = text_value
	label.font = HudTheme.font("bold")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	label.fixed_size = false
	label.font_size = size
	label.outline_size = maxi(6, size / 8)
	label.outline_modulate = Color(0.04, 0.03, 0.05, 0.95)
	label.pixel_size = 0.01
	label.modulate = Color(color, alpha * color.a)
	label.render_priority = 3
	label.outline_render_priority = 2
	host.add_child(label)
	label.global_position = pos
	label.scale = Vector3.ONE * 1.5
	_live += 1
	var tween = label.create_tween().set_parallel(true)
	tween.tween_property(label, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "global_position:y", pos.y + rise, 0.95).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.5)
	tween.chain().tween_callback(_done.bind(label))


func _done(label):
	_live = maxi(0, _live - 1)
	if is_instance_valid(label):
		label.queue_free()
