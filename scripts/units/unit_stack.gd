class_name UnitStack
extends RefCounted
## A single faction's units sitting in one region.

var faction_id: StringName
var units: Dictionary = {}  # unit_type_id (StringName) -> count (int)

func _init(owner_faction_id: StringName) -> void:
	faction_id = owner_faction_id

func total_count() -> int:
	var total := 0
	for count in units.values():
		total += count
	return total

func add_units(unit_type_id: StringName, count: int) -> void:
	units[unit_type_id] = units.get(unit_type_id, 0) + count

func apply_losses(losses: Dictionary) -> void:
	for unit_id in losses:
		var lost: int = losses[unit_id]
		var remaining: int = max(units.get(unit_id, 0) - lost, 0)
		if remaining <= 0:
			units.erase(unit_id)
		else:
			units[unit_id] = remaining

func is_empty() -> bool:
	return total_count() == 0
