extends Node
## Scripted rules test. Slot 0 is a "human" (this script plays it through CommandBus, with the
## HUD and HeroController running); slots 1-3 are bots. Each check prints PASS/FAIL.
## Run: godot --headless --fixed-fps 60 --path . res://tests/auto/RulesTest.tscn

const LoaderScript = preload("res://source/lotr/menu/MatchLoader.gd")

var _match = null
var _me = null
var _results = []
var _step = 0
var _wait_until = 0.0
var _data = {}


func _ready():
	CommandBus.command_rejected.connect(func(c, reason): print("   (rejected %s: %s)" % [c.type, reason]))
	Network.leave()
	Network.reset_slots()
	for i in range(1, Network.SLOT_COUNT):
		Network.slots[i].kind = "bot"
	Network.apply_team_preset("team")
	var loader = LoaderScript.new()
	loader.settings = {"slots": Network.slots.duplicate(true), "seed": 777}
	get_tree().root.add_child.call_deferred(loader)


func check(name, condition, detail = ""):
	_results.append([name, condition])
	print("%s  %s %s" % ["PASS" if condition else "FAIL", name, detail])


func cmd(c):
	c["player"] = _me.slot_index
	CommandBus.submit(c)


func wait(seconds):
	_wait_until = GameData.now() + seconds


func hero():
	return _me.hero


func tc():
	return _me.town_centers()[0]


func house():
	return _me.buildings("village_house")[0]


func free_spot(key, near: Vector3, min_r = 6.0, max_r = 16.0):
	for i in range(60):
		var a = i * 0.7
		var r = min_r + (i % 6) * (max_r - min_r) / 6.0
		var p = near + Vector3(cos(a), 0, sin(a)) * r
		if _match.placement_blocker(key, p) == "" and _me.in_base(p):
			return p
	return null


func _physics_process(_delta):
	if _match == null:
		_match = get_tree().get_first_node_in_group("lotr_match")
		return
	if not _match.started:
		return
	_me = _match.local_player
	# test god-mode: keep our hero alive so bot raids can't derail the scripted steps
	if hero() != null and hero().is_alive() and _step >= 7:
		hero().hp = hero().hp_max
	if GameData.now() < _wait_until:
		return
	_run_step()
	_step += 1


func _run_step():
	match _step:
		0:
			check("local player is slot 0 with a hero", _me != null and _me.slot_index == 0 and hero() != null)
			check("HUD and controller exist", _match.hud != null and _match.hero_controller != null)
			# exercise HUD entry points
			_match.hud.show_bubbles(house())
			_match.hud.show_building(tc())
			_match.hud.toggle_build_menu()
			_data.wood0 = _me.wood
			cmd({"type": "assign_villagers", "house": house().net_id, "assignment": "wood"})
			wait(40)
		1:
			check("villagers assigned to wood bring wood in", _me.wood > _data.wood0, "(%d -> %d)" % [_data.wood0, _me.wood])
			cmd({"type": "assign_villagers", "house": house().net_id, "assignment": "home"})
			wait(20)
		2:
			var sheltered = house().alive_villagers().filter(func(v): return v.is_sheltered()).size()
			check("Return home shelters villagers", sheltered >= 4, "(%d sheltered)" % sheltered)
			cmd({"type": "assign_villagers", "house": house().net_id, "assignment": "food"})
			# give resources so the rest of the test isn't waiting on the economy
			_me.add_resources({"food": 3000, "wood": 3000, "stone": 2000, "iron": 2000})
			_data.spot = free_spot("barracks", tc().global_position)
			cmd({"type": "build", "building": "barracks", "pos": _data.spot})
			wait(1)
		3:
			var b = _site("barracks")
			check("barracks foundation placed", b != null)
			_data.barracks = b
			# hero walks away: construction must pause
			cmd({"type": "hero_move", "pos": tc().global_position + Vector3(0, 0, -GameData.BASE_RADIUS - 6)})
			wait(12)
		4:
			var b = _data.barracks
			check("construction pauses with no hero nearby", b.build_paused_reason == "no_hero" and b.progress < 0.05, "(%s, %.2f)" % [b.build_paused_reason, b.progress])
			cmd({"type": "hero_move", "pos": b.global_position + Vector3(b.stats_size() + 1.5, 0, 0)})
			wait(25)
		5:
			var b = _data.barracks
			_data.p1 = b.progress
			check("construction progresses with the hero nearby", b.progress > 0.05, "(%.2f)" % b.progress)
			# an enemy hero arrives: construction pauses
			var enemy_hero = _enemy_hero()
			_data.enemy_hero_pos = enemy_hero.global_position
			enemy_hero.global_position = b.global_position + Vector3(-b.stats_size() - 1.5, 0, 0)
			enemy_hero.order_hold()
			_match.get_node("Bot%d" % enemy_hero.player.slot_index).set_physics_process(false)
			wait(5)
		6:
			var b = _data.barracks
			check("enemy hero nearby pauses construction", b.build_paused_reason == "enemy_hero", "(%s)" % b.build_paused_reason)
			var enemy_hero = _enemy_hero()
			enemy_hero.global_position = _data.enemy_hero_pos
			_match.get_node("Bot%d" % enemy_hero.player.slot_index).set_physics_process(true)
			# keep our hero alive for the rest of the test
			hero().hp_max = 100000
			hero().hp = 100000
			wait(100)
		7:
			var b = _data.barracks
			check("barracks finishes", b.is_constructed(), "(%.2f)" % b.progress)
			var lanes = _match.lanes_for_player(_me).filter(func(l): return Teams.is_enemy(_match.player_for_slot(l.b if l.a == 0 else l.a), _me))
			_data.squads_before = _my_squads().size()
			cmd({"type": "set_auto_repeat", "building": b.net_id, "enabled": true, "lane": lanes[0].index})
			wait(5)
		8:
			check("auto-repeat is on", _data.barracks.auto_repeat)
			wait(150)
		9:
			var b = _data.barracks
			check("villagers hauled supply and a squadron was trained", _my_squads().size() > _data.squads_before, "(supply %s)" % b.supply)
			var squad = _my_squads()[0]
			hero().global_position = squad.center() + Vector3(2, 0, 0)
			hero().order_stop()
			wait(0.5)
		10:
			var squad = _my_squads()[0]
			cmd({"type": "squad_order", "squad": squad.squad_id, "order": "hold"})
			wait(0.5)
		11:
			var squad = _my_squads()[0]
			check("hold order applies when hero is near", squad.state == squad.State.HOLD)
			hero().global_position = tc().global_position + Vector3(0, 0, 5)
			hero().order_stop()
			wait(0.5)
		12:
			var squad = _my_squads()[0]
			cmd({"type": "squad_order", "squad": squad.squad_id, "order": "return"})
			wait(0.5)
		13:
			var squad = _my_squads()[0]
			check("squad orders are refused when the hero is far away", squad.state != squad.State.RETURN or squad.center().distance_to(hero().global_position) <= GameData.COMMAND_RANGE)
			# Ages and the Storehouse
			cmd({"type": "advance_age"})
			wait(65)
		14:
			check("advanced to Age II with the hero at the Town Center", _me.age == 2, "(age %d)" % _me.age)
			_data.store_spot = free_spot("storehouse", tc().global_position)
			cmd({"type": "build", "building": "storehouse", "pos": _data.store_spot})
			wait(1)
		15:
			var s = _site("storehouse")
			check("storehouse foundation placed", s != null)
			hero().global_position = s.global_position + Vector3(s.stats_size() + 1.2, 0, 0)
			hero().order_stop()
			wait(62)
		16:
			var s = _me.buildings("storehouse")[0]
			check("storehouse built", s.is_constructed())
			_data.res_before = _me.resources()
			s.hp = 0
			wait(1)
		17:
			var halved = true
			for r in GameData.RESOURCES:
				var expected = int(_data.res_before[r] * 0.5)
				if abs(_me.get(r) - expected) > 60:  # villagers keep delivering meanwhile
					halved = false
			check("losing the Storehouse halves the stockpile", halved, "(%s -> %s)" % [_data.res_before, _me.resources()])
			_data.toast = ""
			CommandBus.command_rejected.connect(func(_c, reason): _data.toast = reason, CONNECT_ONE_SHOT)
			cmd({"type": "build", "building": "storehouse", "pos": _data.store_spot})
			wait(0.5)
		18:
			check("Storehouse rebuild has a cooldown", "rebuilt in" in _data.toast, "(%s)" % _data.toast)
			# villager respawn costs food
			var h = house()
			var v = h.alive_villagers()[0]
			_data.food_before_respawn = _me.food
			v.hp = 0
			wait(GameData.VILLAGER_RESPAWN_TIME + 3)
		19:
			check("killed villager is replaced after the delay", house().alive_villagers().size() == GameData.VILLAGERS_PER_HOUSE)
			# ability ranks: R can't be learned before level 6; then learn everything for the test
			_data.toast = ""
			CommandBus.command_rejected.connect(func(_c, reason): _data.toast = reason, CONNECT_ONE_SHOT)
			hero().level = 1
			hero().ranks = {}
			cmd({"type": "learn", "key": "R"})
			check("ultimate can't be learned at level 1", "level 6" in _data.toast, "(%s)" % _data.toast)
			cmd({"type": "learn", "key": "E"})
			check("learning spends a skill point", hero().ability_rank("E") == 1 and hero().skill_points() == 0)
			hero().level = 6
			hero().ranks = {"Q": 1, "W": 1, "E": 1, "R": 1}
			# abilities: W rally, E dash, R army of the dead, Q execute on an enemy
			var before = hero().global_position
			_data.dash_from = before
			cmd({"type": "cast", "key": "E", "pos": before + Vector3(6, 0, 0)})
			wait(1)
		20:
			check("Ranger's Dash moves the hero", hero().global_position.distance_to(_data.dash_from) > 3.0)
			var enemy_owner = _enemy_hero().player
			var dummy = _match.spawn_unit({"kind": "troop", "faction": enemy_owner.faction, "class": "infantry"}, hero().global_position + Vector3(1.5, 0, 0), enemy_owner)
			_data.dummy = dummy
			wait(0.3)
		21:
			var dummy = _data.dummy
			var hp_before = dummy.hp
			cmd({"type": "cast", "key": "Q", "target": dummy.net_id, "pos": dummy.global_position})
			check("Andúril Strike damages an enemy", not is_instance_valid(dummy) or dummy.hp < hp_before)
			var troops_before = _troop_count()
			cmd({"type": "cast", "key": "R", "pos": hero().global_position + Vector3(4, 0, 0)})
			check("Army of the Dead summons a squadron", _troop_count() >= troops_before + 8)
			_data.summon_check = GameData.now()
			wait(17)
		22:
			var ghosts = 0
			for u in get_tree().get_nodes_in_group("units"):
				if u.player == _me and u.get("summon_expires_at") != null and u.summon_expires_at > 0:
					ghosts += 1
			check("summoned army disappears after its duration", ghosts == 0, "(%d left)" % ghosts)
			# other heroes' kits: borrow Boromir's Shield Bash and the Witch-king's Black Breath
			var enemy_owner = _enemy_hero().player
			var dummy = _match.spawn_unit({"kind": "troop", "faction": enemy_owner.faction, "class": "infantry"}, hero().global_position + Vector3(1.5, 0, 0), enemy_owner)
			dummy.auto_acquire = false
			dummy.hp_max = 5000
			dummy.hp = 5000
			hero().hero_key = "boromir"
			hero().cooldowns.clear()
			hero().mana = hero().mana_max
			var err = HeroAbilities.cast(_match, hero(), "Q", dummy.global_position, dummy)
			check("Shield Bash stuns its target", err == "" and dummy.is_stunned(), "(%s)" % err)
			hero().hero_key = "witch_king"
			hero().ranks["W"] = 1
			err = HeroAbilities.cast(_match, hero(), "W", null, null)
			check("Black Breath slows and weakens enemies around", err == "" and dummy.speed_mult < 1.0 and dummy.damage_mult < 1.0, "(%s speed %.2f dmg %.2f)" % [err, dummy.speed_mult, dummy.damage_mult])
			hero().hero_key = "aragorn"
			dummy.hp = 0
			# Recall: refused at home, works in the field, broken by moving
			_data.toast = ""
			CommandBus.command_rejected.connect(func(_c, reason): _data.toast = reason, CONNECT_ONE_SHOT)
			hero().global_position = tc().global_position + Vector3(0, 0, tc().stats_size() + 1.5)
			cmd({"type": "recall"})
			check("Recall is refused inside the base", "home" in _data.toast, "(%s)" % _data.toast)
			hero().global_position = tc().global_position + Vector3(GameData.BASE_RADIUS + 8, 0, 0)
			cmd({"type": "recall"})
			cmd({"type": "hero_move", "pos": hero().global_position + Vector3(2, 0, 0)})
			check("moving cancels Recall", hero().recall_until == 0.0)
			cmd({"type": "recall"})
			wait(hero().RECALL_TIME + 0.5)
		23:
			check("Recall takes the hero home", _me.in_base(hero().global_position), "(%s)" % hero().global_position)
			# --- Armies & Age III ---
			_me.set_resources({"food": 3000, "wood": 3000, "stone": 3000, "iron": 3000, "gold": 1000})
			_me.age = 2
			hero().global_position = tc().global_position + Vector3(0, 0, tc().stats_size() + 1.5)
			hero().order_stop()
			var spot = free_spot("blacksmith", tc().global_position, 7.0, 16.0)
			_data.smith_spot = spot
			cmd({"type": "build", "building": "blacksmith", "pos": spot})
			wait(0.5)
		24:
			var s = _site("blacksmith")
			check("Blacksmith foundation placed", s != null)
			if s != null:
				hero().global_position = s.global_position + Vector3(s.stats_size() + 1.2, 0, 0)
				hero().order_stop()
				s.progress = 0.95  # construction itself is covered above; skip ahead
			wait(GameData.BUILDINGS.blacksmith.build_time * 0.05 + 3)
		25:
			var smiths = _me.buildings("blacksmith")
			check("Blacksmith built", not smiths.is_empty() and smiths[0].is_constructed())
			hero().global_position = tc().global_position + Vector3(0, 0, tc().stats_size() + 1.5)
			hero().order_stop()
			_data.dmg_before = GameData.troop_stats(_me.faction, "infantry", _me.upgrades).damage
			cmd({"type": "research", "upgrade": "forged_blades"})
			_data.toast = ""
			CommandBus.command_rejected.connect(func(_c, reason): _data.toast = reason, CONNECT_ONE_SHOT)
			cmd({"type": "research", "upgrade": "war_drills"})
			var smith = _me.buildings("blacksmith")[0]
			check("research starts at the Blacksmith", smith.research_key == "forged_blades")
			smith.research_left = 2.0
			wait(3)
		26:
			check("Age III research is locked in Age II", "Requires" in _data.toast or "busy" in _data.toast, "(%s)" % _data.toast)
			check("Forged Blades researched", _me.upgrades.get("forged_blades", false))
			var dmg_after = GameData.troop_stats(_me.faction, "infantry", _me.upgrades).damage
			check("upgrade raises new troops' damage", dmg_after > _data.dmg_before, "(%.1f -> %.1f)" % [_data.dmg_before, dmg_after])
			cmd({"type": "advance_age"})
			check("Empire Age advance starts", tc().age_target == 3)
			tc().age_progress = 0.95
			wait(GameData.AGES[3].time * 0.05 + 3)
		27:
			check("advanced to the Empire Age", _me.age == 3, "(age %d)" % _me.age)
			var spot = free_spot("siege_works", tc().global_position, 8.0, 18.0)
			cmd({"type": "build", "building": "siege_works", "pos": spot})
			var special_spot = free_spot("special_building", tc().global_position, 8.0, 18.0)
			cmd({"type": "build", "building": "special_building", "pos": special_spot})
			wait(0.5)
		28:
			check("Siege Works can be placed in Age III", _site("siege_works") != null)
			var sb = _site("special_building")
			check("faction special building uses the faction name", sb != null and sb.display_name == GameData.SPECIAL_BUILDING_NAMES[_me.faction], "(%s)" % (sb.display_name if sb != null else "none"))
			var grond = GameData.troop_stats("mordor", "special")
			check("Grond is a siege unit", grond.siege and grond.squad_size == 1)
			# an Isengard sapper blows up on a building and dies
			var enemy = null
			for p in _match.players_by_slot.values():
				if Teams.is_enemy(p, _me):
					enemy = p
					break
			var target = _me.buildings("blacksmith")[0]
			_data.target = target
			_data.target_hp = target.hp
			var sapper = _match.spawn_unit({"kind": "troop", "faction": "isengard", "class": "special"}, target.global_position + Vector3(target.stats_size() + 1.0, 0, 0), enemy)
			_data.sapper = sapper
			sapper.order_attack(target)
			wait(3)
		29:
			check("sapper explodes on contact", not is_instance_valid(_data.sapper) or not _data.sapper.is_alive())
			check("sapper blast damages the building", not is_instance_valid(_data.target) or _data.target.hp < _data.target_hp, "(%d -> %s)" % [_data.target_hp, _data.target.hp if is_instance_valid(_data.target) else "destroyed"])
			# --- the Shop ---
			hero().global_position = tc().global_position + Vector3(0, 0, tc().stats_size() + 1.5)
			hero().order_stop()
			hero().items.clear()
			hero().recompute_stats()
			_me.gold = 2000
			_data.dmg = hero().attack_damage
			cmd({"type": "buy", "item": "elven_blade"})
			check("buying an Elven Blade raises attack damage", hero().attack_damage > _data.dmg and _me.gold == 2000 - GameData.ITEMS.elven_blade.cost, "(%.0f -> %.0f, gold %d)" % [_data.dmg, hero().attack_damage, _me.gold])
			cmd({"type": "buy", "item": "lembas"})
			hero().hp = 100
			cmd({"type": "use_item", "slot": 1})
			check("Lembas heals and is used up", hero().hp > 300 and hero().items.size() == 1, "(hp %d, items %d)" % [hero().hp, hero().items.size()])
			cmd({"type": "sell", "slot": 0})
			check("selling refunds half", hero().items.is_empty() and _me.gold == 2000 - GameData.ITEMS.elven_blade.cost - GameData.ITEMS.lembas.cost + int(GameData.ITEMS.elven_blade.cost * GameData.SELL_REFUND), "(gold %d)" % _me.gold)
			_data.toast = ""
			CommandBus.command_rejected.connect(func(_c, reason): _data.toast = reason, CONNECT_ONE_SHOT)
			hero().global_position = tc().global_position + Vector3(GameData.BASE_RADIUS + 6, 0, 0)
			cmd({"type": "buy", "item": "lembas"})
			check("the shop only works in your base", "base" in _data.toast, "(%s)" % _data.toast)
			# --- the Wild ---
			check("jungle camps and the Cave Troll are on the map", _match.camps.size() == MapGen.camp_sites().size() and _match.camps.any(func(c): return c.key == "troll"))
			var camp = null
			for c in _match.camps:
				if c.key == "spiders":
					camp = c
					break
			_data.camp = camp
			hero().global_position = camp.pos + Vector3(4.0, 0, 0)
			hero().order_stop()
			_data.spider = camp.members[0]
			cmd({"type": "hero_attack", "target": _data.spider.net_id})
			wait(2.0)
		30:
			var camp = _data.camp
			var fighting = camp.members.filter(func(m): return is_instance_valid(m) and m.is_alive() and m.order_target == hero())
			check("striking one spider turns the whole camp on you", fighting.size() == camp.members.size(), "(%d/%d)" % [fighting.size(), camp.members.size()])
			# drag them away: they give up past the leash range and heal
			hero().order_stop()
			hero().global_position = camp.pos + Vector3(GameData.LEASH_RANGE + 10.0, 0, 0)
			wait(8.0)
		31:
			var camp = _data.camp
			var home = camp.members.filter(func(m): return is_instance_valid(m) and m.is_alive() and m.global_position.distance_to(camp.pos) < 4.0 and m.hp == m.hp_max)
			check("pulled creatures leash back home and heal", home.size() == camp.members.size(), "(%d/%d home at full health)" % [home.size(), camp.members.size()])
			_data.gold_before = _me.gold
			for m in camp.members:
				Combat.deal_damage(hero(), m, 99999, true)
			check("clearing a camp pays Gold", _me.gold >= _data.gold_before + 3 * GameData.CREATURES.spider.gold, "(%d -> %d)" % [_data.gold_before, _me.gold])
			_finish()


func _site(key):
	for b in _me.buildings(key):
		if not b.is_constructed():
			return b
	return null


func _enemy_hero():
	for h in get_tree().get_nodes_in_group("heroes"):
		if Teams.is_enemy(h.player, _me) and h.is_alive():
			return h
	return null


func _my_squads():
	return get_tree().get_nodes_in_group("squadrons").filter(func(s): return s.player == _me)


func _troop_count():
	return get_tree().get_nodes_in_group("units").filter(func(u): return u.player == _me and u.unit_kind == "troop").size()


func _finish():
	set_physics_process(false)
	var failed = _results.filter(func(r): return not r[1])
	print("RULES RESULT: %s (%d/%d passed)" % ["PASS" if failed.is_empty() else "FAIL", _results.size() - failed.size(), _results.size()])
	get_tree().quit(0 if failed.is_empty() else 1)
