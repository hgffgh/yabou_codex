extends SceneTree

var failures := PackedStringArray()
var game_state: Node


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	if game_state == null:
		push_error("battle_squad_movement_ai_test: GameState autoload is unavailable")
		quit(1)
		return

	_test_headless_battle_moves_squads_without_a_view()
	_test_offensive_squad_targets_nearest_enemy()
	_test_defensive_squad_holds_near_own_hq()
	_test_player_squad_destination_is_never_ai_overridden()
	_test_retreat_policy_auto_triggers_at_low_hp()
	_test_movement_ai_disabled_opts_a_squad_out()
	_finish()


## Before this milestone, destination-seeking movement lived only in
## BattlePrototypeView's _process, so a battle built and advanced with no
## view attached (exactly what auto-resolved AI-vs-AI battles do) never
## moved a single squad. This proves movement now happens purely through
## BattleRuntimeState.advance_time.
func _test_headless_battle_moves_squads_without_a_view() -> void:
	var battle := _build_battle(Vector3(-400, 0, 0), Vector3(400, 0, 0))
	if battle == null:
		return
	var attacker_squad := _only_squad(battle, battle.attacker_squad_ids)
	var defender_squad := _only_squad(battle, battle.defender_squad_ids)
	var start_distance := Vector2(attacker_squad.world_position.x, attacker_squad.world_position.y).distance_to(
		Vector2(defender_squad.world_position.x, defender_squad.world_position.y))

	for _tick in range(10):
		battle.advance_time(1.0)

	var end_distance := Vector2(attacker_squad.world_position.x, attacker_squad.world_position.y).distance_to(
		Vector2(defender_squad.world_position.x, defender_squad.world_position.y))
	_check(end_distance < start_distance,
		"squads should have closed distance over 10 headless seconds (start=%.1f end=%.1f)" % [start_distance, end_distance])


func _test_offensive_squad_targets_nearest_enemy() -> void:
	var battle := _build_battle(Vector3(-400, 0, 0), Vector3(400, 0, 0))
	if battle == null:
		return
	var defender_squad := _only_squad(battle, battle.defender_squad_ids)
	var attacker_squad := _only_squad(battle, battle.attacker_squad_ids)
	defender_squad.policy = GameEnums.BattlePolicy.OFFENSIVE
	battle._advance_ai_squad_orders()
	_check(defender_squad.destination == attacker_squad.world_position,
		"an OFFENSIVE non-player squad should target the nearest living enemy squad")


func _test_defensive_squad_holds_near_own_hq() -> void:
	var battle := _build_battle(Vector3(-400, 0, 0), Vector3(400, 0, 0))
	if battle == null:
		return
	var defender_squad := _only_squad(battle, battle.defender_squad_ids)
	defender_squad.policy = GameEnums.BattlePolicy.DEFENSIVE
	battle._advance_ai_squad_orders()
	var defender_hq := battle.control_point_defs_by_id[battle.defender_hq_id] as BattleControlPointDef
	_check(defender_squad.destination == defender_hq.position,
		"a DEFENSIVE non-player squad should hold near its own HQ instead of charging the enemy")


func _test_player_squad_destination_is_never_ai_overridden() -> void:
	var battle := _build_battle(Vector3(-400, 0, 0), Vector3(400, 0, 0))
	if battle == null:
		return
	var attacker_squad := _only_squad(battle, battle.attacker_squad_ids)
	_check(battle.player_faction_id == &"nova_republic", "battle should have snapshotted the player faction")
	attacker_squad.policy = GameEnums.BattlePolicy.OFFENSIVE
	var manual_destination := Vector3(12, 34, 0)
	attacker_squad.destination = manual_destination
	battle._advance_ai_squad_orders()
	_check(attacker_squad.destination == manual_destination,
		"the player's own squad destination must never be overwritten by AI orders")


func _test_retreat_policy_auto_triggers_at_low_hp() -> void:
	var battle := _build_battle(Vector3(-400, 0, 0), Vector3(400, 0, 0))
	if battle == null:
		return
	var defender_squad := _only_squad(battle, battle.defender_squad_ids)
	defender_squad.policy = GameEnums.BattlePolicy.RETREAT
	var unit := battle.unit_states_by_id[defender_squad.unit_instance_ids[0]] as BattleUnitState
	_check(not defender_squad.retreat_requested, "setup should not have already requested retreat")

	unit.current_hp = int(round(float(unit.max_hp) * 0.5))
	battle._advance_ai_squad_orders()
	_check(not defender_squad.retreat_requested,
		"a RETREAT-policy squad above the 30%% HP threshold should not auto-retreat yet")

	unit.current_hp = int(round(float(unit.max_hp) * 0.3))
	battle._advance_ai_squad_orders()
	_check(defender_squad.retreat_requested,
		"a RETREAT-policy squad at or below 30%% HP should auto-request retreat without a manual call")


func _test_movement_ai_disabled_opts_a_squad_out() -> void:
	var battle := _build_battle(Vector3(-400, 0, 0), Vector3(400, 0, 0))
	if battle == null:
		return
	var defender_squad := _only_squad(battle, battle.defender_squad_ids)
	defender_squad.policy = GameEnums.BattlePolicy.OFFENSIVE
	defender_squad.movement_ai_disabled = true
	var original_destination := defender_squad.destination
	battle._advance_ai_squad_orders()
	_check(defender_squad.destination == original_destination,
		"movement_ai_disabled should prevent AI from assigning a new destination")


func _build_battle(attacker_spawn: Vector3, defender_spawn: Vector3) -> BattleRuntimeState:
	game_state.start_new_game(&"nova_republic")
	var attacker: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"crimson_border")
	var defender: Dictionary = game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", &"crimson_border")
	attacker.squad.move_origin_region_id = &"nova_border"
	var pending := {
		"type": "squad_battle_pending", "region_id": &"crimson_border",
		"attacker_id": &"nova_republic", "defender_id": &"crimson_empire",
		"attacker_squad_ids": [attacker.squad.squad_id], "defender_squad_ids": [defender.squad.squad_id],
	}
	var battle_map := game_state.master_data.battle_maps[&"standard_battle_map"] as BattleMapDef
	var created: Dictionary = BattleRuntimeFactory.new().create_from_pending(
		pending, game_state.campaign_runtime, &"movement_ai_test", 1, attacker_spawn, defender_spawn, battle_map,
	)
	_check(created.errors.is_empty(), "battle creation failed: %s" % created.errors)
	return created.state as BattleRuntimeState


func _only_squad(battle: BattleRuntimeState, squad_ids: Array[StringName]) -> BattleSquadState:
	return battle.squad_states_by_id[squad_ids[0]] as BattleSquadState


func _finish() -> void:
	if failures.is_empty():
		print("battle_squad_movement_ai_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("battle_squad_movement_ai_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
