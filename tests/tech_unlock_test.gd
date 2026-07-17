extends SceneTree
## DATA_DEFINITION.md section 15's TechDef.unlocks_unit_ids, now gating
## GameState.queue_production and AiController._best_affordable_unit via
## TechUnlock. Calls turn_manager.call("_run_ai_orders") rather than the
## bare AiController identifier -- see ai_squad_movement_test.gd's
## already-established compile-order-bug workaround.

var failures := PackedStringArray()
var game_state: Node
var turn_manager: Node


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	turn_manager = root.get_node_or_null("TurnManager")
	if game_state == null or turn_manager == null:
		push_error("tech_unlock_test: required autoload is unavailable")
		quit(1)
		return

	_test_unit_not_referenced_by_any_tech_is_always_unlocked()
	_test_gated_unit_requires_research()
	_test_queue_production_rejects_a_locked_unit()
	_test_queue_production_accepts_once_researched()
	_test_ai_skips_a_locked_unit_when_choosing_what_to_build()
	_finish()


func _test_unit_not_referenced_by_any_tech_is_always_unlocked() -> void:
	turn_manager.start_new_game(&"crimson_empire")
	var crimson: Faction = game_state.get_faction(&"crimson_empire")
	# No sample TechDef lists crimson_bastion in unlocks_unit_ids -- it
	## must remain unrestricted regardless of research state.
	_check(TechUnlock.is_unit_unlocked(crimson, &"crimson_bastion", game_state.master_data), "a unit no tech references should always be unlocked")


func _test_gated_unit_requires_research() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var nova: Faction = game_state.get_faction(&"nova_republic")
	_check(not TechUnlock.is_unit_unlocked(nova, &"nova_vanguard", game_state.master_data), "nova_vanguard should be locked before nova_hull_foundation is researched")
	_check(TechUnlock.is_unit_unlocked(nova, &"nova_scout", game_state.master_data), "nova_scout is not referenced by any tech and should stay unlocked")

	var hull_node := _find_node_by_tech(nova, &"nova_hull_foundation")
	_check(hull_node != null, "setup: nova_hull_foundation should always be in nova's generated tree")
	if hull_node == null:
		return
	hull_node.researched = true
	_check(TechUnlock.is_unit_unlocked(nova, &"nova_vanguard", game_state.master_data), "nova_vanguard should unlock once nova_hull_foundation is researched")


func _test_queue_production_rejects_a_locked_unit() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var errors: PackedStringArray = (game_state.queue_production(&"nova_republic", &"nova_shipyard_production", &"nova_vanguard") as Dictionary).errors
	_check(not errors.is_empty(), "queue_production should reject nova_vanguard before its unlocking tech is researched")


func _test_queue_production_accepts_once_researched() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var nova: Faction = game_state.get_faction(&"nova_republic")
	var hull_node := _find_node_by_tech(nova, &"nova_hull_foundation")
	if hull_node != null:
		hull_node.researched = true
	var result: Dictionary = game_state.queue_production(&"nova_republic", &"nova_shipyard_production", &"nova_vanguard")
	_check((result.errors as PackedStringArray).is_empty(), "queue_production should accept nova_vanguard once its unlocking tech is researched: %s" % [result.errors])


func _test_ai_skips_a_locked_unit_when_choosing_what_to_build() -> void:
	turn_manager.start_new_game(&"crimson_empire")  # nova_republic is AI-controlled
	var nova: Faction = game_state.get_faction(&"nova_republic")
	nova.funds = 1000000
	nova.materials = 1000000
	turn_manager.call("_run_ai_orders")
	var facility_ids: Array[StringName] = game_state.production_facility_ids_for_region(&"nova_shipyard")
	_check(not facility_ids.is_empty(), "setup: nova_shipyard should have a production facility")
	if facility_ids.is_empty():
		return
	var queue := game_state.campaign_runtime.production_queues_by_facility_id.get(facility_ids[0]) as ProductionQueueState
	_check(queue != null and not queue.job_ids.is_empty(), "setup: the AI should have queued something with ample funds")
	if queue == null or queue.job_ids.is_empty():
		return
	var job := game_state.campaign_runtime.production_jobs_by_id.get(queue.job_ids[0]) as ProductionJobState
	_check(job != null and job.unit_def_id == &"nova_scout", "the AI should build the still-unlocked nova_scout instead of the locked nova_vanguard while nothing is researched yet")


func _find_node_by_tech(faction: Faction, tech_id: StringName) -> GeneratedTechNodeState:
	for node_id: Variant in faction.generated_tech_nodes:
		var node := faction.generated_tech_nodes[node_id] as GeneratedTechNodeState
		if node.tech_id == tech_id:
			return node
	return null


func _finish() -> void:
	if failures.is_empty():
		print("tech_unlock_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("tech_unlock_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
