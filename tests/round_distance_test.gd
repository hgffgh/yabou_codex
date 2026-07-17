extends SceneTree
## COMBAT_DETAIL_SPECIFICATION.md section 26: the abstract in-round
## engagement distance, decoupled from world_position, that shifts each
## tick per both squads' policy and gates which weapons stay usable.

var failures := PackedStringArray()
var game_state: Node


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	if game_state == null:
		push_error("round_distance_test: GameState autoload is unavailable")
		quit(1)
		return

	_test_round_distance_rate_matches_the_policy_table()
	_test_engagement_seeds_distance_from_real_world_position()
	_test_mutual_offensive_closes_distance()
	_test_mutual_retreat_opens_distance()
	_test_distance_change_clamps_at_zero()
	_test_weapon_range_gated_by_abstract_distance_not_world_position()
	_test_world_position_frozen_while_engagement_distance_drifts()
	_test_next_round_distance_recalculates_from_real_position()
	_finish()


func _test_round_distance_rate_matches_the_policy_table() -> void:
	var speed := 20.0
	var cases := {
		GameEnums.BattlePolicy.OFFENSIVE: {"approach": 20.0, "withdraw": 0.0},
		GameEnums.BattlePolicy.BALANCED: {"approach": 10.0, "withdraw": 0.0},
		GameEnums.BattlePolicy.DEFENSIVE: {"approach": 0.0, "withdraw": 5.0},
		GameEnums.BattlePolicy.SUPPORT: {"approach": 0.0, "withdraw": 10.0},
		GameEnums.BattlePolicy.RETREAT: {"approach": 0.0, "withdraw": 20.0},
	}
	for policy: GameEnums.BattlePolicy in cases:
		var expected: Dictionary = cases[policy]
		var rate: Dictionary = BattleRuntimeState._round_distance_rate(policy, speed)
		_check(is_equal_approx(float(rate.approach), float(expected.approach)) and is_equal_approx(float(rate.withdraw), float(expected.withdraw)),
			"policy %d rate mismatch: got %s expected %s" % [policy, rate, expected])


func _test_engagement_seeds_distance_from_real_world_position() -> void:
	var battle := _build_battle(Vector3(0, 0, 0), Vector3(40, 0, 0))
	if battle == null:
		return
	battle.update_engagements(0.0)
	var attacker_squad := _only_squad(battle, battle.attacker_squad_ids)
	var engagement := battle.engagements_by_squad_id.get(attacker_squad.squad_id) as BattleEngagementState
	_check(engagement != null, "squads 40m apart with a 60m-range weapon should have formed an engagement")
	if engagement == null:
		return
	_check(is_equal_approx(engagement.engagement_distance_m, 40.0),
		"a freshly-formed engagement's distance should equal the real world distance at formation, got %.2f" % engagement.engagement_distance_m)


func _test_mutual_offensive_closes_distance() -> void:
	var battle := _build_battle(Vector3(0, 0, 0), Vector3(40, 0, 0))
	if battle == null:
		return
	battle.update_engagements(0.0)
	var attacker_squad := _only_squad(battle, battle.attacker_squad_ids)
	var defender_squad := _only_squad(battle, battle.defender_squad_ids)
	attacker_squad.policy = GameEnums.BattlePolicy.OFFENSIVE
	defender_squad.policy = GameEnums.BattlePolicy.OFFENSIVE
	var engagement := battle.engagements_by_squad_id[attacker_squad.squad_id] as BattleEngagementState
	var before := engagement.engagement_distance_m
	battle._advance_engagement_distance(engagement, 1.0)
	_check(engagement.engagement_distance_m < before,
		"two mutually OFFENSIVE squads should close the in-round distance (before=%.2f after=%.2f)" % [before, engagement.engagement_distance_m])


func _test_mutual_retreat_opens_distance() -> void:
	var battle := _build_battle(Vector3(0, 0, 0), Vector3(40, 0, 0))
	if battle == null:
		return
	battle.update_engagements(0.0)
	var attacker_squad := _only_squad(battle, battle.attacker_squad_ids)
	var defender_squad := _only_squad(battle, battle.defender_squad_ids)
	attacker_squad.policy = GameEnums.BattlePolicy.RETREAT
	defender_squad.policy = GameEnums.BattlePolicy.RETREAT
	var engagement := battle.engagements_by_squad_id[attacker_squad.squad_id] as BattleEngagementState
	var before := engagement.engagement_distance_m
	battle._advance_engagement_distance(engagement, 1.0)
	_check(engagement.engagement_distance_m > before,
		"two mutually RETREAT squads should open the in-round distance (before=%.2f after=%.2f)" % [before, engagement.engagement_distance_m])


func _test_distance_change_clamps_at_zero() -> void:
	var battle := _build_battle(Vector3(0, 0, 0), Vector3(40, 0, 0))
	if battle == null:
		return
	battle.update_engagements(0.0)
	var attacker_squad := _only_squad(battle, battle.attacker_squad_ids)
	var defender_squad := _only_squad(battle, battle.defender_squad_ids)
	attacker_squad.policy = GameEnums.BattlePolicy.OFFENSIVE
	defender_squad.policy = GameEnums.BattlePolicy.OFFENSIVE
	var engagement := battle.engagements_by_squad_id[attacker_squad.squad_id] as BattleEngagementState
	battle._advance_engagement_distance(engagement, 100.0)
	_check(engagement.engagement_distance_m == 0.0, "the abstract distance must never go negative, got %.2f" % engagement.engagement_distance_m)


## The whole point of section 26: two squads sitting 40m apart in real
## world_position (well within light_autocannon's 0-60m range) can still
## have their weapon go unusable mid-round once the abstract distance has
## drifted past 60m, proving the range check no longer reads world_position
## at all once an engagement is active.
func _test_weapon_range_gated_by_abstract_distance_not_world_position() -> void:
	var battle := _build_battle(Vector3(0, 0, 0), Vector3(40, 0, 0))
	if battle == null:
		return
	battle.update_engagements(0.0)
	var attacker_squad := _only_squad(battle, battle.attacker_squad_ids)
	var defender_squad := _only_squad(battle, battle.defender_squad_ids)
	var engagement := battle.engagements_by_squad_id[attacker_squad.squad_id] as BattleEngagementState
	var weapon := battle.weapon_defs[&"light_autocannon"] as WeaponDef

	_check(not BattleCombatSystem._select_target(battle, attacker_squad, weapon).is_empty(),
		"at the freshly-seeded 40m abstract distance, a target within range should be selectable")

	engagement.engagement_distance_m = 100.0
	_check(
		Vector2(attacker_squad.world_position.x, attacker_squad.world_position.y).distance_to(
			Vector2(defender_squad.world_position.x, defender_squad.world_position.y)
		) == 40.0,
		"world_position itself must be untouched by directly editing the engagement's abstract distance",
	)
	_check(BattleCombatSystem._select_target(battle, attacker_squad, weapon).is_empty(),
		"once the abstract distance drifts past max_range_m, the weapon must stop being usable even though the real world distance (40m) is still in range")


func _test_world_position_frozen_while_engagement_distance_drifts() -> void:
	var battle := _build_battle(Vector3(0, 0, 0), Vector3(40, 0, 0))
	if battle == null:
		return
	var attacker_squad := _only_squad(battle, battle.attacker_squad_ids)
	var defender_squad := _only_squad(battle, battle.defender_squad_ids)
	attacker_squad.policy = GameEnums.BattlePolicy.RETREAT
	defender_squad.policy = GameEnums.BattlePolicy.RETREAT
	var attacker_position_before := attacker_squad.world_position
	var defender_position_before := defender_squad.world_position

	for _tick in range(50):
		battle.advance_time(0.1)
		if battle.result != null:
			break

	var engagement := battle.engagements_by_squad_id.get(attacker_squad.squad_id) as BattleEngagementState
	_check(engagement != null, "setup: an engagement should have formed and still be active after 5 seconds")
	if engagement != null:
		_check(not is_equal_approx(engagement.engagement_distance_m, 40.0),
			"the abstract distance should have drifted away from its 40m seed under a RETREAT/RETREAT pairing")
	_check(attacker_squad.world_position == attacker_position_before and defender_squad.world_position == defender_position_before,
		"real world_position must stay frozen for the whole battle while any engagement is active, however the abstract distance moves")


## "次ラウンドの初期距離は、戦場上の実際の位置から再計算する" -- ending an
## engagement, moving the squads for real, and forming a new one must seed
## the new engagement from the new real distance, not carry over whatever
## the old engagement's abstract distance had drifted to.
func _test_next_round_distance_recalculates_from_real_position() -> void:
	var battle := _build_battle(Vector3(0, 0, 0), Vector3(40, 0, 0))
	if battle == null:
		return
	battle.update_engagements(0.0)
	var attacker_squad := _only_squad(battle, battle.attacker_squad_ids)
	var defender_squad := _only_squad(battle, battle.defender_squad_ids)
	var engagement := battle.engagements_by_squad_id[attacker_squad.squad_id] as BattleEngagementState
	engagement.engagement_distance_m = 9999.0
	battle._end_engagement(engagement)
	_check(not battle.is_squad_engaged(attacker_squad.squad_id), "setup: ending the engagement should clear both squads' engaged state")

	defender_squad.world_position = Vector3(20, 0, 0)
	# _end_engagement sets a 5-second reengage_wait_sec on both squads.
	# update_engagements(delta) both decrements that cooldown *and* (once a
	# new engagement forms in the same call) advances that same engagement's
	# distance by delta -- passing 5.0 here would immediately collapse the
	# freshly-seeded distance under the default BALANCED/BALANCED mutual
	# approach. Clearing the cooldown directly instead isolates "did the new
	# engagement seed correctly" from "how did it evolve afterward."
	attacker_squad.reengage_wait_sec = 0.0
	defender_squad.reengage_wait_sec = 0.0
	battle.update_engagements(0.0)
	var new_engagement := battle.engagements_by_squad_id.get(attacker_squad.squad_id) as BattleEngagementState
	_check(new_engagement != null and new_engagement != engagement, "a new engagement should form once real world_position brings the squads back into weapon contact")
	if new_engagement != null:
		_check(is_equal_approx(new_engagement.engagement_distance_m, 20.0),
			"the new engagement's distance should be recomputed from the new real 20m distance, not inherit the old engagement's drifted value, got %.2f" % new_engagement.engagement_distance_m)


func _build_battle(attacker_spawn: Vector3, defender_spawn: Vector3) -> BattleRuntimeState:
	game_state.start_new_game(&"nova_republic")
	var attacker: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"crimson_border")
	var defender: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"crimson_empire", &"crimson_border")
	attacker.squad.move_origin_region_id = &"nova_border"
	var pending := {
		"type": "squad_battle_pending", "region_id": &"crimson_border",
		"attacker_id": &"nova_republic", "defender_id": &"crimson_empire",
		"attacker_squad_ids": [attacker.squad.squad_id], "defender_squad_ids": [defender.squad.squad_id],
	}
	var battle_map := game_state.master_data.battle_maps[&"standard_battle_map"] as BattleMapDef
	var created: Dictionary = BattleRuntimeFactory.new().create_from_pending(
		pending, game_state.campaign_runtime, &"round_distance_test", 1, attacker_spawn, defender_spawn, battle_map,
	)
	_check(created.errors.is_empty(), "battle creation failed: %s" % created.errors)
	var battle := created.state as BattleRuntimeState
	if battle == null:
		return null
	var attacker_squad := _only_squad(battle, battle.attacker_squad_ids)
	var defender_squad := _only_squad(battle, battle.defender_squad_ids)
	attacker_squad.world_position = attacker_spawn
	attacker_squad.destination = attacker_spawn
	defender_squad.world_position = defender_spawn
	defender_squad.destination = defender_spawn
	# None of these tests are about AI destination-seeking, and letting it
	# run would move world_position for real during the brief pre-engagement
	# window each advance_time call has before contact forms, contaminating
	# the "world_position stays frozen" assertions below.
	attacker_squad.movement_ai_disabled = true
	defender_squad.movement_ai_disabled = true
	return battle


func _only_squad(battle: BattleRuntimeState, squad_ids: Array[StringName]) -> BattleSquadState:
	return battle.squad_states_by_id[squad_ids[0]] as BattleSquadState


func _finish() -> void:
	if failures.is_empty():
		print("round_distance_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("round_distance_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
