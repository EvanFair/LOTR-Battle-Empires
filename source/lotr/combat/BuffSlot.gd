class_name BuffSlot
extends RefCounted
## All stacks of one buff key from one source (or from nobody, when the buff has
## stacks_exclusive = false). Adapted from League-of-Jinx engine/buffs/buff_slot.gd.

var mngr = null
var key = ""
var source_id = 0
var stacks = []  # Buff instances, each one stack


func _init(manager = null, buff_key = "", source = 0):
	mngr = manager
	key = buff_key
	source_id = source


func sort_stacks():
	"""Longest remaining first, so the shortest ones are dropped first."""
	stacks.sort_custom(_longer_first)


static func _longer_first(a, b) -> bool:
	return a.time_left() > b.time_left()


func queue_time() -> float:
	"""When the last stack of this slot ends (the delay for a STACKS_AND_CONTINUE add)."""
	var t = 0.0
	for b in stacks:
		t = maxf(t, b.time_left())
	return t


func renew_all(new_duration: float, incoming = null):
	for b in stacks:
		if incoming != null:
			b.on_refresh(incoming)
		if not b.active and b.delay > 0.0:
			continue
		b.renew(new_duration)
