extends SceneTree
## Regression test for a real bug reported live: after ending a turn, the
## strategic map's end-turn button stayed showing "AI行動中" (disabled)
## forever, even though TurnManager.commit_turn() had already fully
## resolved and handed control back to the player. Root cause: on the
## turn-wraparound path, TurnManager.commit_turn() called
## _begin_faction_turn() (which emits active_faction_changed/phase_changed
## synchronously, both of which StrategicMap._update_turn_ui() listens to)
## *before* setting is_resolving_turn back to false, so that first
## post-transition UI refresh read the still-true value and disabled the
## button with nothing left to ever refresh it again. Fixed by flipping
## is_resolving_turn to false before calling _begin_faction_turn().

var game_state: Node
var turn_manager: Node

func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	turn_manager = root.get_node_or_null("TurnManager")
	if game_state == null or turn_manager == null:
		push_error("turn_ui_refresh_test: required autoload is unavailable")
		quit(1)
		return

	turn_manager.start_new_game(&"nova_republic")
	var result := change_scene_to_file("res://scenes/strategic_map/strategic_map.tscn")
	if result != OK:
		push_error("turn_ui_refresh_test: failed to load strategic map")
		quit(1)
		return
	await process_frame
	await process_frame

	turn_manager.commit_turn()
	var frame_count := 0
	while frame_count < 300 and turn_manager.is_resolving_turn:
		await process_frame
		frame_count += 1
	await process_frame

	var failures := PackedStringArray()
	if turn_manager.is_resolving_turn:
		failures.append("commit_turn() did not finish resolving within 300 frames")
	var button := _find_end_turn_button(current_scene)
	if button == null:
		failures.append("could not find the end-turn button in the loaded scene")
	else:
		if button.disabled:
			failures.append("end-turn button stayed disabled after the turn cycle completed")
		if button.text != "行動終了":
			failures.append("end-turn button text should read 行動終了, not %s" % button.text)

	if failures.is_empty():
		print("turn_ui_refresh_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("turn_ui_refresh_test: %s" % failure)
		quit(1)

func _find_end_turn_button(node: Node) -> Button:
	if node is Button and (node as Button).text in ["行動終了", "AI行動中"]:
		return node
	for child in node.get_children():
		var found := _find_end_turn_button(child)
		if found != null:
			return found
	return null
