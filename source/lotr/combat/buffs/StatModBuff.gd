class_name StatModBuff
extends Buff
## Generic stat buff / debuff: a list of layer changes applied to the temp stat layer while it lasts.
##   StatModBuff.new("mod_damage_up", 8.0).best_mult("attack_damage", 1.25)
##   StatModBuff.new("armor_up", 4.0).flat("armour", 40)
## Kinds: flat, percent, mult (always stacks), best_mult / best_flat (only the strongest buff and the
## strongest debuff of that stat apply, the pre-v4 apply_buff rule). stacks_exclusive is off so two
## sources with the same key share one slot.

var mods = []  # [stat index, kind, amount]


func _init(buff_key = "stat_mod", seconds = 5.0, is_negative = false):
	key = buff_key
	type = 0
	negative = is_negative
	duration = seconds
	add_type = Buff.AddType.REPLACE_EXISTING
	_apply_info()
	if is_negative:
		negative = true


func flat(stat_name: String, amount: float):
	mods.append([Stats.idx(stat_name), "flat", amount])
	return self


func percent(stat_name: String, amount: float):
	mods.append([Stats.idx(stat_name), "percent", amount])
	return self


func mult(stat_name: String, factor: float):
	mods.append([Stats.idx(stat_name), "mult", factor])
	return self


func best_mult(stat_name: String, factor: float):
	mods.append([Stats.idx(stat_name), "best_mult", factor])
	return self


func best_flat(stat_name: String, amount: float):
	mods.append([Stats.idx(stat_name), "best_flat", amount])
	return self


func on_update_stats(stats):
	for m in mods:
		match m[1]:
			"flat":
				stats.add_flat(m[0], m[2])
			"percent":
				stats.add_percent(m[0], m[2])
			"mult":
				stats.add_mult(m[0], m[2])
			"best_mult":
				stats.add_best_mult(m[0], m[2])
			"best_flat":
				stats.add_best_flat(m[0], m[2])
