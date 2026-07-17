class_name IntelRecordState
extends RefCounted

## DATA_DEFINITION.md section 21, trimmed to the strategic layer: whether
## observer_faction_id currently has confirmed intel on target_squad_id.
## Battle-scoped position/snapshot tracking is handled separately by
## BattleSquadState's intel_confirmed/currently_sensed/last_known_world_position
## (see COMBAT_DETAIL_SPECIFICATION.md section 24); this class only tracks
## the campaign-persistent, region-granularity confirmation used by the
## strategic map.

var observer_faction_id: StringName = &""
var target_squad_id: StringName = &""
var intel_state: GameEnums.IntelState = GameEnums.IntelState.UNKNOWN
var target_revision: int = 0
var last_seen_turn: int = 0


func to_dict() -> Dictionary:
	return {
		"observer_faction_id": observer_faction_id,
		"target_squad_id": target_squad_id,
		"intel_state": intel_state,
		"target_revision": target_revision,
		"last_seen_turn": last_seen_turn,
	}


static func from_dict(data: Dictionary) -> IntelRecordState:
	var state := IntelRecordState.new()
	state.observer_faction_id = StringName(data.get("observer_faction_id", ""))
	state.target_squad_id = StringName(data.get("target_squad_id", ""))
	state.intel_state = int(data.get("intel_state", GameEnums.IntelState.UNKNOWN))
	state.target_revision = int(data.get("target_revision", 0))
	state.last_seen_turn = int(data.get("last_seen_turn", 0))
	return state
