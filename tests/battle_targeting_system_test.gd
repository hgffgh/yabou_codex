extends SceneTree

var failures := PackedStringArray()


func _initialize() -> void:
	_test_target_rules()
	_test_random_rule_is_deterministic()
	_test_front_priority_and_fallback()
	_test_fixed_target_patterns()
	if failures.is_empty():
		print("battle_targeting_system_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("battle_targeting_system_test: %s" % failure)
		quit(1)


func _test_target_rules() -> void:
	var cases := [
		[GameEnums.TargetRule.FRONT, &"defender_0"],
		[GameEnums.TargetRule.LOW_HP, &"defender_1"],
		[GameEnums.TargetRule.HIGH_HP, &"defender_2"],
		[GameEnums.TargetRule.LOW_ARMOR, &"defender_1"],
		[GameEnums.TargetRule.HIGH_ARMOR, &"defender_2"],
		[GameEnums.TargetRule.HIGH_SPEED, &"defender_2"],
		[GameEnums.TargetRule.SUPPORT, &"defender_1"],
	]
	for entry: Array in cases:
		var battle := _create_battle(101)
		var weapon := battle.weapon_defs[&"test_weapon"] as WeaponDef
		weapon.target_rule = entry[0]
		weapon.target_pattern = GameEnums.TargetPattern.SINGLE
		var targets := _fire_once(battle)
		_check(targets == [entry[1]], "target rule %d chose %s instead of %s" % [entry[0], targets, entry[1]])


func _test_random_rule_is_deterministic() -> void:
	var first := _create_battle(777)
	var second := _create_battle(777)
	(first.weapon_defs[&"test_weapon"] as WeaponDef).target_rule = GameEnums.TargetRule.RANDOM
	(second.weapon_defs[&"test_weapon"] as WeaponDef).target_rule = GameEnums.TargetRule.RANDOM
	var first_targets := _fire_once(first)
	var second_targets := _fire_once(second)
	_check(first_targets.size() == 1, "random target rule did not select exactly one target")
	_check(first_targets == second_targets, "random target rule was not reproducible for the same seed")
	_check(first.rng_state == second.rng_state, "random target selection did not preserve deterministic RNG state")


func _test_front_priority_and_fallback() -> void:
	var battle := _create_battle(303)
	var weapon := battle.weapon_defs[&"test_weapon"] as WeaponDef
	weapon.target_rule = GameEnums.TargetRule.FRONT
	weapon.target_pattern = GameEnums.TargetPattern.SINGLE
	_check(_fire_once(battle) == [&"defender_0"], "front targeting did not prefer the smallest living front slot")
	for slot in range(3):
		(battle.unit_states_by_id[StringName("defender_%d" % slot)] as BattleUnitState).current_hp = 0
	_reset_attacker(battle)
	_check(_fire_once(battle) == [&"defender_3"], "front targeting did not fall back to the smallest living rear slot")


func _test_fixed_target_patterns() -> void:
	var cases := [
		[GameEnums.TargetPattern.FRONT_ROW, [&"defender_0", &"defender_1", &"defender_2"]],
		[GameEnums.TargetPattern.REAR_ROW, [&"defender_3", &"defender_4"]],
		[GameEnums.TargetPattern.LEFT_COLUMN, [&"defender_0", &"defender_3"]],
		[GameEnums.TargetPattern.CENTER, [&"defender_1"]],
		[GameEnums.TargetPattern.RIGHT_COLUMN, [&"defender_2", &"defender_4"]],
		[GameEnums.TargetPattern.ALL_ENEMIES, [&"defender_0", &"defender_1", &"defender_2", &"defender_3", &"defender_4"]],
	]
	for entry: Array in cases:
		var battle := _create_battle(909)
		var weapon := battle.weapon_defs[&"test_weapon"] as WeaponDef
		weapon.target_rule = GameEnums.TargetRule.FRONT
		weapon.target_pattern = entry[0]
		var actual := _fire_once(battle)
		actual.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		var expected: Array = entry[1]
		_check(actual == expected, "target pattern %d affected %s instead of %s" % [entry[0], actual, expected])


func _create_battle(seed: int) -> BattleRuntimeState:
	var battle := BattleRuntimeState.new()
	battle.battle_id = &"targeting_test"
	battle.attacker_faction_id = &"attackers"
	battle.defender_faction_id = &"defenders"
	battle.rng_state = seed
	battle.attacker_squad_ids = [&"attacker_squad"]
	battle.defender_squad_ids = [&"defender_squad"]
	var attacker_squad := _make_squad(&"attacker_squad", &"attackers", Vector3.ZERO)
	attacker_squad.unit_instance_ids = [&"attacker"]
	var defender_squad := _make_squad(&"defender_squad", &"defenders", Vector3(50, 0, 0))
	for slot in range(5):
		defender_squad.unit_instance_ids.append(StringName("defender_%d" % slot))
	battle.squad_states_by_id = {
		attacker_squad.squad_id: attacker_squad,
		defender_squad.squad_id: defender_squad,
	}
	var weapon := WeaponDef.new()
	weapon.id = &"test_weapon"
	weapon.total_power = 1
	weapon.hit_count = 1
	weapon.en_cost = 1
	weapon.min_range_m = 0.0
	weapon.max_range_m = 500.0
	weapon.can_target_front = true
	weapon.can_target_rear = true
	battle.weapon_defs[weapon.id] = weapon
	var attacker_def := _make_unit_def(&"attacker_def", 100, 100, GameEnums.UnitRole.ATTACK)
	attacker_def.weapon_ids = [weapon.id]
	battle.unit_defs[attacker_def.id] = attacker_def
	var attacker := _make_unit(&"attacker", attacker_def.id, attacker_squad.squad_id, 0, 1000)
	attacker.action_gauge = 100.0
	battle.unit_states_by_id[attacker.unit_instance_id] = attacker
	var hp_values := [500, 100, 900, 400, 600]
	var armor_values := [100, 90, 110, 10, 500]
	var speed_values := [100, 80, 300, 60, 50]
	var roles := [GameEnums.UnitRole.ATTACK, GameEnums.UnitRole.SUPPORT, GameEnums.UnitRole.RECON, GameEnums.UnitRole.SUPPORT, GameEnums.UnitRole.DEFENSE]
	for slot in range(5):
		var def_id := StringName("defender_def_%d" % slot)
		var unit_def := _make_unit_def(def_id, armor_values[slot], speed_values[slot], roles[slot])
		battle.unit_defs[def_id] = unit_def
		var unit := _make_unit(StringName("defender_%d" % slot), def_id, defender_squad.squad_id, slot, hp_values[slot])
		battle.unit_states_by_id[unit.unit_instance_id] = unit
	return battle


func _make_squad(id: StringName, faction_id: StringName, position: Vector3) -> BattleSquadState:
	var squad := BattleSquadState.new()
	squad.squad_id = id
	squad.faction_id = faction_id
	squad.world_position = position
	squad.destination = position
	return squad


func _make_unit_def(id: StringName, armor: int, speed: int, role: int) -> UnitDef:
	var unit_def := UnitDef.new()
	unit_def.id = id
	unit_def.max_hp = 1000
	unit_def.max_en = 1000
	unit_def.firepower = 1
	unit_def.armor = armor
	unit_def.speed = speed
	unit_def.evasion = 0
	unit_def.role = role
	return unit_def


func _make_unit(id: StringName, def_id: StringName, squad_id: StringName, slot: int, hp: int) -> BattleUnitState:
	var unit := BattleUnitState.new()
	unit.unit_instance_id = id
	unit.unit_def_id = def_id
	unit.squad_id = squad_id
	unit.slot_index = slot
	unit.initial_hp = hp
	unit.current_hp = hp
	unit.max_hp = 1000
	unit.initial_en = 1000
	unit.current_en = 1000
	unit.max_en = 1000
	return unit


func _reset_attacker(battle: BattleRuntimeState) -> void:
	var attacker := battle.unit_states_by_id[&"attacker"] as BattleUnitState
	attacker.action_gauge = 100.0
	attacker.post_action_delay_sec = 0.0
	attacker.current_en = attacker.max_en
	battle.result = null


func _fire_once(battle: BattleRuntimeState) -> Array[StringName]:
	BattleCombatSystem.advance(battle, 0.001)
	var targets: Array[StringName] = []
	for event: Dictionary in battle.combat_events:
		if event.get("type") == &"shot" and event.get("source_unit_id") == &"attacker":
			var target_id := StringName(event.get("target_unit_id", ""))
			if not targets.has(target_id): targets.append(target_id)
	return targets


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
