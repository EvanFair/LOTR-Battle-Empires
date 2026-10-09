extends "res://source/lotr/units/LotrUnit.gd"
## The only unit a player controls directly. Levels up from XP, casts QWER abilities, and
## respawns at its Town Center after a timer that grows with level.

signal leveled_up(level)
signal death_state_changed(dead)

var hero_key = "aragorn"
var level = 1
var xp = 0
var mana = 0.0
var mana_max = 0.0
var mana_regen = 2.0
var hp_regen = 0.0  # per second, from Stats
var ability_power = 0.0
var ability_haste = 0.0
var crit_chance = 0.0
var magic_resist = 0.0  # damage reduction fraction (stats.magic_resist is in points)
var dead = false
var respawn_at = 0.0
var cooldowns = {}  # ability key -> time (s) when ready again
var ranks = {}  # ability key -> learned rank (0 = not learned)
var items = []  # up to GameData.ITEM_SLOTS dicts: {key, ready_at}
var pending_cast = null  # {key, target}: walking into range of a unit-target ability
var home_position = Vector3.ZERO
var recall_until = 0.0  # > 0 while channelling Recall
var _recall_hp = 0
var _hp_carry = 0.0

const RECALL_TIME = 6.0


func _ready():
	await super()
	auto_acquire = false  # heroes only fight when told to (or when attacked, see below)
	home_position = global_position


func is_alive():
	return super() and not dead


func abilities():
	return GameData.HEROES[hero_key].abilities


func ability(key: String):
	for a in abilities():
		if a.key == key:
			return a
	return null


func ability_rank(key: String) -> int:
	return ranks.get(key, 0)


func skill_points() -> int:
	var spent = 0
	for key in ranks:
		spent += ranks[key]
	return level - spent


func can_learn(key: String) -> String:
	"""'' if a skill point can go into this ability now, otherwise why not."""
	if ability(key) == null:
		return "No such ability"
	var next = ability_rank(key) + 1
	if next > GameData.ABILITY_MAX_RANK:
		return "Already at max rank"
	if skill_points() <= 0:
		return "No skill points (you get one per level)"
	if level < GameData.ability_rank_level(key, next):
		return "Needs hero level %d" % GameData.ability_rank_level(key, next)
	return ""


func learn(key: String) -> String:
	var err = can_learn(key)
	if err == "":
		ranks[key] = ability_rank(key) + 1
	return err


func notify_cast(animate = true):
	cancel_recall()
	if animate and anim_driver != null:
		anim_driver.play_cast()


func cooldown_left(key: String) -> float:
	return max(0.0, cooldowns.get(key, 0.0) - GameData.now())


func add_xp(amount: int):
	xp += amount
	var new_level = GameData.level_for_xp(xp)
	while level < new_level:
		_level_up()


func _level_up():
	level += 1
	recompute_stats()
	leveled_up.emit(level)
	_fx("level_up")


func item_bonus(stat: String) -> float:
	var total = 0.0
	for it in items:
		total += GameData.ITEMS[it.key].get("stats", {}).get(stat, 0.0)
	return total


func recompute_stats():
	"""Level, items and buffs into Stats (keeps current HP/mana, adding any max increase)."""
	rebuild_stats()


func _stat_level() -> int:
	return level


func _seed_stats():
	"""Base + growth per level from GameData.HEROES (legends get the tier bonus)."""
	var data = GameData.HEROES[hero_key]
	var tier = GameData.LEGEND_BONUS if data.get("tier", "captain") == "legend" else 1.0
	stats.set_base("max_hp", data.hp * tier, data.hp_per_level * tier)
	stats.set_base("attack_damage", data.damage * tier, data.damage_per_level * tier)
	stats.set_base("attack_speed", 1.0 / maxf(0.05, data.interval))
	stats.set_base("attack_range", data.range)
	stats.set_base("move_speed", data.speed)
	stats.set_base("max_mana", data.mana)
	stats.set_base("mana_regen", data.get("mana_regen", 2.0))
	stats.set_base("hp_regen", data.get("hp_regen", 0.0))
	stats.set_base("armour", data.get("armour", 0.0))
	stats.set_base("magic_resist", data.get("magic_resist", 0.0))
	stats.set_base("ability_power", data.get("ability_power", 0.0))


func _contribute_stats(s):
	"""Items into the temp layer (old item stat keys: hp, mana, mana_regen, damage, attack_speed and
	speed are fractions/flats as before; armor is a damage-reduction fraction capped at 60%;
	mr, ap, armour, hp_regen, lifesteal, tenacity, ability_haste and crit are the v4 additions)."""
	var armor_fraction = 0.0
	for it in items:
		var st = GameData.ITEMS[it.key].get("stats", {})
		for k in st:
			var v = st[k]
			match k:
				"hp":
					s.add_flat(Stats.S.MAX_HP, v)
				"mana":
					s.add_flat(Stats.S.MAX_MANA, v)
				"mana_regen":
					s.add_flat(Stats.S.MANA_REGEN, v)
				"hp_regen":
					s.add_flat(Stats.S.HP_REGEN, v)
				"damage":
					s.add_flat(Stats.S.ATTACK_DAMAGE, v)
				"attack_speed":
					s.add_percent(Stats.S.ATTACK_SPEED, v)
				"speed":
					s.add_percent(Stats.S.MOVE_SPEED, v)
				"armor":
					armor_fraction += v
				"armour":
					s.add_flat(Stats.S.ARMOUR, v)
				"mr":
					s.add_flat(Stats.S.MAGIC_RESIST, v)
				"ap":
					s.add_flat(Stats.S.ABILITY_POWER, v)
				"lifesteal":
					s.add_flat(Stats.S.LIFESTEAL, v)
				"tenacity":
					s.add_flat(Stats.S.TENACITY, v)
				"ability_haste":
					s.add_flat(Stats.S.ABILITY_HASTE, v)
				"crit":
					s.add_flat(Stats.S.CRIT_CHANCE, v)
	if armor_fraction > 0.0:
		s.add_flat(Stats.S.ARMOUR, Stats.points_from_fraction(minf(0.6, armor_fraction)))


func _sync_extra(first):
	var new_max = stats.max_mana
	if first or not _synced.has("mana"):
		mana_max = new_max
		mana = mana_max
	elif new_max != _synced.mana:
		var diff = new_max - _synced.mana
		mana_max += diff
		mana = min(mana_max, mana + max(0.0, diff))
	_synced.mana = new_max
	mana_regen = stats.mana_regen
	hp_regen = stats.hp_regen
	ability_power = stats.ability_power
	ability_haste = stats.ability_haste
	crit_chance = stats.crit_chance
	magic_resist = stats.magic_fraction()


# --- items (host) ---------------------------------------------------------------------------------
func buy_item(key: String) -> String:
	if not GameData.ITEMS.has(key):
		return "No such item"
	var data = GameData.ITEMS[key]
	if items.size() >= GameData.ITEM_SLOTS:
		return "Your bags are full (%d items). Sell something first" % GameData.ITEM_SLOTS
	if not player.has_resources({"gold": data.cost}):
		return player.missing_text({"gold": data.cost})
	player.subtract_resources({"gold": data.cost})
	player.log_spend(data.name, data.cost)
	items.append({"key": key, "ready_at": 0.0})
	recompute_stats()
	return ""


func sell_item(slot: int) -> String:
	if slot < 0 or slot >= items.size():
		return "Nothing in that slot"
	var data = GameData.ITEMS[items[slot].key]
	player.add_resources({"gold": int(data.cost * GameData.SELL_REFUND)})
	items.remove_at(slot)
	recompute_stats()
	return ""


func use_item(slot: int) -> String:
	if slot < 0 or slot >= items.size():
		return "Nothing in that slot"
	var it = items[slot]
	var data = GameData.ITEMS[it.key]
	var now = GameData.now()
	if data.get("consumable", false):
		var use = data.use
		Combat.heal(self, self, float(use.get("heal", 0)))
		mana = min(mana_max, mana + use.get("mana", 0.0))
		items.remove_at(slot)
		_fx("respawn")
		return ""
	if not data.has("active"):
		return "%s has no use ability" % data.name
	if now < it.ready_at:
		return "%s is recharging (%ds)" % [data.name, ceili(it.ready_at - now)]
	var a = data.active
	for u in get_tree().get_nodes_in_group("units"):
		if not u.is_alive() or u.unit_kind not in ["hero", "troop"] or not Teams.is_ally(u.player, player):
			continue
		if u.global_position.distance_to(global_position) > a.radius:
			continue
		if a.has("heal"):
			Combat.heal(self, u, float(a.heal))
		if a.has("stat"):
			u.apply_buff(a.stat, a.mult, a.duration, self)
	it.ready_at = now + a.cooldown
	var match_node = get_tree().get_first_node_in_group("lotr_match")
	match_node.fx("nova", global_position, global_position + Vector3(a.radius, 0, 0))
	return ""


func _physics_process(delta):
	if puppet:
		return
	if dead:
		if player.defeated:
			return
		if GameData.now() >= respawn_at:
			_respawn()
		return
	mana = min(mana_max, mana + mana_regen * delta)
	if hp_regen > 0.0 and hp < hp_max:
		_hp_carry += hp_regen * bm.heal_mod() * delta
		if _hp_carry >= 1.0:
			hp = min(hp_max, hp + int(_hp_carry))
			_hp_carry -= int(_hp_carry)
	_fountain_tick(delta)
	if recall_until > 0.0:
		_recall_tick()
	if pending_cast != null:
		_pending_cast_tick()
	super(delta)


const FOUNTAIN_RANGE = 10.0
const FOUNTAIN_HP_PER_SEC = 0.06  # fraction of max per second at your own Town Center
const FOUNTAIN_MANA_PER_SEC = 0.08


func _fountain_tick(delta):
	"""Like the fountain in League of Legends: your hero heals fast next to your Town Center."""
	var tc = _find_town_center()
	if tc == null or global_position_yless.distance_to(tc.global_position_yless) > FOUNTAIN_RANGE + tc.stats_size():
		return
	_fountain_carry += hp_max * FOUNTAIN_HP_PER_SEC * delta
	if _fountain_carry >= 1.0:
		hp = min(hp_max, hp + int(_fountain_carry))
		_fountain_carry -= int(_fountain_carry)
	mana = min(mana_max, mana + mana_max * FOUNTAIN_MANA_PER_SEC * delta)


var _fountain_carry = 0.0


func queue_cast(key: String, target):
	order_attack(target)
	pending_cast = {"key": key, "target": target}


func _pending_cast_tick():
	var target = pending_cast.target
	if order != Order.ATTACK or order_target != target or not is_instance_valid(target) or not target.is_alive():
		pending_cast = null  # a new order replaced it
		return
	var a = ability(pending_cast.key)
	if global_position_yless.distance_to(target.global_position_yless) <= a.get("range", 2.5) + 0.6:
		var key = pending_cast.key
		pending_cast = null
		var match_node = get_tree().get_first_node_in_group("lotr_match")
		var err = HeroAbilities.cast(match_node, self, key, target.global_position, target)
		if err != "":
			match_node.toast_player(player.slot_index, err)


func _process_idle(delta):
	# heroes don't chase things on their own, but they hit back at whatever is next to them
	if order == Order.HOLD or attack_damage == null:
		return
	_retarget_timer -= delta
	if _retarget_timer > 0.0:
		return
	_retarget_timer = RETARGET_INTERVAL
	var enemy = Combat.closest_enemy(self, global_position, attack_range + 0.8)
	if enemy != null:
		_try_hit(enemy)


func _handle_unit_death():
	if dead:
		return
	_on_death_common()
	set_dead(true)
	if not puppet:
		respawn_at = GameData.now() + GameData.hero_respawn_time(level)
		var match_node = get_tree().get_first_node_in_group("lotr_match")
		if match_node != null:
			match_node.toast_player(player.slot_index, "%s has fallen! Your army loses heart (-20%% damage) until %s returns." % [display_name, display_name])
		died_on_host.emit()
		MatchSignals.unit_died.emit(self)


func set_dead(value: bool):
	if dead == value:
		return
	dead = value
	if anim_driver != null and anim_driver.player != null:
		# the hero falls and lies where they died until the respawn timer runs out
		anim_driver.locked = dead
		if dead:
			anim_driver.player.play("Death_A", 0.1)
		else:
			anim_driver.player.play("Idle")
	else:
		find_child("Geometry").visible = not dead
	find_child("HealthBar").visible = false
	input_ray_pickable = not dead
	if dead:
		order_stop()
		if not puppet:
			bm.clear_all(true)
			rebuild_stats()
	death_state_changed.emit(dead)


func _respawn():
	var spawn = home_position
	var tc = _find_town_center()
	if tc != null:
		spawn = tc.global_position + Vector3(0, 0, tc.stats_size() + 1.5)
	global_position = spawn
	set_dead(false)
	hp = hp_max
	mana = mana_max
	_fx("respawn")


func _find_town_center():
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.player == player and b.building_key == "town_center" and b.is_alive():
			return b
	return null


func _fx(kind):
	var match_node = get_tree().get_first_node_in_group("lotr_match")
	if match_node != null:
		match_node.fx(kind, global_position, global_position)


# --- recall -------------------------------------------------------------------------------------
func order_move(position: Vector3):
	cancel_recall()
	super(position)


func order_attack(target, keep_attack_move = false):
	cancel_recall()
	super(target, keep_attack_move)


func start_recall():
	order_stop()
	recall_until = GameData.now() + RECALL_TIME
	_recall_hp = hp
	_fx("recall")


func cancel_recall():
	recall_until = 0.0


func recall_left() -> float:
	return max(0.0, recall_until - GameData.now()) if recall_until > 0.0 else 0.0


func _recall_tick():
	if hp < _recall_hp or order != Order.IDLE:
		cancel_recall()  # taking damage or any order breaks the channel
		return
	_recall_hp = hp  # regeneration raises the bar, so a hit still breaks it
	if GameData.now() < recall_until:
		return
	cancel_recall()
	var tc = _find_town_center()
	if tc != null:
		if _movement != null:
			_movement.stop()
		global_position = tc.global_position + Vector3(0, 0, tc.stats_size() + 1.5)
		_fx("respawn")
