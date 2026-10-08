extends Node
## Headless end-to-end test: 4 bots play an offline match on a fixed seed.
## Run:  godot --headless --fixed-fps 60 --path . res://tests/auto/BotMatchTest.tscn -- --minutes=6
## Exits 0 if the economy, construction, armies and combat all worked, 1 otherwise.

const LoaderScript = preload("res://source/lotr/menu/MatchLoader.gd")

var minutes = 6.0
var preset = "team"
var _match = null
var _events = {"spawned": {}, "died": {}, "squads": 0, "constructed": 0}
var _done = false


func _ready():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--minutes="):
			minutes = float(arg.split("=")[1])
		elif arg.begins_with("--preset="):
			preset = arg.split("=")[1]
	Network.leave()
	Network.reset_slots()
	for i in range(Network.SLOT_COUNT):
		Network.slots[i].kind = "bot"
		Network.slots[i].peer = 0
	Network.apply_team_preset(preset)
	MatchSignals.unit_spawned.connect(func(u): _count("spawned", u))
	MatchSignals.unit_died.connect(func(u): _count("died", u))
	MatchSignals.unit_construction_finished.connect(func(_u): _events.constructed += 1)
	var loader = LoaderScript.new()
	loader.settings = {"slots": Network.slots.duplicate(true), "seed": 12345}
	get_tree().root.add_child.call_deferred(loader)


func _count(kind, unit):
	var k = unit.get("unit_kind")
	if k == null:
		return
	_events[kind][k] = _events[kind].get(k, 0) + 1


func _physics_process(_delta):
	if _done:
		return
	if _match == null:
		_match = get_tree().get_first_node_in_group("lotr_match")
		return
	if GameData.now() >= minutes * 60.0 or _match.ended:
		_done = true
		_report()


func _report():
	var ok = true
	print("\n===== Bot match report after %.1f game-minutes (%s) =====" % [GameData.now() / 60.0, preset])
	for p in _match.players_by_slot.values():
		var buildings = {}
		for b in p.buildings():
			var key = b.building_key + ("" if b.is_constructed() else "(wip)")
			buildings[key] = buildings.get(key, 0) + 1
		var villagers = 0
		for c in p.get_children():
			if c.get("unit_kind") == "villager":
				villagers += 1
		var squads = get_tree().get_nodes_in_group("squadrons").filter(func(s): return s.player == p)
		var hero = p.hero
		print("%-8s team %d age %d %s | res %s" % [p.faction, p.team, p.age, "DEFEATED" if p.defeated else "", p.resources()])
		print("   buildings %s" % buildings)
		print("   villagers %d, squads alive %d, hero %s lvl %d xp %d %s" % [
			villagers, squads.size(), hero.display_name, hero.level, hero.xp, "dead" if hero.dead else "alive"])
		if buildings.get("village_house", 0) < 2:
			print("   FAIL: expected at least 2 finished houses")
			ok = false
		if villagers < 5:
			print("   FAIL: expected villagers")
			ok = false
	print("events: spawned %s" % _events.spawned)
	print("        died    %s" % _events.died)
	print("        constructed %d" % _events.constructed)
	if _events.spawned.get("troop", 0) == 0:
		print("FAIL: no squadrons were ever trained")
		ok = false
	if _events.died.get("troop", 0) + _events.died.get("hero", 0) == 0:
		print("FAIL: no combat deaths happened")
		ok = false
	if _match.ended:
		print("match ended, winning team %d" % _match.winning_team)
	print("RESULT: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
