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


var _regrow_carry = 0.0


func take(wanted: int) -> int:
	var taken = mini(wanted, amount)
	amount -= taken
	if amount <= 0 and not puppet and not GameData.RESOURCE_NODES[resource_type].has("regrow"):
		queue_free()
	return taken


func _physics_process(delta):
	var regrow = GameData.RESOURCE_NODES[resource_type].get("regrow", 0.0)
	if puppet or regrow <= 0.0:
		return
	var cap = GameData.RESOURCE_NODES[resource_type].amount
	if amount >= cap:
		return
	_regrow_carry += regrow * delta
	if _regrow_carry >= 1.0:
		amount = mini(cap, amount + int(_regrow_carry))
		_regrow_carry -= int(_regrow_carry)


func is_depleted():
	return amount <= 0
