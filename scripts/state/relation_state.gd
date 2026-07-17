class_name RelationState
extends RefCounted
## DATA_DEFINITION.md section 18.1 / STRATEGY_DETAIL_SPECIFICATION.md
## section 11. One instance per unordered faction pair -- CampaignRuntimeState
## indexes it under a sorted key so either lookup order resolves the same
## object, keeping friendship/treaty state symmetric by construction.

var faction_a_id: StringName
var faction_b_id: StringName
var friendship: int = GameConstants.INITIAL_FRIENDSHIP
var treaty_type: GameEnums.TreatyType = GameEnums.TreatyType.NONE
var treaty_turns_remaining: int = 0
var proposal_cooldown_turns: int = 0
var gift_cooldown_turns: int = 0
var intel_purchase_cooldown_turns: int = 0
## Only set while a unilateral treaty break's success-rate penalty is active;
## the penalty applies only to proposals from this faction, not both sides.
var violator_faction_id: StringName = &""
var violation_penalty_turns: int = 0
var violation_success_penalty_pct: int = 0


func _init(a: StringName = &"", b: StringName = &"") -> void:
	faction_a_id = a
	faction_b_id = b


func other_of(faction_id: StringName) -> StringName:
	return faction_b_id if faction_id == faction_a_id else faction_a_id


func relation_band() -> GameEnums.RelationBand:
	if friendship <= -61:
		return GameEnums.RelationBand.NEMESIS
	elif friendship <= -21:
		return GameEnums.RelationBand.HOSTILE
	elif friendship <= 20:
		return GameEnums.RelationBand.NEUTRAL
	elif friendship <= 60:
		return GameEnums.RelationBand.FRIENDLY
	else:
		return GameEnums.RelationBand.CLOSE


func to_dict() -> Dictionary:
	return {
		"faction_a_id": faction_a_id,
		"faction_b_id": faction_b_id,
		"friendship": friendship,
		"treaty_type": treaty_type,
		"treaty_turns_remaining": treaty_turns_remaining,
		"proposal_cooldown_turns": proposal_cooldown_turns,
		"gift_cooldown_turns": gift_cooldown_turns,
		"intel_purchase_cooldown_turns": intel_purchase_cooldown_turns,
		"violator_faction_id": violator_faction_id,
		"violation_penalty_turns": violation_penalty_turns,
		"violation_success_penalty_pct": violation_success_penalty_pct,
	}


static func from_dict(data: Dictionary) -> RelationState:
	var state := RelationState.new(
		StringName(data.get("faction_a_id", "")), StringName(data.get("faction_b_id", ""))
	)
	state.friendship = int(data.get("friendship", GameConstants.INITIAL_FRIENDSHIP))
	state.treaty_type = int(data.get("treaty_type", GameEnums.TreatyType.NONE))
	state.treaty_turns_remaining = int(data.get("treaty_turns_remaining", 0))
	state.proposal_cooldown_turns = int(data.get("proposal_cooldown_turns", 0))
	state.gift_cooldown_turns = int(data.get("gift_cooldown_turns", 0))
	state.intel_purchase_cooldown_turns = int(data.get("intel_purchase_cooldown_turns", 0))
	state.violator_faction_id = StringName(data.get("violator_faction_id", ""))
	state.violation_penalty_turns = int(data.get("violation_penalty_turns", 0))
	state.violation_success_penalty_pct = int(data.get("violation_success_penalty_pct", 0))
	return state
