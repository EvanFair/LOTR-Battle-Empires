extends Node

@export_group("Game")
@export var show_logos_on_startup = true
@export var save_user_files_in_tmp = false

@export_group("Match")
@export var allow_resources_deficit_spending = false
@export var handle_match_end = true
@export var show_minimap = true
@export var allow_navigation_rebaking = true
# air units (aircraft factory, helicopters, drones, AA turrets) are kept for later
# flying factions (Eagles, Fell Beasts) but are switched off for now
@export var air_units_enabled = false

@export_group("Match/Debug")
@export var frame_incrementer = false
@export var god_mode = false
