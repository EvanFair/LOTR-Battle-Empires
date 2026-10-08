extends Node3D

const SIGHT_COMPENSATION = 2.0  # compensates for blurry edges of FoW

const Structure = preload("res://source/match/units/Structure.gd")

var _units_processed_at_least_once = {}
var _structure_to_dummy_mapping = {}
var _orphaned_dummies = []


func _ready():
	MatchSignals.unit_spawned.connect(_recalculate_unit_visibility)
	MatchSignals.unit_died.connect(_on_unit_died)


const UPDATE_EVERY_N_PHYSICS_FRAMES = 6  # 10 Hz is plenty for fog of war
const GRID_CELL = 16.0  # >= the longest sight range + compensation

var _frame_counter = 0


func _physics_process(_delta):
	_frame_counter += 1
	if _frame_counter % UPDATE_EVERY_N_PHYSICS_FRAMES != 0:
		return
	var all_units = get_tree().get_nodes_in_group("units")
	var revealed_units = all_units.filter(func(unit): return unit.is_in_group("revealed_units"))
	# bucket revealers into a coarse grid: each unit then only checks the 3x3 cells around it
	# instead of every revealer on the map (the original was O(units x revealers) per frame)
	var grid = {}
	for r in revealed_units:
		if not r.is_revealing() or r.sight_range == null:
			continue
		var k = Vector2i(floori(r.global_position.x / GRID_CELL), floori(r.global_position.z / GRID_CELL))
		if grid.has(k):
			grid[k].append(r)
		else:
			grid[k] = [r]
	for unit in all_units:
		if unit.is_in_group("revealed_units") or _is_disabled():
			_update_unit_visibility(unit, true)
			continue
		var k = Vector2i(floori(unit.global_position.x / GRID_CELL), floori(unit.global_position.z / GRID_CELL))
		var nearby = []
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var bucket = grid.get(k + Vector2i(dx, dz))
				if bucket != null:
					nearby.append_array(bucket)
		_recalculate_unit_visibility(unit, nearby)
	for orphaned_dummy in _orphaned_dummies:
		_recalcuate_orphaned_dummy_existence(orphaned_dummy, revealed_units)


func _is_disabled():
	return not visible


func _recalculate_unit_visibility(unit, revealed_units = null):
	if unit.is_in_group("revealed_units") or _is_disabled():
		_update_unit_visibility(unit, true)
		return

	var should_be_visible = false
	if revealed_units == null:
		revealed_units = get_tree().get_nodes_in_group("units").filter(
			func(a_unit): return a_unit.is_in_group("revealed_units")
		)
	for revealed_unit in revealed_units:
		if (
			revealed_unit.is_revealing()
			and revealed_unit.sight_range != null
			and (
				(revealed_unit.global_position * Vector3(1, 0, 1)).distance_to(
					unit.global_position * Vector3(1, 0, 1)
				)
				<= revealed_unit.sight_range + SIGHT_COMPENSATION
			)
		):
			should_be_visible = true
			break
	_update_unit_visibility(unit, should_be_visible)


func _update_unit_visibility(unit, should_be_visible):
	if (
		unit in _units_processed_at_least_once
		and unit is Structure
		and unit.visible != should_be_visible
	):
		if unit.visible:
			_create_dummy_structure(unit)
		else:
			_try_removing_dummy_structure(unit)
	unit.visible = should_be_visible
	_units_processed_at_least_once[unit] = true


func _create_dummy_structure(unit):
	if unit in _structure_to_dummy_mapping:
		return
	var dummy = unit.find_child("Geometry").duplicate()
	dummy.global_transform = unit.find_child("Geometry").global_transform
	add_child(dummy)
	_structure_to_dummy_mapping[unit] = dummy


func _try_removing_dummy_structure(unit):
	if unit in _structure_to_dummy_mapping:
		_structure_to_dummy_mapping[unit].queue_free()
		_structure_to_dummy_mapping.erase(unit)


func _recalcuate_orphaned_dummy_existence(orphaned_dummy, revealed_units = null):
	var should_exist = true
	if revealed_units == null:
		revealed_units = get_tree().get_nodes_in_group("units").filter(
			func(unit): return unit.is_in_group("revealed_units")
		)
	for revealed_unit in revealed_units:
		if (
			revealed_unit.is_revealing()
			and revealed_unit.sight_range != null
			and (
				(revealed_unit.global_position * Vector3(1, 0, 1)).distance_to(
					orphaned_dummy.global_position * Vector3(1, 0, 1)
				)
				<= revealed_unit.sight_range + SIGHT_COMPENSATION
			)
		):
			should_exist = false
			break
	if not should_exist:
		_orphaned_dummies.erase(orphaned_dummy)
		orphaned_dummy.queue_free()


func _on_unit_died(unit):
	_units_processed_at_least_once.erase(unit)
	if unit in _structure_to_dummy_mapping:
		var orphaned_dummy = _structure_to_dummy_mapping[unit]
		_structure_to_dummy_mapping.erase(unit)
		_orphaned_dummies.append(orphaned_dummy)
		_recalcuate_orphaned_dummy_existence(orphaned_dummy)
