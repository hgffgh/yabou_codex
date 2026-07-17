extends SceneTree

var _failures: PackedStringArray = []
var _registry := MasterDataRegistry.new()
var _regions := {&"nova_capital": true, &"nova_border": true}


func _initialize() -> void:
	_registry.load_all()
	_check(_registry.load_errors.is_empty(), "master data must load before campaign tests")
	_test_rollout_and_deterministic_ids()
	_test_collision_skip()
	_test_failed_rollout_is_atomic()
	_test_stable_serialization_and_round_trip()
	_test_relation_state_round_trip()
	_test_disband_and_remove()
	_test_reset()
	if _failures.is_empty():
		print("campaign_runtime_state_test: all checks passed")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("campaign_runtime_state_test: %s" % failure)
		quit(1)


func _test_rollout_and_deterministic_ids() -> void:
	var state := CampaignRuntimeState.new()
	var result := state.rollout_unit(
		&"nova_vanguard", &"nova_republic", &"nova_capital", _registry, _regions
	)
	_check(result.errors.is_empty(), "valid rollout failed: %s" % result.errors)
	var unit: UnitInstanceState = result.unit
	var squad: SquadState = result.squad
	_check(unit != null and squad != null, "valid rollout did not return both records")
	if unit == null or squad == null:
		return
	_check(unit.instance_id == &"unit_00000001", "first unit ID is not deterministic")
	_check(squad.squad_id == &"squad_00000001", "first squad ID is not deterministic")
	_check(unit.current_hp == 2200 and unit.current_en == 360, "rollout did not use master HP/EN")
	_check(unit.pilot_id.is_empty() and squad.leader_pilot_id.is_empty(), "rollout must use a generic pilot")
	_check(unit.squad_id == squad.squad_id and unit.slot_index == 0, "unit back-reference is not front slot 0")
	_check(squad.get_unit_at_slot(0) == unit.instance_id, "squad front slot 0 does not contain rollout unit")
	var expected_unit_ids: Array[StringName] = [unit.instance_id]
	_check(squad.unit_instance_ids == expected_unit_ids, "squad membership is not exactly one unit")
	_check(squad.intel_revision == 0, "initial rollout revision must be zero")
	_check(state.units_by_id.size() == 1 and state.squads_by_id.size() == 1, "rollout did not commit exactly one pair")
	_check(state.validate(_registry, _regions).is_empty(), "rollout graph failed runtime validation")

	var second := state.rollout_unit(
		&"nova_scout", &"nova_republic", &"nova_border", _registry, _regions
	)
	_check(second.errors.is_empty(), "second valid rollout failed")
	_check(second.unit.instance_id == &"unit_00000002", "unit serial did not advance deterministically")
	_check(second.squad.squad_id == &"squad_00000002", "squad serial did not advance deterministically")


func _test_collision_skip() -> void:
	var state := CampaignRuntimeState.new()
	var occupied_unit := UnitInstanceState.new()
	occupied_unit.instance_id = &"unit_00000001"
	state.units_by_id[occupied_unit.instance_id] = occupied_unit
	var occupied_squad := SquadState.new()
	occupied_squad.squad_id = &"squad_00000001"
	state.squads_by_id[occupied_squad.squad_id] = occupied_squad

	var result := state.rollout_unit(
		&"nova_scout", &"nova_republic", &"nova_capital", _registry, _regions
	)
	_check(result.errors.is_empty(), "rollout failed instead of skipping occupied IDs")
	_check(result.unit.instance_id == &"unit_00000002", "unit allocator did not skip a collision")
	_check(result.squad.squad_id == &"squad_00000002", "squad allocator did not skip a collision")
	_check(state.units_by_id[&"unit_00000001"] == occupied_unit, "unit collision overwrote existing state")
	_check(state.squads_by_id[&"squad_00000001"] == occupied_squad, "squad collision overwrote existing state")


func _test_failed_rollout_is_atomic() -> void:
	var state := CampaignRuntimeState.new()
	var before := state.to_dict()
	for invalid_args: Array in [
		[&"missing_unit", &"nova_republic", &"nova_capital"],
		[&"nova_scout", &"missing_faction", &"nova_capital"],
		[&"nova_scout", &"nova_republic", &"missing_region"],
	]:
		var result := state.rollout_unit(
			invalid_args[0], invalid_args[1], invalid_args[2], _registry, _regions
		)
		_check(not result.errors.is_empty(), "invalid rollout was accepted: %s" % [invalid_args])
		_check(result.unit == null and result.squad == null, "failed rollout returned a partial record")
		_check(state.to_dict() == before, "failed rollout mutated records or serial counters")


func _test_stable_serialization_and_round_trip() -> void:
	var state := CampaignRuntimeState.new()
	state.rollout_unit(&"nova_vanguard", &"nova_republic", &"nova_border", _registry, _regions)
	state.rollout_unit(&"nova_scout", &"nova_republic", &"nova_capital", _registry, _regions)
	var saved := state.to_dict()
	_check(not _contains_object(saved), "campaign save dictionary contains an Object")
	_check(saved.unit_states[0].instance_id == &"unit_00000001", "unit save order is not stable")
	_check(saved.unit_states[1].instance_id == &"unit_00000002", "unit save order is not sorted")
	_check(saved.squad_states[0].squad_id == &"squad_00000001", "squad save order is not stable")
	_check(saved.squad_states[1].squad_id == &"squad_00000002", "squad save order is not sorted")

	var decoded: Variant = JSON.parse_string(JSON.stringify(saved))
	_check(decoded is Dictionary, "campaign JSON did not decode to a Dictionary")
	if not decoded is Dictionary:
		return
	var restored_result := CampaignRuntimeState.from_dict(decoded)
	_check(restored_result.errors.is_empty(), "campaign restore failed: %s" % restored_result.errors)
	var restored: CampaignRuntimeState = restored_result.state
	_check(restored.to_dict() == saved, "campaign JSON round trip changed state")
	_check(not _contains_object(restored.to_dict()), "restored save dictionary contains an Object")
	_check(restored.validate(_registry, _regions).is_empty(), "restored campaign failed runtime validation")
	var next := restored.rollout_unit(
		&"nova_scout", &"nova_republic", &"nova_capital", _registry, _regions
	)
	_check(next.unit.instance_id == &"unit_00000003", "restored unit counter reused an ID")
	_check(next.squad.squad_id == &"squad_00000003", "restored squad counter reused an ID")


## DATA_DEFINITION.md section 18: relation_states and diplomacy_log must
## survive a JSON round trip alongside everything else, and get_relation_state
## must resolve the same instance regardless of which faction is queried
## first (STRATEGY_DETAIL_SPECIFICATION.md 18.1's "対称値を原則とする").
func _test_relation_state_round_trip() -> void:
	var state := CampaignRuntimeState.new()
	state.ensure_relation_states([&"nova_republic", &"crimson_empire"])
	var relation := state.get_relation_state(&"nova_republic", &"crimson_empire")
	_check(relation.friendship == GameConstants.INITIAL_FRIENDSHIP, "ensure_relation_states did not seed the fixed initial friendship")
	_check(state.get_relation_state(&"crimson_empire", &"nova_republic") == relation,
		"get_relation_state must resolve the same instance regardless of argument order")

	relation.friendship = 12
	relation.treaty_type = GameEnums.TreatyType.CEASEFIRE
	relation.treaty_turns_remaining = 3
	relation.violator_faction_id = &"nova_republic"
	relation.violation_penalty_turns = 10
	relation.violation_success_penalty_pct = 10
	state.log_diplomacy(5, &"nova_republic", &"crimson_empire", &"gift", {}, true)  # empty payload: JSON has no int/float distinction, and a numeric payload would spuriously fail the strict to_dict() == saved comparison below

	var saved := state.to_dict()
	_check(not _contains_object(saved), "campaign save dictionary contains an Object")
	var decoded: Variant = JSON.parse_string(JSON.stringify(saved))
	_check(decoded is Dictionary, "campaign JSON did not decode to a Dictionary")
	if not decoded is Dictionary:
		return
	var restored_result := CampaignRuntimeState.from_dict(decoded)
	_check(restored_result.errors.is_empty(), "campaign restore failed: %s" % restored_result.errors)
	var restored: CampaignRuntimeState = restored_result.state
	_check(restored.to_dict() == saved, "campaign JSON round trip changed state")
	_check(restored.validate(_registry, _regions).is_empty(), "restored campaign failed runtime validation")

	var restored_relation := restored.get_relation_state(&"nova_republic", &"crimson_empire", false)
	_check(
		restored_relation != null and restored_relation.friendship == 12
		and restored_relation.treaty_type == GameEnums.TreatyType.CEASEFIRE
		and restored_relation.violator_faction_id == &"nova_republic",
		"relation_states did not survive the JSON round trip",
	)
	_check(
		restored.diplomacy_log.size() == 1 and StringName(restored.diplomacy_log[0].action_type) == &"gift",
		"diplomacy_log did not survive the JSON round trip",
	)


func _test_disband_and_remove() -> void:
	var state := CampaignRuntimeState.new()
	var result := state.rollout_unit(
		&"nova_scout", &"nova_republic", &"nova_capital", _registry, _regions
	)
	var unit: UnitInstanceState = result.unit
	var squad: SquadState = result.squad
	_check(not state.remove_unassigned_unit(unit.instance_id), "assigned unit was removed directly")
	_check(state.disband_squad(squad.squad_id), "existing squad could not be disbanded")
	_check(state.get_squad(squad.squad_id) == null, "disbanded squad remains registered")
	_check(unit.squad_id.is_empty() and unit.slot_index == -1, "disband did not clear unit membership")
	_check(not state.disband_squad(squad.squad_id), "missing squad was disbanded twice")
	_check(state.remove_unassigned_unit(unit.instance_id), "unassigned unit could not be removed")
	_check(state.get_unit(unit.instance_id) == null, "removed unit remains registered")
	_check(not state.remove_unassigned_unit(unit.instance_id), "missing unit was removed twice")
	_check(state.validate(_registry, _regions).is_empty(), "empty campaign failed runtime validation")


func _test_reset() -> void:
	var state := CampaignRuntimeState.new()
	state.rollout_unit(&"nova_scout", &"nova_republic", &"nova_capital", _registry, _regions)
	state.reset()
	_check(state.units_by_id.is_empty() and state.squads_by_id.is_empty(), "reset retained runtime records")
	_check(state.next_unit_serial == 1 and state.next_squad_serial == 1, "reset retained ID counters")
	var result := state.rollout_unit(
		&"nova_scout", &"nova_republic", &"nova_capital", _registry, _regions
	)
	_check(result.unit.instance_id == &"unit_00000001", "reset did not restore deterministic unit IDs")
	_check(result.squad.squad_id == &"squad_00000001", "reset did not restore deterministic squad IDs")


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


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
