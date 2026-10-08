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


func _send_fast():
	var data = PackedFloat32Array()
	for unit in get_tree().get_nodes_in_group("units") + _sheltered_villagers():
		if unit.get("net_id") == null or unit.unit_kind == "building":
			continue
		var flags = 0
		if (unit.unit_kind == "villager" and unit.is_sheltered()) or (unit.unit_kind == "hero" and unit.dead):
			flags |= FLAG_HIDDEN
		if GameData.now() - unit.last_attack_at < FAST_INTERVAL + 0.02:
			flags |= FLAG_ATTACKING
		data.append(unit.net_id)
		data.append(unit.global_position.x)
		data.append(unit.global_position.z)
		data.append(unit.global_transform.basis.get_euler().y)
		data.append(unit.hp)
		data.append(flags)
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
				"bot": p.is_bot,
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
				"cds": cds,
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
	_rpc_slow.rpc(players, heroes, buildings, squad_list, resources)


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
func _rpc_fast(data: PackedFloat32Array, fx_list):
	var i = 0
	while i + 6 <= data.size():
		var net_id = int(data[i])
		var unit = _match.by_net_id(net_id)
		if unit != null:
			_targets[net_id] = [Vector3(data[i + 1], unit.global_position.y, data[i + 2]), data[i + 3]]
			var new_hp = int(data[i + 4])
			if unit.hp != new_hp and new_hp > 0:
				unit.hp = new_hp
			var hidden = (int(data[i + 5]) & FLAG_HIDDEN) != 0
			if (int(data[i + 5]) & FLAG_ATTACKING) != 0 and GameData.now() - unit.last_attack_at > 0.3:
				unit.notify_attack()
			if unit.unit_kind == "villager":
				unit.find_child("Geometry").visible = not hidden
		i += 6
	for f in fx_list:
		if _match.hud != null:
			_match.hud.play_fx(f[0], f[1], f[2])


@rpc("authority", "reliable")
func _rpc_slow(players, heroes, buildings, squad_list, resources):
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
