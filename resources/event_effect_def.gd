class_name EventEffectDef
extends Resource
## EVENT_DETAIL_SPECIFICATION.md section 5 / DATA_DEFINITION.md section 22's
## "効果ID" (choice_entries/default_effect_ids reference these by id).
## DATA_DEFINITION.md doesn't name a distinct effect-definition resource, but
## an effect needs to be authorable as data (not code) the same way
## AchievementDef.condition_type/condition_payload is -- see
## EventEffectApplier for the exact payload shape each effect_type expects.

@export var id: StringName
@export var effect_type: GameEnums.EventEffectType = GameEnums.EventEffectType.EVENT_FLAG
@export var payload: Dictionary = {}
