extends SceneTree
## EVENT_DETAIL_SPECIFICATION.md / DATA_DEFINITION.md section 22:
## EventConditionEvaluator, EventEffectApplier, and GameState's
## check_pending_events/resolve_event_choice/auto_resolve_pending_events.

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
		push_error("event_system_test: required autoload is unavailable")
		quit(1)
		return

	# resolve_event_choice persists to the real user://profile.json for MAIN
	# events -- snapshot/restore around the whole run, same reason as
	# achievements_profile_test.gd (user:// survives across --script runs).
	_profile_path_existed_before = FileAccess.file_exists(PROFILE_PATH)
	if _profile_path_existed_before:
		var existing := FileAccess.open(PROFILE_PATH, FileAccess.READ)
		_original_profile_text = existing.get_as_text()
		existing.close()

	_test_master_data_loaded_sample_events()
	_test_condition_tree_boolean_composition()
	_test_condition_leaf_types()
	_test_squad_near_region_bfs_hop_cap()
	_test_effect_applier_funds_materials_relation_flag()
	_test_effect_applier_tech_candidate_dedup()
	_test_effect_applier_pilot_leave_blocks_reassignment()
	_test_check_pending_events_sorts_main_before_sub_and_gates_once_per_campaign()
	_test_resolve_event_choice_applies_effect_and_records_choice_flag()
	_test_event_choice_selected_condition_gates_a_followup_event()
	_test_auto_resolve_picks_first_choice_for_ai_faction()
	_test_turn_manager_wires_events_into_begin_faction_turn()
	_test_save_load_round_trips_event_state()

	if _profile_path_existed_before:
		var restored := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
		restored.store_string(_original_profile_text)
		restored.close()
	elif FileAccess.file_exists(PROFILE_PATH):
		DirAccess.remove_absolute(PROFILE_PATH)
	game_state._load_profile()

	_finish()


func _test_master_data_loaded_sample_events() -> void:
	_check(game_state.master_data_errors.is_empty(), "event/event_effect data failed master-data validation: %s" % game_state.master_data_errors)
	_check(game_state.master_data.events.size() == 8, "expected exactly 8 sample events in the standard dataset")
	_check(game_state.master_data.event_effects.size() == 11, "expected exactly 11 sample event effects in the standard dataset")


func _test_condition_tree_boolean_composition() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var true_leaf := {"type": "turn_at_least", "turn": 1}
	var false_leaf := {"type": "turn_at_least", "turn": 999}
	_check(EventConditionEvaluator.evaluate({}, game_state, &"nova_republic"), "an empty condition_tree should always be true")
	_check(EventConditionEvaluator.evaluate({"all": [true_leaf, true_leaf]}, game_state, &"nova_republic"), "all() of two true leaves should be true")
	_check(not EventConditionEvaluator.evaluate({"all": [true_leaf, false_leaf]}, game_state, &"nova_republic"), "all() with one false leaf should be false")
	_check(EventConditionEvaluator.evaluate({"any": [false_leaf, true_leaf]}, game_state, &"nova_republic"), "any() with one true leaf should be true")
	_check(not EventConditionEvaluator.evaluate({"any": [false_leaf, false_leaf]}, game_state, &"nova_republic"), "any() of two false leaves should be false")
	_check(EventConditionEvaluator.evaluate({"not": false_leaf}, game_state, &"nova_republic"), "not() of a false leaf should be true")
	_check(not EventConditionEvaluator.evaluate({"not": true_leaf}, game_state, &"nova_republic"), "not() of a true leaf should be false")
	_check(EventConditionEvaluator.evaluate({"all": [{"any": [false_leaf, true_leaf]}, {"not": false_leaf}]}, game_state, &"nova_republic"), "nested all/any/not should compose correctly")


func _test_condition_leaf_types() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var nova: Faction = game_state.get_faction(&"nova_republic")

	_check(EventConditionEvaluator.evaluate({"type": "region_owned", "region_id": &"nova_capital"}, game_state, &"nova_republic"), "nova_republic should own its own starting capital")
	_check(not EventConditionEvaluator.evaluate({"type": "region_owned", "region_id": &"crimson_capital"}, game_state, &"nova_republic"), "nova_republic should not own crimson's capital")
	_check(EventConditionEvaluator.evaluate({"type": "region_not_owned", "region_id": &"crimson_capital"}, game_state, &"nova_republic"), "region_not_owned should be true for a region nova_republic doesn't own")

	var node := GeneratedTechNodeState.new()
	node.node_id = &"t1"
	node.tech_id = &"improved_targeting_array"
	node.tier = 1
	node.researched = true
	nova.generated_tech_nodes[node.node_id] = node
	_check(EventConditionEvaluator.evaluate({"type": "tech_researched", "tech_id": &"improved_targeting_array"}, game_state, &"nova_republic"), "tech_researched should see the researched node")
	_check(not EventConditionEvaluator.evaluate({"type": "tech_researched", "tech_id": &"advanced_propulsion"}, game_state, &"nova_republic"), "tech_researched should be false for an unresearched tech_id")

	_check(EventConditionEvaluator.evaluate({"type": "pilot_assigned", "pilot_id": &"aria_nova"}, game_state, &"nova_republic"), "aria_nova should be auto-assigned to a unit at new-game seeding")
	var pilot: PilotState = game_state.campaign_runtime.get_pilot(&"aria_nova")
	game_state.campaign_runtime.unassign_pilot(&"aria_nova")
	_check(not EventConditionEvaluator.evaluate({"type": "pilot_assigned", "pilot_id": &"aria_nova"}, game_state, &"nova_republic"), "pilot_assigned should go false once unassigned")
	pilot.injury_turns_remaining = 3
	_check(EventConditionEvaluator.evaluate({"type": "pilot_injured", "pilot_id": &"aria_nova"}, game_state, &"nova_republic"), "pilot_injured should see the injury countdown")

	var relation: RelationState = game_state.campaign_runtime.get_relation_state(&"nova_republic", &"crimson_empire")
	relation.friendship = 40  # RelationState.relation_band(): <=20 NEUTRAL, <=60 FRIENDLY, else CLOSE
	_check(EventConditionEvaluator.evaluate({"type": "relation_band_at_least", "other_faction_id": &"crimson_empire", "band": &"friendly"}, game_state, &"nova_republic"), "friendship 40 should be at least FRIENDLY")
	_check(not EventConditionEvaluator.evaluate({"type": "relation_band_at_least", "other_faction_id": &"crimson_empire", "band": &"close"}, game_state, &"nova_republic"), "friendship 40 should not be at least CLOSE")
	relation.treaty_type = GameEnums.TreatyType.CEASEFIRE
	_check(EventConditionEvaluator.evaluate({"type": "treaty_active", "other_faction_id": &"crimson_empire", "treaty_type": &"ceasefire"}, game_state, &"nova_republic"), "treaty_active should match the active ceasefire")
	_check(not EventConditionEvaluator.evaluate({"type": "treaty_active", "other_faction_id": &"crimson_empire", "treaty_type": &"non_aggression"}, game_state, &"nova_republic"), "treaty_active should not match a different treaty type")

	nova.total_units_captured = 3
	_check(EventConditionEvaluator.evaluate({"type": "capture_count_at_least", "count": 3}, game_state, &"nova_republic"), "capture_count_at_least should read Faction.total_units_captured")
	_check(not EventConditionEvaluator.evaluate({"type": "capture_count_at_least", "count": 4}, game_state, &"nova_republic"), "capture_count_at_least should fail below the threshold")

	_check(EventConditionEvaluator.evaluate({"type": "region_count_at_least", "count": 1}, game_state, &"nova_republic"), "nova_republic starts owning at least 1 region")
	_check(not EventConditionEvaluator.evaluate({"type": "region_count_at_least", "count": 999}, game_state, &"nova_republic"), "region_count_at_least should fail for an absurd threshold")

	nova.event_flags[&"met_rival_scout"] = true
	_check(EventConditionEvaluator.evaluate({"type": "event_flag_set", "flag": &"met_rival_scout"}, game_state, &"nova_republic"), "event_flag_set should read Faction.event_flags")
	_check(not EventConditionEvaluator.evaluate({"type": "event_flag_set", "flag": &"never_set"}, game_state, &"nova_republic"), "event_flag_set should be false for an unset flag")

	nova.event_flags[&"choice:some_event"] = "brave"
	_check(EventConditionEvaluator.evaluate({"type": "event_choice_selected", "event_id": &"some_event", "choice_id": &"brave"}, game_state, &"nova_republic"), "event_choice_selected should match the recorded choice")
	_check(not EventConditionEvaluator.evaluate({"type": "event_choice_selected", "event_id": &"some_event", "choice_id": &"cautious"}, game_state, &"nova_republic"), "event_choice_selected should not match a different choice_id")


func _test_squad_near_region_bfs_hop_cap() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var squad: SquadState = null
	for candidate: SquadState in game_state.campaign_runtime.squads_by_id.values():
		if candidate.owner_faction_id == &"nova_republic":
			squad = candidate
			break
	_check(squad != null, "setup: nova_republic should have at least one seeded squad")
	squad.region_id = &"nova_border"
	# nova_border -> crimson_border (1) -> crimson_outpost/crimson_shipyard (2) -> crimson_capital (3)
	_check(EventConditionEvaluator.evaluate({"type": "squad_near_region", "target_region_id": &"crimson_capital", "max_hops": 3}, game_state, &"nova_republic"), "3 hops should be enough to reach crimson_capital from nova_border")
	_check(not EventConditionEvaluator.evaluate({"type": "squad_near_region", "target_region_id": &"crimson_capital", "max_hops": 2}, game_state, &"nova_republic"), "2 hops should not be enough to reach crimson_capital from nova_border")


func _test_effect_applier_funds_materials_relation_flag() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var nova: Faction = game_state.get_faction(&"nova_republic")
	nova.funds = 1000
	nova.materials = 500

	var funds_effect := EventEffectDef.new()
	funds_effect.effect_type = GameEnums.EventEffectType.FUNDS
	funds_effect.payload = {"amount": -5000}
	EventEffectApplier.apply(game_state, &"nova_republic", funds_effect)
	_check(nova.funds == 0, "FUNDS effect should floor at 0 instead of going negative")

	var materials_effect := EventEffectDef.new()
	materials_effect.effect_type = GameEnums.EventEffectType.MATERIALS
	materials_effect.payload = {"amount": 250}
	EventEffectApplier.apply(game_state, &"nova_republic", materials_effect)
	_check(nova.materials == 750, "MATERIALS effect should add to the current amount")

	var relation_effect := EventEffectDef.new()
	relation_effect.effect_type = GameEnums.EventEffectType.RELATION
	relation_effect.payload = {"other_faction_id": &"crimson_empire", "delta": 20}
	var before: int = game_state.campaign_runtime.get_relation_state(&"nova_republic", &"crimson_empire").friendship
	EventEffectApplier.apply(game_state, &"nova_republic", relation_effect)
	var after: int = game_state.campaign_runtime.get_relation_state(&"nova_republic", &"crimson_empire").friendship
	_check(after == before + 20, "RELATION effect should adjust friendship by delta")

	var flag_effect := EventEffectDef.new()
	flag_effect.effect_type = GameEnums.EventEffectType.EVENT_FLAG
	flag_effect.payload = {"flag": &"tested_flag", "value": true}
	EventEffectApplier.apply(game_state, &"nova_republic", flag_effect)
	_check(bool(nova.event_flags.get(&"tested_flag", false)), "EVENT_FLAG effect should set Faction.event_flags")


func _test_effect_applier_tech_candidate_dedup() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var nova: Faction = game_state.get_faction(&"nova_republic")
	# TechTreeGenerator draws from a real, non-deterministic campaign_rng
	# seed (start_new_game calls randomize()), so singularity_drive could
	# already be present by chance -- clear to a known-empty tree first.
	nova.generated_tech_nodes.clear()
	var before_count: int = nova.generated_tech_nodes.size()

	var tech_effect := EventEffectDef.new()
	tech_effect.effect_type = GameEnums.EventEffectType.TECH_CANDIDATE
	tech_effect.payload = {"tech_id": &"singularity_drive"}
	EventEffectApplier.apply(game_state, &"nova_republic", tech_effect)
	_check(nova.generated_tech_nodes.size() == before_count + 1, "TECH_CANDIDATE should add exactly one new node the first time")
	EventEffectApplier.apply(game_state, &"nova_republic", tech_effect)
	_check(nova.generated_tech_nodes.size() == before_count + 1, "TECH_CANDIDATE should not add a duplicate node for a tech_id already present")

	var found_node: GeneratedTechNodeState = null
	for node_id: Variant in nova.generated_tech_nodes:
		var node := nova.generated_tech_nodes[node_id] as GeneratedTechNodeState
		if node.tech_id == &"singularity_drive":
			found_node = node
	_check(found_node != null and found_node.gifted and not found_node.researched, "the granted node should be gifted=true and start unresearched")


## PILOT_LEAVE sets PilotState.available = false; this proves
## CampaignRuntimeState.assign_pilot_to_unit's new availability gate
## (added alongside this effect) actually reads it, the same way it already
## read is_injured().
func _test_effect_applier_pilot_leave_blocks_reassignment() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var pilot: PilotState = game_state.campaign_runtime.get_pilot(&"aria_nova")
	_check(pilot != null and pilot.is_assigned(), "setup: aria_nova should start assigned to a unit")
	var unit_id: StringName = pilot.assigned_unit_instance_id

	var leave_effect := EventEffectDef.new()
	leave_effect.effect_type = GameEnums.EventEffectType.PILOT_LEAVE
	leave_effect.payload = {"pilot_id": &"aria_nova"}
	EventEffectApplier.apply(game_state, &"nova_republic", leave_effect)

	_check(not pilot.available, "PILOT_LEAVE should mark the pilot unavailable")
	_check(not pilot.is_assigned(), "PILOT_LEAVE should unassign the pilot from their unit")
	var errors: PackedStringArray = game_state.campaign_runtime.assign_pilot_to_unit(&"aria_nova", unit_id)
	_check(not errors.is_empty(), "an unavailable pilot should be rejected for reassignment")


func _test_check_pending_events_sorts_main_before_sub_and_gates_once_per_campaign() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var nova: Faction = game_state.get_faction(&"nova_republic")
	game_state.set_region_owner(&"nova_outpost", &"nova_republic")
	game_state.set_region_owner(&"nova_shipyard", &"nova_republic")

	game_state.check_pending_events(&"nova_republic")
	# nova_main_001_first_contact (turn_at_least 1, MAIN) and
	# nova_sub_001_border_skirmish (region_count_at_least 2, SUB) should both
	# be satisfied by fresh-game state plus the two extra regions above.
	_check(nova.pending_event_ids.has(&"nova_main_001_first_contact"), "nova_main_001_first_contact's condition should already be satisfied at new game")
	_check(nova.pending_event_ids.has(&"nova_sub_001_border_skirmish"), "nova_sub_001_border_skirmish's region_count_at_least condition should be satisfied")
	_check(int(nova.pending_event_ids.find(&"nova_main_001_first_contact")) < int(nova.pending_event_ids.find(&"nova_sub_001_border_skirmish")), "MAIN events should sort before SUB events regardless of id")

	var pending_count_before: int = nova.pending_event_ids.size()
	game_state.check_pending_events(&"nova_republic")
	_check(nova.pending_event_ids.size() == pending_count_before, "re-checking should not register the same once_per_campaign events a second time while still pending")


func _test_resolve_event_choice_applies_effect_and_records_choice_flag() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var nova: Faction = game_state.get_faction(&"nova_republic")
	game_state.check_pending_events(&"nova_republic")
	_check(nova.pending_event_ids.has(&"nova_main_001_first_contact"), "setup: the MAIN event should be pending")

	var before: int = game_state.campaign_runtime.get_relation_state(&"nova_republic", &"crimson_empire").friendship
	var errors: PackedStringArray = game_state.resolve_event_choice(&"nova_republic", &"nova_main_001_first_contact", &"diplomatic")
	_check(errors.is_empty(), "resolving a valid choice should not error: %s" % [errors])
	_check(not nova.pending_event_ids.has(&"nova_main_001_first_contact"), "the resolved event should be removed from pending_event_ids")
	var after: int = game_state.campaign_runtime.get_relation_state(&"nova_republic", &"crimson_empire").friendship
	_check(after == before + 15, "the diplomatic choice's relation_gain_toward_crimson effect should have applied")
	_check(bool(nova.event_flags.get(&"chose_diplomatic", false)), "the diplomatic choice's flag_chose_diplomatic effect should have applied")
	_check(String(nova.event_flags.get(&"choice:nova_main_001_first_contact", "")) == "diplomatic", "resolve_event_choice should record 'choice:<event_id>' -> choice_id")
	_check(game_state.profile.has_viewed_event(&"nova_main_001_first_contact"), "a resolved MAIN event should be added to the cross-campaign recap list")

	var bad_errors: PackedStringArray = game_state.resolve_event_choice(&"nova_republic", &"nova_main_001_first_contact", &"diplomatic")
	_check(not bad_errors.is_empty(), "resolving an event that is no longer pending should error")


func _test_event_choice_selected_condition_gates_a_followup_event() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var nova: Faction = game_state.get_faction(&"nova_republic")
	game_state.check_pending_events(&"nova_republic")
	game_state.resolve_event_choice(&"nova_republic", &"nova_main_001_first_contact", &"diplomatic")
	_check(not nova.pending_event_ids.has(&"nova_sub_002_diplomacy_pays_off"), "nova_sub_002_diplomacy_pays_off should not be pending before its trigger condition is checked again")
	game_state.check_pending_events(&"nova_republic")
	_check(nova.pending_event_ids.has(&"nova_sub_002_diplomacy_pays_off"), "choosing 'diplomatic' should satisfy nova_sub_002_diplomacy_pays_off's event_choice_selected condition")


func _test_auto_resolve_picks_first_choice_for_ai_faction() -> void:
	turn_manager.start_new_game(&"nova_republic")  # crimson_empire is AI-controlled
	var crimson: Faction = game_state.get_faction(&"crimson_empire")
	game_state.check_pending_events(&"crimson_empire")
	_check(crimson.pending_event_ids.has(&"crimson_main_001_iron_resolve"), "setup: crimson's MAIN event should be pending")
	game_state.auto_resolve_pending_events(&"crimson_empire")
	_check(crimson.pending_event_ids.is_empty(), "auto_resolve_pending_events should clear the whole queue")
	_check(bool(crimson.event_flags.get(&"chose_aggressive", false)), "auto-resolve should deterministically pick the first choice_entries option (aggressive)")
	_check(not bool(crimson.event_flags.get(&"chose_diplomatic", false)), "auto-resolve should not have applied the second choice's effects")


## Unlike the other tests above (which call GameState.check_pending_events/
## auto_resolve_pending_events directly), this exercises the actual
## TurnManager._begin_faction_turn wiring: start_new_game already calls
## _begin_faction_turn once for the player faction, and commit_turn()
## advances to (and begins) every AI faction's turn in the same call.
func _test_turn_manager_wires_events_into_begin_faction_turn() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var nova: Faction = game_state.get_faction(&"nova_republic")
	_check(nova.pending_event_ids.has(&"nova_main_001_first_contact"), "TurnManager.start_new_game's own _begin_faction_turn call should already have registered the player's pending events")

	# Resolve the player's own turn's events so commit_turn can proceed
	# through the full faction cycle without EventPanel (no UI in a test).
	for event_id: StringName in nova.pending_event_ids.duplicate():
		game_state.resolve_event_choice(&"nova_republic", event_id, &"diplomatic")
	turn_manager.commit_turn()
	for _frame in range(120):
		if turn_manager.active_faction_id == &"nova_republic" and turn_manager.current_phase == turn_manager.Phase.ORDERS:
			break
		await process_frame

	var crimson: Faction = game_state.get_faction(&"crimson_empire")
	_check(crimson.pending_event_ids.is_empty(), "an AI faction's own _begin_faction_turn should auto-resolve its pending events immediately, leaving none queued")
	_check(crimson.triggered_event_ids.has(&"crimson_main_001_iron_resolve"), "the AI faction's MAIN event should have been registered and (auto-)resolved during its turn")


func _test_save_load_round_trips_event_state() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var nova: Faction = game_state.get_faction(&"nova_republic")
	nova.event_flags[&"round_trip_flag"] = true
	nova.pending_event_ids = [&"nova_sub_001_border_skirmish"] as Array[StringName]
	nova.triggered_event_ids = [&"nova_main_001_first_contact", &"nova_sub_001_border_skirmish"] as Array[StringName]
	game_state.campaign_runtime.campaign_event_history = [&"nova_sub_001_border_skirmish"] as Array[StringName]

	var saved: Dictionary = game_state.to_save_dict()
	turn_manager.start_new_game(&"crimson_empire")  # mutate live state away before reloading
	var errors: PackedStringArray = game_state.apply_save_dict(saved)
	_check(errors.is_empty(), "reloading saved event state should not error: %s" % [errors])

	var reloaded: Faction = game_state.get_faction(&"nova_republic")
	_check(bool(reloaded.event_flags.get(&"round_trip_flag", false)), "event_flags should survive a save/load round trip")
	_check(reloaded.pending_event_ids == [&"nova_sub_001_border_skirmish"], "pending_event_ids should survive a save/load round trip")
	_check(reloaded.triggered_event_ids.has(&"nova_main_001_first_contact") and reloaded.triggered_event_ids.has(&"nova_sub_001_border_skirmish"), "triggered_event_ids should survive a save/load round trip")
	_check(game_state.campaign_runtime.campaign_event_history == [&"nova_sub_001_border_skirmish"], "campaign_event_history should survive a save/load round trip")


func _finish() -> void:
	if failures.is_empty():
		print("event_system_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("event_system_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
