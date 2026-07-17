extends SceneTree

var failures := PackedStringArray()
var game_state: Node
var turn_manager: Node


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	turn_manager = root.get_node_or_null("TurnManager")
	if game_state == null or turn_manager == null:
		push_error("ai_battle_auto_resolve_test: required autoload is unavailable")
		quit(1)
		return

	_test_battle_involves_player()
	_test_auto_resolve_completes_a_non_player_battle_synchronously()
	await _test_commit_turn_resolves_non_player_contact_without_ui()
	_finish()


func _test_battle_involves_player() -> void:
	game_state.start_new_game(&"nova_republic")
	var battle := BattleRuntimeState.new()
	battle.attacker_faction_id = &"nova_republic"
	battle.defender_faction_id = &"crimson_empire"
	_check(turn_manager._battle_involves_player(battle),
		"a battle with the player as attacker should be reported as player-involved")
	battle.attacker_faction_id = &"crimson_empire"
	battle.defender_faction_id = &"nova_republic"
	_check(turn_manager._battle_involves_player(battle),
		"a battle with the player as defender should be reported as player-involved")
	battle.attacker_faction_id = &"crimson_empire"
	battle.defender_faction_id = &"pirate_faction"
	_check(not turn_manager._battle_involves_player(battle),
		"a battle between two non-player factions should not be reported as player-involved")


## A battle between two non-player factions must resolve to completion
## through _auto_resolve_battle's synchronous simulation loop alone --
## nothing here ever connects to battle_runtime_ready or calls
## complete_battle_runtime manually, unlike every other battle test.
func _test_auto_resolve_completes_a_non_player_battle_synchronously() -> void:
	game_state.start_new_game(&"nova_republic")
	var attacker: Dictionary = game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", &"crimson_border")
	var defender: Dictionary = _insert_fake_faction_squad(&"pirate_faction", &"squad_pirate_ai_test", &"unit_pirate_ai_test", &"crimson_border")
	attacker.squad.move_origin_region_id = &"nova_border"
	var pending := {
		"type": "squad_battle_pending", "region_id": &"crimson_border",
		"attacker_id": &"crimson_empire", "defender_id": &"pirate_faction",
		"attacker_squad_ids": [attacker.squad.squad_id], "defender_squad_ids": [defender.squad.squad_id],
	}
	var battle_map := game_state.master_data.battle_maps[&"standard_battle_map"] as BattleMapDef
	var created: Dictionary = BattleRuntimeFactory.new().create_from_pending(
		pending, game_state.campaign_runtime, &"auto_resolve_unit_test", 1, Vector3.ZERO, Vector3.ONE, battle_map,
	)
	_check(created.errors.is_empty(), "battle creation failed: %s" % created.errors)
	var battle := created.state as BattleRuntimeState
	if battle == null:
		return
	_check(not turn_manager._battle_involves_player(battle), "setup should have produced a non-player battle")

	turn_manager._auto_resolve_battle(battle)

	_check(battle.result != null, "auto-resolve should have finalized the battle within the world-time cap")
	_check(battle.applied_to_campaign, "auto-resolve should have applied the result back to the campaign")
	_check(not turn_manager.pending_battle_states.has(battle), "the completed battle should be removed from pending_battle_states")


## Drives a real commit_turn() where the only active-turn faction
## (crimson_empire) fights a synthetic third faction it just invaded --
## since neither side is the player, this must resolve on its own. No
## battle_runtime_ready handler is connected at all; if the old
## always-await-the-UI behavior regressed, this would hang until the test
## harness's own timeout instead of turn_number ever advancing.
func _test_commit_turn_resolves_non_player_contact_without_ui() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var crimson_attacker: Dictionary = game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", &"crimson_border")
	_insert_fake_faction_squad(&"pirate_faction", &"squad_pirate_commit_test", &"unit_pirate_commit_test", &"crimson_border")
	crimson_attacker.squad.owner_faction_id = &"crimson_empire"

	# Simulate crimson_empire having just moved into crimson_border on its
	# own turn, the same shape detect_squad_conflicts requires of a real
	# attacker, without needing the full AI order pipeline to produce it.
	crimson_attacker.squad.move_origin_region_id = &"crimson_capital"

	turn_manager.commit_turn()
	for frame in range(180):
		if game_state.turn_number == 2 and turn_manager.current_phase == turn_manager.Phase.ORDERS:
			break
		await process_frame

	_check(game_state.turn_number == 2,
		"the faction turn cycle should complete even though crimson_empire fought a non-player faction mid-turn")
	_check(game_state.get_region(&"crimson_border").owner_faction_id == &"crimson_empire",
		"crimson_empire should have taken crimson_border from the annihilated pirate_faction squad")


func _insert_fake_faction_squad(faction_id: StringName, squad_id: StringName, unit_id: StringName, region_id: StringName) -> Dictionary:
	var unit := UnitInstanceState.new()
	unit.instance_id = unit_id
	unit.unit_def_id = &"nova_scout"
	unit.owner_faction_id = faction_id
	unit.origin_faction_id = faction_id
	unit.current_hp = 1
	unit.current_en = 1
	unit.squad_id = squad_id
	unit.slot_index = 0

	var squad := SquadState.new()
	squad.squad_id = squad_id
	squad.owner_faction_id = faction_id
	squad.region_id = region_id
	squad.assign_unit(unit_id, 0)

	game_state.campaign_runtime.units_by_id[unit_id] = unit
	game_state.campaign_runtime.squads_by_id[squad_id] = squad
	return {"unit": unit, "squad": squad}


func _finish() -> void:
	if failures.is_empty():
		print("ai_battle_auto_resolve_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("ai_battle_auto_resolve_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
