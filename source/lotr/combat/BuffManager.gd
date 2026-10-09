class_name BuffManager
extends RefCounted
## Owns every Buff of one unit. Adapted from League-of-Jinx engine/buffs/buff_manager.gd
## (BuffAddType semantics, slots per key + source, dispel by type) with the crowd-control
## rules of the v4 plan (A5) added in add():
##   - invulnerable / unstoppable / cc_immune units ignore crowd control; buildings too
##   - tenacity shortens stun, root, slow, fear and charm (not knock-ups)
##   - heroes only: diminishing returns, the same CC type inside 6 s lasts 100% / 50% / 25%, then 3 s immune
##   - a new hard CC (stun, fear, taunt, charm, knock-up) overwrites the old one
##   - a root keeps the longer of the old and the new time
##   - slows: one entry per source (a slot per source); only the strongest applies (Stats.add_slow)
##
## The host drives process(delta) from its physics tick and calls apply_stats() while rebuilding Stats.

var host = null
var slots = {}  # "key#source_id" -> BuffSlot
var active = []  # every Buff (running or queued)
var net_list = []  # client puppets: [[key, stacks, until, duration]] from the host's slow state
var _dr = {}  # cc type bit -> [count, window_end, immune_until]
var _in_hook = 0


func _init(h = null):
	host = h


static func _slot_key(key: String, sid: int) -> String:
	return "%s#%d" % [key, sid]


func is_empty() -> bool:
	return active.is_empty()


# --- adding -------------------------------------------------------------------------------------------
func add(buff, source = null, new_duration = -1.0, number_of_stacks = 1):
	"""Apply `buff` (a fresh instance) to the host. new_duration < 0 keeps the buff's own duration.
	Returns the Buff now in effect (an existing renewed one for RENEW_EXISTING) or null if the
	host is dead or immune."""
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return null
	if host.get("puppet") == true or host.hp == null or host.hp <= 0:
		return null
	buff.host = host
	buff.source = source
	if new_duration >= 0.0:
		buff.duration = new_duration
	var is_cc = buff.negative and (buff.type & Buff.CC_MASK) != 0
	if is_cc and not _admit_cc(buff):
		return null
	if buff.negative:
		Combat.note_credit(source, host)
	if (buff.type & Buff.HARD_CC) != 0 and buff.negative:
		_remove_matching(Buff.HARD_CC, true)
	elif (buff.type & Buff.ROOT) != 0 and buff.negative:
		var longest = null
		for b in active:
			if (b.type & Buff.ROOT) != 0 and b.negative and (longest == null or b.time_left() > longest.time_left()):
				longest = b
		if longest != null:
			if longest.time_left() >= buff.duration:
				return longest  # the old root already outlasts it
			_remove_matching(Buff.ROOT, true)
	buff.renew()
	var sid = buff.source_id() if buff.stacks_exclusive else 0
	var sk = _slot_key(buff.key, sid)
	var slot = slots.get(sk)
	if slot == null:
		slot = BuffSlot.new(self, buff.key, sid)
		slots[sk] = slot
	buff.slot = slot
	var n = clampi(number_of_stacks, 1, maxi(1, buff.max_stack))
	var result = buff
	var structural = true  # false when an existing buff was only renewed (nothing to rebuild)
	match buff.add_type:
		Buff.AddType.REPLACE_EXISTING, Buff.AddType.STACKS_AND_OVERLAPS:
			_drop_stacks(slot, maxi(0, slot.stacks.size() + n - buff.max_stack))
			_add_stacks(slot, buff, n, false)
		Buff.AddType.RENEW_EXISTING:
			if slot.stacks.size() > 0:
				slot.renew_all(buff.duration, buff)
				result = slot.stacks[0]
				structural = n > slot.stacks.size()
				if structural:
					_add_stacks(slot, buff, n - slot.stacks.size(), false)
			else:
				_add_stacks(slot, buff, n, false)
		Buff.AddType.STACKS_AND_RENEWS:
			_drop_stacks(slot, maxi(0, slot.stacks.size() + n - buff.max_stack))
			_add_stacks(slot, buff, n, false)
			slot.renew_all(buff.duration)
		Buff.AddType.STACKS_AND_CONTINUE:
			_drop_stacks(slot, maxi(0, slot.stacks.size() + n - buff.max_stack))
			_add_stacks(slot, buff, n, true)
	if structural:
		_changed()
	return result


func _admit_cc(buff) -> bool:
	if host.get("unit_kind") == "building":
		return false
	var st = host.status
	if st.invulnerable or st.unstoppable or st.cc_immune:
		return false
	var d = buff.duration
	if d <= 0.0:
		return true
	if (buff.type & Buff.TENACITY_MASK) != 0:
		d *= 1.0 - host.stats.tenacity
	var bit = buff.type & Buff.DR_MASK
	if bit != 0 and host.get("unit_kind") == "hero":
		bit = bit & -bit  # the first CC type the buff carries
		var now = GameData.now()
		var s = _dr.get(bit)
		if s == null:
			s = [0, 0.0, 0.0]
			_dr[bit] = s
		if now < s[2]:
			return false  # immune after three of the same
		if s[0] >= GameData.CC_DR_STEPS.size() or now >= s[1]:
			s[0] = 0
		d *= GameData.CC_DR_STEPS[s[0]]
		s[0] += 1
		s[1] = now + GameData.CC_DR_WINDOW
		if s[0] >= GameData.CC_DR_STEPS.size():
			s[2] = now + GameData.CC_DR_IMMUNE
	if d < 0.05:
		return false
	buff.duration = d
	return true


func dr_state(cc_bit: int) -> Array:
	return _dr.get(cc_bit, [0, 0.0, 0.0])


func _add_stacks(slot, buff, n: int, queued: bool):
	for i in range(n):
		var b = buff if i == 0 else buff.clone()
		b.host = host
		b.source = buff.source
		b.slot = slot
		b.removed = false
		b.active = false
		b.renew()
		b.delay = slot.queue_time() if queued else 0.0
		slot.stacks.append(b)
		active.append(b)
		if b.delay <= 0.0:
			_activate(b)


func _activate(b):
	b.active = true
	b._tick_left = b.tick_rate if b.tick_rate > 0.0 else 0.0
	b.on_activate()


func _drop_stacks(slot, count: int):
	if count <= 0 or slot.stacks.is_empty():
		return
	slot.sort_stacks()
	for i in range(mini(count, slot.stacks.size())):
		_remove_internal(slot.stacks[slot.stacks.size() - 1], false)


# --- removing -----------------------------------------------------------------------------------------
func remove_buff(b):
	if b == null or b.removed:
		return
	_remove_internal(b, false)
	_changed()


func _remove_internal(b, expired: bool):
	if b.removed:
		return
	b.removed = true
	b.expired = expired
	var slot = b.slot
	if slot != null:
		slot.stacks.erase(b)
		if not expired:
			# queued stacks behind it move up
			var gap = b.remaining if b.active else b.duration
			for s in slot.stacks:
				if s.delay > 0.0 and (b.active or s.delay > b.delay):
					s.delay = maxf(0.0, s.delay - gap)
		if slot.stacks.is_empty():
			slots.erase(_slot_key(slot.key, slot.source_id))
	active.erase(b)
	if b.active:
		b.active = false
		b.on_deactivate(expired)


func _remove_matching(mask: int, only_negative: bool) -> int:
	var removed = 0
	for b in active.duplicate():
		if (b.type & mask) != 0 and (b.negative or not only_negative):
			_remove_internal(b, false)
			removed += 1
	return removed


func cleanse(mask = Buff.ALL) -> int:
	"""Remove negative buffs whose type matches `mask` (Buff.STUN | Buff.ROOT ..., default all).
	Non-dispellable ones stay. Returns how many were removed."""
	var removed = 0
	for b in active.duplicate():
		if b.negative and not b.non_dispellable and (b.type & mask) != 0:
			_remove_internal(b, false)
			removed += 1
	if removed > 0:
		_changed()
	return removed


func remove_by_type(mask: int) -> int:
	"""Dispel by type regardless of sign (LoJ remove_by_type)."""
	var removed = _remove_matching(mask, false)
	if removed > 0:
		_changed()
	return removed


func remove_by_key(key: String, source = null) -> int:
	var removed = 0
	var sid = source.get_instance_id() if source != null and is_instance_valid(source) else -1
	for b in active.duplicate():
		if b.key == key and (sid == -1 or b.source_id() == sid):
			_remove_internal(b, false)
			removed += 1
	if removed > 0:
		_changed()
	return removed


func clear_all(include_persistent = false):
	var any = false
	for b in active.duplicate():
		if include_persistent or not b.persists_through_death:
			_remove_internal(b, false)
			any = true
	_dr.clear()
	if any:
		_changed()


# --- per-frame ----------------------------------------------------------------------------------------
func process(dt: float):
	if active.is_empty():
		return
	var changed = false
	for b in active.duplicate():
		if b.removed:
			continue
		if not b.active:
			b.delay -= dt
			if b.delay <= 0.0:
				var over = b.delay  # time already spent past the queue point
				b.delay = 0.0
				b.renew()
				if b.remaining != INF:
					b.remaining += over
				_activate(b)
				changed = true
			continue
		if b.remaining != INF:
			b.remaining -= dt
		if b.tick_rate > 0.0:
			b._tick_left -= dt
			var guard = 0
			while b._tick_left <= 0.0 and guard < 8 and not b.removed:
				b._tick_left += b.tick_rate
				guard += 1
				b.on_tick(b.tick_rate)
		elif b.tick_rate < 0.0:
			b.on_tick(dt)
		if b.removed:
			changed = true
			continue
		if b.remaining <= 0.0:
			_remove_internal(b, true)
			changed = true
	if changed:
		_changed()


func _changed():
	if host == null or not is_instance_valid(host):
		return
	rebuild_status()
	if host.has_method("rebuild_stats"):
		host.rebuild_stats()


func rebuild_status():
	var st = host.status
	st.reset()
	for b in active:
		if b.active:
			b.on_update_status(st)
	st.finish()
	if host.has_method("_status_changed"):
		host._status_changed()


func apply_stats(stats):
	"""Feed every active buff's on_update_stats into the temp layer (called by the host's rebuild)."""
	for b in active:
		if b.active:
			b.on_update_stats(stats)


# --- hooks fired by Combat ------------------------------------------------------------------------------
func fire_before_damage(ctx):
	for b in active.duplicate():
		if b.active and not b.removed:
			b.on_before_damage_taken(ctx)


func fire_damage_dealt(ctx):
	for b in active.duplicate():
		if b.active and not b.removed:
			b.on_damage_dealt(ctx)


func fire_hit(ctx):
	for b in active.duplicate():
		if b.active and not b.removed:
			b.on_hit(ctx)


func fire_kill(victim, ctx):
	for b in active.duplicate():
		if b.active and not b.removed:
			b.on_kill(victim, ctx)


func fire_death(ctx):
	for b in active.duplicate():
		if b.active and not b.removed:
			b.on_death(ctx)


func fire_cast(ability_key):
	for b in active.duplicate():
		if b.active and not b.removed:
			b.on_cast(ability_key)


# --- shields and healing ------------------------------------------------------------------------------
func shield_total() -> float:
	var total = 0.0
	for b in active:
		if b.active and (b.type & Buff.SHIELD) != 0:
			total += b.value
	return total


func absorb(amount: float) -> float:
	"""Soak up to `amount` damage: the shield that expires first drains first. Returns how much."""
	if amount <= 0.0 or active.is_empty():
		return 0.0
	var shields = []
	for b in active:
		if b.active and (b.type & Buff.SHIELD) != 0 and b.value > 0.0:
			shields.append(b)
	if shields.is_empty():
		return 0.0
	shields.sort_custom(_expires_first)
	var absorbed = 0.0
	var depleted = false
	for s in shields:
		var take = minf(s.value, amount - absorbed)
		s.value -= take
		absorbed += take
		if s.value <= 0.01:
			s.value = 0.0
			_remove_internal(s, false)
			depleted = true
		if absorbed >= amount - 0.0001:
			break
	if depleted:
		_changed()
	return absorbed


static func _expires_first(a, b) -> bool:
	return a.time_left() < b.time_left()


func heal_mod() -> float:
	"""Multiplier on healing received (grievous wounds: the strongest one applies)."""
	var m = 1.0
	for b in active:
		if b.active and (b.type & Buff.GRIEVOUS) != 0:
			m = minf(m, 1.0 - clampf(b.value, 0.0, 1.0))
	return m


# --- queries --------------------------------------------------------------------------------------------
func has_type(mask: int) -> bool:
	for b in active:
		if b.active and (b.type & mask) != 0:
			return true
	return false


func has_key(key: String) -> bool:
	for b in active:
		if b.key == key and b.active:
			return true
	return false


func get_buff(key: String, source = null):
	"""The first active stack with this key (from `source`, if given)."""
	var sid = source.get_instance_id() if source != null and is_instance_valid(source) else -1
	for b in active:
		if b.key == key and b.active and (sid == -1 or b.source_id() == sid):
			return b
	return null


func count(key: String, source = null) -> int:
	var sid = source.get_instance_id() if source != null and is_instance_valid(source) else -1
	var n = 0
	for b in active:
		if b.key == key and (sid == -1 or b.source_id() == sid):
			n += 1
	return n


func remaining(key: String) -> float:
	var t = 0.0
	for b in active:
		if b.key == key and b.active:
			t = maxf(t, b.remaining)
	return t


func longest_remaining(mask: int) -> float:
	var t = 0.0
	for b in active:
		if b.active and (b.type & mask) != 0 and b.remaining != INF:
			t = maxf(t, b.remaining)
	return t


func list() -> Array:
	"""For the HUD: [{key, icon, title, tooltip, stacks, remaining, duration, negative}], one per key.
	On a client puppet this is built from what the host replicated."""
	var out = []
	if host != null and host.get("puppet") == true:
		var now = GameData.now()
		for e in net_list:
			var info = Buff.info_for(e[0])
			out.append({
				"key": e[0], "icon": info[0], "title": info[1], "tooltip": info[3], "stacks": e[1],
				"remaining": maxf(0.0, e[2] - now), "duration": e[3], "negative": info[2],
			})
		return out
	var by_key = {}
	for b in active:
		if not b.active or b.hidden:
			continue
		var e = by_key.get(b.key)
		if e == null:
			by_key[b.key] = {
				"key": b.key, "icon": b.icon, "title": b.title, "tooltip": b.tooltip, "stacks": 1,
				"remaining": b.remaining, "duration": b.duration, "negative": b.negative,
			}
		else:
			e.stacks += 1
			e.remaining = maxf(e.remaining, b.remaining)
			e.duration = maxf(e.duration, b.duration)
	return by_key.values()


func to_net() -> Array:
	"""Compact list for the 2 Hz slow state: [[key, stacks, remaining, duration], ...]."""
	var out = []
	for e in list():
		if e.remaining == INF:
			e.remaining = 9999.0
		if e.duration <= 0.0:
			e.duration = 9999.0
		out.append([e.key, e.stacks, snappedf(e.remaining, 0.1), snappedf(e.duration, 0.1)])
	return out


func set_net(list_from_host: Array):
	var now = GameData.now()
	net_list = list_from_host.map(func(e): return [e[0], e[1], now + e[2], e[3]])
