class_name TauntBuff
extends Buff
## Forced to attack the source. Hard CC.


func _init(seconds = 1.5):
	key = "taunt"
	type = Buff.TAUNT
	negative = true
	duration = seconds
	tick_rate = 0.3
	add_type = Buff.AddType.REPLACE_EXISTING
	_apply_info()


func on_activate():
	on_tick(0.0)


func on_tick(_dt):
	if host != null and is_instance_valid(host) and source != null and is_instance_valid(source) and source.is_alive():
		host.force_attack(source)
