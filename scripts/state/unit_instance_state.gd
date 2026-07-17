class_name UnitInstanceState
extends RefCounted

var instance_id: StringName = &""
var unit_def_id: StringName = &""
var owner_faction_id: StringName = &""
var origin_faction_id: StringName = &""
var current_hp: int = 0
var current_en: int = 0
var pilot_id: StringName = &""
var squad_id: StringName = &""
var slot_index: int = -1
var condition: GameEnums.UnitCondition = GameEnums.UnitCondition.ACTIVE
var repair_turns_remaining: int = 0
var movement_used: bool = false
var captured: bool = false


func is_generic_pilot() -> bool:
	return pilot_id.is_empty()


func is_assigned_to_squad() -> bool:
	return not squad_id.is_empty() and slot_index >= 0 and slot_index < 5


func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"unit_def_id": unit_def_id,
		"owner_faction_id": owner_faction_id,
		"origin_faction_id": origin_faction_id,
		"current_hp": current_hp,
		"current_en": current_en,
		"pilot_id": pilot_id,
		"squad_id": squad_id,
		"slot_index": slot_index,
		"condition": condition,
		"repair_turns_remaining": repair_turns_remaining,
		"movement_used": movement_used,
		"captured": captured,
	}


static func from_dict(data: Dictionary) -> UnitInstanceState:
	var state := UnitInstanceState.new()
	state.instance_id = StringName(data.get("instance_id", ""))
	state.unit_def_id = StringName(data.get("unit_def_id", ""))
	state.owner_faction_id = StringName(data.get("owner_faction_id", ""))
	state.origin_faction_id = StringName(data.get("origin_faction_id", ""))
	state.current_hp = int(data.get("current_hp", 0))
	state.current_en = int(data.get("current_en", 0))
	state.pilot_id = StringName(data.get("pilot_id", ""))
	state.squad_id = StringName(data.get("squad_id", ""))
	state.slot_index = int(data.get("slot_index", -1))
	state.condition = int(data.get("condition", GameEnums.UnitCondition.ACTIVE))
	state.repair_turns_remaining = int(data.get("repair_turns_remaining", 0))
	state.movement_used = bool(data.get("movement_used", false))
	state.captured = bool(data.get("captured", false))
	return state
