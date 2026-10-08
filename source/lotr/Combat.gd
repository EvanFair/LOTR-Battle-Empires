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
		match_node.fx(kind, attacker.global_position, target.global_position)
	deal_damage(attacker, target, base_damage)


static func deal_damage(attacker, target, base_damage: float, ignore_counters = false):
	if target == null or not is_instance_valid(target) or not target.is_alive():
		return
	var mult = 1.0
	if not ignore_counters and attacker != null and is_instance_valid(attacker):
		mult = GameData.counter(attacker.unit_class, target.target_kind)
	var damage = base_damage * mult * (1.0 - clampf(target.armor, 0.0, 0.9))
	if attacker != null and is_instance_valid(attacker):
		target.last_attacker = attacker
	var was_alive = target.hp > 0
	target.hp = max(0, target.hp - max(1, int(round(damage))))
	if was_alive and target.hp == 0 and attacker != null and is_instance_valid(attacker):
		_reward_kill(attacker, target)


static func _reward_kill(attacker, victim):
	var killer_player = attacker.player
	if killer_player == null or not Teams.is_enemy(killer_player, victim.player):
		return
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


static func closest_enemy(unit, from: Vector3, radius: float):
	var best = null
	var best_d2 = radius * radius
	for other in unit.get_tree().get_nodes_in_group("units"):
		if other == unit or not other.is_alive() or not unit.is_enemy_of(other):
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
	for other in tree.get_nodes_in_group("units"):
		if not other.is_alive() or not Teams.is_enemy(p, other.player):
			continue
		var d = other.global_position - from
		d.y = 0.0
		if d.length() <= radius:
			result.append(other)
	return result
