class_name SupportSkillDef
extends Resource

@export var id: StringName
@export var display_name_key: StringName
@export var action_type: GameEnums.ActionType = GameEnums.ActionType.REPAIR
@export var priority: int = 0
@export var trigger_resource: StringName = &"hp_pct"
@export_range(0.0, 1.0, 0.01) var trigger_threshold_pct: float = 0.5
@export var target_rule: GameEnums.SupportTargetRule = GameEnums.SupportTargetRule.LOW_HP_RATIO
@export var target_pattern: GameEnums.TargetPattern = GameEnums.TargetPattern.SINGLE
@export var fixed_repair: int = 0
@export_range(0.0, 1.0, 0.01) var max_hp_repair_pct: float = 0.0
@export var transfer_en: int = 0
@export var en_cost: int = 0
@export var post_action_delay_sec: float = 0.0
@export var can_target_self: bool = false
