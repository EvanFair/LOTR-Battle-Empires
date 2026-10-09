class_name StunBuff
extends Buff
## Cannot move, attack or cast. Hard CC: a new one overwrites the old.


func _init(seconds = 1.0):
	key = "stun"
	type = Buff.STUN
	negative = true
	duration = seconds
	add_type = Buff.AddType.REPLACE_EXISTING
	_apply_info()
