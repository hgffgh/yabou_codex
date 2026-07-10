extends Node
## Drives the per-turn phase state machine. This is the core of the
## "shorter playtime than the original" design: orders are given per-region
## (not per-unit), and AI factions commit instantly with no "thinking" delay.

enum Phase { INCOME, ORDERS, MOVEMENT, COMBAT, DIPLOMACY, VICTORY_CHECK }

signal phase_changed(phase: Phase)

var current_phase: Phase = Phase.INCOME

func start_new_game(player_faction_id: StringName) -> void:
	GameState.start_new_game(player_faction_id)
	_begin_turn()

func _begin_turn() -> void:
	_set_phase(Phase.INCOME)
	_run_income_phase()
	_set_phase(Phase.ORDERS)
	# Waits here: the player issues per-region orders directly against
	# GameState/Region from the StrategicMap UI, then calls commit_turn().

## Called by the StrategicMap UI's "End Turn" button.
func commit_turn() -> void:
	if GameState.is_game_over:
		return
	_run_ai_orders()
	_set_phase(Phase.MOVEMENT)
	_run_movement_phase()
	_set_phase(Phase.COMBAT)
	_run_combat_phase()
	_set_phase(Phase.DIPLOMACY)
	_run_diplomacy_phase()
	_set_phase(Phase.VICTORY_CHECK)
	if _run_victory_check():
		return
	GameState.advance_turn()
	_begin_turn()

func _set_phase(phase: Phase) -> void:
	current_phase = phase
	phase_changed.emit(phase)

func _run_income_phase() -> void:
	for region in GameState.regions.values():
		_advance_production(region)
		if region.owner_faction_id == &"":
			continue
		var faction: Faction = GameState.get_faction(region.owner_faction_id)
		if faction:
			faction.resources += region.def.resource_yield

func _advance_production(region: Region) -> void:
	var still_building := []
	for job in region.pending_production:
		job["turns_remaining"] -= 1
		if job["turns_remaining"] <= 0:
			var stack := region.get_or_create_stack(region.owner_faction_id)
			stack.add_units(job["unit_type_id"], 1)
		else:
			still_building.append(job)
	region.pending_production = still_building

func _run_ai_orders() -> void:
	for fid in GameState.factions:
		var faction: Faction = GameState.factions[fid]
		if faction.is_ai_controlled and not faction.eliminated:
			AiController.decide_orders(fid)

func _run_movement_phase() -> void:
	for region in GameState.regions.values():
		if region.pending_move_order == &"":
			continue
		var dest_id: StringName = region.pending_move_order
		region.pending_move_order = &""
		var dest: Region = GameState.get_region(dest_id)
		if dest == null or not region.def.neighbor_ids.has(dest_id):
			continue
		for faction_id in region.stacks.keys():
			var source_stack: UnitStack = region.stacks[faction_id]
			if source_stack.is_empty():
				continue
			var dest_stack := dest.get_or_create_stack(faction_id)
			for unit_id in source_stack.units:
				dest_stack.add_units(unit_id, source_stack.units[unit_id])
			source_stack.units.clear()

func _run_combat_phase() -> void:
	# CombatResolver lands in M3. For now just detect+log contested regions
	# so the phase pipeline is fully exercised end-to-end ahead of that work.
	for region in GameState.regions.values():
		if region.owner_faction_id == &"":
			continue
		var hostile_occupants: Array = []
		for fid in region.occupying_faction_ids():
			if fid != region.owner_faction_id and fid != &"":
				hostile_occupants.append(fid)
		if not hostile_occupants.is_empty():
			print("TurnManager: %s contested by %s (combat resolution lands in M3)" % [region.def.display_name, hostile_occupants])

func _run_diplomacy_phase() -> void:
	pass  # Relation-score ticking/events land with AI/diplomacy work in M4.

func _run_victory_check() -> bool:
	var alive := GameState.alive_faction_ids()
	var total_regions := GameState.regions.size()
	for fid in alive:
		var pct := float(GameState.region_count_for(fid)) / float(total_regions)
		if pct >= GameState.campaign_config.victory_region_threshold_pct:
			_end_game("region_threshold", [{"faction_id": fid, "score": -1}])
			return true
	if GameState.turn_number >= GameState.campaign_config.turn_cap:
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
	GameState.game_over.emit(reason, standings)
