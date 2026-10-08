extends "res://source/match/units/non-player/ResourceUnit.gd"
## A forest, quarry, iron mine or herd of game. Villagers take from it until it runs out.

var resource_type = "wood"
var amount = 500
var spawn_params = {}
var net_id = 0
var puppet = false
var color:
	get:
		return GameData.RESOURCE_NODES[resource_type].color


func take(wanted: int) -> int:
	var taken = mini(wanted, amount)
	amount -= taken
	if amount <= 0 and not puppet:
		queue_free()
	return taken


func is_depleted():
	return amount <= 0
