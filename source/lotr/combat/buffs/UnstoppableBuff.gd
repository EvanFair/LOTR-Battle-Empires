class_name UnstoppableBuff
extends Buff
## Immune to crowd control (and cleanses what is already on); still takes damage.


func _init(seconds = 3.0):
	key = "unstoppable"
	type = Buff.UNSTOPPABLE
	negative = false
	duration = seconds
	add_type = Buff.AddType.REPLACE_EXISTING
	_apply_info()


func on_activate():
	host.bm.cleanse(Buff.CC_MASK)
