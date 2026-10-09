class_name HeroAbilities
## Ability logic, keyed by the "kind" field in GameData.HEROES. Host only.
## cast() returns "" on success or a reason the cast failed.
##
## Kinds: strike / execute_strike / pin_shot (one enemy), nova (around the hero),
## ground_aoe (circle at a point), skillshot (line), leap / dash (move), buff_self,
## heal_allies / rally_aura / team_haste (allies around the hero), summon.
## Effects any kind may carry: damage (+ ap_ratio x ability power), damage_type ("magic" or default
## physical), stun, root, slow + slow_time, weaken (enemy damage mult). They go through Combat.deal_damage
## and the target's BuffManager, so armour, tenacity, diminishing returns and immunity all apply.

# how each ability kind is aimed (drives the client's indicators and target picking)
const AIM_MODES = {
	"execute_strike": "unit", "pin_shot": "unit", "strike": "unit", "rally_aura": "self",
	"team_haste": "self", "nova": "self", "buff_self": "self", "heal_allies": "self",
	"dash": "line", "skillshot": "line", "leap": "point", "ground_aoe": "point", "summon": "point",
}


static func aim(ability: Dictionary) -> Dictionary:
	var mode = ability.get("aim", AIM_MODES.get(ability.kind, "point"))
	var reach = ability.get("range", ability.get("distance", 6.0))
	return {
		"mode": mode, "range": reach, "radius": ability.get("radius", 2.5),
		"width": ability.get("width", 1.2),
	}


static func cast(match_node, hero, key: String, target_pos, target_unit) -> String:
	var base = hero.ability(key)
	if base == null:
		return "%s has no %s ability" % [hero.display_name, key]
	if not hero.is_alive():
		return "Your hero is dead"
	var rank = hero.ability_rank(key)
	if rank < 1:
		return "Learn %s first (Ctrl+%s)" % [base.name, key]
	var ability = GameData.ability_at_rank(base, rank)
	if hero.cooldown_left(key) > 0.0:
		return "%s is on cooldown (%ds)" % [ability.name, ceili(hero.cooldown_left(key))]
	if hero.mana < ability.mana:
		return "Not enough mana for %s" % ability.name
	if not hero.status.can_cast:
		return "You are stunned" if hero.is_stunned() else ("You are silenced" if hero.status.silenced else "You cannot cast right now")
	var result = ""
	match ability.kind:
		"execute_strike", "strike", "pin_shot":
			result = _strike(match_node, hero, ability, target_unit)
		"nova":
			result = _nova(match_node, hero, ability)
		"ground_aoe":
			result = _ground_aoe(match_node, hero, ability, target_pos)
		"skillshot":
			result = _skillshot(match_node, hero, ability, target_pos)
		"dash":
			result = _dash(hero, ability, target_pos)
		"leap":
			result = _leap(match_node, hero, ability, target_pos)
		"buff_self":
			result = _buff_self(hero, ability)
		"rally_aura", "heal_allies":
			result = _rally(match_node, hero, ability)
		"summon":
			result = _summon(match_node, hero, ability, target_pos)
		"team_haste":
			result = _team_haste(match_node, hero, ability)
		_:
			result = "Unknown ability"
	if result == "":
		hero.mana -= ability.mana
		hero.cooldowns[key] = GameData.now() + ability.cooldown * hero.stats.cooldown_scale()
		hero.notify_cast(ability.kind not in ["dash", "leap"])
		hero.bm.fire_cast(key)
		match_node.fx("cast", hero.global_position, hero.global_position)
	return result


# --- effects ------------------------------------------------------------------------------------
static func hit(hero, target, ability: Dictionary, mult = 1.0):
	"""Apply an ability's damage and crowd control to one enemy. Damage goes through the Combat
	pipeline: "damage_type": "magic" abilities hit magic resist, everything else armour."""
	if target == null or not is_instance_valid(target) or not target.is_alive():
		return
	var damage = ability.get("damage", 0.0) * mult
	damage += ability.get("ap_ratio", 0.0) * hero.stats.ability_power * mult
	var dtype = Combat.MAGIC if ability.get("damage_type", "physical") == "magic" else Combat.PHYSICAL
	var tags = ["no_counter"]
	if ability.kind in ["nova", "ground_aoe", "leap"]:
		tags.append("aoe")
	if target.unit_kind == "hero":
		damage *= ability.get("hero_bonus", 1.0)
	if target.unit_kind == "building":
		damage *= ability.get("building_mult", 0.5)
		Combat.deal_damage(hero, target, damage, dtype, Combat.SPELL, tags)
		return  # buildings can't be stunned or slowed
	if ability.has("missing_hp_bonus"):
		damage += (target.hp_max - target.hp) * ability.missing_hp_bonus
	if damage > 0.0:
		Combat.deal_damage(hero, target, damage, dtype, Combat.SPELL, tags)
	if not target.is_alive():
		return
	if ability.has("stun"):
		target.bm.add(StunBuff.new(), hero, ability.stun)
	if ability.has("root"):
		target.bm.add(RootBuff.new(), hero, ability.root)
	if ability.has("slow"):
		target.bm.add(SlowBuff.new(1.0 - ability.slow), hero, ability.get("slow_time", 2.0))
	if ability.has("weaken"):
		target.bm.add(StatModBuff.new("mod_damage_down", ability.get("slow_time", 4.0)).best_mult("attack_damage", ability.weaken), hero)


static func _enemy_target(hero, target_unit, reach) -> String:
	if target_unit == null or not is_instance_valid(target_unit) or not target_unit.is_alive():
		return "Pick an enemy target"
	if not hero.is_enemy_of(target_unit):
		return "Target must be an enemy"
	if hero.global_position_yless.distance_to(target_unit.global_position_yless) > reach:
		return "Target is out of range"
	return ""


static func _strike(match_node, hero, ability, target):
	var err = _enemy_target(hero, target, ability.get("range", 2.5) + 0.8)
	if err != "":
		return err
	hero._face(target.global_position)
	if ability.get("range", 2.5) > 4.0:
		match_node.fx("arrow", hero.global_position, target.global_position)
	else:
		match_node.fx("hit", hero.global_position, target.global_position)
	hit(hero, target, ability)
	return ""


static func _nova(match_node, hero, ability):
	match_node.fx("nova", hero.global_position, hero.global_position + Vector3(ability.radius, 0, 0))
	for enemy in Combat.enemies_in_radius(hero, hero.global_position, ability.radius, hero.get_tree()):
		hit(hero, enemy, ability)
	return ""


static func _clamp_point(hero, target_pos, reach):
	if target_pos == null:
		return null
	var to = target_pos - hero.global_position
	to.y = 0.0
	if to.length() > reach:
		to = to.normalized() * reach
	return hero.global_position + to


static func _ground_aoe(match_node, hero, ability, target_pos):
	var point = _clamp_point(hero, target_pos, ability.range)
	if point == null:
		return "Pick a point"
	hero._face(point)
	match_node.fx(ability.get("fx", "volley"), point, hero.global_position)
	match_node.fx("nova", point, point + Vector3(ability.radius, 0, 0))
	for enemy in Combat.enemies_in_radius(hero, point, ability.radius, hero.get_tree()):
		hit(hero, enemy, ability)
	return ""


static func _skillshot(match_node, hero, ability, target_pos):
	if target_pos == null:
		return "Pick a direction"
	var dir = target_pos - hero.global_position
	dir.y = 0.0
	if dir.length() < 0.1:
		return "Pick a direction"
	dir = dir.normalized()
	var start = hero.global_position
	var end = start + dir * ability.range
	hero._face(end)
	var half_width = ability.get("width", 1.0) * 0.5
	var hits = []
	for enemy in Combat.enemies_in_radius(hero, start, ability.range + 1.0, hero.get_tree()):
		var p = Vector2(enemy.global_position.x, enemy.global_position.z)
		var closest = Geometry2D.get_closest_point_to_segment(p, Vector2(start.x, start.z), Vector2(end.x, end.z))
		var r = enemy.get("radius")
		if p.distance_to(closest) <= half_width + (r if r != null else 0.4):
			hits.append([start.distance_to(enemy.global_position), enemy])
	hits.sort_custom(func(a, b): return a[0] < b[0])
	if not ability.get("pierce", false) and hits.size() > 1:
		hits = [hits[0]]
	var stop_at = end if hits.is_empty() or ability.get("pierce", false) else hits[0][1].global_position
	match_node.fx("bolt", start, stop_at)
	for h in hits:
		hit(hero, h[1], ability)
	return ""


static func _move_hero_to(hero, target_pos, distance, time = 0.18):
	if target_pos == null:
		return "Pick a point"
	var dir = target_pos - hero.global_position
	dir.y = 0
	if dir.length() < 0.5:
		return "Too close"
	if hero.status.grounded:
		return "You cannot dash right now"
	if hero.is_rooted():
		return "You are rooted"
	var dest = hero.global_position + dir.normalized() * min(dir.length(), distance)
	var nav_map = hero.find_child("Movement").get_navigation_map()
	dest = NavigationServer3D.map_get_closest_point(nav_map, dest)
	dest.y = hero.global_position.y
	hero.order_stop()
	hero._face(dest)
	if hero.anim_driver != null:
		hero.anim_driver.play_once("Jump_Full_Short" if time > 0.3 else "Dodge_Forward", 1.6)
	var tween = hero.create_tween()
	tween.tween_property(hero, "global_position", dest, time)
	return dest


static func _dash(hero, ability, target_pos):
	var dest = _move_hero_to(hero, target_pos, ability.distance)
	return dest if dest is String else ""


static func _leap(match_node, hero, ability, target_pos):
	var dest = _move_hero_to(hero, target_pos, ability.distance, 0.35)
	if dest is String:
		return dest
	# land, then hit everything around the landing point
	var tree = hero.get_tree()
	var tween = hero.create_tween()
	tween.tween_interval(0.36)
	tween.tween_callback(func():
		if not is_instance_valid(hero) or not hero.is_alive():
			return
		match_node.fx("nova", hero.global_position, hero.global_position + Vector3(ability.radius, 0, 0))
		for enemy in Combat.enemies_in_radius(hero, hero.global_position, ability.radius, tree):
			hit(hero, enemy, ability))
	return ""


static func _buff_self(hero, ability):
	for stat in ability.get("buffs", {}):
		hero.apply_buff(stat, ability.buffs[stat], ability.duration, hero)
	if ability.has("heal"):
		Combat.heal(hero, hero, float(ability.heal))
	return ""


static func _rally(match_node, hero, ability):
	"""Allies (troops, and heroes when heroes_too or healing) around the hero get a buff/heal;
	enemy_slow slows enemies in the same radius."""
	for unit in hero.get_tree().get_nodes_in_group("units"):
		if not unit.is_alive() or unit.global_position.distance_to(hero.global_position) > ability.radius:
			continue
		if Teams.is_ally(unit.player, hero.player):
			var is_hero = unit.unit_kind == "hero"
			if unit.unit_kind != "troop" and not is_hero:
				continue
			if ability.has("heal"):
				Combat.heal(hero, unit, float(ability.heal))
			if ability.has("stat") and (not is_hero or ability.get("heroes_too", false) or unit == hero):
				unit.apply_buff(ability.stat, ability.mult, ability.duration, hero)
		elif ability.has("enemy_slow") and unit.unit_kind != "building":
			unit.apply_buff("speed", ability.enemy_slow, ability.duration * 0.5, hero)
	return ""


static func _summon(match_node, hero, ability, target_pos):
	var where = _clamp_point(hero, target_pos, ability.get("range", 8.0))
	if where == null:
		where = hero.global_position
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
			unit.apply_buff("speed", ability.speed, ability.duration, hero)
			if ability.has("damage_mult"):
				unit.apply_buff("damage", ability.damage_mult, ability.duration, hero)
			unit.bm.cleanse(Buff.ROOT)  # shrugs off roots
	return ""
