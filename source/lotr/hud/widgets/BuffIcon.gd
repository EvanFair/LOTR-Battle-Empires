extends "res://source/lotr/hud/widgets/TipArea.gd"
## One buff / debuff icon (after League-of-Jinx ui_buff.gd): the status art, a radial timer that
## drains clockwise, a stack count, green border for buffs and red for debuffs.

const HudTheme = preload("res://source/lotr/hud/widgets/HudTheme.gd")
const Sweep = preload("res://source/lotr/hud/widgets/CooldownSweep.gd")

var debuff = false
var _sweep = null
var _count = null


func build(px: float):
	custom_minimum_size = Vector2(px, px)
	size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_sweep = Sweep.new()
	_sweep.size = size
	_sweep.line_width = 1.0
	_sweep.tint_under = Color(0.2, 0.2, 0.24)
	_sweep.tint_progress = Color.WHITE
	_sweep.max_value = 100.0
	add_child(_sweep)
	_count = HudTheme.label(self, "", 12, Color.WHITE, "bold")
	_count.position = Vector2(px - 12, px - 17)
	_count.visible = false


func apply(tex: Texture2D, remaining_frac: float, stacks: int, is_debuff: bool):
	if _sweep.texture_progress != tex:
		_sweep.texture_progress = tex
		_sweep.texture_under = tex
	_sweep.value = clampf(remaining_frac, 0.0, 1.0) * 100.0
	_sweep.queue_redraw()
	var t = str(stacks) if stacks > 1 else ""
	if t != _count.text:
		_count.text = t
		_count.visible = t != ""
	if is_debuff != debuff:
		debuff = is_debuff
		queue_redraw()


func _draw():
	draw_rect(Rect2(Vector2.ZERO, size), Color("d84a42") if debuff else Color("58c86a"), false, 2.0)
	draw_rect(Rect2(Vector2.ZERO, size).grow(1), Color(0, 0, 0, 0.8), false, 1.0)
