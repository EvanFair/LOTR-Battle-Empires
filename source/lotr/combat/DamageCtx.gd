class_name DamageCtx
extends RefCounted
## One damage event travelling through Combat.deal_damage. Buff hooks may edit `amount`
## (or set `cancelled`) while it passes through their stage.

var src = null  # attacker (may be null: environment, expired source)
var target = null
var amount = 0.0  # current amount; changes at every stage
var base_amount = 0.0  # what the caller asked for
var type = 0  # Combat.PHYSICAL | MAGIC | TRUE
var kind = 0  # Combat.BASIC | SPELL | DOT | ITEM | TOWER | BUILDING
var tags = []
var armour_used = 0.0  # armour or magic resist after penetration (points)
var mitigated = 0.0  # amount after mitigation
var shielded = 0.0  # absorbed by shields
var dealt = 0  # hit points actually lost
var killed = false
var cancelled = false


func has_tag(tag: String) -> bool:
	return tags.has(tag)
