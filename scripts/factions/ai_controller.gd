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
	_decide_research(faction_id, faction)
	for region in GameState.regions.values():
		if region.owner_faction_id != faction_id:
			continue
		_decide_production(faction, region)
		_decide_movement(faction_id, faction, region)

const MAX_QUEUE_LENGTH := 3  # keep the AI's production responsive to the battlefield rather than committing resources many turns ahead
const RESEARCH_RESERVE := 40  # only research if this much would still be left over for production

## Opportunistic: research whenever affordable with a comfortable buffer
## left over, rather than always saving for it or never bothering — a
## faction that's flush with income naturally starts climbing tiers.
static func _decide_research(faction_id: StringName, faction: Faction) -> void:
	if faction.research_in_progress:
		return
	var config: CampaignConfig = GameState.campaign_config
	if faction.tech_tier >= config.research_costs.size():
		return
	var cost: int = config.research_costs[faction.tech_tier]
	if faction.resources >= cost + RESEARCH_RESERVE:
		TurnManager.start_research(faction_id)

static func _decide_production(faction: Faction, region: Region) -> void:
	if region.pending_production.size() >= MAX_QUEUE_LENGTH:
		return
	var best := _best_affordable_unit(faction)
	if best != null:
		faction.resources -= best.build_cost
		region.pending_production.append({
			"unit_type_id": best.id,
			"turns_remaining": best.build_time_turns,
		})

## Picks the strongest (attack+defense) unit the faction can both afford
## and has researched, not just the cheapest — otherwise researching
## higher tiers would never actually change what the AI builds.
static func _best_affordable_unit(faction: Faction) -> UnitType:
	var best: UnitType = null
	var best_power := -1
	for unit_type in GameState.unit_defs.values():
		if unit_type.tech_tier_required > faction.tech_tier:
			continue
		if unit_type.build_cost > faction.resources:
			continue
		var power: int = unit_type.attack + unit_type.defense
		if power > best_power:
			best_power = power
			best = unit_type
	return best

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
