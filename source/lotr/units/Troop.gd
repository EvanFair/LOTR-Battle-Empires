extends "res://source/lotr/units/LotrUnit.gd"
## A soldier in a squadron. The Squadron decides what it does; it fights on its own when idle.

const EXPLODE_RADIUS = 3.5

var summon_expires_at = 0.0  # summoned units (Army of the Dead, Wargs) vanish after this time
var siege = false  # prefers buildings (squadron targeting)
var explode = false  # Isengard sappers: blow up on the first hit, damaging everything nearby


func _ready():
	await super()
	aggro_range = GameData.SQUAD_AGGRO_RANGE


func _physics_process(delta):
	super(delta)
	if (
		not puppet
		and summon_expires_at > 0.0
		and GameData.now() > summon_expires_at
		and is_alive()
	):
		hp = 0


func _try_hit(target):
	if not explode:
		super(target)
		return
	var distance = global_position_yless.distance_to(target.global_position_yless)
	if distance > attack_range + _target_radius(target) + 0.2:
		return
	var match_node = get_tree().get_first_node_in_group("lotr_match")
	if match_node != null:
		match_node.fx("blast", global_position, global_position)
	for other in Combat.enemies_in_radius(self, global_position, EXPLODE_RADIUS + _target_radius(target), get_tree()):
		var falloff = 1.0 if other == target or other.unit_kind == "building" else 0.5
		Combat.deal_damage(self, other, attack_damage * damage_mult * falloff, Combat.PHYSICAL, Combat.BASIC, ["aoe", "siege"])
	hp = 0
