extends SceneTree

var failures := PackedStringArray()


func _initialize() -> void:
	_test_rates_and_fractional_accumulation()
	_test_destroyed_units_are_excluded()
	_test_enemy_presence_stops_recovery()
	_test_pause_and_engagement_stop_recovery()
	_test_overlapping_points_do_not_stack()
	_test_owner_change_switches_recovering_faction()
	if failures.is_empty():
		print("battle_control_point_recovery_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("battle_control_point_recovery_test: %s" % failure)
		quit(1)


func _test_rates_and_fractional_accumulation() -> void:
	var battle := _create_battle(false)
	var unit := battle.unit_states_by_id[&"attacker_unit"] as BattleUnitState
	unit.current_hp = 500
	unit.current_en = 500
	battle.advance_time(0.05)
	_check(unit.current_hp == 500, "fractional HP recovery was rounded up per tick")
	_check(unit.current_en == 501, "whole EN recovery was not applied while retaining only the fractional remainder")
	battle.advance_time(0.05)
	_check(unit.current_hp == 501, "control point did not recover exactly 1% max HP per second with fractional carry")
	_check(unit.current_en == 502, "control point did not recover exactly 2% max EN per second with fractional carry")
	battle.advance_time(100.0)
	_check(unit.current_hp == unit.max_hp and unit.current_en == unit.max_en, "control-point recovery exceeded or failed to clamp at HP/EN maximum")


func _test_destroyed_units_are_excluded() -> void:
	var battle := _create_battle(false)
	var unit := battle.unit_states_by_id[&"attacker_unit"] as BattleUnitState
	unit.current_hp = 0
	unit.current_en = 100
	unit.destroyed_this_battle = true
	battle.advance_time(5.0)
	_check(unit.current_hp == 0 and unit.current_en == 100 and unit.destroyed_this_battle, "control point recovered a destroyed unit")


func _test_enemy_presence_stops_recovery() -> void:
	var battle := _create_battle(true)
	var friendly := battle.unit_states_by_id[&"attacker_unit"] as BattleUnitState
	friendly.current_hp = 500
	friendly.current_en = 500
	var enemy_squad := battle.squad_states_by_id[&"defender_squad"] as BattleSquadState
	enemy_squad.world_position = Vector3.ZERO
	enemy_squad.destination = enemy_squad.world_position
	enemy_squad.reengage_wait_sec = 100.0
	battle.advance_time(1.0)
	_check(friendly.current_hp == 500 and friendly.current_en == 500, "control point recovered units while an enemy was inside its radius")


func _test_pause_and_engagement_stop_recovery() -> void:
	var paused := _create_battle(false)
	var paused_unit := paused.unit_states_by_id[&"attacker_unit"] as BattleUnitState
	paused_unit.current_hp = 500
	paused_unit.current_en = 500
	paused.time_scale = 0.0
	paused.advance_time(10.0)
	_check(paused_unit.current_hp == 500 and paused_unit.current_en == 500, "control-point recovery advanced while paused")

	var engaged := _create_battle(true)
	var engaged_unit := engaged.unit_states_by_id[&"attacker_unit"] as BattleUnitState
	engaged_unit.current_hp = 500
	engaged_unit.current_en = 500
	var engagement := BattleEngagementState.new()
	engagement.first_squad_id = &"attacker_squad"
	engagement.second_squad_id = &"defender_squad"
	engagement.confirmed = true
	engaged.engagements_by_squad_id[&"attacker_squad"] = engagement
	engaged.engagements_by_squad_id[&"defender_squad"] = engagement
	engaged.advance_time(1.0)
	_check(engaged_unit.current_hp == 500 and engaged_unit.current_en == 500, "control point recovered units during an engagement")


func _test_overlapping_points_do_not_stack() -> void:
	var battle := _create_battle(false)
	_add_control_point(battle, &"second_point", &"attackers", Vector3.ZERO)
	var unit := battle.unit_states_by_id[&"attacker_unit"] as BattleUnitState
	unit.current_hp = 500
	unit.current_en = 500
	battle.advance_time(1.0)
	_check(unit.current_hp == 510, "overlapping friendly control points stacked HP recovery")
	_check(unit.current_en == 520, "overlapping friendly control points stacked EN recovery")


func _test_owner_change_switches_recovering_faction() -> void:
	var battle := _create_battle(true)
	var attacker := battle.unit_states_by_id[&"attacker_unit"] as BattleUnitState
	var defender := battle.unit_states_by_id[&"defender_unit"] as BattleUnitState
	attacker.current_hp = 500
	attacker.current_en = 500
	defender.current_hp = 500
	defender.current_en = 500
	var defender_squad := battle.squad_states_by_id[&"defender_squad"] as BattleSquadState
	defender_squad.world_position = Vector3.ZERO
	defender_squad.destination = defender_squad.world_position
	var attacker_squad := battle.squad_states_by_id[&"attacker_squad"] as BattleSquadState
	attacker_squad.world_position = Vector3(300, 300, 0)
	attacker_squad.destination = attacker_squad.world_position
	var point := battle.control_point_states[&"test_point"] as BattleControlPointState
	point.owner_faction_id = &"defenders"
	battle.advance_time(1.0)
	_check(defender.current_hp == 510 and defender.current_en == 520, "new owner did not receive control-point recovery")
	_check(attacker.current_hp == 500 and attacker.current_en == 500, "previous owner continued receiving control-point recovery")


func _create_battle(include_defender: bool) -> BattleRuntimeState:
	var battle := BattleRuntimeState.new()
	battle.battle_id = &"control_recovery_test"
	battle.attacker_faction_id = &"attackers"
	battle.defender_faction_id = &"defenders"
	battle.attacker_squad_ids = [&"attacker_squad"]
	battle.defender_squad_ids = []
	if include_defender:
		battle.defender_squad_ids.append(&"defender_squad")
	_add_squad_and_unit(battle, &"attacker_squad", &"attacker_unit", &"attackers", Vector3.ZERO)
	if include_defender:
		_add_squad_and_unit(battle, &"defender_squad", &"defender_unit", &"defenders", Vector3(300, 300, 0))
	_add_control_point(battle, &"test_point", &"attackers", Vector3.ZERO)
	return battle


func _add_control_point(battle: BattleRuntimeState, id: StringName, owner: StringName, position: Vector3) -> void:
	var definition := BattleControlPointDef.new()
	definition.id = id
	definition.position = position
	definition.capture_radius_m = 70.0
	definition.hp_recovery_pct_per_sec = 0.01
	definition.en_recovery_pct_per_sec = 0.02
	battle.control_point_defs_by_id[id] = definition
	var state := BattleControlPointState.new()
	state.control_point_id = id
	state.owner_faction_id = owner
	battle.control_point_states[id] = state


func _add_squad_and_unit(battle: BattleRuntimeState, squad_id: StringName, unit_id: StringName, faction: StringName, position: Vector3) -> void:
	var squad := BattleSquadState.new()
	squad.squad_id = squad_id
	squad.faction_id = faction
	squad.world_position = position
	squad.destination = position
	squad.unit_instance_ids = [unit_id]
	battle.squad_states_by_id[squad_id] = squad
	var unit := BattleUnitState.new()
	unit.unit_instance_id = unit_id
	unit.unit_def_id = &"recovery_unit"
	unit.squad_id = squad_id
	unit.slot_index = 0
	unit.initial_hp = 1000
	unit.current_hp = 1000
	unit.max_hp = 1000
	unit.initial_en = 1000
	unit.current_en = 1000
	unit.max_en = 1000
	battle.unit_states_by_id[unit_id] = unit


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
