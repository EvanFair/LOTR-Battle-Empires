extends Node
## Combat foundations test (v4 plan A1-A5): stats layers, mitigation, buff add types, hooks, crowd-control
## rules, shields, lifesteal, assists. Runs inside a loaded 3v3 match (bots paused) so real units are used;
## everything is synchronous and game time is advanced by hand.
## Run: godot --headless --fixed-fps 60 --path . res://tests/auto/CombatTest.tscn

const LoaderScript = preload("res://source/lotr/menu/MatchLoader.gd")

var _match = null
var _me = null
var _results = []
var _done = false
var _spawned = []


# --- test buffs ---------------------------------------------------------------------------------
class CountBuff:
	extends Buff
	static var activated = 0
	static var deactivated = 0
	static var expired_flags = []

	func _init(k = "t", seconds = 5.0, kind = Buff.AddType.REPLACE_EXISTING, stack_limit = 1):
		key = k
		duration = seconds
		add_type = kind
		max_stack = stack_limit
		negative = false

	static func reset():
		activated = 0
		deactivated = 0
		expired_flags = []

	func on_activate():
		activated += 1

	func on_deactivate(was_expired):
		deactivated += 1
		expired_flags.append(was_expired)


class HookBuff:
	extends Buff
	var dealt_add = 0.0
	var taken_add = 0.0
	var log = []

	func _init(seconds = 30.0):
		key = "hook"
		duration = seconds
		tick_rate = 1.0

	func on_damage_dealt(ctx):
		ctx.amount += dealt_add
		log.append("dealt")

	func on_before_damage_taken(ctx):
		ctx.amount += taken_add
		log.append("taken")

	func on_hit(_ctx):
		log.append("hit")

	func on_kill(_victim, _ctx):
		log.append("kill")

	func on_death(_ctx):
		log.append("death")

	func on_cast(k):
		log.append("cast_" + k)

	func on_tick(_dt):
		log.append("tick")


func _ready():
	Network.leave()
	Network.reset_slots()
	for i in range(1, Network.SLOT_COUNT):
		Network.slots[i].kind = "bot"
	var loader = LoaderScript.new()
	loader.settings = {"slots": Network.slots.duplicate(true), "seed": 4242}
	get_tree().root.add_child.call_deferred(loader)


func check(name, condition, detail = ""):
	_results.append([name, condition])
	print("%s  %s %s" % ["PASS" if condition else "FAIL", name, detail])


func near(a, b, eps = 0.05) -> bool:
	return absf(a - b) <= eps


func _physics_process(_delta):
	if _done:
		return
	if _match == null:
		_match = get_tree().get_first_node_in_group("lotr_match")
		return
	if not _match.started:
		return
	_done = true
	_me = _match.local_player
	for p in _match.players_by_slot.values():
		var bot = _match.get_node_or_null("Bot%d" % p.slot_index)
		if bot != null:
			bot.set_physics_process(false)
	_run()
	var failed = _results.filter(func(r): return not r[1])
	print("COMBAT RESULT: %s (%d/%d passed)" % ["PASS" if failed.is_empty() else "FAIL", _results.size() - failed.size(), _results.size()])
	get_tree().quit(0 if failed.is_empty() else 1)


# --- helpers ------------------------------------------------------------------------------------
func hero():
	return _me.hero


func enemy_hero():
	for h in get_tree().get_nodes_in_group("heroes"):
		if Teams.is_enemy(h.player, _me) and h.is_alive():
			return h
	return null


func ally_heroes():
	return get_tree().get_nodes_in_group("heroes").filter(func(h): return Teams.is_ally(h.player, _me) and h != hero())


func dummy_troop(enemy = true, offset = 0.0):
	var owner_player = enemy_hero().player if enemy else _me
	var u = _match.spawn_unit({"kind": "troop", "faction": owner_player.faction, "class": "infantry"}, hero().global_position + Vector3(3.0 + offset, 0, 0), owner_player)
	u.auto_acquire = false
	big(u)
	_spawned.append(u)
	return u


func big(u):
	u.stats.set_base("max_hp", 1000000.0)
	u.rebuild_stats()


func advance(seconds, units = []):
	GameData._game_time += seconds
	for u in units:
		if is_instance_valid(u):
			u.bm.process(seconds)


func fresh(u):
	u.bm.clear_all(true)
	return u


func hp_lost(u, fn) -> int:
	var before = u.hp
	fn.call()
	return before - u.hp


func spell(attacker, target, amount, type = Combat.TRUE, tags = ["no_counter"]):
	return Combat.deal_damage(attacker, target, amount, type, Combat.SPELL, tags)


# --- the test -----------------------------------------------------------------------------------
func _run():
	_test_stats()
	_test_mitigation()
	_test_add_types()
	_test_hooks()
	_test_cc()
	_test_diminishing_returns()
	_test_shields()
	_test_lifesteal_and_credit()
	_test_units_and_shims()


func _test_stats():
	var s = Stats.new()
	s.set_base("max_hp", 100.0, 10.0)
	s.set_flat("max_hp", 20.0)
	s.set_percent("max_hp", 0.5)
	s.level = 3
	s.begin()
	s.finish()
	check("stats: (base + per_level*(lvl-1) + flat) * (1 + percent)", near(s.max_hp, (100 + 20 + 20) * 1.5), "(%.1f)" % s.max_hp)
	s.begin()
	s.add_flat(Stats.S.MAX_HP, 10.0)
	s.add_percent(Stats.S.MAX_HP, 0.5)
	s.add_mult(Stats.S.MAX_HP, 1.1)
	s.finish()
	check("stats: temp flat, temp percent and multiplicative layers", near(s.max_hp, 150.0 * 2.0 * 1.1), "(%.1f)" % s.max_hp)
	s.begin()
	s.finish()
	check("stats: begin() clears the temp layer", near(s.max_hp, 210.0))
	s.set_base("move_speed", 10.0)
	s.begin()
	s.add_slow(0.95)
	s.finish()
	check("stats: slow never goes below 30% of base speed", near(s.move_speed, 3.0), "(%.2f)" % s.move_speed)
	s.begin()
	s.add_best_mult(Stats.S.MOVE_SPEED, 1.2)
	s.add_best_mult(Stats.S.MOVE_SPEED, 1.5)
	s.add_best_mult(Stats.S.MOVE_SPEED, 0.8)
	s.add_best_mult(Stats.S.MOVE_SPEED, 0.6)
	s.finish()
	check("stats: only the strongest buff and strongest debuff of a stat apply", near(s.move_speed, 10.0 * 1.5 * 0.6), "(%.2f)" % s.move_speed)
	var h = hero()
	var data = GameData.hero_stats_at_level(h.hero_key, 1)
	check("hero stats seeded from GameData (hp, damage at level 1)", h.hp_max == data.hp and near(h.attack_damage * h.damage_mult, data.damage, 0.5), "(%d vs %d)" % [h.hp_max, data.hp])
	var before_items = h.stats.armour
	var mr_before = h.stats.magic_resist
	h.items.append({"key": "mithril", "ready_at": 0.0})
	h.recompute_stats()
	var expect = Stats.points_from_fraction(0.22)
	check("items feed the temp layer: mithril adds armour and magic resist", near(h.stats.armour - before_items, expect, 0.1) and near(h.stats.magic_resist - mr_before, 20.0), "(+%.1f armour, +%.1f mr)" % [h.stats.armour - before_items, h.stats.magic_resist - mr_before])
	check("legacy armor fraction mirrors armour points", near(h.armor, Stats.fraction_from_points(h.stats.armour), 0.001))
	h.items.clear()
	h.level = 4
	h.recompute_stats()
	var d4 = GameData.hero_stats_at_level(h.hero_key, 4)
	check("level growth: hero max hp at level 4", h.hp_max == d4.hp, "(%d vs %d)" % [h.hp_max, d4.hp])
	h.level = 1
	h.recompute_stats()


func _test_mitigation():
	check("mitigation: 100 armour halves damage", near(Stats.mitigation(100.0), 0.5))
	check("mitigation: 0 armour changes nothing", near(Stats.mitigation(0.0), 1.0))
	check("mitigation: negative armour amplifies, 2 - 100/(100-a)", near(Stats.mitigation(-100.0), 1.5) and near(Stats.mitigation(-50.0), 2.0 - 100.0 / 150.0))
	var h = hero()
	var t = dummy_troop()
	t.stats.set_base("armour", 100.0)
	t.stats.set_base("magic_resist", 0.0)
	t.rebuild_stats()
	var phys = hp_lost(t, func(): spell(h, t, 100.0, Combat.PHYSICAL))
	var magic = hp_lost(t, func(): spell(h, t, 100.0, Combat.MAGIC))
	var true_dmg = hp_lost(t, func(): spell(h, t, 100.0, Combat.TRUE))
	check("physical damage uses armour, magic uses magic resist, true ignores both", phys == 50 and magic == 100 and true_dmg == 100, "(%d / %d / %d)" % [phys, magic, true_dmg])
	t.stats.set_base("armour", -100.0)
	t.stats.set_base("magic_resist", 100.0)
	t.rebuild_stats()
	phys = hp_lost(t, func(): spell(h, t, 100.0, Combat.PHYSICAL))
	magic = hp_lost(t, func(): spell(h, t, 100.0, Combat.MAGIC))
	check("-100 armour deals +50%, 100 magic resist halves magic", phys == 150 and magic == 50, "(%d / %d)" % [phys, magic])
	# penetration
	h.stats.set_flat("armour_pen_flat", 40.0)
	h.rebuild_stats()
	t.stats.set_base("armour", 100.0)
	t.rebuild_stats()
	phys = hp_lost(t, func(): spell(h, t, 100.0, Combat.PHYSICAL))
	h.stats.set_flat("armour_pen_flat", 0.0)
	h.rebuild_stats()
	check("flat armour penetration lowers the armour used", phys == int(round(100.0 * 100.0 / 160.0)), "(%d)" % phys)
	# counters only for basic attacks
	var troop_counter = GameData.counter(h.unit_class, t.target_kind)
	t.stats.set_base("armour", 0.0)
	t.rebuild_stats()
	var basic = hp_lost(t, func(): Combat.deal_damage(h, t, 100.0, Combat.PHYSICAL, Combat.BASIC))
	check("basic attacks use the counter table", basic == int(round(100.0 * troop_counter)), "(%d, x%.2f)" % [basic, troop_counter])


func _test_add_types():
	var t = dummy_troop()
	var a = dummy_troop(true, 1.0)
	var b = dummy_troop(true, 2.0)
	var us = [t]
	# REPLACE_EXISTING
	CountBuff.reset()
	t.bm.add(CountBuff.new("rep", 10.0), a)
	advance(1.0, us)
	t.bm.add(CountBuff.new("rep", 5.0), a)
	check("REPLACE_EXISTING: one stack, new timer, old one deactivated", t.bm.count("rep") == 1 and near(t.bm.remaining("rep"), 5.0) and CountBuff.activated == 2 and CountBuff.deactivated == 1)
	advance(5.1, us)
	check("buff expires and on_deactivate(true) fires", t.bm.count("rep") == 0 and CountBuff.expired_flags.back() == true)
	# RENEW_EXISTING
	fresh(t)
	CountBuff.reset()
	t.bm.add(CountBuff.new("ren", 2.0, Buff.AddType.RENEW_EXISTING), a)
	advance(1.5, us)
	t.bm.add(CountBuff.new("ren", 2.0, Buff.AddType.RENEW_EXISTING), a)
	check("RENEW_EXISTING: same buff kept, timer restarted, no second activation", t.bm.count("ren") == 1 and near(t.bm.remaining("ren"), 2.0) and CountBuff.activated == 1 and CountBuff.deactivated == 0)
	# STACKS_AND_RENEWS
	fresh(t)
	t.bm.add(CountBuff.new("sr", 4.0, Buff.AddType.STACKS_AND_RENEWS, 3), a)
	advance(2.0, us)
	t.bm.add(CountBuff.new("sr", 4.0, Buff.AddType.STACKS_AND_RENEWS, 3), a)
	var first_renewed = near(t.bm.remaining("sr"), 4.0)
	advance(1.0, us)
	t.bm.add(CountBuff.new("sr", 4.0, Buff.AddType.STACKS_AND_RENEWS, 3), a)
	t.bm.add(CountBuff.new("sr", 4.0, Buff.AddType.STACKS_AND_RENEWS, 3), a)
	check("STACKS_AND_RENEWS: stacks up to max_stack and every add renews them all", t.bm.count("sr") == 3 and first_renewed and near(t.bm.remaining("sr"), 4.0), "(%d stacks)" % t.bm.count("sr"))
	advance(3.9, us)
	check("STACKS_AND_RENEWS: all stacks end together", t.bm.count("sr") == 3)
	advance(0.3, us)
	check("STACKS_AND_RENEWS: ...and expire together", t.bm.count("sr") == 0)
	# STACKS_AND_OVERLAPS
	fresh(t)
	t.bm.add(CountBuff.new("ov", 3.0, Buff.AddType.STACKS_AND_OVERLAPS, 5), a)
	advance(2.0, us)
	t.bm.add(CountBuff.new("ov", 3.0, Buff.AddType.STACKS_AND_OVERLAPS, 5), a)
	check("STACKS_AND_OVERLAPS: independent copies", t.bm.count("ov") == 2)
	advance(1.2, us)
	check("STACKS_AND_OVERLAPS: the older copy expires first, the newer keeps going", t.bm.count("ov") == 1 and near(t.bm.remaining("ov"), 1.8, 0.1), "(%.2f)" % t.bm.remaining("ov"))
	# STACKS_AND_CONTINUE
	fresh(t)
	CountBuff.reset()
	t.bm.add(CountBuff.new("co", 2.0, Buff.AddType.STACKS_AND_CONTINUE, 3), a)
	t.bm.add(CountBuff.new("co", 2.0, Buff.AddType.STACKS_AND_CONTINUE, 3), a)
	check("STACKS_AND_CONTINUE: the second stack is queued, not active", t.bm.count("co") == 2 and CountBuff.activated == 1)
	advance(1.0, us)
	check("STACKS_AND_CONTINUE: still queued after 1 s", CountBuff.activated == 1)
	advance(1.5, us)
	check("STACKS_AND_CONTINUE: the queued stack starts when the first ends", CountBuff.activated == 2 and t.bm.count("co") == 1 and near(t.bm.remaining("co"), 1.5, 0.1), "(%.2f)" % t.bm.remaining("co"))
	# stacks_exclusive: per source
	fresh(t)
	t.bm.add(CountBuff.new("ex", 5.0), a)
	t.bm.add(CountBuff.new("ex", 5.0), b)
	check("stacks_exclusive: each source keeps its own entry", t.bm.count("ex") == 2 and t.bm.count("ex", a) == 1 and t.bm.count("ex", b) == 1)
	fresh(t)
	var shared1 = CountBuff.new("ex2", 5.0)
	shared1.stacks_exclusive = false
	var shared2 = CountBuff.new("ex2", 5.0)
	shared2.stacks_exclusive = false
	t.bm.add(shared1, a)
	t.bm.add(shared2, b)
	check("stacks_exclusive = false: sources share one slot", t.bm.count("ex2") == 1)
	# cleanse by type
	fresh(t)
	t.bm.add(StunBuff.new(5.0), a)
	t.bm.add(SlowBuff.new(0.3, 5.0), a)
	t.bm.add(HasteBuff.new(0.3, 5.0), a)
	var n = t.bm.cleanse(Buff.SLOW)
	check("cleanse(SLOW) removes only the slow", n == 1 and not t.bm.has_key("slow") and t.bm.has_key("stun") and t.bm.has_key("haste"))
	t.bm.cleanse()
	check("cleanse() removes every debuff but keeps buffs", not t.bm.has_key("stun") and t.bm.has_key("haste") and not t.status.stunned)
	var stubborn = SlowBuff.new(0.3, 5.0)
	stubborn.non_dispellable = true
	t.bm.add(stubborn, a)
	t.bm.cleanse()
	check("non-dispellable debuffs survive a cleanse", t.bm.has_key("slow"))
	t.bm.remove_by_type(Buff.HASTE)
	check("remove_by_type dispels buffs too", not t.bm.has_key("haste"))
	fresh(t)


func _test_hooks():
	var h = hero()
	var t = dummy_troop()
	t.stats.set_base("armour", 100.0)
	t.rebuild_stats()
	var attacker_buff = HookBuff.new()
	attacker_buff.dealt_add = 100.0
	var victim_buff = HookBuff.new()
	victim_buff.taken_add = -10.0
	h.bm.add(attacker_buff, h)
	t.bm.add(victim_buff, h)
	var lost = hp_lost(t, func(): Combat.deal_damage(h, t, 100.0, Combat.PHYSICAL, Combat.BASIC, ["no_counter"]))
	# (100 + 100 dealt hook) * 0.5 armour = 100, then -10 from the taken hook
	check("pipeline order: dealt hooks, mitigation, taken hooks", lost == 90, "(%d, expected 90)" % lost)
	check("on_hit fires for a basic attack and not for a spell", attacker_buff.log.has("hit"))
	attacker_buff.log.clear()
	spell(h, t, 10.0, Combat.TRUE)
	check("...a spell fires on_damage_dealt but not on_hit", attacker_buff.log.has("dealt") and not attacker_buff.log.has("hit"))
	h.bm.fire_cast("Q")
	check("on_cast hook", attacker_buff.log.has("cast_Q"))
	advance(2.1, [h])
	check("on_tick fires every tick_rate", attacker_buff.log.count("tick") == 2, "(%d)" % attacker_buff.log.count("tick"))
	# kill and death hooks
	var weak = dummy_troop()
	weak.stats.set_base("max_hp", 50.0)
	weak.rebuild_stats()
	weak.hp = 50
	var death_buff = HookBuff.new()
	weak.bm.add(death_buff, h)
	spell(h, weak, 500.0, Combat.TRUE)
	check("on_kill fires on the killer and on_death on the victim", attacker_buff.log.has("kill") and death_buff.log.has("death"))
	h.bm.remove_buff(attacker_buff)
	# on_before_damage_taken can cancel
	var t2 = dummy_troop()
	var shield_all = HookBuff.new()
	shield_all.taken_add = -1000000.0
	t2.bm.add(shield_all, h)
	check("a taken hook can cancel a hit", hp_lost(t2, func(): spell(h, t2, 100.0)) == 0)


func _test_cc():
	var h = hero()
	var t = dummy_troop()
	var us = [t]
	t.bm.add(StunBuff.new(2.0), h)
	check("stun sets status flags (can't move, attack or cast)", t.status.stunned and not t.status.can_move and not t.status.can_attack and not t.status.can_cast and t.is_stunned())
	advance(2.1, us)
	check("stun expires and clears the flags", not t.status.stunned and t.status.can_attack and not t.is_stunned())
	# hard CC overwrites
	t.bm.add(StunBuff.new(5.0), h)
	t.bm.add(KnockupBuff.new(1.0), h)
	check("a new hard CC overwrites the old one (even a longer stun)", not t.bm.has_key("stun") and t.bm.has_key("knockup") and t.status.airborne)
	fresh(t)
	# roots take the longer duration
	t.bm.add(RootBuff.new(3.0), h)
	t.bm.add(RootBuff.new(1.0), h)
	check("a shorter root does not shorten the active one", near(t.bm.remaining("root"), 3.0))
	fresh(t)
	t.bm.add(RootBuff.new(1.0), h)
	t.bm.add(RootBuff.new(3.0), h)
	check("a longer root replaces the shorter one", near(t.bm.remaining("root"), 3.0) and t.bm.count("root") == 1)
	check("rooted units can still attack and cast", t.status.rooted and t.status.can_attack and t.status.can_cast and not t.status.can_move)
	fresh(t)
	# slows
	var base = t.stats.base_move_speed
	var other = dummy_troop(false)
	t.bm.add(SlowBuff.new(0.3, 5.0), h)
	t.bm.add(SlowBuff.new(0.5, 5.0), other)
	check("slows: the strongest of several sources applies", near(t.stats.move_speed, base * 0.5, 0.01), "(%.2f of %.2f)" % [t.stats.move_speed, base])
	t.bm.add(SlowBuff.new(0.2, 5.0), other)
	check("slows: one entry per source (a new one replaces the old)", t.bm.count("slow", other) == 1 and near(t.stats.move_speed, base * 0.7, 0.01), "(%.2f)" % t.stats.move_speed)
	t.bm.add(SlowBuff.new(0.95, 5.0), h)
	check("slows: floor of 30% of base speed", near(t.stats.move_speed, base * 0.3, 0.01), "(%.2f)" % t.stats.move_speed)
	fresh(t)
	check("slow ends: speed back to normal", near(t.stats.move_speed, base, 0.01))
	# tenacity
	t.bm.add(StatModBuff.new("test_tenacity", 60.0).flat("tenacity", 0.5), t)
	t.bm.add(StunBuff.new(2.0), h)
	var stun_left = t.bm.remaining("stun")
	t.bm.cleanse()
	t.bm.add(KnockupBuff.new(2.0), h)
	var knock_left = t.bm.remaining("knockup")
	t.bm.cleanse()
	t.bm.add(RootBuff.new(2.0), h)
	var root_left = t.bm.remaining("root")
	t.bm.cleanse()
	t.bm.add(SlowBuff.new(0.4, 2.0), h)
	var slow_left = t.bm.remaining("slow")
	check("tenacity 50% halves stun, root and slow but not knock-ups", near(stun_left, 1.0) and near(root_left, 1.0) and near(slow_left, 1.0) and near(knock_left, 2.0), "(%.1f %.1f %.1f / knockup %.1f)" % [stun_left, root_left, slow_left, knock_left])
	fresh(t)
	# unstoppable
	t.bm.add(StunBuff.new(3.0), h)
	t.bm.add(UnstoppableBuff.new(5.0), t)
	check("unstoppable cleanses existing crowd control", not t.status.stunned and t.status.unstoppable)
	var blocked_stun = t.bm.add(StunBuff.new(2.0), h)
	var blocked_slow = t.bm.add(SlowBuff.new(0.5, 2.0), h)
	check("unstoppable blocks stuns and slows", blocked_stun == null and blocked_slow == null and not t.status.stunned)
	var lost = hp_lost(t, func(): spell(h, t, 100.0))
	check("unstoppable still takes damage", lost == 100)
	fresh(t)
	# disarm / silence flags
	t.bm.add(DisarmBuff.new(2.0), h)
	t.bm.add(SilenceBuff.new(2.0), h)
	check("disarm stops basic attacks, silence stops casts", not t.status.can_attack and not t.status.can_cast and t.status.can_move)
	fresh(t)
	# buildings are never crowd-controlled
	var tc = _me.town_centers()[0]
	check("buildings ignore crowd control", tc.bm.add(StunBuff.new(2.0), h) == null)
	# dots and grievous wounds
	var d = dummy_troop()
	d.bm.add(DotBuff.new(10.0, 3.0, 1.0, Combat.TRUE), h)
	var before = d.hp
	advance(3.1, [d])
	check("DOT ticks through the damage pipeline", before - d.hp == 30, "(%d)" % (before - d.hp))
	d.hp = d.hp_max - 1000
	d.bm.add(GrievousWoundsBuff.new(0.4, 5.0), h)
	var healed = Combat.heal(h, d, 100.0)
	check("grievous wounds cut healing by 40%", healed == 60, "(%d)" % healed)
	# marks
	d.bm.clear_all(true)
	d.bm.add(MarkBuff.new(0.5, 5.0, true), h)
	var marked = hp_lost(d, func(): spell(h, d, 100.0))
	var after_mark = hp_lost(d, func(): spell(h, d, 100.0))
	check("a mark amplifies its owner's damage once when consumed", marked == 150 and after_mark == 100, "(%d then %d)" % [marked, after_mark])
	# stealth breaks on damage
	h.bm.add(StealthBuff.new(5.0), h)
	var was_stealth = h.status.stealthed
	spell(h, d, 1.0)
	check("stealth is a status flag and breaks when the unit deals damage", was_stealth and not h.status.stealthed)


func _test_diminishing_returns():
	var h = hero()
	var eh = enemy_hero()
	big(eh)
	fresh(eh)
	var results = []
	for i in range(4):
		var b = eh.bm.add(StunBuff.new(2.0), h)
		results.append(b.duration if b != null else -1.0)
		eh.bm.cleanse()
		advance(0.5, [eh])
	check("hero DR: 100%, 50%, 25%, then immune", near(results[0], 2.0) and near(results[1], 1.0) and near(results[2], 0.5) and results[3] < 0.0, "(%s)" % str(results))
	advance(3.2, [eh])
	var later = eh.bm.add(StunBuff.new(2.0), h)
	check("hero DR: the immunity ends after 3 s", later != null and near(later.duration, 2.0), "(%s)" % (str(later.duration) if later != null else "blocked"))
	eh.bm.cleanse()
	advance(7.0, [eh])
	var reset = eh.bm.add(StunBuff.new(2.0), h)
	check("hero DR: counter resets after 6 s", reset != null and near(reset.duration, 2.0))
	eh.bm.cleanse()
	fresh(eh)
	# a different CC type has its own counter
	eh.bm.add(StunBuff.new(2.0), h)
	eh.bm.cleanse()
	var root = eh.bm.add(RootBuff.new(2.0), h)
	check("hero DR: each CC type counts separately", root != null and near(root.duration, 2.0))
	fresh(eh)
	# slows have no DR; troops none at all
	var t = dummy_troop()
	var troop_durations = []
	for i in range(4):
		var b = t.bm.add(StunBuff.new(2.0), h)
		troop_durations.append(b.duration if b != null else -1.0)
		t.bm.cleanse()
	check("troops have no diminishing returns", troop_durations == [2.0, 2.0, 2.0, 2.0], "(%s)" % str(troop_durations))
	var slow_durations = []
	for i in range(4):
		var b = eh.bm.add(SlowBuff.new(0.3, 2.0), h)
		slow_durations.append(b.duration)
	check("slows are not subject to diminishing returns", slow_durations == [2.0, 2.0, 2.0, 2.0])
	fresh(eh)
	# DR then tenacity multiply
	eh.bm.add(StatModBuff.new("test_tenacity", 60.0).flat("tenacity", 0.5), eh)
	var first = eh.bm.add(StunBuff.new(2.0), h)
	eh.bm.cleanse()
	var second = eh.bm.add(StunBuff.new(2.0), h)
	check("tenacity and DR multiply", near(first.duration, 1.0) and near(second.duration, 0.5), "(%.2f, %.2f)" % [first.duration, second.duration])
	fresh(eh)


func _test_shields():
	var h = hero()
	var t = dummy_troop()
	var a = dummy_troop(false, 1.0)
	var b = dummy_troop(false, 2.0)
	Combat.shield(a, t, 100.0, 5.0)
	check("a shield absorbs damage", hp_lost(t, func(): spell(h, t, 60.0)) == 0 and near(t.bm.shield_total(), 40.0))
	Combat.shield(a, t, 100.0, 5.0)
	check("recasting from the same source stacks the amount", near(t.bm.shield_total(), 140.0) and t.bm.count("shield") == 1, "(%.0f)" % t.bm.shield_total())
	Combat.shield(a, t, 100.0, 5.0)
	Combat.shield(a, t, 100.0, 5.0)
	check("same-source shield stacking caps at 2x one cast", near(t.bm.shield_total(), 200.0), "(%.0f)" % t.bm.shield_total())
	fresh(t)
	# earliest expiring first, regardless of cast order
	Combat.shield(b, t, 50.0, 8.0)
	Combat.shield(a, t, 50.0, 3.0)
	check("one shield entry per source", t.bm.count("shield") == 2 and near(t.bm.shield_total(), 100.0))
	var lost = hp_lost(t, func(): spell(h, t, 70.0))
	var remaining_source_b = t.bm.get_buff("shield", b)
	check("the shield expiring first drains first", lost == 0 and t.bm.get_buff("shield", a) == null and remaining_source_b != null and near(remaining_source_b.value, 30.0), "(lost %d)" % lost)
	lost = hp_lost(t, func(): spell(h, t, 50.0))
	check("damage beyond the shields hurts", lost == 20 and t.bm.shield_total() == 0.0)
	# shields come after mitigation
	t.stats.set_base("armour", 100.0)
	t.rebuild_stats()
	Combat.shield(a, t, 60.0, 5.0)
	lost = hp_lost(t, func(): spell(h, t, 200.0, Combat.PHYSICAL))
	check("shields absorb after armour (200 -> 100 -> 60 absorbed -> 40 lost)", lost == 40, "(%d)" % lost)
	t.stats.set_base("armour", 0.0)
	t.rebuild_stats()
	# shield expiry
	Combat.shield(a, t, 50.0, 2.0)
	advance(2.1, [t])
	check("shields expire", t.bm.shield_total() == 0.0)
	fresh(t)


func _test_lifesteal_and_credit():
	var h = hero()
	var t = dummy_troop()
	h.hp = h.hp_max - 300
	h.bm.add(StatModBuff.new("test_lifesteal", 60.0).flat("lifesteal", 0.9), h)
	check("lifesteal stat is capped to 1.0 in Stats, 35% in Combat", h.stats.lifesteal > 0.35)
	var before = h.hp
	Combat.deal_damage(h, t, 100.0, Combat.TRUE, Combat.BASIC, ["no_counter"])
	check("lifesteal heals at most 35% of basic attack damage", h.hp - before == 35, "(+%d)" % (h.hp - before))
	before = h.hp
	spell(h, t, 100.0)
	Combat.deal_damage(h, t, 100.0, Combat.TRUE, Combat.DOT, [])
	Combat.deal_damage(h, t, 100.0, Combat.TRUE, Combat.BASIC, ["no_counter", "no_lifesteal"])
	check("no lifesteal from spells, DOTs or no_lifesteal hits", h.hp == before, "(+%d)" % (h.hp - before))
	h.bm.cleanse()
	h.bm.clear_all(true)
	# assists
	var allies = ally_heroes()
	var eh = enemy_hero()
	if allies.size() >= 2 and eh != null:
		var a1 = allies[0]
		var a2 = allies[1]
		big(eh)
		eh.credit.clear()
		spell(a1, eh, 10.0)
		eh.bm.add(SlowBuff.new(0.3, 2.0), a2)
		var list = Combat.assists_for(eh, h)
		check("assists: heroes who damaged or CC'd the victim are credited", list.has(a1) and list.has(a2) and not list.has(h), "(%d)" % list.size())
		advance(9.0)
		check("assists: still credited 9 s later", Combat.assists_for(eh, h).has(a1))
		advance(1.5)
		check("assists: the window closes after 10 s", Combat.assists_for(eh, h).size() == 0)
		h.support.clear()
		Combat.heal(a1, h, 5.0)
		Combat.shield(a2, h, 50.0, 3.0)
		var sup = Combat.assists_for(eh, h)
		check("assists: allies who healed or shielded the killer count", sup.has(a1) and sup.has(a2))
		var weak = eh
		weak.hp = 1
		var killer_slot_hero = a1
		spell(killer_slot_hero, weak, 50.0)
		check("the kill records killer and assists", weak.last_credit.has("killer") and weak.last_credit.killer == killer_slot_hero)
	else:
		check("assists: needs allied heroes", false)


func _test_units_and_shims():
	var t = dummy_troop()
	var base_speed_mult = t.speed_mult
	t.apply_buff("speed", 0.5, 4.0)
	check("legacy apply_buff('speed', 0.5) is now a slow", t.bm.has_key("slow") and t.speed_mult < 1.0 and near(t.stats.move_speed, t.stats.base_move_speed * 0.5, 0.01))
	t.apply_buff("damage", 1.25, 4.0)
	check("legacy apply_buff('damage') multiplies attack damage", near(t.damage_mult, 1.25))
	t.apply_buff("damage", 1.4, 4.0, hero())
	check("two damage buffs: the strongest applies", near(t.damage_mult, 1.4))
	t.apply_buff("armor", 0.3, 4.0)
	check("legacy armour buff raises armour", t.armor > 0.29 and near(t.stats.armour, t.stats.armour_before_buffs + Stats.points_from_fraction(0.3), 0.01), "(%.2f)" % t.armor)
	var list = t.buff_list()
	check("buff_list() entries carry key, icon, stacks, remaining, duration, negative", list.size() >= 3 and list[0].has_all(["key", "icon", "stacks", "remaining", "duration", "negative"]))
	t.stun(1.0)
	check("stun() shim sets stunned and stunned_until", t.is_stunned() and t.stunned_until > GameData.now())
	var net = t.bm.to_net()
	check("to_net() is a compact [key, stacks, remaining, duration] list", net.size() >= 4 and net[0].size() == 4)
	var mask = t.status.to_mask()
	var s2 = Status.new()
	s2.from_mask(mask)
	check("status flags round-trip through the replication mask", s2.stunned and not s2.silenced and not s2.can_move)
	fresh(t)
	# real attacks: a troop's swing goes through the pipeline
	var enemy = dummy_troop()
	t.global_position = enemy.global_position + Vector3(1.0, 0, 0)
	var dealt = Combat.deal_damage(t, enemy, 40.0)
	check("a troop's basic attack deals counter-adjusted damage", dealt > 0)
	# hero cast with magic damage type
	var h = hero()
	var old_key = h.hero_key
	h.hero_key = "saruman"
	h.ranks["Q"] = 1
	h.cooldowns.clear()
	h.mana = h.mana_max
	var target = dummy_troop()
	target.stats.set_base("magic_resist", 100.0)
	target.stats.set_base("armour", 0.0)
	target.rebuild_stats()
	var fireball_hp = hp_lost(target, func(): HeroAbilities.hit(h, target, GameData.ability_at_rank(GameData.HEROES.saruman.abilities[0], 1)))
	check("magic abilities (Saruman Q) are mitigated by magic resist", fireball_hp == int(round(85 * 0.5)), "(%d)" % fireball_hp)
	h.hero_key = "boromir"
	HeroAbilities.hit(h, target, {"kind": "strike", "damage": 0.0, "stun": 1.0})
	check("ability hit() stuns through the BuffManager", target.is_stunned())
	h.hero_key = old_key
