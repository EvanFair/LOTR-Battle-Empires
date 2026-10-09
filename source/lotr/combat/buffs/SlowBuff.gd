class_name SlowBuff
extends Buff
## Move speed slow. One entry per source (slot per source); only the strongest applies and
## move speed never drops below 30% of base (Stats.finish).


func _init(fraction = 0.3, seconds = 2.0, buff_key = "slow"):
	key = buff_key
	type = Buff.SLOW
	negative = true
	value = fraction  # 0.3 = 30% slower
	duration = seconds
	add_type = Buff.AddType.REPLACE_EXISTING
	_apply_info()


func on_update_stats(stats):
	stats.add_slow(value)
