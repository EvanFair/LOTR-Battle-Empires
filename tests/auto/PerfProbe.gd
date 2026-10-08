extends Node
## Performance probe: 4 bots play; every 30 game-seconds prints how many units exist and how long
## a physics frame takes (headless, so rendering is excluded). 16.6 ms is the 60 Hz budget.
## Run: godot --headless --fixed-fps 60 --path . res://tests/auto/PerfProbe.tscn -- --minutes=8

const LoaderScript = preload("res://source/lotr/menu/MatchLoader.gd")

var minutes = 8.0
var ablate_at = -1.0  # --ablate=SECONDS: at that time, measure each system's cost by pausing it
var _ablating = false
var _match = null
var _next_report = 30.0
var _frames = 0
var _usec = 0
var _last = 0


func _ready():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--minutes="):
			minutes = float(arg.split("=")[1])
		elif arg.begins_with("--ablate="):
			ablate_at = float(arg.split("=")[1])
	Network.leave()
	Network.reset_slots()
	for i in range(Network.SLOT_COUNT):
		Network.slots[i].kind = "bot"
		Network.slots[i].peer = 0
	Network.apply_team_preset("team")
	var loader = LoaderScript.new()
	loader.settings = {"slots": Network.slots.duplicate(true), "seed": 12345}
	get_tree().root.add_child.call_deferred(loader)
	_last = Time.get_ticks_usec()


func _physics_process(_delta):
	var now_us = Time.get_ticks_usec()
	_usec += now_us - _last
	_last = now_us
	_frames += 1
	if _match == null:
		_match = get_tree().get_first_node_in_group("lotr_match")
		return
	if ablate_at > 0.0 and GameData.now() >= ablate_at and not _ablating:
		_ablating = true
		_ablate()
	if GameData.now() >= _next_report:
		_next_report += 30.0
		var counts = {}
		for u in get_tree().get_nodes_in_group("units"):
			counts[u.unit_kind] = counts.get(u.unit_kind, 0) + 1
		print("t=%4ds  frame %.2f ms (physics %.2f ms)  nodes %d  units %s" % [
			int(GameData.now()), _usec / 1000.0 / max(1, _frames),
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), counts,
		])
		_frames = 0
		_usec = 0
	if GameData.now() >= minutes * 60.0:
		get_tree().quit()


func _avg_frame_ms(frames: int) -> float:
	var start = Time.get_ticks_usec()
	for i in range(frames):
		await get_tree().physics_frame
	return (Time.get_ticks_usec() - start) / 1000.0 / frames


func _set_physics(nodes: Array, on: bool):
	for n in nodes:
		if is_instance_valid(n):
			n.set_physics_process(on)
			n.set_process(on)


func _ablate():
	var tree = get_tree()
	var units = tree.get_nodes_in_group("units")
	var by_kind = {}
	for u in units:
		by_kind[u.unit_kind] = by_kind.get(u.unit_kind, []) + [u]
	var groups = {}
	for k in by_kind:
		groups["units:" + k] = by_kind[k]
	groups["squadrons"] = tree.get_nodes_in_group("squadrons")
	groups["movement traits"] = tree.root.find_children("Movement", "", true, false)
	groups["anim drivers"] = tree.root.find_children("AnimDriver", "", true, false)
	groups["health bars"] = tree.root.find_children("HealthBar", "", true, false)
	var minimap = _match.find_child("Minimap")
	groups["minimap"] = [minimap] if minimap != null else []
	groups["fog of war"] = [_match.fog_of_war] if _match.get("fog_of_war") != null else []
	groups["bots"] = _match.get_children().filter(func(c): return String(c.name).begins_with("Bot"))
	groups["hud"] = [_match.hud] if _match.hud != null else []
	var anims = tree.root.find_children("*", "AnimationPlayer", true, false)
	print("ABLATE units %d, animation players %d" % [units.size(), anims.size()])
	var base = await _avg_frame_ms(90)
	print("ABLATE baseline %.2f ms" % base)
	for name in groups:
		_set_physics(groups[name], false)
		var t = await _avg_frame_ms(90)
		_set_physics(groups[name], true)
		print("ABLATE without %-18s %.2f ms  (saves %.2f ms, %d nodes)" % [name, t, base - t, groups[name].size()])
	for a in anims:
		a.active = false
	var t2 = await _avg_frame_ms(90)
	for a in anims:
		a.active = true
	print("ABLATE without %-18s %.2f ms  (saves %.2f ms)" % ["animation players", t2, base - t2])
