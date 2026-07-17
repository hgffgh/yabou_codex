extends SceneTree

var failures := PackedStringArray()
var game_state: Node
var turn_manager: Node
const TEST_SLOTS := [90, 91]


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	turn_manager = root.get_node_or_null("TurnManager")
	if game_state == null or turn_manager == null:
		push_error("save_load_test: required autoload is unavailable")
		quit(1)
		return

	_test_save_load_round_trips_state()
	_test_save_rejected_outside_orders_phase()
	_test_list_save_slots_reflects_disk()
	_test_load_rejects_missing_or_corrupt_slot()
	_cleanup_test_slot_files()
	_finish()


## Uses a high slot number (90) unlikely to collide with a real save on a
## developer's machine, and always cleans up after itself.
func _test_save_load_round_trips_state() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var faction: Faction = game_state.get_faction(&"nova_republic")
	faction.funds += 12345
	faction.materials += 678
	var funds_at_save := faction.funds
	var materials_at_save := faction.materials
	game_state.set_region_owner(&"crimson_border", &"nova_republic")
	var rollout: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"nova_capital")
	var unit_id: StringName = rollout.unit.instance_id
	var unit_count_at_save: int = game_state.campaign_runtime.units_by_id.size()

	var save_errors: PackedStringArray = turn_manager.save_game(TEST_SLOTS[0])
	_check(save_errors.is_empty(), "save_game failed: %s" % save_errors)

	# Mutate further after saving, so a successful load must revert this.
	faction.funds = 1
	faction.materials = 1
	game_state.set_region_owner(&"crimson_border", &"crimson_empire")
	game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"nova_capital")

	var load_errors: PackedStringArray = turn_manager.load_game(TEST_SLOTS[0])
	_check(load_errors.is_empty(), "load_game failed: %s" % load_errors)

	var reloaded_faction: Faction = game_state.get_faction(&"nova_republic")
	_check(reloaded_faction.funds == funds_at_save, "funds did not round-trip through save/load, got %d expected %d" % [reloaded_faction.funds, funds_at_save])
	_check(reloaded_faction.materials == materials_at_save, "materials did not round-trip through save/load, got %d expected %d" % [reloaded_faction.materials, materials_at_save])
	_check(game_state.get_region(&"crimson_border").owner_faction_id == &"nova_republic",
		"region ownership did not round-trip through save/load")
	_check(game_state.campaign_runtime.units_by_id.size() == unit_count_at_save,
		"campaign_runtime unit count did not round-trip (post-save rollout should have been undone)")
	_check(game_state.campaign_runtime.get_unit(unit_id) != null,
		"the unit that existed at save time should still resolve after load")
	_check(turn_manager.active_faction_id == &"nova_republic" and turn_manager.current_phase == turn_manager.Phase.ORDERS,
		"load should restore the player's ORDERS phase")

	var validation_errors: PackedStringArray = game_state.campaign_runtime.validate(game_state.master_data, game_state.region_defs)
	_check(validation_errors.is_empty(), "reloaded campaign state failed validation: %s" % validation_errors)


func _test_save_rejected_outside_orders_phase() -> void:
	turn_manager.start_new_game(&"nova_republic")
	_check(turn_manager.can_save_now(), "setup should start in a savable state")

	turn_manager.is_resolving_turn = true
	_check(not turn_manager.can_save_now(), "saving mid-resolution should not be allowed")
	var errors: PackedStringArray = turn_manager.save_game(TEST_SLOTS[1])
	_check(not errors.is_empty(), "save_game should refuse to save while is_resolving_turn is true")
	turn_manager.is_resolving_turn = false

	turn_manager.current_phase = turn_manager.Phase.COMBAT
	_check(not turn_manager.can_save_now(), "saving outside Phase.ORDERS should not be allowed")
	turn_manager.current_phase = turn_manager.Phase.ORDERS


func _test_list_save_slots_reflects_disk() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var save_errors: PackedStringArray = turn_manager.save_game(TEST_SLOTS[0])
	_check(save_errors.is_empty(), "save_game failed: %s" % save_errors)

	var slots: Array[Dictionary] = turn_manager.list_save_slots()
	var found: Dictionary = {}
	for entry: Dictionary in slots:
		if int(entry.slot) == TEST_SLOTS[0]:
			found = entry
	_check(not found.is_empty(), "list_save_slots did not report the just-written slot")
	if not found.is_empty():
		_check(int(found.turn_number) == 1, "listed slot reported the wrong turn_number")
		_check(StringName(found.player_faction_id) == &"nova_republic", "listed slot reported the wrong player_faction_id")


func _test_load_rejects_missing_or_corrupt_slot() -> void:
	var missing_errors: PackedStringArray = turn_manager.load_game(89)
	_check(not missing_errors.is_empty(), "loading a nonexistent slot should fail, not silently no-op")

	var path := "user://saves/slot_%02d.json" % TEST_SLOTS[1]
	DirAccess.make_dir_recursive_absolute("user://saves/")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{ not valid json ")
	file.close()
	var corrupt_errors: PackedStringArray = turn_manager.load_game(TEST_SLOTS[1])
	_check(not corrupt_errors.is_empty(), "loading corrupt JSON should fail cleanly instead of crashing")


func _cleanup_test_slot_files() -> void:
	for slot in TEST_SLOTS + [89]:
		var path := "user://saves/slot_%02d.json" % slot
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _finish() -> void:
	if failures.is_empty():
		print("save_load_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("save_load_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
