extends Node
## Scripted rules test (3v3). Slot 0 is a "human" and the bank of team 1 (this script plays it
## through CommandBus, with the HUD and HeroController running); slots 1-2 are its teammates and
## slots 3-5 the enemy team, all bots. Each check prints PASS/FAIL.
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
	var loader = LoaderScript.new()
	loader.settings = {"slots": Network.slots.duplicate(true), "seed": 777}
	get_tree().root.add_child.call_deferred(loader)


func check(name, condition, detail = ""):
	_results.append([name, condition])
	print("%s  %s %s" % ["PASS" if condition else "FAIL", name, detail])


func cmd(c):
	c["player"] = _me.slot_index
	CommandBus.submit(c)


func cmd_as(slot, c):
	"""A teammate (or anyone) issues a command."""
	c["player"] = slot
	CommandBus.submit(c)


func wait(seconds):
	_wait_until = GameData.now() + seconds


func hero():
	return _me.hero


func tc():
	return _me.town_centers()[0]


func house():
	return _me.buildings("village_house")[0]


func supplies():
	return _me.treasury().supplies


func capture_rejection():
	_data.toast = ""
	CommandBus.command_rejected.connect(func(_c, reason): _data.toast = reason, CONNECT_ONE_SHOT)


func to_center() -> Vector3:
	var center = Vector3(MapGen.SIZE / 2.0, 0, MapGen.SIZE / 2.0)
	return (center - tc().global_position).normalized()


func building_ids() -> Array:
	return get_tree().get_nodes_in_group("buildings").map(func(b): return b.net_id)


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
			# 3v3: slots 0-2 against slots 3-5, one shared city and one chest per team
			var teams_ok = _match.players_by_slot.size() == 6
			for i in range(6):
				teams_ok = teams_ok and _match.players_by_slot[i].team == (1 if i < 3 else 2)
			check("six slots: 0-2 on team 1, 3-5 on team 2", teams_ok)
			var banks_ok = true
			var detail = ""
			for team in [1, 2]:
				var bank = _match.team_bank(team)
				banks_ok = banks_ok and bank != null and bank.slot_index == (0 if team == 1 else 3)
				var heroes = {}
				for p in _match.players_by_slot.values():
					if p.team != team:
						continue
					heroes[p.hero_key] = true
					banks_ok = banks_ok and p.hero != null and p.treasury() == bank
					banks_ok = banks_ok and p.resources() == bank.resources() and p.town_centers() == bank.town_centers()
					banks_ok = banks_ok and p.age == bank.age and (p == bank or p.bank == bank)
				banks_ok = banks_ok and heroes.size() == 3 and bank.town_centers().size() == 1
				detail += "(team %d: %d heroes) " % [team, heroes.size()]
			check("each team shares one city, one chest and one Age, with three different heroes", banks_ok, detail)
			check("the team chest holds Supplies only", _me.resources().keys() == ["supplies"] and _me.resources().supplies > 0, "(%s)" % _me.resources())
			check("costs convert to Supplies through GameData.price",
				GameData.price({"wood": 100}) == 100 and GameData.price({"stone": 100}) == 150 and GameData.price({"iron": 100, "gold": 10}) == 210)
			check("a Steward runs for each team bank and its bots", _me.steward and _match.has_node("Bot0") and _match.has_node("Bot3") and _match.has_node("Bot1") and _match.has_node("Bot5"))
			_data.buildings0 = _me.buildings().size()
			_data.income0 = 0
			cmd({"type": "assign_villagers", "assignment": "wood"})  # villagers lean towards wood
			wait(30)
		1:
			check("the Steward builds houses and core buildings by itself", _me.buildings().size() > _data.buildings0, "(%d -> %d buildings)" % [_data.buildings0, _me.buildings().size()])
			var income = 0
			for v in _me.income.values():
				income += v
			for v in _me.income_per_min.values():
				income += v
			check("villagers' loads reach the team chest", income > 0, "(%d Supplies from villagers)" % income)
			var jobs = {}
			var villagers = 0
			for h in _me.buildings("village_house"):
				for v in h.alive_villagers():
					villagers += 1
					jobs[v.job] = jobs.get(v.job, 0) + 1
			var wood_is_top = true
			for j in jobs:
				wood_is_top = wood_is_top and jobs.get("wood", 0) >= jobs[j]
			check("the wood focus puts most villagers on wood", villagers > 0 and jobs.get("wood", 0) > 0 and wood_is_top, "(%s)" % jobs)
			# test isolation: from here on we drive the city ourselves and the teammate bots stand still
			cmd({"type": "assign_villagers", "assignment": "steward"})
			_match.get_node("Bot1").set_physics_process(false)
			_match.get_node("Bot2").set_physics_process(false)
			cmd({"type": "assign_villagers", "assignment": "home"})
			wait(20)
		2:
			check("the Steward can be turned off", not _me.steward)
			var sheltered = house().alive_villagers().filter(func(v): return v.is_sheltered()).size()
			check("Return home shelters villagers", sheltered >= GameData.VILLAGERS_PER_HOUSE - 1, "(%d sheltered)" % sheltered)
			cmd({"type": "assign_villagers", "assignment": "balanced"})
			check("balanced focus ends the shelter", not _me.shelter and _me.focus == "balanced")
			# give Supplies so the rest of the test isn't waiting on the economy
			_me.set_resources({"supplies": 8000})
			_data.ids = building_ids()
			_data.spot = free_spot("barracks", tc().global_position)
			var before = supplies()
			cmd({"type": "build", "building": "barracks", "pos": _data.spot})
			check("building spends the team chest", supplies() == before - GameData.price(GameData.BUILDINGS.barracks.cost), "(%d -> %d)" % [before, supplies()])
			# every hero (ours and the teammates') leaves, so nobody is near the foundation
			var away = tc().global_position + to_center() * 45.0
			for slot in [0, 1, 2]:
				var h = _match.players_by_slot[slot].hero
				h.global_position = away + Vector3(slot, 0, 0)
				h.order_stop()
			wait(1)
		3:
			var b = _site("barracks")
			check("barracks foundation placed", b != null)
			check("teammates see the team's buildings", b != null and _match.players_by_slot[1].buildings("barracks").has(b) and _match.players_by_slot[2].buildings("barracks").has(b))
			_data.barracks = b
			_data.p0 = b.progress
			wait(10)
		4:
			var b = _data.barracks
			var expected = 10.0 / GameData.BUILDINGS.barracks.build_time
			check("construction progresses with no hero nearby", b.build_paused_reason == "" and b.progress - _data.p0 > expected * 0.6 and b.progress < expected * 1.6, "(%s, %.2f, expected about %.2f)" % [b.build_paused_reason, b.progress, expected])
			# our hero stands beside it: faster
			hero().global_position = b.global_position + Vector3(b.stats_size() + 1.5, 0, 0)
			hero().order_stop()
			_data.p1 = b.progress
			wait(6)
		5:
			var b = _data.barracks
			var gained = b.progress - _data.p1
			var base_rate = 6.0 / GameData.BUILDINGS.barracks.build_time
			check("a friendly hero nearby speeds construction up", gained > base_rate * 1.25, "(%.3f vs %.3f without)" % [gained, base_rate])
			# an enemy hero arrives: construction stops
			_data.p2 = b.progress
			var enemy_hero = _enemy_hero()
			enemy_hero.hp_max = 100000
			enemy_hero.hp = 100000
			_data.enemy_hero_pos = enemy_hero.global_position
			enemy_hero.global_position = b.global_position + Vector3(-b.stats_size() - 1.5, 0, 0)
			enemy_hero.order_hold()
			_match.get_node("Bot%d" % enemy_hero.player.slot_index).set_physics_process(false)
			wait(5)
		6:
			var b = _data.barracks
			check("enemy hero nearby stops construction", b.build_paused_reason == "enemy_hero" and abs(b.progress - _data.p2) < 0.01, "(%s, %.3f -> %.3f)" % [b.build_paused_reason, _data.p2, b.progress])
			var enemy_hero = _enemy_hero()
			enemy_hero.global_position = _data.enemy_hero_pos
			_match.get_node("Bot%d" % enemy_hero.player.slot_index).set_physics_process(true)
			# keep our hero alive for the rest of the test
			hero().hp_max = 100000
			hero().hp = 100000
			b.progress = 0.97  # the rate is covered above; skip the long wait
			b.hp = b.hp_max
			wait(4)
		7:
			var b = _data.barracks
			check("barracks finishes", b.is_constructed(), "(%.2f)" % b.progress)
			var lanes = _match.lanes_for_player(_me).filter(func(t): return t.kind == "base")
			_data.squads_before = _match._next_squad_id
			_me.set_resources({"supplies": 5000})
			cmd({"type": "set_auto_repeat", "building": b.net_id, "enabled": true, "lane": lanes[0].index})
			b.cycle_left = 1.0  # skip the minute between squadrons
			wait(5)
		8:
			var b = _data.barracks
			check("auto-repeat is on", b.auto_repeat)
			var cost = GameData.price(b.squad_cost())
			check("auto-repeat trains a squadron paid from the team chest", _match._next_squad_id > _data.squads_before and supplies() < 5000 - cost / 2, "(chest %d, squad costs %d)" % [supplies(), cost])
			if _my_squads().is_empty():
				_match.spawn_squadron(_me, "infantry", b, -1)  # the trained one may already have died on its lane
			var squad = _my_squads()[0]
			hero().global_position = squad.center() + Vector3(2, 0, 0)
			hero().order_stop()
			wait(0.5)
		9:
			var squad = _my_squads()[0]
			cmd({"type": "squad_order", "squad": squad.squad_id, "order": "hold"})
			wait(0.5)
		10:
			var squad = _my_squads()[0]
			check("hold order applies when hero is near", squad.state == squad.State.HOLD)
			hero().global_position = tc().global_position + Vector3(0, 0, 5)
			hero().order_stop()
			wait(0.5)
		11:
			var squad = _my_squads()[0]
			cmd({"type": "squad_order", "squad": squad.squad_id, "order": "return"})
			wait(0.5)
		12:
			var squad = _my_squads()[0]
			check("squad orders work from anywhere on the map", squad.state == squad.State.RETURN)
			cmd({"type": "squad_order", "squads": [squad.squad_id], "order": "follow"})
			check("Follow me puts the squadron on your hero", squad.state == squad.State.FOLLOW)
			# Ages need feats (cleared lairs or held towers), not only Supplies
			_me.feats = 0
			capture_rejection()
			cmd({"type": "advance_age"})
			check("the Kingdom Age needs a feat", "feat" in _data.toast and tc().age_target == 0, "(%s)" % _data.toast)
			_me.feats = 1
			var before = supplies()
			cmd({"type": "advance_age"})
			check("with a feat the Kingdom Age starts and is paid in Supplies", tc().age_target == 2 and supplies() == before - GameData.price(GameData.AGES[2].cost), "(%d -> %d)" % [before, supplies()])
			tc().age_progress = 0.97  # the minute-long advance is not what we test
			wait(4)
		13:
			check("advanced to Age II (for the whole team)", _me.age == 2 and _match.players_by_slot[1].age == 2 and _match.players_by_slot[2].age == 2, "(age %d)" % _me.age)
			_data.store_spot = free_spot("storehouse", tc().global_position)
			_data.ids = building_ids()
			# a teammate builds for the shared city
			cmd_as(1, {"type": "build", "building": "storehouse", "pos": _data.store_spot})
			wait(1)
		14:
			var s = _site("storehouse")
			check("a teammate placed the storehouse for the shared city", s != null and s.player.slot_index == 1 and _me.buildings("storehouse").has(s))
			capture_rejection()
			cmd({"type": "build", "building": "storehouse", "pos": free_spot("storehouse", tc().global_position, 9.0, 18.0)})
			check("the Storehouse limit is per city, not per player", "only have 1" in _data.toast, "(%s)" % _data.toast)
			if s != null:
				s.progress = 0.97
				s.hp = s.hp_max
			wait(3)
		15:
			var s = _me.buildings("storehouse")[0]
			check("storehouse built", s.is_constructed())
			_data.res_before = supplies()
			s.hp = 0
			wait(1)
		16:
			var expected = int(_data.res_before * GameData.STOREHOUSE_LOSS_FACTOR)
			check("losing the Storehouse halves the team chest", abs(supplies() - expected) <= 60, "(%d -> %d)" % [_data.res_before, supplies()])
			capture_rejection()
			cmd_as(2, {"type": "build", "building": "storehouse", "pos": _data.store_spot})
			wait(0.5)
		17:
			check("Storehouse rebuild has a cooldown for the whole team", "rebuilt in" in _data.toast, "(%s)" % _data.toast)
			# villager respawn is free
			var h = house()
			var v = h.alive_villagers()[0]
			v.hp = 0
			wait(1.5)
		18:
			house().respawn_left = 1.0  # skip most of the respawn delay
			wait(3)
		19:
			check("killed villager is replaced after the delay", house().alive_villagers().size() == GameData.VILLAGERS_PER_HOUSE)
			# ability ranks: R can't be learned before level 6; then learn everything for the test
			capture_rejection()
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
			check("Army of the Dead summons a squadron", _troop_count() >= troops_before + 5)
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
			capture_rejection()
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
			_me.set_resources({"supplies": 8000})
			hero().global_position = tc().global_position + Vector3(0, 0, tc().stats_size() + 1.5)
			hero().order_stop()
			_data.ids = building_ids()
			var spot = free_spot("blacksmith", tc().global_position, 7.0, 16.0)
			_data.smith_spot = spot
			cmd({"type": "build", "building": "blacksmith", "pos": spot})
			wait(0.5)
		24:
			var s = _site("blacksmith")
			check("Blacksmith foundation placed", s != null)
			if s != null:
				s.progress = 0.95  # construction itself is covered above; skip ahead
				s.hp = s.hp_max
			wait(GameData.BUILDINGS.blacksmith.build_time * 0.05 + 3)
		25:
			var smiths = _me.buildings("blacksmith")
			check("Blacksmith built", not smiths.is_empty() and smiths[0].is_constructed())
			_data.dmg_before = GameData.troop_stats(_me.faction, "infantry", _me.upgrades).damage
			var before = supplies()
			cmd({"type": "research", "upgrade": "forged_blades"})
			check("research is paid in Supplies", supplies() == before - GameData.price(GameData.UPGRADES.forged_blades.cost), "(%d -> %d)" % [before, supplies()])
			capture_rejection()
			cmd({"type": "research", "upgrade": "war_drills"})
			var smith = _me.buildings("blacksmith")[0]
			check("research starts at the Blacksmith", smith.research_key == "forged_blades")
			smith.research_left = 2.0
			wait(3)
		26:
			check("Age III research is locked in Age II", "Requires" in _data.toast or "busy" in _data.toast, "(%s)" % _data.toast)
			check("Forged Blades researched (for the whole team)", _me.upgrades.get("forged_blades", false) and _match.players_by_slot[2].upgrades.get("forged_blades", false))
			var dmg_after = GameData.troop_stats(_me.faction, "infantry", _me.upgrades).damage
			check("upgrade raises new troops' damage", dmg_after > _data.dmg_before, "(%.1f -> %.1f)" % [_data.dmg_before, dmg_after])
			# the Empire Age needs three feats; lairs and held towers count
			_me.set_resources({"supplies": 8000})
			_me.feats = 2
			capture_rejection()
			cmd({"type": "advance_age"})
			check("the Empire Age needs three feats", "3 feats" in _data.toast and tc().age_target == 0, "(%s)" % _data.toast)
			_me.feats = 3
			cmd({"type": "advance_age"})
			check("Empire Age advance starts", tc().age_target == 3)
			tc().age_progress = 0.97
			wait(4)
		27:
			check("advanced to the Empire Age", _me.age == 3, "(age %d)" % _me.age)
			_data.ids = building_ids()
			var spot = free_spot("siege_works", tc().global_position, 8.0, 18.0)
			cmd({"type": "build", "building": "siege_works", "pos": spot})
			var special_spot = free_spot("special_building", tc().global_position, 8.0, 18.0)
			cmd({"type": "build", "building": "special_building", "pos": special_spot})
			wait(0.5)
		28:
			check("Siege Works can be placed in Age III", _site("siege_works") != null)
			var sb = _site("special_building")
			check("faction special building uses the faction name", sb != null and sb.display_name == GameData.SPECIAL_BUILDING_NAMES[_me.faction], "(%s)" % (sb.display_name if sb != null else "none"))
			var grond = GameData.troop_stats("mordor", "heavy")
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
			# --- the Shop (v3: Supplies, and the city is run from anywhere) ---
			hero().global_position = tc().global_position + Vector3(0, 0, tc().stats_size() + 1.5)
			hero().order_stop()
			hero().items.clear()
			hero().recompute_stats()
			_me.set_resources({"supplies": 2000})
			_data.dmg = hero().attack_damage
			cmd({"type": "buy", "item": "elven_blade"})
			check("buying an Elven Blade raises attack damage", hero().attack_damage > _data.dmg and supplies() == 2000 - GameData.ITEMS.elven_blade.cost, "(%.0f -> %.0f, chest %d)" % [_data.dmg, hero().attack_damage, supplies()])
			cmd({"type": "buy", "item": "lembas"})
			hero().hp = 100
			cmd({"type": "use_item", "slot": 1})
			check("Lembas heals and is used up", hero().hp > 300 and hero().items.size() == 1, "(hp %d, items %d)" % [hero().hp, hero().items.size()])
			cmd({"type": "sell", "slot": 0})
			check("selling refunds half", hero().items.is_empty() and supplies() == 2000 - GameData.ITEMS.elven_blade.cost - GameData.ITEMS.lembas.cost + int(GameData.ITEMS.elven_blade.cost * GameData.SELL_REFUND), "(chest %d)" % supplies())
			# out on the map the hero can still shop for the team
			hero().global_position = tc().global_position + Vector3(GameData.BASE_RADIUS + 6, 0, 0)
			var chest = supplies()
			cmd({"type": "buy", "item": "lembas"})
			check("the shop works from anywhere on the map", hero().items.size() == 1 and supplies() == chest - GameData.ITEMS.lembas.cost, "(chest %d -> %d)" % [chest, supplies()])
			# a teammate buys from the same chest and the purchase feed names who
			var mate = _match.players_by_slot[1]
			mate.hero.items.clear()
			chest = supplies()
			cmd_as(1, {"type": "buy", "item": "athelas"})
			var latest = _me.spend_log[0] if not _me.spend_log.is_empty() else {}
			check("a teammate spends the shared chest and the feed shows who", mate.hero.items.size() == 1 and supplies() == chest - GameData.ITEMS.athelas.cost and latest.get("who") == mate.player_name and latest.get("what") == GameData.ITEMS.athelas.name, "(%s)" % [latest])
			# --- the Wild ---
			check("jungle camps and the Cave Troll are on the map", _match.camps.size() == MapGen.camp_sites().size() and _match.camps.any(func(c): return c.key == "troll"))
			var camp = null
			for c in _match.camps:
				if c.key == "spiders":
					camp = c
					break
			_data.camp = camp
			var mines = get_tree().get_nodes_in_group("lotr_resources").filter(func(r): return r.global_position_yless.distance_to(camp.pos * Vector3(1, 0, 1)) < 9.0)
			_data.mines = mines
			check("a living lair guards its mine", not mines.is_empty() and mines.all(func(r): return _match.site_guarded(r.global_position)), "(%d mines)" % mines.size())
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
			_data.chest_before = supplies()
			_data.feats_before = _me.feats
			for m in camp.members:
				Combat.deal_damage(hero(), m, 99999, true)
			var spider = GameData.CREATURES.spider
			var reward = 3 * GameData.price({"gold": int(spider.gold * GameData.LAST_HIT_BONUS), "food": spider.food})
			check("clearing a camp pays Supplies to the team chest", supplies() >= _data.chest_before + reward, "(%d -> %d, expected +%d)" % [_data.chest_before, supplies(), reward])
			check("clearing a lair is a feat and opens its mine", _me.feats == _data.feats_before + 1 and _data.mines.all(func(r): return not _match.site_guarded(r.global_position)), "(feats %d -> %d)" % [_data.feats_before, _me.feats])
			# forgotten towers: march targets follow the roads, and standing on a ruin claims it
			var path = _match.route_points(_match.targets.filter(func(t): return t.kind == "tower")[0].index, tc().global_position)
			check("march routes follow the road network", path.size() > 5, "(%d waypoints)" % path.size())
			var free = -1
			for i in range(_match.tower_state.size()):
				if _match.tower_holder(i) == null:
					free = i
					break
			_data.tower = free
			_data.towers_before = _match._team_towers(_me)
			hero().global_position = _match.tower_state[free].site.pos + Vector3(1.5, 0, 0)
			hero().order_stop()
			wait(_match.TOWER_CLAIM_TIME + 1.5)
		32:
			var holder = _match.tower_holder(_data.tower)
			check("standing on a forgotten tower claims it", holder != null and holder.player == _me, "(%s)" % (holder.player.player_name if holder != null else "nobody"))
			check("a held tower counts as a feat for the whole team", _match._team_towers(_me) == _data.towers_before + 1 and _match._team_towers(_match.players_by_slot[2]) == _match._team_towers(_me))
			# walls: a wall dragged across one of our roads gets a gate where it crosses
			var road = _match.lanes.filter(func(l): return l.a == "B0")[0]
			var mid = road.points[3]
			var along = (road.points[4] - road.points[2]).normalized()
			var across = Vector3(-along.z, 0, along.x)
			_data.gates_before = _me.buildings("gate").size()
			_data.walls_before = _me.buildings("wall").size()
			hero().global_position = mid + across * 2.0
			hero().order_stop()
			cmd({"type": "build_wall", "building": "wall", "from": mid - across * 6.0, "to": mid + across * 6.0})
			wait(0.5)
		33:
			check("dragging a wall places wall pieces", _me.buildings("wall").size() > _data.walls_before, "(%d pieces)" % (_me.buildings("wall").size() - _data.walls_before))
			check("a wall across a road gets a gate", _me.buildings("gate").size() > _data.gates_before)
			_finish()


func _site(key):
	"""The unfinished building of this kind that was placed after the last building_ids() snapshot."""
	for b in _me.buildings(key):
		if not b.is_constructed() and not _data.ids.has(b.net_id):
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
