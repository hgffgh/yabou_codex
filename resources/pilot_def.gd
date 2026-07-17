class_name PilotDef
extends Resource

@export var id: StringName
@export var display_name_key: StringName
@export var description_key: StringName
@export var faction_id: StringName
@export var portrait: Texture2D
@export_range(1, 50, 1) var initial_level: int = 1
@export_range(0, 200, 1) var initial_shooting: int = 100
@export_range(0, 200, 1) var initial_melee: int = 100
@export_range(0, 200, 1) var initial_defense: int = 100
@export_range(0, 200, 1) var initial_reaction: int = 100
@export_range(0, 200, 1) var initial_command: int = 100
@export_range(0, 3, 1) var growth_shooting: int = 0
@export_range(0, 3, 1) var growth_melee: int = 0
@export_range(0, 3, 1) var growth_defense: int = 0
@export_range(0, 3, 1) var growth_reaction: int = 0
@export_range(0, 3, 1) var growth_command: int = 0
@export var skill_ids: Array[StringName] = []
@export var preferred_unit_ids: Array[StringName] = []
@export var poor_unit_ids: Array[StringName] = []
@export var exclusive_unit_ids: Array[StringName] = []
@export var relationship_tags: Array[StringName] = []
