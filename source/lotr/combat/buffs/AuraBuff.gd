class_name AuraBuff
extends Buff
## A permanent (or timed) buff on its owner that, every 0.5 s, gives nearby units a short
## StatModBuff made by `make_child` (a Callable returning a Buff). Because the child lasts
## slightly longer than one pulse, units leaving the radius lose it a moment later.
##   var aura = AuraBuff.new(12.0, "ally", func(): return StatModBuff.new("rally", 1.0).best_mult("attack_damage", 1.1))

var radius = 8.0
var affects = "ally"  # ally | enemy
var include_self = true
var troops_and_heroes_only = true
var make_child = null  # Callable -> Buff


func _init(aura_radius = 8.0, who = "ally", child_factory = null, seconds = 0.0):
	key = "aura"
	type = Buff.AURA
	negative = false
	duration = seconds  # <= 0: until removed
	radius = aura_radius
	affects = who
	make_child = child_factory
	tick_rate = 0.5
	add_type = Buff.AddType.REPLACE_EXISTING
	hidden = true
	_apply_info()


func on_activate():
	on_tick(0.0)


func on_tick(_dt):
	if host == null or not is_instance_valid(host) or not host.is_alive() or not make_child is Callable:
		return
	var tree = host.get_tree()
	if tree == null:
		return
	for u in SpatialGrid.near(tree, host.global_position, radius + 1.0):
		if not is_instance_valid(u) or not u.is_alive() or (u == host and not include_self):
			continue
		var friendly = Teams.is_ally(u.player, host.player)
		if (affects == "ally") != friendly:
			continue
		if troops_and_heroes_only and u.unit_kind not in ["hero", "troop"]:
			continue
		if u.global_position.distance_to(host.global_position) > radius:
			continue
		var child = make_child.call()
		child.duration = maxf(child.duration, tick_rate * 1.6)
		child.add_type = Buff.AddType.RENEW_EXISTING
		u.bm.add(child, host)
