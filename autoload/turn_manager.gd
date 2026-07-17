extends Node
## Drives the per-turn phase state machine. This is the core of the
## "shorter playtime than the original" design: orders are given per-region
## (not per-unit), and AI factions commit instantly with no "thinking" delay.

enum Phase { INCOME, ORDERS, MOVEMENT, COMBAT, DIPLOMACY, VICTORY_CHECK }

signal phase_changed(phase: Phase)
## Short human-readable line about AI-vs-AI activity the player didn't see
## directly (world keeps moving even off-screen). Empty string means
## nothing notable happened this turn.
signal turn_events_ready(summary: String)
signal research_completed(faction_id: StringName, new_tier: int)

var current_phase: Phase = Phase.INCOME
var last_combat_log: Array = []  # this turn's auto-captures/battles, for logging/UI
var faction_turn_order: Array[StringName] = []
var active_faction_index: int = 0
var active_faction_id: StringName = &""
var is_resolving_turn: bool = false

signal active_faction_changed(faction_id: StringName, index: int)
signal squad_battles_detected(battles: Array[Dictionary])
signal battle_runtime_ready(battle: BattleRuntimeState)
signal battle_runtime_finished(battle_id: StringName)
var pending_squad_battles: Array[Dictionary] = []
var pending_battle_states: Array[BattleRuntimeState] = []
var next_battle_serial: int = 1

## Global "development" command (per the original series' overall-menu
## research command, not a per-region build item). Returns false if the
## faction can't research right now (already researching, maxed out, or
## can't afford it) without changing any state.
func start_research(faction_id: StringName) -> bool:
	var faction: Faction = GameState.get_faction(faction_id)
	if faction == null or faction.research_in_progress:
		return false
	var config: CampaignConfig = GameState.campaign_config
	if faction.tech_tier >= config.research_costs.size():
		return false
	var cost: int = config.research_costs[faction.tech_tier]
	if faction.resources < cost:
		return false
	faction.resources -= cost
	faction.research_in_progress = true
	faction.research_turns_remaining = config.research_turns[faction.tech_tier]
	return true

func _advance_research(faction_id: StringName) -> void:
	var config: CampaignConfig = GameState.campaign_config
	var faction: Faction = GameState.get_faction(faction_id)
	if faction == null or not faction.research_in_progress:
		return
	faction.research_turns_remaining -= 1
	if faction.research_turns_remaining <= 0:
		faction.tech_tier += 1
		faction.research_in_progress = false
		research_completed.emit(faction_id, faction.tech_tier)

func start_new_game(player_faction_id: StringName) -> void:
	is_resolving_turn = false
	pending_battle_states.clear()
	next_battle_serial = 1
	GameState.start_new_game(player_faction_id)
	_build_faction_turn_order(player_faction_id)
	active_faction_index = 0
	_begin_faction_turn()

func _build_faction_turn_order(player_faction_id: StringName) -> void:
	faction_turn_order.clear()
	faction_turn_order.append(player_faction_id)
	for faction_id: StringName in GameState.campaign_config.faction_turn_order:
		if faction_id != player_faction_id and GameState.factions.has(faction_id):
			faction_turn_order.append(faction_id)
	var remaining := GameState.factions.keys()
	remaining.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for faction_id: StringName in remaining:
		if not faction_turn_order.has(faction_id):
			faction_turn_order.append(faction_id)

func _begin_faction_turn() -> void:
	active_faction_id = faction_turn_order[active_faction_index]
	active_faction_changed.emit(active_faction_id, active_faction_index)
	GameState.campaign_runtime.reset_movement_for_faction(active_faction_id)
	_set_phase(Phase.INCOME)
	_run_income_phase(active_faction_id)
	GameState.advance_repairs_for_faction(active_faction_id)
	_set_phase(Phase.ORDERS)

## Called by the StrategicMap UI's "End Turn" button.
func commit_turn() -> void:
	if GameState.is_game_over or is_resolving_turn or active_faction_id != GameState.player_faction_id or current_phase != Phase.ORDERS:
		return
	is_resolving_turn = true
	await _finish_active_faction_turn()
	while not GameState.is_game_over:
		active_faction_index += 1
		if active_faction_index >= faction_turn_order.size():
			_run_diplomacy_week_end()
			if _run_victory_check(true):
				return
			GameState.advance_turn()
			active_faction_index = 0
			_begin_faction_turn()
			is_resolving_turn = false
			return
		_begin_faction_turn()
		var faction := GameState.get_faction(active_faction_id) as Faction
		if faction == null or faction.eliminated:
			continue
		AiController.decide_orders(active_faction_id)
		await _finish_active_faction_turn()

func _finish_active_faction_turn() -> void:
	_set_phase(Phase.MOVEMENT)
	_run_movement_phase(active_faction_id)
	_set_phase(Phase.COMBAT)
	await _run_combat_phase()
	turn_events_ready.emit(_build_world_events_summary())
	_set_phase(Phase.DIPLOMACY)
	Diplomacy.apply_combat_events(last_combat_log)
	_set_phase(Phase.VICTORY_CHECK)
	_run_victory_check(false)

func _involves_player(entry: Dictionary) -> bool:
	return entry["attacker_id"] == GameState.player_faction_id or entry["defender_id"] == GameState.player_faction_id

func _set_phase(phase: Phase) -> void:
	current_phase = phase
	phase_changed.emit(phase)

func _run_income_phase(faction_id: StringName) -> void:
	for region in GameState.regions.values():
		if region.owner_faction_id != faction_id:
			continue
		GameState.advance_region_production(region.def.id)
		var faction: Faction = GameState.get_faction(faction_id)
		if faction:
			faction.resources += region.def.resource_yield
			faction.funds += region.def.base_funds_income
			faction.materials += region.def.base_materials_income
			for facility_id: StringName in region.def.facility_instance_ids:
				var instance := GameState.master_data.facility_instances.get(facility_id) as FacilityInstanceDef
				if instance == null:
					continue
				var facility_def := GameState.master_data.facility_defs.get(instance.facility_def_id) as FacilityDef
				if facility_def != null:
					faction.funds += facility_def.funds_income
					faction.materials += facility_def.materials_income
	_advance_research(faction_id)

func _run_ai_orders() -> void:
	for fid in GameState.factions:
		var faction: Faction = GameState.factions[fid]
		if faction.is_ai_controlled and not faction.eliminated:
			AiController.decide_orders(fid)

func _run_movement_phase(faction_id: StringName) -> void:
	GameState.campaign_runtime.execute_planned_squad_movements(faction_id)

func _run_combat_phase() -> void:
	last_combat_log = []
	pending_squad_battles.clear()
	pending_battle_states.clear()
	for entry: Dictionary in GameState.detect_squad_conflicts(active_faction_id):
		if entry.type == "auto_capture":
			last_combat_log.append(entry)
		else:
			pending_squad_battles.append(entry)
	if not pending_squad_battles.is_empty():
		squad_battles_detected.emit(pending_squad_battles)
		for pending: Dictionary in pending_squad_battles:
			if pending.type == "squad_battle_pending":
				await _resolve_squad_battle(pending)
			elif pending.type == "multi_faction_battle_pending":
				await _resolve_multi_faction_battle(pending)

## A region with two or more distinct hostile defending factions can't be
## represented by the single-attacker/single-defender BattleRuntimeState
## model, so it is resolved as a sequence of pairwise battles against each
## defending faction in turn. Squad membership is re-derived from the live
## campaign state before each sub-battle so attrition from an earlier fight
## (or a wiped-out attacker) carries forward correctly.
func _resolve_multi_faction_battle(pending: Dictionary) -> void:
	# apply_battle_result unconditionally clears every participant's
	# move_origin_region_id once its battle finishes, since it normally
	# assumes a squad fights at most once per turn. A surviving attacker
	# fighting a second defender still needs that retreat origin for
	# BattleRuntimeFactory's validation, so it is restored before each
	# sub-battle from a snapshot taken before the sequence starts.
	var retreat_origin_by_squad_id: Dictionary = {}
	for squad_id: StringName in pending.attacker_squad_ids:
		var squad := GameState.campaign_runtime.get_squad(squad_id)
		if squad != null:
			retreat_origin_by_squad_id[squad_id] = squad.move_origin_region_id
	for defender_id: StringName in pending.defender_faction_ids:
		for squad_id: StringName in retreat_origin_by_squad_id:
			var squad := GameState.campaign_runtime.get_squad(squad_id)
			if squad != null and squad.move_origin_region_id.is_empty():
				squad.move_origin_region_id = retreat_origin_by_squad_id[squad_id]
		var attacker_squad_ids := GameState.combat_capable_squad_ids_in_region(pending.region_id, pending.attacker_id)
		if attacker_squad_ids.is_empty():
			break
		var defender_squad_ids := GameState.combat_capable_squad_ids_in_region(pending.region_id, defender_id)
		if defender_squad_ids.is_empty():
			continue
		await _resolve_squad_battle({
			"type": "squad_battle_pending", "region_id": pending.region_id,
			"attacker_id": pending.attacker_id, "defender_id": defender_id,
			"attacker_squad_ids": attacker_squad_ids, "defender_squad_ids": defender_squad_ids,
		})

func _resolve_squad_battle(pending: Dictionary) -> void:
	var battle_id := StringName("battle_%08d" % next_battle_serial)
	next_battle_serial += 1
	var region_def := GameState.region_defs[pending.region_id] as RegionDef
	var battle_map := GameState.master_data.battle_maps.get(region_def.battle_map_id) as BattleMapDef
	var created := BattleRuntimeFactory.new().create_from_pending(
		pending, GameState.campaign_runtime, battle_id, hash(String(battle_id)),
		Vector3(-400.0, 0.0, 0.0), Vector3(400.0, 0.0, 0.0),
		battle_map,
	)
	if created.errors.is_empty():
		var battle := created.state as BattleRuntimeState
		pending_battle_states.append(battle)
		battle_runtime_ready.emit(battle)
		await battle_runtime_finished
		if battle.result != null:
			last_combat_log.append({
				"type": "battle",
				"region_id": battle.region_id,
				"attacker_id": battle.attacker_faction_id,
				"defender_id": battle.defender_faction_id,
				"winner_id": battle.result.winner_faction_id,
				"reason": battle.result.reason,
				"captured": battle.result.winner_faction_id == battle.attacker_faction_id and battle.result.reason in [&"hq_capture", &"annihilation"],
			})
	else:
		push_error("Failed to create battle runtime: %s" % created.errors)

func complete_battle_runtime(battle: BattleRuntimeState) -> PackedStringArray:
	var errors := GameState.apply_battle_result(battle)
	if errors.is_empty():
		pending_battle_states.erase(battle)
		battle_runtime_finished.emit(battle.battle_id)
	return errors

func _build_world_events_summary() -> String:
	var lines: Array = []
	for entry in last_combat_log:
		var region_name: String = GameState.region_defs[entry["region_id"]].display_name
		if entry["type"] == "auto_capture":
			var fdef: FactionDef = GameState.faction_defs[entry["faction_id"]]
			lines.append("%s が %s を無血占領しました。" % [fdef.display_name, region_name])
		elif entry["type"] == "battle":
			if _involves_player(entry):
				continue  # the player already watched this battle resolve live
			var attacker_fdef: FactionDef = GameState.faction_defs[entry["attacker_id"]]
			var defender_fdef: FactionDef = GameState.faction_defs[entry["defender_id"]]
			if entry["captured"]:
				lines.append("%s が %s で %s を撃破し占領しました。" % [attacker_fdef.display_name, region_name, defender_fdef.display_name])
			else:
				lines.append("%s が %s で %s と交戦しました。" % [attacker_fdef.display_name, region_name, defender_fdef.display_name])
	return "\n".join(lines)

func _run_diplomacy_week_end() -> void:
	Diplomacy.tick_drift()

func _run_victory_check(check_turn_cap: bool = false) -> bool:
	var player_faction: Faction = GameState.get_faction(GameState.player_faction_id)
	if player_faction and player_faction.eliminated:
		_end_game("player_eliminated", [])
		return true

	var alive := GameState.alive_faction_ids()
	if alive.size() <= 1:
		var winner_id: StringName = alive[0] if alive.size() == 1 else &""
		var standings: Array = [{"faction_id": winner_id, "score": -1}] if winner_id != &"" else []
		_end_game("capital_capture", standings)
		return true

	var total_regions := GameState.regions.size()
	for fid in alive:
		var pct := float(GameState.region_count_for(fid)) / float(total_regions)
		if pct >= GameState.campaign_config.victory_region_threshold_pct:
			_end_game("region_threshold", [{"faction_id": fid, "score": -1}])
			return true
	if check_turn_cap and GameState.turn_number >= GameState.campaign_config.turn_cap:
		_end_game("turn_cap", _score_standings(alive))
		return true
	return false

func _score_standings(faction_ids: Array) -> Array:
	var scored := []
	for fid in faction_ids:
		var faction: Faction = GameState.factions[fid]
		var score := GameState.region_count_for(fid) * 10 + faction.resources
		scored.append({"faction_id": fid, "score": score})
	scored.sort_custom(func(a, b): return a["score"] > b["score"])
	return scored

func _end_game(reason: String, standings: Array) -> void:
	GameState.is_game_over = true
	GameState.last_game_over_reason = reason
	GameState.last_game_over_standings = standings
	GameState.game_over.emit(reason, standings)
