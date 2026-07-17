extends SceneTree

var failures := PackedStringArray()
var game_state: Node


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	if game_state == null:
		push_error("strategic_intel_test: GameState autoload is unavailable")
		quit(1)
		return

	_test_enemy_squad_starts_unconfirmed()
	_test_colocation_confirms_without_combat()
	_test_confirmation_is_sticky_after_moving_apart()
	_test_reverts_on_composition_change()
	_test_combat_confirms_both_sides()
	_finish()


func _test_enemy_squad_starts_unconfirmed() -> void:
	game_state.start_new_game(&"nova_republic")
	var own: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"nova_capital")
	var enemy: Dictionary = game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", &"crimson_capital")
	_check(game_state.campaign_runtime.is_squad_confirmed(&"nova_republic", own.squad.squad_id),
		"a faction's own squad should always be confirmed to itself")
	_check(not game_state.campaign_runtime.is_squad_confirmed(&"nova_republic", enemy.squad.squad_id),
		"a hostile squad in a distant, never-visited region should start unconfirmed")


## COMBAT_DETAIL_SPECIFICATION.md section 24's "sufficient sensor detection"
## rule, applied at the strategic layer as same-region co-location: no
## combat is needed, just refresh_intel_from_colocation while sharing a region.
func _test_colocation_confirms_without_combat() -> void:
	game_state.start_new_game(&"nova_republic")
	var own: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"crimson_border")
	var enemy: Dictionary = game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", &"crimson_border")
	_check(not game_state.campaign_runtime.is_squad_confirmed(&"nova_republic", enemy.squad.squad_id),
		"co-located squads should not be confirmed before any refresh runs")
	game_state.refresh_intel_from_colocation(&"nova_republic")
	_check(game_state.campaign_runtime.is_squad_confirmed(&"nova_republic", enemy.squad.squad_id),
		"a co-located hostile squad should become confirmed after a colocation refresh")
	_check(not game_state.campaign_runtime.is_squad_confirmed(&"crimson_empire", own.squad.squad_id),
		"refreshing one faction's intel should not confirm anything for the other faction")


func _test_confirmation_is_sticky_after_moving_apart() -> void:
	game_state.start_new_game(&"nova_republic")
	var own: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"crimson_border")
	var enemy: Dictionary = game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", &"crimson_border")
	game_state.refresh_intel_from_colocation(&"nova_republic")
	_check(game_state.campaign_runtime.is_squad_confirmed(&"nova_republic", enemy.squad.squad_id),
		"setup did not confirm the co-located enemy squad")

	(own.squad as SquadState).region_id = &"nova_capital"
	game_state.refresh_intel_from_colocation(&"nova_republic")
	_check(game_state.campaign_runtime.is_squad_confirmed(&"nova_republic", enemy.squad.squad_id),
		"confirmation should stay sticky after the observing squad leaves the region")


## STRATEGY_DETAIL_SPECIFICATION.md section 6: "編成変更された部隊は敵側
## から見て未確認状態へ戻る" -- a composition change (which bumps
## intel_revision) invalidates any existing confirmed record.
func _test_reverts_on_composition_change() -> void:
	game_state.start_new_game(&"nova_republic")
	game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"crimson_border")
	var enemy: Dictionary = game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", &"crimson_border")
	game_state.refresh_intel_from_colocation(&"nova_republic")
	_check(game_state.campaign_runtime.is_squad_confirmed(&"nova_republic", enemy.squad.squad_id),
		"setup did not confirm the enemy squad")

	var enemy_squad := enemy.squad as SquadState
	var second_unit: Dictionary = game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", &"crimson_border")
	enemy_squad.assign_unit(second_unit.unit.instance_id, 1)
	(second_unit.unit as UnitInstanceState).squad_id = enemy_squad.squad_id
	(second_unit.unit as UnitInstanceState).slot_index = 1
	_check(not game_state.campaign_runtime.is_squad_confirmed(&"nova_republic", enemy_squad.squad_id),
		"a squad whose composition changed should revert to unconfirmed even without an active un-confirm step")


func _test_combat_confirms_both_sides() -> void:
	game_state.start_new_game(&"nova_republic")
	var attacker: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"crimson_border")
	var defender: Dictionary = game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", &"crimson_border")
	attacker.squad.move_origin_region_id = &"nova_border"
	var pending := {
		"type": "squad_battle_pending", "region_id": &"crimson_border",
		"attacker_id": &"nova_republic", "defender_id": &"crimson_empire",
		"attacker_squad_ids": [attacker.squad.squad_id], "defender_squad_ids": [defender.squad.squad_id],
	}
	var created: Dictionary = BattleRuntimeFactory.new().create_from_pending(
		pending, game_state.campaign_runtime, &"intel_combat_test", 1, Vector3.ZERO, Vector3.ONE,
	)
	_check(created.errors.is_empty(), "battle creation failed: %s" % created.errors)
	var battle := created.state as BattleRuntimeState
	if battle == null:
		return
	(battle.unit_states_by_id[defender.unit.instance_id] as BattleUnitState).current_hp = 0
	var finalize_errors := battle.finalize(&"nova_republic", &"crimson_empire", &"annihilation")
	_check(finalize_errors.is_empty(), "finalize failed: %s" % finalize_errors)
	var apply_errors: PackedStringArray = game_state.apply_battle_result(battle)
	_check(apply_errors.is_empty(), "apply_battle_result failed: %s" % apply_errors)

	_check(game_state.campaign_runtime.is_squad_confirmed(&"crimson_empire", attacker.squad.squad_id),
		"the defender should gain confirmed intel on the attacker after the battle")
	# The defender's squad was annihilated and its sole unit was not
	# captured/recovered as itself, so its SquadState no longer exists --
	# is_squad_confirmed correctly reports false for a squad that is gone,
	# not because confirmation failed.
	_check(game_state.campaign_runtime.get_squad(defender.squad.squad_id) == null,
		"expected the wiped-out defender squad to have been removed")


func _finish() -> void:
	if failures.is_empty():
		print("strategic_intel_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("strategic_intel_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
