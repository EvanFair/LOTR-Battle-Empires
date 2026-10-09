extends Control
## Builds the map from the shared seed and starts the match scene. Every peer runs this with
## the same settings, so maps and resource ids match.

const MatchScene = preload("res://source/lotr/LotrMatch.tscn")

var settings = {}


func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg = ColorRect.new()
	bg.color = Color("14110e")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var factions = ["gondor", "rohan", "mordor", "isengard"]
	var path = "res://assets/art/keyart/loading_%s.webp" % factions[abs(hash(settings.get("seed", 0))) % 4]
	if ResourceLoader.exists(path):
		var art = TextureRect.new()
		art.texture = load(path)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(art)
	var label = Label.new()
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.text = "Marching to Middle-earth..."
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	label.position.y -= 60
	add_child(label)
	await get_tree().process_frame
	await get_tree().process_frame
	start()


func start():
	var map = MapGen.build(settings.seed)
	var a_match = MatchScene.instantiate()
	a_match.match_settings = settings
	a_match.map = map
	a_match.name = "Match"
	get_tree().root.add_child(a_match)
	get_tree().current_scene = a_match
	queue_free()
