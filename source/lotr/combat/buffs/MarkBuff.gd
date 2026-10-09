class_name MarkBuff
extends Buff
## A mark left by `source`. While it lasts the marker's damage is amplified by `value`
## (0.25 = +25%); with consume_on_hit the mark is spent by the next hit. Spells and passives
## read it with  target.bm.has_key("mark")  /  target.bm.get_buff("mark", marker).

var consume_on_hit = false


func _init(bonus = 0.0, seconds = 5.0, consume = false):
	key = "mark"
	type = Buff.MARK
	negative = true
	value = bonus
	duration = seconds
	consume_on_hit = consume
	add_type = Buff.AddType.RENEW_EXISTING
	_apply_info()


func on_before_damage_taken(ctx):
	if ctx.src != null and source != null and ctx.src == source:
		ctx.amount *= 1.0 + value
		if consume_on_hit:
			remove()
