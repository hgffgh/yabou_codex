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
	var profile := ai_profile()
	_decide_research(faction_id, faction, profile)
	for region in GameState.regions.values():
		if region.owner_faction_id != faction_id:
			continue
		_decide_production(faction, region, profile)
	_decide_squad_movements(faction_id, faction, profile)

## DATA_DEFINITION.md section 5: DifficultyDef.ai_profile_id selects one of
## these to drive the knobs below. Falls back to a neutral AiProfileDef.new()
## (matching the pre-profile-system hardcoded constants this replaced) if
## the id doesn't resolve, same graceful-degradation pattern as
## GameState.current_difficulty().
static func ai_profile() -> AiProfileDef:
	var profile := GameState.master_data.ai_profiles.get(GameState.current_difficulty().ai_profile_id) as AiProfileDef
	return profile if profile != null else AiProfileDef.new()

## Opportunistic: research the cheapest currently-available node (lowest
## tier, ties broken by id) whenever affordable with a comfortable buffer
## left over, rather than always saving for it or never bothering -- a
## faction that's flush with income naturally starts climbing the tree.
static func _decide_research(faction_id: StringName, faction: Faction, profile: AiProfileDef) -> void:
	if faction.current_research != null:
		return
	var node_id := _cheapest_available_node(faction)
	if node_id.is_empty():
		return
	var node := faction.generated_tech_nodes[node_id] as GeneratedTechNodeState
	var config: CampaignConfig = GameState.campaign_config
	var cost: int = config.research_costs[node.tier - 1]
	if faction.funds >= cost + profile.research_reserve:
		TurnManager.start_research(faction_id, node_id)

static func _cheapest_available_node(faction: Faction) -> StringName:
	var candidates: Array[StringName] = []
	for node_id: StringName in faction.generated_tech_nodes:
		var node := faction.generated_tech_nodes[node_id] as GeneratedTechNodeState
		if not node.researched and TurnManager._node_prerequisites_met(faction, node):
			candidates.append(node_id)
	if candidates.is_empty():
		return &""
	candidates.sort_custom(func(a: StringName, b: StringName) -> bool:
		var na := faction.generated_tech_nodes[a] as GeneratedTechNodeState
		var nb := faction.generated_tech_nodes[b] as GeneratedTechNodeState
		if na.tier != nb.tier: return na.tier < nb.tier
		return String(a) < String(b))
	return candidates[0]

static func _decide_production(faction: Faction, region: Region, profile: AiProfileDef) -> void:
	var facility_ids := GameState.production_facility_ids_for_region(region.def.id)
	if facility_ids.is_empty():
		return
	var facility_id: StringName = facility_ids[0]
	var queue := GameState.campaign_runtime.production_queues_by_facility_id.get(facility_id) as ProductionQueueState
	if queue != null and queue.job_ids.size() >= profile.production_queue_length:
		return
	var best := _best_affordable_unit(faction)
	if best != null:
		GameState.queue_production(faction.def.id, facility_id, best.id)

## Picks the strongest (attack+defense) unit the faction can both afford
## and has researched, not just the cheapest — otherwise researching
## higher tiers would never actually change what the AI builds.
static func _best_affordable_unit(faction: Faction) -> UnitDef:
	var best: UnitDef = null
	var best_power := -1
	for unit_type: UnitDef in GameState.master_data.units.values():
		if unit_type.faction_origin_id != faction.def.id:
			continue
		var funds_cost: int = GameConstants.UNIT_PRODUCTION_FUNDS[unit_type.size]
		var materials_cost: int = GameConstants.UNIT_PRODUCTION_MATERIALS[unit_type.size]
		if funds_cost > faction.funds or materials_cost > faction.materials:
			continue
		var power: int = unit_type.firepower + unit_type.armor
		if power > best_power:
			best_power = power
			best = unit_type
	return best

## Issues one adjacent order per eligible new-model squad. Hostile destinations
## take priority; otherwise squads advance through owned regions toward the
## neighbor with the most hostile borders.
static func _decide_squad_movements(faction_id: StringName, faction: Faction, profile: AiProfileDef) -> void:
	var squads := GameState.campaign_runtime.squads_by_id.values()
	squads.sort_custom(func(a: SquadState, b: SquadState) -> bool: return String(a.squad_id) < String(b.squad_id))
	for squad: SquadState in squads:
		if squad == null or squad.owner_faction_id != faction_id or squad.movement_used:
			continue
		var source := GameState.get_region(squad.region_id) as Region
		if source == null:
			continue
		var target_id := _best_squad_destination(faction_id, faction, squad, source, profile)
		if not target_id.is_empty():
			GameState.plan_squad_movement(squad.squad_id, target_id, faction_id)


## required_ratio is divided by profile.aggression_multiplier (DATA_
## DEFINITION.md section 5's ai_profile_id): a more aggressive profile
## accepts a lower relative power advantage before attacking, on top of
## FactionDef.ai_aggression's per-faction baseline.
static func _best_squad_destination(
	faction_id: StringName,
	faction: Faction,
	squad: SquadState,
	source: Region,
	profile: AiProfileDef,
) -> StringName:
	var own_power := _squad_power(squad)
	var base_required_ratio: float = lerp(2.0, 1.05, faction.def.ai_aggression) / profile.aggression_multiplier
	var best_target_id: StringName = &""
	var best_score := -INF
	var neighbor_ids := source.def.neighbor_ids.duplicate()
	neighbor_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for neighbor_id: StringName in neighbor_ids:
		var neighbor := GameState.get_region(neighbor_id) as Region
		if neighbor == null:
			continue
		var score: float
		if neighbor.owner_faction_id != faction_id:
			if not neighbor.owner_faction_id.is_empty() and Diplomacy.has_active_treaty(GameState, faction_id, neighbor.owner_faction_id):
				continue
			var defender_power := _region_squad_power(neighbor_id, neighbor.owner_faction_id)
			if defender_power > 0.0:
				var relation: float = Diplomacy.friendship(GameState, faction_id, neighbor.owner_faction_id)
				var required_ratio: float = max(base_required_ratio - relation / 200.0, 1.0)
				if own_power < defender_power * required_ratio:
					continue
			score = 10000.0 - defender_power
		else:
			score = float(_hostile_neighbor_count(neighbor, faction_id) * 100)
			if neighbor.def.is_capital_slot:
				score -= 1.0
		if score > best_score:
			best_score = score
			best_target_id = neighbor_id
	return best_target_id


static func _squad_power(squad: SquadState) -> float:
	var power := 0.0
	for unit_id: StringName in squad.unit_instance_ids:
		var unit := GameState.campaign_runtime.get_unit(unit_id) as UnitInstanceState
		if unit == null:
			continue
		var unit_def := GameState.master_data.units.get(unit.unit_def_id) as UnitDef
		if unit_def != null:
			power += float(unit_def.firepower + unit_def.armor)
	return power


static func _region_squad_power(region_id: StringName, faction_id: StringName) -> float:
	if faction_id.is_empty():
		return 0.0
	var power := 0.0
	for squad: SquadState in GameState.campaign_runtime.get_squads_in_region(region_id, faction_id):
		power += _squad_power(squad)
	return power


static func _hostile_neighbor_count(region: Region, faction_id: StringName) -> int:
	var count := 0
	for neighbor_id: StringName in region.def.neighbor_ids:
		var neighbor := GameState.get_region(neighbor_id) as Region
		if neighbor != null and neighbor.owner_faction_id != faction_id:
			count += 1
	return count
