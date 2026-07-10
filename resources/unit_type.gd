class_name UnitType
extends Resource

@export var id: StringName
@export var display_name: String
@export var icon: Texture2D
@export_enum("Ground", "Space", "Orbital") var domain: String = "Space"
@export var build_cost: int = 10
@export var build_time_turns: int = 1
@export var attack: int = 1
@export var defense: int = 1
@export var hp: int = 10
@export var move_range: int = 1
@export var tech_tier_required: int = 0
@export var terrain_bonus: Dictionary = {}
@export var vignette_sprite: Texture2D
