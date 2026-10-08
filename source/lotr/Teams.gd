class_name Teams
## Team rules. FFA is simply every player on their own team.


static func is_enemy(player_a, player_b) -> bool:
	if player_a == null or player_b == null or player_a == player_b:
		return false
	var team_a = player_a.get("team")
	var team_b = player_b.get("team")
	if team_a == null or team_b == null:
		return player_a != player_b
	return team_a != team_b


static func is_ally(player_a, player_b) -> bool:
	return player_a != null and player_b != null and not is_enemy(player_a, player_b)
