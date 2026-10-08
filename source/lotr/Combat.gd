class_name Combat
## Damage, counters, kill rewards and target search. Host only.

const GOLD_FOR_KILL = {"troop": 4, "villager": 2, "hero": 150, "building": 25}
const XP_FOR_KILL = {"troop": 20, "villager": 8, "hero": 200, "building": 40}


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
	deal_damage(attacker, target, base_damage)


static func deal_damage(attacker, target, base_damage: float, ignore_counters = false):
	if target == null or not is_instance_valid(target) or not target.is_alive():
		return
	var mult = 1.0
	if not ignore_counters and attacker != null and is_instance_valid(attacker):
		mult = GameData.counter(attacker.unit_class, target.target_kind)
	# an army without its hero loses heart
	if attacker != null and is_instance_valid(attacker) and attacker.unit_kind == "troop" and attacker.player != null:
		var h = attacker.player.get("hero")
		if h != null and is_instance_valid(h) and h.dead:
			mult *= GameData.ARMY_LOST_HEART
	var damage = base_damage * mult * (1.0 - clampf(target.armor, 0.0, 0.9))
	if attacker != null and is_instance_valid(attacker):
		target.last_attacker = attacker
	var was_alive = target.hp > 0
	var dealt = max(1, int(round(damage)))
	target.hp = max(0, target.hp - dealt)
	# floating numbers for fights that involve a hero (MOBA feedback); payload rides in "to"
	var hero_fight = target.unit_kind == "hero" or (attacker != null and is_instance_valid(attacker) and attacker.unit_kind == "hero")
	if hero_fight and was_alive:
		var match_node = target.get_tree().get_first_node_in_group("lotr_match")
		if match_node != null:
			var from_slot = attacker.player.slot_index if attacker != null and is_instance_valid(attacker) and attacker.player != null else -99
			match_node.fx("dmg", target.global_position, Vector3(dealt, from_slot, target.player.slot_index if target.player != null else -99))
	if was_alive and target.hp == 0 and attacker != null and is_instance_valid(attacker):
		_reward_kill(attacker, target)


static func _reward_kill(attacker, victim):
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
	var gold = GOLD_FOR_KILL.get(victim.unit_kind, 0)
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


static func _reward_creature(attacker, victim):
	var data = GameData.CREATURES[victim.creature_key]
	var killer_player = attacker.player
	killer_player.add_resources({"gold": data.gold, "food": data.get("food", 0)})
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
