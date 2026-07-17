class_name ProfileState
extends RefCounted
## DATA_DEFINITION.md section 24, scoped to what this codebase drives today:
## achievement_ids, the permanent_exp_bonus_pct recomputed from them, and
## viewed_event_ids (EVENT_DETAIL_SPECIFICATION.md section 6/9: every MAIN
## event a player has resolved, plus any SUB event explicitly flagged
## EventDef.once_per_profile -- this is both the once_per_profile gate and
## the 回想 (recap) unlock list). Persists across campaigns in its own file
## (GameState.save_profile/_load_profile), separate from any
## CampaignSaveData slot -- per SYSTEM_DETAIL_SPECIFICATION.md section 2.3,
## "実績はキャンペーンセーブと別のプロフィールへ保存する".
## encyclopedia_*/unlocked_tech_candidate_ids/settings are not modeled: the
## encyclopedia and settings menu are out of scope entirely, and
## unlocked_tech_candidate_ids belongs to the permanent cross-campaign tech
## pool TechTreeGenerator explicitly doesn't model yet (see HANDOFF.md).

const MAX_PERMANENT_EXP_BONUS_PCT := 0.50

var profile_version: int = 1
var achievement_ids: Array[StringName] = []
var permanent_exp_bonus_pct: float = 0.0
var viewed_event_ids: Array[StringName] = []


func has_achievement(id: StringName) -> bool:
	return achievement_ids.has(id)


## Returns true only if this call actually unlocked something new.
func unlock_achievement(id: StringName, registry: MasterDataRegistry) -> bool:
	if id.is_empty() or achievement_ids.has(id) or not registry.achievements.has(id):
		return false
	achievement_ids.append(id)
	recalculate_bonus(registry)
	return true


## DATA_DEFINITION.md section 24: "permanent_exp_bonus_pctは実績配列から
##起動時に再計算し、破損・不整合を検証する" -- never trust a stored value,
## always derive it fresh from achievement_ids against current master data.
func recalculate_bonus(registry: MasterDataRegistry) -> void:
	var total := 0.0
	for id: StringName in achievement_ids:
		var def := registry.achievements.get(id) as AchievementDef
		if def != null:
			total += def.exp_bonus_pct
	permanent_exp_bonus_pct = minf(total, MAX_PERMANENT_EXP_BONUS_PCT)


func has_viewed_event(id: StringName) -> bool:
	return viewed_event_ids.has(id)


## Returns true only if this call actually added a new entry.
func mark_event_viewed(id: StringName) -> bool:
	if id.is_empty() or viewed_event_ids.has(id):
		return false
	viewed_event_ids.append(id)
	return true


func to_dict() -> Dictionary:
	var sorted_ids := achievement_ids.duplicate()
	sorted_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var sorted_event_ids := viewed_event_ids.duplicate()
	sorted_event_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return {
		"profile_version": profile_version,
		"achievement_ids": sorted_ids,
		"viewed_event_ids": sorted_event_ids,
	}


static func from_dict(data: Dictionary, registry: MasterDataRegistry) -> ProfileState:
	var state := ProfileState.new()
	state.profile_version = int(data.get("profile_version", 1))
	var ids_value: Variant = data.get("achievement_ids", [])
	if ids_value is Array:
		for id_value: Variant in ids_value as Array:
			var id := StringName(id_value)
			if not id.is_empty() and not state.achievement_ids.has(id):
				state.achievement_ids.append(id)
	var event_ids_value: Variant = data.get("viewed_event_ids", [])
	if event_ids_value is Array:
		for id_value: Variant in event_ids_value as Array:
			var id := StringName(id_value)
			if not id.is_empty() and not state.viewed_event_ids.has(id):
				state.viewed_event_ids.append(id)
	state.recalculate_bonus(registry)
	return state
