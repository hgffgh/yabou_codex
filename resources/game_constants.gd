class_name GameConstants
extends RefCounted

const GENERIC_PILOT_ABILITY: int = 100


static func is_generic_pilot_id(pilot_id: StringName) -> bool:
	return pilot_id == &""

const MAX_UNITS_PER_SQUAD: int = 5
const FRONT_SLOT_COUNT: int = 3
const REAR_SLOT_COUNT: int = 2
const FRONT_SLOT_START: int = 0
const REAR_SLOT_START: int = 3

const UNIT_PRODUCTION_FUNDS: Dictionary = {
	GameEnums.UnitSize.LIGHT: 300,
	GameEnums.UnitSize.STANDARD: 600,
	GameEnums.UnitSize.HEAVY: 1200,
}
const UNIT_PRODUCTION_MATERIALS: Dictionary = {
	GameEnums.UnitSize.LIGHT: 200,
	GameEnums.UnitSize.STANDARD: 400,
	GameEnums.UnitSize.HEAVY: 800,
}
const UNIT_PRODUCTION_POWER: Dictionary = {
	GameEnums.UnitSize.LIGHT: 100,
	GameEnums.UnitSize.STANDARD: 200,
	GameEnums.UnitSize.HEAVY: 400,
}

## Fraction of a defeated faction's destroyed units that the winner salvages
## as captured, rather than losing outright. DATA_DEFINITION.md
## capture_enemy_unit_pct default; not yet promoted to a CampaignConfig field.
const CAPTURE_ENEMY_UNIT_PCT: float = 0.10

## STRATEGY_DETAIL_SPECIFICATION.md section 5.3/5.5/5.7: named-pilot level
## cap, permanent-stat cap, and destroyed-pilot injury duration in weeks.
const PILOT_LEVEL_CAP: int = 50
const PILOT_STAT_CAP: int = 200
const PILOT_INJURY_TURNS: int = 3

## Base EXP per source, before the (currently unimplemented) permanent
## profile EXP bonus. section 5.3's award table.
const PILOT_EXP_ROUND_PARTICIPATION: int = 50
const PILOT_EXP_ENEMY_DESTROYED: int = 50
const PILOT_EXP_SUPPORT_SUCCESS: int = 20
const PILOT_EXP_BATTLE_VICTORY: int = 50
const PILOT_EXP_HQ_CAPTURE_VICTORY: int = 100

## EXP required to advance from `level` to `level + 1`, by section 5.3's
## table. Returns 0 at or above the level cap (no further level exists).
static func pilot_exp_to_next_level(level: int) -> int:
	if level >= PILOT_LEVEL_CAP:
		return 0
	if level <= 10:
		return 250
	if level <= 20:
		return 500
	if level <= 30:
		return 750
	if level <= 40:
		return 1000
	return 1500

const NORMAL_SENSOR_RANGE_M: float = 150.0
const RECON_SENSOR_RANGE_M: float = 300.0
const ALLOWED_DAMAGE_MULTIPLIERS: Array[float] = [0.50, 0.75, 1.00, 1.25, 1.50]

const APTITUDE_MOVE_MULTIPLIERS: Dictionary = {
	GameEnums.EnvironmentAptitude.PROFICIENT: 1.20,
	GameEnums.EnvironmentAptitude.STANDARD: 1.00,
	GameEnums.EnvironmentAptitude.POOR: 0.80,
}
const APTITUDE_ACCURACY_ADDITIONS: Dictionary = {
	GameEnums.EnvironmentAptitude.PROFICIENT: 10,
	GameEnums.EnvironmentAptitude.STANDARD: 0,
	GameEnums.EnvironmentAptitude.POOR: -10,
}
const APTITUDE_EVASION_ADDITIONS: Dictionary = {
	GameEnums.EnvironmentAptitude.PROFICIENT: 10,
	GameEnums.EnvironmentAptitude.STANDARD: 0,
	GameEnums.EnvironmentAptitude.POOR: -10,
}

## STRATEGY_DETAIL_SPECIFICATION.md section 11: diplomacy.
const FRIENDSHIP_MIN: int = -100
const FRIENDSHIP_MAX: int = 100
const INITIAL_FRIENDSHIP: int = -50
const TREATY_ACTIVE_FRIENDSHIP_GAIN_PER_TURN: int = 1
const COMBAT_FRIENDSHIP_PENALTY: int = -15

const CEASEFIRE_DURATIONS: Array[int] = [3, 5, 10]
const NON_AGGRESSION_DURATIONS: Array[int] = [10, 20, 30]
const TREATY_BASE_SUCCESS_PCT: Dictionary = {
	GameEnums.TreatyType.CEASEFIRE: 60,
	GameEnums.TreatyType.NON_AGGRESSION: 40,
}
## Success-rate penalty by treaty type and chosen duration (11.3's table).
const TREATY_DURATION_PENALTY_PCT: Dictionary = {
	GameEnums.TreatyType.CEASEFIRE: {3: 0, 5: 5, 10: 10},
	GameEnums.TreatyType.NON_AGGRESSION: {10: 0, 20: 10, 30: 20},
}
const FRIENDSHIP_SUCCESS_MULTIPLIER: float = 0.25
const POWER_RATIO_SUCCESS_MULTIPLIER: float = 20.0
const POWER_RATIO_SUCCESS_CLAMP_PCT: float = 10.0
const GIFT_OFFER_SUCCESS_MULTIPLIER: float = 5.0
const GIFT_OFFER_SUCCESS_MAX_PCT: float = 30.0
const TREATY_SUCCESS_MIN_PCT: int = 5
const TREATY_SUCCESS_MAX_PCT: int = 95

const DIPLOMACY_PROPOSAL_COOLDOWN_TURNS: int = 5
const DIPLOMACY_GIFT_COOLDOWN_TURNS: int = 5
const DIPLOMACY_INTEL_PURCHASE_COOLDOWN_TURNS: int = 5

const TREATY_VIOLATION_FRIENDSHIP_PENALTY: int = 20
const TREATY_VIOLATION_SUCCESS_PENALTY_PCT: int = 10
const TREATY_VIOLATION_PENALTY_TURNS: int = 10

const MIN_GIFT_FUNDS: int = 300
const MIN_GIFT_MATERIALS: int = 200
const GIFT_FRIENDSHIP_GAIN: int = 5

const INTEL_PURCHASE_COST_FUNDS: int = 2000

## Ransom price is 75% of the unit's production funds cost (11.8: 225/450/900
## for light/standard/heavy against the 300/600/1200 UNIT_PRODUCTION_FUNDS).
const RANSOM_PRICE_PCT: float = 0.75
