extends SceneTree

var failures := PackedStringArray()
var game_state: Node
var turn_manager: Node


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	turn_manager = root.get_node_or_null("TurnManager")
	if game_state == null or turn_manager == null:
		push_error("battle_result_application_test: required autoload is unavailable")
		quit(1)
		return

	_test_recovered_captured_lost_outcomes()
	await _test_turn_manager_applies_diplomacy_penalty()
	_finish()


## A destroyed unit's fate depends on which side it belonged to: the
## winner's own losses are "recovered" (kept, unassigned, HP 0), the loser's
## losses are captured at a deterministic ~10% rate and otherwise lost
## outright (deleted). Ten loser losses guarantees exactly one capture,
## since GameConstants.CAPTURE_ENEMY_UNIT_PCT == 0.10.
func _test_recovered_captured_lost_outcomes() -> void:
	game_state.start_new_game(&"nova_republic")
	var survivor: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"crimson_border")
	var doomed_attacker: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"crimson_border")
	var defender_squad_ids: Array[StringName] = []
	var defender_unit_ids: Array[StringName] = []
	for i in range(10):
		var rollout: Dictionary = game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", &"crimson_border")
		defender_squad_ids.append(rollout.squad.squad_id)
		defender_unit_ids.append(rollout.unit.instance_id)
	survivor.squad.move_origin_region_id = &"nova_border"
	doomed_attacker.squad.move_origin_region_id = &"nova_border"

	var pending := {
		"type": "squad_battle_pending", "region_id": &"crimson_border",
		"attacker_id": &"nova_republic", "defender_id": &"crimson_empire",
		"attacker_squad_ids": [survivor.squad.squad_id, doomed_attacker.squad.squad_id],
		"defender_squad_ids": defender_squad_ids,
	}
	var created: Dictionary = BattleRuntimeFactory.new().create_from_pending(
		pending, game_state.campaign_runtime, &"outcome_test", 1, Vector3.ZERO, Vector3.ONE,
	)
	_check(created.errors.is_empty(), "battle creation failed: %s" % created.errors)
	var battle := created.state as BattleRuntimeState
	if battle == null:
		return

	(battle.unit_states_by_id[doomed_attacker.unit.instance_id] as BattleUnitState).current_hp = 0
	for unit_id: StringName in defender_unit_ids:
		(battle.unit_states_by_id[unit_id] as BattleUnitState).current_hp = 0
	var finalize_errors := battle.finalize(&"nova_republic", &"crimson_empire", &"annihilation")
	_check(finalize_errors.is_empty(), "finalize failed: %s" % finalize_errors)
	_check(battle.result.destroyed_unit_ids.size() == 11,
		"expected 11 destroyed units, got %d" % battle.result.destroyed_unit_ids.size())

	var apply_errors: PackedStringArray = game_state.apply_battle_result(battle)
	_check(apply_errors.is_empty(), "apply_battle_result failed: %s" % apply_errors)

	_check(battle.result.recovered_unit_ids == [doomed_attacker.unit.instance_id],
		"recovered_unit_ids did not list exactly the winner's destroyed unit")
	var recovered_unit: UnitInstanceState = game_state.campaign_runtime.get_unit(doomed_attacker.unit.instance_id)
	_check(recovered_unit != null, "recovered unit record was deleted instead of kept")
	if recovered_unit != null:
		_check(recovered_unit.condition == GameEnums.UnitCondition.DESTROYED_RECOVERED,
			"recovered unit condition was not DESTROYED_RECOVERED")
		_check(recovered_unit.current_hp == 0, "recovered unit did not have current_hp == 0")
		_check(recovered_unit.squad_id.is_empty() and recovered_unit.slot_index == -1,
			"recovered unit was not unassigned from its squad")
	_check(game_state.campaign_runtime.get_squad(doomed_attacker.squad.squad_id) == null,
		"attacker squad with zero remaining units was not deleted")
	_check(game_state.campaign_runtime.get_squad(survivor.squad.squad_id) != null,
		"surviving attacker squad was deleted")

	_check(battle.result.captured_unit_ids.size() == 1,
		"expected exactly one captured unit out of ten losses, got %d" % battle.result.captured_unit_ids.size())
	_check(battle.result.lost_unit_ids.size() == 9,
		"expected exactly nine lost units, got %d" % battle.result.lost_unit_ids.size())
	if battle.result.captured_unit_ids.size() == 1:
		var captured_id: StringName = battle.result.captured_unit_ids[0]
		var captured_unit: UnitInstanceState = game_state.campaign_runtime.get_unit(captured_id)
		_check(captured_unit != null, "captured unit record was deleted")
		if captured_unit != null:
			_check(captured_unit.owner_faction_id == &"nova_republic", "captured unit did not change owner")
			_check(captured_unit.captured, "captured unit did not set captured == true")
			_check(captured_unit.pilot_id.is_empty(), "captured unit kept its original pilot")
			_check(captured_unit.condition == GameEnums.UnitCondition.ACTIVE, "captured unit was not returned to ACTIVE")
			_check(captured_unit.current_hp == 1, "captured unit did not start at 1 HP")
			var captured_squad: SquadState = game_state.campaign_runtime.get_squad(captured_unit.squad_id)
			_check(
				captured_squad != null and captured_squad.owner_faction_id == &"nova_republic" and captured_squad.region_id == &"crimson_border",
				"captured unit was not placed into a new winner-owned squad in the battle region",
			)
	for unit_id: StringName in battle.result.lost_unit_ids:
		_check(game_state.campaign_runtime.get_unit(unit_id) == null, "lost unit '%s' was not fully removed" % unit_id)

	var validation_errors: PackedStringArray = game_state.campaign_runtime.validate(game_state.master_data, game_state.region_defs)
	_check(validation_errors.is_empty(), "campaign state failed validation after battle outcomes: %s" % validation_errors)


## Drives a real squad_battle_pending contact through TurnManager end to end
## (auto-resolving every battle it emits as a decisive attacker win, so the
## turn cascade can never hang regardless of what the AI does afterward) and
## confirms Diplomacy.apply_combat_events actually receives a "battle" log
## entry now that the vignette-only wiring is gone.
func _test_turn_manager_applies_diplomacy_penalty() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var attacker: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"crimson_border")
	game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", &"crimson_border")
	attacker.squad.move_origin_region_id = &"nova_border"

	var relation_before: float = _relation(&"nova_republic", &"crimson_empire")
	# CONNECT_DEFERRED: _resolve_squad_battle emits battle_runtime_ready and
	# then immediately awaits battle_runtime_finished. A same-stack (direct)
	# callback would call complete_battle_runtime before that await has
	# actually registered its listener, permanently losing the completion
	# signal. Deferring to the next idle frame guarantees the await is live.
	turn_manager.battle_runtime_ready.connect(_auto_resolve_battle, CONNECT_DEFERRED)
	turn_manager.commit_turn()
	for frame in range(180):
		if game_state.turn_number == 2 and turn_manager.current_phase == turn_manager.Phase.ORDERS:
			break
		await process_frame
	turn_manager.battle_runtime_ready.disconnect(_auto_resolve_battle)

	_check(game_state.turn_number == 2, "faction turn cycle did not complete after the battle resolved")
	var relation_after: float = _relation(&"nova_republic", &"crimson_empire")
	_check(relation_after < relation_before,
		"diplomacy attack penalty was not applied after the battle resolved (before=%s after=%s)" % [relation_before, relation_after])


## Reads Faction.relations directly instead of calling the Diplomacy utility
## class by name, since --script test entry points can hit a compile-order
## issue where a directly-referenced static-only class fails to resolve the
## GameState autoload identifier.
func _relation(faction_id: StringName, other_id: StringName) -> float:
	var faction: Faction = game_state.get_faction(faction_id)
	return faction.relations.get(other_id, 0.0) if faction != null else 0.0


## Forces the attacker side to win by destroying every defender unit, so any
## battle_runtime_ready emitted during the test resolves immediately without
## needing real combat simulation.
func _auto_resolve_battle(battle: BattleRuntimeState) -> void:
	for squad_id: StringName in battle.defender_squad_ids:
		var squad := battle.squad_states_by_id[squad_id] as BattleSquadState
		if squad == null:
			continue
		for unit_id: StringName in squad.unit_instance_ids:
			(battle.unit_states_by_id[unit_id] as BattleUnitState).current_hp = 0
	battle.finalize(battle.attacker_faction_id, battle.defender_faction_id, &"annihilation")
	turn_manager.complete_battle_runtime(battle)


func _finish() -> void:
	if failures.is_empty():
		print("battle_result_application_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("battle_result_application_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
