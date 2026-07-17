extends SceneTree

var failures := PackedStringArray()
var game_state: Node

func _initialize() -> void:
	await process_frame
	game_state = root.get_node("GameState")
	game_state.start_new_game(&"nova_republic")
	var attacker: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"crimson_border")
	var defender: Dictionary = game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", &"crimson_border")
	attacker.squad.move_origin_region_id = &"nova_border"
	var pending := {"type":"squad_battle_pending", "region_id":&"crimson_border", "attacker_id":&"nova_republic", "defender_id":&"crimson_empire", "attacker_squad_ids":[attacker.squad.squad_id], "defender_squad_ids":[defender.squad.squad_id]}
	var map_def := game_state.master_data.battle_maps[&"standard_battle_map"] as BattleMapDef
	var created: Dictionary = BattleRuntimeFactory.new().create_from_pending(pending, game_state.campaign_runtime, &"capture_test", 99, Vector3.ZERO, Vector3.ZERO, map_def)
	_check(created.errors.is_empty(), "battle map factory failed: %s" % created.errors)
	var battle := created.state as BattleRuntimeState
	_check(battle.control_point_states.size() == 3, "battle map did not create both HQs and relay")
	var attacker_state := battle.squad_states_by_id[attacker.squad.squad_id] as BattleSquadState
	var defender_state := battle.squad_states_by_id[defender.squad.squad_id] as BattleSquadState
	attacker_state.world_position = Vector3(500, 0, 0)
	defender_state.world_position = Vector3(300, 300, 0)
	battle.time_scale = 0.0
	battle.advance_time(10.0)
	var defender_hq := battle.control_point_states[battle.defender_hq_id] as BattleControlPointState
	_check(defender_hq.capture_progress == 0.0, "capture advanced while paused")
	battle.time_scale = 1.0
	battle.advance_time(99.9)
	_check(battle.result == null and defender_hq.capture_progress > 99.0, "HQ capture timing was incorrect before completion")
	battle.advance_time(0.1)
	_check(battle.result != null and battle.result.reason == &"hq_capture" and battle.result.winner_faction_id == &"nova_republic", "HQ capture did not finalize attacker victory")
	var errors: PackedStringArray = game_state.apply_battle_result(battle)
	_check(errors.is_empty() and game_state.get_region(&"crimson_border").owner_faction_id == &"nova_republic", "HQ result did not transfer strategic ownership")
	_check(not game_state.apply_battle_result(battle).is_empty(), "battle result was applied twice")
	if failures.is_empty(): print("battle_capture_system_test: all checks passed"); quit(0)
	else:
		for failure: String in failures: push_error("battle_capture_system_test: %s" % failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
