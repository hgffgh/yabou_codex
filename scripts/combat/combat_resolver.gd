class_name CombatResolver
extends RefCounted
## Pure combat math: given an attacking and defending UnitStack, computes a
## deterministic-except-for-one-roll outcome. Never touches presentation —
## BattleVignette only animates a CombatResult that already happened here.

enum Outcome { FULL_VICTORY, MARGINAL_VICTORY, STALEMATE, DEFEAT }

class CombatResult:
	var outcome: int
	var outcome_ratio: float
	var attacker_losses: Dictionary = {}  # unit_type_id -> count destroyed
	var defender_losses: Dictionary = {}
	var region_captured: bool = false

static func resolve(attacker_stack: UnitStack, defender_stack: UnitStack, region: Region) -> CombatResult:
	var attacker_faction: Faction = GameState.get_faction(attacker_stack.faction_id)
	var defender_faction: Faction = null
	if defender_stack:
		defender_faction = GameState.get_faction(defender_stack.faction_id)

	var attacker_power := stack_power(attacker_stack, true, attacker_faction, region)
	var defender_power := stack_power(defender_stack, false, defender_faction, region)

	var roll := randf_range(0.85, 1.15)
	var ratio: float = (attacker_power * roll) / max(defender_power, 1.0)

	var result := CombatResult.new()
	result.outcome_ratio = ratio

	if ratio >= 1.5:
		result.outcome = Outcome.FULL_VICTORY
		result.defender_losses = _full_losses(defender_stack)
		result.attacker_losses = _fractional_losses(attacker_stack, 0.1)
		result.region_captured = true
	elif ratio >= 1.0:
		result.outcome = Outcome.MARGINAL_VICTORY
		result.defender_losses = _full_losses(defender_stack)
		result.attacker_losses = _fractional_losses(attacker_stack, 0.4)
		result.region_captured = true
	elif ratio >= 0.66:
		result.outcome = Outcome.STALEMATE
		result.attacker_losses = _fractional_losses(attacker_stack, 0.3)
		result.defender_losses = _fractional_losses(defender_stack, 0.3)
	else:
		result.outcome = Outcome.DEFEAT
		result.attacker_losses = _full_losses(attacker_stack)
		result.defender_losses = _fractional_losses(defender_stack, 0.1)

	return result

static func stack_power(stack: UnitStack, is_attack: bool, faction: Faction, region: Region) -> float:
	if stack == null:
		return 0.0
	var power := 0.0
	for unit_id in stack.units:
		var udef: UnitType = GameState.unit_defs[unit_id]
		var stat: int = udef.attack if is_attack else udef.defense
		power += stat * stack.units[unit_id]
	if faction:
		var bonus_key := "attack" if is_attack else "defense"
		power *= 1.0 + float(faction.def.tech_bonus.get(bonus_key, 0.0))
	if not is_attack and region:
		power *= 1.0 + region.def.defense_terrain_bonus / 100.0
	return power

static func _full_losses(stack: UnitStack) -> Dictionary:
	if stack == null:
		return {}
	return stack.units.duplicate()

static func _fractional_losses(stack: UnitStack, fraction: float) -> Dictionary:
	if stack == null:
		return {}
	var losses := {}
	for unit_id in stack.units:
		var count: int = stack.units[unit_id]
		var lost: int = int(round(count * fraction))
		if lost > 0:
			losses[unit_id] = lost
	return losses
