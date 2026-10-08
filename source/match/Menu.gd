extends CanvasLayer


func _ready():
	hide()


func _unhandled_input(event):
	if (
		event.is_action_pressed("toggle_match_menu")
		and (visible or not get_tree().paused)
	):
		_toggle()


func _toggle():
	visible = not visible
	# pausing only makes sense offline; in a LAN match the others keep playing
	get_tree().paused = visible and not Network.is_online()


func _on_resume_button_pressed():
	_toggle()


func _on_exit_button_pressed():
	MatchSignals.match_aborted.emit()
	await get_tree().create_timer(1.74).timeout  # Give voice narrator some time to finish.
	get_tree().paused = false
	Network.leave()
	get_tree().change_scene_to_file("res://source/main-menu/Main.tscn")
