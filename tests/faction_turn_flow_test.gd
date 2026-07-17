extends SceneTree

var failures := PackedStringArray()
var game_state: Node
var turn_manager: Node


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	turn_manager = root.get_node_or_null("TurnManager")
	if game_state == null or turn_manager == null:
		push_error("faction_turn_flow_test: required autoload is unavailable")
		quit(1)
		return

	turn_manager.start_new_game(&"nova_republic")
	if not _has_faction_turn_api():
		_finish()
		return
	_test_initial_player_turn()
	await _test_full_faction_round()
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("faction_turn_flow_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("faction_turn_flow_test: %s" % failure)
		quit(1)


func _has_faction_turn_api() -> bool:
	var available := (
		"faction_turn_order" in turn_manager
		and "active_faction_index" in turn_manager
		and "active_faction_id" in turn_manager
	)
	_check(available, "TurnManager does not expose the required faction-turn state")
	return available


func _test_initial_player_turn() -> void:
	_check(turn_manager.faction_turn_order.size() == game_state.factions.size(),
		"turn order does not contain every runtime faction")
	_check(not turn_manager.faction_turn_order.is_empty(), "turn order is empty")
	if turn_manager.faction_turn_order.is_empty():
		return
	_check(turn_manager.faction_turn_order[0] == &"nova_republic",
		"the selected player faction is not first in the fixed turn order")
	_check(turn_manager.active_faction_index == 0, "new game did not start at turn-order index zero")
	_check(turn_manager.active_faction_id == &"nova_republic",
		"new game did not wait on the player faction")
	_check(turn_manager.current_phase == turn_manager.Phase.ORDERS,
		"new game did not wait in the player's strategy/orders phase")
	_check(game_state.turn_number == 1, "new game did not start in week one")


func _test_full_faction_round() -> void:
	# A faction's movement reset belongs to its own turn start. Mark an AI squad
	# as already moved and verify the automated AI turn gets a fresh move.
	var ai_id: StringName = &""
	for faction_id: StringName in turn_manager.faction_turn_order:
		if faction_id != game_state.player_faction_id:
			ai_id = faction_id
			break
	var ai_squads: Array[SquadState] = []
	if not ai_id.is_empty():
		for squad: SquadState in game_state.campaign_runtime.squads_by_id.values():
			if squad.owner_faction_id == ai_id:
				ai_squads.append(squad)
				squad.movement_used = true

	turn_manager.commit_turn()
	for frame in range(120):
		if game_state.turn_number == 2 and turn_manager.current_phase == turn_manager.Phase.ORDERS:
			break
		await process_frame

	_check(game_state.turn_number == 2,
		"week number did not advance exactly once after the complete faction round")
	_check(turn_manager.active_faction_index == 0,
		"complete faction round did not wrap to turn-order index zero")
	_check(turn_manager.active_faction_id == game_state.player_faction_id,
		"complete faction round did not return control to the player")
	_check(turn_manager.current_phase == turn_manager.Phase.ORDERS,
		"next week did not wait in the player's strategy/orders phase")
	for squad: SquadState in ai_squads:
		_check(squad.movement_used,
			"AI squad did not receive a movement opportunity during its faction turn")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
