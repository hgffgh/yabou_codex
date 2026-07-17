class_name FactionDef
extends Resource

@export var id: StringName
@export var display_name: String
@export var color: Color = Color.WHITE
@export var emblem: Texture2D
@export var is_ai_controlled: bool = true
@export var starting_region_id: StringName
@export var starting_resources: int = 100
@export var starting_funds: int = 3000
@export var starting_materials: int = 2000
@export var tech_bonus: Dictionary = {}
@export var ai_aggression: float = 0.5
@export var starting_relations: Dictionary = {}
