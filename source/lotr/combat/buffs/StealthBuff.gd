class_name StealthBuff
extends Buff
## Sets the stealthed flag (vision code decides who can see it). Attacking or casting breaks it.


func _init(seconds = 5.0):
	key = "stealth"
	type = Buff.STEALTH
	negative = false
	duration = seconds
	add_type = Buff.AddType.REPLACE_EXISTING
	_apply_info()


func on_damage_dealt(_ctx):
	remove()


func on_cast(_ability_key):
	remove()
