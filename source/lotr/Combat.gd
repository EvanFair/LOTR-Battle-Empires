class_name Combat
## Damage, counters, kill rewards and target search. Host only.

const GOLD_FOR_KILL = {"troop": 12, "villager": 6, "hero": 200, "building": 40}
const XP_FOR_KILL = {"troop": 20, "villager": 8, "hero": 200, "building": 40}


# damage types and where a hit comes from (v4 plan A4)
const PHYSICAL = 0
const MAGIC = 1
const TRUE = 2
const BASIC = 0
const SPELL = 1
const DOT = 2
const ITEM = 3
const TOWER = 4
const BUILDING = 5


static func attack(attacker, target, base_damage: float):
	if target == null or not is_instance_valid(target) or not target.is_alive():
		return
	var match_node = attacker.get_tree().get_first_node_in_group("lotr_match")
	if match_node != null:
		var kind = "arrow" if attacker.ranged else "hit"
		if attacker.ranged and attacker.get("siege") == true:
			kind = "boulder"
		elif attacker.unit_kind == "building":
			kind = "tower_shot"
		match_node.fx(kind, attacker.global_position, target.global_position)
	deal_damage(attacker, target, base_damage, PHYSICAL, TOWER if attacker.unit_kind == "building" else BASIC)


static func deal_damage(attacker, target, amount: float, type = PHYSICAL, source_kind = BASIC, tags = []) -> int:
	"""The damage pipeline. Returns the hit points the target actually lost.
	type: PHYSICAL | MAGIC | TRUE.  source_kind: BASIC | SPELL | DOT | ITEM | TOWER | BUILDING.
	tags: "aoe", "siege", "no_counter", "no_lifesteal", ... Order (v4 plan A4):
	  1 attacker's on_damage_dealt hooks   2 multipliers (counters, army heart, tags, damage_vs_*)
	  3 armour / magic resist (TRUE skips)  4 target's on_before_damage_taken hooks
	  5 shields (earliest-expiring first)   6 hit points fall, credit and rewards
	  7 lifesteal (basic attacks only, capped) and on_hit / on_kill hooks."""
	if target == null or not is_instance_valid(target) or not target.is_alive():
		return 0
	if type is bool:  # the old signature: deal_damage(attacker, target, amount, ignore_counters)
		tags = ["no_counter"] if type else []
		source_kind = SPELL if type else BASIC
		type = PHYSICAL
	if attacker != null and not is_instance_valid(attacker):
		attacker = null
	if target.status.invulnerable:
		return 0
	var ctx = DamageCtx.new()
	ctx.src = attacker
	ctx.target = target
	ctx.amount = amount
	ctx.base_amount = amount
	ctx.type = type
	ctx.kind = source_kind
	ctx.tags = tags
	# 1. attacker hooks
	if attacker != null and not attacker.bm.is_empty():
		attacker.bm.fire_damage_dealt(ctx)
		if ctx.cancelled or ctx.amount <= 0.0:
			return 0
	# 2. multipliers
	var dmg = ctx.amount
	if attacker != null:
		if source_kind == BASIC and not tags.has("no_counter"):
			dmg *= GameData.counter(attacker.unit_class, target.target_kind)
		if attacker.unit_kind == "troop" and attacker.player != null:
			var h = attacker.player.get("hero")
			if h != null and is_instance_valid(h) and h.dead:
				dmg *= GameData.ARMY_LOST_HEART  # an army without its hero loses heart
		if attacker.unit_kind == "hero" and tags.has("aoe") and target.unit_kind in ["troop", "villager"]:
			dmg *= GameData.TAG_MULT.get("aoe_vs_troop", 1.0)
		if tags.has("siege") and target.unit_kind == "building":
			dmg *= GameData.TAG_MULT.get("siege_vs_building", 1.0)
		var st = attacker.stats
		match target.unit_kind:
			"troop", "villager":
				dmg *= 1.0 + st.damage_vs_troops
			"hero":
				dmg *= 1.0 + st.damage_vs_heroes
			"building":
				dmg *= 1.0 + st.damage_vs_buildings
	# 3. mitigation
	if type != TRUE:
		var tstats = target.stats
		var points = tstats.armour if type == PHYSICAL else tstats.magic_resist
		if points > 0.0:
			var pen_pct = attacker.stats.armour_pen_pct if (attacker != null and type == PHYSICAL) else (attacker.stats.magic_pen_pct if attacker != null else 0.0)
			var pen_flat = attacker.stats.armour_pen_flat if (attacker != null and type == PHYSICAL) else (attacker.stats.magic_pen_flat if attacker != null else 0.0)
			points = maxf(0.0, points * (1.0 - pen_pct) - pen_flat)
		ctx.armour_used = points
		dmg *= Stats.mitigation(points)
	ctx.mitigated = dmg
	# 4. target hooks (block, death-save, parry...)
	ctx.amount = dmg
	if not target.bm.is_empty():
		target.bm.fire_before_damage(ctx)
		if ctx.cancelled:
			return 0
	dmg = ctx.amount
	if dmg <= 0.0:
		return 0
	# 5. shields
	var absorbed = target.bm.absorb(dmg) if not target.bm.is_empty() else 0.0
	ctx.shielded = absorbed
	dmg -= absorbed
	# 6. hit points, credit
	var dealt = max(1, int(round(dmg))) if dmg > 0.001 else 0
	ctx.dealt = dealt
	if attacker != null:
		target.last_attacker = attacker
		note_credit(attacker, target)
	var was_alive = target.hp > 0
	# floating numbers for fights that involve a hero (MOBA feedback); payload rides in "to"
	var hero_fight = target.unit_kind == "hero" or (attacker != null and attacker.unit_kind == "hero")
	if hero_fight and was_alive and dealt + absorbed > 0:
		var match_node = target.get_tree().get_first_node_in_group("lotr_match")
		if match_node != null:
			var from_slot = attacker.player.slot_index if attacker != null and attacker.player != null else -99
			match_node.fx("dmg", target.global_position, Vector3(dealt + int(absorbed), from_slot, target.player.slot_index if target.player != null else -99))
	target._death_ctx = ctx
	if dealt > 0:
		target.hp = max(0, target.hp - dealt)
	var killed = was_alive and target.hp == 0
	ctx.killed = killed
	# 7. lifesteal (basic attacks only), on_hit, on_kill
	if attacker != null and is_instance_valid(attacker):
		if source_kind == BASIC:
			if dealt > 0 and not tags.has("no_lifesteal") and attacker.stats.lifesteal > 0.0 and attacker.is_alive():
				heal(attacker, attacker, dealt * minf(GameData.MAX_LIFESTEAL, attacker.stats.lifesteal))
			if not attacker.bm.is_empty():
				attacker.bm.fire_hit(ctx)
		if killed and not attacker.bm.is_empty():
			attacker.bm.fire_kill(target, ctx)
	if killed and attacker != null and is_instance_valid(attacker):
		_reward_kill(attacker, target)
	return dealt


# --- healing, shields and kill credit -------------------------------------------------------------------
static func heal(source, target, amount: float, _tags = []) -> int:
	"""Restore hit points (grievous wounds reduce it). Healing an ally hero counts as an assist for
	the next 10 s. Returns what was actually restored."""
	if target == null or not is_instance_valid(target) or not target.is_alive() or amount <= 0.0:
		return 0
	if not target.bm.is_empty():
		amount *= target.bm.heal_mod()
	var gain = mini(target.hp_max - target.hp, int(round(amount)))
	if gain <= 0:
		return 0
	target.hp += gain
	if source != target:
		note_support(source, target)
	return gain


static func shield(source, target, amount: float, duration: float, key = "shield"):
	"""Give `target` a damage shield (one per source; the same source recasting stacks up to 2x)."""
	if target == null or not is_instance_valid(target) or not target.is_alive():
		return null
	if source != target:
		note_support(source, target)
	return target.bm.add(ShieldBuff.new(amount, duration, key), source)


static func note_credit(src, victim):
	"""A hero damaged or crowd-controlled `victim`: remember it for the assist window."""
	if src == null or not is_instance_valid(src) or victim == src or victim == null:
		return
	if src.get("unit_kind") != "hero" or not src.is_enemy_of(victim):
		return
	victim.credit[src.get_instance_id()] = [src, GameData.now()]


static func note_support(src, target):
	"""A hero healed or shielded an allied hero: assist credit if that ally scores a kill soon."""
	if src == null or not is_instance_valid(src) or src.get("unit_kind") != "hero" or target.get("unit_kind") != "hero":
		return
	target.support[src.get_instance_id()] = [src, GameData.now()]


static func assists_for(victim, killer) -> Array:
	"""Heroes that earn an assist for `victim` dying to `killer`: enemies of the victim who damaged or
	crowd-controlled it in the last ASSIST_WINDOW seconds, plus allies who healed or shielded the killer.
	The killer itself is never listed."""
	var now = GameData.now()
	var out = []
	var credit = victim.get("credit")
	if credit != null:
		for id in credit:
			var e = credit[id]
			if is_instance_valid(e[0]) and e[0] != killer and now - e[1] <= GameData.ASSIST_WINDOW and not out.has(e[0]):
				out.append(e[0])
	var support = killer.get("support") if killer != null and is_instance_valid(killer) else null
	if support != null:
		for id in support:
			var e = support[id]
			if is_instance_valid(e[0]) and e[0] != killer and now - e[1] <= GameData.ASSIST_WINDOW and not out.has(e[0]):
				out.append(e[0])
	return out


static func _reward_kill(attacker, victim):
	# who gets credit (bounty rules read victim.last_credit; see assists_for)
	victim.last_credit = {"killer": attacker, "assists": assists_for(victim, attacker) if victim.unit_kind == "hero" else []}
	var killer_player = attacker.player
	if killer_player == null or not Teams.is_enemy(killer_player, victim.player):
		return
	if killer_player.get("is_neutral") == true:
		return  # creatures earn nothing
	if victim.unit_kind == "creature":
		_reward_creature(attacker, victim)
		return
	if victim.unit_kind == "hero":
		var match_node = victim.get_tree().get_first_node_in_group("lotr_match")
		if match_node != null:
			match_node.fx("kill", victim.global_position, victim.global_position)
	# v3: every kill feeds the team war chest; a hero's own killing blow pays more (last hit)
	var gold = GOLD_FOR_KILL.get(victim.unit_kind, 0)
	if attacker.unit_kind == "hero":
		gold = int(gold * GameData.LAST_HIT_BONUS)
		_float_supplies(attacker, victim, gold)
	if gold > 0 and killer_player.has_method("add_resources"):
		killer_player.add_resources({"gold": gold})
	var xp = XP_FOR_KILL.get(victim.unit_kind, 0)
	if victim.unit_kind == "hero":
		xp += 40 * victim.level
	# XP is shared by the killer's team heroes nearby (MOBA style)
	for hero in victim.get_tree().get_nodes_in_group("heroes"):
		if (
			hero.is_alive()
			and Teams.is_ally(hero.player, killer_player)
			and hero.global_position.distance_to(victim.global_position) <= GameData.XP_RADIUS
		):
			hero.add_xp(xp)


static func _float_supplies(attacker, victim, amount):
	# a gold "+N" pops over the kill for the hero who landed it
	var match_node = victim.get_tree().get_first_node_in_group("lotr_match")
	if match_node != null and amount > 0:
		match_node.fx("loot", victim.global_position, Vector3(amount, attacker.player.slot_index, 0))


static func _reward_creature(attacker, victim):
	var data = GameData.CREATURES[victim.creature_key]
	var killer_player = attacker.player
	var reward = {"gold": data.gold, "food": data.get("food", 0)}
	if attacker.unit_kind == "hero":
		reward.gold = int(data.gold * GameData.LAST_HIT_BONUS)
		_float_supplies(attacker, victim, GameData.price(reward))
	killer_player.add_resources(reward)
	# MOBA jungle: the last hitter heals a little; nearby allied heroes share the XP
	if attacker.unit_kind == "hero":
		attacker.hp = min(attacker.hp_max, attacker.hp + int(attacker.hp_max * 0.1))
	for hero in victim.get_tree().get_nodes_in_group("heroes"):
		if hero.is_alive() and Teams.is_ally(hero.player, killer_player) and hero.global_position.distance_to(victim.global_position) <= GameData.XP_RADIUS:
			hero.add_xp(data.xp)
	var match_node = victim.get_tree().get_first_node_in_group("lotr_match")
	if match_node != null:
		match_node.on_creature_slain(victim, killer_player)


# --- target priority (troops, towers, Follow-mode squads) ----------------------------------------
# League of Legends minion/tower rules, adapted. Lower tier wins; ties go to the closest.
#   0  an enemy HERO attacking one of our heroes
#   1  any other enemy attacking one of our heroes
#   2  an enemy unit attacking one of our troops, villagers or buildings
#   3  the closest enemy troop, creature in a fight, or villager
#   4  an enemy building
#   5  an enemy hero that is not attacking anyone of ours (heroes are hit last)
const TIER_NAMES = ["hero attacking our hero", "unit attacking our hero", "unit attacking our units",
	"closest unit", "building", "idle hero"]


static func current_target(unit):
	"""What a unit is hitting right now (its attack order, or its last swing in the last 2s)."""
	var t = unit.get("order_target")
	if t != null and is_instance_valid(t) and t.is_alive() and unit.get("order") == unit.Order.ATTACK:
		return t
	var last = unit.get("last_hit_target")
	if last != null and is_instance_valid(last) and last.is_alive() and GameData.now() - unit.last_attack_at < 2.0:
		return last
	return null


static func target_tier(unit, enemy) -> int:
	var victim = current_target(enemy)
	var hits_ours = victim != null and Teams.is_ally(victim.player, unit.player)
	if hits_ours and victim.unit_kind == "hero":
		return 0 if enemy.unit_kind == "hero" else 1
	if hits_ours and enemy.unit_kind != "hero":
		return 2
	match enemy.unit_kind:
		"troop", "creature", "villager":
			return 3
		"building":
			return 4
	return 5


static func pick_target(unit, from: Vector3, radius: float, include_wild = false):
	var best = null
	var best_tier = 99
	var best_d2 = INF
	for other in SpatialGrid.near(unit.get_tree(), from, radius + 3.0):
		if other == unit or not is_instance_valid(other) or not other.is_alive() or not unit.is_enemy_of(other):
			continue
		if not include_wild and is_wild(other) and other.get("order_target") == null:
			continue
		var d = other.global_position - from
		d.y = 0.0
		var d2 = d.length_squared()
		if d2 > radius * radius:
			continue
		var tier = target_tier(unit, other)
		if tier < best_tier or (tier == best_tier and d2 < best_d2):
			best_tier = tier
			best_d2 = d2
			best = other
	return best


static func is_wild(unit) -> bool:
	return unit.player != null and unit.player.get("is_neutral") == true


static func closest_enemy(unit, from: Vector3, radius: float, include_wild = false):
	"""Nearest enemy. Wild creatures are skipped unless asked for: armies march past camps and
	only fight them when ordered (or when a creature attacks them)."""
	var best = null
	var best_d2 = radius * radius
	for other in SpatialGrid.near(unit.get_tree(), from, radius + 3.0):
		if other == unit or not is_instance_valid(other) or not other.is_alive() or not unit.is_enemy_of(other):
			continue
		if not include_wild and is_wild(other) and other.get("order_target") != unit:
			continue
		var d = other.global_position - from
		d.y = 0.0
		var d2 = d.length_squared()
		if d2 <= best_d2:
			best_d2 = d2
			best = other
	return best


static func enemies_in_radius(unit_or_player, from: Vector3, radius: float, tree: SceneTree):
	var result = []
	var p = unit_or_player.player if "unit_kind" in unit_or_player else unit_or_player
	for other in SpatialGrid.near(tree, from, radius + 1.0):
		if not is_instance_valid(other) or not other.is_alive() or not Teams.is_enemy(p, other.player):
			continue
		var d = other.global_position - from
		d.y = 0.0
		if d.length() <= radius:
			result.append(other)
	return result
