extends "res://source/lotr/units/LotrUnit.gd"
## A wild creature in a jungle camp (spiders, wargs, the Cave Troll). Passive until struck;
## then its whole camp turns on the attacker. Pulled too far from home it walks back and heals.
## Host only (clients see puppets).

enum State { HOME, FIGHT, RETURN }

var creature_key = "spider"
var anchor = Vector3.ZERO  # where the camp lives
var home_spot = Vector3.ZERO  # this creature's own resting place
var camp = null  # Dictionary shared by the camp's creatures (see LotrMatch camps)
var state = State.HOME

var _think_left = 0.0


func _ready():
	await super()
	auto_acquire = false


func _physics_process(delta):
	if puppet or not is_alive():
		return
	_think_left -= delta
	if _think_left <= 0.0:
		_think_left = 0.25
		_think()
	super(delta)


func _think():
	match state:
		State.HOME:
			var attacker = _valid_attacker()
			if attacker != null:
				_camp_aggro(attacker)
		State.FIGHT:
			if global_position_yless.distance_to(anchor * Vector3(1, 0, 1)) > GameData.LEASH_RANGE:
				_go_home()
				return
			if order != Order.ATTACK:
				# target gone: fight whoever hit us last, else go home
				var attacker = _valid_attacker()
				if attacker != null:
					order_attack(attacker)
				else:
					_go_home()
		State.RETURN:
			hp = min(hp_max, hp + max(1, int(hp_max * 0.08)))
			if global_position_yless.distance_to(home_spot * Vector3(1, 0, 1)) < 1.2 or order == Order.IDLE:
				hp = hp_max
				state = State.HOME
				last_attacker = null
				order_stop()


func _valid_attacker():
	var a = last_attacker
	if a == null or not is_instance_valid(a) or not a.is_alive() or not "player" in a:
		return null
	if a.player == null or a.player.get("is_neutral") == true:
		return null
	if a.global_position_yless.distance_to(anchor * Vector3(1, 0, 1)) > GameData.LEASH_RANGE + 4.0:
		return null
	return a


func _camp_aggro(attacker):
	var members = camp.members if camp != null else [self]
	for m in members:
		if is_instance_valid(m) and m.is_alive() and m.state != State.RETURN:
			m.state = State.FIGHT
			m.order_attack(attacker)


func _go_home():
	state = State.RETURN
	last_attacker = null
	order_move(home_spot)
