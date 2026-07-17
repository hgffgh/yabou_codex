class_name GeneratedTechNodeState
extends RefCounted
## DATA_DEFINITION.md section 15.1. One instance per node in a single
## faction's campaign-generated tech tree (TechTreeGenerator).

var node_id: StringName = &""
var tech_id: StringName = &""
var tier: int = 1
## Empty for a gifted node -- see Diplomacy.gift_tech and
## TurnManager._node_prerequisites_met for the special "any researched node
## one tier down" rule that applies instead in that case.
var prerequisite_node_ids: Array[StringName] = []
var gifted: bool = false
var researched: bool = false


func to_dict() -> Dictionary:
	return {
		"node_id": node_id,
		"tech_id": tech_id,
		"tier": tier,
		"prerequisite_node_ids": prerequisite_node_ids.duplicate(),
		"gifted": gifted,
		"researched": researched,
	}


static func from_dict(data: Dictionary) -> GeneratedTechNodeState:
	var state := GeneratedTechNodeState.new()
	state.node_id = StringName(data.get("node_id", ""))
	state.tech_id = StringName(data.get("tech_id", ""))
	state.tier = int(data.get("tier", 1))
	var prereq_value: Variant = data.get("prerequisite_node_ids", [])
	if prereq_value is Array:
		for id_value: Variant in prereq_value as Array:
			state.prerequisite_node_ids.append(StringName(id_value))
	state.gifted = bool(data.get("gifted", false))
	state.researched = bool(data.get("researched", false))
	return state
