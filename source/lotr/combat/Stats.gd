class_name Stats
extends RefCounted
## One per unit. Adapted from League-of-Jinx engine/stats.gd + engine/game/balancer.gd.
##
## Every stat is   (base + per_level * (level - 1) + flat + temp_flat) * (1 + percent + temp_percent) * temp_mult
## The permanent layers (base, per_level, flat, percent) are set by code that owns them (the
## factory, a hero's level). The temp layers are cleared by begin() and refilled every 0.25 s
## (see LotrUnit.rebuild_stats) from items, buffs, auras, research and level, then finish()
## writes the final numbers into the read-only members below (max_hp, armour, ...).
##
## Special cases (kept out of the generic layers on purpose):
##   - "best" layers keep only the strongest buff and the strongest debuff of a stat (the old
##     apply_buff rule), see add_best_mult / add_best_flat.
##   - slows: one value, the strongest (add_slow); move_speed never drops below SLOW_FLOOR
##     (30%) of its base while slowed.
##
## Units: armour / magic_resist are points (damage taken = 100 / (100 + points), see mitigation()),
## attack_speed is attacks per second, tenacity / lifesteal / crit_chance are fractions 0..1,
## damage_vs_* are fractions (0.1 = +10%), ability_haste is points (cooldown = 100 / (100 + haste)).

enum S {
	MAX_HP, HP_REGEN, MAX_MANA, MANA_REGEN, ATTACK_DAMAGE, ABILITY_POWER, ARMOUR, MAGIC_RESIST,
	ATTACK_SPEED, ATTACK_RANGE, MOVE_SPEED, CRIT_CHANCE, LIFESTEAL, TENACITY, ABILITY_HASTE,
	DAMAGE_VS_TROOPS, DAMAGE_VS_HEROES, DAMAGE_VS_BUILDINGS,
	ARMOUR_PEN_FLAT, ARMOUR_PEN_PCT, MAGIC_PEN_FLAT, MAGIC_PEN_PCT,
}
const COUNT = 22
const NAMES = [
	"max_hp", "hp_regen", "max_mana", "mana_regen", "attack_damage", "ability_power", "armour",
	"magic_resist", "attack_speed", "attack_range", "move_speed", "crit_chance", "lifesteal",
	"tenacity", "ability_haste", "damage_vs_troops", "damage_vs_heroes", "damage_vs_buildings",
	"armour_pen_flat", "armour_pen_pct", "magic_pen_flat", "magic_pen_pct",
]

var level = 1

# permanent layers
var base = PackedFloat64Array()
var per_level = PackedFloat64Array()
var flat = PackedFloat64Array()
var percent = PackedFloat64Array()
# temp layers (cleared by begin())
var t_flat = PackedFloat64Array()
var t_percent = PackedFloat64Array()
var t_mult = PackedFloat64Array()
var best_up = PackedFloat64Array()  # strongest buff multiplier per stat (>= 1)
var best_down = PackedFloat64Array()  # strongest debuff multiplier per stat (<= 1)
var best_flat = PackedFloat64Array()  # strongest flat add per stat (max)
var slow = 0.0  # strongest slow this rebuild (0.3 = 30% slower)

# results of finish(): final values
var value = PackedFloat64Array()
var mult_part = PackedFloat64Array()  # temp multiplicative layer per stat (incl. best_up * best_down)
var pct_part = PackedFloat64Array()  # percent layers (perm + temp) per stat
var max_hp = 0.0
var hp_regen = 0.0
var max_mana = 0.0
var mana_regen = 0.0
var attack_damage = 0.0
var ability_power = 0.0
var armour = 0.0
var magic_resist = 0.0
var attack_speed = 1.0
var attack_range = 0.0
var move_speed = 0.0
var crit_chance = 0.0
var lifesteal = 0.0
var tenacity = 0.0
var ability_haste = 0.0
var damage_vs_troops = 0.0
var damage_vs_heroes = 0.0
var damage_vs_buildings = 0.0
var armour_pen_flat = 0.0
var armour_pen_pct = 0.0
var magic_pen_flat = 0.0
var magic_pen_pct = 0.0

var armour_before_buffs = 0.0  # armour after items/level but before buffs (HUD "buffs: +x")
var base_move_speed = 0.0  # base + growth, no bonuses (slow floor reference)

const _INDEX = {
	"max_hp": 0, "hp_regen": 1, "max_mana": 2, "mana_regen": 3, "attack_damage": 4,
	"ability_power": 5, "armour": 6, "magic_resist": 7, "attack_speed": 8, "attack_range": 9,
	"move_speed": 10, "crit_chance": 11, "lifesteal": 12, "tenacity": 13, "ability_haste": 14,
	"damage_vs_troops": 15, "damage_vs_heroes": 16, "damage_vs_buildings": 17,
	"armour_pen_flat": 18, "armour_pen_pct": 19, "magic_pen_flat": 20, "magic_pen_pct": 21,
}


func _init():
	base = _filled(0.0)
	per_level = _filled(0.0)
	flat = _filled(0.0)
	percent = _filled(0.0)
	t_flat = _filled(0.0)
	t_percent = _filled(0.0)
	best_flat = _filled(0.0)
	value = _filled(0.0)
	pct_part = _filled(0.0)
	t_mult = _filled(1.0)
	best_up = _filled(1.0)
	best_down = _filled(1.0)
	mult_part = _filled(1.0)


static func _filled(v: float) -> PackedFloat64Array:
	var a = PackedFloat64Array()
	a.resize(COUNT)
	a.fill(v)
	return a


static func idx(stat_name: String) -> int:
	return _INDEX[stat_name]


static func mitigation(points: float) -> float:
	"""Fraction of damage that gets through `points` of armour or magic resist. Negative points
	amplify: 2 - 100 / (100 - points) (so -100 armour = +50% damage taken)."""
	if points >= 0.0:
		return 100.0 / (100.0 + points)
	return 2.0 - 100.0 / (100.0 - points)


static func points_from_fraction(fraction: float) -> float:
	"""Old-style 'x% less damage' as armour points: 0.25 -> 33.3 points."""
	var f = clampf(fraction, 0.0, 0.95)
	return 100.0 * f / (1.0 - f)


static func fraction_from_points(points: float) -> float:
	return 1.0 - mitigation(points)


# --- permanent layers ---------------------------------------------------------------------------
func set_base(stat_name: String, v: float, growth = 0.0):
	var i = _INDEX[stat_name]
	base[i] = v
	per_level[i] = growth


func set_flat(stat_name: String, v: float):
	flat[_INDEX[stat_name]] = v


func set_percent(stat_name: String, v: float):
	percent[_INDEX[stat_name]] = v


# --- temp layers: call begin(), then any number of add_*(), then finish() -----------------------
func begin():
	t_flat.fill(0.0)
	t_percent.fill(0.0)
	t_mult.fill(1.0)
	best_up.fill(1.0)
	best_down.fill(1.0)
	best_flat.fill(0.0)
	slow = 0.0


func add_flat(i: int, v: float):
	t_flat[i] += v


func add_percent(i: int, v: float):
	t_percent[i] += v


func add_mult(i: int, factor: float):
	t_mult[i] *= factor


func add_best_mult(i: int, factor: float):
	"""Only the strongest buff (factor > 1) and the strongest debuff (factor < 1) of a stat apply."""
	if factor >= 1.0:
		best_up[i] = maxf(best_up[i], factor)
	else:
		best_down[i] = minf(best_down[i], factor)


func add_best_flat(i: int, v: float):
	best_flat[i] = maxf(best_flat[i], v)


func add_slow(fraction: float):
	slow = maxf(slow, fraction)


func mark_gear():
	"""Call after items/level/research and before buffs: remembers armour for the HUD."""
	var lv = float(level - 1)
	var i = S.ARMOUR
	armour_before_buffs = (base[i] + per_level[i] * lv + flat[i] + t_flat[i]) * (1.0 + percent[i] + t_percent[i])


func finish():
	var lv = float(level - 1)
	for i in range(COUNT):
		var m = t_mult[i] * best_up[i] * best_down[i]
		var p = percent[i] + t_percent[i]
		var grown = base[i] + per_level[i] * lv
		var v = (grown + flat[i] + t_flat[i] + best_flat[i]) * (1.0 + p) * m
		mult_part[i] = m
		pct_part[i] = p
		value[i] = v
	# move speed: slow, with a floor
	base_move_speed = base[S.MOVE_SPEED] + per_level[S.MOVE_SPEED] * lv
	var ms = value[S.MOVE_SPEED]
	if slow > 0.0:
		var slowed = ms * (1.0 - slow)
		var floor_ms = minf(ms, base_move_speed * GameData.SLOW_FLOOR)
		ms = maxf(slowed, floor_ms)
	value[S.MOVE_SPEED] = maxf(0.0, ms)
	value[S.ATTACK_SPEED] = maxf(0.05, value[S.ATTACK_SPEED]) if base[S.ATTACK_SPEED] > 0.0 else 0.0
	value[S.CRIT_CHANCE] = clampf(value[S.CRIT_CHANCE], 0.0, 1.0)
	value[S.LIFESTEAL] = clampf(value[S.LIFESTEAL], 0.0, 1.0)
	value[S.TENACITY] = clampf(value[S.TENACITY], 0.0, GameData.TENACITY_CAP)
	value[S.MAX_HP] = maxf(1.0, value[S.MAX_HP])
	value[S.ATTACK_RANGE] = maxf(0.0, value[S.ATTACK_RANGE])
	max_hp = value[S.MAX_HP]
	hp_regen = value[S.HP_REGEN]
	max_mana = value[S.MAX_MANA]
	mana_regen = value[S.MANA_REGEN]
	attack_damage = value[S.ATTACK_DAMAGE]
	ability_power = value[S.ABILITY_POWER]
	armour = value[S.ARMOUR]
	magic_resist = value[S.MAGIC_RESIST]
	attack_speed = value[S.ATTACK_SPEED]
	attack_range = value[S.ATTACK_RANGE]
	move_speed = value[S.MOVE_SPEED]
	crit_chance = value[S.CRIT_CHANCE]
	lifesteal = value[S.LIFESTEAL]
	tenacity = value[S.TENACITY]
	ability_haste = value[S.ABILITY_HASTE]
	damage_vs_troops = value[S.DAMAGE_VS_TROOPS]
	damage_vs_heroes = value[S.DAMAGE_VS_HEROES]
	damage_vs_buildings = value[S.DAMAGE_VS_BUILDINGS]
	armour_pen_flat = value[S.ARMOUR_PEN_FLAT]
	armour_pen_pct = clampf(value[S.ARMOUR_PEN_PCT], 0.0, 1.0)
	magic_pen_flat = value[S.MAGIC_PEN_FLAT]
	magic_pen_pct = clampf(value[S.MAGIC_PEN_PCT], 0.0, 1.0)


# --- reading ------------------------------------------------------------------------------------
func get_stat(stat_name: String) -> float:
	return value[_INDEX[stat_name]]


func growth(stat_name: String) -> float:
	var i = _INDEX[stat_name]
	return per_level[i] * (level - 1)


func cooldown_scale() -> float:
	"""Multiply a cooldown by this (ability haste 100 = half the cooldown)."""
	return 100.0 / (100.0 + maxf(0.0, ability_haste))


func armour_fraction() -> float:
	"""Damage reduction as a fraction, the old unit.armor number."""
	return fraction_from_points(armour)


func magic_fraction() -> float:
	return fraction_from_points(magic_resist)
