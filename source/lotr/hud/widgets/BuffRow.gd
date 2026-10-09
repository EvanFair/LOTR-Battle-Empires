extends Control
## The row of buff / debuff icons above the champion panel. Reads what the hero exposes today:
## `buffs` ({stat, mult, until}), stunned_until, rooted_until, recall_until. (Clients only get the
## stun and recall timers through the Replicator for now.)

const HudTheme = preload("res://source/lotr/hud/widgets/HudTheme.gd")
const BuffIcon = preload("res://source/lotr/hud/widgets/BuffIcon.gd")
const Tooltips = preload("res://source/lotr/hud/widgets/Tooltips.gd")

const ICON_PX = 34.0
# stat + direction -> [status art, name, description]
const KINDS = {
	"stun": ["stun", "Stunned", "You cannot move, attack or cast."],
	"root": ["root", "Rooted", "You cannot move."],
	"recall": ["recall", "Recalling", "Returning to the Town Center. Moving, casting or taking damage cancels it."],
	"speed_up": ["haste", "Haste", "Moving faster."],
	"speed_down": ["slow", "Slowed", "Moving slower."],
	"attack_speed_up": ["haste", "Battle Rhythm", "Attacking faster."],
	"attack_speed_down": ["slow", "Sluggish", "Attacking slower."],
	"damage_up": ["damage_up", "Empowered", "Dealing more damage."],
	"damage_down": ["weaken", "Weakened", "Dealing less damage."],
	"armor_up": ["armor_up", "Fortified", "Taking less damage."],
}

var _icons = {}  # id -> BuffIcon
var _totals = {}  # id -> longest remaining time seen (the duration)


func update_from(h):
	var now = GameData.now()
	var entries = {}
	if h != null and not h.dead:
		if h.stunned_until > now:
			entries["stun"] = {"kind": "stun", "left": h.stunned_until - now, "debuff": true}
		elif h.get("rooted_until") != null and h.rooted_until > now:
			entries["root"] = {"kind": "root", "left": h.rooted_until - now, "debuff": true}
		if h.recall_until > now:
			entries["recall"] = {"kind": "recall", "left": h.recall_until - now, "debuff": false}
		for b in h.buffs:
			var up = b.mult >= 1.0 or b.stat == "armor"
			var kind = "%s_%s" % [b.stat, "up" if up else "down"]
			if not KINDS.has(kind):
				continue
			var id = "%s_%s" % [b.stat, "up" if up else "down"]
			var left = b.until - now
			if left > 0.0 and (not entries.has(id) or entries[id].left < left):
				var stacks = 1
				if entries.has(id):
					stacks = entries[id].stacks + 1
				entries[id] = {"kind": kind, "left": left, "debuff": not up, "stacks": stacks, "mult": b.mult}
	for id in _icons.keys():
		if not entries.has(id):
			_icons[id].queue_free()
			_icons.erase(id)
			_totals.erase(id)
	var x = 0.0
	for id in entries:
		var e = entries[id]
		var icon = _icons.get(id)
		if icon == null:
			icon = BuffIcon.new()
			icon.build(ICON_PX)
			add_child(icon)
			_icons[id] = icon
			var spec = KINDS[e.kind]
			icon.tip = _tip.bind(spec, id)
		_totals[id] = maxf(_totals.get(id, 0.0), e.left)
		icon.position = Vector2(x, 0)
		icon.apply(HudTheme.status_tex(KINDS[e.kind][0]), e.left / maxf(0.01, _totals[id]), e.get("stacks", 1), e.debuff)
		x += ICON_PX + 4.0
	size = Vector2(maxf(x, 1.0), ICON_PX)


func _tip(spec, id):
	var left = 0.0
	var icon = _icons.get(id)
	var text = "[color=#c8c0b0]%s[/color]" % spec[2]
	return Tooltips.make(spec[1], "", text, 240.0, HudTheme.RED if (icon != null and icon.debuff) else HudTheme.HEAL_GREEN)
