extends SceneTree

var failures := PackedStringArray()


func _initialize() -> void:
	_test_repair_amount_cost_cap_and_priority()
	_test_destroyed_unit_cannot_be_repaired()
	_test_en_transfer_conserves_total_en()
	_test_support_applies_after_simultaneous_damage()
	if failures.is_empty():
		print("battle_support_action_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("battle_support_action_test: %s" % failure)
		quit(1)


func _test_repair_amount_cost_cap_and_priority() -> void:
	var battle := _create_support_battle(_repair_skill(0.5))
	var supporter := battle.unit_states_by_id[&"supporter"] as BattleUnitState
	var low_ratio := battle.unit_states_by_id[&"ally_1"] as BattleUnitState
	var other := battle.unit_states_by_id[&"ally_2"] as BattleUnitState
	low_ratio.current_hp = 200
	other.current_hp = 450
	var supporter_en_before := supporter.current_en
	_fire_support_once(battle)
	_check(low_ratio.current_hp == 550, "repair did not apply fixed 250 + 10% max HP to the lowest-HP-ratio ally")
	_check(other.current_hp == 450, "repair ignored LOW_HP_RATIO target priority")
	_check(supporter.current_en == supporter_en_before - 40, "repair did not consume its full fixed EN cost")
	var repair_events := _support_events(battle, GameEnums.ActionType.REPAIR)
	_check(repair_events.size() == 1 and repair_events[0].get("target_unit_id") == &"ally_1", "repair event did not identify the selected target")

	var capped := _create_support_battle(_repair_skill(0.95))
	var capped_supporter := capped.unit_states_by_id[&"supporter"] as BattleUnitState
	var capped_target := capped.unit_states_by_id[&"ally_1"] as BattleUnitState
	capped_target.current_hp = 900
	(capped.unit_states_by_id[&"ally_2"] as BattleUnitState).current_hp = 1000
	var capped_en_before := capped_supporter.current_en
	_fire_support_once(capped)
	_check(capped_target.current_hp == capped_target.max_hp, "repair exceeded or failed to clamp at maximum HP")
	_check(capped_supporter.current_en == capped_en_before - 40, "capped repair did not consume the specified EN cost")


func _test_destroyed_unit_cannot_be_repaired() -> void:
	var battle := _create_support_battle(_repair_skill(1.0))
	var supporter := battle.unit_states_by_id[&"supporter"] as BattleUnitState
	var destroyed := battle.unit_states_by_id[&"ally_1"] as BattleUnitState
	destroyed.current_hp = 0
	destroyed.destroyed_this_battle = true
	(battle.unit_states_by_id[&"ally_2"] as BattleUnitState).current_hp = 1000
	var en_before := supporter.current_en
	_fire_support_once(battle)
	_check(destroyed.current_hp == 0 and destroyed.destroyed_this_battle, "repair revived a destroyed unit")
	_check(supporter.current_en == en_before, "supporter spent EN when no living repair target existed")


func _test_en_transfer_conserves_total_en() -> void:
	var skill := SupportSkillDef.new()
	skill.id = &"en_transfer_test"
	skill.action_type = GameEnums.ActionType.EN_TRANSFER
	skill.priority = 20
	skill.trigger_resource = &"en_pct"
	skill.trigger_threshold_pct = 0.5
	skill.target_rule = GameEnums.SupportTargetRule.LOW_EN_RATIO
	skill.target_pattern = GameEnums.TargetPattern.SINGLE
	skill.transfer_en = 60
	skill.en_cost = 60
	skill.can_target_self = false
	var battle := _create_support_battle(skill)
	var supporter := battle.unit_states_by_id[&"supporter"] as BattleUnitState
	var target := battle.unit_states_by_id[&"ally_1"] as BattleUnitState
	var other := battle.unit_states_by_id[&"ally_2"] as BattleUnitState
	supporter.current_en = 200
	target.current_en = 10
	other.current_en = 70
	var total_before := _squad_total_en(battle, &"attacker_squad")
	_fire_support_once(battle)
	_check(target.current_en == 70, "EN transfer did not select and replenish the lowest-EN-ratio ally")
	_check(supporter.current_en == 140, "EN transfer did not remove the transferred amount from the supporter")
	_check(_squad_total_en(battle, &"attacker_squad") == total_before, "EN transfer increased or decreased total squad EN")


func _test_support_applies_after_simultaneous_damage() -> void:
	var battle := _create_support_battle(_repair_skill(1.0), true)
	var victim := battle.unit_states_by_id[&"ally_1"] as BattleUnitState
	victim.current_hp = 50
	(battle.unit_states_by_id[&"ally_2"] as BattleUnitState).current_hp = 1000
	var enemy := battle.unit_states_by_id[&"enemy"] as BattleUnitState
	enemy.action_gauge = 100.0
	_fire_support_once(battle)
	_check(victim.current_hp == 0 and victim.destroyed_this_battle, "support was applied before simultaneous lethal damage")
	var repairs := _support_events(battle, GameEnums.ActionType.REPAIR)
	for event: Dictionary in repairs:
		_check(event.get("target_unit_id") != &"ally_1", "repair event was applied to a unit destroyed in the simultaneous damage phase")


func _repair_skill(threshold: float) -> SupportSkillDef:
	var skill := SupportSkillDef.new()
	skill.id = &"repair_test"
	skill.action_type = GameEnums.ActionType.REPAIR
	skill.priority = 20
	skill.trigger_resource = &"hp_pct"
	skill.trigger_threshold_pct = threshold
	skill.target_rule = GameEnums.SupportTargetRule.LOW_HP_RATIO
	skill.target_pattern = GameEnums.TargetPattern.SINGLE
	skill.fixed_repair = 250
	skill.max_hp_repair_pct = 0.1
	skill.en_cost = 40
	skill.post_action_delay_sec = 2.0
	skill.can_target_self = false
	return skill


func _create_support_battle(skill: SupportSkillDef, lethal_enemy: bool = false) -> BattleRuntimeState:
	var battle := BattleRuntimeState.new()
	battle.battle_id = &"support_test"
	battle.attacker_faction_id = &"attackers"
	battle.defender_faction_id = &"defenders"
	battle.attacker_squad_ids = [&"attacker_squad"]
	battle.defender_squad_ids = [&"defender_squad"]
	battle.rng_state = 4242
	var dummy_weapon := WeaponDef.new()
	dummy_weapon.id = &"dummy_weapon"
	dummy_weapon.total_power = 0
	dummy_weapon.hit_count = 1
	dummy_weapon.en_cost = 0
	dummy_weapon.min_range_m = 0.0
	dummy_weapon.max_range_m = 100.0
	battle.weapon_defs[dummy_weapon.id] = dummy_weapon
	var lethal_weapon := WeaponDef.new()
	lethal_weapon.id = &"lethal_weapon"
	lethal_weapon.total_power = 10000
	lethal_weapon.hit_count = 10
	lethal_weapon.penetration = 10000
	lethal_weapon.base_accuracy_pct = 95
	lethal_weapon.base_critical_pct = 0
	lethal_weapon.en_cost = 0
	lethal_weapon.min_range_m = 0.0
	lethal_weapon.max_range_m = 100.0
	battle.weapon_defs[lethal_weapon.id] = lethal_weapon
	var support_def := _unit_def(&"support_def", GameEnums.UnitRole.SUPPORT, [dummy_weapon.id], [skill.id])
	var ally_def := _unit_def(&"ally_def", GameEnums.UnitRole.DEFENSE, [], [])
	var enemy_def := _unit_def(&"enemy_def", GameEnums.UnitRole.ATTACK, [lethal_weapon.id if lethal_enemy else dummy_weapon.id], [])
	battle.unit_defs = {support_def.id: support_def, ally_def.id: ally_def, enemy_def.id: enemy_def}
	if _has_property(battle, &"support_skill_defs"):
		battle.set("support_skill_defs", {skill.id: skill})
	var attackers := _squad(&"attacker_squad", &"attackers", Vector3.ZERO, GameEnums.BattlePolicy.SUPPORT)
	attackers.unit_instance_ids = [&"ally_1", &"supporter", &"ally_2"]
	var defenders := _squad(&"defender_squad", &"defenders", Vector3(50, 0, 0), GameEnums.BattlePolicy.BALANCED)
	defenders.unit_instance_ids = [&"enemy"]
	battle.squad_states_by_id = {attackers.squad_id: attackers, defenders.squad_id: defenders}
	battle.unit_states_by_id[&"ally_1"] = _unit(&"ally_1", ally_def.id, attackers.squad_id, 0)
	battle.unit_states_by_id[&"supporter"] = _unit(&"supporter", support_def.id, attackers.squad_id, 1)
	battle.unit_states_by_id[&"ally_2"] = _unit(&"ally_2", ally_def.id, attackers.squad_id, 2)
	battle.unit_states_by_id[&"enemy"] = _unit(&"enemy", enemy_def.id, defenders.squad_id, 0)
	return battle


func _unit_def(id: StringName, role: int, weapons: Array[StringName], supports: Array[StringName]) -> UnitDef:
	var value := UnitDef.new()
	value.id = id
	value.role = role
	value.max_hp = 1000
	value.max_en = 1000
	value.firepower = 1000 if id == &"enemy_def" else 0
	value.armor = 0
	value.speed = 0
	value.evasion = 0
	value.weapon_ids = weapons
	value.support_skill_ids = supports
	return value


func _squad(id: StringName, faction: StringName, position: Vector3, policy: int) -> BattleSquadState:
	var value := BattleSquadState.new()
	value.squad_id = id
	value.faction_id = faction
	value.world_position = position
	value.destination = position
	value.policy = policy
	return value


func _unit(id: StringName, def_id: StringName, squad_id: StringName, slot: int) -> BattleUnitState:
	var value := BattleUnitState.new()
	value.unit_instance_id = id
	value.unit_def_id = def_id
	value.squad_id = squad_id
	value.slot_index = slot
	value.initial_hp = 1000
	value.current_hp = 1000
	value.max_hp = 1000
	value.initial_en = 1000
	value.current_en = 1000
	value.max_en = 1000
	return value


func _fire_support_once(battle: BattleRuntimeState) -> void:
	var supporter := battle.unit_states_by_id[&"supporter"] as BattleUnitState
	supporter.action_gauge = 100.0
	supporter.post_action_delay_sec = 0.0
	BattleCombatSystem.advance(battle, 0.001)


func _events_of_type(battle: BattleRuntimeState, type: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in battle.combat_events:
		if event.get("type") == type:
			result.append(event)
	return result


func _support_events(battle: BattleRuntimeState, action_type: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in battle.combat_events:
		if event.get("type") == &"support" and int(event.get("action_type", -1)) == action_type:
			result.append(event)
	return result


func _squad_total_en(battle: BattleRuntimeState, squad_id: StringName) -> int:
	var result := 0
	var squad := battle.squad_states_by_id[squad_id] as BattleSquadState
	for unit_id: StringName in squad.unit_instance_ids:
		result += (battle.unit_states_by_id[unit_id] as BattleUnitState).current_en
	return result


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if property.get("name") == property_name:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
