extends Node
## Renders the lobby (single-player view) to a PNG. Use with xvfb-run + --rendering-driver opengl3.

var out = "/tmp/lobby.png"


func _ready():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.split("=")[1]
	var lobby = load("res://source/lotr/menu/Lobby.tscn").instantiate()
	add_child(lobby)
	await get_tree().process_frame
	lobby._on_single_player()
	for i in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
