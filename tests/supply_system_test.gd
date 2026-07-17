extends SceneTree

const GAME_STATE_SCRIPT := preload("res://autoload/game_state.gd")
var failures := PackedStringArray()
var state: Node

func _initialize() -> void:
	state = GAME_STATE_SCRIPT.new()
	state._load_static_data()
	state.start_new_game(&"nova_republic")
	_test_network_and_en()
	_test_repair_pause_and_completion()
	state.free()
	if failures.is_empty():
		print("supply_system_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures: push_error("supply_system_test: %s" % failure)
		quit(1)

func _test_network_and_en() -> void:
	_check(state.is_region_supplied(&"nova_capital", &"nova_republic"), "capital was not supplied")
	_check(state.is_region_supplied(&"nova_border", &"nova_republic"), "owned border was not connected through either route")
	state.get_region(&"nova_shipyard").owner_faction_id = &"crimson_empire"
	state.get_region(&"nova_outpost").owner_faction_id = &""
	state.recompute_all_supply_networks()
	_check(not state.is_region_supplied(&"nova_border", &"nova_republic"), "enemy and neutral regions did not isolate border")
	var rollout: Dictionary = state.rollout_new_unit(&"nova_scout", &"nova_republic", &"nova_border")
	rollout.unit.current_en = 1
	var errors: PackedStringArray = state.resupply_unit_en(rollout.unit.instance_id, &"nova_republic")
	_check(not errors.is_empty() and rollout.unit.current_en == 1, "isolated unit replenished EN")
	state.get_region(&"nova_outpost").owner_faction_id = &"nova_republic"
	state.recompute_all_supply_networks()
	var funds_before: int = state.get_faction(&"nova_republic").funds
	var materials_before: int = state.get_faction(&"nova_republic").materials
	errors = state.resupply_unit_en(rollout.unit.instance_id, &"nova_republic")
	var scout_def := state.master_data.units[&"nova_scout"] as UnitDef
	_check(errors.is_empty() and rollout.unit.current_en == scout_def.max_en, "connected unit did not replenish to max EN")
	_check(state.get_faction(&"nova_republic").funds == funds_before and state.get_faction(&"nova_republic").materials == materials_before, "EN replenishment consumed resources")

func _test_repair_pause_and_completion() -> void:
	var rollout: Dictionary = state.rollout_new_unit(&"nova_vanguard", &"nova_republic", &"nova_border")
	rollout.unit.current_hp = 1100
	var faction := state.get_faction(&"nova_republic") as Faction
	var funds_before := faction.funds
	var result: Dictionary = state.start_unit_repair(rollout.unit.instance_id, &"nova_republic")
	_check(result.errors.is_empty(), "valid repair start failed: %s" % result.errors)
	_check(rollout.unit.condition == GameEnums.UnitCondition.REPAIRING and faction.funds < funds_before, "repair did not prepay and enter repairing state")
	var remaining: int = rollout.unit.repair_turns_remaining
	state.get_region(&"nova_outpost").owner_faction_id = &"crimson_empire"
	state.recompute_all_supply_networks()
	state.advance_repairs_for_faction(&"nova_republic")
	_check(rollout.unit.repair_turns_remaining == remaining, "isolated repair did not pause")
	state.get_region(&"nova_outpost").owner_faction_id = &"nova_republic"
	state.recompute_all_supply_networks()
	for _index in range(remaining): state.advance_repairs_for_faction(&"nova_republic")
	_check(rollout.unit.condition == GameEnums.UnitCondition.ACTIVE and rollout.unit.current_hp == 2200, "reconnected repair did not complete at max HP")

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
