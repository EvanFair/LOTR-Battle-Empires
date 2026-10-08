class_name HeroAbilities
## Ability logic, keyed by the "kind" field in GameData.HEROES. Host only.
## cast() returns "" on success or a reason the cast failed.


static func cast(match_node, hero, key: String, target_pos, target_unit) -> String:
	var ability = hero.ability(key)
	if ability == null:
		return "%s has no %s ability yet" % [hero.display_name, key]
	if not hero.is_alive():
		return "Your hero is dead"
	if hero.cooldown_left(key) > 0.0:
		return "%s is on cooldown (%ds)" % [ability.name, ceili(hero.cooldown_left(key))]
	if hero.mana < ability.mana:
		return "Not enough mana for %s" % ability.name
	var result = ""
	match ability.kind:
		"execute_strike":
			result = _execute_strike(hero, ability, target_unit)
		"rally_aura":
			result = _rally_aura(match_node, hero, ability)
		"dash":
			result = _dash(hero, ability, target_pos)
		"summon":
			result = _summon(match_node, hero, ability, target_pos)
		"team_haste":
			result = _team_haste(match_node, hero, ability)
		"pin_shot":
			result = _pin_shot(match_node, hero, ability, target_unit)
		_:
			result = "Unknown ability"
	if result == "":
		hero.mana -= ability.mana
		hero.cooldowns[key] = GameData.now() + ability.cooldown
		match_node.fx("cast", hero.global_position, hero.global_position)
	return result


static func _enemy_target(hero, target_unit, reach) -> String:
	if target_unit == null or not is_instance_valid(target_unit) or not target_unit.is_alive():
		return "Pick an enemy target"
	if not hero.is_enemy_of(target_unit):
		return "Target must be an enemy"
	if hero.global_position_yless.distance_to(target_unit.global_position_yless) > reach:
		return "Target is out of range"
	return ""


static func _execute_strike(hero, ability, target):
	var err = _enemy_target(hero, target, ability.range + 0.8)
	if err != "":
		return err
	var missing = target.hp_max - target.hp
	var damage = ability.damage + missing * ability.missing_hp_bonus
	Combat.deal_damage(hero, target, damage, true)
	return ""


static func _rally_aura(match_node, hero, ability):
	for unit in hero.get_tree().get_nodes_in_group("units"):
		if unit.unit_kind != "troop" or unit.player != hero.player or not unit.is_alive():
			continue
		if unit.global_position.distance_to(hero.global_position) <= ability.radius:
			unit.apply_buff("attack_speed", ability.attack_speed, ability.duration)
	return ""


static func _dash(hero, ability, target_pos):
	if target_pos == null:
		return "Pick a point to dash to"
	var dir = target_pos - hero.global_position
	dir.y = 0
	if dir.length() < 0.5:
		return "Too close"
	var dest = hero.global_position + dir.normalized() * min(dir.length(), ability.distance)
	var nav_map = hero.find_child("Movement").get_navigation_map()
	dest = NavigationServer3D.map_get_closest_point(nav_map, dest)
	dest.y = hero.global_position.y
	hero.order_stop()
	var tween = hero.create_tween()
	tween.tween_property(hero, "global_position", dest, 0.18)
	return ""


static func _summon(match_node, hero, ability, target_pos):
	var where = target_pos if target_pos != null else hero.global_position
	var units = []
	var faction = hero.player.faction
	for i in range(ability.count):
		var angle = TAU * i / ability.count
		var pos = hero.global_position + Vector3(cos(angle), 0, sin(angle)) * 1.8
		var params = {
			"kind": "troop", "faction": faction, "class": ability.unit_class,
			"summon_name": ability.summon_name,
		}
		if ability.summon_name == "Army of the Dead":
			params["ghost"] = true
		var unit = match_node.spawn_unit(params, pos, hero.player)
		unit.summon_expires_at = GameData.now() + ability.duration
		units.append(unit)
	var squad = match_node.make_squadron(hero.player, ability.unit_class, units, hero.global_position)
	squad.order_defend(where)
	return ""


static func _team_haste(match_node, hero, ability):
	for unit in hero.get_tree().get_nodes_in_group("units"):
		if not unit.is_alive() or not Teams.is_ally(unit.player, hero.player):
			continue
		if unit.unit_kind not in ["troop", "hero"]:
			continue
		if unit.global_position.distance_to(hero.global_position) <= ability.radius:
			unit.apply_buff("speed", ability.speed, ability.duration)
			unit.rooted_until = 0.0  # cleanse
	return ""


static func _pin_shot(match_node, hero, ability, target):
	var err = _enemy_target(hero, target, ability.range)
	if err != "":
		return err
	match_node.fx("arrow", hero.global_position, target.global_position)
	Combat.deal_damage(hero, target, ability.damage, true)
	target.rooted_until = GameData.now() + ability.root
	return ""
