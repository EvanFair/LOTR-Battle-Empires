extends Node
## M5 hordes: formation slots, formations and stances, pike wall vs charge, trample, ranks, reinforce,
## control groups and the selection panel. Team 1 is Rohan (spears, cavalry), team 2 Mordor (riders, trolls).
## Bots are switched off; this script builds the hordes itself.
## Run: godot --headless --fixed-fps 60 --path . res://tests/auto/ArmyTest.tscn

const LoaderScript = preload("res://source/lotr/menu/MatchLoader.gd")
const SelectionPanel = preload("res://source/lotr/hud/widgets/SelectionPanel.gd")

var _match = null
var _me = null
var _foe = null
var _results = []
var _step = 0
var _wait_until = 0.0
var _data = {}
var _watch = ""  # which fight flags to collect each frame


func _ready():
	CommandBus.command_rejected.connect(func(c, reason): _data.toast = reason; print("   (rejected %s: %s)" % [c.type, reason]))
	Network.leave()
	Network.reset_slots()
	for i in range(1, Network.SLOT_COUNT):
		Network.slots[i].kind = "bot"
	for i in range(3):
		Network.slots[i].faction = "rohan"
		Network.slots[i].hero = Network.faction_heroes("rohan")[i % 3]
	var loader = LoaderScript.new()
	loader.settings = {"slots": Network.slots.duplicate(true), "seed": 4242}
	get_tree().root.add_child.call_deferred(loader)


func check(name, condition, detail = ""):
	_results.append([name, condition])
	print("%s  %s %s" % ["PASS" if condition else "FAIL", name, detail])


func cmd(c):
	c["player"] = _me.slot_index
	CommandBus.submit(c)


func cmd_as(slot, c):
	c["player"] = slot
	CommandBus.submit(c)


func wait(seconds):
	_wait_until = GameData.now() + seconds


func tc():
	return _me.town_centers()[0]


func supplies():
	return _me.treasury().supplies


func dir_out() -> Vector3:
	var center = Vector3(MapGen.SIZE / 2.0, 0, MapGen.SIZE / 2.0)
	return (center - tc().global_position).normalized()


func make_squad(p, cls, pos):
	var st = GameData.troop_stats(p.faction, cls, p.upgrades)
	var units = []
	for i in range(st.squad_size):
		var off = Vector3((i % 4) - 1.5, 0, int(i / 4)) * 1.1
		units.append(_match.spawn_unit({"kind": "troop", "faction": p.faction, "class": cls, "upgrades": p.upgrades.duplicate()}, pos + off, p))
	var sq = _match.make_squadron(p, cls, units, pos)
	sq.reinforceable = true
	return sq


func kill_all(sq):
	for m in sq.alive_members():
		m.hp = 0


func _physics_process(_delta):
	if _match == null:
		_match = get_tree().get_first_node_in_group("lotr_match")
		return
	if not _match.started:
		return
	_me = _match.local_player
	_foe = _match.players_by_slot[3]
	if _me.hero != null and _me.hero.is_alive():
		_me.hero.hp = _me.hero.hp_max
	_collect()
	if GameData.now() < _wait_until:
		return
	_run_step()
	_step += 1


func _collect():
	"""Fight flags, sampled every frame."""
	match _watch:
		"pike":
			for r in _data.riders.alive_members():
				if r.bm.longest_remaining(Buff.STUN) > 0.8:
					_data.pike_stun = true
			for m in _data.A.alive_members():
				if m.status.stunned:
					_data.pike_stunned = true
		"charge":
			for m in _data.A.alive_members():
				if m.trampled_until > _data.t0:
					_data.knocked = true
				if m.status.stunned and m.bm.longest_remaining(Buff.STUN) <= 0.55:
					_data.stunned_short = true
		"crush":
			for m in _data.B.alive_members():
				if m.trampled_until > _data.t0:
					_data.crushed = true


func _run_step():
	match _step:
		0:
			for n in _match.get_children():
				if n.name.begins_with("Bot"):
					n.set_physics_process(false)
			_me.set_resources({"supplies": 9000})
			check("Rohan player and Mordor foe", _me.faction == "rohan" and _foe.faction == "mordor")
			var p0 = tc().global_position + dir_out() * 40.0
			_data.p0 = p0
			_data.dir = dir_out()
			var a = make_squad(_me, "infantry", p0)
			_data.A = a
			_data.n = a.max_size
			check("a horde starts at full strength, rank 1, no banner", a.max_size == a.alive_members().size() and a.rank == 1 and a.banner_unit == null, "(%d soldiers)" % a.max_size)
			var forms = Formations.available(a)
			check("spearmen may form Line, Shield Wall, Wedge and Pike Wall", forms == ["line", "shield_wall", "wedge", "pike_wall"], "(%s)" % [forms])
			check("infantry cannot spread out like archers", Formations.refusal(a, "spread") != "")
			a.order_defend(p0 + _data.dir * 32.0)
			wait(5.0)
		1:
			var a = _data.A
			var moved = a.anchor.distance_to(_data.p0)
			var far = 0.0
			for m in a.alive_members():
				far = maxf(far, m.global_position.distance_to(a.center()))
			var lag = a._mean_lag(a.alive_members())
			check("the banner advances with the march", moved > 5.0, "(%.1f m)" % moved)
			check("soldiers keep their slots while marching", far < 7.0 and lag < a.LAG_MAX + 0.5, "(widest %.1f m, mean lag %.1f m)" % [far, lag])
			wait(22.0)
		2:
			var a = _data.A
			var worst = 0.0
			for m in a.alive_members():
				worst = maxf(worst, m.global_position.distance_to(m.slot_pos))
			check("the horde arrives and settles into formation", a.anchor.distance_to(_data.p0 + _data.dir * 32.0) < 1.5 and worst < 2.5, "(worst slot error %.1f m, state %s)" % [worst, a.state_name()])
			var m0 = a.alive_members()[0]
			_data.armour0 = m0.stats.armour
			_data.speed0 = m0.stats.move_speed
			cmd({"type": "squad_formation", "squads": [a.squad_id], "formation": "shield_wall"})
			wait(0.8)
		3:
			var a = _data.A
			var m0 = a.alive_members()[0]
			check("Shield Wall adds armour and slows the horde", a.formation == "shield_wall" and m0.stats.armour > _data.armour0 + 20.0 and m0.stats.move_speed < _data.speed0 * 0.75, "(armour %.0f -> %.0f, speed %.2f -> %.2f)" % [_data.armour0, m0.stats.armour, _data.speed0, m0.stats.move_speed])
			cmd({"type": "squad_formation", "squads": [a.squad_id], "formation": "wedge"})
			var e = make_squad(_foe, "infantry", _data.p0 + _data.dir * 60.0)
			_data.E = e
			wait(0.8)
		4:
			var a = _data.A
			var e = _data.E
			var m = a.alive_members()[0]
			var t = e.alive_members()[0]
			t.hp_max = 5000
			t.hp = 5000
			t.global_position = m.global_position + Vector3(1.0, 0, 0)
			var hp0 = t.hp
			m._pending_hit = {"target": t, "at": 0.0}
			m._land_pending_hit()
			var first = hp0 - t.hp
			var hp1 = t.hp
			m._pending_hit = {"target": t, "at": 0.0}
			m._land_pending_hit()
			var second = hp1 - t.hp
			check("Wedge: the first blow on a target hits 50% harder", second > 0 and abs(first - 1.5 * second) <= 2.0, "(%d then %d)" % [first, second])
			kill_all(e)
			# stances
			cmd({"type": "squad_stance", "squads": [a.squad_id], "stance": "hold"})
			cmd({"type": "squad_formation", "squads": [a.squad_id], "formation": "line"})
			wait(0.8)
		5:
			var a = _data.A
			var m0 = a.alive_members()[0]
			check("Hold Ground: soldiers only fight what is in weapon reach, and gain armour", a.stance == "hold" and m0.aggro_range < 3.0 and m0.stats.armour > 10.0, "(aggro %.1f, armour %.0f)" % [m0.aggro_range, m0.stats.armour])
			cmd({"type": "squad_stance", "squads": [a.squad_id], "stance": "defensive"})
			wait(0.3)
		6:
			var a = _data.A
			var m0 = a.alive_members()[0]
			check("Defensive stance holds a smaller chase radius", a.stance == "defensive" and m0.aggro_range == GameData.STANCES.defensive.radius and a.guard_point.distance_to(a.center()) < 4.0)
			cmd({"type": "squad_stance", "squads": [a.squad_id], "stance": "aggressive"})
			# archers: spread and fire arrows
			var g = make_squad(_me, "archer", _data.p0 + Vector3(0, 0, 6))
			_data.G = g
			capture()
			cmd({"type": "squad_formation", "squads": [g.squad_id], "formation": "fire_arrows"})
			check("Fire Arrows need Forged Blades", g.formation == "line" and "Forged Blades" in _data.toast, "(%s)" % _data.toast)
			cmd({"type": "squad_formation", "squads": [g.squad_id], "formation": "spread"})
			var gm = g.alive_members()[0]
			check("Spread: archers take half area damage", g.formation == "spread" and Formations.aoe_taken(gm) == 0.5)
			_me.upgrades["forged_blades"] = true
			cmd({"type": "squad_formation", "squads": [g.squad_id], "formation": "fire_arrows"})
			wait(0.8)
		7:
			var g = _data.G
			var gm = g.alive_members()[0]
			check("Fire Arrows add damage against buildings", g.formation == "fire_arrows" and gm.stats.damage_vs_buildings >= 0.5, "(+%.0f%%)" % (gm.stats.damage_vs_buildings * 100.0))
			kill_all(g)
			# pike wall against a cavalry charge
			var a = _data.A
			cmd({"type": "squad_formation", "squads": [a.squad_id], "formation": "pike_wall"})
			var riders = make_squad(_foe, "rider", a.center() + _data.dir * 24.0)
			_data.riders = riders
			cmd_as(3, {"type": "squad_formation", "squads": [riders.squad_id], "formation": "charge"})
			riders.order_attack(a.alive_members()[0])
			_data.pike_stun = false
			_data.pike_stunned = false
			_watch = "pike"
			wait(11.0)
		8:
			_watch = ""
			var a = _data.A
			check("Pike Wall: the charge breaks, riders are stunned for 1 s", _data.pike_stun)
			check("Pike Wall: the spearmen are not trampled or stunned", not _data.pike_stunned)
			check("Pike Wall: armour up, speed down", a.formation == "pike_wall" and a.alive_members()[0].stats.move_speed < _data.speed0 * 0.8)
			kill_all(_data.riders)
			# the same charge into a plain line tramples
			cmd({"type": "squad_formation", "squads": [a.squad_id], "formation": "line"})
			wait(1.0)
		9:
			var a = _data.A
			var riders = make_squad(_foe, "rider", a.center() + _data.dir * 24.0)
			_data.riders = riders
			cmd_as(3, {"type": "squad_formation", "squads": [riders.squad_id], "formation": "charge"})
			riders.order_attack(a.alive_members()[0])
			_data.t0 = GameData.now()
			_data.knocked = false
			_data.stunned_short = false
			_watch = "charge"
			wait(10.0)
		10:
			_watch = ""
			check("Charge: infantry in the way are knocked back and stunned", _data.knocked)
			check("Charge: the stun is the short 0.5 s kind", _data.stunned_short)
			kill_all(_data.riders)
			kill_all(_data.A)
			# trolls crush infantry
			var b = make_squad(_me, "infantry", _data.p0 + _data.dir * 20.0)
			_data.B = b
			var trolls = make_squad(_foe, "special", b.center() + _data.dir * 22.0)
			_data.trolls = trolls
			check("Mountain Trolls are crushers", trolls.alive_members()[0].trample_mode == "crush")
			trolls.order_attack(b.alive_members()[0])
			_data.t0 = GameData.now()
			_data.crushed = false
			_watch = "crush"
			wait(14.0)
		11:
			_watch = ""
			check("Trolls trample infantry", _data.crushed)
			kill_all(_data.trolls)
			kill_all(_data.B)
			# ranks
			var c = make_squad(_me, "infantry", _data.p0)
			_data.C = c
			_data.hp0 = c.hp_max_sum()
			_data.dmg0 = GameData.troop_stats(_me.faction, "infantry", _me.upgrades).damage
			wait(1.0)
		12:
			var c = _data.C
			var victim = _match.spawn_unit({"kind": "troop", "faction": "mordor", "class": "infantry"}, c.center() + Vector3(2, 0, 0), _foe)
			var x0 = c.xp
			Combat.deal_damage(c.alive_members()[0], victim, 99999)
			check("a horde earns XP from its kills", c.xp == x0 + Combat.XP_FOR_KILL.troop, "(%d -> %d)" % [x0, c.xp])
			var victim2 = _match.spawn_unit({"kind": "troop", "faction": "mordor", "class": "infantry"}, c.center() + Vector3(2, 0, 1), _foe)
			_me.hero.global_position = c.center() + Vector3(3, 0, 0)
			x0 = c.xp
			Combat.deal_damage(_me.hero, victim2, 99999)
			check("it earns half the XP from kills by its hero nearby", c.xp == x0 + int(round(Combat.XP_FOR_KILL.troop * GameData.HERO_XP_SHARE)), "(%d -> %d)" % [x0, c.xp])
			c.add_xp(GameData.RANK_XP[1] - c.xp)
			wait(1.2)
		13:
			var c = _data.C
			var banners = c.alive_members().filter(func(m): return m.has_banner()).size()
			check("rank 2: one banner carrier appears", c.rank == 2 and banners == 1 and c.banner_unit != null)
			check("rank 2: +10% hit points", c.hp_max_sum() >= int(_data.hp0 * 1.09), "(%d -> %d)" % [_data.hp0, c.hp_max_sum()])
			var sm = _match.replicator.squad_summaries().filter(func(s): return s.id == c.squad_id)[0]
			check("the squad summary carries rank, formation, stance, soldiers, banner", sm.rank == 2 and sm.formation == "line" and sm.stance == "aggressive" and sm.count == c.max_size and sm.banner == c.banner_unit.net_id and sm.hp_max == c.hp_max_sum())
			c.add_xp(GameData.RANK_XP[2] - c.xp)
			wait(1.0)
		14:
			var c = _data.C
			var m = c.alive_members()[0]
			check("rank 3: +15% damage", c.rank == 3 and m.attack_damage * m.damage_mult >= _data.dmg0 * 1.14, "(%.1f -> %.1f)" % [_data.dmg0, m.attack_damage * m.damage_mult])
			# reinforce
			c.auto_reinforce = false
			var ms = c.alive_members()
			ms[0].hp = 0
			ms[1].hp = 0
			wait(1.0)
		15:
			var c = _data.C
			check("losses shrink the horde", c.alive_members().size() == c.max_size - 2)
			capture()
			cmd({"type": "squad_reinforce", "squads": [c.squad_id], "mode": "now"})
			check("reinforcing needs the horde to stand in its city", "city" in _data.toast and c.alive_members().size() == c.max_size - 2, "(%s)" % _data.toast)
			var home = tc().global_position + Vector3(5, 0, 5)
			for m in c.alive_members():
				m.global_position = home
				m.order_stop()
			_data.chest = supplies()
			wait(0.5)
		16:
			var c = _data.C
			cmd({"type": "squad_reinforce", "squads": [c.squad_id], "mode": "now"})
			wait(2.0 * GameData.REINFORCE_INTERVAL + 3.0)
		17:
			var c = _data.C
			var cost = GameData.price(c.soldier_cost())
			check("Reinforce refills the horde over time", c.alive_members().size() == c.max_size, "(%d/%d)" % [c.alive_members().size(), c.max_size])
			check("each replacement soldier costs Supplies", c.reinforce_spent == 2 * cost and _data.chest - supplies() >= cost, "(spent %d, %d each, chest %d -> %d)" % [c.reinforce_spent, cost, _data.chest, supplies()])
			# auto refill when idle in the city
			c.alive_members()[0].hp = 0
			cmd({"type": "squad_reinforce", "squads": [c.squad_id], "mode": "toggle", "enabled": true})
			wait(GameData.REINFORCE_INTERVAL + 3.0)
		18:
			var c = _data.C
			check("auto-refill tops up an idle horde in its city", c.auto_reinforce and c.alive_members().size() == c.max_size, "(%d/%d state %s engaged %s city %s)" % [c.alive_members().size(), c.max_size, c.state_name(), c._engaged, c.in_city(c.center())])
			# control groups
			var hc = _match.hero_controller
			var d = make_squad(_me, "archer", _data.p0 + Vector3(0, 0, 10))
			_data.D = d
			hc.set_selection([c.squad_id, d.squad_id])
			hc.set_control_group(1)
			hc.set_selection([])
			var centered = hc.recall_control_group(1)
			check("a control group recalls its hordes", hc.selected_squads == [c.squad_id, d.squad_id] and not centered)
			var centered2 = hc.recall_control_group(1)
			check("double-tap centres the camera on the group", centered2 and not hc.camera_locked)
			hc.set_selection([], tc())
			hc.set_control_group(2)
			hc.set_selection([])
			hc.recall_control_group(2)
			check("a group can hold a building", hc.selected_building == tc() and hc.selected_squads.is_empty())
			hc.set_selection([c.squad_id, d.squad_id])
			kill_all(d)
			wait(1.0)
		19:
			var hc = _match.hero_controller
			var c = _data.C
			hc.set_selection([])
			hc.recall_control_group(1)
			check("dead hordes drop out of a group", hc.selected_squads == [c.squad_id])
			hc.set_selection([c.squad_id], null)
			hc.remove_squad(c.squad_id)
			check("Shift-click removes a horde from the selection", hc.selected_squads.is_empty())
			# selection panel with mixed hordes
			var r = make_squad(_me, "rider", _data.p0 + Vector3(0, 0, -6))
			_data.R = r
			var panel = SelectionPanel.new()
			panel.match_node = _match
			add_child(panel)
			_data.panel = panel
			panel.set_selection([c.squad_id, r.squad_id])
			panel.refresh()
			check("several hordes show a grid of portraits", panel.mode == "multi" and panel._w.cards.size() == 2 and panel.visible)
			check("mixed hordes share only the formations they all can use", panel._w.formation_btns.is_empty() and panel._w.stance_btns.size() == 3)
			panel.set_selection([r.squad_id])
			panel.refresh()
			check("a cavalry horde offers Line and Charge", panel.mode == "single" and panel._w.formation_btns.keys() == ["line", "charge"])
			panel._on_formation("charge")
			panel._on_stance("hold")
			wait(0.5)
		20:
			var r = _data.R
			var panel = _data.panel
			check("panel buttons go through CommandBus", r.formation == "charge" and r.stance == "hold")
			panel.set_selection([_data.C.squad_id])
			panel.refresh()
			check("a spear horde offers Pike Wall and Reinforce", panel._w.formation_btns.has("pike_wall") and panel._w.has("reinforce"))
			panel.set_selection([], tc())
			panel.refresh()
			check("a building shows its own panel", panel.mode == "building" and panel.visible)
			panel.set_selection([])
			panel.refresh()
			check("an empty selection hides the panel", panel.mode == "" and not panel.visible)
			var ok = true
			for key in GameData.FORMATIONS:
				ok = ok and GameData.FORMATIONS[key].has("layout") and GameData.FORMATIONS[key].has("classes")
			check("formation table is complete", ok)
			_finish()


func capture():
	_data.toast = ""


func _finish():
	set_physics_process(false)
	var failed = _results.filter(func(r): return not r[1])
	print("ARMY RESULT: %s (%d/%d passed)" % ["PASS" if failed.is_empty() else "FAIL", _results.size() - failed.size(), _results.size()])
	get_tree().quit(0 if failed.is_empty() else 1)
