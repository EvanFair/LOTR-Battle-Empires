extends Node
## Sound effects and music. Clips are CC0 (assets/omoba/audio: Kenney + Open MOBA synths,
## music by Cleyton Kauffman; assets/lotr/audio: horns and drums synthesized for this game).
## play() is throttled per clip so a 100-unit battle doesn't stack hundreds of identical sounds.

const DIRS = ["res://assets/lotr/audio/", "res://assets/omoba/audio/sfx/"]
const MUSIC = {
	"battle": "res://assets/omoba/audio/music/arena.ogg",
}
const MIN_GAP = 0.06  # seconds between two plays of the same clip
const MAX_VOICES = 24
const HEARING_RANGE = 55.0

# per-clip volume trim (dB)
const VOLUME = {
	"hit": -8.0, "melee": -9.0, "arrow": -10.0, "death": -12.0, "tower": -6.0, "ui_click": -6.0,
	"ui_confirm": -4.0, "boulder": -4.0, "blast": -2.0, "horn": -2.0, "drums": -3.0,
}

var enabled = true
var music_volume_db = -14.0
var _streams = {}
var _last_played = {}
var _voices = []
var _music_player = null


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "Music"
	_music_player.volume_db = music_volume_db
	add_child(_music_player)


func _stream(clip: String):
	if _streams.has(clip):
		return _streams[clip]
	var stream = null
	for dir in DIRS:
		for ext in [".ogg", ".wav"]:
			if ResourceLoader.exists(dir + clip + ext):
				stream = load(dir + clip + ext)
				break
		if stream != null:
			break
	_streams[clip] = stream
	return stream


func play(clip: String, at = null, volume_db = 0.0, pitch_jitter = 0.08):
	"""Play a clip. at: a Vector3 world position (positional, culled when far from the camera)
	or null for a flat UI sound."""
	if not enabled or DisplayServer.get_name() == "headless":
		return
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_played.get(clip, -1.0) < MIN_GAP:
		return
	var stream = _stream(clip)
	if stream == null:
		return
	if at != null:
		var camera = get_viewport().get_camera_3d()
		if camera != null and _listener_point(camera).distance_to(at) > HEARING_RANGE:
			return
	_voices = _voices.filter(func(v): return is_instance_valid(v))
	if _voices.size() >= MAX_VOICES:
		return
	_last_played[clip] = now
	var player
	if at != null:
		player = AudioStreamPlayer3D.new()
		player.max_distance = HEARING_RANGE
		player.unit_size = 14.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		player.global_position = at
	else:
		player = AudioStreamPlayer.new()
		add_child(player)
	player.stream = stream
	player.volume_db = VOLUME.get(clip, 0.0) + volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.finished.connect(player.queue_free)
	player.play()
	_voices.append(player)


func _listener_point(camera: Camera3D) -> Vector3:
	# the isometric camera sits high above the field; measure from where it looks at the ground
	var origin = camera.global_position
	var dir = -camera.global_transform.basis.z
	if abs(dir.y) > 0.01:
		var t = -origin.y / dir.y
		if t > 0.0:
			return origin + dir * t
	return origin


func play_music(key = "battle"):
	if not enabled or DisplayServer.get_name() == "headless" or not MUSIC.has(key):
		return
	var stream = load(MUSIC[key])
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_music_player.stream = stream
	_music_player.volume_db = music_volume_db
	_music_player.play()


func stop_music():
	if _music_player != null:
		_music_player.stop()
