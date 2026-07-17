extends SceneTree

func _initialize() -> void:
	var battle := BattleRuntimeState.new()
	var squad := BattleSquadState.new()
	squad.squad_id = &"squad"
	squad.faction_id = &"a"
	squad.unit_instance_ids = [&"dead_leader", &"front_candidate", &"rear_candidate"]
	squad.leader_unit_id = &"dead_leader"
	squad.leader_command = 180
	battle.squad_states_by_id[squad.squad_id] = squad
	_add_unit(battle, &"dead_leader", 0, 180, 0)
	_add_unit(battle, &"front_candidate", 1, 140, 100)
	_add_unit(battle, &"rear_candidate", 3, 140, 100)
	battle._reselect_leader_if_needed(squad)
	if squad.leader_unit_id == &"front_candidate" and squad.leader_command == 140:
		print("battle_leader_reselection_test: all checks passed")
		quit(0)
	else:
		push_error("battle_leader_reselection_test: highest-command front-slot candidate was not selected")
		quit(1)

func _add_unit(battle: BattleRuntimeState, id: StringName, slot: int, command: int, hp: int) -> void:
	var unit := BattleUnitState.new()
	unit.unit_instance_id = id
	unit.squad_id = &"squad"
	unit.slot_index = slot
	unit.command = command
	unit.current_hp = hp
	battle.unit_states_by_id[id] = unit
