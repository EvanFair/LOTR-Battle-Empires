extends Control
## A Control that shows a rich LoL-style tooltip above itself while hovered. Set `tip` to a
## Callable returning a Control (see Tooltips.make) or null. The tooltip lives in the HUD root
## (Tooltips.host) so it scales with the HUD and sits above the panel instead of under the
## cursor; it is rebuilt a few times a second so cooldowns and Shift stay live.

const _Tips = preload("res://source/lotr/hud/widgets/Tooltips.gd")

var tip = null
var _tt = null
var _hovered = false
var _refresh_left = 0.0


func _init():
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)


func _on_enter():
	_hovered = true
	_rebuild()
	set_process(true)


func _on_exit():
	_hovered = false
	_clear()


func _exit_tree():
	_clear()


func _clear():
	if _tt != null and is_instance_valid(_tt):
		_tt.queue_free()
	_tt = null


func _process(delta):
	if not _hovered:
		return
	if not is_visible_in_tree():
		_on_exit()
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_rebuild()


func _rebuild():
	_refresh_left = 0.25
	if tip == null or _Tips.host == null or not is_instance_valid(Tooltips.host):
		_clear()
		return
	var t = tip.call()
	var old = _tt
	var old_pos = old.position if old != null and is_instance_valid(old) else null
	_clear()
	if t == null:
		return
	_tt = t
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.z_index = 200
	_Tips.host.add_child(t)
	t.reset_size()
	if old_pos != null:
		t.position = old_pos
		_place_tip()
	else:
		t.modulate.a = 0.0
		await get_tree().process_frame
		_place_tip()
		if is_instance_valid(t):
			t.modulate.a = 1.0


func _place_tip():
	if _tt == null or not is_instance_valid(_tt):
		return
	var host = _Tips.host
	_tt.reset_size()
	var gt = get_global_transform_with_canvas()
	var inv = host.get_global_transform_with_canvas().affine_inverse()
	var top_left = inv * gt.origin
	var s = _tt.size
	var x = top_left.x + size.x / 2.0 - s.x / 2.0
	var y = top_left.y - s.y - 14.0
	if y < 6.0:
		y = top_left.y + size.y + 10.0
	x = clampf(x, 6.0, maxf(6.0, host.size.x - s.x - 6.0))
	_tt.position = Vector2(x, y)
