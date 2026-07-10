class_name RegionDef
extends Resource

@export var id: StringName
@export var display_name: String
@export var map_position: Vector2 = Vector2.ZERO
@export var neighbor_ids: Array[StringName] = []
@export var terrain_type: StringName = &"open_space"
@export var resource_yield: int = 5
@export var is_capital_slot: bool = false
@export var starting_owner_faction_id: StringName = &""
@export var defense_terrain_bonus: int = 0
