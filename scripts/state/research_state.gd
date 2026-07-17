class_name ResearchState
extends RefCounted
## DATA_DEFINITION.md section 15.2. At most one per faction at a time
## (Faction.current_research, null when nothing is in progress). Cannot be
## cancelled, paused, or switched once started (STRATEGY_DETAIL_
## SPECIFICATION.md section 7.1).

var node_id: StringName = &""
var funds_paid: int = 0
var turns_remaining: int = 0
var started_turn: int = 0


func to_dict() -> Dictionary:
	return {
		"node_id": node_id,
		"funds_paid": funds_paid,
		"turns_remaining": turns_remaining,
		"started_turn": started_turn,
	}


static func from_dict(data: Dictionary) -> ResearchState:
	var state := ResearchState.new()
	state.node_id = StringName(data.get("node_id", ""))
	state.funds_paid = int(data.get("funds_paid", 0))
	state.turns_remaining = int(data.get("turns_remaining", 0))
	state.started_turn = int(data.get("started_turn", 0))
	return state
