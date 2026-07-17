extends SceneTree

var failures := PackedStringArray()
var game_state: Node


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	if game_state == null:
		push_error("squad_combat_boundary_test: GameState autoload is unavailable")
		quit(1)
		return
	if not game_state.has_method("detect_squad_conflicts"):
		push_error("squad_combat_boundary_test: GameState.detect_squad_conflicts is unavailable")
		quit(1)
		return

	_test_undefended_region_is_captured()
	_test_defended_region_creates_pending_battle()
	_test_only_moved_active_squads_can_invade()
	_test_conflicts_are_sorted_by_region_id()
	_finish()


func _test_undefended_region_is_captured() -> void:
	_reset_runtime()
	var attacker := _rollout(&"nova_scout", &"nova_republic", &"crimson_border")
	_mark_as_invader(attacker, &"nova_border")

	var events: Array[Dictionary] = game_state.detect_squad_conflicts(&"nova_republic")
	_check(events.size() == 1, "undefended invasion did not produce exactly one event")
	if events.size() != 1:
		return
	var event := events[0]
	_check(event.get("type", "") == "auto_capture", "undefended invasion was not an auto_capture")
	_check(event.get("region_id", &"") == &"crimson_border", "auto_capture reported the wrong region")
	_check(event.get("faction_id", &"") == &"nova_republic", "auto_capture reported the wrong faction")
	_check(game_state.get_region(&"crimson_border").owner_faction_id == &"nova_republic",
		"auto_capture did not update region ownership")


func _test_defended_region_creates_pending_battle() -> void:
	_reset_runtime()
	var attacker := _rollout(&"nova_scout", &"nova_republic", &"crimson_border")
	var defender := _rollout(&"crimson_bastion", &"crimson_empire", &"crimson_border")
	_mark_as_invader(attacker, &"nova_border")

	var events: Array[Dictionary] = game_state.detect_squad_conflicts(&"nova_republic")
	_check(events.size() == 1, "defended invasion did not produce exactly one event")
	if events.size() != 1:
		return
	var event := events[0]
	_check(event.get("type", "") == "squad_battle_pending", "defended invasion was not left pending")
	_check(event.get("attacker_id", &"") == &"nova_republic", "pending battle has the wrong attacker")
	_check(event.get("defender_id", &"") == &"crimson_empire", "pending battle has the wrong defender")
	_check(event.get("attacker_squad_ids", []) == [attacker.squad.squad_id],
		"pending battle does not reference the invading squad")
	_check(event.get("defender_squad_ids", []) == [defender.squad.squad_id],
		"pending battle does not reference the defending squad")
	_check(game_state.get_region(&"crimson_border").owner_faction_id == &"crimson_empire",
		"pending battle changed ownership before combat resolution")


func _test_only_moved_active_squads_can_invade() -> void:
	_reset_runtime()
	_rollout(&"nova_scout", &"nova_republic", &"crimson_border")
	_rollout(&"crimson_bastion", &"crimson_empire", &"crimson_border")

	var events: Array[Dictionary] = game_state.detect_squad_conflicts(&"nova_republic")
	_check(events.is_empty(), "a stationary hostile squad was treated as an invader")
	_check(game_state.get_region(&"crimson_border").owner_faction_id == &"crimson_empire",
		"stationary hostile squad changed region ownership")


func _test_conflicts_are_sorted_by_region_id() -> void:
	_reset_runtime()
	var border_attacker := _rollout(&"nova_scout", &"nova_republic", &"crimson_border")
	var outpost_attacker := _rollout(&"nova_vanguard", &"nova_republic", &"crimson_outpost")
	_rollout(&"crimson_bastion", &"crimson_empire", &"crimson_border")
	_rollout(&"crimson_bastion", &"crimson_empire", &"crimson_outpost")
	_mark_as_invader(outpost_attacker, &"nova_outpost")
	_mark_as_invader(border_attacker, &"nova_border")

	var events: Array[Dictionary] = game_state.detect_squad_conflicts(&"nova_republic")
	_check(events.size() == 2, "two collision regions did not produce two events")
	if events.size() == 2:
		_check(events[0].get("region_id", &"") == &"crimson_border",
			"collision events are not sorted by ascending region ID")
		_check(events[1].get("region_id", &"") == &"crimson_outpost",
			"collision events are not sorted by ascending region ID")


func _reset_runtime() -> void:
	game_state.start_new_game(&"nova_republic")
	game_state.campaign_runtime.reset()


func _rollout(unit_def_id: StringName, faction_id: StringName, region_id: StringName) -> Dictionary:
	var result: Dictionary = game_state.rollout_new_unit(unit_def_id, faction_id, region_id)
	_check(result.get("errors", PackedStringArray(["missing errors"])).is_empty(),
		"rollout failed for %s in %s: %s" % [unit_def_id, region_id, result.get("errors", [])])
	return result


func _mark_as_invader(rollout: Dictionary, origin_region_id: StringName) -> void:
	var squad := rollout.get("squad") as SquadState
	if squad != null:
		squad.move_origin_region_id = origin_region_id
		squad.movement_used = true


func _finish() -> void:
	if failures.is_empty():
		print("squad_combat_boundary_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("squad_combat_boundary_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
