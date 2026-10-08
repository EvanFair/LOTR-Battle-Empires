extends Node
## Plays the right character animation from what the unit is visibly doing: idle, walk/run (from
## how fast it is actually moving, so it works for host units and LAN puppets alike), attack
## (when the unit swings), work (villagers gathering). Death is handled by LotrUnit.

const RUN_SPEED = 2.2
const MOVE_EPS = 0.25
const BLEND = 0.15

var anim_set = "melee"
var locked = false  # true while a one-off (e.g. a dead hero lying down) must not be replaced
var player: AnimationPlayer = null

var _unit = null
var _last_pos = Vector3.ZERO
var _speed = 0.0
var _current = ""
var _attack_ends = 0.0
var _attack_index = 0


func _ready():
	_unit = get_parent()
	_last_pos = _unit.global_position


func play_attack():
	if player == null or locked:
		return
	var options = Art.ANIMS[anim_set].attack
	var anim_name = options[_attack_index % options.size()]
	_attack_index += 1
	if not player.has_animation(anim_name):
		return
	var length = player.get_animation(anim_name).length
	var speed = 1.0
	var interval = _unit.get("attack_interval")
	if interval != null and interval > 0.0:
		speed = clampf(length / interval, 1.0, 2.5)  # never slower than the hit rate
	player.play(anim_name, BLEND, speed)
	_current = anim_name
	_attack_ends = GameData.now() + length / speed


func _process(delta):
	if player == null or locked or not is_instance_valid(_unit) or delta <= 0.0:
		return
	var pos = _unit.global_position
	var step = Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length() / delta
	_last_pos = pos
	_speed = lerpf(_speed, step, clampf(delta * 10.0, 0.0, 1.0))
	if GameData.now() < _attack_ends:
		return
	var set = Art.ANIMS[anim_set]
	var wanted = set.idle
	if _speed > MOVE_EPS:
		wanted = set.run if _speed > RUN_SPEED else set.walk
	elif set.has("work") and _unit.get("state") != null and _unit.state == 3:  # Villager GATHER
		wanted = set.work
	if wanted != _current or not player.is_playing():
		if player.has_animation(wanted):
			player.play(wanted, BLEND, clampf(_speed / 2.0, 0.8, 1.6) if wanted != set.idle else 1.0)
			_current = wanted
