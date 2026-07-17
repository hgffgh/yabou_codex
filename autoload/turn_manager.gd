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
signal research_completed(faction_id: StringName, tech_id: StringName)

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

## STRATEGY_DETAIL_SPECIFICATION.md section 7: starts research on one node
## of this faction's generated tech tree. A gifted node (Diplomacy.gift_tech)
## uses a different availability rule than a normally-generated node's fixed
## prerequisite_node_ids -- see _node_prerequisites_met.
func start_research(faction_id: StringName, node_id: StringName) -> PackedStringArray:
	var errors := PackedStringArray()
	var faction: Faction = GameState.get_faction(faction_id)
	if faction == null:
		errors.append("research: faction_id does not resolve")
		return errors
	if faction.current_research != null:
		errors.append("research: this faction already has research in progress")
		return errors
	var node := faction.generated_tech_nodes.get(node_id) as GeneratedTechNodeState
	if node == null:
		errors.append("research: node_id does not resolve to this faction's tech tree")
		return errors
	if node.researched:
		errors.append("research: node is already researched")
		return errors
	if not _node_prerequisites_met(faction, node):
		errors.append("research: node's prerequisites are not fully researched")
		return errors
	var config: CampaignConfig = GameState.campaign_config
	var tier_index := node.tier - 1
	if tier_index < 0 or tier_index >= config.research_costs.size():
		errors.append("research: node tier is outside the configured cost table")
		return errors
	var cost := ceili(float(config.research_costs[tier_index]) * (1.0 - _research_discount_pct(faction_id)))
	if faction.funds < cost:
		errors.append("research: insufficient funds")
		return errors

	faction.funds -= cost
	var research := ResearchState.new()
	research.node_id = node_id
	research.funds_paid = cost
	research.turns_remaining = config.research_turns[tier_index]
	research.started_turn = GameState.turn_number
	faction.current_research = research
	return errors

## A gifted node ignores its (empty) prerequisite_node_ids in favor of
## STRATEGY_DETAIL_SPECIFICATION.md section 11.6's own rule: "Tier 1は即時
## 研究可能、Tier 2以上は直前Tierを1件以上研究済みで研究可能とする
## (個別の元前提技術は要求しない)" -- any researched node one tier down
## satisfies it, not a specific fixed chain.
func _node_prerequisites_met(faction: Faction, node: GeneratedTechNodeState) -> bool:
	if node.gifted:
		if node.tier <= 1:
			return true
		for other_id: StringName in faction.generated_tech_nodes:
			var other := faction.generated_tech_nodes[other_id] as GeneratedTechNodeState
			if other.tier == node.tier - 1 and other.researched:
				return true
		return false
	for prereq_id: StringName in node.prerequisite_node_ids:
		var prereq := faction.generated_tech_nodes.get(prereq_id) as GeneratedTechNodeState
		if prereq == null or not prereq.researched:
			return false
	return true

## STRATEGY_DETAIL_SPECIFICATION.md section 8.3: 5% off per owned research
## facility in this faction's own territory, capped at 25%.
func _research_discount_pct(faction_id: StringName) -> float:
	var facility_count := 0
	for region: Region in GameState.regions.values():
		if region.owner_faction_id != faction_id:
			continue
		for facility_id: StringName in region.def.facility_instance_ids:
			var instance := GameState.master_data.facility_instances.get(facility_id) as FacilityInstanceDef
			if instance == null:
				continue
			var facility_def := GameState.master_data.facility_defs.get(instance.facility_def_id) as FacilityDef
			if facility_def != null and facility_def.facility_type == GameEnums.FacilityType.RESEARCH:
				facility_count += 1
	return minf(float(facility_count) * 0.05, 0.25)

func _advance_research(faction_id: StringName) -> void:
	var faction: Faction = GameState.get_faction(faction_id)
	if faction == null or faction.current_research == null:
		return
	faction.current_research.turns_remaining -= 1
	if faction.current_research.turns_remaining <= 0:
		var node := faction.generated_tech_nodes.get(faction.current_research.node_id) as GeneratedTechNodeState
		faction.current_research = null
		if node != null:
			node.researched = true
			if faction_id == GameState.player_faction_id:
				GameState.unlock_tech_candidate_from_research(node.tech_id)
			research_completed.emit(faction_id, node.tech_id)

func start_new_game(player_faction_id: StringName, difficulty_id: StringName = &"normal") -> void:
	is_resolving_turn = false
	pending_battle_states.clear()
	next_battle_serial = 1
	GameState.start_new_game(player_faction_id, difficulty_id)
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

## DATA_DEFINITION.md section 26: current_phase/is_resolving_turn are not
## saved because a manual save is only ever possible during Phase.ORDERS on
## the player's own, non-resolving turn (see save_game's gate) -- that
## state is implied rather than persisted, and restored directly on load.
func to_save_dict() -> Dictionary:
	return {
		"faction_turn_order": faction_turn_order.duplicate(),
		"active_faction_index": active_faction_index,
	}

func apply_save_dict(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var order_value: Variant = data.get("faction_turn_order", [])
	if not order_value is Array or (order_value as Array).is_empty():
		errors.append("save.turn_manager: faction_turn_order must be a non-empty Array")
		return errors
	var order: Array[StringName] = []
	for item: Variant in order_value as Array:
		order.append(StringName(item))
	for faction_id: StringName in order:
		if not GameState.factions.has(faction_id):
			errors.append("save.turn_manager: faction_turn_order entry '%s' does not resolve" % faction_id)
	var index := int(data.get("active_faction_index", 0))
	if index < 0 or index >= order.size():
		errors.append("save.turn_manager: active_faction_index is out of range")
	if not errors.is_empty():
		errors.sort()
		return errors

	faction_turn_order = order
	active_faction_index = index
	active_faction_id = faction_turn_order[active_faction_index]
	current_phase = Phase.ORDERS
	is_resolving_turn = false
	pending_battle_states.clear()
	pending_squad_battles.clear()
	last_combat_log.clear()
	return errors

const SAVE_DIRECTORY := "user://saves/"
const SAVE_VERSION := 1
## SYSTEM_DETAIL_SPECIFICATION.md section 2.2: 3 rotating autosave slots,
## displayed and stored separately from the 10 manual slots.
const AUTOSAVE_SLOT_COUNT := 3

func _save_path(slot: int, auto: bool = false) -> String:
	return SAVE_DIRECTORY + ("autosave_%02d.json" % slot if auto else "slot_%02d.json" % slot)

## DATA_DEFINITION.md section 26.2: manual saves are only ever possible
## during the player's own Phase.ORDERS, not mid-resolution or on an AI turn.
## Autosaves aren't gated by this -- see _autosave's own doc comment.
func can_save_now() -> bool:
	return not GameState.is_game_over and active_faction_id == GameState.player_faction_id and current_phase == Phase.ORDERS and not is_resolving_turn

func save_game(slot: int, auto: bool = false) -> PackedStringArray:
	var errors := PackedStringArray()
	if not auto and not can_save_now():
		errors.append("save: manual saves are only available during the player's own strategy phase")
		return errors
	var data := {
		"save_version": SAVE_VERSION,
		"saved_at_unix": Time.get_unix_time_from_system(),
		"campaign": GameState.to_save_dict(),
		"turn_manager": to_save_dict(),
	}
	var dir_error := DirAccess.make_dir_recursive_absolute(SAVE_DIRECTORY)
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		errors.append("save: could not create the save directory (error %d)" % dir_error)
		return errors
	var file := FileAccess.open(_save_path(slot, auto), FileAccess.WRITE)
	if file == null:
		errors.append("save: could not open the save file for writing (error %d)" % FileAccess.get_open_error())
		return errors
	file.store_string(JSON.stringify(data))
	file.close()
	return errors

## SYSTEM_DETAIL_SPECIFICATION.md section 2.1: "戦闘フェイズ開始前と各勢力
## ターン開始時にオートセーブする" -- called from _begin_faction_turn and
## right before Phase.COMBAT in _finish_active_faction_turn, for every
## faction's turn, not just the player's, so it deliberately doesn't go
## through can_save_now()'s player/ORDERS-phase gate (that gate exists to
## stop the *player* from save-scumming mid-resolution, not because other
## moments are unsafe to serialize -- both autosave triggers land on stable,
## no-battle-in-progress states). Overwrites whichever of the 3 rotating
## slots has the oldest saved_at_unix, or the first slot that doesn't exist
## yet. Best-effort: failures are logged, not surfaced to the player.
func _autosave() -> void:
	if GameState.is_game_over:
		return
	var oldest_slot := 0
	var oldest_time := INF
	for slot in range(AUTOSAVE_SLOT_COUNT):
		if not FileAccess.file_exists(_save_path(slot, true)):
			oldest_slot = slot
			oldest_time = -1.0
			break
		var saved_at := float(_read_save_summary(slot, true).get("saved_at_unix", 0))
		if saved_at < oldest_time:
			oldest_time = saved_at
			oldest_slot = slot
	var errors := save_game(oldest_slot, true)
	if not errors.is_empty():
		push_error("autosave failed: %s" % errors)

## Applies GameState's half first, then this autoload's own, since
## TurnManager.apply_save_dict validates faction_turn_order entries against
## GameState.factions and needs that already rebuilt.
func load_game(slot: int, auto: bool = false) -> PackedStringArray:
	var errors := PackedStringArray()
	var path := _save_path(slot, auto)
	if not FileAccess.file_exists(path):
		errors.append("load: save slot %d does not exist" % slot)
		return errors
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("load: could not open the save file (error %d)" % FileAccess.get_open_error())
		return errors
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		errors.append("load: save file is not valid JSON")
		return errors
	var data := parsed as Dictionary
	var campaign_data: Variant = data.get("campaign", {})
	var turn_manager_data: Variant = data.get("turn_manager", {})
	if not campaign_data is Dictionary or not turn_manager_data is Dictionary:
		errors.append("load: save file is missing its campaign/turn_manager sections")
		return errors

	var campaign_errors := GameState.apply_save_dict(campaign_data as Dictionary)
	if not campaign_errors.is_empty():
		errors.append_array(campaign_errors)
		return errors
	var turn_errors := apply_save_dict(turn_manager_data as Dictionary)
	if not turn_errors.is_empty():
		errors.append_array(turn_errors)
		return errors

	GameState.turn_advanced.emit(GameState.turn_number)
	active_faction_changed.emit(active_faction_id, active_faction_index)
	phase_changed.emit(current_phase)
	return errors

func list_save_slots(auto: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(SAVE_DIRECTORY)
	if dir == null:
		return result
	var prefix := "autosave_" if auto else "slot_"
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.begins_with(prefix) and file_name.ends_with(".json"):
			var slot := int(file_name.trim_prefix(prefix).trim_suffix(".json"))
			var info := _read_save_summary(slot, auto)
			if not info.is_empty():
				result.append(info)
		file_name = dir.get_next()
	dir.list_dir_end()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.slot) < int(b.slot))
	return result

func _read_save_summary(slot: int, auto: bool = false) -> Dictionary:
	var file := FileAccess.open(_save_path(slot, auto), FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {}
	var data := parsed as Dictionary
	var campaign_data: Variant = data.get("campaign", {})
	if not campaign_data is Dictionary:
		return {}
	var campaign := campaign_data as Dictionary
	return {
		"slot": slot,
		"saved_at_unix": int(data.get("saved_at_unix", 0)),
		"turn_number": int(campaign.get("turn_number", 0)),
		"player_faction_id": StringName(campaign.get("player_faction_id", "")),
	}

func _begin_faction_turn() -> void:
	active_faction_id = faction_turn_order[active_faction_index]
	_autosave()
	active_faction_changed.emit(active_faction_id, active_faction_index)
	GameState.campaign_runtime.reset_movement_for_faction(active_faction_id)
	_set_phase(Phase.INCOME)
	_run_income_phase(active_faction_id)
	GameState.advance_repairs_for_faction(active_faction_id)
	GameState.advance_pilot_injuries_for_faction(active_faction_id)
	GameState.refresh_intel_from_colocation(active_faction_id)
	## EVENT_DETAIL_SPECIFICATION.md section 8: "次の該当勢力ターン開始処理後、
	## 戦略フェイズ前に再生する". The player faction's pending_event_ids is
	## left populated for StrategicMap's EventPanel to present (blocking
	## player input the same way every other modal panel does); an AI
	## faction has no UI to show them to, so it auto-resolves immediately.
	GameState.check_pending_events(active_faction_id)
	if active_faction_id != GameState.player_faction_id:
		GameState.auto_resolve_pending_events(active_faction_id)
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
	GameState.refresh_intel_from_colocation(active_faction_id)
	_autosave()
	_set_phase(Phase.COMBAT)
	await _run_combat_phase()
	turn_events_ready.emit(_build_world_events_summary())
	_set_phase(Phase.DIPLOMACY)
	Diplomacy.apply_combat_events(GameState, last_combat_log)
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
		if _battle_involves_player(battle):
			battle_runtime_ready.emit(battle)
			await battle_runtime_finished
		else:
			_auto_resolve_battle(battle)
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

func _battle_involves_player(battle: BattleRuntimeState) -> bool:
	return battle.attacker_faction_id == GameState.player_faction_id or battle.defender_faction_id == GameState.player_faction_id

## A battle neither side of which is the player never emits battle_runtime_ready
## (strategic_map.gd would otherwise pop a BattlePrototypeView for every
## battle unconditionally), so it is simulated to completion synchronously
## here instead, using the same deterministic BattleRuntimeState/
## BattleCombatSystem the interactive view drives. Stepping in whole
## seconds (rather than one call covering the full 300-second cap) keeps
## elapsed_world_sec advancing accurately throughout, since a few call
## sites (e.g. the firing-disclosure reveal window) read it mid-battle.
func _auto_resolve_battle(battle: BattleRuntimeState) -> void:
	const AUTO_RESOLVE_STEP_SEC := 1.0
	battle.is_auto_resolving = true
	var max_iterations := int(ceil(BattleRuntimeState.MAX_WORLD_SEC / AUTO_RESOLVE_STEP_SEC)) + 5
	var iterations := 0
	while battle.result == null and iterations < max_iterations:
		battle.advance_time(AUTO_RESOLVE_STEP_SEC)
		iterations += 1
	if battle.result == null:
		push_error("Auto-resolved battle '%s' did not finalize within the world-time cap" % battle.battle_id)
		return
	var errors := complete_battle_runtime(battle)
	if not errors.is_empty():
		push_error("Failed to apply auto-resolved battle '%s': %s" % [battle.battle_id, errors])

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
	Diplomacy.tick_week(GameState, GameState.turn_number)

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
	if GameState.did_player_win():
		GameState.evaluate_achievements()
	GameState.game_over.emit(reason, standings)
