extends Control
## BFME-style info bubbles floating over the selected hordes: name, rank stars, soldiers and an
## HP bar. Screen-space (the camera projects the horde's position every frame); add it under the
## HUD root, call update(summaries) with the selected hordes' summaries.

const HudTheme = preload("res://source/lotr/hud/widgets/HudTheme.gd")
const RankStars = preload("res://source/lotr/hud/widgets/RankStars.gd")
const MAX_BUBBLES = 8

var hud = null  # LotrHud (for to_hud); null = screen coordinates
var _pool = []


func _init():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _make():
	var panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", HudTheme.flat_box(Color(0.05, 0.05, 0.07, 0.8), HudTheme.GOLD_DIM, 1, 4, 4.0))
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var top = HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	var name_label = HudTheme.label(top, "", 13)
	var stars = RankStars.new(11.0)
	top.add_child(stars)
	var bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(110, 7)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("fill", HudTheme.flat_box(HudTheme.HP_GREEN, HudTheme.HP_GREEN_DARK, 0, 2, 0.0))
	bar.add_theme_stylebox_override("background", HudTheme.flat_box(Color(0.02, 0.02, 0.03, 0.9), Color(0, 0, 0, 0), 0, 2, 0.0))
	box.add_child(bar)
	panel.set_meta("name", name_label)
	panel.set_meta("stars", stars)
	panel.set_meta("bar", bar)
	add_child(panel)
	return panel


func update(summaries: Array):
	var camera = get_viewport().get_camera_3d()
	var n = mini(summaries.size(), MAX_BUBBLES)
	while _pool.size() < n:
		_pool.append(_make())
	for i in range(_pool.size()):
		var panel = _pool[i]
		if i >= n or camera == null:
			panel.visible = false
			continue
		var s = summaries[i]
		var world = Vector3(s.x, 3.2, s.z)
		if camera.is_position_behind(world):
			panel.visible = false
			continue
		var screen = camera.unproject_position(world)
		if hud != null and hud.has_method("to_hud"):
			screen = hud.to_hud(screen)
		panel.visible = true
		panel.get_meta("name").text = "%s  %d/%d" % [s.name, s.count, s.get("max", s.count)]
		panel.get_meta("stars").rank = s.get("rank", 1)
		var bar = panel.get_meta("bar")
		bar.max_value = maxf(1.0, s.get("hp_max", 100))
		bar.value = s.get("hp_sum", s.hp * 100.0)
		panel.position = screen - Vector2(panel.size.x / 2.0, panel.size.y)
