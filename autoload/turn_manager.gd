extends Node
## Drives the per-turn phase state machine. This is the core of the
## "shorter playtime than the original" design: orders are given per-region
## (not per-unit), and AI factions commit instantly with no "thinking" delay.

enum Phase { INCOME, ORDERS, MOVEMENT, COMBAT, DIPLOMACY, VICTORY_CHECK }

signal phase_changed(phase: Phase)
## Emitted once per player-involved battle so the UI can play a vignette.
## commit_turn() awaits vignette_dismissed before moving on, so battles are
## shown one at a time; AI-vs-AI battles never emit this (resolved silently).
signal battle_ready_for_vignette(entry: Dictionary)
signal vignette_dismissed
## Short human-readable line about AI-vs-AI activity the player didn't see
## a vignette for (world keeps moving even off-screen). Empty string means
## nothing notable happened this turn.
signal turn_events_ready(summary: String)

var current_phase: Phase = Phase.INCOME
var last_combat_log: Array = []  # this turn's auto-captures/battles, for logging/UI

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
	for entry in last_combat_log:
		if entry["type"] == "battle" and _involves_player(entry):
			battle_ready_for_vignette.emit(entry)
			await vignette_dismissed
	turn_events_ready.emit(_build_world_events_summary())
	_set_phase(Phase.DIPLOMACY)
	_run_diplomacy_phase()
	_set_phase(Phase.VICTORY_CHECK)
	if _run_victory_check():
		return
	GameState.advance_turn()
	_begin_turn()

func _involves_player(entry: Dictionary) -> bool:
	return entry["attacker_id"] == GameState.player_faction_id or entry["defender_id"] == GameState.player_faction_id

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
	last_combat_log = []
	for region in GameState.regions.values():
		var occupants: Array = region.occupying_faction_ids()
		if occupants.is_empty():
			continue

		var hostile_occupants: Array = []
		for fid in occupants:
			if fid != region.owner_faction_id:
				hostile_occupants.append(fid)
		if hostile_occupants.is_empty():
			continue

		var attacker_id: StringName = _strongest_faction(hostile_occupants, region)

		if region.owner_faction_id == &"":
			var others: Array = []
			for fid in hostile_occupants:
				if fid != attacker_id:
					others.append(fid)
			if others.is_empty():
				_auto_capture(region, attacker_id)
			else:
				var defender_id: StringName = _strongest_faction(others, region)
				_resolve_combat(region, attacker_id, defender_id)
		else:
			var defender_stack: UnitStack = region.stacks.get(region.owner_faction_id)
			if defender_stack == null or defender_stack.is_empty():
				_auto_capture(region, attacker_id)
			else:
				_resolve_combat(region, attacker_id, region.owner_faction_id)

func _strongest_faction(candidate_ids: Array, region: Region) -> StringName:
	var best_id: StringName = candidate_ids[0]
	var best_power := -1.0
	for fid in candidate_ids:
		var stack: UnitStack = region.stacks.get(fid)
		var faction: Faction = GameState.get_faction(fid)
		var power := CombatResolver.stack_power(stack, true, faction, region)
		if power > best_power:
			best_power = power
			best_id = fid
	return best_id

func _auto_capture(region: Region, faction_id: StringName) -> void:
	GameState.set_region_owner(region.def.id, faction_id)
	last_combat_log.append({"region_id": region.def.id, "type": "auto_capture", "faction_id": faction_id})

func _resolve_combat(region: Region, attacker_id: StringName, defender_id: StringName) -> void:
	var attacker_stack: UnitStack = region.stacks.get(attacker_id)
	var defender_stack: UnitStack = region.stacks.get(defender_id)
	var attacker_before: int = attacker_stack.total_count()
	var defender_before: int = defender_stack.total_count() if defender_stack else 0
	# Snapshot composition before losses are applied, so the vignette can
	# show which unit types were actually involved (apply_losses may zero
	# out and erase entries from stack.units).
	var attacker_units_before: Dictionary = attacker_stack.units.duplicate()
	var defender_units_before: Dictionary = defender_stack.units.duplicate() if defender_stack else {}

	var result := CombatResolver.resolve(attacker_stack, defender_stack, region)
	attacker_stack.apply_losses(result.attacker_losses)
	if defender_stack:
		defender_stack.apply_losses(result.defender_losses)
	if result.region_captured:
		GameState.set_region_owner(region.def.id, attacker_id)

	last_combat_log.append({
		"region_id": region.def.id,
		"type": "battle",
		"attacker_id": attacker_id,
		"defender_id": defender_id,
		"outcome": result.outcome,
		"attacker_before": attacker_before,
		"attacker_after": attacker_stack.total_count(),
		"defender_before": defender_before,
		"defender_after": defender_stack.total_count() if defender_stack else 0,
		"attacker_units": attacker_units_before,
		"defender_units": defender_units_before,
		"captured": result.region_captured,
	})

func _build_world_events_summary() -> String:
	var lines: Array = []
	for entry in last_combat_log:
		var region_name: String = GameState.region_defs[entry["region_id"]].display_name
		if entry["type"] == "auto_capture":
			var fdef: FactionDef = GameState.faction_defs[entry["faction_id"]]
			lines.append("%s が %s を無血占領しました。" % [fdef.display_name, region_name])
		elif entry["type"] == "battle":
			if _involves_player(entry):
				continue  # the player already saw this one via the vignette
			var attacker_fdef: FactionDef = GameState.faction_defs[entry["attacker_id"]]
			var defender_fdef: FactionDef = GameState.faction_defs[entry["defender_id"]]
			if entry["captured"]:
				lines.append("%s が %s で %s を撃破し占領しました。" % [attacker_fdef.display_name, region_name, defender_fdef.display_name])
			else:
				lines.append("%s が %s で %s と交戦しましたが決着つかず。" % [attacker_fdef.display_name, region_name, defender_fdef.display_name])
	return "\n".join(lines)

func _run_diplomacy_phase() -> void:
	Diplomacy.apply_combat_events(last_combat_log)
	Diplomacy.tick_drift()

func _run_victory_check() -> bool:
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
	GameState.last_game_over_reason = reason
	GameState.last_game_over_standings = standings
	GameState.game_over.emit(reason, standings)
