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
## encyclopedia_unit_ids/encyclopedia_weapon_ids/encyclopedia_pilot_ids
## (DATA_DEFINITION.md section 24): grown by GameState.
## register_encyclopedia_for_squad whenever a unit/weapon/pilot becomes
## known to the player (their own roster immediately; an enemy's once its
## squad is intel-confirmed). `settings` is not modeled -- the settings menu
## is out of scope entirely.
##
## unlocked_tech_candidate_ids: STRATEGY_DETAIL_SPECIFICATION.md section
## 7.2's permanent cross-campaign tech pool -- see TechTreeGenerator's own
## doc comment for exactly how this grows and what it changes.

const MAX_PERMANENT_EXP_BONUS_PCT := 0.50

var profile_version: int = 1
var achievement_ids: Array[StringName] = []
var permanent_exp_bonus_pct: float = 0.0
var viewed_event_ids: Array[StringName] = []
var unlocked_tech_candidate_ids: Array[StringName] = []
var encyclopedia_unit_ids: Array[StringName] = []
var encyclopedia_weapon_ids: Array[StringName] = []
var encyclopedia_pilot_ids: Array[StringName] = []


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


## Returns true only if this call actually added a new entry.
func unlock_tech_candidate(tech_id: StringName) -> bool:
	if tech_id.is_empty() or unlocked_tech_candidate_ids.has(tech_id):
		return false
	unlocked_tech_candidate_ids.append(tech_id)
	return true


## Returns true only if this call actually added a new entry.
func register_encyclopedia_unit(unit_def_id: StringName) -> bool:
	if unit_def_id.is_empty() or encyclopedia_unit_ids.has(unit_def_id):
		return false
	encyclopedia_unit_ids.append(unit_def_id)
	return true


## Returns true only if this call actually added a new entry.
func register_encyclopedia_weapon(weapon_id: StringName) -> bool:
	if weapon_id.is_empty() or encyclopedia_weapon_ids.has(weapon_id):
		return false
	encyclopedia_weapon_ids.append(weapon_id)
	return true


## Returns true only if this call actually added a new entry.
func register_encyclopedia_pilot(pilot_id: StringName) -> bool:
	if pilot_id.is_empty() or encyclopedia_pilot_ids.has(pilot_id):
		return false
	encyclopedia_pilot_ids.append(pilot_id)
	return true


func _sorted(ids: Array[StringName]) -> Array[StringName]:
	var copy := ids.duplicate()
	copy.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return copy


func to_dict() -> Dictionary:
	return {
		"profile_version": profile_version,
		"achievement_ids": _sorted(achievement_ids),
		"viewed_event_ids": _sorted(viewed_event_ids),
		"unlocked_tech_candidate_ids": _sorted(unlocked_tech_candidate_ids),
		"encyclopedia_unit_ids": _sorted(encyclopedia_unit_ids),
		"encyclopedia_weapon_ids": _sorted(encyclopedia_weapon_ids),
		"encyclopedia_pilot_ids": _sorted(encyclopedia_pilot_ids),
	}


static func _load_id_array(data: Dictionary, key: String) -> Array[StringName]:
	var result: Array[StringName] = []
	var value: Variant = data.get(key, [])
	if value is Array:
		for id_value: Variant in value as Array:
			var id := StringName(id_value)
			if not id.is_empty() and not result.has(id):
				result.append(id)
	return result


static func from_dict(data: Dictionary, registry: MasterDataRegistry) -> ProfileState:
	var state := ProfileState.new()
	state.profile_version = int(data.get("profile_version", 1))
	state.achievement_ids = _load_id_array(data, "achievement_ids")
	state.viewed_event_ids = _load_id_array(data, "viewed_event_ids")
	state.unlocked_tech_candidate_ids = _load_id_array(data, "unlocked_tech_candidate_ids")
	state.encyclopedia_unit_ids = _load_id_array(data, "encyclopedia_unit_ids")
	state.encyclopedia_weapon_ids = _load_id_array(data, "encyclopedia_weapon_ids")
	state.encyclopedia_pilot_ids = _load_id_array(data, "encyclopedia_pilot_ids")
	state.recalculate_bonus(registry)
	return state
