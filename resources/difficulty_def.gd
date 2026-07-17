class_name DifficultyDef
extends Resource
## DATA_DEFINITION.md section 5. Scales non-player ("enemy") factions only;
## the player's own income/units/combat stats are never touched by this.
## Defaults match the Normal preset, so a DifficultyDef.new() fallback (used
## when a save or difficulty_id fails to resolve one) is already neutral.

@export var id: StringName = &"normal"
@export var enemy_income_multiplier: float = 1.0
@export var enemy_hp_multiplier: float = 1.0
@export var enemy_firepower_multiplier: float = 1.0
@export var enemy_accuracy_add: int = 0
@export var enemy_evasion_add: int = 0
## Schema-only for now (DATA_DEFINITION.md section 5): there is no AI
## behavior-profile system to select between yet, so this doesn't drive
## anything -- AiController is a single, non-parameterized strategy.
@export var ai_profile_id: StringName = &"normal"
