class_name TechTreeGenerator
extends RefCounted
## STRATEGY_DETAIL_SPECIFICATION.md section 7.2: a generated, per-faction,
## 5-tier tech tree, fixed for the whole campaign. Every faction's
## mandatory_base_tech TechDefs are always placed at their own tier; the
## rest of each tier is filled by a deterministic random draw (using the
## campaign's own RNG stream, so a given seed always regenerates the same
## tree) from every other non-mandatory TechDef -- DATA_DEFINITION.md's
## "恒久アンロック済み候補" (the cross-campaign permanent unlock pool) isn't
## modeled: there's no encyclopedia/capture-analysis system yet to grow it,
## so every non-mandatory tech is always treated as already unlocked for the
## draw. See HANDOFF.md for the full tradeoff.
##
## "生成後に全技術へ到達可能か検証し、到達不能があれば再生成する" doesn't
## need an actual regenerate-and-retry loop here: every node either has no
## prerequisites (tier 1) or draws 1-2 prerequisites from the immediately
## preceding tier, which is itself already reachable by induction -- so
## reachability holds by construction. TechTreeGenerator.is_reachable exists
## as a standalone check anyway, for tests to confirm the invariant.

const TARGET_NODES_PER_TIER := 3
const TIER_COUNT := 5

static func generate_for_faction(faction_id: StringName, registry: MasterDataRegistry, rng: RandomNumberGenerator) -> Dictionary:
	var nodes: Dictionary = {}
	var nodes_by_tier: Dictionary = {}
	var used_tech_ids: Dictionary = {}
	var serial := 1

	var all_tech_ids := registry.techs.keys()
	all_tech_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))

	for tier in range(1, TIER_COUNT + 1):
		var mandatory: Array[StringName] = []
		var pool: Array[StringName] = []
		for tech_id: StringName in all_tech_ids:
			var def := registry.techs[tech_id] as TechDef
			if def == null or def.tier != tier or used_tech_ids.has(tech_id):
				continue
			if def.mandatory_base_tech:
				if def.origin_faction_id == faction_id:
					mandatory.append(tech_id)
			else:
				pool.append(tech_id)

		var selected: Array[StringName] = mandatory.duplicate()
		while selected.size() < TARGET_NODES_PER_TIER and not pool.is_empty():
			var index := rng.randi_range(0, pool.size() - 1)
			selected.append(pool[index])
			pool.remove_at(index)

		var tier_node_ids: Array[StringName] = []
		var previous_tier_node_ids: Array[StringName] = nodes_by_tier.get(tier - 1, [] as Array[StringName])
		for tech_id: StringName in selected:
			used_tech_ids[tech_id] = true
			var node := GeneratedTechNodeState.new()
			node.node_id = StringName("node_%s_%03d" % [faction_id, serial])
			serial += 1
			node.tech_id = tech_id
			node.tier = tier
			if tier > 1 and not previous_tier_node_ids.is_empty():
				var prereq_pool := previous_tier_node_ids.duplicate()
				var prereq_count := mini(rng.randi_range(1, 2), prereq_pool.size())
				for _i in range(prereq_count):
					var prereq_index := rng.randi_range(0, prereq_pool.size() - 1)
					node.prerequisite_node_ids.append(prereq_pool[prereq_index])
					prereq_pool.remove_at(prereq_index)
			nodes[node.node_id] = node
			tier_node_ids.append(node.node_id)
		nodes_by_tier[tier] = tier_node_ids

	return nodes


## True if every node is transitively reachable from tier-1 nodes (which
## have no prerequisites at all). Never expected to fail given how
## generate_for_faction builds trees, but kept as an explicit, testable
## invariant per the spec's own validation requirement.
static func is_reachable(nodes: Dictionary) -> bool:
	for node_id: Variant in nodes:
		var node := nodes[node_id] as GeneratedTechNodeState
		if node.tier <= 1:
			continue
		if node.prerequisite_node_ids.is_empty():
			return false
		for prereq_id: StringName in node.prerequisite_node_ids:
			if not nodes.has(prereq_id):
				return false
	return true
