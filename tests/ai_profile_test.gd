extends SceneTree
## DATA_DEFINITION.md section 5's DifficultyDef.ai_profile_id, now wired
## into AiController via AiProfileDef (res://data/ai_profiles/). Calls
## turn_manager.call("_run_ai_orders") rather than the bare AiController
## identifier -- see HANDOFF.md's compile-order-bug note (ai_controller.gd
## bare-references GameState/TurnManager internally, same as
## ai_squad_movement_test.gd already established).

var failures := PackedStringArray()
var game_state: Node
var turn_manager: Node


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	turn_manager = root.get_node_or_null("TurnManager")
	if game_state == null or turn_manager == null:
		push_error("ai_profile_test: required autoload is unavailable")
		quit(1)
		return

	_test_ai_profiles_load_expected_presets()
	_test_production_queue_length_respects_profile()
	_test_research_reserve_respects_profile()
	_test_aggression_multiplier_lets_ai_attack_at_a_lower_power_ratio()
	_finish()


func _test_ai_profiles_load_expected_presets() -> void:
	_check(game_state.master_data_errors.is_empty(), "ai_profile data failed master-data validation: %s" % game_state.master_data_errors)
	_check(game_state.master_data.ai_profiles.size() == 3, "expected exactly 3 ai_profile presets (ai_easy/ai_normal/ai_hard)")
	var hard: AiProfileDef = game_state.master_data.ai_profiles.get(&"ai_hard")
	var easy: AiProfileDef = game_state.master_data.ai_profiles.get(&"ai_easy")
	_check(hard != null and easy != null, "setup: ai_hard and ai_easy should both resolve")
	_check(hard.aggression_multiplier > 1.0, "ai_hard should be more aggressive than baseline")
	_check(easy.aggression_multiplier < 1.0, "ai_easy should be less aggressive than baseline")
	_check(hard.production_queue_length > easy.production_queue_length, "ai_hard should queue deeper than ai_easy")
	_check(hard.research_reserve < easy.research_reserve, "ai_hard should research more eagerly (lower reserve) than ai_easy")


func _test_production_queue_length_respects_profile() -> void:
	var normal_length := _measure_production_queue_length(&"normal")
	var hard_length := _measure_production_queue_length(&"hard")
	var normal_profile: AiProfileDef = game_state.master_data.ai_profiles.get(&"ai_normal")
	var hard_profile: AiProfileDef = game_state.master_data.ai_profiles.get(&"ai_hard")
	_check(normal_length == normal_profile.production_queue_length, "normal-difficulty AI should cap its production queue at ai_normal.production_queue_length (%d), got %d" % [normal_profile.production_queue_length, normal_length])
	_check(hard_length == hard_profile.production_queue_length, "hard-difficulty AI should cap its production queue at ai_hard.production_queue_length (%d), got %d" % [hard_profile.production_queue_length, hard_length])
	_check(hard_length > normal_length, "hard difficulty should let the AI queue more production than normal")


func _measure_production_queue_length(difficulty_id: StringName) -> int:
	turn_manager.start_new_game(&"nova_republic", difficulty_id)
	var crimson: Faction = game_state.get_faction(&"crimson_empire")
	crimson.funds = 1000000
	crimson.materials = 1000000
	var facility_ids: Array[StringName] = game_state.production_facility_ids_for_region(&"crimson_shipyard")
	_check(not facility_ids.is_empty(), "setup: crimson_shipyard should have a production facility")
	if facility_ids.is_empty():
		return -1
	var facility_id: StringName = facility_ids[0]
	for _i in range(8):  # comfortably more than any profile's queue length
		turn_manager.call("_run_ai_orders")
	var queue := game_state.campaign_runtime.production_queues_by_facility_id.get(facility_id) as ProductionQueueState
	return queue.job_ids.size() if queue != null else 0


func _test_research_reserve_respects_profile() -> void:
	_check(not _research_started_with_reserve_gap(&"normal", 200), "normal-difficulty AI (reserve 300) should not start research when only 200 funds would be left over")
	_check(_research_started_with_reserve_gap(&"hard", 200), "hard-difficulty AI (reserve 150) should start research when 200 funds would be left over")


## Sets crimson_empire's funds to exactly cost + leftover_gap and returns
## whether _run_ai_orders started research on a synthetic, always-available
## tier-1 node.
func _research_started_with_reserve_gap(difficulty_id: StringName, leftover_gap: int) -> bool:
	turn_manager.start_new_game(&"nova_republic", difficulty_id)
	var crimson: Faction = game_state.get_faction(&"crimson_empire")
	var node := GeneratedTechNodeState.new()
	node.node_id = &"t1"
	node.tech_id = &"reinforced_plating"
	node.tier = 1
	crimson.generated_tech_nodes = {node.node_id: node}
	var cost: int = game_state.campaign_config.research_costs[0]
	crimson.funds = cost + leftover_gap
	turn_manager.call("_run_ai_orders")
	return crimson.current_research != null


## crimson_border's only neighbor outside its own territory is nova_border
## (see HANDOFF.md's region graph). crimson_empire's single seeded
## crimson_bastion squad has power 320+560=880 (firepower+armor); giving
## nova_republic two nova_vanguard units (260+180=440 each) at nova_border
## makes the defender's power exactly 880 too, landing it precisely in the
## gray zone between the two difficulties' required ratios (with relation
## zeroed out below, since _best_squad_destination's required_ratio also
## factors in friendship, which isn't this test's concern):
## FactionDef.ai_aggression=0.65 gives a required_ratio of 1.3825 at normal
## (attacks only at defender power <= 880/1.3825 =~ 636), which ai_hard's
## 1.4x aggression_multiplier divides down to 0.9875 -- but
## _best_squad_destination floors required_ratio at 1.0 (never attack below
## parity), so ai_hard's effective ratio is exactly 1.0 (attacks at defender
## power <= 880/1.0 = 880) -- 880 clears the hard threshold (as an exact
## parity match) but not the normal one.
func _test_aggression_multiplier_lets_ai_attack_at_a_lower_power_ratio() -> void:
	_check(not _crimson_attacks_nova_border(&"normal"), "normal-difficulty AI should not attack a defender at parity power")
	_check(_crimson_attacks_nova_border(&"hard"), "hard-difficulty AI's higher aggression_multiplier should attack that same parity-power defender")


func _crimson_attacks_nova_border(difficulty_id: StringName) -> bool:
	turn_manager.start_new_game(&"nova_republic", difficulty_id)
	var crimson_squad: SquadState = null
	for squad: SquadState in game_state.campaign_runtime.squads_by_id.values():
		if squad.owner_faction_id == &"crimson_empire":
			crimson_squad = squad
			break
	var nova_squad: SquadState = null
	for squad: SquadState in game_state.campaign_runtime.squads_by_id.values():
		if squad.owner_faction_id == &"nova_republic" and squad.unit_instance_ids.size() > 0:
			var first_unit: UnitInstanceState = game_state.campaign_runtime.get_unit(squad.unit_instance_ids[0])
			if first_unit != null and first_unit.unit_def_id == &"nova_vanguard":
				nova_squad = squad
				break
	_check(crimson_squad != null and nova_squad != null, "setup: both factions should have their expected seeded squad")
	if crimson_squad == null or nova_squad == null:
		return false

	var extra: Dictionary = game_state.rollout_new_unit(&"nova_vanguard", &"nova_republic", &"nova_capital")
	_check((extra.errors as PackedStringArray).is_empty(), "setup: rolling out a second nova_vanguard should succeed: %s" % [extra.errors])
	var extra_squad_id: StringName = (extra.squad as SquadState).squad_id
	var merge_errors: PackedStringArray = game_state.campaign_runtime.merge_squads(nova_squad.squad_id, extra_squad_id)
	_check(merge_errors.is_empty(), "setup: merging the extra nova_vanguard into the defending squad should succeed: %s" % [merge_errors])

	crimson_squad.region_id = &"crimson_border"
	nova_squad.region_id = &"nova_border"
	# _best_squad_destination's required_ratio also factors in relation
	# (required_ratio -= friendship/200), which the module-level doc comment
	# above deliberately ignores to keep the arithmetic simple -- zero it out
	# so the gray-zone math there holds exactly (INITIAL_FRIENDSHIP starts
	# well below 0, which would otherwise raise the effective required_ratio
	# for both difficulties).
	game_state.campaign_runtime.get_relation_state(&"crimson_empire", &"nova_republic").friendship = 0
	turn_manager.call("_run_ai_orders")
	return crimson_squad.planned_destination_region_id == &"nova_border"


func _finish() -> void:
	if failures.is_empty():
		print("ai_profile_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("ai_profile_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
