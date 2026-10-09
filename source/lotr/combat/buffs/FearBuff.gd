class_name FearBuff
extends Buff
## Forced to run away from the source and unable to act. Hard CC.


func _init(seconds = 1.5):
	key = "fear"
	type = Buff.FEAR
	negative = true
	duration = seconds
	tick_rate = 0.4
	add_type = Buff.AddType.REPLACE_EXISTING
	_apply_info()


func on_activate():
	on_tick(0.0)


func on_tick(_dt):
	if host == null or not is_instance_valid(host) or host._movement == null:
		return
	var away = Vector3(randf() - 0.5, 0, randf() - 0.5)
	if source != null and is_instance_valid(source):
		away = host.global_position - source.global_position
		away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else Vector3.RIGHT
	host._movement.move(host.global_position + away * 6.0)


func on_deactivate(_expired):
	if host != null and is_instance_valid(host) and host.has_method("order_stop"):
		host.order_stop()
