class_name DotBuff
extends Buff
## Damage over time: `value` damage every tick_rate seconds, through the full damage pipeline
## (source_kind DOT, never lifesteals).

var damage_type = 1  # Combat.MAGIC


func _init(per_tick = 10.0, seconds = 4.0, tick = 1.0, dmg_type = 1):
	key = "dot"
	type = Buff.DOT
	negative = true
	value = per_tick
	duration = seconds
	tick_rate = tick
	damage_type = dmg_type
	add_type = Buff.AddType.REPLACE_EXISTING
	_apply_info()


func on_tick(_dt):
	if host == null or not is_instance_valid(host) or not host.is_alive():
		return
	var src = source if source != null and is_instance_valid(source) else null
	Combat.deal_damage(src, host, value, damage_type, Combat.DOT, ["no_lifesteal"])
