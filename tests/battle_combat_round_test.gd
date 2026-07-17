extends SceneTree

const ROUND_DURATION_SEC := 30.0
const REENGAGE_WAIT_SEC := 5.0

var failures := PackedStringArray()


func _initialize() -> void:
	_test_thirty_second_round_cleanup()
	_test_reengage_wait()
	_test_one_to_one_exclusivity()
	_test_pause_freezes_round_state()
	if failures.is_empty():
		print("battle_combat_round_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("battle_combat_round_test: %s" % failure)
		quit(1)


func _test_thirty_second_round_cleanup() -> void:
	var battle := _create_battle(false)
	var attacker := battle.unit_states_by_id[&"attacker_unit_0"] as BattleUnitState
	var defender := battle.unit_states_by_id[&"defender_unit"] as BattleUnitState
	attacker.action_gauge = 41.0
	defender.action_gauge = 63.0
	attacker.post_action_delay_sec = 100.0
	defender.post_action_delay_sec = 100.0
	battle.advance_time(ROUND_DURATION_SEC - 0.1)
	_check(attacker.action_gauge == 41.0 and defender.action_gauge == 63.0, "round state was discarded before 30 seconds")
	_check(attacker.post_action_delay_sec > 0.0 and defender.post_action_delay_sec > 0.0, "post-action delay was discarded before 30 seconds")
	battle.advance_time(0.1)
	_check(attacker.action_gauge == 0.0 and defender.action_gauge == 0.0, "30-second round end did not discard action gauges")
	_check(attacker.post_action_delay_sec == 0.0 and defender.post_action_delay_sec == 0.0, "30-second round end did not discard post-action delays")
	var attacker_squad := battle.squad_states_by_id[&"attacker_squad_0"] as BattleSquadState
	var defender_squad := battle.squad_states_by_id[&"defender_squad"] as BattleSquadState
	_check(is_equal_approx(attacker_squad.reengage_wait_sec, REENGAGE_WAIT_SEC), "attacker did not enter five-second reengage wait")
	_check(is_equal_approx(defender_squad.reengage_wait_sec, REENGAGE_WAIT_SEC), "defender did not enter five-second reengage wait")


func _test_reengage_wait() -> void:
	var battle := _create_battle(false)
	battle.advance_time(ROUND_DURATION_SEC)
	var attacker_squad := battle.squad_states_by_id[&"attacker_squad_0"] as BattleSquadState
	var defender_squad := battle.squad_states_by_id[&"defender_squad"] as BattleSquadState
	battle.advance_time(REENGAGE_WAIT_SEC - 0.1)
	_check(attacker_squad.reengage_wait_sec > 0.0 and defender_squad.reengage_wait_sec > 0.0, "reengage wait ended before five seconds")
	battle.advance_time(0.1)
	_check(attacker_squad.reengage_wait_sec == 0.0 and defender_squad.reengage_wait_sec == 0.0, "reengage wait did not end after five seconds")


func _test_one_to_one_exclusivity() -> void:
	var battle := _create_battle(true)
	for unit: BattleUnitState in battle.unit_states_by_id.values():
		unit.action_gauge = 100.0
		unit.post_action_delay_sec = 0.0
	BattleCombatSystem.advance(battle, 0.001)
	var pairs := {}
	for event: Dictionary in battle.combat_events:
		if event.get("type") != &"shot":
			continue
		var source_id := StringName(event.get("source_unit_id", ""))
		var target_id := StringName(event.get("target_unit_id", ""))
		pairs["%s>%s" % [source_id, target_id]] = true
	_check(pairs.has("attacker_unit_0>defender_unit"), "stable first attacker was not paired with the defender")
	_check(pairs.has("defender_unit>attacker_unit_0"), "defender did not return fire against its exclusive opponent")
	_check(not pairs.has("attacker_unit_1>defender_unit"), "a second squad attacked a defender already engaged in a 1-to-1 round")


func _test_pause_freezes_round_state() -> void:
	var battle := _create_battle(false)
	var attacker := battle.unit_states_by_id[&"attacker_unit_0"] as BattleUnitState
	var attacker_squad := battle.squad_states_by_id[&"attacker_squad_0"] as BattleSquadState
	attacker.action_gauge = 25.0
	attacker.post_action_delay_sec = 2.0
	attacker_squad.reengage_wait_sec = 4.0
	battle.time_scale = 0.0
	var elapsed_before := battle.elapsed_world_sec
	var rng_before := battle.rng_state
	battle.advance_time(10.0)
	_check(battle.elapsed_world_sec == elapsed_before, "pause advanced battle world time")
	_check(attacker.action_gauge == 25.0 and attacker.post_action_delay_sec == 2.0, "pause advanced round unit state")
	_check(attacker_squad.reengage_wait_sec == 4.0, "pause advanced reengage wait")
	_check(battle.rng_state == rng_before and battle.combat_events.is_empty(), "pause consumed combat RNG or emitted events")


func _create_battle(include_second_attacker: bool) -> BattleRuntimeState:
	var battle := BattleRuntimeState.new()
	battle.battle_id = &"round_test"
	battle.attacker_faction_id = &"attackers"
	battle.defender_faction_id = &"defenders"
	battle.rng_state = 4242
	battle.attacker_squad_ids = [&"attacker_squad_0"]
	if include_second_attacker:
		battle.attacker_squad_ids.append(&"attacker_squad_1")
	battle.defender_squad_ids = [&"defender_squad"]
	var weapon := WeaponDef.new()
	weapon.id = &"round_weapon"
	weapon.total_power = 0
	weapon.hit_count = 1
	weapon.en_cost = 0
	weapon.post_action_delay_sec = 0.0
	weapon.min_range_m = 0.0
	weapon.max_range_m = 100.0
	weapon.base_accuracy_pct = 95
	weapon.target_pattern = GameEnums.TargetPattern.SINGLE
	battle.weapon_defs[weapon.id] = weapon
	var unit_def := UnitDef.new()
	unit_def.id = &"round_unit"
	unit_def.max_hp = 10000
	unit_def.max_en = 10000
	unit_def.firepower = 0
	unit_def.armor = 10000
	unit_def.speed = 0
	unit_def.weapon_ids = [weapon.id]
	battle.unit_defs[unit_def.id] = unit_def
	_add_squad_and_unit(battle, &"attacker_squad_0", &"attacker_unit_0", &"attackers", Vector3.ZERO)
	if include_second_attacker:
		_add_squad_and_unit(battle, &"attacker_squad_1", &"attacker_unit_1", &"attackers", Vector3(0, 10, 0))
	_add_squad_and_unit(battle, &"defender_squad", &"defender_unit", &"defenders", Vector3(50, 0, 0))
	return battle


func _add_squad_and_unit(battle: BattleRuntimeState, squad_id: StringName, unit_id: StringName, faction_id: StringName, position: Vector3) -> void:
	var squad := BattleSquadState.new()
	squad.squad_id = squad_id
	squad.faction_id = faction_id
	squad.world_position = position
	squad.destination = position
	squad.unit_instance_ids = [unit_id]
	battle.squad_states_by_id[squad_id] = squad
	var unit := BattleUnitState.new()
	unit.unit_instance_id = unit_id
	unit.unit_def_id = &"round_unit"
	unit.squad_id = squad_id
	unit.slot_index = 0
	unit.initial_hp = 10000
	unit.current_hp = 10000
	unit.max_hp = 10000
	unit.initial_en = 10000
	unit.current_en = 10000
	unit.max_en = 10000
	battle.unit_states_by_id[unit_id] = unit


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
