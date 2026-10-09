class_name ShieldBuff
extends Buff
## Absorbs damage after mitigation. One entry per source; recasting from the same source adds
## its amount, up to 2x one cast (GameData.SHIELD_STACK_CAP), and restarts the timer.
## The shield that expires first drains first (BuffManager.absorb).

var cast_amount = 0.0


func _init(amount = 50.0, seconds = 4.0, buff_key = "shield"):
	key = buff_key
	type = Buff.SHIELD
	negative = false
	value = amount
	cast_amount = amount
	duration = seconds
	add_type = Buff.AddType.RENEW_EXISTING
	_apply_info()


func on_refresh(incoming):
	value = minf(value + incoming.value, cast_amount * GameData.SHIELD_STACK_CAP)
