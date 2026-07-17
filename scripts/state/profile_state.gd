class_name ProfileState
extends RefCounted
## DATA_DEFINITION.md section 24, scoped to what this codebase drives today:
## achievement_ids and the permanent_exp_bonus_pct recomputed from them.
## Persists across campaigns in its own file (GameState.save_profile/
## _load_profile), separate from any CampaignSaveData slot -- per
## SYSTEM_DETAIL_SPECIFICATION.md section 2.3, "実績はキャンペーンセーブと
## 別のプロフィールへ保存する". encyclopedia_*/unlocked_tech_candidate_ids/
## viewed_event_ids/settings are not modeled: the encyclopedia and settings
## menu are out of scope entirely, and the other two belong to systems
## (tech-node generation, events) that don't exist yet.

const MAX_PERMANENT_EXP_BONUS_PCT := 0.50

var profile_version: int = 1
var achievement_ids: Array[StringName] = []
var permanent_exp_bonus_pct: float = 0.0


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


func to_dict() -> Dictionary:
	var sorted_ids := achievement_ids.duplicate()
	sorted_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return {
		"profile_version": profile_version,
		"achievement_ids": sorted_ids,
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
	state.recalculate_bonus(registry)
	return state
