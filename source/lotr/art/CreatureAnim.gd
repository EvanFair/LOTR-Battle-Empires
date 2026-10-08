extends Node
## Procedural animation for creatures without a skeleton (spiders, siege engines): legs
## scuttle and the body bobs with how fast the unit is moving; a lunge plays on attack.

var legs = []  # Node3D pivots; each swings around its own X axis
var body: Node3D = null
var gait = 9.0  # leg cycles per metre-ish

var _unit = null
var _last_pos = Vector3.ZERO
var _phase = 0.0
var _lunge = 0.0
var _last_attack_seen = -10.0


func _ready():
	_unit = get_parent()
	_last_pos = _unit.global_position


func _process(delta):
	if not is_instance_valid(_unit) or delta <= 0.0:
		return
	var pos = _unit.global_position
	var speed = Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length() / delta
	_last_pos = pos
	_phase += delta * (2.0 + speed * gait)
	var swing = clampf(speed / 3.0, 0.15, 1.0) * 0.45
	for i in range(legs.size()):
		var offset = PI * (i % 2) + (i / 2) * 0.6
		legs[i].rotation.x = sin(_phase + offset) * swing
	var attack_at = _unit.get("last_attack_at")
	if attack_at != null and attack_at > _last_attack_seen:
		_last_attack_seen = attack_at
		_lunge = 1.0
	_lunge = max(0.0, _lunge - delta * 3.0)
	if body != null:
		body.position.y = body.get_meta("base_y", 0.0) + sin(_phase * 2.0) * 0.04
		body.position.z = -sin(_lunge * PI) * 0.35
