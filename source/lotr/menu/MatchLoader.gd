extends Control
## Builds the map from the shared seed and starts the match scene. Every peer runs this with
## the same settings, so maps and resource ids match.

const MatchScene = preload("res://source/lotr/LotrMatch.tscn")

var settings = {}


func _ready():
	var label = Label.new()
	label.text = "Marching to Middle-earth..."
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(label)
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
