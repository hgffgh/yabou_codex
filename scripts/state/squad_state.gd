class_name SquadState
extends RefCounted

const SLOT_COUNT := GameConstants.MAX_UNITS_PER_SQUAD

var squad_id: StringName = &""
var display_name: String = ""
var owner_faction_id: StringName = &""
var region_id: StringName = &""
var unit_instance_ids: Array[StringName] = []
var slot_unit_ids: Array[StringName] = []
var leader_pilot_id: StringName = &""
var battle_policy: GameEnums.BattlePolicy = GameEnums.BattlePolicy.BALANCED
var movement_used: bool = false
var move_origin_region_id: StringName = &""
var planned_destination_region_id: StringName = &""
var intel_revision: int = 0


func _init() -> void:
	_reset_empty_slots()


func is_generic_pilot_leader() -> bool:
	return leader_pilot_id.is_empty()


func assign_unit(unit_instance_id: StringName, target_slot_index: int) -> bool:
	if unit_instance_id.is_empty() or not _is_valid_slot(target_slot_index):
		return false
	if not slot_unit_ids[target_slot_index].is_empty() and slot_unit_ids[target_slot_index] != unit_instance_id:
		return false

	var current_slot := get_slot_index(unit_instance_id)
	if current_slot == target_slot_index:
		return false
	if current_slot >= 0:
		slot_unit_ids[current_slot] = &""

	slot_unit_ids[target_slot_index] = unit_instance_id
	_rebuild_unit_instance_ids()
	intel_revision += 1
	return true


func remove_unit(unit_instance_id: StringName) -> bool:
	var current_slot := get_slot_index(unit_instance_id)
	if current_slot < 0:
		return false

	slot_unit_ids[current_slot] = &""
	_rebuild_unit_instance_ids()
	intel_revision += 1
	return true


func contains_unit(unit_instance_id: StringName) -> bool:
	return get_slot_index(unit_instance_id) >= 0


func get_unit_at_slot(target_slot_index: int) -> StringName:
	if not _is_valid_slot(target_slot_index):
		return &""
	return slot_unit_ids[target_slot_index]


func get_slot_index(unit_instance_id: StringName) -> int:
	if unit_instance_id.is_empty():
		return -1
	for index in range(slot_unit_ids.size()):
		if slot_unit_ids[index] == unit_instance_id:
			return index
	return -1


func to_dict() -> Dictionary:
	return {
		"squad_id": squad_id,
		"display_name": display_name,
		"owner_faction_id": owner_faction_id,
		"region_id": region_id,
		"unit_instance_ids": unit_instance_ids.duplicate(),
		"slot_unit_ids": slot_unit_ids.duplicate(),
		"leader_pilot_id": leader_pilot_id,
		"battle_policy": battle_policy,
		"movement_used": movement_used,
		"move_origin_region_id": move_origin_region_id,
		"planned_destination_region_id": planned_destination_region_id,
		"intel_revision": intel_revision,
	}


static func from_dict(data: Dictionary) -> SquadState:
	var state := SquadState.new()
	state.squad_id = StringName(data.get("squad_id", ""))
	state.display_name = str(data.get("display_name", ""))
	state.owner_faction_id = StringName(data.get("owner_faction_id", ""))
	state.region_id = StringName(data.get("region_id", ""))
	state.slot_unit_ids = _string_name_array(data.get("slot_unit_ids", []))
	if state.slot_unit_ids.is_empty():
		state._reset_empty_slots()
	state.unit_instance_ids = _string_name_array(data.get("unit_instance_ids", []))
	state.leader_pilot_id = StringName(data.get("leader_pilot_id", ""))
	state.battle_policy = int(data.get("battle_policy", GameEnums.BattlePolicy.BALANCED))
	state.movement_used = bool(data.get("movement_used", false))
	state.move_origin_region_id = StringName(data.get("move_origin_region_id", ""))
	state.planned_destination_region_id = StringName(data.get("planned_destination_region_id", ""))
	state.intel_revision = int(data.get("intel_revision", 0))
	return state


static func _string_name_array(value: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if value is Array:
		for item in value:
			result.append(StringName(item))
	return result


func _reset_empty_slots() -> void:
	slot_unit_ids.clear()
	for _index in range(SLOT_COUNT):
		slot_unit_ids.append(&"")


func _rebuild_unit_instance_ids() -> void:
	unit_instance_ids.clear()
	for unit_instance_id in slot_unit_ids:
		if not unit_instance_id.is_empty():
			unit_instance_ids.append(unit_instance_id)


func _is_valid_slot(target_slot_index: int) -> bool:
	return target_slot_index >= 0 and target_slot_index < SLOT_COUNT and slot_unit_ids.size() == SLOT_COUNT
