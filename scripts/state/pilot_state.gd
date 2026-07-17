class_name PilotState
extends RefCounted

var pilot_id: StringName = &""
var owner_faction_id: StringName = &""
var level: int = 1
var current_exp: int = 0
var injury_turns_remaining: int = 0
var assigned_unit_instance_id: StringName = &""
var available: bool = true
var joined: bool = true


func is_injured() -> bool:
	return injury_turns_remaining > 0


func is_assigned() -> bool:
	return not assigned_unit_instance_id.is_empty()


func to_dict() -> Dictionary:
	return {
		"pilot_id": pilot_id,
		"owner_faction_id": owner_faction_id,
		"level": level,
		"current_exp": current_exp,
		"injury_turns_remaining": injury_turns_remaining,
		"assigned_unit_instance_id": assigned_unit_instance_id,
		"available": available,
		"joined": joined,
	}


static func from_dict(data: Dictionary) -> PilotState:
	var state := PilotState.new()
	state.pilot_id = StringName(data.get("pilot_id", ""))
	state.owner_faction_id = StringName(data.get("owner_faction_id", ""))
	state.level = int(data.get("level", 1))
	state.current_exp = int(data.get("current_exp", 0))
	state.injury_turns_remaining = int(data.get("injury_turns_remaining", 0))
	state.assigned_unit_instance_id = StringName(data.get("assigned_unit_instance_id", ""))
	state.available = bool(data.get("available", true))
	state.joined = bool(data.get("joined", true))
	return state
