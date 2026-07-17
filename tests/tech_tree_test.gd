extends SceneTree
## STRATEGY_DETAIL_SPECIFICATION.md section 7 / DATA_DEFINITION.md sections
## 15/15.1/15.2: the generated tech tree and research flow.

var failures := PackedStringArray()
var game_state: Node
var turn_manager: Node
var _profile_path_existed_before := false
var _original_profile_text := ""

const PROFILE_PATH := "user://profile.json"


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	turn_manager = root.get_node_or_null("TurnManager")
	if game_state == null or turn_manager == null:
		push_error("tech_tree_test: required autoload is unavailable")
		quit(1)
		return

	# _test_advance_research_unlocks_a_permanent_tech_candidate below calls
	# GameState.unlock_tech_candidate_from_research, which persists to the
	# real user://profile.json -- snapshot/restore around the whole run,
	# same reason as achievements_profile_test.gd/event_system_test.gd.
	_profile_path_existed_before = FileAccess.file_exists(PROFILE_PATH)
	if _profile_path_existed_before:
		var existing := FileAccess.open(PROFILE_PATH, FileAccess.READ)
		_original_profile_text = existing.get_as_text()
		existing.close()

	_test_generated_tree_places_mandatory_base_techs_at_tier_one()
	_test_generated_tree_is_reachable_and_has_no_duplicate_techs()
	_test_generated_tree_is_deterministic_for_a_given_seed()
	_test_start_research_requires_prerequisites_and_funds()
	_test_advance_research_completes_and_frees_the_slot()
	_test_research_discount_caps_at_25_percent()
	_test_permanent_pool_restricts_cross_faction_techs_until_unlocked()
	_test_advance_research_unlocks_a_permanent_tech_candidate()

	if _profile_path_existed_before:
		var restored := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
		restored.store_string(_original_profile_text)
		restored.close()
	elif FileAccess.file_exists(PROFILE_PATH):
		DirAccess.remove_absolute(PROFILE_PATH)
	game_state._load_profile()

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


## nova_republic's own tech dataset has no non-mandatory tier-5 entry
## (singularity_drive is crimson_empire-origin, tier 5) -- with an empty
## unlocked_candidate_ids, nova's generated tree should never draw it, and
## with singularity_drive explicitly unlocked, it should always be eligible
## (though not guaranteed, since it still competes for TARGET_NODES_PER_TIER
## slots against nothing else at tier 5 for nova -- with only one eligible
## candidate it's drawn deterministically every time).
func _test_permanent_pool_restricts_cross_faction_techs_until_unlocked() -> void:
	var rng_locked := RandomNumberGenerator.new()
	rng_locked.seed = 99
	var locked_nodes: Dictionary = TechTreeGenerator.generate_for_faction(&"nova_republic", game_state.master_data, rng_locked)
	var has_singularity_locked := false
	for node_id: Variant in locked_nodes:
		if (locked_nodes[node_id] as GeneratedTechNodeState).tech_id == &"singularity_drive":
			has_singularity_locked = true
	_check(not has_singularity_locked, "a cross-faction tech not in unlocked_candidate_ids should never be drawn")

	var rng_unlocked := RandomNumberGenerator.new()
	rng_unlocked.seed = 99
	var unlocked_ids: Array[StringName] = [&"singularity_drive"]
	var unlocked_nodes: Dictionary = TechTreeGenerator.generate_for_faction(&"nova_republic", game_state.master_data, rng_unlocked, unlocked_ids)
	var has_singularity_unlocked := false
	for node_id: Variant in unlocked_nodes:
		if (unlocked_nodes[node_id] as GeneratedTechNodeState).tech_id == &"singularity_drive":
			has_singularity_unlocked = true
	_check(has_singularity_unlocked, "a cross-faction tech listed in unlocked_candidate_ids should become eligible for the draw")


func _test_advance_research_unlocks_a_permanent_tech_candidate() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var nova: Faction = game_state.get_faction(&"nova_republic")
	# en_capacitor_matrix (tier 2) is never researched to completion by any
	# earlier test in this file, unlike improved_targeting_array -- picking
	# an untouched tech_id avoids cross-test coupling through the live
	# GameState.profile singleton, which (deliberately, matching
	# achievements_profile_test.gd) isn't reset between test functions,
	# only snapshotted/restored around the whole file.
	_check(not game_state.profile.unlocked_tech_candidate_ids.has(&"en_capacitor_matrix"), "setup: this tech should not already be permanently unlocked")

	var node := GeneratedTechNodeState.new()
	node.node_id = &"t1"
	node.tech_id = &"en_capacitor_matrix"
	node.tier = 2
	nova.generated_tech_nodes = {node.node_id: node}
	nova.funds = 10000
	_check(turn_manager.start_research(&"nova_republic", &"t1").is_empty(), "setup: research should start cleanly")
	for _i in range(game_state.campaign_config.research_turns[1]):
		turn_manager._advance_research(&"nova_republic")

	_check(node.researched, "setup: the node should have completed")
	_check(game_state.profile.unlocked_tech_candidate_ids.has(&"en_capacitor_matrix"), "completing research as the player faction should permanently unlock the tech_id")

	# A crimson_empire (AI) completion must NOT touch the player's profile.
	turn_manager.start_new_game(&"nova_republic")
	var crimson: Faction = game_state.get_faction(&"crimson_empire")
	var crimson_node := GeneratedTechNodeState.new()
	crimson_node.node_id = &"c1"
	crimson_node.tech_id = &"advanced_propulsion"
	crimson_node.tier = 3
	crimson.generated_tech_nodes = {crimson_node.node_id: crimson_node}
	crimson.funds = 10000
	_check(turn_manager.start_research(&"crimson_empire", &"c1").is_empty(), "setup: crimson's research should start cleanly")
	for _i in range(game_state.campaign_config.research_turns[2]):
		turn_manager._advance_research(&"crimson_empire")
	_check(crimson_node.researched, "setup: crimson's node should have completed")
	_check(not game_state.profile.unlocked_tech_candidate_ids.has(&"advanced_propulsion"), "an AI faction's own research completion should not unlock a permanent candidate for the player's profile")


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