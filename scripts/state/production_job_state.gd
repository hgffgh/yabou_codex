class_name ProductionJobState
extends RefCounted

var job_id: StringName = &""
var unit_def_id: StringName = &""
var production_required: int = 0
var production_accumulated: int = 0
var funds_paid: int = 0
var materials_paid: int = 0
var registered_turn: int = 0


func to_dict() -> Dictionary:
	return {
		"job_id": job_id,
		"unit_def_id": unit_def_id,
		"production_required": production_required,
		"production_accumulated": production_accumulated,
		"funds_paid": funds_paid,
		"materials_paid": materials_paid,
		"registered_turn": registered_turn,
	}


static func from_dict(data: Dictionary) -> ProductionJobState:
	var job := ProductionJobState.new()
	job.job_id = StringName(data.get("job_id", ""))
	job.unit_def_id = StringName(data.get("unit_def_id", ""))
	job.production_required = int(data.get("production_required", 0))
	job.production_accumulated = int(data.get("production_accumulated", 0))
	job.funds_paid = int(data.get("funds_paid", 0))
	job.materials_paid = int(data.get("materials_paid", 0))
	job.registered_turn = int(data.get("registered_turn", 0))
	return job
