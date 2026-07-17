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
