class_name Status
extends RefCounted
## Boolean state flags of one unit. Adapted from League-of-Jinx engine/status.gd.
## Nothing writes these except buffs: BuffManager clears them and every active buff's
## on_update_status() sets what it grants, then finish() derives the can_* flags.
## Read them everywhere an order or a cast could be refused.

const FLAGS = [
	"stunned", "rooted", "silenced", "feared", "taunted", "charmed", "airborne", "disarmed",
	"stealthed", "revealed", "unstoppable", "invulnerable", "cc_immune", "grounded",
]

var stunned = false
var rooted = false
var silenced = false
var feared = false
var taunted = false
var charmed = false
var airborne = false  # knocked up
var disarmed = false  # no basic attacks
var stealthed = false
var revealed = false  # stealth does not hide a revealed unit
var unstoppable = false  # immune to crowd control, still takes damage
var invulnerable = false
var cc_immune = false
var grounded = false  # no dashes or leaps

# derived by finish()
var can_move = true
var can_attack = true
var can_cast = true
var can_be_targeted = true
var controllable = true  # false while feared / charmed / taunted (the AI takes over)


func reset():
	stunned = false
	rooted = false
	silenced = false
	feared = false
	taunted = false
	charmed = false
	airborne = false
	disarmed = false
	stealthed = false
	revealed = false
	unstoppable = false
	invulnerable = false
	cc_immune = false
	grounded = false


func finish():
	can_move = not (stunned or rooted or airborne)
	can_attack = not (stunned or disarmed or airborne or feared or charmed)
	can_cast = not (stunned or silenced or airborne or feared or charmed)
	can_be_targeted = not invulnerable
	controllable = not (stunned or feared or charmed or taunted or airborne)


func is_hard_cc() -> bool:
	return stunned or feared or charmed or taunted or airborne


func is_disabled() -> bool:
	return stunned or silenced or feared or charmed or taunted or airborne


func to_mask() -> int:
	var m = 0
	for i in range(FLAGS.size()):
		if get(FLAGS[i]):
			m |= 1 << i
	return m


func from_mask(m: int):
	for i in range(FLAGS.size()):
		set(FLAGS[i], (m & (1 << i)) != 0)
	finish()
