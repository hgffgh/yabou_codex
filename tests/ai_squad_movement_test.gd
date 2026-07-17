extends SceneTree

var failures := PackedStringArray()
var game_state: Node
var turn_manager: Node


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	turn_manager = root.get_node_or_null("TurnManager")
	if game_state == null or turn_manager == null:
		push_error("ai_squad_movement_test: required autoload is unavailable")
		quit(1)
		return
	game_state.start_new_game(&"nova_republic")
	_test_ai_issues_squad_order()
	if failures.is_empty():
		print("ai_squad_movement_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("ai_squad_movement_test: %s" % failure)
		quit(1)


func _test_ai_issues_squad_order() -> void:
	var squads: Array[SquadState] = game_state.campaign_runtime.get_squads_in_region(
		&"crimson_capital", &"crimson_empire"
	)
	_check(not squads.is_empty(), "new game did not seed a crimson squad")
	if squads.is_empty():
		return
	var squad := squads[0] as SquadState
	# Place the squad at the contested border to isolate attack selection from
	# the multi-turn friendly-region advance behavior.
	squad.region_id = &"crimson_border"
	turn_manager.call("_run_ai_orders")
	_check(
		squad.planned_destination_region_id == &"nova_border",
		"AI did not plan the adjacent hostile destination by squad ID",
	)
	_check(squad.movement_used, "AI squad order did not consume movement")
	var first_destination := squad.planned_destination_region_id
	turn_manager.call("_run_ai_orders")
	_check(
		squad.planned_destination_region_id == first_destination,
		"a second AI pass replaced an already committed squad order",
	)
	game_state.campaign_runtime.execute_planned_squad_movements()
	_check(squad.region_id == &"nova_border", "movement phase did not execute the AI squad order")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
