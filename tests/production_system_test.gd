extends SceneTree

var _failures: PackedStringArray = []
var _registry := MasterDataRegistry.new()
var _regions := {&"nova_capital": true}


func _initialize() -> void:
	_registry.load_all()
	_test_fifo_and_same_turn_overflow()
	_test_unused_power_is_not_saved()
	_test_invalid_registration_is_atomic()
	_test_clear_facility_without_refund_state()
	_test_round_trip_and_counter()
	if _failures.is_empty():
		print("production_system_test: all checks passed")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("production_system_test: %s" % failure)
		quit(1)


func _test_fifo_and_same_turn_overflow() -> void:
	var state := CampaignRuntimeState.new()
	var first := state.queue_production(&"factory_a", &"nova_scout", 300, 200, 1, 100).job as ProductionJobState
	var second := state.queue_production(&"factory_a", &"nova_vanguard", 600, 400, 1, 200).job as ProductionJobState
	var third := state.queue_production(&"factory_a", &"nova_scout", 300, 200, 1, 100).job as ProductionJobState
	_check(first.job_id == &"production_job_00000001", "first production job ID is not deterministic")
	var completed := state.advance_production(&"factory_a", 350)
	_check(completed.size() == 2, "production power did not complete two FIFO jobs")
	if completed.size() == 2:
		_check(completed[0] == first and completed[1] == second, "completed jobs were not returned in FIFO order")
	_check(third.production_accumulated == 50, "same-turn excess production did not flow to the next job")
	_check(not state.production_jobs_by_id.has(first.job_id) and not state.production_jobs_by_id.has(second.job_id), "completed jobs remain registered")
	var queue := state.production_queues_by_facility_id[&"factory_a"] as ProductionQueueState
	_check(queue.job_ids == [third.job_id], "queue did not retain exactly the incomplete tail job")
	_check(state.validate(_registry, _regions).is_empty(), "valid production graph failed validation")


func _test_unused_power_is_not_saved() -> void:
	var state := CampaignRuntimeState.new()
	state.queue_production(&"factory_a", &"nova_scout", 300, 200, 1, 100)
	state.advance_production(&"factory_a", 200)
	var next := state.queue_production(&"factory_a", &"nova_scout", 300, 200, 2, 100).job as ProductionJobState
	_check(next.production_accumulated == 0, "unused production power was saved across registrations/turns")
	_check(state.advance_production(&"factory_a", 0).is_empty(), "zero power unexpectedly completed a job")
	_check(next.production_accumulated == 0, "zero-power turn changed production progress")


func _test_invalid_registration_is_atomic() -> void:
	var state := CampaignRuntimeState.new()
	var before := state.to_dict()
	for args: Array in [
		[&"", &"nova_scout", 300, 200, 1, 100],
		[&"factory_a", &"", 300, 200, 1, 100],
		[&"factory_a", &"nova_scout", -1, 200, 1, 100],
		[&"factory_a", &"nova_scout", 300, -1, 1, 100],
		[&"factory_a", &"nova_scout", 300, 200, -1, 100],
		[&"factory_a", &"nova_scout", 300, 200, 1, 0],
	]:
		var result := state.queue_production(args[0], args[1], args[2], args[3], args[4], args[5])
		_check(result.job == null and not result.errors.is_empty(), "invalid production registration was accepted")
		_check(state.to_dict() == before, "failed production registration mutated state or serial")


func _test_clear_facility_without_refund_state() -> void:
	var state := CampaignRuntimeState.new()
	var first := state.queue_production(&"factory_a", &"nova_vanguard", 600, 400, 1, 200).job as ProductionJobState
	var second := state.queue_production(&"factory_a", &"nova_scout", 300, 200, 1, 100).job as ProductionJobState
	state.advance_production(&"factory_a", 50)
	var removed := state.clear_production_facility(&"factory_a")
	_check(removed == [first, second], "facility loss did not return paid jobs in FIFO order")
	_check(state.production_jobs_by_id.is_empty() and state.production_queues_by_facility_id.is_empty(), "facility loss retained its queue or jobs")
	_check(first.funds_paid == 600 and first.materials_paid == 400, "facility clear changed paid-cost snapshots")
	_check(state.clear_production_facility(&"factory_a").is_empty(), "facility queue was cleared twice")


func _test_round_trip_and_counter() -> void:
	var state := CampaignRuntimeState.new()
	var first := state.queue_production(&"factory_b", &"nova_vanguard", 600, 400, 3, 200).job as ProductionJobState
	state.advance_production(&"factory_b", 75)
	state.queue_production(&"factory_b", &"nova_scout", 300, 200, 3, 100)
	var saved := state.to_dict()
	_check(not _contains_object(saved), "production save dictionary contains an Object")
	var decoded: Variant = JSON.parse_string(JSON.stringify(saved))
	var result := CampaignRuntimeState.from_dict(decoded)
	_check(result.errors.is_empty(), "production state failed JSON restore: %s" % result.errors)
	var restored := result.state as CampaignRuntimeState
	_check(restored.to_dict() == saved, "production JSON round trip changed state")
	var restored_first := restored.production_jobs_by_id[first.job_id] as ProductionJobState
	_check(restored_first.production_accumulated == 75, "production progress was not restored")
	var next := restored.queue_production(&"factory_b", &"nova_scout", 300, 200, 4, 100).job as ProductionJobState
	_check(next.job_id == &"production_job_00000003", "restored production counter reused an ID")
	_check(restored.validate(_registry, _regions).is_empty(), "restored production graph failed validation")
	restored.reset()
	_check(restored.production_jobs_by_id.is_empty() and restored.production_queues_by_facility_id.is_empty(), "reset retained production state")
	_check(restored.next_production_job_serial == 1, "reset retained production job serial")


func _contains_object(value: Variant) -> bool:
	if value is Object:
		return true
	if value is Dictionary:
		for key: Variant in value:
			if _contains_object(key) or _contains_object(value[key]):
				return true
	elif value is Array:
		for item: Variant in value:
			if _contains_object(item):
				return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
