extends Node
## Every player intent (human input or bot) goes through here as a plain Dictionary:
##   {"type": "hero_move", "player": 2, ...}
## The host is the only machine that runs the simulation. On a client, submit() sends the
## command to the host; on the host (or offline) it is executed straight away.

signal command_executed(command)
signal command_rejected(command, reason)

var _handlers = {}  # type -> Callable(command) -> bool/String (true or "" = ok, String = reason)
var _owner_check = null  # Callable(player_index, peer_id) -> bool, set by the match


func register(type: String, handler: Callable):
	_handlers[type] = handler


func clear():
	_handlers.clear()
	_owner_check = null


func set_owner_check(check: Callable):
	_owner_check = check


func submit(command: Dictionary):
	assert(command.has("type") and command.has("player"), "command needs type and player")
	if _is_authority():
		_execute(command)
	else:
		_receive.rpc_id(1, command)


func _is_authority():
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


@rpc("any_peer", "reliable")
func _receive(command: Dictionary):
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if _owner_check != null and not _owner_check.call(command.get("player", -1), sender):
		command_rejected.emit(command, "peer %d does not own player %s" % [sender, command.player])
		return
	_execute(command)


func _execute(command: Dictionary):
	var handler = _handlers.get(command.type)
	if handler == null:
		command_rejected.emit(command, "no handler for %s" % command.type)
		return
	var result = handler.call(command)
	if result is String and result != "":
		command_rejected.emit(command, result)
		_notify_rejection(command, result)
		return
	command_executed.emit(command)


func _notify_rejection(command: Dictionary, reason: String):
	# let the issuing player see why (e.g. "not enough Wood")
	var match_node = get_tree().get_first_node_in_group("lotr_match")
	if match_node != null and match_node.has_method("toast_player"):
		match_node.toast_player(command.player, reason)
