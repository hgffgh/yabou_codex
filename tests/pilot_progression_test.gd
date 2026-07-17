extends SceneTree

var failures := PackedStringArray()
var game_state: Node


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	if game_state == null:
		push_error("pilot_progression_test: GameState autoload is unavailable")
		quit(1)
		return

	_test_pilots_seeded_and_auto_assigned()
	_test_assign_and_unassign_semantics()
	_test_growth_stats_in_battle()
	_test_exp_award_and_level_up()
	_test_injury_on_destruction_blocks_reassignment_and_decrements()
	_test_capture_allowed_false_is_always_lost()
	_finish()


## _seed_initial_pilots should create a PilotState at PilotDef.initial_level
## for every roster pilot and auto-claim a still-generic-piloted unit for
## their faction.
func _test_pilots_seeded_and_auto_assigned() -> void:
	game_state.start_new_game(&"nova_republic")
	var aria: PilotState = game_state.campaign_runtime.get_pilot(&"aria_nova")
	_check(aria != null, "aria_nova was not seeded")
	if aria == null:
		return
	_check(aria.owner_faction_id == &"nova_republic", "aria_nova has the wrong owner faction")
	_check(aria.level == 8, "aria_nova was not seeded at PilotDef.initial_level (8), got %d" % aria.level)
	_check(aria.current_exp == 0, "aria_nova did not start at 0 EXP")
	_check(aria.injury_turns_remaining == 0, "aria_nova started injured")
	_check(not aria.assigned_unit_instance_id.is_empty(), "aria_nova was not auto-assigned to a unit")
	if not aria.assigned_unit_instance_id.is_empty():
		var unit: UnitInstanceState = game_state.campaign_runtime.get_unit(aria.assigned_unit_instance_id)
		_check(unit != null and unit.pilot_id == &"aria_nova", "aria_nova's assigned unit does not point back to her")

	var darius: PilotState = game_state.campaign_runtime.get_pilot(&"darius_crimson")
	_check(darius != null and darius.level == 10 and darius.owner_faction_id == &"crimson_empire",
		"darius_crimson was not seeded correctly")

	var validation_errors: PackedStringArray = game_state.campaign_runtime.validate(game_state.master_data, game_state.region_defs)
	_check(validation_errors.is_empty(), "seeded campaign failed validation: %s" % validation_errors)


## Placing a named pilot displaces whatever previously crewed both the
## source and destination units; injured pilots cannot be (re)assigned.
func _test_assign_and_unassign_semantics() -> void:
	game_state.start_new_game(&"nova_republic")
	var aria: PilotState = game_state.campaign_runtime.get_pilot(&"aria_nova")
	var original_unit_id := aria.assigned_unit_instance_id
	var rollout: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"crimson_border")
	var new_unit: UnitInstanceState = rollout.unit

	var errors: PackedStringArray = game_state.campaign_runtime.assign_pilot_to_unit(&"aria_nova", new_unit.instance_id)
	_check(errors.is_empty(), "reassigning aria_nova to a fresh unit failed: %s" % errors)
	_check(new_unit.pilot_id == &"aria_nova", "target unit was not crewed by aria_nova")
	_check(aria.assigned_unit_instance_id == new_unit.instance_id, "aria_nova's assignment did not update")
	var original_unit: UnitInstanceState = game_state.campaign_runtime.get_unit(original_unit_id)
	_check(original_unit != null and original_unit.pilot_id.is_empty(),
		"vacated unit did not revert to a generic pilot")

	var cross_faction_errors: PackedStringArray = game_state.campaign_runtime.assign_pilot_to_unit(&"darius_crimson", new_unit.instance_id)
	_check(not cross_faction_errors.is_empty(), "assigning a pilot to another faction's unit should fail")

	aria.injury_turns_remaining = 1
	var injured_errors: PackedStringArray = game_state.campaign_runtime.assign_pilot_to_unit(&"aria_nova", original_unit_id)
	_check(not injured_errors.is_empty(), "assigning an injured pilot should fail")
	aria.injury_turns_remaining = 0

	var unassign_errors: PackedStringArray = game_state.campaign_runtime.unassign_pilot(&"aria_nova")
	_check(unassign_errors.is_empty() and new_unit.pilot_id.is_empty() and aria.assigned_unit_instance_id.is_empty(),
		"unassign_pilot did not fully revert the pilot and unit")


## STRATEGY_DETAIL_SPECIFICATION.md section 5.5: fixed per-level growth,
## no randomness, capped at 200. aria_nova: initial_shooting=125,
## growth_shooting=2 -> at level 5, effective shooting = 125 + 2*4 = 133.
func _test_growth_stats_in_battle() -> void:
	game_state.start_new_game(&"nova_republic")
	var aria: PilotState = game_state.campaign_runtime.get_pilot(&"aria_nova")
	var unit_id := aria.assigned_unit_instance_id
	aria.level = 5
	var unit: UnitInstanceState = game_state.campaign_runtime.get_unit(unit_id)
	var squad: SquadState = game_state.campaign_runtime.get_squad(unit.squad_id)
	squad.move_origin_region_id = &"nova_border"

	var defender: Dictionary = game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", squad.region_id)
	var pending := {
		"type": "squad_battle_pending", "region_id": squad.region_id,
		"attacker_id": &"nova_republic", "defender_id": &"crimson_empire",
		"attacker_squad_ids": [squad.squad_id], "defender_squad_ids": [defender.squad.squad_id],
	}
	var created: Dictionary = BattleRuntimeFactory.new().create_from_pending(
		pending, game_state.campaign_runtime, &"growth_test", 1, Vector3.ZERO, Vector3.ONE,
	)
	_check(created.errors.is_empty(), "battle creation failed: %s" % created.errors)
	var battle := created.state as BattleRuntimeState
	if battle == null:
		return
	var battle_unit := battle.unit_states_by_id[unit_id] as BattleUnitState
	_check(battle_unit.shooting == 133, "expected growth-adjusted shooting 133, got %d" % battle_unit.shooting)
	_check(battle_unit.melee == 95 + 1 * 4, "expected growth-adjusted melee, got %d" % battle_unit.melee)
	_check(battle_unit.command == 115 + 2 * 4, "expected growth-adjusted command, got %d" % battle_unit.command)


## STRATEGY_DETAIL_SPECIFICATION.md section 5.3: base EXP accumulates on
## BattleUnitState.exp_earned; apply_battle_result applies it (ceil with the
## 0.0 placeholder permanent bonus) and levels the pilot up across the
## 250-EXP band that covers levels 1-10. finalize() itself adds the 50 EXP
## battle-victory bonus (annihilation, not hq_capture) to every winning-side
## unit, so the manually-seeded 300 plus that 50 totals 350.
func _test_exp_award_and_level_up() -> void:
	game_state.start_new_game(&"nova_republic")
	var aria: PilotState = game_state.campaign_runtime.get_pilot(&"aria_nova")
	var unit_id := aria.assigned_unit_instance_id
	var unit: UnitInstanceState = game_state.campaign_runtime.get_unit(unit_id)
	var squad: SquadState = game_state.campaign_runtime.get_squad(unit.squad_id)
	squad.move_origin_region_id = &"nova_border"
	var defender: Dictionary = game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", squad.region_id)

	var pending := {
		"type": "squad_battle_pending", "region_id": squad.region_id,
		"attacker_id": &"nova_republic", "defender_id": &"crimson_empire",
		"attacker_squad_ids": [squad.squad_id], "defender_squad_ids": [defender.squad.squad_id],
	}
	var created: Dictionary = BattleRuntimeFactory.new().create_from_pending(
		pending, game_state.campaign_runtime, &"exp_test", 1, Vector3.ZERO, Vector3.ONE,
	)
	_check(created.errors.is_empty(), "battle creation failed: %s" % created.errors)
	var battle := created.state as BattleRuntimeState
	if battle == null:
		return
	(battle.unit_states_by_id[unit_id] as BattleUnitState).exp_earned = 300
	var finalize_errors := battle.finalize(&"nova_republic", &"crimson_empire", &"annihilation")
	_check(finalize_errors.is_empty(), "finalize failed: %s" % finalize_errors)
	var apply_errors: PackedStringArray = game_state.apply_battle_result(battle)
	_check(apply_errors.is_empty(), "apply_battle_result failed: %s" % apply_errors)

	_check(aria.level == 9, "expected aria_nova to level up from 8 to 9 on 350 EXP, got %d" % aria.level)
	_check(aria.current_exp == 100, "expected 100 leftover EXP after the level-up, got %d" % aria.current_exp)
	_check(int(battle.result.pilot_exp.get(&"aria_nova", -1)) == 350,
		"battle.result.pilot_exp did not record aria_nova's 350 EXP")


## COMBAT_DETAIL_SPECIFICATION.md section 18 / STRATEGY_DETAIL_SPECIFICATION.md
## section 5.7: any destroyed unit's named pilot is injured for three turns,
## unassigned, and cannot be reassigned until advance_pilot_injuries_for_faction
## has ticked it down to zero across three of that faction's own turns.
func _test_injury_on_destruction_blocks_reassignment_and_decrements() -> void:
	game_state.start_new_game(&"nova_republic")
	var aria: PilotState = game_state.campaign_runtime.get_pilot(&"aria_nova")
	var unit_id := aria.assigned_unit_instance_id
	var unit: UnitInstanceState = game_state.campaign_runtime.get_unit(unit_id)
	var squad: SquadState = game_state.campaign_runtime.get_squad(unit.squad_id)
	squad.move_origin_region_id = &"nova_border"
	var defender: Dictionary = game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", squad.region_id)

	var pending := {
		"type": "squad_battle_pending", "region_id": squad.region_id,
		"attacker_id": &"nova_republic", "defender_id": &"crimson_empire",
		"attacker_squad_ids": [squad.squad_id], "defender_squad_ids": [defender.squad.squad_id],
	}
	var created: Dictionary = BattleRuntimeFactory.new().create_from_pending(
		pending, game_state.campaign_runtime, &"injury_test", 1, Vector3.ZERO, Vector3.ONE,
	)
	(battle_state(created).unit_states_by_id[unit_id] as BattleUnitState).current_hp = 0
	var battle := battle_state(created)
	# aria_nova's faction wins so her destroyed unit takes the "recovered"
	# path (winner's own losses), which is what exercises the pilot_id
	# back-reference this test checks.
	var finalize_errors := battle.finalize(&"nova_republic", &"crimson_empire", &"annihilation")
	_check(finalize_errors.is_empty(), "finalize failed: %s" % finalize_errors)
	var apply_errors: PackedStringArray = game_state.apply_battle_result(battle)
	_check(apply_errors.is_empty(), "apply_battle_result failed: %s" % apply_errors)

	_check(aria.injury_turns_remaining == 3, "expected a 3-turn injury, got %d" % aria.injury_turns_remaining)
	_check(aria.assigned_unit_instance_id.is_empty(), "injured pilot was not unassigned")
	_check(battle.result.injured_pilot_ids == [&"aria_nova"], "injured_pilot_ids did not list aria_nova")
	var recovered_unit: UnitInstanceState = game_state.campaign_runtime.get_unit(unit_id)
	_check(recovered_unit != null and recovered_unit.pilot_id.is_empty(),
		"recovered husk still points to the now-injured pilot")

	var some_other_unit: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"nova_capital")
	var blocked_errors: PackedStringArray = game_state.campaign_runtime.assign_pilot_to_unit(&"aria_nova", some_other_unit.unit.instance_id)
	_check(not blocked_errors.is_empty(), "an injured pilot should not be assignable")

	game_state.advance_pilot_injuries_for_faction(&"nova_republic")
	_check(aria.injury_turns_remaining == 2, "injury did not decrement on the first turn")
	game_state.advance_pilot_injuries_for_faction(&"nova_republic")
	_check(aria.injury_turns_remaining == 1, "injury did not decrement on the second turn")
	game_state.advance_pilot_injuries_for_faction(&"nova_republic")
	_check(aria.injury_turns_remaining == 0, "injury did not clear after the third turn")
	var recovered_errors: PackedStringArray = game_state.campaign_runtime.assign_pilot_to_unit(&"aria_nova", some_other_unit.unit.instance_id)
	_check(recovered_errors.is_empty(), "a recovered pilot should be assignable again: %s" % recovered_errors)

	var validation_errors: PackedStringArray = game_state.campaign_runtime.validate(game_state.master_data, game_state.region_defs)
	_check(validation_errors.is_empty(), "campaign state failed validation after injury handling: %s" % validation_errors)


## COMBAT_DETAIL_SPECIFICATION.md section 18: capture-disallowed units have
## a 0% capture probability and are always lost outright.
func _test_capture_allowed_false_is_always_lost() -> void:
	game_state.start_new_game(&"nova_republic")
	var attacker: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"crimson_border")
	var defender: Dictionary = game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", &"crimson_border")
	attacker.squad.move_origin_region_id = &"nova_border"

	var uncapturable_def: UnitDef = (game_state.master_data.units[&"crimson_bastion"] as UnitDef).duplicate()
	uncapturable_def.id = &"test_story_unit"
	uncapturable_def.capture_allowed = false
	game_state.master_data.units[uncapturable_def.id] = uncapturable_def
	(defender.unit as UnitInstanceState).unit_def_id = uncapturable_def.id

	var pending := {
		"type": "squad_battle_pending", "region_id": &"crimson_border",
		"attacker_id": &"nova_republic", "defender_id": &"crimson_empire",
		"attacker_squad_ids": [attacker.squad.squad_id], "defender_squad_ids": [defender.squad.squad_id],
	}
	var created: Dictionary = BattleRuntimeFactory.new().create_from_pending(
		pending, game_state.campaign_runtime, &"capture_gate_test", 1, Vector3.ZERO, Vector3.ONE,
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

	_check(battle.result.captured_unit_ids.is_empty(), "a capture_allowed=false unit was captured")
	_check(battle.result.lost_unit_ids == [defender.unit.instance_id], "a capture_allowed=false unit was not lost outright")

	game_state.master_data.units.erase(uncapturable_def.id)


func battle_state(created: Dictionary) -> BattleRuntimeState:
	return created.state as BattleRuntimeState


func _finish() -> void:
	if failures.is_empty():
		print("pilot_progression_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("pilot_progression_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
