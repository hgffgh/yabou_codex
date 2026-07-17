extends SceneTree

var failures := PackedStringArray()
var game_state: Node


func _initialize() -> void:
	await process_frame
	game_state = root.get_node_or_null("GameState")
	if game_state == null:
		push_error("pilot_skills_test: GameState autoload is unavailable")
		quit(1)
		return

	_test_unlock_level_gates_the_higher_tier_skill()
	_test_leader_only_gates_the_skill()
	_test_en_pct_and_environment_conditions()
	_test_firepower_skill_measurably_increases_damage()
	_test_action_skill_id_grants_an_extra_support_skill()
	_finish()


## aria_nova is seeded at level 8: her Lv1 aria_marksman_instinct
## (always, accuracy+10) should already apply, but her Lv10 aria_last_stand
## (hp_pct <= 0.3, firepower+30/critical+10) should not, even once her HP
## condition is satisfied, until she actually reaches level 10.
func _test_unlock_level_gates_the_higher_tier_skill() -> void:
	var battle := _build_solo_battle(&"nova_scout", &"crimson_bastion")
	if battle == null:
		return
	var pilot: PilotState = game_state.campaign_runtime.get_pilot(&"aria_nova")
	var unit := _first_unit(battle, battle.attacker_squad_ids)
	_check(unit.pilot_level == 8, "expected aria_nova's battle snapshot to carry her seeded level 8, got %d" % unit.pilot_level)
	unit.current_hp = int(round(float(unit.max_hp) * 0.2))

	_check(is_equal_approx(BattleCombatSystem.pilot_skill_modifier(battle, unit, &"accuracy"), 10.0),
		"Lv1 always-on accuracy skill should already apply at level 8")
	_check(is_equal_approx(BattleCombatSystem.pilot_skill_modifier(battle, unit, &"firepower"), 0.0),
		"Lv10 skill should not apply yet at level 8, even with its HP condition satisfied")

	pilot.level = 10
	unit.pilot_level = pilot.level
	_check(is_equal_approx(BattleCombatSystem.pilot_skill_modifier(battle, unit, &"firepower"), 30.0),
		"Lv10 skill should apply once the pilot reaches level 10 with HP at 20%")
	_check(is_equal_approx(BattleCombatSystem.pilot_skill_modifier(battle, unit, &"critical"), 10.0),
		"Lv10 skill's critical modifier should apply alongside its firepower modifier")

	unit.current_hp = unit.max_hp
	_check(is_equal_approx(BattleCombatSystem.pilot_skill_modifier(battle, unit, &"firepower"), 0.0),
		"Lv10 skill should stop applying once HP rises back above its 30% threshold")


## darius_crimson (seeded at level 10) has darius_iron_will (Lv1, always,
## armor+15) and darius_command_aura (Lv10, leader_only, armor+20/evasion+10).
func _test_leader_only_gates_the_skill() -> void:
	var battle := _build_solo_battle(&"crimson_bastion", &"nova_scout", &"crimson_empire", &"nova_republic")
	if battle == null:
		return
	var unit := _first_unit(battle, battle.attacker_squad_ids)
	var squad := battle.squad_states_by_id[unit.squad_id] as BattleSquadState
	_check(squad.leader_unit_id == unit.unit_instance_id,
		"a lone-unit squad's only member should be its leader by construction")
	_check(is_equal_approx(BattleCombatSystem.pilot_skill_modifier(battle, unit, &"armor"), 35.0),
		"leading darius_crimson should get both armor skills (15 + 20)")

	squad.leader_unit_id = &""
	_check(is_equal_approx(BattleCombatSystem.pilot_skill_modifier(battle, unit, &"armor"), 15.0),
		"a non-leading darius_crimson should lose the leader_only armor bonus, keeping only the always-on one")
	_check(is_equal_approx(BattleCombatSystem.pilot_skill_modifier(battle, unit, &"evasion"), 0.0),
		"the leader_only evasion bonus should also disappear when not leading")


## Exercises en_pct and environment (both unused by the two seeded sample
## pilots) via a synthetic pilot/skill pair registered and cleaned up
## locally, so the shared master-data pilots are never mutated.
func _test_en_pct_and_environment_conditions() -> void:
	var battle := _build_solo_battle(&"nova_scout", &"crimson_bastion")
	if battle == null:
		return
	_check(battle.environment == GameEnums.EnvironmentType.SPACE,
		"standard_battle_map should default to the SPACE environment")

	var synthetic_pilot: PilotDef = (game_state.master_data.pilots[&"aria_nova"] as PilotDef).duplicate()
	synthetic_pilot.id = &"test_synthetic_pilot"
	synthetic_pilot.skill_ids = [&"test_en_skill", &"test_environment_skill"]
	game_state.master_data.pilots[synthetic_pilot.id] = synthetic_pilot

	var en_skill := PilotSkillDef.new()
	en_skill.id = &"test_en_skill"
	en_skill.unlock_level = 1
	en_skill.condition_type = &"en_pct"
	en_skill.condition_value = 0.5
	en_skill.modifiers = {"accuracy": 5.0}
	game_state.master_data.pilot_skills[en_skill.id] = en_skill

	var environment_skill := PilotSkillDef.new()
	environment_skill.id = &"test_environment_skill"
	environment_skill.unlock_level = 1
	environment_skill.condition_type = &"environment"
	environment_skill.condition_value = float(GameEnums.EnvironmentType.MOON)
	environment_skill.modifiers = {"evasion": 7.0}
	game_state.master_data.pilot_skills[environment_skill.id] = environment_skill

	var unit := _first_unit(battle, battle.attacker_squad_ids)
	unit.pilot_id = synthetic_pilot.id
	unit.pilot_level = 1
	unit.current_en = int(round(float(unit.max_en) * 0.8))
	_check(is_equal_approx(BattleCombatSystem.pilot_skill_modifier(battle, unit, &"accuracy"), 0.0),
		"en_pct skill should not apply at 80% EN against a 50% threshold")
	unit.current_en = int(round(float(unit.max_en) * 0.3))
	_check(is_equal_approx(BattleCombatSystem.pilot_skill_modifier(battle, unit, &"accuracy"), 5.0),
		"en_pct skill should apply once EN drops to 30%, below its 50% threshold")

	_check(is_equal_approx(BattleCombatSystem.pilot_skill_modifier(battle, unit, &"evasion"), 0.0),
		"environment skill requiring MOON should not apply in this battle's SPACE environment")
	battle.environment = GameEnums.EnvironmentType.MOON
	_check(is_equal_approx(BattleCombatSystem.pilot_skill_modifier(battle, unit, &"evasion"), 7.0),
		"environment skill requiring MOON should apply once the battle's environment matches")

	game_state.master_data.pilots.erase(synthetic_pilot.id)
	game_state.master_data.pilot_skills.erase(en_skill.id)
	game_state.master_data.pilot_skills.erase(environment_skill.id)


## Replays the exact same RNG sequence (accuracy roll, variance roll,
## critical roll) with and without aria_nova's always-on firepower... her
## Lv1 skill only boosts accuracy, so this levels her to 10 and drops her
## HP to arm aria_last_stand's firepower bonus, then compares
## BattleCombatSystem._resolve_attack's damage output against the same
## attack with her pilot_id cleared (generic pilot, no skills), starting
## from an identical rng_state both times so any hit/miss/critical outcome
## is identical and the only variable left is the firepower modifier.
func _test_firepower_skill_measurably_increases_damage() -> void:
	# crimson_bastion's armor (560) would floor-clamp base_damage to the
	# minimum-5%-of-weapon-power rule regardless of any firepower bonus, so
	# this uses a lightly-armored nova_scout as the target instead (still
	# owned by crimson_empire) to keep the raw formula above that floor.
	var battle := _build_solo_battle(&"nova_scout", &"nova_scout")
	if battle == null:
		return
	var attacker := _first_unit(battle, battle.attacker_squad_ids)
	var target := _first_unit(battle, battle.defender_squad_ids)
	var pilot: PilotState = game_state.campaign_runtime.get_pilot(&"aria_nova")
	pilot.level = 10
	attacker.pilot_level = 10
	attacker.current_hp = int(round(float(attacker.max_hp) * 0.2))
	var weapon := battle.weapon_defs[&"light_autocannon"] as WeaponDef
	var attack := {"attacker_id": attacker.unit_instance_id, "target_ids": [target.unit_instance_id], "weapon_id": weapon.id, "weapon": weapon}

	var seed := 1
	battle.rng_state = seed
	target.current_hp = target.max_hp
	var damage_with_skill: int = BattleCombatSystem._resolve_attack(battle, attack, target.unit_instance_id)

	var original_pilot_id := attacker.pilot_id
	attacker.pilot_id = &""
	battle.rng_state = seed
	target.current_hp = target.max_hp
	var damage_without_skill: int = BattleCombatSystem._resolve_attack(battle, attack, target.unit_instance_id)
	attacker.pilot_id = original_pilot_id

	_check(damage_with_skill > 0 and damage_without_skill > 0,
		"expected a guaranteed hit at seed %d for this test to be meaningful (with=%d without=%d)" % [seed, damage_with_skill, damage_without_skill])
	_check(damage_with_skill > damage_without_skill,
		"aria_last_stand's firepower bonus should increase damage given an identical RNG sequence (with=%d without=%d)" % [damage_with_skill, damage_without_skill])


## DATA_DEFINITION.md section 13's action_skill_id: aria_last_stand grants
## field_repair once unlocked (Lv10) and its hp_pct <= 0.3 condition is met.
## Uses nova_scout, whose UnitDef.support_skill_ids is empty, so any repair
## capability observed must have come from the pilot grant, not the unit.
func _test_action_skill_id_grants_an_extra_support_skill() -> void:
	var battle := _build_solo_battle(&"nova_scout", &"crimson_bastion")
	if battle == null:
		return
	var pilot: PilotState = game_state.campaign_runtime.get_pilot(&"aria_nova")
	var unit := _first_unit(battle, battle.attacker_squad_ids)
	var unit_def := battle.unit_defs[&"nova_scout"] as UnitDef
	_check(unit_def.support_skill_ids.is_empty(), "setup: nova_scout should have no built-in support skills for this test to be meaningful")

	unit.current_hp = int(round(float(unit.max_hp) * 0.2))
	_check(BattleCombatSystem.pilot_action_skill_ids(battle, unit).is_empty(),
		"the action skill should not be granted before the pilot reaches its unlock level")

	pilot.level = 10
	unit.pilot_level = pilot.level
	_check(BattleCombatSystem.pilot_action_skill_ids(battle, unit) == [&"field_repair"],
		"aria_last_stand should grant field_repair once level 10 and its HP condition are both satisfied")

	unit.current_en = 999
	var support: Dictionary = BattleCombatSystem._prepare_support(battle, unit.unit_instance_id)
	_check(not support.is_empty() and (support.skill as SupportSkillDef).id == &"field_repair",
		"_prepare_support should pick the pilot-granted skill when it's the only one available")

	unit.current_hp = unit.max_hp
	_check(BattleCombatSystem.pilot_action_skill_ids(battle, unit).is_empty(),
		"the action skill should stop being granted once its HP condition is no longer met")


func _build_solo_battle(
	attacker_unit_def: StringName, defender_unit_def: StringName,
	attacker_faction: StringName = &"nova_republic", defender_faction: StringName = &"crimson_empire",
) -> BattleRuntimeState:
	game_state.start_new_game(&"nova_republic")
	var attacker: Dictionary = game_state.rollout_new_unit(attacker_unit_def, attacker_faction, &"crimson_border")
	var defender: Dictionary = game_state.rollout_new_unit(defender_unit_def, defender_faction, &"crimson_border")
	if attacker_faction == &"nova_republic":
		var assign_errors: PackedStringArray = game_state.campaign_runtime.assign_pilot_to_unit(&"aria_nova", attacker.unit.instance_id)
		_check(assign_errors.is_empty(), "assigning aria_nova failed: %s" % assign_errors)
	else:
		var assign_errors: PackedStringArray = game_state.campaign_runtime.assign_pilot_to_unit(&"darius_crimson", attacker.unit.instance_id)
		_check(assign_errors.is_empty(), "assigning darius_crimson failed: %s" % assign_errors)
	attacker.squad.move_origin_region_id = &"nova_border"
	var pending := {
		"type": "squad_battle_pending", "region_id": &"crimson_border",
		"attacker_id": attacker_faction, "defender_id": defender_faction,
		"attacker_squad_ids": [attacker.squad.squad_id], "defender_squad_ids": [defender.squad.squad_id],
	}
	var battle_map := game_state.master_data.battle_maps[&"standard_battle_map"] as BattleMapDef
	var created: Dictionary = BattleRuntimeFactory.new().create_from_pending(
		pending, game_state.campaign_runtime, &"pilot_skills_test", 1, Vector3.ZERO, Vector3(60, 0, 0), battle_map,
	)
	_check(created.errors.is_empty(), "battle creation failed: %s" % created.errors)
	return created.state as BattleRuntimeState


func _first_unit(battle: BattleRuntimeState, squad_ids: Array[StringName]) -> BattleUnitState:
	var squad := battle.squad_states_by_id[squad_ids[0]] as BattleSquadState
	return battle.unit_states_by_id[squad.unit_instance_ids[0]] as BattleUnitState


func _finish() -> void:
	if failures.is_empty():
		print("pilot_skills_test: all checks passed")
		quit(0)
	else:
		for failure: String in failures:
			push_error("pilot_skills_test: %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
