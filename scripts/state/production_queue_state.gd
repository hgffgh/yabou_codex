class_name ProductionQueueState
extends RefCounted

var facility_instance_id: StringName = &""
var job_ids: Array[StringName] = []


func to_dict() -> Dictionary:
	return {
		"facility_instance_id": facility_instance_id,
		"job_ids": job_ids.duplicate(),
	}


static func from_dict(data: Dictionary) -> ProductionQueueState:
	var queue := ProductionQueueState.new()
	queue.facility_instance_id = StringName(data.get("facility_instance_id", ""))
	var values: Variant = data.get("job_ids", [])
	if values is Array:
		for value: Variant in values:
			queue.job_ids.append(StringName(value))
	return queue
