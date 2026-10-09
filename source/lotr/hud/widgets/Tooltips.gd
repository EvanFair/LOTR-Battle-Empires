extends RefCounted
## LoL-style tooltips (B10): name + key + rank on the first line, cost / cooldown / range on
## the second, a description with coloured keywords and the numbers of every rank (Shift shows
## all ranks at once).

const HudTheme = preload("res://source/lotr/hud/widgets/HudTheme.gd")

const KEYWORDS = "(?i)\\b(physical damage|attack damage|magic damage|true damage|armou?r|attack speed|movement speed|move speed|damage|heals?|healing|health|shields?|mana|stuns?|stunned|roots?|rooted|slows?|slowed|knock(?:s|ed)? ?down|fear|stealth|cooldown)\\b"
const ACCENT_HEX = "c8aa6e"

static var host = null  # the HUD root Control tooltips are added to (set by LotrHud)


static func hex(c: Color) -> String:
	return "#" + c.to_html(false)


static func colour_for(word: String) -> String:
	var w = word.to_lower()
	if w.begins_with("magic"):
		return hex(HudTheme.MAGIC)
	if w.begins_with("true"):
		return hex(HudTheme.TRUE_DMG)
	if w.begins_with("heal") or w == "health":
		return hex(HudTheme.HEAL_GREEN)
	if w.begins_with("shield"):
		return "#d8dde8"
	if w == "mana":
		return hex(HudTheme.MANA_BLUE.lightened(0.25))
	if w.begins_with("stun") or w.begins_with("root") or w.begins_with("slow") or w.begins_with("knock") or w == "fear":
		return hex(HudTheme.CC_PURPLE)
	if w == "stealth":
		return "#a0a0a8"
	if w.begins_with("armo") or w.begins_with("attack speed") or w.begins_with("move") or w.begins_with("movement"):
		return "#e8d070"
	if w == "cooldown":
		return "#e8d070"
	return hex(HudTheme.PHYSICAL)  # damage, attack damage, physical damage


static func colorize(text: String) -> String:
	var re = RegEx.new()
	re.compile(KEYWORDS)
	var out = ""
	var last = 0
	for m in re.search_all(text):
		out += text.substr(last, m.get_start() - last)
		out += "[color=%s]%s[/color]" % [colour_for(m.get_string()), m.get_string()]
		last = m.get_end()
	out += text.substr(last)
	return out


static func num(v) -> String:
	if v is float and absf(v - roundf(v)) > 0.05:
		return "%.1f" % v
	return str(int(roundf(v)))


# --- the tooltip control --------------------------------------------------------------------------
static func make(title: String, right: String, body: String, width = 340.0, accent = HudTheme.GOLD) -> Control:
	var k = 1.0
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudTheme.tooltip_box())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.custom_minimum_size.x = width
	panel.add_child(box)
	var head = HBoxContainer.new()
	box.add_child(head)
	var t = HudTheme.label(head, title, int(19 * k), accent, "head")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if right != "":
		var r = HudTheme.label(head, right, int(15 * k), HudTheme.TEXT_DIM, "bold")
		r.size_flags_vertical = Control.SIZE_SHRINK_END
	var line = ColorRect.new()
	line.color = Color(HudTheme.GOLD_DIM, 0.8)
	line.custom_minimum_size.y = 1
	box.add_child(line)
	var rich = RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rich.add_theme_font_override("normal_font", HudTheme.font("body"))
	rich.add_theme_font_override("bold_font", HudTheme.font("bold"))
	rich.add_theme_font_override("italics_font", HudTheme.font("italic"))
	rich.add_theme_font_size_override("normal_font_size", int(16 * k))
	rich.add_theme_font_size_override("bold_font_size", int(16 * k))
	rich.add_theme_font_size_override("italics_font_size", int(16 * k))
	rich.fit_content = false
	rich.add_theme_color_override("default_color", Color("d8d0c0"))
	rich.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	rich.add_theme_constant_override("outline_size", 2)
	rich.text = body
	# measure the wrapped height up front: fit_content cannot know the width yet
	rich.size = Vector2(width, 40)
	rich.custom_minimum_size = Vector2(width, ceilf(rich.get_content_height()) + 2.0)
	box.add_child(rich)
	return panel


static func label_val(label: String, value: String, color = "#9ab4e8") -> String:
	return "[color=%s]%s[/color] %s" % [color, label, value]


# --- abilities ------------------------------------------------------------------------------------
const STAT_LABELS = {
	"damage": "Damage", "heal": "Heal", "stun": "Stun", "root": "Root", "duration": "Duration",
	"radius": "Radius", "slow_time": "Slow duration", "count": "Summons",
}


static func ability(h, a: Dictionary) -> Control:
	var key = a.key
	var rank = h.ability_rank(key)
	var shift = Input.is_key_pressed(KEY_SHIFT)
	var live = GameData.ability_at_rank(a, maxi(1, rank))
	var cd = live.cooldown
	var parts = []
	var cost = "[color=%s]Cost:[/color] [color=%s]%d Mana[/color]" % ["#8fa0b8", hex(HudTheme.MANA_BLUE.lightened(0.25)), a.mana]
	var cdt = "[color=#8fa0b8]Cooldown:[/color] %s s" % num(cd)
	var rng = ""
	if a.has("range"):
		rng = "   [color=#8fa0b8]Range:[/color] %s" % num(a.range)
	parts.append("%s    %s%s" % [cost, cdt, rng])
	var text = "\n".join(parts) + "\n\n" + colorize(a.get("desc", ""))
	text += "\n"
	for stat in ["damage", "heal", "stun", "root", "duration", "radius", "count"]:
		if not a.has(stat):
			continue
		var line = ""
		if shift or rank < 1:
			var vals = []
			for r in range(1, GameData.ABILITY_MAX_RANK + 1):
				var v = GameData.ability_at_rank(a, r)[stat]
				vals.append(("[b]%s[/b]" if r == rank else "%s") % num(v))
			line = " / ".join(vals)
		else:
			line = "[b]%s[/b]" % num(live[stat])
			if rank < GameData.ABILITY_MAX_RANK:
				line += "  [color=#7a8090](next %s)[/color]" % num(GameData.ability_at_rank(a, rank + 1)[stat])
		var label = STAT_LABELS.get(stat, stat.capitalize())
		var unit = " s" if stat in ["stun", "root", "duration"] else ""
		var c = colour_for(stat) if stat in ["damage", "heal", "stun", "root"] else "#c8c0b0"
		text += "\n[color=%s]%s:[/color] %s%s" % [c, label, line, unit]
	if rank < 1:
		var err = h.can_learn(key)
		text += "\n\n[color=#e07070]Not learned[/color]" + ("" if err != "" else "  [color=#e8c24a]Ctrl+%s or the + button to learn[/color]" % key)
		if err != "":
			text += "\n[color=#8a8a90]%s[/color]" % err
	elif rank < GameData.ABILITY_MAX_RANK and h.can_learn(key) == "":
		text += "\n\n[color=#e8c24a]Ctrl+%s to upgrade[/color]" % key
	if not shift:
		text += "\n[color=#6a6e78]Hold Shift: numbers of every rank[/color]"
	var right = "[%s]   Rank %d/%d" % [key, rank, GameData.ABILITY_MAX_RANK]
	return make(a.name, right, text, 350.0, HudTheme.GOLD_BRIGHT if key == "R" else HudTheme.GOLD)


# --- items ----------------------------------------------------------------------------------------
static func item(key: String, owned_slot = -1) -> Control:
	var d = GameData.ITEMS[key]
	var text = ""
	var stats = d.get("stats", {})
	var names = {"damage": "attack damage", "hp": "health", "armor": "armor", "mana": "mana", "mana_regen": "mana per second", "speed": "movement speed", "attack_speed": "attack speed"}
	for s in stats:
		var v = stats[s]
		var shown = ("+%d%%" % int(round(v * 100.0))) if s in ["armor", "speed", "attack_speed"] else "+%s" % num(v)
		text += "%s %s\n" % [shown, colorize(names.get(s, s))]
	if text != "":
		text += "\n"
	var desc = d.desc
	text += colorize(desc).replace("Use:", "[color=#e8c24a]Use:[/color]")
	if d.has("active"):
		text += "\n[color=#8fa0b8]Cooldown:[/color] %s s" % num(d.active.cooldown)
	if owned_slot >= 0:
		text += "\n\n[color=#e8c24a]Key %d to use[/color]" % (owned_slot + 5) if (d.get("consumable", false) or d.has("active")) else ""
		text += "\n[color=#8a8a90]Sells for %d[/color]" % int(d.cost * GameData.SELL_REFUND)
	return make(d.name, "%d" % d.cost, text, 320.0)


# --- stats ----------------------------------------------------------------------------------------
static func stat(title: String, value: String, lines: Array) -> Control:
	var text = "\n".join(lines)
	return make(title, value, text, 300.0)
