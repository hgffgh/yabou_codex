extends SceneTree

var failures := PackedStringArray()
var game_state: Node
var turn_manager: Node


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	turn_manager = root.get_node_or_null("TurnManager")
	if game_state == null or turn_manager == null:
		push_error("diplomacy_test: required autoload is unavailable")
		quit(1)
		return

	_test_initial_friendship_and_band()
	_test_combat_events_lower_friendship()
	_test_tick_week_treaty_countdown_and_cooldowns()
	_test_propose_treaty_rejects_invalid_duration()
	_test_propose_treaty_success_forms_treaty_and_retreats_squads()
	_test_propose_treaty_failure_costs_nothing_but_sets_cooldown()
	_test_active_treaty_blocks_invasion_movement()
	_test_break_treaty_penalizes_the_breaker_only()
	_test_gift_resources_requires_minimum_and_applies_cooldown()
	_test_gift_tech_registers_a_new_gifted_node()
	_test_gifted_node_uses_the_any_prior_tier_prerequisite_rule()
	_test_purchase_intel_transfers_only_confirmed_squads()
	_test_ransom_captured_unit_returns_it_to_the_original_faction()
	_finish()


func _test_initial_friendship_and_band() -> void:
	turn_manager.start_new_game(&"nova_republic")
	_check(Diplomacy.friendship(game_state, &"nova_republic", &"crimson_empire") == GameConstants.INITIAL_FRIENDSHIP,
		"initial friendship was not the fixed -50 default")
	_check(Diplomacy.relation_band(game_state, &"nova_republic", &"crimson_empire") == GameEnums.RelationBand.HOSTILE,
		"-50 friendship did not classify as HOSTILE")
	_check(not Diplomacy.has_active_treaty(game_state, &"nova_republic", &"crimson_empire"),
		"factions should start at war with no treaty")


func _test_combat_events_lower_friendship() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var before := Diplomacy.friendship(game_state, &"nova_republic", &"crimson_empire")
	Diplomacy.apply_combat_events(game_state, [{"type": "battle", "attacker_id": &"nova_republic", "defender_id": &"crimson_empire"}])
	var after := Diplomacy.friendship(game_state, &"nova_republic", &"crimson_empire")
	_check(after == before + GameConstants.COMBAT_FRIENDSHIP_PENALTY, "combat event did not apply the symmetric attack penalty")
	_check(Diplomacy.friendship(game_state, &"crimson_empire", &"nova_republic") == after,
		"friendship must read identically from either faction's perspective")


func _test_tick_week_treaty_countdown_and_cooldowns() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var relation: RelationState = game_state.campaign_runtime.get_relation_state(&"nova_republic", &"crimson_empire")
	relation.treaty_type = GameEnums.TreatyType.CEASEFIRE
	relation.treaty_turns_remaining = 2
	relation.proposal_cooldown_turns = 1
	var friendship_before: int = relation.friendship

	Diplomacy.tick_week(game_state, 1)
	_check(relation.friendship == friendship_before + GameConstants.TREATY_ACTIVE_FRIENDSHIP_GAIN_PER_TURN,
		"active treaty did not add +1 friendship for the turn")
	_check(relation.treaty_turns_remaining == 1, "treaty countdown did not decrement")
	_check(relation.proposal_cooldown_turns == 0, "proposal cooldown did not decrement")
	var log_entry: Dictionary = game_state.campaign_runtime.diplomacy_log[-1]
	_check(StringName(log_entry.action_type) == &"treaty_expiring",
		"one turn before expiry should log a treaty_expiring notice, got %s" % [game_state.campaign_runtime.diplomacy_log])

	Diplomacy.tick_week(game_state, 2)
	_check(relation.treaty_turns_remaining == 0 and relation.treaty_type == GameEnums.TreatyType.NONE,
		"treaty did not auto-revert to NONE once its countdown reached zero")
	var final_entry: Dictionary = game_state.campaign_runtime.diplomacy_log[-1]
	_check(StringName(final_entry.action_type) == &"treaty_expired", "expiry should log a treaty_expired entry")


func _test_propose_treaty_rejects_invalid_duration() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var result := Diplomacy.propose_treaty(game_state, &"nova_republic", &"crimson_empire", GameEnums.TreatyType.CEASEFIRE, 4)
	_check(not (result.errors as PackedStringArray).is_empty(), "an off-menu duration should be rejected")
	_check(not result.success, "a rejected proposal must not report success")


## Forces a guaranteed roll by driving friendship to its maximum first (a
## friendship of 100 alone pushes the ceasefire success rate to 95%, the
## formula's own cap), then pins campaign_rng deterministically so the roll
## itself is reproducible instead of flaky.
func _test_propose_treaty_success_forms_treaty_and_retreats_squads() -> void:
	turn_manager.start_new_game(&"nova_republic")
	game_state.campaign_rng.seed = 2  # rolls 51 on the first draw, comfortably under the 95%-capped rate below
	var relation: RelationState = game_state.campaign_runtime.get_relation_state(&"nova_republic", &"crimson_empire")
	relation.friendship = 100

	var stray: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"crimson_capital")
	var stray_squad: SquadState = stray.squad
	stray_squad.move_origin_region_id = &"nova_border"

	var nova: Faction = game_state.get_faction(&"nova_republic")
	var crimson: Faction = game_state.get_faction(&"crimson_empire")
	var nova_funds_before := nova.funds
	var crimson_funds_before := crimson.funds

	var result := Diplomacy.propose_treaty(game_state, &"nova_republic", &"crimson_empire", GameEnums.TreatyType.CEASEFIRE, 3, 300, 0)
	_check((result.errors as PackedStringArray).is_empty(), "a well-formed proposal should not error: %s" % [result.errors])
	_check(result.success, "a 95%%-capped success rate should succeed with this seed")
	_check(relation.treaty_type == GameEnums.TreatyType.CEASEFIRE and relation.treaty_turns_remaining == 3,
		"a successful proposal must establish the treaty")
	_check(nova.funds == nova_funds_before - 300 and crimson.funds == crimson_funds_before + 300,
		"the offered funds were not transferred from proposer to target")
	_check(stray_squad.region_id == &"nova_border",
		"a squad stranded in the new treaty partner's territory should retreat to its move origin")


func _test_propose_treaty_failure_costs_nothing_but_sets_cooldown() -> void:
	turn_manager.start_new_game(&"nova_republic")
	game_state.campaign_rng.seed = 1
	var relation: RelationState = game_state.campaign_runtime.get_relation_state(&"nova_republic", &"crimson_empire")
	relation.friendship = -100
	relation.violator_faction_id = &"nova_republic"
	relation.violation_penalty_turns = 10
	relation.violation_success_penalty_pct = 10

	var nova: Faction = game_state.get_faction(&"nova_republic")
	var funds_before := nova.funds
	var result := Diplomacy.propose_treaty(game_state, &"nova_republic", &"crimson_empire", GameEnums.TreatyType.NON_AGGRESSION, 30, 300, 0)
	_check(result.success_rate_pct == GameConstants.TREATY_SUCCESS_MIN_PCT,
		"a maximally unfavorable proposal should clamp to the 5%% floor, got %d" % int(result.success_rate_pct))
	_check(not result.success, "a 5%% floor roll with seed 1 should fail")
	_check(nova.funds == funds_before, "a failed proposal must not consume the offered funds")
	_check(relation.proposal_cooldown_turns == GameConstants.DIPLOMACY_PROPOSAL_COOLDOWN_TURNS,
		"a rolled failure must set the 5-turn proposal cooldown")

	var second_attempt := Diplomacy.propose_treaty(game_state, &"nova_republic", &"crimson_empire", GameEnums.TreatyType.NON_AGGRESSION, 10, 0, 0)
	_check(not (second_attempt.errors as PackedStringArray).is_empty(),
		"proposing again during the cooldown should be rejected")


func _test_active_treaty_blocks_invasion_movement() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var relation: RelationState = game_state.campaign_runtime.get_relation_state(&"nova_republic", &"crimson_empire")
	relation.treaty_type = GameEnums.TreatyType.NON_AGGRESSION
	relation.treaty_turns_remaining = 10

	var rollout: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"nova_border")
	var errors: PackedStringArray = game_state.plan_squad_movement(rollout.squad.squad_id, &"crimson_border", &"nova_republic")
	_check(not errors.is_empty(), "an active treaty must forbid planning a move into the partner's territory")

	relation.treaty_type = GameEnums.TreatyType.NONE
	relation.treaty_turns_remaining = 0
	var errors_after_expiry: PackedStringArray = game_state.plan_squad_movement(rollout.squad.squad_id, &"crimson_border", &"nova_republic")
	_check(errors_after_expiry.is_empty(), "movement should be allowed again once the treaty lapses: %s" % [errors_after_expiry])


func _test_break_treaty_penalizes_the_breaker_only() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var relation: RelationState = game_state.campaign_runtime.get_relation_state(&"nova_republic", &"crimson_empire")
	relation.treaty_type = GameEnums.TreatyType.CEASEFIRE
	relation.treaty_turns_remaining = 5
	relation.friendship = 0

	var errors := Diplomacy.break_treaty(game_state, &"nova_republic", &"crimson_empire")
	_check(errors.is_empty(), "breaking an active treaty should not error: %s" % [errors])
	_check(relation.treaty_type == GameEnums.TreatyType.NONE, "breaking must immediately clear the treaty")
	_check(relation.friendship == -GameConstants.TREATY_VIOLATION_FRIENDSHIP_PENALTY,
		"unilateral break must apply the 20-point friendship penalty")
	_check(relation.violator_faction_id == &"nova_republic", "the breaker must be recorded as the violator")

	# Isolate the violation term itself (toggling only the violator_faction_id
	# fields, same proposer/target direction each time) rather than comparing
	# across the two factions' own success rates, since nova_republic and
	# crimson_empire own different unit rosters with different total power --
	# that asymmetric power_bonus term would otherwise contaminate a
	# breaker-vs-victim comparison.
	var breaker_rate_with_penalty := Diplomacy.compute_success_rate_pct(game_state, &"nova_republic", &"crimson_empire", GameEnums.TreatyType.CEASEFIRE, 3)
	relation.violator_faction_id = &""
	relation.violation_penalty_turns = 0
	relation.violation_success_penalty_pct = 0
	var breaker_rate_without_penalty := Diplomacy.compute_success_rate_pct(game_state, &"nova_republic", &"crimson_empire", GameEnums.TreatyType.CEASEFIRE, 3)
	_check(breaker_rate_with_penalty == breaker_rate_without_penalty - GameConstants.TREATY_VIOLATION_SUCCESS_PENALTY_PCT,
		"the breaker's own future proposals must carry the violation success-rate penalty")

	relation.violator_faction_id = &"nova_republic"
	relation.violation_penalty_turns = 10
	relation.violation_success_penalty_pct = GameConstants.TREATY_VIOLATION_SUCCESS_PENALTY_PCT
	var victim_rate_with_violation_recorded := Diplomacy.compute_success_rate_pct(game_state, &"crimson_empire", &"nova_republic", GameEnums.TreatyType.CEASEFIRE, 3)
	relation.violator_faction_id = &""
	relation.violation_penalty_turns = 0
	relation.violation_success_penalty_pct = 0
	var victim_rate_without_violation := Diplomacy.compute_success_rate_pct(game_state, &"crimson_empire", &"nova_republic", GameEnums.TreatyType.CEASEFIRE, 3)
	_check(victim_rate_with_violation_recorded == victim_rate_without_violation,
		"the wronged faction's own proposals must not carry the breaker's violation penalty")

	var no_treaty_errors := Diplomacy.break_treaty(game_state, &"nova_republic", &"crimson_empire")
	_check(not no_treaty_errors.is_empty(), "breaking with no active treaty should error instead of silently no-op")


func _test_gift_resources_requires_minimum_and_applies_cooldown() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var below_minimum := Diplomacy.gift_resources(game_state, &"nova_republic", &"crimson_empire", 100, 50)
	_check(not below_minimum.is_empty(), "a gift below both minimums should be rejected")

	var relation: RelationState = game_state.campaign_runtime.get_relation_state(&"nova_republic", &"crimson_empire")
	var friendship_before: int = relation.friendship
	var nova: Faction = game_state.get_faction(&"nova_republic")
	var crimson: Faction = game_state.get_faction(&"crimson_empire")
	var nova_funds_before := nova.funds
	var crimson_funds_before := crimson.funds

	var errors := Diplomacy.gift_resources(game_state, &"nova_republic", &"crimson_empire", GameConstants.MIN_GIFT_FUNDS, 0)
	_check(errors.is_empty(), "a minimum-qualifying gift should succeed: %s" % [errors])
	_check(nova.funds == nova_funds_before - GameConstants.MIN_GIFT_FUNDS, "gift did not deduct funds from the giver")
	_check(crimson.funds == crimson_funds_before + GameConstants.MIN_GIFT_FUNDS, "gift did not credit funds to the receiver")
	_check(relation.friendship == friendship_before + GameConstants.GIFT_FRIENDSHIP_GAIN,
		"gift did not apply the fixed +5 friendship gain")

	var cooldown_errors := Diplomacy.gift_resources(game_state, &"nova_republic", &"crimson_empire", GameConstants.MIN_GIFT_FUNDS, 0)
	_check(not cooldown_errors.is_empty(), "gifting again immediately should be blocked by the shared 5-turn cooldown")


## Replaces both factions' generated trees with small, fully-controlled
## fixtures instead of relying on TechTreeGenerator's random draw, so this
## test is deterministic regardless of campaign_rng's seed.
func _test_gift_tech_registers_a_new_gifted_node() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var nova: Faction = game_state.get_faction(&"nova_republic")
	var crimson: Faction = game_state.get_faction(&"crimson_empire")

	var giver_node := GeneratedTechNodeState.new()
	giver_node.node_id = &"test_giver_node"
	giver_node.tech_id = &"improved_targeting_array"  # tier 1, giftable=true in the real data
	giver_node.tier = 1
	giver_node.researched = true
	var unresearched_node := GeneratedTechNodeState.new()
	unresearched_node.node_id = &"test_unresearched_node"
	unresearched_node.tech_id = &"reinforced_plating"
	unresearched_node.tier = 2
	var non_giftable_node := GeneratedTechNodeState.new()
	non_giftable_node.node_id = &"test_non_giftable_node"
	non_giftable_node.tech_id = &"nova_hull_foundation"  # giftable=false in the real data
	non_giftable_node.tier = 1
	non_giftable_node.researched = true
	nova.generated_tech_nodes = {
		giver_node.node_id: giver_node,
		unresearched_node.node_id: unresearched_node,
		non_giftable_node.node_id: non_giftable_node,
	}
	crimson.generated_tech_nodes = {}

	var unresearched_gift_errors := Diplomacy.gift_tech(game_state, &"nova_republic", &"crimson_empire", &"test_unresearched_node")
	_check(not unresearched_gift_errors.is_empty(), "gifting a node the giver hasn't researched should be rejected")
	var non_giftable_errors := Diplomacy.gift_tech(game_state, &"nova_republic", &"crimson_empire", &"test_non_giftable_node")
	_check(not non_giftable_errors.is_empty(), "a tech marked giftable=false must not be gift-able")

	var relation: RelationState = game_state.campaign_runtime.get_relation_state(&"nova_republic", &"crimson_empire")
	var friendship_before: int = relation.friendship
	var errors := Diplomacy.gift_tech(game_state, &"nova_republic", &"crimson_empire", &"test_giver_node")
	_check(errors.is_empty(), "a well-formed tech gift should succeed: %s" % [errors])
	_check(crimson.generated_tech_nodes.size() == 1, "the receiver should gain exactly one new node, got %d" % crimson.generated_tech_nodes.size())
	if crimson.generated_tech_nodes.size() == 1:
		var gifted_node: GeneratedTechNodeState = crimson.generated_tech_nodes.values()[0]
		_check(gifted_node.tech_id == &"improved_targeting_array" and gifted_node.gifted and not gifted_node.researched,
			"the gifted node should carry the giver's tech_id, be marked gifted, and start unresearched")
	_check(giver_node.researched, "the giver must keep their own researched node untouched")
	_check(relation.friendship == friendship_before + GameConstants.GIFT_FRIENDSHIP_GAIN,
		"tech gift should apply the same fixed +5 friendship gain as a resource gift")
	_check(relation.gift_cooldown_turns == GameConstants.DIPLOMACY_GIFT_COOLDOWN_TURNS,
		"tech gift should set the shared gift cooldown")

	var blocked_resource_gift := Diplomacy.gift_resources(game_state, &"nova_republic", &"crimson_empire", GameConstants.MIN_GIFT_FUNDS, 0)
	_check(not blocked_resource_gift.is_empty(), "a resource gift should be blocked by the cooldown a tech gift just set, since they share one pool")

	relation.gift_cooldown_turns = 0
	var duplicate_errors := Diplomacy.gift_tech(game_state, &"nova_republic", &"crimson_empire", &"test_giver_node")
	_check(not duplicate_errors.is_empty(), "gifting the same tech_id to a receiver who already has it should be rejected")


func _test_gifted_node_uses_the_any_prior_tier_prerequisite_rule() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var crimson: Faction = game_state.get_faction(&"crimson_empire")

	var gifted_tier1 := GeneratedTechNodeState.new()
	gifted_tier1.node_id = &"gift_tier1"
	gifted_tier1.tech_id = &"improved_targeting_array"
	gifted_tier1.tier = 1
	gifted_tier1.gifted = true
	crimson.generated_tech_nodes = {gifted_tier1.node_id: gifted_tier1}
	_check(turn_manager._node_prerequisites_met(crimson, gifted_tier1), "a gifted Tier 1 node should always be immediately researchable")

	var gifted_tier2 := GeneratedTechNodeState.new()
	gifted_tier2.node_id = &"gift_tier2"
	gifted_tier2.tech_id = &"reinforced_plating"
	gifted_tier2.tier = 2
	gifted_tier2.gifted = true
	crimson.generated_tech_nodes[gifted_tier2.node_id] = gifted_tier2
	_check(not turn_manager._node_prerequisites_met(crimson, gifted_tier2),
		"a gifted Tier 2 node should need any researched Tier 1 node first, not be free of prerequisites")

	gifted_tier1.researched = true
	_check(turn_manager._node_prerequisites_met(crimson, gifted_tier2),
		"once any Tier 1 node is researched (not a specific one), the gifted Tier 2 node should become available")


## No FactionDef exists for a third distinct faction in the current dataset,
## so this uses the same synthetic-squad approach as
## multi_faction_conflict_test.gd's pirate_faction fixture -- purchase_intel
## only needs a real Faction for the buyer and partner (funds/cooldown
## tracking); the third party is looked up purely by owner_faction_id.
func _test_purchase_intel_transfers_only_confirmed_squads() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var nova: Faction = game_state.get_faction(&"nova_republic")
	nova.funds = 10000

	var confirmed_unit := UnitInstanceState.new()
	confirmed_unit.instance_id = &"unit_pirate_confirmed"
	confirmed_unit.unit_def_id = &"crimson_bastion"
	confirmed_unit.owner_faction_id = &"pirate_faction"
	confirmed_unit.origin_faction_id = &"pirate_faction"
	confirmed_unit.current_hp = 100
	confirmed_unit.current_en = 100
	confirmed_unit.squad_id = &"squad_pirate_confirmed"
	confirmed_unit.slot_index = 0
	var confirmed_squad := SquadState.new()
	confirmed_squad.squad_id = &"squad_pirate_confirmed"
	confirmed_squad.owner_faction_id = &"pirate_faction"
	confirmed_squad.region_id = &"crimson_capital"
	confirmed_squad.assign_unit(confirmed_unit.instance_id, 0)
	game_state.campaign_runtime.units_by_id[confirmed_unit.instance_id] = confirmed_unit
	game_state.campaign_runtime.squads_by_id[confirmed_squad.squad_id] = confirmed_squad
	game_state.campaign_runtime.confirm_squad_intel(&"crimson_empire", confirmed_squad.squad_id, 1)

	var unconfirmed_unit := UnitInstanceState.new()
	unconfirmed_unit.instance_id = &"unit_pirate_unconfirmed"
	unconfirmed_unit.unit_def_id = &"crimson_bastion"
	unconfirmed_unit.owner_faction_id = &"pirate_faction"
	unconfirmed_unit.origin_faction_id = &"pirate_faction"
	unconfirmed_unit.current_hp = 100
	unconfirmed_unit.current_en = 100
	unconfirmed_unit.squad_id = &"squad_pirate_unconfirmed"
	unconfirmed_unit.slot_index = 0
	var unconfirmed_squad := SquadState.new()
	unconfirmed_squad.squad_id = &"squad_pirate_unconfirmed"
	unconfirmed_squad.owner_faction_id = &"pirate_faction"
	unconfirmed_squad.region_id = &"crimson_capital"
	unconfirmed_squad.assign_unit(unconfirmed_unit.instance_id, 0)
	game_state.campaign_runtime.units_by_id[unconfirmed_unit.instance_id] = unconfirmed_unit
	game_state.campaign_runtime.squads_by_id[unconfirmed_squad.squad_id] = unconfirmed_squad

	var result := Diplomacy.purchase_intel(game_state, &"nova_republic", &"crimson_empire", &"pirate_faction")
	_check((result.errors as PackedStringArray).is_empty(), "a well-formed purchase should not error: %s" % [result.errors])
	var confirmed_ids: Array = result.confirmed_squad_ids
	_check(confirmed_ids == [&"squad_pirate_confirmed"],
		"purchase should only transfer squads the partner already confirmed, got %s" % [confirmed_ids])
	_check(game_state.campaign_runtime.is_squad_confirmed(&"nova_republic", &"squad_pirate_confirmed"),
		"the buyer should now have the confirmed squad's intel")
	_check(not game_state.campaign_runtime.is_squad_confirmed(&"nova_republic", &"squad_pirate_unconfirmed"),
		"the buyer must not gain intel the partner never had")
	_check(nova.funds == 10000 - GameConstants.INTEL_PURCHASE_COST_FUNDS, "purchase did not deduct its fixed funds cost")

	var relation: RelationState = game_state.campaign_runtime.get_relation_state(&"nova_republic", &"crimson_empire")
	_check(relation.intel_purchase_cooldown_turns == GameConstants.DIPLOMACY_INTEL_PURCHASE_COOLDOWN_TURNS,
		"purchase must set the 5-turn cooldown")
	var repeat_result := Diplomacy.purchase_intel(game_state, &"nova_republic", &"crimson_empire", &"pirate_faction")
	_check(not (repeat_result.errors as PackedStringArray).is_empty(), "purchasing again during the cooldown should be rejected")


func _test_ransom_captured_unit_returns_it_to_the_original_faction() -> void:
	turn_manager.start_new_game(&"nova_republic")
	var captured := UnitInstanceState.new()
	captured.instance_id = &"unit_ransom_target"
	captured.unit_def_id = &"nova_scout"
	captured.owner_faction_id = &"crimson_empire"
	captured.origin_faction_id = &"nova_republic"
	captured.captured = true
	captured.current_hp = 1
	captured.current_en = 0
	captured.squad_id = &"squad_ransom_target"
	captured.slot_index = 0
	var squad := SquadState.new()
	squad.squad_id = &"squad_ransom_target"
	squad.owner_faction_id = &"crimson_empire"
	squad.region_id = &"crimson_capital"
	squad.assign_unit(captured.instance_id, 0)
	game_state.campaign_runtime.units_by_id[captured.instance_id] = captured
	game_state.campaign_runtime.squads_by_id[squad.squad_id] = squad

	var nova: Faction = game_state.get_faction(&"nova_republic")
	var crimson: Faction = game_state.get_faction(&"crimson_empire")
	var nova_funds_before := nova.funds
	var crimson_funds_before := crimson.funds
	var expected_price := ceili(float(GameConstants.UNIT_PRODUCTION_FUNDS[GameEnums.UnitSize.LIGHT]) * GameConstants.RANSOM_PRICE_PCT)

	var errors := Diplomacy.ransom_captured_unit(game_state, captured.instance_id)
	_check(errors.is_empty(), "a well-formed ransom should not error: %s" % [errors])
	_check(captured.owner_faction_id == &"nova_republic" and not captured.captured,
		"ransom must return the unit to its original faction and clear the captured flag")
	_check(captured.condition == GameEnums.UnitCondition.DESTROYED_RECOVERED,
		"a ransomed unit should arrive as a destroyed-and-recovered record, not combat-ready")
	_check(captured.squad_id.is_empty(), "ransom must detach the unit from its captor squad")
	_check(nova.funds == nova_funds_before - expected_price, "ransom did not deduct the price from the original faction")
	_check(crimson.funds == crimson_funds_before + expected_price, "ransom did not credit the price to the captor")

	var repeat_errors := Diplomacy.ransom_captured_unit(game_state, captured.instance_id)
	_check(not repeat_errors.is_empty(), "ransoming an already-returned unit should fail instead of double-paying")

	var validation_errors: PackedStringArray = game_state.campaign_runtime.validate(game_state.master_data, game_state.region_defs)
	_check(validation_errors.is_empty(), "campaign state failed validation after ransom: %s" % validation_errors)


func _finish() -> void:
	if failures.is_empty():
		print("diplomacy_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("diplomacy_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
