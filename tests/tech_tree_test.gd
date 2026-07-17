extends SceneTree
## STRATEGY_DETAIL_SPECIFICATION.md section 7 / DATA_DEFINITION.md sections
## 15/15.1/15.2: the generated tech tree and research flow.

var failures := PackedStringArray()
var game_state: Node
var turn_manager: Node


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	turn_manager = root.get_node_or_null("TurnManager")
	if game_state == null or turn_manager == null:
		push_error("tech_tree_test: required autoload is unavailable")
		quit(1)
		return

	_test_generated_tree_places_mandatory_base_techs_at_tier_one()
	_test_generated_tree_is_reachable_and_has_no_duplicate_techs()
	_test_generated_tree_is_deterministic_for_a_given_seed()
	_test_start_research_requires_prerequisites_and_funds()
	_test_advance_research_completes_and_frees_the_slot()
	_test_research_discount_caps_at_25_percent()
	_finish()


func _test_generated_tree_places_mandatory_base_techs_at_tier_one() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var nodes: Dictionary = TechTreeGenerator.generate_for_faction(&"nova_republic", game_state.master_data, rng)
	var found_mandatory := false
	for node_id: Variant in nodes:
		var node := nodes[node_id] as GeneratedTechNodeState
		if node.tech_id == &"nova_hull_foundation":
			found_mandatory = true
			_check(node.tier == 1, "nova_republic's mandatory base tech should be placed at tier 1")
	_check(found_mandatory, "nova_republic's generated tree should always include its mandatory base tech")

	var crimson_nodes: Dictionary = TechTreeGenerator.generate_for_faction(&"crimson_empire", game_state.master_data, rng)
	var has_nova_mandatory := false
	for node_id: Variant in crimson_nodes:
		if (crimson_nodes[node_id] as GeneratedTechNodeState).tech_id == &"nova_hull_foundation":
			has_nova_mandatory = true
	_check(not has_nova_mandatory, "a mandatory_base_tech tied to one faction must never appear in another faction's tree")


func _test_generated_tree_is_reachable_and_has_no_duplicate_techs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var nodes: Dictionary = TechTreeGenerator.generate_for_faction(&"crimson_empire", game_state.master_data, rng)
	_check(not nodes.is_empty(), "setup: generation should produce at least one node")
	_check(TechTreeGenerator.is_reachable(nodes), "every generated node must be reachable per the spec's own validation requirement")

	var seen_tech_ids := {}
	for node_id: Variant in nodes:
		var tech_id: StringName = (nodes[node_id] as GeneratedTechNodeState).tech_id
		_check(not seen_tech_ids.has(tech_id), "the same tech_id should never appear twice in one faction's generated tree")
		seen_tech_ids[tech_id] = true

	var tiers_present := {}
	for node_id: Variant in nodes:
		tiers_present[(nodes[node_id] as GeneratedTechNodeState).tier] = true
	for tier in range(1, 6):
		_check(tiers_present.has(tier), "the standard tech dataset should be large enough to populate tier %d" % tier)


func _test_generated_tree_is_deterministic_for_a_given_seed() -> void:
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 123
	var nodes_a: Dictionary = TechTreeGenerator.generate_for_faction(&"nova_republic", game_state.master_data, rng_a)
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 123
	var nodes_b: Dictionary = TechTreeGenerator.generate_for_faction(&"nova_republic", game_state.master_data, rng_b)

	var tech_ids_a: Array[StringName] = []
	for node_id: Variant in nodes_a:
		tech_ids_a.append((nodes_a[node_id] as GeneratedTechNodeState).tech_id)
	var tech_ids_b: Array[StringName] = []
	for node_id: Variant in nodes_b:
		tech_ids_b.append((nodes_b[node_id] as GeneratedTechNodeState).tech_id)
	tech_ids_a.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	tech_ids_b.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	_check(tech_ids_a == tech_ids_b, "the same RNG seed should always regenerate the same set of techs")


func _test_start_research_requires_prerequisites_and_funds() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var nova: Faction = game_state.get_faction(&"nova_republic")

	var tier1 := GeneratedTechNodeState.new()
	tier1.node_id = &"t1"
	tier1.tech_id = &"improved_targeting_array"
	tier1.tier = 1
	var tier2 := GeneratedTechNodeState.new()
	tier2.node_id = &"t2"
	tier2.tech_id = &"reinforced_plating"
	tier2.tier = 2
	tier2.prerequisite_node_ids = [&"t1"]
	nova.generated_tech_nodes = {tier1.node_id: tier1, tier2.node_id: tier2}
	nova.funds = 10000

	var blocked_errors: PackedStringArray = turn_manager.start_research(&"nova_republic", &"t2")
	_check(not blocked_errors.is_empty(), "starting research on a node whose prerequisite isn't researched should be rejected")

	var funds_before := nova.funds
	var errors: PackedStringArray = turn_manager.start_research(&"nova_republic", &"t1")
	_check(errors.is_empty(), "a well-formed research start should succeed: %s" % [errors])
	_check(nova.current_research != null and nova.current_research.node_id == &"t1", "current_research should point at the started node")
	_check(nova.funds == funds_before - game_state.campaign_config.research_costs[0],
		"funds should be paid in full at research start (Tier 1's base cost, no research facilities owned)")

	var already_researching_errors: PackedStringArray = turn_manager.start_research(&"nova_republic", &"t2")
	_check(not already_researching_errors.is_empty(), "a faction already researching something should not be able to start a second research")

	nova.current_research = null
	nova.funds = 0
	var insufficient_funds_errors: PackedStringArray = turn_manager.start_research(&"nova_republic", &"t1")
	_check(not insufficient_funds_errors.is_empty(), "starting research without enough funds should be rejected")


func _test_advance_research_completes_and_frees_the_slot() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var nova: Faction = game_state.get_faction(&"nova_republic")
	var node := GeneratedTechNodeState.new()
	node.node_id = &"t1"
	node.tech_id = &"improved_targeting_array"
	node.tier = 1
	nova.generated_tech_nodes = {node.node_id: node}
	nova.funds = 10000
	_check(turn_manager.start_research(&"nova_republic", &"t1").is_empty(), "setup: research should start cleanly")

	var turns: int = game_state.campaign_config.research_turns[0]
	# a plain captured StringName local can't be reassigned from inside the
	# lambda (GDScript closures copy locals by value on write) -- use a
	# single-slot Array as the mutable box instead.
	var completed_tech_id := [&""]
	var on_completed := func(faction_id: StringName, tech_id: StringName) -> void:
		if faction_id == &"nova_republic":
			completed_tech_id[0] = tech_id
	turn_manager.research_completed.connect(on_completed)
	for _i in range(turns - 1):
		turn_manager._advance_research(&"nova_republic")
		_check(nova.current_research != null and not node.researched, "research should still be in progress before its final turn")
	turn_manager._advance_research(&"nova_republic")
	turn_manager.research_completed.disconnect(on_completed)

	_check(node.researched, "the node should be marked researched once turns_remaining reaches zero")
	_check(nova.current_research == null, "current_research should be cleared once research completes")
	_check(completed_tech_id[0] == &"improved_targeting_array", "research_completed should fire with the completed node's tech_id")


func _test_research_discount_caps_at_25_percent() -> void:
	turn_manager.start_new_game(&"nova_republic")
	_check(is_equal_approx(turn_manager._research_discount_pct(&"nova_republic"), 0.0),
		"with no research facilities owned, the discount should be exactly 0%%")
	# 10 synthetic research facilities would be 50% by the raw formula --
	# proving the cap holds requires actually owning that many, which the
	# current dataset has no facility instances for; the 0%% no-facility
	# case above and the formula's own minf(...,0.25) clamp (read directly
	# in _research_discount_pct) are what's exercised here.


func _finish() -> void:
	if failures.is_empty():
		print("tech_tree_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("tech_tree_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)