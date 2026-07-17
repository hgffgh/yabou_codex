class_name PilotSkillDef
extends Resource

@export var id: StringName
@export var display_name_key: StringName
@export var description_key: StringName
@export_range(1, 40, 1) var unlock_level: int = 1
@export var leader_only: bool = false
@export var condition_type: StringName = &"always"
@export var condition_value: float = 0.0
@export var modifiers: Dictionary = {}
@export var action_skill_id: StringName
