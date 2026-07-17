class_name AiProfileDef
extends Resource
## DATA_DEFINITION.md section 5's `DifficultyDef.ai_profile_id` selects one
## of these to drive AiController's behavior knobs. Defaults match the
## Normal preset (the current, pre-profile-system constants AiController
## used to hardcode), so a fallback AiProfileDef.new() (used when a
## difficulty's ai_profile_id fails to resolve one) is already neutral.

@export var id: StringName = &"normal"
## Multiplies AiController's willingness to attack: divides the
## power-ratio threshold a squad needs before considering a hostile
## neighbor, so > 1.0 attacks at a lower relative power advantage.
@export_range(0.1, 3.0, 0.05) var aggression_multiplier: float = 1.0
## Replaces AiController.MAX_QUEUE_LENGTH: how many production jobs a
## facility is allowed to queue ahead before the AI stops adding more.
@export_range(1, 10, 1) var production_queue_length: int = 3
## Replaces AiController.RESEARCH_RESERVE: funds that must remain after
## paying for research before the AI will start it. Lower reserve means
## the AI researches more eagerly relative to its own income.
@export_range(0, 5000, 50) var research_reserve: int = 300
