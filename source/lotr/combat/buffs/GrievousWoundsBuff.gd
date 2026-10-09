class_name GrievousWoundsBuff
extends Buff
## Reduces healing and regeneration received by `value` (0.4 = 40% less). The strongest applies.


func _init(reduction = 0.4, seconds = 3.0):
	key = "grievous"
	type = Buff.GRIEVOUS
	negative = true
	value = reduction
	duration = seconds
	add_type = Buff.AddType.REPLACE_EXISTING
	_apply_info()
