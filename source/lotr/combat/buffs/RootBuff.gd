class_name RootBuff
extends Buff
## Cannot move or dash, but can still attack and cast. BuffManager keeps the longer of old and new.


func _init(seconds = 1.0):
	key = "root"
	type = Buff.ROOT
	negative = true
	duration = seconds
	add_type = Buff.AddType.REPLACE_EXISTING
	_apply_info()
