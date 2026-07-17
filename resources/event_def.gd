class_name EventDef
extends Resource
## DATA_DEFINITION.md section 22 / EVENT_DETAIL_SPECIFICATION.md.
## condition_tree is data, not code (section 22: "実行コードをResourceへ
## 保存せず、許可された条件タイプと値のデータとして表現する"), evaluated by
## EventConditionEvaluator. Its shape:
##   {"all": [subtree, ...]}   -- AND
##   {"any": [subtree, ...]}   -- OR
##   {"not": subtree}          -- NOT
##   {"type": "<condition_type>", ...params}  -- leaf; see
##     EventConditionEvaluator's own header for the supported type list.
## dialogue_entries: Array of {"speaker_key": StringName, "body_key": StringName}.
## choice_entries: Array of {"id": StringName, "label_key": StringName,
##   "effect_ids": Array[StringName]}. scene_background/portraits are
## schema-only (no art assets exist in this project yet); the event UI is
## text-only.

@export var id: StringName
@export var faction_id: StringName
@export var importance: GameEnums.EventImportance = GameEnums.EventImportance.SUB
@export var priority: int = 0
@export var title_key: StringName
@export var condition_tree: Dictionary = {}
@export var exclusive_group_id: StringName = &""
@export var once_per_profile: bool = false
@export var once_per_campaign: bool = true
@export var scene_background: Texture2D
@export var dialogue_entries: Array[Dictionary] = []
@export var choice_entries: Array[Dictionary] = []
@export var default_effect_ids: Array[StringName] = []
@export var followup_event_ids: Array[StringName] = []
