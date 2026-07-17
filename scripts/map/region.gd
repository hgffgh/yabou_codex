class_name Region
extends RefCounted
## Runtime state for one region, wrapping its static RegionDef content.

var def: RegionDef
var owner_faction_id: StringName

func _init(region_def: RegionDef) -> void:
	def = region_def
	owner_faction_id = region_def.starting_owner_faction_id
