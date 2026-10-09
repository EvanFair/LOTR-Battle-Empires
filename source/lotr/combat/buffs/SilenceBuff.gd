class_name SilenceBuff
extends Buff
## Cannot cast abilities; basic attacks and movement still work.


func _init(seconds = 2.0):
	key = "silence"
	type = Buff.SILENCE
	negative = true
	duration = seconds
	add_type = Buff.AddType.REPLACE_EXISTING
	_apply_info()
