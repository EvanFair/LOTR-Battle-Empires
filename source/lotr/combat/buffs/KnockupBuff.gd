class_name KnockupBuff
extends Buff
## Airborne and helpless. Not shortened by tenacity (LoL rule). Hard CC.


func _init(seconds = 0.8):
	key = "knockup"
	type = Buff.KNOCKUP
	negative = true
	duration = seconds
	add_type = Buff.AddType.REPLACE_EXISTING
	_apply_info()
