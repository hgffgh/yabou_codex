extends SceneTree
## DATA_DEFINITION.md sections 23/24 (AchievementDef/ProfileState) and
## SYSTEM_DETAIL_SPECIFICATION.md section 2 (autosave).

var failures := PackedStringArray()
var game_state: Node
var turn_manager: Node
var _profile_path_existed_before := false
var _original_profile_text := ""

const PROFILE_PATH := "user://profile.json"


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	turn_manager = root.get_node_or_null("TurnManager")
	if game_state == null or turn_manager == null:
		push_error("achievements_profile_test: required autoload is unavailable")
		quit(1)
		return

	# Several tests below call evaluate_achievements(), which persists to
	# the real user://profile.json whenever it unlocks anything -- snapshot
	# it once up front and restore it once at the end, rather than leaking
	# real achievement unlocks into whatever profile this machine actually
	# has (and, worse, into every later test run in the same sweep, since
	# user:// survives across separate --script process invocations).
	_profile_path_existed_before = FileAccess.file_exists(PROFILE_PATH)
	if _profile_path_existed_before:
		var existing := FileAccess.open(PROFILE_PATH, FileAccess.READ)
		_original_profile_text = existing.get_as_text()
		existing.close()

	_test_achievement_registry_loads_expected_presets()
	_test_profile_unlock_achievement_is_idempotent_and_validated()
	_test_permanent_exp_bonus_caps_at_half()
	_test_save_and_load_profile_round_trips()
	_test_did_player_win_across_reason_types()
	_test_evaluate_achievements_unlocks_matching_conditions_only()
	_test_capture_and_treaty_count_achievements()
	_test_permanent_exp_bonus_applies_only_to_player_pilots()
	_test_autosave_writes_a_rotating_slot()

	if _profile_path_existed_before:
		var restored := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
		restored.store_string(_original_profile_text)
		restored.close()
	elif FileAccess.file_exists(PROFILE_PATH):
		DirAccess.remove_absolute(PROFILE_PATH)
	game_state._load_profile()

	_finish()


func _test_achievement_registry_loads_expected_presets() -> void:
	_check(game_state.master_data_errors.is_empty(), "achievement data failed master-data validation: %s" % game_state.master_data_errors)
	_check(game_state.master_data.achievements.size() == 7, "expected exactly 7 achievement presets in the standard dataset")


func _test_profile_unlock_achievement_is_idempotent_and_validated() -> void:
	var profile := ProfileState.new()
	_check(profile.unlock_achievement(&"clear_normal", game_state.master_data), "unlocking a real achievement id should succeed")
	_check(not profile.unlock_achievement(&"clear_normal", game_state.master_data), "unlocking the same achievement twice should be a no-op")
	_check(not profile.unlock_achievement(&"not_a_real_id", game_state.master_data), "unlocking an unresolved id should fail")
	_check(profile.has_achievement(&"clear_normal") and profile.achievement_ids.size() == 1, "profile should record exactly one unlocked achievement")


func _test_permanent_exp_bonus_caps_at_half() -> void:
	var registry := MasterDataRegistry.new()
	for i in range(3):
		var def := AchievementDef.new()
		def.id = StringName("synthetic_achievement_%d" % i)
		def.exp_bonus_pct = 0.3
		registry.achievements[def.id] = def
	var profile := ProfileState.new()
	for id: StringName in registry.achievements.keys():
		profile.unlock_achievement(id, registry)
	_check(is_equal_approx(profile.permanent_exp_bonus_pct, ProfileState.MAX_PERMANENT_EXP_BONUS_PCT),
		"three 0.3 bonuses (0.9 total) should clamp to the 0.5 cap, got %.3f" % profile.permanent_exp_bonus_pct)


## Writes to the real user://profile.json -- see _initialize's snapshot/
## restore wrapper around the whole test run for why that's safe here.
func _test_save_and_load_profile_round_trips() -> void:
	game_state.profile = ProfileState.new()
	game_state.profile.unlock_achievement(&"clear_normal", game_state.master_data)
	game_state.save_profile()

	game_state.profile = ProfileState.new()
	game_state._load_profile()
	_check(game_state.profile.has_achievement(&"clear_normal"), "profile should round-trip the unlocked achievement through save/load")
	var expected_bonus: float = (game_state.master_data.achievements[&"clear_normal"] as AchievementDef).exp_bonus_pct
	_check(is_equal_approx(game_state.profile.permanent_exp_bonus_pct, expected_bonus),
		"permanent_exp_bonus_pct should be recalculated from achievement_ids on load, not trusted from the file")


func _test_did_player_win_across_reason_types() -> void:
	game_state.start_new_game(&"nova_republic")
	game_state.is_game_over = true
	game_state.last_game_over_reason = "player_eliminated"
	game_state.last_game_over_standings = []
	_check(not game_state.did_player_win(), "player_eliminated must never count as a win")

	game_state.last_game_over_reason = "capital_capture"
	game_state.last_game_over_standings = [{"faction_id": "nova_republic", "score": -1}]
	_check(game_state.did_player_win(), "capital_capture with the player as sole winner should count as a win")
	game_state.last_game_over_standings = [{"faction_id": "crimson_empire", "score": -1}]
	_check(not game_state.did_player_win(), "capital_capture won by another faction should not count as a player win")

	game_state.last_game_over_reason = "turn_cap"
	game_state.last_game_over_standings = [{"faction_id": "nova_republic", "score": 500}, {"faction_id": "crimson_empire", "score": 200}]
	_check(game_state.did_player_win(), "turn_cap with the player leading the standings should count as a win")
	game_state.last_game_over_standings = [{"faction_id": "crimson_empire", "score": 500}, {"faction_id": "nova_republic", "score": 200}]
	_check(not game_state.did_player_win(), "turn_cap with the player trailing should not count as a win")


func _test_evaluate_achievements_unlocks_matching_conditions_only() -> void:
	game_state.start_new_game(&"nova_republic", &"hard")
	game_state.profile = ProfileState.new()
	game_state.turn_number = 30
	game_state.is_game_over = true
	game_state.last_game_over_reason = "capital_capture"
	game_state.last_game_over_standings = [{"faction_id": "nova_republic", "score": -1}]

	var unlocked: Array[StringName] = game_state.evaluate_achievements()
	_check(unlocked.has(&"clear_nova_republic"), "should unlock clear_nova_republic when the player wins as nova_republic")
	_check(not unlocked.has(&"clear_crimson_empire"), "should not unlock the other faction's clear achievement")
	_check(unlocked.has(&"clear_hard"), "should unlock clear_hard at hard difficulty")
	_check(not unlocked.has(&"clear_normal"), "should not unlock clear_normal at hard difficulty")
	_check(unlocked.has(&"clear_within_50_turns"), "should unlock the turn-limit achievement when won within 50 turns")
	_check(not unlocked.has(&"capture_ten_units"), "should not unlock capture_ten_units with zero captures")
	_check(not unlocked.has(&"three_treaties_in_run"), "should not unlock three_treaties_in_run with zero treaties")
	_check(game_state.profile.has_achievement(&"clear_hard"), "unlocked achievements should be recorded on the profile")
	_check(game_state.last_unlocked_achievement_ids == unlocked, "last_unlocked_achievement_ids should mirror the return value for the results screen to read")

	var second_call: Array[StringName] = game_state.evaluate_achievements()
	_check(second_call.is_empty(), "calling evaluate_achievements again should not re-unlock anything")


func _test_capture_and_treaty_count_achievements() -> void:
	game_state.start_new_game(&"nova_republic")
	game_state.profile = ProfileState.new()
	var nova: Faction = game_state.get_faction(&"nova_republic")
	nova.total_units_captured = 10
	game_state.campaign_runtime.log_diplomacy(1, &"nova_republic", &"crimson_empire", &"treaty_proposal", {}, true)
	game_state.campaign_runtime.log_diplomacy(2, &"nova_republic", &"crimson_empire", &"treaty_proposal", {}, true)
	game_state.campaign_runtime.log_diplomacy(3, &"crimson_empire", &"nova_republic", &"treaty_proposal", {}, true)
	game_state.campaign_runtime.log_diplomacy(4, &"nova_republic", &"crimson_empire", &"treaty_proposal", {}, false)  # failed proposal must not count
	game_state.is_game_over = true
	game_state.last_game_over_reason = "capital_capture"
	game_state.last_game_over_standings = [{"faction_id": "nova_republic", "score": -1}]

	var unlocked: Array[StringName] = game_state.evaluate_achievements()
	_check(unlocked.has(&"capture_ten_units"), "10 captures should unlock capture_ten_units")
	_check(unlocked.has(&"three_treaties_in_run"), "3 successful treaty proposals involving the player should unlock three_treaties_in_run")


func _test_permanent_exp_bonus_applies_only_to_player_pilots() -> void:
	game_state.start_new_game(&"nova_republic")
	game_state.profile = ProfileState.new()
	game_state.profile.permanent_exp_bonus_pct = 0.5

	var attacker: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"crimson_border")
	var defender: Dictionary = game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", &"crimson_border")
	game_state.campaign_runtime.assign_pilot_to_unit(&"aria_nova", attacker.unit.instance_id)
	game_state.campaign_runtime.assign_pilot_to_unit(&"darius_crimson", defender.unit.instance_id)
	attacker.squad.move_origin_region_id = &"nova_border"
	var pending := {
		"type": "squad_battle_pending", "region_id": &"crimson_border",
		"attacker_id": &"nova_republic", "defender_id": &"crimson_empire",
		"attacker_squad_ids": [attacker.squad.squad_id], "defender_squad_ids": [defender.squad.squad_id],
	}
	var battle_map := game_state.master_data.battle_maps[&"standard_battle_map"] as BattleMapDef
	var created: Dictionary = BattleRuntimeFactory.new().create_from_pending(
		pending, game_state.campaign_runtime, &"achievements_profile_test", 1, Vector3(-400, 0, 0), Vector3(400, 0, 0), battle_map,
	)
	_check(created.errors.is_empty(), "battle creation failed: %s" % created.errors)
	var battle := created.state as BattleRuntimeState
	if battle == null:
		return
	battle.result = BattleResultState.new()

	var attacker_unit := battle.unit_states_by_id[attacker.unit.instance_id] as BattleUnitState
	var defender_unit := battle.unit_states_by_id[defender.unit.instance_id] as BattleUnitState
	attacker_unit.exp_earned = 100
	defender_unit.exp_earned = 100

	var aria: PilotState = game_state.campaign_runtime.get_pilot(&"aria_nova")
	var darius: PilotState = game_state.campaign_runtime.get_pilot(&"darius_crimson")
	var aria_exp_before := aria.current_exp
	var darius_exp_before := darius.current_exp

	game_state._apply_battle_pilot_exp(battle)

	_check(aria.current_exp == aria_exp_before + 150,
		"the player's own pilot should get the 50%% permanent bonus applied (ceil(100*1.5)=150), got %d" % (aria.current_exp - aria_exp_before))
	_check(darius.current_exp == darius_exp_before + 100,
		"a non-player pilot must not receive the player's permanent EXP bonus, got %d" % (darius.current_exp - darius_exp_before))


func _test_autosave_writes_a_rotating_slot() -> void:
	turn_manager.start_new_game(&"nova_republic")
	# 3, matching TurnManager.AUTOSAVE_SLOT_COUNT -- not read directly, since a
	# fresh --script entry bare-referencing the TurnManager global identifier
	# hits the same headless compile-order bug GameState/DiplomacyPanel/etc.
	# do (see HANDOFF.md's "Validation and setup" section).
	for slot in range(3):
		var path := "user://saves/autosave_%02d.json" % slot
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

	turn_manager._autosave()
	var slots: Array[Dictionary] = turn_manager.list_save_slots(true)
	_check(slots.size() == 1, "the first autosave should occupy exactly one of the 3 rotating slots, got %d" % slots.size())

	# 3, matching TurnManager.AUTOSAVE_SLOT_COUNT -- not read directly, since a
	# fresh --script entry bare-referencing the TurnManager global identifier
	# hits the same headless compile-order bug GameState/DiplomacyPanel/etc.
	# do (see HANDOFF.md's "Validation and setup" section).
	for slot in range(3):
		var path := "user://saves/autosave_%02d.json" % slot
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _finish() -> void:
	if failures.is_empty():
		print("achievements_profile_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("achievements_profile_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
