class_name HasteBuff
extends Buff
## Move speed (and optionally attack speed) bonus. The strongest haste on a unit applies.

var attack_speed_pct = 0.0


func _init(pct = 0.3, seconds = 4.0, attack_pct = 0.0, buff_key = "haste"):
	key = buff_key
	type = Buff.HASTE
	negative = false
	value = pct  # 0.3 = +30% move speed
	attack_speed_pct = attack_pct
	duration = seconds
	add_type = Buff.AddType.REPLACE_EXISTING
	_apply_info()


func on_update_stats(stats):
	stats.add_best_mult(Stats.S.MOVE_SPEED, 1.0 + value)
	if attack_speed_pct != 0.0:
		stats.add_best_mult(Stats.S.ATTACK_SPEED, 1.0 + attack_speed_pct)
