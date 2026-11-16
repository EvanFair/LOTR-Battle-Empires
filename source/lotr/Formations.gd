class_name Formations
## Horde rules in one place (plan C1-C4): which formations a squad may use, where each soldier
## stands, the stat changes formation / stance / rank give (ONE entry point, `contribute`, read
## by Troop._contribute_stats), squad XP, the banner model and the trample test.
## Tables live in GameData (FORMATIONS, STANCES, RANK_*).


static func def(key: String) -> Dictionary:
	return GameData.FORMATIONS.get(key, GameData.FORMATIONS.line)


static func counter_class(squad) -> String:
	"""What the soldiers are for formation purposes: infantry / archer / rider / heavy / special."""
	var m = squad.first_member()
	if m != null:
		return str(m.unit_class)
	return squad.unit_class


static func is_spear(squad) -> bool:
	return squad.unit_class in GameData.SPEAR_UNITS.get(squad.faction(), [])


static func refusal(squad, key: String) -> String:
	"""'' when the squad may use the formation now, else why not."""
	if not GameData.FORMATIONS.has(key):
		return "Unknown formation"
	var d = GameData.FORMATIONS[key]
	var cls = counter_class(squad)
	if not cls in d.classes:
		return "%s cannot use %s" % [squad.display_name, d.name]
	if d.get("spear", false) and not is_spear(squad):
		return "Only spearmen can form a %s" % d.name
	var need = d.get("needs", "")
	if need != "" and (squad.player == null or not squad.player.upgrades.get(need, false)):
		return "%s needs %s" % [d.name, GameData.UPGRADES[need].name]
	return ""


static func available(squad) -> Array:
	"""Formation keys this squad could ever use (research requirements are checked on use)."""
	return available_for(counter_class(squad), is_spear(squad))


static func available_for(cls: String, spear: bool) -> Array:
	var out = []
	for key in GameData.FORMATION_ORDER:
		var d = GameData.FORMATIONS[key]
		if cls in d.classes and (not d.get("spear", false) or spear):
			out.append(key)
	return out


# --- slots -----------------------------------------------------------------------------------------------
static func slot_offset(layout: String, i: int, n: int, spacing: float) -> Vector2:
	"""Where soldier i of n stands: x to the right of the banner, y behind it (metres)."""
	match layout:
		"wedge":
			var r = 0
			var rem = i
			while rem > r:
				rem -= r + 1
				r += 1
			return Vector2((rem - r / 2.0) * spacing, r * spacing * 0.9)
		"block":
			var cols = maxi(2, ceili(sqrt(float(n))))
			var row = i / cols
			var col = i % cols
			var in_row = mini(cols, n - row * cols)
			return Vector2((col - (in_row - 1) / 2.0) * spacing, row * spacing)
		_:
			var cols2 = maxi(2, ceili(n / 2.0))
			var row2 = i / cols2
			var col2 = i % cols2
			var in_row2 = mini(cols2, n - row2 * cols2)
			return Vector2((col2 - (in_row2 - 1) / 2.0) * spacing, row2 * spacing)


static func banner_slot(layout: String, n: int) -> int:
	"""Index of the banner carrier: the middle of rank 2 (or the last soldier of a tiny horde)."""
	if n <= 1:
		return 0
	var best = n - 1
	var best_row = 1.0e9
	for i in range(n):
		var o = slot_offset(layout, i, n, 1.0)
		if o.y > 0.5 and (o.y < best_row - 0.01 or (absf(o.y - best_row) < 0.01 and absf(o.x) < absf(slot_offset(layout, best, n, 1.0).x))):
			best_row = o.y
			best = i
	return best


# --- stat modifiers: the ONLY place formation / stance / rank touch a unit's numbers ----------------------
static func contribute(unit, s):
	"""Add the squad's formation, stance and rank bonuses to a soldier's temp Stats layer.
	(Called from Troop._contribute_stats. Swap this body if the Stats API changes.)"""
	var sq = unit.squad
	if sq == null or not is_instance_valid(sq):
		return
	var f = def(sq.formation)
	var st = GameData.STANCES[sq.stance]
	var keep = 1.0 - f.get("armour", 0.0)
	keep *= 1.0 - st.get("armour", 0.0)
	if keep < 1.0:
		s.add_flat(Stats.S.ARMOUR, Stats.points_from_fraction(1.0 - keep))
	var spd = f.get("speed", 1.0)
	if spd != 1.0:
		s.add_mult(Stats.S.MOVE_SPEED, spd)
	var dmg = f.get("damage", 1.0) * (1.0 + GameData.RANK_DAMAGE[clampi(sq.rank - 1, 0, 2)])
	if dmg != 1.0:
		s.add_mult(Stats.S.ATTACK_DAMAGE, dmg)
	var hp = GameData.RANK_HP[clampi(sq.rank - 1, 0, 2)]
	if hp > 0.0:
		s.add_mult(Stats.S.MAX_HP, 1.0 + hp)
	if f.has("vs_buildings"):
		s.add_flat(Stats.S.DAMAGE_VS_BUILDINGS, f.vs_buildings)


static func aoe_taken(target) -> float:
	var sq = target.squad
	if sq == null or not is_instance_valid(sq):
		return 1.0
	return def(sq.formation).get("aoe_taken", 1.0)


static func aggro_for(unit) -> float:
	"""How far a soldier goes looking for a fight on its own (the stance)."""
	var sq = unit.squad
	if sq == null or not is_instance_valid(sq):
		return GameData.SQUAD_AGGRO_RANGE
	match sq.stance:
		"defensive":
			return GameData.STANCES.defensive.radius
		"hold":
			return unit.attack_range + 0.6
	return GameData.SQUAD_AGGRO_RANGE


static func is_pike(squad) -> bool:
	return squad != null and is_instance_valid(squad) and def(squad.formation).get("pike", false)


# --- experience (called from Combat._reward_kill) ----------------------------------------------------------
static func award_xp(attacker, victim, xp: int):
	"""Hordes earn the kill's XP; hordes of the owner's hero's player near the kill earn half
	of what the hero kills."""
	if xp <= 0 or attacker == null or not is_instance_valid(attacker):
		return
	if attacker.unit_kind == "troop":
		var sq = attacker.squad
		if sq != null and is_instance_valid(sq):
			sq.add_xp(xp)
	elif attacker.unit_kind == "hero" and attacker.is_inside_tree():
		for sq in attacker.get_tree().get_nodes_in_group("squadrons"):
			if sq.player == attacker.player and sq.center().distance_to(victim.global_position) <= GameData.XP_RADIUS:
				sq.add_xp(int(round(xp * GameData.HERO_XP_SHARE)))


static func rank_for_xp(xp: int) -> int:
	var r = 1
	for i in range(GameData.RANK_XP.size()):
		if xp >= GameData.RANK_XP[i]:
			r = i + 1
	return r


# --- banner ------------------------------------------------------------------------------------------------
static func make_banner(faction: String, team_material) -> Node3D:
	"""A tall pole with a flag in the faction colour and a team-colour stripe."""
	var root = Node3D.new()
	root.name = "Banner"
	var wood = StandardMaterial3D.new()
	wood.albedo_color = Color(0.25, 0.17, 0.1)
	var pole = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.032
	cyl.height = 2.8
	cyl.radial_segments = 6
	cyl.rings = 1
	pole.mesh = cyl
	pole.material_override = wood
	pole.position = Vector3(0, 1.4, 0)
	root.add_child(pole)
	var tip = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	sphere.radial_segments = 6
	sphere.rings = 3
	tip.mesh = sphere
	var gold = StandardMaterial3D.new()
	gold.albedo_color = Color("d4aa3a")
	gold.metallic = 0.6
	tip.material_override = gold
	tip.position = Vector3(0, 2.84, 0)
	root.add_child(tip)
	var colour = GameData.FACTIONS.get(faction, {}).get("color", Color.WHITE)
	var cloth = StandardMaterial3D.new()
	cloth.albedo_color = colour
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var flag = MeshInstance3D.new()
	var quad = BoxMesh.new()
	quad.size = Vector3(0.8, 0.55, 0.02)
	flag.mesh = quad
	flag.material_override = cloth
	flag.position = Vector3(-0.42, 2.45, 0)
	root.add_child(flag)
	var stripe = MeshInstance3D.new()
	var sq = BoxMesh.new()
	sq.size = Vector3(0.8, 0.13, 0.03)
	stripe.mesh = sq
	if team_material != null:
		stripe.material_override = team_material
	stripe.position = Vector3(-0.42, 2.45, 0)
	root.add_child(stripe)
	for mesh in [pole, tip, flag, stripe]:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


static func sync_banners(match_node, summaries: Array):
	"""Clients: show the banner on the soldier each squad summary names (hosts do it in Squadron)."""
	for s in summaries:
		var carrier = s.get("banner", 0)
		for id in s.get("members", []):
			var u = match_node.by_net_id(id)
			if u != null and u.has_method("set_banner"):
				u.set_banner(id == carrier)
