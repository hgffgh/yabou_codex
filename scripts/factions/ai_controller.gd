class_name AiController
extends RefCounted
## Minimal v1 AI: each owned, idle region queues its cheapest affordable
## tier-0 unit. No movement/targeting yet — that lands with combat in M3/M4.

static func decide_orders(faction_id: StringName) -> void:
	var faction: Faction = GameState.get_faction(faction_id)
	if faction == null:
		return
	for region in GameState.regions.values():
		if region.owner_faction_id != faction_id:
			continue
		if not region.pending_production.is_empty():
			continue
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
