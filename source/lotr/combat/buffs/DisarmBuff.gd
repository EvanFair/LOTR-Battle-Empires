class_name DisarmBuff
extends Buff
## Cannot make basic attacks.


func _init(seconds = 2.0):
	key = "disarm"
	type = Buff.DISARM
	negative = true
	duration = seconds
	add_type = Buff.AddType.REPLACE_EXISTING
	_apply_info()
