class_name AiController
extends RefCounted
## v1 AI: each owned, idle region queues its cheapest affordable tier-0
## unit, and each owned non-capital region with an idle stack considers
## attacking a weaker neighbor. Capitals never launch attacks — they're the
## faction's standing home defense. Willingness to attack scales with
## ai_aggression and current relation to the target (Diplomacy).

static func decide_orders(faction_id: StringName) -> void:
	var faction: Faction = GameState.get_faction(faction_id)
	if faction == null:
		return
	for region in GameState.regions.values():
		if region.owner_faction_id != faction_id:
			continue
		_decide_production(faction, region)
		_decide_movement(faction_id, faction, region)

static func _decide_production(faction: Faction, region: Region) -> void:
	if not region.pending_production.is_empty():
		return
	var cheapest := _cheapest_tier0_unit()
	if cheapest != null and faction.resources >= cheapest.build_cost:
		faction.resources -= cheapest.build_cost
		region.pending_production.append({
			"unit_type_id": cheapest.id,
			"turns_remaining": cheapest.build_time_turns,
		})

static func _cheapest_tier0_unit() -> UnitType:
	var cheapest: UnitType = null
	for unit_type in GameState.unit_defs.values():
		if unit_type.tech_tier_required > 0:
			continue
		if cheapest == null or unit_type.build_cost < cheapest.build_cost:
			cheapest = unit_type
	return cheapest

static func _decide_movement(faction_id: StringName, faction: Faction, region: Region) -> void:
	if region.def.is_capital_slot:
		return  # capitals garrison, they never launch the attack themselves
	if region.pending_move_order != &"":
		return
	var own_stack: UnitStack = region.stacks.get(faction_id)
	if own_stack == null or own_stack.is_empty():
		return

	var own_power := CombatResolver.stack_power(own_stack, true, faction, region)
	var base_required_ratio: float = lerp(2.0, 1.05, faction.def.ai_aggression)

	var best_target_id: StringName = &""
	var best_score := -INF

	for neighbor_id in region.def.neighbor_ids:
		var neighbor: Region = GameState.get_region(neighbor_id)
		if neighbor == null or neighbor.owner_faction_id == faction_id:
			continue

		var defender_stack: UnitStack = null
		var defender_faction: Faction = null
		if neighbor.owner_faction_id != &"":
			defender_stack = neighbor.stacks.get(neighbor.owner_faction_id)
			defender_faction = GameState.get_faction(neighbor.owner_faction_id)
		var defender_power := CombatResolver.stack_power(defender_stack, false, defender_faction, neighbor)

		var score: float
		if defender_power <= 0.0:
			score = 1000.0 - own_power  # undefended: always worth taking; prefer the cheapest such grab
		else:
			var relation: float = Diplomacy.relation(faction_id, neighbor.owner_faction_id)
			var required_ratio: float = max(base_required_ratio - relation / 200.0, 1.0)
			if own_power < defender_power * required_ratio:
				continue
			score = -defender_power  # among viable targets, prefer the weakest

		if score > best_score:
			best_score = score
			best_target_id = neighbor_id

	if best_target_id != &"":
		region.pending_move_order = best_target_id
