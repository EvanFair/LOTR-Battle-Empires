extends Node
## LAN multiplayer: ENet host/join, automatic game discovery on the local network, and the
## shared 3v3 lobby (slots 0-2 = team 1, 3-5 = team 2). The host is authoritative: it owns the lobby and runs the match.

signal lobby_changed(slots)
signal games_found_changed(games)
signal connected_to_host
signal connection_failed
signal host_left
signal peer_left(peer_id)
signal match_starting(settings)

const GAME_PORT = 24565
const DISCOVERY_PORT = 24566
const MAX_CLIENTS = 5
const SLOT_COUNT = 6
const TEAM_SIZE = 3
const BROADCAST_INTERVAL = 1.0
const GAME_TIMEOUT_MS = 3500

var player_name = "Player"
var slots = []  # Array of Dictionaries: {kind, peer, name, faction, team, hero}
var games_found = {}  # ip -> {name, players, seen_ms}
var in_match = false

var _broadcaster: PacketPeerUDP = null
var _listener: PacketPeerUDP = null
var _broadcast_timer = 0.0


func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): connected_to_host.emit())
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	reset_slots()


func _process(delta):
	if _broadcaster != null and not in_match:
		_broadcast_timer -= delta
		if _broadcast_timer <= 0.0:
			_broadcast_timer = BROADCAST_INTERVAL
			_broadcast_presence()
	if _listener != null:
		_poll_discovery()


# --- state queries ----------------------------------------------------------------------------
func is_online():
	return (
		multiplayer.multiplayer_peer != null
		and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	)


func is_host():
	return not is_online() or multiplayer.is_server()


func local_peer_id():
	return multiplayer.get_unique_id() if is_online() else 1


# --- hosting / joining ------------------------------------------------------------------------
func host_game(port = GAME_PORT) -> Error:
	leave()
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	reset_slots()
	slots[0] = _human_slot(1, player_name, slots[0])
	_broadcaster = PacketPeerUDP.new()
	_broadcaster.set_broadcast_enabled(true)
	_broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_emit_lobby()
	return OK


func join_game(address: String, port = GAME_PORT) -> Error:
	leave()
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave():
	stop_discovery()
	if _broadcaster != null:
		_broadcaster.close()
		_broadcaster = null
	if is_online():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	in_match = false
	reset_slots()


func start_discovery():
	stop_discovery()
	_listener = PacketPeerUDP.new()
	if _listener.bind(DISCOVERY_PORT) != OK:
		_listener = null
		return
	games_found.clear()


func stop_discovery():
	if _listener != null:
		_listener.close()
		_listener = null


# --- lobby ------------------------------------------------------------------------------------
func reset_slots():
	slots = []
	for i in range(SLOT_COUNT):
		var team = team_of_slot(i)
		var faction = "gondor" if team == 1 else "mordor"
		slots.append(
			{
				"kind": "bot", "peer": 0, "name": "Bot %d" % (i + 1),
				"faction": faction, "team": team, "hero": faction_heroes(faction)[i % TEAM_SIZE],
			}
		)
	slots[0] = _human_slot(1, player_name, slots[0])


static func team_of_slot(i: int) -> int:
	return 1 if i < TEAM_SIZE else 2


static func faction_heroes(faction: String) -> Array:
	return GameData.FACTIONS[faction]["heroes"].filter(func(h): return GameData.HEROES.has(h))


func apply_team_preset(_preset: String):
	pass  # v3: always two teams of three


func request_slot_change(slot_index: int, field: String, value):
	if is_host():
		_apply_slot_change(slot_index, field, value, 1)
	else:
		_rpc_request_slot_change.rpc_id(1, slot_index, field, value)


func local_slot_index():
	var me = local_peer_id()
	for i in range(slots.size()):
		if slots[i].kind == "human" and slots[i].peer == me:
			return i
	return -1


func can_start():
	if not is_host():
		return false
	var teams = {}
	for slot in slots:
		if slot.kind != "open":
			teams[slot.team] = true
	return teams.size() >= 2  # both sides need at least one hero


func start_match():
	assert(is_host())
	var settings = {"slots": slots.duplicate(true), "seed": randi()}
	in_match = true
	if is_online():
		_rpc_start_match.rpc(settings)
	else:
		_rpc_start_match(settings)


@rpc("any_peer", "reliable")
func _rpc_request_slot_change(slot_index: int, field: String, value):
	if is_host():
		_apply_slot_change(slot_index, field, value, multiplayer.get_remote_sender_id())


func _apply_slot_change(slot_index: int, field: String, value, sender: int):
	if slot_index < 0 or slot_index >= slots.size():
		return
	var slot = slots[slot_index]
	var owns_slot = slot.kind == "human" and slot.peer == sender
	if sender != 1 and not owns_slot:
		return  # clients may only edit their own slot
	match field:
		"kind":
			if sender != 1 or value == "human" or slot.kind == "human":
				return  # only the host toggles open/bot; humans arrive by joining
			slot.kind = value
			slot.name = "Bot %d" % (slot_index + 1) if value == "bot" else "Open"
		"faction":
			if not GameData.PLAYABLE_FACTIONS.has(value):
				return
			# a team is one people: the whole side changes faction, each slot keeps a
			# different one of its three heroes
			var heroes = faction_heroes(value)
			for i in range(slots.size()):
				if slots[i].team == slot.team:
					slots[i].faction = value
					slots[i].hero = heroes[i % TEAM_SIZE]
		"team":
			return  # fixed by slot in v3
		"hero":
			if GameData.HEROES.has(value) and GameData.HEROES[value]["faction"] == slot.faction:
				for other in slots:
					if other != slot and other.team == slot.team and other.hero == value:
						other.hero = slot.hero  # swap with the teammate who had it
				slot.hero = value
		"name":
			slot.name = str(value).left(16)
	_emit_lobby()


func _emit_lobby():
	if is_online() and multiplayer.is_server():
		_rpc_sync_lobby.rpc(slots)
	lobby_changed.emit(slots)


@rpc("authority", "reliable")
func _rpc_sync_lobby(new_slots):
	slots = new_slots
	lobby_changed.emit(slots)


@rpc("authority", "reliable", "call_local")
func _rpc_start_match(settings):
	in_match = true
	match_starting.emit(settings)


# --- peers ------------------------------------------------------------------------------------
func _on_peer_connected(peer_id):
	if not multiplayer.is_server():
		return
	if in_match:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)  # no joining mid-match
		return
	for i in range(slots.size()):
		if slots[i].kind != "human":
			slots[i] = _human_slot(peer_id, "Player %d" % (i + 1), slots[i])
			_emit_lobby()
			return
	multiplayer.multiplayer_peer.disconnect_peer(peer_id)  # lobby full


func _on_peer_disconnected(peer_id):
	peer_left.emit(peer_id)
	if not multiplayer.is_server():
		return
	for i in range(slots.size()):
		if slots[i].kind == "human" and slots[i].peer == peer_id:
			slots[i].kind = "bot"
			slots[i].peer = 0
			slots[i].name = "Bot %d" % (i + 1)
	if not in_match:
		_emit_lobby()


func _on_connection_failed():
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	connection_failed.emit()


func _on_server_disconnected():
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	in_match = false
	host_left.emit()


func _human_slot(peer_id, a_name, previous):
	return {
		"kind": "human", "peer": peer_id, "name": a_name, "faction": previous.faction,
		"team": previous.team, "hero": previous.hero,
	}


# --- LAN discovery ----------------------------------------------------------------------------
func _broadcast_presence():
	var humans = slots.filter(func(s): return s.kind == "human").size()
	var payload = JSON.stringify(
		{"game": "lotr-battle-empires", "name": player_name, "players": humans, "port": GAME_PORT}
	)
	_broadcaster.put_packet(payload.to_utf8_buffer())


func _poll_discovery():
	var changed = false
	while _listener.get_available_packet_count() > 0:
		var packet = _listener.get_packet().get_string_from_utf8()
		var ip = _listener.get_packet_ip()
		var data = JSON.parse_string(packet)
		if data is Dictionary and data.get("game") == "lotr-battle-empires":
			data["seen_ms"] = Time.get_ticks_msec()
			games_found[ip] = data
			changed = true
	var now = Time.get_ticks_msec()
	for ip in games_found.keys():
		if now - games_found[ip].seen_ms > GAME_TIMEOUT_MS:
			games_found.erase(ip)
			changed = true
	if changed:
		games_found_changed.emit(games_found)
