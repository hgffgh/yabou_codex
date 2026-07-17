class_name AchievementDef
extends Resource
## DATA_DEFINITION.md section 23. condition_type/condition_payload only
## cover what this codebase can actually evaluate today -- see
## GameState._achievement_condition_met for the exact supported set
## (faction_clear, difficulty_clear, turn_limit_clear, capture_count,
## treaty_count). research_three_tier5-style tiered-tech conditions are
## intentionally not modeled since tier 5 doesn't exist under the current
## flat, 2-tier placeholder tech system.

@export var id: StringName
@export var display_name_key: StringName
@export var description_key: StringName
@export var condition_type: StringName = &"always"
@export var condition_payload: Dictionary = {}
@export_range(0.0, 0.5, 0.01) var exp_bonus_pct: float = 0.05
@export var steam_achievement_id: StringName
