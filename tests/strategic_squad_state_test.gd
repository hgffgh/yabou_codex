extends SceneTree

var failures := PackedStringArray()
var registry := MasterDataRegistry.new()
var regions := {&"nova_capital": true, &"nova_shipyard": true, &"crimson_capital": true}


func _initialize() -> void:
	registry.load_all()
	_test_movement_lifecycle()
	_test_split_and_merge()
	if failures.is_empty():
		print("strategic_squad_state_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("strategic_squad_state_test: %s" % failure)
		quit(1)


func _test_movement_lifecycle() -> void:
	var state := CampaignRuntimeState.new()
	var rollout := state.rollout_unit(&"nova_scout", &"nova_republic", &"nova_capital", registry, regions)
	var squad := rollout.squad as SquadState
	var unit := rollout.unit as UnitInstanceState
	var adjacent: Array[StringName] = [&"nova_shipyard"]
	var errors := state.plan_squad_movement(squad.squad_id, &"nova_shipyard", &"nova_republic", adjacent)
	_check(errors.is_empty(), "valid adjacent movement was rejected: %s" % errors)
	_check(squad.region_id == &"nova_capital", "planning moved the squad before movement phase")
	_check(squad.move_origin_region_id == &"nova_capital" and squad.planned_destination_region_id == &"nova_shipyard", "planning fields were not recorded")
	_check(squad.movement_used and unit.movement_used, "movement use was not recorded on squad and unit")
	_check(not state.plan_squad_movement(squad.squad_id, &"nova_shipyard", &"nova_republic", adjacent).is_empty(), "second movement was accepted")
	state.execute_planned_squad_movements()
	_check(squad.region_id == &"nova_shipyard" and squad.planned_destination_region_id.is_empty(), "movement phase did not apply the plan")
	state.reset_movement_for_faction(&"nova_republic")
	_check(not squad.movement_used and not unit.movement_used and squad.move_origin_region_id.is_empty(), "turn reset did not clear movement state")


func _test_split_and_merge() -> void:
	var state := CampaignRuntimeState.new()
	var first := state.rollout_unit(&"nova_scout", &"nova_republic", &"nova_capital", registry, regions)
	var second := state.rollout_unit(&"nova_vanguard", &"nova_republic", &"nova_capital", registry, regions)
	var merge_errors := state.merge_squads(first.squad.squad_id, second.squad.squad_id)
	_check(merge_errors.is_empty(), "valid merge failed: %s" % merge_errors)
	_check(state.squads_by_id.size() == 1 and first.squad.unit_instance_ids.size() == 2, "merge did not produce one two-unit squad")
	_check(second.unit.squad_id == first.squad.squad_id and second.unit.slot_index == 1, "merge did not update unit back-reference")
	first.squad.movement_used = true
	first.unit.movement_used = true
	var selected: Array[StringName] = [second.unit.instance_id]
	var split := state.split_squad(first.squad.squad_id, selected, "Detached")
	_check(split.errors.is_empty(), "valid split failed: %s" % split.errors)
	var detached := split.squad as SquadState
	_check(detached != null and detached.movement_used, "split allowed movement state to reset")
	_check(second.unit.squad_id == detached.squad_id and second.unit.slot_index == 0, "split did not update unit back-reference")
	var slot_errors := state.move_unit_to_slot(detached.squad_id, second.unit.instance_id, 4)
	_check(slot_errors.is_empty() and detached.get_unit_at_slot(4) == second.unit.instance_id, "unit could not move to an empty rear slot")
	_check(second.unit.slot_index == 4, "slot move did not update unit back-reference")
	merge_errors = state.merge_squads(first.squad.squad_id, detached.squad_id)
	_check(merge_errors.is_empty(), "merge from a holey source failed: %s" % merge_errors)
	_check(second.unit.slot_index == 1 and first.squad.get_unit_at_slot(1) == second.unit.instance_id, "merge did not choose the first actual empty slot")
	_check(state.validate(registry, regions).is_empty(), "split/merge graph failed validation: %s" % state.validate(registry, regions))


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
