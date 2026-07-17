extends SceneTree


func _initialize() -> void:
	await process_frame
	var game_state := root.get_node_or_null("GameState")
	if game_state == null:
		push_error("strategic_map_smoke_test: GameState autoload is unavailable")
		quit(1)
		return
	game_state.start_new_game(&"nova_republic")
	var result := change_scene_to_file("res://scenes/strategic_map/strategic_map.tscn")
	if result != OK:
		push_error("strategic_map_smoke_test: failed to load strategic map")
		quit(1)
		return
	await process_frame
	await process_frame
	print("strategic_map_smoke_test: scene loaded successfully")
	quit(0)
