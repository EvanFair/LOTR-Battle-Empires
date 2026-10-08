extends "res://source/lotr/units/LotrUnit.gd"
## The only unit a player controls directly. Levels up from XP, casts QWER abilities, and
## respawns at its Town Center after a timer that grows with level.

signal leveled_up(level)
signal death_state_changed(dead)

var hero_key = "aragorn"
var level = 1
var xp = 0
var mana = 0.0
var mana_max = 0.0
var mana_regen = 2.0
var dead = false
var respawn_at = 0.0
var cooldowns = {}  # ability key -> time (s) when ready again
var home_position = Vector3.ZERO


func _ready():
	await super()
	var data = GameData.HEROES[hero_key]
	mana_max = data.mana
	mana = mana_max
	mana_regen = data.get("mana_regen", 2.0)
	auto_acquire = false  # heroes only fight when told to (or when attacked, see below)
	home_position = global_position


func is_alive():
	return super() and not dead


func abilities():
	return GameData.HEROES[hero_key].abilities


func ability(key: String):
	for a in abilities():
		if a.key == key:
			return a
	return null


func cooldown_left(key: String) -> float:
	return max(0.0, cooldowns.get(key, 0.0) - GameData.now())


func add_xp(amount: int):
	xp += amount
	var new_level = GameData.level_for_xp(xp)
	while level < new_level:
		_level_up()


func _level_up():
	level += 1
	var s = GameData.hero_stats_at_level(hero_key, level)
	var hp_gain = s.hp - hp_max
	hp_max = s.hp
	hp = min(hp_max, hp + hp_gain)
	attack_damage = s.damage
	leveled_up.emit(level)


func _physics_process(delta):
	if puppet:
		return
	if dead:
		if player.defeated:
			return
		if GameData.now() >= respawn_at:
			_respawn()
		return
	mana = min(mana_max, mana + mana_regen * delta)
	super(delta)


func _process_idle(delta):
	# heroes don't chase things on their own, but they hit back at whatever is next to them
	if order == Order.HOLD or attack_damage == null:
		return
	_retarget_timer -= delta
	if _retarget_timer > 0.0:
		return
	_retarget_timer = RETARGET_INTERVAL
	var enemy = Combat.closest_enemy(self, global_position, attack_range + 0.8)
	if enemy != null:
		_try_hit(enemy)


func _handle_unit_death():
	if dead:
		return
	set_dead(true)
	if not puppet:
		respawn_at = GameData.now() + GameData.hero_respawn_time(level)
		died_on_host.emit()
		MatchSignals.unit_died.emit(self)


func set_dead(value: bool):
	if dead == value:
		return
	dead = value
	if anim_driver != null and anim_driver.player != null:
		# the hero falls and lies where they died until the respawn timer runs out
		anim_driver.locked = dead
		if dead:
			anim_driver.player.play("Death_A", 0.1)
		else:
			anim_driver.player.play("Idle")
	else:
		find_child("Geometry").visible = not dead
	find_child("HealthBar").visible = false
	input_ray_pickable = not dead
	if dead:
		order_stop()
		buffs.clear()
		_recompute_buffs()
	death_state_changed.emit(dead)


func _respawn():
	var spawn = home_position
	var tc = _find_town_center()
	if tc != null:
		spawn = tc.global_position + Vector3(0, 0, tc.stats_size() + 1.5)
	global_position = spawn
	set_dead(false)
	hp = hp_max
	mana = mana_max


func _find_town_center():
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.player == player and b.building_key == "town_center" and b.is_alive():
			return b
	return null
