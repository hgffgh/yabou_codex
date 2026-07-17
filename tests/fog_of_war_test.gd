extends SceneTree

var failures := PackedStringArray()
var game_state: Node


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	if game_state == null:
		push_error("fog_of_war_test: GameState autoload is unavailable")
		quit(1)
		return

	_test_starts_unconfirmed_then_confirms_asymmetrically_by_sensor_range()
	_test_confirmation_is_sticky_after_leaving_range()
	_test_engagement_confirms_regardless_of_distance()
	_test_reveal_window_counts_as_sensed_until_it_expires()
	_test_firing_from_outside_sensor_range_opens_reveal_window()
	_test_view_hides_unconfirmed_enemy_and_freezes_last_known_position()
	_finish()


## nova_scout has sensor_range_m 300, crimson_bastion 150. At 800m apart,
## neither side's sensor (nor combat) reaches the other, so both start
## fully unconfirmed. Moving to 200m apart lets nova's stronger sensor spot
## crimson, but crimson's weaker sensor still cannot spot nova back.
func _test_starts_unconfirmed_then_confirms_asymmetrically_by_sensor_range() -> void:
	var battle := _build_battle(Vector3(-400, 0, 0), Vector3(400, 0, 0))
	if battle == null:
		return
	var attacker_squad := _only_squad(battle, battle.attacker_squad_ids)
	var defender_squad := _only_squad(battle, battle.defender_squad_ids)
	battle._advance_intel_sensing()
	_check(not attacker_squad.intel_confirmed and not defender_squad.intel_confirmed,
		"squads 800m apart should both start unconfirmed")

	attacker_squad.world_position = Vector3(-400, 0, 0)
	defender_squad.world_position = Vector3(-200, 0, 0)
	battle._advance_intel_sensing()
	_check(defender_squad.intel_confirmed and defender_squad.currently_sensed,
		"defender at 200m should be confirmed by nova_scout's 300m sensor")
	_check(defender_squad.last_known_world_position == defender_squad.world_position,
		"confirmed-and-sensed squad should track its live position")
	_check(not attacker_squad.intel_confirmed and not attacker_squad.currently_sensed,
		"attacker at 200m should stay unconfirmed against crimson_bastion's 150m sensor")


## intel_confirmed never reverts within a battle; currently_sensed and the
## displayed position do react to distance again once out of range.
func _test_confirmation_is_sticky_after_leaving_range() -> void:
	var battle := _build_battle(Vector3(-400, 0, 0), Vector3(-200, 0, 0))
	if battle == null:
		return
	var attacker_squad := _only_squad(battle, battle.attacker_squad_ids)
	var defender_squad := _only_squad(battle, battle.defender_squad_ids)
	battle._advance_intel_sensing()
	_check(defender_squad.intel_confirmed, "setup did not confirm the defender")
	var confirmed_position := defender_squad.world_position

	defender_squad.world_position = Vector3(400, 0, 0)
	battle._advance_intel_sensing()
	_check(defender_squad.intel_confirmed, "confirmation reverted after leaving sensor range")
	_check(not defender_squad.currently_sensed, "currently_sensed should clear once out of range")
	_check(defender_squad.last_known_world_position == confirmed_position,
		"last_known_world_position should freeze at the last sensed position, not follow the squad out of range")


## COMBAT_DETAIL_SPECIFICATION.md section 24: a squad that has engaged in
## combat becomes confirmed, independent of the sensor-range check.
func _test_engagement_confirms_regardless_of_distance() -> void:
	var battle := _build_battle(Vector3(-400, 0, 0), Vector3(400, 0, 0))
	if battle == null:
		return
	var attacker_squad := _only_squad(battle, battle.attacker_squad_ids)
	var defender_squad := _only_squad(battle, battle.defender_squad_ids)
	var engagement := BattleEngagementState.new()
	engagement.first_squad_id = attacker_squad.squad_id
	engagement.second_squad_id = defender_squad.squad_id
	battle.engagements_by_squad_id[attacker_squad.squad_id] = engagement
	battle.engagements_by_squad_id[defender_squad.squad_id] = engagement

	battle._advance_intel_sensing()
	# Engagement alone reveals composition (intel_confirmed) but is not a
	# continuous position fix -- these squads are still 800m apart, far
	# beyond any sensor, so currently_sensed stays false.
	_check(attacker_squad.intel_confirmed, "engaged attacker should be confirmed even at 800m")
	_check(defender_squad.intel_confirmed, "engaged defender should be confirmed even at 800m")
	_check(not attacker_squad.currently_sensed and not defender_squad.currently_sensed,
		"engagement alone should not grant live position tracking at 800m")


func _test_reveal_window_counts_as_sensed_until_it_expires() -> void:
	var battle := _build_battle(Vector3(-400, 0, 0), Vector3(400, 0, 0))
	if battle == null:
		return
	var attacker_squad := _only_squad(battle, battle.attacker_squad_ids)
	battle.elapsed_world_sec = 10.0
	attacker_squad.revealed_until_world_sec = 15.0
	battle._advance_intel_sensing()
	_check(attacker_squad.currently_sensed, "attacker inside its reveal window should count as sensed")

	battle.elapsed_world_sec = 15.1
	battle._advance_intel_sensing()
	_check(not attacker_squad.currently_sensed, "attacker's reveal window should have expired")


## Uses a synthetic sensor override (real weapon/sensor pairings in the
## current dataset never let a squad fire from beyond every enemy's sensor
## range) to deterministically exercise the exact
## BattleCombatSystem._advance_step branch that opens the reveal window.
func _test_firing_from_outside_sensor_range_opens_reveal_window() -> void:
	game_state.start_new_game(&"nova_republic")
	var attacker: Dictionary = game_state.rollout_new_unit(&"crimson_bastion", &"nova_republic", &"crimson_border")
	var defender: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"crimson_empire", &"crimson_border")
	var short_sensor_def: UnitDef = (game_state.master_data.units[&"nova_scout"] as UnitDef).duplicate()
	short_sensor_def.id = &"test_short_sensor_scout"
	short_sensor_def.sensor_range_m = 10.0
	game_state.master_data.units[short_sensor_def.id] = short_sensor_def
	(defender.unit as UnitInstanceState).unit_def_id = short_sensor_def.id
	attacker.squad.move_origin_region_id = &"nova_border"

	var pending := {
		"type": "squad_battle_pending", "region_id": &"crimson_border",
		"attacker_id": &"nova_republic", "defender_id": &"crimson_empire",
		"attacker_squad_ids": [attacker.squad.squad_id], "defender_squad_ids": [defender.squad.squad_id],
	}
	var created: Dictionary = BattleRuntimeFactory.new().create_from_pending(
		pending, game_state.campaign_runtime, &"reveal_test", 3, Vector3(0, 0, 0), Vector3(200, 0, 0),
	)
	_check(created.errors.is_empty(), "battle creation failed: %s" % created.errors)
	var battle := created.state as BattleRuntimeState
	if battle == null:
		return
	var attacker_squad := battle.squad_states_by_id[attacker.squad.squad_id] as BattleSquadState
	var defender_squad := battle.squad_states_by_id[defender.squad.squad_id] as BattleSquadState
	attacker_squad.world_position = Vector3(0, 0, 0)
	defender_squad.world_position = Vector3(200, 0, 0)
	# COMBAT_DETAIL_SPECIFICATION.md section 26: both squads default to
	# BALANCED, which mutually approaches and would collapse the in-round
	# abstract distance below siege_cannon's 60m minimum range before
	# crimson_bastion's slow action gauge even fills once, so it would
	# never get to fire at all. DEFENSIVE on both instead grows the
	# distance (with comfortable margin under the 300m max range for the
	# duration of this test), keeping the shot this test needs reliable.
	attacker_squad.policy = GameEnums.BattlePolicy.DEFENSIVE
	defender_squad.policy = GameEnums.BattlePolicy.DEFENSIVE

	var revealed := false
	for _tick in range(200):
		battle.advance_time(0.1)
		if attacker_squad.revealed_until_world_sec > 0.0:
			revealed = true
			break
		if battle.result != null:
			break
	_check(revealed, "crimson_bastion firing its 300m siege_cannon at 200m, unseen by the 10m-sensor defender, should have opened a reveal window")

	game_state.master_data.units.erase(short_sensor_def.id)


func _test_view_hides_unconfirmed_enemy_and_freezes_last_known_position() -> void:
	var battle := _build_battle(Vector3(-400, 0, 0), Vector3(400, 0, 0))
	if battle == null:
		return
	var view := BattlePrototypeView.new()
	view.setup(battle)
	root.add_child(view)
	await process_frame
	await process_frame

	var defender_squad := _only_squad(battle, battle.defender_squad_ids)
	var defender_visual := view.squad_visuals.get(defender_squad.squad_id) as Node3D
	_check(defender_visual != null and not defender_visual.visible,
		"an unconfirmed enemy squad's visual should start hidden")

	defender_squad.intel_confirmed = true
	defender_squad.currently_sensed = false
	defender_squad.last_known_world_position = Vector3(11, 0, 22)
	view._sync_intel_visibility(defender_squad)
	_check(defender_visual.visible, "a confirmed enemy squad's visual should become visible")
	_check(defender_visual.position == Vector3(11, 0, 22),
		"an out-of-range confirmed squad should render at its last known position")

	defender_squad.currently_sensed = true
	defender_squad.world_position = Vector3(33, 0, 44)
	view._sync_intel_visibility(defender_squad)
	_check(defender_visual.position == Vector3(33, 0, 44),
		"a currently-sensed confirmed squad should render at its live position")

	view.queue_free()


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
	var created: Dictionary = BattleRuntimeFactory.new().create_from_pending(
		pending, game_state.campaign_runtime, &"fog_test", 1, attacker_spawn, defender_spawn,
	)
	_check(created.errors.is_empty(), "battle creation failed: %s" % created.errors)
	return created.state as BattleRuntimeState


func _only_squad(battle: BattleRuntimeState, squad_ids: Array[StringName]) -> BattleSquadState:
	return battle.squad_states_by_id[squad_ids[0]] as BattleSquadState


func _finish() -> void:
	if failures.is_empty():
		print("fog_of_war_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("fog_of_war_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
