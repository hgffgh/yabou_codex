extends SceneTree

const GAME_STATE_SCRIPT := preload("res://autoload/game_state.gd")

var _failures: PackedStringArray = []
var _game_state: Node


func _initialize() -> void:
	_game_state = GAME_STATE_SCRIPT.new()
	_game_state._load_static_data()
	_game_state.start_new_game(&"nova_republic")
	_test_registration_completion_and_no_dual_write()
	_test_facility_loss_clears_without_refund()
	_game_state.free()
	_game_state = null
	if _failures.is_empty():
		print("production_integration_test: all checks passed")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("production_integration_test: %s" % failure)
		quit(1)


func _test_registration_completion_and_no_dual_write() -> void:
	var faction: Faction = _game_state.get_faction(&"nova_republic")
	var region: Region = _game_state.get_region(&"nova_shipyard")
	var facilities: Array[StringName] = _game_state.production_facility_ids_for_region(region.def.id)
	_check(facilities == [&"nova_shipyard_production"], "nova shipyard production facility did not resolve")
	var funds_before := faction.funds
	var materials_before := faction.materials
	var runtime_units_before: int = _game_state.campaign_runtime.units_by_id.size()
	var runtime_squads_before: int = _game_state.campaign_runtime.squads_by_id.size()
	var queued: Dictionary = _game_state.queue_production(
		&"nova_republic", facilities[0], &"nova_scout"
	)
	_check(queued.errors.is_empty(), "valid integrated production registration failed")
	_check(faction.funds == funds_before - 300, "funds were not paid at registration")
	_check(faction.materials == materials_before - 200, "materials were not paid at registration")
	var completed: Array[Dictionary] = _game_state.advance_region_production(region.def.id)
	_check(completed.size() == 1, "completed production did not roll out exactly one unit")
	_check(_game_state.campaign_runtime.units_by_id.size() == runtime_units_before + 1, "rollout unit was not registered")
	_check(_game_state.campaign_runtime.squads_by_id.size() == runtime_squads_before + 1, "rollout squad was not registered")
	completed = _game_state.advance_region_production(region.def.id)
	_check(completed.is_empty(), "completed job rolled out more than once")
	_check(_game_state.campaign_runtime.units_by_id.size() == runtime_units_before + 1, "second advance duplicated the unit")


func _test_facility_loss_clears_without_refund() -> void:
	var faction: Faction = _game_state.get_faction(&"nova_republic")
	var facility_id := &"nova_shipyard_production"
	var funds_before := faction.funds
	var materials_before := faction.materials
	var queued: Dictionary = _game_state.queue_production(
		&"nova_republic", facility_id, &"nova_vanguard"
	)
	_check(queued.errors.is_empty(), "second integrated production registration failed")
	var paid_funds := faction.funds
	var paid_materials := faction.materials
	_check(paid_funds == funds_before - 600, "standard unit funds cost was incorrect")
	_check(paid_materials == materials_before - 400, "standard unit materials cost was incorrect")
	_game_state.advance_region_production(&"nova_shipyard")
	_check(
		_game_state.campaign_runtime.production_jobs_by_id.size() == 1,
		"partially completed job was not retained",
	)
	_game_state.set_region_owner(&"nova_shipyard", &"crimson_empire")
	_check(
		_game_state.campaign_runtime.production_jobs_by_id.is_empty(),
		"facility loss retained production jobs",
	)
	_check(
		_game_state.campaign_runtime.production_queues_by_facility_id.is_empty(),
		"facility loss retained its queue",
	)
	_check(faction.funds == paid_funds, "facility loss refunded funds")
	_check(faction.materials == paid_materials, "facility loss refunded materials")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
