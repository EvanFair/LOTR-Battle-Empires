class_name Buff
extends RefCounted
## One buff or debuff instance (one "stack"). Adapted from League-of-Jinx engine/buffs/buff.gd,
## but a plain RefCounted updated by BuffManager instead of a Timer node, so 200 units stay cheap.
##
## Make a buff by subclassing (see combat/buffs/): set key/type/duration/add_type in _init, override
## the hooks you need. Apply it with  target.bm.add(StunBuff.new(1.2), source_unit).
##
## Hooks (all optional):
##   on_activate()                  the buff starts (queued stacks start when their delay ends)
##   on_deactivate(expired)         it ends; expired = false when removed early (cleanse, replace)
##   on_update_stats(stats)         add to the temp layer of Stats (every rebuild)
##   on_update_status(status)       set Status flags (default: from the type bits)
##   on_tick(dt)                    every tick_rate seconds (0 = never)
##   on_before_damage_taken(ctx)    this unit is about to be hurt; ctx.amount may be changed or ctx.cancelled set
##   on_damage_dealt(ctx)           this unit is about to deal damage (before mitigation)
##   on_hit(ctx)                    a basic attack of this unit landed
##   on_kill(victim, ctx)           this unit killed someone
##   on_death(ctx)                  this unit died
##   on_cast(ability_key)           this unit cast an ability
##   on_refresh(incoming)           RENEW_* adds merge into this stack (shields use it to stack)

enum AddType {
	REPLACE_EXISTING,  # drop the old stacks, start fresh (max_stack > 1: oldest lowest-time stacks go first)
	RENEW_EXISTING,  # keep the old buff and restart its timer
	STACKS_AND_RENEWS,  # add a stack, every stack's timer restarts
	STACKS_AND_CONTINUE,  # add a stack that starts when the last one ends (queued)
	STACKS_AND_OVERLAPS,  # add an independent stack with its own timer
}

# type bit flags
const STUN = 1 << 0
const ROOT = 1 << 1
const SLOW = 1 << 2
const SILENCE = 1 << 3
const FEAR = 1 << 4
const TAUNT = 1 << 5
const CHARM = 1 << 6
const KNOCKUP = 1 << 7
const DISARM = 1 << 8
const BLIND = 1 << 9
const GRIEVOUS = 1 << 10
const SHIELD = 1 << 11
const HASTE = 1 << 12
const AURA = 1 << 13
const DOT = 1 << 14
const MARK = 1 << 15
const STEALTH = 1 << 16
const UNSTOPPABLE = 1 << 17

const CC_MASK = STUN | ROOT | SLOW | SILENCE | FEAR | TAUNT | CHARM | KNOCKUP | DISARM | BLIND
const HARD_CC = STUN | FEAR | TAUNT | CHARM | KNOCKUP  # a new one overwrites the old one
const TENACITY_MASK = STUN | ROOT | SLOW | FEAR | CHARM  # not knock-ups
const DR_MASK = STUN | ROOT | FEAR | TAUNT | CHARM | KNOCKUP  # diminishing returns on heroes
const ALL = -1

# key -> [icon (assets/art/status name), title, negative, tooltip]; clients render replicated buff keys from this
const INFO = {
	"stun": ["stun", "Stunned", true, "You cannot move, attack or cast."],
	"root": ["root", "Rooted", true, "You cannot move."],
	"slow": ["slow", "Slowed", true, "Moving slower."],
	"silence": ["weaken", "Silenced", true, "You cannot cast abilities."],
	"fear": ["stun", "Terrified", true, "You flee and cannot act."],
	"taunt": ["stun", "Taunted", true, "You are forced to attack the taunter."],
	"charm": ["stun", "Charmed", true, "You are drawn toward the charmer."],
	"knockup": ["stun", "Knocked up", true, "Airborne: you cannot act."],
	"disarm": ["weaken", "Disarmed", true, "You cannot make basic attacks."],
	"grievous": ["weaken", "Grievous Wounds", true, "Healing and regeneration reduced."],
	"dot": ["weaken", "Burning", true, "Taking damage over time."],
	"shield": ["armor_up", "Shielded", false, "Damage is absorbed first."],
	"haste": ["haste", "Haste", false, "Moving faster."],
	"stealth": ["haste", "Stealth", false, "Hidden from enemies until you attack."],
	"unstoppable": ["armor_up", "Unstoppable", false, "Immune to crowd control."],
	"mark": ["damage_up", "Marked", true, "Takes extra damage from its marker."],
	"aura": ["damage_up", "Aura", false, "Radiates a bonus to allies."],
	"mod_damage_up": ["damage_up", "Empowered", false, "Dealing more damage."],
	"mod_damage_down": ["weaken", "Weakened", true, "Dealing less damage."],
	"mod_attack_speed_up": ["haste", "Battle Rhythm", false, "Attacking faster."],
	"mod_attack_speed_down": ["slow", "Sluggish", true, "Attacking slower."],
	"armor_up": ["armor_up", "Fortified", false, "Taking less damage."],
	"stat_mod": ["damage_up", "Bonus", false, "Improved stats."],
}

var key = "buff"
var type = 0
var add_type = AddType.REPLACE_EXISTING
var max_stack = 1
var duration = 5.0  # seconds; <= 0 means permanent until removed
var tick_rate = 0.0
var stacks_exclusive = true  # true: one slot per source (two heroes' slows are separate entries)
var negative = false
var non_dispellable = false
var persists_through_death = false
var hidden = false
var icon = ""
var title = ""
var tooltip = ""
var value = 0.0  # the buff's main number (slow fraction, shield amount, dot damage per tick...)

# runtime, filled by BuffManager
var source = null  # the unit that applied it (may be null or freed)
var host = null
var slot = null
var remaining = 0.0
var delay = 0.0  # > 0: queued behind another stack (STACKS_AND_CONTINUE), not active yet
var active = false
var expired = false
var removed = false
var applied_at = 0.0
var _tick_left = 0.0


func _apply_info():
	var info = INFO.get(key)
	if info != null:
		icon = info[0]
		title = info[1]
		negative = info[2]
		tooltip = info[3]


static func info_for(buff_key: String) -> Array:
	return INFO.get(buff_key, ["haste", buff_key.capitalize(), false, ""])


func stacks() -> int:
	return slot.stacks.size() if slot != null else 1


func source_id() -> int:
	return source.get_instance_id() if source != null and is_instance_valid(source) else 0


func time_left() -> float:
	return delay + remaining


func renew(new_duration = -1.0):
	if new_duration > 0.0:
		duration = new_duration
	remaining = duration if duration > 0.0 else INF
	applied_at = GameData.now()


func remove():
	if host != null and is_instance_valid(host):
		host.bm.remove_buff(self)


func clone():
	"""A fresh copy with the same settings (used when one add() creates several stacks)."""
	var c = get_script().new()
	for p in get_property_list():
		if (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and p.name not in ["slot", "removed", "active", "expired"]:
			c.set(p.name, get(p.name))
	return c


# --- hooks ----------------------------------------------------------------------------------------
func on_activate():
	pass


func on_deactivate(_expired: bool):
	pass


func on_update_stats(_stats):
	pass


func on_update_status(status):
	if type & STUN:
		status.stunned = true
	if type & ROOT:
		status.rooted = true
	if type & SILENCE:
		status.silenced = true
	if type & FEAR:
		status.feared = true
	if type & TAUNT:
		status.taunted = true
	if type & CHARM:
		status.charmed = true
	if type & KNOCKUP:
		status.airborne = true
	if type & DISARM:
		status.disarmed = true
	if type & STEALTH:
		status.stealthed = true
	if type & UNSTOPPABLE:
		status.unstoppable = true


func on_tick(_dt: float):
	pass


func on_before_damage_taken(_ctx):
	pass


func on_damage_dealt(_ctx):
	pass


func on_hit(_ctx):
	pass


func on_kill(_victim, _ctx):
	pass


func on_death(_ctx):
	pass


func on_cast(_ability_key):
	pass


func on_refresh(_incoming):
	pass
