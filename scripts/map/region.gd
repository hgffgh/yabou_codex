class_name Region
extends RefCounted
## Runtime state for one region, wrapping its static RegionDef content.

var def: RegionDef
var owner_faction_id: StringName
var stacks: Dictionary = {}  # faction_id -> UnitStack
var pending_production: Array = []  # Array of {unit_type_id: StringName, turns_remaining: int}
var pending_move_order: StringName = &""  # destination region id, empty = none

func _init(region_def: RegionDef) -> void:
	def = region_def
	owner_faction_id = region_def.starting_owner_faction_id

func get_or_create_stack(faction_id: StringName) -> UnitStack:
	if not stacks.has(faction_id):
		stacks[faction_id] = UnitStack.new(faction_id)
	return stacks[faction_id]

func occupying_faction_ids() -> Array:
	var ids := []
	for fid in stacks.keys():
		if not stacks[fid].is_empty():
			ids.append(fid)
	return ids
