extends SceneTree

var _failures: PackedStringArray = []
var _registry := MasterDataRegistry.new()
var _regions := {&"nova_capital": true, &"nova_border": true}


func _initialize() -> void:
	_registry.load_all()
	_check(_registry.load_errors.is_empty(), "master data must load before runtime tests")
	_test_valid_graph()
	_test_json_round_trip()
	_test_invalid_graph()
	if _failures.is_empty():
		print("runtime_state_test: all checks passed")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("runtime_state_test: %s" % failure)
		quit(1)


func _test_valid_graph() -> void:
	var unit := _make_unit(&"unit_001", &"aria_nova")
	var squad := _make_squad(unit)
	var errors := RuntimeStateValidator.new().validate(
		{unit.instance_id: unit}, {squad.squad_id: squad}, _registry, _regions
	)
	_check(errors.is_empty(), "valid graph rejected: %s" % errors)
	_check(not unit.is_generic_pilot(), "named pilot must not be generic")
	_check(unit.is_assigned_to_squad(), "assigned unit sentinel must be recognized")

	unit.pilot_id = &""
	squad.leader_pilot_id = &""
	errors = RuntimeStateValidator.new().validate(
		{unit.instance_id: unit}, {squad.squad_id: squad}, _registry, _regions,
		{unit.instance_id: 2500},
	)
	_check(errors.is_empty(), "generic pilot or HP override rejected: %s" % errors)
	_check(unit.is_generic_pilot(), "empty pilot ID must mean generic pilot")
	_check(squad.is_generic_pilot_leader(), "empty leader ID must mean generic leader")


func _test_json_round_trip() -> void:
	var unit := _make_unit(&"unit_round_trip", &"aria_nova")
	unit.movement_used = true
	unit.captured = true
	var squad := _make_squad(unit)
	squad.display_name = "Round Trip"
	squad.movement_used = true
	squad.move_origin_region_id = &"nova_border"
	squad.planned_destination_region_id = &"nova_capital"

	var unit_dict := unit.to_dict()
	var squad_dict := squad.to_dict()
	_check(not _contains_object(unit_dict), "unit save dictionary contains an Object")
	_check(not _contains_object(squad_dict), "squad save dictionary contains an Object")
	var unit_json: Variant = JSON.parse_string(JSON.stringify(unit_dict))
	var squad_json: Variant = JSON.parse_string(JSON.stringify(squad_dict))
	_check(unit_json is Dictionary, "unit JSON did not decode to Dictionary")
	_check(squad_json is Dictionary, "squad JSON did not decode to Dictionary")
	if not unit_json is Dictionary or not squad_json is Dictionary:
		return
	var restored_unit := UnitInstanceState.from_dict(unit_json)
	var restored_squad := SquadState.from_dict(squad_json)
	_check(restored_unit.to_dict() == unit.to_dict(), "unit JSON round trip changed state")
	_check(restored_squad.to_dict() == squad.to_dict(), "squad JSON round trip changed state")
	var errors := RuntimeStateValidator.new().validate(
		{restored_unit.instance_id: restored_unit},
		{restored_squad.squad_id: restored_squad},
		_registry,
		_regions,
	)
	_check(errors.is_empty(), "round-tripped graph rejected: %s" % errors)


func _test_invalid_graph() -> void:
	var first := _make_unit(&"unit_bad_1", &"aria_nova")
	var second := _make_unit(&"unit_bad_2", &"aria_nova")
	first.unit_def_id = &"missing_unit"
	first.owner_faction_id = &"missing_faction"
	first.origin_faction_id = &""
	first.current_hp = -1
	first.current_en = 999999
	first.condition = GameEnums.UnitCondition.REPAIRING
	first.repair_turns_remaining = 0
	first.squad_id = &"bad_squad"
	first.slot_index = 6
	second.squad_id = &"bad_squad"
	second.slot_index = 0

	var squad := SquadState.new()
	squad.squad_id = &"bad_squad"
	squad.owner_faction_id = &"nova_republic"
	squad.region_id = &"missing_region"
	var invalid_unit_ids: Array[StringName] = [&"unit_bad_1", &"unit_bad_2", &"unit_bad_2"]
	var invalid_slots: Array[StringName] = [&"unit_bad_2", &"unit_bad_2", &"missing_instance", &"", &""]
	squad.unit_instance_ids = invalid_unit_ids
	squad.slot_unit_ids = invalid_slots
	squad.leader_pilot_id = &"darius_crimson"
	squad.battle_policy = 99
	squad.intel_revision = -1

	var errors := RuntimeStateValidator.new().validate(
		{&"wrong_dictionary_key": first, second.instance_id: second},
		{&"wrong_squad_key": squad},
		_registry,
		_regions,
	)
	_check(errors.size() >= 12, "invalid graph produced too few errors: %s" % errors)
	for fragment: String in [
		"dictionary key does not match", "unit_def_id", "owner_faction_id",
		"origin_faction_id", "current_hp", "current_en", "repair_turns_remaining",
		"slot_index", "region_id", "duplicate", "back-reference", "named leader",
		"battle_policy", "intel_revision", "assigned to both",
	]:
		_check(_has_fragment(errors, fragment), "invalid graph missed '%s': %s" % [fragment, errors])
	var sorted := errors.duplicate()
	sorted.sort()
	_check(errors == sorted, "validator errors must be deterministically sorted")

	var empty_squad := SquadState.new()
	empty_squad.squad_id = &"empty_squad"
	empty_squad.owner_faction_id = &"nova_republic"
	empty_squad.region_id = &"nova_capital"
	var empty_errors := RuntimeStateValidator.new().validate(
		{}, {empty_squad.squad_id: empty_squad}, _registry, _regions
	)
	_check(_has_fragment(empty_errors, "1..5"), "empty squad must be rejected")


func _make_unit(id: StringName, pilot: StringName) -> UnitInstanceState:
	var unit := UnitInstanceState.new()
	unit.instance_id = id
	unit.unit_def_id = &"nova_vanguard"
	unit.owner_faction_id = &"nova_republic"
	unit.origin_faction_id = &"nova_republic"
	unit.current_hp = 2200
	unit.current_en = 360
	unit.pilot_id = pilot
	unit.squad_id = &"squad_001"
	unit.slot_index = 0
	return unit


func _make_squad(unit: UnitInstanceState) -> SquadState:
	var squad := SquadState.new()
	squad.squad_id = unit.squad_id
	squad.display_name = "Test Squad"
	squad.owner_faction_id = unit.owner_faction_id
	squad.region_id = &"nova_capital"
	_check(squad.assign_unit(unit.instance_id, unit.slot_index), "test setup failed to assign unit")
	squad.leader_pilot_id = unit.pilot_id
	return squad


func _contains_object(value: Variant) -> bool:
	if value is Object:
		return true
	if value is Dictionary:
		for key: Variant in value:
			if _contains_object(key) or _contains_object(value[key]):
				return true
	elif value is Array:
		for item: Variant in value:
			if _contains_object(item):
				return true
	return false


func _has_fragment(errors: PackedStringArray, fragment: String) -> bool:
	for error: String in errors:
		if fragment in error:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
