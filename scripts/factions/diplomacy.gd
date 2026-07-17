class_name Diplomacy
extends RefCounted
## STRATEGY_DETAIL_SPECIFICATION.md section 11 / DATA_DEFINITION.md section
## 18: treaty proposals, resource gifting, tech gifting, captured-unit
## ransom, and intel purchase, operating on a CampaignRuntimeState's
## relation_states.
##
## Every function below takes `game_state` as an explicit first parameter
## instead of referencing the GameState autoload by its bare global
## identifier: a --script test entry point that reaches this class before
## any autoload-chained script does hits a headless-only GDScript
## compile-order bug ("Identifier not found: GameState") on any such bare
## reference -- see HANDOFF.md's "Validation and setup" section. Passing it
## in sidesteps the bug entirely and lets this class be exercised directly
## from tests, not just indirectly through TurnManager/AiController.

const CEASEFIRE := GameEnums.TreatyType.CEASEFIRE
const NON_AGGRESSION := GameEnums.TreatyType.NON_AGGRESSION


static func friendship(game_state: Node, faction_id: StringName, other_id: StringName) -> int:
	if other_id == &"" or faction_id == other_id:
		return 0
	return game_state.campaign_runtime.get_relation_state(faction_id, other_id).friendship


static func relation_band(game_state: Node, faction_id: StringName, other_id: StringName) -> GameEnums.RelationBand:
	return game_state.campaign_runtime.get_relation_state(faction_id, other_id).relation_band()


static func current_treaty_type(game_state: Node, faction_id: StringName, other_id: StringName) -> GameEnums.TreatyType:
	if other_id == &"" or faction_id == other_id:
		return GameEnums.TreatyType.NONE
	return game_state.campaign_runtime.get_relation_state(faction_id, other_id).treaty_type


static func has_active_treaty(game_state: Node, faction_id: StringName, other_id: StringName) -> bool:
	return current_treaty_type(game_state, faction_id, other_id) != GameEnums.TreatyType.NONE


## Call once per turn after combat resolves: every battle sours relations
## between the two factions involved (symmetrically).
static func apply_combat_events(game_state: Node, combat_log: Array) -> void:
	for entry in combat_log:
		if entry["type"] != "battle":
			continue
		_adjust_friendship(game_state, entry["attacker_id"], entry["defender_id"], GameConstants.COMBAT_FRIENDSHIP_PENALTY)


## Called once per full round (TurnManager._run_diplomacy_week_end, after
## every faction has acted): advances every relation pair's treaty countdown
## and cooldowns by one turn. STRATEGY_DETAIL_SPECIFICATION.md section 11.1:
## friendship drifts +1 per turn only while a treaty is active; there is no
## general decay toward neutral outside that.
static func tick_week(game_state: Node, turn_number: int) -> void:
	for relation: RelationState in game_state.campaign_runtime.relation_states.values():
		if relation.treaty_type != GameEnums.TreatyType.NONE:
			relation.friendship = clampi(
				relation.friendship + GameConstants.TREATY_ACTIVE_FRIENDSHIP_GAIN_PER_TURN,
				GameConstants.FRIENDSHIP_MIN, GameConstants.FRIENDSHIP_MAX,
			)
			relation.treaty_turns_remaining -= 1
			if relation.treaty_turns_remaining == 1:
				game_state.campaign_runtime.log_diplomacy(
					turn_number, relation.faction_a_id, relation.faction_b_id, &"treaty_expiring", {}, true
				)
			elif relation.treaty_turns_remaining <= 0:
				relation.treaty_type = GameEnums.TreatyType.NONE
				relation.treaty_turns_remaining = 0
				game_state.campaign_runtime.log_diplomacy(
					turn_number, relation.faction_a_id, relation.faction_b_id, &"treaty_expired", {}, true
				)
		relation.proposal_cooldown_turns = maxi(0, relation.proposal_cooldown_turns - 1)
		relation.gift_cooldown_turns = maxi(0, relation.gift_cooldown_turns - 1)
		relation.intel_purchase_cooldown_turns = maxi(0, relation.intel_purchase_cooldown_turns - 1)
		if relation.violation_penalty_turns > 0:
			relation.violation_penalty_turns -= 1
			if relation.violation_penalty_turns == 0:
				relation.violator_faction_id = &""
				relation.violation_success_penalty_pct = 0


static func _adjust_friendship(game_state: Node, a: StringName, b: StringName, delta: int) -> void:
	var relation: RelationState = game_state.campaign_runtime.get_relation_state(a, b)
	relation.friendship = clampi(relation.friendship + delta, GameConstants.FRIENDSHIP_MIN, GameConstants.FRIENDSHIP_MAX)


static func _durations_for(treaty: GameEnums.TreatyType) -> Array[int]:
	match treaty:
		CEASEFIRE:
			return GameConstants.CEASEFIRE_DURATIONS
		NON_AGGRESSION:
			return GameConstants.NON_AGGRESSION_DURATIONS
		_:
			return []


## STRATEGY_DETAIL_SPECIFICATION.md section 11.3. Pure/no side effects, so
## it can back both the real proposal roll and a UI preview of the odds.
static func compute_success_rate_pct(
	game_state: Node, proposer_id: StringName, target_id: StringName,
	treaty: GameEnums.TreatyType, duration_turns: int,
	offered_funds: int = 0, offered_materials: int = 0,
) -> int:
	var relation: RelationState = game_state.campaign_runtime.get_relation_state(proposer_id, target_id)
	var base: float = GameConstants.TREATY_BASE_SUCCESS_PCT.get(treaty, 0)
	var friendship_bonus := float(relation.friendship) * GameConstants.FRIENDSHIP_SUCCESS_MULTIPLIER

	var proposer_power := BattlePowerEstimator.faction_total_power(proposer_id, game_state.campaign_runtime, game_state.master_data)
	var target_power := BattlePowerEstimator.faction_total_power(target_id, game_state.campaign_runtime, game_state.master_data)
	var power_bonus := 0.0
	if proposer_power + target_power > 0.0:
		var power_ratio := (proposer_power - target_power) / (proposer_power + target_power)
		power_bonus = clampf(
			power_ratio * GameConstants.POWER_RATIO_SUCCESS_MULTIPLIER,
			-GameConstants.POWER_RATIO_SUCCESS_CLAMP_PCT, GameConstants.POWER_RATIO_SUCCESS_CLAMP_PCT,
		)

	var duration_table: Dictionary = GameConstants.TREATY_DURATION_PENALTY_PCT.get(treaty, {})
	var duration_penalty: float = duration_table.get(duration_turns, 0)

	var target_income: Dictionary = game_state.estimate_faction_income(target_id)
	var gift_bonus := 0.0
	if int(target_income.funds) > 0 or int(target_income.materials) > 0:
		var funds_ratio := float(offered_funds) / float(target_income.funds) if int(target_income.funds) > 0 else 0.0
		var materials_ratio := float(offered_materials) / float(target_income.materials) if int(target_income.materials) > 0 else 0.0
		gift_bonus = clampf(
			(funds_ratio + materials_ratio) * GameConstants.GIFT_OFFER_SUCCESS_MULTIPLIER,
			0.0, GameConstants.GIFT_OFFER_SUCCESS_MAX_PCT,
		)

	var violation_penalty := 0.0
	if relation.violator_faction_id == proposer_id and relation.violation_penalty_turns > 0:
		violation_penalty = float(relation.violation_success_penalty_pct)

	var total := base + friendship_bonus + power_bonus + gift_bonus - duration_penalty - violation_penalty
	return clampi(int(round(total)), GameConstants.TREATY_SUCCESS_MIN_PCT, GameConstants.TREATY_SUCCESS_MAX_PCT)


## Attempts to establish `treaty` for `duration_turns` between proposer_id
## and target_id, spending offered_funds/materials only on success (section
## 11.3: "失敗時は提示対価を消費しない"). Validation failures (bad
## duration, cooldown active, can't afford the offer) return early without
## rolling or touching the cooldown -- only an actual probabilistic loss
## burns the 5-turn cooldown.
static func propose_treaty(
	game_state: Node, proposer_id: StringName, target_id: StringName,
	treaty: GameEnums.TreatyType, duration_turns: int,
	offered_funds: int = 0, offered_materials: int = 0,
) -> Dictionary:
	var errors := PackedStringArray()
	var proposer: Faction = game_state.get_faction(proposer_id)
	var target: Faction = game_state.get_faction(target_id)
	if proposer_id == target_id or proposer == null or target == null:
		errors.append("diplomacy: proposer and target must be distinct, resolvable factions")
	if treaty != CEASEFIRE and treaty != NON_AGGRESSION:
		errors.append("diplomacy: treaty must be CEASEFIRE or NON_AGGRESSION")
	elif not _durations_for(treaty).has(duration_turns):
		errors.append("diplomacy: duration_turns is not a valid option for this treaty type")
	if offered_funds < 0 or offered_materials < 0:
		errors.append("diplomacy: offered amounts must not be negative")
	if not errors.is_empty():
		errors.sort()
		return {"success": false, "success_rate_pct": 0, "errors": errors}

	var relation: RelationState = game_state.campaign_runtime.get_relation_state(proposer_id, target_id)
	if relation.treaty_type != GameEnums.TreatyType.NONE:
		errors.append("diplomacy: a treaty is already active with this faction")
	if relation.proposal_cooldown_turns > 0:
		errors.append("diplomacy: this faction rejected a recent proposal and cannot be approached yet")
	if proposer.funds < offered_funds:
		errors.append("diplomacy: insufficient funds for the offered amount")
	if proposer.materials < offered_materials:
		errors.append("diplomacy: insufficient materials for the offered amount")
	if not errors.is_empty():
		errors.sort()
		return {"success": false, "success_rate_pct": 0, "errors": errors}

	var success_rate := compute_success_rate_pct(game_state, proposer_id, target_id, treaty, duration_turns, offered_funds, offered_materials)
	var roll: int = game_state.campaign_rng.randi_range(1, 100)
	var success := roll <= success_rate
	var payload := {
		"treaty_type": treaty, "duration_turns": duration_turns,
		"offered_funds": offered_funds, "offered_materials": offered_materials,
		"success_rate_pct": success_rate,
	}
	game_state.campaign_runtime.log_diplomacy(game_state.turn_number, proposer_id, target_id, &"treaty_proposal", payload, success)
	if not success:
		relation.proposal_cooldown_turns = GameConstants.DIPLOMACY_PROPOSAL_COOLDOWN_TURNS
		return {"success": false, "success_rate_pct": success_rate, "errors": PackedStringArray()}

	proposer.funds -= offered_funds
	proposer.materials -= offered_materials
	target.funds += offered_funds
	target.materials += offered_materials
	relation.treaty_type = treaty
	relation.treaty_turns_remaining = duration_turns
	_retreat_squads_from_foreign_territory(game_state, proposer_id, target_id)
	return {"success": true, "success_rate_pct": success_rate, "errors": PackedStringArray()}


## STRATEGY_DETAIL_SPECIFICATION.md section 11.2: "条約成立時、敵領内の双方
## 部隊を侵攻元へ即時撤退させる". Battles in this engine fully resolve
## within the same turn's combat phase (there is no persistent mid-battle
## state spanning turns), so by the time a treaty can be proposed in a later
## ORDERS phase, a squad "in foreign territory" can only be one that hasn't
## fought yet -- this simply sends it home instead of leaving it stranded to
## potentially clash again once the treaty lapses.
static func _retreat_squads_from_foreign_territory(game_state: Node, faction_a: StringName, faction_b: StringName) -> void:
	for squad: SquadState in game_state.campaign_runtime.squads_by_id.values():
		if squad == null:
			continue
		var other_id := faction_b if squad.owner_faction_id == faction_a else (faction_a if squad.owner_faction_id == faction_b else &"")
		if other_id.is_empty():
			continue
		var region: Region = game_state.get_region(squad.region_id)
		if region == null or region.owner_faction_id != other_id:
			continue
		var owner_def: FactionDef = game_state.faction_defs.get(squad.owner_faction_id)
		var destination := squad.move_origin_region_id
		if destination.is_empty():
			destination = owner_def.starting_region_id if owner_def != null else squad.region_id
		squad.region_id = destination
		squad.move_origin_region_id = &""
		squad.planned_destination_region_id = &""


## STRATEGY_DETAIL_SPECIFICATION.md section 11.4: a unilateral break costs
## the breaker 20 friendship and a 10-turn, 10-point success-rate penalty on
## future proposals to the wronged faction. There's no separate "at war"
## flag to flip -- invasion simply becomes possible again the instant
## treaty_type reverts to NONE, which is what this does immediately.
static func break_treaty(game_state: Node, breaker_id: StringName, other_id: StringName) -> PackedStringArray:
	var errors := PackedStringArray()
	var relation: RelationState = game_state.campaign_runtime.get_relation_state(breaker_id, other_id)
	if relation.treaty_type == GameEnums.TreatyType.NONE:
		errors.append("diplomacy: no active treaty with this faction to break")
		return errors
	relation.treaty_type = GameEnums.TreatyType.NONE
	relation.treaty_turns_remaining = 0
	relation.friendship = clampi(
		relation.friendship - GameConstants.TREATY_VIOLATION_FRIENDSHIP_PENALTY,
		GameConstants.FRIENDSHIP_MIN, GameConstants.FRIENDSHIP_MAX,
	)
	relation.violator_faction_id = breaker_id
	relation.violation_penalty_turns = GameConstants.TREATY_VIOLATION_PENALTY_TURNS
	relation.violation_success_penalty_pct = GameConstants.TREATY_VIOLATION_SUCCESS_PENALTY_PCT
	game_state.campaign_runtime.log_diplomacy(game_state.turn_number, breaker_id, other_id, &"treaty_broken", {}, true)
	return errors


## STRATEGY_DETAIL_SPECIFICATION.md section 11.5: a one-way funds/materials
## gift that always succeeds once the minimum-amount and cooldown gates are
## met. Tech gifting (11.6) shares this same cooldown but is deferred -- see
## the class doc comment.
static func gift_resources(game_state: Node, giver_id: StringName, receiver_id: StringName, funds: int, materials: int) -> PackedStringArray:
	var errors := PackedStringArray()
	var giver: Faction = game_state.get_faction(giver_id)
	var receiver: Faction = game_state.get_faction(receiver_id)
	if giver_id == receiver_id or giver == null or receiver == null:
		errors.append("diplomacy: giver and receiver must be distinct, resolvable factions")
	if funds < 0 or materials < 0:
		errors.append("diplomacy: gift amounts must not be negative")
	elif funds < GameConstants.MIN_GIFT_FUNDS and materials < GameConstants.MIN_GIFT_MATERIALS:
		errors.append("diplomacy: gift must meet the minimum funds or materials threshold")
	if not errors.is_empty():
		errors.sort()
		return errors

	var relation: RelationState = game_state.campaign_runtime.get_relation_state(giver_id, receiver_id)
	if relation.gift_cooldown_turns > 0:
		errors.append("diplomacy: gifting to this faction is on cooldown")
	if giver.funds < funds:
		errors.append("diplomacy: insufficient funds")
	if giver.materials < materials:
		errors.append("diplomacy: insufficient materials")
	if not errors.is_empty():
		errors.sort()
		return errors

	giver.funds -= funds
	receiver.funds += funds
	giver.materials -= materials
	receiver.materials += materials
	relation.gift_cooldown_turns = GameConstants.DIPLOMACY_GIFT_COOLDOWN_TURNS
	relation.friendship = clampi(
		relation.friendship + GameConstants.GIFT_FRIENDSHIP_GAIN, GameConstants.FRIENDSHIP_MIN, GameConstants.FRIENDSHIP_MAX
	)
	game_state.campaign_runtime.log_diplomacy(
		game_state.turn_number, giver_id, receiver_id, &"gift", {"funds": funds, "materials": materials}, true
	)
	return errors


## See the class doc comment for how this simplifies section 11.6. Shares
## gift_resources' cooldown (section 11.4: "資源贈与と技術贈与は共通の贈与
## 待ち時間を使用し"). "同じ技術を同じ勢力へ複数回贈与できない" needs no
## extra bookkeeping here: since this always targets receiver_id's next
## tier and tech_tier only ever increases, a repeat gift naturally targets a
## tier one higher than the last, never the same one twice.
## STRATEGY_DETAIL_SPECIFICATION.md section 11.6: gives receiver_id a new
## gifted node for whatever tech giver_id's giver_node_id has already
## researched. "贈与側は技術を失わない" -- the giver's own node is
## untouched. "受取側では即時研究済みにせず...候補へ登録する" -- the
## gifted node starts unresearched; TurnManager._node_prerequisites_met's
## gifted-node branch handles "Tier 1は即時研究可能、Tier 2以上は直前Tierを
## 1件以上研究済みで研究可能とする（個別の元前提技術は要求しない）".
## "同じ技術を同じ勢力へ複数回贈与できない" is enforced by checking
## receiver_id doesn't already have this tech_id anywhere in its tree.
static func gift_tech(game_state: Node, giver_id: StringName, receiver_id: StringName, giver_node_id: StringName) -> PackedStringArray:
	var errors := PackedStringArray()
	var giver: Faction = game_state.get_faction(giver_id)
	var receiver: Faction = game_state.get_faction(receiver_id)
	if giver_id == receiver_id or giver == null or receiver == null:
		errors.append("diplomacy: giver and receiver must be distinct, resolvable factions")
		return errors
	var giver_node: GeneratedTechNodeState = giver.generated_tech_nodes.get(giver_node_id)
	if giver_node == null or not giver_node.researched:
		errors.append("diplomacy: giver has not researched the selected tech")
		return errors
	var tech_def: TechDef = game_state.master_data.techs.get(giver_node.tech_id)
	if tech_def == null or not tech_def.giftable:
		errors.append("diplomacy: this tech cannot be gifted")
		return errors
	for existing_id: StringName in receiver.generated_tech_nodes:
		if (receiver.generated_tech_nodes[existing_id] as GeneratedTechNodeState).tech_id == giver_node.tech_id:
			errors.append("diplomacy: the receiver already has this tech in their tree")
			return errors
	var relation: RelationState = game_state.campaign_runtime.get_relation_state(giver_id, receiver_id)
	if relation.gift_cooldown_turns > 0:
		errors.append("diplomacy: gifting to this faction is on cooldown")
	if not errors.is_empty():
		errors.sort()
		return errors

	var new_node := GeneratedTechNodeState.new()
	new_node.node_id = StringName("gift_%s_%s" % [receiver_id, giver_node.tech_id])
	new_node.tech_id = giver_node.tech_id
	new_node.tier = giver_node.tier
	new_node.gifted = true
	receiver.generated_tech_nodes[new_node.node_id] = new_node

	relation.gift_cooldown_turns = GameConstants.DIPLOMACY_GIFT_COOLDOWN_TURNS
	relation.friendship = clampi(
		relation.friendship + GameConstants.GIFT_FRIENDSHIP_GAIN, GameConstants.FRIENDSHIP_MIN, GameConstants.FRIENDSHIP_MAX
	)
	game_state.campaign_runtime.log_diplomacy(
		game_state.turn_number, giver_id, receiver_id, &"tech_gift", {"tech_id": giver_node.tech_id, "tier": giver_node.tier}, true
	)
	return errors


## STRATEGY_DETAIL_SPECIFICATION.md section 11.7: no friendship or
## probability check, just funds and a per-partner cooldown. Confirms
## buyer_id's intel on every third_party_id squad that partner_id currently
## has confirmed; squads partner_id hasn't confirmed simply aren't
## transferable (not an error -- the caller is expected to warn the player
## up front that a zero-result purchase is possible and non-refundable).
static func purchase_intel(game_state: Node, buyer_id: StringName, partner_id: StringName, third_party_id: StringName) -> Dictionary:
	var errors := PackedStringArray()
	var buyer: Faction = game_state.get_faction(buyer_id)
	if buyer_id == partner_id or buyer_id == third_party_id or partner_id == third_party_id:
		errors.append("diplomacy: buyer, partner, and third_party must be three distinct factions")
	if buyer == null or game_state.get_faction(partner_id) == null:
		errors.append("diplomacy: buyer and partner must both resolve to a faction")
	if third_party_id.is_empty():
		errors.append("diplomacy: third_party_id must not be empty")
	if not errors.is_empty():
		errors.sort()
		return {"confirmed_squad_ids": [] as Array[StringName], "errors": errors}

	var relation: RelationState = game_state.campaign_runtime.get_relation_state(buyer_id, partner_id)
	if relation.intel_purchase_cooldown_turns > 0:
		errors.append("diplomacy: intel purchases from this faction are on cooldown")
	if buyer.funds < GameConstants.INTEL_PURCHASE_COST_FUNDS:
		errors.append("diplomacy: insufficient funds")
	if not errors.is_empty():
		errors.sort()
		return {"confirmed_squad_ids": [] as Array[StringName], "errors": errors}

	buyer.funds -= GameConstants.INTEL_PURCHASE_COST_FUNDS
	relation.intel_purchase_cooldown_turns = GameConstants.DIPLOMACY_INTEL_PURCHASE_COOLDOWN_TURNS
	var confirmed: Array[StringName] = []
	for squad: SquadState in game_state.campaign_runtime.squads_by_id.values():
		if squad == null or squad.owner_faction_id != third_party_id:
			continue
		if game_state.campaign_runtime.is_squad_confirmed(partner_id, squad.squad_id):
			game_state.campaign_runtime.confirm_squad_intel(buyer_id, squad.squad_id, game_state.turn_number)
			if buyer_id == game_state.player_faction_id:
				game_state.register_encyclopedia_for_squad(squad.squad_id)
			confirmed.append(squad.squad_id)
	game_state.campaign_runtime.log_diplomacy(
		game_state.turn_number, buyer_id, partner_id, &"intel_purchase",
		{"third_party_id": third_party_id, "confirmed_squad_count": confirmed.size()}, true,
	)
	return {"confirmed_squad_ids": confirmed, "errors": PackedStringArray()}


## STRATEGY_DETAIL_SPECIFICATION.md section 11.8: a captured unit can be
## ransomed back to the faction that originally built it, for 75% of its
## production funds cost. No friendship change; the returned unit arrives
## as a DESTROYED_RECOVERED record on the original side (needing a fresh
## rebuild) rather than combat-ready, and is removed from the captor.
static func ransom_captured_unit(game_state: Node, unit_instance_id: StringName) -> PackedStringArray:
	var errors := PackedStringArray()
	var unit: UnitInstanceState = game_state.campaign_runtime.get_unit(unit_instance_id)
	if unit == null or not unit.captured:
		errors.append("diplomacy: unit_instance_id does not resolve to a captured unit")
		return errors
	var original: Faction = game_state.get_faction(unit.origin_faction_id)
	if original == null or original.eliminated:
		errors.append("diplomacy: the original owning faction no longer exists")
		return errors
	var unit_def: UnitDef = game_state.master_data.units.get(unit.unit_def_id)
	if unit_def == null:
		errors.append("diplomacy: unit definition does not resolve")
		return errors
	var price := ceili(float(GameConstants.UNIT_PRODUCTION_FUNDS[unit_def.size]) * GameConstants.RANSOM_PRICE_PCT)
	if original.funds < price:
		errors.append("diplomacy: original faction cannot afford the ransom price")
		return errors

	var captor_id := unit.owner_faction_id
	var captor: Faction = game_state.get_faction(captor_id)
	original.funds -= price
	if captor != null:
		captor.funds += price
	game_state.campaign_runtime.remove_unit_from_squad(unit_instance_id)
	unit.owner_faction_id = unit.origin_faction_id
	unit.pilot_id = &""
	unit.captured = false
	unit.condition = GameEnums.UnitCondition.DESTROYED_RECOVERED
	unit.current_hp = 0
	unit.current_en = 0
	unit.repair_turns_remaining = 0
	game_state.campaign_runtime.log_diplomacy(
		game_state.turn_number, captor_id, unit.origin_faction_id, &"unit_ransom",
		{"unit_instance_id": unit_instance_id, "price": price}, true,
	)
	return errors
