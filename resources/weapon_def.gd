class_name WeaponDef
extends Resource

@export var id: StringName
@export var display_name_key: StringName
@export var weapon_class: GameEnums.WeaponClass = GameEnums.WeaponClass.STANDARD
@export var damage_attribute: GameEnums.DamageAttribute = GameEnums.DamageAttribute.BALLISTIC
@export var action_type: GameEnums.ActionType = GameEnums.ActionType.ATTACK
@export var total_power: int = 300
@export_range(1, 10, 1) var hit_count: int = 1
@export var penetration: int = 100
@export_range(0, 100, 1) var base_accuracy_pct: int = 80
@export_range(0, 100, 1) var base_critical_pct: int = 5
@export var en_cost: int = 30
@export var post_action_delay_sec: float = 2.0
@export var min_range_m: float = 0.0
@export var max_range_m: float = 150.0
@export var target_rule: GameEnums.TargetRule = GameEnums.TargetRule.FRONT
@export var target_pattern: GameEnums.TargetPattern = GameEnums.TargetPattern.SINGLE
@export var can_target_front: bool = true
@export var can_target_rear: bool = true
@export var ignores_cover: bool = false
@export var is_giftable: bool = true
