extends Control
## Play menu: single player vs bots, host a LAN game, or join one (LAN games are found
## automatically; typing an IP is the fallback). The lobby has 4 slots, each with a faction,
## hero and Team 1-4 dropdown, plus Team / FFA presets. Only the host can start.

const LoaderScript = preload("res://source/lotr/menu/MatchLoader.gd")
const KIND_LABELS = {"open": "Open", "bot": "Bot", "human": "Human"}

var _screens = {}
var _name_edit = null
var _games_list = null
var _ip_edit = null
var _status = null
var _slot_rows = []
var _start_button = null
var _preset_row = null
var _offline = false


func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg = ColorRect.new()
	bg.color = Color("14110e")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_key_art(self, "lobby")
	Sfx.play_music("lobby")
	_build_start_screen()
	_build_join_screen()
	_build_lobby_screen()
	_show("start")
	Network.lobby_changed.connect(_refresh_lobby)
	Network.games_found_changed.connect(_refresh_games)
	Network.connected_to_host.connect(func(): _show("lobby"))
	Network.connection_failed.connect(func(): _set_status("Couldn't connect to that game."))
	Network.host_left.connect(_on_host_left)
	Network.match_starting.connect(_on_match_starting)


func _exit_tree():
	Network.stop_discovery()


# --- layout helpers ---------------------------------------------------------------------------
func _screen(name) -> VBoxContainer:
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box = VBoxContainer.new()
	box.custom_minimum_size = Vector2(760, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	_screens[name] = center
	return box


func _title(parent, text, size = 32):
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("e8c24a"))
	parent.add_child(label)
	return label


func _btn(parent, text, cb):
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _show(name):
	for key in _screens:
		_screens[key].visible = key == name
	if name == "join":
		Network.start_discovery()
	else:
		Network.stop_discovery()


func _set_status(text):
	if _status != null:
		_status.text = text


# --- start screen ---------------------------------------------------------------------------------
func _build_start_screen():
	var box = _screen("start")
	_title(box, "LOTR Battle Empires", 40)
	_title(box, "Hero-led armies. Four kingdoms. One map.", 16)
	var row = HBoxContainer.new()
	box.add_child(row)
	var l = Label.new()
	l.text = "Your name: "
	row.add_child(l)
	_name_edit = LineEdit.new()
	_name_edit.text = Network.player_name
	_name_edit.custom_minimum_size.x = 260
	_name_edit.text_changed.connect(func(t): Network.player_name = t.strip_edges().left(16))
	row.add_child(_name_edit)
	_btn(box, "Single player (you vs bots)", _on_single_player)
	_btn(box, "Host a LAN game", _on_host)
	_btn(box, "Join a LAN game", func(): _show("join"))
	_btn(box, "Back", func(): get_tree().change_scene_to_file("res://source/main-menu/Main.tscn"))
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)


func _on_single_player():
	_offline = true
	Network.leave()
	Network.reset_slots()
	Network.slots[0].name = Network.player_name
	_show("lobby")
	_refresh_lobby(Network.slots)


func _on_host():
	_offline = false
	var err = Network.host_game()
	if err != OK:
		_set_status("Couldn't host (port %d busy?)" % Network.GAME_PORT)
		return
	Network.slots[0].name = Network.player_name
	_show("lobby")
	_refresh_lobby(Network.slots)


# --- join screen ----------------------------------------------------------------------------------
func _build_join_screen():
	var box = _screen("join")
	_title(box, "Join a LAN game")
	var hint = Label.new()
	hint.text = "Games on your network appear below automatically."
	box.add_child(hint)
	_games_list = VBoxContainer.new()
	box.add_child(_games_list)
	var row = HBoxContainer.new()
	box.add_child(row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "or type the host's IP, e.g. 192.168.1.20"
	_ip_edit.custom_minimum_size.x = 400
	row.add_child(_ip_edit)
	_btn(row, "Join by IP", func(): _join(_ip_edit.text.strip_edges()))
	_btn(box, "Back", func(): _show("start"))
	_refresh_games({})


func _refresh_games(games):
	for c in _games_list.get_children():
		c.queue_free()
	if games.is_empty():
		var l = Label.new()
		l.text = "Looking for games..."
		_games_list.add_child(l)
		return
	for ip in games:
		var g = games[ip]
		_btn(_games_list, "%s's game  (%s, %d player%s)" % [g.name, ip, g.players, "" if g.players == 1 else "s"], _join.bind(ip))


func _join(ip):
	if ip == "":
		return
	_offline = false
	Network.player_name = _name_edit.text.strip_edges().left(16)
	if Network.join_game(ip) != OK:
		_set_status("Couldn't start connecting to %s" % ip)
		_show("start")
		return
	_set_status("Connecting to %s..." % ip)
	_show("start")
	await Network.connected_to_host
	await get_tree().create_timer(0.3).timeout
	var idx = Network.local_slot_index()
	if idx >= 0:
		Network.request_slot_change(idx, "name", Network.player_name)


func _on_host_left():
	_set_status("The host closed the game.")
	_show("start")


# --- lobby screen ---------------------------------------------------------------------------------
func _build_lobby_screen():
	var box = _screen("lobby")
	_title(box, "Lobby")
	var grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	box.add_child(grid)
	for header in ["Player", "Slot", "Faction", "Hero", "Team"]:
		var l = Label.new()
		l.text = header
		l.add_theme_color_override("font_color", Color("e8c24a"))
		grid.add_child(l)
	for i in range(Network.SLOT_COUNT):
		var row = {}
		row.name = Label.new()
		row.name.custom_minimum_size.x = 160
		grid.add_child(row.name)
		row.kind = OptionButton.new()
		for k in ["open", "bot", "human"]:
			row.kind.add_item(KIND_LABELS[k])
		row.kind.set_item_disabled(2, true)  # humans arrive by joining
		row.kind.item_selected.connect(func(idx):
			if idx < 2:
				Network.request_slot_change(i, "kind", ["open", "bot"][idx]))
		grid.add_child(row.kind)
		row.faction = OptionButton.new()
		row.faction.add_theme_constant_override("icon_max_width", 28)
		row.faction.get_popup().add_theme_constant_override("icon_max_width", 40)
		for f in GameData.PLAYABLE_FACTIONS:
			var emblem = Icons.art("emblems", f)
			if emblem != null:
				row.faction.add_icon_item(emblem, GameData.FACTIONS[f].name)
			else:
				row.faction.add_item(GameData.FACTIONS[f].name)
		row.faction.item_selected.connect(func(idx): Network.request_slot_change(i, "faction", GameData.PLAYABLE_FACTIONS[idx]))
		grid.add_child(row.faction)
		row.hero = OptionButton.new()
		row.hero.add_theme_constant_override("icon_max_width", 28)
		row.hero.get_popup().add_theme_constant_override("icon_max_width", 40)
		row.hero.item_selected.connect(func(idx): Network.request_slot_change(i, "hero", row.hero.get_item_metadata(idx)))
		grid.add_child(row.hero)
		row.team = Label.new()
		row.team.text = "Team %d" % Network.team_of_slot(i)
		row.team.add_theme_color_override("font_color", Color("8fb4ff") if Network.team_of_slot(i) == 1 else Color("ff8a7a"))
		grid.add_child(row.team)
		_slot_rows.append(row)
	_preset_row = HBoxContainer.new()
	box.add_child(_preset_row)
	var info = Label.new()
	info.text = "3 v 3. Each team is one people and shares one city and one war chest of Supplies. Team 1 holds the south-west city, Team 2 the north-east. Picking a faction changes it for the whole team; every hero is taken once."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(info)
	_start_button = _btn(box, "Start match", _on_start)
	_btn(box, "Leave", _on_leave)


func _refresh_lobby(slots):
	var is_host = Network.is_host()
	var me = Network.local_slot_index()
	for i in range(_slot_rows.size()):
		var row = _slot_rows[i]
		var slot = slots[i]
		row.name.text = slot.name + ("  (you)" if i == me else "")
		var human = slot.kind == "human"
		row.kind.disabled = not is_host or human
		row.kind.select(["open", "bot", "human"].find(slot.kind))
		var editable = (is_host and not human) or i == me
		var open = slot.kind == "open"
		row.faction.disabled = not editable or open
		row.hero.disabled = not editable or open
		row.faction.select(GameData.PLAYABLE_FACTIONS.find(slot.faction))
		row.hero.clear()
		var idx = 0
		for hero_key in GameData.FACTIONS[slot.faction].heroes:
			if GameData.HEROES.has(hero_key):
				var portrait = Icons.art("portraits", hero_key)
				if portrait != null:
					row.hero.add_icon_item(portrait, GameData.HEROES[hero_key].name)
				else:
					row.hero.add_item(GameData.HEROES[hero_key].name)
				row.hero.set_item_metadata(idx, hero_key)
				if hero_key == slot.hero:
					row.hero.select(idx)
				idx += 1
	_preset_row.visible = is_host
	_start_button.visible = is_host
	_start_button.disabled = not Network.can_start()
	_start_button.text = "Start match" if Network.can_start() else "Need at least two teams"


func _on_start():
	if Network.can_start():
		Network.start_match()


func _on_leave():
	Network.leave()
	_show("start")


func _on_match_starting(settings):
	var loader = LoaderScript.new()
	loader.settings = settings
	get_tree().root.add_child(loader)
	get_tree().current_scene = loader
	queue_free()


func _key_art(parent, name, dim = 0.45):
	var tex = load("res://assets/art/keyart/%s.webp" % name) if ResourceLoader.exists("res://assets/art/keyart/%s.webp" % name) else null
	if tex == null:
		return
	var art = TextureRect.new()
	art.texture = tex
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(art)
	var shade = ColorRect.new()
	shade.color = Color(0, 0, 0, dim)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(shade)
