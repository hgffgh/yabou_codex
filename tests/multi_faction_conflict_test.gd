extends SceneTree

var failures := PackedStringArray()
var game_state: Node
var turn_manager: Node


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	turn_manager = root.get_node_or_null("TurnManager")
	if game_state == null or turn_manager == null:
		push_error("multi_faction_conflict_test: required autoload is unavailable")
		quit(1)
		return

	_test_detect_squad_conflicts_reports_multi_faction_pending()
	await _test_sequential_resolution_clears_every_defender()
	_finish()


func _test_detect_squad_conflicts_reports_multi_faction_pending() -> void:
	game_state.start_new_game(&"nova_republic")
	var attacker: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"crimson_border")
	game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", &"crimson_border")
	_insert_fake_faction_squad(&"pirate_faction", &"squad_pirate_00000001", &"unit_pirate_00000001", &"crimson_border")
	attacker.squad.move_origin_region_id = &"nova_border"

	var events: Array[Dictionary] = game_state.detect_squad_conflicts(&"nova_republic")
	_check(events.size() == 1, "two hostile defending factions in one region did not produce exactly one event")
	if events.size() != 1:
		return
	var event := events[0]
	_check(event.get("type", "") == "multi_faction_battle_pending",
		"two hostile defenders did not report as multi_faction_battle_pending")
	_check(event.get("attacker_id", &"") == &"nova_republic", "multi-faction event has the wrong attacker")
	var defender_ids: Array = event.get("defender_faction_ids", [])
	_check(defender_ids == [&"crimson_empire", &"pirate_faction"],
		"multi-faction event did not list both defending factions sorted by ID, got %s" % [defender_ids])
	_check(game_state.get_region(&"crimson_border").owner_faction_id == &"crimson_empire",
		"multi-faction pending contact changed ownership before combat resolution")


## Directly drives TurnManager._resolve_multi_faction_battle — the sequential
## pairwise resolution that replaced the permanent dead end where a region
## with two or more hostile defending factions was detected every turn and
## then silently skipped forever. Each emitted sub-battle is auto-resolved
## as a decisive attacker win, and both defending factions must actually be
## fought within the same combat phase.
func _test_sequential_resolution_clears_every_defender() -> void:
	game_state.start_new_game(&"nova_republic")
	var attacker: Dictionary = game_state.rollout_new_unit(&"nova_scout", &"nova_republic", &"crimson_border")
	game_state.rollout_new_unit(&"crimson_bastion", &"crimson_empire", &"crimson_border")
	_insert_fake_faction_squad(&"pirate_faction", &"squad_pirate_00000002", &"unit_pirate_00000002", &"crimson_border")
	attacker.squad.move_origin_region_id = &"nova_border"

	var events: Array[Dictionary] = game_state.detect_squad_conflicts(&"nova_republic")
	_check(events.size() == 1 and events[0].get("type", "") == "multi_faction_battle_pending",
		"setup did not produce a multi-faction pending contact")
	if events.size() != 1:
		return

	var resolved_defenders: Array[StringName] = []
	var on_ready := func(battle: BattleRuntimeState) -> void:
		resolved_defenders.append(battle.defender_faction_id)
		for squad_id: StringName in battle.defender_squad_ids:
			var squad := battle.squad_states_by_id[squad_id] as BattleSquadState
			for unit_id: StringName in squad.unit_instance_ids:
				(battle.unit_states_by_id[unit_id] as BattleUnitState).current_hp = 0
		battle.finalize(battle.attacker_faction_id, battle.defender_faction_id, &"annihilation")
		turn_manager.complete_battle_runtime(battle)
	# CONNECT_DEFERRED: a same-stack callback would call complete_battle_runtime
	# before _resolve_squad_battle's "await battle_runtime_finished" has
	# actually registered its listener, permanently losing the completion
	# signal. Deferring to the next idle frame guarantees the await is live.
	turn_manager.battle_runtime_ready.connect(on_ready, CONNECT_DEFERRED)
	await turn_manager._resolve_multi_faction_battle(events[0])
	turn_manager.battle_runtime_ready.disconnect(on_ready)

	_check(resolved_defenders == [&"crimson_empire", &"pirate_faction"],
		"sequential resolution did not fight both defenders in sorted order, got %s" % [resolved_defenders])
	_check(game_state.get_region(&"crimson_border").owner_faction_id == &"nova_republic",
		"attacker did not end up owning the region after clearing every defender")
	_check(game_state.combat_capable_squad_ids_in_region(&"crimson_border", &"crimson_empire").is_empty(),
		"crimson defender still has combat-capable squads after annihilation")
	_check(game_state.combat_capable_squad_ids_in_region(&"crimson_border", &"pirate_faction").is_empty(),
		"pirate defender still has combat-capable squads after annihilation")


## Bypasses rollout_new_unit's registry.factions validation to plant a
## defending squad for a faction that has no FactionDef, since the current
## two-faction dataset can't otherwise produce a real 2-hostile-defender
## contact. detect_squad_conflicts groups purely by owner_faction_id and
## never consults faction_defs, so this is representative of the real path.
func _insert_fake_faction_squad(faction_id: StringName, squad_id: StringName, unit_id: StringName, region_id: StringName) -> Dictionary:
	var unit := UnitInstanceState.new()
	unit.instance_id = unit_id
	unit.unit_def_id = &"crimson_bastion"
	unit.owner_faction_id = faction_id
	unit.origin_faction_id = faction_id
	unit.current_hp = 100
	unit.current_en = 100
	unit.squad_id = squad_id
	unit.slot_index = 0

	var squad := SquadState.new()
	squad.squad_id = squad_id
	squad.owner_faction_id = faction_id
	squad.region_id = region_id
	squad.assign_unit(unit_id, 0)

	game_state.campaign_runtime.units_by_id[unit_id] = unit
	game_state.campaign_runtime.squads_by_id[squad_id] = squad
	return {"unit": unit, "squad": squad}


func _finish() -> void:
	if failures.is_empty():
		print("multi_faction_conflict_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("multi_faction_conflict_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
