extends Node
## Host -> client state replication.
##  - spawn / despawn: reliable RPCs as units appear and die
##  - fast snapshot (10 Hz, unreliable): position, facing, HP and flags of mobile units + effects
##  - slow state (2 Hz, reliable): stockpiles, heroes, buildings, squadrons, resource amounts
## Clients interpolate puppets toward the latest snapshot. Offline, this node does almost nothing.

const FAST_INTERVAL = 0.1
const SLOW_INTERVAL = 0.5
const CLIENT_READY_TIMEOUT = 20.0
const SNAP_DISTANCE = 6.0
const LERP_SPEED = 14.0
const FLAG_HIDDEN = 1
const FLAG_ATTACKING = 2

signal all_clients_ready

var squads = {}  # client mirror: squad id -> summary

var _match = null
var _fast_left = 0.0
var _slow_left = 0.0
var _fx_queue = []
var _targets = {}  # net_id -> [Vector3, yaw]
var _ready_peers = {}
var _resource_amounts_sent = {}
var _heard_from_host = false


func _ready():
	_match = get_parent()
	if not _is_online():
		return
	if not _match.is_host():
		_announce_ready()


func _announce_ready():
	# keep telling the host we're loaded until it starts sending (it may still be loading itself)
	while is_inside_tree() and not _heard_from_host:
		_rpc_client_ready.rpc_id(1)
		await get_tree().create_timer(0.5).timeout


func _is_online():
	return Network.is_online()


# --- start handshake -----------------------------------------------------------------------------
func wait_for_clients():
	"""Host: resolves once every human client has loaded the match (or after a timeout)."""
	if not _is_online():
		return
	var deadline = Time.get_ticks_msec() + int(CLIENT_READY_TIMEOUT * 1000)
	while not _all_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _all_ready():
	for p in _match.players_by_slot.values():
		if p.peer_id > 1 and not _ready_peers.has(p.peer_id):
			return false
	return true


@rpc("any_peer", "reliable")
func _rpc_client_ready():
	_ready_peers[multiplayer.get_remote_sender_id()] = true


# --- host: events ----------------------------------------------------------------------------------
func on_host_spawn(unit):
	if not _is_online() or not _match.is_host():
		return
	var extra = {}
	if unit.get("progress") != null and unit.progress < 1.0:
		extra["under_construction"] = true
	var yaw = unit.global_transform.basis.get_euler().y if unit.is_inside_tree() else 0.0
	_rpc_spawn.rpc(
		unit.net_id, unit.spawn_params, unit.player.slot_index, unit.transform.origin, yaw, extra
	)


func on_host_despawn(net_id):
	if not _is_online() or not _match.is_host():
		return
	_rpc_despawn.rpc(net_id)


func queue_fx(kind, from: Vector3, to: Vector3):
	if not _is_online():
		return
	if _fx_queue.size() < 120:
		_fx_queue.append([kind, from, to])


func send_toast(peer_id: int, text: String):
	if not _is_online() or not _match.is_host():
		return
	if peer_id == 0:
		_rpc_toast.rpc(text)
	else:
		_rpc_toast.rpc_id(peer_id, text)


func send_ping(peer_id: int, pos: Vector3, kind: String, from_slot: int):
	if _is_online() and _match.is_host():
		_rpc_ping.rpc_id(peer_id, pos, kind, from_slot)


func send_match_over(team: int):
	if _is_online() and _match.is_host():
		_rpc_match_over.rpc(team)


# --- host: snapshots -------------------------------------------------------------------------------
func _physics_process(delta):
	if not _is_online():
		return
	if _match.is_host():
		_fast_left -= delta
		if _fast_left <= 0.0:
			_fast_left = FAST_INTERVAL
			_send_fast()
		_slow_left -= delta
		if _slow_left <= 0.0:
			_slow_left = SLOW_INTERVAL
			_send_slow()


# Fast snapshot: 12 bytes per unit (id u32, x/z as u16 in 2.5 mm steps, yaw u8, hp u16, flags
# u8), and only units that changed since the last send, plus a full refresh every KEYFRAME_EVERY
# sends (fast snapshots are unreliable, so a lost packet heals within a second).
const POS_SCALE = 400.0
const KEYFRAME_EVERY = 10
var _last_sent = {}  # net_id -> [x, z, yaw, hp, flags]
var _sends = 0


func _send_fast():
	_sends += 1
	var keyframe = _sends % KEYFRAME_EVERY == 0
	var data = PackedByteArray()
	var seen = {}
	for unit in get_tree().get_nodes_in_group("units") + _sheltered_villagers():
		if unit.get("net_id") == null or unit.unit_kind == "building":
			continue
		var flags = 0
		if (unit.unit_kind == "villager" and unit.is_sheltered()) or (unit.unit_kind == "hero" and unit.dead):
			flags |= FLAG_HIDDEN
		if GameData.now() - unit.last_attack_at < FAST_INTERVAL + 0.02:
			flags |= FLAG_ATTACKING
		var x = clampi(int(unit.global_position.x * POS_SCALE), 0, 65535)
		var z = clampi(int(unit.global_position.z * POS_SCALE), 0, 65535)
		var yaw = int(fposmod(unit.global_transform.basis.get_euler().y, TAU) / TAU * 255.0)
		var hp = clampi(int(unit.hp), 0, 65535)
		var state = [x, z, yaw, hp, flags]
		seen[unit.net_id] = true
		if not keyframe and _last_sent.get(unit.net_id) == state:
			continue
		_last_sent[unit.net_id] = state
		var at = data.size()
		data.resize(at + 12)
		data.encode_u32(at, unit.net_id)
		data.encode_u16(at + 4, x)
		data.encode_u16(at + 6, z)
		data.encode_u8(at + 8, yaw)
		data.encode_u16(at + 9, hp)
		data.encode_u8(at + 11, flags)
	for id in _last_sent.keys():
		if not seen.has(id):
			_last_sent.erase(id)
	_rpc_fast.rpc(data, _fx_queue)
	_fx_queue = []


func _sheltered_villagers():
	var result = []
	for p in _match.players_by_slot.values():
		for child in p.get_children():
			if child.get("unit_kind") == "villager" and not child.is_in_group("units"):
				result.append(child)
	return result


func _send_slow():
	var now = GameData.now()
	var players = []
	for p in _match.players_by_slot.values():
		players.append(
			{
				"slot": p.slot_index, "res": p.resources(), "age": p.age, "defeated": p.defeated,
				"store_cd": max(0.0, p.storehouse_ready_at - now), "income": p.income_per_min,
				"bot": p.is_bot, "upgrades": p.upgrades, "focus": p.focus, "shelter": p.shelter,
				"steward": p.steward, "feats": p.feats, "feed": p.spend_log.map(func(e): return [e.who, e.what, e.amount, now - e.at]),
			}
		)
	var heroes = []
	for h in get_tree().get_nodes_in_group("heroes"):
		var cds = {}
		for a in h.abilities():
			cds[a.key] = h.cooldown_left(a.key)
		heroes.append(
			{
				"id": h.net_id, "level": h.level, "xp": h.xp, "mana": h.mana, "mana_max": h.mana_max,
				"hp_max": h.hp_max, "dead": h.dead, "respawn": max(0.0, h.respawn_at - now),
				"cds": cds, "recall": h.recall_left(), "ranks": h.ranks,
				"stun": max(0.0, h.stunned_until - now), "root": max(0.0, h.rooted_until - now),
				"flags": h.status.to_mask(), "buffs": h.bm.to_net(),
				"items": h.items.map(func(it): return [it.key, max(0.0, it.ready_at - now)]),
			}
		)
	var buildings = []
	for b in get_tree().get_nodes_in_group("buildings"):
		buildings.append(
			{
				"id": b.net_id, "hp": b.hp, "hp_max": b.hp_max, "progress": b.progress,
				"paused": b.build_paused_reason, "auto": b.auto_repeat, "lane": b.lane,
				"cycle": b.cycle_left, "manual": b.manual_pending, "supply": b.supply,
				"incoming": b.incoming, "assign": b.assignment,
				"villagers": b.alive_villagers().size() if b.building_key == "village_house" else 0,
				"respawn": b.respawn_left, "age_target": b.age_target, "age_progress": b.age_progress,
				"research": b.research_key, "research_left": b.research_left, "gate": b.gate_open,
			}
		)
	var squad_list = []
	for s in get_tree().get_nodes_in_group("squadrons"):
		squad_list.append(s.summary())
	var resources = {}
	for r in get_tree().get_nodes_in_group("lotr_resources"):
		if _resource_amounts_sent.get(r.net_id, -1) != r.amount:
			_resource_amounts_sent[r.net_id] = r.amount
			resources[r.net_id] = r.amount
	_rpc_slow.rpc(players, heroes, buildings, squad_list, resources, _match.tower_progress())


func squad_summaries() -> Array:
	if _match.is_host():
		var list = []
		for s in get_tree().get_nodes_in_group("squadrons"):
			list.append(s.summary())
		return list
	return squads.values()


# --- client: receiving ------------------------------------------------------------------------------
@rpc("authority", "reliable")
func _rpc_spawn(net_id, params, slot, position, yaw, extra):
	_heard_from_host = true
	var p = _match.player_for_slot(slot)
	if p == null or _match.by_net_id(net_id) != null:
		return
	_match.spawn_puppet(net_id, params, position, yaw, p, extra)
	_targets[net_id] = [position, yaw]


@rpc("authority", "reliable")
func _rpc_despawn(net_id):
	_targets.erase(net_id)
	var node = _match.by_net_id(net_id)
	if node == null:
		return
	if node.get("unit_kind") == "hero":
		return  # heroes never despawn, they die and respawn
	if node.has_method("is_alive") and node.hp != null and node.hp > 0:
		node.hp = 0  # runs the normal death path (signals, fog cleanup) and frees it
	else:
		node.queue_free()


@rpc("authority", "unreliable_ordered")
func _rpc_fast(data: PackedByteArray, fx_list):
	var i = 0
	while i + 12 <= data.size():
		var net_id = data.decode_u32(i)
		var unit = _match.by_net_id(net_id)
		if unit != null:
			var x = data.decode_u16(i + 4) / POS_SCALE
			var z = data.decode_u16(i + 6) / POS_SCALE
			var yaw = data.decode_u8(i + 8) / 255.0 * TAU
			_targets[net_id] = [Vector3(x, unit.global_position.y, z), yaw]
			var new_hp = data.decode_u16(i + 9)
			if unit.hp != new_hp and new_hp > 0:
				unit.hp = new_hp
			var flags = data.decode_u8(i + 11)
			var hidden = (flags & FLAG_HIDDEN) != 0
			if (flags & FLAG_ATTACKING) != 0 and GameData.now() - unit.last_attack_at > 0.3:
				unit.notify_attack()
			if unit.unit_kind == "villager":
				unit.find_child("Geometry").visible = not hidden
		i += 12
	for f in fx_list:
		if _match.hud != null:
			_match.hud.play_fx(f[0], f[1], f[2])


@rpc("authority", "reliable")
func _rpc_slow(players, heroes, buildings, squad_list, resources, towers = []):
	for i in range(min(towers.size(), _match.tower_state.size())):
		_match.tower_state[i].progress = towers[i][0]
		_match.tower_state[i].claimer = towers[i][1]
	_heard_from_host = true
	var now = GameData.now()
	for pd in players:
		var p = _match.player_for_slot(pd.slot)
		if p == null:
			continue
		p.set_resources(pd.res)
		p.age = pd.age
		p.defeated = pd.defeated
		p.storehouse_ready_at = now + pd.store_cd
		p.income_per_min = pd.income
		p.is_bot = pd.bot
		p.upgrades = pd.upgrades
		p.focus = pd.get("focus", "balanced")
		p.shelter = pd.get("shelter", false)
		p.steward = pd.get("steward", true)
		p.feats = pd.get("feats", 0)
		p.spend_log = pd.get("feed", []).map(func(e): return {"who": e[0], "what": e[1], "amount": e[2], "at": now - e[3]})
	for hd in heroes:
		var h = _match.by_net_id(hd.id)
		if h == null:
			continue
		h.level = hd.level
		h.xp = hd.xp
		h.mana = hd.mana
		h.mana_max = hd.mana_max
		h.hp_max = hd.hp_max
		h.respawn_at = now + hd.respawn
		for key in hd.cds:
			h.cooldowns[key] = now + hd.cds[key]
		h.set_dead(hd.dead)
		h.recall_until = now + hd.recall if hd.recall > 0.0 else 0.0
		h.ranks = hd.ranks
		h.stunned_until = now + hd.stun
		h.rooted_until = now + hd.get("root", 0.0)
		h.status.from_mask(hd.get("flags", 0))
		h.bm.set_net(hd.get("buffs", []))
		h.items = hd.items.map(func(it): return {"key": it[0], "ready_at": now + it[1]})
	for bd in buildings:
		var b = _match.by_net_id(bd.id)
		if b == null:
			continue
		var was_built = b.is_constructed()
		b.hp_max = bd.hp_max
		if bd.hp > 0:
			b.hp = bd.hp
		b.progress = bd.progress
		if not was_built and b.is_constructed():
			b._finish_construction()
		b.build_paused_reason = bd.paused
		b.auto_repeat = bd.auto
		b.lane = bd.lane
		b.cycle_left = bd.cycle
		b.manual_pending = bd.manual
		b.supply = bd.supply
		b.incoming = bd.incoming
		b.assignment = bd.assign
		b.set_meta("villagers_alive", bd.villagers)
		b.respawn_left = bd.respawn
		b.age_target = bd.age_target
		b.age_progress = bd.age_progress
		b.research_key = bd.research
		b.research_left = bd.research_left
		b.gate_open = bd.get("gate", false)
	squads.clear()
	for s in squad_list:
		squads[s.id] = s
	for id in resources:
		var r = _match.by_net_id(id)
		if r != null:
			r.amount = resources[id]


@rpc("authority", "reliable")
func _rpc_toast(text):
	_match.toast.emit(text)


@rpc("authority", "reliable")
func _rpc_ping(pos, kind, from_slot):
	_match.hud.show_ping(pos, kind, _match.player_for_slot(from_slot))


@rpc("authority", "reliable")
func _rpc_match_over(team):
	_match._show_match_over(team)


# --- client: interpolation ---------------------------------------------------------------------------
func _process(delta):
	if _match.is_host():
		return
	var t = 1.0 - exp(-LERP_SPEED * delta)
	for net_id in _targets.keys():
		var unit = _match.by_net_id(net_id)
		if unit == null:
			_targets.erase(net_id)
			continue
		var target = _targets[net_id]
		var pos = unit.global_position
		if pos.distance_to(target[0]) > SNAP_DISTANCE:
			unit.global_position = target[0]
		else:
			unit.global_position = pos.lerp(target[0], t)
		var basis = Basis(Vector3.UP, target[1])
		unit.global_transform.basis = unit.global_transform.basis.slerp(basis, t).orthonormalized()
