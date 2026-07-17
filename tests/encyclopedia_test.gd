extends SceneTree
## DATA_DEFINITION.md section 24: ProfileState.encyclopedia_unit_ids/
## encyclopedia_weapon_ids/encyclopedia_pilot_ids, grown by
## GameState.register_encyclopedia_for_squad.

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
		push_error("encyclopedia_test: required autoload is unavailable")
		quit(1)
		return

	_profile_path_existed_before = FileAccess.file_exists(PROFILE_PATH)
	if _profile_path_existed_before:
		var existing := FileAccess.open(PROFILE_PATH, FileAccess.READ)
		_original_profile_text = existing.get_as_text()
		existing.close()
	# GameState.rollout_new_unit/refresh_intel_from_colocation now register
	# encyclopedia entries for the player faction unconditionally, so *any*
	# other test file that calls start_new_game (nearly all of them) also
	# writes real encyclopedia data to user://profile.json as a side effect
	# -- unlike achievement_ids/unlocked_tech_candidate_ids (only touched by
	# a handful of dedicated tests), this file's "should not be known yet"
	# assertions would otherwise be fragile against whatever the rest of the
	# suite happened to run first. Force a guaranteed-clean in-memory
	# profile for this run regardless of what's already on disk; the
	# snapshot/restore above still protects the real file's content either way.
	game_state.profile = ProfileState.new()

	_test_player_roster_known_immediately_at_seeding()
	_test_enemy_units_unknown_until_intel_confirmed()
	_test_colocation_confirmation_registers_encyclopedia_entries()
	_test_production_registers_a_newly_built_player_unit()
	_test_registration_is_idempotent()
	_test_save_load_round_trips_encyclopedia_state()

	if _profile_path_existed_before:
		var restored := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
		restored.store_string(_original_profile_text)
		restored.close()
	elif FileAccess.file_exists(PROFILE_PATH):
		DirAccess.remove_absolute(PROFILE_PATH)
	game_state._load_profile()

	_finish()


func _test_player_roster_known_immediately_at_seeding() -> void:
	turn_manager.start_new_game(&"nova_republic")
	_check(game_state.profile.encyclopedia_unit_ids.has(&"nova_scout"), "the player's own seeded nova_scout should be known immediately")
	_check(game_state.profile.encyclopedia_unit_ids.has(&"nova_vanguard"), "the player's own seeded nova_vanguard should be known immediately")
	_check(game_state.profile.encyclopedia_weapon_ids.has(&"light_autocannon"), "a known unit's weapon should be registered too")
	_check(game_state.profile.encyclopedia_pilot_ids.has(&"aria_nova"), "the player's own named pilot should be known immediately once _seed_initial_pilots assigns them")


func _test_enemy_units_unknown_until_intel_confirmed() -> void:
	turn_manager.start_new_game(&"nova_republic")
	_check(not game_state.profile.encyclopedia_unit_ids.has(&"crimson_bastion"), "an enemy faction's unit should not be known before any intel confirmation")
	_check(not game_state.profile.encyclopedia_pilot_ids.has(&"darius_crimson"), "an enemy faction's named pilot should not be known before any intel confirmation")


func _test_colocation_confirmation_registers_encyclopedia_entries() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var crimson_squad: SquadState = null
	for squad: SquadState in game_state.campaign_runtime.squads_by_id.values():
		if squad.owner_faction_id == &"crimson_empire":
			crimson_squad = squad
			break
	_check(crimson_squad != null, "setup: crimson_empire should have a seeded squad")
	if crimson_squad == null:
		return
	crimson_squad.region_id = &"nova_capital"  # force colocation with a nova squad
	game_state.refresh_intel_from_colocation(&"nova_republic")
	_check(game_state.profile.encyclopedia_unit_ids.has(&"crimson_bastion"), "colocation-based intel confirmation should register the confirmed squad's unit")
	_check(game_state.profile.encyclopedia_pilot_ids.has(&"darius_crimson"), "colocation-based intel confirmation should register the confirmed squad's assigned named pilot")


func _test_production_registers_a_newly_built_player_unit() -> void:
	# Not asserting "not already known" first: an earlier test in this file
	# may have already registered crimson_bastion via colocation, and
	# GameState.profile (deliberately, matching tech_tree_test.gd/
	# achievements_profile_test.gd) isn't reset between test functions, only
	# snapshotted/restored around the whole file. What this test actually
	# proves -- that rollout_new_unit registers regardless of prior state --
	# doesn't depend on that precondition anyway.
	turn_manager.start_new_game(&"crimson_empire")  # nova_republic is AI this time
	var result: Dictionary = game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", &"crimson_capital")
	_check((result.errors as PackedStringArray).is_empty(), "setup: rollout should succeed: %s" % [result.errors])
	_check(game_state.profile.encyclopedia_unit_ids.has(&"crimson_bastion"), "rollout_new_unit for the player's own faction should register the new unit immediately, covering production mid-campaign the same way as initial seeding")


func _test_registration_is_idempotent() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var nova_squad: SquadState = null
	for squad: SquadState in game_state.campaign_runtime.squads_by_id.values():
		if squad.owner_faction_id == &"nova_republic":
			nova_squad = squad
			break
	_check(nova_squad != null, "setup: nova_republic should have a seeded squad")
	if nova_squad == null:
		return
	var before_count: int = game_state.profile.encyclopedia_unit_ids.size()
	game_state.register_encyclopedia_for_squad(nova_squad.squad_id)
	game_state.register_encyclopedia_for_squad(nova_squad.squad_id)
	_check(game_state.profile.encyclopedia_unit_ids.size() == before_count, "re-registering an already-known squad should not add duplicate entries")


func _test_save_load_round_trips_encyclopedia_state() -> void:
	var profile := ProfileState.new()
	profile.register_encyclopedia_unit(&"nova_scout")
	profile.register_encyclopedia_weapon(&"beam_rifle")
	profile.register_encyclopedia_pilot(&"aria_nova")
	var dict := profile.to_dict()
	_check((dict.encyclopedia_unit_ids as Array).has(&"nova_scout"), "to_dict should include encyclopedia_unit_ids")
	_check((dict.encyclopedia_weapon_ids as Array).has(&"beam_rifle"), "to_dict should include encyclopedia_weapon_ids")
	_check((dict.encyclopedia_pilot_ids as Array).has(&"aria_nova"), "to_dict should include encyclopedia_pilot_ids")

	var reloaded := ProfileState.from_dict(dict, game_state.master_data)
	_check(reloaded.encyclopedia_unit_ids.has(&"nova_scout"), "encyclopedia_unit_ids should survive a to_dict/from_dict round trip")
	_check(reloaded.encyclopedia_weapon_ids.has(&"beam_rifle"), "encyclopedia_weapon_ids should survive a to_dict/from_dict round trip")
	_check(reloaded.encyclopedia_pilot_ids.has(&"aria_nova"), "encyclopedia_pilot_ids should survive a to_dict/from_dict round trip")


func _finish() -> void:
	if failures.is_empty():
		print("encyclopedia_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("encyclopedia_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
