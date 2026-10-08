extends "res://source/lotr/units/LotrUnit.gd"
## A soldier in a squadron. The Squadron decides what it does; it fights on its own when idle.

var summon_expires_at = 0.0  # summoned units (Army of the Dead, Wargs) vanish after this time


func _ready():
	await super()
	aggro_range = GameData.SQUAD_AGGRO_RANGE


func _physics_process(delta):
	super(delta)
	if (
		not puppet
		and summon_expires_at > 0.0
		and GameData.now() > summon_expires_at
		and is_alive()
	):
		hp = 0
