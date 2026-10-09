class_name CharmBuff
extends Buff
## Forced to walk toward the source and unable to attack or cast. Hard CC.


func _init(seconds = 1.5):
	key = "charm"
	type = Buff.CHARM
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
	if source != null and is_instance_valid(source):
		host._movement.move(source.global_position)


func on_deactivate(_expired):
	if host != null and is_instance_valid(host) and host.has_method("order_stop"):
		host.order_stop()
